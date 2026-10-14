/**
 * Prestataires de paiement du site : NOWPayments (crypto) et E-Billing (Mobile Money).
 *
 * Chacun est activé seulement si ses identifiants sont configurés (variables
 * d'environnement des fonctions, écrites au déploiement depuis les secrets
 * GitHub : voir le README de Buteo).
 */

import { createHmac, timingSafeEqual } from "node:crypto";

import { Checkout, Notification, Order, PaymentProvider, PaymentState, Providers } from "./orders";

type Fetch = typeof fetch;
type Headers = Record<string, string | string[] | undefined>;

const header = (headers: Headers, name: string) => {
  const v = headers[name.toLowerCase()];
  return Array.isArray(v) ? v[0] : v;
};

async function json(res: Response, what: string): Promise<Record<string, unknown>> {
  const text = await res.text();
  if (!res.ok) throw new Error(`${what} : HTTP ${res.status} ${text.slice(0, 200)}`);
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch {
    throw new Error(`${what} : réponse illisible`);
  }
}

// --- NOWPayments ------------------------------------------------------------------

/** Clés triées à tous les niveaux, comme NOWPayments les signe. */
function sorted(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sorted);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value as object)
        .sort()
        .map((k) => [k, sorted((value as Record<string, unknown>)[k])]),
    );
  }
  return value;
}

export function nowPaymentsSignature(body: unknown, secret: string): string {
  return createHmac("sha512", secret).update(JSON.stringify(sorted(body))).digest("hex");
}

const NOWPAYMENTS_STATES: Record<string, PaymentState> = {
  waiting: "pending",
  confirming: "pending",
  partially_paid: "pending",
  confirmed: "paid",
  sending: "paid",
  finished: "paid",
  failed: "failed",
  refunded: "failed",
  expired: "failed",
};

export class NowPayments implements PaymentProvider {
  readonly name = "nowpayments";

  constructor(
    private readonly apiKey: string,
    private readonly ipnSecret: string,
    private readonly notifyUrl: string,
    private readonly siteUrl: string,
    private readonly apiUrl = "https://api.nowpayments.io/v1",
    private readonly fetchFn: Fetch = fetch,
  ) {}

  async start(order: Order): Promise<Checkout> {
    const back = `${this.siteUrl}/?commande=${order.id}`;
    const res = await this.fetchFn(`${this.apiUrl}/invoice`, {
      method: "POST",
      headers: { "x-api-key": this.apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        price_amount: order.amount,
        price_currency: order.currency.toLowerCase(),
        order_id: order.id,
        order_description: order.label,
        ipn_callback_url: this.notifyUrl,
        success_url: back,
        cancel_url: back,
      }),
    });
    const data = await json(res, "NOWPayments");
    if (!data.invoice_url) throw new Error("NOWPayments : facture sans lien de paiement");
    return { reference: `invoice:${data.id}`, url: String(data.invoice_url) };
  }

  async status(reference: string) {
    // Tant que le client n'a pas choisi sa monnaie, seule la facture existe.
    if (!reference.startsWith("payment:")) return { state: "pending" as const };
    const res = await this.fetchFn(`${this.apiUrl}/payment/${reference.slice(8)}`, {
      headers: { "x-api-key": this.apiKey },
    });
    const data = await json(res, "NOWPayments");
    return {
      state: NOWPAYMENTS_STATES[String(data.payment_status)] ?? "pending",
      orderId: data.order_id ? String(data.order_id) : undefined,
      amount: typeof data.price_amount === "number" ? data.price_amount : undefined,
    };
  }

  notification(_raw: Buffer, headers: Headers, body: unknown): Notification | null {
    const given = header(headers, "x-nowpayments-sig");
    if (!given || !body || typeof body !== "object") return null;
    const expected = Buffer.from(nowPaymentsSignature(body, this.ipnSecret));
    const received = Buffer.from(given);
    if (expected.length !== received.length || !timingSafeEqual(expected, received)) return null;
    const b = body as Record<string, unknown>;
    if (!b.order_id || !b.payment_id) return null;
    return { orderId: String(b.order_id), reference: `payment:${b.payment_id}` };
  }
}

// --- E-Billing (Digitech Africa) --------------------------------------------------

const EBILLING_STATES: Record<string, PaymentState> = {
  paid: "paid",
  processed: "paid",
  failed: "failed",
  cancelled: "failed",
  expired: "failed",
};

export class EBilling implements PaymentProvider {
  readonly name = "ebilling";

  constructor(
    private readonly username: string,
    private readonly sharedKey: string,
    private readonly siteUrl: string,
    private readonly apiUrl = "https://lab.billing-easy.net/api/v1/merchant",
    private readonly portalUrl = "https://test.billing-easy.net",
    private readonly fetchFn: Fetch = fetch,
  ) {}

  private get auth() {
    return `Basic ${Buffer.from(`${this.username}:${this.sharedKey}`).toString("base64")}`;
  }

  async start(order: Order): Promise<Checkout> {
    const res = await this.fetchFn(`${this.apiUrl}/e_bills`, {
      method: "POST",
      headers: { Authorization: this.auth, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        amount: order.amount,
        payer_msisdn: order.phone,
        payer_email: order.email ?? undefined,
        short_description: order.label,
        external_reference: order.id,
        expiry_period: 60, // minutes
      }),
    });
    const data = await json(res, "E-Billing");
    const bill = (data.e_bill ?? data) as Record<string, unknown>;
    if (!bill.bill_id) throw new Error("E-Billing : facture sans numéro");
    // Le client choisit Airtel Money ou Moov Money sur la page d'E-Billing, puis revient sur le site.
    return {
      reference: String(bill.bill_id),
      url: this.portalUrl,
      fields: { invoice_number: String(bill.bill_id), eb_callbackurl: `${this.siteUrl}/?commande=${order.id}` },
    };
  }

  async status(reference: string) {
    const res = await this.fetchFn(`${this.apiUrl}/e_bills/${encodeURIComponent(reference)}`, {
      headers: { Authorization: this.auth, Accept: "application/json" },
    });
    const data = await json(res, "E-Billing");
    const bill = (data.e_bill ?? data) as Record<string, unknown>;
    return {
      state: EBILLING_STATES[String(bill.state)] ?? "pending",
      orderId: bill.external_reference ? String(bill.external_reference) : undefined,
      amount: bill.amount !== undefined ? Number(bill.amount) : undefined,
    };
  }

  notification(_raw: Buffer, _headers: Headers, body: unknown): Notification | null {
    // E-Billing envoie la référence de la commande et le numéro de sa facture ; le
    // paiement est ensuite vérifié auprès de son API (la notification n'est pas signée).
    const b = (body ?? {}) as Record<string, unknown>;
    const orderId = b.reference ?? b.external_reference;
    const billId = b.billingid ?? b.bill_id;
    if (!orderId || !billId) return null;
    return { orderId: String(orderId), reference: String(billId) };
  }
}

// --- Configuration ----------------------------------------------------------------

/** Prestataires configurés dans l'environnement des fonctions. */
export function providersFromEnv(env: NodeJS.ProcessEnv = process.env): Providers {
  const project = env.GCLOUD_PROJECT ?? "buteo-bbec5";
  const siteUrl = env.SITE_URL || `https://${project}.web.app`;
  const notifyBase = `https://europe-west1-${project}.cloudfunctions.net/notificationPaiement`;
  const providers: Providers = {};
  if (env.NOWPAYMENTS_API_KEY && env.NOWPAYMENTS_IPN_SECRET) {
    providers.crypto = new NowPayments(
      env.NOWPAYMENTS_API_KEY,
      env.NOWPAYMENTS_IPN_SECRET,
      `${notifyBase}/nowpayments`,
      siteUrl,
      env.NOWPAYMENTS_API_URL || undefined,
    );
  }
  if (env.EBILLING_USERNAME && env.EBILLING_SHARED_KEY) {
    providers.mobile = new EBilling(
      env.EBILLING_USERNAME,
      env.EBILLING_SHARED_KEY,
      siteUrl,
      env.EBILLING_API_URL || undefined,
      env.EBILLING_PORTAL_URL || undefined,
    );
  }
  return providers;
}
