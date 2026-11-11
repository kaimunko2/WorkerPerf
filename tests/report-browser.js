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
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(await page.locator('#oldBrowser').count() === 0, 'Hinweis fuer alte Browser entfernt, sobald das Skript laeuft');
  {                                                                  // Minor 18: without script the static message stays visible
    const ctx = await browser.newContext({ javaScriptEnabled: false }), plain = await ctx.newPage();
    await plain.goto('file://' + path.join(dir, 'report.html'));
    ok((await plain.locator('#oldBrowser').innerText()).includes('Dieser Bericht benötigt einen aktuellen Browser (Microsoft Edge, Chrome oder Firefox).'), 'Hinweis ohne laufendes Skript sichtbar');
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
  const nd = await open(browser, path.join(dir, 'report-nodata.html'), scheme);
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
  const v = await open(browser, patched(dir, 'report.html', 'report-variant.html', (J) => {
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
  const k = await open(browser, patched(dir, 'report.html', 'report-killed.html', (J) => { J.meta.endReason = null; }), scheme);
  ok((await k.page.locator('#subtitle').innerText()).includes('Aufzeichnung nicht regulär beendet (kein Abschluss in meta.json).'), 'fehlender Abschluss im Kopf');
  await k.page.close();
}

(async () => {
  const dir = path.resolve(process.argv[2]);
  const browser = await chromium.launch();
  for (const scheme of ['light', 'dark']) { await checkPage(browser, dir, scheme); await checkFindings(browser, dir, scheme); await checkFinalFix(browser, dir, scheme); }
  console.log('browser checks passed: ' + checks);
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
