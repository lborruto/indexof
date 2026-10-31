// What the page shows, checked in a real browser (the integration test checks the server): the
// upload line at the top of a writable folder and in its subfolders, "read-only folder" in a
// read-only one, [rename] [delete] on lines inside a writable folder but never on a mounted
// folder itself; the free space on the home page; [delete selected] [move selected] for ticked
// lines of a writable folder only, and doing it; files dropped on the page uploaded (a drop
// anywhere else doing nothing); [view] on a text file. Works in a folder of its own, ui-test, made
// in the writable folder and removed at the end. Drives a Chrome already running with --remote-debugging-port, over the DevTools
// protocol (Node 24, nothing to install).
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
for (const n of ['a.txt', 'b.txt', 'c.txt', 'd.txt']) await dav('PUT', t + n, n + '\n');
await show(t);
check(await ev(`document.getElementById('ws').hidden`), `${t}: no [delete selected] [move selected] before a line is ticked`);
check(await tick(['a.txt', 'b.txt']), `${t}: ticked lines offer [delete selected] [move selected]`);
const viewHref = await ev(`(() => { const a = [...document.querySelectorAll('pre span > a')].find(a => a.textContent === 'a.txt'); const v = a && [...a.parentNode.querySelectorAll('a')].find(l => l.textContent === '[view]'); return v ? v.getAttribute('href') : ''; })()`);
check(viewHref === '/_play?f=' + encodeURIComponent(t + 'a.txt'), `${t}a.txt (a text file) has [view] (${viewHref})`);
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
await dav('DELETE', t);
ws.close();
process.exit(failed ? 1 : 0);
