"""Données simulées au format d'API-Football, pour l'essai hors ligne et les tests.

Deux championnats fictifs avec des équipes de forces connues : on simule
une saison de résultats, puis une journée de matchs avec des cotes de
bookmakers tirées des vraies probabilités (plus une marge).
"""

from __future__ import annotations

import math
import random
from datetime import datetime, timedelta, timezone

from . import model

_LEAGUES = {
    61: ("France", "Ligue 1", ["PSG", "Marseille", "Lyon", "Monaco", "Lille", "Lens", "Rennes", "Nice", "Nantes", "Brest"]),
    386: (
        "Ivory-Coast",
        "Ligue 1",
        ["ASEC Mimosas", "Africa Sports", "Stade d'Abidjan", "SOA", "San Pédro", "Sporting Gagnoa", "LYS Sassandra", "Mouna"],
    ),
}
_KICKOFFS = ["13:00", "15:00", "16:30", "18:00", "19:00", "19:45", "20:00", "21:00"]


def _poisson_sample(rng: random.Random, lam: float) -> int:
    k, p, threshold = 0, 1.0, math.exp(-lam)
    while True:
        p *= rng.random()
        if p <= threshold:
            return k
        k += 1


class SampleApi:
    """Même interface que `ApiFootball`, sans réseau."""

    def __init__(self, date: str, seed: int = 7):
        self.calls = 0
        self._rng = random.Random(seed)
        self._day = datetime.fromisoformat(date).replace(tzinfo=timezone.utc)
        self._strength = {}
        for _, (_, _, teams) in _LEAGUES.items():
            for t in teams:
                self._strength[t] = (math.exp(self._rng.gauss(0, 0.25)), math.exp(self._rng.gauss(0, 0.2)))
        self._history = {lid: self._simulate_season(lid) for lid in _LEAGUES}
        self._fixtures = self._make_fixtures()

    def _lambdas(self, home: str, away: str) -> tuple[float, float]:
        ah, dh = self._strength[home]
        aa, da = self._strength[away]
        return 1.45 * ah * da, 1.15 * aa * dh

    def _api_fixture(self, fid: int, lid: int, home: str, away: str, when: datetime, status: str, score=None, half=None):
        country, name, _ = _LEAGUES[lid]
        return {
            "fixture": {"id": fid, "date": when.strftime("%Y-%m-%dT%H:%M:%S+00:00"), "status": {"short": status, "elapsed": None}},
            "league": {"id": lid, "name": name, "country": country, "season": 2026},
            "teams": {"home": {"name": home}, "away": {"name": away}},
            "goals": {"home": score[0] if score else None, "away": score[1] if score else None},
            "score": {
                "halftime": {"home": half[0] if half else None, "away": half[1] if half else None},
                "fulltime": {"home": score[0] if score else None, "away": score[1] if score else None},
            },
        }

    def _simulate_season(self, lid: int) -> list[dict]:
        teams = _LEAGUES[lid][2]
        out = []
        fid = lid * 10000
        for round_ in range(14):
            when = self._day - timedelta(days=7 * (14 - round_))
            order = teams[:]
            self._rng.shuffle(order)
            for i in range(0, len(order) - 1, 2):
                h, a = order[i], order[i + 1]
                lh, la = self._lambdas(h, a)
                gh, ga = _poisson_sample(self._rng, lh), _poisson_sample(self._rng, la)
                hh = sum(1 for _ in range(gh) if self._rng.random() < model.FIRST_HALF_SHARE)
                ha = sum(1 for _ in range(ga) if self._rng.random() < model.FIRST_HALF_SHARE)
                fid += 1
                out.append(self._api_fixture(fid, lid, h, a, when, "FT", (gh, ga), (hh, ha)))
        return out

    def _make_fixtures(self) -> list[dict]:
        out = []
        fid = 900000
        for lid, (_, _, teams) in _LEAGUES.items():
            order = teams[:]
            self._rng.shuffle(order)
            for i in range(0, len(order) - 1, 2):
                hh, mm = map(int, self._rng.choice(_KICKOFFS).split(":"))
                fid += 1
                out.append(self._api_fixture(fid, lid, order[i], order[i + 1], self._day.replace(hour=hh, minute=mm), "NS"))
        return out

    # --- Interface d'ApiFootball -------------------------------------------------

    def current_leagues(self, country: str) -> list[dict]:
        self.calls += 1
        return [
            {"league": {"id": lid, "name": name}, "seasons": [{"year": 2026, "current": True}]}
            for lid, (c, name, _) in _LEAGUES.items()
            if c == country
        ]

    def fixtures_on(self, date: str) -> list[dict]:
        self.calls += 1
        return [f for f in self._fixtures if f["fixture"]["date"].startswith(date)]

    def finished(self, league_id: int, season: int) -> list[dict]:
        self.calls += 1
        return self._history.get(league_id, []) if season == 2026 else []

    def odds(self, fixture_id: int) -> list[dict]:
        self.calls += 1
        f = next(f for f in self._fixtures if f["fixture"]["id"] == fixture_id)
        lh, la = self._lambdas(f["teams"]["home"]["name"], f["teams"]["away"]["name"])
        p = model.market_probabilities(lh, la)
        books = []
        for name in ("Bookmaker A", "Bookmaker B", "Bookmaker C"):

            def odd(prob: float, margin: float = 1.06) -> str:
                return f"{max(1.01, 1 / (prob * margin) * math.exp(self._rng.gauss(0, 0.03))):.2f}"

            bets = [
                {"name": "Match Winner", "values": [{"value": v, "odd": odd(p[k])} for v, k in (("Home", "1"), ("Draw", "X"), ("Away", "2"))]},
                {
                    "name": "Double Chance",
                    "values": [{"value": v, "odd": odd(p[k])} for v, k in (("Home/Draw", "1X"), ("Draw/Away", "X2"), ("Home/Away", "12"))],
                },
                {
                    "name": "Goals Over/Under",
                    "values": [
                        {"value": f"{side} {line}", "odd": odd(p[code] if side == "Over" else 1 - p[code])}
                        for line, code in (("1.5", "o15"), ("2.5", "o25"), ("3.5", "o35"))
                        for side in ("Over", "Under")
                    ],
                },
                {"name": "Both Teams Score", "values": [{"value": "Yes", "odd": odd(p["by"])}, {"value": "No", "odd": odd(p["bn"])}]},
                {
                    "name": "Exact Score",
                    "values": [{"value": f"{h}:{a}", "odd": odd(p[f"cs:{h}-{a}"], 1.25)} for h in range(4) for a in range(4)],
                },
                {
                    "name": "HT/FT Double",
                    "values": [{"value": "Home/Home", "odd": odd(p["htft:1/1"], 1.15)}, {"value": "Away/Away", "odd": odd(p["htft:2/2"], 1.15)}],
                },
            ]
            books.append({"name": name, "bets": bets})
        return books

    def fixtures_by_ids(self, ids: list[int]) -> list[dict]:
        """Matchs joués : le score est tiré selon les vraies forces des équipes."""
        self.calls += 1
        out = []
        for f in self._fixtures:
            if f["fixture"]["id"] not in ids:
                continue
            lh, la = self._lambdas(f["teams"]["home"]["name"], f["teams"]["away"]["name"])
            gh, ga = _poisson_sample(self._rng, lh), _poisson_sample(self._rng, la)
            hh = sum(1 for _ in range(gh) if self._rng.random() < model.FIRST_HALF_SHARE)
            ha = sum(1 for _ in range(ga) if self._rng.random() < model.FIRST_HALF_SHARE)
            done = dict(f)
            done["fixture"] = {**f["fixture"], "status": {"short": "FT", "elapsed": 90}}
            done["goals"] = {"home": gh, "away": ga}
            done["score"] = {"halftime": {"home": hh, "away": ha}, "fulltime": {"home": gh, "away": ga}}
            out.append(done)
        return out
