"""Notifications envoyées aux abonnés (Firebase Cloud Messaging).

Les téléphones s'abonnent au sujet « results » depuis leur profil
(voir lib/services/notification_service.dart). On n'annonce que les
résultats de la Sélection du jour et du Combiné du jour, pour ne pas
envoyer trop de messages.
"""

from __future__ import annotations

import logging

log = logging.getLogger("buteo")

ANNOUNCED = {"selection": "Sélection du jour", "combine": "Combiné du jour"}


def _odds(v: float) -> str:
    return f"{v:.2f}".replace(".", ",")


class Notifier:
    """Prépare les messages ; `send` les envoie (à remplacer dans les tests)."""

    def __init__(self, send=None):
        self.sent: list[dict] = []
        self._send = send

    def on_change(self, doc: dict, before: dict[int, str], old_status: str) -> None:
        name = ANNOUNCED.get(doc["rubric"])
        if not name:
            return
        if doc.get("combo"):
            if doc["status"] in ("won", "lost") and old_status not in ("won", "lost"):
                self._push(
                    f"{name} : {'gagné' if doc['status'] == 'won' else 'perdu'}",
                    f"{len(doc['tips'])} matchs · cote totale {_odds(_product(doc))}",
                )
            return
        for t in doc["tips"]:
            if t["status"] in ("won", "lost") and before.get(t["fixtureId"]) not in ("won", "lost"):
                self._push(
                    f"{name} : {'gagné' if t['status'] == 'won' else 'perdu'}",
                    f"{t['home']} – {t['away']} · {t['label']} · cote {_odds(t['odds'])}",
                )

    def _push(self, title: str, body: str) -> None:
        message = {"topic": "results", "title": title, "body": body}
        self.sent.append(message)
        if self._send:
            try:
                self._send(message)
            except Exception as e:  # une notification ratée ne doit pas bloquer les résultats
                log.warning("Notification non envoyée : %s", e)


def _product(doc: dict) -> float:
    p = 1.0
    for t in doc["tips"]:
        if t["status"] != "void":
            p *= t["odds"]
    return p


def firebase_sender(message: dict) -> None:
    from firebase_admin import messaging

    messaging.send(
        messaging.Message(
            topic=message["topic"],
            notification=messaging.Notification(title=message["title"], body=message["body"]),
            android=messaging.AndroidConfig(
                notification=messaging.AndroidNotification(channel_id="alertes", icon="ic_notification")
            ),
        )
    )
