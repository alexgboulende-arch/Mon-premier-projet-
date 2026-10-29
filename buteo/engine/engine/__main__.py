"""Ligne de commande du moteur.

    python -m engine publier   [--date AAAA-MM-JJ]   pronos de la journée (par défaut : demain après 20:00 GMT)
    python -m engine resultats                       met à jour les matchs en cours et terminés
    python -m engine essai     [--json fichier]      essai hors ligne avec des données simulées
    python -m engine diagnostic                      ce que permet la clé API-Football (forfait, cotes…)
    python -m engine sources                         format des réponses de football-data.org, Highlightly et The Odds API

`publier` et `resultats` lisent FIREBASE_SERVICE_ACCOUNT et les clés des données :
FOOTBALL_DATA_KEY et ODDS_API_KEY (plus HIGHLIGHTLY_API_KEY, facultative) pour les
sources gratuites (voir sources_libres.py), sinon API_FOOTBALL_KEY. Sans ces
variables, ils s'arrêtent sans erreur. Avec l'offre gratuite d'API-Football, le
moteur passe seul en mode économique (voir jobs.py).
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
from .store import BadServiceAccount, FirestoreStore, MemoryStore


def _default_date(now: datetime) -> str:
    return (now + timedelta(days=1) if now.hour >= 20 else now).date().isoformat()


def _free_sources() -> bool:
    """Les sources gratuites (football-data.org et The Odds API) passent avant API-Football."""
    return bool(os.environ.get("FOOTBALL_DATA_KEY") and os.environ.get("ODDS_API_KEY"))


def _keys_present() -> bool:
    data_key = "FOOTBALL_DATA_KEY" if _free_sources() else "API_FOOTBALL_KEY"
    missing = [k for k in (data_key, "FIREBASE_SERVICE_ACCOUNT") if not os.environ.get(k)]
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
    sub.add_parser("diagnostic", help="ce que permet la clé API-Football")
    sub.add_parser("sources", help="format des réponses de football-data.org, Highlightly et The Odds API")
    args = parser.parse_args(argv)
    now = datetime.now(timezone.utc)

    if args.command == "sources":
        from .sources import run as run_sources

        run_sources(now)
        return 0

    if args.command == "diagnostic":
        if not os.environ.get("API_FOOTBALL_KEY"):
            print("::notice::Secret API_FOOTBALL_KEY manquant : diagnostic impossible.")
            return 0
        from .diagnostic import run

        run(os.environ["API_FOOTBALL_KEY"], now)
        return 0

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
    from .api_football import ApiError, ApiFootball

    try:
        if _free_sources():
            from .sources_libres import SourcesLibres

            store = FirestoreStore()
            client = SourcesLibres(
                os.environ["FOOTBALL_DATA_KEY"].strip(),
                os.environ["ODDS_API_KEY"].strip(),
                (os.environ.get("HIGHLIGHTLY_API_KEY") or "").strip() or None,
                store=store,
            )
        else:
            client = ApiFootball(os.environ["API_FOOTBALL_KEY"])
            if args.command == "resultats" and not jobs.results_due(client.free, now):
                print("Offre gratuite : résultats lus toutes les 20 minutes, rien à faire maintenant.")
                return 0
            store = FirestoreStore()
        if args.command == "publier":
            jobs.publish(client, store, args.date or _default_date(now), now)
        else:
            changed = jobs.update_results(client, store, now, Notifier(firebase_sender))
            print(f"{changed} pronos mis à jour ({client.calls} requêtes API)")
    except ApiError as e:
        if not e.restricted:
            raise
        # Quota du jour atteint ou date hors de l'offre : on réessaiera au prochain passage.
        print(f"::warning::La source des données a refusé la demande : {e}")
    except BadServiceAccount as e:
        print(f"::error::{e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
