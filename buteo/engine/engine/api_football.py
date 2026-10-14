"""Client de l'API API-Football (v3), https://www.api-football.com.

La clé se crée sur dashboard.api-football.com et se passe dans la variable
d'environnement API_FOOTBALL_KEY.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

import requests

BASE_URL = "https://v3.football.api-sports.io"

# Codes d'état d'un match.
NOT_STARTED = {"TBD", "NS"}
LIVE = {"1H", "HT", "2H", "ET", "BT", "P", "SUSP", "INT", "LIVE"}
FINISHED = {"FT", "AET", "PEN"}
CANCELLED = {"PST", "CANC", "ABD", "AWD", "WO"}


class ApiError(RuntimeError):
    @property
    def restricted(self) -> bool:
        """Refus lié au forfait (offre gratuite) ou au quota du jour."""
        text = str(self).lower()
        return "free plans" in text or "request limit" in text or "reached the limit" in text


@dataclass(frozen=True)
class League:
    """Championnat suivi, tel qu'il s'affiche dans l'app."""

    api_country: str  # nom du pays pour l'API (« Ivory-Coast »)
    api_name: str  # nom du championnat dans l'API
    country: str  # nom affiché (« Côte d'Ivoire »)
    name: str  # nom affiché (« Ligue 1 »)


# Championnats couverts. Les identifiants sont retrouvés automatiquement
# par leur nom ; un championnat introuvable est simplement ignoré.
LEAGUES = [
    League("France", "Ligue 1", "France", "Ligue 1"),
    League("France", "Ligue 2", "France", "Ligue 2"),
    League("England", "Premier League", "Angleterre", "Premier League"),
    League("Spain", "La Liga", "Espagne", "LaLiga"),
    League("Italy", "Serie A", "Italie", "Serie A"),
    League("Germany", "Bundesliga", "Allemagne", "Bundesliga"),
    League("Portugal", "Primeira Liga", "Portugal", "Liga Portugal"),
    League("Belgium", "Jupiler Pro League", "Belgique", "Pro League"),
    League("Netherlands", "Eredivisie", "Pays-Bas", "Eredivisie"),
    League("World", "UEFA Champions League", "Europe", "Ligue des champions"),
    League("World", "UEFA Europa League", "Europe", "Ligue Europa"),
    League("World", "CAF Champions League", "Afrique", "Ligue des champions CAF"),
    League("Ivory-Coast", "Ligue 1", "Côte d'Ivoire", "Ligue 1"),
    League("Senegal", "Ligue 1", "Sénégal", "Ligue 1"),
    League("Cameroon", "Elite One", "Cameroun", "Elite One"),
    League("Morocco", "Botola Pro", "Maroc", "Botola Pro"),
    League("Tunisia", "Ligue 1", "Tunisie", "Ligue 1"),
    League("Algeria", "Ligue 1", "Algérie", "Ligue 1"),
]


class ApiFootball:
    def __init__(self, key: str, session: requests.Session | None = None):
        if not key:
            raise ApiError("Clé API_FOOTBALL_KEY manquante.")
        self._session = session or requests.Session()
        self._session.headers.update({"x-apisports-key": key})
        self.calls = 0
        self._plan: str | None = None

    def status(self) -> dict:
        """Forfait et requêtes du jour. Cette page ne compte pas dans le quota."""
        r = self._session.get(f"{BASE_URL}/status", timeout=30)
        r.raise_for_status()
        data = r.json()
        if data.get("errors"):
            raise ApiError(f"status : {data['errors']}")
        resp = data.get("response") or {}
        sub, req = resp.get("subscription", {}), resp.get("requests", {})
        return {"plan": sub.get("plan", ""), "current": req.get("current", 0), "limit_day": req.get("limit_day", 0)}

    @property
    def free(self) -> bool:
        """Offre gratuite : 100 requêtes par jour, matchs d'hier à demain seulement."""
        if self._plan is None:
            self._plan = self.status()["plan"]
        return "free" in self._plan.lower()

    def remaining(self) -> int:
        s = self.status()
        return max(0, s["limit_day"] - s["current"])

    def get(self, path: str, **params) -> list[dict]:
        """Toutes les pages d'une requête."""
        out: list[dict] = []
        page = 1
        while True:
            if page > 1:
                params["page"] = page
            for attempt in range(3):
                r = self._session.get(f"{BASE_URL}/{path}", params=params, timeout=30)
                self.calls += 1
                if r.status_code == 429 and attempt < 2:
                    time.sleep(6 * (attempt + 1))  # trop de requêtes par minute : on patiente
                    continue
                break
            r.raise_for_status()
            data = r.json()
            errors = data.get("errors")
            if errors:
                raise ApiError(f"{path} : {errors}")
            out.extend(data.get("response", []))
            paging = data.get("paging") or {}
            if paging.get("current", 1) >= paging.get("total", 1):
                return out
            page += 1

    def current_leagues(self, country: str) -> list[dict]:
        return self.get("leagues", country=country, current="true")

    def fixtures_on(self, date: str) -> list[dict]:
        """Tous les matchs d'une journée (toutes compétitions), heures en UTC."""
        return self.get("fixtures", date=date, timezone="UTC")

    def finished(self, league_id: int, season: int) -> list[dict]:
        return self.get("fixtures", league=league_id, season=season, status="FT-AET-PEN")

    def fixtures_by_ids(self, ids: list[int]) -> list[dict]:
        out: list[dict] = []
        for i in range(0, len(ids), 20):  # l'API accepte 20 identifiants par requête
            out.extend(self.get("fixtures", ids="-".join(map(str, ids[i : i + 20]))))
        return out

    def odds(self, fixture_id: int) -> list[dict]:
        """Bookmakers et cotes d'un match (vide si aucune cote publiée)."""
        response = self.get("odds", fixture=fixture_id)
        return response[0].get("bookmakers", []) if response else []
