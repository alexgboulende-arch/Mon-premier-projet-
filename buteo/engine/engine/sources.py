"""Sondage des nouvelles sources de données (football-data.org, Highlightly, The Odds API).

Quelques requêtes pour voir le format réel des réponses avant d'écrire les
clients : chemin, code HTTP, quota restant, clés de la réponse et un exemple
d'élément. Les clés d'API ne sont jamais affichées.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta

import requests

FOOTBALL_DATA = "https://api.football-data.org/v4"
HIGHLIGHTLY = "https://soccer.highlightly.net"
HIGHLIGHTLY_RAPIDAPI = "football-highlights-api.p.rapidapi.com"
ODDS_API = "https://api.the-odds-api.com/v4"
SAMPLE_CHARS = 3000


def _show(session: requests.Session, base: str, path: str, secret: dict | None = None, **params) -> dict | list | None:
    """`secret` : paramètres envoyés mais jamais affichés (clé passée dans l'adresse)."""
    print(f"\n### GET {path} {params}")
    try:
        r = session.get(f"{base}{path}", params={**params, **(secret or {})}, timeout=30)
    except requests.RequestException as e:
        print(f"réseau : {e.__class__.__name__}")
        return None
    quota = {k: v for k, v in r.headers.items() if any(w in k.lower() for w in ("limit", "remaining", "request", "reset"))}
    print(f"HTTP {r.status_code} · quota {quota}")
    try:
        data = r.json()
    except ValueError:
        print(r.text[:500])
        return None
    if isinstance(data, dict):
        print("clés :", {k: (f"liste de {len(v)}" if isinstance(v, list) else type(v).__name__) for k, v in data.items()})
        items = next((v for v in data.values() if isinstance(v, list) and v), None)
        if items is None:
            print(json.dumps(data, ensure_ascii=False)[:SAMPLE_CHARS])
    else:
        print(f"liste de {len(data)}")
        items = data
    if items:
        print("exemple :", json.dumps(items[0], ensure_ascii=False)[:SAMPLE_CHARS])
        if len(items) > 1:
            print("dernier :", json.dumps(items[-1], ensure_ascii=False)[:SAMPLE_CHARS])
    return data


def football_data(key: str, now: datetime) -> None:
    print("\n## football-data.org")
    s = requests.Session()
    s.headers.update({"X-Auth-Token": key})
    today = now.date().isoformat()
    yesterday = (now - timedelta(days=1)).date().isoformat()
    comps = _show(s, FOOTBALL_DATA, "/competitions")
    if isinstance(comps, dict):
        for c in comps.get("competitions", []):
            print(f"  {c.get('id')} {c.get('code')} {c.get('name')} ({(c.get('area') or {}).get('name')}) plan={c.get('plan')}")
    _show(s, FOOTBALL_DATA, "/matches", dateFrom=today, dateTo=today)
    _show(s, FOOTBALL_DATA, "/matches", dateFrom=yesterday, dateTo=yesterday, status="FINISHED")
    _show(s, FOOTBALL_DATA, "/competitions/FL1/matches", status="FINISHED")


def highlightly(key: str, now: datetime) -> None:
    print("\n## Highlightly")
    s = requests.Session()
    s.headers.update({"x-rapidapi-key": key})
    base = HIGHLIGHTLY
    probe = _show(s, base, "/leagues", countryName="France", limit=10)
    if isinstance(probe, dict) and probe.get("statusCode") == 401:
        print("Clé refusée par highlightly.net : essai par RapidAPI.")
        s.headers.update({"x-rapidapi-host": HIGHLIGHTLY_RAPIDAPI})
        base = f"https://{HIGHLIGHTLY_RAPIDAPI}"
        probe = _show(s, base, "/leagues", countryName="France", limit=10)
    if not isinstance(probe, dict) or "data" not in probe:
        return
    for country in ("Ivory Coast", "Senegal", "Morocco", "Cameroon"):
        data = _show(s, base, "/leagues", countryName=country, limit=10)
        if isinstance(data, dict):
            for lg in data.get("data", []):
                print(f"  {lg.get('id')} {lg.get('name')}")
    today = now.date().isoformat()
    yesterday = (now - timedelta(days=1)).date().isoformat()
    matches = _show(s, base, "/matches", date=today, timezone="UTC", limit=100)
    _show(s, base, "/matches", date=yesterday, timezone="UTC", limit=5)
    first = matches.get("data", []) if isinstance(matches, dict) else []
    if first:
        _show(s, base, "/odds", matchId=first[0].get("id"), oddsType="prematch")


def odds_api(key: str) -> None:
    print("\n## The Odds API")
    s = requests.Session()
    sports = _show(s, ODDS_API, "/sports", secret={"apiKey": key})  # gratuit, hors quota
    if isinstance(sports, list):
        for sp in sports:
            if sp.get("group") == "Soccer":
                print(f"  {sp.get('key')} · {sp.get('title')} · actif={sp.get('active')}")
    # Une requête = toutes les cotes d'un championnat ; coût : 1 par marché et par région.
    _show(s, ODDS_API, "/sports/soccer_france_ligue_one/odds", secret={"apiKey": key}, regions="eu", markets="h2h,totals", oddsFormat="decimal")


def details(fd_key: str | None, hl_key: str | None, now: datetime) -> None:
    """Derniers formats à vérifier avant d'écrire les clients."""
    if fd_key:
        print("\n## football-data.org : recherche par identifiants")
        s = requests.Session()
        s.headers.update({"X-Auth-Token": fd_key})
        _show(s, FOOTBALL_DATA, "/matches", ids="559715,559648")
        _show(s, FOOTBALL_DATA, "/competitions/FL1/matches", season=2025, status="FINISHED")
    if not hl_key:
        return
    print("\n## Highlightly : championnats et filtres")
    s = requests.Session()
    s.headers.update({"x-rapidapi-key": hl_key})
    ids = {}
    for params in ({"countryName": "France"}, {"countryName": "Belgium"}, {"leagueName": "UEFA Europa League"}):
        data = _show(s, HIGHLIGHTLY, "/leagues", limit=20, **params)
        for lg in (data or {}).get("data", []) if isinstance(data, dict) else []:
            print(f"  {lg.get('id')} {lg.get('name')} ({(lg.get('country') or {}).get('name')})")
            ids.setdefault(lg.get("name"), lg.get("id"))
    league = ids.get("Ligue 2")
    if league:
        day = now.date()
        for back in range(0, 7):  # dernier jour de match de Ligue 2
            d = (day - timedelta(days=back)).isoformat()
            data = _show(s, HIGHLIGHTLY, "/matches", leagueId=league, date=d, timezone="UTC")
            if isinstance(data, dict) and data.get("data"):
                break
        _show(s, HIGHLIGHTLY, "/matches", leagueId=league, season=2026, limit=100)


def run(now: datetime) -> None:
    fd, hl = os.environ.get("FOOTBALL_DATA_KEY"), os.environ.get("HIGHLIGHTLY_API_KEY")
    if os.environ.get("SONDAGE") == "details":
        details(fd, hl.strip() if hl else None, now)
        return
    if fd:
        football_data(fd, now)
    else:
        print("::notice::Secret FOOTBALL_DATA_KEY manquant.")
    if hl:
        highlightly(hl.strip(), now)
    else:
        print("::notice::Secret HIGHLIGHTLY_API_KEY manquant.")
    odds = os.environ.get("ODDS_API_KEY")
    if odds:
        odds_api(odds.strip())
    else:
        print("::notice::Secret ODDS_API_KEY manquant.")
