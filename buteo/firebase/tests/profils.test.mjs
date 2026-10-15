import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';
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

await check('créer son profil (favoris, alertes)', assertSucceeds(setDoc(doc(awa, 'users/awa'), { favorites: ['foot:Lyon'], notifications: { drop: true }, updatedAt: serverTimestamp() }, { merge: true })));
await check('mettre à jour ses favoris', assertSucceeds(setDoc(doc(awa, 'users/awa'), { favorites: ['foot:Lyon', 'basket:Lakers'] }, { merge: true })));
await check('lire son profil', assertSucceeds(getDoc(doc(awa, 'users/awa'))));
await check("se donner la formule Élite à la création : refusé", assertFails(setDoc(doc(moussa, 'users/moussa'), { tier: 'elite' })));
await check("se donner la formule Élite ensuite : refusé", assertFails(updateDoc(doc(awa, 'users/awa'), { tier: 'elite' })));
await check("prolonger soi-même sa formule : refusé", assertFails(setDoc(doc(awa, 'users/awa'), { tierUntil: new Date(2030, 0, 1) }, { merge: true })));
await check("s'ajouter des coupons : refusé", assertFails(setDoc(doc(awa, 'users/awa'), { coupons: ['score'] }, { merge: true })));
await check("lire le profil d'un autre : refusé", assertFails(getDoc(doc(moussa, 'users/awa'))));
await check("modifier le profil d'un autre : refusé", assertFails(setDoc(doc(moussa, 'users/awa'), { favorites: [] }, { merge: true })));
await check('sans compte, lire un profil : refusé', assertFails(getDoc(doc(anon, 'users/awa'))));
await check('écrire ailleurs que dans son profil : refusé', assertFails(setDoc(doc(awa, 'pronos/demain'), { x: 1 })));

// Le serveur (règles contournées) attribue la formule ; l'utilisateur peut encore modifier ses favoris.
await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'users/awa'), { tier: 'pro' }, { merge: true }));
await check('modifier ses favoris quand le serveur a écrit la formule', assertSucceeds(setDoc(doc(awa, 'users/awa'), { favorites: ['foot:Raja'] }, { merge: true })));
await check('changer la formule écrite par le serveur : refusé', assertFails(setDoc(doc(awa, 'users/awa'), { tier: 'elite' }, { merge: true })));
await check('supprimer son profil', assertSucceeds(deleteDoc(doc(awa, 'users/awa'))));

// Journal de paris : privé.
const bet = { id: 'p1', day: '2026-10-15', label: 'Benfica – Celtic · Victoire Benfica', odds: 1.25, stake: 2000, status: 'pending', updatedAt: '2026-10-15T08:00:00Z' };
await check('noter un pari dans son journal', assertSucceeds(setDoc(doc(awa, 'users/awa/journal/p1'), bet)));
await check('relire son journal', assertSucceeds(getDoc(doc(awa, 'users/awa/journal/p1'))));
await check("lire le journal d'un autre : refusé", assertFails(getDoc(doc(moussa, 'users/awa/journal/p1'))));
await check("écrire dans le journal d'un autre : refusé", assertFails(setDoc(doc(moussa, 'users/awa/journal/p2'), { ...bet, id: 'p2' })));
await check('mise négative : refusé', assertFails(setDoc(doc(awa, 'users/awa/journal/p3'), { ...bet, id: 'p3', stake: -5 })));
await check('champ inconnu : refusé', assertFails(setDoc(doc(awa, 'users/awa/journal/p4'), { ...bet, id: 'p4', tier: 'elite' })));
await check('effacer un pari', assertSucceeds(deleteDoc(doc(awa, 'users/awa/journal/p1'))));

// Commandes du site : écrites par le serveur, lisibles seulement par leur auteur.
await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'orders/cmd1'), { uid: 'awa', status: 'pending', amount: 500 }));
await check('suivre sa commande', assertSucceeds(getDoc(doc(awa, 'orders/cmd1'))));
await check("lire la commande d'un autre : refusé", assertFails(getDoc(doc(moussa, 'orders/cmd1'))));
await check('sans compte, lire une commande : refusé', assertFails(getDoc(doc(anon, 'orders/cmd1'))));
await check('marquer soi-même sa commande payée : refusé', assertFails(updateDoc(doc(awa, 'orders/cmd1'), { status: 'paid' })));
await check('créer une commande soi-même : refusé', assertFails(setDoc(doc(awa, 'orders/cmd2'), { uid: 'awa', status: 'paid' })));

await env.cleanup();
console.log(`\n${ok} vérifications réussies`);
