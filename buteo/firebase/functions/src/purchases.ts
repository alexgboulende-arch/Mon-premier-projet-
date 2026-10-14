/**
 * Vérification des achats Google Play et attribution des accès.
 *
 * L'app envoie le jeton d'achat ; le serveur le vérifie auprès de Google, puis
 * écrit la formule (`tier`, `tierUntil`) ou le coupon (`coupons`) dans le
 * profil `users/{uid}`. Les règles Firestore interdisent à l'app d'écrire
 * ces champs : seul ce code peut débloquer le VIP.
 */

import { createHash } from "node:crypto";
import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";

export const PACKAGE_NAME = "com.buteo.pronostics";

/** Abonnements Google Play et formule correspondante (les durées sont des « forfaits de base »). */
export const SUBSCRIPTIONS: Record<string, Tier> = { buteo_pro: "pro", buteo_elite: "elite" };

/** Produit consommable : une rubrique VIP débloquée pour la journée. */
export const COUPON_PRODUCT = "coupon_vip";

export const VIP_RUBRICS = ["score", "htft", "c5", "c10", "simples", "live"];

/** États Google d'un abonnement qui donnent accès (résilié = actif jusqu'à l'échéance). */
const ACTIVE_STATES = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  "SUBSCRIPTION_STATE_CANCELED",
]);

export type Tier = "free" | "pro" | "elite";

export interface SubscriptionInfo {
  productId: string;
  state: string;
  expiry: Date | null;
  acknowledged: boolean;
  orderId?: string;
}

export interface ProductInfo {
  purchased: boolean;
  orderId?: string;
}

/** Ce dont le serveur a besoin chez Google (remplacé par une version simulée dans les tests). */
export interface PlayApi {
  subscription(token: string): Promise<SubscriptionInfo>;
  acknowledgeSubscription(productId: string, token: string): Promise<void>;
  product(productId: string, token: string): Promise<ProductInfo>;
}

export interface PurchaseRequest {
  kind: "subscription" | "coupon";
  productId: string;
  purchaseToken: string;
  rubric?: string;
}

export interface Entitlement {
  tier: Tier;
  tierUntil: string | null;
  coupons: string[];
}

export class PurchaseError extends Error {
  constructor(
    readonly code: "invalid-argument" | "permission-denied" | "failed-precondition" | "not-found" | "unavailable",
    message: string,
  ) {
    super(message);
  }
}

export const tokenId = (token: string) => createHash("sha256").update(token).digest("hex");

export const dayKey = (d: Date) => d.toISOString().slice(0, 10);

function parse(input: unknown): PurchaseRequest {
  const r = (input ?? {}) as Record<string, unknown>;
  if (r.kind !== "subscription" && r.kind !== "coupon") throw new PurchaseError("invalid-argument", "Type d'achat inconnu.");
  if (typeof r.productId !== "string" || typeof r.purchaseToken !== "string" || r.purchaseToken.length < 10) {
    throw new PurchaseError("invalid-argument", "Achat incomplet.");
  }
  if (r.kind === "subscription" && !(r.productId in SUBSCRIPTIONS)) {
    throw new PurchaseError("invalid-argument", "Abonnement inconnu.");
  }
  if (r.kind === "coupon" && (r.productId !== COUPON_PRODUCT || !VIP_RUBRICS.includes(String(r.rubric)))) {
    throw new PurchaseError("invalid-argument", "Coupon invalide.");
  }
  return { kind: r.kind, productId: r.productId, purchaseToken: r.purchaseToken, rubric: r.rubric as string | undefined };
}

/** Vérifie un achat et attribue l'accès correspondant. Renvoie les accès à jour. */
export async function verifyPlayPurchase(
  db: Firestore,
  play: PlayApi,
  uid: string,
  input: unknown,
  now: Date,
): Promise<Entitlement> {
  const req = parse(input);
  const purchaseRef = db.doc(`purchases/${tokenId(req.purchaseToken)}`);
  const userRef = db.doc(`users/${uid}`);

  const existing = await purchaseRef.get();
  if (existing.exists && existing.get("uid") !== uid) {
    throw new PurchaseError("permission-denied", "Cet achat est déjà rattaché à un autre compte Buteo.");
  }

  if (req.kind === "subscription") {
    const info = await play.subscription(req.purchaseToken);
    if (info.productId !== req.productId) throw new PurchaseError("invalid-argument", "Abonnement inattendu.");
    if (!ACTIVE_STATES.has(info.state) || !info.expiry || info.expiry <= now) {
      throw new PurchaseError("failed-precondition", "Cet abonnement n'est pas actif.");
    }
    if (!info.acknowledged) await play.acknowledgeSubscription(req.productId, req.purchaseToken);
    const expiry = Timestamp.fromDate(info.expiry);
    await db.runTransaction(async (tx) => {
      tx.set(
        purchaseRef,
        {
          uid,
          kind: "subscription",
          productId: req.productId,
          token: req.purchaseToken,
          state: info.state,
          expiry,
          orderId: info.orderId ?? null,
          updatedAt: Timestamp.fromDate(now),
        },
        { merge: true },
      );
      tx.set(
        userRef,
        { tier: SUBSCRIPTIONS[req.productId], tierUntil: expiry, subscription: purchaseRef.id },
        { merge: true },
      );
    });
  } else if (!existing.exists) {
    const info = await play.product(req.productId, req.purchaseToken);
    if (!info.purchased) throw new PurchaseError("failed-precondition", "Le paiement n'est pas encore confirmé.");
    const coupon = `${dayKey(now)}|${req.rubric}`;
    await db.runTransaction(async (tx) => {
      tx.set(purchaseRef, {
        uid,
        kind: "coupon",
        productId: req.productId,
        rubric: req.rubric,
        date: dayKey(now),
        orderId: info.orderId ?? null,
        createdAt: Timestamp.fromDate(now),
      });
      tx.set(userRef, { coupons: FieldValue.arrayUnion(coupon) }, { merge: true });
    });
  }
  // Un coupon déjà enregistré n'est pas compté deux fois : on renvoie simplement les accès.
  return entitlementOf((await userRef.get()).data(), now);
}

export function entitlementOf(profile: Record<string, unknown> | undefined, now: Date): Entitlement {
  const until = profile?.tierUntil instanceof Timestamp ? profile.tierUntil.toDate() : null;
  const tier = (profile?.tier as Tier | undefined) ?? "free";
  const active = tier !== "free" && until !== null && until > now;
  return {
    tier: active ? tier : "free",
    tierUntil: active ? until.toISOString() : null,
    coupons: Array.isArray(profile?.coupons) ? (profile.coupons as string[]) : [],
  };
}

/**
 * Tâche régulière : abonnements renouvelés ou arrivés à échéance, et
 * nettoyage des coupons de plus de 3 jours. Renvoie le nombre de profils modifiés.
 */
export async function refreshSubscriptions(db: Firestore, play: PlayApi, now: Date): Promise<number> {
  const soon = Timestamp.fromMillis(now.getTime() + 24 * 3600e3);
  const snap = await db.collection("users").where("tierUntil", "<", soon).get();
  const oldest = dayKey(new Date(now.getTime() - 3 * 24 * 3600e3));
  let changed = 0;
  for (const user of snap.docs) {
    const update: Record<string, unknown> = {};
    const subscription = user.get("subscription");
    const current = user.get("tierUntil") instanceof Timestamp ? (user.get("tierUntil") as Timestamp).toDate() : null;
    if (user.get("tier") !== "free" && typeof subscription === "string") {
      const purchase = await db.doc(`purchases/${subscription}`).get();
      const token = purchase.get("token");
      if (typeof token === "string") {
        const info = await play.subscription(token);
        if (ACTIVE_STATES.has(info.state) && info.expiry && info.expiry > now) {
          // Une formule payée sur le site peut aller plus loin : on ne raccourcit jamais.
          if (!current || info.expiry > current) update.tierUntil = Timestamp.fromDate(info.expiry);
          await purchase.ref.set({ state: info.state, expiry: Timestamp.fromDate(info.expiry) }, { merge: true });
        } else if (!info.expiry || info.expiry <= now) {
          if (!current || current <= now) update.tier = "free";
          await purchase.ref.set({ state: info.state }, { merge: true });
        }
      }
    }
    const coupons = user.get("coupons");
    if (Array.isArray(coupons)) {
      const kept = coupons.filter((c: string) => c.slice(0, 10) >= oldest);
      if (kept.length !== coupons.length) update.coupons = kept;
    }
    if (Object.keys(update).length) {
      await user.ref.set(update, { merge: true });
      changed++;
    }
  }
  return changed;
}
