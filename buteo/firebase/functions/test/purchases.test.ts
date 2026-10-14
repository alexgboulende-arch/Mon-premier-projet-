import assert from "node:assert/strict";
import { beforeEach, describe, test } from "node:test";

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import {
  PlayApi,
  ProductInfo,
  PurchaseError,
  SubscriptionInfo,
  refreshSubscriptions,
  tokenId,
  verifyPlayPurchase,
} from "../src/purchases";

// Lancé par `npm test` dans l'émulateur Firestore (FIRESTORE_EMULATOR_HOST).
const app = initializeApp({ projectId: "buteo-test" }, "tests");
const db = getFirestore(app);
const NOW = new Date("2026-10-14T20:00:00Z");
const IN_A_MONTH = new Date("2026-11-14T20:00:00Z");

/** Google simulé : les achats connus et ce qui a été confirmé. */
class FakePlay implements PlayApi {
  subscriptions = new Map<string, SubscriptionInfo>();
  products = new Map<string, ProductInfo>();
  acknowledged: string[] = [];

  async subscription(token: string) {
    const s = this.subscriptions.get(token);
    if (!s) throw new Error("jeton inconnu");
    return s;
  }
  async acknowledgeSubscription(_productId: string, token: string) {
    this.acknowledged.push(token);
  }
  async product(_productId: string, token: string) {
    return this.products.get(token) ?? { purchased: false };
  }
}

async function clear() {
  for (const name of ["users", "purchases"]) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

const rejects = (p: Promise<unknown>, code: string) =>
  assert.rejects(p, (e: unknown) => e instanceof PurchaseError && e.code === code);

describe("achats Google Play", () => {
  let play: FakePlay;
  beforeEach(async () => {
    await clear();
    play = new FakePlay();
  });

  test("un abonnement Pro actif donne la formule jusqu'à l'échéance", async () => {
    play.subscriptions.set("jeton-pro-0001", {
      productId: "buteo_pro",
      state: "SUBSCRIPTION_STATE_ACTIVE",
      expiry: IN_A_MONTH,
      acknowledged: false,
    });
    const access = await verifyPlayPurchase(
      db,
      play,
      "awa",
      { kind: "subscription", productId: "buteo_pro", purchaseToken: "jeton-pro-0001" },
      NOW,
    );
    assert.equal(access.tier, "pro");
    assert.equal(access.tierUntil, IN_A_MONTH.toISOString());
    assert.deepEqual(play.acknowledged, ["jeton-pro-0001"]);
    const profile = (await db.doc("users/awa").get()).data()!;
    assert.equal(profile.tier, "pro");
    // Le jeton brut n'est gardé que côté serveur, jamais dans le profil.
    assert.equal(profile.subscription, tokenId("jeton-pro-0001"));
  });

  test("un abonnement expiré ou d'un autre produit est refusé", async () => {
    play.subscriptions.set("jeton-expire-01", {
      productId: "buteo_elite",
      state: "SUBSCRIPTION_STATE_EXPIRED",
      expiry: new Date("2026-10-01T00:00:00Z"),
      acknowledged: true,
    });
    await rejects(
      verifyPlayPurchase(db, play, "awa", { kind: "subscription", productId: "buteo_elite", purchaseToken: "jeton-expire-01" }, NOW),
      "failed-precondition",
    );
    await rejects(
      verifyPlayPurchase(db, play, "awa", { kind: "subscription", productId: "buteo_pro", purchaseToken: "jeton-expire-01" }, NOW),
      "invalid-argument",
    );
    assert.equal((await db.doc("users/awa").get()).exists, false);
  });

  test("un coupon débloque la rubrique choisie pour la journée, une seule fois", async () => {
    play.products.set("jeton-coupon-01", { purchased: true, orderId: "GPA.1" });
    const req = { kind: "coupon", productId: "coupon_vip", purchaseToken: "jeton-coupon-01", rubric: "score" };
    const first = await verifyPlayPurchase(db, play, "awa", req, NOW);
    assert.deepEqual(first.coupons, ["2026-10-14|score"]);
    assert.equal(first.tier, "free");
    // Le même jeton renvoyé (nouvel essai réseau, autre rubrique) ne crée pas un second coupon.
    const again = await verifyPlayPurchase(db, play, "awa", { ...req, rubric: "c10" }, NOW);
    assert.deepEqual(again.coupons, ["2026-10-14|score"]);
  });

  test("un achat ne peut pas servir à deux comptes", async () => {
    play.products.set("jeton-coupon-02", { purchased: true });
    const req = { kind: "coupon", productId: "coupon_vip", purchaseToken: "jeton-coupon-02", rubric: "c5" };
    await verifyPlayPurchase(db, play, "awa", req, NOW);
    await rejects(verifyPlayPurchase(db, play, "moussa", req, NOW), "permission-denied");
  });

  test("paiement en attente, coupon pour une rubrique gratuite, requête incomplète : refusés", async () => {
    play.products.set("jeton-attente-1", { purchased: false });
    await rejects(
      verifyPlayPurchase(db, play, "awa", { kind: "coupon", productId: "coupon_vip", purchaseToken: "jeton-attente-1", rubric: "score" }, NOW),
      "failed-precondition",
    );
    await rejects(
      verifyPlayPurchase(db, play, "awa", { kind: "coupon", productId: "coupon_vip", purchaseToken: "jeton-attente-1", rubric: "selection" }, NOW),
      "invalid-argument",
    );
    await rejects(verifyPlayPurchase(db, play, "awa", { kind: "coupon" }, NOW), "invalid-argument");
  });
});

describe("suivi des abonnements", () => {
  let play: FakePlay;
  beforeEach(async () => {
    await clear();
    play = new FakePlay();
  });

  async function subscribe(uid: string, token: string, expiry: Date) {
    play.subscriptions.set(token, { productId: "buteo_elite", state: "SUBSCRIPTION_STATE_ACTIVE", expiry, acknowledged: true });
    await verifyPlayPurchase(db, play, uid, { kind: "subscription", productId: "buteo_elite", purchaseToken: token }, NOW);
  }

  test("renouvellement : l'échéance est repoussée", async () => {
    await subscribe("awa", "jeton-renouvele", new Date("2026-10-15T08:00:00Z"));
    const renewed = new Date("2026-11-15T08:00:00Z");
    play.subscriptions.set("jeton-renouvele", { productId: "buteo_elite", state: "SUBSCRIPTION_STATE_ACTIVE", expiry: renewed, acknowledged: true });
    assert.equal(await refreshSubscriptions(db, play, NOW), 1);
    const until = (await db.doc("users/awa").get()).get("tierUntil") as Timestamp;
    assert.equal(until.toDate().toISOString(), renewed.toISOString());
  });

  test("échéance passée sans renouvellement : retour au gratuit", async () => {
    await subscribe("awa", "jeton-termine-1", new Date("2026-10-15T08:00:00Z"));
    play.subscriptions.set("jeton-termine-1", {
      productId: "buteo_elite",
      state: "SUBSCRIPTION_STATE_EXPIRED",
      expiry: new Date("2026-10-15T08:00:00Z"),
      acknowledged: true,
    });
    await refreshSubscriptions(db, play, new Date("2026-10-15T09:00:00Z"));
    assert.equal((await db.doc("users/awa").get()).get("tier"), "free");
  });

  test("les coupons de plus de trois jours sont retirés", async () => {
    await db.doc("users/moussa").set({
      tier: "free",
      tierUntil: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")),
      coupons: ["2026-10-01|score", "2026-10-13|c10", "2026-10-14|c5"],
    });
    await refreshSubscriptions(db, play, NOW);
    assert.deepEqual((await db.doc("users/moussa").get()).get("coupons"), ["2026-10-13|c10", "2026-10-14|c5"]);
  });
});
