"""Lecture et écriture dans Firestore, et une version en mémoire pour les tests.

Documents écrits par le moteur (lus par l'app, voir firebase/firestore.rules) :

- `picks/{date}_{rubrique}` : les pronos d'une rubrique pour une journée ;
- `stats/summary` : résultats agrégés par jour et par rubrique (30 jours) ;
- `config/engine` : état du moteur (championnats, dernière publication) ;
- `history/{championnat}` : résultats gardés par le moteur (offre gratuite) ;
- concours : voir contest.py.
"""

from __future__ import annotations

import copy
import json
import os
from datetime import datetime
from typing import Protocol


class Store(Protocol):
    def get(self, path: str) -> dict | None: ...

    def set(self, path: str, data: dict) -> None: ...

    def query_picks(self, date: str) -> dict[str, dict]: ...

    def list(self, collection: str) -> dict[str, dict]: ...


class MemoryStore:
    """Firestore simulé, pour les tests et l'essai hors ligne."""

    def __init__(self):
        self.docs: dict[str, dict] = {}

    def get(self, path: str) -> dict | None:
        doc = self.docs.get(path)
        return copy.deepcopy(doc) if doc is not None else None

    def set(self, path: str, data: dict) -> None:
        self.docs[path] = copy.deepcopy(data)

    def query_picks(self, date: str) -> dict[str, dict]:
        return {
            path.split("/", 1)[1]: copy.deepcopy(doc)
            for path, doc in self.docs.items()
            if path.startswith("picks/") and doc.get("date") == date
        }

    def list(self, collection: str) -> dict[str, dict]:
        """Documents d'une collection (sans les sous-collections)."""
        prefix = collection.rstrip("/") + "/"
        return {
            path[len(prefix) :]: copy.deepcopy(doc)
            for path, doc in self.docs.items()
            if path.startswith(prefix) and "/" not in path[len(prefix) :]
        }


class FirestoreStore:
    """Accès administrateur (les règles de sécurité ne s'appliquent pas au moteur)."""

    def __init__(self, service_account_json: str | None = None):
        import firebase_admin
        from firebase_admin import credentials, firestore

        raw = service_account_json or os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
        if not raw:
            raise RuntimeError("Variable FIREBASE_SERVICE_ACCOUNT manquante.")
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(service_account(raw)))
        self._db = firestore.client()

    def get(self, path: str) -> dict | None:
        snap = self._db.document(path).get()
        return snap.to_dict() if snap.exists else None

    def set(self, path: str, data: dict) -> None:
        self._db.document(path).set(data)

    def query_picks(self, date: str) -> dict[str, dict]:
        return {snap.id: snap.to_dict() for snap in self._db.collection("picks").where("date", "==", date).stream()}

    def list(self, collection: str) -> dict[str, dict]:
        return {snap.id: snap.to_dict() for snap in self._db.collection(collection).stream()}


class BadServiceAccount(RuntimeError):
    pass


def service_account(raw: str) -> dict:
    """Clé du compte de service, avec un message clair si le secret contient autre chose."""
    hint = (
        "Le secret FIREBASE_SERVICE_ACCOUNT doit contenir la clé privée du compte de service "
        "(console Firebase → Paramètres du projet → Comptes de service → Générer une nouvelle clé privée), "
        'un texte qui commence par {"type": "service_account". '
    )
    try:
        data = json.loads(raw)
    except ValueError:
        raise BadServiceAccount(hint + "Le texte collé n'est pas un fichier JSON complet.") from None
    if not isinstance(data, dict) or data.get("type") != "service_account":
        found = " C'est le fichier google-services.json de l'app." if isinstance(data, dict) and "project_info" in data else ""
        raise BadServiceAccount(hint + "Le texte collé est un autre fichier." + found)
    return data


def iso(dt: datetime) -> str:
    """Date et heure UTC au format « 2026-10-14T19:00:00Z »."""
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
