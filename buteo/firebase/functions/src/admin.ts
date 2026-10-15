/**
 * Espace d'administration (page admin.html du site), réservé aux adresses
 * listées dans BUTEO_ADMINS (variable GitHub passée aux fonctions au
 * déploiement, séparées par des virgules).
 *
 *  - chiffres : utilisateurs, ventes des 30 derniers jours, moteur, pronos ;
 *  - accès offert : formule ou coupon, enregistré comme une commande « admin » ;
 *  - modération du concours : renommer ou exclure un joueur ;
 *  - message à tous : notification envoyée au sujet « annonces » de l'app.
 */

import { FieldPath, Firestore, Timestamp } from "firebase-admin/firestore";

import { COUPON_RUBRICS, grant } from "./orders";
import { PurchaseError } from "./purchases";

export interface AdminToken {
  email?: string;
  email_verified?: boolean;
}

export function isAdmin(token: AdminToken | undefined, env: NodeJS.ProcessEnv = process.env): boolean {
  const allowed = (env.BUTEO_ADMINS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  return !!token?.email && token.email_verified === true && allowed.includes(token.email.toLowerCase());
}

const DAY = 24 * 3600e3;

/** Tableau de bord. */
export async function adminFigures(db: Firestore, now: Date) {
  const since = Timestamp.fromMillis(now.getTime() - 30 * DAY);
  const [users, orders, engine, summary] = await Promise.all([
    db.collection("users").count().get(),
    db.collection("orders").where("paidAt", ">=", since).get(),
    db.doc("config/engine").get(),
    db.doc("stats/summary").get(),
  ]);
  const sales: Record<string, { count: number; amount: number; currency: string }> = {};
  for (const o of orders.docs) {
    if (o.get("status") !== "paid") continue;
    const key = String(o.get("method"));
    const s = (sales[key] ??= { count: 0, amount: 0, currency: String(o.get("currency") ?? "XAF") });
    s.count += 1;
    s.amount = Math.round((s.amount + Number(o.get("amount") ?? 0)) * 100) / 100;
  }
  const week = new Date(now.getTime() - 7 * DAY).toISOString().slice(0, 10);
  let count = 0;
  let won = 0;
  for (const [day, rubrics] of Object.entries((summary.get("days") ?? {}) as Record<string, Record<string, { count: number; won: number }>>)) {
    if (day < week) continue;
    for (const r of Object.values(rubrics)) {
      count += r.count;
      won += r.won;
    }
  }
  const e = engine.data() ?? {};
  const date = (v: unknown) => (v instanceof Timestamp ? v.toDate().toISOString() : (v ?? null));
  return {
    users: users.data().count,
    sales,
    engine: { lastPublish: e.lastPublish ?? null, lastRun: date(e.lastRun), plan: e.plan ?? null, apiCalls: e.apiCalls ?? null },
    picks7days: { count, won },
  };
}

/** Accès offert à un utilisateur (retrouvé par son adresse e-mail). */
export async function adminGrant(
  db: Firestore,
  findUid: (email: string) => Promise<string | null>,
  input: unknown,
  adminEmail: string,
  now: Date,
) {
  const r = (input ?? {}) as Record<string, unknown>;
  const email = String(r.email ?? "").trim().toLowerCase();
  if (!email.includes("@")) throw new PurchaseError("invalid-argument", "Adresse e-mail invalide.");
  const product = r.product;
  if (product !== "pro" && product !== "elite" && product !== "coupon") throw new PurchaseError("invalid-argument", "Offre inconnue.");
  const months = product === "coupon" ? null : Number(r.months);
  if (months !== null && ![1, 3, 6].includes(months)) throw new PurchaseError("invalid-argument", "Durée invalide.");
  const rubric = product === "coupon" ? String(r.rubric ?? "") : null;
  if (rubric !== null && !(rubric in COUPON_RUBRICS)) throw new PurchaseError("invalid-argument", "Rubrique inconnue.");

  const uid = await findUid(email);
  if (!uid) throw new PurchaseError("not-found", "Aucun compte Buteo avec cette adresse.");
  const orderRef = db.collection("orders").doc();
  const userRef = db.doc(`users/${uid}`);
  const order = { uid, product, months, rubric, method: "admin", amount: 0, currency: "XAF", email, grantedBy: adminEmail };
  return db.runTransaction(async (tx) => {
    const profile = (await tx.get(userRef)).data();
    const given = grant(tx, userRef, profile, order, now);
    tx.set(orderRef, {
      ...order,
      provider: "admin",
      status: "paid",
      label: "Accès offert",
      createdAt: Timestamp.fromDate(now),
      paidAt: Timestamp.fromDate(now),
      ...given,
    });
    const until = given.grantedUntil instanceof Timestamp ? given.grantedUntil.toDate().toISOString() : null;
    return { uid, tier: (given.grantedTier as string | undefined) ?? null, until, coupon: (given.coupon as string | undefined) ?? null };
  });
}

/** Renommer ou exclure un joueur du concours (appliqué tout de suite aux classements en cours). */
export async function adminModerate(db: Firestore, input: unknown, now: Date) {
  const r = (input ?? {}) as Record<string, unknown>;
  const uid = String(r.uid ?? "");
  if (!/^[A-Za-z0-9_-]{6,128}$/.test(uid)) throw new PurchaseError("invalid-argument", "Joueur invalide.");
  const excluded = r.excluded === true;
  const pseudo = typeof r.pseudo === "string" ? r.pseudo.trim() : null;
  if (!excluded && (!pseudo || !/^[\p{L}\p{N} ._-]{3,20}$/u.test(pseudo))) {
    throw new PurchaseError("invalid-argument", "Pseudo invalide (3 à 20 caractères).");
  }
  const decision = excluded ? { excluded: true } : { pseudo };
  // La nouvelle décision remplace l'ancienne pour ce joueur.
  const moderation = db.doc("moderation/all");
  await moderation.set({ updatedAt: Timestamp.fromDate(now) }, { merge: true });
  await moderation.update(new FieldPath("players", uid), decision);

  const boards = await db.collection("leaderboards").get();
  for (const board of boards.docs) {
    if (board.get("final")) continue;
    const players = (board.get("players") ?? []) as Array<Record<string, unknown>>;
    if (!players.some((p) => p.uid === uid)) continue;
    const updated = excluded
      ? players.filter((p) => p.uid !== uid).map((p, i) => ({ ...p, rank: i + 1 }))
      : players.map((p) => (p.uid === uid ? { ...p, pseudo } : p));
    await board.ref.update({ players: updated, updatedAt: Timestamp.fromDate(now) });
  }
  if (!excluded) await db.doc(`contestPlayers/${uid}`).set({ pseudo }, { merge: true });
  return decision;
}

export interface Messenger {
  sendToTopic(topic: string, title: string, body: string): Promise<string>;
}

/** Notification à tous les utilisateurs de l'app (abonnés au sujet « annonces »). */
export async function adminMessage(messenger: Messenger, input: unknown) {
  const r = (input ?? {}) as Record<string, unknown>;
  const title = String(r.title ?? "").trim();
  const body = String(r.body ?? "").trim();
  if (title.length < 3 || title.length > 60) throw new PurchaseError("invalid-argument", "Titre : 3 à 60 caractères.");
  if (body.length < 3 || body.length > 240) throw new PurchaseError("invalid-argument", "Message : 3 à 240 caractères.");
  return { id: await messenger.sendToTopic("annonces", title, body) };
}
