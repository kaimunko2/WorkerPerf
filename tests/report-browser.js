// Aufruf: node tests/report-browser.js <Ordner aus tests/New-TestReports.ps1> [--only <Pruefung,Pruefung,...>] [--scheme light|dark]
// Ohne Optionen laufen alle Pruefungen: die meisten in beiden Farbschemata des Systems, einige nur im hellen. Die letzte
// Zeile ist immer "browser checks passed: <n>".
// --only nennt Pruefungen beim Namen ihrer Funktion (beim Arbeiten an einem Teil der Seite). Laeuft dabei keine Pruefung
// (eine nur einmal laufende zusammen mit --scheme dark), endet der Aufruf mit einer Zeile dazu und einem Fehlercode.
// --scheme laesst nur ein Farbschema laufen: "--scheme light" und "--scheme dark" sind zusammen der ganze Lauf in zwei Teilen
// (die Pruefungen fuer nur ein Schema laufen im hellen Teil), ihre Zahlen ergeben zusammen die des ganzen Laufs.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const assert = require('assert');
let checks = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); checks++; };
const hhmm = (ms, offMin) => new Date(ms + offMin * 60000).toISOString().substr(11, 5);

// ---------- colours ----------
// A colour as the browser computes it ("rgb(r, g, b)"), as "#rrggbb" or as [r, g, b] (0-255): its three channels.
const rgbOf = (c) => Array.isArray(c) ? c.slice(0, 3) : c.trim().startsWith('#') ? [1, 3, 5].map((i) => parseInt(c.trim().substr(i, 2), 16)) : c.match(/[\d.]+/g).slice(0, 3).map(Number);
const toLinear = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
const fromLinear = (v) => { v = Math.min(1, Math.max(0, v)); return 255 * (v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055); };
// contrast of two colours after WCAG 2 (relative luminance)
const luminance = (c) => { const [r, g, b] = rgbOf(c).map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
const contrast = (a, b) => { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
// CIELAB (D65) of an sRGB colour
function labOf(c) {
  const [r, g, b] = rgbOf(c).map(toLinear), f = (t) => t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116;
  const x = f((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047), y = f(0.2126729 * r + 0.7151522 * g + 0.0721750 * b), z = f((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883);
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
}
// colour difference CIEDE2000 of two CIELAB colours [L, a, b] (Sharma, Wu, Dalal 2005; kL = kC = kH = 1)
function deltaE2000([L1, a1, b1], [L2, a2, b2]) {
  const rad = Math.PI / 180, pow7 = (v) => v ** 7, C1 = Math.hypot(a1, b1), C2 = Math.hypot(a2, b2), Cm = (C1 + C2) / 2;
  const G = 0.5 * (1 - Math.sqrt(pow7(Cm) / (pow7(Cm) + pow7(25)))), a1p = (1 + G) * a1, a2p = (1 + G) * a2, C1p = Math.hypot(a1p, b1), C2p = Math.hypot(a2p, b2);
  const hue = (a, b) => { if (a === 0 && b === 0) return 0; const h = Math.atan2(b, a) / rad; return h < 0 ? h + 360 : h; }, h1p = hue(a1p, b1), h2p = hue(a2p, b2), both = C1p * C2p !== 0;
  let dh = 0; if (both) { dh = h2p - h1p; if (dh > 180) dh -= 360; else if (dh < -180) dh += 360; }
  const dL = L2 - L1, dC = C2p - C1p, dH = 2 * Math.sqrt(C1p * C2p) * Math.sin(dh / 2 * rad), Lm = (L1 + L2) / 2, Cmp = (C1p + C2p) / 2;
  let hm = h1p + h2p; if (both) hm = Math.abs(h1p - h2p) <= 180 ? hm / 2 : (hm < 360 ? hm + 360 : hm - 360) / 2;
  const T = 1 - 0.17 * Math.cos((hm - 30) * rad) + 0.24 * Math.cos(2 * hm * rad) + 0.32 * Math.cos((3 * hm + 6) * rad) - 0.20 * Math.cos((4 * hm - 63) * rad);
  const dTheta = 30 * Math.exp(-(((hm - 275) / 25) ** 2)), RC = 2 * Math.sqrt(pow7(Cmp) / (pow7(Cmp) + pow7(25)));
  const SL = 1 + 0.015 * (Lm - 50) ** 2 / Math.sqrt(20 + (Lm - 50) ** 2), SC = 1 + 0.045 * Cmp, SH = 1 + 0.015 * Cmp * T, RT = -Math.sin(2 * dTheta * rad) * RC;
  return Math.sqrt((dL / SL) ** 2 + (dC / SC) ** 2 + (dH / SH) ** 2 + RT * (dC / SC) * (dH / SH));
}
const colourDiff = (c1, c2) => deltaE2000(labOf(c1), labOf(c2));
// Colour vision deficiencies after Machado, Oliveira, Fernandes 2009, severity 1.0: matrices on linear RGB
const CVD = {
  protan: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
  deutan: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
  tritan: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]
};
const cvdLinear = (type, lin) => CVD[type].map((row) => row[0] * lin[0] + row[1] * lin[1] + row[2] * lin[2]);
// the colour as a person with that deficiency sees it, as [r, g, b] (0-255, clamped to the sRGB gamut)
const simulateCvd = (type, c) => cvdLinear(type, rgbOf(c).map(toLinear)).map(fromLinear);
// The series colours of a chart can be told apart (Task 11): every pair differs by at least 12 (CIEDE2000) for normal
// vision and by at least 6 after a simulated protanopia, deuteranopia and tritanopia; every colour has a contrast of at least
// 3:1 to the chart ground. Returns the smallest values and whether they hold.
function paletteCheck(cols, bg) {
  const out = { normal: Infinity, protan: Infinity, deutan: Infinity, tritan: Infinity, contrast: Infinity, worst: {} };
  const seen = { normal: cols, protan: cols.map((c) => simulateCvd('protan', c)), deutan: cols.map((c) => simulateCvd('deutan', c)), tritan: cols.map((c) => simulateCvd('tritan', c)) };
  for (const k of Object.keys(seen)) for (let i = 0; i < cols.length; i++) for (let j = i + 1; j < cols.length; j++) {
    const d = colourDiff(seen[k][i], seen[k][j]); if (d < out[k]) { out[k] = d; out.worst[k] = `--s${i + 1}/--s${j + 1}`; }
  }
  for (const c of cols) out.contrast = Math.min(out.contrast, contrast(c, bg));
  out.ok = cols.length === 8 && cols.every((c) => /^#[0-9a-f]{6}$|^rgb/i.test(c)) && out.normal >= 12 && out.protan >= 6 && out.deutan >= 6 && out.tritan >= 6 && out.contrast >= 3;
  return out;
}
const paletteOk = (cols, bg) => paletteCheck(cols, bg).ok;
// The colour functions against published values before they judge the page: the 34 test pairs of Sharma, Wu, Dalal (2005,
// table 1: L, a, b of both colours and their CIEDE2000), the first row of Machado's matrix for protanopia, severity 1.0
// (0.152286, 1.052583, -0.204868), and the WCAG contrast of black on white (21:1) and of #767676 on white (4.54:1).
const SHARMA = [
  [50, 2.6772, -79.7751, 50, 0, -82.7485, 2.0425], [50, 3.1571, -77.2803, 50, 0, -82.7485, 2.8615], [50, 2.8361, -74.02, 50, 0, -82.7485, 3.4412],
  [50, -1.3802, -84.2814, 50, 0, -82.7485, 1], [50, -1.1848, -84.8006, 50, 0, -82.7485, 1], [50, -0.9009, -85.5211, 50, 0, -82.7485, 1],
  [50, 0, 0, 50, -1, 2, 2.3669], [50, -1, 2, 50, 0, 0, 2.3669], [50, 2.49, -0.001, 50, -2.49, 0.0009, 7.1792], [50, 2.49, -0.001, 50, -2.49, 0.001, 7.1792],
  [50, 2.49, -0.001, 50, -2.49, 0.0011, 7.2195], [50, 2.49, -0.001, 50, -2.49, 0.0012, 7.2195], [50, -0.001, 2.49, 50, 0.0009, -2.49, 4.8045],
  [50, -0.001, 2.49, 50, 0.001, -2.49, 4.8045], [50, -0.001, 2.49, 50, 0.0011, -2.49, 4.7461], [50, 2.5, 0, 50, 0, -2.5, 4.3065],
  [50, 2.5, 0, 73, 25, -18, 27.1492], [50, 2.5, 0, 61, -5, 29, 22.8977], [50, 2.5, 0, 56, -27, -3, 31.903], [50, 2.5, 0, 58, 24, 15, 19.4535],
  [50, 2.5, 0, 50, 3.1736, 0.5854, 1], [50, 2.5, 0, 50, 3.2972, 0, 1], [50, 2.5, 0, 50, 1.8634, 0.5757, 1], [50, 2.5, 0, 50, 3.2592, 0.335, 1],
  [60.2574, -34.0099, 36.2677, 60.4626, -34.1751, 39.4387, 1.2644], [63.0109, -31.0961, -5.8663, 62.8187, -29.7946, -4.0864, 1.263],
  [61.2901, 3.7196, -5.3901, 61.4292, 2.248, -4.962, 1.8731], [35.0831, -44.1164, 3.7933, 35.0232, -40.0716, 1.5901, 1.8645],
  [22.7233, 20.0904, -46.694, 23.0331, 14.973, -42.5619, 2.0373], [36.4612, 47.858, 18.3852, 36.2715, 50.5065, 21.2231, 1.4146],
  [90.8027, -2.0831, 1.441, 91.1528, -1.6435, 0.0447, 1.4441], [90.9257, -0.5406, -0.9208, 88.6381, -0.8985, -0.7239, 1.5381],
  [6.7747, -0.2908, -2.4247, 5.8714, -0.0985, -2.2286, 0.6377], [2.0776, 0.0795, -1.135, 0.9033, -0.0636, -0.5514, 0.9082]];
async function checkColourMath() {                                     // Farbabstand, Farbfehlsichtigkeit und Kontrast gegen veroeffentlichte Werte
  const off = SHARMA.map((p, k) => [k + 1, deltaE2000(p.slice(0, 3), p.slice(3, 6)), deltaE2000(p.slice(3, 6), p.slice(0, 3)), p[6]]).filter(([, d, r, want]) => Math.abs(d - want) > 5e-5 || Math.abs(r - want) > 5e-5);
  ok(off.length === 0, 'CIEDE2000: die 34 Testpaare von Sharma, Wu, Dalal (2005) auf vier Stellen, in beiden Richtungen: ' + off.map((o) => o.map((v) => +(+v).toFixed(4)).join('/')).join(' | '));
  // the matrix applied to the three primaries in linear RGB gives its columns: their first entries are the first row
  const row = [[1, 0, 0], [0, 1, 0], [0, 0, 1]].map((p) => cvdLinear('protan', p)[0]), want = [0.152286, 1.052583, -0.204868];
  ok(row.every((v, k) => Math.abs(v - want[k]) < 1e-6), 'Machado 2009, Protanopie, Schwere 1,0: erste Zeile der Matrix: ' + row.join(', '));
  // a grey stays a grey in all three (each row of the matrices sums to 1); red and green, which a protanope and a deuteranope
  // confuse, come closer; blue and green, which a tritanope confuses, come closer for him
  const grey = ['protan', 'deutan', 'tritan'].map((t) => simulateCvd(t, '#808080').map((v) => Math.round(v)).join(','));
  ok(grey.every((g) => g === '128,128,128'), 'Grau bleibt Grau bei jeder Farbfehlsichtigkeit: ' + grey.join(' | '));
  const near = (t, a, b) => colourDiff(simulateCvd(t, a), simulateCvd(t, b)) < colourDiff(a, b) / 2;
  ok(near('protan', '#d62728', '#2ca02c') && near('deutan', '#d62728', '#2ca02c') && near('tritan', '#1f77b4', '#2ca02c') && !near('tritan', '#d62728', '#2ca02c'), 'die Simulation verwechselt, was die jeweilige Farbfehlsichtigkeit verwechselt');
  ok(Math.abs(contrast('#000000', '#ffffff') - 21) < 1e-9 && Math.abs(contrast('rgb(118, 118, 118)', '#ffffff') - 4.54) < 0.01, 'WCAG-Kontrast: Schwarz auf Weiss 21:1, #767676 auf Weiss 4,54:1');
  ok(paletteOk(['#000000', '#0000ff', '#00ff00', '#ff0000', '#ffff00', '#ff00ff', '#00ffff', '#888888'], '#ffffff') === false && paletteCheck(['#2a78d6', '#2a78d7'], '#ffffff').normal < 1, 'die Pruefung der Palette lehnt ab, was die Schwellen verfehlt');
}
const paletteText = (p) => `ΔE2000 normal ${p.normal.toFixed(1)} (${p.worst.normal}), Protanopie ${p.protan.toFixed(1)} (${p.worst.protan}), Deuteranopie ${p.deutan.toFixed(1)} (${p.worst.deutan}), Tritanopie ${p.tritan.toFixed(1)} (${p.worst.tritan}), Kontrast ${p.contrast.toFixed(2)}:1`;

async function open(browser, file, scheme) {
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 }, colorScheme: scheme });
  page.errors = [];
  page.on('pageerror', (e) => page.errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') page.errors.push(m.text()); });
  page.requests = [];
  page.on('request', (r) => page.requests.push(r.url()));
  await page.goto('file://' + file);
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent));
  return { page, D };
}
// The report opens in the guided view. The expert view shows the incident column, the tiles and the charts always and the
// tables in the eight tabs of #xtabs.
// Switching tabs and views (P3-R55): click, then wait until the section the button leads to is visible. A click can miss its
// button while the page still scrolls smoothly to a chosen row: when the section is not visible after a second, the click is
// repeated once - unless the button itself is gone by then (the click worked: "In der Expertenansicht zeigen" leaves the view
// of its button), in which case the helper goes on waiting for the section.
async function showSection(page, button, section) {
  for (let again = 0; ; again++) {
    await page.click(button);
    try { await page.locator(section).waitFor({ state: 'visible', timeout: again ? 15000 : 1000 }); return; }
    catch (e) {
      if (again) throw e;
      if (!(await page.locator(button).isVisible())) { await page.locator(section).waitFor({ state: 'visible', timeout: 15000 }); return; }
    }
  }
}
const showExpert = (page) => showSection(page, '#viewSwitch button[data-view=expert]', '#expert');
const showGuided = (page) => showSection(page, '#viewSwitch button[data-view=guided]', '#guided');
// a tab of the tables of the expert view (the view is shown first where the page stands in the guided one)
async function showTab(page, name) {
  if (await page.evaluate(() => window.WP.view) !== 'expert') await showExpert(page);
  await showSection(page, `#xtabs button[data-tab=${name}]`, '#xt-' + name);
}
const ivExpert = (page) => showSection(page, '#ivExpert', '#expert');                   // "In der Expertenansicht zeigen"
const TABS = ['sollist', 'sessions', 'apps', 'procs', 'quality', 'events', 'print', 'before'];
async function openExpert(browser, file, scheme) {
  const r = await open(browser, file, scheme);
  await showExpert(r.page);
  return r;
}

async function checkGuided(browser, dir, scheme) {                  // gefuehrter Bericht: Lagebild und Karten
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.evaluate(() => document.body.dataset.view) === 'guided' && await page.locator('#guided').isVisible() && !(await page.locator('#expert').isVisible()), 'oeffnet in der gefuehrten Ansicht');
  ok(await page.locator('#band').getAttribute('data-state') === D.lagebild.state, 'Bandfarbe nach Zustand');
  ok((await page.locator('#bandState').innerText()).includes(D.lagebild.word) && (await page.locator('#bandSentence').innerText()) === D.lagebild.sentence, 'Zustand als Symbol und Wort, Satz');
  for (const k of ['bottlenecks', 'delays', 'events', 'chronic']) ok((await page.locator(`#kpis .kpi[data-kpi="${k}"] .num`).innerText()) === String(D.lagebild.kpis[k]), 'Kennzahl ' + k);
  const box = await page.locator('#openTop').boundingBox();
  ok(box && box.y + box.height <= 900, 'Handlungsbedarf und erster Klick ohne Scrollen sichtbar');
  ok(await page.locator('#cards .card.inc').count() === D.cards.length, 'zehn Karten');
  ok(await page.locator('#cards .card.inc').first().getAttribute('data-id') === String(D.order[0]), 'wichtigster Vorfall zuerst');
  const first = D.incidents.find((i) => i.id === D.order[0]);
  const card = page.locator(`#cards .card.inc[data-id="${first.id}"]`);
  ok((await card.locator('.card-title').innerText()) === first.guide.title && (await card.locator('.card-first').innerText()).includes(first.guide.checks[0].text), 'Karte mit Titel und erstem Schritt');
  ok((await card.locator('.card-short').innerText()) === first.guide.short && await card.locator('.card-open').count() === 1 && await card.locator('.card-copy').count() === 1, 'Kuerzel und Knoepfe');
  ok(await page.locator('#more > .group').count() === D.more.length, 'uebrige Vorfaelle als kompakte Liste');
  ok(await page.locator('#beforeG .card.inc').count() === D.before.incidents.length, 'Vor der Messung mit denselben Karten');
  // the text of a folded area is not part of innerText: folded at first, one click on its heading shows it
  const folded = !(await page.locator('#qualityG').evaluate((d) => d.open));
  await page.click('#qualityG > summary');
  ok(folded && (await page.locator('#qualityG').innerText()).includes('WorkerPerf'), 'Messqualitaet eingeklappt erreichbar');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#band').getAttribute('data-state') === 'green' && (await n.page.locator('#bandSentence').innerText()) === 'Keine Störung erkannt.', 'kein Vorfall: gruenes Band');
  ok(await n.page.locator('#cards .card').count() === 0 && await n.page.locator('#openTop').count() === 0, 'kein Vorfall: keine Karten');
  await n.page.close();
  const r = await open(browser, path.join(dir, 'report-none-reported.html'), scheme);
  ok(await r.page.locator('#aroundReported svg path').count() > 0, 'kein Vorfall: Messwerte um die gemeldete Zeit');
  await r.page.close();
}

// relative brightness of the page ground: the appearance follows the view, not the colour scheme of the system
const pageLum = (page) => page.evaluate(() => { const c = getComputedStyle(document.body).backgroundColor.match(/[\d.]+/g).map(Number); return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255; });
const viewState = (page) => page.evaluate(() => [window.WP.view, document.body.dataset.view, [...document.querySelectorAll('#viewSwitch button')].map((b) => b.dataset.view + ':' + b.getAttribute('aria-pressed')).join(' ')].join(' | '));
const cardIds = (page, sel) => page.locator(sel).evaluateAll((c) => c.map((x) => Number(x.dataset.id)));
async function checkViews(browser, dir, scheme) {                   // zwei Ansichten, Umschalter, Kopfleiste
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await viewState(page) === 'guided | guided | guided:true expert:false', 'Umschalter und WP.view nennen die gefuehrte Ansicht: ' + await viewState(page));
  ok((await page.locator('header #viewSwitch button').allInnerTexts()).join('|') === 'Geführt|Experte', 'Umschalter in der Kopfleiste');
  ok(await pageLum(page) > 0.85, 'gefuehrte Ansicht hell, bei jedem Farbschema: ' + await pageLum(page));
  ok((await page.locator('header #title').innerText()).includes(D.meta.computer) && (await page.locator('header #subtitle').innerText()).length > 20, 'Kopfleiste mit Server und Zeitraum');
  ok(page.requests.length === 1 && page.requests[0].startsWith('file://'), 'keine nachgeladenen Inhalte: ' + page.requests.join(' '));
  await page.evaluate(() => window.scrollTo(0, 500));
  await showExpert(page);
  ok(await viewState(page) === 'expert | expert | guided:false expert:true', 'Umschalter und WP.view nennen die Expertenansicht: ' + await viewState(page));
  ok(await page.locator('#expert').isVisible() && !(await page.locator('#guided').isVisible()), 'Expertenansicht sichtbar, gefuehrte verborgen');
  ok(await pageLum(page) < 0.1, 'Expertenansicht dunkel, bei jedem Farbschema: ' + await pageLum(page));
  ok(await page.evaluate(() => getComputedStyle(document.documentElement).colorScheme) === 'dark', 'Expertenansicht: auch Rollbalken und Grund des Fensters dunkel (Schema am Wurzelelement)');
  ok(await page.locator('#expert #xtabs button[data-tab]').count() === 8 && await page.locator('#expert #rangeBar #rangeInfo').count() === 1 && await page.locator('#expert #xtables > section[role=tabpanel]').count() === 8, 'Expertenansicht mit Zeitraumleiste, Reiterleiste und acht Reitern');
  ok(await page.locator('#incList').isVisible() && await page.locator('#tiles').isVisible() && await page.locator('#charts').isVisible(), 'Expertenansicht: Vorfallsspalte, Kacheln und Diagramme stehen ohne Reiter da');
  ok(await page.locator('header').isVisible() && await page.locator('footer').isVisible() && (await page.locator('footer').innerText()).includes('Bericht erstellt am'), 'Kopfleiste und Fuss in beiden Ansichten');
  ok(await page.evaluate(() => window.scrollY) === 0, 'Expertenansicht beginnt oben');
  await page.evaluate(() => window.scrollTo(0, 700));
  const hb = await page.locator('header').boundingBox(), tb = await page.locator('#rangeBar').boundingBox(), cb = await page.locator('#incCol').boundingBox();
  ok(hb.y === 0 && Math.abs(tb.y - hb.height) <= 1, 'Kopfleiste oben fest, Zeitraumleiste direkt darunter: ' + JSON.stringify([hb, tb]));
  ok(cb.y >= tb.y + tb.height && cb.y <= tb.y + tb.height + 12 && cb.y + cb.height <= 900 && Math.abs(cb.width - 280) <= 1, 'Vorfallsspalte bleibt unter der Zeitraumleiste im Bild, 280 px breit: ' + JSON.stringify(cb));
  await page.evaluate(() => window.WP.showView('guided'));
  ok(await viewState(page) === 'guided | guided | guided:true expert:false' && await page.locator('#guided').isVisible() && await page.locator('#guided #timeline .mark').count() === D.incidents.length, 'WP.showView wechselt zurueck');
  ok(await page.evaluate(() => window.scrollY) === 500, 'die gefuehrte Ansicht steht wieder an ihrer Stelle');
  await page.evaluate(() => window.WP.showView('nichts'));
  ok(await viewState(page) === 'guided | guided | guided:true expert:false', 'unbekannte Ansicht aendert nichts');
  // "Oeffnen" leads to the incident view; from there "In der Expertenansicht zeigen" leads to the incident in the expert
  // view: its entry unfolded, the charts on its window
  const inView = async (id) => await page.evaluate(() => window.WP.view) === 'guided' && await page.locator(`#incident[data-id="${id}"]`).isVisible() && !(await page.locator('#expert').isVisible());
  const opened = async (list, id) => await page.evaluate(() => window.WP.view) === 'expert' && await page.locator(`${list} .inc[data-id="${id}"].selected`).isVisible();
  const leave = async () => { await showGuided(page); await page.click('#ivBack'); await page.waitForFunction(() => window.WP.incident === null && history.state === null); };
  ok(await page.locator('#incident').isHidden() && await page.locator('#incList .inc.selected').count() === 0 && await page.evaluate(() => window.WP.zoom === null), 'vor dem Oeffnen: keine Vorfallsansicht, kein Eintrag gewaehlt, kein Zeitraum');
  await page.click('#openTop');
  ok(await inView(D.lagebild.top), 'Wichtigsten Vorfall oeffnen: Vorfallsansicht');
  await ivExpert(page);
  ok(await opened('#incList', D.lagebild.top) && await page.evaluate(() => window.WP.zoom !== null), 'Wichtigsten Vorfall oeffnen');
  await leave();
  await page.click(`#cards .card.inc[data-id="${D.cards[2]}"] .card-open`);
  ok(await inView(D.cards[2]), 'Karte oeffnet ihren Vorfall: Vorfallsansicht');
  await ivExpert(page);
  ok(await opened('#incList', D.cards[2]), 'Karte oeffnet ihren Vorfall');
  await leave();
  await page.click(`#more .row[data-id="${D.more[0].ids[0]}"] .row-open`);
  ok(await inView(D.more[0].ids[0]), 'Zeile der weiteren Vorfaelle oeffnet ihren Vorfall: Vorfallsansicht');
  await ivExpert(page);
  ok(await opened('#incList', D.more[0].ids[0]), 'Zeile der weiteren Vorfaelle oeffnet ihren Vorfall');
  await leave();
  await page.click(`#beforeG .card.inc[data-id="${D.before.incidents[0].id}"] .card-open`);
  ok(await inView(D.before.incidents[0].id), 'Karte vor der Messung oeffnet ihren Vorfall: Vorfallsansicht');
  await ivExpert(page);
  ok(await opened('#before', D.before.incidents[0].id) && await page.locator('#xt-before').isVisible(), 'Karte vor der Messung oeffnet ihren Vorfall');
  ok(page.errors.length === 0, 'Skriptfehler Ansichten: ' + page.errors.join(' | '));
  await page.close();
}

async function checkCards(browser, dir, scheme) {                   // Karten, weitere Vorfaelle, Vor der Messung, eingeklappte Bereiche
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  const byId = new Map(D.incidents.concat(D.before.incidents).map((i) => [i.id, i])), word = (i) => i.severity >= 2 ? 'kritisch' : 'auffällig';
  ok((await cardIds(page, '#cards .card.inc')).join() === D.cards.join(), 'Karten in der Rangfolge');
  for (const id of D.cards) {
    const inc = byId.get(id), g = inc.guide, card = page.locator(`#cards .card.inc[data-id="${id}"]`), t = (c) => card.locator(c).innerText();
    ok(await t('.card-view') === g.userView && await t('.card-title') === g.title && await t('.card-impact') === g.impact && await t('.card-short') === g.short, 'Karte ' + id + ': Einordnung, Titel, Wirkung, Kuerzel');
    ok(await t('.card-cause') === inc.causeText && await card.locator('.card-cause').getAttribute('title') === inc.causeText, 'Karte ' + id + ': Verursacherzeile, voller Text im Titel');
    ok(await t('.card-first') === 'Erster Schritt: ' + g.checks[0].text, 'Karte ' + id + ': erster Schritt');
    ok((await t('.card-when')).startsWith(hhmm(inc.start, D.meta.offsetMin)), 'Karte ' + id + ': Uhrzeit: ' + await t('.card-when'));
    ok((await t('.status')).includes(word(inc)), 'Karte ' + id + ': Schwere als Symbol und Wort');
  }
  const line = await page.locator(`#cards .card.inc[data-id="${D.cards[0]}"] .card-cause`).evaluate((e) => [e.getBoundingClientRect().height, e.scrollWidth > e.clientWidth]);
  ok(line[0] <= 30 && line[1], 'lange Verursacherzeile auf eine Zeile gekuerzt: ' + line.join(' '));
  const boxes = await page.locator('#cards .card.inc').evaluateAll((c) => c.slice(0, 3).map((x) => { const r = x.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top), Math.round(r.height)]; }));
  ok(boxes[0][1] === boxes[1][1] && boxes[0][0] < boxes[1][0] && boxes[0][2] === boxes[1][2] && boxes[2][1] > boxes[0][1] && boxes[2][0] === boxes[0][0], 'Karten in zwei Spalten, in einer Zeile gleich hoch: ' + JSON.stringify(boxes));
  ok(await page.locator('#cards .card.inc a, #cards .card.inc[tabindex], #cards .card.inc[role]').count() === 0, 'die Karte selbst ist kein Link');
  await page.click(`#cards .card.inc[data-id="${D.cards[0]}"] .card-title`);
  ok(await page.evaluate(() => window.WP.view) === 'guided' && await page.locator('#incident').isHidden() && await page.locator('#cards').isVisible(), 'ein Klick auf die Karte neben den Knoepfen tut nichts');
  for (const g of D.more) {
    const inc = byId.get(g.ids[0]), row = page.locator(`#more > div.group .row[data-id="${inc.id}"]`), text = await row.innerText();
    ok(g.ids.length === 1 && text.includes(inc.guide.title) && text.includes(hhmm(inc.start, D.meta.offsetMin)) && text.includes(word(inc)) && await row.locator('.row-open').count() === 1, 'einzelner Vorfall als Zeile mit Schwere, Uhrzeit, Titel und Oeffnen: ' + text);
  }
  const bg = await page.locator('#beforeG').innerText(), rank = D.before.incidents.slice().sort((a, b) => a.rank - b.rank);
  ok(bg.includes('Vor der Messung') && bg.includes('Für diese Zeit liegen keine Messwerte vor.'), 'Vor der Messung mit Hinweis, gefuehrte Ansicht');
  ok((await cardIds(page, '#beforeG .card.inc')).join() === rank.map((i) => i.id).join(), 'Karten vor der Messung in ihrer Rangfolge');
  ok((await page.locator(`#beforeG .card.inc[data-id="${rank[0].id}"] .card-when`).innerText()).includes(ddmmyyyy(rank[0].events[0].t, rank[0].events[0].offsetMin)), 'Karte vor der Messung mit Datum');
  ok((await page.locator('#guided .card:has(#timeline) h3').innerText()) === 'Zeitleiste der Messung', 'Zeitleiste in einer Karte');
  ok((await page.locator('#openTop').innerText()) === 'Wichtigsten Vorfall öffnen' && (await page.locator('#copyAll').innerText()) === 'Zusammenfassung kopieren', 'Knoepfe im Band');
  ok(await page.locator('#anonSwitch').getAttribute('type') === 'checkbox' && (await page.locator('label:has(#anonSwitch)').innerText()).includes('ohne Namen'), 'Schalter ohne Namen');
  const lbl = (k) => page.locator(`#kpis .kpi[data-kpi="${k}"] .lbl`).innerText();
  ok(await page.locator('#kpis .kpi').count() === 5 && (await page.locator('#kpis .kpi[data-kpi="minutes"] .num').innerText()) === D.lagebild.kpis.minutes.toLocaleString('de-DE'), 'fuenf Kennzahlen, Minuten in deutscher Schreibweise');
  ok(await lbl('bottlenecks') === 'Engpässe auf dem Server' && await lbl('delays') === 'Verzögerungen von außen' && await lbl('events') === 'Abstürze und Fehler' && await lbl('chronic') === 'Dauerzustände' && await lbl('minutes') === 'Minuten mit spürbarer Störung', 'Beschriftung der Kennzahlen');
  ok(await page.locator('#hints').isHidden() && await page.locator('#aroundReported').isHidden(), 'ohne Hinweise keine Hinweiszeile; mit Vorfaellen keine Karte um die gemeldete Zeit');
  ok(!(await page.locator('#measured').evaluate((d) => d.open)) && !(await page.locator('#qualityG').evaluate((d) => d.open)), 'mit Vorfaellen sind beide Bereiche eingeklappt');
  await page.click('#measured > summary');
  const mt = await page.locator('#measured').innerText(), meas = D.sollIst.filter((r) => r.measured);
  ok(mt.includes('Was wurde gemessen, was nicht') && mt.includes(`Gemessen (${meas.length})`) && mt.includes(`Nicht gemessen (${D.sollIst.length - meas.length})`) && mt.includes(meas[0].label + ': Max'), 'gemessene und nicht gemessene Werte');
  ok(!mt.includes('Kein Vorfall') && !mt.includes('Keine Schwelle wurde überschritten') && !mt.includes('in der gesamten Messung im Soll'), 'mit Vorfaellen keine Aussage ohne Befund');
  await page.click('#qualityG > summary');
  const flat = (s) => s.replace(/\s+/g, ' ').trim(), qg = flat(await page.locator('#qualityG').innerText());
  await showTab(page, 'quality');
  ok(qg === flat(await page.locator('#quality').innerText()) && await page.locator('#qualityG table tbody tr').count() === await page.locator('#tSources tbody tr').count(), 'Messqualitaet mit denselben Inhalten wie in der Expertenansicht');
  ok(await page.evaluate(() => [...document.querySelectorAll('[id]')].map((e) => e.id).filter((id, k, a) => a.indexOf(id) !== k).length) === 0, 'keine Kennung doppelt');
  ok(page.errors.length === 0, 'Skriptfehler Karten: ' + page.errors.join(' | '));
  await page.close();
}

async function checkGuidedStates(browser, dir, scheme) {            // gefuehrte Ansicht: ohne Vorfall, Hinweise, nicht gemessen, Werte als Text
  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#kpis .kpi').count() === 5 && await n.page.locator('#copyAll').count() === 1 && await n.page.locator('#guided #timeline').isVisible(), 'kein Vorfall: Kennzahlen, Kopierknopf und Zeitleiste bleiben');
  ok(await n.page.locator('#cardsHead').isHidden() && await n.page.locator('#more').isHidden() && await n.page.locator('#beforeG').isHidden() && await n.page.locator('#aroundReported').isHidden() && await n.page.locator('#hints').isHidden(), 'kein Vorfall: keine leeren Bereiche');
  await n.page.close();
  const r = await open(browser, path.join(dir, 'report-none-reported.html'), scheme), rep = r.D.meta.focus.reportedMs, off = r.D.meta.offsetMin;
  const heads = await r.page.locator('#aroundReported .chartbox h3').allInnerTexts();
  ok(heads.length === 3 && heads[0].includes('CPU') && heads[1].includes('Arbeitsspeicher') && heads[2].includes('Eingabeverzögerung') && await r.page.locator('#aroundReported .chartbox svg').count() === 3, 'um die gemeldete Zeit: CPU, Arbeitsspeicher, Eingabeverzoegerung: ' + heads.join(' / '));
  const art = await r.page.locator('#aroundReported').innerText();
  ok(art.includes('Um die gemeldete Zeit') && art.includes(hhmm(rep, off)), 'Karte nennt die gemeldete Uhrzeit');
  const axis = await r.page.locator('#aroundReported .chartbox >> nth=0').locator('svg text.xaxis').allTextContents();
  ok(axis[0] === hhmm(rep - 900000, off) && axis[axis.length - 1] === hhmm(rep + 900000, off), 'Verlauf 15 min davor bis 15 min danach: ' + axis.join(' '));
  ok(await r.page.locator('#aroundReported svg .repmark').count() === 3, 'gemeldete Uhrzeit in den Diagrammen markiert');
  const drag = await r.page.locator('#aroundReported svg >> nth=0').boundingBox();
  await r.page.mouse.move(drag.x + drag.width * 0.3, drag.y + 60); await r.page.mouse.down(); await r.page.mouse.move(drag.x + drag.width * 0.6, drag.y + 60); await r.page.mouse.up();
  ok(await r.page.evaluate(() => window.WP.zoom === null), 'Ziehen in diesen Diagrammen stellt keinen Ausschnitt ein');
  ok(r.page.errors.length === 0, 'Skriptfehler um die gemeldete Zeit: ' + r.page.errors.join(' | '));
  await r.page.close();
  const f = await open(browser, path.join(dir, 'report-focus.html'), scheme);
  ok(f.D.meta.focus.reportedMs != null && await f.page.locator('#aroundReported').isHidden(), 'mit Vorfaellen keine Karte um die gemeldete Zeit');
  await f.page.close();
  // hints of the situation summary stand directly under the band, as delivered
  const s = await open(browser, path.join(dir, 'report-spike.html'), scheme);
  ok(s.D.lagebild.hints.length === 1 && (await s.page.locator('#hints .hint').allInnerTexts()).map((t) => t.replace(/^▲\s*/, '')).join('|') === s.D.lagebild.hints.join('|'), 'Hinweise wie geliefert');
  ok((await s.page.locator('#hints .hint .sym').first().innerText()) === '▲', 'Hinweis mit Symbol');
  const sb = await s.page.locator('#band').boundingBox(), sh = await s.page.locator('#hints').boundingBox(), st = await s.page.locator('#guided .card:has(#timeline)').boundingBox();
  ok(sh.y >= sb.y + sb.height && sh.y - sb.y - sb.height <= 30 && st.y >= sh.y + sh.height, 'Hinweise direkt unter dem Band, vor der Zeitleiste');
  ok(await s.page.locator('#cards .card').count() === 0 && await s.page.locator('#beforeG .card.inc').count() === s.D.before.incidents.length && await s.page.locator('#beforeG').isVisible(), 'kein Vorfall, aber Vorfaelle vor der Messung');
  await s.page.close();
  const m = await open(browser, path.join(dir, 'report-masked.html'), scheme);
  ok(m.D.copyAll.anonymous === null && await m.page.locator('#anonSwitch').count() === 0 && await m.page.locator('#copyAll').count() === 1, 'maskiert: kein Schalter ohne Namen');
  await m.page.close();
  // categories left out with -Skip: nothing of them reads as 0, as "keine" or as measured
  const e = await open(browser, path.join(dir, 'report-skip-ereignisse.html'), scheme), kpi = e.page.locator('#kpis .kpi[data-kpi="events"]');
  ok((await kpi.locator('.num').innerText()) === '–' && await kpi.locator('.notmeasured[data-place="events"]').isVisible(), 'ohne Ereignisse: Kennzahl nicht als 0, mit Hinweis');
  ok((await e.page.locator('#kpis .kpi[data-kpi="bottlenecks"] .num').innerText()) === String(e.D.lagebild.kpis.bottlenecks) && await e.page.locator('#kpis .notmeasured').count() === 1, 'ohne Ereignisse: die uebrigen Kennzahlen wie geliefert');
  ok((await e.page.locator('#hints').innerText()).includes(e.D.lagebild.hints[0]) && await e.page.locator('#guided #timeline .tl-row[data-group="skipped"] .notmeasured[data-place="events"]').isVisible(), 'ohne Ereignisse: Hinweis unter dem Band und in der Zeitleiste');
  const eb = await e.page.locator('#openTop').boundingBox();
  ok(eb && eb.y + eb.height <= 900, 'ohne Ereignisse: erster Knopf ohne Scrollen sichtbar: ' + JSON.stringify(eb));
  await e.page.close();
  const l = await open(browser, path.join(dir, 'report-skip-laufwerke.html'), scheme);
  ok(l.D.lagebild.kpis.delaysUnverified > 0 && (await l.page.locator('#kpis .kpi[data-kpi="delays"] .lbl').innerText()) === 'Verzögerungen ohne erkannten Engpass', 'ohne Laufwerke: Verzoegerungen ohne erkannten Engpass');
  const lt = await l.page.locator('#guided').innerText();
  ok(!lt.includes('von außen') && !lt.includes('ohne Engpass'), 'ohne Laufwerke: kein "von aussen" und kein "ohne Engpass" in der gefuehrten Ansicht');
  await l.page.close();
  // chronic states of the network paths form from the ICA values: without them the count 0 is no measured 0
  const ci = await open(browser, path.join(dir, 'report-skip-citrix.html'), scheme), ck = ci.page.locator('#kpis .kpi[data-kpi="chronic"]');
  ok(ci.D.lagebild.kpis.chronic === 0 && (await ck.locator('.num').innerText()) === '–' && await ck.locator('.notmeasured[data-place="citrix"]').isVisible() && (await ck.innerText()).includes('nicht gemessen') && (await ck.innerText()).includes(ci.D.skipped[0].text), 'ohne Citrix: die Kennzahl der Dauerzustaende ist keine 0, sie sagt "nicht gemessen" mit dem Grund');
  ok((await ci.page.locator('#kpis .kpi[data-kpi="events"] .num').innerText()) === String(ci.D.lagebild.kpis.events) && await ci.page.locator('#kpis .notmeasured').count() === 1, 'ohne Citrix: die uebrigen Kennzahlen wie geliefert');
  await ci.page.close();
  const cz = await open(browser, patched(dir, 'report-skip-citrix.html', 'report-skip-citrix-chronic.html', (J) => { J.lagebild.kpis.chronic = 2; }), scheme);
  ok((await cz.page.locator('#kpis .kpi[data-kpi="chronic"] .num').innerText()) === '2' && await cz.page.locator('#kpis .kpi[data-kpi="chronic"] .notmeasured').count() === 0, 'ohne Citrix mit gezaehlten Dauerzustaenden: die Zahl wie geliefert, ohne Hinweis');
  await cz.page.close();
  const p = await open(browser, path.join(dir, 'report-skip-prozesse.html'), scheme);
  const cpu = p.D.incidents.find((i) => i.lead === 'cpu'), delay = p.D.incidents.find((i) => i.type === 'ohne-engpass'), reason = p.D.skipped[0].text;
  let card = p.page.locator(`#cards .card.inc[data-id="${cpu.id}"]`), text = await card.innerText();
  ok(cpu.cause.kind === 'notmeasured' && await card.locator('.notmeasured[data-place="incidents.contributors"]').isVisible() && text.includes('nicht gemessen') && text.split(reason).length === 2, 'ohne Prozesse: Karte sagt "nicht gemessen" und nennt den Grund einmal: ' + text);
  card = p.page.locator(`#cards .card.inc[data-id="${delay.id}"]`);
  const rest = delay.causeText.replace('Prozess mit der höchsten Verzögerung nicht ermittelt: ' + reason, '').trim();
  text = await card.innerText();
  ok(await card.locator('.notmeasured[data-place="incidents.delayProcs"]').isVisible() && text.split(reason).length === 2, 'ohne Prozesse: Verzoegerung sagt "nicht gemessen" und nennt den Grund einmal: ' + text);
  ok(rest.length > 20 && delay.causeText.includes(reason) && (await card.locator('.card-cause').innerText()) === rest && await card.locator('.card-cause').getAttribute('title') === delay.causeText, 'ohne Prozesse: Verursacherzeile mit dem uebrigen Satz, voller Text im Titel');
  const ev = p.D.incidents.find((i) => i.type === 'ereignis' && i.event.unchecked.length > 0);
  ok(await p.page.locator(`#cards .card.inc[data-id="${ev.id}"] .notmeasured`).count() === 0 && (await p.page.locator(`#cards .card.inc[data-id="${ev.id}"] .card-cause`).innerText()).includes('Nicht geprüft'), 'ohne Prozesse: Ereignisvorfall sagt "nicht geprueft" in seinem Satz');
  await p.page.click('#qualityG > summary');
  ok(await p.page.locator('#qualityG .notmeasured[data-place="procs"]').isVisible() && await p.page.locator('footer .notmeasured[data-place="procs"]').isVisible(), 'ohne Prozesse: Messqualitaet und Fuss der gefuehrten Ansicht');
  await p.page.close();
  const rb = await open(browser, path.join(dir, 'report-skip-rueckblick.html'), scheme);
  ok(await rb.page.locator('#beforeG .notmeasured[data-place="before"]').isVisible() && await rb.page.locator('#beforeG .card.inc').count() === 0 && (await rb.page.locator('#beforeG').innerText()).includes('Vor der Messung'), 'ohne Rueckblick: Hinweis statt Karten');
  await rb.page.close();
  const ne = await open(browser, path.join(dir, 'report-skip-none-ereignisse.html'), scheme);
  ok(await ne.page.locator('#band').getAttribute('data-state') === 'green' && (await ne.page.locator('#bandSentence').innerText()) === ne.D.lagebild.sentence && ne.D.lagebild.sentence.includes('wurden nicht erfasst'), 'ohne Ereignisse ohne Befund: Satz mit Vorbehalt, wie geliefert');
  ok((await ne.page.locator('#measured').innerText()).replace(/\s+/g, ' ').includes('Nicht gemessen (1) Ereignisse – Ereignisse während der Messung wurden nicht erfasst. (-Skip Ereignisse)'), 'ohne Ereignisse ohne Befund: Kategorie unter "Nicht gemessen"');
  await ne.page.close();
  const na = await open(browser, path.join(dir, 'report-skip-none-alle.html'), scheme);
  const items = await na.page.locator('#measured .notm li').evaluateAll((l) => l.map((x) => x.dataset.skip || ''));
  ok(items.slice(0, 7).join() === na.D.skipped.map((x) => x.id).join() && items.length === 7 + na.D.sollIst.filter((x) => !x.measured).length && items.slice(7).every((x) => x === ''), 'ohne alle: die Kategorien vor den nicht gemessenen Werten: ' + items.join());
  ok(!(await na.page.locator('#measured').innerText()).includes('alle Messwerte wurden erfasst'), 'ohne alle: nie "alle Messwerte wurden erfasst"');
  await na.page.close();
  // values of the report data are text, never markup
  const bad = '<img src=x onerror="window.__xss=1">';
  const x = await open(browser, patched(dir, 'report.html', 'report-guided-markup.html', (J) => {
    Object.assign(J.lagebild, { sentence: 'Satz ' + bad, word: 'Wort ' + bad, hints: ['Hinweis ' + bad] });
    const c = J.incidents.find((i) => i.id === J.cards[0]);
    Object.assign(c.guide, { title: 'Titel ' + bad, userView: 'Sicht ' + bad, impact: 'Wirkung ' + bad, short: 'Kurz ' + bad }); c.guide.checks[0].text = 'Schritt ' + bad; c.causeText = 'Ursache ' + bad;
    J.incidents.find((i) => i.id === J.more[0].ids[0]).guide.title = 'Zeile ' + bad;
    J.before.incidents[0].guide.title = 'Davor ' + bad;
    J.skipped = [{ id: 'Rueckblick ' + bad, label: 'Label ' + bad, text: 'Grund ' + bad, places: ['events'] }];
  }), scheme);
  ok(await x.page.evaluate(() => window.__xss === undefined) && await x.page.locator('#guided img, header img, footer img').count() === 0, 'gefuehrte Ansicht: Markup aus den Daten wird nicht ausgefuehrt');
  const xc = x.page.locator('#cards .card.inc').first(), xt = (c) => xc.locator(c).innerText();
  ok((await x.page.locator('#bandSentence').innerText()) === 'Satz ' + bad && (await x.page.locator('#bandState').innerText()).includes('Wort ' + bad) && (await x.page.locator('#hints .hint').innerText()).includes('Hinweis ' + bad), 'Band und Hinweis: Markup als Text');
  ok(await xt('.card-title') === 'Titel ' + bad && await xt('.card-view') === 'Sicht ' + bad && await xt('.card-impact') === 'Wirkung ' + bad && await xt('.card-short') === 'Kurz ' + bad && (await xt('.card-first')).includes('Schritt ' + bad) && await xc.locator('.card-cause').getAttribute('title') === 'Ursache ' + bad, 'Karte: Markup als Text');
  ok((await x.page.locator('#more').innerText()).includes('Zeile ' + bad) && (await x.page.locator('#beforeG').innerText()).includes('Davor ' + bad) && (await x.page.locator('#kpis .kpi[data-kpi="events"]').innerText()).includes('Grund ' + bad), 'Listen und Hinweis "nicht gemessen": Markup als Text');
  ok(x.page.errors.length === 0, 'Skriptfehler Markup: ' + x.page.errors.join(' | '));
  await x.page.close();
  // a group of several incidents, a card without cause line and step, a long list before the capture
  const g = await open(browser, patched(dir, 'report.html', 'report-guided-groups.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu'), base = Math.max(...J.incidents.concat(J.before.incidents).map((i) => i.id)), ids = [1, 2, 3].map((k) => base + k);
    ids.forEach((id, k) => J.incidents.push(Object.assign({}, c, { id, rank: 100 + k, start: c.start + (k + 1) * 600000, end: c.end + (k + 1) * 600000 })));
    J.order = J.order.concat(ids); J.more.unshift({ label: '3-mal ' + c.guide.title, situation: 'cpu', ids });
    const d = J.incidents.find((i) => i.id === J.cards[1]); d.causeText = ''; d.guide = Object.assign({}, d.guide, { checks: [] });
    const b = J.before.incidents[0];
    for (let k = 0; k < 11; k++) J.before.incidents.push(Object.assign({}, b, { id: base + 10 + k, rank: 10 + k }));
  }), scheme);
  const grp = g.page.locator('#more > details.group');
  ok(await g.page.locator('#more > .group').count() === g.D.more.length && await grp.count() === 1 && await g.page.locator('#more > div.group').count() === 2, 'Gruppe mit mehreren Vorfaellen als aufklappbares Element');
  ok((await grp.locator('summary').innerText()).includes(g.D.more[0].label) && await grp.locator('.row').count() === 3 && !(await grp.locator('.row').first().isVisible()), 'Label als Zusammenfassung, Zeilen eingeklappt');
  await grp.locator('summary').click();
  ok(await grp.locator('.row:visible').count() === 3 && await grp.locator('.row .row-open').count() === 3, 'aufgeklappt: je Vorfall eine Zeile mit Oeffnen');
  const bare = g.page.locator(`#cards .card.inc[data-id="${g.D.cards[1]}"]`);
  ok(await bare.locator('.card-cause').count() === 0 && await bare.locator('.card-first').count() === 0 && await bare.locator('.card-open').count() === 1 && await bare.locator('.card-copy').count() === 1, 'Karte ohne Verursacherzeile und ohne Schritt');
  ok(await g.page.locator('#beforeG .card.inc').count() === 15 && await g.page.locator('#beforeG .card.inc:visible').count() === 10 && (await g.page.locator('#beforeMoreG').innerText()) === 'weitere 5 Vorfälle anzeigen', 'Karten vor der Messung nach zehn gefaltet');
  await g.page.click('#beforeMoreG');
  ok(await g.page.locator('#beforeG .card.inc:visible').count() === 15 && await g.page.locator('#beforeMoreG').count() === 0, 'alle Karten nach dem Klick');
  ok(g.page.errors.length === 0, 'Skriptfehler Gruppen: ' + g.page.errors.join(' | '));
  await g.page.close();
}

// the places of the incident view that depend on a category left out with -Skip, and the incidents that have each place
const perfInc = (i) => i.type !== 'ereignis';
const IV_PLACES = { 'incidents.contributors': (i) => perfInc(i) && i.type !== 'umfeld', 'incidents.delayProcs': (i) => perfInc(i) && i.type !== 'umfeld',
  'incidents.ica': (i) => perfInc(i) && i.type !== 'engpass', 'incidents.endpoints': perfInc, 'incidents.events': (i) => perfInc(i) && i.type !== 'umfeld' && !i.chronic };
// every report of tests/New-TestReports.ps1 (New-TestReports and New-SkipReports of tests/TestHelpers.ps1)
const ALL_REPORTS = ['report', 'report-focus', 'report-none', 'report-none-reported', 'report-spike', 'report-nodata', 'report-cutrep', 'report-masked', 'report-masked-personen']
  .concat(['voll', 'prozesse', 'laufwerke', 'citrix', 'ereignisse', 'rueckblick', 'drucken', 'gegenstellen', 'alle', 'alle-masked', 'none-ereignisse', 'none-alle', 'focus-ereignisse', 'focus-prozesse', 'odd'].map((n) => 'report-skip-' + n));
async function checkOpens(browser, dir, scheme) {                   // jeder Bericht oeffnet in der gefuehrten Ansicht, ohne Skriptfehler
  for (const name of ALL_REPORTS) {
    const { page, D } = await open(browser, path.join(dir, name + '.html'), scheme);
    ok(await page.evaluate(() => document.body.dataset.view) === 'guided' && await page.locator('#guided').isVisible() && !(await page.locator('#expert').isVisible()), name + ': oeffnet in der gefuehrten Ansicht');
    ok(await page.locator('#band').getAttribute('data-state') === D.lagebild.state && (await page.locator('#bandSentence').innerText()) === D.lagebild.sentence && (await page.locator('#bandState').innerText()).includes(D.lagebild.word), name + ': Band wie geliefert');
    ok(await page.locator('#hints .hint').count() === D.lagebild.hints.length, name + ': ein Hinweis je Eintrag');
    ok(await page.locator('#cards .card.inc').count() === D.cards.length && await page.locator('#more > .group').count() === D.more.length && await page.locator('#beforeG .card.inc').count() === D.before.incidents.length, name + ': Karten, weitere Vorfaelle, Vor der Messung');
    ok(await page.locator('#openTop').count() === (D.lagebild.top == null ? 0 : 1) && await page.locator('#measured').evaluate((d) => d.open) === (D.incidents.length === 0), name + ': erster Knopf nur mit Vorfall; gemessene Werte ohne Vorfall aufgeklappt');
    const w = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
    ok(w[0] <= w[1], name + ': ohne seitliches Rollen: ' + w.join(' > '));
    await showExpert(page);
    // the expert view of every report: incident column, tiles, range bar, every tab, and a range in the middle of the capture
    const x = await page.evaluate(() => {
      const count = (sel) => document.querySelectorAll(sel).length, info = () => document.getElementById('rangeInfo').textContent;
      const out = { inc: count('#incList .inc'), tiles: count('#tiles .tile'), range: info(), all: document.getElementById('rangeAll').disabled, tabs: count('#xtabs button[data-tab]') };
      for (const b of document.querySelectorAll('#xtabs button[data-tab]')) b.click();
      const mid = (FULL.t0 + FULL.t1) / 2;
      window.WP.setZoom(mid - 30000, mid + 30000);
      out.ranged = [count('#tiles .tile'), document.getElementById('rangeAll').disabled, info().startsWith('Zeitraum') && !info().includes('gesamte Messung'), [...document.querySelectorAll('#tiles .tile[data-status="na"] .value')].every((v) => v.textContent === '–')].join();
      window.WP.resetZoom();
      out.fits = document.documentElement.scrollWidth <= document.documentElement.clientWidth;
      return out;
    });
    ok(x.inc === D.incidents.length && x.tiles === D.sollIst.length + (D.mainApp ? 1 : 0) + 1 && x.tabs === 8 && x.range.startsWith('Zeitraum') && x.range.includes('gesamte Messung') && x.all, name + ': Expertenansicht mit Vorfallsspalte, Kacheln, Zeitraumleiste und acht Reitern: ' + JSON.stringify(x));
    ok(x.ranged === [x.tiles, false, true, true].join() && x.fits, name + ': Expertenansicht mit einem Zeitraum in der Mitte der Messung, ohne seitliches Rollen: ' + x.ranged + ' ' + x.fits);
    await showGuided(page);
    ok(page.errors.length === 0, name + ': Skriptfehler: ' + page.errors.join(' | '));
    // every incident opens in the incident view with its five sections; each place of the view that depends on a category
    // left out with -Skip says "nicht gemessen" there, and only there
    const byId = new Map(D.incidents.concat(D.before.incidents).map((i) => [i.id, i])), ids = D.order.concat(D.before.incidents.map((i) => i.id)), skipped = new Set(D.skipped.flatMap((x) => x.places));
    const shown = await page.evaluate(([list, places]) => list.map((id) => {
      window.WP.openIncident(id);
      const iv = document.getElementById('incident'); iv.querySelector('details.iv-evidence').open = true;
      return { id, open: !iv.hidden && iv.dataset.id === String(id) && window.WP.incident === id, title: iv.querySelector('.iv-title').textContent, sentence: iv.querySelector('.techtext').textContent,
        sections: [...iv.querySelectorAll('section, details')].map((e) => e.className.split(' ').find((c) => c.startsWith('iv-'))).filter(Boolean).join(),
        fits: document.documentElement.scrollWidth <= document.documentElement.clientWidth, text: iv.innerText,
        bare: [...iv.querySelectorAll('section')].filter((x) => x.textContent.trim() === x.querySelector('h3').textContent.trim()).map((x) => x.className).concat([...iv.querySelectorAll('p, ol, ul, dl')].filter((x) => !x.textContent.trim()).map((x) => x.tagName + '.' + x.className)).join(),
        places: places.filter((p) => [...iv.querySelectorAll('.notmeasured[data-place="' + p + '"]')].some((e) => e.getClientRects().length > 0)).join() };
    }), [ids, Object.keys(IV_PLACES)]);
    const wrong = [];
    for (const v of shown) {
      const inc = byId.get(v.id), want = Object.keys(IV_PLACES).filter((p) => skipped.has(p) && IV_PLACES[p](inc)).join();
      if (!v.open || v.title !== inc.guide.title || v.sentence !== inc.text || v.sections !== IV_SECTIONS || !v.fits) wrong.push(v.id + ': Ansicht ' + JSON.stringify([v.open, v.title, v.sections, v.fits]));
      if (v.places !== want) wrong.push(v.id + ': nicht gemessen an "' + v.places + '" statt "' + want + '"');
      if (v.bare) wrong.push(v.id + ': Ueberschrift ohne Inhalt oder leerer Absatz: ' + v.bare);
      if (skipped.has('incidents.contributors') && /keine Prozessdaten|keine Prozesse mit der Rolle Sicherheit/.test(v.text)) wrong.push(v.id + ': "keine" fuer nicht gemessene Prozesse');
      if (skipped.has('incidents.events') && inc.type !== 'ereignis' && (/Ereignisse im Fenster\s*keine/.test(v.text) || v.text.includes('lief ein Virenscan'))) wrong.push(v.id + ': Aussage ueber nicht gelesene Ereignisse');
      if (inc.unverified && (v.text.includes('ohne Engpass') || !v.text.includes('ohne erkannten Engpass'))) wrong.push(v.id + ': "ohne Engpass" fuer einen ungeprueften Vorfall');
    }
    ok(shown.length === ids.length && wrong.length === 0, name + ': jeder Vorfall oeffnet in der Vorfallsansicht (' + ids.length + '), nicht Gemessenes steht an seiner Stelle: ' + wrong.join(' | '));
    await page.evaluate(() => window.WP.closeIncident());
    ok(await page.locator('#incident').isHidden() && await page.locator('#band').isVisible() && page.errors.length === 0, name + ': Vorfallsansicht ohne Skriptfehler, danach wieder das Lagebild: ' + page.errors.join(' | '));
    await page.close();
  }
}

// ---------- incident view and copying ----------
// the three ways of copying made observable: the clipboard interface, the older command (which sees the hidden field and what
// its copy event hands over), then the fallback dialog
function watchCopy() {
  window.__copied = []; window.__exec = 0;
  Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: (t) => { window.__copied.push(t); return Promise.resolve(); } } });
  document.execCommand = () => {
    window.__exec++;
    const field = document.activeElement, data = new DataTransfer();
    field.dispatchEvent(new ClipboardEvent('copy', { clipboardData: data, bubbles: true, cancelable: true }));
    window.__execData = data.getData('text/plain');
    window.__execField = [field.tagName, field.value, field.selectionStart, field.selectionEnd];
    return true;
  };
}
async function openWatched(browser, file, scheme, more) {
  const ctx = await browser.newContext(Object.assign({ viewport: { width: 1400, height: 900 }, colorScheme: scheme }, more || {}));
  await ctx.addInitScript(watchCopy);
  const page = await ctx.newPage(); page.errors = []; page.on('pageerror', (e) => page.errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') page.errors.push(m.text()); });
  page.requests = []; page.on('request', (r) => page.requests.push(r.url()));
  await page.goto('file://' + file);
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent));
  return { ctx, page, D };
}
const ivOpen = async (page, id) => { await page.evaluate((i) => window.WP.openIncident(i), id); return page.locator('#incident'); };
// leaving the incident view goes one step back in the history of the page: wait until that step is done
const ivClosed = (page) => page.waitForFunction(() => window.WP.incident === null && (history.state === null || history.state.wpIncident == null));
const ivSections = (page) => page.locator('#incident').locator('section, details').evaluateAll((els) => els.map((e) => e.className.split(' ').find((c) => c.startsWith('iv-'))).filter(Boolean).join());
const IV_SECTIONS = 'iv-what,iv-cause,iv-todo,iv-affected,iv-evidence';
const oneLine = (s) => s.replace(/\s+/g, ' ').trim();
// the folded rest of a long list of steps ("Weitere n Pruefschritte anzeigen"), opened so that its text can be read
const unfoldSteps = async (page) => { const closed = page.locator('#incident .iv-todo details.morefold:not([open]) > summary'); while (await closed.count()) await closed.first().click(); };
// the steps and proposals of the incident view that are in the picture, and the lines that fold the rest
const stepsShown = (page) => page.evaluate(() => { const seen = (sel) => [...document.querySelectorAll('#incident ' + sel)].filter((e) => e.offsetParent !== null && !e.closest('details.morefold:not([open])')).length;
  return { checks: seen('ol.checks > li'), remedies: seen('.remedies li'), folds: [...document.querySelectorAll('#incident .iv-todo details.morefold > summary')].map((x) => x.textContent) }; });
// the lines that fold the rest of a guidance's checks beyond five (or maxChecks) and of its proposals beyond three (or
// maxRemedies), worded for the numbers of its report data (the catalogue grows: a count of steps is never a literal of these checks)
const foldsOf = (g, maxChecks = 5, maxRemedies = 3) => [[g.checks.length - maxChecks, 'Weiteren Prüfschritt anzeigen', 'Prüfschritte'], [g.remedies.length - maxRemedies, 'Weiteren Vorschlag anzeigen', 'Vorschläge']]
  .filter(([n]) => n > 0).map(([n, one, many]) => n === 1 ? one : `Weitere ${n} ${many} anzeigen`).join('|');
const deNum = (v) => v.toLocaleString('de-DE', { maximumFractionDigits: 0 });

async function checkIncidentView(browser, dir, scheme) {
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 }, colorScheme: scheme });
  await ctx.addInitScript(() => {                                     // die drei Wege beobachtbar machen
    window.__copied = []; window.__exec = 0;
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: (t) => { window.__copied.push(t); return Promise.resolve(); } } });
    document.execCommand = () => { window.__exec++; return true; };
  });
  const page = await ctx.newPage(); page.errors = []; page.on('pageerror', (e) => page.errors.push(e.message));
  await page.goto('file://' + path.join(dir, 'report.html'));
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent));
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  await page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-open`);
  const iv = page.locator('#incident');
  ok(await iv.getAttribute('data-id') === String(cpu.id) && (await iv.locator('.iv-title').innerText()) === cpu.guide.title, 'Vorfallsansicht ueber die Karte');
  const order = await iv.locator('section, details').evaluateAll((els) => els.map((e) => e.className.split(' ').find((c) => c.startsWith('iv-'))));
  ok(JSON.stringify(order.filter(Boolean)) === JSON.stringify(['iv-what', 'iv-cause', 'iv-todo', 'iv-affected', 'iv-evidence']), 'Abschnitte in fester Reihenfolge');
  ok(await iv.locator('.iv-todo ol.checks li').count() === cpu.guide.checks.length && await iv.locator('.iv-chart svg path').count() > 0, 'Pruefschritte und Diagramm');
  ok(await iv.locator('.iv-affected li').count() === cpu.affected.length, 'Betroffene aufgelistet');               // aus checkFindings
  await iv.locator('details.iv-evidence summary').click();
  ok((await iv.locator('.iv-evidence .contributors').innerText()).includes('EXCEL.EXE') && (await iv.locator('.iv-evidence').innerText()).includes(cpu.text), 'Belege mit Rangliste und Fachsatz');
  if (cpu.guide.terms.length) { await iv.locator('.term').first().hover(); ok(await page.locator('.term-pop').isVisible(), 'Fachbegriff erklaert sich'); }
  await page.click('#ivCopy');
  ok(await page.evaluate(() => window.__copied.at(-1)) === cpu.copy.named && (await page.locator('#ivCopy').innerText()).includes('Kopiert'), 'Kopieren ueber die Zwischenablage');
  await page.click('#ivBack'); await page.check('#anonSwitch'); await page.click('#copyAll');
  ok(await page.evaluate(() => window.__copied.at(-1)) === D.copyAll.anonymous, 'Zusammenfassung ohne Namen');
  await page.evaluate(() => { Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined }); });
  await page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-copy`);
  ok(await page.evaluate(() => window.__exec) === 1 && (await page.locator(`#cards .card.inc[data-id="${cpu.id}"] .card-copy`).innerText()).includes('Kopiert'), 'Kopieren ueber den aelteren Befehl');
  await page.evaluate(() => { document.execCommand = () => false; });
  await page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-copy`);
  ok(await page.locator('#copyFallback textarea').isVisible() && await page.evaluate(() => { const t = document.querySelector('#copyFallback textarea'); return t.selectionStart === 0 && t.selectionEnd === t.value.length; }), 'Ausweichfeld mit markiertem Text');
  await page.click('#copyFallback button');
  const mark = D.incidents.find((i) => i.lead === 'memory');
  await page.click(`#timeline .mark[data-incident="${mark.id}"]`);
  ok(await iv.getAttribute('data-id') === String(mark.id), 'Vorfallsansicht ueber die Zeitleiste');
  await ivExpert(page);
  const z = await page.evaluate(() => window.WP.zoom);
  ok(await page.evaluate(() => window.WP.view) === 'expert' && z && z.t0 < mark.start && z.t1 > mark.end, 'In der Expertenansicht zeigen setzt den Zeitraum');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await ctx.close();
  const p = await open(browser, patched(dir, 'report.html', 'report-html-value.html', (J) => { const c = J.incidents.find((i) => i.lead === 'cpu'); c.guide.title = '<b>fett</b> {user}'; }), scheme);   // Review Focus 1
  await p.page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-open`);
  ok((await p.page.locator('#incident .iv-title').innerText()) === '<b>fett</b> {user}' && await p.page.locator('#incident .iv-title b').count() === 0, 'Werte nicht als HTML');
  await p.page.close();
}

async function checkIncidentContent(browser, dir, scheme) {         // Vorfallsansicht: Kopf und die fuenf Abschnitte gegen die Berichtsdaten
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  const off = D.meta.offsetMin, sess = new Map(D.sessions.map((s) => [s.i, s])), iv = page.locator('#incident');
  ok(await iv.isHidden() && await page.evaluate(() => window.WP.incident) === null, 'Vorfallsansicht anfangs verborgen');
  const cpu = D.incidents.find((i) => i.lead === 'cpu'), g = cpu.guide;
  await page.evaluate(() => window.scrollTo(0, 400));
  await ivOpen(page, cpu.id);
  ok(await iv.isVisible() && await page.evaluate(() => window.WP.incident) === cpu.id && await page.evaluate(() => window.WP.view) === 'guided', 'WP.openIncident zeigt die Vorfallsansicht');
  for (const sel of ['#band', '#tlCard', '#cardsHead', '#cards', '#more', '#beforeG', '#measured', '#qualityG']) ok(await page.locator(sel).isHidden(), 'die Vorfallsansicht ersetzt ' + sel);
  ok(await page.locator('header #viewSwitch').isVisible() && await page.locator('header #title').isVisible() && await page.locator('footer').isVisible() && await page.evaluate(() => window.scrollY) === 0, 'Kopfleiste bleibt, die Ansicht beginnt oben');
  ok(await iv.locator('h2.iv-title').count() === 1 && (await iv.locator('.iv-title').innerText()) === g.title && (await iv.locator('.iv-tech').innerText()) === g.tech, 'Titel als Ueberschrift, darunter die Fachbezeichnung');
  const meta = oneLine(await iv.locator('.iv-meta').innerText());
  ok(meta.includes('Vorfall ' + cpu.id) && meta.includes(ddmmyyyy(cpu.start, off) + ' ' + hhmm(cpu.start, off)) && meta.includes(hhmm(cpu.end, off)) && meta.includes(' min') && meta.includes(g.userView), 'Zeit, Dauer und Einordnung: ' + meta);
  ok((await iv.locator('.iv-meta .status').innerText()).includes('kritisch') && (await iv.locator('.iv-meta .status .sym').innerText()) === '◆', 'Schwere als Symbol und Wort');
  const label = async (sel) => oneLine(await page.locator(sel).innerText());
  ok(await label('#ivCopy') === 'Zusammenfassung kopieren' && await label('#ivExpert') === 'In der Expertenansicht zeigen' && (await label('#ivBack')).includes('Zurück zum Lagebild') && (await label('#ivNext')).includes('Nächster Vorfall'), 'Knoepfe der Vorfallsansicht');
  ok((await iv.locator('section > h3, details > summary h3').allInnerTexts()).join('|') === 'Was war los|Wer oder was hat es verursacht|Was ist zu tun|Wer war betroffen|Belege', 'Ueberschriften der Abschnitte');
  // 1 what happened: meaning and impact on the left, the chart of the triggering value with its target line on the right
  const what = await iv.locator('.iv-what').innerText();
  ok(what.includes(g.meaning) && what.includes(g.impact), 'Was war los: Bedeutung und Wirkung');
  const tb = await iv.locator('.iv-what .iv-text').boundingBox(), cb = await iv.locator('.iv-what .iv-chart').boundingBox();
  ok(tb.x + tb.width <= cb.x && Math.abs(tb.y - cb.y) < 4 && cb.width >= 380, 'Diagramm rechts neben dem Text: ' + JSON.stringify([tb, cb]));
  ok((await iv.locator('.iv-chart h4').innerText()).includes('CPU') && await iv.locator('.iv-chart .band-warn line').count() === 1 && await iv.locator('.iv-chart .incband').count() === 1, 'Diagramm des ausloesenden Messwerts mit Soll-Linie und dem Fenster des Vorfalls');
  ok((await iv.locator('.iv-chart > p.note').innerText()).endsWith('der Vorfall (getönt) mit Vor- und Nachlauf.'), 'Bildunterschrift: Vorfall getoent mit Vor- und Nachlauf, wo es einen ungetoenten Teil gibt');
  const ax = await iv.locator('.iv-chart svg text.xaxis').allTextContents();
  ok(ax.length >= 2 && ax[0] < hhmm(cpu.start, off) + ':99' && ax[ax.length - 1] > hhmm(cpu.end, off) && await iv.locator('.iv-chart svg text.yaxis').count() >= 3, 'Diagramm mit Achsenbeschriftung, Vorfall mit Rand: ' + ax.join(' '));
  const drag = await iv.locator('.iv-chart svg').boundingBox();
  await page.mouse.move(drag.x + drag.width * 0.3, drag.y + 60); await page.mouse.down(); await page.mouse.move(drag.x + drag.width * 0.6, drag.y + 60); await page.mouse.up();
  ok(await page.evaluate(() => window.WP.zoom === null), 'Ziehen im Diagramm der Vorfallsansicht stellt keinen Ausschnitt ein');
  // 2 cause, as the report data say it (the same text as on the card and in the copy text)
  ok(oneLine(await iv.locator('.iv-cause').innerText()).includes(cpu.causeText) && cpu.copy.named.replace(/\r\n\s*/g, ' ').includes(cpu.causeText), 'Ursache wie in den Berichtsdaten und im Kopiertext');
  // 3 what to do: numbered steps with where and sign, remedies as proposals with their condition, sources with the step
  const steps = iv.locator('.iv-todo ol.checks > li');
  // the first screen (1400 x 900) reaches the heading "Was ist zu tun" and the complete first step
  const fold = await page.evaluate(() => [window.scrollY, window.innerWidth, window.innerHeight, document.querySelector('#incident .iv-todo h3').getBoundingClientRect().bottom, document.querySelector('#incident ol.checks > li').getBoundingClientRect().bottom].map(Math.round));
  ok(fold[0] === 0 && fold[1] === 1400 && fold[2] === 900 && fold[3] < 900 && fold[4] < 900 && (await steps.first().innerText()).includes('Woran erkennbar:'), 'erster Bildschirm: "Was ist zu tun" und der ganze erste Schritt ohne Scrollen: ' + fold.join(' '));
  // a long list shows its first five checks and three proposals; a line folds the rest and goes away when they are shown
  const shown = await stepsShown(page);
  // (literals adapted, P3-R1: since the catalogue's round 5 the CPU incident has 9 checks, not 7; the numbers come from the data)
  ok(g.checks.length > 5 && g.remedies.length > 3 && shown.checks === 5 && shown.remedies === 3 && shown.folds.length === 2 && shown.folds.join('|') === foldsOf(g), 'lange Listen: fuenf von ' + g.checks.length + ' Schritten und drei von ' + g.remedies.length + ' Vorschlaegen, der Rest hinter einer Zeile: ' + JSON.stringify(shown) + ' statt ' + foldsOf(g));
  await unfoldSteps(page);
  const all = await stepsShown(page);
  ok(all.checks === g.checks.length && all.remedies === g.remedies.length && await iv.locator('.iv-todo details.morefold > summary:visible').count() === 0 && await iv.locator('.iv-todo ol.checks').nth(1).getAttribute('start') === '6', 'aufgeklappt: alle Schritte, weiter gezaehlt ab 6, die Zeile ist weg: ' + JSON.stringify(all));
  for (let k = 0; k < g.checks.length; k++) {
    const c = g.checks[k], t = oneLine(await steps.nth(k).innerText());
    ok(t.startsWith(c.text) && t.includes('Wo: ' + c.where) && t.includes('Woran erkennbar: ' + c.sign) && t.indexOf('Wo: ') < t.indexOf('Woran erkennbar: '), 'Schritt ' + (k + 1) + ' mit was, wo, woran erkennbar: ' + t);
  }
  ok(await steps.first().locator('.step').evaluate((e) => Number(getComputedStyle(e).fontWeight) >= 600) && await steps.first().evaluate((e) => getComputedStyle(e).listStyleType) === 'decimal', 'Schritte nummeriert, ihr Text fett');
  const rem = iv.locator('.iv-todo .remedies li');
  ok(await rem.count() === g.remedies.length && (await iv.locator('.iv-todo .remedies h4').innerText()) === 'Mögliche Abhilfe – Vorschlag', 'Abhilfe abgesetzt als Vorschlag');
  // (the catalogue names a source for some proposals since its second round: it stands under the proposal)
  for (let k = 0; k < g.remedies.length; k++) ok(oneLine(await rem.nth(k).innerText()) === 'Wenn ' + g.remedies[k].precondition + ', dann: ' + g.remedies[k].text + (g.remedies[k].source ? ' Quelle: ' + g.remedies[k].source : ''), 'Abhilfe ' + (k + 1) + ': Bedingung vor dem Schritt: ' + oneLine(await rem.nth(k).innerText()));
  const sb = await steps.last().boundingBox(), rb = await iv.locator('.iv-todo .remedies').boundingBox();
  ok(rb.y >= sb.y + sb.height, 'Abhilfe steht unter den Schritten');
  const sourced = g.checks.concat(g.remedies).filter((x) => x.source).length;
  ok(g.contacts.length === 0 && await iv.locator('.iv-todo .contact').count() === 0 && sourced < g.checks.length + g.remedies.length && await iv.locator('.iv-todo .src').count() === sourced && await iv.locator('.iv-todo .fallback').count() === 0, 'ohne Ansprechpartner, Quelle und Auffang-Eintrag kein leerer Bereich');
  // 4 who was affected: user, client, highest delay
  const aff = iv.locator('.iv-affected li');
  for (let k = 0; k < cpu.affected.length; k++) {
    const a = cpu.affected[k], s = sess.get(a.s), t = oneLine(await aff.nth(k).innerText());
    ok(t.includes(s.user) && t.includes(s.client) && t.includes(deNum(a.peakMs) + ' ms'), 'Betroffene Sitzung mit Benutzer, Client und hoechster Verzoegerung: ' + t);
    ok(t.endsWith((a.peakMs >= 500 ? '◆ kritisch ' : '▲ auffällig ') + deNum(a.peakMs) + ' ms'), 'Betroffene Sitzung: Status als Symbol und Wort vor dem Wert: ' + t);
  }
  ok(await iv.locator('.iv-affected .sig[title]').count() === 0, 'Wer war betroffen: kein Status nur als Symbol mit Tooltip');
  // 5 evidence, folded: the technical sentence, the charts of the window, the rankings, the measured values involved
  ok(!(await iv.locator('details.iv-evidence').evaluate((d) => d.open)) && !(await iv.locator('.iv-evidence .techtext').isVisible()), 'Belege eingeklappt');
  await iv.locator('details.iv-evidence > summary').click();
  ok((await iv.locator('.iv-evidence .techtext').innerText()) === cpu.text, 'Belege: der Fachsatz des Vorfalls');
  ok(await iv.locator('.iv-evidence .sigcharts svg path').count() > 0 && await iv.locator('.iv-evidence .contributors table').count() >= 3 && await iv.locator('.iv-evidence .signals tbody tr').count() === cpu.signals.length, 'Belege: Verlauf, Ranglisten, beteiligte Messwerte');
  const ev = await iv.locator('.iv-evidence').innerText();
  ok(ev.includes('Ereignisse im Fenster') && ev.includes('Schutzprodukte') && (await iv.locator('.iv-evidence .causebox').innerText()).includes('EXCEL.EXE'), 'Belege: Ereignisse, Schutzprodukte, Verursacher');
  ok(await iv.locator('.iv-evidence .zoomto').count() === 0 && await iv.locator('.iv-evidence .essentials').count() === 0, 'Belege ohne die Knoepfe und Bloecke, die es in der Vorfallsansicht schon gibt');
  const nm = D.sollIst.filter((r) => !r.measured);
  ok(await iv.locator('.iv-evidence .iv-notm li').count() === nm.length && (nm.length > 0 || await iv.locator('.iv-evidence .iv-notm').count() === 0), 'Belege: nicht Gemessenes nur, wo etwas fehlt (keine leere Liste)');
  // a link of the evidence leads to the table of the expert view
  await iv.locator('.iv-evidence .causebox button.lnk[data-s]').click();
  ok(await page.evaluate(() => window.WP.view) === 'expert' && await page.locator('#xt-sessions').isVisible() && await page.locator('#tSessions tbody tr.selected').count() === 1, 'Verweis aus den Belegen fuehrt in die Tabelle der Expertenansicht');
  await showGuided(page);
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(cpu.id), 'zurueck in der gefuehrten Ansicht steht die Vorfallsansicht noch');
  // "Naechster Vorfall" follows the ranking and is missing on the last incident
  await ivOpen(page, D.order[0]);
  for (let k = 1; k < D.order.length; k++) { await page.click('#ivNext'); ok(await iv.getAttribute('data-id') === String(D.order[k]) && await ivSections(page) === IV_SECTIONS, 'Naechster Vorfall nach Rang, Platz ' + (k + 1)); }
  ok(await page.locator('#ivNext').count() === 0 && await page.locator('#ivBack').count() === 1, 'beim letzten Vorfall kein "Naechster Vorfall"');
  // a delay without a bottleneck: the chart shows the input delay, the cause points outside the worker
  const delay = D.incidents.find((i) => i.type === 'ohne-engpass' && i.affected.length > 1);
  await ivOpen(page, delay.id);
  ok((await iv.locator('.iv-chart h4').innerText()).includes('Eingabeverzögerung') && await iv.locator('.iv-chart svg path').count() > 0 && await iv.locator('.iv-chart .legend span').count() > 1, 'Verzoegerung ohne Engpass: Diagramm der Eingabeverzoegerung je Sitzung');
  ok(oneLine(await iv.locator('.iv-cause').innerText()).includes(delay.causeText) && delay.causeText.includes('außerhalb'), 'Verzoegerung ohne Engpass: Hinweis auf eine Ursache ausserhalb');
  ok(delay.guide.contacts.length > 0 && await iv.locator('.iv-todo .contact li').count() === delay.guide.contacts.length && (await iv.locator('.iv-todo .contact h4').innerText()) === 'An wen wenden' && (await iv.locator('.iv-todo .contact li').first().innerText()).includes(delay.guide.contacts[0].text), 'An wen wenden');
  ok(await iv.locator('.iv-affected li').count() === delay.affected.length, 'Verzoegerung ohne Engpass: Betroffene');
  // an incident with at most five checks and three proposals shows them all, without a line that folds a rest
  const few = D.incidents.find((i) => i.guide.checks.length > 0 && i.guide.checks.length <= 5 && i.guide.remedies.length > 0 && i.guide.remedies.length <= 3);
  await ivOpen(page, few.id);
  const fshown = await stepsShown(page);
  ok(fshown.checks === few.guide.checks.length && fshown.remedies === few.guide.remedies.length && fshown.folds.length === 0 && await iv.locator('details.morefold').count() === 0 && await iv.locator('.iv-todo ol.checks').count() === 1, 'kurze Listen: alle Schritte und Vorschlaege, keine Zeile "Weitere …": ' + JSON.stringify(fshown));
  // a chronic state: the same page; its first sentence says that it lasted
  const chronic = D.incidents.find((i) => i.chronic);
  await ivOpen(page, chronic.id);
  ok(await ivSections(page) === IV_SECTIONS && (await iv.locator('.iv-what .iv-text p').first().innerText()) === chronic.guide.meaning && /ganze Messung/.test(chronic.guide.meaning), 'Dauerzustand: dieselbe Seite, der erste Satz nennt die Dauer');
  // a state of the surroundings: who was affected is the session whose own value is over its target, as the cause names it;
  // what the input delay showed stands as a note under the list (reworded: the sentence alone read as "nobody")
  const csig = chronic.signals[0], cs = sess.get(csig.s), crow = oneLine(await iv.locator('.iv-affected ul.aff > li').first().innerText());
  ok(chronic.type === 'umfeld' && chronic.affected.length === 0 && await iv.locator('.iv-affected ul.aff > li').count() === 1 && crow.includes(cs.user) && crow.includes(cs.client) && crow.includes('▲ auffällig') && crow.includes('ICA Round Trip ' + deNum(csig.peak) + ' ms') && crow.includes('(Soll ' + csig.ideal + ')') && chronic.causeText.includes(cs.user) && chronic.causeText.includes(deNum(csig.peak) + ' ms'), 'Dauerzustand im Umfeld: die Sitzung des Messwerts mit Benutzer, Client und Wert ueber dem Soll, wie die Ursache sie nennt: ' + crow);
  const cnote = iv.locator('.iv-affected ul.aff + p.note'), lb2 = await iv.locator('.iv-affected ul.aff').boundingBox(), nb2 = await cnote.boundingBox();
  ok((await cnote.innerText()) === 'Die auf dem Server gemessene Eingabeverzögerung lag in den Sitzungen dieses Vorfalls nicht über dem Soll.' && nb2.y >= lb2.y + lb2.height && !(await iv.locator('.iv-affected').innerText()).includes('Befund'), 'Dauerzustand im Umfeld: der Satz zur Eingabeverzoegerung als Anmerkung unter der Liste, auf den Vorfall bezogen');
  ok((await iv.locator('.iv-affected .aff-head').innerText()).includes('Messwert über dem Soll'), 'Dauerzustand im Umfeld: Spalte des Messwerts');
  // the chart of an incident that fills the capture claims no lead and lag
  const ccap = await iv.locator('.iv-chart > p.note').innerText();
  ok(ccap.includes('der Vorfall erstreckt sich über die gesamte gemessene Zeit.') && !ccap.includes('Nachlauf') && !ccap.includes('getönt') && await iv.locator('.iv-chart .incband').count() === 0, 'Dauerzustand ueber die ganze Messung: Bildunterschrift ohne Vor- und Nachlauf, nichts getoent: ' + ccap);
  // an incident from events: no chart of a measured value; every element of the print guidance names its source
  const print = D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print'), pg = print.guide;
  await ivOpen(page, print.id);
  ok(await iv.locator('.iv-what .iv-chart').count() === 0 && await iv.locator('.iv-what svg').count() === 0 && (await iv.locator('.iv-what').innerText()).includes(pg.meaning), 'Vorfall aus Ereignissen: kein Diagramm eines Messwerts');
  const psteps = iv.locator('.iv-todo ol.checks > li'), prem = iv.locator('.iv-todo .remedies li'), pcon = iv.locator('.iv-todo .contact li');
  // many checks and proposals (two-digit numbers): five and three are shown, "An wen wenden" is reachable without scrolling
  // through all of them (literals adapted, P3-R1: the catalogue's round 5 gives 17 and 19 instead of 15 and 17; from the data)
  const pshown = await stepsShown(page), ptop = await iv.locator('.iv-todo .contact').evaluate((e) => Math.round(e.getBoundingClientRect().top + window.scrollY));
  ok(pg.checks.length >= 15 && pg.remedies.length >= 13 && pshown.checks === 5 && pshown.remedies === 3 && pshown.folds.join('|') === foldsOf(pg), 'Druckproblem: fuenf von ' + pg.checks.length + ' Schritten und drei von ' + pg.remedies.length + ' Vorschlaegen, der Rest eingeklappt: ' + JSON.stringify(pshown) + ' statt ' + foldsOf(pg));
  ok(await iv.locator('.iv-todo .contact').isVisible() && ptop < 3 * 900, 'Druckproblem: "An wen wenden" steht innerhalb der ersten drei Bildschirme: ' + ptop);
  await iv.locator('.iv-todo details.morefold > summary').first().focus(); await page.keyboard.press('Enter');
  ok((await stepsShown(page)).checks === pg.checks.length && (await stepsShown(page)).remedies === 3, 'die Zeile ist mit der Tastatur bedienbar und klappt nur ihre Liste auf');
  await unfoldSteps(page);
  const ptop2 = await iv.locator('.iv-todo .contact').evaluate((e) => Math.round(e.getBoundingClientRect().top + window.scrollY));
  ok((await stepsShown(page)).remedies === pg.remedies.length && ptop2 > ptop + 1500, 'aufgeklappt stehen alle Schritte da: ' + ptop2);
  ok(await psteps.count() === pg.checks.length && await prem.count() === pg.remedies.length && await pcon.count() === pg.contacts.length && pg.checks.concat(pg.remedies, pg.contacts).every((x) => x.source), 'Druckproblem: Schritte, Abhilfe und Ansprechpartner');
  for (let k = 0; k < pg.checks.length; k++) ok((await psteps.nth(k).locator('.src').innerText()) === 'Quelle: ' + pg.checks[k].source, 'Quelle steht beim Schritt ' + (k + 1));
  for (let k = 0; k < pg.remedies.length; k++) ok((await prem.nth(k).locator('.src').innerText()) === 'Quelle: ' + pg.remedies[k].source, 'Quelle steht bei der Abhilfe ' + (k + 1));
  for (let k = 0; k < pg.contacts.length; k++) ok((await pcon.nth(k).locator('.src').innerText()) === 'Quelle: ' + pg.contacts[k].source, 'Quelle steht beim Ansprechpartner ' + (k + 1));
  ok(await iv.locator('.iv-todo a[href]').count() === 0, 'Quellen ohne Adresse sind kein Verweis');
  ok(oneLine(await iv.locator('.iv-cause').innerText()).includes(print.causeText) && print.causeText.includes(print.event.patterns[0].text), 'Vorfall aus Ereignissen: Ursache mit den Aussagen der Muster');
  ok(await iv.locator('.iv-affected li').count() === 0 && (await iv.locator('.iv-affected').innerText()).includes('Ohne Benutzersitzung'), 'Druckproblem ohne Benutzersitzung: Satz statt leerer Liste');
  await iv.locator('details.iv-evidence > summary').click();
  ok(await iv.locator('.iv-evidence .patterns li').count() === print.event.patterns.length && (await iv.locator('.iv-evidence .patterns').innerText()).includes(print.event.patterns[0].text) && await iv.locator('.iv-evidence .evlist tbody tr').count() === print.events.length, 'Belege: Muster und Ereignisse des Vorfalls');
  ok((await iv.locator('.iv-evidence .techtext').innerText()) === print.text && (await iv.locator('.iv-evidence').innerText()).includes('hpsimgr.dll'), 'Belege: Fachsatz und fehlerhaftes Modul');
  const crash = D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'crash' && i.event.sessions.length > 1);
  await ivOpen(page, crash.id);
  const cl = iv.locator('.iv-affected li');
  ok(await cl.count() === crash.event.sessions.length, 'Absturz: betroffene Sitzungen');
  for (let k = 0; k < crash.event.sessions.length; k++) { const s = sess.get(crash.event.sessions[k]), t = oneLine(await cl.nth(k).innerText()); ok(t.includes(s.user) && t.includes(s.client), 'Absturz: Sitzung mit Benutzer und Client: ' + t); }
  // incidents of the days before the capture open in the same view: no chart, and the view says why
  const lb = D.before.incidents.slice().sort((a, b) => a.rank - b.rank);
  await page.evaluate(() => window.WP.closeIncident()); await ivClosed(page);
  await page.click(`#beforeG .card.inc[data-id="${lb[0].id}"] .card-open`);
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(lb[0].id) && await ivSections(page) === IV_SECTIONS && (await iv.locator('.iv-title').innerText()) === lb[0].guide.title, 'Vorfall vor der Messung in derselben Ansicht');
  // reworded: the note stood in the head (in the classification of the report data) and again in the first section; it
  // stands once now, and the section carries it only where the classification does not say it
  const said = (await iv.innerText()).toLowerCase().split('für diese zeit liegen keine messwerte vor').length - 1;
  ok(said === 1 && lb[0].guide.userView.includes('für diese Zeit liegen keine Messwerte vor') && (await iv.locator('.iv-meta .iv-view').innerText()) === lb[0].guide.userView && await iv.locator('.iv-chart').count() === 0 && await iv.locator('svg').count() === 0 && (await iv.locator('.iv-what').innerText()).includes(lb[0].guide.meaning), 'vor der Messung: Hinweis statt Diagramm, einmal: ' + said);
  ok(oneLine(await iv.locator('.iv-meta').innerText()).includes(ddmmyyyy(lb[0].events[0].t, lb[0].events[0].offsetMin)), 'vor der Messung: mit Datum');
  ok(await iv.locator('.iv-affected li').count() === lb[0].event.users.length && (await iv.locator('.iv-affected li').first().innerText()).includes(lb[0].event.users[0]), 'vor der Messung: Benutzer aus den Ereignissen');
  for (let k = 1; k < lb.length; k++) { await page.click('#ivNext'); ok(await iv.getAttribute('data-id') === String(lb[k].id), 'vor der Messung: naechster Vorfall nach Rang, Platz ' + (k + 1)); }
  ok(await page.locator('#ivNext').count() === 0, 'vor der Messung: beim letzten kein "Naechster Vorfall"');
  await iv.locator('details.iv-evidence > summary').click();
  ok((await iv.locator('.iv-evidence').innerText()).includes('Für die Tage vor der Messung gelten nur die Muster, die keine Messwerte brauchen.') && await iv.locator('.iv-evidence .evlist tbody tr').count() === lb[lb.length - 1].events.length && await iv.locator('.iv-evidence .iv-notm').count() === 0, 'vor der Messung: Belege aus den Ereignissen');
  await ivExpert(page);
  ok(await page.evaluate(() => window.WP.view) === 'expert' && await page.locator('#xt-before').isVisible() && await page.locator(`#before .inc[data-id="${lb[lb.length - 1].id}"].selected`).isVisible() && await page.evaluate(() => window.WP.zoom === null), 'vor der Messung: in der Expertenansicht in ihrem Reiter hervorgehoben, ohne Zeitraum');
  ok(await page.evaluate(() => [...document.querySelectorAll('[id]')].map((e) => e.id).filter((id, k, a) => a.indexOf(id) !== k).length) === 0, 'keine Kennung doppelt, auch mit Vorfallsansicht');
  ok(page.errors.length === 0, 'Skriptfehler Vorfallsansicht: ' + page.errors.join(' | '));
  await page.close();
}

async function checkIncidentStates(browser, dir, scheme) {          // Vorfallsansicht: nicht gemessen, nicht geprueft, Auffang, Werte als Text
  // without processes: the cause says "nicht gemessen" with the reason once; an incident from events says what was not checked
  const p = await open(browser, path.join(dir, 'report-skip-prozesse.html'), scheme), iv = p.page.locator('#incident'), reason = p.D.skipped[0].text;
  const cpu = p.D.incidents.find((i) => i.lead === 'cpu'), delay = p.D.incidents.find((i) => i.type === 'ohne-engpass');
  await ivOpen(p.page, cpu.id);
  let cause = await iv.locator('.iv-cause').innerText();
  ok(await iv.locator('.iv-cause .notmeasured[data-place="incidents.contributors"]').isVisible() && cause.includes('nicht gemessen') && cause.split(reason).length === 2 && cause.includes('(-Skip Prozesse)'), 'ohne Prozesse: Ursache sagt "nicht gemessen" und nennt den Grund einmal: ' + cause);
  await iv.locator('details.iv-evidence > summary').click();
  ok(await iv.locator('.iv-evidence .notmeasured[data-place="incidents.contributors"]').first().isVisible() && await iv.locator('.iv-evidence .contributors table').count() === 0 && (await iv.locator('.iv-evidence .techtext').innerText()) === cpu.text, 'ohne Prozesse: Hinweis statt Rangliste, der Fachsatz bleibt');
  await ivOpen(p.page, delay.id);
  cause = oneLine(await iv.locator('.iv-cause').innerText());
  const rest = delay.causeText.replace('Prozess mit der höchsten Verzögerung nicht ermittelt: ' + reason, '').trim();
  ok(await iv.locator('.iv-cause .notmeasured[data-place="incidents.delayProcs"]').isVisible() && cause.split(reason).length === 2 && rest.length > 20 && cause.includes(rest), 'ohne Prozesse: Verzoegerung nennt den Grund einmal und den uebrigen Satz: ' + cause);
  const ev = p.D.incidents.find((i) => i.type === 'ereignis' && i.event.unchecked.some((u) => u.id === 'users')), un = ev.event.unchecked.find((u) => u.id === 'users');
  await ivOpen(p.page, ev.id);
  const who = await iv.locator('.iv-affected').innerText();
  ok(who.includes('nicht geprüft: ' + un.text) && !who.includes('Sitzung nicht ermittelt') && !who.includes('Ohne Benutzersitzung') && await iv.locator('.iv-affected li').count() === 0, 'ohne Prozesse: Betroffene eines Ereignisvorfalls nicht geprueft: ' + who);
  ok(oneLine(await iv.locator('.iv-cause').innerText()).includes(ev.causeText) && ev.causeText.includes('Nicht geprüft'), 'ohne Prozesse: Ursache des Ereignisvorfalls wie geliefert');
  await iv.locator('details.iv-evidence > summary').click();
  ok((await iv.locator('.iv-evidence .patterns li.unchecked').allInnerTexts()).some((t) => t.includes('nicht geprüft: ' + un.text)) && !(await iv.locator('.iv-evidence').innerText()).includes('Sitzung nicht ermittelt'), 'ohne Prozesse: Muster "nicht geprueft" wie im Eintrag der Expertenansicht');
  await p.page.close();
  const d = await open(browser, path.join(dir, 'report-skip-drucken.html'), scheme);
  await ivOpen(d.page, d.D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print').id);
  await d.page.locator('#incident details.iv-evidence > summary').click();
  const pat = await d.page.locator('#incident .iv-evidence .patterns').innerText();
  ok(pat.includes('nicht geprüft: Bezug zu einem Druckertreiber (Drucken nicht gemessen)') && !pat.includes('Kein Muster erkannt'), 'ohne Drucken: Muster nicht geprueft statt "kein Muster"');
  await d.page.close();
  const a = await open(browser, path.join(dir, 'report-skip-alle.html'), scheme);
  await ivOpen(a.page, a.D.incidents[0].id);
  await a.page.locator('#incident details.iv-evidence > summary').click();
  ok((await a.page.locator('#incident .iv-notm li').evaluateAll((l) => l.map((x) => x.dataset.skip || '').filter(Boolean))).join() === a.D.skipped.map((s) => s.id).join(), 'ohne alle: die Belege nennen die weggelassenen Kategorien');
  await a.page.close();
  // input delay not measured: who was affected cannot be told, and the view says so
  const nd = await open(browser, path.join(dir, 'report-nodata.html'), scheme), nc = nd.D.incidents.find((i) => i.lead === 'cpu');
  await ivOpen(nd.page, nc.id);
  ok(await nd.page.locator('#incident .iv-affected li').count() === 0 && (await nd.page.locator('#incident .iv-affected').innerText()).includes('Eingabeverzögerung nicht gemessen; betroffene Sitzungen sind nicht bestimmbar.'), 'Eingabeverzoegerung nicht gemessen: Betroffene nicht bestimmbar');
  ok(oneLine(await nd.page.locator('#incident .iv-cause').innerText()).includes(nc.causeText) && await nd.page.locator('#incident .iv-chart svg path').count() > 0, 'ohne Prozessdaten: Ursache wie geliefert, Diagramm bleibt');
  await nd.page.locator('#incident details.iv-evidence > summary').click();
  const nm = nd.D.sollIst.filter((r) => !r.measured), nt = await nd.page.locator('#incident .iv-evidence .iv-notm').innerText();
  ok(nm.length > 0 && await nd.page.locator('#incident .iv-notm li').count() === nm.length && nm.every((r) => nt.includes(r.label)) && nt.includes('Nicht gemessen'), 'Belege: was nicht gemessen wurde: ' + oneLine(nt));
  ok(nd.page.errors.length === 0, 'Skriptfehler ohne Daten: ' + nd.page.errors.join(' | '));
  await nd.page.close();
  // the fallback entry of the catalogue shows its note above the steps; a source with an address shows it as plain text
  const fb = await open(browser, patched(dir, 'report.html', 'report-iv-fallback.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu'); c.guide.fallback = true;
    c.guide.checks[0].source = { title: 'Hersteller: Leitfaden', url: 'https://example.invalid/leitfaden' }; c.guide.checks[1].where = null; c.guide.checks[1].sign = null; c.guide.remedies[0].precondition = null;
    J.incidents.find((i) => i.lead === 'memory').guide = null;
  }), scheme), fc = fb.D.incidents.find((i) => i.lead === 'cpu');
  await ivOpen(fb.page, fc.id);
  const note = fb.page.locator('#incident .iv-todo .fallback'), nb = await note.boundingBox(), ob = await fb.page.locator('#incident .iv-todo ol.checks').first().boundingBox();
  ok((await note.innerText()).includes(fb.D.guidance.fallbackNote) && nb.y + nb.height <= ob.y, 'Auffang-Eintrag: sichtbarer Hinweis ueber den Schritten');
  const src = await fb.page.locator('#incident ol.checks > li').first().locator('.src').innerText();
  ok(src === 'Quelle: Hersteller: Leitfaden – https://example.invalid/leitfaden' && await fb.page.locator('#incident .iv-todo a').count() === 0 && fb.page.requests.length === 1, 'Quelle mit Adresse als Text, ohne Abruf: ' + src);
  const bare = oneLine(await fb.page.locator('#incident ol.checks > li').nth(1).innerText());
  ok(bare === fc.guide.checks[1].text && oneLine(await fb.page.locator('#incident .remedies li').first().innerText()) === fc.guide.remedies[0].text, 'Schritt ohne Ort und Merkmal, Abhilfe ohne Bedingung: nur der Text');
  await ivOpen(fb.page, fb.D.incidents.find((i) => i.lead === 'memory').id);
  // reworded: an incident without guidance showed the heading "Was ist zu tun" over nothing and empty paragraphs. A section
  // whose data is missing is left out; what the page knows by itself stays (title from the type, chart, cause, affected, evidence)
  const bareParts = (pg) => pg.evaluate(() => { const iv = document.getElementById('incident');
    return [...iv.querySelectorAll('section')].filter((x) => x.textContent.trim() === x.querySelector('h3').textContent.trim()).map((x) => x.className).concat([...iv.querySelectorAll('p, ol, ul, dl')].filter((x) => !x.textContent.trim()).map((x) => x.tagName + '.' + x.className)).join(); });
  ok(await ivSections(fb.page) === 'iv-what,iv-cause,iv-affected,iv-evidence' && await fb.page.locator('#incident ol.checks li').count() === 0 && await bareParts(fb.page) === '' && fb.page.errors.length === 0, 'Vorfall ohne Anleitung: kein Abschnitt "Was ist zu tun", keine Ueberschrift ohne Inhalt, kein Skriptfehler: ' + await ivSections(fb.page) + ' / ' + await bareParts(fb.page) + ' / ' + fb.page.errors.join(' | '));
  ok((await fb.page.locator('#incident .iv-title').innerText()) === 'Engpass' && await fb.page.locator('#incident .iv-tech').count() === 0 && await fb.page.locator('#incident .iv-what .iv-chart svg path').count() > 0 && await fb.page.locator('#incident .iv-what .iv-text').count() === 0, 'Vorfall ohne Anleitung: Titel aus der Art, Diagramm ohne leere Textspalte');
  await fb.page.close();
  // the guidance reduced to its title, no cause: only the sections that have something to say; steps without a list of checks
  const rd = await open(browser, patched(dir, 'report.html', 'report-iv-reduced.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu'); c.guide = { title: c.guide.title }; c.causeText = '';
    const e = J.incidents.find((i) => i.type === 'ereignis'); e.guide = { title: e.guide.title }; e.causeText = '';
    const m = J.incidents.find((i) => i.lead === 'memory'); m.guide.checks = []; m.guide.remedies = null;
    const d = J.incidents.find((i) => i.lead === 'disk'); d.guide.checks = []; d.guide.contacts = [];
    J.guidance.copy.maxChecks = 2; J.guidance.copy.maxRemedies = 1;
  }), scheme);
  await ivOpen(rd.page, rd.D.incidents.find((i) => i.lead === 'cpu').id);
  ok(await ivSections(rd.page) === 'iv-what,iv-affected,iv-evidence' && await bareParts(rd.page) === '', 'Anleitung nur mit Titel, ohne Ursache: Diagramm, Betroffene, Belege: ' + await ivSections(rd.page) + ' / ' + await bareParts(rd.page));
  await ivOpen(rd.page, rd.D.incidents.find((i) => i.type === 'ereignis').id);
  ok(await ivSections(rd.page) === 'iv-affected,iv-evidence' && await bareParts(rd.page) === '', 'Ereignisvorfall nur mit Titel: Betroffene und Belege: ' + await ivSections(rd.page) + ' / ' + await bareParts(rd.page));
  await ivOpen(rd.page, rd.D.incidents.find((i) => i.lead === 'memory').id);
  ok(await ivSections(rd.page) === 'iv-what,iv-cause,iv-affected,iv-evidence' && await bareParts(rd.page) === '', 'ohne Schritte, Abhilfe und Ansprechpartner kein Abschnitt "Was ist zu tun": ' + await ivSections(rd.page));
  await ivOpen(rd.page, rd.D.incidents.find((i) => i.lead === 'disk').id);
  ok(await ivSections(rd.page) === IV_SECTIONS && await rd.page.locator('#incident ol.checks').count() === 0 && await rd.page.locator('#incident .remedies li').count() > 0 && await bareParts(rd.page) === '', 'nur Abhilfe: der Abschnitt ohne leere Schrittliste');
  // the numbers of items shown before the fold come from the report data when it carries them
  const rs = rd.D.incidents.find((i) => i.lead === 'share'), rshown = (await ivOpen(rd.page, rs.id), await stepsShown(rd.page));
  // (literal adapted, P3-R1: the catalogue after its round 3 gives this incident six checks, not seven; the number comes from the data.
  // Since its round 5 it has three proposals instead of one: one is shown, the line folds the other two)
  ok(rs.guide.checks.length >= 4 && rs.guide.remedies.length >= 1 && rshown.checks === 2 && rshown.remedies === 1 && rshown.folds.join('|') === foldsOf(rs.guide, 2, 1) && rshown.folds[0] === `Weitere ${rs.guide.checks.length - 2} Prüfschritte anzeigen` && await rd.page.locator('#incident ol.checks').nth(1).getAttribute('start') === '3', 'Zahl der gezeigten Schritte aus den Berichtsdaten (maxChecks, maxRemedies): ' + JSON.stringify(rshown) + ' statt ' + foldsOf(rs.guide, 2, 1));
  ok(rd.page.errors.length === 0, 'Skriptfehler fehlende Teile: ' + rd.page.errors.join(' | '));
  await rd.page.close();
  // incidents of the surroundings: a session with input delay over its target shows both values and no note; an endpoint alone
  // names no session and says why; without a measured input delay the note says so
  const um = await open(browser, patched(dir, 'report.html', 'report-iv-umfeld.html', (J) => {
    const c = J.incidents.find((i) => i.type === 'umfeld'); c.affected = [{ s: c.signals[0].s, peakMs: 612 }];
    const e = JSON.parse(JSON.stringify(c)), id = Math.max(...J.incidents.concat(J.before.incidents).map((i) => i.id)) + 1;
    Object.assign(e, { id, rank: 99, chronic: false, affected: [], ica: [], signals: [{ id: 'probe.connect', label: 'Oracle-Listener', resource: 'endpoint', instance: 'Oracle-Listener', s: -1, peak: 260, unit: 'ms', ideal: 'unter 50 ms', severity: 2, start: c.start, end: c.end }] });
    J.incidents.push(e); J.order.push(id);
  }), scheme), uc = um.D.incidents.find((i) => i.type === 'umfeld'), ue = um.D.incidents[um.D.incidents.length - 1];
  await ivOpen(um.page, uc.id);
  const urow = oneLine(await um.page.locator('#incident .iv-affected ul.aff > li').first().innerText());
  ok(urow.includes('▲ auffällig ICA Round Trip') && urow.includes('Eingabeverzögerung ◆ kritisch 612 ms') && await um.page.locator('#incident .iv-affected p.note').count() === 0, 'Umfeld mit Eingabeverzoegerung: beide Werte in der Zeile, keine Anmerkung: ' + urow);
  await ivOpen(um.page, ue.id);
  ok(await um.page.locator('#incident .iv-affected ul.aff').count() === 0 && (await um.page.locator('#incident .iv-affected p.note').innerText()).startsWith('Der Vorfall betrifft eine Gegenstelle, keine einzelne Sitzung') && await bareParts(um.page) === '', 'Umfeld nur mit Gegenstelle: Satz statt Liste');
  ok(um.page.errors.length === 0, 'Skriptfehler Umfeld: ' + um.page.errors.join(' | '));
  await um.page.close();
  const un2 = await open(browser, patched(dir, 'report.html', 'report-iv-umfeld-noinput.html', (J) => { J.unmeasured = { input: true, worker: [] }; }), scheme);
  await ivOpen(un2.page, un2.D.incidents.find((i) => i.type === 'umfeld').id);
  ok(await un2.page.locator('#incident .iv-affected ul.aff > li').count() === 1 && (await un2.page.locator('#incident .iv-affected p.note').innerText()) === 'Eingabeverzögerung nicht gemessen; ob Eingaben in diesen Sitzungen verzögert ankamen, ist nicht bestimmbar.', 'Umfeld ohne gemessene Eingabeverzoegerung: Liste und Anmerkung');
  await un2.page.close();
  // an incident before the capture whose classification does not carry the note: the first section says it (once)
  const bn = await open(browser, patched(dir, 'report.html', 'report-iv-before-note.html', (J) => { J.before.incidents[0].guide.userView = 'Vor der Messung aufgetreten, 1-mal.'; }), scheme);
  await ivOpen(bn.page, bn.D.before.incidents[0].id);
  ok((await bn.page.locator('#incident .iv-what .bnote').innerText()) === 'Für diese Zeit liegen keine Messwerte vor.' && (await bn.page.locator('#incident').innerText()).split('Für diese Zeit liegen keine Messwerte vor.').length === 2, 'vor der Messung: steht der Hinweis nicht in der Einordnung, steht er im ersten Abschnitt');
  await bn.page.close();
  // values of the report data are text, never markup
  const bad = '<img src=x onerror="window.__xss=1">';
  const x = await open(browser, patched(dir, 'report.html', 'report-iv-markup.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu'), g = c.guide;
    Object.assign(g, { title: 'Titel ' + bad, tech: 'Fach ' + bad, meaning: 'Bedeutung Engpass ' + bad, impact: 'Wirkung ' + bad, userView: 'Sicht ' + bad, fallback: true, contacts: [{ text: 'Kontakt ' + bad, source: 'Quelle3 ' + bad }] });
    Object.assign(g.checks[0], { text: 'Schritt ' + bad, where: 'Ort ' + bad, sign: 'Merkmal ' + bad, source: 'Quelle1 ' + bad });
    Object.assign(g.remedies[0], { text: 'Abhilfe ' + bad, precondition: 'Bedingung ' + bad, source: 'Quelle2 ' + bad });
    c.causeText = 'Ursache ' + bad; c.text = 'Fachsatz ' + bad;
    J.guidance.fallbackNote = 'Auffang ' + bad; J.guidance.terms.Engpass = 'Erklaerung ' + bad;
  }), scheme), xc = x.D.incidents.find((i) => i.lead === 'cpu');
  await ivOpen(x.page, xc.id);
  await x.page.locator('#incident details.iv-evidence > summary').click();
  await x.page.locator('#incident .iv-meaning .term').hover();
  const xt = await x.page.locator('#incident').innerText();
  ok(await x.page.evaluate(() => window.__xss === undefined) && await x.page.locator('#incident img, .term-pop img').count() === 0, 'Vorfallsansicht: Markup aus den Daten wird nicht ausgefuehrt');
  for (const w of ['Titel', 'Fach', 'Bedeutung Engpass', 'Wirkung', 'Sicht', 'Kontakt', 'Quelle3', 'Schritt', 'Ort', 'Merkmal', 'Quelle1', 'Abhilfe', 'Bedingung', 'Quelle2', 'Ursache', 'Fachsatz', 'Auffang']) ok(xt.includes(w + ' ' + bad), 'Vorfallsansicht: Markup als Text: ' + w);
  ok((await x.page.locator('.term-pop').innerText()).includes('Erklaerung ' + bad), 'Erklaerung eines Begriffs: Markup als Text');
  ok(x.page.errors.length === 0, 'Skriptfehler Markup Vorfallsansicht: ' + x.page.errors.join(' | '));
  await x.page.close();
}

async function checkTerms(browser, dir, scheme) {                   // Fachbegriffe erklaeren sich: Ueberfahren, Tastaturfokus, Antippen
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme), iv = page.locator('#incident'), pop = page.locator('.term-pop');
  const mem = D.incidents.find((i) => i.lead === 'memory');
  await ivOpen(page, mem.id);
  const marked = await iv.locator('.term').evaluateAll((t) => t.map((x) => x.dataset.term));
  ok(marked.length > 0 && marked.every((t) => mem.guide.terms.includes(t) && D.guidance.terms[t]) && mem.guide.terms.every((t) => marked.includes(t)), 'die Begriffe der Anleitung sind in den Texten unterlegt: ' + marked.join(', ') + ' / ' + mem.guide.terms.join(', '));
  ok(await iv.evaluate((el) => [...el.querySelectorAll('.tx')].every((p) => { const t = [...p.querySelectorAll('.term')].map((x) => x.dataset.term); return new Set(t).size === t.length; })) && await iv.locator('.tx').count() > 10, 'je Absatz ist ein Begriff hoechstens einmal unterlegt');
  ok(await iv.locator('.iv-title .term, .iv-tech .term, .iv-meta .term, .iv-evidence .term, .src .term').count() === 0, 'Titel, Kopfzeile, Quellen und Belege ohne Unterlegung');
  const first = iv.locator('.term').first(), word = await first.getAttribute('data-term');
  ok(await pop.isHidden() && await first.getAttribute('tabindex') === '0' && await first.getAttribute('aria-describedby') === await pop.getAttribute('id') && await pop.getAttribute('role') === 'tooltip', 'Begriff mit der Tastatur erreichbar, Erklaerung zunaechst verborgen');
  await first.hover();
  ok(await pop.isVisible() && (await pop.innerText()).includes(D.guidance.terms[word]) && (await pop.innerText()).includes(word), 'Ueberfahren zeigt die Erklaerung aus dem Katalog');
  const pb = await pop.boundingBox(), fb = await first.boundingBox();
  ok(pb.x >= 0 && pb.x + pb.width <= 1400 && (pb.y >= fb.y + fb.height - 1 || pb.y + pb.height <= fb.y + 1), 'Erklaerung steht am Begriff, ohne ihn zu verdecken: ' + JSON.stringify([pb, fb]));
  await page.mouse.move(5, 5);
  ok(await pop.isHidden(), 'Erklaerung verschwindet, wenn der Zeiger den Begriff verlaesst');
  await first.focus();
  ok(await pop.isVisible() && (await pop.innerText()).includes(D.guidance.terms[word]), 'Tastaturfokus zeigt die Erklaerung');
  await page.keyboard.press('Escape');
  ok(await pop.isHidden() && await iv.isVisible(), 'Esc schliesst zuerst die Erklaerung, nicht die Vorfallsansicht');
  const other = iv.locator('.term:not([data-term="' + word + '"])').first(), word2 = await other.getAttribute('data-term');
  await other.focus();
  ok(await pop.isVisible() && (await pop.innerText()).includes(D.guidance.terms[word2]) && !(await pop.innerText()).includes(D.guidance.terms[word]), 'ein anderer Begriff zeigt seine eigene Erklaerung: ' + word2);
  await page.locator('#ivBack').focus();
  ok(await pop.isHidden(), 'Erklaerung verschwindet, wenn der Fokus den Begriff verlaesst');
  await page.close();
  // the same word twice in a paragraph, inflected, inside another word, and a term without an explanation
  const v = await open(browser, patched(dir, 'report.html', 'report-iv-terms.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu');
    c.guide.meaning = 'Ein Engpass, des Engpasses wegen, kein Dauerengpass; die vCPU zählt.'; c.guide.impact = 'Noch ein Engpass.';
    c.guide.terms = ['Engpass', 'vCPU', 'Unbekannt']; c.guide.checks[0].text = 'Unbekannt bleibt Text, der Engpass nicht';
  }), scheme), vc = v.D.incidents.find((i) => i.lead === 'cpu');
  await ivOpen(v.page, vc.id);
  const mt = await v.page.locator('#incident .iv-meaning .term').evaluateAll((t) => t.map((x) => x.dataset.term + '=' + x.textContent));
  ok(mt.join() === 'Engpass=Engpass,vCPU=vCPU' && (await v.page.locator('#incident .iv-meaning').innerText()) === vc.guide.meaning, 'einmal je Absatz, am Wortanfang, der Text bleibt wie geliefert: ' + mt.join());
  ok(await v.page.locator('#incident .iv-impact .term').count() === 1 && (await v.page.locator('#incident ol.checks > li').first().locator('.term').evaluateAll((t) => t.map((x) => x.dataset.term))).join() === 'Engpass', 'jeder Absatz fuer sich; ein Begriff ohne Erklaerung bleibt Text');
  await v.page.close();
  // touch: a tap shows the explanation, a tap beside it hides it
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, colorScheme: scheme }), touch = await ctx.newPage();
  await touch.goto('file://' + path.join(dir, 'report.html'));
  await touch.evaluate((i) => window.WP.openIncident(i), mem.id);
  const t1 = touch.locator('#incident .term').first();
  await t1.tap();
  const tp = await touch.locator('.term-pop').boundingBox();
  ok(await touch.locator('.term-pop').isVisible() && tp.x >= 0 && tp.x + tp.width <= 390, 'Antippen zeigt die Erklaerung, auch schmal im Bild: ' + JSON.stringify(tp));
  await touch.locator('#incident .iv-title').tap();
  ok(await touch.locator('.term-pop').isHidden(), 'Antippen daneben schliesst die Erklaerung');
  await ctx.close();
}

async function checkCopy(browser, dir, scheme) {                    // Kopieren: Text wie geliefert, Schalter "ohne Namen", Bestaetigung, maskierter Bericht
  const { ctx, page, D } = await openWatched(browser, path.join(dir, 'report.html'), scheme);
  const byId = new Map(D.incidents.concat(D.before.incidents).map((i) => [i.id, i])), last = () => page.evaluate(() => window.__copied.at(-1)), iv = page.locator('#incident');
  const first = byId.get(D.cards[0]), btn = page.locator(`#cards .card.inc[data-id="${first.id}"] .card-copy`);
  const w0 = (await btn.boundingBox()).width;
  await btn.click();
  ok(await last() === first.copy.named && first.copy.named.includes('\r\n') && first.copy.named.split('\r\n').every((l) => l.length <= 78), 'Karte kopiert ihren Text wie geliefert, mit seinen Zeilenenden');
  ok((await btn.innerText()).includes('Kopiert') && Math.abs((await btn.boundingBox()).width - w0) < 1, 'Bestaetigung am Knopf, ohne dass er springt');
  await page.waitForTimeout(1900);
  ok((await btn.innerText()) === 'Kopieren', 'nach etwa 1,5 s wieder die Beschriftung');
  const lb = D.before.incidents[0];
  await page.click(`#beforeG .card.inc[data-id="${lb.id}"] .card-copy`);
  ok(await last() === lb.copy.named, 'Karte vor der Messung kopiert ihren Text');
  await page.click('#copyAll');
  ok(await last() === D.copyAll.named && (await page.locator('#copyAll').innerText()).includes('Kopiert'), 'Zusammenfassung der Messung mit Namen');
  // reworded: the comparison of two counts was true before this task; the one button of a row opens the incident view of its
  // incident and copies nothing
  const row = page.locator('#more .row').first(), rowId = await row.getAttribute('data-id'), copies = await page.evaluate(() => window.__copied.length);
  ok(await page.locator('#more .row').count() > 0 && await page.locator('#more .row button').count() === await page.locator('#more .row').count() && (await row.locator('button').innerText()) === 'Öffnen' && await page.locator('#more .row .card-copy').count() === 0, 'Zeilen der weiteren Vorfaelle haben nur "Oeffnen"');
  await row.locator('button').click();
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === rowId && await page.evaluate(() => window.WP.view) === 'guided' && await page.evaluate(() => window.__copied.length) === copies, '"Oeffnen" einer Zeile oeffnet die Vorfallsansicht ihres Vorfalls und kopiert nichts');
  await page.click('#ivBack'); await ivClosed(page);
  // the switch "ohne Namen" chooses the second version, on the cards and in the incident view
  await page.check('#anonSwitch');
  await btn.click();
  ok(await last() === first.copy.anonymous && first.copy.anonymous !== first.copy.named, 'ohne Namen: Karte');
  await page.click(`#cards .card.inc[data-id="${first.id}"] .card-open`);
  ok(await page.locator('#ivAnon').isChecked() && (await page.locator('label:has(#ivAnon)').innerText()).includes('ohne Namen'), 'der Schalter steht auch in der Vorfallsansicht und folgt dem des Lagebilds');
  await page.click('#ivCopy');
  ok(await last() === first.copy.anonymous, 'ohne Namen: Vorfallsansicht');
  await page.uncheck('#ivAnon'); await page.click('#ivCopy');
  ok(await last() === first.copy.named, 'mit Namen: Vorfallsansicht');
  await page.click('#ivBack'); await ivClosed(page);
  ok(!(await page.locator('#anonSwitch').isChecked()), 'der Schalter des Lagebilds folgt dem der Vorfallsansicht');
  ok(await page.evaluate(() => window.__exec) === 0, 'mit Zwischenablage kein aelterer Befehl');
  // the clipboard interface refuses: the older command through a hidden field hands over the text as delivered
  await page.evaluate(() => { navigator.clipboard.writeText = () => Promise.reject(new Error('nicht erlaubt')); });
  await btn.click();
  await page.waitForFunction(() => window.__exec === 1);
  const field = await page.evaluate(() => window.__execField);
  ok(await page.evaluate(() => window.__execData) === first.copy.named, 'aelterer Befehl: der Text wie geliefert, mit CR LF');
  ok(field[0] === 'TEXTAREA' && field[1] === first.copy.named.replace(/\r\n/g, '\n') && field[2] === 0 && field[3] === field[1].length, 'aelterer Befehl ueber ein Textfeld mit markiertem Text');
  ok(await page.locator('textarea').count() === 1 && (await btn.innerText()).includes('Kopiert') && await page.evaluate(() => document.activeElement.className).then((c) => c.includes('card-copy')), 'das versteckte Feld ist wieder entfernt, der Fokus bleibt am Knopf');
  // both ways fail: the dialog with the selected text; Esc closes the dialog, not the incident view
  await page.evaluate(() => { document.execCommand = () => { throw new Error('nicht unterstuetzt'); }; });
  await page.click(`#cards .card.inc[data-id="${first.id}"] .card-open`);
  await page.click('#ivCopy');
  const dlg = page.locator('#copyFallback');
  await dlg.locator('textarea').waitFor();
  ok(await dlg.isVisible() && await dlg.locator('textarea').evaluate((t) => t.value) === first.copy.named.replace(/\r\n/g, '\n') && (await dlg.locator('button').innerText()) === 'Schließen', 'Ausweichfeld mit dem Text und "Schliessen"');
  ok(await dlg.locator('textarea').evaluate((t) => t === document.activeElement && t.selectionStart === 0 && t.selectionEnd === t.value.length && t.readOnly) && !(await page.locator('#ivCopy').innerText()).includes('Kopiert'), 'Text markiert und im Fokus, keine Bestaetigung am Knopf');
  const db = await dlg.boundingBox();
  ok(db.x >= 0 && db.y >= 0 && db.x + db.width <= 1400 && db.y + db.height <= 900, 'Ausweichfeld ganz im Bild: ' + JSON.stringify(db));
  await page.keyboard.press('Escape');
  ok(await dlg.isHidden() && await iv.isVisible(), 'Esc schliesst das Ausweichfeld, nicht die Vorfallsansicht');
  ok(await page.evaluate(() => document.activeElement.id) === 'ivCopy', 'nach Esc kehrt der Fokus zum Knopf zurueck (Task 11): ' + await page.evaluate(() => document.activeElement.id || document.activeElement.tagName));
  await page.click('#ivCopy'); await dlg.locator('textarea').waitFor(); await dlg.locator('button').click();
  ok(await dlg.isHidden() && await page.evaluate(() => document.activeElement.id) === 'ivCopy', '"Schliessen" schliesst das Ausweichfeld, der Fokus kehrt zum Knopf zurueck');
  ok(page.requests.length === 1 && page.errors.length === 0, 'Kopieren ohne Abruf und ohne Skriptfehler: ' + page.errors.join(' | '));
  await ctx.close();
  // a masked report has one version of each text: no switch, every copy takes it
  const m = await openWatched(browser, path.join(dir, 'report-masked.html'), scheme), mc = m.D.incidents.find((i) => i.lead === 'cpu'), mlast = () => m.page.evaluate(() => window.__copied.at(-1));
  await m.page.click('#copyAll');
  ok(await mlast() === m.D.copyAll.named && m.D.copyAll.anonymous === null, 'maskiert: Zusammenfassung');
  await m.page.click(`#cards .card.inc[data-id="${mc.id}"] .card-copy`);
  ok(await mlast() === mc.copy.named && mc.copy.anonymous === null, 'maskiert: Karte');
  await m.page.click(`#cards .card.inc[data-id="${mc.id}"] .card-open`);
  ok(await m.page.locator('#ivAnon').count() === 0 && await m.page.locator('#anonSwitch').count() === 0, 'maskiert: kein Schalter, auch nicht in der Vorfallsansicht');
  await m.page.click('#ivCopy');
  ok(await mlast() === mc.copy.named && !mc.copy.named.includes('user0') && m.page.errors.length === 0, 'maskiert: Vorfallsansicht kopiert den maskierten Text');
  await m.ctx.close();
}

async function checkIncidentNav(browser, dir, scheme) {             // Oeffnen und Verlassen der Vorfallsansicht: Zurueck, Esc, Zurueck-Taste des Browsers
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme), iv = page.locator('#incident');
  // a card whose button is in the picture after scrolling, so that the click does not scroll
  await page.evaluate(() => window.scrollTo(0, document.getElementById('cards').getBoundingClientRect().top + window.scrollY - 200));
  const y0 = await page.evaluate(() => window.scrollY), id = D.cards[1], opener = `#cards .card.inc[data-id="${id}"] .card-open`;
  const place = async () => [await page.evaluate(() => window.scrollY), await iv.isHidden(), await page.locator('#band').isVisible() || await page.locator('#cards').isVisible(), await page.evaluate(() => window.WP.incident)].join();
  const home = [y0, true, true, ''].join();
  ok(y0 > 300, 'Lagebild gescrollt: ' + y0);
  await page.click(opener);
  ok(await iv.isVisible() && await page.evaluate(() => window.scrollY) === 0 && await page.evaluate(() => document.activeElement.className).then((c) => c.includes('iv-title')), 'Vorfallsansicht oben, der Fokus steht auf ihrem Titel');
  await page.click('#ivBack'); await ivClosed(page);
  ok(await place() === home, '"Zurueck zum Lagebild" fuehrt an die Stelle zurueck: ' + await place());
  ok(await page.evaluate((sel) => document.activeElement === document.querySelector(sel), opener), 'der Fokus steht wieder auf dem Knopf, der geoeffnet hat');
  await page.keyboard.press('Enter');
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(id), 'Eingabetaste auf dem Knopf oeffnet wieder');
  await page.keyboard.press('Escape'); await ivClosed(page);
  ok(await place() === home, 'Esc schliesst die Vorfallsansicht: ' + await place());
  await page.click(opener);
  await page.goBack(); await ivClosed(page);
  ok(await place() === home, 'die Zurueck-Taste des Browsers schliesst die Vorfallsansicht: ' + await place());
  await page.goForward();
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(id) && await page.evaluate(() => window.WP.incident) === id, 'Vorwaerts oeffnet sie wieder');
  // "Naechster Vorfall" does not lengthen the way back
  await page.click('#ivNext'); await page.click('#ivNext');
  await page.goBack(); await ivClosed(page);
  ok(await place() === home, 'nach "Naechster Vorfall" fuehrt ein Schritt zurueck zum Lagebild: ' + await place());
  // from the incident view to the expert view and back with the browser
  await page.click(opener); await ivExpert(page);
  ok(await page.evaluate(() => window.WP.view) === 'expert' && await page.locator(`#incList .inc[data-id="${id}"].selected`).isVisible(), 'In der Expertenansicht zeigen hebt den Vorfall dort hervor');
  await page.goBack();
  await page.waitForFunction(() => window.WP.view === 'guided');
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(id), 'Zurueck-Taste: aus der Expertenansicht wieder in die Vorfallsansicht');
  await page.goBack(); await ivClosed(page);
  ok(await place() === home, 'Zurueck-Taste: dann zum Lagebild: ' + await place());
  // the functions of the page
  await page.evaluate((i) => window.WP.openIncident(i), id);
  ok(await iv.isVisible() && await page.evaluate(() => window.WP.incident) === id, 'WP.openIncident');
  await page.evaluate(() => window.WP.openIncident(987654));
  ok(await iv.getAttribute('data-id') === String(id) && page.errors.length === 0, 'unbekannter Vorfall aendert nichts');
  await page.evaluate(() => window.WP.closeIncident()); await ivClosed(page);
  ok(await place() === home, 'WP.closeIncident: ' + await place());
  await page.evaluate(() => window.WP.closeIncident());
  ok(await place() === home && await page.evaluate(() => history.state === null), 'WP.closeIncident ohne offene Ansicht aendert nichts');
  // Opened from the expert view, the incident view returns there: with its button (which says so), with Esc and with the back
  // button of the browser; the expert view stands where it stood. (Reworded: Esc led to the situation summary before.)
  await showExpert(page);
  await page.evaluate(() => window.scrollTo(0, 260));
  const state = () => page.evaluate(() => JSON.stringify(history.state)), inExpert = async () => [await page.evaluate(() => window.WP.view), await page.locator('#expert').isVisible(), await iv.isHidden(), await page.evaluate(() => window.WP.incident), await page.evaluate(() => window.scrollY)].join();
  await page.evaluate((i) => window.WP.openIncident(i), id);
  ok(await page.evaluate(() => window.WP.view) === 'guided' && await iv.isVisible(), 'WP.openIncident aus der Expertenansicht wechselt in die gefuehrte');
  ok(oneLine(await page.locator('#ivBack').innerText()).includes('Zurück zur Expertenansicht') && await state() === JSON.stringify({ wpIncident: id, wpFrom: 'expert' }), 'aus der Expertenansicht geoeffnet: der Knopf nennt das Ziel, der Schritt ist der der Vorfallsansicht und nennt ihre Herkunft: ' + await state());
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => window.WP.incident === null && history.state !== null && history.state.wpIncident == null);
  ok(await inExpert() === 'expert,true,true,,260' && await state() === JSON.stringify({ wpView: 'expert' }), 'Esc fuehrt in die Expertenansicht zurueck, an ihre Stelle: ' + await inExpert() + ' ' + await state());
  await page.evaluate((i) => window.WP.openIncident(i), id);
  await page.click('#ivBack');
  await page.waitForFunction(() => window.WP.incident === null && history.state !== null && history.state.wpIncident == null);
  ok(await inExpert() === 'expert,true,true,,260', '"Zurueck zur Expertenansicht" fuehrt dorthin zurueck: ' + await inExpert());
  await page.evaluate((i) => window.WP.openIncident(i), id);
  await page.goBack();
  await page.waitForFunction(() => window.WP.view === 'expert');
  ok(await inExpert() === 'expert,true,true,,260', 'die Zurueck-Taste des Browsers fuehrt in die Expertenansicht zurueck: ' + await inExpert());
  await page.goForward();
  await page.waitForFunction(() => window.WP.view === 'guided');
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(id), 'Vorwaerts zeigt die Vorfallsansicht wieder');
  // shown again by a step of the history (forward, reload), the view still knows where it was opened from: label and target agree
  const backLabel = async () => oneLine(await page.locator('#ivBack').innerText());
  ok((await backLabel()).includes('Zurück zur Expertenansicht'), 'nach Vorwaerts nennt der Knopf wieder die Expertenansicht: ' + await backLabel());
  await page.click('#ivBack');
  await page.waitForFunction(() => window.WP.incident === null && history.state !== null && history.state.wpIncident == null);
  ok(await inExpert() === 'expert,true,true,,260' && await state() === JSON.stringify({ wpView: 'expert' }), 'und fuehrt dorthin: ' + await inExpert());
  // (Task 11) closing the incident view is a step of its own: the back button of the browser shows the incident view again
  // (before: closing went back in the history, and the forward button showed it again)
  await page.goBack();
  await page.waitForFunction(() => window.WP.view === 'guided');
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(id) && (await backLabel()).includes('Zurück zur Expertenansicht'), 'nach dem Schliessen zeigt die Zurueck-Taste die Vorfallsansicht wieder, mit ihrer Herkunft');
  await page.reload();
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(id) && (await backLabel()).includes('Zurück zur Expertenansicht'), 'nach dem Neuladen ebenso: ' + await backLabel());
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => window.WP.incident === null && history.state !== null && history.state.wpIncident == null);
  ok(await page.evaluate(() => window.WP.view) === 'expert' && await page.locator('#expert').isVisible() && await iv.isHidden(), 'Esc fuehrt nach dem Neuladen in die Expertenansicht');
  // "Naechster Vorfall" keeps the origin
  await page.evaluate((i) => window.WP.openIncident(i), id);
  await page.click('#ivNext');
  ok((await backLabel()).includes('Zurück zur Expertenansicht') && JSON.parse(await state()).wpFrom === 'expert', '"Naechster Vorfall" behaelt die Herkunft: ' + await state());
  await page.goBack();
  await page.waitForFunction(() => window.WP.view === 'expert');
  // back in the situation summary, the incident view opened there returns there again
  await showGuided(page);
  ok(await iv.isHidden() && await page.locator('#band').isVisible(), 'nach der Rueckkehr steht in der gefuehrten Ansicht das Lagebild');
  await page.click(opener);
  ok(oneLine(await page.locator('#ivBack').innerText()).includes('Zurück zum Lagebild'), 'aus dem Lagebild geoeffnet: "Zurueck zum Lagebild"');
  await page.goBack(); await ivClosed(page);
  ok(await page.evaluate(() => window.WP.view) === 'guided' && await page.locator('#band').isVisible() && await page.evaluate(() => history.state) === null, 'und die Zurueck-Taste fuehrt zum Lagebild, der Schritt davor nennt wieder die gefuehrte Ansicht');
  // A step of the history is true to the screen: after the way into the expert view and back with the switch of the head bar,
  // "Naechster Vorfall" writes the step of the incident view alone, so a reload shows that incident (it showed the expert view)
  // (Task 11: the switch of the head bar is a step of its own; before, the step stayed the one of the expert view)
  await page.click(opener); await ivExpert(page); await showGuided(page);
  ok(await iv.isVisible() && await state() === JSON.stringify({ wpIncident: id }) && (await page.evaluate(() => location.hash)) === '#v=guided&i=' + id + await page.evaluate(() => window.WP.zoom ? `&t0=${window.WP.zoom.t0}&t1=${window.WP.zoom.t1}` : ''), 'zurueck ueber die Kopfleiste: ein Schritt der Vorfallsansicht: ' + await state());
  await page.click('#ivNext');
  const nextId = Number(await iv.getAttribute('data-id'));
  ok(nextId !== id && await state() === JSON.stringify({ wpIncident: nextId }), '"Naechster Vorfall" schreibt den Schritt der Vorfallsansicht allein: ' + await state());
  await page.reload();
  ok(await page.evaluate(() => window.WP.view) === 'guided' && await iv.isVisible() && await iv.getAttribute('data-id') === String(nextId) && await page.locator('#expert').isHidden(), 'Neuladen zeigt die Vorfallsansicht des naechsten Vorfalls');
  // (Task 11: one step back is the expert view the reader came back from with the head bar, the second the incident before)
  await page.goBack();
  await page.waitForFunction(() => window.WP.view === 'expert');
  ok(await page.locator('#expert').isVisible() && (await page.evaluate(() => location.hash)).startsWith('#v=expert'), 'ein Schritt zurueck: die Expertenansicht, aus der die Kopfleiste zurueckfuehrte');
  await page.goBack();
  await page.waitForFunction((i) => window.WP.incident === i && window.WP.view === 'guided', id);
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(id), 'noch ein Schritt zurueck: der Vorfall davor');
  await page.goForward(); await page.waitForFunction(() => window.WP.view === 'expert');
  await page.goForward();
  await page.waitForFunction((i) => window.WP.incident === i && window.WP.view === 'guided', nextId);
  // "Zurueck zum Lagebild" leads to the situation summary (Task 11: as a step of its own, before: back over every step of the
  // incident view)
  await page.click('#ivBack'); await ivClosed(page);
  ok(await iv.isHidden() && await page.locator('#band').isVisible() && await page.evaluate(() => history.state) === null && (await page.evaluate(() => location.hash)).startsWith('#v=guided') && !(await page.evaluate(() => location.hash)).includes('i='), '"Zurueck zum Lagebild" fuehrt zum Lagebild, die Adresse nennt keinen Vorfall');
  // the way into the expert view twice is one step
  await page.click(opener); await ivExpert(page); await showGuided(page); await ivExpert(page);
  await page.goBack();
  await page.waitForFunction(() => window.WP.view === 'guided');
  ok(await iv.isVisible() && await state() === JSON.stringify({ wpIncident: id }), 'zweimal in die Expertenansicht: ein Schritt zurueck zeigt die Vorfallsansicht');
  await page.keyboard.press('Escape'); await ivClosed(page);
  // Esc in the expert view does not close the incident view behind it
  await page.click(opener); await showExpert(page); await page.keyboard.press('Escape'); await showGuided(page);
  ok(await iv.isVisible(), 'Esc in der Expertenansicht laesst die Vorfallsansicht stehen');
  // a reload keeps the place
  await page.reload();
  ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(id), 'Neuladen zeigt dieselbe Vorfallsansicht');
  await page.click('#ivBack'); await ivClosed(page);
  ok(await iv.isHidden() && await page.locator('#band').isVisible(), 'und "Zurueck" fuehrt zum Lagebild');
  // every way in: band, card, row of the further incidents, mark of the timeline and its word, card before the capture
  const ways = [['#openTop', D.lagebild.top], [`#more .row[data-id="${D.more[0].ids[0]}"] .row-open`, D.more[0].ids[0]], [`#beforeG .card.inc[data-id="${D.before.incidents[1].id}"] .card-open`, D.before.incidents[1].id],
    [`#timeline .mark-word[data-incident="${D.incidents.find((i) => i.type === 'ereignis').id}"]`, D.incidents.find((i) => i.type === 'ereignis').id]];
  for (const [sel, wid] of ways) {
    await page.click(sel);
    ok(await iv.isVisible() && await iv.getAttribute('data-id') === String(wid) && await page.evaluate(() => window.WP.view) === 'guided', 'oeffnet die Vorfallsansicht: ' + sel);
    await page.click('#ivBack'); await ivClosed(page);
  }
  ok(page.errors.length === 0, 'Skriptfehler Oeffnen und Verlassen: ' + page.errors.join(' | '));
  await page.close();
  // narrow: one column without sideways scrolling, the chart under the text
  const narrow = await browser.newPage({ viewport: { width: 390, height: 844 }, colorScheme: scheme });
  await narrow.goto('file://' + path.join(dir, 'report.html'));
  for (const nid of [D.incidents.find((i) => i.lead === 'cpu').id, D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print').id]) {
    await narrow.evaluate((i) => { window.WP.openIncident(i); document.querySelector('#incident details.iv-evidence').open = true; }, nid);
    const w = await narrow.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
    ok(w[0] <= w[1], 'Vorfallsansicht schmal ohne seitliches Rollen: ' + w.join(' > '));
  }
  await narrow.evaluate((i) => window.WP.openIncident(i), D.incidents.find((i) => i.lead === 'cpu').id);
  const nt = await narrow.locator('#incident .iv-text').boundingBox(), nc = await narrow.locator('#incident .iv-chart').boundingBox();
  ok(nc.y >= nt.y + nt.height && nc.x + nc.width <= 390 && await narrow.locator('#incident .iv-chart svg path').count() > 0, 'schmal: Diagramm unter dem Text');
  const nb = await narrow.locator('#incident .iv-actions, #incident .iv-nav').evaluateAll((els) => els.every((e) => e.getBoundingClientRect().right <= 390));
  ok(nb, 'schmal: Knoepfe brechen um');
  await narrow.close();
}

async function checkPrint(browser, dir, scheme) {                   // Drucken druckt die Ansicht auf dem Bildschirm (P3-R51)
  const { page, D } = await open(browser, patched(dir, 'report.html', 'report-print-groups.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu'), base = Math.max(...J.incidents.concat(J.before.incidents).map((i) => i.id)), ids = [1, 2, 3].map((k) => base + k);
    ids.forEach((id, k) => J.incidents.push(Object.assign({}, c, { id, rank: 100 + k, start: c.start + (k + 1) * 600000, end: c.end + (k + 1) * 600000 })));
    J.order = J.order.concat(ids); J.more.unshift({ label: '3-mal ' + c.guide.title, situation: 'cpu', ids });
  }), scheme);
  const folded = () => page.evaluate(() => [...document.querySelectorAll('#measured, #qualityG, #more details.group, #incident details.iv-evidence')].map((d) => d.open).join());
  // the page learns of the medium with the next rendering
  const media = async (m) => { await page.emulateMedia({ media: m }); await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)))); };
  // guided view: the folded areas are open on paper and folded again afterwards
  ok(await folded() === 'false,false,false', 'gefuehrte Ansicht: Bereiche am Bildschirm eingeklappt');
  await media('print');
  ok(await folded() === 'true,true,true' && await page.locator('#measuredBody').isVisible() && await page.locator('#qualityGBody table').isVisible() && await page.locator('#more details.group .row:visible').count() === 3, 'gefuehrte Ansicht: im Druck sind die eingeklappten Bereiche offen');
  ok(await page.locator('#band').isVisible() && await page.locator('#cards .card.inc').first().isVisible() && await page.locator('#expert').isHidden() && await page.locator('#viewSwitch').isHidden(), 'gefuehrte Ansicht: gedruckt wird die Ansicht auf dem Bildschirm, ohne Umschalter');
  await media('screen');
  ok(await folded() === 'false,false,false', 'gefuehrte Ansicht: nach dem Druck wieder eingeklappt');
  await page.click('#measured > summary');
  await media('print'); await media('screen');
  ok(await folded() === 'false,true,false', 'ein vom Leser geoeffneter Bereich bleibt nach dem Druck offen: ' + await folded());
  // incident view: the evidence is open on paper
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  await ivOpen(page, cpu.id);
  ok((await folded()).endsWith(',false'), 'Vorfallsansicht: Belege am Bildschirm eingeklappt');
  await media('print');
  ok((await folded()).endsWith(',true') && (await page.locator('#incident .iv-evidence .contributors').innerText()).includes('EXCEL.EXE') && await page.locator('#incident .iv-evidence .sigcharts svg path').count() > 0, 'Vorfallsansicht: im Druck sind die Belege offen, mit Diagrammen');
  ok(await page.locator('#incident .iv-title').isVisible() && await page.locator('#incident .iv-todo ol.checks').first().isVisible() && await page.locator('#band').isHidden() && await page.locator('#cards').isHidden() && await page.locator('#expert').isHidden(), 'Vorfallsansicht: gedruckt wird nur sie');
  ok(await page.locator('#ivBack').isHidden() && await page.locator('#ivCopy').isHidden() && await page.locator('#ivExpert').isHidden(), 'Vorfallsansicht: Knoepfe werden nicht gedruckt');
  const more = () => page.locator('#incident .iv-todo details.morefold').evaluateAll((d) => d.map((x) => x.open).join());
  ok(await more() === 'true,true' && (await stepsShown(page)).checks === cpu.guide.checks.length && (await stepsShown(page)).remedies === cpu.guide.remedies.length && await page.locator('#incident details.morefold > summary:visible').count() === 0, 'Vorfallsansicht: im Druck stehen alle Schritte und Vorschlaege da, ohne die Zeile "Weitere …"');
  // a chart card, a step and a proposal are not torn over a page break; the colour squares of a legend are printed
  const paper = await page.evaluate(() => { const cs = (sel) => getComputedStyle(document.querySelector(sel)), sq = cs('#incident .sigcharts .legend i');
    return [cs('#incident .iv-chart').breakInside, cs('#incident .sigcharts > .card').breakInside, cs('#incident ol.checks > li').breakInside, cs('#incident .remedies li').breakInside, sq.getPropertyValue('print-color-adjust') || sq.getPropertyValue('-webkit-print-color-adjust')].join(); });
  ok(paper === 'avoid,avoid,avoid,avoid,exact', 'Druck: Diagrammkarte, Schritt und Vorschlag ohne Seitenumbruch im Innern, Farbkaestchen der Legende gedruckt: ' + paper);
  await media('screen');
  ok((await folded()).endsWith(',false') && await page.locator('#ivBack').isVisible() && await more() === 'false,false', 'Vorfallsansicht: nach dem Druck wieder eingeklappt');
  // expert view: every tab, as before the two views
  await showExpert(page);
  await media('print');
  for (const t of TABS) ok(await page.locator('#xt-' + t).isVisible(), 'Expertenansicht: Reiter ' + t + ' wird gedruckt');
  ok(await page.evaluate(() => getComputedStyle(document.querySelector('#charts .grid2 > .card')).breakInside) === 'avoid', 'Expertenansicht: Diagrammkarte ohne Seitenumbruch im Innern');
  ok(await page.locator('#expert #xtabs').isHidden() && await page.locator('#guided').isHidden() && await page.locator('#chCpu svg path').count() > 0 && await page.locator('#sollist tbody tr').first().isVisible(), 'Expertenansicht: ohne Reiterleiste, Diagramme gezeichnet, gefuehrte Ansicht nicht gedruckt');
  ok(await page.locator('#rangeInfo').isVisible() && await page.locator('#rangeAll').isHidden() && await page.locator('#incList .inc:visible').count() === D.incidents.length && await page.locator('#incList .inc-guided:visible').count() === 0 && await page.locator('#tiles .tile').first().isVisible(),
    'Expertenansicht: gedruckt werden der Zeitraum, alle Vorfaelle und die Kacheln, ohne Knoepfe');
  await media('screen');
  ok(await page.locator('#xt-sollist').isVisible() && await page.locator('#xt-sessions').isHidden(), 'Expertenansicht: nach dem Druck wieder ein Reiter');
  ok(page.errors.length === 0, 'Skriptfehler Drucken: ' + page.errors.join(' | '));
  await page.close();
}

// headings of the page that stand more than one level below the heading before them
const headingJumps = (page) => page.evaluate(() => {
  const bad = []; let last = 0;
  for (const h of document.querySelectorAll('h1, h2, h3, h4, h5')) {
    if (!h.getClientRects().length) continue;
    const level = Number(h.tagName[1]);
    if (level > last + 1) bad.push(h.tagName + ' ' + h.textContent.trim().substring(0, 40));
    last = level;
  }
  return bad.join(' | ');
});
async function checkCarried(browser, dir, scheme) {                 // Punkte aus der Durchsicht der gefuehrten Ansicht (Task 8)
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  const scheme2 = () => page.evaluate(() => getComputedStyle(document.documentElement).colorScheme + ' ' + getComputedStyle(document.body).colorScheme);
  ok(await scheme2() === 'light light', 'gefuehrte Ansicht: helles Schema am Wurzelelement: ' + await scheme2());
  // headings without a jump; the folded areas are sections of their own
  await page.evaluate(() => { for (const d of document.querySelectorAll('#guided details')) d.open = true; });
  ok(await headingJumps(page) === '', 'gefuehrte Ansicht: Ueberschriften ohne Sprung: ' + await headingJumps(page));
  const outline = await page.evaluate(() => { let h2 = ''; const out = {}; for (const h of document.querySelectorAll('#guided h2, #guided h3')) { if (h.tagName === 'H2') h2 = h.textContent.trim(); else out[h.textContent.trim().replace(/ \(\d+\)$/, '')] = h2; } return out; });
  ok(outline['Gemessen'] === 'Was wurde gemessen, was nicht' && outline['Nicht gemessen'] === 'Was wurde gemessen, was nicht' && await page.locator('#measured > summary h2').count() === 1 && (await page.locator('#qualityG > summary h2').innerText()) === 'Messqualität', 'die eingeklappten Bereiche haben eigene Ueberschriften: ' + JSON.stringify(outline));
  ok(await page.locator('#qualityG h4').count() === 0 && await page.locator('#quality h4').count() === await page.locator('#qualityG h3').count(), 'Messqualitaet der gefuehrten Ansicht: Zwischenueberschriften eine Ebene unter ihrer Ueberschrift');
  await ivOpen(page, D.incidents.find((i) => i.lead === 'cpu').id);
  await page.locator('#incident details.iv-evidence > summary').click();
  ok(await headingJumps(page) === '', 'Vorfallsansicht: Ueberschriften ohne Sprung: ' + await headingJumps(page));
  // the timeline of the guided view shows the capture: no zoom band and no ring after the way through the expert view
  await ivExpert(page);
  ok(await page.evaluate(() => window.WP.zoom !== null) && await scheme2() === 'dark dark', 'Expertenansicht: Zeitraum gesetzt, dunkles Schema am Wurzelelement: ' + await scheme2());
  await showGuided(page); await page.click('#ivBack'); await ivClosed(page);
  ok(await page.locator('#timeline').isVisible() && await page.locator('#timeline .mark.open').count() === 0 && await page.locator('#timeline .tl-zoom:visible').count() === 0, 'Zeitleiste nach der Rueckkehr ohne Zoomband und ohne Ring');
  ok(await scheme2() === 'light light', 'zurueck in der gefuehrten Ansicht wieder hell');
  ok((await page.locator('#tlLegend').innerText()).includes('kritisch') && (await page.locator('#tlLegend').innerText()).includes('Klick auf eine Markierung öffnet den Vorfall.'), 'Legende mit Vorfaellen nennt die Schwere und den Klick');
  // the status mark of the compact rows has the size of the cards'
  const sizes = await page.evaluate(() => [getComputedStyle(document.querySelector('#more .row .status')).fontSize, getComputedStyle(document.querySelector('#cards .card-foot .status')).fontSize]);
  ok(sizes[0] === sizes[1] && sizes[0] === '13px', 'Statuskennzeichen der Zeilen so gross wie auf den Karten: ' + sizes.join(' '));
  // a card before the capture: date and time on one line of their own, the classification under it, the same on every card
  const tops = await page.locator('#beforeG .card.inc').evaluateAll((cards) => cards.map((c) => { const w = c.querySelector('.card-when'), v = c.querySelector('.card-view'), lh = parseFloat(getComputedStyle(v).lineHeight);
    return [Math.round(w.getBoundingClientRect().height / lh), Math.round(v.getBoundingClientRect().height / lh), w.getBoundingClientRect().bottom <= v.getBoundingClientRect().top + 1]; }));
  ok(tops.length === D.before.incidents.length && tops.every((t) => t[0] === 1 && t[1] <= 2 && t[2]) && D.before.incidents.some((i) => i.end > i.start), 'Karten vor der Messung: Zeit auf einer eigenen Zeile, Einordnung in hoechstens zwei: ' + JSON.stringify(tops));
  // the colours of band, hints and key figures are variables of the view
  const vars = await page.evaluate(() => { const b = getComputedStyle(document.body), g = (n) => b.getPropertyValue(n).trim(); return ['--tint-crit', '--tint-crit-edge', '--tint-warn', '--tint-warn-edge', '--tint-good', '--tint-good-edge', '--kpi', '--kpi-edge'].map(g); });
  ok(vars.every((v) => v !== ''), 'Farben von Band, Hinweis und Kennzahl als Variablen der Ansicht: ' + vars.join(' '));
  ok(page.errors.length === 0, 'Skriptfehler uebernommene Punkte: ' + page.errors.join(' | '));
  await page.close();
  const src = fs.readFileSync(path.join(dir, 'report.html'), 'utf8'), css = src.substring(src.indexOf('<style>'), src.indexOf('</style>'));
  ok(!/#(band|hints|kpis)[^{]*\{[^}]*(#[0-9a-f]{3,8}|rgba?\()/i.test(css) && !/\.(hint|kpi)\b[^{]*\{[^}]*(#[0-9a-f]{3,8}|rgba?\()/i.test(css), 'Band, Hinweis und Kennzahl ohne feste Farbwerte neben den Variablen');
  // no incident: the legend does not name marks that do not exist
  for (const name of ['report-none.html', 'report-spike.html']) {
    const n = await open(browser, path.join(dir, name), scheme), lg = await n.page.locator('#tlLegend').innerText();
    ok(n.D.incidents.length === 0 && !lg.includes('kritisch') && !lg.includes('auffällig') && !lg.includes('Klick auf eine Markierung'), name + ': ohne Vorfall keine Legende der Schwere: ' + lg);
    await n.page.close();
  }
  // "(-Skip …)" stays together in the list of what was not measured
  const na = await open(browser, path.join(dir, 'report-skip-none-alle.html'), scheme);
  const opts = await na.page.locator('#measured .notm li[data-skip] .opt').evaluateAll((o) => o.map((x) => [x.textContent, x.getClientRects().length, getComputedStyle(x).whiteSpace]));
  ok(opts.length === na.D.skipped.length && opts.every((o) => /^\(-Skip \S+\)$/.test(o[0]) && o[1] === 1 && o[2] === 'nowrap'), '"(-Skip …)" bricht in der Liste nicht um: ' + JSON.stringify(opts));
  await na.page.close();
  // optional parts of the data missing: the guided view stays empty there, the expert view works, nothing throws
  const r = await open(browser, patched(dir, 'report.html', 'report-guided-bare.html', (J) => { delete J.lagebild; delete J.cards; delete J.copyAll; delete J.guidance; J.more = [{ label: 'Gruppe ohne Kennungen' }, { label: 'Gruppe', ids: [J.order[0]] }]; J.incidents[0].guide = null; delete J.incidents[1].copy; }), scheme);
  ok(r.page.errors.length === 0, 'ohne Lagebild, Karten, Kopiertexte und Katalog: kein Skriptfehler: ' + r.page.errors.join(' | '));
  ok(await r.page.locator('#guided #timeline .mark').count() === r.D.incidents.length && await r.page.locator('#more > .group').count() === 1 && await r.page.locator('#more .row').count() === 1 && await r.page.locator('#kpis .kpi').count() === 5 && (await r.page.locator('#kpis .kpi .num').allInnerTexts()).every((t) => t === '–'), 'ohne Lagebild: Zeitleiste, Liste und Kennzahlen stehen, eine Gruppe ohne Kennungen entfaellt');
  await r.page.click('#copyAll');
  await ivOpen(r.page, r.D.incidents[0].id); await r.page.click('#ivCopy'); await ivOpen(r.page, r.D.incidents[1].id); await r.page.click('#ivCopy'); await ivExpert(r.page);
  ok(await r.page.evaluate(() => window.WP.view) === 'expert' && (await r.page.locator('#rangeInfo').innerText()).startsWith('Zeitraum') && await r.page.locator('#rangeAll').isEnabled() && await r.page.locator('#incList .inc').count() === r.D.incidents.length && await r.page.locator(`#incList .inc[data-id="${r.D.incidents[1].id}"].selected`).count() === 1 && await r.page.locator('#chCpu svg path').count() > 0, 'ohne Lagebild: die Expertenansicht arbeitet');
  ok(r.page.errors.length === 0, 'ohne optionale Teile: kein Skriptfehler: ' + r.page.errors.join(' | '));
  await r.page.close();
}

// The label of each target line of a chart and the number of points of its measured lines that lie under the label.
const labelCovers = (page, chart) => page.locator(chart).evaluate((host) => {
  const svg = host.querySelector('svg'), out = [];
  for (const t of svg.querySelectorAll('.band-warn text, .band-crit text')) {
    const b = t.getBBox(); let n = 0;
    for (const p of svg.querySelectorAll('g[clip-path] path:not(.fail)')) {
      for (let d = 0, len = p.getTotalLength(); d <= len; d += 2) { const q = p.getPointAtLength(d); if (q.x >= b.x && q.x <= b.x + b.width && q.y >= b.y + 2 && q.y <= b.y + b.height - 2) n++; }
    }
    out.push(t.textContent.trim() + ': ' + n);
  }
  return out.join(' | ');
});
async function checkIncidentLayout(browser, dir, scheme) {          // Vorfallsansicht: Beschriftung der Soll-Linien, Status mit Wort, Listen der Belege
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme), iv = page.locator('#incident'), cpu = D.incidents.find((i) => i.lead === 'cpu');
  const de1 = (v) => v.toLocaleString('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  await ivOpen(page, cpu.id);
  // the labels of the target lines do not lie on the measured line (the critical one covered the plateau of the incident)
  const free = '▲ auffällig ab 75 %: 0 | ◆ kritisch ab 90 %: 0';
  ok(await labelCovers(page, '#incident .iv-plot') === free, 'Diagramm der Vorfallsansicht: die Beschriftung der Soll-Linien verdeckt die Messlinie nicht: ' + await labelCovers(page, '#incident .iv-plot'));
  const lab = await page.locator('#incident .iv-plot svg').evaluate((svg) => [...svg.querySelectorAll('.band-warn, .band-crit')].map((g) => { const t = g.querySelector('text').getBBox(), y = Number(g.querySelector('line').getAttribute('y1')), c = svg.querySelector('clipPath rect');
    return Math.min(Math.abs(t.y + t.height - y), Math.abs(t.y - y)) < 6 && t.x >= Number(c.getAttribute('x')) && t.x + t.width <= Number(c.getAttribute('x')) + Number(c.getAttribute('width')); }));
  ok(lab.length === 2 && lab.every(Boolean), 'die Beschriftung bleibt an ihrer Linie und im Diagramm');
  await iv.locator('details.iv-evidence > summary').click();
  ok(await labelCovers(page, '#incident .sigcharts .card >> nth=0') === free, 'Diagramm in den Belegen: ebenso: ' + await labelCovers(page, '#incident .sigcharts .card >> nth=0'));
  // status as symbol and word in the lists of the evidence
  const dl = iv.locator('.iv-evbody .evidence ul.vals').first(), nums = (await dl.locator('li .num').allInnerTexts()).map(oneLine);
  ok(nums.length === cpu.delayProcs.length && nums.every((t, k) => t === (cpu.delayProcs[k].maxMs >= 500 ? '◆ kritisch ' : '▲ auffällig ') + deNum(cpu.delayProcs[k].maxMs) + ' ms') && await iv.locator('.iv-evbody .evidence .sig[title]').count() === 0, 'Belege: hoechste Eingabeverzoegerung je Prozess mit Status als Symbol und Wort: ' + nums.join(' / '));
  // an endpoint whose name ends with its kind does not repeat the kind
  const eps = (await iv.locator('.iv-evbody .evidence ul.vals').nth(1).locator('li').allInnerTexts()).map(oneLine), kind = (e) => e.name.toLowerCase().endsWith(e.role.toLowerCase()) ? '' : ' ' + e.role;
  ok(cpu.endpoints.some((e) => e.name !== e.role && !kind(e)) && cpu.endpoints.some((e) => kind(e)) && eps.join('|') === cpu.endpoints.map((e) => e.name + kind(e) + ' ' + de1(e.maxMs) + ' ms').join('|') && !eps.join('|').includes('Proxy Proxy'), 'Gegenstellen: die Art steht nicht noch einmal hinter einem Namen, der mit ihr endet: ' + eps.join(' | '));
  ok(page.errors.length === 0, 'Skriptfehler Gestaltung der Vorfallsansicht: ' + page.errors.join(' | '));
  await page.close();
  // 1000 px: the rows of the list wrap the same way, the value stands in its own column at the right of the first line
  const mid = await browser.newPage({ viewport: { width: 1000, height: 700 }, colorScheme: scheme });
  await mid.goto('file://' + path.join(dir, 'report.html'));
  await mid.evaluate((i) => { window.WP.openIncident(i); document.querySelector('#incident details.iv-evidence').open = true; }, cpu.id);
  const rows = await mid.locator('#incident .iv-evbody .evidence ul.vals').first().locator('li').evaluateAll((ls) => ls.map((li) => { const r = li.getBoundingClientRect(), n = li.querySelector('.num').getBoundingClientRect(); return [Math.round(n.top - r.top), Math.round(r.right - n.right), Math.round(n.height)]; }));
  ok(rows.length === cpu.delayProcs.length && rows.every((r) => r[0] <= 4 && r[1] <= 1 && r[2] < 30), '1000 px: der Wert jeder Zeile steht rechts in der ersten Zeile, auf einer Zeile: ' + JSON.stringify(rows));
  await mid.close();
  // 390 px: the same for the labels of the small chart
  const narrow = await browser.newPage({ viewport: { width: 390, height: 844 }, colorScheme: scheme });
  await narrow.goto('file://' + path.join(dir, 'report.html'));
  await narrow.evaluate((i) => window.WP.openIncident(i), cpu.id);
  ok(await labelCovers(narrow, '#incident .iv-plot') === free, 'schmal: die Beschriftung der Soll-Linien verdeckt die Messlinie nicht: ' + await labelCovers(narrow, '#incident .iv-plot'));
  await narrow.close();
  // (carried from the re-review of Task 9) the incidents of a share, a drive, a profile container, the memory and a delay: no
  // label lies on a measured line, two labels never touch, at 1400 and at 390 px; the width of a label is the measured one
  const picks = [['Freigabe', (i) => i.lead === 'share'], ['Laufwerk', (i) => i.lead === 'disk'], ['Profil', (i) => i.lead === 'profile'], ['Arbeitsspeicher', (i) => i.lead === 'memory'], ['Verzoegerung', (i) => i.type === 'ohne-engpass' && i.affected.length > 1]];
  for (const [width, height] of [[1400, 900], [390, 844]]) {
    const lp = await browser.newPage({ viewport: { width, height }, colorScheme: scheme });
    await lp.goto('file://' + path.join(dir, 'report.html'));
    for (const [name, pick] of picks) {
      await lp.evaluate((i) => window.WP.openIncident(i), D.incidents.find(pick).id);
      const cov = await labelCovers(lp, '#incident .iv-plot'), faults = await labelFaults(lp, '#incident .iv-plot');
      ok(cov !== '' && cov.split(' | ').every((c) => c.endsWith(': 0')) && faults === '', `${width} px, ${name}: Beschriftungen der Soll-Linien frei von der Messlinie und voneinander: ${cov} ${faults}`);
    }
    const est = await lp.locator('#incident .iv-plot svg').evaluate((svg) => [...svg.querySelectorAll('.band-warn text, .band-crit text')].map((t) => [Math.round(t.getComputedTextLength()), Math.round(textWidth(t.textContent))]));
    ok(est.length > 0 && est.every((e) => Math.abs(e[0] - e[1]) <= 1), width + ' px: die Breite einer Beschriftung ist gemessen, nicht geschaetzt: ' + JSON.stringify(est));
    await lp.close();
  }
  // (carried, too) the folded rest of a list of steps: shown with the keyboard or the mouse, the focus stands on its first step
  // (the line that was clicked is gone; the focus fell to the page)
  const fp = await open(browser, path.join(dir, 'report.html'), scheme), pr = D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print');
  await ivOpen(fp.page, pr.id);
  const focusAt = () => fp.page.evaluate(() => { const a = document.activeElement, d = a.closest('details.morefold'); return [a.tagName, !!d && d.open, !!d && a === d.querySelector('li'), !!d && d.parentNode.className, document.querySelectorAll('#incident details.morefold > summary').length].join(); });
  await fp.page.focus('#incident .iv-todo > details.morefold > summary');
  await fp.page.keyboard.press('Enter');
  ok(await focusAt() === 'LI,true,true,iv-todo card,2' && await fp.page.locator('#incident .iv-todo > details.morefold > summary').isHidden(), 'weitere Pruefschritte mit der Tastatur gezeigt: der Fokus steht auf dem ersten von ihnen: ' + await focusAt());
  await fp.page.keyboard.press('Tab');
  ok(await fp.page.evaluate(() => document.activeElement !== document.body && !!document.activeElement.closest('#incident')), 'von dort fuehrt die Tabulatortaste in der Vorfallsansicht weiter');
  await fp.page.click('#incident .remedies details.morefold > summary');
  ok(await focusAt() === 'LI,true,true,remedies,2', 'weitere Vorschlaege mit der Maus gezeigt: der Fokus steht auf dem ersten von ihnen: ' + await focusAt());
  ok(fp.page.errors.length === 0, 'Skriptfehler Fokus der Schrittliste: ' + fp.page.errors.join(' | '));
  await fp.page.close();
}

async function checkReported(browser, dir, scheme) {                // gemeldeter Benutzer und gemeldete Uhrzeit in der Vorfallsansicht
  const { page, D } = await open(browser, path.join(dir, 'report-focus.html'), scheme), iv = page.locator('#incident'), F = D.meta.focus, when = hhmm(F.reportedMs, D.meta.offsetMin);
  const inc = D.incidents.find((i) => i.focus && i.nearReported && i.type === 'engpass'), sess = new Map(D.sessions.map((s) => [s.i, s]));
  ok((await page.locator('#timeline .reported').innerText()) === 'gemeldet ' + when, 'Zeitleiste: gemeldete Uhrzeit');
  await ivOpen(page, inc.id);
  ok((await iv.locator('.iv-meta .flag').allInnerTexts()).join('|') === 'betrifft den gemeldeten Benutzer ' + F.user + '|nahe der gemeldeten Uhrzeit ' + when, 'Kopf nennt den gemeldeten Benutzer und die gemeldete Uhrzeit: ' + (await iv.locator('.iv-meta .flag').allInnerTexts()).join('|'));
  // the chart of the first section marks the reported time like the timeline, inside the tinted span, the label above the plot
  const mark = await iv.locator('.iv-plot svg').evaluate((svg) => { const m = svg.querySelector('.repmark'), b = svg.querySelector('.incband'), c = svg.querySelector('clipPath rect'); if (!m) return null;
    const x = Number(m.querySelector('line').getAttribute('x1')), bx = Number(b.getAttribute('x')), t = m.querySelector('text').getBBox();
    return [m.querySelector('text').textContent, x > bx && x < bx + Number(b.getAttribute('width')), t.y + t.height <= Number(c.getAttribute('y')) + 3]; });
  ok(inc.start < F.reportedMs && F.reportedMs < inc.end && mark && mark[0] === 'gemeldet ' + when && mark[1] && mark[2] && await iv.locator('.iv-plot .repmark').count() === 1, 'Diagramm markiert die gemeldete Uhrzeit im getoenten Bereich, die Beschriftung ueber dem Diagramm: ' + JSON.stringify(mark));
  const rep = iv.locator('.iv-affected li.rep-user');
  ok(await rep.count() === 1 && inc.affected.some((a) => a.s === F.sessions[0]) && oneLine(await rep.innerText()).startsWith(F.user + ' (#' + sess.get(F.sessions[0]).id + ') gemeldeter Benutzer') && await iv.locator('.iv-affected li .flag').count() === 1, 'Wer war betroffen: der gemeldete Benutzer ist gekennzeichnet: ' + oneLine(await rep.innerText()));
  const doc = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok(doc[0] <= doc[1] && await page.evaluate(() => [...document.querySelectorAll('#incident .rep-user, #incident .flag')].every((e) => getComputedStyle(e).position === 'static')), 'die Kennzeichnung liegt im Textfluss');
  // an incident near the reported time only, and one with neither
  const near = D.incidents.find((i) => !i.focus && i.nearReported && i.type !== 'ereignis' && !i.chronic), far = D.incidents.find((i) => !i.focus && !i.nearReported && i.type === 'engpass');
  await ivOpen(page, near.id);
  ok((await iv.locator('.iv-meta .flag').allInnerTexts()).join('|') === 'nahe der gemeldeten Uhrzeit ' + when && await iv.locator('.iv-affected li.rep-user').count() === 0, 'nur nahe der gemeldeten Uhrzeit: ein Hinweis, kein gekennzeichneter Benutzer');
  await ivOpen(page, far.id);
  ok(await iv.locator('.iv-meta .flag').count() === 0 && await iv.locator('.iv-plot .repmark').count() === 0 && await iv.locator('.iv-plot svg path').count() > 0, 'weder Benutzer noch Uhrzeit: keine Hinweise, keine Markierung im Diagramm');
  // the entries of the expert view name them the same way
  await showExpert(page);
  ok((await page.locator(`#incList .inc[data-id="${inc.id}"] .flag`).allInnerTexts()).join('|') === 'betrifft den gemeldeten Benutzer ' + F.user + '|nahe der gemeldeten Uhrzeit ' + when, 'Eintrag der Expertenansicht nennt Benutzer und Uhrzeit ebenso');
  ok(page.errors.length === 0, 'Skriptfehler gemeldeter Benutzer: ' + page.errors.join(' | '));
  await page.close();
  // a masked report shows the alias, as everywhere
  const m = await open(browser, patched(dir, 'report-masked.html', 'report-masked-reported.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu'), s = J.sessions.find((x) => x.i === c.affected[0].s);
    J.meta.focus = { user: s.user, found: true, sessions: [s.i], reportedMs: c.start + 30000 }; c.focus = true; c.nearReported = true;
  }), scheme), mc = m.D.incidents.find((i) => i.lead === 'cpu'), alias = m.D.meta.focus.user;
  await ivOpen(m.page, mc.id);
  const mt = await m.page.locator('#incident').innerText();
  // (fix round 1 of Task 10, item 10: the alias begins with the word the label ends with, so the word is said once:
  // "betrifft den gemeldeten Benutzer 02", not "… Benutzer Benutzer 02")
  ok(/^Benutzer \d+$/.test(alias) && (await m.page.locator('#incident .iv-meta .flag').first().innerText()) === 'betrifft den gemeldeten ' + alias && oneLine(await m.page.locator('#incident .iv-affected li.rep-user').innerText()).startsWith(alias + ' (#') && !/user\d{3}/.test(mt), 'maskiert: Hinweis und Kennzeichnung zeigen das Alias: ' + alias);
  await m.page.close();
}

async function checkMotion(browser, dir, scheme) {                  // weiches Rollen der Seite nur ohne den Wunsch nach reduzierter Bewegung (P3-R55)
  for (const [motion, smooth] of [['reduce', false], ['no-preference', true]]) {
    const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 }, colorScheme: scheme, reducedMotion: motion }), page = await ctx.newPage();
    page.errors = []; page.on('pageerror', (e) => page.errors.push(e.message));
    await page.goto('file://' + path.join(dir, 'report.html'));
    await showExpert(page); await showTab(page, 'sessions');
    // the click on a row scrolls to the detail of the session: at once, or smoothly over the next frames
    const y = await page.evaluate(() => { const y0 = window.scrollY; document.querySelector('#tSessions tbody tr').click(); return [y0, window.scrollY]; });
    await page.waitForFunction((y1) => window.scrollY > y1 + 50 || window.scrollY > 300, y[0]);
    await page.waitForTimeout(900);
    const end = await page.evaluate(() => window.scrollY);
    ok(end > y[0] + 100 && (y[1] === end) === !smooth, (smooth ? 'ohne den Wunsch rollt die Seite weich zur gewaehlten Sitzung' : 'reduzierte Bewegung: die Seite springt ohne weiches Rollen zur gewaehlten Sitzung') + ': ' + y.concat(end).join(' '));
    await showTab(page, 'sollist');
    ok(await page.locator('#xt-sollist').isVisible() && page.errors.length === 0, 'danach wechselt der Reiter (' + motion + ')');
    // the helper of these checks repeats a click that did not switch the tab (here: the page swallows the first one)
    if (smooth) {
      await page.evaluate(() => { window.__swallowed = 0; document.querySelector('#xtabs').addEventListener('click', (ev) => { if (!window.__swallowed++) ev.stopPropagation(); }, true); });
      await showTab(page, 'apps');
      ok(await page.locator('#xt-apps').isVisible() && await page.evaluate(() => window.__swallowed) === 2, 'der Helfer wiederholt einen Klick, nach dem der Reiter nicht gewechselt hat');
      // a click that worked is not repeated: "In der Expertenansicht zeigen" leaves the view of its button, and where the expert
      // view takes longer than a second to appear, the helper waits for it (a second click on the hidden button waited 30 s)
      await page.evaluate((i) => window.WP.openIncident(i), 2);
      await page.evaluate(() => { const x = document.getElementById('expert'); x.style.visibility = 'hidden'; setTimeout(() => { x.style.visibility = ''; }, 1600); });
      const t0 = Date.now();
      await ivExpert(page);
      ok(Date.now() - t0 < 8000 && await page.evaluate(() => window.WP.view) === 'expert' && await page.locator('#expert').isVisible(), 'der Helfer wiederholt den Klick nicht, wenn sein Knopf nicht mehr zu sehen ist: ' + (Date.now() - t0) + ' ms');
    }
    await ctx.close();
  }
}

async function checkPage(browser, dir, scheme) {                    // Task 13
  const { page, D } = await openExpert(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('#xtabs button[data-tab]').count() === 8, 'acht Reiter');
  // tiles and charts stand above the tabs, always visible
  for (const id of ['chCpu', 'chMem', 'chInput', 'chVolumes', 'chCpuStack', 'chMemStack']) ok(await page.locator(`#${id} svg path`).count() > 0, id + ' gezeichnet');
  ok(await page.locator('#chCpu .band-warn').count() === 1 && await page.locator('#chCpu .band-crit').count() === 1, 'Soll-Baender im CPU-Diagramm');
  ok(await page.locator('.tile[data-signal="cpu.host"]').getAttribute('data-status') === '2', 'CPU-Kachel kritisch');
  ok((await page.locator('.tile[data-signal="cpu.host"]').innerText()).includes('kritisch'), 'Status als Wort');
  ok(await page.locator('.tile.info[data-info="userspercore"]').count() === 1, 'Benutzer je logischer CPU als Information');
  ok(await page.locator('#chMainApp svg path').count() > 0, 'Verlauf der Hauptanwendung');
  ok(await page.locator('#rangeAll').isVisible() && await page.locator('#rangeAll').isDisabled(), 'ohne Zeitraum ist "Gesamte Messung" deaktiviert');
  const inc = D.incidents.find((i) => i.lead === 'cpu');
  await page.evaluate(([a, b]) => window.WP.setZoom(a, b), [inc.start, inc.end]);
  ok(await page.locator('#rangeAll').isVisible() && await page.locator('#rangeAll').isEnabled(), 'mit Zeitraum ist "Gesamte Messung" aktiv');
  ok((await page.locator('#chCpu svg text.xaxis').first().textContent()).startsWith(hhmm(inc.start, D.meta.offsetMin)), 'Zeitachse beginnt am Fensteranfang');
  await page.click('#rangeAll');
  ok(await page.evaluate(() => window.WP.zoom === null), 'Zoom zurueckgesetzt');
  await showTab(page, 'apps');
  await page.selectOption('#fRoleApps', 'Sicherheit');
  const roles = await page.locator('#tApps tbody tr td.role').allInnerTexts();
  ok(roles.length > 0 && roles.every((r) => r.includes('Sicherheit')), 'Rollenfilter Anwendungen');
  await showTab(page, 'sessions');
  await page.click('#tSessions tbody tr >> nth=0');
  ok(await page.locator('#dSessions .chart-input svg path').count() > 0, 'Eingabeverzoegerung in der Sitzungsansicht');
  await showTab(page, 'procs');
  ok(await page.locator('#tProcs tbody tr.collector').count() === 1, 'Collector gekennzeichnet');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
}

async function checkFindings(browser, dir, scheme) {                // Task 14
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('#guided #timeline .mark').count() === D.incidents.length && await page.locator('#guided #timeline').isVisible(), 'eine Markierung je Vorfall');
  ok(await page.locator('#guided #timeline .event').count() === D.events.length, 'Ereignisse in der Zeitleiste');
  await showExpert(page);
  ok(await page.locator('#incList').isVisible() && await page.locator('#xtabs button[data-tab]').first().getAttribute('data-tab') === 'sollist' && await page.locator('#xtabs button[data-tab=sollist]').getAttribute('aria-selected') === 'true' && await page.locator('#xt-sollist').isVisible(),
    'in der Expertenansicht stehen die Vorfaelle in ihrer Spalte, Soll-Ist ist der erste Reiter');
  ok(await page.locator('#incList .inc').count() === D.incidents.length, 'ein Eintrag je Vorfall');
  ok(!(await page.locator('#noFinding').isVisible()), 'kein Hinweis auf fehlende Befunde');
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  // the entry of the column: status as symbol and word, time, kind, the cause in one line with its full text as the tooltip
  const item = page.locator(`#incList .inc[data-id="${cpu.id}"]`), itemText = oneLine(await item.innerText());
  ok(itemText.includes('◆ kritisch') && itemText.includes(hhmm(cpu.start, D.meta.offsetMin)) && (await item.locator('.inc-kind').innerText()) === cpu.guide.tech && await item.locator('.inc-cause').getAttribute('title') === cpu.causeText && cpu.causeText.startsWith(await item.locator('.inc-cause').innerText()),
    'Eintrag der Spalte: Schwere als Symbol und Wort, Uhrzeit, Art, Verursacher: ' + itemText);
  const line = await item.locator('.inc-cause').evaluate((e) => e.getBoundingClientRect().height);
  ok(line <= 22 && (await item.locator('.inc-guided').innerText()) === 'Geführt öffnen' && (await item.locator('.inum').innerText()) === 'Vorfall ' + cpu.id, 'Eintrag: Verursacher in einer Zeile, darunter "Gefuehrt oeffnen" und die Nummer: ' + line);
  // the detail of an incident stands in its incident view
  const entry = await openIncident(page, cpu.id);
  ok((await entry.locator('.iv-evidence .techtext').innerText()).includes('CPU-Engpass'), 'Klartext sichtbar');
  ok((await entry.locator('.iv-meta .status').innerText()).includes('kritisch'), 'Schwere als Wort');
  ok(await entry.locator('.iv-affected ul.aff > li').count() === cpu.affected.length, 'Betroffene aufgelistet');
  ok((await entry.locator('.iv-evidence .contributors').innerText()).includes('EXCEL.EXE'), 'Verursacher aufgelistet');
  ok(await entry.locator('.iv-evidence svg path').count() > 0, 'Verlauf im Vorfall');
  await page.click('#ivBack'); await ivClosed(page);
  await showGuided(page);
  // the mark of an incident that was not chosen so far: nothing of what follows holds before the click
  const disk = D.incidents.find((i) => i.lead === 'disk'), dEntry = page.locator(`#incList .inc[data-id="${disk.id}"]`);
  ok(await page.locator('#incident').isHidden() && !(await dEntry.getAttribute('class')).includes('selected') && await page.evaluate(() => window.WP.zoom === null), 'vor dem Klick: keine Vorfallsansicht, Eintrag nicht gewaehlt, kein Zeitraum');
  await page.click(`#guided #timeline .mark[data-incident="${disk.id}"]`);
  ok(await page.evaluate(() => window.WP.view) === 'guided' && await page.locator(`#incident[data-id="${disk.id}"]`).isVisible() && await page.locator('#incident .iv-chart svg path').count() > 0, 'Klick auf die Markierung oeffnet die Vorfallsansicht ihres Vorfalls');
  await ivExpert(page);
  const z = await page.evaluate(() => window.WP.zoom);
  ok(await page.evaluate(() => window.WP.view) === 'expert' && await dEntry.isVisible() && (await dEntry.getAttribute('class')).includes('selected') && await page.locator('#chVolumes svg .incband').count() === 1, 'Klick auf die Markierung wechselt in die Expertenansicht zum gewaehlten Vorfall, sein Fenster ist in den Diagrammen getoent');
  ok(z && z.t0 < disk.start && z.t1 > disk.end && z.t1 - z.t0 < (disk.end - disk.start) * 3, 'Klick stellt die Diagramme auf das Fenster ein');
  await showTab(page, 'sollist');
  ok(await page.locator('#sollist tbody tr').count() === D.sollIst.length, 'Soll-Ist-Tabelle vollstaendig');
  ok((await page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText()).includes('unter 75 %'), 'Idealbereich genannt');
  ok(await page.locator('#sollist tbody tr[data-id="cpu.host"] a[href]').count() === 1, 'Herkunft verlinkt');
  {                                                                  // only http(s) links from the threshold file
    const src = fs.readFileSync(path.join(dir, 'report.html'), 'utf8'), tag = '<script id="wp-data" type="application/json">';
    const a = src.indexOf(tag) + tag.length, b = src.indexOf('</script>', a), J = JSON.parse(src.substring(a, b));
    J.sollIst.find((r) => r.id === 'cpu.queue').url = 'javascript:alert(1)';
    const bad = path.join(dir, 'report-badurl.html');
    fs.writeFileSync(bad, src.substring(0, a) + JSON.stringify(J).replace(/</g, '\\u003c') + src.substring(b));
    const u = await openExpert(browser, bad, scheme);
    ok(await u.page.locator('#sollist tbody tr[data-id="cpu.queue"] a[href]').count() === 0, 'kein Link auf javascript:');
    ok(await u.page.locator('#sollist tbody tr[data-id="cpu.host"] a[href]').count() === 1, 'https-Link bleibt');
    ok(u.page.errors.length === 0, 'Skriptfehler mit javascript:-URL: ' + u.page.errors.join(' | '));
    await u.page.close();
  }
  // the list of events stands in its tab and follows the range: the whole capture shows them all
  await page.click('#rangeAll');
  await showTab(page, 'events');
  ok(await page.locator('#tEvents tbody tr').count() === Math.min(200, D.events.length) && (await page.locator('#eventHead').innerText()) === `Ereignisse (${D.events.length})`, 'Ereignisliste');
  await page.click('#tEvents tbody tr >> nth=0');
  const ez = await page.evaluate(() => window.WP.zoom);
  ok(ez && Math.abs((ez.t0 + ez.t1) / 2 - D.events[0].t) <= 60000, 'Ereignis stellt den Zoom ein');
  const near = D.events.filter((e) => e.t >= ez.t0 && e.t <= ez.t1).length;
  ok(near >= 1 && near < D.events.length && await page.locator('#tEvents tbody tr').count() === near && (await page.locator('#eventHead').innerText()) === `Ereignisse im Zeitraum (${near} von ${D.events.length})` && (await page.locator('#xtab-events .cnt').innerText()) === String(near),
    'die Ereignisliste folgt dem Zeitraum: ' + await page.locator('#eventHead').innerText());
  await showTab(page, 'quality');
  ok((await page.locator('#quality').innerText()).includes('WorkerPerf'), 'Messqualitaet nennt den Collector');
  ok((await page.locator('#limits').innerText()).includes('SYSTEM'), 'Grenzen der Aussage genannt');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();

  const f = await open(browser, path.join(dir, 'report-focus.html'), scheme);
  ok(await f.page.locator('#guided #timeline .reported').isVisible() && await f.page.locator('#timeline .reported').count() === 1, 'gemeldete Uhrzeit markiert');
  ok(await f.page.locator('header #focusInfo').isVisible() && (await f.page.locator('header #focusInfo').innerText()).includes('user003'), 'Fokus in der Kopfleiste genannt, auch in der gefuehrten Ansicht');
  await showExpert(f.page);
  const fFirst = f.page.locator('#incList .inc').first();
  ok((await fFirst.getAttribute('class')).includes('focus') && await fFirst.getAttribute('data-id') === String(f.D.incidents.find((i) => i.focus).id) && (await fFirst.locator('.flag').first().innerText()) === 'betrifft den gemeldeten Benutzer user003', 'Vorfall des Benutzers steht vorn und traegt die Kennzeichnung');
  ok(await f.page.locator('header #focusInfo').isVisible() && (await f.page.locator('#focusInfo').innerText()).includes('user003'), 'Fokus genannt');
  await f.page.close();

  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#measured').isVisible() && await n.page.locator('#measured').evaluate((d) => d.open), 'Hinweis ohne Befund, gefuehrte Ansicht: aufgeklappt');
  ok((await n.page.locator('#measured').innerText()).includes('Keine Schwelle wurde überschritten'), 'ausdrueckliche Aussage, gefuehrte Ansicht');
  await showExpert(n.page);
  ok(await n.page.locator('#noFinding').isVisible(), 'Hinweis ohne Befund');
  ok((await n.page.locator('#noFinding').innerText()).includes('Keine Schwelle wurde überschritten'), 'ausdrueckliche Aussage');
  ok(await n.page.locator('#incList .inc').count() === 0 && await n.page.locator('#incList').isHidden() && (await n.page.locator('#findHead').innerText()) === 'Keine Vorfälle im Messzeitraum.', 'keine Vorfaelle');
  ok(n.page.errors.length === 0, 'Skriptfehler ohne Befund: ' + n.page.errors.join(' | '));
  await n.page.close();
}

// A copy of a report with changed data (for states that are costly to record): returns the new file.
function patched(dir, base, name, change) {
  const src = fs.readFileSync(path.join(dir, base), 'utf8'), tag = '<script id="wp-data" type="application/json">';
  const a = src.indexOf(tag) + tag.length, b = src.indexOf('</script>', a), J = JSON.parse(src.substring(a, b));
  change(J);
  const file = path.join(dir, name);
  fs.writeFileSync(file, src.substring(0, a) + JSON.stringify(J).replace(/</g, '\\u003c') + src.substring(b));
  return file;
}
// The detail of an incident stands in its incident view (the entries of the expert view do not unfold): opens the view of
// the incident, unfolds its evidence and returns the view.
async function openIncident(page, id) {
  await page.evaluate((i) => { window.WP.openIncident(i); document.querySelector('#incident details.iv-evidence').open = true; }, id);
  await page.locator(`#incident[data-id="${id}"] .iv-evbody`).waitFor({ state: 'visible' });
  // the charts of the evidence are drawn when it has unfolded
  await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
  return page.locator('#incident');
}

async function checkFinalFix(browser, dir, scheme) {                // Abschlussrunde
  const { page, D } = await openExpert(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('#oldBrowser').count() === 0, 'Hinweis fuer alte Browser entfernt, sobald das Skript laeuft');
  {                                                                  // Minor 18: without script the static message stays visible
    const ctx = await browser.newContext({ javaScriptEnabled: false }), plain = await ctx.newPage();
    await plain.goto('file://' + path.join(dir, 'report.html'));
    ok((await plain.locator('#oldBrowser').innerText()).includes('Dieser Bericht benötigt einen aktuellen Browser (Microsoft Edge, Chrome oder Firefox).'), 'Hinweis ohne laufendes Skript vorhanden');
    if (scheme === 'light') {                                       // it appears after a delay, so it does not flash while a report loads
      ok(await plain.evaluate(() => getComputedStyle(document.getElementById('oldBrowser')).opacity) === '0', 'Hinweis zunaechst unsichtbar');
      await plain.waitForTimeout(4500);
      ok(await plain.evaluate(() => getComputedStyle(document.getElementById('oldBrowser')).opacity) === '1', 'Hinweis ohne laufendes Skript nach kurzer Zeit sichtbar');
    }
    await ctx.close();
  }
  // I2: the chronic state of one session's network path shows nothing of other sessions
  const chronic = D.incidents.find((i) => i.chronic && i.type === 'umfeld');
  let entry = await openIncident(page, chronic.id), text = await entry.locator('.iv-evidence').innerText();
  ok((await entry.locator('.iv-evidence .causebox').innerText()).includes('nicht den Server'), 'Umfeld: Aussage zur Netzstrecke');
  for (const word of ['nexus.exe', 'Oracle-Listener', 'Virenscan', 'Ereignisse im Fenster', 'Schutzprodukte', 'Kein Engpass auf dem Server']) ok(!text.includes(word), 'Dauerzustand im Umfeld ohne fremde Belege: ' + word);
  // engpass with main cause: as before, with the unit of the ranking
  const mem = D.incidents.find((i) => i.lead === 'memory');
  entry = await openIncident(page, mem.id);
  ok((await entry.locator('.iv-evidence .causebox').innerText()).includes('ms-teams.exe') && (await entry.locator('.iv-evidence .causebox').innerText()).includes('des Arbeitsspeichers aller Prozesse (Working Set)'), 'Hauptverursacher mit Einheit');
  const prof = D.incidents.find((i) => i.lead === 'profile');
  entry = await openIncident(page, prof.id);
  ok((await entry.locator('.iv-evidence .causebox').innerText()).includes('der I/O-Menge dieser Sitzung'), 'Profilcontainer: Anteil der Sitzung');
  ok((await entry.locator('.iv-evidence .contributors').innerText()).includes('Anteil an der I/O-Menge dieser Sitzung'), 'Profilcontainer: Rangliste der Sitzung');
  // ohne-engpass: as before; Minor 20: a chart with a single probe names the endpoint
  const backend = D.incidents.find((i) => i.type === 'ohne-engpass' && i.resources.includes('endpoint'));
  entry = await openIncident(page, backend.id);
  ok((await entry.locator('.iv-evidence .causebox').innerText()).includes('Kein Engpass auf dem Server. Höchste Eingabeverzögerung in nexus.exe'), 'Verzoegerung ohne Engpass wie bisher');
  ok((await entry.locator('.iv-evidence .sigcharts .legend').allInnerTexts()).some((t) => t.includes('Oracle-Listener')), 'Diagramm einer einzelnen Probe nennt die Gegenstelle');
  ok((await entry.locator('.iv-evidence').innerText()).includes('Ereignisse im Fenster'), 'Ereignisse bleiben beim kurzen Vorfall');
  // Minor 1, 2, 11 and the limits
  await showTab(page, 'quality');
  const q = await page.locator('#quality').innerText(), burstTicks = D.host.burst.filter((b) => b).length;
  ok(burstTicks > 0 && D.quality.burstTicks === burstTicks && Math.abs(D.quality.burstMin - burstTicks * D.meta.fastSec / 60) < 0.01, 'Zeit im Verdichtungsmodus aus den Takten');
  ok(q.includes(burstTicks.toLocaleString('de-DE') + ' Takte') && q.includes('im Abstand von 6 s'), 'Verdichtung: Dauer aus den Takten, Abstand wie gemessen');
  ok(!q.includes('unlesbare Zeilen') && !q.includes('Fehlgeschlagene Abfragen'), 'ohne uebersprungene Zeilen und Fehler keine Zeile dazu');
  ok((await page.locator('#limits').innerText()).includes('Prozesse, die zwischen zwei Schnappschüssen starten und wieder enden, werden nicht erfasst; für einen beendeten Prozess fehlt der Verbrauch seit dem letzten Schnappschuss.'), 'Grenze der Prozess-Schnappschuesse');
  await showTab(page, 'sollist');
  ok((await page.locator('#sollNote').innerText()).includes('gelten Ø, P95 und Max für die jeweils schlechteste Instanz je Zeitpunkt'), 'Hinweis zu mehreren Instanzen');
  ok((await page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText()).includes('vor produktiver Nutzung'), 'Hinweis zur Herkunft der Citrix-Werte');
  ok(!(await page.locator('#subtitle').innerText()).includes('Aufzeichnung'), 'regulaeres Ende ohne Hinweis im Kopf');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();

  // I4: two critical CPU ticks without a finding
  const sp = await open(browser, path.join(dir, 'report-spike.html'), scheme);
  const ms = await sp.page.locator('#measured').innerText();
  ok(ms.includes('Kein Vorfall.') && ms.includes('Einzelne Überschreitungen ohne Befund (kürzer als die Mindestdauer): CPU-Auslastung Max 96,5 % (Soll unter 75 %).'), 'einzelne Ueberschreitungen genannt, gefuehrte Ansicht: ' + ms.split('\n').slice(0, 3).join(' / '));
  ok(!ms.includes('Keine Schwelle wurde überschritten') && !ms.includes('lagen in der gesamten Messung im Soll'), 'keine Aussage, alles sei im Soll, gefuehrte Ansicht');
  await showExpert(sp.page);
  const nf = await sp.page.locator('#noFinding').innerText();
  ok(nf.includes('Kein Vorfall.') && nf.includes('Einzelne Überschreitungen ohne Befund (kürzer als die Mindestdauer): CPU-Auslastung Max 96,5 % (Soll unter 75 %).'), 'einzelne Ueberschreitungen genannt: ' + nf.split('\n').slice(0, 2).join(' / '));
  ok(!nf.includes('Keine Schwelle wurde überschritten') && !nf.includes('lagen in der gesamten Messung im Soll'), 'keine Aussage, alles sei im Soll');
  ok(await sp.page.locator('#incList .inc').count() === 0, 'kein Vorfall aus zwei Takten');
  let row = await sp.page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText();
  ok(row.includes('normal') && row.includes('einzelne Überschreitungen') && !row.includes('kritisch'), 'Soll-Ist-Zeile normal mit Zusatz');
  ok(await sp.page.locator('.tile[data-signal="cpu.host"]').isVisible() && await sp.page.locator('.tile[data-signal="cpu.host"]').getAttribute('data-status') === '0', 'CPU-Kachel normal');
  ok((await sp.page.locator('.tile[data-signal="cpu.host"]').innerText()).includes('einzelne Überschreitungen'), 'CPU-Kachel mit Zusatz');
  ok(await sp.page.locator('.tile[data-signal="ica.rtt"]').getAttribute('data-status') === 'na', 'nicht gemessen bleibt');
  ok(sp.page.errors.length === 0, 'Skriptfehler einzelne Ueberschreitungen: ' + sp.page.errors.join(' | '));
  await sp.page.close();

  // I1/I2/I3: engpass without process data and without measured input delay
  const nd = await openExpert(browser, path.join(dir, 'report-nodata.html'), scheme);
  const bare = nd.D.incidents.find((i) => i.type === 'engpass' && i.lead === 'cpu');
  entry = await openIncident(nd.page, bare.id);
  let box = await entry.locator('.iv-evidence .causebox').innerText();
  ok(box.includes('Kein Hauptverursacher ermittelt: im Fenster liegen keine Prozessdaten vor.') && bare.text.includes('Kein Hauptverursacher ermittelt: im Fenster liegen keine Prozessdaten vor.'), 'Engpass ohne Prozessdaten: Text und Seite gleich');
  ok(!(await entry.locator('.iv-evidence').innerText()).includes('Kein Engpass auf dem Server'), 'Engpass nie als "Kein Engpass auf dem Server"');
  ok((await entry.locator('.iv-affected').innerText()).includes('Eingabeverzögerung nicht gemessen; betroffene Sitzungen sind nicht bestimmbar.'), 'Betroffene nicht bestimmbar');
  ok(nd.page.errors.length === 0, 'Skriptfehler ohne Prozessdaten: ' + nd.page.errors.join(' | '));
  await nd.page.close();

  // states changed in the data: security product as the largest consumer, no share at the minimum, unmeasured worker
  // resource, end of the capture, unreadable rows and failed source calls
  const disk = D.incidents.find((i) => i.lead === 'disk');
  const v = await openExpert(browser, patched(dir, 'report.html', 'report-variant.html', (J) => {
    const d = J.incidents.find((i) => i.id === disk.id);
    d.cause = Object.assign({}, d.cause, { kind: 'security', security: { label: 'Microsoft Defender', sharePct: 96 }, scan: true, other: d.main }); d.main = null; d.companion = null;
    const c = J.incidents.find((i) => i.lead === 'cpu'); c.cause = Object.assign({}, c.cause, { kind: 'none' }); c.main = null;
    J.unmeasured = { input: false, worker: ['Datenträger-Antwortzeit', 'Freigabe-Antwortzeit (SMB)'] };
    J.meta.endReason = 'error'; J.meta.endMessage = 'Testfehler <b>im Takt</b>';
    J.quality.unreadable = { ticks: 3, snapshots: 1 };
    J.quality.sourceErrors = [{ source: 'events', label: 'Ereignisprotokoll', count: 240, firstMs: J.meta.start + 15000, firstMessage: 'Zugriff verweigert' }];
  }), scheme);
  entry = await openIncident(v.page, disk.id);
  box = await entry.locator('.iv-evidence .causebox').innerText();
  ok(box.includes('Größter Verbraucher: Microsoft Defender mit 96 % der I/O-Menge. Im Fenster lief ein Virenscan; Zeitplan und Umfang des Scans prüfen.'), 'Schutzsoftware als groesster Verbraucher: ' + box);
  // the whole evidence of the incident view (cause box, rankings, lists, table of the measured values, chart legends) without
  // the technical text, which is the incident's sentence as delivered (the patched data keep it)
  const evBody = await entry.locator('.iv-evbody').evaluate((b) => { const c = b.cloneNode(true); for (const t of c.querySelectorAll('.techtext')) t.remove(); return c.textContent; });
  ok(box.includes('Größter Anteil außerhalb der Schutzsoftware: robocopy.exe') && !box.includes('Begleiter') && evBody.length > 500 && evBody.includes('Größter Anteil außerhalb der Schutzsoftware') && !evBody.includes('Begleiter'), 'nicht als Begleiter bezeichnet');
  entry = await openIncident(v.page, D.incidents.find((i) => i.lead === 'cpu').id);
  ok((await entry.locator('.iv-evidence .causebox').innerText()).includes('Kein einzelner Hauptverursacher: kein Prozess erreicht 10 % der CPU-Zeit.'), 'kein Hauptverursacher unter der Untergrenze');
  entry = await openIncident(v.page, backend.id);
  ok((await entry.locator('.iv-evidence .causebox').innerText()).includes('Kein Engpass in den gemessenen Server-Ressourcen. Nicht gemessen: Datenträger-Antwortzeit, Freigabe-Antwortzeit (SMB); ein Engpass dort ist nicht ausgeschlossen.'), 'nicht gemessene Server-Ressourcen genannt');
  ok((await v.page.locator('#subtitle').innerText()).includes('Aufzeichnung mit Fehler beendet: Testfehler <b>im Takt</b>'), 'Ende mit Fehler im Kopf');
  await showTab(v.page, 'quality');
  const vq = await v.page.locator('#quality').innerText();
  ok(vq.includes('Übersprungene unlesbare Zeilen ticks.csv: 3 · snapshots.csv: 1'), 'uebersprungene Zeilen je Datei');
  ok(vq.includes('Ereignisprotokoll: 240 mal, zuerst') && vq.includes('Zugriff verweigert'), 'fehlgeschlagene Abfragen mit Anzahl, Zeit und Meldung');
  ok(v.page.errors.length === 0, 'Skriptfehler Varianten: ' + v.page.errors.join(' | '));
  await v.page.close();
  const k = await openExpert(browser, patched(dir, 'report.html', 'report-killed.html', (J) => { J.meta.endReason = null; }), scheme);
  ok((await k.page.locator('#subtitle').innerText()).includes('Aufzeichnung nicht regulär beendet (kein Abschluss in meta.json).'), 'fehlender Abschluss im Kopf');
  await k.page.close();
}

async function checkEvents(browser, dir, scheme) {                 // Ereignisse, Abstuerze, Drucken
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  const ev = D.incidents.filter((i) => i.type === 'ereignis');
  ok(await page.locator('#guided #timeline .mark.type-ereignis').count() === ev.length, 'Ereignisvorfaelle in der Zeitleiste');
  for (const g of ['app', 'session', 'security', 'profile']) ok(await page.locator(`#guided #timeline .tl-row[data-group="${g}"] .event`).count() === D.events.filter((e) => e.group === g).length, 'Ereigniszeile ' + g);
  await showExpert(page);
  ok(ev.length === 4 && await page.locator('#incList .inc.type-ereignis').count() === ev.length, 'Ereignisvorfaelle in der Liste');
  const many = ev.find((i) => i.event.app === 'OUTLOOK.EXE');
  const entry = await openIncident(page, many.id);
  ok((await entry.locator('.iv-evidence .patterns').innerText()).includes('spricht für Installation oder Update'), 'Aussage des Musters');
  const prof = ev.find((i) => i.event.kind === 'profileerror');
  ok((await (await openIncident(page, prof.id)).locator('.iv-evidence .patterns').innerText()).includes('Kein Muster erkannt'), 'kein Muster');
  await showTab(page, 'before');
  ok((await page.locator('#before').innerText()).includes('Für diese Zeit liegen keine Messwerte vor.'), 'Vor der Messung mit Hinweis');
  ok(await page.locator('#before .day').count() === D.before.perDay.length && await page.locator('#before .inc').count() === D.before.incidents.length && (await page.locator('#xtab-before .cnt').innerText()) === String(D.before.incidents.length), 'Rueckblick je Tag und Vorfall');
  await showTab(page, 'print');
  ok(await page.locator('#tPrintDrivers tbody tr').count() === 3 && (await page.locator('#tPrintQueues').innerText()).includes('PRN-EG-01'), 'Tabelle Drucken');
  await showTab(page, 'sessions');
  const s14 = D.sessions.find((s) => s.user === 'user014');
  await page.click(`#tSessions tbody tr[data-id="${s14.i}"]`);
  ok(await page.locator('#dSessions .sess-events li').count() === 2, 'Sitzungsereignisse bei der Sitzung');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
}

const ddmmyyyy = (ms, offMin) => { const d = new Date(ms + offMin * 60000).toISOString(); return d.substr(8, 2) + '.' + d.substr(5, 2) + '.' + d.substr(0, 4); };
// local clock time of an event in its own UTC offset
const evHms = (e) => new Date(e.t + e.offsetMin * 60000).toISOString().substr(11, 8);
async function checkEventDetails(browser, dir, scheme) {           // Ereignisse: Einzelheiten der Anzeige
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  const ev = D.incidents.filter((i) => i.type === 'ereignis'), outlook = ev.find((i) => i.event.app === 'OUTLOOK.EXE');
  // the timeline stands in the guided view: marks, rows of events and legend
  ok((await page.locator(`#guided #timeline .mark[data-incident="${outlook.id}"]`).getAttribute('aria-label')).includes('Absturz'), 'Markierung mit dem Wort der Art');
  ok((await page.locator('#guided #tlLegend').innerText()).includes('Anwendungen') && (await page.locator('#guided #tlLegend').innerText()).includes('Sitzungen'), 'Legende nennt die Gruppen');
  ok((await page.locator('#guided #timeline .tl-row[data-group="app"] .tl-label').innerText()) === 'Anwendungen', 'Zeile mit dem Wort der Gruppe');
  ok(await page.locator('#eventsOutsideCut').count() === 0, 'ohne Ausschnitt kein Hinweis');
  await showExpert(page);
  ok((await page.locator('#findHead').innerText()).includes('4 Vorfälle aus Ereignissen'), 'Kopfsatz nennt die Vorfaelle aus Ereignissen');
  const entry = await openIncident(page, outlook.id);
  ok((await entry.locator('.iv-meta .status').innerText()).includes('kritisch') && (await entry.locator('.iv-evidence .techtext').innerText()) === outlook.text, 'Ereignisvorfall: Satz und Schwere als Wort');
  ok(await entry.locator('.iv-evidence .patterns li').count() === outlook.event.patterns.length, 'eine Zeile je Muster');
  ok(await entry.locator('.iv-evidence .evlist tbody tr').count() === outlook.events.length, 'Ereignisse des Vorfalls');
  ok((await entry.locator('.iv-evidence .evlist').innerText()).includes(evHms(outlook.events[0])), 'Zeit des Ereignisses in seiner Ortszeit');
  const head = await entry.locator('.iv-evidence .kv').innerText();
  ok(head.includes('olmapi32.dll') && head.includes('user010') && head.includes('3'), 'Kopfzeile mit Modul, Benutzern und Anzahl');
  // the crash after the memory incident and the memory incident refer to each other
  const chrome = ev.find((i) => i.event.app === 'chrome.exe'), mem = D.incidents.find((i) => i.lead === 'memory');
  let e2 = await openIncident(page, chrome.id);
  ok(await e2.locator(`.iv-evidence .lnk[data-incident="${mem.id}"]`).count() === 1, 'Verweis auf den Leistungsvorfall');
  e2 = await openIncident(page, mem.id);
  ok(await e2.locator(`.iv-evidence .lnk[data-incident="${chrome.id}"]`).count() === 1, 'Leistungsvorfall verweist auf den Ereignisvorfall');
  await e2.locator(`.iv-evidence .lnk[data-incident="${chrome.id}"]`).click();
  ok(await page.locator('#incident').getAttribute('data-id') === String(chrome.id) && await page.locator('#incident').isVisible(), 'Verweis oeffnet den Ereignisvorfall');
  // the print incident: the driver is named as involved, in words
  await showTab(page, 'print');
  const drv = await page.locator('#tPrintDrivers tbody tr', { hasText: 'HP Universal Printing PCL 6 (Sim)' }).innerText();
  ok(drv.includes('beteiligt') && drv.includes('Typ 3') && !drv.includes('möglicherweise'), 'Treiber als beteiligt bezeichnet');
  ok((await page.locator('#tPrintDrivers tbody tr', { hasText: 'Kyocera' }).innerText()).includes('isoliert'), 'Isolierung als Wort');
  const spool = await page.locator('#tPrintProcs tbody tr', { hasText: 'spoolsv.exe' }).innerText();
  ok(spool.includes('16 MB'), 'Arbeitsspeicher der Druckwarteschlange');
  // lookback: both counts labelled, per-day bars with their number, lookback incidents with their date
  await showTab(page, 'before');
  const before = await page.locator('#before').innerText();
  ok(before.includes('Ereignisse aus diesen Tagen') && before.includes('davon mit Vorfallsart'), 'beide Zahlen des Rueckblicks benannt');
  // the simulated lookback lies before the day of the run: its dates come from the data, not a fixed calendar day
  const d0 = D.before.perDay[0], d0Text = d0.day.split('-').reverse().join('.'), bar0 = await page.locator('#before .day').first().innerText();
  ok(bar0.includes(d0Text) && bar0.includes(String(d0.count)), 'Balken mit Datum und Zahl: ' + bar0);
  const nexus = D.before.incidents.find((i) => i.event.app === 'nexus.exe');
  // the entry of a lookback incident carries its date and leads into its incident view
  const bItem = page.locator(`#before .inc[data-id="${nexus.id}"]`);
  ok((await bItem.locator('.inc-when').innerText()).includes(ddmmyyyy(nexus.events[0].t, nexus.events[0].offsetMin)) && (await bItem.innerText()).includes('kritisch') && await bItem.locator('button.inc-main').count() === 0, 'Eintrag vor der Messung mit Datum und Schwere, ohne Zeitraum zum Setzen');
  await bItem.locator('.inc-guided').click();
  ok(await page.evaluate(() => window.WP.view) === 'guided' && await page.locator('#incident').getAttribute('data-id') === String(nexus.id), 'Eintrag vor der Messung fuehrt in seine Vorfallsansicht');
  const be = await openIncident(page, nexus.id);
  ok((await be.locator('.iv-evidence .patterns').innerText()).includes('spricht für Profil oder Daten dieses Benutzers'), 'Muster im Rueckblick');
  ok((await be.locator('.iv-evidence .evlist').innerText()).includes(ddmmyyyy(nexus.events[0].t, nexus.events[0].offsetMin)), 'Rueckblick-Ereignisse mit Datum');
  // (reworded: the entry had no button "Alle Diagramme auf diesen Zeitraum stellen") the way into the expert view sets no range
  await ivExpert(page);
  ok(await page.evaluate(() => window.WP.zoom === null) && await page.locator('#rangeAll').isDisabled() && await page.locator(`#before .inc[data-id="${nexus.id}"].selected`).isVisible(), 'kein Zoom fuer die Zeit vor der Messung');
  // C1: a lookback crash without session and account says so, never "ohne Benutzersitzung"
  const nosess = D.before.incidents.find((i) => i.event.app === 'simscan.exe');
  const ne = await openIncident(page, nosess.id);
  const nkv = await ne.locator('.iv-evidence .kv').innerText();
  ok(nkv.includes('Sitzung nicht ermittelt') && !nkv.includes('ohne Benutzersitzung') && (await ne.locator('.iv-evidence .techtext').innerText()).includes('Sitzung nicht ermittelt.'), 'Rueckblick: unbekannte Sitzung als solche benannt: ' + nkv);
  await showTab(page, 'quality');
  ok(!(await page.locator('#quality').innerText()).includes('unvollständig'), 'ohne Obergrenze kein Hinweis');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();

  // without event files: the report without a finding stays as it was
  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#guided #timeline .tl-row').count() > 0 && await n.page.locator('#guided #timeline .event').count() === 0 && await n.page.locator('#guided #timeline .tl-row[data-group]').count() === 0, 'ohne Ereignisse keine Ereigniszeilen');
  await showTab(n.page, 'before');
  // changed in fix round 1 (I1), and again in fix round 2 (N2): without events_before.csv the card says that the file is
  // missing; the sources of this capture were available
  ok((await n.page.locator('#before').innerText()).includes('Für die Tage vor der Messung liegt keine Ereignisdatei vor (events_before.csv fehlt).') && await n.page.locator('.type-ereignis').count() === 0, 'ohne Ereignisdatei: Datei fehlt, keine Ereignisvorfaelle');
  ok((await n.page.locator('#findHead').innerText()) === 'Keine Vorfälle im Messzeitraum.' && await n.page.locator('#eventList').isHidden(), 'Kopfsatz und Ereignisliste wie bisher');
  ok(n.page.errors.length === 0, 'Skriptfehler ohne Ereignisse: ' + n.page.errors.join(' | '));
  await n.page.close();

  // a time cut names the events it leaves out
  const c = await open(browser, path.join(dir, 'report-nodata.html'), scheme);
  ok(c.D.eventsOutsideCut > 0 && (await c.page.locator('#guided #eventsOutsideCut').innerText()).includes(c.D.eventsOutsideCut + ' Ereignisse der Aufzeichnung liegen außerhalb'), 'Hinweis auf Ereignisse ausserhalb des Ausschnitts');
  await c.page.close();

  // states changed in the data: markup in server texts, a possibly involved driver, a restarted spooler, a capped lookback,
  // unreadable rows of the event files, a cut event list, events near a reported time before the capture
  const bad = '<img src=x onerror="window.__xss=1">';
  const v = await openExpert(browser, patched(dir, 'report.html', 'report-events-variant.html', (J) => {
    const out = J.incidents.find((i) => i.type === 'ereignis' && i.event.app === 'OUTLOOK.EXE');
    J.events[0].text = 'Text ' + bad; out.text = 'Satz ' + bad; out.events[0].text = 'Ereignis ' + bad; out.events[0].app = bad;
    out.event.modules[0].name = bad; out.event.users[0] = bad; out.event.patterns[0].text = 'Muster ' + bad;
    out.event.eventsTruncated = true; out.event.count = 120;
    J.print.drivers[1].name = bad; J.print.drivers[1].possiblyInvolved = true; J.print.queues[0].name = bad;
    const p = J.print.processes[0], proc = J.procs.find((x) => x.k === p.k), k2 = Math.max(...J.procs.map((x) => x.k)) + 1;
    J.procs.push(Object.assign({}, proc, { k: k2, pid: 9999, first: proc.first - 600000, last: proc.first - 1000 }));
    J.print.processes = [Object.assign({}, p, { wsStartMB: 40, wsEndMB: 70, wsMaxMB: 75.5 }), Object.assign({}, p, { k: k2, wsStartMB: 12, wsEndMB: 30, wsMaxMB: 31 })];
    J.before.capped = ['application'];
    J.before.near = [J.before.incidents[0].events[0]];
    J.meta.focus = Object.assign({}, J.meta.focus, { reportedMs: J.before.incidents[0].start + 60000 });
    J.quality.unreadable = Object.assign({}, J.quality.unreadable, { events: 2, printQueues: 1 });
    J.sessions.find((s) => s.user === 'user014').user = 'u' + bad;
  }), scheme);
  ok(await v.page.evaluate(() => window.__xss === undefined) && await v.page.locator('#expert img, #guided img').count() === 0, 'Markup aus den Daten wird nicht ausgefuehrt');
  const ve = await openIncident(v.page, D.incidents.find((i) => i.type === 'ereignis' && i.event.app === 'OUTLOOK.EXE').id);
  ok((await ve.locator('.iv-evidence .techtext').innerText()).includes('Satz ' + bad) && (await ve.locator('.iv-evidence .evlist').innerText()).includes('Ereignis ' + bad), 'Markup erscheint als Text');
  ok((await ve.locator('.iv-evidence .patterns').innerText()).includes('Muster ' + bad) && (await ve.locator('.iv-evidence .kv').innerText()).includes(bad), 'Muster und Kopfzeile als Text');
  ok(await ve.locator('img').count() === 0, 'kein Bild im Vorfall');
  ok((await ve.locator('.iv-evidence .evlist').innerText()).includes('die ersten 2 und das letzte der 120 Ereignisse'), 'gekuerzte Ereignisliste benannt');
  await showTab(v.page, 'events');
  ok((await v.page.locator('#tEvents').innerText()).includes('Text ' + bad) && await v.page.locator('#expert img').count() === 0, 'Ereignisliste zeigt Markup als Text');
  await showTab(v.page, 'print');
  const pd = await v.page.locator('#tPrintDrivers tbody tr', { hasText: bad }).innerText();
  ok(pd.includes('möglicherweise beteiligt'), 'moeglicherweise beteiligter Treiber in Worten');
  ok((await v.page.locator('#tPrintQueues').innerText()).includes(bad), 'Warteschlange als Text');
  const sp = await v.page.locator('#tPrintProcs tbody tr', { hasText: 'spoolsv.exe' });
  ok(await sp.count() === 1, 'neu gestarteter Druckprozess in einer Zeile');
  const spt = await sp.innerText();
  ok(spt.includes('12 MB') && spt.includes('70 MB') && spt.includes('76 MB') && spt.includes('9999'), 'Anfang des ersten, Ende des letzten Prozesses, Hoechstwert: ' + spt);
  await showTab(v.page, 'before');
  const vb = await v.page.locator('#before').innerText();
  ok(vb.includes('unvollständig') && vb.includes('Anwendung'), 'unvollstaendiger Rueckblick im Block');
  ok(vb.includes('Ereignisse um die gemeldete Uhrzeit') && vb.includes(D.before.incidents[0].events[0].text), 'Ereignisse um die gemeldete Zeit');
  ok(vb.includes('Ereignisse um die gemeldete Uhrzeit ' + ddmmyyyy(D.before.incidents[0].start + 60000, D.meta.offsetMin)), 'gemeldete Uhrzeit mit Datum');
  await showTab(v.page, 'quality');
  const vq = await v.page.locator('#quality').innerText();
  ok(vq.includes('ticks.csv: 0 · snapshots.csv: 0 · events.csv: 2 · printqueues.csv: 1'), 'uebersprungene Zeilen der Ereignisdateien: ' + vq);
  ok(vq.includes('Rückblick unvollständig') && vq.includes('Anwendung'), 'Obergrenze des Rueckblicks in der Messqualitaet');
  await showTab(v.page, 'sessions');
  await v.page.click(`#tSessions tbody tr[data-id="${D.sessions.find((s) => s.user === 'user014').i}"]`);
  ok((await v.page.locator('#dSessions .sess-events').innerText()).includes('Anmeldung') && await v.page.locator('#dSessions img').count() === 0, 'Sitzungsereignisse mit Art; Benutzername als Text');
  ok(v.page.errors.length === 0, 'Skriptfehler Ereignis-Varianten: ' + v.page.errors.join(' | '));
  await v.page.close();
}

async function checkNarrow(browser, dir, scheme) {                  // schmale Ansicht ohne seitliches Rollen der Seite
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, colorScheme: scheme });
  page.errors = []; page.on('pageerror', (e) => page.errors.push(e.message));
  await page.goto('file://' + path.join(dir, 'report.html'));
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent));
  // the guided view: one column, both folded areas open, nothing wider than the page
  await page.click('#measured > summary'); await page.click('#qualityG > summary');
  const wg = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok(wg[0] <= wg[1], 'gefuehrte Ansicht schmal ohne seitliches Rollen: ' + wg.join(' > '));
  const col = await page.locator('#cards .card.inc').evaluateAll((c) => c.slice(0, 2).map((x) => { const r = x.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top), Math.round(r.right)]; }));
  ok(col[0][0] === col[1][0] && col[1][1] > col[0][1] && col[0][2] <= 390, 'gefuehrte Ansicht schmal: Karten in einer Spalte: ' + JSON.stringify(col));
  const kp = await page.locator('#kpis .kpi').evaluateAll((k) => k.map((x) => Math.round(x.getBoundingClientRect().right)));
  ok(kp.every((r) => r <= 390), 'gefuehrte Ansicht schmal: Kennzahlen brechen um: ' + kp.join(' '));
  // the expert view in one column: the incident column is a list over the tiles that unfolds
  await showExpert(page);
  const widths = () => page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok(await page.locator('#incList').isHidden() && await page.locator('#incToggle').getAttribute('aria-expanded') === 'false', 'schmal: die Vorfallsspalte ist eingeklappt');
  await page.click('#incToggle');
  const nb = await page.evaluate(() => { const b = (id) => document.getElementById(id).getBoundingClientRect(); return [b('incCol').bottom, b('tiles').top, b('incCol').width, b('tiles').width]; });
  ok(await page.locator('#incList .inc:visible').count() === D.incidents.length && await page.locator('#incToggle').getAttribute('aria-expanded') === 'true' && nb[0] <= nb[1] && Math.abs(nb[2] - nb[3]) <= 2, 'schmal: aufgeklappt steht die Liste der Vorfaelle ueber den Kacheln, in einer Spalte: ' + nb.join(' '));
  await showTab(page, 'before');
  let w = await widths();
  ok(w[0] <= w[1], 'Befunde schmal ohne seitliches Rollen: ' + w.join(' > '));
  // the detail of an incident (it unfolded in the list before) stands in its incident view
  for (const inc of [D.incidents.find((i) => i.type === 'ereignis'), D.incidents.find((i) => i.lead === 'memory'), D.before.incidents[0]]) {
    await openIncident(page, inc.id);
    w = await widths();
    ok(w[0] <= w[1], 'Vorfall ' + inc.id + ' schmal ohne seitliches Rollen: ' + w.join(' > '));
  }
  await showTab(page, 'sessions');
  await page.click(`#tSessions tbody tr[data-id="${D.sessions.find((s) => s.user === 'user014').i}"]`);
  const w2 = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok(w2[0] <= w2[1], 'Sitzung schmal ohne seitliches Rollen: ' + w2.join(' > '));
  ok(page.errors.length === 0, 'Skriptfehler schmal: ' + page.errors.join(' | '));
  await page.close();
}

async function checkFix1(browser, dir, scheme) {                   // Task 9, Korrekturrunde 1
  const bt = async (page) => { await showTab(page, 'before'); return page.locator('#before').innerText(); };
  // C1: a reported time inside the capture but before the cut: the page names the cut, never "no events"
  const c = await openExpert(browser, path.join(dir, 'report-cutrep.html'), scheme);
  ok(c.D.meta.focus.reportedMs >= c.D.before.captureStart && c.D.meta.focus.reportedMs < c.D.meta.start && c.D.eventsOutsideCut > 0, 'Eingabe: gemeldete Zeit in der Aufzeichnung vor dem Ausschnitt');
  let t = await bt(c.page);
  ok(!t.includes('Keine Ereignisse') && !t.includes('Ereignisse um die gemeldete Uhrzeit'), 'Ausschnitt: keine falsche Aussage im Rueckblick');
  const fi = await c.page.locator('#focusInfo').innerText();
  ok(fi.includes('außerhalb des gewählten Zeitraums') && fi.includes(c.D.eventsOutsideCut + ' Ereignisse der Aufzeichnung liegen außerhalb des gewählten Zeitraums'), 'Ausschnitt laesst die Ereignisse um die gemeldete Zeit aus: ' + fi);
  ok(c.page.errors.length === 0, 'Skriptfehler Ausschnitt: ' + c.page.errors.join(' | '));
  await c.page.close();
  // I1: what was read, never a result that was not measured
  const empty = (J) => { Object.assign(J.before, { eventCount: 0, incidentEventCount: 0, perDay: [], incidents: [], near: [], nearCapture: [], capped: [] }); };
  const cases = [
    ['off', (J) => { empty(J); J.before.status = 'off'; J.before.days = 0; }, 'Der Rückblick war abgeschaltet (-Skip Rueckblick oder -EventLookbackDays 0).'],
    ['unavailable', (J) => { empty(J); J.before.status = 'unavailable'; }, 'Für die Tage vor der Messung wurden keine Ereignisse gelesen: die Ereignisquellen waren nicht verfügbar.'],
    ['read', (J) => { empty(J); J.before.status = 'read'; }, 'In den 7 Tagen vor der Messung stehen keine Ereignisse der erfassten Arten in den Protokollen.']];
  for (const [name, change, text] of cases) {
    const p = await open(browser, patched(dir, 'report.html', `report-lb-${name}.html`, (J) => { change(J); J.meta.focus = Object.assign({}, J.meta.focus, { reportedMs: J.before.captureStart - 3600000 }); }), scheme);
    ok(await p.page.locator('#beforeG').isHidden() && await p.page.locator('#cards .card.inc').count() === p.D.cards.length, 'Rueckblick ' + name + ': gefuehrte Ansicht ohne leeren Bereich "Vor der Messung"');
    await showExpert(p.page);
    t = await bt(p.page);
    ok(t.includes(text), 'Rueckblick ' + name + ': ' + t.split('\n').slice(0, 3).join(' / '));
    ok(!t.includes('Ereignisse aus diesen Tagen') && !t.includes('Vorfälle vor der Messung') && await p.page.locator('#before .day').count() === 0, 'Rueckblick ' + name + ' ohne Zahlen, Balken und Vorfallsliste');
    ok(!t.includes('Ereignisse um die gemeldete Uhrzeit'), 'Rueckblick ' + name + ': keine leere Liste um die gemeldete Zeit');
    ok(p.page.errors.length === 0, 'Skriptfehler Rueckblick ' + name + ': ' + p.page.errors.join(' | '));
    await p.page.close();
  }
  const f2 = await openExpert(browser, patched(dir, 'report.html', 'report-lb-fmt2.html', (J) => { empty(J); J.before.status = 'notRecorded'; J.before.days = 0; }), scheme);
  await showTab(f2.page, 'before');
  ok(await f2.page.locator('#before').isHidden(), 'Format 2 ohne Rueckblick: keine Karte');
  ok((await f2.page.locator('#xt-before').innerText()).includes('Diese Aufzeichnung enthält keinen Rückblick auf die Tage vor der Messung.') && (await f2.page.locator('#xtab-before .cnt').innerText()) === '', 'Format 2 ohne Rueckblick: der Reiter sagt es, ohne Zahl');
  await f2.page.close();
  // M1, M3, M4, M5 on the simulated hour
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  for (const inc of D.incidents.filter((i) => i.type === 'ereignis' && i.start === i.end)) {
    const box = await page.locator(`#guided #timeline .mark[data-incident="${inc.id}"]`).boundingBox();
    ok(box.width <= 13, 'Zeitpunkt-Vorfall nicht als Zeitspanne gezeichnet: ' + box.width);
    ok((await page.locator(`#guided #timeline .mark-word[data-incident="${inc.id}"]`).innerText()).length > 0, 'Wort neben der Markierung');
  }
  ok((await page.locator('#guided #tlLegend').innerText()).includes('Ortszeit des Ereignisses'), 'Legende: Tooltip in der Ortszeit des Ereignisses');
  await showExpert(page);
  const chrome = D.incidents.find((i) => i.type === 'ereignis' && i.event.app === 'chrome.exe');
  const ce = await openIncident(page, chrome.id);
  ok((await ce.locator('.iv-evidence .lnk[data-incident]').first().innerText()).includes('Arbeitsspeicher-Engpass'), 'Verweis nennt die Ressource wie der Satz');
  await showTab(page, 'events');
  const sec = D.events.find((e) => e.kind === 'scan-start');
  ok((await page.locator('#tEvents').innerText()).includes('Virenscan gestartet') && !(await page.locator('#tEvents').innerText()).includes('Scan gestartet\t'), 'ein Wort fuer dasselbe Ereignis' + (sec ? '' : ' (kein Scan in den Daten)'));
  ok(page.errors.length === 0, 'Skriptfehler Runde 1: ' + page.errors.join(' | '));
  await page.close();
  // M3: at most 10 users, versions and sessions in the head line, the rest on demand
  const out = D.incidents.find((i) => i.type === 'ereignis' && i.event.app === 'OUTLOOK.EXE');
  const many = await openExpert(browser, patched(dir, 'report.html', 'report-many.html', (J) => {
    const o = J.incidents.find((i) => i.id === out.id);
    o.event.users = Array.from({ length: 60 }, (_, k) => 'user' + String(100 + k));
    o.event.versions = Array.from({ length: 60 }, (_, k) => '16.0.' + k);
    o.event.sessions = J.sessions.map((s) => s.i);
  }), scheme);
  const me = await openIncident(many.page, out.id);
  let kv = await me.locator('.iv-evidence .kv').innerText();
  ok(kv.includes('user109') && !kv.includes('user110') && kv.includes('(+50 weitere)') && kv.includes('16.0.9') && !kv.includes('16.0.10'), 'Kopfzeile hoechstens 10 Eintraege: ' + kv.slice(0, 200));
  await me.locator('.iv-evidence .kv button.more').first().click();
  kv = await me.locator('.iv-evidence .kv').innerText();
  ok(kv.includes('user159'), 'die ganze Liste bleibt erreichbar');
  ok(many.page.errors.length === 0, 'Skriptfehler viele Benutzer: ' + many.page.errors.join(' | '));
  await many.page.close();
}

async function checkFix2(browser, dir, scheme) {                   // Task 9, Korrekturrunde 2
  const bt = async (page) => { await showTab(page, 'before'); return page.locator('#before').innerText(); };
  // N1: five lookback logs not available, Defender and AppLocker available (the reviewer's input)
  const partLogs = (J) => J.before.logs.map((l) => Object.assign({}, l, { available: l.id === 'defender' || l.id === 'applocker' }));
  const pe = await openExpert(browser, patched(dir, 'report.html', 'report-lb-partial.html', (J) => {
    Object.assign(J.before, { eventCount: 0, incidentEventCount: 0, perDay: [], incidents: [], near: [], nearCapture: [], capped: [], status: 'partial', logs: partLogs(J) });
  }), scheme);
  let t = await bt(pe.page);
  ok(t.includes('Gelesen: Ereignisprotokoll Microsoft Defender, Ereignisprotokolle AppLocker.') && t.includes('Nicht gelesen: Ereignisprotokoll Anwendung, Ereignisprotokoll System, Ereignisprotokoll Druckdienst, Ereignisprotokoll SMB-Client.'), 'teilweiser Rueckblick nennt gelesene und nicht gelesene Protokolle: ' + t);
  ok(t.includes('In den gelesenen Protokollen stehen für die 7 Tage vor der Messung keine Ereignisse der erfassten Arten.') && !t.includes('Arten in den Protokollen'), 'teilweiser Rueckblick ohne Ereignisse: keine Aussage ueber alle Protokolle');
  ok(pe.page.errors.length === 0, 'Skriptfehler teilweiser Rueckblick: ' + pe.page.errors.join(' | '));
  await pe.page.close();
  const pv = await openExpert(browser, patched(dir, 'report.html', 'report-lb-partial-events.html', (J) => { J.before.status = 'partial'; J.before.logs = partLogs(J); }), scheme);
  t = await bt(pv.page);
  ok(t.includes('Nicht gelesen: Ereignisprotokoll Anwendung') && t.includes('Ereignisse aus diesen Tagen') && await pv.page.locator('#before .day').count() === pv.D.before.perDay.length && await pv.page.locator('#before .inc').count() === pv.D.before.incidents.length, 'teilweiser Rueckblick mit Ereignissen: Zahlen, Balken, Vorfaelle und nicht gelesene Protokolle');
  ok(!t.includes('keine Ereignisse der erfassten Arten'), 'teilweiser Rueckblick mit Ereignissen ohne Leer-Aussage');
  await pv.page.close();
  const full = await openExpert(browser, path.join(dir, 'report.html'), scheme);
  ok(!(await bt(full.page)).includes('Nicht gelesen'), 'vollstaendig gelesener Rueckblick ohne Liste nicht gelesener Protokolle');
  await full.page.close();
  // N3: a reported time after a -To cut but inside the capture
  const tc = await openExpert(browser, patched(dir, 'report-nodata.html', 'report-tocut.html', (J) => {
    J.meta.focus = Object.assign({}, J.meta.focus, { reportedMs: J.tickT[J.tickT.length - 1] + 120000 }); J.eventsOutsideCut = 0;
  }), scheme);
  ok(tc.D.meta.focus.reportedMs < tc.D.before.captureEnd, 'Eingabe: gemeldete Zeit nach dem Ausschnitt in der Aufzeichnung');
  const fi = await tc.page.locator('#focusInfo').innerText();
  ok(fi.includes('(außerhalb des gewählten Zeitraums)') && !fi.includes('außerhalb der Messung'), 'nach einem Ausschnitt mit -To: ausserhalb des gewaehlten Zeitraums: ' + fi);
  ok(tc.page.errors.length === 0, 'Skriptfehler Ausschnitt -To: ' + tc.page.errors.join(' | '));
  await tc.page.close();
}

async function checkLongNames(browser, dir, scheme) {               // I2: lange Namen ohne seitliches Rollen
  const long = 'Microsoft.VisualStudio.Diagnostics.ServiceModelSink.Extended.Instrumentation.Runtime.4.0.dll';
  const file = patched(dir, 'report.html', 'report-long.html', (J) => {
    const o = J.incidents.find((i) => i.type === 'ereignis' && i.event.app === 'OUTLOOK.EXE');
    o.event.modules[0].name = long; o.event.app = long.replace('.dll', '.exe'); o.events[0].module = long;
    const pr = J.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print');
    pr.event.driver = long.replace('.dll', ' Druckertreiber'); pr.event.modules[0].name = long; J.print.drivers[0].name = pr.event.driver;
    // the texts of the guided view carry the same names: card, row of the further incidents, band and hint
    Object.assign(o.guide, { title: 'Absturz von ' + o.event.app, userView: long, impact: long, short: long }); o.guide.checks[0].text = 'Modul ' + long + ' prüfen'; o.causeText = 'Fehlerhaftes Modul: ' + long;
    pr.guide.title = 'Drucken gestört: ' + pr.event.driver; J.lagebild.sentence = 'Handlungsbedarf: ' + long; J.lagebild.hints = ['Nicht gemessen: ' + long];
  });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, colorScheme: scheme });
  page.errors = []; page.on('pageerror', (e) => page.errors.push(e.message));
  await page.goto('file://' + file);
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent));
  const wg = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok((await page.locator('#cards').innerText()).includes(long) && (await page.locator('#more').innerText()).includes(long.replace('.dll', ' Druckertreiber')) && wg[0] <= wg[1], 'lange Namen in der gefuehrten Ansicht schmal ohne seitliches Rollen: ' + wg.join(' > '));
  // the expert view with the list of incidents unfolded and the tab of the print drivers, then the incident views
  await showExpert(page);
  await page.click('#incToggle'); await showTab(page, 'print');
  ok(long.length >= 90, 'Name mit 90 Zeichen');
  let w = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok((await page.locator('#tPrintDrivers').innerText()).includes(long.replace('.dll', ' Druckertreiber')) && w[0] <= w[1], 'lange Namen schmal ohne seitliches Rollen: ' + w.join(' > '));
  for (const inc of D.incidents.filter((i) => i.type === 'ereignis' && (i.event.kind === 'print' || i.event.modules.some((m) => m.name.length > 80)))) {
    await openIncident(page, inc.id);
    w = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
    ok(w[0] <= w[1], 'lange Namen im Vorfall ' + inc.id + ' schmal ohne seitliches Rollen: ' + w.join(' > '));
  }
  ok(page.errors.length === 0, 'Skriptfehler lange Namen: ' + page.errors.join(' | '));
  await page.close();
}

async function checkMask(browser, dir, scheme) {                   // Maskierung: Stufe im Kopf
  const { page } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('#maskInfo').count() === 0, 'unmaskiert ohne Hinweis');
  await page.close();
  // the head bar is the same in both views: the note stands in the guided view the report opens in, and in the expert view
  const m = await open(browser, path.join(dir, 'report-masked.html'), scheme);
  ok(await m.page.locator('#maskInfo').count() === 1 && await m.page.locator('header #maskInfo').isVisible(), 'Hinweis vorhanden');
  ok((await m.page.locator('#maskInfo').innerText()).includes('Maskiert: alle Namen'), 'Stufe im Kopf');
  await showExpert(m.page);
  ok(await m.page.locator('header #maskInfo').isVisible() && (await m.page.locator('#maskInfo').innerText()).includes('Maskiert: alle Namen'), 'Stufe im Kopf, Expertenansicht');
  // the whole text of the page, hidden tabs and sections included; the embedded data are checked by the Pester test
  const all = await m.page.evaluate(() => { const b = document.body.cloneNode(true); b.querySelectorAll('script').forEach((x) => x.remove()); return b.textContent; });
  ok(all.length > 10000 && !all.match(/user0\d\d|SIM-VDA01|CONTOSO/), 'keine Namen auf der Seite');
  ok(m.page.errors.length === 0, 'Skriptfehler maskiert: ' + m.page.errors.join(' | '));
  await m.page.close();
  // the note is text in the header next to the subtitle; the symbol is hidden from screen readers
  const p = await open(browser, path.join(dir, 'report-masked.html'), scheme);
  ok(await p.page.locator('header #maskInfo').count() === 1 && await p.page.locator('#maskInfo [aria-hidden="true"]').count() === 1, 'Hinweis im Kopf, Symbol fuer Vorleser verborgen');
  ok((await p.page.locator('#maskInfo').innerText()).includes('Maskiert: alle Namen (Benutzer, Clients, Server, Freigaben, Domänen, Adressen, Drucker ersetzt)'), 'Text der Stufe Alles');
  const colours = () => p.page.evaluate(() => [getComputedStyle(document.getElementById('maskInfo')).color, getComputedStyle(document.body).color]);
  let col = await colours();
  ok(col[0] === col[1], 'Hinweis in der Textfarbe der gefuehrten Ansicht: ' + col.join(' / '));
  await showExpert(p.page);
  col = await colours();
  ok(col[0] === col[1], 'Hinweis in der Textfarbe der Expertenansicht: ' + col.join(' / '));
  await p.page.emulateMedia({ media: 'print' });
  ok(await p.page.locator('#maskInfo').isVisible(), 'Hinweis bleibt im Druck');
  await p.page.close();
  // the other level, an unknown value: the page never looks unmasked; markup in the value stays text
  const pers = await openExpert(browser, patched(dir, 'report-masked.html', 'report-mask-personen.html', (J) => { J.meta.mask = 'Personen'; }), scheme);
  ok((await pers.page.locator('#maskInfo').innerText()).includes('Maskiert: Personen (Benutzer und Clients ersetzt)'), 'Text der Stufe Personen');
  await pers.page.close();
  const bad = '<img src=x onerror="window.__xss=1">';
  const unk = await openExpert(browser, patched(dir, 'report-masked.html', 'report-mask-unknown.html', (J) => { J.meta.mask = 'Neu ' + bad; }), scheme);
  ok((await unk.page.locator('#maskInfo').innerText()).includes('Maskiert: Neu ' + bad), 'unbekannte Stufe zeigt den Wert');
  ok(await unk.page.evaluate(() => window.__xss === undefined) && await unk.page.locator('header img').count() === 0, 'Stufe als Text, nicht als Markup');
  ok(unk.page.errors.length === 0, 'Skriptfehler unbekannte Stufe: ' + unk.page.errors.join(' | '));
  await unk.page.close();
}

async function checkMaskedPersonen(browser, dir, scheme) {         // Maskierung: ein echter Bericht der Stufe Personen
  const { page, D } = await open(browser, path.join(dir, 'report-masked-personen.html'), scheme);
  ok(D.meta.mask === 'Personen' && (await page.locator('#maskInfo').innerText()).includes('Maskiert: Personen (Benutzer und Clients ersetzt)'), 'Personen: Stufe im Kopf');
  // removed message texts say so, without a dangling colon
  const titles = await page.locator('#guided #timeline .event').evaluateAll((els) => els.map((e) => e.getAttribute('title')));
  ok(titles.length > 0 && titles.every((t) => t.endsWith(': Meldung entfernt (maskiert)')), 'Personen: Ereignisse ohne Meldungstext sagen es');
  await showExpert(page);
  const focus = await page.locator('#focusInfo').innerText();
  ok(focus.includes('(Name entfernt)') && focus.includes('nicht gefunden') && !/schmidt|unbekannt|KLINIK/i.test(focus), 'Personen: unbekannter gemeldeter Benutzer ohne Namen: ' + focus);
  const all = await page.evaluate(() => { const b = document.body.cloneNode(true); b.querySelectorAll('script').forEach((x) => x.remove()); return b.textContent; });
  ok(all.length > 10000 && !/user0\d\d|WS-\d{4}|schmidt|KLINIK/.test(all), 'Personen: keine Benutzer und Clients auf der Seite');
  ok(all.includes('SIM-VDA01') && all.includes('Benutzer 01'), 'Personen: Server bleibt, Ersatznamen stehen');
  ok(page.errors.length === 0, 'Skriptfehler Personen: ' + page.errors.join(' | '));
  await page.close();
  // the events in the window of a performance incident (the simulated hour has none there: one masked event is put in)
  const win = await openExpert(browser, patched(dir, 'report-masked-personen.html', 'report-mask-window.html', (J) => {
    J.incidents.find((i) => i.lead === 'cpu').events = [J.events.find((e) => e.text === '')];
  }), scheme);
  const cpu = win.D.incidents.find((i) => i.lead === 'cpu');
  await openIncident(win.page, cpu.id);
  const li = await win.page.locator(`#incident[data-id="${cpu.id}"] .iv-evidence ul.plain li`).allInnerTexts();
  ok(li.some((t) => t.endsWith(': Meldung entfernt (maskiert)')) && !li.some((t) => /:\s*$/.test(t)), 'Personen: Ereignisse im Fenster ohne leeren Doppelpunkt');
  ok(win.page.errors.length === 0, 'Skriptfehler Ereignisse im Fenster: ' + win.page.errors.join(' | '));
  await win.page.close();
  // a capture that ended on an error and a failed source call, both with their message removed by the masking
  const err = await openExpert(browser, patched(dir, 'report-masked-personen.html', 'report-mask-errors.html', (J) => {
    J.meta.endReason = 'error'; J.meta.endMessage = ''; J.quality.sourceErrors = [{ source: 'proc.info', label: 'Prozessdaten', count: 2, firstMs: null, firstMessage: '' }];
  }), scheme);
  ok((await err.page.locator('#subtitle').innerText()).includes('Aufzeichnung mit Fehler beendet: Meldung entfernt (maskiert)'), 'Personen: Endemeldung entfernt');
  ok((await err.page.locator('#sourceErrors').evaluate((e) => e.textContent)).includes(': Meldung entfernt (maskiert)'), 'Personen: Fehlermeldung der Abfrage entfernt');
  ok(err.page.errors.length === 0, 'Skriptfehler entfernte Meldungen: ' + err.page.errors.join(' | '));
  await err.page.close();
  const plain = await openExpert(browser, path.join(dir, 'report.html'), scheme);
  const plainText = await plain.page.evaluate(() => { const b = document.body.cloneNode(true); b.querySelectorAll('script').forEach((x) => x.remove()); return b.textContent + [...b.querySelectorAll('[title]')].map((e) => e.title).join(' '); });
  ok(!plainText.includes('Meldung entfernt'), 'unmaskiert: kein Hinweis auf entfernte Meldungen');
  await plain.page.close();
}

async function checkMaskedPage(browser, dir, scheme) {             // Maskierung: der ganze Bericht bleibt bedienbar (ein Schema genuegt)
  const { page, D } = await openExpert(browser, path.join(dir, 'report-masked.html'), scheme);
  ok(D.incidents.length > 0 && await page.locator('#incList .inc').count() === D.incidents.length, 'maskiert: ein Eintrag je Vorfall');
  let shown = 0;
  for (const inc of D.incidents.concat(D.before.incidents)) { const v = await openIncident(page, inc.id); if ((await v.locator('.iv-evidence .techtext').innerText()) === inc.text) shown++; }
  ok(shown === D.incidents.length + D.before.incidents.length, 'maskiert: alle Vorfaelle geoeffnet');
  await showTab(page, 'events');
  ok(await page.locator('#tEvents tbody tr').count() === Math.min(200, D.events.length), 'maskiert: Ereignisliste');
  await showTab(page, 'print');
  ok(await page.locator('#tPrintQueues tbody tr').count() > 0 && (await page.locator('#tPrintQueues').innerText()).includes('Drucker 01'), 'maskiert: Drucken mit Ersatznamen');
  ok(await page.locator('#chCpu svg path').count() > 0 && await page.locator('#tiles .tile').count() > 0, 'maskiert: Uebersicht gezeichnet');
  await showTab(page, 'sessions');
  const s = D.sessions.find((x) => x.user === 'Benutzer 01');
  await page.click(`#tSessions tbody tr[data-id="${s.i}"]`);
  ok((await page.locator('#tSessions').innerText()).includes('Benutzer 01') && await page.locator('#dSessions .chart-input svg path').count() > 0, 'maskiert: Sitzungstabelle und Sitzung');
  await showTab(page, 'apps');
  await showTab(page, 'procs');
  ok(await page.locator('#tProcs tbody tr').count() > 0, 'maskiert: Prozesse');
  ok(page.errors.length === 0, 'Skriptfehler maskierter Bericht: ' + page.errors.join(' | '));
  await page.close();
  // the masked header at phone width
  const n = await browser.newPage({ viewport: { width: 390, height: 844 }, colorScheme: scheme });
  n.errors = []; n.on('pageerror', (e) => n.errors.push(e.message));
  await n.goto('file://' + path.join(dir, 'report-masked.html'));
  for (const view of ['gefuehrte Ansicht', 'Expertenansicht']) {
    const w = await n.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
    ok(w[0] <= w[1], 'maskierter Kopf schmal ohne seitliches Rollen, ' + view + ': ' + w.join(' > '));
    const box = await n.locator('#maskInfo').boundingBox(), sw = await n.locator('#viewSwitch').boundingBox();
    ok(box && box.x >= 0 && box.x + box.width <= 390, 'Hinweis passt in die schmale Ansicht, ' + view);
    ok(sw && sw.x >= 0 && sw.x + sw.width <= 390, 'Umschalter passt in die schmale Ansicht, ' + view);
    await showExpert(n);
  }
  ok(n.errors.length === 0, 'Skriptfehler maskiert schmal: ' + n.errors.join(' | '));
  await n.close();
}

async function checkFinalWave(browser, dir, scheme) {               // Abschlussrunde des Plans: Zaehler, Rueckblick, Quellen
  // the simulated hour: no counters, no folding, nothing read incompletely
  const base = await openExpert(browser, path.join(dir, 'report.html'), scheme);
  ok(await base.page.locator('#eventReads').count() === 0 && await base.page.locator('#beforeReads').count() === 0 && await base.page.locator('#beforeMore').count() === 0, 'ohne Zaehler und kurze Liste: kein Hinweis');
  await showTab(base.page, 'quality');
  ok(!(await base.page.locator('#tSources').innerText()).includes('beim Lesen fehlgeschlagen'), 'ohne Lesefehler kein Vermerk in den Quellen');
  await base.page.close();
  const p = await openExpert(browser, patched(dir, 'report.html', 'report-finalwave.html', (J) => {
    J.quality.eventReads = [{ log: 'application', label: 'Ereignisprotokoll Anwendung', dropped: 250, skipped: 3, unformatted: 0 }, { log: 'defender', label: 'Ereignisprotokoll Microsoft Defender', dropped: 0, skipped: 0, unformatted: 1 }];
    J.before.readCounts = [{ log: 'application', label: 'Ereignisprotokoll Anwendung', skipped: 2, unformatted: 1 }];
    J.before.capped = ['application', 'system'];
    J.before.perDay[0].partial = true;
    J.quality.sources.find((s) => s.id === 'events.system').readFailed = true;
    const first = J.before.incidents[0];
    for (let k = 0; k < 27; k++) J.before.incidents.push(Object.assign({}, first, { id: 1000 + k, start: first.start + (k + 1) * 3600000, end: first.end + (k + 1) * 3600000, focus: false }));
  }), scheme);
  await showTab(p.page, 'quality');
  const D = p.D, q = await p.page.locator('#quality').innerText();
  ok(q.includes('Ereignisprotokoll Anwendung: mindestens 250 Ereignisse nicht aufgezeichnet (Obergrenze je Abruf) · 3 Datensätze nicht lesbar und übersprungen'), 'Messqualitaet nennt die nicht aufgezeichneten Ereignisse: ' + q);
  ok(q.includes('Ereignisprotokoll Microsoft Defender: 1 Meldungstext nicht lesbar') && !q.includes('0 Datensätze'), 'nur Zahlen ueber null');
  ok(q.includes('Rückblick unvollständig gelesen für Anwendung, System'), 'unvollstaendig gelesener Rueckblick in der Messqualitaet');
  ok((await p.page.locator('#tSources tbody tr', { hasText: 'Ereignisprotokoll System' }).innerText()).includes('beim Lesen fehlgeschlagen'), 'Lesefehler beim Protokoll in den Quellen');
  await showTab(p.page, 'before');
  const b = await p.page.locator('#before').innerText();
  const oldest = D.before.oldest.find((o) => o.log === 'application');
  ok(b.includes('Rückblick unvollständig gelesen') && b.includes('Anwendung (gelesen ab ' + ddmmyyyy(oldest.t, D.meta.offsetMin)) && b.includes('System (kein Ereignis gelesen)') && !b.includes('Obergrenze der gelesenen'), 'je Protokoll gelesen ab: ' + b.split('\n').slice(0, 6).join(' / '));
  ok(b.includes('Beim Lesen des Rückblicks: Anwendung: 2 Datensätze nicht lesbar und übersprungen, 1 Meldungstext nicht lesbar.'), 'Hinweis am Rueckblick: ' + b);
  ok(await p.page.locator('#before .day.partial').count() === 1 && (await p.page.locator('#before .day.partial').innerText()).includes('(Teil des Tages)') && b.includes('nur zum Teil erfasst'), 'Teiltage gekennzeichnet');
  ok(await p.page.locator('#before .before-incidents > .inc').count() === 20 && await p.page.locator('#before .inc:visible').count() === 20 && (await p.page.locator('#beforeMore').innerText()) === 'weitere 11 Vorfälle anzeigen', 'Liste der Vorfaelle vor der Messung nach 20 gefaltet');
  await p.page.click('#beforeMore');
  ok(await p.page.locator('#before .inc:visible').count() === 31 && await p.page.locator('#beforeMore').count() === 0, 'alle Vorfaelle nach dem Klick');
  ok(p.page.errors.length === 0, 'Skriptfehler Abschlussrunde: ' + p.page.errors.join(' | '));
  await p.page.close();
}

// locations of each place of the brief's table: [where, selector of the hint there, optional condition on the report data].
// where: 'guided' for the guided view (its folded areas are opened before), 'expert' for what the expert view always shows
// (incident column, tiles, charts, foot), a tab of its tables, or 'incident' for the evidence of the incident view of an
// incident that has the place (the detail of an incident does not unfold in the expert view any more)
const SKIP_LOCATIONS = (() => {
  const at = (p) => `.notmeasured[data-place="${p}"]`, inc = (p) => `#incident .iv-evidence .evidence ${at(p)}`;
  return {
    procs: [['procs', `#xt-procs > ${at('procs')}`], ['expert', `#chCpuStack ${at('procs')}`], ['expert', `#chMemStack ${at('procs')}`],
      ['expert', `footer ${at('procs')}`], ['quality', `#quality ${at('procs')}`], ['guided', `footer ${at('procs')}`], ['guided', `#qualityG ${at('procs')}`]],
    apps: [['apps', `#xt-apps > ${at('apps')}`], ['expert', `#cardMainApp #chMainApp ${at('apps')}`]],
    'sessions.resources': [['sessions', `#xt-sessions > ${at('sessions.resources')}`], ['sessions', `#dSessions .chart-cpu ${at('sessions.resources')}`],
      ['sessions', `#dSessions .chart-ws ${at('sessions.resources')}`], ['sessions', `#dSessions .chart-io ${at('sessions.resources')}`],
      ['sessions', `#dSessions > ${at('sessions.resources')} >> nth=0`], ['sessions', `#dSessions > ${at('sessions.resources')} >> nth=1`]],
    'incidents.contributors': [['incident', inc('incidents.contributors')], ['expert', `#incList .inc ${at('incidents.contributors')}`], ['guided', `#cards .card.inc ${at('incidents.contributors')}`]],
    'incidents.delayProcs': [['incident', inc('incidents.delayProcs')], ['expert', `#incList .inc ${at('incidents.delayProcs')}`], ['guided', `#cards .card.inc ${at('incidents.delayProcs')}`]],
    'print.processes': [['print', `#print ${at('print.processes')}`]],
    'print.drivers': [['print', `#print ${at('print.drivers')}`]],
    'print.queues': [['print', `#print ${at('print.queues')}`]],
    volumes: [['expert', `#chVolumes ${at('volumes')}`]],
    shares: [['expert', `#chShares ${at('shares')}`]],
    probes: [['expert', `#chProbes ${at('probes')}`]],
    'sessions.profile': [['sessions', `#dSessions .chart-profile ${at('sessions.profile')}`]],
    'sessions.rtt': [['sessions', `#dSessions .chart-rtt ${at('sessions.rtt')}`]],
    // the key figure of the chronic states says "nicht gemessen" where its count is 0 only because the ICA values are missing
    citrix: [['sessions', `#dSessions > ${at('citrix')}`], ['guided', `#kpis .kpi[data-kpi="chronic"] ${at('citrix')}`, (D) => !D.lagebild.kpis.chronic]],
    'sessions.events': [['sessions', `#dSessions .sess-events ${at('sessions.events')}`]],
    'incidents.ica': [['incident', inc('incidents.ica')]],
    'incidents.endpoints': [['incident', inc('incidents.endpoints')]],
    'incidents.events': [['incident', inc('incidents.events')]],
    events: [['guided', `#guided #timeline .tl-row[data-group="skipped"] ${at('events')}`], ['guided', `#kpis .kpi[data-kpi="events"] ${at('events')}`], ['guided', `#qualityG ${at('events')}`],
      ['quality', `#quality ${at('events')}`], ['events', `#xt-events ${at('events')}`]],
    before: [['before', `#before ${at('before')}`], ['guided', `#beforeG ${at('before')}`]]
  };
})();
async function checkSkip(browser, dir, scheme) {   // Messkategorien
  const full = await openExpert(browser, path.join(dir, 'report.html'), scheme);
  ok(await full.page.locator('#skipInfo').count() === 0 && await full.page.locator('.notmeasured').count() === 0, 'ohne -Skip kein Hinweis und keine Stelle "nicht gemessen"');
  await full.page.close();
  for (const n of ['prozesse', 'laufwerke', 'citrix', 'ereignisse', 'rueckblick', 'drucken', 'gegenstellen', 'alle', 'alle-masked']) {   // Review Focus 1
    const { page, D } = await open(browser, path.join(dir, `report-skip-${n}.html`), scheme);
    ok(await page.locator('header #skipInfo').isVisible(), n + ': Kopf nennt die Kategorien auch in der gefuehrten Ansicht');
    await page.evaluate(() => { for (const d of document.querySelectorAll('#guided details')) d.open = true; });
    await showExpert(page);
    for (const t of ['apps', 'procs', 'sessions']) await showTab(page, t);
    await page.click('#tSessions tbody tr >> nth=0');
    // the incident view of an incident that has a place of the incident's evidence; back out of it to the view it was opened from
    const withPlace = (p) => D.incidents.find((i) => IV_PLACES[p](i));
    const leaveIncident = async () => { if (await page.evaluate(() => window.WP.incident) != null) { await page.evaluate(() => window.WP.closeIncident()); await ivClosed(page); } };
    const info = await page.locator('header #skipInfo').innerText();
    ok(info.includes('Nicht gemessen (-Skip): ' + D.skipped.map((s) => s.label).join(', ')), n + ': Kopf nennt die Kategorien: ' + info);
    const all = await page.evaluate(() => { const b = document.body.cloneNode(true); b.querySelectorAll('script').forEach((x) => x.remove()); return b.textContent; });
    for (const s of D.skipped) {
      ok(all.includes(s.text + ' (-Skip ' + s.id + ')'), n + ': Grund von ' + s.id + ' steht auf der Seite');
      for (const p of s.places) {
        if (IV_PLACES[p] && withPlace(p)) await openIncident(page, withPlace(p).id);
        ok(await page.locator(`.notmeasured[data-place="${p}"]`).count() > 0, n + ': Stelle ' + p + ' sagt "nicht gemessen"');
      }
    }
    // every location of a place in the brief's table shows its hint, visibly, in the view and on the tab where it stands
    for (const s of D.skipped) for (const p of s.places) for (const [where, sel, when] of (ok(SKIP_LOCATIONS[p], n + ': Stelle ' + p + ' fehlt in SKIP_LOCATIONS (tests/report-browser.js)'), SKIP_LOCATIONS[p])) {
      if (when && !when(D)) continue;
      if (where === 'incident') await openIncident(page, withPlace(p).id);
      else { await leaveIncident(); if (where === 'guided') await showGuided(page); else if (where === 'expert') await showExpert(page); else await showTab(page, where); }
      ok(await page.locator(sel).first().isVisible(), n + ': Stelle ' + p + ' sichtbar an ' + sel);
    }
    await leaveIncident(); await showExpert(page);
    // an input delay that could not be checked for a bottleneck (without Laufwerke) is never called "ohne Engpass"
    if (n === 'laufwerke' || n === 'alle') {
      ok(D.incidents.some((i) => i.type === 'ohne-engpass' && i.unverified), n + ': Daten mit ungeprueftem Vorfall ohne erkannten Engpass');
      const shown = await page.evaluate(() => document.body.innerText);
      ok(!shown.includes('ohne Engpass') && shown.includes('ohne erkannten Engpass'), n + ': kein "ohne Engpass" fuer einen ungeprueften Vorfall');
      await showGuided(page);
      const guided = await page.evaluate(() => document.body.innerText);
      ok(!guided.includes('ohne Engpass') && guided.includes('ohne erkannten Engpass'), n + ': kein "ohne Engpass" fuer einen ungeprueften Vorfall, gefuehrte Ansicht');
    }
    ok(page.errors.length === 0, n + ': Skriptfehler: ' + page.errors.join(' | '));
    await page.close();
  }
  const p = await openExpert(browser, path.join(dir, 'report-skip-prozesse.html'), scheme);
  const cpu = p.D.incidents.find((i) => i.lead === 'cpu'), sentence = 'Kein Hauptverursacher ermittelt: Prozesse wurden bei dieser Messung nicht erfasst.';
  let entry = await openIncident(p.page, cpu.id);
  ok((await entry.locator('.iv-evidence .causebox').innerText()).includes(sentence) && cpu.text.includes(sentence), 'Verursacher: Text und Seite gleich');   // Review Focus 3
  ok(!(await entry.locator('.iv-evidence').innerText()).match(/keine Prozessdaten|keine Prozesse mit der Rolle Sicherheit/), 'kein "keine" fuer nicht Gemessenes');
  // counts that are 0 only because processes were not measured are not printed as numbers
  const foot = await p.page.locator('footer').innerText();
  ok(!foot.includes('von 0 Prozessen') && !foot.includes('Prozess-Messwerte') && await p.page.locator('footer .notmeasured[data-place="procs"]').count() === 1, 'Fuss ohne Prozesszahlen: ' + foot);
  await showTab(p.page, 'sessions');
  ok(await p.page.locator('#xt-sessions .notmeasured[data-place="sessions.resources"]').count() === 1, 'Hinweis ueber der Sitzungstabelle');
  const row = await p.page.locator('#tSessions tbody tr >> nth=0').innerText(), heads = await p.page.locator('#tSessions thead th').allInnerTexts();
  const cells = row.split('\t'), at = (h) => cells[heads.findIndex((x) => x.startsWith(h))];
  ok(['CPU-Anteil %', 'CPU-Zeit s', 'CPU Ø %', 'RAM Ø', 'I/O MB', 'Prozesse Ø'].every((h) => at(h) === '–'), 'Spalten der Prozessdaten zeigen "–": ' + row);
  await p.page.click('#tSessions tbody tr >> nth=0');
  ok(!(await p.page.locator('#dSessions .kv').innerText()).match(/CPU-Anteil 0/), 'Sitzungsansicht ohne 0 % CPU-Anteil');
  // a crash without process data: the assignment to sessions was not checked, never "Sitzung nicht ermittelt"
  const chrome = p.D.incidents.find((i) => i.type === 'ereignis' && i.event.app === 'chrome.exe');
  ok(chrome && chrome.event.sessionUnknown && chrome.event.unchecked.some((u) => u.id === 'users'), 'Daten: chrome.exe ohne Zuordnung, nicht geprueft');
  entry = await openIncident(p.page, chrome.id);
  const det = await entry.locator('.iv-evidence').innerText(), pats = await entry.locator('.iv-evidence .patterns li').allInnerTexts();
  ok(!det.includes('Sitzung nicht ermittelt') && !det.match(/ohne Benutzersitzung/i), 'chrome.exe: keine Aussage zur Sitzung: ' + det.slice(0, 300));
  ok(chrome.event.unchecked.every((u) => pats.some((t) => t.includes('nicht geprüft: ' + u.text))) && !pats.some((t) => t.includes('Kein Muster erkannt')), 'chrome.exe: je Eintrag ein "nicht geprueft": ' + pats.join(' / '));
  ok(p.page.errors.length === 0, 'Skriptfehler prozesse: ' + p.page.errors.join(' | '));
  await p.page.close();
  const d = await openExpert(browser, path.join(dir, 'report-skip-drucken.html'), scheme);
  entry = await openIncident(d.page, d.D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print').id);
  const pat = await entry.locator('.iv-evidence .patterns').innerText();
  ok(pat.includes('nicht geprüft: Bezug zu einem Druckertreiber (Drucken nicht gemessen)') && !pat.includes('Kein Muster erkannt'), 'Muster nicht geprueft statt "kein Muster"');
  await showTab(d.page, 'print');
  ok(!(await d.page.locator('#print').innerText()).includes('Keine Treiberliste aufgezeichnet'), 'Drucken: nicht "keine Treiberliste"');
  await d.page.close();
  const r = await openExpert(browser, path.join(dir, 'report-skip-rueckblick.html'), scheme);
  // Aussage geaendert (Abschlussrunde, Minor 5): der Hinweis nennt den Grund, der Satz zum Zustand sagt dasselbe nicht noch einmal
  await showTab(r.page, 'before');
  const rbt = await r.page.locator('#before').innerText();
  ok(rbt.includes('nicht gemessen – Ereignisse der Tage vor der Messung wurden nicht erfasst. (-Skip Rueckblick)') && !rbt.includes('Der Rückblick war abgeschaltet'), 'Rueckblick abgeschaltet, einmal gesagt: ' + rbt);
  await r.page.close();
  const e = await openExpert(browser, path.join(dir, 'report-skip-ereignisse.html'), scheme);
  ok(e.D.quality.eventReads.length === 0 && await e.page.locator('#quality .notmeasured[data-place="events"]').count() === 1, 'Messqualitaet: Ereignisprotokolle nicht gemessen');
  await showTab(e.page, 'print');
  // driver involvement draws on the incidents from events: without the events of the capture never "nein"
  const cellsOf = async (page) => (await page.locator('#tPrintDrivers tbody td:nth-child(6)').allInnerTexts()).map((t) => t.replace(/\s+/g, ' ').trim());
  let drv = await cellsOf(e.page);
  // Aussage geaendert (Abschlussrunde, Minor 10): der Rueckblick ist gelesen, "nein" gilt fuer die Tage vor der Messung
  ok(e.D.before.status === 'read' && drv.length === 3 && drv.every((t, k) => t === (e.D.print.drivers[k].involved ? 'beteiligt' : 'nein (vor der Messung)')) && await e.page.locator('#print .notmeasured[data-place="events"]').isVisible(), 'Ereignisse: Treiber "nein" nur vor der Messung, mit Grund: ' + drv.join(' / '));
  await e.page.close();
  const a = await openExpert(browser, path.join(dir, 'report-skip-alle.html'), scheme);
  await showTab(a.page, 'print');
  ok(await a.page.locator('#tPrintDrivers').count() === 0 && !(await a.page.locator('#print').innerText()).match(/\bnein\b/), 'alle: keine Treibertabelle, kein "nein"');
  await a.page.close();
  const rb = await openExpert(browser, path.join(dir, 'report-skip-rueckblick.html'), scheme);
  await showTab(rb.page, 'print');
  drv = await cellsOf(rb.page);
  ok(drv.filter((t) => t === 'beteiligt').length === 1 && drv.filter((t) => t === 'nein (während der Messung)').length === 2 && await rb.page.locator('#print .notmeasured[data-place="before"]').isVisible(), 'Rueckblick: "nein" nur fuer die Messung: ' + drv.join(' / '));
  await rb.page.close();
  const f = await openExpert(browser, path.join(dir, 'report.html'), scheme);
  await showTab(f.page, 'print');
  drv = await cellsOf(f.page);
  ok(drv.join('|') === f.D.print.drivers.map((x) => x.involved ? 'beteiligt' : 'nein').join('|') && await f.page.locator('#print .note', { hasText: 'An einem Vorfall beteiligt' }).count() === 0, 'voller Lauf: Spalte unveraendert: ' + drv.join(' / '));
  await f.page.close();
}

async function checkFixWave(browser, dir, scheme) {   // Messkategorien, Abschlussrunde
  const txt = async (page, sel) => (await page.locator(sel).innerText()).replace(/\s+/g, ' ').trim();
  // I1: a capture without findings names every category left out and never says that everything was measured
  const ne = await openExpert(browser, path.join(dir, 'report-skip-none-ereignisse.html'), scheme);
  ok(ne.D.noFinding && ne.D.skipped.length === 1, 'ohne Ereignisse ohne Befund: Daten');
  ok(await txt(ne.page, '#findHead') === 'Keine Vorfälle aus den gemessenen Werten; Vorfälle aus Ereignissen wurden nicht erfasst (-Skip Ereignisse).', 'Kopf ohne Ereignisse: ' + await txt(ne.page, '#findHead'));
  let nf = await txt(ne.page, '#noFinding');
  ok(nf.includes('Nicht gemessen (1) Ereignisse – Ereignisse während der Messung wurden nicht erfasst. (-Skip Ereignisse)') && !nf.includes('alle Messwerte wurden erfasst'), 'ohne Befund ohne Ereignisse: ' + nf);
  ok(ne.page.errors.length === 0, 'Skriptfehler none-ereignisse: ' + ne.page.errors.join(' | '));
  await ne.page.close();
  const na = await openExpert(browser, path.join(dir, 'report-skip-none-alle.html'), scheme);
  nf = await txt(na.page, '#noFinding');
  const listed = await na.page.locator('#noFinding li[data-skip]').evaluateAll((l) => l.map((x) => x.dataset.skip));
  ok(na.D.noFinding && listed.join(',') === na.D.skipped.map((x) => x.id).join(',') && listed.length === 7, 'ohne Befund ohne alle: jede Kategorie genannt: ' + listed.join(','));
  ok(na.D.skipped.every((x) => nf.includes(x.label + ' – ' + x.text + ' (-Skip ' + x.id + ')')) && nf.includes('Nicht gemessen (' + (7 + na.D.sollIst.filter((r) => !r.measured).length) + ')') && !nf.includes('alle Messwerte wurden erfasst'), 'ohne alle: Liste: ' + nf);
  ok((await txt(na.page, '#findHead')).startsWith('Keine Vorfälle aus den gemessenen Werten;'), 'Kopf ohne alle');
  ok(na.page.errors.length === 0, 'Skriptfehler none-alle: ' + na.page.errors.join(' | '));
  await na.page.close();
  const n0 = await openExpert(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await txt(n0.page, '#findHead') === 'Keine Vorfälle im Messzeitraum.' && (await txt(n0.page, '#noFinding')).includes('Nicht gemessen (0) keine: alle Messwerte wurden erfasst') && await n0.page.locator('#noFinding li[data-skip]').count() === 0, 'ohne -Skip ohne Befund: wie bisher');
  await n0.page.close();
  // the count of a capture with incidents without the events of the capture says that incidents from events were not recorded
  for (const [file, want] of [['report-skip-ereignisse.html', true], ['report-skip-alle.html', true], ['report-skip-prozesse.html', false], ['report.html', false]]) {
    const r = await openExpert(browser, path.join(dir, file), scheme), h = await txt(r.page, '#findHead');
    ok(h.endsWith(' Vorfälle aus Ereignissen wurden nicht erfasst (-Skip Ereignisse).') === want && /^\d+ Vorf/.test(h), file + ': Kopf: ' + h);
    await r.page.close();
  }
  // I2: the sentence for the reported user says what it does not count
  const fe = await openExpert(browser, path.join(dir, 'report-skip-focus-ereignisse.html'), scheme);
  ok(await txt(fe.page, '#focusInfo') === 'Gemeldeter Benutzer user008, Sitzung #9. 1 Vorfall betrifft den Benutzer. Abstürze und Hänger sind dabei nicht gezählt: Ereignisse während der Messung wurden nicht erfasst (-Skip Ereignisse).', 'Fokus ohne Ereignisse: ' + await txt(fe.page, '#focusInfo'));
  await fe.page.close();
  const fp = await openExpert(browser, path.join(dir, 'report-skip-focus-prozesse.html'), scheme);
  ok(await txt(fp.page, '#focusInfo') === 'Gemeldeter Benutzer user008, Sitzung #9. 1 Vorfall betrifft den Benutzer. Abstürze und Hänger sind dabei nicht gezählt: Prozesse wurden bei dieser Messung nicht erfasst (-Skip Prozesse).', 'Fokus ohne Prozesse: ' + await txt(fp.page, '#focusInfo'));
  await fp.page.close();
  const fb = await openExpert(browser, patched(dir, 'report-skip-focus-prozesse.html', 'report-skip-focus-beide.html', (J) => {
    J.skipped.splice(1, 0, { id: 'Ereignisse', label: 'Ereignisse', text: 'Ereignisse während der Messung wurden nicht erfasst.', places: ['events', 'sessions.events', 'incidents.events'] });
    J.meta.focus.reportedMs = J.meta.start + 600000;
  }), scheme);
  const fbt = await txt(fb.page, '#focusInfo');
  ok(fbt.endsWith('Abstürze und Hänger sind dabei nicht gezählt: Ereignisse während der Messung wurden nicht erfasst (-Skip Ereignisse); Prozesse wurden bei dieser Messung nicht erfasst (-Skip Prozesse).'), 'Fokus ohne beide: ' + fbt);
  ok(fb.page.errors.length === 0, 'Skriptfehler Fokus beide: ' + fb.page.errors.join(' | '));
  await fb.page.close();
  const ft = await openExpert(browser, patched(dir, 'report-skip-focus-prozesse.html', 'report-skip-focus-zeit.html', (J) => { J.meta.focus.reportedMs = J.meta.start + 600000; }), scheme);
  ok((await txt(ft.page, '#focusInfo')).includes(' Abstürze und Hänger sind beim Benutzer nicht gezählt: Prozesse wurden bei dieser Messung nicht erfasst (-Skip Prozesse).'), 'Fokus ohne Prozesse mit Uhrzeit: nur beim Benutzer: ' + await txt(ft.page, '#focusInfo'));
  await ft.page.close();
  const ff = await openExpert(browser, path.join(dir, 'report-focus.html'), scheme);
  ok(!(await txt(ff.page, '#focusInfo')).includes('nicht gezählt'), 'voller Lauf: Fokus wie bisher');
  await ff.page.close();
  // Minor 1: without the events of the capture a scan is unknown, not absent
  const sec = (J) => { const i = J.incidents.find((x) => x.type === 'engpass' && x.cause && x.cause.kind === 'main'); i.cause = Object.assign({}, i.cause, { kind: 'security', security: { label: 'Microsoft Defender', sharePct: 74 }, scan: false, other: null }); J.secId = i.id; };
  for (const [base, want] of [['report-skip-ereignisse.html', 'Ob im Fenster ein Virenscan lief, ist nicht erfasst (Ereignisse nicht gemessen); Zeitplan des Scans und Scan-Ausschlüsse prüfen.'], ['report.html', 'Scan-Ausschlüsse prüfen.']]) {
    const q = await openExpert(browser, patched(dir, base, 'scan-' + base, sec), scheme), id = q.D.secId;
    const box = await (await openIncident(q.page, id)).locator('.iv-evidence .causebox').innerText();
    ok(box.includes('Microsoft Defender mit 74 %') && box.includes(want) && (base === 'report.html') === !box.includes('nicht erfasst'), base + ': Schutzsoftware ohne Scan: ' + box);
    await q.page.close();
  }
  // Minor 3: several categories of the overlap left out make one line
  const g = await openExpert(browser, patched(dir, 'report-skip-gegenstellen.html', 'report-skip-overlap3.html', (J) => {
    const i = J.incidents.find((x) => x.type === 'ereignis' && x.event.unchecked.length === 1 && x.event.unchecked[0].id === 'overlap');
    i.event.unchecked = ['Laufwerke', 'Citrix', 'Gegenstellen'].map((c) => ({ id: 'overlap', category: c, text: `Zusammentreffen mit einem Vorfall der Kategorie ${c} (${c} nicht gemessen)` }));
    J.overlapId = i.id;
  }), scheme);
  let pats = await (await openIncident(g.page, g.D.overlapId)).locator('.iv-evidence .patterns li.unchecked').allInnerTexts();
  ok(pats.length === 1 && pats[0].includes('nicht geprüft: Zusammentreffen mit Vorfällen der Kategorien Laufwerke, Citrix, Gegenstellen (nicht gemessen)'), 'drei Kategorien in einer Zeile: ' + pats.join(' / '));
  await g.page.close();
  const g1 = await openExpert(browser, path.join(dir, 'report-skip-gegenstellen.html'), scheme);
  const one = g1.D.incidents.find((x) => x.type === 'ereignis' && x.event.unchecked.length === 1);
  pats = await (await openIncident(g1.page, one.id)).locator('.iv-evidence .patterns li.unchecked').allInnerTexts();
  ok(pats.length === 1 && pats[0].includes('nicht geprüft: Zusammentreffen mit einem Vorfall der Kategorie Gegenstellen (Gegenstellen nicht gemessen)'), 'eine Kategorie wie bisher: ' + pats.join(' / '));
  await g1.page.close();
  // Minor 4: the limits of a category left out are no limits of the capture
  const IO = 'Bei Datenträgern und Freigaben ist sichtbar', SHORT = 'Prozesse, die zwischen zwei Schnappschüssen starten';
  for (const [file, io, short] of [['report.html', true, true], ['report-skip-laufwerke.html', false, true], ['report-skip-prozesse.html', false, false], ['report-skip-alle.html', false, false], ['report-skip-citrix.html', true, true]]) {
    const r = await openExpert(browser, path.join(dir, file), scheme);
    await showTab(r.page, 'quality');
    const l = await r.page.locator('#limits').innerText();
    ok(l.includes(IO) === io && l.includes(SHORT) === short && l.includes('Die Eingabeverzögerung enthält keine Prozesse, die als SYSTEM laufen.'), file + ': Grenzen der Aussage: ' + l);
    await r.page.close();
  }
  // Minor 10: neither the capture nor the lookback read: "–" and "nicht geprueft"
  const both = await openExpert(browser, patched(dir, 'report-skip-ereignisse.html', 'report-skip-ereignisse-rueckblick.html', (J) => {
    J.skipped.push({ id: 'Rueckblick', label: 'Rückblick', text: 'Ereignisse der Tage vor der Messung wurden nicht erfasst.', places: ['before'] });
    Object.assign(J.before, { status: 'off', days: 0, eventCount: 0, incidentEventCount: 0, perDay: [], incidents: [], near: [], nearCapture: [], capped: [] });
  }), scheme);
  await showTab(both.page, 'print');
  const cells = (await both.page.locator('#tPrintDrivers tbody td:nth-child(6)').allInnerTexts()).map((t) => t.trim());
  ok(cells.length === 3 && cells.every((t) => t === '–') && (await both.page.locator('#print').innerText()).includes('„An einem Vorfall beteiligt“: nicht geprüft.'), 'Ereignisse und Rueckblick weggelassen: ' + cells.join(' / '));
  ok(both.page.errors.length === 0, 'Skriptfehler beide weggelassen: ' + both.page.errors.join(' | '));
  await both.page.close();
  // Minor 6: a capture whose Skip contradicts its files gives the page of its Skip, without a script error
  const odd = await openExpert(browser, path.join(dir, 'report-skip-odd.html'), scheme);
  let oddText = '';
  for (const t of TABS) { await showTab(odd.page, t); oddText += t + ': ' + await odd.page.locator('#xt-' + t).innerText() + '\n'; }
  ok(odd.page.errors.length === 0 && odd.D.procs.length === 0 && (await odd.page.locator('header #skipInfo').innerText()).includes('Nicht gemessen (-Skip): Prozesse') && oddText.includes('print: Drucken') && /quality: \S/.test(oddText), 'Skip gegen die Dateien: Seite ohne Fehler: ' + odd.page.errors.join(' | '));
  await odd.page.close();
}

// ---------- expert view with one shared time range (Task 10) ----------
async function checkRange(browser, dir, scheme) {
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  await showExpert(page);
  ok(await page.locator('#rangeAll').isDisabled() && (await page.locator('#rangeInfo').innerText()).startsWith('Zeitraum'), 'Zeitraumleiste zeigt immer den Zeitraum');
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  const before = await page.locator('#tSessions tbody tr').count();
  await page.click(`#incList .inc[data-id="${cpu.id}"]`);
  const z = await page.evaluate(() => window.WP.zoom);
  ok(z && z.t0 < cpu.start && z.t1 > cpu.end, 'Klick auf einen Vorfall setzt den Zeitraum');
  ok(await page.locator(`#incList .inc[data-id="${cpu.id}"].selected`).count() === 1 && await page.locator('#chCpu .incband').count() === 1, 'Vorfall und Fenster hervorgehoben');
  // (P3-R74: the brief asserted "kritisch", which the tile shows for the whole capture too: the share of time of the range,
  // computed from the series, stands in the tile, and the share of the whole capture does not)
  const crit = D.thresholds.find((x) => x.id === 'cpu.host').crit, inZ = D.host.cpu.filter((v, k) => v != null && D.tickT[k] >= z.t0 && D.tickT[k] <= z.t1);
  const share = de(100 * inZ.filter((v) => v >= crit).length / inZ.length, 1) + ' % der Zeit', whole = de(D.sollIst.find((r) => r.id === 'cpu.host').pctCrit, 1) + ' % der Zeit', tile = oneLine(await page.locator('.tile[data-signal="cpu.host"]').innerText());
  ok(inZ.length > 30 && share !== whole && tile.includes('◆ kritisch ' + share) && !tile.includes(whole), 'Kachel bezogen auf den Zeitraum: ' + tile);
  await page.click('#xtabs button[data-tab=sessions]');
  // (P3-R74: the brief asserted "<= before", which holds on a page that ignores the range: the number of rows is the number
  // of sessions with load at a snapshot of the range, from the data; a range in which fewer sessions have load than the capture
  // holds is asserted with the patched report further down)
  const [zlo, zhi] = snapRange(D, z);
  ok(before === D.sessions.length && await page.locator('#tSessions tbody tr').count() === D.sessions.filter((x) => hasLoad(x, zlo, zhi)).length, 'Tabellen nur mit im Zeitraum aktiven Sitzungen');
  // (literal adapted, P3-R1: the simulated hour takes a snapshot every 6 s while an incident lasts, so 20 s hold four of them;
  // the shortest range, 10 s from the start of the incident, holds two)
  const few = D.snapT.filter((t) => t >= cpu.start && t <= cpu.start + 10000).length;
  await page.evaluate(([a]) => window.WP.setZoom(a, a + 10000), [cpu.start]);
  ok(few === 2 && await page.locator('#rangeSnaps').isVisible() && (await page.locator('#rangeSnaps').innerText()).includes('gestützt auf 2 Schnappschüsse'), 'Hinweis bei weniger als drei Schnappschuessen: ' + await page.locator('#rangeSnaps').innerText());
  await page.click('#xtabs button[data-tab=sollist]');
  const rowMax = await page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText();
  await page.click('#rangeAll');
  ok(await page.evaluate(() => window.WP.zoom === null) && (await page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText()) !== rowMax, 'Soll-Ist folgt dem Zeitraum');
  ok(await page.locator('#rangeSnaps').isHidden() && await page.locator('#rangeAll').isDisabled(), 'gesamte Messung: kein Hinweis auf Schnappschuesse, Knopf deaktiviert');
  // (added to the brief's check: the tab button scrolled the page down to the tables, the chart is brought back into the picture)
  await page.evaluate(() => document.getElementById('chCpu').scrollIntoView({ block: 'center' }));
  const box = await page.locator('#chCpu svg').boundingBox();
  await page.mouse.move(box.x + box.width * 0.3, box.y + 40); await page.mouse.down(); await page.mouse.move(box.x + box.width * 0.5, box.y + 40); await page.mouse.up();
  ok(await page.evaluate(() => window.WP.zoom !== null), 'Ziehen im Diagramm setzt den Zeitraum');
  await page.click(`#incList .inc[data-id="${cpu.id}"] .inc-guided`);
  ok(await page.evaluate(() => window.WP.view) === 'guided' && await page.locator('#incident').getAttribute('data-id') === String(cpu.id), 'Eintrag fuehrt in die gefuehrte Vorfallsansicht');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
  // (file name per P3-R11: report-many.html is the file of checkFix1)
  const many = await open(browser, patched(dir, 'report.html', 'report-many-cards.html', (J) => {    // viele Vorfaelle: zehn Karten, Rest als Liste
    const c = J.incidents.find((i) => i.lead === 'cpu'), base = Math.max(...J.incidents.concat(J.before.incidents).map((i) => i.id));
    for (let k = 1; k <= 14; k++) J.incidents.push(Object.assign({}, c, { id: base + k, rank: 100 + k }));
    J.order = J.order.concat([...Array(14).keys()].map((k) => base + k + 1)); J.cards = J.order.slice(0, 10);
    J.more = [{ label: '14-mal ' + c.guide.title, situation: 'cpu', ids: J.order.slice(10) }];
  }), scheme);
  ok(await many.page.locator('#cards .card.inc').count() === 10 && await many.page.locator('#more details.group').count() === 1, 'viele Vorfaelle');
  await many.page.click('#more details.group summary');
  ok(await many.page.locator('#more details.group .row').count() === many.D.more[0].ids.length, 'Gruppe laesst sich aufklappen');
  // the incident column of the expert view holds them all and scrolls in itself
  await showExpert(many.page);
  const col = await many.page.evaluate(() => { const l = document.getElementById('incList'), c = document.getElementById('incCol').getBoundingClientRect(); return [l.children.length, l.scrollHeight > l.clientHeight, c.bottom <= window.innerHeight, document.documentElement.scrollWidth <= document.documentElement.clientWidth]; });
  ok(col[0] === many.D.incidents.length && col[1] && col[2] && col[3], 'viele Vorfaelle: die Vorfallsspalte nennt alle und rollt in sich: ' + col.join(' '));
  await many.page.close();
  // (P3-R74) sessions without load in a range are left out: two sessions idle around the CPU incident, the table of the range
  // holds exactly the others
  const idle = await openExpert(browser, patched(dir, 'report.html', 'report-range-idle.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu');
    for (const s of J.sessions.filter((x) => x.user).slice(-2)) J.snapT.forEach((t, i) => { if (t >= c.start - 60000 && t <= c.end + 60000) { s.cpu[i] = 0; s.ws[i] = 0; } });
  }), scheme);
  const ic = idle.D.incidents.find((i) => i.lead === 'cpu'), allRows = await idle.page.locator('#tSessions tbody tr').count();
  await idle.page.click(`#incList .inc[data-id="${ic.id}"]`);
  const [ilo, ihi] = snapRange(idle.D, await idle.page.evaluate(() => window.WP.zoom)), withLoad = idle.D.sessions.filter((x) => hasLoad(x, ilo, ihi)).length;
  ok(allRows === idle.D.sessions.length && withLoad === allRows - 2 && await idle.page.locator('#tSessions tbody tr').count() === withLoad, 'Tabellen nur mit im Zeitraum aktiven Sitzungen: zwei Sitzungen ohne Last im Zeitraum fehlen');
  await idle.page.close();
  const edge = await open(browser, patched(dir, 'report.html', 'report-edge.html', (J) => {          // Review Focus 5
    const e = J.incidents.find((i) => i.type === 'ereignis'); e.start = e.end = J.meta.end;
  }), scheme);
  const e = edge.D.incidents.find((i) => i.type === 'ereignis');
  await edge.page.evaluate((id) => window.WP.openIncident(id), e.id); await edge.page.click('#ivExpert');
  const ez = await edge.page.evaluate(() => window.WP.zoom);
  ok(ez && ez.t1 - ez.t0 >= 10000 && ez.t1 <= edge.D.meta.end && ez.t0 < e.start, 'Zeitraum eines Ereignisses ohne Dauer am Ende');
  ok(await edge.page.locator(`#incList .inc[data-id="${e.id}"].selected`).count() === 1 && await edge.page.locator('#chCpu .incband').count() === 1 && edge.page.errors.length === 0, 'Ereignis ohne Dauer am Ende: gewaehlt und im Diagramm getoent, ohne Skriptfehler: ' + edge.page.errors.join(' | '));
  await edge.page.close();
}

// what the tables of a range hold, computed from the report data as the page does: an item has load at a snapshot of the range
const snapRange = (D, z) => [D.snapT.findIndex((t) => t >= z.t0) < 0 ? D.snapT.length : D.snapT.findIndex((t) => t >= z.t0), D.snapT.filter((t) => t <= z.t1).length];
const hasLoad = (it, lo, hi) => { const o = it.o || 0; for (let i = Math.max(lo, o); i < hi; i++) if ((it.cpu && it.cpu[i - o] > 0) || (it.ws && it.ws[i - o] > 0)) return true; return false; };
const de = (v, d) => v.toLocaleString('de-DE', { minimumFractionDigits: d, maximumFractionDigits: d });
// the means over time of an item at the snapshots lo to hi - 1, from its series: a snapshot weighs the seconds since the one
// before it (the first one a regular snapshot interval); cpuCov: the seconds covered by snapshots with a CPU value
const timeMeans = (D, it, lo, hi) => {
  const sec = (i) => (i > 0 ? D.snapT[i] - D.snapT[i - 1] : D.meta.snapSec * 1000) / 1000, o = it.o || 0; let cs = 0, cc = 0, ws = 0, wc = 0;
  for (let i = Math.max(lo, o); i < hi; i++) { const c = it.cpu ? it.cpu[i - o] : null, w = it.ws ? it.ws[i - o] : null; if (c != null) { cs += c * sec(i); cc += sec(i); } if (w != null) { ws += w * sec(i); wc += sec(i); } }
  return { cpuAvg: cc ? cs / cc : null, wsAvg: wc ? ws / wc : null, cpuCov: cc };
};
// pairs of target-line labels of the charts under a selector that touch each other, and labels that leave their chart: a
// label stands in the plot or (fix round 1 of Task 10: where no place on its line is free) wholly in the right margin
// beside the plot, inside the picture
const labelFaults = (page, sel) => page.locator(sel).evaluateAll((hosts) => {
  const bad = [];
  for (const host of hosts) for (const svg of host.querySelectorAll('svg')) {
    const boxes = [...svg.querySelectorAll('.band-warn text, .band-crit text')].map((t) => t.getBBox()), c = svg.querySelector('clipPath rect');
    const x0 = Number(c.getAttribute('x')), x1 = x0 + Number(c.getAttribute('width')), W = Number(svg.getAttribute('width'));
    boxes.forEach((b, k) => {
      if (!(b.x >= x0 - 1 && b.x + b.width <= x1 + 1) && !(b.x >= x1 && b.x + b.width <= W)) bad.push((host.id || host.className) + ': ausserhalb');
      for (const o of boxes.slice(k + 1)) if (b.x < o.x + o.width && b.x + b.width > o.x && b.y < o.y + o.height && b.y + b.height > o.y) bad.push((host.id || host.className) + ': ueberlappt');
    });
  }
  return bad.join(' | ');
});
async function checkExpert(browser, dir, scheme) {                  // Expertenansicht: Spalte, Kacheln, Diagramme, Tabellen folgen einem Zeitraum
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  await showExpert(page);
  const tileOf = (id) => page.locator(`.tile[data-signal="${id}"]`), rowOf = (id) => page.locator(`#sollist tbody tr[data-id="${id}"]`);
  const off = D.meta.offsetMin, cpu = D.incidents.find((i) => i.lead === 'cpu'), word = (i) => i.severity >= 2 ? '◆ kritisch' : '▲ auffällig';
  // the incident column: every incident, by time, chronic states last
  const order = D.incidents.slice().sort((a, b) => (b.focus - a.focus) || (a.chronic - b.chronic) || (a.start - b.start) || (a.id - b.id)).map((i) => i.id);
  ok((await cardIds(page, '#incList .inc')).join() === order.join() && (await page.locator('#incCol h2').innerText()) === 'Vorfälle' && /^\d+ Vorfälle: /.test(await page.locator('#findHead').innerText()), 'Vorfallsspalte: alle Vorfaelle nach der Zeit, Dauerzustaende zuletzt, mit dem Kopfsatz');
  for (const inc of D.incidents) {
    const e = page.locator(`#incList .inc[data-id="${inc.id}"]`), t = oneLine(await e.innerText());
    ok(t.startsWith(word(inc) + ' ' + hhmm(inc.start, off)) && (await e.locator('.inc-kind').innerText()) === inc.guide.tech && await e.locator('.inc-cause').getAttribute('title') === inc.causeText && await e.locator('.inc-guided').count() === 1 && await e.locator('button.inc-main[aria-pressed="false"]').count() === 1,
      'Eintrag ' + inc.id + ': Status, Uhrzeit, Art, Verursacher, Weg in die gefuehrte Ansicht: ' + t);
  }
  // tiles and charts stand above the tabs, always
  const nTiles = D.sollIst.length + (D.mainApp ? 1 : 0) + 1;
  ok(await page.locator('#tiles .tile:visible').count() === nTiles && await page.locator('#charts .card:visible').count() === 14 && await page.locator('#charts .card svg').count() === 14, 'Kacheln je Messwert und vierzehn gezeichnete Diagramme, ohne Reiter sichtbar');
  const first = await page.evaluate(() => [document.getElementById('tiles').getBoundingClientRect().top, document.querySelector('#charts .card').getBoundingClientRect().top, document.documentElement.scrollWidth - document.documentElement.clientWidth]);
  ok(first[0] < 200 && first[1] < 900 && first[2] <= 0, 'erster Bildschirm (1400 x 900): Kacheln oben, das erste Diagramm beginnt im Bild, kein seitliches Rollen: ' + first.join(' '));
  ok(await labelFaults(page, '#charts .card > div[id]') === '', 'Diagramme: die Beschriftungen der Soll-Linien beruehren einander nicht und bleiben im Diagramm: ' + await labelFaults(page, '#charts .card > div[id]'));
  const tiles0 = await page.locator('#tiles').innerHTML(), counts0 = (await page.locator('#xtabs .cnt').allInnerTexts()).join();
  ok(counts0 === [D.sessions.length, D.apps.length, D.procs.length, D.events.length, D.before.incidents.length].join(), 'Reiter nennen die Zahl ihrer Zeilen: ' + counts0);
  // the functions of the range reproduce the target comparison of the whole capture from the series of the report data
  const stats = await page.evaluate(() => D.sollIst.map((r) => Object.assign({ id: r.id }, rangeStats(r.id, FULL.t0, FULL.t1))));
  const near = (a, b, tol) => a != null && b != null && Math.abs(a - b) <= tol, wrong = [];
  for (const st of stats) {
    const r = D.sollIst.find((x) => x.id === st.id);
    if (!st.series) { if (st.id !== 'ica.latency') wrong.push(st.id + ': ohne Verlauf'); continue; }
    if (!(near(st.max, r.max, 0.06) && near(st.avg, r.avg, 0.06) && near(st.p95, r.p95, 0.06) && near(st.pctNormal, r.pctNormal, 0.06) && near(st.pctWarn, r.pctWarn, 0.06) && near(st.pctCrit, r.pctCrit, 0.06) && st.status === r.status && st.worst === r.worstInstance && st.exceeded === r.exceeded))
      wrong.push(st.id + ': ' + JSON.stringify(st) + ' statt ' + JSON.stringify([r.max, r.avg, r.p95, r.pctNormal, r.pctWarn, r.pctCrit, r.status, r.worstInstance]));
  }
  ok(stats.length === D.sollIst.length && stats.filter((x) => x.series).length === D.sollIst.length - 1 && stats.every((x) => x.snaps === D.snapT.length) && !wrong.length, 'rangeStats ueber die ganze Messung ergibt den Soll-Ist-Vergleich: ' + wrong.join(' | '));
  const rowsAll = await page.evaluate(() => ['sessions', 'apps', 'procs'].map((k) => rangeRows(k, FULL.t0, FULL.t1).map((r) => [k === 'procs' ? r.k : r.i, r.cpuSec, r.cpuMax, r.wsMax, r.cpuShare, r.inMax, r.cpuAvg, r.wsAvg, r.rttAvg])));
  const drift = [];
  rowsAll[0].forEach((r) => { const x = D.sessions.find((y) => y.i === r[0]); if (!(near(r[1], x.cpuSec, Math.max(2, x.cpuSec * 0.01)) && near(r[2], x.cpuMax, 0.01) && near(r[3], x.wsMax, 1) && near(r[4], x.cpuShare, 0.2) && r[5] === x.inMax)) drift.push('Sitzung ' + r[0] + ' ' + JSON.stringify(r)); });
  rowsAll[2].forEach((r) => { const x = D.procs.find((y) => y.k === r[0]); if (!(near(r[1], x.cpuSec, Math.max(2, x.cpuSec * 0.02)) && near(r[2], x.cpuMax, 0.01) && near(r[3], x.wsMax, 1))) drift.push('Prozess ' + r[0] + ' ' + JSON.stringify(r)); });
  // (fix round 1, item 1; fix round 2, P3-R77) the means are means over time, and a range that covers the whole capture gives
  // the means the report data state, within the rounding of the series (CPU 0,01 %, working set 1 MB, round trip 0,1 ms):
  // for sessions, applications and processes. CPU: the delivered CPU seconds over the capacity of the seconds the item is
  // covered by snapshots. Working set: the mean of the series weighted by the seconds each snapshot stands for.
  const nS = D.snapT.length, means = [];
  [[rowsAll[0], D.sessions, (x) => x.i, 'Sitzung '], [rowsAll[1], D.apps, (x) => x.i, 'Anwendung '], [rowsAll[2], D.procs, (x) => x.k, 'Prozess ']].forEach(([rows, list, id, what]) => rows.forEach((r) => { const x = list.find((y) => id(y) === r[0]);
    if (!(near(r[6], x.cpuAvg, 0.011) && near(r[7], x.wsAvg, 1.01) && (what !== 'Sitzung ' || (x.rttAvg == null ? r[8] == null : near(r[8], x.rttAvg, 0.11))))) means.push(what + (x.user || x.name) + ' geliefert: CPU ' + r[6] + ' / ' + x.cpuAvg + ', RAM ' + r[7] + ' / ' + x.wsAvg + ', RTT ' + r[8] + ' / ' + x.rttAvg); }));
  rowsAll[2].forEach((r) => { const x = D.procs.find((y) => y.k === r[0]), m = timeMeans(D, x, 0, nS); if (!(near(r[6], x.cpuAvg, 0.02) && near(r[6], 100 * x.cpuSec / (D.meta.cores * m.cpuCov), Math.max(0.02, r[6] * 0.03)) && near(r[7], m.wsAvg, 1))) means.push('Prozess ' + x.name + ' ' + x.pid + ': ' + r[6] + ' / ' + x.cpuAvg + ', ' + r[7] + ' / ' + m.wsAvg); });
  [[rowsAll[0], D.sessions, 'Sitzung '], [rowsAll[1], D.apps, 'Anwendung ']].forEach(([rows, list, what]) => rows.forEach((r) => { const x = list.find((y) => y.i === r[0]), m = timeMeans(D, x, 0, nS);
    if (!(near(r[6], 100 * x.cpuSec / (D.meta.cores * m.cpuCov), Math.max(0.02, r[6] * 0.01)) && near(r[6], m.cpuAvg, 0.005) && near(r[7], m.wsAvg, 1))) means.push(what + (x.user || x.name) + ': ' + r[6] + ' / ' + m.cpuAvg + ', ' + r[7] + ' / ' + m.wsAvg); }));
  ok(rowsAll[2].length > 200 && rowsAll[2].some((r) => r[6] > 1) && rowsAll[0].some((r) => r[8] != null) && !means.length, 'rangeRows ueber die ganze Messung: CPU Ø, RAM Ø und ICA RTT Ø sind Mittel ueber die Zeit und die gelieferten Werte (Sitzungen, Anwendungen, Prozesse): ' + means.slice(0, 4).join(' | '));
  const bare = D.apps.filter((a) => !a.cpu && !a.ws).length;
  ok(rowsAll[0].length === D.sessions.length && rowsAll[1].length === D.apps.length - bare && bare > 0 && rowsAll[2].length === D.procs.length && !drift.length, 'rangeRows ueber die ganze Messung: alle Sitzungen und Prozesse mit ihren Werten, Anwendungen ohne Verlauf fehlen: ' + drift.slice(0, 3).join(' | '));

  // an incident chosen in the column: range, mark, tint in every chart, tiles and tables of the range
  await page.click(`#incList .inc[data-id="${cpu.id}"]`);
  const z = await page.evaluate(() => window.WP.zoom), [lo, hi] = snapRange(D, z);
  const info = await page.locator('#rangeInfo').innerText();
  ok(info.startsWith('Zeitraum ' + ddmmyyyy(z.t0, off) + ' ' + hhmm(z.t0, off)) && info.includes(`· Vorfall ${cpu.id}: ${cpu.guide.tech}`) && !info.includes('gesamte Messung') && await page.locator('#rangeAll').isEnabled(), 'Zeitraumleiste nennt Zeitraum und gewaehlten Vorfall: ' + info);
  ok(await page.locator(`#incList .inc[data-id="${cpu.id}"] .inc-main`).getAttribute('aria-pressed') === 'true' && await page.locator('#incList .inc.selected').count() === 1 && await page.locator('#expert.ranged').count() === 1, 'der gewaehlte Eintrag ist als gedrueckt gekennzeichnet');
  ok(await page.locator('#charts .card svg').count() === 14 && await page.locator('#charts .card svg .incband').count() === 14, 'das Fenster des Vorfalls ist in allen Diagrammen getoent');
  ok(await labelFaults(page, '#charts .card > div[id]') === '', 'Diagramme im Zeitraum: Beschriftungen ohne Beruehrung: ' + await labelFaults(page, '#charts .card > div[id]'));
  const axis = await page.locator('#chMem svg text.xaxis').allTextContents();
  ok(axis[0].startsWith(hhmm(z.t0, off)) && axis[axis.length - 1].startsWith(hhmm(z.t1, off)), 'gemeinsame Zeitachse: ' + axis.join(' '));
  const cpuRow = D.sollIst.find((r) => r.id === 'cpu.host'), mem = D.sollIst.find((r) => r.id === 'mem.used');
  let t = oneLine(await tileOf('cpu.host').innerText());
  ok(await tileOf('cpu.host').getAttribute('data-status') === '2' && t.includes(de(cpuRow.max, 1) + ' % Max') && t.includes('◆ kritisch') && / \d+,\d % der Zeit/.test(t) && !t.includes(de(cpuRow.pctCrit, 1) + ' % der Zeit'), 'CPU-Kachel: Maximum, Status und Zeitanteil des Zeitraums: ' + t);
  t = oneLine(await tileOf('mem.used').innerText());
  ok(mem.status === 2 && await tileOf('mem.used').getAttribute('data-status') === '0' && t.includes('● normal') && !t.includes(de(mem.max, 0) + ' % Max'), 'Kachel folgt dem Zeitraum: der Arbeitsspeicher ist im Fenster des CPU-Vorfalls normal: ' + t);
  t = oneLine(await tileOf('ica.latency').innerText());
  ok(t.includes('kein Verlauf in den Berichtsdaten: für einen Zeitraum nicht auswertbar') && t.includes('● normal in der gesamten Messung') && !/\d Max/.test(t), 'Messwert ohne Verlauf in den Berichtsdaten: kein Wert fuer den Zeitraum, Status aus den Befunden der gesamten Messung: ' + t);
  await showTab(page, 'sollist');
  t = oneLine(await rowOf('mem.used').innerText());
  ok(t.includes('● normal') && !t.includes('◆ kritisch') && (await page.locator('#sollRange').innerText()).startsWith('Zeitraum ' + ddmmyyyy(z.t0, off) + ' ' + hhmm(z.t0, off)) && /● normal in der gesamten Messung ?kein Verlauf in den Berichtsdaten/.test(oneLine(await rowOf('ica.latency').innerText())), 'Soll-Ist im Zeitraum, mit Hinweis ueber der Tabelle: ' + t);
  ok(oneLine(await rowOf('input.session').innerText()).includes(D.sessions.find((x) => x.i === cpu.affected[0].s).user), 'Soll-Ist im Zeitraum: am staerksten ist eine Sitzung des Vorfalls');
  // tables: who had load in the range, with the values of the range
  await showTab(page, 'sessions');
  const main = D.sessions.find((x) => x.i === cpu.main.s), sRows = await page.locator('#tSessions tbody tr').count();
  const firstRow = (await page.locator('#tSessions tbody tr').first().innerText()).split('\t'), heads = await page.locator('#tSessions thead th').allInnerTexts(), cell = (h) => firstRow[heads.findIndex((x) => x.startsWith(h))];
  ok(sRows === D.sessions.filter((x) => hasLoad(x, lo, hi)).length && firstRow[0].startsWith(main.user) && cell('Aktiv %') === '–' && cell('Commit Max') === '–' && cell('Prozesse Ø') === '–' && parseFloat(cell('CPU-Anteil %').replace(',', '.')) > main.cpuShare * 2,
    'Sitzungen im Zeitraum: die Sitzung des Verursachers fuehrt, Spalten ohne Verlauf zeigen "–": ' + firstRow.join(' | '));
  const sn = await page.locator('#sessRange').innerText();
  ok(sn.includes(`${sRows} von ${D.sessions.length} Sitzungen mit Last, Werte aus ${hi - lo} Schnappschüssen`) && sn.includes('Aktiv %, Commit Max, Prozesse Ø') && (await page.locator('#xtab-sessions .cnt').innerText()) === String(sRows), 'Hinweis ueber der Sitzungstabelle nennt Zeitraum, Zahl und Schnappschuesse: ' + sn);
  await showTab(page, 'apps');
  const aRows = D.apps.filter((a) => (a.cpu || a.ws) && hasLoad(a, lo, hi)).length, an = await page.locator('#appsRange').innerText();
  ok(await page.locator('#tApps tbody tr').count() === aRows && an.includes(`${aRows} von ${D.apps.length} Anwendungen mit Last`) && an.includes(`${bare} Anwendungen mit geringer Last haben keinen gespeicherten Verlauf und fehlen im gewählten Zeitraum.`) && (await page.locator('#tApps tbody tr').first().innerText()).startsWith(cpu.main.app),
    'Anwendungen im Zeitraum: ohne Verlauf fehlen sie, der Hinweis nennt ihre Zahl: ' + an);
  await showTab(page, 'procs');
  const pIn = D.procs.filter((x) => hasLoad(x, lo, hi)), gone = D.procs.find((x) => !hasLoad(x, lo, hi));
  ok(pIn.length < D.procs.length && await page.locator('#tProcs tbody tr').count() === pIn.length && await page.locator(`#tProcs tbody tr[data-id="${gone.k}"]`).count() === 0 && (await page.locator('#procsRange').innerText()).includes(`${pIn.length} von ${D.procs.length} Prozessen mit Last`),
    'Prozesse im Zeitraum: wer keinen Schnappschuss mit Last hat, fehlt (' + gone.name + ')');
  // the detail of a session: charts of the range, its processes of the range, the rest marked as the whole capture
  await showTab(page, 'sessions');
  // (a session one of whose processes has no load in the range)
  await page.click(`#tSessions tbody tr[data-id="${gone.s}"]`);
  const dAxis = await page.locator('#dSessions .chart-cpu svg text.xaxis').allTextContents(), ownIn = pIn.filter((x) => x.s === gone.s).length, ownAll = D.procs.filter((x) => x.s === gone.s).length;
  const tags = await page.locator('#dSessions .whole-tag:visible').allInnerTexts();
  ok(dAxis[0].startsWith(hhmm(z.t0, off)) && await page.locator('#dSessions .chart-cpu svg .incband').count() === 1 && tags.join('|') === 'Gesamte Messung:|· gesamte Messung|· gesamte Messung|· im gewählten Zeitraum', 'Sitzung im Zeitraum: Diagramme im Zeitraum, was fuer die ganze Messung gilt, sagt es: ' + tags.join('|'));
  ok(ownIn > 0 && ownIn < ownAll && await page.locator('#dSessions table[id^="sp"] tbody tr').count() === ownIn, 'Sitzung im Zeitraum: ihre Prozesse im Zeitraum');
  // a link to a row the range leaves out shows the whole capture
  await page.evaluate((k) => toTable('procs', k), gone.k);
  ok(await page.evaluate(() => window.WP.zoom === null) && await page.locator('#xt-procs').isVisible() && await page.locator(`#tProcs tbody tr.selected[data-id="${gone.k}"]`).count() === 1, 'Verweis auf eine Zeile ausserhalb des Zeitraums: die gesamte Messung zeigt sie');
  // "Gesamte Messung": everything as at the start
  ok(await page.locator('#tiles').innerHTML() === tiles0 && (await page.locator('#xtabs .cnt').allInnerTexts()).join() === counts0 && await page.locator('#incList .inc.selected').count() === 0 && await page.locator('#charts .incband').count() === 0 && await page.locator('.rangenote:visible').count() === 0 && await page.locator('#expert.ranged').count() === 0,
    'gesamte Messung: Kacheln, Zahlen der Reiter und Diagramme wie zu Beginn, kein Vorfall gewaehlt, keine Hinweise zum Zeitraum');
  await showTab(page, 'sessions');
  ok(await page.locator('#dSessions .whole-tag:visible').count() === 0 && await page.locator('#dSessions table[id^="sp"] tbody tr').count() === ownAll, 'gesamte Messung: die geoeffnete Sitzung zeigt wieder alles, ohne Kennzeichnung');
  // a range chosen otherwise: it keeps the chosen incident while it reaches into it, and lets go of it beyond
  await page.click(`#incList .inc[data-id="${cpu.id}"]`);
  await page.evaluate(([a, b]) => window.WP.setZoom(a, b), [cpu.start + 20000, cpu.start + 50000]);
  ok(await page.locator(`#incList .inc[data-id="${cpu.id}"].selected`).count() === 1 && await page.locator('#chCpu .incband').count() === 0, 'ein Zeitraum im Vorfall: der Vorfall bleibt gewaehlt, getoent wird nichts (er fuellt das Diagramm)');
  await page.evaluate(([a]) => window.WP.setZoom(a + 600000, a + 660000), [cpu.end]);
  ok(await page.locator('#incList .inc.selected').count() === 0 && !(await page.locator('#rangeInfo').innerText()).includes('Vorfall'), 'ein Zeitraum neben dem Vorfall: kein Vorfall mehr gewaehlt');
  // a chronic state over the whole capture: chosen, the range is the whole capture, nothing to tint
  const chronic = D.incidents.find((i) => i.chronic);
  await page.click(`#incList .inc[data-id="${chronic.id}"]`);
  const ci = await page.locator('#rangeInfo').innerText();
  ok(await page.evaluate(() => window.WP.zoom === null) && await page.locator(`#incList .inc[data-id="${chronic.id}"].selected`).count() === 1 && ci.includes('gesamte Messung') && ci.includes('Vorfall ' + chronic.id) && await page.locator('#charts .incband').count() === 0, 'Dauerzustand ueber die ganze Messung: gewaehlt, Zeitraum bleibt die gesamte Messung: ' + ci);
  // the entry is a button that stays pressed: pressed again, it lets go of the incident
  await page.click(`#incList .inc[data-id="${chronic.id}"]`);
  ok(await page.locator('#incList .inc.selected').count() === 0 && !(await page.locator('#rangeInfo').innerText()).includes('Vorfall') && await page.locator(`#incList .inc[data-id="${chronic.id}"] .inc-main`).getAttribute('aria-pressed') === 'false', 'der gewaehlte Dauerzustand, noch einmal gedrueckt, ist nicht mehr gewaehlt');
  await page.click(`#incList .inc[data-id="${cpu.id}"]`); await page.click(`#incList .inc[data-id="${cpu.id}"]`);
  ok(await page.evaluate(() => window.WP.zoom === null) && await page.locator('#incList .inc.selected').count() === 0 && await page.locator('#rangeAll').isDisabled(), 'der gewaehlte Vorfall, noch einmal gedrueckt: gesamte Messung, kein Vorfall gewaehlt');
  await page.click(`#incList .inc[data-id="${cpu.id}"]`);
  await page.evaluate(([a, b]) => window.WP.setZoom(a, b), [cpu.start + 20000, cpu.start + 50000]);
  await page.click(`#incList .inc[data-id="${cpu.id}"]`);
  const zz = await page.evaluate(() => window.WP.zoom);
  ok(zz && zz.t0 === z.t0 && zz.t1 === z.t1 && await page.locator(`#incList .inc[data-id="${cpu.id}"].selected`).count() === 1, 'nach einem anderen Zeitraum stellt der Eintrag wieder das Fenster seines Vorfalls ein');
  // a range without a snapshot: sessions by presence, values from snapshots "–", a signal of the snapshot grid not measured there
  const k0 = D.snapKind.indexOf('RRRR') + 1, gap = [D.snapT[k0] + 2000, D.snapT[k0] + 12000];
  await page.evaluate(([a, b]) => window.WP.setZoom(a, b), gap);
  ok(D.snapT.every((x) => x < gap[0] || x > gap[1]) && (await page.locator('#rangeSnaps').innerText()).includes('Tabellenwerte ohne Schnappschuss im Zeitraum'), 'Zeitraum ohne Schnappschuss: die Leiste sagt es: ' + await page.locator('#rangeSnaps').innerText());
  const sr = (await page.locator('#tSessions tbody tr').first().innerText()).split('\t');
  ok(await page.locator('#tSessions tbody tr').count() === D.sessions.length && sr[heads.findIndex((x) => x.startsWith('CPU-Zeit'))] === '–' && sr[heads.findIndex((x) => x.startsWith('RAM Ø'))] === '–', 'ohne Schnappschuss: Sitzungen nach Anwesenheit, Werte aus Schnappschuessen "–": ' + sr.join(' | '));
  // (fix round 1, item 5: nothing of the applications and processes was sampled in such a range; the former texts counted
  // "0 von 27 Anwendungen mit Last" and "26 von 26 Sitzungen mit Last")
  const NO_SNAP = 'Im gewählten Zeitraum liegt kein Schnappschuss: Anwendungen und Prozesse sind für ihn nicht auswertbar.', gapNote = await page.locator('#sessRange').innerText();
  ok(gapNote.includes(`${D.sessions.length} von ${D.sessions.length} Sitzungen anwesend. Im Zeitraum liegt kein Schnappschuss`) && !gapNote.includes('mit Last') && (await page.locator('#xtab-sessions .cnt').innerText()) === String(D.sessions.length), 'ohne Schnappschuss: der Hinweis nennt die anwesenden Sitzungen, niemand "mit Last": ' + gapNote);
  await showTab(page, 'apps');
  const appsNote = await page.locator('#appsRange').innerText();
  ok((await page.locator('#tApps tbody').innerText()).trim() === NO_SNAP && (await page.locator('#xtab-apps .cnt').innerText()) === '' && (await page.locator('#xtab-procs .cnt').innerText()) === '', 'ohne Schnappschuss: die Tabelle der Anwendungen sagt es, die Reiter zaehlen nicht');
  const emptyCell = await page.locator('#tApps td.empty').evaluate((td) => { const cs = getComputedStyle(td), r = td.getBoundingClientRect(), w = td.closest('.tablewrap').getBoundingClientRect();
    return { pad: [cs.paddingTop, cs.paddingLeft].map(parseFloat), pos: cs.position, wrap: cs.whiteSpace, height: Math.round(r.height), inside: r.left >= w.left - 1 && r.right <= w.right + 1 }; });
  ok(Math.min(...emptyCell.pad) >= 24 && emptyCell.pos === 'static' && emptyCell.wrap === 'normal' && emptyCell.height >= 70 && emptyCell.inside, 'ohne Schnappschuss: der Satz der leeren Tabelle hat seinen Raum (kein enges, festes Feld der Namensspalte): ' + JSON.stringify(emptyCell));
  ok(appsNote.includes('im Zeitraum liegt kein Schnappschuss, Anwendungen sind für ihn nicht auswertbar.') && !/\d+ von \d+/.test(appsNote) && !appsNote.includes('mit Last'), 'ohne Schnappschuss: Hinweis ueber den Anwendungen ohne "0 von n mit Last": ' + appsNote);
  await showTab(page, 'procs');
  const procsNote = await page.locator('#procsRange').innerText();
  ok((await page.locator('#tProcs tbody').innerText()).trim() === NO_SNAP && procsNote.includes('im Zeitraum liegt kein Schnappschuss, Prozesse sind für ihn nicht auswertbar.') && !/\d+ von \d+/.test(procsNote), 'ohne Schnappschuss: Tabelle und Hinweis der Prozesse ebenso: ' + procsNote);
  t = oneLine(await tileOf('probe.connect').innerText());
  ok(await tileOf('probe.connect').getAttribute('data-status') === 'na' && t.includes('○ nicht gemessen') && t.includes('keine Messwerte im gewählten Zeitraum') && await tileOf('cpu.host').getAttribute('data-status') === '0' && /\d % Max/.test(await tileOf('cpu.host').innerText()),
    'ohne Messpunkt im Zeitraum sagt eine Kachel "nicht gemessen", nie "normal": ' + t);
  await page.click('#rangeAll');
  // stacked charts: by session, by application, or the host as a whole
  const areas = () => page.locator('#chCpuStack svg g[clip-path] path').count();
  ok((await page.locator('#segCpu button').allInnerTexts()).join('|') === 'Server|nach Sitzung|nach Anwendung' && await areas() === 8, 'gestapeltes Diagramm aufteilbar nach Server, Sitzung, Anwendung; nach Sitzung: sieben und Sonstige');
  await page.click('#segCpu button[data-by=host]');
  ok(await areas() === 1 && (await page.locator('#chCpuStack .legend').innerText()).trim() === 'alle Prozesse' && await page.locator('#segCpu button[data-by=host]').getAttribute('aria-pressed') === 'true', 'Server: eine Flaeche fuer alle Prozesse');
  await page.click('#segMem button[data-by=apps]');
  ok(await page.locator('#chMemStack svg g[clip-path] path').count() > 1 && await areas() === 1, 'jedes der beiden Diagramme hat seine eigene Aufteilung');
  // tabs with the keyboard
  await page.focus('#xtab-sollist'); await page.keyboard.press('ArrowRight');
  const kb1 = await page.evaluate(() => [document.activeElement.id, !document.getElementById('xt-sessions').hidden, document.getElementById('xt-sollist').hidden].join());
  await page.keyboard.press('End');
  ok(kb1 === 'xtab-sessions,true,true' && await page.locator('#xt-before').isVisible() && await page.locator('#xtab-before').getAttribute('aria-selected') === 'true' && await page.locator('#xtabs button[tabindex="0"]').count() === 1, 'Reiter mit den Pfeiltasten und Ende: ' + kb1);
  ok(await page.locator('#printNone').innerText() === '' && await page.locator('#beforeNone').innerText() === '' && await page.locator('#eventNone').innerText() === '', 'Reiter mit Inhalt ohne Leer-Hinweis');
  ok(page.errors.length === 0, 'Skriptfehler Expertenansicht: ' + page.errors.join(' | '));
  await page.close();

  // other widths: three charts beside each other on a wide screen, two at 1200 px (as at 1400 px); one column at 390 px.
  // (fix round 1, items 20 and 21: on a wide screen the two stacked charts share a row of their own and three charts stand in
  // each row after it; the width with two charts beside the column is 1200 px, because below 1180 px the column is folded
  // over the tiles - the layout at 1000 px is asserted in checkExpertFix)
  for (const [width, height, cols] of [[1920, 1080, 3], [1200, 800, 2]]) {
    const w = await browser.newPage({ viewport: { width, height }, colorScheme: scheme });
    w.errors = []; w.on('pageerror', (e) => w.errors.push(e.message));
    await w.goto('file://' + path.join(dir, 'report.html'));
    await showExpert(w);
    await w.click(`#incList .inc[data-id="${cpu.id}"]`);
    const lay = await w.evaluate(() => { const tops = [...document.querySelectorAll('#charts .card')].map((c) => Math.round(c.getBoundingClientRect().top)), col = document.getElementById('incCol').getBoundingClientRect(), tl = document.getElementById('tiles').getBoundingClientRect();
      return [tops.filter((y) => y === tops[0]).length, tops.filter((y) => y === tops[2]).length, Math.round(col.width), col.right <= tl.left, document.documentElement.scrollWidth <= document.documentElement.clientWidth, col.bottom <= window.innerHeight]; });
    ok(lay[0] === 2 && lay[1] === cols && lay[2] === 280 && lay[3] && lay[4] && lay[5] && w.errors.length === 0, width + ' px: Vorfallsspalte links neben Kacheln und Diagrammen (die zwei gestapelten in einer Zeile, danach ' + cols + ' je Zeile), ohne seitliches Rollen: ' + lay.join(' '));
    ok(await labelFaults(w, '#charts .card > div[id]') === '', width + ' px: Beschriftungen der Soll-Linien ohne Beruehrung: ' + await labelFaults(w, '#charts .card > div[id]'));
    await w.close();
  }
  const n = await browser.newPage({ viewport: { width: 390, height: 844 }, colorScheme: scheme });
  n.errors = []; n.on('pageerror', (e) => n.errors.push(e.message));
  await n.goto('file://' + path.join(dir, 'report.html'));
  await showExpert(n);
  await n.evaluate((i) => selectIncident(i), cpu.id);
  for (const tab of TABS) await showTab(n, tab);
  const nw = await n.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok(nw[0] <= nw[1] && await labelFaults(n, '#charts .card > div[id]') === '' && n.errors.length === 0, '390 px: Expertenansicht mit Zeitraum und allen Reitern ohne seitliches Rollen, Beschriftungen ohne Beruehrung: ' + nw.join(' > ') + ' ' + await labelFaults(n, '#charts .card > div[id]'));
  await n.close();

  // states changed in the data: a session without load in the range, a response time that was too thin to be rated, a
  // measured value whose series is missing
  const v = await openExpert(browser, patched(dir, 'report.html', 'report-range-variant.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu'), s = J.sessions.find((x) => x.user === 'user020'), vol = J.volumes.find((x) => x.name === 'C:');
    J.snapT.forEach((t, i) => { if (t >= c.start - 60000 && t <= c.end + 60000) { s.cpu[i] = 0; s.ws[i] = 0; } });
    vol.ms[vol.t.findIndex((ti) => J.tickT[ti] >= c.start)] = 5000;
    J.probes = [];
  }), scheme);
  const vc = v.D.incidents.find((i) => i.lead === 'cpu'), idle = v.D.sessions.find((x) => x.user === 'user020');
  ok(await v.page.locator(`#tSessions tbody tr[data-id="${idle.i}"]`).count() === 1, 'Sitzung ohne Last im Fenster: in der gesamten Messung steht sie in der Tabelle');
  await v.page.click(`#incList .inc[data-id="${vc.id}"]`);
  ok(await v.page.locator(`#tSessions tbody tr[data-id="${idle.i}"]`).count() === 0 && await v.page.locator('#tSessions tbody tr').count() === v.D.sessions.length - 1, 'wer im Zeitraum keinen Schnappschuss mit Last hat, fehlt in der Tabelle der Sitzungen');
  const disk = v.D.sollIst.find((r) => r.id === 'disk.latency'), dt = oneLine(await v.page.locator('.tile[data-signal="disk.latency"]').innerText());
  ok(!dt.includes('5.000') && parseFloat(dt.match(/([\d.,]+) ms Max/)[1].replace('.', '').replace(',', '.')) <= disk.max, 'ein Wert ueber dem Maximum der ganzen Messung (nicht bewertbar) zaehlt im Zeitraum nicht: ' + dt);
  const pt = oneLine(await v.page.locator('.tile[data-signal="probe.connect"]').innerText());
  ok(pt.includes('kein Verlauf in den Berichtsdaten') && v.page.errors.length === 0, 'gemessener Wert ohne Verlauf in den Daten: der Zeitraum sagt es, ohne Skriptfehler: ' + pt);
  await v.page.close();

  // nothing measured reads as measured: tiles, tabs and tables of a capture with every category left out, also with a range
  const a = await openExpert(browser, path.join(dir, 'report-skip-alle.html'), scheme), unm = a.D.sollIst.filter((r) => !r.measured);
  const naTiles = async () => (await a.page.locator('#tiles .tile[data-status="na"]').allInnerTexts()).map(oneLine);
  let na = await naTiles();
  ok(unm.length === 5 && na.length === unm.length && na.every((x, k) => x === `${unm[k].label} – ○ nicht gemessen ${unm[k].detail}`), 'ohne alle: Kacheln der nicht gemessenen Werte sagen "nicht gemessen" mit dem Grund: ' + na.join(' / '));
  ok((await a.page.locator('#xtabs .cnt').allInnerTexts()).join('|') === `${a.D.sessions.length}||||` && await a.page.locator('#tiles .tile[data-signal="mainapp"]').count() === 0, 'ohne alle: Reiter ohne Zahl, wo nichts gemessen wurde; keine Kachel der Hauptanwendung');
  for (const [tab, place] of [['apps', 'apps'], ['procs', 'procs'], ['events', 'events'], ['before', 'before'], ['print', 'print.drivers']]) {
    await showTab(a.page, tab);
    ok(await a.page.locator(`#xt-${tab} .notmeasured[data-place="${place}"]`).first().isVisible() && await a.page.locator(`#xt-${tab} table:visible`).count() === 0 && !/Keine Einträge|keine Ereignisse/i.test(await a.page.locator('#xt-' + tab).innerText()), 'ohne alle: Reiter ' + tab + ' sagt "nicht gemessen" statt einer leeren Tabelle');
  }
  const ac = a.D.incidents.find((i) => i.lead === 'cpu');
  await a.page.click(`#incList .inc[data-id="${ac.id}"]`);
  na = await naTiles();
  ok(na.length === unm.length && na.every((x) => !x.includes('keine Messwerte im gewählten Zeitraum')) && await a.page.locator('#appsRange').isHidden() && await a.page.locator('#procsRange').isHidden() && (await a.page.locator('#xtabs .cnt').allInnerTexts()).join('|') === `${a.D.sessions.length}||||`,
    'ohne alle, mit Zeitraum: nicht Gemessenes bleibt "nicht gemessen", keine Hinweise zu Tabellen, die es nicht gibt');
  await showTab(a.page, 'sessions');
  const ar = (await a.page.locator('#tSessions tbody tr').first().innerText()).split('\t'), ah = await a.page.locator('#tSessions thead th').allInnerTexts();
  ok(await a.page.locator('#tSessions tbody tr').count() === a.D.sessions.length && ar[ah.findIndex((x) => x.startsWith('CPU-Anteil'))] === '–' && (await a.page.locator('#sessRange').innerText()).includes(`${a.D.sessions.length} von ${a.D.sessions.length} Sitzungen anwesend.`) && a.page.errors.length === 0,
    'ohne alle, mit Zeitraum: Sitzungen nach Anwesenheit, Prozesswerte "–", ohne Skriptfehler: ' + a.page.errors.join(' | '));
  await a.page.close();
  // no incident: the column says so, the statement stands above the tiles; a capture without events and lookback says so in its tabs
  const none = await openExpert(browser, path.join(dir, 'report-none.html'), scheme);
  const nfb = await none.page.locator('#noFinding').boundingBox(), ntb = await none.page.locator('#tiles').boundingBox();
  ok(await none.page.locator('#incList').isHidden() && (await none.page.locator('#incCol').innerText()).includes('Keine Vorfälle im Messzeitraum.') && nfb && nfb.y + nfb.height <= ntb.y, 'ohne Vorfall: die Spalte sagt es, die Aussage ohne Befund steht ueber den Kacheln');
  await showTab(none.page, 'events');
  ok((await none.page.locator('#xt-events').innerText()).trim() === 'Die Aufzeichnung enthält keine Ereignisse.' && (await none.page.locator('#xtab-events .cnt').innerText()) === '0' && none.page.errors.length === 0, 'ohne Ereignisse: der Reiter sagt es');
  await none.page.close();
}

// ---------- expert view: fix round 1 of Task 10 ----------
async function checkExpertFix(browser, dir, scheme) {               // Zeitmittel, Namensspalte, Marke des Vorfalls, Zaehler, Leiste, Kennzeichnungen, Kontraste, Breiten
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  await showExpert(page);
  const cpu = D.incidents.find((i) => i.lead === 'cpu'), crash = D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'crash' && i.end === i.start);
  const pick = (p, id) => p.click(`#incList .inc[data-id="${id}"] .inc-main`);
  const num = (s) => parseFloat(s.replace(/\./g, '').replace(',', '.'));
  // -- item 1: the means of the tables are means over time; a range one second shorter than the capture shows no jump.
  // (fix round 2, P3-R77) For the whole capture the tables show the values the report data state: they are means over time.
  const avgCells = () => page.evaluate(() => ['tSessions', 'tApps', 'tProcs'].map((id) => { const t = document.getElementById(id), c = [...t.querySelectorAll('thead th')].findIndex((x) => x.textContent.startsWith('CPU Ø %'));
    return [...t.querySelectorAll('tbody tr[data-id]')].map((r) => [Number(r.dataset.id), r.cells[c].textContent]); }));
  const whole = await avgCells(), nS = D.snapT.length, lists = [D.sessions, D.apps, D.procs], key = [(x) => x.i, (x) => x.i, (x) => x.k], off = [];
  whole.forEach((rows, k) => rows.forEach(([id, text]) => { const x = lists[k].find((y) => key[k](y) === id), m = x.cpu ? timeMeans(D, x, 0, nS).cpuAvg : x.cpuAvg; if (!(Math.abs(num(text) - m) <= 0.011 && num(text) === x.cpuAvg)) off.push(k + ':' + id + ' ' + text + ' statt ' + m + ' (geliefert ' + x.cpuAvg + ')'); }));
  const excel = D.procs.filter((x) => x.name === 'EXCEL.EXE').sort((a, b) => b.cpuSec - a.cpuSec)[0], excelSess = D.sessions.find((s) => s.i === excel.s);
  const cell = (rows, id) => num(rows.find((r) => r[0] === id)[1]);
  // (the session of the CPU incident: the plain mean of its snapshots lies more than one point above the mean over time)
  const plain = (a) => { const v = a.filter((x) => x != null); return v.reduce((x, y) => x + y, 0) / v.length; };
  ok(whole[0].length === D.sessions.length && whole[1].length === D.apps.length && whole[2].length === D.procs.length && !off.length && cell(whole[2], excel.k) === excel.cpuAvg && cell(whole[0], excelSess.i) === excelSess.cpuAvg && plain(excelSess.cpu) - cell(whole[0], excelSess.i) > 1,
    'gesamte Messung: "CPU Ø %" ist der gelieferte Wert und das Mittel ueber die Zeit (Sitzung: nicht das Mittel der Schnappschuesse): ' + off.slice(0, 3).join(' | '));
  // "RAM Ø" and, for sessions, "Prozesse Ø" and "ICA RTT Ø ms": the cells of the whole capture are the delivered values
  const wsOff = await page.evaluate(() => [['tSessions', D.sessions, ['wsAvg', 'procsAvg', 'rttAvg']], ['tApps', D.apps, ['wsAvg', 'instAvg', 'wsPerInst']], ['tProcs', D.procs, ['wsAvg']]].flatMap(([id, list, keys]) => { const t = document.getElementById(id);
    const cols = keys.map((k) => [k, [...t.querySelectorAll('thead th')].findIndex((x) => x.dataset.k === k)]).filter(([, c]) => c >= 0), by = new Map(list.map((x) => [String(id === 'tProcs' ? x.k : x.i), x]));
    return [...t.querySelectorAll('tbody tr[data-id]')].flatMap((r) => cols.filter(([k, c]) => r.cells[c].textContent !== (k === 'wsAvg' || k === 'wsPerInst' ? fmtMB(by.get(r.dataset.id)[k]) : fmt(by.get(r.dataset.id)[k], k === 'instAvg' ? 1 : 0))).map(([k, c]) => id + ' ' + r.dataset.id + ' ' + k + ': ' + r.cells[c].textContent)); }));
  ok(!wsOff.length, 'gesamte Messung: "RAM Ø", "Prozesse Ø", "gleichzeitig Ø", "RAM Ø je Instanz" und "ICA RTT Ø ms" sind die gelieferten Werte: ' + wsOff.slice(0, 3).join(' | '));
  await page.evaluate(() => window.WP.setZoom(FULL.t0, FULL.t1 - 1000));
  const shorter = await avgCells(), jumps = []; let compared = 0;
  whole.forEach((rows, k) => rows.forEach(([id, text]) => { const x = lists[k].find((y) => key[k](y) === id), now = shorter[k].find((r) => r[0] === id); if (!x.cpu || x.cpu.length < 30 || !now) return; compared++;
    if (Math.abs(num(now[1]) - num(text)) > Math.max(0.05, 0.03 * num(text))) jumps.push(k + ':' + id + ' ' + text + ' -> ' + now[1]); }));
  const wsJump = await page.evaluate(() => ['sessions', 'apps', 'procs'].flatMap((k) => { const w = new Map(D[k].map((r) => [k === 'procs' ? r.k : r.i, r])); return rangeRows(k, FULL.t0, FULL.t1 - 1000).filter((r) => (r.ws || []).length >= 30)
    .filter((r) => Math.abs(r.wsAvg - w.get(k === 'procs' ? r.k : r.i).wsAvg) > Math.max(1, 0.03 * r.wsAvg)).map((r) => k + ' ' + (r.name || r.user)); }));
  ok(await page.evaluate(() => window.WP.zoom !== null) && compared > 150 && !jumps.length && Math.abs(cell(shorter[2], excel.k) - excel.cpuAvg) <= 0.02 && !wsJump.length, 'ein Zeitraum, eine Sekunde kuerzer als die Messung: "CPU Ø %" und "RAM Ø" springen nicht: ' + jumps.slice(0, 3).concat(wsJump.slice(0, 3)).join(' | '));
  // -- item 15: the use of the sessions is computed once per range; the two functions take their bounds in either order
  const once = await page.evaluate(() => { let n = 0; const orig = window.snapUse; window.snapUse = function (it, lo, hi) { n++; return orig(it, lo, hi); };
    window.WP.setZoom(FULL.t0 + 600000, FULL.t0 + 1500000); window.snapUse = orig;
    const z = window.WP.zoom, lo = lowerBound(GRID.snap, z.t0), hi = upperBound(GRID.snap, z.t1), a = sessionUse(lo, hi), st = rangeStats('cpu.host', z.t1, z.t0), ts = rangeStats('cpu.host', z.t0, z.t1);
    return [n, D.sessions.length + D.apps.filter((x) => x.cpu || x.ws).length + D.procs.filter((x) => x.cpu || x.ws).length, a === sessionUse(lo, hi), st.snaps === ts.snaps && st.snaps > 30 && st.max === ts.max && st.n === ts.n,
      JSON.stringify(rangeRows('sessions', z.t1, z.t0).map((r) => [r.i, r.cpuSec])) === JSON.stringify(rangeRows('sessions', z.t0, z.t1).map((r) => [r.i, r.cpuSec])), rangeRows('procs', z.t1, z.t0).length]; });
  ok(once[0] === once[1] && once[2] && once[3] && once[4] && once[5] > 100, 'ein Zeitraum: die Nutzung der Sitzungen wird einmal berechnet; rangeStats und rangeRows nehmen die Grenzen in jeder Reihenfolge: ' + once.join(' '));
  await page.click('#rangeAll');
  // -- item 2: the first column of the wide tables stays in the picture; tables at 1400 px
  for (const [tab, table] of [['sessions', 'tSessions'], ['apps', 'tApps'], ['procs', 'tProcs']]) {
    await showTab(page, tab);
    const st = await page.evaluate((id) => { const t = document.getElementById(id), w = t.closest('.tablewrap'), row = t.querySelector('tbody tr:nth-child(3)');
      row.scrollIntoView({ block: 'center' }); w.scrollLeft = w.scrollWidth;
      const b = w.getBoundingClientRect(), c = row.cells[0].getBoundingClientRect(), h = t.querySelector('thead th').getBoundingClientRect(), last = row.cells[row.cells.length - 1].getBoundingClientRect(), at = document.elementFromPoint(c.left + 6, c.top + c.height / 2);
      return [w.scrollLeft > 50, c.left >= b.left - 1 && c.right <= b.right && h.left >= b.left - 1, row.cells[0].contains(at), last.right <= b.right + 1, w.scrollWidth - w.clientWidth, getComputedStyle(row.cells[0]).backgroundColor !== 'rgba(0, 0, 0, 0)']; }, table);
    ok(st[0] && st[1] && st[2] && st[3] && st[4] < 300 && st[5], `${table}, 1400 px, ans rechte Ende gerollt: die erste Spalte bleibt im Kasten und liegt ueber den anderen; es fehlen weniger als 300 px: ${st.join(' ')}`);
    await page.hover(`#${table} tbody tr:nth-child(3) td:nth-child(4)`);
    const hov = await page.evaluate((id) => { const r = document.querySelector(`#${id} tbody tr:nth-child(3)`); return [getComputedStyle(r.cells[0]).backgroundColor, getComputedStyle(r).backgroundColor, getComputedStyle(r.closest('.tablewrap')).backgroundColor]; }, table);
    await page.click(`#${table} tbody tr:nth-child(3) td:nth-child(4)`);
    const sel = await page.evaluate((id) => { const r = document.querySelector(`#${id} tbody tr.selected`); return r ? [getComputedStyle(r.cells[0]).backgroundColor, getComputedStyle(r).backgroundColor] : []; }, table);
    ok(hov[0] === hov[1] && hov[0] !== hov[2] && sel.length === 2 && sel[0] === sel[1] && sel[0] !== hov[2] && sel[0] !== hov[0], `${table}: die feste erste Spalte traegt den Grund ihrer Zeile, ueberfahren und gewaehlt: ${hov.join(' ')} / ${sel.join(' ')}`);
    await page.mouse.move(0, 0);
  }
  // -- item 19: contrast in the dark view: the bars of the cells on the surface and on a selected row
  const bars = await page.evaluate(() => { const r = document.querySelector('#tProcs tbody tr.selected'), bar = document.querySelector('#tProcs .cellbar'); return [getComputedStyle(bar).backgroundColor, getComputedStyle(bar.closest('.tablewrap')).backgroundColor, getComputedStyle(r).backgroundColor]; });
  ok(contrast(bars[0], bars[1]) >= 3 && contrast(bars[0], bars[2]) >= 3, 'Balken der Tabellenzellen: Kontrast mindestens 3:1 auf der Flaeche und auf einer gewaehlten Zeile: ' + contrast(bars[0], bars[1]).toFixed(2) + ' ' + contrast(bars[0], bars[2]).toFixed(2));
  // -- item 3: the time of the chosen incident. A crash has no duration: a mark of its own in every chart
  await page.evaluate(() => window.scrollTo(0, 0));
  await pick(page, crash.id);
  const marks = await page.locator('#charts .card svg').evaluateAll((svgs) => svgs.map((svg) => { const m = svg.querySelector('.incband'); if (!m || !m.classList.contains('incmark')) return null;
    const cs = getComputedStyle(m), c = svg.querySelector('clipPath rect'), grid = svg.querySelector('line[stroke="var(--grid)"]');
    // (fix round 2, item 2) the mark is a dashed line (the stem, .incmark) and a cap of its own above the plot (.inccap) with a halo
    // (Task 11, N1) the plot is its clip rectangle: a stacked total at 100 % or a line at the top of the axis is drawn up to its edge
    const cap = svg.querySelector('.inccap'), halo = svg.querySelector('.inchalo'), cc = cap ? getComputedStyle(cap) : null, box = m.getBBox(), cb = cap ? cap.getBBox() : null, plot = { y: Number(c.getAttribute('y')), h: Number(c.getAttribute('height')) };
    const ground = getComputedStyle(svg.closest('.card')).backgroundColor, g = svg.querySelector('g[clip-path]'), lineStrokes = [...g.querySelectorAll('path[fill="none"]')].map((e) => getComputedStyle(e).stroke);
    // what is drawn in the surface colour after the measured lines or areas and reaches into the plot at the time of the mark
    const cover = [...svg.querySelectorAll('path, rect, line, circle, polygon')].filter((e) => !g.contains(e) && !e.closest('defs') && (g.compareDocumentPosition(e) & Node.DOCUMENT_POSITION_FOLLOWING)).filter((e) => { const s = getComputedStyle(e);
      if (s.visibility === 'hidden' || s.display === 'none') return false;
      const sw = s.stroke === ground && parseFloat(s.strokeWidth) > 0 && parseFloat(s.strokeOpacity) > 0 ? parseFloat(s.strokeWidth) / 2 : null, fl = s.fill === ground && parseFloat(s.fillOpacity) > 0;
      if (sw == null && !fl) return false;
      const b = e.getBBox(), d = sw || 0; return b.x - d <= box.x + 1 && b.x + b.width + d >= box.x - 1 && b.y + b.height + d > plot.y + 0.25 && b.y - d < plot.y + plot.h - 0.25; }).map((e) => e.getAttribute('class') || e.tagName);
    return { stroke: cs.stroke, width: parseFloat(cs.strokeWidth), solid: cs.strokeDasharray === 'none', op: parseFloat(cs.strokeOpacity) * parseFloat(cs.opacity) * parseFloat(cs.fillOpacity), ground,
      grid: getComputedStyle(grid).stroke, tall: cb ? box.y + box.height - cb.y - Number(c.getAttribute('height')) : 0, wide: cb ? cb.width : 0, halo: !!halo, over: !!(g.compareDocumentPosition(m) & Node.DOCUMENT_POSITION_FOLLOWING),
      stack: !!svg.closest('#chCpuStack, #chMemStack'), lines: lineStrokes.length,
      free: cs.pointerEvents === 'none' && !!cc && cc.pointerEvents === 'none' && !!halo && getComputedStyle(halo).pointerEvents === 'none', n: svg.querySelectorAll('.incband').length,
      caps: svg.querySelectorAll('.inccap').length, capFill: cc ? cc.fill : '', capSolid: !!cc && cc.strokeDasharray === 'none' && parseFloat(cc.fillOpacity) * parseFloat(cc.opacity) === 1, capAbove: !!cb && cb.y + cb.height <= plot.y,
      haloOnCap: !!halo && halo.getAttribute('d') === cap.getAttribute('d') && svg.querySelectorAll('.inchalo').length === 1 && getComputedStyle(halo).stroke === ground,
      likeLine: lineStrokes.length === 1 && lineStrokes[0] === cs.stroke, sameHue: lineStrokes.includes(cs.stroke), cover }; }));
  const weak = marks.filter((m) => !(m && m.n === 1 && m.op === 1 && m.width >= 2 && !m.solid && contrast(m.stroke, m.ground) >= 3 && m.stroke !== m.grid && m.tall >= 4 && m.wide >= 8 && m.halo && m.over === m.stack && (m.stack || m.lines >= 1) && m.free
    && m.caps === 1 && m.capSolid && m.capAbove && contrast(m.capFill, m.ground) >= 3));
  // (follow-up: above the lines the mark and its halo cut a gap into every curve at the very moment of the incident)
  ok(crash.end === crash.start && marks.length === 14 && marks.filter((m) => m && m.stack).length === 2 && !weak.length, 'Vorfall ohne Dauer: in jedem Diagramm eine eigene Marke (gestrichelte Linie mit deckender Kappe ueber dem Diagramm, Kontrast mindestens 3:1 zum Grund, hinter den Messlinien und ueber den Flaechen eines gestapelten Diagramms, ohne den Zeiger zu fangen): ' +
    JSON.stringify(weak[0] || null) + ' ' + (marks[0] ? contrast(marks[0].stroke, marks[0].ground).toFixed(2) + ' ' + (marks[0].capFill ? contrast(marks[0].capFill, marks[0].ground).toFixed(2) : 'keine Kappe') : ''));
  // (fix round 2, item 2) at the time of the incident nothing in the surface colour lies over what was measured (the halo
  // belongs to the cap alone), and the mark cannot be taken for the line of a chart with one series: it is dashed and has
  // another colour than every measured line of its chart
  const covered = marks.map((m, k) => m && (m.cover.length || !m.haloOnCap) ? k + ': ' + m.cover.join('+') + (m.haloOnCap ? '' : ' Hof nicht nur an der Kappe') : '').filter(Boolean);
  const oneSeries = marks.filter((m) => m && !m.stack && m.lines === 1).length, alike = marks.map((m, k) => m && (m.solid || m.likeLine || m.sameHue) ? k : -1).filter((k) => k >= 0);
  ok(!covered.length && oneSeries >= 3 && !alike.length, 'Vorfall ohne Dauer: nichts in der Farbe der Flaeche liegt ueber den Messlinien oder Flaechen, die Marke gleicht keiner Messlinie (gestrichelt, andere Farbe; ' + oneSeries + ' Diagramme mit einer Reihe): ' + covered.concat(alike.map((k) => 'gleicht einer Linie: ' + k)).slice(0, 4).join(' | '));
  let info = await page.locator('#rangeInfo').innerText();
  ok(info.endsWith(`· Vorfall ${crash.id}: Anwendungsabsturz`) && !info.includes('Vorfall aus Ereignissen'), 'Zeitraumleiste nennt einen Vorfall aus Ereignissen bei seiner Art, ohne das Wort doppelt: ' + info);
  // a span with a duration: tinted; in the stacked charts above the areas, with its two edges; never in the way of the pointer
  await pick(page, cpu.id);
  const bands = await page.evaluate(() => ['chCpuStack', 'chMemStack', 'chCpu'].map((id) => { const svg = document.querySelector(`#${id} svg`), b = svg.querySelector('.incband'), g = svg.querySelector('g[clip-path]'), r = b.getBoundingClientRect();
    document.getElementById(id).scrollIntoView({ block: 'center' }); const q = b.getBoundingClientRect(), at = document.elementFromPoint(q.left + q.width / 2, q.top + q.height / 2);
    return [b.tagName, r.width > 100, !!(g.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING), svg.querySelectorAll('.incedge').length, svg.querySelectorAll('.incveil').length, getComputedStyle(b).pointerEvents, at && at.getAttribute('class')].join(); }));
  ok(bands[0] === 'rect,true,true,1,1,none,hit' && bands[1] === bands[0] && bands[2] === 'rect,true,false,0,0,none,hit', 'Vorfall mit Dauer: getoent; in den gestapelten Diagrammen liegt der Bereich ueber den Flaechen, mit seinen Raendern; der Zeiger erreicht das Diagramm: ' + bands.join(' | '));
  // -- item 19: the way into the guided view on the chosen entry
  const lnk = await page.evaluate(() => { const e = document.querySelector('#incList .inc.selected'); return [getComputedStyle(e.querySelector('.inc-guided')).color, getComputedStyle(e).backgroundColor]; });
  ok(contrast(lnk[0], lnk[1]) >= 4.5, '"Geführt öffnen" auf dem gewaehlten Eintrag: Kontrast mindestens 4,5:1: ' + contrast(lnk[0], lnk[1]).toFixed(2));
  // -- item 17: what does not follow the range says so while a range is set
  const heads = async () => { const out = []; for (const [tab, sel] of [['print', '#print h3'], ['quality', '#quality h3'], ['before', '#before h3']]) { await showTab(page, tab); out.push(oneLine(await page.locator(sel).first().innerText())); } return out.join('|'); };
  ok(await heads() === 'Drucken · gesamte Messung|Messqualität · gesamte Messung|Vor der Messung · unabhängig vom gewählten Zeitraum', 'mit Zeitraum: Drucken, Messqualitaet und Vor der Messung sagen, dass sie ihm nicht folgen: ' + await heads());
  await page.click('#rangeAll');
  ok(await heads() === 'Drucken|Messqualität|Vor der Messung', 'ohne Zeitraum: keine Kennzeichnung: ' + await heads());
  // -- item 16: the range bar keeps its height, whatever is chosen; the hint is left out before the range is cut
  await page.evaluate(() => window.scrollTo(0, 0));
  const barOf = (p) => p.evaluate(() => { const b = document.getElementById('rangeBar'), i = document.getElementById('rangeInfo'), n = b.querySelector('.note'); return [b.offsetHeight, Math.round(document.getElementById('tiles').getBoundingClientRect().top + window.scrollY), i.scrollWidth <= i.clientWidth, n.getClientRects().length > 0, b.scrollWidth <= b.clientWidth].join(); });
  const bar0 = await barOf(page), barAll = [];
  for (const inc of D.incidents) { await page.evaluate((id) => selectIncident(id), inc.id); barAll.push(await barOf(page)); }
  ok(bar0 === '40,' + bar0.split(',')[1] + ',true,true,true' && barAll.every((b) => b.startsWith(bar0.split(',').slice(0, 2).join() + ',true,') && b.endsWith(',true')) && barAll.some((b) => b.includes(',true,false,')), 'Zeitraumleiste: gleiche Hoehe fuer jeden gewaehlten Vorfall, nichts darunter verschiebt sich, der Text des Zeitraums bleibt ganz, der Hinweis weicht: ' + bar0 + ' / ' + [...new Set(barAll)].join(' / '));
  await page.click('#rangeAll');
  // "In der Expertenansicht zeigen": the entry stands in the picture of the column, for every incident
  const outside = [];
  for (const inc of D.incidents) {
    await page.evaluate((id) => window.WP.openIncident(id), inc.id); await ivExpert(page);
    const at = await page.evaluate((id) => { const e = document.querySelector(`#incList .inc[data-id="${id}"]`).getBoundingClientRect(), l = document.getElementById('incList').getBoundingClientRect(); return [e.top >= l.top - 1 && e.bottom <= l.bottom + 1 && e.bottom <= window.innerHeight, document.querySelector(`#incList .inc[data-id="${id}"]`).classList.contains('selected')]; }, inc.id);
    if (!at[0] || !at[1]) outside.push(inc.id + ':' + at.join());
  }
  ok(D.incidents.length >= 12 && !outside.length, 'aus der Vorfallsansicht in die Expertenansicht: der gewaehlte Eintrag steht ganz im Bild der Spalte: ' + outside.join(' '));
  await page.click('#rangeAll');
  // -- item 18: a label of a target line that finds no free place on its line stands in the right margin, off the curve
  const inputLabels = await labelCovers(page, '#chInput'), side = await page.locator('#chInput svg').evaluate((svg) => { const c = svg.querySelector('clipPath rect'), x1 = Number(c.getAttribute('x')) + Number(c.getAttribute('width'));
    return [...svg.querySelectorAll('.band-warn, .band-crit')].map((g) => { const t = g.querySelector('text').getBBox(), y = Number(g.querySelector('line').getAttribute('y1')); return t.x >= x1 && t.x + t.width <= Number(svg.getAttribute('width')) && Math.abs(t.y + t.height / 2 - y) < 16; }); });
  ok(inputLabels === '▲ auffällig ab 150 ms: 0 | ◆ kritisch ab 500 ms: 0' && side.length === 2 && side.every(Boolean) && await labelFaults(page, '#chInput') === '', 'Eingabeverzoegerung aller Sitzungen (gesamte Messung): die Beschriftungen der Soll-Linien stehen neben ihren Linien am rechten Rand, mit Symbol und Wort, nicht auf der Kurve: ' + inputLabels + ' ' + side.join());
  const inPlot = await page.locator('#chCpu svg').evaluate((svg) => { const c = svg.querySelector('clipPath rect'), x1 = Number(c.getAttribute('x')) + Number(c.getAttribute('width')); return [...svg.querySelectorAll('.band-warn text, .band-crit text')].every((t) => t.getBBox().x + t.getBBox().width <= x1 + 1); });
  ok(inPlot && await labelCovers(page, '#chCpu') === '▲ auffällig ab 75 %: 0 | ◆ kritisch ab 90 %: 0', 'wo auf der Linie Platz ist, bleibt die Beschriftung im Diagramm');
  // -- item 20: first screen at 1400 x 900: the tiles need two rows, the second row of charts begins in the picture
  await page.evaluate(() => window.scrollTo(0, 0));
  const first = await page.evaluate(() => { const tops = [...document.querySelectorAll('#tiles .tile')].map((e) => Math.round(e.getBoundingClientRect().top)), ch = [...document.querySelectorAll('#charts .card')].map((e) => e.getBoundingClientRect().top), t = document.querySelector('#tiles .tile[data-signal="input.session"]');
    return [new Set(tops).size, Math.round(document.getElementById('tiles').getBoundingClientRect().height), ch[2] < window.innerHeight - 40, t.title.includes('am stärksten: '), t.querySelector('.goal').scrollWidth >= t.querySelector('.goal').clientWidth, [...document.querySelectorAll('#tiles .tile')].every((e) => e.scrollWidth <= e.clientWidth)]; });
  ok(first[0] === 2 && first[1] < 320 && first[2] && first[3] && first[4] && first[5], '1400 x 900: die Kacheln brauchen zwei Zeilen, die zweite Zeile der Diagramme beginnt im Bild; "am staerksten" steht auf einer Zeile und ganz im Tooltip der Kachel: ' + first.join(' '));
  // -- item 5 (the tiles of the same state are asserted in checkExpert) and item 7: a chart without a value in the range says "Zeitraum"
  const k0 = D.snapKind.indexOf('RRRR') + 1;
  await page.evaluate(([a, b]) => window.WP.setZoom(a, b), [D.snapT[k0] + 2000, D.snapT[k0] + 12000]);
  ok((await page.locator('#chSess').innerText()).trim() === 'Keine Messwerte im gewählten Zeitraum.' && (await page.locator('#footer').innerText()).includes('Punkten im Zeitraum'), 'ein Diagramm ohne Messwert im Zeitraum und die Fusszeile sagen "Zeitraum"');
  ok(page.errors.length === 0, 'Skriptfehler Korrekturrunde: ' + page.errors.join(' | '));
  await page.close();

  // -- item 11 (P3-R70): "immer dasselbe" only of several events that name the module
  const mp = await open(browser, path.join(dir, 'report.html'), scheme), one = D.incidents.find((i) => i.type === 'ereignis' && i.event.sameModule && i.event.moduleEvents === 1), several = D.incidents.find((i) => i.type === 'ereignis' && i.event.sameModule && i.event.moduleEvents > 1);
  const kvOf = async (id) => oneLine(await (await openIncident(mp.page, id)).locator('.iv-evidence .kv').first().innerText());
  const kv1 = await kvOf(one.id), kvN = await kvOf(several.id);
  ok(kv1.includes('Fehlerhaftes Modul ' + one.event.modules[0].name + ' (1 von 1)') && !kv1.includes('immer dasselbe') && kvN.includes(`(${several.event.moduleEvents} von ${several.event.moduleEvents}), immer dasselbe`), 'ein einzelnes Ereignis nennt sein Modul ohne "immer dasselbe", mehrere mit: ' + kv1 + ' / ' + kvN);
  await mp.page.close();

  // -- item 4: the tab "Vor der Messung" counts only what a lookback read
  const none = await openExpert(browser, path.join(dir, 'report-none.html'), scheme);
  ok(none.D.before.status === 'missingFile' && (await none.page.locator('#xtab-before').innerText()).trim() === 'Vor der Messung' && (await none.page.locator('#xtab-events .cnt').innerText()) === '0', 'Rueckblick nicht gelesen (Datei fehlt): der Reiter traegt keine Zahl (die Ereignisse der Messung zaehlen 0)');
  // -- item 17: the statement of a capture without a finding is one of the whole capture and says so under a range
  const nf = none.page.locator('#noFinding');
  ok(oneLine(await nf.locator('.lead').innerText()) === '● Keine Schwelle wurde überschritten.' && (await nf.innerText()).includes('Alle gemessenen Werte lagen in der gesamten Messung im Soll.'), 'ohne Befund, ohne Zeitraum: die Aussage ohne Kennzeichnung');
  await none.page.evaluate(() => window.WP.setZoom(FULL.t0 + 300000, FULL.t0 + 600000));
  ok(oneLine(await nf.locator('.lead').innerText()) === '● Keine Schwelle wurde überschritten. · gesamte Messung' && !(await nf.innerText()).includes('im ganzen Zeitraum'), 'ohne Befund, mit Zeitraum: die Aussage sagt, dass sie fuer die gesamte Messung gilt: ' + oneLine(await nf.locator('.lead').innerText()));
  await none.page.close();
  const emptyLb = (J) => { Object.assign(J.before, { eventCount: 0, incidentEventCount: 0, perDay: [], incidents: [], near: [], nearCapture: [], capped: [] }); };
  for (const [name, change, count] of [['unavailable', (J) => { emptyLb(J); J.before.status = 'unavailable'; }, ''], ['off', (J) => { emptyLb(J); J.before.status = 'off'; J.before.days = 0; }, ''], ['missing', (J) => { emptyLb(J); J.before.status = 'missingFile'; }, ''],
    ['read-none', (J) => { emptyLb(J); J.before.status = 'read'; }, '0'], ['partial', (J) => { J.before.status = 'partial'; J.before.logs = []; }, String(D.before.incidents.length)], ['read', () => {}, String(D.before.incidents.length)]]) {
    const lb = await openExpert(browser, patched(dir, 'report.html', `report-fix-lb-${name}.html`, change), scheme);
    ok(D.before.incidents.length > 0 && (await lb.page.locator('#xtab-before .cnt').innerText()) === count && lb.page.errors.length === 0, `Rueckblick ${name}: Zahl am Reiter "${count}": ` + await lb.page.locator('#xtab-before').innerText());
    await lb.page.close();
  }

  // -- item 14: fewer than three snapshots in the whole capture: the bar says so without a range
  const two = await openExpert(browser, patched(dir, 'report.html', 'report-fix-snaps2.html', (J) => { J.snapT = J.snapT.slice(0, 2); }), scheme);
  ok(await two.page.evaluate(() => window.WP.zoom === null) && await two.page.locator('#rangeSnaps').isVisible() && (await two.page.locator('#rangeSnaps').innerText()).includes('Tabellenwerte gestützt auf 2 Schnappschüsse') && two.page.errors.length === 0, 'gesamte Messung mit zwei Schnappschuessen: die Leiste sagt es: ' + two.page.errors.join(' | '));
  await two.page.close();

  // -- item 9: only a response time above the delivered maximum is left out of a range; every other signal keeps each point
  const cap = await openExpert(browser, patched(dir, 'report.html', 'report-fix-cap.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu'), vol = J.volumes.find((x) => x.name === 'C:'), k = J.tickT.findIndex((t) => t >= c.start + 10000);
    vol.ms[vol.t.findIndex((ti) => J.tickT[ti] >= c.start)] = 5000; J.host.queue[k] = 40; J.host.pagesIn[k] = 9000;
  }), scheme);
  await pick(cap.page, cap.D.incidents.find((i) => i.lead === 'cpu').id);
  const tileText = async (id) => oneLine(await cap.page.locator(`.tile[data-signal="${id}"]`).innerText());
  const capRow = (id) => cap.D.sollIst.find((r) => r.id === id);
  ok(capRow('cpu.queue').max < 40 && capRow('mem.pagesin').max < 9000 && (await tileText('cpu.queue')).includes('40,00 Max') && (await tileText('mem.pagesin')).includes('9.000 1/s Max') && !(await tileText('disk.latency')).includes('5.000'),
    'Zeitraum: nur eine Antwortzeit ueber dem gelieferten Maximum zaehlt nicht; Warteschlange und gelesene Seiten behalten jeden Punkt: ' + await tileText('cpu.queue') + ' / ' + await tileText('mem.pagesin') + ' / ' + await tileText('disk.latency'));
  await cap.page.close();

  // -- item 10: a masked report never says a designation twice ("Benutzer Benutzer 14", "Client Client 03")
  const mk = await open(browser, patched(dir, 'report-masked.html', 'report-fix-masked-focus.html', (J) => {
    const c = J.incidents.find((i) => i.lead === 'cpu'), s = J.sessions.find((x) => x.i === c.affected[0].s);
    J.meta.focus = { user: s.user, found: true, sessions: [s.i], reportedMs: c.start + 30000 }; c.focus = true; c.nearReported = true;
  }), scheme);
  const seenText = () => mk.page.evaluate(() => document.body.innerText + '\n' + [...document.querySelectorAll('[title]')].filter((e) => e.getClientRects().length).map((e) => e.title).join('\n'));
  const DOUBLE = /\b(\S+) \1 \d+/g, doubles = [], scan = async (where) => { for (const m of (await seenText()).matchAll(DOUBLE)) doubles.push(where + ': ' + m[0]); };
  await scan('gefuehrt');
  for (const inc of mk.D.incidents.concat(mk.D.before.incidents)) { await openIncident(mk.page, inc.id); await scan('Vorfall ' + inc.id); }
  await mk.page.evaluate(() => window.WP.closeIncident());
  await showExpert(mk.page);
  const userSess = mk.D.sessions.find((x) => x.user && x.client && x.domain);
  let kvS = '';
  for (const t of TABS) {
    await showTab(mk.page, t);
    if (t === 'sessions') { await mk.page.click(`#tSessions tbody tr[data-id="${userSess.i}"]`); kvS = oneLine(await mk.page.locator('#dSessions .kv').innerText()); }
    else if (t === 'apps' || t === 'procs') await mk.page.click(`#xt-${t} tbody tr >> nth=1`);
    await scan('Reiter ' + t);
  }
  await mk.page.evaluate((id) => selectIncident(id), mk.D.incidents.find((i) => i.lead === 'cpu').id);
  await scan('Zeitraum');
  const fi = await mk.page.locator('#focusInfo').innerText(), flags = (await mk.page.locator('#incList .inc.focus .flag').first().innerText());
  ok(/^Benutzer \d+$/.test(userSess.user) && /^Client \d+$/.test(userSess.client) && /^Domäne \d+$/.test(userSess.domain) && kvS.includes(userSess.domain + ' ' + userSess.client + ' Anmeldung') && fi.startsWith('Gemeldeter ' + mk.D.meta.focus.user + ', Sitzung') &&
    flags === 'betrifft den gemeldeten ' + mk.D.meta.focus.user && !doubles.length && mk.page.errors.length === 0, 'maskiert: keine Bezeichnung steht doppelt (Sitzung, Vorfall aus Ereignissen, gemeldeter Benutzer): ' + [...new Set(doubles)].slice(0, 5).join(' | ') + ' ' + kvS.substring(0, 60) + ' / ' + fi.substring(0, 50));
  await mk.page.close();
  // an unmasked report keeps its labels
  const um = await openExpert(browser, path.join(dir, 'report.html'), scheme), us = D.sessions.find((x) => x.user && x.client && x.domain);
  await showTab(um.page, 'sessions'); await um.page.click(`#tSessions tbody tr[data-id="${us.i}"]`);
  ok(oneLine(await um.page.locator('#dSessions .kv').innerText()).includes(`Domäne ${us.domain} Client ${us.client} Anmeldung`), 'unmaskiert: die Beschriftungen stehen vor ihren Werten');
  // -- item 1 (follow-up; fix round 2, P3-R77): every mean ("Ø") of the tabs of sessions, applications and processes says in
  // its title which mean it is. The report data state means over time, so every one of them is a mean over time and no title
  // claims a mean of the snapshots: CPU and working set of the three tables, processes and instances at a time, the working
  // set per instance, the working set of one application in one session (the pair tables of the details), the ICA round
  // trip and the Citrix values of a session.
  // (an application whose working set over time differs from the plain mean of its snapshots by more than a twentieth)
  const plainMean = (a) => { const v = a.filter((x) => x != null); return v.reduce((x, y) => x + y, 0) / v.length; };
  const ma = D.apps.filter((a) => a.ws && a.wsPerInst != null && a.instAvg > 1.2 && Math.abs(plainMean(a.ws) - a.wsAvg) > 0.05 * a.wsAvg).sort((a, b) => b.sess - a.sess)[0];
  await showTab(um.page, 'apps'); await um.page.click(`#tApps tbody tr[data-id="${ma.i}"]`);
  await um.page.locator('#dApps table tbody tr').first().waitFor();
  const means = await um.page.evaluate(() => [...document.querySelectorAll('#xt-sessions th, #xt-apps th, #xt-procs th, #dApps .kv span')].filter((e) => e.textContent.includes('Ø'))
    .map((e) => [e.closest('table') ? e.closest('table').id.replace(/\d+$/, '') : 'kv', (e.closest('table') ? e.textContent : e.childNodes[0].textContent).trim(), e.title || '']));
  const OVER_TIME = /(^|, | als )Mittelwert über die (Zeit|Laufzeit)( |,|$)/, OF_SNAPS = /Mittel(wert)? (der|über die) Schnappschüsse/;
  const timeMean = ['tSessions|CPU Ø %', 'tSessions|RAM Ø', 'tApps|CPU Ø %', 'tApps|RAM Ø gesamt', 'tProcs|CPU Ø %', 'tProcs|RAM Ø', 'sp|CPU Ø %', 'sp|RAM Ø',
    'tSessions|Prozesse Ø', 'sa|RAM Ø', 'tApps|gleichzeitig Ø', 'tApps|RAM Ø je Instanz', 'as|RAM Ø', 'kv|gleichzeitig Ø', 'kv|RAM je Instanz Ø'].concat(D.sessions.some((x) => x.rttAvg != null) ? ['tSessions|ICA RTT Ø ms'] : [], D.citrix.some((c) => c.s === us.i) ? ['sx|Ø'] : []);
  const snapMean = [];                                             // (fix round 2) none is left
  const said = new Map(means.map(([t, h, title]) => [t + '|' + h, title]));
  const untold = means.filter(([, , title]) => OVER_TIME.test(title) === OF_SNAPS.test(title)).map(([t, h, title]) => `${t}|${h}: "${title}"`)
    .concat(timeMean.filter((k) => !OVER_TIME.test(said.get(k) || '')).map((k) => k + ' nicht ueber die Zeit'), snapMean.filter((k) => !OF_SNAPS.test(said.get(k) || '')).map((k) => k + ' nicht als Mittel der Schnappschuesse'));
  ok(means.length >= timeMean.length + snapMean.length && D.citrix.some((c) => c.s === us.i) && !untold.length && !means.some(([, , title]) => OF_SNAPS.test(title)),
    'jeder Mittelwert der Reiter Sitzungen, Anwendungen und Prozesse sagt im Titel, dass er ueber die Zeit gebildet ist, keiner nennt sich Mittel der Schnappschuesse: ' + untold.concat(means.filter(([, , title]) => OF_SNAPS.test(title)).map(([t, h]) => t + '|' + h + ' nennt die Schnappschuesse')).slice(0, 4).join(' | '));
  // the titles are true: every cell is the delivered value, and the delivered working set is the mean over time of its series,
  // not the plain mean of the snapshots; the value per instance is the quotient of the two delivered means
  const maRow = await um.page.evaluate((i) => { const t = document.getElementById('tApps'), col = (k) => [...t.querySelectorAll('thead th')].findIndex((x) => x.dataset.k === k), r = t.querySelector(`tbody tr[data-id="${i}"]`), a = D.apps.find((x) => x.i === i);
    const pt = document.querySelector('#dApps table'), pc = [...pt.querySelectorAll('thead th')].findIndex((x) => x.dataset.k === 'wsAvg'), pair = D.pairs.filter((x) => x.a === i).sort((x, y) => y.cpuSec - x.cpuSec)[0];
    return { perInst: r.cells[col('wsPerInst')].textContent, perInstData: fmtMB(a.wsPerInst), inst: r.cells[col('instAvg')].textContent, instData: fmt(a.instAvg, 1), ws: r.cells[col('wsAvg')].textContent, wsData: fmtMB(a.wsAvg), wsTime: fmtMB(snapUse(a, 0, GRID.snap.length).wsAvg),
      pair: pt.querySelector(`tbody tr[data-id="${pair.s}"]`).cells[pc].textContent, pairData: fmtMB(pair.wsAvg), kv: document.querySelector('#dApps .kv').textContent }; }, ma.i);
  ok(maRow.perInst === maRow.perInstData && maRow.inst === maRow.instData && maRow.pair === maRow.pairData && maRow.kv.includes('RAM je Instanz Ø ' + maRow.perInstData) && maRow.ws === maRow.wsData
    && Math.abs(timeMeans(D, ma, 0, D.snapT.length).wsAvg - ma.wsAvg) <= 1.01 && Math.abs(plainMean(ma.ws) - ma.wsAvg) > 0.05 * ma.wsAvg && Math.abs(ma.wsAvg / ma.instAvg - ma.wsPerInst) <= 0.06 * ma.wsPerInst,
    `die Titel stimmen: "RAM Ø je Instanz", "gleichzeitig Ø", "RAM Ø" je Sitzung und "RAM Ø gesamt" sind die gelieferten Werte, "RAM Ø gesamt" ist das Mittel ueber die Zeit und nicht das Mittel der Schnappschuesse (${ma.name}: ${JSON.stringify(maRow).substring(0, 260)})`);
  await um.page.close();

  // -- items 2, 20: 1920 x 1080: the three wide tables fit their box; every row of charts holds plots of one height
  const w = await browser.newPage({ viewport: { width: 1920, height: 1080 }, colorScheme: scheme });
  w.errors = []; w.on('pageerror', (e) => w.errors.push(e.message));
  await w.goto('file://' + path.join(dir, 'report.html'));
  await showExpert(w);
  const rowsOf = await w.evaluate(() => { const rows = new Map(); for (const c of document.querySelectorAll('#charts .card')) { const y = Math.round(c.getBoundingClientRect().top), r = c.querySelector('clipPath rect'); if (!rows.has(y)) rows.set(y, []); rows.get(y).push(r ? Number(r.getAttribute('height')) : -1); } return [...rows.values()]; });
  ok(rowsOf.length === 5 && rowsOf[0].length === 2 && rowsOf.slice(1).every((r) => r.length === 3) && rowsOf.every((r) => new Set(r).size === 1), '1920 px: die zwei gestapelten Diagramme in einer Zeile, danach drei je Zeile; in jeder Zeile gleich hohe Diagramme: ' + JSON.stringify(rowsOf));
  const fit = [];
  for (const t of ['sessions', 'apps', 'procs', 'sollist']) { await showTab(w, t); fit.push(await w.evaluate((t) => { const b = document.querySelector(`#xt-${t} .tablewrap`); return t + ' ' + b.scrollWidth + '/' + b.clientWidth; }, t)); }
  ok(fit.every((f) => { const [a, b] = f.split(' ')[1].split('/').map(Number); return a <= b; }) && w.errors.length === 0, '1920 x 1080: keine Tabelle ist breiter als ihr Kasten: ' + fit.join(', '));
  await w.close();

  // -- items 20, 21: 1000 x 700: the incident column is a list over the tiles; the tiles need three rows; the target table fits
  const s = await browser.newPage({ viewport: { width: 1000, height: 700 }, colorScheme: scheme });
  s.errors = []; s.on('pageerror', (e) => s.errors.push(e.message));
  await s.goto('file://' + path.join(dir, 'report.html'));
  await showExpert(s);
  const lay = await s.evaluate(() => { const col = document.getElementById('incCol').getBoundingClientRect(), tl = document.getElementById('tiles').getBoundingClientRect(), tops = [...document.querySelectorAll('#tiles .tile')].map((e) => Math.round(e.getBoundingClientRect().top)), ch = [...document.querySelectorAll('#charts .card')].map((e) => Math.round(e.getBoundingClientRect().top));
    return [col.bottom <= tl.top, Math.round(col.width) === Math.round(tl.width), getComputedStyle(document.getElementById('incList')).display, getComputedStyle(document.getElementById('incToggle')).display !== 'none', new Set(tops).size, ch.filter((y) => y === ch[0]).length, document.documentElement.scrollWidth <= document.documentElement.clientWidth, document.getElementById('rangeBar').offsetHeight]; });
  ok(lay[0] && lay[1] && lay[2] === 'none' && lay[3] && lay[4] === 3 && lay[5] === 2 && lay[6] && lay[7] === 40, '1000 px: die Vorfallsspalte ist eine Liste ueber den Kacheln, die Kacheln brauchen drei Zeilen, zwei Diagramme je Zeile, ohne seitliches Rollen: ' + lay.join(' '));
  await s.click('#incToggle');
  await s.click(`#incList .inc[data-id="${cpu.id}"] .inc-main`);
  await showTab(s, 'sollist');
  const sw = await s.evaluate(() => { const b = document.querySelector('#xt-sollist .tablewrap'); return [b.scrollWidth, b.clientWidth, document.getElementById('rangeBar').offsetHeight, document.documentElement.scrollWidth <= document.documentElement.clientWidth]; });
  ok(sw[0] <= sw[1] && sw[2] === 40 && sw[3] && await s.locator(`#incList .inc[data-id="${cpu.id}"].selected`).count() === 1 && s.errors.length === 0, '1000 px: die Soll-Ist-Tabelle passt in ihren Kasten, die Leiste bleibt eine Zeile, auch mit gewaehltem Vorfall: ' + sw.join(' '));
  await s.close();
  // the widths between: the target table fits its box wherever the column stands beside it
  for (const width of [1180, 1280]) {
    const b = await browser.newPage({ viewport: { width, height: 800 }, colorScheme: scheme });
    await b.goto('file://' + path.join(dir, 'report.html'));
    await showExpert(b); await showTab(b, 'sollist');
    const bw = await b.evaluate(() => { const x = document.querySelector('#xt-sollist .tablewrap'), col = document.getElementById('incCol').getBoundingClientRect(); return [x.scrollWidth, x.clientWidth, Math.round(col.width), col.right <= x.getBoundingClientRect().left]; });
    ok(bw[0] <= bw[1] && bw[2] === 280 && bw[3], width + ' px: die Spalte steht neben den Tabellen, die Soll-Ist-Tabelle passt in ihren Kasten: ' + bw.join(' '));
    await b.close();
  }

  // -- item 21: a long name of a printer driver wraps, the columns behind it stay in the box
  const long = 'Microsoft.VisualStudio.Diagnostics.ServiceModelSink.Extended.Instrumentation.Runtime.4.0 Druckertreiber';
  const lp = await openExpert(browser, patched(dir, 'report.html', 'report-fix-driver.html', (J) => { J.print.drivers[0].name = long; }), scheme);
  await showTab(lp.page, 'print');
  const dw = await lp.page.evaluate(() => { const t = document.getElementById('tPrintDrivers'), b = t.closest('.tablewrap'), r = t.querySelector('tbody tr'), o = t.querySelector('tbody tr:nth-child(2)'); return [b.scrollWidth, b.clientWidth, r.cells[0].getBoundingClientRect().height > o.cells[0].getBoundingClientRect().height + 10, r.cells[r.cells.length - 1].getBoundingClientRect().right <= b.getBoundingClientRect().right + 1, r.cells[0].textContent]; });
  ok(dw[0] <= dw[1] && dw[2] && dw[3] && dw[4] === long, 'ein langer Treibername bricht um, die Tabelle der Treiber bleibt in ihrem Kasten: ' + dw.slice(0, 4).join(' '));
  await lp.page.close();
}

async function checkWording(browser, dir, scheme) {                 // die gemessene Maschine heisst in den Texten der Seite "Server" (P3-R66)
  // the page's own texts: everything of the page source but the report data (labels, hints, sentences, titles, tooltips);
  // the name of the tool stays
  const src = fs.readFileSync(path.join(dir, 'report.html'), 'utf8'), tag = '<script id="wp-data" type="application/json">';
  const own = src.substring(0, src.indexOf(tag)) + src.substring(src.indexOf('</script>', src.indexOf(tag)));
  const hits = own.match(/.{0,40}(?<![A-Za-zÄÖÜäöüß])Worker(?!Perf)[A-Za-zÄÖÜäöüß-]*.{0,20}/g) || [];
  ok(own.length > 100000 && own.includes('WorkerPerf') && hits.length === 0, 'die Texte der Seite nennen die gemessene Maschine nie "Worker": ' + hits.join(' | '));
  ok(own.includes('Kein Engpass auf dem Server.') && own.includes('nicht den Server.') && own.includes('Server-Ressourcen'), 'die Saetze zum Verursacher sagen "Server"');
  // shown: the page's own sentences on the cause of every incident (the report data may still say otherwise in this line of work)
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme), boxes = [];
  for (const inc of D.incidents.filter((i) => i.type !== 'ereignis')) boxes.push(await (await openIncident(page, inc.id)).locator('.iv-evidence .causebox').innerText());
  ok(boxes.length >= 8 && boxes.some((b) => b.includes('Server')) && !boxes.some((b) => /Worker(?!Perf)/.test(b)), 'Verursacher-Aussagen der Seite ohne "Worker": ' + boxes.filter((b) => /Worker/.test(b)).join(' | '));
  // (P3-R71, "durchgehend Server") The measured machine is never called "Host": not in the page's own texts, not in what the
  // page shows, not in the texts of the report data and of the text files they come from. "Host" stays where it means the
  // hypervisor ("VMware-Host", the "Hosts" of vCenter in the terms of the catalogue) and in "hostbasiert" (a kind of printer
  // driver); names of programs ("CtxSvcHost.exe") are no words of their own. (fix round 2: since its round 5 the catalogue
  // also says "Host" and "des Hosts" for the hypervisor in a sentence about VMware, before or after the word: "ob die Summe
  // der vCPU zum Host passt, beurteilt die Betreuung von VMware", "… Co-Stop des Hosts" after "der VMware-Host" more than
  // 150 characters before. "Host" or "Hosts" as a word of its own in a sentence, or a part of one after a semicolon, that names
  // VMware is the hypervisor. (Task 11: the catalogue after round 5's fix round puts a semicolon part between them: "…: die
  // CPU-Bereitschaft (Ready) ist ein Zähler des Hosts; nach Angabe von VMware …; die Praxisquelle GO-EUC (2026) wertet dazu auch
  // CPU-Latenz und Co-Stop des Hosts aus" in a sentence that starts with "ob der VMware-Host dem Server Rechenzeit entzogen hat".
  // "Hosts" after the "VMware-Host" in a whole sentence, semicolons included, is the hypervisor too.)
  const sentenceBefore = (text, i) => text.substring(Math.max(...['. ', '! ', '? ', '\n'].map((x) => text.lastIndexOf(x, i))) + 1, i);
  const sentenceOf = (text, i) => { const a = Math.max(...['. ', '! ', '? ', ';', '\n'].map((x) => text.lastIndexOf(x, i))), b = text.slice(i).search(/[.!?](\s|$)|[;\n]/); return text.substring(a + 1, b < 0 ? text.length : i + b); };
  const hostWords = (text) => [...text.matchAll(/(?<![\p{L}\p{N}])Host[\p{L}]*/gu)].filter((m) => !/^Hostbasiert/i.test(m[0]) && !text.substring(Math.max(0, m.index - 7), m.index).endsWith('VMware-') &&
    !(m[0] === 'Hosts' && /VMware/.test(text.substring(Math.max(0, m.index - 150), m.index))) && !(/^Hosts?$/.test(m[0]) && text[m.index + m[0].length] !== '-' && /VMware/.test(sentenceOf(text, m.index))) && !(m[0] === 'Hosts' && /VMware-Host/.test(sentenceBefore(text, m.index))))
    .map((m) => text.substring(Math.max(0, m.index - 40), m.index + 30).replace(/\s+/g, ' '));
  ok(hostWords('des Hosts, Host-Signale; der VMware-Host, hostbasierte und Hostbasierte Treiber, CtxSvcHost.exe').length === 2 && hostWords('Last des Hosts. Ob die vCPU zum Host passt, beurteilt die Betreuung von VMware. Der Host-Name').length === 2 &&
    hostWords('Ob der VMware-Host Zeit entzog; ' + 'Wert A; '.repeat(25) + 'dazu Co-Stop des Hosts. ' + 'Text. '.repeat(30) + 'Last des Hosts; Wert des Hosts').length === 2,
    'Eingabe: die Suche nach "Host" findet das Wort und laesst die Ausnahmen aus');
  const ownHost = hostWords(own);
  ok(own.includes('% des Servers') && own.includes('Server-Kapazität') && ownHost.length === 0, 'die Texte der Seite nennen die gemessene Maschine nie "Host": ' + ownHost.join(' | '));
  const strings = (v, out) => { if (typeof v === 'string') out.push(v); else if (Array.isArray(v)) v.forEach((x) => strings(x, out)); else if (v && typeof v === 'object') Object.values(v).forEach((x) => strings(x, out)); return out; };
  const dataHost = strings(D, []).flatMap(hostWords);
  ok(dataHost.length === 0, 'die Texte der Berichtsdaten nennen die gemessene Maschine nie "Host": ' + dataHost.slice(0, 5).join(' | '));
  const srcDir = path.join(__dirname, '..', 'src'), fileHost = [];
  for (const f of ['texts.de.json', 'guidance.de.json', 'thresholds.json']) for (const h of strings(JSON.parse(fs.readFileSync(path.join(srcDir, f), 'utf8')), []).flatMap(hostWords)) fileHost.push(f + ': ' + h);
  ok(JSON.parse(fs.readFileSync(path.join(srcDir, 'texts.de.json'), 'utf8'))['sourcecall.fast'].includes('Server-Signale') && fileHost.length === 0, 'die Textdateien der Berichtsdaten nennen die gemessene Maschine nie "Host": ' + fileHost.slice(0, 5).join(' | '));
  // shown: both views with every tab, an opened session, application and process, and what the tooltips and labels say
  const shown = async () => page.evaluate(() => document.body.innerText + '\n' + [...document.querySelectorAll('[title], [aria-label]')].map((e) => (e.getAttribute('title') || '') + ' ' + (e.getAttribute('aria-label') || '')).join('\n'));
  await page.evaluate(() => window.WP.closeIncident());
  await showGuided(page);
  let seen = await shown();
  await showExpert(page);
  for (const t of TABS) { await showTab(page, t); if (['sessions', 'apps', 'procs'].includes(t)) await page.click(`#xt-${t} tbody tr >> nth=1`); seen += '\n' + await shown(); }
  await page.click(`#incList .inc[data-id="${D.incidents.find((i) => i.lead === 'cpu').id}"] .inc-main`);
  seen += '\n' + await shown();
  const seenHost = hostWords(seen);
  ok(seen.includes('% des Servers') && seen.includes('Server-Kapazität') && seenHost.length === 0 && !/Ausschnitt/.test(seen), 'was die Seite zeigt, nennt die gemessene Maschine nie "Host" und den Zeitraum nie "Ausschnitt": ' + seenHost.slice(0, 5).join(' | '));
  ok(page.errors.length === 0, 'Skriptfehler Wortwahl: ' + page.errors.join(' | '));
  await page.close();
}

// ---------- Task 11: address, keyboard, motion, narrow width, colours ----------
// the background a chart is drawn on: the card of the split CPU chart in the colours of the view on screen
const chartGround = (page) => page.evaluate(() => getComputedStyle(document.querySelector('#chCpuStack').closest('.card')).backgroundColor);
const seriesColours = (page) => page.evaluate(() => [1, 2, 3, 4, 5, 6, 7, 8].map((k) => getComputedStyle(document.body).getPropertyValue('--s' + k).trim()));
async function checkNavigation(browser, dir, scheme) {
  const file = path.join(dir, 'report.html');
  const { page, D } = await open(browser, file, scheme);
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  await page.click(`#cards .card.inc[data-id="${cpu.id}"] .card-open`);
  ok((await page.evaluate(() => location.hash)).includes('i=' + cpu.id), 'Adresse haelt den Vorfall');
  await ivExpert(page);                                             // P3-R55: the helper instead of page.click('#ivExpert')
  const h = await page.evaluate(() => location.hash);
  ok(h.includes('v=expert') && h.includes('t0=') && h.includes('t1='), 'Adresse haelt Ansicht und Zeitraum');
  await page.goBack(); await page.waitForFunction(() => window.WP.view === 'guided');
  ok(await page.evaluate(() => window.WP.view) === 'guided' && await page.locator('#incident').isVisible(), 'Zurueck-Taste fuehrt innerhalb des Berichts zurueck');
  await page.keyboard.press('Escape'); await page.waitForFunction(() => window.WP.incident === null);
  ok(!(await page.locator('#incident').isVisible()), 'Esc schliesst die Vorfallsansicht');
  const b = await browser.newPage({ colorScheme: scheme }); b.errors = []; b.on('pageerror', (e) => b.errors.push(e.message));
  await b.goto('file://' + file + h);
  ok(await b.evaluate(() => window.WP.view) === 'expert' && await b.evaluate(() => window.WP.zoom !== null), 'Lesezeichen oeffnet dieselbe Stelle');
  // (added) the same place: the same range to the millisecond and the same incident chosen in the incident column
  const at = new URLSearchParams(h.slice(1));
  ok(await b.evaluate(() => JSON.stringify(window.WP.zoom)) === JSON.stringify({ t0: Number(at.get('t0')), t1: Number(at.get('t1')) }) && await b.locator(`#incList .inc[data-id="${cpu.id}"].selected`).isVisible(), 'Lesezeichen: derselbe Zeitraum, derselbe gewaehlte Vorfall: ' + await b.evaluate(() => JSON.stringify(window.WP.zoom)));
  await b.goto('file://' + file + '#v=guided&i=99999&t0=abc'); await b.reload();
  ok(await b.locator('#band').isVisible() && !(await b.locator('#incident').isVisible()) && b.errors.length === 0, 'unbekannter Vorfall im Lesezeichen');          // Review Focus 2
  // (added) an unreadable or reversed range, a range outside the capture: the whole capture; an unknown view counts as
  // missing: the view shown last
  for (const [hash, want] of [['#v=expert&t0=12&t1=abc', 'null'], ['#v=expert&t0=&t1=', 'null'], ['#v=nichts&i=x', 'remembered'], ['#v=expert&i=abc&t0=1e400&t1=-1', 'null'], [`#v=expert&t0=${D.meta.end + 3600000}&t1=${D.meta.end + 7200000}`, 'null']]) {
    await b.goto('file://' + file + hash); await b.reload();
    const z = await b.evaluate(() => window.WP.zoom), v = await b.evaluate(() => window.WP.view);
    const fine = want === 'remembered' ? v === 'expert' && z === null && await b.evaluate(() => localStorage.getItem('wp-view:' + location.pathname)) === 'expert' && await b.locator('#incident').isHidden() : z === null && v === 'expert';
    ok(fine && b.errors.length === 0, 'Lesezeichen ' + hash + ': ganze Messung bzw. Lagebild, ohne Skriptfehler: ' + v + ' ' + JSON.stringify(z) + ' ' + b.errors.join(' | '));
  }
  await b.close();
  await page.evaluate(() => { location.hash = ''; }); await page.reload();
  await page.keyboard.press('Tab'); await page.keyboard.press('Tab');
  ok(await page.evaluate(() => document.activeElement && getComputedStyle(document.activeElement).outlineStyle !== 'none'), 'sichtbarer Fokus');
  const durs = await page.evaluate(() => [...document.querySelectorAll('*')].flatMap((e) => getComputedStyle(e).transitionDuration.split(',').map(parseFloat)));
  ok(Math.max(...durs) <= 0.25, 'Bewegungen unter 250 ms');
  await page.close();
  const rm = await browser.newPage({ reducedMotion: 'reduce' }); await rm.goto('file://' + file);
  ok(await rm.evaluate(() => [...document.querySelectorAll('*')].every((e) => getComputedStyle(e).transitionDuration.split(',').every((d) => parseFloat(d) === 0))), 'keine Bewegung bei reduzierter Bewegung');
  await rm.close();
  const ls = await browser.newPage(); ls.errors = []; ls.on('pageerror', (e) => ls.errors.push(e.message));          // Review Focus 3
  await ls.addInitScript(() => { Object.defineProperty(window, 'localStorage', { get() { throw new Error('gesperrt'); } }); });
  await ls.goto('file://' + file);
  ok(await ls.locator('#guided').isVisible() && ls.errors.length === 0, 'ohne Speicher in der gefuehrten Ansicht');
  await ls.click('#viewSwitch button[data-view=expert]'); ok(await ls.locator('#expert').isVisible() && ls.errors.length === 0, 'Umschalten ohne Speicher');
  await ls.close();
  for (const view of ['guided', 'expert']) {
    const n = await browser.newPage({ viewport: { width: 400, height: 800 } }); await n.goto('file://' + file + '#v=' + view);
    ok(await n.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'schmale Breite ohne seitliches Scrollen: ' + view);
    await n.close();
  }
  const c = await browser.newPage({ colorScheme: scheme }); await c.goto('file://' + file);
  for (const view of ['guided', 'expert']) {
    await c.evaluate((v) => window.WP.showView(v), view);
    // (adapted) the chart ground is the card of a split chart in the colours of the view; the brief's
    // querySelector('.chart, .card') takes the first card of the page, which would be transparent if a .chart came first
    const cols = await seriesColours(c), bg = await chartGround(c), p = paletteCheck(cols, bg);
    ok(p.ok && paletteOk(cols, bg), 'Reihenfarben unterscheidbar, auch bei Farbfehlsichtigkeit: ' + view + ' (' + cols.join(' ') + ' auf ' + bg + '): ' + paletteText(p));
  }
  await c.close();
}

// The address in detail (Task 11, additions c-f): every way of changing the screen is a step of the history, back and forward
// restore view, incident and range and put the focus where the reader was, the remembered view, the keyboard in the
// incident column, the copy dialog, motion, the crosshair, narrow widths.
const addr = (page) => page.evaluate(() => Object.fromEntries(new URLSearchParams(location.hash.slice(1))));
const focusName = (page) => page.evaluate(() => { const a = document.activeElement; return !a || a === document.body ? 'body' : a.id || a.className || a.tagName; });
async function checkAddress(browser, dir, scheme) {
  const file = path.join(dir, 'report.html');
  const { page, D } = await open(browser, file, scheme);
  const cpu = D.incidents.find((i) => i.lead === 'cpu'), disk = D.incidents.find((i) => i.lead === 'disk'), len = () => page.evaluate(() => history.length);
  // the switch of the head bar is a step; back gives the focus to the switch that opened the expert view, forward to the
  // heading of the view it shows
  let n = await len();
  await showExpert(page);
  ok(await len() === n + 1 && (await addr(page)).v === 'expert', 'Umschalter: ein Schritt, die Adresse nennt die Expertenansicht: ' + JSON.stringify(await addr(page)));
  await page.goBack(); await page.waitForFunction(() => window.WP.view === 'guided');
  ok(await page.evaluate(() => document.activeElement === document.querySelector('#viewSwitch button[data-view=expert]')), 'Zurueck: der Fokus steht auf dem Umschalter, der die Expertenansicht geoeffnet hat: ' + await focusName(page));
  await page.goForward(); await page.waitForFunction(() => window.WP.view === 'expert');
  ok(await focusName(page) !== 'body' && await page.evaluate(() => document.getElementById('expert').contains(document.activeElement) || document.activeElement.closest('header') !== null), 'Vorwaerts: der Fokus steht in der Expertenansicht, nie auf <body>: ' + await focusName(page));
  // a click on an incident entry: one step with range and incident; a second click lets go (one more step)
  n = await len();
  await page.click(`#incList .inc[data-id="${cpu.id}"] .inc-main`);
  let a = await addr(page); const a0 = a;
  ok(await len() === n + 1 && a.v === 'expert' && a.i === String(cpu.id) && Number(a.t1) - Number(a.t0) > 0 && Number(a.t0) === (await page.evaluate(() => window.WP.zoom)).t0, 'Klick auf einen Vorfall: ein Schritt, die Adresse haelt Vorfall und Zeitraum: ' + JSON.stringify(a));
  // dragging over a chart writes one step when it ends, not one per movement of the mouse
  n = await len();
  const box = await page.locator('#chCpu svg .hit').boundingBox();
  await page.mouse.move(box.x + box.width * 0.2, box.y + box.height / 2); await page.mouse.down();
  for (let k = 1; k <= 8; k++) await page.mouse.move(box.x + box.width * (0.2 + k * 0.05), box.y + box.height / 2);
  await page.mouse.up();
  const dragged = await page.evaluate(() => window.WP.zoom), chosen = await page.evaluate(() => { const e = document.querySelector('#incList .inc.selected'); return e ? e.dataset.id : undefined; });
  a = await addr(page);
  // (a range that still reaches into the chosen incident keeps the choice, Task 10: the address names it as long as it is chosen)
  ok(await len() === n + 1 && Number(a.t0) === dragged.t0 && Number(a.t1) === dragged.t1 && a.i === chosen, 'Ziehen im Diagramm: ein Schritt am Ende, die Adresse haelt den neuen Zeitraum und den gewaehlten Vorfall: ' + (await len() - n) + ' ' + JSON.stringify(a) + ' ' + chosen);
  await page.goBack(); await page.waitForFunction((t) => window.WP.zoom && window.WP.zoom.t0 !== t, dragged.t0);
  ok(await page.locator(`#incList .inc[data-id="${cpu.id}"].selected`).isVisible() && (await addr(page)).i === String(cpu.id) && JSON.stringify(await page.evaluate(() => window.WP.zoom)) === JSON.stringify({ t0: Number(a0.t0), t1: Number(a0.t1) }), 'Zurueck: der Zeitraum des Vorfalls und seine Wahl sind wieder da');
  ok(await page.evaluate((id) => document.activeElement === document.querySelector(`#incList .inc[data-id="${id}"] .inc-main`) || document.activeElement.closest('#charts') !== null || document.activeElement.id === 'incHead', cpu.id), 'Zurueck: der Fokus steht beim Diagramm oder beim Eintrag, nie auf <body>: ' + await focusName(page));
  await page.goBack(); await page.waitForFunction(() => window.WP.zoom === null);
  ok((await addr(page)).t0 === undefined && await page.locator('#incList .inc.selected').count() === 0, 'noch ein Schritt zurueck: die ganze Messung');
  ok(await page.evaluate((id) => document.activeElement === document.querySelector(`#incList .inc[data-id="${id}"] .inc-main`), cpu.id), 'Zurueck: der Fokus steht auf dem Eintrag, der den Zeitraum gesetzt hatte: ' + await focusName(page));
  // "Gesamte Messung" is a step too
  await page.click(`#incList .inc[data-id="${disk.id}"] .inc-main`);
  n = await len(); await page.click('#rangeAll');
  ok(await len() === n + 1 && (await addr(page)).t0 === undefined && await page.evaluate(() => window.WP.zoom) === null, '"Gesamte Messung": ein Schritt, die Adresse ohne Zeitraum');
  // keyboard in the incident column: arrows move between the entries, Enter sets the range, Shift+Enter opens the guided view
  const entries = await page.locator('#incList .inc[data-id] button.inc-main').evaluateAll((els) => els.map((e) => Number(e.closest('.inc').dataset.id)));
  await page.focus(`#incList .inc[data-id="${entries[0]}"] .inc-main`);
  await page.keyboard.press('ArrowDown'); await page.keyboard.press('ArrowDown');
  const onEntry = () => page.evaluate(() => { const e = document.activeElement.closest('.inc[data-id]'); return e ? Number(e.dataset.id) : null; });
  ok(await onEntry() === entries[2], 'Pfeil nach unten: zum naechsten Eintrag: ' + await onEntry());
  await page.keyboard.press('ArrowUp');
  ok(await onEntry() === entries[1], 'Pfeil nach oben: zum vorigen Eintrag');
  await page.keyboard.press('End'); const last = await onEntry(); await page.keyboard.press('Home');
  ok(last === entries[entries.length - 1] && await onEntry() === entries[0], 'Pos1 und Ende: erster und letzter Eintrag');
  await page.keyboard.press('ArrowDown'); await page.keyboard.press('Enter');
  ok(await page.locator(`#incList .inc[data-id="${entries[1]}"].selected`).isVisible() && await page.evaluate(() => window.WP.zoom !== null) && (await addr(page)).i === String(entries[1]), 'Eingabetaste: der Zeitraum des Eintrags');
  ok(await page.locator(`#incList .inc[data-id="${entries[1]}"] .inc-main`).getAttribute('aria-keyshortcuts') === 'Shift+Enter', 'der Eintrag nennt seine zweite Taste (aria-keyshortcuts)');
  await page.keyboard.press('Shift+Enter'); await page.waitForFunction(() => window.WP.view === 'guided');
  ok(await page.locator(`#incident[data-id="${entries[1]}"]`).isVisible() && (await addr(page)).v === 'guided' && (await addr(page)).i === String(entries[1]), 'Umschalt+Eingabetaste: die gefuehrte Vorfallsansicht des Eintrags');
  await page.goBack(); await page.waitForFunction(() => window.WP.view === 'expert');
  ok(await onEntry() === entries[1], 'Zurueck aus der Vorfallsansicht: der Fokus steht wieder auf dem Eintrag: ' + await focusName(page));
  // into the guided view with the switch, back: the expert view at its place
  await page.evaluate(() => window.WP.closeIncident());
  // every element can be reached with Tab and shows its focus: the switch, a card button, a tab, a term
  for (const sel of ['#viewSwitch button[data-view=guided]', '#xtabs button[aria-selected=true]', `#incList .inc[data-id="${entries[0]}"] .inc-main`, `#incList .inc[data-id="${entries[0]}"] .inc-guided`, '#rangeAll:not([disabled]), #viewSwitch button[data-view=expert]']) {
    const el = page.locator(sel).first();
    await page.evaluate(() => document.activeElement && document.activeElement.blur());
    let hit = false;
    for (let k = 0; k < 80 && !hit; k++) { await page.keyboard.press('Tab'); hit = await el.evaluate((e) => e === document.activeElement); }
    const ring = hit ? await el.evaluate((e) => { const s = getComputedStyle(e); return s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) >= 2; }) : false;
    ok(hit && ring, 'mit Tab erreichbar und mit sichtbarem Fokus: ' + sel);
  }
  ok(page.errors.length === 0, 'Skriptfehler Adresse: ' + page.errors.join(' | '));
  await page.close();

  // the remembered view: the expert view chosen once opens again; the address goes before it
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 }, colorScheme: scheme }), r = await ctx.newPage();
  await r.goto('file://' + file); await showExpert(r);
  const key = await r.evaluate(() => 'wp-view:' + location.pathname);
  ok(await r.evaluate((k) => localStorage.getItem(k), key) === 'expert', 'gemerkte Ansicht unter ' + key);
  await r.goto('file://' + file + '?neu');                                   // another load of the page without an address
  ok(await r.evaluate(() => window.WP.view) === 'expert' && await r.locator('#expert').isVisible(), 'ohne Adresse oeffnet die gemerkte Ansicht');
  await r.goto('file://' + file + '?neu2#v=guided');
  ok(await r.evaluate(() => window.WP.view) === 'guided', 'die Adresse gilt vor der gemerkten Ansicht');
  // the incident view by address at 400 px: no sideways scrolling
  await r.setViewportSize({ width: 400, height: 800 });
  for (const id of [cpu.id, D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print').id]) {
    await r.goto(`file://${file}?n${id}#v=guided&i=${id}`);
    await r.evaluate(() => { document.querySelector('#incident details.iv-evidence').open = true; });
    ok(await r.locator(`#incident[data-id="${id}"]`).isVisible() && await r.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'Vorfallsansicht aus der Adresse, 400 px ohne seitliches Scrollen: ' + id);
  }
  // the search field of the sessions shows its whole placeholder (400 and 1400 px)
  for (const w of [400, 1400]) {
    await r.setViewportSize({ width: w, height: 800 });
    await r.goto(`file://${file}?w${w}#v=expert`); await showTab(r, 'sessions');
    const fit = await r.evaluate(() => { const f = document.getElementById('fSessions'), s = getComputedStyle(f), c = document.createElement('canvas').getContext('2d'); c.font = `${s.fontSize} ${s.fontFamily}`;
      return [Math.ceil(c.measureText(f.placeholder).width), f.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight), f.getBoundingClientRect().right <= window.innerWidth]; });
    ok(fit[0] <= fit[1] && fit[2], `Suchfeld der Sitzungen zeigt seinen ganzen Platzhalter (${w} px): ${fit.join(' ')}`);
  }
  await ctx.close();

  // a masked report: the address holds ids and times, no name
  const m = await open(browser, path.join(dir, 'report-masked.html'), scheme), mc = m.D.incidents.find((i) => i.lead === 'cpu');
  await m.page.click(`#cards .card.inc[data-id="${mc.id}"] .card-open`); await ivExpert(m.page);
  const mh = await m.page.evaluate(() => location.hash);
  ok(/^#v=expert&i=\d+&t0=\d+&t1=\d+$/.test(mh), 'maskierter Bericht: die Adresse haelt nur Ansicht, Nummer und Zeiten: ' + mh);
  await m.page.close();

  // motion: the switch of the views and of the incident view fade in, at most 0,24 s; every transition and animation of the
  // page at most 0,24 s; nothing moves when the reader asked for reduced motion
  for (const motion of ['no-preference', 'reduce']) {
    const mc2 = await browser.newContext({ viewport: { width: 1400, height: 900 }, colorScheme: scheme, reducedMotion: motion }), p = await mc2.newPage();
    p.errors = []; p.on('pageerror', (e) => p.errors.push(e.message));
    await p.goto('file://' + file);
    const times = () => p.evaluate(() => [...document.querySelectorAll('*')].flatMap((e) => { if (e.id === 'oldBrowser') return []; const s = getComputedStyle(e); return [s.transitionDuration, s.animationName === 'none' ? '0s' : s.animationDuration].join(',').split(',').map(parseFloat); }));
    const fadeOf = (sel) => p.evaluate((s) => { const e = document.querySelector(s); const st = getComputedStyle(e); return [st.animationName, parseFloat(st.animationDuration)]; }, sel);
    let all = await times();
    await p.click('#viewSwitch button[data-view=expert]'); const fx = await fadeOf('#expert'); all = all.concat(await times());
    await p.click('#viewSwitch button[data-view=guided]'); const fg = await fadeOf('#guided');
    await p.click(`#cards .card.inc[data-id="${cpu.id}"] .card-open`); const fi = await fadeOf('#incident'); all = all.concat(await times());
    if (motion === 'reduce') ok(all.every((v) => v === 0) && fx[1] === 0 && fi[1] === 0, 'reduzierte Bewegung: keine Uebergaenge und Animationen, auch beim Wechsel der Ebenen: ' + Math.max(...all) + ' ' + fx + ' ' + fi);
    else ok(Math.max(...all) <= 0.24 && [fx, fg, fi].every((f) => f[0] !== 'none' && f[1] > 0 && f[1] <= 0.24), 'Ueberblenden beim Wechsel der Ebenen, jede Bewegung hoechstens 0,24 s: ' + Math.max(...all) + ' ' + [fx, fg, fi].join(' | '));
    ok(p.errors.length === 0, 'Skriptfehler Bewegung (' + motion + '): ' + p.errors.join(' | '));
    await mc2.close();
  }

  // crosshair with time, value and status; mutual highlight of an incident entry and its time window
  const x = await open(browser, file, scheme);
  await showExpert(x.page);
  // the whole capture as the page computes it: first and last point of both time grids, the start and end of the capture
  const fr = { t0: Math.min(x.D.tickT[0], x.D.snapT[0], x.D.meta.start), t1: Math.max(x.D.tickT.at(-1), x.D.snapT.at(-1), x.D.meta.end) };
  const hb = await x.page.locator('#chCpu svg .hit').boundingBox(), frac = (cpu.start + cpu.end) / 2;
  await x.page.mouse.move(hb.x + hb.width * (frac - fr.t0) / (fr.t1 - fr.t0), hb.y + hb.height / 2);
  const tip = oneLine(await x.page.locator('#chCpu .tip').innerText());
  ok(/\d\d:\d\d:\d\d/.test(tip) && /\d+,\d %/.test(tip) && /(◆ kritisch|▲ auffällig|● normal)/.test(tip), 'Fadenkreuz: Uhrzeit, Wert und Status mit Symbol und Wort: ' + tip);
  ok(await x.page.locator(`#incList .inc[data-id="${cpu.id}"].hl`).count() === 1, 'Ueberfahren des Diagramms im Vorfall hebt seinen Eintrag hervor');
  await x.page.mouse.move(0, 0);
  ok(await x.page.locator('#incList .inc.hl').count() === 0, 'und nimmt die Hervorhebung wieder weg');
  await x.page.hover(`#incList .inc[data-id="${disk.id}"] .inc-main`);
  const hov = await x.page.evaluate(() => [...document.querySelectorAll('#charts svg')].filter((s) => s.querySelector('.hoverband')).length);
  ok(hov >= 10, 'Ueberfahren eines Eintrags zeigt sein Zeitfenster in den Diagrammen: ' + hov);
  await x.page.mouse.move(0, 0);
  ok(await x.page.locator('#charts .hoverband').count() === 0 && x.page.errors.length === 0, 'und nimmt es wieder weg');
  await x.page.close();
}

// every check function with the colour scheme of the system, then those that need one scheme only
// (the page does not follow the colour scheme of the system, checkViews asserts that for both: the checks of single states of
// the incident view, of copying, of printing and of the points carried from the review run once)
const PER_SCHEME = [checkNavigation, checkGuided, checkViews, checkCards, checkGuidedStates, checkOpens, checkIncidentView, checkIncidentContent, checkRange, checkPage, checkFindings, checkFinalFix, checkEvents,
  checkEventDetails, checkNarrow, checkFix1, checkFix2, checkLongNames, checkMask, checkMaskedPersonen, checkFinalWave, checkSkip];
const ONCE = [checkColourMath, checkAddress, checkIncidentStates, checkTerms, checkCopy, checkIncidentNav, checkIncidentLayout, checkReported, checkMotion, checkPrint, checkCarried, checkMaskedPage, checkFixWave, checkExpert, checkExpertFix, checkWording];
// the colour functions serve other scripts too (require): the checks run only when this file is called
module.exports = { deltaE2000, simulateCvd, contrast, labOf, colourDiff, paletteCheck };
if (require.main === module) (async () => {
  const args = process.argv.slice(2), option = (name) => { const k = args.indexOf(name); return k < 0 ? null : args.splice(k, 2)[1]; };
  const only = option('--only'), oneScheme = option('--scheme'), dir = path.resolve(args[0]);
  const names = only ? only.split(',') : null, known = PER_SCHEME.concat(ONCE).map((f) => f.name);
  for (const n of names || []) assert.ok(known.includes(n), 'unbekannte Pruefung: ' + n + ' (bekannt: ' + known.join(', ') + ')');
  const browser = await chromium.launch();
  let ran = 0;
  const run = async (fn, scheme) => {
    if (names && !names.includes(fn.name)) return;
    const t = Date.now(), before = checks;
    await fn(browser, dir, scheme); ran++;
    if (names) console.log(`${fn.name} (${scheme}): ${checks - before} in ${((Date.now() - t) / 1000).toFixed(1)} s`);
  };
  assert.ok(!oneScheme || ['light', 'dark'].includes(oneScheme), 'unbekanntes Farbschema: ' + oneScheme);
  const schemes = oneScheme ? [oneScheme] : ['light', 'dark'];
  for (const scheme of schemes) for (const fn of PER_SCHEME) await run(fn, scheme);
  if (schemes.includes('light')) for (const fn of ONCE) await run(fn, 'light');
  // the functions that run once run with the light scheme: named with --only beside --scheme dark, they did not run
  const left = names && !schemes.includes('light') ? ONCE.filter((f) => names.includes(f.name)).map((f) => f.name) : [];
  if (left.length) console.log('nicht gelaufen: ' + left.join(', ') + ' (diese Pruefungen laufen nur einmal, im hellen Farbschema; --scheme dark laesst sie aus)');
  console.log('browser checks passed: ' + checks);
  await browser.close();
  if (!ran) { console.error('keine Pruefung gelaufen'); process.exit(1); }
})().catch((e) => { console.error(e); process.exit(1); });
