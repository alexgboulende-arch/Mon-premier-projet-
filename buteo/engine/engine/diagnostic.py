"""Ce que la clé API-Football permet vraiment (offre gratuite ou payante).

Une dizaine de requêtes : forfait et quota, matchs d'hier à demain, historique
de la saison, cotes. Le résultat s'affiche dans le journal (et dans le résumé
de l'exécution GitHub). La clé n'est jamais affichée.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta

import requests

from .api_football import BASE_URL

# Identifiants API-Football de quelques championnats suivis (stables).
KNOWN_LEAGUES = {
    39: "Premier League",
    61: "Ligue 1",
    62: "Ligue 2",
    140: "LaLiga",
    135: "Serie A",
    78: "Bundesliga",
    94: "Liga Portugal",
    144: "Pro League",
    88: "Eredivisie",
    2: "Ligue des champions",
    3: "Ligue Europa",
    12: "Ligue des champions CAF",
}
WANTED_BETS = ["Match Winner", "Double Chance", "Goals Over/Under", "Both Teams Score", "HT/FT Double", "Exact Score"]


class Probe:
    def __init__(self, key: str):
        self.session = requests.Session()
        self.session.headers.update({"x-apisports-key": key})
        self.lines: list[str] = []

    def call(self, path: str, **params) -> tuple[dict | None, str]:
        """Réponse de l'API, ou None et le message d'erreur."""
        try:
            r = self.session.get(f"{BASE_URL}/{path}", params=params, timeout=30)
        except requests.RequestException as e:
            return None, f"réseau : {e.__class__.__name__}"
        if r.status_code != 200:
            return None, f"HTTP {r.status_code}"
        data = r.json()
        errors = data.get("errors")
        if errors:
            text = "; ".join(f"{v}" for v in errors.values()) if isinstance(errors, dict) else str(errors)
            return None, text
        return data, ""

    def report(self, title: str, ok: bool, detail: str) -> None:
        line = f"{'OK     ' if ok else 'REFUSÉ '} {title} : {detail}"
        print(line)
        self.lines.append(f"| {'✅' if ok else '❌'} | {title} | {detail} |")


def _ours(fixtures: list[dict]) -> list[dict]:
    return [f for f in fixtures if f["league"]["id"] in KNOWN_LEAGUES]


def run(key: str, now: datetime) -> None:
    p = Probe(key)
    today = now.date()
    yesterday, tomorrow = today - timedelta(days=1), today + timedelta(days=1)

    data, err = p.call("status")
    if data:
        resp = data.get("response") or {}
        sub, req = resp.get("subscription", {}), resp.get("requests", {})
        p.report("Forfait", True, f"{sub.get('plan')} · {req.get('current')}/{req.get('limit_day')} requêtes aujourd'hui")
    else:
        p.report("Forfait", False, err)

    season = None
    data, err = p.call("leagues", id=61, current="true")
    if data and data.get("response"):
        seasons = data["response"][0].get("seasons", [])
        season = next((s["year"] for s in seasons if s.get("current")), None)
        p.report("Championnats (Ligue 1)", True, f"saison en cours {season}")
    else:
        p.report("Championnats (Ligue 1)", False, err or "aucun résultat")

    by_day: dict[str, list[dict]] = {}
    for name, day in [("hier", yesterday), ("aujourd'hui", today), ("demain", tomorrow)]:
        data, err = p.call("fixtures", date=day.isoformat(), timezone="UTC")
        if data is None:
            p.report(f"Matchs {name} ({day})", False, err)
            continue
        fixtures = data.get("response", [])
        by_day[name] = fixtures
        ours = _ours(fixtures)
        leagues = sorted({KNOWN_LEAGUES[f["league"]["id"]] for f in ours})
        p.report(
            f"Matchs {name} ({day})",
            True,
            f"{len(fixtures)} matchs dans le monde, {len(ours)} dans nos grands championnats ({', '.join(leagues) or 'aucun'})",
        )

    data, err = p.call("fixtures", date=(tomorrow + timedelta(days=2)).isoformat(), timezone="UTC")
    p.report("Matchs dans 3 jours", data is not None, f"{len(data.get('response', []))} matchs" if data else err)

    if season:
        for label, year in [("saison en cours", season), ("saison précédente", season - 1)]:
            data, err = p.call("fixtures", league=61, season=year, status="FT-AET-PEN")
            p.report(f"Historique Ligue 1, {label} ({year})", data is not None,
                     f"{len(data.get('response', []))} matchs terminés" if data else err)

    sample = [f["fixture"]["id"] for f in (by_day.get("demain") or by_day.get("aujourd'hui") or [])[:2]]
    if len(sample) == 2:
        data, err = p.call("fixtures", ids="-".join(map(str, sample)))
        p.report("Plusieurs matchs par identifiants", data is not None, "accepté" if data else err)

    data, err = p.call("odds", date=tomorrow.isoformat())
    if data is None:
        p.report(f"Cotes de demain ({tomorrow})", False, err)
    else:
        items = data.get("response", [])
        paging = data.get("paging") or {}
        p.report(f"Cotes de demain ({tomorrow})", True,
                 f"{paging.get('total', 1)} pages de 10 matchs avec cotes")
        if items:
            bets = {b.get("name") for bk in items[0].get("bookmakers", []) for b in bk.get("bets", [])}
            present = [b for b in WANTED_BETS if b in bets]
            missing = [b for b in WANTED_BETS if b not in bets]
            p.report("Types de paris (1er match)", bool(present),
                     f"{len(items[0].get('bookmakers', []))} bookmakers ; présents : {', '.join(present) or 'aucun'}"
                     + (f" ; absents : {', '.join(missing)}" if missing else ""))
            league_id = items[0]["league"]["id"]
            league_season = items[0]["league"].get("season")
            data, err = p.call("odds", league=league_id, season=league_season, date=tomorrow.isoformat())
            p.report("Cotes par championnat et date", data is not None,
                     f"{len(data.get('response', []))} matchs" if data else err)

    data, err = p.call("status")
    if data:
        req = (data.get("response") or {}).get("requests", {})
        print(f"Requêtes utilisées après le test : {req.get('current')}/{req.get('limit_day')}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write("### Ce que permet la clé API-Football\n\n| | Essai | Résultat |\n|---|---|---|\n")
            fh.write("\n".join(p.lines) + "\n")
