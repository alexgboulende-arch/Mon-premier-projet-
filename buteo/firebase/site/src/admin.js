// Espace d'administration de Buteo : chiffres, accès offerts, modération du
// concours, message à tous. Les fonctions serveur vérifient que l'adresse
// connectée figure dans BUTEO_ADMINS ; cette page ne fait qu'afficher.

import { onAuthStateChanged, signOut } from "firebase/auth";
import { doc, getDoc } from "firebase/firestore";

import { auth, call, db, fcfa, signInWithGoogle } from "./firebase.js";

const $ = (id) => document.getElementById(id);
const METHODS = { mobile: "Mobile Money", crypto: "Crypto", admin: "Offerts" };

function weekId(d) {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
  const week = Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

function show(id, text, ok = true) {
  $(id).textContent = text;
  $(id).style.color = ok ? "var(--win)" : "var(--loss)";
}

const errorText = (e) => e?.message || "Une erreur est survenue.";

function figure(label, value, note = "") {
  const box = document.createElement("div");
  box.className = "figure";
  box.innerHTML = `<span class="muted small"></span><strong></strong><small class="muted"></small>`;
  box.children[0].textContent = label;
  box.children[1].textContent = value;
  box.children[2].textContent = note;
  return box;
}

async function loadFigures() {
  const box = $("chiffres");
  try {
    const f = await call("adminChiffres");
    box.replaceChildren(figure("Utilisateurs", String(f.users)));
    const sales = Object.entries(f.sales);
    if (sales.length === 0) box.append(figure("Ventes (30 jours)", "0"));
    for (const [method, s] of sales) {
      const amount = s.currency === "EUR" ? `${s.amount.toLocaleString("fr-FR")} €` : fcfa(s.amount);
      box.append(figure(`Ventes ${METHODS[method] ?? method} (30 j)`, String(s.count), amount));
    }
    const rate = f.picks7days.count ? Math.round((100 * f.picks7days.won) / f.picks7days.count) : null;
    box.append(figure("Pronos (7 jours)", rate === null ? "—" : `${rate} %`, `${f.picks7days.won}/${f.picks7days.count} gagnés`));
    const run = f.engine.lastRun ? new Date(f.engine.lastRun).toLocaleString("fr-FR", { timeZone: "UTC" }) + " GMT" : "—";
    box.append(figure("Moteur", f.engine.lastPublish ?? "—", `offre ${f.engine.plan ?? "?"} · ${run}`));
  } catch (e) {
    box.replaceChildren(Object.assign(document.createElement("p"), { className: "error", textContent: errorText(e) }));
  }
}

async function loadLeaderboard() {
  const box = $("classement");
  const snap = await getDoc(doc(db, "leaderboards", `week-${weekId(new Date())}`)).catch(() => null);
  const players = snap?.data()?.players ?? [];
  if (players.length === 0) {
    box.replaceChildren(Object.assign(document.createElement("p"), { className: "muted small", textContent: "Pas encore de classement cette semaine." }));
    return;
  }
  const list = document.createElement("ol");
  list.className = "board";
  for (const p of players.slice(0, 50)) {
    const row = document.createElement("li");
    row.innerHTML = `<span class="rank"></span><span class="who"></span><span class="pts"></span><button class="link small" type="button">Renommer</button><button class="link small danger" type="button">Exclure</button>`;
    row.children[0].textContent = p.rank;
    row.children[1].textContent = p.pseudo;
    row.children[2].textContent = `${p.points} pts`;
    row.children[3].onclick = async () => {
      const pseudo = prompt(`Nouveau pseudo pour « ${p.pseudo} » (3 à 20 caractères)`, "Joueur");
      if (!pseudo) return;
      await moderate({ uid: p.uid, pseudo }, `« ${p.pseudo} » renommé en « ${pseudo} ».`);
    };
    row.children[4].onclick = async () => {
      if (!confirm(`Exclure « ${p.pseudo} » du concours ?`)) return;
      await moderate({ uid: p.uid, excluded: true }, `« ${p.pseudo} » est exclu du concours.`);
    };
    list.append(row);
  }
  box.replaceChildren(list);
}

async function moderate(data, done) {
  try {
    await call("adminModerer", data);
    show("moderation-resultat", done);
    await loadLeaderboard();
  } catch (e) {
    show("moderation-resultat", errorText(e), false);
  }
}

$("acces-donner").onclick = async () => {
  const [product, value] = $("acces-offre").value.split(":");
  const data = { email: $("acces-email").value, product, ...(product === "coupon" ? { rubric: value } : { months: Number(value) }) };
  $("acces-donner").disabled = true;
  try {
    const r = await call("adminDonnerAcces", data);
    show(
      "acces-resultat",
      r.coupon
        ? `Coupon offert pour aujourd'hui (${r.coupon.split("|")[1]}).`
        : `Formule ${r.tier === "elite" ? "Élite" : "Pro"} active jusqu'au ${new Date(r.until).toLocaleDateString("fr-FR")}.`,
    );
    loadFigures();
  } catch (e) {
    show("acces-resultat", errorText(e), false);
  } finally {
    $("acces-donner").disabled = false;
  }
};

$("message-envoyer").onclick = async () => {
  const title = $("message-titre").value.trim();
  const body = $("message-texte").value.trim();
  if (!confirm(`Envoyer « ${title} » à tous les utilisateurs ?`)) return;
  $("message-envoyer").disabled = true;
  try {
    await call("adminMessage", { title, body });
    show("message-resultat", "Message envoyé.");
    $("message-titre").value = "";
    $("message-texte").value = "";
  } catch (e) {
    show("message-resultat", errorText(e), false);
  } finally {
    $("message-envoyer").disabled = false;
  }
};

$("rafraichir").onclick = () => {
  loadFigures();
  loadLeaderboard();
};
$("connexion").onclick = () => signInWithGoogle().catch((e) => show("porte-texte", errorText(e), false));
$("deconnexion").onclick = () => signOut(auth);

onAuthStateChanged(auth, async (user) => {
  $("espace").hidden = true;
  $("connexion").hidden = !!user;
  $("connecte-comme").hidden = !user;
  if (!user) return;
  $("connecte-comme").textContent = `Connecté : ${user.email}`;
  try {
    await call("adminChiffres");
  } catch (e) {
    show("porte-texte", e?.code === "functions/permission-denied" ? "Ce compte n'a pas accès à l'administration." : errorText(e), false);
    return;
  }
  $("porte-texte").textContent = "Bienvenue.";
  $("porte-texte").style.color = "";
  $("espace").hidden = false;
  loadFigures();
  loadLeaderboard();
});
