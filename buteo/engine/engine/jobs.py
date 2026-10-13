"""Les deux tâches du moteur : publier les pronos, puis suivre les résultats."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from . import api_football as api
from . import model
from .markets import bookmaker_odds
from .notify import Notifier
from .picks import SETTLED, day_stats, doc_status, rubric_doc, tip_update
from .selection import Candidate, Fixture, candidates, pick_all
from .store import Store

log = logging.getLogger("buteo")

# Les championnats sont recherchés une fois par semaine (économie de requêtes).
LEAGUES_TTL = timedelta(days=7)
STATS_DAYS = 35


def _utc(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)


def resolve_leagues(client: api.ApiFootball, store: Store, now: datetime) -> list[dict]:
    """Identifiant et saison en cours de chaque championnat suivi."""
    cfg = store.get("config/engine") or {}
    cached = cfg.get("leagues")
    resolved_at = cfg.get("leaguesResolvedAt")
    if cached and resolved_at and now - _as_dt(resolved_at) < LEAGUES_TTL:
        return cached

    out = []
    by_country: dict[str, list[dict]] = {}
    for league in api.LEAGUES:
        if league.api_country not in by_country:
            by_country[league.api_country] = client.current_leagues(league.api_country)
        found = _find_league(by_country[league.api_country], league.api_name)
        if not found:
            log.warning("Championnat introuvable : %s (%s)", league.api_name, league.api_country)
            continue
        season = next((s["year"] for s in found.get("seasons", []) if s.get("current")), None)
        if season is None:
            continue
        out.append({"id": found["league"]["id"], "season": season, "country": league.country, "name": league.name})
    store.set("config/engine", {**cfg, "leagues": out, "leaguesResolvedAt": now})
    return out


def _find_league(items: list[dict], name: str) -> dict | None:
    exact = [i for i in items if i["league"]["name"] == name]
    if exact:
        return exact[0]
    loose = [i for i in items if name.lower() in i["league"]["name"].lower()]
    return loose[0] if loose else None


def _as_dt(value) -> datetime:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    return _utc(str(value))


def _results(raw: list[dict]) -> list[model.Result]:
    out = []
    for f in raw:
        goals = f.get("score", {}).get("fulltime") or f.get("goals") or {}
        if goals.get("home") is None:
            continue
        out.append(
            model.Result(
                f["teams"]["home"]["name"],
                f["teams"]["away"]["name"],
                goals["home"],
                goals["away"],
                _utc(f["fixture"]["date"]),
            )
        )
    return out


def publish(client: api.ApiFootball, store: Store, date: str, now: datetime) -> dict[str, list[Candidate]]:
    """Calcule et publie les pronos de football de la journée `date`."""
    leagues = resolve_leagues(client, store, now)
    by_id = {lg["id"]: lg for lg in leagues}

    fixtures = [
        f
        for f in client.fixtures_on(date)
        if f["league"]["id"] in by_id and f["fixture"]["status"]["short"] in api.NOT_STARTED
    ]
    log.info("%d matchs suivis le %s", len(fixtures), date)

    strengths: dict[int, model.Strengths] = {}
    teams: dict[int, set[str]] = {}
    pool: list[Candidate] = []
    for f in fixtures:
        league_id = f["league"]["id"]
        lg = by_id[league_id]
        if league_id not in strengths:
            history = _results(client.finished(league_id, lg["season"]))
            if len(history) < 40:  # début de saison : on ajoute la saison précédente
                history += _results(client.finished(league_id, lg["season"] - 1))
            strengths[league_id] = model.fit(history, now)
            teams[league_id] = {r.home for r in history} | {r.away for r in history}
        bookmakers = client.odds(f["fixture"]["id"])
        if not bookmakers:
            continue
        home, away = f["teams"]["home"]["name"], f["teams"]["away"]["name"]
        lam_h, lam_a = strengths[league_id].expected_goals(home, away)
        fixture = Fixture(f["fixture"]["id"], lg["name"], lg["country"], home, away, _utc(f["fixture"]["date"]))
        pool += candidates(fixture, model.market_probabilities(lam_h, lam_a), bookmaker_odds(bookmakers))

    chosen = pick_all(pool)
    _save_teams(store, by_id, teams, now)
    for rubric, items in chosen.items():
        store.set(f"picks/{date}_{rubric}", rubric_doc(rubric, date, items, now))
    cfg = store.get("config/engine") or {}
    store.set("config/engine", {**cfg, "active": True, "lastPublish": date, "lastRun": now, "apiCalls": client.calls})
    log.info("Publié : %s (%d requêtes API)", {r: len(p) for r, p in chosen.items()}, client.calls)
    return chosen


def update_results(client: api.ApiFootball, store: Store, now: datetime, notifier: Notifier | None = None) -> int:
    """Met à jour les pronos d'aujourd'hui et d'hier qui ne sont pas terminés.

    Renvoie le nombre de pronos modifiés.
    """
    changed_total = 0
    dates = [(now - timedelta(days=1)).date().isoformat(), now.date().isoformat()]
    for date in dates:
        docs = store.query_picks(date)
        pending = sorted(
            {
                t["fixtureId"]
                for d in docs.values()
                for t in d.get("tips", [])
                if t["status"] not in SETTLED and _utc(t["kickoff"]) <= now
            }
        )
        if not pending:
            continue
        fixtures = {f["fixture"]["id"]: f for f in client.fixtures_by_ids(pending)}
        touched = False
        for doc_id, doc in docs.items():
            new_tips = [tip_update(t, fixtures[t["fixtureId"]]) if t["fixtureId"] in fixtures else t for t in doc["tips"]]
            if new_tips == doc["tips"]:
                continue
            before = {t["fixtureId"]: t["status"] for t in doc["tips"]}
            old_status = doc_status(doc)
            doc = {**doc, "tips": new_tips, "updatedAt": now}
            doc["status"] = doc_status(doc)
            store.set(f"picks/{doc_id}", doc)
            touched = True
            changed_total += sum(1 for t in new_tips if t["status"] != before[t["fixtureId"]])
            if notifier:
                notifier.on_change(doc, before, old_status)
        if touched:
            _update_summary(store, date, now)
    return changed_total


def _update_summary(store: Store, date: str, now: datetime) -> None:
    summary = store.get("stats/summary") or {"days": {}}
    days = dict(summary.get("days", {}))
    stats = day_stats(store.query_picks(date))
    if stats:
        days[date] = stats
    cutoff = (now - timedelta(days=STATS_DAYS)).date().isoformat()
    days = {d: v for d, v in days.items() if d >= cutoff}
    store.set("stats/summary", {"days": days, "updatedAt": now})


def _save_teams(store: Store, leagues: dict[int, dict], teams: dict[int, set[str]], now: datetime) -> None:
    """Équipes de chaque championnat, pour l'écran « Mes équipes » de l'app."""
    known = {g["league"] + "|" + g["country"]: g for g in (store.get("config/teams") or {}).get("groups", [])}
    for league_id, names in teams.items():
        lg = leagues[league_id]
        key = lg["name"] + "|" + lg["country"]
        previous = set(known.get(key, {}).get("teams", []))
        known[key] = {"sport": "foot", "league": lg["name"], "country": lg["country"], "teams": sorted(previous | names)}
    store.set("config/teams", {"groups": sorted(known.values(), key=lambda g: (g["country"], g["league"])), "updatedAt": now})
