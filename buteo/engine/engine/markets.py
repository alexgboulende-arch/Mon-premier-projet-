"""Paris proposés par Buteo : libellé en français, cotes des bookmakers, résultat.

Les codes des paris sont les mêmes que dans l'application Flutter
(`lib/data/tips_repository.dart`).
"""

from __future__ import annotations

import statistics

# Libellé affiché dans l'app. {home} et {away} sont remplacés par les équipes.
LABELS = {
    "1": "Victoire {home}",
    "2": "Victoire {away}",
    "1X": "{home} ou nul",
    "X2": "{away} ou nul",
    "12": "Pas de match nul",
    "o15": "Plus de 1,5 buts",
    "o25": "Plus de 2,5 buts",
    "o35": "Plus de 3,5 buts",
    "u25": "Moins de 2,5 buts",
    "u35": "Moins de 3,5 buts",
    "by": "Les deux marquent : oui",
    "bn": "Les deux marquent : non",
    "htft:1/1": "{home} mène à la pause et gagne",
    "htft:2/2": "{away} mène à la pause et gagne",
}


def label(market: str, home: str, away: str) -> str:
    if market.startswith("cs:"):
        h, a = market[3:].split("-")
        return f"Score exact {h}-{a}"
    return LABELS[market].format(home=home, away=away)


# Correspondance entre les paris de l'API (nom du pari, valeur) et nos codes.
_API_BETS = {
    "Match Winner": {"Home": "1", "Draw": "X", "Away": "2"},
    "Double Chance": {"Home/Draw": "1X", "Draw/Away": "X2", "Home/Away": "12"},
    "Goals Over/Under": {
        "Over 1.5": "o15",
        "Over 2.5": "o25",
        "Over 3.5": "o35",
        "Under 1.5": "u15",
        "Under 2.5": "u25",
        "Under 3.5": "u35",
    },
    "Both Teams Score": {"Yes": "by", "No": "bn"},
    "HT/FT Double": {"Home/Home": "htft:1/1", "Away/Away": "htft:2/2"},
}

# Paris complémentaires : leurs probabilités « sans marge » se calculent ensemble.
_GROUPS = [("1", "X", "2"), ("o15", "u15"), ("o25", "u25"), ("o35", "u35"), ("by", "bn")]


def bookmaker_odds(bookmakers: list[dict]) -> dict[str, float]:
    """Cote médiane de chaque pari parmi les bookmakers (réponse de /odds)."""
    seen: dict[str, list[float]] = {}
    for bookmaker in bookmakers:
        for bet in bookmaker.get("bets", []):
            name = bet.get("name")
            mapping = _API_BETS.get(name)
            for v in bet.get("values", []):
                value = str(v.get("value"))
                code = None
                if mapping is not None:
                    code = mapping.get(value)
                elif name == "Exact Score" and ":" in value:
                    h, a = value.split(":")
                    code = f"cs:{int(h)}-{int(a)}"
                try:
                    odd = float(v.get("odd"))
                except (TypeError, ValueError):
                    continue
                if code and odd > 1.0:
                    seen.setdefault(code, []).append(odd)
    return {code: round(statistics.median(values), 2) for code, values in seen.items()}


def market_probabilities_from_odds(odds: dict[str, float]) -> dict[str, float]:
    """Probabilités implicites des bookmakers, une fois leur marge retirée."""
    out: dict[str, float] = {}
    margin = 1.05
    for group in _GROUPS:
        if all(g in odds for g in group):
            inv = [1 / odds[g] for g in group]
            total = sum(inv)
            if group == ("1", "X", "2"):
                margin = total
            for g, x in zip(group, inv):
                out[g] = x / total
    # Paris sans contrepartie directe : on retire la marge observée sur 1X2.
    for code, odd in odds.items():
        if code not in out:
            out[code] = min(1 / odd / margin, 0.99)
    return out


def check(market: str, home: int, away: int, ht_home: int | None = None, ht_away: int | None = None) -> bool:
    """Le pari est-il gagné avec ce score (90 minutes) ?"""
    total = home + away
    if market.startswith("cs:"):
        h, a = market[3:].split("-")
        return home == int(h) and away == int(a)
    if market.startswith("htft:"):
        if ht_home is None or ht_away is None:
            return False
        ht, ft = market[5:].split("/")
        ht_result = "1" if ht_home > ht_away else ("2" if ht_away > ht_home else "X")
        ft_result = "1" if home > away else ("2" if away > home else "X")
        return ht_result == ht and ft_result == ft
    return {
        "1": home > away,
        "2": away > home,
        "X": home == away,
        "1X": home >= away,
        "X2": away >= home,
        "12": home != away,
        "o15": total >= 2,
        "o25": total >= 3,
        "o35": total >= 4,
        "u15": total <= 1,
        "u25": total <= 2,
        "u35": total <= 3,
        "by": home > 0 and away > 0,
        "bn": not (home > 0 and away > 0),
    }[market]
