import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, Timestamp } from 'firebase/firestore';
import { readFileSync } from 'node:fs';

const env = await initializeTestEnvironment({
  projectId: 'buteo-test2',
  firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8089 },
});
const tomorrow = Timestamp.fromMillis(Date.now() + 86400e3);
const past = Timestamp.fromMillis(Date.now() - 3600e3);
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'picks/2026-10-14_selection'), { date: '2026-10-14', rubric: 'selection', tier: 'free', publicAfter: past });
  await setDoc(doc(db, 'picks/2026-10-14_c10'), { date: '2026-10-14', rubric: 'c10', tier: 'pro', publicAfter: tomorrow });
  await setDoc(doc(db, 'picks/2026-10-14_score'), { date: '2026-10-14', rubric: 'score', tier: 'elite', publicAfter: tomorrow });
  await setDoc(doc(db, 'picks/2026-10-13_score'), { date: '2026-10-13', rubric: 'score', tier: 'elite', publicAfter: past });
  await setDoc(doc(db, 'users/pro'), { tier: 'pro' });
  await setDoc(doc(db, 'users/elite'), { tier: 'elite' });
  await setDoc(doc(db, 'users/coupon'), { coupons: ['2026-10-14|score'] });
  await setDoc(doc(db, 'stats/summary'), { days: {} });
});
const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = env.unauthenticatedContext().firestore();
const free = as('gratuit');
let ok = 0;
const check = async (name, p) => { await p; ok++; console.log('OK  ', name); };

await check('prono gratuit lisible sans compte', assertSucceeds(getDoc(doc(anon, 'picks/2026-10-14_selection'))));
await check('statistiques publiques', assertSucceeds(getDoc(doc(anon, 'stats/summary'))));
await check('document absent : demande autorisée', assertSucceeds(getDoc(doc(anon, 'picks/2026-10-14_tennis'))));
await check('VIP du jour sans compte : refusé', assertFails(getDoc(doc(anon, 'picks/2026-10-14_c10'))));
await check('VIP du jour, compte gratuit : refusé', assertFails(getDoc(doc(free, 'picks/2026-10-14_c10'))));
await check('rubrique Pro, formule Pro : lisible', assertSucceeds(getDoc(doc(as('pro'), 'picks/2026-10-14_c10'))));
await check('rubrique Élite, formule Pro : refusé', assertFails(getDoc(doc(as('pro'), 'picks/2026-10-14_score'))));
await check('rubrique Élite, formule Élite : lisible', assertSucceeds(getDoc(doc(as('elite'), 'picks/2026-10-14_score'))));
await check('rubrique Pro, formule Élite : lisible', assertSucceeds(getDoc(doc(as('elite'), 'picks/2026-10-14_c10'))));
await check('coupon du jour pour cette rubrique : lisible', assertSucceeds(getDoc(doc(as('coupon'), 'picks/2026-10-14_score'))));
await check('coupon d’une autre rubrique : refusé', assertFails(getDoc(doc(as('coupon'), 'picks/2026-10-14_c10'))));
await check('VIP de la veille : public', assertSucceeds(getDoc(doc(anon, 'picks/2026-10-13_score'))));
await check('écrire un prono depuis l’app : refusé', assertFails(setDoc(doc(as('elite'), 'picks/2026-10-14_score'), { tier: 'free' })));
await check('écrire les statistiques : refusé', assertFails(setDoc(doc(as('elite'), 'stats/summary'), { days: {} })));
await check('se donner un coupon : refusé', assertFails(setDoc(doc(free, 'users/gratuit'), { coupons: ['2026-10-14|score'] })));
await env.cleanup();
console.log(`\n${ok} vérifications réussies`);
