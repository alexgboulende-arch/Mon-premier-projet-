"""Choix des pronos de chaque rubrique.

Pour chaque match, on compare la probabilité de chaque pari (modèle et
bookmakers mélangés) à la cote proposée. Chaque rubrique a ses règles :
fourchette de cotes, confiance minimale, et critère de tri (la confiance
pour les rubriques « sûres », la valeur pour les autres).
"""

from __future__ import annotations

import itertools
import math
from dataclasses import dataclass
from datetime import datetime

from . import markets

# Poids du modèle face aux bookmakers. Les cotes contiennent déjà beaucoup
# d'information : le modèle sert surtout à repérer les écarts.
MODEL_WEIGHT = 0.35


@dataclass(frozen=True)
class Fixture:
    id: int
    league: str
    country: str
    home: str
    away: str
    kickoff: datetime


@dataclass(frozen=True)
class Candidate:
    fixture: Fixture
    market: str
    odds: float
    probability: float  # probabilité retenue (modèle + bookmakers)

    @property
    def value(self) -> float:
        """Gain moyen espéré pour une mise de 1 (positif = cote intéressante)."""
        return self.probability * self.odds - 1

    @property
    def confidence(self) -> int:
        return max(1, min(99, round(self.probability * 100)))


@dataclass(frozen=True)
class Rule:
    tier: str
    markets: tuple[str, ...]
    odds: tuple[float, float]
    min_probability: float
    count: int = 0  # pronos simples
    legs: int = 0  # combiné
    total: tuple[float, float] = (0, 0)  # cote totale du combiné
    by_value: bool = False  # trier par valeur plutôt que par confiance


EXACT_SCORES = tuple(f"cs:{h}-{a}" for h in range(4) for a in range(4))

RULES: dict[str, Rule] = {
    "selection": Rule("free", ("1", "1X", "X2", "2", "o15"), (1.25, 2.10), 0.60, count=3),
    "combine": Rule("free", ("1X", "X2", "o15", "u35"), (1.15, 1.55), 0.72, legs=3, total=(2.0, 3.5)),
    "overunder": Rule("free", ("o15", "o25", "o35", "u25", "u35"), (1.30, 2.20), 0.50, count=4, by_value=True),
    "btts": Rule("free", ("by", "bn"), (1.50, 2.20), 0.50, count=3, by_value=True),
    "bonus": Rule("free", ("2", "o35", "htft:1/1", "htft:2/2"), (2.20, 4.50), 0.25, count=1, by_value=True),
    "score": Rule("elite", EXACT_SCORES, (5.0, 12.0), 0.08, count=2, by_value=True),
    "htft": Rule("pro", ("htft:1/1", "htft:2/2"), (2.20, 5.00), 0.25, count=2, by_value=True),
    "c5": Rule("elite", ("1", "1X", "X2", "o15", "o25", "by"), (1.30, 2.00), 0.55, legs=4, total=(5.0, 9.0)),
    "c10": Rule("pro", ("1", "2", "o25", "by", "u25"), (1.45, 2.40), 0.45, legs=5, total=(10.0, 20.0)),
    "simples": Rule("pro", ("1", "2", "o25", "by"), (1.60, 2.60), 0.42, count=3, by_value=True),
}


def blend(model: dict[str, float], bookmaker: dict[str, float], weight: float = MODEL_WEIGHT) -> dict[str, float]:
    """Mélange la probabilité du modèle et celle des bookmakers."""
    out = {}
    for code, p_book in bookmaker.items():
        p_model = model.get(code)
        out[code] = p_book if p_model is None else weight * p_model + (1 - weight) * p_book
    return out


def candidates(
    fixture: Fixture, model: dict[str, float], odds: dict[str, float], model_weight: float = MODEL_WEIGHT
) -> list[Candidate]:
    probabilities = blend(model, markets.market_probabilities_from_odds(odds), model_weight)
    return [
        Candidate(fixture, code, odds[code], probabilities[code])
        for code in odds
        if code in probabilities and (code in markets.LABELS or code.startswith("cs:"))
    ]


def _eligible(rule: Rule, pool: list[Candidate]) -> list[Candidate]:
    lo, hi = rule.odds
    return [
        c
        for c in pool
        if c.market in rule.markets and lo <= c.odds <= hi and c.probability >= rule.min_probability
        # On écarte les paris nettement défavorables, même dans les rubriques « sûres ».
        and c.value >= -0.04
    ]


def _best_per_fixture(items: list[Candidate], key) -> list[Candidate]:
    best: dict[int, Candidate] = {}
    for c in items:
        if c.fixture.id not in best or key(c) > key(best[c.fixture.id]):
            best[c.fixture.id] = c
    return sorted(best.values(), key=key, reverse=True)


def pick_singles(rule: Rule, pool: list[Candidate]) -> list[Candidate]:
    key = (lambda c: c.value) if rule.by_value else (lambda c: c.probability)
    return _best_per_fixture(_eligible(rule, pool), key)[: rule.count]


def pick_combo(rule: Rule, pool: list[Candidate]) -> list[Candidate]:
    """Combiné le plus probable dont la cote totale est dans la fourchette."""
    options = _best_per_fixture(_eligible(rule, pool), lambda c: c.probability)[:14]
    lo, hi = rule.total
    best: tuple[float, tuple[Candidate, ...]] | None = None
    for combo in itertools.combinations(options, rule.legs):
        total = math.prod(c.odds for c in combo)
        if not lo <= total <= hi:
            continue
        p = math.prod(c.probability for c in combo)
        if best is None or p > best[0]:
            best = (p, combo)
    return sorted(best[1], key=lambda c: c.fixture.kickoff) if best else []


def pick_all(pool: list[Candidate]) -> dict[str, list[Candidate]]:
    """Pronos du jour pour chaque rubrique de football."""
    out = {}
    for rubric, rule in RULES.items():
        picks = pick_combo(rule, pool) if rule.legs else pick_singles(rule, pool)
        out[rubric] = sorted(picks, key=lambda c: c.fixture.kickoff)
    return out
