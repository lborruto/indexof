// What the page shows, checked in a real browser (the integration test checks the server): the
// upload line at the top of a writable folder and in its subfolders, "read-only folder" in a
// read-only one, [rename] [delete] on lines inside a writable folder but never on a mounted
// folder itself. Drives a Chrome already running with --remote-debugging-port, over the DevTools
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
ws.close();
process.exit(failed ? 1 : 0);
