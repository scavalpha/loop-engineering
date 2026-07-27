// v6.60 CAPTURE CONFINEE du critique produit. Remplace `npx playwright screenshot` (CLI)
// qui ne lit PAS playwright.config.ts et lancait donc chromium GPU-ON: c'etait le dernier
// chromium non confine du loop (cause identifiee des 3 reboots machine sans trace,
// cf v6.59). Ici on lance chromium EXPLICITEMENT avec la chaine GPU coupee.
//
// Ajout produit (revue proprietaire 13/07): PASSE D'INTERACTION avant capture. Scroller
// tout en bas puis remonter, puis capturer. Un ecran qui blanchit apres scroll (bug reel
// vu sur un ecran de detail) apparait BLANC sur la capture: le juge vision le voit, sans
// assertion supplementaire. Angle mort "interaction dans le temps" partiellement couvert.
//
// v6.75 SESSION AUTHENTIFIEE (demande pilote 17/07: les routes protegees etaient
// capturees comme la page de connexion, le juge vision voyait "ecran identique" et le
// critic semait des cartes aveugles sur le coeur du produit). 4e argument optionnel
// "cle=jeton": injecte localStorage[cle]=jeton via addInitScript AVANT tout script de
// l'app (meme mecanisme que ouvrirSession des e2e), la garde de session passe, l'ecran
// reel est capture. Generique: la loi ne connait ni la cle ni la forme du jeton (contrat
// EYE_SESSION_KEY / EYE_SESSION_TOKEN_CMD dans stack.sh). Sans 4e arg = comportement v6.60.
//
// v6.76 (pilote: session en sessionStorage, pas localStorage): 5e arg optionnel
// 'local'|'session' choisit le store (defaut 'local', retro-compatible). La loi reste
// agnostique: le contrat (EYE_SESSION_STORAGE) decide.
//
// Usage: node critic-shot.mjs <url> <out.png> <WxH> [cle=jeton] [local|session]  (cwd = FRONT_DIR)
import { createRequire } from 'node:module';
const require = createRequire(process.cwd() + '/');
const { chromium } = require('playwright');

const [url, out, size, session, storage] = process.argv.slice(2);
if (!url || !out || !size) { console.error('usage: critic-shot.mjs <url> <out> <WxH> [cle=jeton] [local|session]'); process.exit(2); }
const [w, h] = size.split(/[x,]/).map(Number);
// 4e arg "cle=jeton": tout apres le premier '=' est le jeton (un JWT ou un JSON, peut
// contenir des '='). 5e arg: store cible (sessionStorage si 'session', sinon localStorage).
let sessKey = '', sessTok = '';
if (session) { const i = session.indexOf('='); if (i > 0) { sessKey = session.slice(0, i); sessTok = session.slice(i + 1); } }
const sessStore = storage === 'session' ? 'session' : 'local';

const browser = await chromium.launch({
  headless: true,
  args: [
    '--disable-gpu',
    '--disable-software-rasterizer',
    '--disable-gpu-compositing',
    '--disable-accelerated-2d-canvas',
    '--in-process-gpu',
    '--use-gl=swiftshader',
    '--no-sandbox',
  ],
});
try {
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  // Session posee AVANT navigation (addInitScript s'execute avant les scripts de la page):
  // la garde de session lit deja le jeton au demarrage de l'app, comme apres une connexion.
  if (sessKey && sessTok) {
    await page.addInitScript(
      ([k, v, s]) => (s === 'session' ? sessionStorage : localStorage).setItem(k, v),
      [sessKey, sessTok, sessStore],
    );
  }
  await page.goto(url, { waitUntil: 'networkidle', timeout: 45000 }).catch(() => {});
  // Garde anti-faux-ecran (pilote point c): si une session etait fournie mais que l'app
  // a redirige vers la connexion, la capture ne montre PAS l'ecran demande. Echouer
  // explicitement plutot que livrer une page de login que le juge vision lira comme l'ecran.
  if (sessKey && sessTok) {
    const here = page.url();
    if (/\/(login|connexion)(\b|\/|\?|$)/i.test(here) && !/\/(login|connexion)(\b|\/|\?|$)/i.test(url)) {
      console.error(`[critic-shot] session refusee: ${url} a redirige vers ${here} (jeton invalide/expire?)`);
      await browser.close(); process.exit(3);
    }
  }
  // passe d'interaction: bas puis haut, avec le temps de re-rendre
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(400);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(400);
  await page.screenshot({ path: out, fullPage: true });
} finally {
  await browser.close();
}
