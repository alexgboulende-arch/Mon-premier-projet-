"""Modèle statistique des matchs de football.

Chaque équipe a une force d'attaque et une fragilité défensive, estimées à
partir de ses résultats récents (les matchs anciens comptent moins). Le
nombre de buts de chaque équipe suit une loi de Poisson ; une petite
correction (Dixon-Coles) rend les scores serrés (0-0, 1-1…) plus réalistes.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import datetime

MAX_GOALS = 10
# Part des buts marqués en première mi-temps (moyenne observée en Europe).
FIRST_HALF_SHARE = 0.45
# Corrélation des scores serrés (Dixon-Coles), négative = un peu plus de 0-0 et 1-1.
RHO = -0.08


@dataclass(frozen=True)
class Result:
    """Un match terminé."""

    home: str
    away: str
    home_goals: int
    away_goals: int
    played: datetime


@dataclass
class Strengths:
    """Forces estimées pour un championnat."""

    home_rate: float  # buts moyens de l'équipe à domicile
    away_rate: float  # buts moyens de l'équipe à l'extérieur
    attack: dict[str, float] = field(default_factory=dict)
    defence: dict[str, float] = field(default_factory=dict)  # > 1 : encaisse plus que la moyenne

    def expected_goals(self, home: str, away: str) -> tuple[float, float]:
        att_h = self.attack.get(home, 1.0)
        att_a = self.attack.get(away, 1.0)
        def_h = self.defence.get(home, 1.0)
        def_a = self.defence.get(away, 1.0)
        return self.home_rate * att_h * def_a, self.away_rate * att_a * def_h


def fit(results: list[Result], today: datetime, half_life_days: float = 180, prior: float = 3.0) -> Strengths:
    """Estime les forces par itérations successives.

    `prior` ajoute des matchs « moyens » fictifs à chaque équipe : avec peu de
    matchs joués, les forces restent proches de la moyenne au lieu de
    s'emballer sur deux ou trois résultats.
    """
    if not results:
        return Strengths(1.4, 1.1)

    weights = [0.5 ** (max((today - r.played).days, 0) / half_life_days) for r in results]
    total_w = sum(weights)
    home_rate = sum(w * r.home_goals for w, r in zip(weights, results)) / total_w
    away_rate = sum(w * r.away_goals for w, r in zip(weights, results)) / total_w
    home_rate = max(home_rate, 0.3)
    away_rate = max(away_rate, 0.3)

    teams = sorted({r.home for r in results} | {r.away for r in results})
    attack = {t: 1.0 for t in teams}
    defence = {t: 1.0 for t in teams}

    for _ in range(60):
        scored = {t: 0.0 for t in teams}
        exp_scored = {t: 0.0 for t in teams}
        for w, r in zip(weights, results):
            scored[r.home] += w * r.home_goals
            scored[r.away] += w * r.away_goals
            exp_scored[r.home] += w * home_rate * defence[r.away]
            exp_scored[r.away] += w * away_rate * defence[r.home]
        new_attack = {
            t: (scored[t] + prior * 1.0) / (exp_scored[t] + prior) if exp_scored[t] + prior > 0 else 1.0 for t in teams
        }

        conceded = {t: 0.0 for t in teams}
        exp_conceded = {t: 0.0 for t in teams}
        for w, r in zip(weights, results):
            conceded[r.home] += w * r.away_goals
            conceded[r.away] += w * r.home_goals
            exp_conceded[r.home] += w * away_rate * new_attack[r.away]
            exp_conceded[r.away] += w * home_rate * new_attack[r.home]
        new_defence = {
            t: (conceded[t] + prior) / (exp_conceded[t] + prior) if exp_conceded[t] + prior > 0 else 1.0 for t in teams
        }

        # On garde une moyenne de 1 pour que les taux de base restent interprétables.
        mean_a = sum(new_attack.values()) / len(teams)
        mean_d = sum(new_defence.values()) / len(teams)
        new_attack = {t: v / mean_a for t, v in new_attack.items()}
        new_defence = {t: v / mean_d for t, v in new_defence.items()}

        change = max(abs(new_attack[t] - attack[t]) + abs(new_defence[t] - defence[t]) for t in teams)
        attack, defence = new_attack, new_defence
        if change < 1e-6:
            break

    return Strengths(home_rate, away_rate, attack, defence)


def _poisson(lam: float, n: int) -> list[float]:
    probs = [math.exp(-lam)]
    for k in range(1, n + 1):
        probs.append(probs[-1] * lam / k)
    return probs


def score_matrix(lam_home: float, lam_away: float, n: int = MAX_GOALS, rho: float = RHO) -> list[list[float]]:
    """Probabilité de chaque score [buts domicile][buts extérieur]."""
    ph = _poisson(lam_home, n)
    pa = _poisson(lam_away, n)
    m = [[ph[i] * pa[j] for j in range(n + 1)] for i in range(n + 1)]
    # Correction Dixon-Coles des petits scores.
    m[0][0] *= 1 - lam_home * lam_away * rho
    m[0][1] *= 1 + lam_home * rho
    m[1][0] *= 1 + lam_away * rho
    m[1][1] *= 1 - rho
    total = sum(map(sum, m))
    return [[p / total for p in row] for row in m]


def _outcome(h: int, a: int) -> str:
    return "1" if h > a else ("2" if a > h else "X")


def market_probabilities(lam_home: float, lam_away: float) -> dict[str, float]:
    """Probabilité de chaque pari proposé par Buteo."""
    m = score_matrix(lam_home, lam_away)
    n = len(m)
    p: dict[str, float] = {k: 0.0 for k in ("1", "X", "2", "o15", "o25", "o35", "by")}
    for i in range(n):
        for j in range(n):
            q = m[i][j]
            p[_outcome(i, j)] += q
            if i + j >= 2:
                p["o15"] += q
            if i + j >= 3:
                p["o25"] += q
            if i + j >= 4:
                p["o35"] += q
            if i > 0 and j > 0:
                p["by"] += q
            if i <= 5 and j <= 5:
                p[f"cs:{i}-{j}"] = q
    p["1X"] = p["1"] + p["X"]
    p["X2"] = p["X"] + p["2"]
    p["12"] = p["1"] + p["2"]
    p["u25"] = 1 - p["o25"]
    p["u35"] = 1 - p["o35"]
    p["bn"] = 1 - p["by"]
    p.update(_half_time_full_time(lam_home, lam_away))
    return p


def _half_time_full_time(lam_home: float, lam_away: float) -> dict[str, float]:
    """Mi-temps / fin de match : on additionne les deux mi-temps, supposées indépendantes."""
    first = score_matrix(lam_home * FIRST_HALF_SHARE, lam_away * FIRST_HALF_SHARE, n=6, rho=0)
    second = score_matrix(lam_home * (1 - FIRST_HALF_SHARE), lam_away * (1 - FIRST_HALF_SHARE), n=7, rho=0)
    out: dict[str, float] = {}
    for h1, row in enumerate(first):
        for a1, p1 in enumerate(row):
            ht = _outcome(h1, a1)
            for h2, row2 in enumerate(second):
                for a2, p2 in enumerate(row2):
                    key = f"htft:{ht}/{_outcome(h1 + h2, a1 + a2)}"
                    out[key] = out.get(key, 0.0) + p1 * p2
    return out
