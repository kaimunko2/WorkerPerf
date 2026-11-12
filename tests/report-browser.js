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

async function checkEvents(browser, dir, scheme) {                 // Ereignisse, Abstuerze, Drucken
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  const ev = D.incidents.filter((i) => i.type === 'ereignis');
  ok(ev.length === 4 && await page.locator('#incidents .incident.type-ereignis').count() === ev.length, 'Ereignisvorfaelle in der Liste');
  ok(await page.locator('#timeline .mark.type-ereignis').count() === ev.length, 'Ereignisvorfaelle in der Zeitleiste');
  for (const g of ['app', 'session', 'security', 'profile']) ok(await page.locator(`#timeline .tl-row[data-group="${g}"] .event`).count() === D.events.filter((e) => e.group === g).length, 'Ereigniszeile ' + g);
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
  const ev = D.incidents.filter((i) => i.type === 'ereignis');
  ok((await page.locator('#findHead').innerText()).includes('4 Vorfälle aus Ereignissen'), 'Kopfsatz nennt die Vorfaelle aus Ereignissen');
  const outlook = ev.find((i) => i.event.app === 'OUTLOOK.EXE'), entry = await openIncident(page, outlook.id);
  ok((await entry.locator('.badge').innerText()).includes('kritisch') && (await entry.locator('.text').innerText()) === outlook.text, 'Ereignisvorfall: Satz und Schwere als Wort');
  ok(await entry.locator('.detail .patterns li').count() === outlook.event.patterns.length, 'eine Zeile je Muster');
  ok(await entry.locator('.detail .evlist tbody tr').count() === outlook.events.length, 'Ereignisse des Vorfalls');
  ok((await entry.locator('.detail .evlist').innerText()).includes(evHms(outlook.events[0])), 'Zeit des Ereignisses in seiner Ortszeit');
  const head = await entry.locator('.detail .kv').innerText();
  ok(head.includes('olmapi32.dll') && head.includes('user010') && head.includes('3'), 'Kopfzeile mit Modul, Benutzern und Anzahl');
  ok((await page.locator(`#timeline .mark[data-incident="${outlook.id}"]`).getAttribute('aria-label')).includes('Absturz'), 'Markierung mit dem Wort der Art');
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
  ok((await page.locator('#before .day').first().innerText()).includes('07.11.2026') && (await page.locator('#before .day').first().innerText()).includes('2'), 'Balken mit Datum und Zahl');
  const nexus = D.before.incidents.find((i) => i.event.app === 'nexus.exe');
  const be = page.locator(`#before .incident[data-id="${nexus.id}"]`);
  await be.locator('.text').click();
  ok((await be.locator('.detail .patterns').innerText()).includes('spricht für Profil oder Daten dieses Benutzers'), 'Muster im Rueckblick');
  ok((await be.locator('.detail .evlist').innerText()).includes('09.11.2026'), 'Rueckblick-Ereignisse mit Datum');
  ok(await be.locator('.detail .zoomto').count() === 0, 'kein Zoom fuer die Zeit vor der Messung');
  // events table and timeline rows
  ok((await page.locator('#tlLegend').innerText()).includes('Anwendungen') && (await page.locator('#tlLegend').innerText()).includes('Sitzungen'), 'Legende nennt die Gruppen');
  ok((await page.locator('#timeline .tl-row[data-group="app"] .tl-label').innerText()) === 'Anwendungen', 'Zeile mit dem Wort der Gruppe');
  ok(await page.locator('#eventsOutsideCut').count() === 0, 'ohne Ausschnitt kein Hinweis');
  ok(!(await page.locator('#quality').innerText()).includes('unvollständig'), 'ohne Obergrenze kein Hinweis');
  ok(page.errors.length === 0, 'Skriptfehler: ' + page.errors.join(' | '));
  await page.close();

  // without event files: the report without a finding stays as it was
  const n = await open(browser, path.join(dir, 'report-none.html'), scheme);
  ok(await n.page.locator('#timeline .event').count() === 0 && await n.page.locator('#timeline .tl-row[data-group]').count() === 0, 'ohne Ereignisse keine Ereigniszeilen');
  // changed in fix round 1 (I1), and again in fix round 2 (N2): without events_before.csv the card says that the file is
  // missing; the sources of this capture were available
  ok((await n.page.locator('#before').innerText()).includes('Für die Tage vor der Messung liegt keine Ereignisdatei vor (events_before.csv fehlt).') && await n.page.locator('.type-ereignis').count() === 0, 'ohne Ereignisdatei: Datei fehlt, keine Ereignisvorfaelle');
  ok((await n.page.locator('#findHead').innerText()) === 'Keine Vorfälle im Messzeitraum.' && await n.page.locator('#eventList').isHidden(), 'Kopfsatz und Ereignisliste wie bisher');
  ok(n.page.errors.length === 0, 'Skriptfehler ohne Ereignisse: ' + n.page.errors.join(' | '));
  await n.page.close();

  // a time cut names the events it leaves out
  const c = await open(browser, path.join(dir, 'report-nodata.html'), scheme);
  ok(c.D.eventsOutsideCut > 0 && (await c.page.locator('#eventsOutsideCut').innerText()).includes(c.D.eventsOutsideCut + ' Ereignisse der Aufzeichnung liegen außerhalb'), 'Hinweis auf Ereignisse ausserhalb des Ausschnitts');
  await c.page.close();

  // states changed in the data: markup in server texts, a possibly involved driver, a restarted spooler, a capped lookback,
  // unreadable rows of the event files, a cut event list, events near a reported time before the capture
  const bad = '<img src=x onerror="window.__xss=1">';
  const v = await open(browser, patched(dir, 'report.html', 'report-events-variant.html', (J) => {
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
  ok(await v.page.evaluate(() => window.__xss === undefined) && await v.page.locator('#tab-findings img').count() === 0, 'Markup aus den Daten wird nicht ausgefuehrt');
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
  const c = await open(browser, path.join(dir, 'report-cutrep.html'), scheme);
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
    ['off', (J) => { empty(J); J.before.status = 'off'; J.before.days = 0; }, 'Der Rückblick war abgeschaltet (-EventLookbackDays 0).'],
    ['unavailable', (J) => { empty(J); J.before.status = 'unavailable'; }, 'Für die Tage vor der Messung wurden keine Ereignisse gelesen: die Ereignisquellen waren nicht verfügbar.'],
    ['read', (J) => { empty(J); J.before.status = 'read'; }, 'In den 7 Tagen vor der Messung stehen keine Ereignisse der erfassten Arten in den Protokollen.']];
  for (const [name, change, text] of cases) {
    const p = await open(browser, patched(dir, 'report.html', `report-lb-${name}.html`, (J) => { change(J); J.meta.focus = Object.assign({}, J.meta.focus, { reportedMs: J.before.captureStart - 3600000 }); }), scheme);
    t = await bt(p.page);
    ok(t.includes(text), 'Rueckblick ' + name + ': ' + t.split('\n').slice(0, 3).join(' / '));
    ok(!t.includes('Ereignisse aus diesen Tagen') && !t.includes('Vorfälle vor der Messung') && await p.page.locator('#before .day').count() === 0, 'Rueckblick ' + name + ' ohne Zahlen, Balken und Vorfallsliste');
    ok(!t.includes('Ereignisse um die gemeldete Uhrzeit'), 'Rueckblick ' + name + ': keine leere Liste um die gemeldete Zeit');
    ok(p.page.errors.length === 0, 'Skriptfehler Rueckblick ' + name + ': ' + p.page.errors.join(' | '));
    await p.page.close();
  }
  const f2 = await open(browser, patched(dir, 'report.html', 'report-lb-fmt2.html', (J) => { empty(J); J.before.status = 'notRecorded'; J.before.days = 0; }), scheme);
  ok(await f2.page.locator('#before').isHidden(), 'Format 2 ohne Rueckblick: keine Karte');
  await f2.page.close();
  // M1, M3, M4, M5 on the simulated hour
  const { page, D } = await open(browser, path.join(dir, 'report.html'), scheme);
  for (const inc of D.incidents.filter((i) => i.type === 'ereignis' && i.start === i.end)) {
    const box = await page.locator(`#timeline .mark[data-incident="${inc.id}"]`).boundingBox();
    ok(box.width <= 13, 'Zeitpunkt-Vorfall nicht als Zeitspanne gezeichnet: ' + box.width);
    ok((await page.locator(`#timeline .mark-word[data-incident="${inc.id}"]`).innerText()).length > 0, 'Wort neben der Markierung');
  }
  ok((await page.locator('#tlLegend').innerText()).includes('Ortszeit des Ereignisses'), 'Legende: Tooltip in der Ortszeit des Ereignisses');
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
  const many = await open(browser, patched(dir, 'report.html', 'report-many.html', (J) => {
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
  const pe = await open(browser, patched(dir, 'report.html', 'report-lb-partial.html', (J) => {
    Object.assign(J.before, { eventCount: 0, incidentEventCount: 0, perDay: [], incidents: [], near: [], nearCapture: [], capped: [], status: 'partial', logs: partLogs(J) });
  }), scheme);
  let t = await bt(pe.page);
  ok(t.includes('Gelesen: Ereignisprotokoll Microsoft Defender, Ereignisprotokolle AppLocker.') && t.includes('Nicht gelesen: Ereignisprotokoll Anwendung, Ereignisprotokoll System, Ereignisprotokoll Druckdienst, Ereignisprotokoll SMB-Client, Ereignisprotokoll Benutzerprofildienst.'), 'teilweiser Rueckblick nennt gelesene und nicht gelesene Protokolle: ' + t);
  ok(t.includes('In den gelesenen Protokollen stehen für die 7 Tage vor der Messung keine Ereignisse der erfassten Arten.') && !t.includes('Arten in den Protokollen'), 'teilweiser Rueckblick ohne Ereignisse: keine Aussage ueber alle Protokolle');
  ok(pe.page.errors.length === 0, 'Skriptfehler teilweiser Rueckblick: ' + pe.page.errors.join(' | '));
  await pe.page.close();
  const pv = await open(browser, patched(dir, 'report.html', 'report-lb-partial-events.html', (J) => { J.before.status = 'partial'; J.before.logs = partLogs(J); }), scheme);
  t = await bt(pv.page);
  ok(t.includes('Nicht gelesen: Ereignisprotokoll Anwendung') && t.includes('Ereignisse aus diesen Tagen') && await pv.page.locator('#before .day').count() === pv.D.before.perDay.length && await pv.page.locator('#before .incident').count() === pv.D.before.incidents.length, 'teilweiser Rueckblick mit Ereignissen: Zahlen, Balken, Vorfaelle und nicht gelesene Protokolle');
  ok(!t.includes('keine Ereignisse der erfassten Arten'), 'teilweiser Rueckblick mit Ereignissen ohne Leer-Aussage');
  await pv.page.close();
  const full = await open(browser, path.join(dir, 'report.html'), scheme);
  ok(!(await bt(full.page)).includes('Nicht gelesen'), 'vollstaendig gelesener Rueckblick ohne Liste nicht gelesener Protokolle');
  await full.page.close();
  // N3: a reported time after a -To cut but inside the capture
  const tc = await open(browser, patched(dir, 'report-nodata.html', 'report-tocut.html', (J) => {
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
  });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, colorScheme: scheme });
  page.errors = []; page.on('pageerror', (e) => page.errors.push(e.message));
  await page.goto('file://' + file);
  const D = await page.evaluate(() => JSON.parse(document.getElementById('wp-data').textContent));
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
  const m = await open(browser, path.join(dir, 'report-masked.html'), scheme);
  ok(await m.page.locator('#maskInfo').count() === 1, 'Hinweis vorhanden');
  ok((await m.page.locator('#maskInfo').innerText()).includes('Maskiert: alle Namen'), 'Stufe im Kopf');
  // the whole text of the page, hidden tabs and sections included; the embedded data are checked by the Pester test
  const all = await m.page.evaluate(() => { const b = document.body.cloneNode(true); b.querySelectorAll('script').forEach((x) => x.remove()); return b.textContent; });
  ok(all.length > 10000 && !all.match(/user0\d\d|SIM-VDA01|CONTOSO/), 'keine Namen auf der Seite');
  ok(m.page.errors.length === 0, 'Skriptfehler maskiert: ' + m.page.errors.join(' | '));
  await m.page.close();
  // the note is text in the header next to the subtitle; the symbol is hidden from screen readers
  const p = await open(browser, path.join(dir, 'report-masked.html'), scheme);
  ok(await p.page.locator('header #maskInfo').count() === 1 && await p.page.locator('#maskInfo [aria-hidden="true"]').count() === 1, 'Hinweis im Kopf, Symbol fuer Vorleser verborgen');
  ok((await p.page.locator('#maskInfo').innerText()).includes('Maskiert: alle Namen (Benutzer, Clients, Server, Freigaben, Domänen, Adressen, Drucker ersetzt)'), 'Text der Stufe Alles');
  const col = await p.page.evaluate(() => [getComputedStyle(document.getElementById('maskInfo')).color, getComputedStyle(document.body).color]);
  ok(col[0] === col[1], 'Hinweis in der Textfarbe des Schemas: ' + col.join(' / '));
  await p.page.emulateMedia({ media: 'print' });
  ok(await p.page.locator('#maskInfo').isVisible(), 'Hinweis bleibt im Druck');
  await p.page.close();
  // the other level, an unknown value: the page never looks unmasked; markup in the value stays text
  const pers = await open(browser, patched(dir, 'report-masked.html', 'report-mask-personen.html', (J) => { J.meta.mask = 'Personen'; }), scheme);
  ok((await pers.page.locator('#maskInfo').innerText()).includes('Maskiert: Personen (Benutzer und Clients ersetzt)'), 'Text der Stufe Personen');
  await pers.page.close();
  const bad = '<img src=x onerror="window.__xss=1">';
  const unk = await open(browser, patched(dir, 'report-masked.html', 'report-mask-unknown.html', (J) => { J.meta.mask = 'Neu ' + bad; }), scheme);
  ok((await unk.page.locator('#maskInfo').innerText()).includes('Maskiert: Neu ' + bad), 'unbekannte Stufe zeigt den Wert');
  ok(await unk.page.evaluate(() => window.__xss === undefined) && await unk.page.locator('header img').count() === 0, 'Stufe als Text, nicht als Markup');
  ok(unk.page.errors.length === 0, 'Skriptfehler unbekannte Stufe: ' + unk.page.errors.join(' | '));
  await unk.page.close();
}

async function checkMaskedPersonen(browser, dir, scheme) {         // Maskierung: ein echter Bericht der Stufe Personen
  const { page, D } = await open(browser, path.join(dir, 'report-masked-personen.html'), scheme);
  ok(D.meta.mask === 'Personen' && (await page.locator('#maskInfo').innerText()).includes('Maskiert: Personen (Benutzer und Clients ersetzt)'), 'Personen: Stufe im Kopf');
  const focus = await page.locator('#focusInfo').innerText();
  ok(focus.includes('(Name entfernt)') && focus.includes('nicht gefunden') && !/schmidt|unbekannt|KLINIK/i.test(focus), 'Personen: unbekannter gemeldeter Benutzer ohne Namen: ' + focus);
  const all = await page.evaluate(() => { const b = document.body.cloneNode(true); b.querySelectorAll('script').forEach((x) => x.remove()); return b.textContent; });
  ok(all.length > 10000 && !/user0\d\d|WS-\d{4}|schmidt|KLINIK/.test(all), 'Personen: keine Benutzer und Clients auf der Seite');
  ok(all.includes('SIM-VDA01') && all.includes('Benutzer 01'), 'Personen: Server bleibt, Ersatznamen stehen');
  // removed message texts say so, without a dangling colon
  const titles = await page.locator('#timeline .event').evaluateAll((els) => els.map((e) => e.getAttribute('title')));
  ok(titles.length > 0 && titles.every((t) => t.endsWith(': Meldung entfernt (maskiert)')), 'Personen: Ereignisse ohne Meldungstext sagen es');
  ok(page.errors.length === 0, 'Skriptfehler Personen: ' + page.errors.join(' | '));
  await page.close();
  // the events in the window of a performance incident (the simulated hour has none there: one masked event is put in)
  const win = await open(browser, patched(dir, 'report-masked-personen.html', 'report-mask-window.html', (J) => {
    J.incidents.find((i) => i.lead === 'cpu').events = [J.events.find((e) => e.text === '')];
  }), scheme);
  const cpu = win.D.incidents.find((i) => i.lead === 'cpu');
  await openIncident(win.page, cpu.id);
  const li = await win.page.locator(`#incidents .incident[data-id="${cpu.id}"] .detail ul.plain li`).allInnerTexts();
  ok(li.some((t) => t.endsWith(': Meldung entfernt (maskiert)')) && !li.some((t) => /:\s*$/.test(t)), 'Personen: Ereignisse im Fenster ohne leeren Doppelpunkt');
  ok(win.page.errors.length === 0, 'Skriptfehler Ereignisse im Fenster: ' + win.page.errors.join(' | '));
  await win.page.close();
  // a capture that ended on an error and a failed source call, both with their message removed by the masking
  const err = await open(browser, patched(dir, 'report-masked-personen.html', 'report-mask-errors.html', (J) => {
    J.meta.endReason = 'error'; J.meta.endMessage = ''; J.quality.sourceErrors = [{ source: 'proc.info', label: 'Prozessdaten', count: 2, firstMs: null, firstMessage: '' }];
  }), scheme);
  ok((await err.page.locator('#subtitle').innerText()).includes('Aufzeichnung mit Fehler beendet: Meldung entfernt (maskiert)'), 'Personen: Endemeldung entfernt');
  ok((await err.page.locator('#sourceErrors').evaluate((e) => e.textContent)).includes(': Meldung entfernt (maskiert)'), 'Personen: Fehlermeldung der Abfrage entfernt');
  ok(err.page.errors.length === 0, 'Skriptfehler entfernte Meldungen: ' + err.page.errors.join(' | '));
  await err.page.close();
  const plain = await open(browser, path.join(dir, 'report.html'), scheme);
  const plainText = await plain.page.evaluate(() => { const b = document.body.cloneNode(true); b.querySelectorAll('script').forEach((x) => x.remove()); return b.textContent + [...b.querySelectorAll('[title]')].map((e) => e.title).join(' '); });
  ok(!plainText.includes('Meldung entfernt'), 'unmaskiert: kein Hinweis auf entfernte Meldungen');
  await plain.page.close();
}

async function checkMaskedPage(browser, dir, scheme) {             // Maskierung: der ganze Bericht bleibt bedienbar (ein Schema genuegt)
  const { page, D } = await open(browser, path.join(dir, 'report-masked.html'), scheme);
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
  const w = await n.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
  ok(w[0] <= w[1], 'maskierter Kopf schmal ohne seitliches Rollen: ' + w.join(' > '));
  const box = await n.locator('#maskInfo').boundingBox();
  ok(box && box.x >= 0 && box.x + box.width <= 390, 'Hinweis passt in die schmale Ansicht');
  ok(n.errors.length === 0, 'Skriptfehler maskiert schmal: ' + n.errors.join(' | '));
  await n.close();
}

(async () => {
  const dir = path.resolve(process.argv[2]);
  const browser = await chromium.launch();
  for (const scheme of ['light', 'dark']) {
    await checkPage(browser, dir, scheme); await checkFindings(browser, dir, scheme); await checkFinalFix(browser, dir, scheme);
    await checkEvents(browser, dir, scheme); await checkEventDetails(browser, dir, scheme); await checkNarrow(browser, dir, scheme);
    await checkFix1(browser, dir, scheme); await checkFix2(browser, dir, scheme); await checkLongNames(browser, dir, scheme);
    await checkMask(browser, dir, scheme); await checkMaskedPersonen(browser, dir, scheme);
  }
  await checkMaskedPage(browser, dir, 'light');
  console.log('browser checks passed: ' + checks);
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
