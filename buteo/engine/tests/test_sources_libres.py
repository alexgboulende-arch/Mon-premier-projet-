"""Sources gratuites : football-data.org, Highlightly et The Odds API.

Les réponses simulées reprennent le format relevé par `python -m engine sources`.
"""

from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

import pytest

from engine import __main__ as cli
from engine import jobs, markets, sources_libres
from engine.picks import tip_update
from engine.sources_libres import (
    SourcesLibres,
    bookmakers_from_event,
    fd_fixture,
    hl_fixture,
    match_event,
    name_similarity,
)
from engine.store import MemoryStore

DATE = "2026-10-31"
EVE = datetime(2026, 10, 30, 23, 30, tzinfo=timezone.utc)


def fd_match(mid, home, away, when, status="TIMED", score=None, duration="REGULAR", minute=None, code="FL1", comp=2015):
    full = {"home": score[0], "away": score[1]} if score else {"home": None, "away": None}
    m = {
        "id": mid,
        "utcDate": when,
        "status": status,
        "competition": {"id": comp, "name": "Ligue 1", "code": code},
        "season": {"startDate": "2026-08-22"},
        "homeTeam": {"name": home[0], "shortName": home[1]},
        "awayTeam": {"name": away[0], "shortName": away[1]},
        "score": {"duration": duration, "fullTime": full, "halfTime": {"home": None, "away": None}},
    }
    if minute is not None:
        m["minute"] = minute
    return m


def hl_match(mid, home, away, when, description="Not started", score=None, clock=None, league=53546):
    return {
        "id": mid,
        "date": when,
        "state": {"clock": clock, "score": {"current": score, "penalties": None}, "description": description},
        "homeTeam": {"name": home},
        "awayTeam": {"name": away},
        "league": {"id": league, "name": "Ligue 2", "season": 2026},
    }


def odds_event(home, away, when, h, d, a, over25=None):
    markets_ = [{"key": "h2h", "outcomes": [{"name": home, "price": h}, {"name": away, "price": a}, {"name": "Draw", "price": d}]}]
    if over25:
        markets_.append(
            {"key": "totals", "outcomes": [{"name": "Over", "price": over25[0], "point": 2.5}, {"name": "Under", "price": over25[1], "point": 2.5}]}
        )
    return {
        "home_team": home,
        "away_team": away,
        "commence_time": when,
        "bookmakers": [{"key": "pinnacle", "title": "Pinnacle", "markets": markets_}],
    }


# --- Conversion au format d'API-Football ------------------------------------------


def test_match_football_data_termine_en_cours_reporte():
    done = fd_fixture(fd_match(1, ("Paris Saint-Germain FC", "PSG"), ("Olympique Lyonnais", "Olympique Lyon"), "2026-10-26T19:30:00Z", "FINISHED", (2, 0)))
    assert done["fixture"]["status"]["short"] == "FT"
    assert done["teams"]["home"]["name"] == "PSG"
    assert done["league"] == {"id": 2015, "name": "Ligue 1", "season": 2026}
    assert done["fixture"]["date"] == "2026-10-26T19:30:00+00:00"
    assert tip_update({"market": "1", "status": "live"}, done)["status"] == "won"

    live = fd_fixture(fd_match(2, ("A", "A"), ("B", "B"), "2026-10-26T19:30:00Z", "IN_PLAY", (1, 1), minute=63))
    assert tip_update({"market": "o25", "status": "soon"}, live) == {"market": "o25", "status": "live", "score": {"home": 1, "away": 1}, "minute": "63'"}
    paused = fd_fixture(fd_match(3, ("A", "A"), ("B", "B"), "2026-10-26T19:30:00Z", "PAUSED", (0, 0)))
    assert tip_update({"market": "1", "status": "live"}, paused)["minute"] == "MT"
    postponed = fd_fixture(fd_match(4, ("A", "A"), ("B", "B"), "2026-10-26T19:30:00Z", "POSTPONED"))
    assert tip_update({"market": "1", "status": "soon"}, postponed)["status"] == "void"


def test_match_football_data_apres_prolongation_garde_le_score_a_90_minutes():
    m = fd_match(5, ("A", "A"), ("B", "B"), "2026-10-26T19:30:00Z", "FINISHED", (2, 1), duration="EXTRA_TIME")
    m["score"]["regularTime"] = {"home": 1, "away": 1}
    f = fd_fixture(m)
    assert f["fixture"]["status"]["short"] == "AET"
    assert tip_update({"market": "1", "status": "live"}, f)["status"] == "lost"
    assert tip_update({"market": "u25", "status": "live"}, f)["status"] == "won"


@pytest.mark.parametrize(
    "description,score,expected",
    [
        ("Not started", None, "soon"),
        ("First half", "1 - 0", "live"),
        ("Half time", "1 - 0", "live"),
        ("Finished", "2 - 1", "won"),
        ("Postponed", None, "void"),
        ("Cancelled", None, "void"),
    ],
)
def test_match_highlightly(description, score, expected):
    f = hl_fixture(hl_match(1321185092, "Montpellier HSC", "RED Star FC 93", "2026-10-26T19:45:00.000Z", description, score, clock=30))
    assert f["fixture"]["date"] == "2026-10-26T19:45:00+00:00"
    assert tip_update({"market": "1", "status": "soon"}, f)["status"] == expected


# --- Cotes ----------------------------------------------------------------------------


@pytest.mark.parametrize(
    "ours,theirs",
    [
        ("Paris Saint-Germain FC", "Paris Saint Germain"),
        ("PSG", "Paris Saint Germain"),
        ("Olympique de Marseille", "Marseille"),
        ("Racing Club de Lens", "RC Lens"),
        ("Le Havre AC", "Le Havre"),
        ("RED Star FC 93", "Red Star"),
        ("Saint-Étienne", "Saint Etienne"),
        ("Bayern München", "Bayern Munich"),
    ],
)
def test_noms_d_equipe_rapproches(ours, theirs):
    assert name_similarity(ours, theirs) >= 0.5


def test_noms_d_equipe_differents():
    assert name_similarity("Olympique de Marseille", "Lille") < 0.5
    assert name_similarity("Stade Rennais", "Stade Brestois") < 1.0


def test_cotes_rattachees_au_bon_match_parmi_ceux_de_la_meme_heure():
    f = fd_fixture(fd_match(10, ("Racing Club de Lens", "RC Lens"), ("Olympique de Marseille", "Marseille"), "2026-11-08T19:45:00Z"))
    names = (["Racing Club de Lens", "RC Lens"], ["Olympique de Marseille", "Marseille"])
    events = [
        odds_event("Lille", "Nantes", "2026-11-08T19:45:00Z", 1.6, 4.0, 5.5),
        odds_event("RC Lens", "Marseille", "2026-11-08T19:45:00Z", 2.07, 3.91, 3.21),
        odds_event("RC Lens", "Marseille", "2026-11-22T19:45:00Z", 2.0, 3.8, 3.3),  # match retour
    ]
    assert match_event(f, names, events) is events[1]
    assert match_event(f, names, events[:1]) is None


def test_cotes_au_format_api_football_avec_double_chance_et_buts():
    event = odds_event("RC Lens", "Marseille", "2026-11-08T19:45:00Z", 2.0, 4.0, 4.0, over25=(1.8, 2.0))
    odds = markets.bookmaker_odds(bookmakers_from_event(event))
    assert odds["1"] == 2.0 and odds["X"] == 4.0 and odds["2"] == 4.0
    assert odds["1X"] == pytest.approx(1.33, abs=0.01)
    assert odds["X2"] == 2.0
    assert odds["12"] == pytest.approx(1.33, abs=0.01)
    assert odds["o25"] == 1.8 and odds["u25"] == 2.0


# --- Client complet --------------------------------------------------------------------


class _Reply:
    def __init__(self, status, data, headers=None):
        self.status_code, self._data, self.headers = status, data, headers or {}

    def json(self):
        return self._data


class _Web:
    """Les trois sources simulées : répond selon l'adresse et note chaque requête."""

    def __init__(self, fd_matches, fd_history, hl_matches, events, hl_left=90):
        self.fd_matches, self.fd_history, self.hl_matches, self.events = fd_matches, fd_history, hl_matches, events
        self.hl_left = hl_left
        self.hl_season = []
        self.log = []

    def get(self, url, params=None, headers=None, timeout=None):
        u = urlparse(url)
        params = params or {}
        self.log.append((u.netloc, u.path, dict(params)))
        if u.netloc == "api.football-data.org":
            assert headers["X-Auth-Token"] == "fd"
            if u.path.endswith("/matches") and "ids" in params:
                ids = {int(i) for i in params["ids"].split(",")}
                return _Reply(200, {"matches": [m for m in self.fd_matches if m["id"] in ids]})
            if u.path == "/v4/matches":
                return _Reply(200, {"matches": self.fd_matches})
            return _Reply(200, {"matches": self.fd_history})
        if u.netloc == "soccer.highlightly.net":
            assert headers["x-rapidapi-key"] == "hl"
            self.hl_left -= 1
            headers = {"x-ratelimit-requests-remaining": str(self.hl_left)}
            if "season" in params:
                season = [m for m in self.hl_season if m["league"]["id"] == params["leagueId"]]
                page = season[params["offset"] : params["offset"] + params["limit"]]
                return _Reply(200, {"data": page, "pagination": {"totalCount": len(season)}}, headers)
            data = [m for m in self.hl_matches if m["league"]["id"] == params["leagueId"]]
            return _Reply(200, {"data": data}, headers)
        if u.netloc == "api.the-odds-api.com":
            assert params["apiKey"] == "odds"
            sport = u.path.split("/")[3]
            return _Reply(200, self.events.get(sport, []), {"x-requests-remaining": "480"})
        raise AssertionError(url)

    def hosts(self):
        return [h for h, _, _ in self.log]


@pytest.fixture(autouse=True)
def _no_wait(monkeypatch):
    monkeypatch.setattr(sources_libres.time, "sleep", lambda s: None)


def _history():
    """Une saison de Ligue 1 : PSG fort, Nantes faible."""
    teams = [("Paris Saint-Germain FC", "PSG"), ("Olympique de Marseille", "Marseille"), ("Racing Club de Lens", "RC Lens"), ("FC Nantes", "Nantes")]
    out, mid = [], 1000
    day = datetime(2026, 8, 22, 19, 0, tzinfo=timezone.utc)
    goals = {"PSG": 3, "Marseille": 2, "RC Lens": 1, "Nantes": 0}
    for rnd in range(4):
        for h in teams:
            for a in teams:
                if h == a:
                    continue
                mid += 1
                day += timedelta(hours=7)
                out.append(fd_match(mid, h, a, day.strftime("%Y-%m-%dT%H:%M:%SZ"), "FINISHED", (goals[h[1]], max(0, goals[a[1]] - 1))))
    return out


def _web(hl_left=90):
    fd = [
        fd_match(559700, ("Paris Saint-Germain FC", "PSG"), ("FC Nantes", "Nantes"), "2026-10-31T16:00:00Z"),
        fd_match(559701, ("Racing Club de Lens", "RC Lens"), ("Olympique de Marseille", "Marseille"), "2026-10-31T19:05:00Z"),
        fd_match(559702, ("Paris Saint-Germain FC", "PSG"), ("Racing Club de Lens", "RC Lens"), "2026-11-01T19:45:00Z"),  # lendemain
    ]
    hl = [hl_match(1321200001, "Montpellier HSC", "RED Star FC 93", "2026-10-31T18:00:00.000Z")]
    events = {
        "soccer_france_ligue_one": [
            odds_event("Paris Saint Germain", "Nantes", "2026-10-31T16:00:00Z", 1.30, 6.0, 10.0, over25=(1.45, 2.75)),
            odds_event("RC Lens", "Marseille", "2026-10-31T19:05:00Z", 2.40, 3.40, 2.90, over25=(1.90, 1.90)),
        ],
        "soccer_france_ligue_two": [odds_event("Montpellier", "Red Star", "2026-10-31T18:00:00Z", 1.95, 3.30, 4.00, over25=(2.10, 1.70))],
    }
    return _Web(fd, _history(), hl, events, hl_left)


def _client(web, store, now=EVE):
    return SourcesLibres("fd", "odds", "hl", store=store, session=web, now=lambda: now)


def test_publication_avec_les_sources_gratuites():
    store, web = MemoryStore(), _web()
    client = _client(web, store)
    chosen = jobs.publish(client, store, DATE, EVE)

    tips = [t for doc in store.docs.values() if "tips" in doc for t in doc["tips"]]
    assert tips, "aucun prono publié"
    assert {t["fixtureId"] for t in tips} <= {559700, 559701, 1321200001}
    assert sum(len(v) for v in chosen.values()) == len([t for d in store.docs.values() if d.get("rubric") for t in d["tips"]])
    cfg = store.get("config/engine")
    assert cfg["leaguesSource"] == "sources-libres"
    assert {lg["name"] for lg in cfg["leagues"]} >= {"Ligue 1", "Ligue 2", "Premier League"}
    assert not any(lg["country"] == "Côte d'Ivoire" for lg in cfg["leagues"])
    # Une seule requête de cotes par championnat qui joue, aucune pour les autres.
    odds = [p for h, p, _ in web.log if h == "api.the-odds-api.com"]
    assert sorted(odds) == ["/v4/sports/soccer_france_ligue_one/odds", "/v4/sports/soccer_france_ligue_two/odds"]
    # Highlightly : les matchs du jour de chaque championnat qu'il couvre (Ligue 2, Pro League,
    # Ligue Europa), puis l'historique de la Ligue 2, qui joue (saison vide : la précédente aussi).
    calls = _hl_calls(web)
    assert [c["leagueId"] for c in calls if "date" in c] == [53546, 123328, 3337]
    assert [(c["leagueId"], c["season"]) for c in calls if "season" in c] == [(53546, 2026), (53546, 2025)]
    assert store.get("config/sources")["highlightlyDays"][DATE] == [53546]


def test_resultats_football_data_par_identifiants_highlightly_par_championnat_du_jour():
    store, web = MemoryStore(), _web()
    jobs.publish(_client(web, store), store, DATE, EVE)
    # Tous les matchs sont terminés le soir.
    for m in web.fd_matches:
        m["status"], m["score"]["fullTime"] = "FINISHED", {"home": 2, "away": 0}
    web.hl_matches[0]["state"] = {"clock": 90, "score": {"current": "1 - 1", "penalties": None}, "description": "Finished"}

    web.log.clear()
    night = datetime(2026, 10, 31, 22, 5, tzinfo=timezone.utc)  # minute 5 : Highlightly relu
    jobs.update_results(_client(web, store, night), store, night)
    fd_calls = [p for h, _, p in web.log if h == "api.football-data.org"]
    assert len(fd_calls) == 1 and "ids" in fd_calls[0]
    assert [p["leagueId"] for h, _, p in web.log if h == "soccer.highlightly.net"] == [53546]
    tips = [t for d in store.docs.values() if d.get("rubric") for t in d["tips"]]
    assert all(t["status"] in ("won", "lost") for t in tips)


def test_resultats_highlightly_toutes_les_20_minutes_seulement():
    store, web = MemoryStore(), _web()
    jobs.publish(_client(web, store), store, DATE, EVE)
    web.log.clear()
    later = datetime(2026, 10, 31, 22, 15, tzinfo=timezone.utc)
    SourcesLibres("fd", "odds", "hl", store=store, session=web, now=lambda: later).fixtures_by_ids([559700, 1321200001], DATE)
    assert "soccer.highlightly.net" not in web.hosts()


def test_quota_highlightly_presque_epuise():
    store, web = MemoryStore(), _web(hl_left=7)
    client = _client(web, store)
    client.fixtures_on(DATE)
    # 7 → 6 → 5 : la troisième requête n'est pas faite (5 gardées pour la soirée).
    assert web.hosts().count("soccer.highlightly.net") == 2


def test_changement_de_source_relit_les_championnats():
    store, web = MemoryStore(), _web()
    store.set("config/engine", {"leagues": [{"id": 61, "season": 2026, "country": "France", "name": "Ligue 1"}], "leaguesResolvedAt": EVE})
    leagues = jobs.resolve_leagues(_client(web, store), store, EVE + timedelta(hours=1))
    assert 2015 in {lg["id"] for lg in leagues} and 61 not in {lg["id"] for lg in leagues}


def test_la_ligne_de_commande_prend_les_sources_gratuites(monkeypatch):
    for k, v in {"FOOTBALL_DATA_KEY": "fd", "ODDS_API_KEY": "odds", "HIGHLIGHTLY_API_KEY": " hl\n", "FIREBASE_SERVICE_ACCOUNT": "{}"}.items():
        monkeypatch.setenv(k, v)
    monkeypatch.delenv("API_FOOTBALL_KEY", raising=False)
    seen = {}
    monkeypatch.setattr(cli, "FirestoreStore", MemoryStore)
    monkeypatch.setattr(jobs, "publish", lambda client, store, date, now: seen.update(client=client))
    assert cli.main(["publier", "--date", DATE]) == 0
    assert isinstance(seen["client"], SourcesLibres)
    assert seen["client"]._hl_key == "hl"


# --- Historique des championnats de Highlightly (Ligue 2…) ----------------------------


def _l2_season(finished=150, upcoming=156):
    """Saison de Ligue 2 dans le désordre, comme chez Highlightly : matchs joués et à venir."""
    teams = ["Montpellier HSC", "RED Star FC 93", "Saint-Étienne", "Rodez", "Dunkerque", "Metz"]
    out = []
    start = datetime(2026, 8, 1, 18, 0, tzinfo=timezone.utc)
    for i in range(finished + upcoming):
        h, a = teams[i % 6], teams[(i + 1 + i // 6) % 6]
        if h == a:
            a = teams[(i + 2) % 6]
        when = (start + timedelta(hours=10 * i)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        if i < finished:
            out.append(hl_match(1321000000 + i, h, a, when, "Finished", f"{2 if h == 'Metz' else 1} - 0", clock=90))
        else:
            out.append(hl_match(1321000000 + i, h, a, when))
    return list(reversed(out))


def _hl_calls(web):
    return [p for h, _, p in web.log if h == "soccer.highlightly.net"]


def test_historique_de_la_ligue_2_lu_page_par_page_et_garde():
    store, web = MemoryStore(), _web()
    web.hl_season = _l2_season()
    games = SourcesLibres("fd", "odds", "hl", store=store, session=web, now=lambda: EVE).finished(53546, 2026)
    assert len(games) == 150 and all(g["fixture"]["status"]["short"] == "FT" for g in games)
    # 306 matchs : 4 pages de 100.
    assert [p["offset"] for p in _hl_calls(web)] == [0, 100, 200, 300]
    doc = store.get("history/hl_53546_2026")
    assert doc["league"] == "Ligue 2" and len(doc["matches"]) == 150
    assert doc["matches"][0]["played"] < doc["matches"][-1]["played"]
    # Le modèle s'en sert : les forces des équipes sont connues.
    assert {r.home for r in jobs._results(games)} >= {"Metz", "Rodez"}

    web.log.clear()
    two_days = EVE + timedelta(days=2)
    SourcesLibres("fd", "odds", "hl", store=store, session=web, now=lambda: two_days).finished(53546, 2026)
    assert _hl_calls(web) == []
    four_days = EVE + timedelta(days=4)
    SourcesLibres("fd", "odds", "hl", store=store, session=web, now=lambda: four_days).finished(53546, 2026)
    assert len(_hl_calls(web)) == 4


def test_saison_passee_lue_une_seule_fois():
    store, web = MemoryStore(), _web()
    web.hl_season = [dict(m, league={**m["league"], "season": 2025}) for m in _l2_season(finished=50, upcoming=0)]
    later = EVE + timedelta(days=60)
    for now in (EVE, later):
        SourcesLibres("fd", "odds", "hl", store=store, session=web, now=lambda now=now: now).finished(53546, 2025)
    assert len(_hl_calls(web)) == 1


def test_resultats_du_soir_ajoutes_a_l_historique_sans_requete_de_plus():
    store, web = MemoryStore(), _web()
    web.hl_season = _l2_season()
    client = _client(web, store)
    client.finished(53546, 2026)
    jobs.publish(client, store, DATE, EVE)
    web.hl_matches[0]["state"] = {"clock": 90, "score": {"current": "3 - 1", "penalties": None}, "description": "Finished"}

    web.log.clear()
    night = datetime(2026, 10, 31, 22, 5, tzinfo=timezone.utc)
    SourcesLibres("fd", "odds", "hl", store=store, session=web, now=lambda: night).fixtures_by_ids([1321200001], DATE)
    assert len(_hl_calls(web)) == 1  # la lecture du soir, pas de relecture de la saison
    added = [m for m in store.get("history/hl_53546_2026")["matches"] if m["id"] == 1321200001]
    assert added == [{"id": 1321200001, "home": "Montpellier HSC", "away": "RED Star FC 93", "hg": 3, "ag": 1, "played": "2026-10-31T18:00:00Z"}]


def test_historique_garde_si_le_quota_du_jour_manque():
    store, web = MemoryStore(), _web(hl_left=6)
    old = {"id": 1, "home": "Metz", "away": "Rodez", "hg": 1, "ag": 0, "played": "2026-09-01T18:00:00Z"}
    store.set("history/hl_53546_2026", {"league": "Ligue 2", "season": 2026, "matches": [old], "fetchedAt": EVE - timedelta(days=5)})
    web.hl_season = _l2_season()
    games = _client(web, store).finished(53546, 2026)
    # 6 → 5 : la deuxième page n'est pas lue, l'ancien historique reste.
    assert len(games) == 1 and store.get("history/hl_53546_2026")["matches"] == [old]
