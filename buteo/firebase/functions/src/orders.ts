/**
 * Paiements sur le site web de Buteo : Mobile Money et crypto.
 *
 * Le site crée une commande (`orders/{id}`), le client paie chez le
 * prestataire, puis le serveur interroge le prestataire avant de débloquer
 * l'accès dans `users/{uid}` (mêmes champs que les achats Google Play, lus par
 * l'app et par les règles Firestore). Une notification du prestataire ne fait
 * que déclencher cette vérification : elle ne suffit jamais à débloquer.
 *
 * Les formules du site se paient une fois pour 1, 3 ou 6 mois (le Mobile Money
 * ne permet pas de prélèvement automatique).
 */

import { DocumentData, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";

import { PurchaseError, Tier, dayKey } from "./purchases";

/** Prix du site, identiques à ceux de l'app (FCFA). */
export const PRICES_FCFA = {
  coupon: 500,
  pro: { 1: 2900, 3: 7500, 6: 13900 },
  elite: { 1: 6900, 3: 17900, 6: 32900 },
} as const;

/** Prix en euros pour la crypto (le coupon est sous les montants minimaux des cryptomonnaies). */
export const PRICES_EUR = {
  pro: { 1: 4.49, 3: 11.49, 6: 20.99 },
  elite: { 1: 10.49, 3: 27.49, 6: 49.99 },
} as const;

/** Rubriques VIP calculées par le moteur, vendues au coupon. */
export const COUPON_RUBRICS: Record<string, string> = {
  score: "Score exact",
  htft: "Mi-temps / Fin",
  c5: "Combiné cote 5+",
  c10: "Combiné cote 10+",
  simples: "Simples VIP",
};

export type Product = "coupon" | "pro" | "elite";
export type Method = "mobile" | "crypto";
export type PaymentState = "pending" | "paid" | "failed";

export interface Order {
  id: string;
  uid: string;
  product: Product;
  months: 1 | 3 | 6 | null;
  rubric: string | null;
  method: Method;
  amount: number;
  currency: "XAF" | "EUR";
  label: string;
  email: string | null;
  phone: string | null;
}

/** Où envoyer le client pour payer (formulaire POST si `fields` est présent). */
export interface Checkout {
  reference: string;
  url: string;
  fields?: Record<string, string>;
}

export interface Notification {
  orderId: string;
  reference: string;
}

/** Un prestataire de paiement (simulé dans les tests). */
export interface PaymentProvider {
  readonly name: string;
  start(order: Order): Promise<Checkout>;
  /** État du paiement chez le prestataire, et la commande à laquelle il se rattache. */
  status(reference: string): Promise<{ state: PaymentState; orderId?: string; amount?: number }>;
  /** Notification reçue du prestataire : commande concernée, ou null si elle est invalide. */
  notification(rawBody: Buffer, headers: Record<string, string | string[] | undefined>, body: unknown): Notification | null;
}

export interface Providers {
  mobile?: PaymentProvider;
  crypto?: PaymentProvider;
}

const TIER_RANK: Record<Tier, number> = { free: 0, pro: 1, elite: 2 };
const TIER_LABEL: Record<Tier, string> = { free: "Gratuit", pro: "Pro", elite: "Élite" };

interface OrderRequest {
  product: Product;
  months: 1 | 3 | 6 | null;
  rubric: string | null;
  method: Method;
  phone: string | null;
}

/** Numéro gabonais (« 077 12 34 56 », « +241 77123456 »…) au format national. */
export function gabonPhone(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  let digits = raw.replace(/[\s.\-()]/g, "");
  if (digits.startsWith("+241")) digits = digits.slice(4);
  else if (digits.startsWith("00241")) digits = digits.slice(5);
  if (!/^\d{8,9}$/.test(digits)) return null;
  return digits.length === 8 ? `0${digits}` : digits;
}

function parseOrder(input: unknown): OrderRequest {
  const r = (input ?? {}) as Record<string, unknown>;
  const product = r.product;
  if (product !== "coupon" && product !== "pro" && product !== "elite") {
    throw new PurchaseError("invalid-argument", "Offre inconnue.");
  }
  if (r.method !== "mobile" && r.method !== "crypto") throw new PurchaseError("invalid-argument", "Moyen de paiement inconnu.");
  const months = product === "coupon" ? null : Number(r.months);
  if (months !== null && months !== 1 && months !== 3 && months !== 6) {
    throw new PurchaseError("invalid-argument", "Durée invalide.");
  }
  const rubric = product === "coupon" ? String(r.rubric ?? "") : null;
  if (rubric !== null && !(rubric in COUPON_RUBRICS)) throw new PurchaseError("invalid-argument", "Rubrique inconnue.");
  if (product === "coupon" && r.method === "crypto") {
    throw new PurchaseError("invalid-argument", "Le coupon se paie par Mobile Money.");
  }
  let phone: string | null = null;
  if (r.method === "mobile") {
    phone = gabonPhone(r.phone);
    if (!phone) throw new PurchaseError("invalid-argument", "Numéro Mobile Money invalide.");
  }
  return { product, months, rubric, method: r.method, phone };
}

function activeTier(profile: DocumentData | undefined, now: Date): { tier: Tier; until: Date | null } {
  const until = profile?.tierUntil instanceof Timestamp ? profile.tierUntil.toDate() : null;
  const tier = (profile?.tier as Tier | undefined) ?? "free";
  return tier !== "free" && until && until > now ? { tier, until } : { tier: "free", until: null };
}

/** Crée la commande et prépare le paiement chez le prestataire. */
export async function createOrder(
  db: Firestore,
  providers: Providers,
  user: { uid: string; email?: string | null },
  input: unknown,
  now: Date,
): Promise<{ orderId: string; checkout: Omit<Checkout, "reference"> }> {
  const req = parseOrder(input);
  const provider = providers[req.method];
  if (!provider) throw new PurchaseError("failed-precondition", "Ce moyen de paiement n'est pas encore disponible.");

  if (req.product !== "coupon") {
    const current = activeTier((await db.doc(`users/${user.uid}`).get()).data(), now);
    if (TIER_RANK[current.tier] > TIER_RANK[req.product]) {
      throw new PurchaseError(
        "failed-precondition",
        `Tu as déjà la formule ${TIER_LABEL[current.tier]} jusqu'au ${current.until!.toLocaleDateString("fr-FR")}.`,
      );
    }
  }

  const crypto = req.method === "crypto";
  const amount =
    req.product === "coupon"
      ? PRICES_FCFA.coupon
      : crypto
        ? PRICES_EUR[req.product][req.months!]
        : PRICES_FCFA[req.product][req.months!];
  const label =
    req.product === "coupon"
      ? `Buteo · coupon ${COUPON_RUBRICS[req.rubric!]}`
      : `Buteo · formule ${TIER_LABEL[req.product]} ${req.months} mois`;
  const ref = db.collection("orders").doc();
  const order: Order = {
    id: ref.id,
    uid: user.uid,
    product: req.product,
    months: req.months,
    rubric: req.rubric,
    method: req.method,
    amount,
    currency: crypto ? "EUR" : "XAF",
    label,
    email: user.email ?? null,
    phone: req.phone,
  };
  const { id: _id, ...fields } = order;
  await ref.set({ ...fields, provider: provider.name, status: "pending", createdAt: Timestamp.fromDate(now) });

  let checkout: Checkout;
  try {
    checkout = await provider.start(order);
  } catch (e) {
    await ref.update({ status: "failed", error: String(e).slice(0, 300) });
    throw new PurchaseError("unavailable", "Le service de paiement ne répond pas. Réessaie dans un instant.");
  }
  await ref.update({ reference: checkout.reference });
  const { reference: _ref, ...redirect } = checkout;
  return { orderId: ref.id, checkout: redirect };
}

/** Interroge le prestataire et débloque l'accès si le paiement est confirmé. */
export async function confirmOrder(
  db: Firestore,
  providers: Providers,
  orderId: string,
  now: Date,
  uid?: string,
): Promise<PaymentState> {
  const ref = db.doc(`orders/${orderId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new PurchaseError("not-found", "Commande introuvable.");
  if (uid !== undefined && snap.get("uid") !== uid) throw new PurchaseError("permission-denied", "Cette commande n'est pas la tienne.");
  if (snap.get("status") !== "pending") return snap.get("status") as PaymentState;

  const provider = providers[snap.get("method") as Method];
  const reference = snap.get("reference");
  if (!provider || typeof reference !== "string") return "pending";
  const result = await provider.status(reference);
  if (result.state === "pending") return "pending";
  // Paiement rattaché à une autre commande, ou montant différent : on ne débloque rien.
  const mismatch =
    (result.orderId !== undefined && result.orderId !== orderId) ||
    (result.amount !== undefined && result.amount + 1e-9 < snap.get("amount"));
  const state: PaymentState = result.state === "paid" && !mismatch ? "paid" : "failed";

  return db.runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    if (fresh.get("status") !== "pending") return fresh.get("status") as PaymentState;
    const userRef = db.doc(`users/${fresh.get("uid")}`);
    const update: Record<string, unknown> = { status: state, updatedAt: Timestamp.fromDate(now) };
    if (state === "paid") {
      const profile = (await tx.get(userRef)).data();
      Object.assign(update, grant(tx, userRef, profile, fresh.data()!, now), { paidAt: Timestamp.fromDate(now) });
    } else if (mismatch) {
      update.error = "Paiement non conforme à la commande.";
    }
    tx.update(ref, update);
    return state;
  });
}

/** Écrit l'accès acheté (ou offert) dans le profil. Renvoie ce qui a été donné, pour la commande. */
export function grant(
  tx: Transaction,
  userRef: FirebaseFirestore.DocumentReference,
  profile: DocumentData | undefined,
  order: DocumentData,
  now: Date,
): Record<string, unknown> {
  if (order.product === "coupon") {
    const coupon = `${dayKey(now)}|${order.rubric}`;
    tx.set(userRef, { coupons: FieldValue.arrayUnion(coupon) }, { merge: true });
    return { coupon };
  }
  const bought = order.product as Tier;
  const current = activeTier(profile, now);
  // Même formule : on prolonge. Formule supérieure : elle remplace la formule en cours.
  // (Formule inférieure payée entre-temps : on prolonge la formule en cours.)
  const tier = TIER_RANK[current.tier] > TIER_RANK[bought] ? current.tier : bought;
  const start = current.tier === tier && current.until ? current.until : now;
  const until = new Date(start);
  until.setUTCMonth(until.getUTCMonth() + Number(order.months));
  tx.set(userRef, { tier, tierUntil: Timestamp.fromDate(until) }, { merge: true });
  return { grantedTier: tier, grantedUntil: Timestamp.fromDate(until) };
}

/** Notification d'un prestataire : on retrouve la commande, puis on vérifie auprès de lui. */
export async function handleNotification(
  db: Firestore,
  providers: Providers,
  providerName: string,
  rawBody: Buffer,
  headers: Record<string, string | string[] | undefined>,
  body: unknown,
  now: Date,
): Promise<PaymentState | null> {
  const provider = Object.values(providers).find((p) => p?.name === providerName);
  if (!provider) return null;
  const note = provider.notification(rawBody, headers, body);
  if (!note) return null;
  const ref = db.doc(`orders/${note.orderId}`);
  const snap = await ref.get();
  if (!snap.exists || snap.get("provider") !== providerName) return null;
  if (snap.get("reference") !== note.reference && snap.get("status") === "pending") {
    // Crypto : le paiement reçoit son propre numéro une fois la monnaie choisie.
    await ref.update({ reference: note.reference });
  }
  return confirmOrder(db, providers, note.orderId, now);
}

/** Moyens de paiement configurés, pour l'affichage du site. */
export const availableMethods = (providers: Providers) => ({
  mobile: providers.mobile?.name ?? null,
  crypto: providers.crypto?.name ?? null,
});
