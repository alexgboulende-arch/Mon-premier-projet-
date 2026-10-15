/**
 * Fonctions serveur de Buteo (Firebase Cloud Functions, région europe-west1).
 *
 *  - verifierAchatPlay : appelée par l'app après un achat Google Play ;
 *  - verifierAbonnements : toutes les 6 heures, renouvellements et échéances ;
 *  - moyensDePaiement, creerCommande, verifierCommande : paiements du site web
 *    (Mobile Money, crypto) ;
 *  - notificationPaiement : adresse appelée par les prestataires après un paiement ;
 *  - adminChiffres, adminDonnerAcces, adminModerer, adminMessage : espace
 *    d'administration du site, réservé aux adresses de BUTEO_ADMINS.
 */

import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { CallableRequest, HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { adminFigures, adminGrant, adminMessage as sendAdminMessage, adminModerate, isAdmin } from "./admin";
import { availableMethods, confirmOrder, createOrder, handleNotification } from "./orders";
import { googlePlayApi } from "./play";
import { providersFromEnv } from "./providers";
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

/** Erreurs prévues : message pour l'utilisateur ; les autres sont journalisées. */
function asHttpsError(e: unknown, what: string): HttpsError {
  if (e instanceof PurchaseError) return new HttpsError(e.code, e.message);
  logger.error(what, e);
  return new HttpsError("internal", "Une erreur est survenue. Réessaie dans un instant.");
}

export const moyensDePaiement = onCall(async () => availableMethods(providersFromEnv()));

export const creerCommande = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Connecte-toi pour acheter.");
  try {
    const user = { uid: request.auth.uid, email: (request.auth.token.email as string | undefined) ?? null };
    return await createOrder(getFirestore(), providersFromEnv(), user, request.data, new Date());
  } catch (e) {
    throw asHttpsError(e, "Création de commande");
  }
});

export const verifierCommande = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Connecte-toi d'abord.");
  const orderId = String((request.data as { orderId?: unknown } | null)?.orderId ?? "");
  if (!/^[A-Za-z0-9]{10,40}$/.test(orderId)) throw new HttpsError("invalid-argument", "Commande invalide.");
  try {
    return { status: await confirmOrder(getFirestore(), providersFromEnv(), orderId, new Date(), request.auth.uid) };
  } catch (e) {
    throw asHttpsError(e, "Vérification de commande");
  }
});

/** https://europe-west1-<projet>.cloudfunctions.net/notificationPaiement/<prestataire> */
export const notificationPaiement = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("POST attendu");
    return;
  }
  const providerName = req.path.replace(/^\/+|\/+$/g, "");
  try {
    const state = await handleNotification(
      getFirestore(),
      providersFromEnv(),
      providerName,
      req.rawBody,
      req.headers,
      req.body,
      new Date(),
    );
    if (state === null) {
      res.status(400).send("notification refusée");
      return;
    }
    res.status(200).send("ok");
  } catch (e) {
    logger.error("Notification de paiement", e);
    res.status(500).send("erreur"); // le prestataire réessaiera
  }
});

// --- Administration ---------------------------------------------------------------

function requireAdmin(request: CallableRequest): string {
  if (!request.auth || !isAdmin(request.auth.token)) {
    throw new HttpsError("permission-denied", "Espace réservé à l'administrateur de Buteo.");
  }
  return String(request.auth.token.email);
}

export const adminChiffres = onCall(async (request) => {
  requireAdmin(request);
  try {
    return await adminFigures(getFirestore(), new Date());
  } catch (e) {
    throw asHttpsError(e, "Chiffres");
  }
});

export const adminDonnerAcces = onCall(async (request) => {
  const admin = requireAdmin(request);
  const findUid = async (email: string) => {
    try {
      return (await getAuth().getUserByEmail(email)).uid;
    } catch {
      return null;
    }
  };
  try {
    return await adminGrant(getFirestore(), findUid, request.data, admin, new Date());
  } catch (e) {
    throw asHttpsError(e, "Accès offert");
  }
});

export const adminModerer = onCall(async (request) => {
  requireAdmin(request);
  try {
    return await adminModerate(getFirestore(), request.data, new Date());
  } catch (e) {
    throw asHttpsError(e, "Modération");
  }
});

export const adminMessage = onCall(async (request) => {
  requireAdmin(request);
  const messenger = {
    sendToTopic: (topic: string, title: string, body: string) =>
      getMessaging().send({
        topic,
        notification: { title, body },
        android: { notification: { channelId: "alertes" } },
      }),
  };
  try {
    return await sendAdminMessage(messenger, request.data);
  } catch (e) {
    throw asHttpsError(e, "Message à tous");
  }
});
