import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, setDoc, deleteDoc, where, Timestamp } from 'firebase/firestore';
import { readFileSync } from 'node:fs';

const env = await initializeTestEnvironment({
  projectId: 'buteo-test',
  firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8089 },
});
const awa = env.authenticatedContext('awa').firestore();
const moussa = env.authenticatedContext('moussa').firestore();
const anon = env.unauthenticatedContext().firestore();
let ok = 0;
const check = async (name, p) => { await p; ok++; console.log('OK  ', name); };

const inAnHour = Timestamp.fromMillis(Date.now() + 3600e3);
const anHourAgo = Timestamp.fromMillis(Date.now() - 3600e3);
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'contests/2026-10-15'), { matches: [], kickoffs: { '101': inAnHour, '102': anHourAgo } });
  await setDoc(doc(db, 'leaderboards/week-2026-W42'), { players: [] });
  await setDoc(doc(db, 'contestPlayers/awa'), { pseudo: 'Awa' });
  await setDoc(doc(db, 'contestScores/2026-10-15'), { players: {} });
});
const pick = (db, uid, fixtureId, extra = {}) =>
  setDoc(doc(db, `contests/2026-10-15/picks/${uid}_${fixtureId}`), { uid, fixtureId, choice: '1', pseudo: 'Awa Koné', ...extra });

await check('sans compte, voir le concours et les classements', Promise.all([
  assertSucceeds(getDoc(doc(anon, 'contests/2026-10-15'))),
  assertSucceeds(getDoc(doc(anon, 'leaderboards/week-2026-W42'))),
  assertSucceeds(getDoc(doc(anon, 'contestPlayers/awa'))),
  assertSucceeds(getDoc(doc(anon, 'contestScores/2026-10-15'))),
]));
await check('jouer avant le coup d\'envoi', assertSucceeds(pick(awa, 'awa', 101)));
await check('changer d\'avis avant le coup d\'envoi', assertSucceeds(pick(awa, 'awa', 101, { choice: 'X' })));
await check('jouer après le coup d\'envoi : refusé', assertFails(pick(awa, 'awa', 102)));
await check('jouer un match hors concours : refusé', assertFails(pick(awa, 'awa', 999)));
await check('jouer pour un autre : refusé', assertFails(pick(moussa, 'awa', 101)));
await check('choix inconnu : refusé', assertFails(pick(awa, 'awa', 101, { choice: '3' })));
await check('pseudo trop court : refusé', assertFails(pick(awa, 'awa', 101, { pseudo: 'A' })));
await check('pseudo avec des liens : refusé', assertFails(pick(awa, 'awa', 101, { pseudo: 'www.paris<script>' })));
await check('se donner des points : refusé', assertFails(pick(awa, 'awa', 101, { points: 500 })));
await check('sans compte, jouer : refusé', assertFails(pick(anon, 'awa', 101)));
await check('lire ses propres pronos', assertSucceeds(getDocs(query(collection(awa, 'contests/2026-10-15/picks'), where('uid', '==', 'awa')))));
await check('lire les pronos des autres : refusé', assertFails(getDocs(query(collection(moussa, 'contests/2026-10-15/picks'), where('uid', '==', 'awa')))));
await check('effacer son prono : refusé', assertFails(deleteDoc(doc(awa, 'contests/2026-10-15/picks/awa_101'))));
await check('écrire un classement : refusé', assertFails(setDoc(doc(awa, 'leaderboards/week-2026-W42'), { players: [] })));
await check('modifier le concours : refusé', assertFails(setDoc(doc(awa, 'contests/2026-10-15'), { kickoffs: {} })));

await env.cleanup();
console.log(`\n${ok} vérifications réussies`);
