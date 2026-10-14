import assert from "node:assert/strict";
import { beforeEach, describe, test } from "node:test";

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import {
  Checkout,
  Notification,
  Order,
  PaymentProvider,
  PaymentState,
  Providers,
  confirmOrder,
  createOrder,
  gabonPhone,
  handleNotification,
} from "../src/orders";
import { EBilling, NowPayments, nowPaymentsSignature } from "../src/providers";
import { PlayApi, PurchaseError, refreshSubscriptions } from "../src/purchases";

// Lancé par `npm test` dans l'émulateur Firestore (FIRESTORE_EMULATOR_HOST).
const app = initializeApp({ projectId: "buteo-test" }, "commandes");
const db = getFirestore(app);
const NOW = new Date("2026-10-14T20:00:00Z");
const AWA = { uid: "awa", email: "awa@example.com" };

/** Prestataire simulé : on décide de l'état de chaque paiement. */
class FakeProvider implements PaymentProvider {
  states = new Map<string, { state: PaymentState; orderId?: string; amount?: number }>();
  started: Order[] = [];
  failStart = false;

  constructor(readonly name: string) {}

  async start(order: Order): Promise<Checkout> {
    if (this.failStart) throw new Error("service indisponible");
    this.started.push(order);
    return { reference: `ref-${order.id}`, url: `https://paiement.example/${order.id}` };
  }
  async status(reference: string) {
    return this.states.get(reference) ?? { state: "pending" as const };
  }
  notification(_raw: Buffer, _headers: Record<string, unknown>, body: unknown): Notification | null {
    const b = body as { order?: string };
    return b?.order ? { orderId: b.order, reference: `ref-${b.order}` } : null;
  }
  pay(orderId: string, extra: { orderId?: string; amount?: number } = {}) {
    this.states.set(`ref-${orderId}`, { state: "paid", ...extra });
  }
}

async function clear() {
  for (const name of ["users", "orders", "purchases"]) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

const rejects = (p: Promise<unknown>, code: string) =>
  assert.rejects(p, (e: unknown) => e instanceof PurchaseError && e.code === code);

const profile = async (uid = "awa") => (await db.doc(`users/${uid}`).get()).data() ?? {};
const until = (data: Record<string, unknown>) => (data.tierUntil as Timestamp).toDate().toISOString();

describe("commandes du site", () => {
  let mobile: FakeProvider;
  let crypto: FakeProvider;
  let providers: Providers;
  beforeEach(async () => {
    await clear();
    mobile = new FakeProvider("ebilling");
    crypto = new FakeProvider("nowpayments");
    providers = { mobile, crypto };
  });

  test("numéros gabonais", () => {
    assert.equal(gabonPhone("077 12 34 56"), "077123456");
    assert.equal(gabonPhone("+241 77 12 34 56"), "077123456");
    assert.equal(gabonPhone("0024162123456"), "062123456");
    assert.equal(gabonPhone("12345"), null);
  });

  test("coupon par Mobile Money : rien avant le paiement, la rubrique du jour après", async () => {
    const { orderId, checkout } = await createOrder(db, providers, AWA, { product: "coupon", rubric: "score", method: "mobile", phone: "077123456" }, NOW);
    assert.equal(checkout.url, `https://paiement.example/${orderId}`);
    const order = (await db.doc(`orders/${orderId}`).get()).data()!;
    assert.equal(order.amount, 500);
    assert.equal(order.currency, "XAF");
    assert.equal(order.status, "pending");
    assert.equal(order.phone, "077123456");

    assert.equal(await confirmOrder(db, providers, orderId, NOW, "awa"), "pending");
    assert.deepEqual(await profile(), {});

    mobile.pay(orderId, { orderId, amount: 500 });
    assert.equal(await confirmOrder(db, providers, orderId, NOW, "awa"), "paid");
    assert.deepEqual((await profile()).coupons, ["2026-10-14|score"]);
    // Une seconde vérification ne redonne rien.
    assert.equal(await confirmOrder(db, providers, orderId, NOW, "awa"), "paid");
    assert.deepEqual((await profile()).coupons, ["2026-10-14|score"]);
  });

  test("demandes invalides", async () => {
    await rejects(createOrder(db, providers, AWA, { product: "coupon", rubric: "score", method: "crypto" }, NOW), "invalid-argument");
    await rejects(createOrder(db, providers, AWA, { product: "coupon", rubric: "score", method: "mobile", phone: "12" }, NOW), "invalid-argument");
    await rejects(createOrder(db, providers, AWA, { product: "coupon", rubric: "live", method: "mobile", phone: "077123456" }, NOW), "invalid-argument");
    await rejects(createOrder(db, providers, AWA, { product: "pro", months: 2, method: "mobile", phone: "077123456" }, NOW), "invalid-argument");
    await rejects(createOrder(db, { mobile }, AWA, { product: "pro", months: 1, method: "crypto" }, NOW), "failed-precondition");
  });

  test("formule Pro : 3 mois, puis 1 mois de plus à la suite", async () => {
    const first = await createOrder(db, providers, AWA, { product: "pro", months: 3, method: "mobile", phone: "062123456" }, NOW);
    assert.equal((await db.doc(`orders/${first.orderId}`).get()).get("amount"), 7500);
    mobile.pay(first.orderId);
    await confirmOrder(db, providers, first.orderId, NOW);
    let p = await profile();
    assert.equal(p.tier, "pro");
    assert.equal(until(p), "2027-01-14T20:00:00.000Z");

    const second = await createOrder(db, providers, AWA, { product: "pro", months: 1, method: "mobile", phone: "062123456" }, NOW);
    mobile.pay(second.orderId);
    await confirmOrder(db, providers, second.orderId, NOW);
    p = await profile();
    assert.equal(until(p), "2027-02-14T20:00:00.000Z");
  });

  test("Élite remplace Pro ; Pro refusé pendant une formule Élite", async () => {
    await db.doc("users/awa").set({ tier: "pro", tierUntil: Timestamp.fromDate(new Date("2026-12-01T00:00:00Z")) });
    const { orderId } = await createOrder(db, providers, AWA, { product: "elite", months: 1, method: "crypto" }, NOW);
    const order = (await db.doc(`orders/${orderId}`).get()).data()!;
    assert.equal(order.amount, 10.49);
    assert.equal(order.currency, "EUR");
    crypto.pay(orderId);
    await confirmOrder(db, providers, orderId, NOW);
    const p = await profile();
    assert.equal(p.tier, "elite");
    assert.equal(until(p), "2026-11-14T20:00:00.000Z");

    await rejects(createOrder(db, providers, AWA, { product: "pro", months: 1, method: "crypto" }, NOW), "failed-precondition");
  });

  test("paiement d'une autre commande ou incomplet : rien n'est débloqué", async () => {
    const a = await createOrder(db, providers, AWA, { product: "elite", months: 1, method: "mobile", phone: "077123456" }, NOW);
    mobile.pay(a.orderId, { orderId: "autre-commande" });
    assert.equal(await confirmOrder(db, providers, a.orderId, NOW), "failed");
    const b = await createOrder(db, providers, AWA, { product: "elite", months: 1, method: "mobile", phone: "077123456" }, NOW);
    mobile.pay(b.orderId, { amount: 100 });
    assert.equal(await confirmOrder(db, providers, b.orderId, NOW), "failed");
    assert.equal((await profile()).tier, undefined);
  });

  test("on ne vérifie que ses propres commandes", async () => {
    const { orderId } = await createOrder(db, providers, AWA, { product: "pro", months: 1, method: "crypto" }, NOW);
    await rejects(confirmOrder(db, providers, orderId, NOW, "moussa"), "permission-denied");
    await rejects(confirmOrder(db, providers, "inconnue1234", NOW, "awa"), "not-found");
  });

  test("prestataire injoignable : commande en échec, message clair", async () => {
    mobile.failStart = true;
    await rejects(createOrder(db, providers, AWA, { product: "pro", months: 1, method: "mobile", phone: "077123456" }, NOW), "unavailable");
    const orders = await db.collection("orders").get();
    assert.equal(orders.docs[0].get("status"), "failed");
  });

  test("notification d'un prestataire : vérification puis accès", async () => {
    const { orderId } = await createOrder(db, providers, AWA, { product: "pro", months: 1, method: "mobile", phone: "077123456" }, NOW);
    const raw = Buffer.from("");
    assert.equal(await handleNotification(db, providers, "ebilling", raw, {}, {}, NOW), null);
    assert.equal(await handleNotification(db, providers, "inconnu", raw, {}, { order: orderId }, NOW), null);
    // Notification sans paiement réel chez le prestataire : rien.
    assert.equal(await handleNotification(db, providers, "ebilling", raw, {}, { order: orderId }, NOW), "pending");
    mobile.pay(orderId);
    assert.equal(await handleNotification(db, providers, "ebilling", raw, {}, { order: orderId }, NOW), "paid");
    assert.equal((await profile()).tier, "pro");
  });

  test("un abonnement Play échu ne retire pas une formule payée sur le site", async () => {
    await db.doc("purchases/play1").set({ uid: "awa", token: "jeton-play-1" });
    await db.doc("users/awa").set({
      tier: "elite",
      tierUntil: Timestamp.fromDate(new Date("2026-10-15T10:00:00Z")),
      subscription: "play1",
    });
    const play: PlayApi = {
      subscription: async () => ({
        productId: "buteo_elite",
        state: "SUBSCRIPTION_STATE_EXPIRED",
        expiry: new Date("2026-10-14T08:00:00Z"),
        acknowledged: true,
      }),
      acknowledgeSubscription: async () => undefined,
      product: async () => ({ purchased: false }),
    };
    await refreshSubscriptions(db, play, NOW);
    assert.equal((await profile()).tier, "elite");
  });
});

/** Réseau simulé pour les vrais clients des prestataires. */
function fakeFetch(replies: Record<string, unknown>) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const fn = (async (url: string, init?: RequestInit) => {
    calls.push({ url, init });
    const key = Object.keys(replies).find((k) => url.endsWith(k));
    if (!key) return new Response("introuvable", { status: 404 });
    return new Response(JSON.stringify(replies[key]), { status: 200 });
  }) as unknown as typeof fetch;
  return { fn, calls };
}

const ORDER: Order = {
  id: "cmd123456789",
  uid: "awa",
  product: "elite",
  months: 1,
  rubric: null,
  method: "crypto",
  amount: 10.49,
  currency: "EUR",
  label: "Buteo · formule Élite 1 mois",
  email: "awa@example.com",
  phone: null,
};

describe("NOWPayments", () => {
  test("facture, notification signée, puis état du paiement", async () => {
    const net = fakeFetch({
      "/invoice": { id: 4521, invoice_url: "https://nowpayments.io/payment/?iid=4521" },
      "/payment/998877": { payment_status: "finished", order_id: ORDER.id, price_amount: 10.49 },
    });
    const np = new NowPayments("cle", "secret-ipn", "https://notif.example/nowpayments", "https://buteo.example", undefined, net.fn);
    const checkout = await np.start(ORDER);
    assert.equal(checkout.url, "https://nowpayments.io/payment/?iid=4521");
    assert.equal(checkout.reference, "invoice:4521");
    const sent = JSON.parse(String(net.calls[0].init?.body));
    assert.equal(sent.price_amount, 10.49);
    assert.equal(sent.price_currency, "eur");
    assert.equal(sent.order_id, ORDER.id);
    assert.equal(sent.ipn_callback_url, "https://notif.example/nowpayments");

    assert.deepEqual(await np.status("invoice:4521"), { state: "pending" });
    const body = { payment_status: "finished", payment_id: 998877, order_id: ORDER.id, price_amount: 10.49 };
    const raw = Buffer.from(JSON.stringify(body));
    assert.equal(np.notification(raw, { "x-nowpayments-sig": "faux" }, body), null);
    const sig = nowPaymentsSignature(body, "secret-ipn");
    assert.deepEqual(np.notification(raw, { "x-nowpayments-sig": sig }, body), { orderId: ORDER.id, reference: "payment:998877" });
    assert.deepEqual(await np.status("payment:998877"), { state: "paid", orderId: ORDER.id, amount: 10.49 });
  });

  test("la signature ne dépend pas de l'ordre des champs", () => {
    const a = nowPaymentsSignature({ b: 1, a: { d: 2, c: 3 } }, "s");
    const b = nowPaymentsSignature({ a: { c: 3, d: 2 }, b: 1 }, "s");
    assert.equal(a, b);
  });
});

describe("E-Billing", () => {
  test("facture, page de paiement et état", async () => {
    const net = fakeFetch({
      "/e_bills": { e_bill: { bill_id: "5550001234" } },
      "/e_bills/5550001234": { e_bill: { state: "paid", external_reference: ORDER.id, amount: 6900 } },
    });
    const eb = new EBilling("marchand", "cle-partagee", "https://buteo.example", "https://api.example/v1/merchant", "https://portail.example", net.fn);
    const checkout = await eb.start({ ...ORDER, method: "mobile", amount: 6900, currency: "XAF", phone: "077123456" });
    assert.equal(checkout.url, "https://portail.example");
    assert.deepEqual(checkout.fields, { invoice_number: "5550001234", eb_callbackurl: `https://buteo.example/?commande=${ORDER.id}` });
    const headers = net.calls[0].init?.headers as Record<string, string>;
    assert.equal(headers.Authorization, `Basic ${Buffer.from("marchand:cle-partagee").toString("base64")}`);
    const sent = JSON.parse(String(net.calls[0].init?.body));
    assert.equal(sent.external_reference, ORDER.id);
    assert.equal(sent.payer_msisdn, "077123456");
    assert.deepEqual(await eb.status("5550001234"), { state: "paid", orderId: ORDER.id, amount: 6900 });
    assert.deepEqual(eb.notification(Buffer.from(""), {}, { reference: ORDER.id, billingid: "5550001234" }), {
      orderId: ORDER.id,
      reference: "5550001234",
    });
  });
});
