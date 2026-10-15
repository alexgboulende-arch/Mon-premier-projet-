import assert from "node:assert/strict";
import { beforeEach, describe, test } from "node:test";

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { adminFigures, adminGrant, adminMessage, adminModerate, isAdmin } from "../src/admin";
import { PurchaseError } from "../src/purchases";

// Lancé par `npm test` dans l'émulateur Firestore (FIRESTORE_EMULATOR_HOST).
const app = initializeApp({ projectId: "buteo-test" }, "admin");
const db = getFirestore(app);
const NOW = new Date("2026-10-15T12:00:00Z");

async function clear() {
  for (const name of ["users", "orders", "moderation", "leaderboards", "contestPlayers", "config", "stats"]) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

const rejects = (p: Promise<unknown>, code: string) =>
  assert.rejects(p, (e: unknown) => e instanceof PurchaseError && e.code === code);

describe("administration", () => {
  beforeEach(clear);

  test("seules les adresses de BUTEO_ADMINS, vérifiées, sont admin", () => {
    const env = { BUTEO_ADMINS: "Alex@Example.com, autre@example.com" };
    assert.equal(isAdmin({ email: "alex@example.com", email_verified: true }, env), true);
    assert.equal(isAdmin({ email: "alex@example.com", email_verified: false }, env), false);
    assert.equal(isAdmin({ email: "pirate@example.com", email_verified: true }, env), false);
    assert.equal(isAdmin(undefined, env), false);
    assert.equal(isAdmin({ email: "alex@example.com", email_verified: true }, {}), false);
  });

  test("chiffres : utilisateurs, ventes des 30 jours, moteur, pronos de la semaine", async () => {
    await db.doc("users/a").set({ favorites: [] });
    await db.doc("users/b").set({ favorites: [] });
    const paid = (days: number, method: string, amount: number, currency = "XAF") => ({
      status: "paid",
      method,
      amount,
      currency,
      paidAt: Timestamp.fromMillis(NOW.getTime() - days * 24 * 3600e3),
    });
    await db.collection("orders").add(paid(2, "mobile", 2900));
    await db.collection("orders").add(paid(5, "mobile", 500));
    await db.collection("orders").add(paid(3, "crypto", 10.49, "EUR"));
    await db.collection("orders").add(paid(40, "mobile", 6900)); // trop ancien
    await db.collection("orders").add({ status: "pending", method: "mobile", amount: 500 });
    await db.doc("config/engine").set({ lastPublish: "2026-10-16", plan: "gratuit", apiCalls: 21, lastRun: Timestamp.fromDate(NOW) });
    await db.doc("stats/summary").set({
      days: {
        "2026-10-14": { selection: { count: 1, won: 1 }, overunder: { count: 2, won: 1 } },
        "2026-10-01": { selection: { count: 3, won: 0 } }, // plus d'une semaine
      },
    });
    const f = await adminFigures(db, NOW);
    assert.equal(f.users, 2);
    assert.deepEqual(f.sales, {
      mobile: { count: 2, amount: 3400, currency: "XAF" },
      crypto: { count: 1, amount: 10.49, currency: "EUR" },
    });
    assert.deepEqual(f.engine, { lastPublish: "2026-10-16", lastRun: NOW.toISOString(), plan: "gratuit", apiCalls: 21 });
    assert.deepEqual(f.picks7days, { count: 3, won: 2 });
  });

  test("offrir une formule ou un coupon, avec une trace dans les commandes", async () => {
    const find = async (email: string) => (email === "awa@example.com" ? "awa" : null);
    const pro = await adminGrant(db, find, { email: "AWA@example.com ", product: "pro", months: 1 }, "alex@example.com", NOW);
    assert.equal(pro.tier, "pro");
    assert.equal(pro.until, "2026-11-15T12:00:00.000Z");
    const coupon = await adminGrant(db, find, { email: "awa@example.com", product: "coupon", rubric: "score" }, "alex@example.com", NOW);
    assert.equal(coupon.coupon, "2026-10-15|score");
    const profile = (await db.doc("users/awa").get()).data()!;
    assert.equal(profile.tier, "pro");
    assert.deepEqual(profile.coupons, ["2026-10-15|score"]);
    const orders = await db.collection("orders").where("method", "==", "admin").get();
    assert.equal(orders.size, 2);
    assert.equal(orders.docs[0].get("grantedBy"), "alex@example.com");

    await rejects(adminGrant(db, find, { email: "inconnu@example.com", product: "pro", months: 1 }, "a", NOW), "not-found");
    await rejects(adminGrant(db, find, { email: "awa@example.com", product: "pro", months: 2 }, "a", NOW), "invalid-argument");
    await rejects(adminGrant(db, find, { email: "pas-une-adresse", product: "pro", months: 1 }, "a", NOW), "invalid-argument");
  });

  test("modération : renommer puis exclure un joueur des classements en cours", async () => {
    const players = [
      { uid: "joueur01", pseudo: "Gros mot", points: 90, rank: 1 },
      { uid: "joueur02", pseudo: "Kofi", points: 50, rank: 2 },
    ];
    await db.doc("leaderboards/week-2026-W42").set({ players });
    await db.doc("leaderboards/week-2026-W41").set({ players, final: true });

    await adminModerate(db, { uid: "joueur01", pseudo: "Joueur 1" }, NOW);
    let board = (await db.doc("leaderboards/week-2026-W42").get()).get("players");
    assert.equal(board[0].pseudo, "Joueur 1");
    assert.equal((await db.doc("contestPlayers/joueur01").get()).get("pseudo"), "Joueur 1");

    await adminModerate(db, { uid: "joueur01", excluded: true }, NOW);
    board = (await db.doc("leaderboards/week-2026-W42").get()).get("players");
    assert.deepEqual(board.map((p: { uid: string; rank: number }) => [p.uid, p.rank]), [["joueur02", 1]]);
    // Une semaine terminée ne bouge plus.
    assert.equal((await db.doc("leaderboards/week-2026-W41").get()).get("players").length, 2);
    assert.deepEqual((await db.doc("moderation/all").get()).get("players"), { joueur01: { excluded: true } });

    await rejects(adminModerate(db, { uid: "joueur02", pseudo: "x" }, NOW), "invalid-argument");
  });

  test("message à tous : envoyé au sujet « annonces »", async () => {
    const sent: string[][] = [];
    const messenger = { sendToTopic: async (t: string, title: string, body: string) => (sent.push([t, title, body]), "id-1") };
    assert.deepEqual(await adminMessage(messenger, { title: "Nouveau : le concours", body: "Joue chaque jour sur 5 matchs !" }), { id: "id-1" });
    assert.deepEqual(sent, [["annonces", "Nouveau : le concours", "Joue chaque jour sur 5 matchs !"]]);
    await rejects(adminMessage(messenger, { title: "", body: "x" }), "invalid-argument");
  });
});
