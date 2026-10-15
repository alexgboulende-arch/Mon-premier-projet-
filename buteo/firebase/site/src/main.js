// Site de paiement de Buteo : formules Pro et Élite, coupon du jour.
// Connexion Google (même compte que l'app), commande créée par le serveur,
// paiement chez E-Billing (Mobile Money) ou NOWPayments (crypto), puis suivi
// de la commande jusqu'à l'accès débloqué dans l'app.

import { onAuthStateChanged, signOut } from "firebase/auth";
import { doc, onSnapshot } from "firebase/firestore";

import { auth, call, db, fcfa, signInWithGoogle } from "./firebase.js";

// Prix affichés (le serveur fixe le prix réel de chaque commande).
const PRICES = { pro: { 1: 2900, 3: 7500, 6: 13900 }, elite: { 1: 6900, 3: 17900, 6: 32900 }, coupon: 500 };
const EUROS = { pro: { 1: "4,49", 3: "11,49", 6: "20,99" }, elite: { 1: "10,49", 3: "27,49", 6: "49,99" } };
const TIERS = { free: "gratuite", pro: "Pro", elite: "Élite" };
const RUBRICS = { score: "Score exact", htft: "Mi-temps / Fin", c5: "Combiné cote 5+", c10: "Combiné cote 10+", simples: "Simples VIP" };

const $ = (id) => document.getElementById(id);
const day = (d) => d.toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" });

let methods = { mobile: null, crypto: null };
const months = { pro: 1, elite: 1 };
let choice = null;
let unwatchProfile = null;
let unwatchOrder = null;
let followed = null;

// --- Offres --------------------------------------------------------------------------

for (const card of document.querySelectorAll(".offer")) {
  const product = card.dataset.product;
  const box = card.querySelector(".durations");
  if (box) {
    for (const m of [1, 3, 6]) {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "duration";
      b.setAttribute("role", "radio");
      b.setAttribute("aria-checked", String(m === 1));
      b.innerHTML = `${m} mois<strong>${fcfa(PRICES[product][m])}</strong>`;
      b.onclick = () => {
        months[product] = m;
        for (const other of box.children) other.setAttribute("aria-checked", String(other === b));
      };
      box.append(b);
    }
  }
  card.querySelector(".choose").onclick = () => {
    choice =
      product === "coupon"
        ? { product, rubric: $("rubrique").value }
        : { product, months: months[product] };
    showPayment();
  };
}

function label(c) {
  return c.product === "coupon"
    ? `Coupon « ${RUBRICS[c.rubric]} » · ${fcfa(PRICES.coupon)}`
    : `Formule ${TIERS[c.product]} ${c.months} mois · ${fcfa(PRICES[c.product][c.months])}`;
}

// --- Paiement ------------------------------------------------------------------------

function showPayment() {
  $("offres").hidden = true;
  $("paiement").hidden = false;
  $("erreur").textContent = "";
  $("recap").textContent = label(choice);
  const allowed = { mobile: !!methods.mobile, crypto: !!methods.crypto && choice.product !== "coupon" };
  for (const input of document.querySelectorAll('input[name="moyen"]')) {
    input.disabled = !allowed[input.value];
    input.closest(".method").classList.toggle("off", input.disabled);
  }
  const first = document.querySelector('input[name="moyen"]:not(:disabled)');
  if (first) first.checked = true;
  updateMethod();
  window.scrollTo({ top: 0 });
}

function selectedMethod() {
  const input = document.querySelector('input[name="moyen"]:checked:not(:disabled)');
  return input ? input.value : null;
}

function updateMethod() {
  const method = selectedMethod();
  $("champ-numero").hidden = method !== "mobile";
  $("payer").disabled = !method;
  if (!method) {
    $("info-moyen").textContent = "Le paiement en ligne arrive très bientôt.";
    $("payer").textContent = "Bientôt disponible";
  } else if (method === "mobile") {
    $("info-moyen").textContent =
      "Tu choisiras Airtel Money ou Moov Money sur la page de paiement E-Billing, puis tu valideras avec ton code secret.";
    $("payer").textContent = `Payer ${fcfa(choice.product === "coupon" ? PRICES.coupon : PRICES[choice.product][choice.months])}`;
  } else {
    $("info-moyen").textContent = "Tu choisiras ta cryptomonnaie sur la page NOWPayments. Le prix est fixé en euros.";
    $("payer").textContent = `Payer ${EUROS[choice.product][choice.months]} € en crypto`;
  }
  if (choice.product === "coupon" && methods.crypto) {
    $("info-moyen").textContent += " Le coupon se paie uniquement par Mobile Money.";
  }
}

for (const input of document.querySelectorAll('input[name="moyen"]')) input.onchange = updateMethod;

$("retour").onclick = () => {
  $("paiement").hidden = true;
  $("offres").hidden = false;
};

$("payer").onclick = async () => {
  const method = selectedMethod();
  if (!method) return;
  $("payer").disabled = true;
  $("erreur").textContent = "";
  try {
    const data = { ...choice, method, phone: method === "mobile" ? $("numero").value : undefined };
    const { orderId, checkout } = await call("creerCommande", data);
    history.replaceState(null, "", `?commande=${orderId}`);
    goTo(checkout);
  } catch (e) {
    $("erreur").textContent = message(e);
    $("payer").disabled = false;
  }
};

/** Page du prestataire (formulaire POST pour E-Billing, lien pour NOWPayments). */
function goTo(checkout) {
  if (!checkout.fields) {
    location.href = checkout.url;
    return;
  }
  const form = document.createElement("form");
  form.method = "POST";
  form.action = checkout.url;
  for (const [name, value] of Object.entries(checkout.fields)) {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.value = value;
    form.append(input);
  }
  document.body.append(form);
  form.submit();
}

function message(e) {
  const code = String(e?.code ?? "");
  if (code.endsWith("unavailable") || code.endsWith("internal") || code.endsWith("not-found")) {
    return e.message && !/^(internal|not-found|unavailable)$/i.test(e.message)
      ? e.message
      : "Le paiement est momentanément indisponible. Réessaie dans un instant.";
  }
  return e?.message || "Une erreur est survenue.";
}

// --- Suivi de la commande ----------------------------------------------------------------

function follow(orderId) {
  if (followed === orderId) return;
  followed = orderId;
  $("offres").hidden = true;
  $("paiement").hidden = true;
  $("suivi").hidden = false;
  showOrder("pending");
  unwatchOrder?.();
  unwatchOrder = onSnapshot(
    doc(db, "orders", orderId),
    (snap) => showOrder(snap.get("status") ?? "pending", snap.data()),
    () => showOrder("failed"),
  );
  // Si la notification du prestataire tarde, on vérifie nous-mêmes de temps en temps.
  let tries = 0;
  const check = () =>
    call("verifierCommande", { orderId })
      .then((r) => r.status === "pending" && ++tries < 15 && setTimeout(check, 20000))
      .catch(() => undefined);
  check();
}

function showOrder(status, order) {
  $("suivi-attente").hidden = status !== "pending";
  $("suivi-ok").hidden = status !== "paid";
  $("suivi-echec").hidden = status !== "failed";
  if (status === "paid" && order) {
    $("suivi-detail").textContent =
      order.product === "coupon"
        ? `Coupon « ${RUBRICS[order.rubric]} » actif aujourd'hui.`
        : `Formule ${TIERS[order.grantedTier ?? order.product]} active jusqu'au ${day(order.grantedUntil.toDate())}.`;
  }
}

$("verifier").onclick = async () => {
  $("verifier").disabled = true;
  try {
    await call("verifierCommande", { orderId: followed });
  } catch {
    // L'état affiché reste celui de la commande.
  }
  setTimeout(() => ($("verifier").disabled = false), 3000);
};

$("recommencer").onclick = () => {
  unwatchOrder?.();
  followed = null;
  history.replaceState(null, "", location.pathname);
  $("suivi").hidden = true;
  $("offres").hidden = false;
};

// --- Compte ----------------------------------------------------------------------------

$("connexion").onclick = () => signInWithGoogle().catch(() => undefined);
$("deconnexion").onclick = () => signOut(auth);

onAuthStateChanged(auth, (user) => {
  $("deconnecte").hidden = !!user;
  $("connecte").hidden = !user;
  unwatchProfile?.();
  if (!user) {
    for (const id of ["offres", "paiement", "suivi"]) $(id).hidden = true;
    return;
  }
  $("email").textContent = user.email ?? user.displayName ?? "";
  unwatchProfile = onSnapshot(
    doc(db, "users", user.uid),
    (snap) => {
      const p = snap.data() ?? {};
      const until = p.tierUntil?.toDate?.();
      const active = p.tier && p.tier !== "free" && until && until > new Date();
      $("formule").textContent = active
        ? `Ta formule : ${TIERS[p.tier]}, jusqu'au ${day(until)}`
        : "Ta formule : gratuite";
    },
    () => ($("formule").textContent = ""),
  );
  const orderId = new URLSearchParams(location.search).get("commande");
  if (orderId) follow(orderId);
  else if ($("paiement").hidden && $("suivi").hidden) $("offres").hidden = false;
});

call("moyensDePaiement")
  .then((m) => (methods = m))
  .catch(() => undefined);
