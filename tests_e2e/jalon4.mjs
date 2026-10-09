// Répétition automatique du JALON 4 : deux « appareils » (deux navigateurs isolés),
// synchronisation en temps réel, puis coupure et retour du réseau chez Alice.
//
// Prérequis (voir README.md, « Tests ») :
//   supabase start && supabase db reset          # base locale + comptes de démo
//   cd app && flutter build web --dart-define-from-file=../env.json
//   cd build/web && python3 -m http.server 8765  # (dans un autre terminal)
//   cd tests_e2e && npm install && npx playwright install firefox
//   node jalon4.mjs captures                     # captures d'écran dans tests_e2e/captures/
import { mkdirSync } from 'node:fs';
import { firefox } from 'playwright';
const sortie = process.argv[2] ?? 'captures';
mkdirSync(sortie, { recursive: true });
const navigateur = await firefox.launch();
let etape = 0;
const capture = async (page, nom) => page.screenshot({ path: `${sortie}/e2e-${String(++etape).padStart(2, '0')}-${nom}.png` });
const ok = (m) => console.log('✓', m);
// Flutter web expose ses widgets via l'arbre d'accessibilité : on cherche le
// texte visible OU libellé d'accessibilité (cases à cocher, tuiles de liste…)
const voir = (page, texte) => page.getByText(texte).or(page.getByLabel(texte)).first();

async function appareil(email) {
  const contexte = await navigateur.newContext({ viewport: { width: 400, height: 860 } });
  const page = await contexte.newPage();
  page.on('console', m => { if (/rror|xception/.test(m.text())) console.log(`[${email}] console :`, m.text().slice(0, 300)); });
  page.on('pageerror', e => console.log(`[${email}] erreur page :`, e.message));
  await page.goto('http://127.0.0.1:8765/');
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 30000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
  await page.getByLabel('Adresse e-mail').fill(email);
  await page.getByLabel('Mot de passe').fill('motdepasse123');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await voir(page, 'Coloc des Alpes').waitFor({ timeout: 40000 });
  return { contexte, page };
}

async function saisirArticle(page, texte) {
  const champ = page.getByLabel('Ajouter un article', { exact: true });
  await champ.click();
  await page.keyboard.type(texte);
  await page.keyboard.press('Enter');
}
const onglet = (page, nom) => page.getByRole('tab', { name: new RegExp(nom + '$') }).click();

const A = await appareil('alice@colloc.test');
ok('Alice connectée, redirigée vers sa coloc');
await voir(A.page, 'Courses Carrefour').waitFor();
await capture(A.page, 'alice-depenses');
const B = await appareil('bob@colloc.test');
ok('Bob connecté sur un second « appareil »');

// --- Courses en temps réel
await onglet(A.page, 'Courses'); await onglet(B.page, 'Courses');
await voir(A.page, 'À acheter').waitFor(); await voir(B.page, 'À acheter').waitFor();
await A.page.waitForTimeout(2000); // abonnements Realtime
await saisirArticle(A.page, 'Chocolat E2E');
await voir(B.page, 'Chocolat E2E').waitFor({ timeout: 10000 });
ok('Bob voit en direct l\'article ajouté par Alice');
await capture(B.page, 'bob-voit-article');

await B.page.getByRole('checkbox', { name: /Chocolat E2E/ }).click();
await voir(A.page, 'Coché par Bob').waitFor({ timeout: 10000 });
ok('Alice voit en direct que Bob l\'a coché');
await capture(A.page, 'alice-voit-coche');

// --- Chat en temps réel
await onglet(A.page, 'Chat'); await onglet(B.page, 'Chat');
await voir(A.page, 'Message de démonstration n° 80').waitFor({ timeout: 10000 });
await A.page.waitForTimeout(2000);
await A.page.getByLabel('Message').fill('Salut Bob, test du jalon 4 !');
await A.page.getByRole('button', { name: 'Envoyer', exact: true }).click();
await voir(B.page, 'Salut Bob, test du jalon 4 !').waitFor({ timeout: 10000 });
ok('Bob reçoit le message d\'Alice en direct');
await capture(B.page, 'bob-recoit-message');

// --- Coupure réseau chez Alice
await onglet(A.page, 'Courses'); await voir(A.page, 'À acheter').waitFor();
await A.contexte.setOffline(true);
await saisirArticle(A.page, 'Article hors ligne');
await voir(A.page, /Hors connexion/).waitFor({ timeout: 20000 });
ok('Alice hors ligne : bandeau affiché, pas de plantage');
await capture(A.page, 'alice-hors-ligne');

await onglet(B.page, 'Courses'); await voir(B.page, 'À acheter').waitFor();
await saisirArticle(B.page, 'Ajouté pendant la coupure');
await voir(B.page, 'Ajouté pendant la coupure').waitFor();

await A.contexte.setOffline(false);
await voir(A.page, /Hors connexion/).waitFor({ state: 'detached', timeout: 30000 });
ok('Réseau revenu : bandeau retiré');
await voir(A.page, 'Ajouté pendant la coupure').waitFor({ timeout: 30000 });
ok('Alice resynchronisée : elle voit l\'article ajouté par Bob pendant la coupure');
await capture(A.page, 'alice-resynchronisee');

await navigateur.close();
