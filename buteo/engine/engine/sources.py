"""Sondage des nouvelles sources de données (football-data.org et Highlightly).

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
SAMPLE_CHARS = 3000


def _show(session: requests.Session, base: str, path: str, **params) -> dict | list | None:
    print(f"\n### GET {path} {params}")
    try:
        r = session.get(f"{base}{path}", params=params, timeout=30)
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
    today = now.date().isoformat()
    yesterday = (now - timedelta(days=1)).date().isoformat()
    _show(s, HIGHLIGHTLY, "/leagues", countryName="France", limit=10)
    for country in ("Ivory Coast", "Senegal", "Morocco", "Cameroon"):
        data = _show(s, HIGHLIGHTLY, "/leagues", countryName=country, limit=10)
        if isinstance(data, dict):
            for lg in data.get("data", []):
                print(f"  {lg.get('id')} {lg.get('name')}")
    matches = _show(s, HIGHLIGHTLY, "/matches", date=today, timezone="UTC", limit=100)
    _show(s, HIGHLIGHTLY, "/matches", date=yesterday, timezone="UTC", limit=5)
    first = (matches or {}).get("data", []) if isinstance(matches, dict) else matches or []
    if first:
        _show(s, HIGHLIGHTLY, "/odds", matchId=first[0].get("id"), oddsType="prematch")
    _show(s, HIGHLIGHTLY, "/bookmakers", limit=5)


def run(now: datetime) -> None:
    fd, hl = os.environ.get("FOOTBALL_DATA_KEY"), os.environ.get("HIGHLIGHTLY_API_KEY")
    if fd:
        football_data(fd, now)
    else:
        print("::notice::Secret FOOTBALL_DATA_KEY manquant.")
    if hl:
        highlightly(hl, now)
    else:
        print("::notice::Secret HIGHLIGHTLY_API_KEY manquant.")
