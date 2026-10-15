"""Suppression de compte : effacer les données du concours qui s'y rattachent.

L'app et le site écrivent `deletionRequests/{uid}` avant d'effacer le compte
et ses données personnelles. Chaque nuit, le moteur retire ce joueur du
concours : profil, pronos, points du jour, classements, modération.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from .store import Store


def purge_deleted_accounts(store: Store, now: datetime) -> int:
    """Traite les demandes en attente ; renvoie le nombre de comptes nettoyés."""
    requests = store.list("deletionRequests")
    if not requests:
        return 0
    contests = store.list("contests")
    boards = store.list("leaderboards")
    recent = (now.date() - timedelta(days=2)).isoformat()
    moderation = store.get("moderation/all")
    for uid in requests:
        store.delete(f"contestPlayers/{uid}")
        for day, contest in contests.items():
            scores = store.get(f"contestScores/{day}")
            played = bool(scores) and uid in scores.get("players", {})
            if played or day >= recent:
                for m in contest.get("matches", []):
                    store.delete(f"contests/{day}/picks/{uid}_{m['fixtureId']}")
            if played:
                scores["players"].pop(uid)
                store.set(f"contestScores/{day}", scores)
        for board_id, board in boards.items():
            players = board.get("players", [])
            if any(p.get("uid") == uid for p in players):
                kept = [{**p, "rank": i + 1} for i, p in enumerate(p for p in players if p.get("uid") != uid)]
                board = {**board, "players": kept}
                boards[board_id] = board
                store.set(f"leaderboards/{board_id}", board)
        if moderation and uid in moderation.get("players", {}):
            moderation["players"].pop(uid)
            store.set("moderation/all", moderation)
        store.delete(f"deletionRequests/{uid}")
    return len(requests)

