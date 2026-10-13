"""Ligne de commande du moteur.

    python -m engine publier   [--date AAAA-MM-JJ]   pronos de la journée (par défaut : demain après 20:00 GMT)
    python -m engine resultats                       met à jour les matchs en cours et terminés
    python -m engine essai     [--json fichier]      essai hors ligne avec des données simulées

`publier` et `resultats` lisent API_FOOTBALL_KEY et FIREBASE_SERVICE_ACCOUNT.
Sans ces variables, ils s'arrêtent sans erreur (le dépôt peut tourner sans
clés tant que le service n'est pas souscrit).
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timedelta, timezone

from . import jobs
from .notify import Notifier, firebase_sender
from .sample import SampleApi
from .store import FirestoreStore, MemoryStore


def _default_date(now: datetime) -> str:
    return (now + timedelta(days=1) if now.hour >= 20 else now).date().isoformat()


def _keys_present() -> bool:
    missing = [k for k in ("API_FOOTBALL_KEY", "FIREBASE_SERVICE_ACCOUNT") if not os.environ.get(k)]
    if missing:
        print(f"::notice::Moteur en attente : secrets manquants ({', '.join(missing)}). Rien n'a été fait.")
        return False
    return True


def _json_default(value):
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%dT%H:%M:%SZ")
    raise TypeError(type(value))


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(prog="engine", description="Moteur de pronostics Buteo")
    sub = parser.add_subparsers(dest="command", required=True)
    p_pub = sub.add_parser("publier", help="publie les pronos d'une journée")
    p_pub.add_argument("--date")
    sub.add_parser("resultats", help="met à jour les résultats")
    p_try = sub.add_parser("essai", help="essai hors ligne avec des données simulées")
    p_try.add_argument("--date", default="2026-10-14")
    p_try.add_argument("--json", help="écrit les documents produits dans ce fichier")
    args = parser.parse_args(argv)
    now = datetime.now(timezone.utc)

    if args.command == "essai":
        store = MemoryStore()
        client = SampleApi(args.date)
        publish_time = datetime.fromisoformat(args.date).replace(tzinfo=timezone.utc) - timedelta(minutes=25)
        chosen = jobs.publish(client, store, args.date, publish_time)
        for rubric, items in chosen.items():
            print(f"\n{rubric} ({len(items)})")
            for c in items:
                f = c.fixture
                print(f"  {f.kickoff:%H:%M} {f.home} – {f.away} : {c.market} @ {c.odds} · confiance {c.confidence} %")
        notifier = Notifier()
        end_of_day = datetime.fromisoformat(args.date).replace(tzinfo=timezone.utc) + timedelta(hours=23, minutes=59)
        changed = jobs.update_results(client, store, end_of_day, notifier)
        print(f"\nRésultats : {changed} pronos mis à jour, {len(notifier.sent)} notifications.")
        print(json.dumps(store.get("stats/summary")["days"], ensure_ascii=False, indent=1))
        if args.json:
            docs = {path: doc for path, doc in sorted(store.docs.items()) if path.startswith("picks/")}
            with open(args.json, "w", encoding="utf-8") as fh:
                json.dump(docs, fh, ensure_ascii=False, indent=2, default=_json_default)
        return 0

    if not _keys_present():
        return 0
    from .api_football import ApiFootball

    client = ApiFootball(os.environ["API_FOOTBALL_KEY"])
    store = FirestoreStore()
    if args.command == "publier":
        jobs.publish(client, store, args.date or _default_date(now), now)
    else:
        changed = jobs.update_results(client, store, now, Notifier(firebase_sender))
        print(f"{changed} pronos mis à jour ({client.calls} requêtes API)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
