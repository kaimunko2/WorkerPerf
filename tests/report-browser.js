// Aufruf: node tests/report-browser.js <Ordner aus tests/New-TestReports.ps1>
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const assert = require('assert');
let checks = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); checks++; };
const hhmm = (ms, offMin) => new Date(ms + offMin * 60000).toISOString().substr(11, 5);

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
// The report opens in the guided view; the tabs of the former page stand in the expert view.
async function showExpert(page) { await page.click('#viewSwitch button[data-view=expert]'); }
async function showGuided(page) { await page.click('#viewSwitch button[data-view=guided]'); }
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
  ok(await page.locator('#expert nav button[data-tab]').count() === 5 && await page.locator('#expert .zoombar #zoomInfo').count() === 1 && await page.locator('#expert main > section[role=tabpanel]').count() === 5, 'Expertenansicht mit Reiterleiste, Zoomleiste und fuenf Reitern');
  ok(await page.locator('header').isVisible() && await page.locator('footer').isVisible() && (await page.locator('footer').innerText()).includes('Bericht erstellt am'), 'Kopfleiste und Fuss in beiden Ansichten');
  ok(await page.evaluate(() => window.scrollY) === 0, 'Expertenansicht beginnt oben');
  await page.evaluate(() => window.scrollTo(0, 700));
  const hb = await page.locator('header').boundingBox(), tb = await page.locator('#expert .topbar').boundingBox();
  ok(hb.y === 0 && Math.abs(tb.y - hb.height) <= 1, 'Kopfleiste oben fest, Reiterleiste direkt darunter: ' + JSON.stringify([hb, tb]));
  await page.evaluate(() => window.WP.showView('guided'));
  ok(await viewState(page) === 'guided | guided | guided:true expert:false' && await page.locator('#guided').isVisible() && await page.locator('#guided #timeline .mark').count() === D.incidents.length, 'WP.showView wechselt zurueck');
  ok(await page.evaluate(() => window.scrollY) === 500, 'die gefuehrte Ansicht steht wieder an ihrer Stelle');
  await page.evaluate(() => window.WP.showView('nichts'));
  ok(await viewState(page) === 'guided | guided | guided:true expert:false', 'unbekannte Ansicht aendert nichts');
  // "Oeffnen" leads to the incident in the expert view: its entry unfolded, the charts on its window
  const opened = async (list, id) => await page.evaluate(() => window.WP.view) === 'expert' && await page.locator(`${list} .incident[data-id="${id}"].open`).isVisible();
  await page.click('#openTop');
  ok(await opened('#incidents', D.lagebild.top) && await page.evaluate(() => window.WP.zoom !== null), 'Wichtigsten Vorfall oeffnen');
  await showGuided(page);
  await page.click(`#cards .card.inc[data-id="${D.cards[2]}"] .card-open`);
  ok(await opened('#incidents', D.cards[2]), 'Karte oeffnet ihren Vorfall');
  await showGuided(page);
  await page.click(`#more .row[data-id="${D.more[0].ids[0]}"] .row-open`);
  ok(await opened('#incidents', D.more[0].ids[0]), 'Zeile der weiteren Vorfaelle oeffnet ihren Vorfall');
  await showGuided(page);
  await page.click(`#beforeG .card.inc[data-id="${D.before.incidents[0].id}"] .card-open`);
  ok(await opened('#before', D.before.incidents[0].id), 'Karte vor der Messung oeffnet ihren Vorfall');
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
  ok(await page.evaluate(() => window.WP.view) === 'guided', 'ein Klick auf die Karte neben den Knoepfen tut nichts');
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
  ok(!mt.includes('Kein Vorfall') && !mt.includes('Keine Schwelle wurde überschritten') && !mt.includes('im ganzen Zeitraum im Soll'), 'mit Vorfaellen keine Aussage ohne Befund');
  await page.click('#qualityG > summary');
  const flat = (s) => s.replace(/\s+/g, ' ').trim(), qg = flat(await page.locator('#qualityG').innerText());
  await showExpert(page);
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
    await showExpert(page); await showGuided(page);
    ok(page.errors.length === 0, name + ': Skriptfehler: ' + page.errors.join(' | '));
    await page.close();
  }
}

async function checkPage(browser, dir, scheme) {                    // Task 13
  const { page, D } = await openExpert(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('nav button[data-tab]').count() === 5, 'fuenf Reiter');
  await page.click('nav button[data-tab=overview]');
  for (const id of ['chCpu', 'chMem', 'chInput', 'chVolumes', 'chCpuStack', 'chMemStack']) ok(await page.locator(`#${id} svg path`).count() > 0, id + ' gezeichnet');
  ok(await page.locator('#chCpu .band-warn').count() === 1 && await page.locator('#chCpu .band-crit').count() === 1, 'Soll-Baender im CPU-Diagramm');
  ok(await page.locator('.tile[data-signal="cpu.host"]').getAttribute('data-status') === '2', 'CPU-Kachel kritisch');
  ok((await page.locator('.tile[data-signal="cpu.host"]').innerText()).includes('kritisch'), 'Status als Wort');
  ok(await page.locator('.tile.info[data-info="userspercore"]').count() === 1, 'Benutzer je logischer CPU als Information');
  ok(await page.locator('#chMainApp svg path').count() > 0, 'Verlauf der Hauptanwendung');
  ok(!(await page.locator('#zoomReset').isVisible()), 'ohne Zoom keine Ruecksetz-Schaltflaeche');
  const inc = D.incidents.find((i) => i.lead === 'cpu');
  await page.evaluate(([a, b]) => window.WP.setZoom(a, b), [inc.start, inc.end]);
  ok(await page.locator('#zoomReset').isVisible(), 'Ruecksetz-Schaltflaeche sichtbar');
  ok((await page.locator('#chCpu svg text.xaxis').first().textContent()).startsWith(hhmm(inc.start, D.meta.offsetMin)), 'Zeitachse beginnt am Fensteranfang');
  await page.click('#zoomReset');
  ok(await page.evaluate(() => window.WP.zoom === null), 'Zoom zurueckgesetzt');
  await page.click('nav button[data-tab=apps]');
  await page.selectOption('#fRoleApps', 'Sicherheit');
  const roles = await page.locator('#tApps tbody tr td.role').allInnerTexts();
  ok(roles.length > 0 && roles.every((r) => r.includes('Sicherheit')), 'Rollenfilter Anwendungen');
  await page.click('nav button[data-tab=sessions]');
  await page.click('#tSessions tbody tr >> nth=0');
  ok(await page.locator('#dSessions .chart-input svg path').count() > 0, 'Eingabeverzoegerung in der Sitzungsansicht');
  await page.click('nav button[data-tab=procs]');
  ok(await page.locator('#tProcs tbody tr.collector').count() === 1, 'Collector gekennzeichnet');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();
}

async function checkFindings(browser, dir, scheme) {                // Task 14
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('#guided #timeline .mark').count() === D.incidents.length && await page.locator('#guided #timeline').isVisible(), 'eine Markierung je Vorfall');
  ok(await page.locator('#guided #timeline .event').count() === D.events.length, 'Ereignisse in der Zeitleiste');
  await showExpert(page);
  ok(await page.locator('#tab-findings').isVisible() && await page.locator('nav button[data-tab]').first().getAttribute('data-tab') === 'findings' && await page.locator('nav button[data-tab=findings]').getAttribute('aria-selected') === 'true', 'in der Expertenansicht ist Befunde der erste Reiter');
  ok(await page.locator('#incidents .incident').count() === D.incidents.length, 'ein Eintrag je Vorfall');
  ok(!(await page.locator('#noFinding').isVisible()), 'kein Hinweis auf fehlende Befunde');
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  const entry = page.locator(`#incidents .incident[data-id="${cpu.id}"]`);
  ok((await entry.locator('.text').innerText()).includes('CPU-Engpass'), 'Klartext sichtbar');
  ok((await entry.locator('.badge').innerText()).includes('kritisch'), 'Schwere als Wort');
  await entry.locator('.text').click();
  ok(await entry.locator('.detail .affected li').count() === cpu.affected.length, 'Betroffene aufgelistet');
  ok((await entry.locator('.detail .contributors').innerText()).includes('EXCEL.EXE'), 'Verursacher aufgelistet');
  ok(await entry.locator('.detail svg path').count() > 0, 'Verlauf im Vorfall');
  await showGuided(page);
  await page.click(`#guided #timeline .mark[data-incident="${cpu.id}"]`);
  const z = await page.evaluate(() => window.WP.zoom);
  ok(await page.evaluate(() => window.WP.view) === 'expert' && await entry.locator('.detail').isVisible(), 'Klick auf die Markierung wechselt in die Expertenansicht zum aufgeklappten Vorfall');
  ok(z && z.t0 < cpu.start && z.t1 > cpu.end && z.t1 - z.t0 < (cpu.end - cpu.start) * 3, 'Klick stellt die Diagramme auf das Fenster ein');
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
  await page.click('#eventList summary');
  ok(await page.locator('#tEvents tbody tr').count() === Math.min(200, D.events.length), 'Ereignisliste');
  await page.click('#tEvents tbody tr >> nth=0');
  const ez = await page.evaluate(() => window.WP.zoom);
  ok(ez && Math.abs((ez.t0 + ez.t1) / 2 - D.events[0].t) <= 60000, 'Ereignis stellt den Zoom ein');
  ok((await page.locator('#quality').innerText()).includes('WorkerPerf'), 'Messqualitaet nennt den Collector');
  ok((await page.locator('#limits').innerText()).includes('SYSTEM'), 'Grenzen der Aussage genannt');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();

  const f = await open(browser, path.join(dir, 'report-focus.html'), scheme);
  ok(await f.page.locator('#guided #timeline .reported').isVisible() && await f.page.locator('#timeline .reported').count() === 1, 'gemeldete Uhrzeit markiert');
  await showExpert(f.page);
  ok((await f.page.locator('#incidents .incident').first().getAttribute('class')).includes('focus'), 'Vorfall des Benutzers steht vorn');
  ok((await f.page.locator('#focusInfo').innerText()).includes('user003'), 'Fokus genannt');
  await f.page.close();

  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#measured').isVisible() && await n.page.locator('#measured').evaluate((d) => d.open), 'Hinweis ohne Befund, gefuehrte Ansicht: aufgeklappt');
  ok((await n.page.locator('#measured').innerText()).includes('Keine Schwelle wurde überschritten'), 'ausdrueckliche Aussage, gefuehrte Ansicht');
  await showExpert(n.page);
  ok(await n.page.locator('#noFinding').isVisible(), 'Hinweis ohne Befund');
  ok((await n.page.locator('#noFinding').innerText()).includes('Keine Schwelle wurde überschritten'), 'ausdrueckliche Aussage');
  ok(await n.page.locator('#incidents .incident').count() === 0, 'keine Vorfaelle');
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
async function openIncident(page, id) {
  const entry = page.locator(`#incidents .incident[data-id="${id}"]`);
  await entry.locator('.text').click();
  return entry;
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
  let entry = await openIncident(page, chronic.id), text = await entry.locator('.detail').innerText();
  ok((await entry.locator('.causebox').innerText()).includes('nicht den Worker'), 'Umfeld: Aussage zur Netzstrecke');
  for (const word of ['nexus.exe', 'Oracle-Listener', 'Virenscan', 'Ereignisse im Fenster', 'Schutzprodukte', 'Kein Engpass auf dem Worker']) ok(!text.includes(word), 'Dauerzustand im Umfeld ohne fremde Belege: ' + word);
  // engpass with main cause: as before, with the unit of the ranking
  const mem = D.incidents.find((i) => i.lead === 'memory');
  entry = await openIncident(page, mem.id);
  ok((await entry.locator('.causebox').innerText()).includes('ms-teams.exe') && (await entry.locator('.causebox').innerText()).includes('des Arbeitsspeichers aller Prozesse (Working Set)'), 'Hauptverursacher mit Einheit');
  const prof = D.incidents.find((i) => i.lead === 'profile');
  entry = await openIncident(page, prof.id);
  ok((await entry.locator('.causebox').innerText()).includes('der I/O-Menge dieser Sitzung'), 'Profilcontainer: Anteil der Sitzung');
  ok((await entry.locator('.detail .contributors').innerText()).includes('Anteil an der I/O-Menge dieser Sitzung'), 'Profilcontainer: Rangliste der Sitzung');
  // ohne-engpass: as before; Minor 20: a chart with a single probe names the endpoint
  const backend = D.incidents.find((i) => i.type === 'ohne-engpass' && i.resources.includes('endpoint'));
  entry = await openIncident(page, backend.id);
  ok((await entry.locator('.causebox').innerText()).includes('Kein Engpass auf dem Worker. Höchste Eingabeverzögerung in nexus.exe'), 'Verzoegerung ohne Engpass wie bisher');
  ok((await entry.locator('.detail .sigcharts .legend').allInnerTexts()).some((t) => t.includes('Oracle-Listener')), 'Diagramm einer einzelnen Probe nennt die Gegenstelle');
  ok((await entry.locator('.detail').innerText()).includes('Ereignisse im Fenster'), 'Ereignisse bleiben beim kurzen Vorfall');
  // Minor 1, 2, 11 and the limits
  const q = await page.locator('#quality').innerText(), burstTicks = D.host.burst.filter((b) => b).length;
  ok(burstTicks > 0 && D.quality.burstTicks === burstTicks && Math.abs(D.quality.burstMin - burstTicks * D.meta.fastSec / 60) < 0.01, 'Zeit im Verdichtungsmodus aus den Takten');
  ok(q.includes(burstTicks.toLocaleString('de-DE') + ' Takte') && q.includes('im Abstand von 6 s'), 'Verdichtung: Dauer aus den Takten, Abstand wie gemessen');
  ok(!q.includes('unlesbare Zeilen') && !q.includes('Fehlgeschlagene Abfragen'), 'ohne uebersprungene Zeilen und Fehler keine Zeile dazu');
  ok((await page.locator('#sollNote').innerText()).includes('gelten Ø, P95 und Max für die jeweils schlechteste Instanz je Zeitpunkt'), 'Hinweis zu mehreren Instanzen');
  ok((await page.locator('#limits').innerText()).includes('Prozesse, die zwischen zwei Schnappschüssen starten und wieder enden, werden nicht erfasst; für einen beendeten Prozess fehlt der Verbrauch seit dem letzten Schnappschuss.'), 'Grenze der Prozess-Schnappschuesse');
  ok((await page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText()).includes('vor produktiver Nutzung'), 'Hinweis zur Herkunft der Citrix-Werte');
  ok(!(await page.locator('#subtitle').innerText()).includes('Aufzeichnung'), 'regulaeres Ende ohne Hinweis im Kopf');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();

  // I4: two critical CPU ticks without a finding
  const sp = await open(browser, path.join(dir, 'report-spike.html'), scheme);
  const ms = await sp.page.locator('#measured').innerText();
  ok(ms.includes('Kein Vorfall.') && ms.includes('Einzelne Überschreitungen ohne Befund (kürzer als die Mindestdauer): CPU-Auslastung Max 96,5 % (Soll unter 75 %).'), 'einzelne Ueberschreitungen genannt, gefuehrte Ansicht: ' + ms.split('\n').slice(0, 3).join(' / '));
  ok(!ms.includes('Keine Schwelle wurde überschritten') && !ms.includes('lagen im ganzen Zeitraum im Soll'), 'keine Aussage, alles sei im Soll, gefuehrte Ansicht');
  await showExpert(sp.page);
  const nf = await sp.page.locator('#noFinding').innerText();
  ok(nf.includes('Kein Vorfall.') && nf.includes('Einzelne Überschreitungen ohne Befund (kürzer als die Mindestdauer): CPU-Auslastung Max 96,5 % (Soll unter 75 %).'), 'einzelne Ueberschreitungen genannt: ' + nf.split('\n').slice(0, 2).join(' / '));
  ok(!nf.includes('Keine Schwelle wurde überschritten') && !nf.includes('lagen im ganzen Zeitraum im Soll'), 'keine Aussage, alles sei im Soll');
  ok(await sp.page.locator('#incidents .incident').count() === 0, 'kein Vorfall aus zwei Takten');
  let row = await sp.page.locator('#sollist tbody tr[data-id="cpu.host"]').innerText();
  ok(row.includes('normal') && row.includes('einzelne Überschreitungen') && !row.includes('kritisch'), 'Soll-Ist-Zeile normal mit Zusatz');
  await sp.page.click('nav button[data-tab=overview]');
  ok(await sp.page.locator('.tile[data-signal="cpu.host"]').getAttribute('data-status') === '0', 'CPU-Kachel normal');
  ok((await sp.page.locator('.tile[data-signal="cpu.host"]').innerText()).includes('einzelne Überschreitungen'), 'CPU-Kachel mit Zusatz');
  ok(await sp.page.locator('.tile[data-signal="ica.rtt"]').getAttribute('data-status') === 'na', 'nicht gemessen bleibt');
  ok(sp.page.errors.length === 0, 'Skriptfehler einzelne Ueberschreitungen: ' + sp.page.errors.join(' | '));
  await sp.page.close();

  // I1/I2/I3: engpass without process data and without measured input delay
  const nd = await openExpert(browser, path.join(dir, 'report-nodata.html'), scheme);
  const bare = nd.D.incidents.find((i) => i.type === 'engpass' && i.lead === 'cpu');
  entry = await openIncident(nd.page, bare.id);
  let box = await entry.locator('.causebox').innerText();
  ok(box.includes('Kein Hauptverursacher ermittelt: im Fenster liegen keine Prozessdaten vor.') && bare.text.includes('Kein Hauptverursacher ermittelt: im Fenster liegen keine Prozessdaten vor.'), 'Engpass ohne Prozessdaten: Text und Seite gleich');
  ok(!(await entry.locator('.detail').innerText()).includes('Kein Engpass auf dem Worker'), 'Engpass nie als "Kein Engpass auf dem Worker"');
  ok((await entry.locator('.detail .essentials').innerText()).includes('Eingabeverzögerung nicht gemessen; betroffene Sitzungen sind nicht bestimmbar.'), 'Betroffene nicht bestimmbar');
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
  box = await entry.locator('.causebox').innerText();
  ok(box.includes('Größter Verbraucher: Microsoft Defender mit 96 % der I/O-Menge. Im Fenster lief ein Virenscan; Zeitplan und Umfang des Scans prüfen.'), 'Schutzsoftware als groesster Verbraucher: ' + box);
  ok(box.includes('Größter Anteil außerhalb der Schutzsoftware: robocopy.exe') && !box.includes('Begleiter') && !(await entry.locator('.detail').innerText()).includes('Begleiter:'), 'nicht als Begleiter bezeichnet');
  entry = await openIncident(v.page, D.incidents.find((i) => i.lead === 'cpu').id);
  ok((await entry.locator('.causebox').innerText()).includes('Kein einzelner Hauptverursacher: kein Prozess erreicht 10 % der CPU-Zeit.'), 'kein Hauptverursacher unter der Untergrenze');
  entry = await openIncident(v.page, backend.id);
  ok((await entry.locator('.causebox').innerText()).includes('Kein Engpass in den gemessenen Worker-Ressourcen. Nicht gemessen: Datenträger-Antwortzeit, Freigabe-Antwortzeit (SMB); ein Engpass dort ist nicht ausgeschlossen.'), 'nicht gemessene Worker-Ressourcen genannt');
  ok((await v.page.locator('#subtitle').innerText()).includes('Aufzeichnung mit Fehler beendet: Testfehler <b>im Takt</b>'), 'Ende mit Fehler im Kopf');
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
  ok(ev.length === 4 && await page.locator('#incidents .incident.type-ereignis').count() === ev.length, 'Ereignisvorfaelle in der Liste');
  const many = ev.find((i) => i.event.app === 'OUTLOOK.EXE');
  const entry = await openIncident(page, many.id);
  ok((await entry.locator('.detail .patterns').innerText()).includes('spricht für Installation oder Update'), 'Aussage des Musters');
  const prof = ev.find((i) => i.event.kind === 'profileerror');
  ok((await (await openIncident(page, prof.id)).locator('.detail .patterns').innerText()).includes('Kein Muster erkannt'), 'kein Muster');
  ok((await page.locator('#before').innerText()).includes('Für diese Zeit liegen keine Messwerte vor.'), 'Vor der Messung mit Hinweis');
  ok(await page.locator('#before .day').count() === D.before.perDay.length && await page.locator('#before .incident').count() === D.before.incidents.length, 'Rueckblick je Tag und Vorfall');
  ok(await page.locator('#tPrintDrivers tbody tr').count() === 3 && (await page.locator('#tPrintQueues').innerText()).includes('PRN-EG-01'), 'Tabelle Drucken');
  await page.click('nav button[data-tab=sessions]');
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
  ok((await entry.locator('.badge').innerText()).includes('kritisch') && (await entry.locator('.text').innerText()) === outlook.text, 'Ereignisvorfall: Satz und Schwere als Wort');
  ok(await entry.locator('.detail .patterns li').count() === outlook.event.patterns.length, 'eine Zeile je Muster');
  ok(await entry.locator('.detail .evlist tbody tr').count() === outlook.events.length, 'Ereignisse des Vorfalls');
  ok((await entry.locator('.detail .evlist').innerText()).includes(evHms(outlook.events[0])), 'Zeit des Ereignisses in seiner Ortszeit');
  const head = await entry.locator('.detail .kv').innerText();
  ok(head.includes('olmapi32.dll') && head.includes('user010') && head.includes('3'), 'Kopfzeile mit Modul, Benutzern und Anzahl');
  // the crash after the memory incident and the memory incident refer to each other
  const chrome = ev.find((i) => i.event.app === 'chrome.exe'), mem = D.incidents.find((i) => i.lead === 'memory');
  let e2 = await openIncident(page, chrome.id);
  ok(await e2.locator(`.detail .lnk[data-incident="${mem.id}"]`).count() === 1, 'Verweis auf den Leistungsvorfall');
  e2 = await openIncident(page, mem.id);
  ok(await e2.locator(`.detail .lnk[data-incident="${chrome.id}"]`).count() === 1, 'Leistungsvorfall verweist auf den Ereignisvorfall');
  await e2.locator(`.detail .lnk[data-incident="${chrome.id}"]`).click();
  ok(await page.locator(`#incidents .incident[data-id="${chrome.id}"]`).evaluate((n) => n.classList.contains('open')), 'Verweis oeffnet den Ereignisvorfall');
  // the print incident: the driver is named as involved, in words
  const drv = await page.locator('#tPrintDrivers tbody tr', { hasText: 'HP Universal Printing PCL 6 (Sim)' }).innerText();
  ok(drv.includes('beteiligt') && drv.includes('Typ 3') && !drv.includes('möglicherweise'), 'Treiber als beteiligt bezeichnet');
  ok((await page.locator('#tPrintDrivers tbody tr', { hasText: 'Kyocera' }).innerText()).includes('isoliert'), 'Isolierung als Wort');
  const spool = await page.locator('#tPrintProcs tbody tr', { hasText: 'spoolsv.exe' }).innerText();
  ok(spool.includes('16 MB'), 'Arbeitsspeicher der Druckwarteschlange');
  // lookback: both counts labelled, per-day bars with their number, lookback incidents with their date
  const before = await page.locator('#before').innerText();
  ok(before.includes('Ereignisse aus diesen Tagen') && before.includes('davon mit Vorfallsart'), 'beide Zahlen des Rueckblicks benannt');
  // the simulated lookback lies before the day of the run: its dates come from the data, not a fixed calendar day
  const d0 = D.before.perDay[0], d0Text = d0.day.split('-').reverse().join('.'), bar0 = await page.locator('#before .day').first().innerText();
  ok(bar0.includes(d0Text) && bar0.includes(String(d0.count)), 'Balken mit Datum und Zahl: ' + bar0);
  const nexus = D.before.incidents.find((i) => i.event.app === 'nexus.exe');
  const be = page.locator(`#before .incident[data-id="${nexus.id}"]`);
  await be.locator('.text').click();
  ok((await be.locator('.detail .patterns').innerText()).includes('spricht für Profil oder Daten dieses Benutzers'), 'Muster im Rueckblick');
  ok((await be.locator('.detail .evlist').innerText()).includes(ddmmyyyy(nexus.events[0].t, nexus.events[0].offsetMin)), 'Rueckblick-Ereignisse mit Datum');
  ok(await be.locator('.detail .zoomto').count() === 0, 'kein Zoom fuer die Zeit vor der Messung');
  // C1: a lookback crash without session and account says so, never "ohne Benutzersitzung"
  const nosess = D.before.incidents.find((i) => i.event.app === 'simscan.exe');
  const ne = page.locator(`#before .incident[data-id="${nosess.id}"]`);
  await ne.locator('.text').click();
  const nkv = await ne.locator('.detail .kv').innerText();
  ok(nkv.includes('Sitzung nicht ermittelt') && !nkv.includes('ohne Benutzersitzung') && (await ne.locator('.text').innerText()).includes('Sitzung nicht ermittelt.'), 'Rueckblick: unbekannte Sitzung als solche benannt: ' + nkv);
  ok(!(await page.locator('#quality').innerText()).includes('unvollständig'), 'ohne Obergrenze kein Hinweis');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();

  // without event files: the report without a finding stays as it was
  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#guided #timeline .tl-row').count() > 0 && await n.page.locator('#guided #timeline .event').count() === 0 && await n.page.locator('#guided #timeline .tl-row[data-group]').count() === 0, 'ohne Ereignisse keine Ereigniszeilen');
  await showExpert(n.page);
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
  ok(await v.page.evaluate(() => window.__xss === undefined) && await v.page.locator('#tab-findings img, #guided img').count() === 0, 'Markup aus den Daten wird nicht ausgefuehrt');
  const ve = await openIncident(v.page, D.incidents.find((i) => i.type === 'ereignis' && i.event.app === 'OUTLOOK.EXE').id);
  ok((await ve.locator('.text').innerText()).includes('Satz ' + bad) && (await ve.locator('.detail .evlist').innerText()).includes('Ereignis ' + bad), 'Markup erscheint als Text');
  ok((await ve.locator('.detail .patterns').innerText()).includes('Muster ' + bad) && (await ve.locator('.detail .kv').innerText()).includes(bad), 'Muster und Kopfzeile als Text');
  ok(await ve.locator('.detail img').count() === 0, 'kein Bild im Vorfall');
  ok((await ve.locator('.detail .evlist').innerText()).includes('die ersten 2 und das letzte der 120 Ereignisse'), 'gekuerzte Ereignisliste benannt');
  await v.page.click('#eventList summary');
  ok((await v.page.locator('#tEvents').innerText()).includes('Text ' + bad), 'Ereignisliste zeigt Markup als Text');
  const pd = await v.page.locator('#tPrintDrivers tbody tr', { hasText: bad }).innerText();
  ok(pd.includes('möglicherweise beteiligt'), 'moeglicherweise beteiligter Treiber in Worten');
  ok((await v.page.locator('#tPrintQueues').innerText()).includes(bad), 'Warteschlange als Text');
  const sp = await v.page.locator('#tPrintProcs tbody tr', { hasText: 'spoolsv.exe' });
  ok(await sp.count() === 1, 'neu gestarteter Druckprozess in einer Zeile');
  const spt = await sp.innerText();
  ok(spt.includes('12 MB') && spt.includes('70 MB') && spt.includes('76 MB') && spt.includes('9999'), 'Anfang des ersten, Ende des letzten Prozesses, Hoechstwert: ' + spt);
  const vb = await v.page.locator('#before').innerText();
  ok(vb.includes('unvollständig') && vb.includes('Anwendung'), 'unvollstaendiger Rueckblick im Block');
  ok(vb.includes('Ereignisse um die gemeldete Uhrzeit') && vb.includes(D.before.incidents[0].events[0].text), 'Ereignisse um die gemeldete Zeit');
  ok(vb.includes('Ereignisse um die gemeldete Uhrzeit ' + ddmmyyyy(D.before.incidents[0].start + 60000, D.meta.offsetMin)), 'gemeldete Uhrzeit mit Datum');
  const vq = await v.page.locator('#quality').innerText();
  ok(vq.includes('ticks.csv: 0 · snapshots.csv: 0 · events.csv: 2 · printqueues.csv: 1'), 'uebersprungene Zeilen der Ereignisdateien: ' + vq);
  ok(vq.includes('Rückblick unvollständig') && vq.includes('Anwendung'), 'Obergrenze des Rueckblicks in der Messqualitaet');
  await v.page.click('nav button[data-tab=sessions]');
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
  await showExpert(page);
  for (const inc of [D.incidents.find((i) => i.type === 'ereignis'), D.incidents.find((i) => i.lead === 'memory')]) await openIncident(page, inc.id);
  await page.locator(`#before .incident[data-id="${D.before.incidents[0].id}"] .text`).click();
  const w = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok(w[0] <= w[1], 'Befunde schmal ohne seitliches Rollen: ' + w.join(' > '));
  await page.click('nav button[data-tab=sessions]');
  await page.click(`#tSessions tbody tr[data-id="${D.sessions.find((s) => s.user === 'user014').i}"]`);
  const w2 = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok(w2[0] <= w2[1], 'Sitzung schmal ohne seitliches Rollen: ' + w2.join(' > '));
  ok(page.errors.length === 0, 'Skriptfehler schmal: ' + page.errors.join(' | '));
  await page.close();
}

async function checkFix1(browser, dir, scheme) {                   // Task 9, Korrekturrunde 1
  const bt = async (page) => page.locator('#before').innerText();
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
  ok(await f2.page.locator('#before').isHidden(), 'Format 2 ohne Rueckblick: keine Karte');
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
  ok((await ce.locator('.detail .lnk[data-incident]').first().innerText()).includes('Arbeitsspeicher-Engpass'), 'Verweis nennt die Ressource wie der Satz');
  await page.click('#eventList summary');
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
  let kv = await me.locator('.detail .kv').innerText();
  ok(kv.includes('user109') && !kv.includes('user110') && kv.includes('(+50 weitere)') && kv.includes('16.0.9') && !kv.includes('16.0.10'), 'Kopfzeile hoechstens 10 Eintraege: ' + kv.slice(0, 200));
  await me.locator('.detail .kv button.more').first().click();
  kv = await me.locator('.detail .kv').innerText();
  ok(kv.includes('user159'), 'die ganze Liste bleibt erreichbar');
  ok(many.page.errors.length === 0, 'Skriptfehler viele Benutzer: ' + many.page.errors.join(' | '));
  await many.page.close();
}

async function checkFix2(browser, dir, scheme) {                   // Task 9, Korrekturrunde 2
  const bt = async (page) => page.locator('#before').innerText();
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
  ok(t.includes('Nicht gelesen: Ereignisprotokoll Anwendung') && t.includes('Ereignisse aus diesen Tagen') && await pv.page.locator('#before .day').count() === pv.D.before.perDay.length && await pv.page.locator('#before .incident').count() === pv.D.before.incidents.length, 'teilweiser Rueckblick mit Ereignissen: Zahlen, Balken, Vorfaelle und nicht gelesene Protokolle');
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
  await showExpert(page);
  for (const inc of D.incidents.filter((i) => i.type === 'ereignis' && (i.event.kind === 'print' || i.event.modules.some((m) => m.name.length > 80)))) await openIncident(page, inc.id);
  ok(long.length >= 90, 'Name mit 90 Zeichen');
  const w = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok(w[0] <= w[1], 'lange Namen schmal ohne seitliches Rollen: ' + w.join(' > '));
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
  const li = await win.page.locator(`#incidents .incident[data-id="${cpu.id}"] .detail ul.plain li`).allInnerTexts();
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
  ok(D.incidents.length > 0 && await page.locator('#incidents .incident').count() === D.incidents.length, 'maskiert: ein Eintrag je Vorfall');
  for (const inc of D.incidents) await openIncident(page, inc.id);
  ok(await page.locator('#incidents .incident.open').count() === D.incidents.length, 'maskiert: alle Vorfaelle geoeffnet');
  for (const inc of D.before.incidents) await page.locator(`#before .incident[data-id="${inc.id}"] .text`).click();
  await page.click('#eventList summary');
  ok(await page.locator('#tEvents tbody tr').count() === Math.min(200, D.events.length), 'maskiert: Ereignisliste');
  ok(await page.locator('#tPrintQueues tbody tr').count() > 0 && (await page.locator('#tPrintQueues').innerText()).includes('Drucker 01'), 'maskiert: Drucken mit Ersatznamen');
  await page.click('nav button[data-tab=overview]');
  ok(await page.locator('#chCpu svg path').count() > 0, 'maskiert: Uebersicht gezeichnet');
  await page.click('nav button[data-tab=sessions]');
  const s = D.sessions.find((x) => x.user === 'Benutzer 01');
  await page.click(`#tSessions tbody tr[data-id="${s.i}"]`);
  ok((await page.locator('#tSessions').innerText()).includes('Benutzer 01') && await page.locator('#dSessions .chart-input svg path').count() > 0, 'maskiert: Sitzungstabelle und Sitzung');
  await page.click('nav button[data-tab=apps]');
  await page.click('nav button[data-tab=procs]');
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
  const D = p.D, q = await p.page.locator('#quality').innerText();
  ok(q.includes('Ereignisprotokoll Anwendung: mindestens 250 Ereignisse nicht aufgezeichnet (Obergrenze je Abruf) · 3 Datensätze nicht lesbar und übersprungen'), 'Messqualitaet nennt die nicht aufgezeichneten Ereignisse: ' + q);
  ok(q.includes('Ereignisprotokoll Microsoft Defender: 1 Meldungstext nicht lesbar') && !q.includes('0 Datensätze'), 'nur Zahlen ueber null');
  ok(q.includes('Rückblick unvollständig gelesen für Anwendung, System'), 'unvollstaendig gelesener Rueckblick in der Messqualitaet');
  ok((await p.page.locator('#tSources tbody tr', { hasText: 'Ereignisprotokoll System' }).innerText()).includes('beim Lesen fehlgeschlagen'), 'Lesefehler beim Protokoll in den Quellen');
  const b = await p.page.locator('#before').innerText();
  const oldest = D.before.oldest.find((o) => o.log === 'application');
  ok(b.includes('Rückblick unvollständig gelesen') && b.includes('Anwendung (gelesen ab ' + ddmmyyyy(oldest.t, D.meta.offsetMin)) && b.includes('System (kein Ereignis gelesen)') && !b.includes('Obergrenze der gelesenen'), 'je Protokoll gelesen ab: ' + b.split('\n').slice(0, 6).join(' / '));
  ok(b.includes('Beim Lesen des Rückblicks: Anwendung: 2 Datensätze nicht lesbar und übersprungen, 1 Meldungstext nicht lesbar.'), 'Hinweis am Rueckblick: ' + b);
  ok(await p.page.locator('#before .day.partial').count() === 1 && (await p.page.locator('#before .day.partial').innerText()).includes('(Teil des Tages)') && b.includes('nur zum Teil erfasst'), 'Teiltage gekennzeichnet');
  ok(await p.page.locator('#before .before-incidents > .incident').count() === 20 && (await p.page.locator('#beforeMore').innerText()) === 'weitere 11 Vorfälle anzeigen', 'Liste der Vorfaelle vor der Messung nach 20 gefaltet');
  await p.page.click('#beforeMore');
  ok(await p.page.locator('#before .incident:visible').count() === 31 && await p.page.locator('#beforeMore').count() === 0, 'alle Vorfaelle nach dem Klick');
  ok(p.page.errors.length === 0, 'Skriptfehler Abschlussrunde: ' + p.page.errors.join(' | '));
  await p.page.close();
}

// locations of each place of the brief's table: [where, selector of the hint there]; where is a tab of the expert view or
// 'guided' for the guided view (its folded areas are opened before); incidents are opened before
const SKIP_LOCATIONS = (() => {
  const at = (p) => `.notmeasured[data-place="${p}"]`, inc = (p) => `#incidents .incident.open .evidence ${at(p)}`;
  return {
    procs: [['procs', `#tab-procs > ${at('procs')}`], ['overview', `#chCpuStack ${at('procs')}`], ['overview', `#chMemStack ${at('procs')}`],
      ['findings', `footer ${at('procs')}`], ['findings', `#quality ${at('procs')}`], ['guided', `footer ${at('procs')}`], ['guided', `#qualityG ${at('procs')}`]],
    apps: [['apps', `#tab-apps > ${at('apps')}`], ['overview', `#cardMainApp #chMainApp ${at('apps')}`]],
    'sessions.resources': [['sessions', `#tab-sessions > ${at('sessions.resources')}`], ['sessions', `#dSessions .chart-cpu ${at('sessions.resources')}`],
      ['sessions', `#dSessions .chart-ws ${at('sessions.resources')}`], ['sessions', `#dSessions .chart-io ${at('sessions.resources')}`],
      ['sessions', `#dSessions > ${at('sessions.resources')} >> nth=0`], ['sessions', `#dSessions > ${at('sessions.resources')} >> nth=1`]],
    'incidents.contributors': [['findings', inc('incidents.contributors')], ['guided', `#cards .card.inc ${at('incidents.contributors')}`]],
    'incidents.delayProcs': [['findings', inc('incidents.delayProcs')], ['guided', `#cards .card.inc ${at('incidents.delayProcs')}`]],
    'print.processes': [['findings', `#print ${at('print.processes')}`]],
    'print.drivers': [['findings', `#print ${at('print.drivers')}`]],
    'print.queues': [['findings', `#print ${at('print.queues')}`]],
    volumes: [['overview', `#chVolumes ${at('volumes')}`]],
    shares: [['overview', `#chShares ${at('shares')}`]],
    probes: [['overview', `#chProbes ${at('probes')}`]],
    'sessions.profile': [['sessions', `#dSessions .chart-profile ${at('sessions.profile')}`]],
    'sessions.rtt': [['sessions', `#dSessions .chart-rtt ${at('sessions.rtt')}`]],
    citrix: [['sessions', `#dSessions > ${at('citrix')}`]],
    'sessions.events': [['sessions', `#dSessions .sess-events ${at('sessions.events')}`]],
    'incidents.ica': [['findings', inc('incidents.ica')]],
    'incidents.endpoints': [['findings', inc('incidents.endpoints')]],
    'incidents.events': [['findings', inc('incidents.events')]],
    events: [['guided', `#guided #timeline .tl-row[data-group="skipped"] ${at('events')}`], ['guided', `#kpis .kpi[data-kpi="events"] ${at('events')}`], ['guided', `#qualityG ${at('events')}`],
      ['findings', `#quality ${at('events')}`]],
    before: [['findings', `#before ${at('before')}`], ['guided', `#beforeG ${at('before')}`]]
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
    for (const t of ['overview', 'apps', 'procs', 'sessions']) await page.click(`nav button[data-tab=${t}]`);
    await page.click('#tSessions tbody tr >> nth=0'); await page.click('nav button[data-tab=findings]');
    for (const i of D.incidents) await openIncident(page, i.id);
    const info = await page.locator('header #skipInfo').innerText();
    ok(info.includes('Nicht gemessen (-Skip): ' + D.skipped.map((s) => s.label).join(', ')), n + ': Kopf nennt die Kategorien: ' + info);
    const all = await page.evaluate(() => { const b = document.body.cloneNode(true); b.querySelectorAll('script').forEach((x) => x.remove()); return b.textContent; });
    for (const s of D.skipped) {
      ok(all.includes(s.text + ' (-Skip ' + s.id + ')'), n + ': Grund von ' + s.id + ' steht auf der Seite');
      for (const p of s.places) ok(await page.locator(`.notmeasured[data-place="${p}"]`).count() > 0, n + ': Stelle ' + p + ' sagt "nicht gemessen"');
    }
    // every location of a place in the brief's table shows its hint, visibly, in the view and on the tab where it stands
    for (const s of D.skipped) for (const p of s.places) for (const [where, sel] of (ok(SKIP_LOCATIONS[p], n + ': Stelle ' + p + ' fehlt in SKIP_LOCATIONS (tests/report-browser.js)'), SKIP_LOCATIONS[p])) {
      if (where === 'guided') await showGuided(page); else { await showExpert(page); await page.click(`nav button[data-tab=${where}]`); }
      ok(await page.locator(sel).first().isVisible(), n + ': Stelle ' + p + ' sichtbar an ' + sel);
    }
    await showExpert(page); await page.click('nav button[data-tab=findings]');
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
  ok((await entry.locator('.causebox').innerText()).includes(sentence) && cpu.text.includes(sentence), 'Verursacher: Text und Seite gleich');   // Review Focus 3
  ok(!(await entry.locator('.detail').innerText()).match(/keine Prozessdaten|keine Prozesse mit der Rolle Sicherheit/), 'kein "keine" fuer nicht Gemessenes');
  // counts that are 0 only because processes were not measured are not printed as numbers
  const foot = await p.page.locator('footer').innerText();
  ok(!foot.includes('von 0 Prozessen') && !foot.includes('Prozess-Messwerte') && await p.page.locator('footer .notmeasured[data-place="procs"]').count() === 1, 'Fuss ohne Prozesszahlen: ' + foot);
  await p.page.click('nav button[data-tab=sessions]');
  ok(await p.page.locator('#tab-sessions .notmeasured[data-place="sessions.resources"]').count() === 1, 'Hinweis ueber der Sitzungstabelle');
  const row = await p.page.locator('#tSessions tbody tr >> nth=0').innerText(), heads = await p.page.locator('#tSessions thead th').allInnerTexts();
  const cells = row.split('\t'), at = (h) => cells[heads.findIndex((x) => x.startsWith(h))];
  ok(['CPU-Anteil %', 'CPU-Zeit s', 'CPU Ø %', 'RAM Ø', 'I/O MB', 'Prozesse Ø'].every((h) => at(h) === '–'), 'Spalten der Prozessdaten zeigen "–": ' + row);
  await p.page.click('#tSessions tbody tr >> nth=0');
  ok(!(await p.page.locator('#dSessions .kv').innerText()).match(/CPU-Anteil 0/), 'Sitzungsansicht ohne 0 % CPU-Anteil');
  await p.page.click('nav button[data-tab=findings]');
  // a crash without process data: the assignment to sessions was not checked, never "Sitzung nicht ermittelt"
  const chrome = p.D.incidents.find((i) => i.type === 'ereignis' && i.event.app === 'chrome.exe');
  ok(chrome && chrome.event.sessionUnknown && chrome.event.unchecked.some((u) => u.id === 'users'), 'Daten: chrome.exe ohne Zuordnung, nicht geprueft');
  entry = await openIncident(p.page, chrome.id);
  const det = await entry.locator('.detail').innerText(), pats = await entry.locator('.patterns li').allInnerTexts();
  ok(!det.includes('Sitzung nicht ermittelt') && !det.match(/ohne Benutzersitzung/i), 'chrome.exe: keine Aussage zur Sitzung: ' + det.slice(0, 300));
  ok(chrome.event.unchecked.every((u) => pats.some((t) => t.includes('nicht geprüft: ' + u.text))) && !pats.some((t) => t.includes('Kein Muster erkannt')), 'chrome.exe: je Eintrag ein "nicht geprueft": ' + pats.join(' / '));
  ok(p.page.errors.length === 0, 'Skriptfehler prozesse: ' + p.page.errors.join(' | '));
  await p.page.close();
  const d = await openExpert(browser, path.join(dir, 'report-skip-drucken.html'), scheme);
  entry = await openIncident(d.page, d.D.incidents.find((i) => i.type === 'ereignis' && i.event.kind === 'print').id);
  const pat = await entry.locator('.patterns').innerText();
  ok(pat.includes('nicht geprüft: Bezug zu einem Druckertreiber (Drucken nicht gemessen)') && !pat.includes('Kein Muster erkannt'), 'Muster nicht geprueft statt "kein Muster"');
  ok(!(await d.page.locator('#print').innerText()).includes('Keine Treiberliste aufgezeichnet'), 'Drucken: nicht "keine Treiberliste"');
  await d.page.close();
  const r = await openExpert(browser, path.join(dir, 'report-skip-rueckblick.html'), scheme);
  // Aussage geaendert (Abschlussrunde, Minor 5): der Hinweis nennt den Grund, der Satz zum Zustand sagt dasselbe nicht noch einmal
  const rbt = await r.page.locator('#before').innerText();
  ok(rbt.includes('nicht gemessen – Ereignisse der Tage vor der Messung wurden nicht erfasst. (-Skip Rueckblick)') && !rbt.includes('Der Rückblick war abgeschaltet'), 'Rueckblick abgeschaltet, einmal gesagt: ' + rbt);
  await r.page.close();
  const e = await openExpert(browser, path.join(dir, 'report-skip-ereignisse.html'), scheme);
  ok(e.D.quality.eventReads.length === 0 && await e.page.locator('#quality .notmeasured[data-place="events"]').count() === 1, 'Messqualitaet: Ereignisprotokolle nicht gemessen');
  // driver involvement draws on the incidents from events: without the events of the capture never "nein"
  const cellsOf = async (page) => (await page.locator('#tPrintDrivers tbody td:nth-child(6)').allInnerTexts()).map((t) => t.replace(/\s+/g, ' ').trim());
  let drv = await cellsOf(e.page);
  // Aussage geaendert (Abschlussrunde, Minor 10): der Rueckblick ist gelesen, "nein" gilt fuer die Tage vor der Messung
  ok(e.D.before.status === 'read' && drv.length === 3 && drv.every((t, k) => t === (e.D.print.drivers[k].involved ? 'beteiligt' : 'nein (vor der Messung)')) && await e.page.locator('#print .notmeasured[data-place="events"]').isVisible(), 'Ereignisse: Treiber "nein" nur vor der Messung, mit Grund: ' + drv.join(' / '));
  await e.page.close();
  const a = await openExpert(browser, path.join(dir, 'report-skip-alle.html'), scheme);
  ok(await a.page.locator('#tPrintDrivers').count() === 0 && !(await a.page.locator('#print').innerText()).match(/\bnein\b/), 'alle: keine Treibertabelle, kein "nein"');
  await a.page.close();
  const rb = await openExpert(browser, path.join(dir, 'report-skip-rueckblick.html'), scheme);
  drv = await cellsOf(rb.page);
  ok(drv.filter((t) => t === 'beteiligt').length === 1 && drv.filter((t) => t === 'nein (während der Messung)').length === 2 && await rb.page.locator('#print .notmeasured[data-place="before"]').isVisible(), 'Rueckblick: "nein" nur fuer die Messung: ' + drv.join(' / '));
  await rb.page.close();
  const f = await openExpert(browser, path.join(dir, 'report.html'), scheme);
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
    const box = await (await openIncident(q.page, id)).locator('.causebox').innerText();
    ok(box.includes('Microsoft Defender mit 74 %') && box.includes(want) && (base === 'report.html') === !box.includes('nicht erfasst'), base + ': Schutzsoftware ohne Scan: ' + box);
    await q.page.close();
  }
  // Minor 3: several categories of the overlap left out make one line
  const g = await openExpert(browser, patched(dir, 'report-skip-gegenstellen.html', 'report-skip-overlap3.html', (J) => {
    const i = J.incidents.find((x) => x.type === 'ereignis' && x.event.unchecked.length === 1 && x.event.unchecked[0].id === 'overlap');
    i.event.unchecked = ['Laufwerke', 'Citrix', 'Gegenstellen'].map((c) => ({ id: 'overlap', category: c, text: `Zusammentreffen mit einem Vorfall der Kategorie ${c} (${c} nicht gemessen)` }));
    J.overlapId = i.id;
  }), scheme);
  let pats = await (await openIncident(g.page, g.D.overlapId)).locator('.patterns li.unchecked').allInnerTexts();
  ok(pats.length === 1 && pats[0].includes('nicht geprüft: Zusammentreffen mit Vorfällen der Kategorien Laufwerke, Citrix, Gegenstellen (nicht gemessen)'), 'drei Kategorien in einer Zeile: ' + pats.join(' / '));
  await g.page.close();
  const g1 = await openExpert(browser, path.join(dir, 'report-skip-gegenstellen.html'), scheme);
  const one = g1.D.incidents.find((x) => x.type === 'ereignis' && x.event.unchecked.length === 1);
  pats = await (await openIncident(g1.page, one.id)).locator('.patterns li.unchecked').allInnerTexts();
  ok(pats.length === 1 && pats[0].includes('nicht geprüft: Zusammentreffen mit einem Vorfall der Kategorie Gegenstellen (Gegenstellen nicht gemessen)'), 'eine Kategorie wie bisher: ' + pats.join(' / '));
  await g1.page.close();
  // Minor 4: the limits of a category left out are no limits of the capture
  const IO = 'Bei Datenträgern und Freigaben ist sichtbar', SHORT = 'Prozesse, die zwischen zwei Schnappschüssen starten';
  for (const [file, io, short] of [['report.html', true, true], ['report-skip-laufwerke.html', false, true], ['report-skip-prozesse.html', false, false], ['report-skip-alle.html', false, false], ['report-skip-citrix.html', true, true]]) {
    const r = await openExpert(browser, path.join(dir, file), scheme), l = await r.page.locator('#limits').innerText();
    ok(l.includes(IO) === io && l.includes(SHORT) === short && l.includes('Die Eingabeverzögerung enthält keine Prozesse, die als SYSTEM laufen.'), file + ': Grenzen der Aussage: ' + l);
    await r.page.close();
  }
  // Minor 10: neither the capture nor the lookback read: "–" and "nicht geprueft"
  const both = await openExpert(browser, patched(dir, 'report-skip-ereignisse.html', 'report-skip-ereignisse-rueckblick.html', (J) => {
    J.skipped.push({ id: 'Rueckblick', label: 'Rückblick', text: 'Ereignisse der Tage vor der Messung wurden nicht erfasst.', places: ['before'] });
    Object.assign(J.before, { status: 'off', days: 0, eventCount: 0, incidentEventCount: 0, perDay: [], incidents: [], near: [], nearCapture: [], capped: [] });
  }), scheme);
  const cells = (await both.page.locator('#tPrintDrivers tbody td:nth-child(6)').allInnerTexts()).map((t) => t.trim());
  ok(cells.length === 3 && cells.every((t) => t === '–') && (await both.page.locator('#print').innerText()).includes('„An einem Vorfall beteiligt“: nicht geprüft.'), 'Ereignisse und Rueckblick weggelassen: ' + cells.join(' / '));
  ok(both.page.errors.length === 0, 'Skriptfehler beide weggelassen: ' + both.page.errors.join(' | '));
  await both.page.close();
  // Minor 6: a capture whose Skip contradicts its files gives the page of its Skip, without a script error
  const odd = await openExpert(browser, path.join(dir, 'report-skip-odd.html'), scheme);
  for (const t of ['overview', 'apps', 'procs', 'sessions', 'findings']) await odd.page.click(`nav button[data-tab=${t}]`);
  ok(odd.page.errors.length === 0 && odd.D.procs.length === 0 && (await odd.page.locator('header #skipInfo').innerText()).includes('Nicht gemessen (-Skip): Prozesse') && (await odd.page.locator('#print').innerText()).includes('Drucken') && (await odd.page.locator('#quality').innerText()).length > 0, 'Skip gegen die Dateien: Seite ohne Fehler: ' + odd.page.errors.join(' | '));
  await odd.page.close();
}

(async () => {
  const dir = path.resolve(process.argv[2]);
  const browser = await chromium.launch();
  for (const scheme of ['light', 'dark']) {
    await checkGuided(browser, dir, scheme); await checkViews(browser, dir, scheme); await checkCards(browser, dir, scheme);
    await checkGuidedStates(browser, dir, scheme); await checkOpens(browser, dir, scheme);
    await checkPage(browser, dir, scheme); await checkFindings(browser, dir, scheme); await checkFinalFix(browser, dir, scheme);
    await checkEvents(browser, dir, scheme); await checkEventDetails(browser, dir, scheme); await checkNarrow(browser, dir, scheme);
    await checkFix1(browser, dir, scheme); await checkFix2(browser, dir, scheme); await checkLongNames(browser, dir, scheme);
    await checkMask(browser, dir, scheme); await checkMaskedPersonen(browser, dir, scheme); await checkFinalWave(browser, dir, scheme);
    await checkSkip(browser, dir, scheme);
  }
  await checkMaskedPage(browser, dir, 'light');
  await checkFixWave(browser, dir, 'light');
  console.log('browser checks passed: ' + checks);
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
