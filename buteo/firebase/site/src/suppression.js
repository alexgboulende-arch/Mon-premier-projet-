// Suppression du compte depuis le site (lien demandé par Google Play) :
// même effet que « Profil → Supprimer mon compte » dans l'app.

import { deleteUser, onAuthStateChanged, reauthenticateWithPopup, GoogleAuthProvider, signOut } from "firebase/auth";
import { collection, deleteDoc, doc, getDocs, serverTimestamp, setDoc } from "firebase/firestore";

import { auth, db, signInWithGoogle } from "./firebase.js";

const $ = (id) => document.getElementById(id);

function show(text, ok) {
  $("resultat").textContent = text;
  $("resultat").className = ok ? "status" : "error";
}

async function removeAccount(user) {
  // 1. Le moteur retirera le compte du concours (pronos, points, classements).
  await setDoc(doc(db, "deletionRequests", user.uid), { uid: user.uid, requestedAt: serverTimestamp() });
  // 2. Journal de paris et profil.
  const journal = await getDocs(collection(db, "users", user.uid, "journal"));
  await Promise.all(journal.docs.map((d) => deleteDoc(d.ref)));
  await deleteDoc(doc(db, "users", user.uid));
  // 3. Le compte lui-même (Google demande parfois de se reconnecter juste avant).
  try {
    await deleteUser(user);
  } catch (e) {
    if (e.code !== "auth/requires-recent-login") throw e;
    await reauthenticateWithPopup(user, new GoogleAuthProvider());
    await deleteUser(user);
  }
}

$("connexion").onclick = () => signInWithGoogle().catch((e) => show(e.message, false));
$("changer").onclick = () => signOut(auth);

$("supprimer").onclick = async () => {
  const user = auth.currentUser;
  if (!user || !confirm("Supprimer définitivement ton compte Buteo ?")) return;
  $("supprimer").disabled = true;
  try {
    await removeAccount(user);
    $("etape-confirmation").hidden = true;
    $("etape-connexion").hidden = true;
    show("Ton compte Buteo est supprimé. Tu peux aussi désinstaller l'app pour effacer les réglages du téléphone.", true);
  } catch (e) {
    show(`La suppression n'a pas abouti : ${e.message}`, false);
    $("supprimer").disabled = false;
  }
};

onAuthStateChanged(auth, (user) => {
  $("etape-connexion").hidden = !!user;
  $("etape-confirmation").hidden = !user;
  if (user) $("email").textContent = user.email ?? user.uid;
});
