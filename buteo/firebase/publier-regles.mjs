// Publie firestore.rules sur le projet Firebase, par l'API Firebase Rules du
// SDK Admin : le compte de service « firebase-adminsdk » suffit tel quel, alors
// que « firebase deploy » demande en plus le rôle Service Usage.
//
//   GOOGLE_APPLICATION_CREDENTIALS=compte.json node publier-regles.mjs <projet>
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

// firebase-admin est installé avec les fonctions serveur.
const require = createRequire(new URL("./functions/package.json", import.meta.url));
const { applicationDefault, initializeApp } = require("firebase-admin/app");
const { getSecurityRules } = require("firebase-admin/security-rules");

const projectId = process.argv[2];
if (!projectId) {
  console.error("Usage : node publier-regles.mjs <projet>");
  process.exit(1);
}

const source = readFileSync(new URL("./firestore.rules", import.meta.url), "utf8");
initializeApp({ credential: applicationDefault(), projectId });
const ruleset = await getSecurityRules().releaseFirestoreRulesetFromSource(source);
console.log(`Règles Firestore publiées sur ${projectId} (${ruleset.name}).`);
