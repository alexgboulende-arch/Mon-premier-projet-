"""Documents de pronos : création, mise à jour des résultats, statistiques.

Format d'un document `picks/{date}_{rubrique}` (lu par l'app) :

    date        « 2026-10-14 »
    rubric      identifiant de la rubrique (« selection », « c10 »…)
    tier        « free », « pro » ou « elite »
    publicAfter instant à partir duquel tout le monde peut lire le document
                (tout de suite pour le gratuit, le lendemain pour le VIP)
    combo       vrai pour un combiné
    status      « soon », « live », « won », « lost », « void » (ensemble des pronos)
    tips        liste de pronos :
        fixtureId, sport, league, country, home, away,
        kickoff (« 2026-10-14T19:00:00Z »), market, label, odds, confidence,
        status, minute (« 63' », « MT » ou absent), score {home, away} ou absent,
        halfTime {home, away} ou absent
"""

from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone

from . import api_football as api
from . import markets
from .selection import RULES, Candidate
from .store import iso

SETTLED = {"won", "lost", "void"}


def tip_doc(c: Candidate) -> dict:
    f = c.fixture
    return {
        "fixtureId": f.id,
        "sport": "foot",
        "league": f.league,
        "country": f.country,
        "home": f.home,
        "away": f.away,
        "kickoff": iso(f.kickoff),
        "market": c.market,
        "label": markets.label(c.market, f.home, f.away),
        "odds": c.odds,
        "confidence": c.confidence,
        "status": "soon",
    }


def rubric_doc(rubric: str, date: str, picks: list[Candidate], now: datetime) -> dict:
    rule = RULES[rubric]
    day_after = datetime.fromisoformat(date).replace(tzinfo=timezone.utc) + timedelta(days=1)
    return {
        "date": date,
        "rubric": rubric,
        "tier": rule.tier,
        "publicAfter": now if rule.tier == "free" else day_after,
        "combo": bool(rule.legs),
        "status": "soon",
        "tips": [tip_doc(c) for c in picks],
        "publishedAt": now,
        "updatedAt": now,
    }


def tip_update(tip: dict, fixture: dict) -> dict:
    """Nouvel état d'un prono d'après les données du match (réponse de /fixtures)."""
    status = fixture["fixture"]["status"]
    short = status.get("short")
    goals = fixture.get("goals") or {}
    score = fixture.get("score") or {}
    full = score.get("fulltime") or {}
    half = score.get("halftime") or {}
    new = dict(tip)
    new.pop("minute", None)

    if short in api.CANCELLED:
        new["status"] = "void"
        return new
    if short in api.NOT_STARTED:
        new["status"] = "soon"
        return new
    if goals.get("home") is not None:
        new["score"] = {"home": goals["home"], "away": goals["away"]}
    if half.get("home") is not None:
        new["halfTime"] = {"home": half["home"], "away": half["away"]}
    if short in api.FINISHED:
        # Les paris portent sur le score après 90 minutes (prolongations exclues).
        h = full.get("home") if full.get("home") is not None else goals.get("home", 0)
        a = full.get("away") if full.get("away") is not None else goals.get("away", 0)
        new["score"] = {"home": h, "away": a}
        won = markets.check(tip["market"], h, a, half.get("home"), half.get("away"))
        new["status"] = "won" if won else "lost"
        return new
    new["status"] = "live"
    new["minute"] = "MT" if short == "HT" else f"{status.get('elapsed') or 0}'"
    return new


def doc_status(doc: dict) -> str:
    """État de la rubrique entière : un combiné est perdu dès qu'un match est perdu."""
    states = [t["status"] for t in doc.get("tips", [])]
    if not states:
        return "void"
    if doc.get("combo"):
        if "lost" in states:
            return "lost"
        if all(s in ("won", "void") for s in states):
            return "void" if all(s == "void" for s in states) else "won"
    elif all(s in SETTLED for s in states):
        return "won" if "won" in states else ("lost" if "lost" in states else "void")
    return "live" if "live" in states or any(s in SETTLED for s in states) else "soon"


def day_stats(docs: dict[str, dict]) -> dict[str, dict]:
    """Résultats d'une journée par rubrique, mise fixe de 1 par prono.

    Un combiné compte comme un seul prono ; un match annulé n'est pas compté
    (et, dans un combiné, il compte comme gagné à la cote 1).
    """
    out: dict[str, dict] = {}
    for doc in docs.values():
        rubric = doc["rubric"]
        s = {"count": 0, "won": 0, "oddsSum": 0.0, "profit": 0.0}
        if doc.get("combo"):
            status = doc_status(doc)
            if status in ("won", "lost"):
                odds = math.prod(t["odds"] for t in doc["tips"] if t["status"] != "void")
                s = _add(s, round(odds, 2), status == "won")
        else:
            for t in doc.get("tips", []):
                if t["status"] in ("won", "lost"):
                    s = _add(s, t["odds"], t["status"] == "won")
        if s["count"]:
            out[rubric] = s
    return out


def _add(s: dict, odds: float, won: bool) -> dict:
    return {
        "count": s["count"] + 1,
        "won": s["won"] + (1 if won else 0),
        "oddsSum": round(s["oddsSum"] + odds, 2),
        "profit": round(s["profit"] + (odds - 1 if won else -1), 2),
    }
