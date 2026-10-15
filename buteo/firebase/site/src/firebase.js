// Connexion au projet Firebase de Buteo, partagée par les pages du site.
// Identifiants publics (comme dans l'app) : la sécurité repose sur les règles et le serveur.

import { initializeApp } from "firebase/app";
import { GoogleAuthProvider, getAuth, signInWithPopup, signInWithRedirect } from "firebase/auth";
import { getFirestore } from "firebase/firestore";
import { getFunctions, httpsCallable } from "firebase/functions";

export const app = initializeApp({
  apiKey: "AIzaSyAiho6O_-xrO2rVs_D_b-8pOmViRTajyjU",
  authDomain: "buteo-bbec5.firebaseapp.com",
  projectId: "buteo-bbec5",
  storageBucket: "buteo-bbec5.firebasestorage.app",
  messagingSenderId: "823242305441",
});
export const auth = getAuth(app);
auth.languageCode = "fr";
export const db = getFirestore(app);
const functions = getFunctions(app, "europe-west1");

/** Fonction serveur appelable (europe-west1). */
export const call = (name, data) => httpsCallable(functions, name)(data).then((r) => r.data);

const google = new GoogleAuthProvider();

/** Connexion Google : fenêtre, ou redirection si le navigateur la bloque. */
export async function signInWithGoogle() {
  try {
    await signInWithPopup(auth, google);
  } catch (e) {
    if (["auth/popup-blocked", "auth/operation-not-supported-in-this-environment"].includes(e.code)) {
      await signInWithRedirect(auth, google);
    } else if (e.code !== "auth/popup-closed-by-user" && e.code !== "auth/cancelled-popup-request") {
      throw e;
    }
  }
}

export const fcfa = (n) => `${Number(n).toLocaleString("fr-FR").replace(/[  ]/g, " ")} FCFA`;
