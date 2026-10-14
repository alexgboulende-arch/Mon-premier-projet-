/**
 * Fonctions serveur de Buteo (Firebase Cloud Functions, région europe-west1).
 *
 *  - verifierAchatPlay : appelée par l'app après un achat Google Play ;
 *  - verifierAbonnements : toutes les 6 heures, renouvellements et échéances.
 */

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { googlePlayApi } from "./play";
import { PurchaseError, refreshSubscriptions, verifyPlayPurchase } from "./purchases";

setGlobalOptions({ region: "europe-west1", maxInstances: 10 });
initializeApp();

export const verifierAchatPlay = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Connecte-toi pour acheter.");
  try {
    return await verifyPlayPurchase(getFirestore(), googlePlayApi(), request.auth.uid, request.data, new Date());
  } catch (e) {
    if (e instanceof PurchaseError) throw new HttpsError(e.code, e.message);
    logger.error("Vérification d'achat", e);
    throw new HttpsError("internal", "La vérification de l'achat a échoué. Réessaie dans un instant.");
  }
});

export const verifierAbonnements = onSchedule({ schedule: "every 6 hours", timeZone: "UTC" }, async () => {
  const changed = await refreshSubscriptions(getFirestore(), googlePlayApi(), new Date());
  logger.info(`${changed} profil(s) mis à jour`);
});
