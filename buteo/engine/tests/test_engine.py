import math
from datetime import datetime, timedelta, timezone

import pytest

from engine import __main__ as cli
from engine import jobs, markets, model
from engine.notify import Notifier
from engine.picks import day_stats, doc_status, tip_update
from engine.sample import SampleApi
from engine.selection import RULES
from engine.store import MemoryStore

DATE = "2026-10-14"
EVE = datetime(2026, 10, 13, 23, 35, tzinfo=timezone.utc)
NIGHT = datetime(2026, 10, 14, 23, 59, tzinfo=timezone.utc)


# --- Modèle -----------------------------------------------------------------


def test_les_probabilites_sont_coherentes():
    p = model.market_probabilities(1.6, 1.0)
    assert p["1"] + p["X"] + p["2"] == pytest.approx(1, abs=1e-9)
    assert p["o25"] + p["u25"] == pytest.approx(1)
    assert p["1X"] == pytest.approx(p["1"] + p["X"])
    assert p["1"] > p["2"]
    assert p["o15"] > p["o25"] > p["o35"]
    assert sum(v for k, v in p.items() if k.startswith("htft:")) == pytest.approx(1, abs=1e-6)


def test_le_modele_retrouve_les_equipes_fortes():
    """Six équipes nettement différentes, 40 journées : l'ordre doit être retrouvé."""
    import random

    from engine.sample import _poisson_sample

    rng = random.Random(11)
    true = {"A": 1.7, "B": 1.35, "C": 1.1, "D": 0.9, "E": 0.7, "F": 0.5}  # attaque ; défense = 1 / attaque
    teams = list(true)
    results = []
    for day in range(40):
        for h in teams:
            for a in teams:
                if h != a and rng.random() < 0.2:
                    lh = 1.45 * true[h] / true[a]
                    la = 1.15 * true[a] / true[h]
                    played = EVE - timedelta(days=200 - day * 5)
                    results.append(model.Result(h, a, _poisson_sample(rng, lh), _poisson_sample(rng, la), played))
    s = model.fit(results, EVE)
    quality = {t: s.attack[t] / s.defence[t] for t in teams}
    assert sorted(teams, key=quality.get, reverse=True) == teams
    # L'équipe la plus forte gagne bien plus souvent contre la plus faible.
    lh, la = s.expected_goals("A", "F")
    assert model.market_probabilities(lh, la)["1"] > 0.7


def test_sans_historique_les_equipes_sont_moyennes():
    s = model.fit([], EVE)
    assert s.expected_goals("A", "B") == (1.4, 1.1)


# --- Paris -------------------------------------------------------------------


def test_cotes_des_bookmakers():
    books = [
        {"bets": [{"name": "Match Winner", "values": [{"value": "Home", "odd": "1.80"}, {"value": "Draw", "odd": "3.5"}]}]},
        {"bets": [{"name": "Match Winner", "values": [{"value": "Home", "odd": "2.00"}]}]},
        {"bets": [{"name": "Exact Score", "values": [{"value": "2:1", "odd": "9.00"}, {"value": "x", "odd": "2"}]}]},
    ]
    assert markets.bookmaker_odds(books) == {"1": 1.9, "X": 3.5, "cs:2-1": 9.0}


def test_marge_des_bookmakers_retiree():
    p = markets.market_probabilities_from_odds({"1": 2.0, "X": 3.3, "2": 3.6, "1X": 1.3})
    assert p["1"] + p["X"] + p["2"] == pytest.approx(1)
    assert p["1X"] < 1 / 1.3


@pytest.mark.parametrize(
    "market,score,half,won",
    [
        ("1", (2, 1), None, True),
        ("1X", (1, 1), None, True),
        ("X2", (2, 0), None, False),
        ("o25", (2, 1), None, True),
        ("u25", (2, 1), None, False),
        ("by", (1, 0), None, False),
        ("bn", (0, 0), None, True),
        ("cs:2-1", (2, 1), None, True),
        ("htft:1/1", (2, 1), (1, 0), True),
        ("htft:1/1", (2, 1), (0, 0), False),
        ("htft:2/2", (0, 3), (0, 1), True),
    ],
)
def test_resultat_des_paris(market, score, half, won):
    assert markets.check(market, *score, *(half or (None, None))) is won


def test_libelles_en_francais():
    assert markets.label("1X", "Lyon", "Nice") == "Lyon ou nul"
    assert markets.label("cs:2-0", "Lyon", "Nice") == "Score exact 2-0"
    assert markets.label("htft:2/2", "Lyon", "Nice") == "Nice mène à la pause et gagne"


# --- Publication et résultats -------------------------------------------------


@pytest.fixture
def published():
    store = MemoryStore()
    api = SampleApi(DATE)
    chosen = jobs.publish(api, store, DATE, EVE)
    return api, store, chosen


def test_chaque_rubrique_respecte_ses_regles(published):
    _, _, chosen = published
    for rubric, items in chosen.items():
        rule = RULES[rubric]
        assert items, f"{rubric} vide"
        assert len({c.fixture.id for c in items}) == len(items), "un match deux fois"
        for c in items:
            assert c.market in rule.markets
            assert rule.odds[0] <= c.odds <= rule.odds[1]
            assert c.probability >= rule.min_probability
        if rule.legs:
            assert len(items) == rule.legs
            assert rule.total[0] <= math.prod(c.odds for c in items) <= rule.total[1]
        else:
            assert len(items) <= rule.count


def test_documents_publies(published):
    _, store, _ = published
    docs = store.query_picks(DATE)
    assert set(docs) == {f"{DATE}_{r}" for r in RULES}
    vip = docs[f"{DATE}_score"]
    assert vip["tier"] == "elite"
    assert vip["publicAfter"] == datetime(2026, 10, 15, tzinfo=timezone.utc)
    free = docs[f"{DATE}_selection"]
    assert free["tier"] == "free" and free["publicAfter"] == EVE
    tip = free["tips"][0]
    assert set(tip) >= {"fixtureId", "home", "away", "kickoff", "market", "label", "odds", "confidence", "status"}
    assert tip["kickoff"].endswith("Z") and tip["status"] == "soon"
    assert store.get("config/engine")["active"] is True
    groups = store.get("config/teams")["groups"]
    assert {g["country"] for g in groups} == {"France", "Côte d'Ivoire"}
    assert "ASEC Mimosas" in next(g for g in groups if g["country"] == "Côte d'Ivoire")["teams"]


def test_resultats_et_statistiques(published):
    api, store, _ = published
    notifier = Notifier()
    changed = jobs.update_results(api, store, NIGHT, notifier)
    assert changed > 0
    docs = store.query_picks(DATE)
    for doc in docs.values():
        assert all(t["status"] in ("won", "lost") for t in doc["tips"])
        assert doc["status"] in ("won", "lost")
    summary = store.get("stats/summary")["days"][DATE]
    assert summary["selection"]["count"] == len(docs[f"{DATE}_selection"]["tips"])
    assert summary["c10"]["count"] == 1  # un combiné compte pour un prono
    # Notifications : uniquement Sélection du jour et Combiné du jour.
    assert notifier.sent and all(m["title"].startswith(("Sélection du jour", "Combiné du jour")) for m in notifier.sent)
    # Un second passage ne change plus rien et n'appelle plus l'API.
    calls = api.calls
    assert jobs.update_results(api, store, NIGHT, Notifier()) == 0
    assert api.calls == calls


def test_les_matchs_pas_encore_commences_ne_sont_pas_interroges(published):
    api, store, _ = published
    calls = api.calls
    assert jobs.update_results(api, store, datetime(2026, 10, 14, 8, 0, tzinfo=timezone.utc)) == 0
    assert api.calls == calls


# --- Mise à jour d'un prono ----------------------------------------------------

TIP = {"fixtureId": 1, "market": "o15", "odds": 1.3, "status": "soon"}


def _fixture(short, elapsed=None, goals=(None, None), full=(None, None), half=(None, None)):
    return {
        "fixture": {"status": {"short": short, "elapsed": elapsed}},
        "goals": {"home": goals[0], "away": goals[1]},
        "score": {"fulltime": {"home": full[0], "away": full[1]}, "halftime": {"home": half[0], "away": half[1]}},
    }


def test_match_en_cours():
    t = tip_update(TIP, _fixture("2H", 63, goals=(1, 0), half=(1, 0)))
    assert (t["status"], t["minute"], t["score"]) == ("live", "63'", {"home": 1, "away": 0})
    assert tip_update(TIP, _fixture("HT", 45, goals=(0, 0)))["minute"] == "MT"


def test_match_termine_apres_prolongation_compte_le_score_a_90_minutes():
    t = tip_update(TIP, _fixture("AET", 120, goals=(2, 1), full=(1, 0)))
    assert t["status"] == "lost" and t["score"] == {"home": 1, "away": 0}
    assert "minute" not in t


def test_match_reporte_ou_annule():
    assert tip_update(TIP, _fixture("PST"))["status"] == "void"
    assert tip_update(TIP, _fixture("NS"))["status"] == "soon"


def test_etat_d_un_combine_et_statistiques():
    legs = [
        {"status": "won", "odds": 1.5},
        {"status": "void", "odds": 1.8},
        {"status": "won", "odds": 2.0},
    ]
    combo = {"rubric": "c5", "combo": True, "tips": legs}
    assert doc_status(combo) == "won"
    assert doc_status({**combo, "tips": legs[:2] + [{"status": "live", "odds": 2}]}) == "live"
    assert doc_status({**combo, "tips": [{"status": "lost", "odds": 2}, {"status": "soon", "odds": 2}]}) == "lost"
    # Match annulé dans un combiné : compté à la cote 1.
    assert day_stats({"a": combo}) == {"c5": {"count": 1, "won": 1, "oddsSum": 3.0, "profit": 2.0}}
    singles = {"rubric": "selection", "combo": False, "tips": [{"status": "won", "odds": 1.4}, {"status": "void", "odds": 1.6}]}
    assert day_stats({"b": singles}) == {"selection": {"count": 1, "won": 1, "oddsSum": 1.4, "profit": 0.4}}


# --- Ligne de commande -----------------------------------------------------------


def test_sans_cles_le_moteur_ne_fait_rien(monkeypatch, capsys):
    monkeypatch.delenv("API_FOOTBALL_KEY", raising=False)
    monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT", raising=False)
    assert cli.main(["publier"]) == 0
    assert "secrets manquants" in capsys.readouterr().out


def test_date_par_defaut():
    assert cli._default_date(datetime(2026, 10, 13, 23, 35, tzinfo=timezone.utc)) == "2026-10-14"
    assert cli._default_date(datetime(2026, 10, 14, 9, 0, tzinfo=timezone.utc)) == "2026-10-14"


def test_les_championnats_sont_gardes_une_semaine(published):
    api, store, _ = published
    calls = api.calls
    jobs.resolve_leagues(api, store, EVE + timedelta(days=3))
    assert api.calls == calls
    jobs.resolve_leagues(api, store, EVE + timedelta(days=8))
    assert api.calls > calls
