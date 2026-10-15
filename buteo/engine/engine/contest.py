"""Concours « Pronos du jour » : 5 grands matchs, chacun prédit 1, N ou 2.

Pas d'argent en jeu : des points, des classements et des badges.

Documents (lus par l'app, voir firebase/firestore.rules) :

- `contests/{date}` (moteur) : les 5 matchs, leurs cotes 1/N/2, l'heure de
  coup d'envoi de chacun (`kickoffs`, utilisée par les règles pour fermer les
  pronos), puis le résultat et le score ;
- `contests/{date}/picks/{uid}_{match}` (joueur) : uid, fixtureId, choice
  (« 1 », « X » ou « 2 »), pseudo — accepté seulement avant le coup d'envoi ;
- `contestScores/{date}` (moteur) : points de chaque joueur pour la journée ;
- `leaderboards/week-2026-W42` et `leaderboards/month-2026-10` (moteur) :
  les 100 premiers ;
- `contestPlayers/{uid}` (moteur) : pseudo, rang de la semaine et du mois,
  journées sans faute, semaines régulières, podiums et victoires (badges).

Un bon prono rapporte sa cote × 10 points (cote 1,85 : 19 points). Un match
annulé ne compte pas. L'administrateur peut renommer ou exclure un joueur
(`moderation/all`, écrit par les fonctions serveur).
"""

from __future__ import annotations

from datetime import date as Date
from datetime import datetime, timedelta

from . import api_football as api
from .selection import Fixture
from .store import Store, iso

CONTEST_SIZE = 5
CHOICES = ("1", "X", "2")
LEADERBOARD_SIZE = 100


def points(odds: float) -> int:
    return round(odds * 10)


# --- Publication -------------------------------------------------------------------


def choose_matches(pool: list[tuple[int, Fixture, dict[str, float]]]) -> list[tuple[Fixture, dict[str, float]]]:
    """Les 5 matchs du concours : championnats prioritaires d'abord, un par championnat
    à chaque tour pour varier, puis par heure de coup d'envoi."""
    by_priority: dict[int, list[tuple[Fixture, dict[str, float]]]] = {}
    for priority, fixture, odds in sorted(pool, key=lambda p: (p[0], p[1].kickoff, p[1].id)):
        by_priority.setdefault(priority, []).append((fixture, odds))
    chosen: list[tuple[Fixture, dict[str, float]]] = []
    while len(chosen) < CONTEST_SIZE and any(by_priority.values()):
        for priority in sorted(by_priority):
            if by_priority[priority] and len(chosen) < CONTEST_SIZE:
                chosen.append(by_priority[priority].pop(0))
    return sorted(chosen, key=lambda m: (m[0].kickoff, m[0].id))


def contest_doc(date: str, matches: list[tuple[Fixture, dict[str, float]]], now: datetime) -> dict:
    return {
        "date": date,
        "status": "open",
        "matches": [
            {
                "fixtureId": f.id,
                "league": f.league,
                "country": f.country,
                "home": f.home,
                "away": f.away,
                "kickoff": iso(f.kickoff),
                "odds": {c: odds[c] for c in CHOICES},
                "result": None,
            }
            for f, odds in matches
        ],
        # Heure limite de chaque prono, lue par les règles Firestore.
        "kickoffs": {str(f.id): f.kickoff for f, _ in matches},
        "publishedAt": now,
        "updatedAt": now,
    }


def publish_contest(store: Store, date: str, pool: list[tuple[int, Fixture, dict[str, float]]], now: datetime) -> None:
    """Concours de la journée. Déjà publié : on le garde (des joueurs ont pu jouer)."""
    existing = store.get(f"contests/{date}")
    if existing and existing.get("matches"):
        return
    matches = choose_matches([p for p in pool if all(c in p[2] for c in CHOICES)])
    if matches:
        store.set(f"contests/{date}", contest_doc(date, matches, now))


# --- Résultats ----------------------------------------------------------------------


def pending_ids(contest: dict | None, now: datetime) -> set[int]:
    if not contest:
        return set()
    return {
        m["fixtureId"]
        for m in contest.get("matches", [])
        if m.get("result") is None and datetime.fromisoformat(m["kickoff"].replace("Z", "+00:00")) <= now
    }


def match_state(fixture: dict) -> tuple[str | None, dict | None]:
    """Résultat (« 1 », « X », « 2 », « void » ou None si pas fini) et score à 90 minutes."""
    short = fixture["fixture"]["status"].get("short")
    goals = fixture.get("goals") or {}
    full = (fixture.get("score") or {}).get("fulltime") or {}
    if short in api.CANCELLED:
        return "void", None
    if short in api.NOT_STARTED or goals.get("home") is None:
        return None, None
    if short in api.FINISHED:
        h = full.get("home") if full.get("home") is not None else goals["home"]
        a = full.get("away") if full.get("away") is not None else goals["away"]
        return ("1" if h > a else "2" if a > h else "X"), {"home": h, "away": a}
    return None, {"home": goals["home"], "away": goals["away"]}


def update_contest(store: Store, date: str, fixtures: dict[int, dict], now: datetime) -> bool:
    """Scores et résultats des matchs du concours. Renvoie vrai si un match vient de se terminer."""
    contest = store.get(f"contests/{date}")
    if not contest:
        return False
    settled_now = False
    matches = []
    for m in contest["matches"]:
        f = fixtures.get(m["fixtureId"])
        if f is None or m.get("result") is not None:
            matches.append(m)
            continue
        result, score = match_state(f)
        new = {**m, "score": score} if score else dict(m)
        if result is not None:
            new["result"] = result
            settled_now = True
        matches.append(new)
    if matches == contest["matches"]:
        return False
    done = all(m.get("result") is not None for m in matches)
    started = any(datetime.fromisoformat(m["kickoff"].replace("Z", "+00:00")) <= now for m in matches)
    status = "done" if done else ("live" if started else "open")
    store.set(f"contests/{date}", {**contest, "matches": matches, "status": status, "updatedAt": now})
    if settled_now:
        score_day(store, date, now)
    return settled_now


# --- Points, classements, badges -------------------------------------------------------


def _moderation(store: Store) -> dict[str, dict]:
    return (store.get("moderation/all") or {}).get("players", {})


def score_day(store: Store, date: str, now: datetime) -> None:
    contest = store.get(f"contests/{date}") or {}
    results = {m["fixtureId"]: m for m in contest.get("matches", []) if m.get("result") is not None}
    moderation = _moderation(store)
    players: dict[str, dict] = {}
    for pick in store.list(f"contests/{date}/picks").values():
        uid = pick.get("uid")
        mod = moderation.get(uid, {})
        if not uid or mod.get("excluded"):
            continue
        p = players.setdefault(uid, {"pseudo": mod.get("pseudo") or pick.get("pseudo") or "Joueur", "points": 0, "correct": 0, "played": 0})
        match = results.get(pick.get("fixtureId"))
        if not match or match["result"] == "void" or pick.get("choice") not in CHOICES:
            continue
        p["played"] += 1
        if pick["choice"] == match["result"]:
            p["correct"] += 1
            p["points"] += points(match["odds"][pick["choice"]])
    all_settled = len(results) == len(contest.get("matches", [])) > 0
    counted = sum(1 for m in results.values() if m["result"] != "void")
    for p in players.values():
        p["perfect"] = all_settled and counted >= CONTEST_SIZE and p["correct"] == counted
    store.set(f"contestScores/{date}", {"date": date, "players": players, "updatedAt": now})
    update_leaderboards(store, date, now)


def week_id(d: Date) -> str:
    year, week, _ = d.isocalendar()
    return f"{year}-W{week:02d}"


def _days(start: Date, end: Date) -> list[str]:
    return [(start + timedelta(days=i)).isoformat() for i in range((end - start).days + 1)]


def _standings(store: Store, days: list[str]) -> list[dict]:
    totals: dict[str, dict] = {}
    for day in days:
        for uid, s in ((store.get(f"contestScores/{day}") or {}).get("players") or {}).items():
            t = totals.setdefault(uid, {"uid": uid, "pseudo": s["pseudo"], "points": 0, "correct": 0, "played": 0, "days": 0})
            t["pseudo"] = s["pseudo"]  # le plus récent
            t["points"] += s["points"]
            t["correct"] += s["correct"]
            t["played"] += s["played"]
            t["days"] += 1 if s["played"] else 0
    ranked = sorted(totals.values(), key=lambda t: (-t["points"], -t["correct"], t["played"], t["pseudo"]))
    for i, t in enumerate(ranked):
        t["rank"] = i + 1
    return ranked


def update_leaderboards(store: Store, date: str, now: datetime) -> None:
    d = Date.fromisoformat(date)
    week_start = d - timedelta(days=d.weekday())
    month_start = d.replace(day=1)
    week = _standings(store, _days(week_start, d))
    month = _standings(store, _days(month_start, d))
    wid, mid = week_id(d), d.strftime("%Y-%m")
    store.set(f"leaderboards/week-{wid}", {"period": wid, "kind": "week", "players": week[:LEADERBOARD_SIZE], "updatedAt": now})
    store.set(f"leaderboards/month-{mid}", {"period": mid, "kind": "month", "players": month[:LEADERBOARD_SIZE], "updatedAt": now})

    day_scores = (store.get(f"contestScores/{date}") or {}).get("players") or {}
    month_by_uid = {t["uid"]: t for t in month}
    for t in week:
        profile = store.get(f"contestPlayers/{t['uid']}") or {}
        m = month_by_uid.get(t["uid"], {})
        profile.update(
            {
                "pseudo": t["pseudo"],
                "week": {"period": wid, **{k: t[k] for k in ("points", "rank", "correct", "played")}},
                "month": {"period": mid, **{k: m.get(k, 0) for k in ("points", "rank", "correct", "played")}},
                "updatedAt": now,
            }
        )
        if day_scores.get(t["uid"], {}).get("perfect"):
            profile["perfectDays"] = sorted({*profile.get("perfectDays", []), date})
        if t["days"] == 7:
            profile["regularWeeks"] = sorted({*profile.get("regularWeeks", []), wid})
        store.set(f"contestPlayers/{t['uid']}", profile)

    _close_previous_week(store, week_start, now)


def _close_previous_week(store: Store, week_start: Date, now: datetime) -> None:
    """Podium et victoire de la semaine précédente, une seule fois."""
    previous = week_id(week_start - timedelta(days=1))
    board = store.get(f"leaderboards/week-{previous}")
    if not board or board.get("final"):
        return
    for t in board.get("players", [])[:3]:
        profile = store.get(f"contestPlayers/{t['uid']}") or {"pseudo": t["pseudo"]}
        profile["podiumWeeks"] = sorted({*profile.get("podiumWeeks", []), previous})
        if t["rank"] == 1:
            profile["championWeeks"] = sorted({*profile.get("championWeeks", []), previous})
        store.set(f"contestPlayers/{t['uid']}", profile)
    store.set(f"leaderboards/week-{previous}", {**board, "final": True, "updatedAt": now})
