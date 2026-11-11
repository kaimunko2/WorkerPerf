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
  await page.goto('file://' + file);
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent));
  return { page, D };
}

async function checkPage(browser, dir, scheme) {                    // Task 13
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
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
  ok(await page.locator('#tab-findings').isVisible(), 'Befunde ist der Startreiter');
  ok(await page.locator('#incidents .incident').count() === D.incidents.length, 'ein Eintrag je Vorfall');
  ok(await page.locator('#timeline .mark').count() === D.incidents.length, 'eine Markierung je Vorfall');
  ok(await page.locator('#timeline .event').count() === D.events.length, 'Ereignisse in der Zeitleiste');
  ok(!(await page.locator('#noFinding').isVisible()), 'kein Hinweis auf fehlende Befunde');
  const cpu = D.incidents.find((i) => i.lead === 'cpu');
  const entry = page.locator(`#incidents .incident[data-id="${cpu.id}"]`);
  ok((await entry.locator('.text').innerText()).includes('CPU-Engpass'), 'Klartext sichtbar');
  ok((await entry.locator('.badge').innerText()).includes('kritisch'), 'Schwere als Wort');
  await entry.locator('.text').click();
  ok(await entry.locator('.detail .affected li').count() === cpu.affected.length, 'Betroffene aufgelistet');
  ok((await entry.locator('.detail .contributors').innerText()).includes('EXCEL.EXE'), 'Verursacher aufgelistet');
  ok(await entry.locator('.detail svg path').count() > 0, 'Verlauf im Vorfall');
  await page.click(`#timeline .mark[data-incident="${cpu.id}"]`);
  const z = await page.evaluate(() => window.WP.zoom);
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
    const u = await open(browser, bad, scheme);
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
  ok((await f.page.locator('#incidents .incident').first().getAttribute('class')).includes('focus'), 'Vorfall des Benutzers steht vorn');
  ok(await f.page.locator('#timeline .reported').count() === 1, 'gemeldete Uhrzeit markiert');
  ok((await f.page.locator('#focusInfo').innerText()).includes('user003'), 'Fokus genannt');
  await f.page.close();

  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#noFinding').isVisible(), 'Hinweis ohne Befund');
  ok((await n.page.locator('#noFinding').innerText()).includes('Keine Schwelle wurde überschritten'), 'ausdrueckliche Aussage');
  ok(await n.page.locator('#incidents .incident').count() === 0, 'keine Vorfaelle');
  ok(n.page.errors.length === 0, 'Skriptfehler ohne Befund: ' + n.page.errors.join(' | '));
  await n.page.close();
}

(async () => {
  const dir = path.resolve(process.argv[2]);
  const browser = await chromium.launch();
  for (const scheme of ['light', 'dark']) { await checkPage(browser, dir, scheme); await checkFindings(browser, dir, scheme); }
  console.log('browser checks passed: ' + checks);
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
