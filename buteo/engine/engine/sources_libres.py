"""Sources gratuites qui remplacent API-Football.

- football-data.org (FOOTBALL_DATA_KEY) : matchs, scores et historique de huit
  championnats (10 requêtes par minute, sans limite par jour) ;
- Highlightly (HIGHLIGHTLY_API_KEY) : matchs et scores des championnats que
  football-data.org ne couvre pas (100 requêtes par jour) ;
- The Odds API (ODDS_API_KEY) : cotes 1X2 et plus/moins de buts des
  bookmakers (500 requêtes par mois, une par championnat et par jour).

`SourcesLibres` a la même interface que `ApiFootball` et rend les données au
format d'API-Football : le reste du moteur ne change pas. Les cotes « double
chance » sont calculées pour chaque bookmaker à partir de ses cotes 1X2.
"""

from __future__ import annotations

import difflib
import logging
import re
import time
import unicodedata
from dataclasses import dataclass
from datetime import date as Date
from datetime import datetime, timedelta, timezone

import requests

from .api_football import ApiError

log = logging.getLogger("buteo")

FOOTBALL_DATA = "https://api.football-data.org/v4"
HIGHLIGHTLY = "https://soccer.highlightly.net"
ODDS_API = "https://api.the-odds-api.com/v4"

FD_INTERVAL = 6.5  # 10 requêtes par minute au plus
HL_RESERVE = 5  # requêtes Highlightly gardées en fin de journée
ODDS_RESERVE = 10  # crédits The Odds API gardés en fin de mois
HL_EVERY_MINUTES = 20  # résultats Highlightly lus toutes les 20 minutes (quota du jour)
# Les identifiants de matchs de Highlightly (plus d'un milliard) ne croisent pas
# ceux de football-data.org (quelques centaines de milliers).
HL_MIN_ID = 100_000_000
KICKOFF_TOLERANCE = timedelta(minutes=90)


@dataclass(frozen=True)
class Source:
    provider: str  # « fd » (football-data.org) ou « hl » (Highlightly)
    league_id: int  # identifiant du championnat chez ce fournisseur
    code: str | None  # code football-data.org (« FL1 »)
    odds_key: str  # championnat chez The Odds API


# Championnats suivis (mêmes clés que api_football.LEAGUES). Ceux qui manquent
# (championnats africains, Ligue des champions CAF) n'ont pas de cotes gratuites.
SOURCES = {
    ("France", "Ligue 1"): Source("fd", 2015, "FL1", "soccer_france_ligue_one"),
    ("France", "Ligue 2"): Source("hl", 53546, None, "soccer_france_ligue_two"),
    ("England", "Premier League"): Source("fd", 2021, "PL", "soccer_epl"),
    ("Spain", "La Liga"): Source("fd", 2014, "PD", "soccer_spain_la_liga"),
    ("Italy", "Serie A"): Source("fd", 2019, "SA", "soccer_italy_serie_a"),
    ("Germany", "Bundesliga"): Source("fd", 2002, "BL1", "soccer_germany_bundesliga"),
    ("Portugal", "Primeira Liga"): Source("fd", 2017, "PPL", "soccer_portugal_primeira_liga"),
    ("Belgium", "Jupiler Pro League"): Source("hl", 123328, None, "soccer_belgium_first_div"),
    ("Netherlands", "Eredivisie"): Source("fd", 2003, "DED", "soccer_netherlands_eredivisie"),
    ("World", "UEFA Champions League"): Source("fd", 2001, "CL", "soccer_uefa_champs_league"),
    ("World", "UEFA Europa League"): Source("hl", 3337, None, "soccer_uefa_europa_league"),
}
BY_LEAGUE = {s.league_id: s for s in SOURCES.values()}

_FD_STATUS = {
    "SCHEDULED": "NS",
    "TIMED": "NS",
    "IN_PLAY": "LIVE",
    "PAUSED": "HT",
    "POSTPONED": "PST",
    "SUSPENDED": "SUSP",
    "CANCELLED": "CANC",
    "AWARDED": "AWD",
}
_FD_FINISHED = {"REGULAR": "FT", "EXTRA_TIME": "AET", "PENALTY_SHOOTOUT": "PEN"}


def season_of(day: Date) -> int:
    """Saison en cours (année de début) des championnats européens, d'août à mai."""
    return day.year if day.month >= 7 else day.year - 1


def _iso(text: str) -> str:
    return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")


def _fixture(fid, league_id, league_name, season, kickoff, status, elapsed, home, away, goals, full, half) -> dict:
    """Un match au format d'API-Football (réponse de /fixtures)."""
    return {
        "fixture": {"id": fid, "date": kickoff, "status": {"short": status, "elapsed": elapsed}},
        "league": {"id": league_id, "name": league_name, "season": season},
        "teams": {"home": {"name": home}, "away": {"name": away}},
        "goals": goals,
        "score": {"fulltime": full, "halftime": half},
    }


def fd_fixture(m: dict) -> dict:
    """Match de football-data.org au format d'API-Football."""
    score = m.get("score") or {}
    status = m.get("status", "")
    if status == "FINISHED":
        short = _FD_FINISHED.get(score.get("duration"), "FT")
    else:
        short = _FD_STATUS.get(status, "NS")
    current = score.get("fullTime") or {"home": None, "away": None}
    # Après prolongation, le score à 90 minutes est dans regularTime.
    full = score.get("regularTime") if short in ("AET", "PEN") and score.get("regularTime") else current
    comp, season = m.get("competition") or {}, m.get("season") or {}
    start = season.get("startDate")
    return _fixture(
        m["id"],
        comp.get("id"),
        comp.get("name"),
        int(start[:4]) if start else None,
        _iso(m["utcDate"]),
        short,
        m.get("minute"),
        _team_name(m.get("homeTeam") or {}),
        _team_name(m.get("awayTeam") or {}),
        {"home": current.get("home"), "away": current.get("away")},
        {"home": full.get("home"), "away": full.get("away")} if short in ("FT", "AET", "PEN") else {"home": None, "away": None},
        score.get("halfTime") or {"home": None, "away": None},
    )


def _team_name(team: dict) -> str:
    return team.get("shortName") or team.get("name") or "?"


def _hl_status(description: str | None) -> str:
    d = (description or "").lower()
    if not d or "not started" in d:
        return "NS"
    if "announced" in d or "defined" in d:
        return "TBD"
    if "postpon" in d:
        return "PST"
    if "cancel" in d:
        return "CANC"
    if "abandon" in d:
        return "ABD"
    if "suspend" in d or "interrupt" in d:
        return "SUSP"
    if "award" in d:
        return "AWD"
    if "finished" in d:
        return "PEN" if "penalt" in d else ("AET" if "extra" in d else "FT")
    if "half time" in d or "halftime" in d or "half-time" in d:
        return "HT"
    return "LIVE"


def _hl_score(text: str | None) -> dict:
    m = re.match(r"\s*(\d+)\s*-\s*(\d+)", text or "")
    return {"home": int(m.group(1)), "away": int(m.group(2))} if m else {"home": None, "away": None}


def hl_fixture(m: dict) -> dict:
    """Match de Highlightly au format d'API-Football.

    Highlightly ne donne que le score courant : après une prolongation, il
    inclut les buts des prolongations (rare dans les championnats suivis).
    """
    state = m.get("state") or {}
    short = _hl_status(state.get("description"))
    goals = _hl_score((state.get("score") or {}).get("current"))
    league = m.get("league") or {}
    return _fixture(
        m["id"],
        league.get("id"),
        league.get("name"),
        league.get("season"),
        _iso(m["date"]),
        short,
        state.get("clock"),
        (m.get("homeTeam") or {}).get("name", "?"),
        (m.get("awayTeam") or {}).get("name", "?"),
        goals,
        goals if short in ("FT", "AET", "PEN") else {"home": None, "away": None},
        {"home": None, "away": None},
    )


# --- Rapprochement des matchs et des cotes ---------------------------------------

_NOISE = {
    "fc", "afc", "cf", "sc", "ac", "as", "ssc", "sv", "vfb", "vfl", "tsg", "fsv", "rcd", "ud", "cd", "sd",
    "club", "de", "la", "le", "les", "du", "der", "of", "the", "calcio", "futbol", "football", "1899",
    "1900", "1901", "1907", "1909", "1913", "29", "04", "05", "93", "hsc", "sco",
}


def _tokens(name: str) -> list[str]:
    text = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()
    words = re.findall(r"[a-z0-9]+", text)
    kept = [w for w in words if w not in _NOISE]
    return kept or words


def name_similarity(a: str, b: str) -> float:
    """Ressemblance de deux noms d'équipe, entre 0 et 1."""
    ta, tb = _tokens(a), _tokens(b)
    if not ta or not tb:
        return 0.0
    sa, sb = set(ta), set(tb)
    if sa <= sb or sb <= sa:
        return 1.0
    # Sigles : « PSG » pour « Paris Saint Germain ».
    if len(ta) == 1 and ta[0] == "".join(w[0] for w in tb):
        return 1.0
    if len(tb) == 1 and tb[0] == "".join(w[0] for w in ta):
        return 1.0
    jaccard = len(sa & sb) / len(sa | sb)
    ratio = difflib.SequenceMatcher(None, " ".join(ta), " ".join(tb)).ratio()
    return max(jaccard, ratio)


def match_event(fixture: dict, names: tuple[list[str], list[str]], events: list[dict]) -> dict | None:
    """Événement de The Odds API correspondant au match (même heure, mêmes équipes)."""
    kickoff = datetime.fromisoformat(fixture["fixture"]["date"])
    best, best_score = None, 0.0
    for e in events:
        when = datetime.fromisoformat(e["commence_time"].replace("Z", "+00:00"))
        if abs(when - kickoff) > KICKOFF_TOLERANCE:
            continue
        home = max(name_similarity(n, e["home_team"]) for n in names[0])
        away = max(name_similarity(n, e["away_team"]) for n in names[1])
        if min(home, away) < 0.5:
            continue
        if home + away > best_score:
            best, best_score = e, home + away
    return best


def bookmakers_from_event(event: dict) -> list[dict]:
    """Cotes d'un événement de The Odds API au format d'API-Football (/odds)."""
    out = []
    for bk in event.get("bookmakers", []):
        bets = []
        for market in bk.get("markets", []):
            outcomes = market.get("outcomes", [])
            if market.get("key") == "h2h":
                side = {event["home_team"]: "Home", event["away_team"]: "Away", "Draw": "Draw"}
                odds = {side[o["name"]]: o["price"] for o in outcomes if o.get("name") in side}
                bets.append({"name": "Match Winner", "values": [{"value": k, "odd": str(v)} for k, v in odds.items()]})
                if len(odds) == 3:
                    dc = {
                        "Home/Draw": 1 / (1 / odds["Home"] + 1 / odds["Draw"]),
                        "Draw/Away": 1 / (1 / odds["Draw"] + 1 / odds["Away"]),
                        "Home/Away": 1 / (1 / odds["Home"] + 1 / odds["Away"]),
                    }
                    bets.append({"name": "Double Chance", "values": [{"value": k, "odd": f"{v:.2f}"} for k, v in dc.items()]})
            elif market.get("key") == "totals":
                values = [
                    {"value": f"{o['name']} {o['point']}", "odd": str(o["price"])}
                    for o in outcomes
                    if o.get("name") in ("Over", "Under") and o.get("point") in (1.5, 2.5, 3.5)
                ]
                if values:
                    bets.append({"name": "Goals Over/Under", "values": values})
        if bets:
            out.append({"name": bk.get("title", bk.get("key")), "bets": bets})
    return out


# --- Client -------------------------------------------------------------------------


class SourcesLibres:
    """Même interface que `ApiFootball`, avec les trois sources gratuites."""

    source = "sources-libres"
    free = False  # historique de la saison et recherche par identifiants disponibles

    def __init__(self, fd_key: str, odds_key: str, hl_key: str | None = None, store=None, session=None, now=None):
        if not fd_key or not odds_key:
            raise ApiError("Clés FOOTBALL_DATA_KEY et ODDS_API_KEY nécessaires.")
        self._session = session or requests.Session()
        self._fd_key, self._odds_key, self._hl_key = fd_key, odds_key, hl_key
        self._store = store
        self._now = now or (lambda: datetime.now(timezone.utc))
        self.calls = 0
        self._fd_last = 0.0
        self._hl_left: int | None = None
        self._odds_left: int | None = None
        self._known: dict[int, tuple[dict, tuple[list[str], list[str]]]] = {}
        self._events: dict[str, list[dict]] = {}

    # Requêtes ---------------------------------------------------------------

    def _get(self, url: str, params: dict, headers: dict) -> requests.Response:
        for attempt in range(3):
            r = self._session.get(url, params=params, headers=headers, timeout=30)
            self.calls += 1
            if r.status_code == 429 and attempt < 2:
                time.sleep(61)
                continue
            return r
        return r

    def _fd(self, path: str, **params) -> dict:
        wait = self._fd_last + FD_INTERVAL - time.monotonic()
        if wait > 0 and self._fd_last:
            time.sleep(wait)
        r = self._get(f"{FOOTBALL_DATA}{path}", params, {"X-Auth-Token": self._fd_key})
        self._fd_last = time.monotonic()
        if r.status_code != 200:
            raise ApiError(f"football-data.org {path} : HTTP {r.status_code} {_message(r)}")
        return r.json()

    def _hl(self, path: str, **params) -> dict | None:
        """Réponse de Highlightly, ou None si le quota du jour est presque épuisé."""
        if not self._hl_key:
            return None
        if self._hl_left is not None and self._hl_left <= HL_RESERVE:
            return None
        r = self._get(f"{HIGHLIGHTLY}{path}", params, {"x-rapidapi-key": self._hl_key})
        left = r.headers.get("x-ratelimit-requests-remaining")
        if left is not None and str(left).isdigit():
            self._hl_left = int(left)
        if r.status_code == 429:
            log.warning("Highlightly : quota du jour atteint")
            self._hl_left = 0
            return None
        if r.status_code != 200:
            raise ApiError(f"Highlightly {path} : HTTP {r.status_code} {_message(r)}")
        return r.json()

    # Interface d'ApiFootball ---------------------------------------------------

    def current_leagues(self, country: str) -> list[dict]:
        season = season_of(self._now().date())
        return [
            {"league": {"id": src.league_id, "name": name}, "seasons": [{"year": season, "current": True}]}
            for (c, name), src in SOURCES.items()
            if c == country
        ]

    def fixtures_on(self, date: str) -> list[dict]:
        """Matchs d'une journée (UTC) dans les championnats suivis."""
        nxt = (Date.fromisoformat(date) + timedelta(days=1)).isoformat()
        out = []
        fd_ids = {s.league_id for s in SOURCES.values() if s.provider == "fd"}
        for m in self._fd("/matches", dateFrom=date, dateTo=nxt).get("matches", []):
            if (m.get("competition") or {}).get("id") in fd_ids and m["utcDate"][:10] == date:
                out.append(self._remember(fd_fixture(m), m))
        playing = []
        for src in SOURCES.values():
            if src.provider != "hl":
                continue
            data = self._hl("/matches", leagueId=src.league_id, date=date, timezone="UTC")
            found = [self._remember(hl_fixture(m), m) for m in (data or {}).get("data", [])]
            out += [f for f in found if f["fixture"]["date"][:10] == date]
            if found:
                playing.append(src.league_id)
        self._save_hl_day(date, playing)
        return out

    def finished(self, league_id: int, season: int) -> list[dict]:
        """Matchs terminés d'une saison. Highlightly : aucun (quota), le modèle suit alors les cotes."""
        src = BY_LEAGUE.get(league_id)
        if src is None or src.provider != "fd":
            return []
        data = self._fd(f"/competitions/{src.code}/matches", season=season, status="FINISHED")
        return [fd_fixture(m) for m in data.get("matches", [])]

    def fixtures_by_ids(self, ids: list[int], date: str | None = None) -> list[dict]:
        """État des matchs demandés. Highlightly : relu toutes les 20 minutes, par championnat du jour."""
        out: list[dict] = []
        fd_ids = [i for i in ids if i < HL_MIN_ID]
        for i in range(0, len(fd_ids), 50):
            chunk = fd_ids[i : i + 50]
            out += [fd_fixture(m) for m in self._fd("/matches", ids=",".join(map(str, chunk))).get("matches", [])]
        hl_ids = {i for i in ids if i >= HL_MIN_ID}
        if hl_ids and date and self._now().minute % HL_EVERY_MINUTES < 10:
            for league_id in self._hl_day(date):
                data = self._hl("/matches", leagueId=league_id, date=date, timezone="UTC")
                out += [hl_fixture(m) for m in (data or {}).get("data", []) if m.get("id") in hl_ids]
        return out

    def odds(self, fixture_id: int) -> list[dict]:
        """Cotes d'un match vu par `fixtures_on` (vide si The Odds API ne le propose pas)."""
        known = self._known.get(fixture_id)
        if known is None:
            return []
        fixture, names = known
        src = BY_LEAGUE.get(fixture["league"]["id"])
        if src is None:
            return []
        event = match_event(fixture, names, self._odds_events(src.odds_key))
        return bookmakers_from_event(event) if event else []

    # Interne -----------------------------------------------------------------

    def _remember(self, fixture: dict, raw: dict) -> dict:
        """Garde les noms d'équipe (complets et courts) pour retrouver les cotes du match."""
        if "homeTeam" in raw:
            home = [n for n in (raw["homeTeam"].get("name"), raw["homeTeam"].get("shortName")) if n]
            away = [n for n in (raw["awayTeam"].get("name"), raw["awayTeam"].get("shortName")) if n]
        else:
            home, away = [fixture["teams"]["home"]["name"]], [fixture["teams"]["away"]["name"]]
        self._known[fixture["fixture"]["id"]] = (fixture, (home or ["?"], away or ["?"]))
        return fixture

    def _odds_events(self, sport: str) -> list[dict]:
        """Cotes de tout un championnat, une requête (2 crédits) par championnat et par exécution."""
        if sport in self._events:
            return self._events[sport]
        if self._odds_left is not None and self._odds_left <= ODDS_RESERVE:
            log.warning("The Odds API : crédits du mois presque épuisés, cotes de %s ignorées", sport)
            self._events[sport] = []
            return []
        r = self._get(
            f"{ODDS_API}/sports/{sport}/odds",
            {"apiKey": self._odds_key, "regions": "eu", "markets": "h2h,totals", "oddsFormat": "decimal"},
            {},
        )
        left = r.headers.get("x-requests-remaining")
        if left is not None:
            try:
                self._odds_left = int(float(left))
            except ValueError:
                pass
        if r.status_code in (401, 422, 429):
            log.warning("The Odds API a refusé %s : HTTP %s %s", sport, r.status_code, _message(r))
            self._events[sport] = []
            return []
        if r.status_code != 200:
            raise ApiError(f"The Odds API {sport} : HTTP {r.status_code} {_message(r)}")
        self._events[sport] = r.json()
        return self._events[sport]

    def _save_hl_day(self, date: str, leagues: list[int]) -> None:
        """Championnats Highlightly qui jouent ce jour-là, pour ne relire qu'eux pendant les matchs."""
        if self._store is None:
            return
        doc = self._store.get("config/sources") or {}
        days = {d: v for d, v in (doc.get("highlightlyDays") or {}).items() if d >= (Date.fromisoformat(date) - timedelta(days=3)).isoformat()}
        days[date] = leagues
        self._store.set("config/sources", {**doc, "highlightlyDays": days})

    def _hl_day(self, date: str) -> list[int]:
        doc = (self._store.get("config/sources") if self._store is not None else None) or {}
        days = doc.get("highlightlyDays") or {}
        if date in days:
            return days[date]
        return [s.league_id for s in SOURCES.values() if s.provider == "hl"]


def _message(r: requests.Response) -> str:
    try:
        data = r.json()
    except ValueError:
        return ""
    if isinstance(data, dict):
        return str(data.get("message") or data.get("error") or "")
    return ""
