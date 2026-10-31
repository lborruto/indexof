// What the page shows, checked in a real browser (the integration test checks the server): the
// upload line at the top of a writable folder and in its subfolders, "read-only folder" in a
// read-only one, [rename] [delete] on lines inside a writable folder but never on a mounted
// folder itself; the free space on the home page; [delete selected] [move selected] for ticked
// lines of a writable folder only, and doing it; files dropped on the page uploaded (a drop
// anywhere else doing nothing); what a file's name, [download] and [raw] do; the pages on a phone. Works in a folder of
// its own, ui-test, made in the writable folder and removed at the end. Drives a Chrome already
// running with --remote-debugging-port, over the DevTools protocol (Node 24, nothing to install).
//
//   INDEXOF_PASSWORD=… CDP_PORT=9333 node tests/ui.mjs http://127.0.0.1:18099 share movies many
//   argument 1  the page's address; 2  a writable folder; 3  a read-only folder; 4  (optional) a
//   subfolder of the writable one, plain-named.
const [base, rw, ro, sub] = process.argv.slice(2);
process.on('unhandledRejection', e => { console.log('FAIL  page: ' + (e && e.message || e)); process.exit(1); });
const password = process.env.INDEXOF_PASSWORD, port = process.env.CDP_PORT || '9222';
if (!base || !rw || !ro || !password) { console.error('usage: INDEXOF_PASSWORD=… node tests/ui.mjs BASE RW_FOLDER RO_FOLDER'); process.exit(2); }
const sleep = ms => new Promise(r => setTimeout(r, ms));
const { webSocketDebuggerUrl } = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
const ws = new WebSocket(webSocketDebuggerUrl);
await new Promise((ok, ko) => { ws.onopen = ok; ws.onerror = ko; });
let id = 0; const waiting = new Map();
ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id && waiting.has(d.id)) { waiting.get(d.id)(d); waiting.delete(d.id); } };
const send = (method, params = {}, sessionId) => new Promise(r => { const i = ++id; waiting.set(i, r); ws.send(JSON.stringify({ id: i, method, params, sessionId })); });
const { result: { targetId } } = await send('Target.createTarget', { url: 'about:blank' });
const { result: { sessionId } } = await send('Target.attachToTarget', { targetId, flatten: true });
await send('Network.enable', {}, sessionId);
await send('Network.setCookie', { name: 'session', value: encodeURIComponent(password), url: base, path: '/' }, sessionId);
const show = async path => {
  await send('Page.navigate', { url: base + path.split('/').map(encodeURIComponent).join('/') }, sessionId);
  await sleep(2500);
  const r = await send('Runtime.evaluate', { expression: `JSON.stringify({ w: document.getElementById('w').hidden ? null : document.getElementById('w').textContent, upload: !!document.querySelector('#w button'), lines: [...document.querySelectorAll('pre span')].filter(s => s.querySelector('a')).map(s => s.textContent) })`, returnByValue: true }, sessionId);
  return JSON.parse(r.result.result.value);
};
// The page's own state (the line under the listing), an expression evaluated in it.
const ev = async expr => { const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }, sessionId); return r.result.result.value; };
// The server, straight (to make the test's files and look at what the page did).
const dav = (method, path, body, headers = {}) => fetch(base + path.split('/').map(encodeURIComponent).join('/'), { method, body, headers: { Cookie: 'session=' + encodeURIComponent(password), ...headers } });
// Tick the lines whose names are given (clicking the box, as a person would).
const tick = names => ev(`(${JSON.stringify(names)}).forEach(n => { const a = [...document.querySelectorAll('pre span > a')].find(a => a.textContent === n); if (a) a.parentNode.querySelector('input[type=checkbox]').click(); }); !document.getElementById('ws').hidden`);
let failed = 0;
const check = (cond, what) => { console.log((cond ? 'ok    ' : 'FAIL  ') + 'page: ' + what); if (!cond) failed++; };
const top = await show(`/${rw}/`);
check(top.upload, `/${rw}/ (the top of a writable folder) shows the upload line`);
check(top.lines.some(l => l.includes('[rename]')), `/${rw}/ offers [rename] on its lines`);
if (sub) { const s = await show(`/${rw}/${sub}/`); check(s.upload, `/${rw}/${sub}/ (a subfolder) shows the upload line`); }
const readOnly = await show(`/${ro}/`);
check(!readOnly.upload && readOnly.w === 'read-only folder', `/${ro}/ (read-only) says "read-only folder", no upload`);
check(!readOnly.lines.some(l => l.includes('[rename]') || l.includes('[delete]')), `/${ro}/ offers no [rename] or [delete]`);
const home = await show('/');
const mountLine = home.lines.find(l => l.trim().startsWith(rw + '/')) || '';
check(mountLine && !mountLine.includes('[rename]') && !mountLine.includes('[delete]'), `/ never offers [rename] or [delete] on the mounted folder ${rw}/`);
const space = await ev(`document.getElementById('d').textContent`);
check(/ free \/ /.test(space), `/ shows the free space (${space})`);
// (Dropped on the home page: nothing, and the browser does not leave the page for the file.)
const drop = `(() => { const dt = new DataTransfer(); dt.items.add(new File(['dropped\\n'], 'dropped.txt', { type: 'text/plain' })); return !document.body.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true })); })()`;
check(await ev(drop) && !(await ev(`!!document.getElementById('ups')`)), '/ (the home page): a drop does nothing, and is kept from the browser');
await show(`/${ro}/`);
check(await ev(drop) && !(await ev(`!!document.getElementById('ups')`)), `/${ro}/ (read-only): a drop does nothing, and is kept from the browser`);
const roNames = await ev(`[...document.querySelectorAll('pre span > a')].map(a => a.textContent).filter(n => n !== '../').slice(0, 2)`);
check(roNames.length === 2 && !(await tick(roNames)), `/${ro}/: ticked lines offer no [delete selected] [move selected]`);

const t = `/${rw}/ui-test/`;
await dav('MKCOL', t);
for (const n of ['a.txt', 'b.txt', 'c.txt', 'd.txt', 'e.pdf', 'f.bin']) await dav('PUT', t + n, n + '\n');
await dav('MKCOL', t + 'sub/');
await show(t);
check(await ev(`document.getElementById('ws').hidden`), `${t}: no [delete selected] [move selected] before a line is ticked`);
check(await tick(['a.txt', 'b.txt']), `${t}: ticked lines offer [delete selected] [move selected]`);
// A file's name: the viewer for what it shows (a text file here), the browser for a PDF, else a
// download; [download] (downloads) and [raw] (opens) on every file; a folder's name opens it.
const line = n => `(() => { const a = [...document.querySelectorAll('pre span > a')].find(a => a.textContent === ${JSON.stringify(n)}); if (!a) return null; const l = t => [...a.parentNode.querySelectorAll('a')].find(x => x.textContent === t); const d = l('[download]'), r = l('[raw]'); const tab = x => x ? (x.getAttribute('target') || '') + ' ' + (x.getAttribute('rel') || '') : ''; return { href: a.getAttribute('href'), dl: a.hasAttribute('download'), tab: tab(a), dtab: tab(d), rtab: tab(r), d: d ? d.getAttribute('href') + ' ' + d.hasAttribute('download') : '', r: r ? r.getAttribute('href') + ' ' + r.hasAttribute('download') : '', view: !!(l('[view]') || l('[play]')) }; })()`;
const txt = await ev(line('a.txt')), pdf = await ev(line('e.pdf')), bin = await ev(line('f.bin')), dir = await ev(line('sub/'));
check(txt && txt.href === '/_play?f=' + encodeURIComponent(t + 'a.txt') && !txt.dl, `${t}a.txt: its name opens the viewer (${txt && txt.href})`);
check(txt && txt.d === encodeURI(t + 'a.txt') + ' true' && txt.r === encodeURI(t + 'a.txt') + ' false' && !txt.view, `${t}a.txt: [download] downloads, [raw] opens, no [view] (${txt && txt.d}; ${txt && txt.r})`);
check(pdf && pdf.href === 'e.pdf' && !pdf.dl, `${t}e.pdf: its name opens it in the browser (${pdf && pdf.href})`);
// A PDF's name and every [raw] open in a new tab; the viewer's links and [download] stay in this one.
check(pdf && pdf.tab === '_blank noopener' && pdf.rtab === '_blank noopener', `${t}e.pdf: its name and [raw] open in a new tab (${pdf && pdf.tab}; ${pdf && pdf.rtab})`);
check(txt && txt.tab === ' ' && txt.dtab === ' ' && txt.rtab === '_blank noopener', `${t}a.txt: its name and [download] in this tab, [raw] in a new one (${JSON.stringify(txt && [txt.tab, txt.dtab, txt.rtab])})`);
check(bin && bin.href === 'f.bin' && bin.dl && bin.d === encodeURI(t + 'f.bin') + ' true', `${t}f.bin (no preview): its name downloads it`);
check(dir && dir.href === 'sub/' && !dir.dl && !dir.d, `${t}sub/: a folder's name opens the folder, no [download]`);
// Delete selected: one confirm, naming the count, then gone.
await ev(`window.confirm = q => { sessionStorage.asked = q; return true; }; document.getElementById('ds').click(); 1`);
await sleep(2500);
const asked = await ev(`sessionStorage.asked`);
check(asked === 'Delete 2 items?', `${t}: [delete selected] asks once: ${asked}`);
check((await dav('GET', t + 'a.txt')).status === 404 && (await dav('GET', t + 'b.txt')).status === 404, `${t}: [delete selected] removed a.txt and b.txt`);
const after = await show(t);
check(!after.lines.some(l => / [ab]\.txt/.test(l)) && after.lines.some(l => l.includes('c.txt')), `${t}: the listing, reloaded, has no a.txt and b.txt, still c.txt`);
// Move selected: into a folder of the same writable folder (made, as it is missing).
await tick(['c.txt', 'd.txt']);
await ev(`window.prompt = () => ${JSON.stringify(t + 'into')}; document.getElementById('ms').click(); 1`);
await sleep(2500);
check((await dav('GET', t + 'into/c.txt')).status === 200 && (await dav('GET', t + 'into/d.txt')).status === 200 && (await dav('GET', t + 'c.txt')).status === 404, `${t}: [move selected] moved c.txt and d.txt into ${t}into/`);
await show(t);
await ev(`window.prompt = () => '/${ro}'; document.querySelector('pre span input[type=checkbox]').click(); document.getElementById('ms').click(); 1`);
await sleep(500);
check((await ev(`document.getElementById('s').textContent`)).includes(`stays inside /${rw}/`), `${t}: [move selected] to /${ro} refused: stays inside /${rw}/`);
// Drag and drop: a file dropped on the page goes up, and the listing (reloaded) shows it.
await show(t);
await ev(drop);
await sleep(4000);
const dropped = await show(t);
check(dropped.lines.some(l => l.includes('dropped.txt')) && (await (await dav('GET', t + 'dropped.txt')).text()) === 'dropped\n', `${t}: a file dropped on the page is uploaded and listed`);
// A phone (390 px wide, Chrome's device mode): the viewport tag, no page wider than the screen,
// [rename] and [delete] tall enough for a finger and apart; on a computer, a line still one line.
const phone = on => send('Emulation.setDeviceMetricsOverride', on ? { width: 390, height: 844, deviceScaleFactor: 2, mobile: true } : { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false }, sessionId);
const visit = async url => { await send('Page.navigate', { url: base + url }, sessionId); await sleep(2500); };
const fits = () => ev(`(() => { const v = document.querySelector('meta[name=viewport]'), d = document.documentElement; return { vp: !!v && /width=device-width/.test(v.content), sw: d.scrollWidth, cw: d.clientWidth }; })()`);
// (ui-test/'s line: its [rename] and [delete], their height, the room between them.)
const tap = `(() => { const n = [...document.querySelectorAll('pre span > a')].find(a => a.textContent === 'ui-test/'), l = n && n.parentNode; if (!l) return null;
  const f = n => [...l.querySelectorAll('a')].find(a => a.textContent === n).getBoundingClientRect(), r = f('[rename]'), d = f('[delete]'), a = l.querySelector('a').getBoundingClientRect();
  return { h: Math.round(Math.min(r.height, d.height)), gap: Math.round(d.top >= r.bottom ? 99 : d.left - r.right), one: Math.abs(a.top - d.top) < 2 }; })()`;
await phone(true);
for (const [what, url] of [['/', '/'], [`/${rw}/`, `/${encodeURIComponent(rw)}/`], [`/${ro}/`, `/${encodeURIComponent(ro)}/`], ['the search', '/_search?q=txt&in='], ['/_login', '/_login']]) {
  await visit(url);
  const f = await fits();
  check(f.vp && f.sw <= f.cw, `390 px phone: ${what}: ${f.vp ? 'viewport tag' : 'NO viewport tag'}, ${f.sw} px wide in ${f.cw}`);
}
await visit(`/${encodeURIComponent(rw)}/`);
let taps = await ev(tap);
check(taps && taps.h >= 32 && taps.gap >= 16, `390 px phone: /${rw}/: [rename] and [delete] ${taps && taps.h} px tall, ${taps && taps.gap} px apart`);
await phone(false);
await visit(`/${encodeURIComponent(rw)}/`);
taps = await ev(tap);
check(taps && taps.one, `1400 px screen: /${rw}/: a line of the listing on one line`);
await send('Emulation.clearDeviceMetricsOverride', {}, sessionId);
await dav('DELETE', t);
ws.close();
process.exit(failed ? 1 : 0);
