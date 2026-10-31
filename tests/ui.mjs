// What the page shows, checked in a real browser (the integration test checks the server): the
// upload line at the top of a writable folder and in its subfolders, "read-only folder" in a
// read-only one, [rename] [delete] on lines inside a writable folder but never on a mounted
// folder itself; the free space on the home page; [delete selected] [move selected] for ticked
// lines of a writable folder only, and doing it; files dropped on the page uploaded (a drop
// anywhere else doing nothing), a folder dropped or picked going up whole, a picture pasted;
// what a file's name, [download] and [raw] do; the Recent link and /_recent; the pages on a
// phone. Works in a folder of its own, ui-test, made in the writable folder and removed at the
// end. Drives a Chrome already
// running with --remote-debugging-port, over the DevTools protocol (Node 24, nothing to install).
//
//   INDEXOF_PASSWORD=… CDP_PORT=9333 node tests/ui.mjs http://127.0.0.1:18099 share movies many
//   argument 1  the page's address; 2  a writable folder; 3  a read-only folder; 4  (optional) a
//   subfolder of the writable one, plain-named. INDEXOF_RW_DIR (optional): the writable folder on
//   this computer's disk, to check a hidden file was not uploaded.
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
// Pasted on the page (a screenshot): it goes up, a nameless picture named for the time it was
// pasted, (2) after a name already taken; text pasted into the search box is left alone.
await ev(`(() => { const dt = new DataTransfer(); dt.items.add(new File(['png1'], 'image.png', { type: 'image/png' })); dt.items.add(new File(['png2'], 'image.png', { type: 'image/png' })); document.body.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true })); return 1; })()`);
await sleep(4000);
const pasted = (await show(t)).lines.map(l => (l.match(/(Pasted \d{4}-\d\d-\d\d \d\d\.\d\d\.\d\d(?: \(2\))?\.png)/) || [])[1]).filter(n => n);
check(pasted.length === 2 && pasted.some(n => n.includes(' (2)')) && (await dav('GET', t + pasted[0])).status === 200, `${t}: two pictures pasted as image.png are uploaded as ${pasted.join(', ') || 'nothing'}`);
const typed = await ev(`(() => { const q = document.getElementById('q'); q.focus(); const dt = new DataTransfer(); dt.setData('text/plain', 'hello'); const e = new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }); q.dispatchEvent(e); return !e.defaultPrevented && !document.getElementById('ups'); })()`);
check(typed, `${t}: text pasted into the search box is left to the browser, nothing uploaded`);
// Upload folder: a folder picked (a/b/c.txt, a/d.txt, a/.hidden) goes up whole, without the hidden file.
const { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync } = await import('node:fs');
const { tmpdir } = await import('node:os');
const disk = mkdtempSync(tmpdir() + '/indexof-ui-');
mkdirSync(disk + '/a/b', { recursive: true });
for (const [n, c] of [['a/b/c.txt', 'c\n'], ['a/d.txt', 'd\n'], ['a/.hidden', 'h\n']]) writeFileSync(disk + '/' + n, c);
await show(t);
// (What the page said, kept across the reload that shows the files: the upload lines, the message.)
await ev(`new MutationObserver(() => { sessionStorage.ups = (document.getElementById('ups') || {}).textContent || ''; sessionStorage.said = document.getElementById('s').textContent; }).observe(document.body, { subtree: true, childList: true, characterData: true }); 1`);
const { result: { root } } = await send('DOM.getDocument', {}, sessionId);
const { result: { nodeId } } = await send('DOM.querySelector', { nodeId: root.nodeId, selector: '#fd' }, sessionId);
await send('DOM.setFileInputFiles', { nodeId, files: [disk + '/a'] }, sessionId);
await sleep(4000);
rmSync(disk, { recursive: true, force: true });
check((await dav('GET', t + 'a/b/c.txt')).status === 200 && (await dav('GET', t + 'a/d.txt')).status === 200, `${t}: Upload folder put a/b/c.txt and a/d.txt`);
// (The server never serves a hidden name, so it is looked for on its disk, when the test knows
// where that is: INDEXOF_RW_DIR, the writable folder's place here.)
const ups = await ev(`sessionStorage.ups`), rwDir = process.env.INDEXOF_RW_DIR;
check(ups.includes('a/b/c.txt') && ups.includes('a/d.txt') && !ups.includes('.hidden') && (!rwDir || !existsSync(rwDir + t.slice(rw.length + 1) + 'a/.hidden')), `${t}: Upload folder left a/.hidden out${rwDir ? ' (not on the disk)' : ''}: ${(await ev(`sessionStorage.said`) || '').trim() || '(not handed over by the browser)'}`);
// A folder dropped: read whole (fake entries, handed out two at a time as a reader may), its
// empty folder made too, the hidden file left out and counted.
await show(t);
const walked = await ev(`(async () => {
  const file = name => ({ isFile: true, isDirectory: false, name, file: ok => ok(new File([name + '\\n'], name)) });
  const dir = (name, kids) => ({ isFile: false, isDirectory: true, name, createReader: () => { let i = 0; return { readEntries: ok => { const got = kids.slice(i, i + 2); i += 2; setTimeout(() => ok(got)); } }; } });
  const tree = dir('dropped', [dir('x', [file('y.txt')]), file('z.txt'), file('.hidden'), dir('empty', []), dir('.git', [file('HEAD')])]);
  const w = await walk([tree]);
  const e = new Event('drop', { bubbles: true, cancelable: true });
  e.dataTransfer = { types: ['Files'], items: [{ kind: 'file', webkitGetAsEntry: () => tree, getAsFile: () => null }] };
  document.body.dispatchEvent(e);
  return JSON.stringify({ files: w.files.map(f => f.rel), dirs: w.dirs, hidden: w.hidden });
})()`);
check(walked === JSON.stringify({ files: ['dropped/x/y.txt', 'dropped/z.txt'], dirs: ['dropped', 'dropped/x', 'dropped/empty'], hidden: 2 }), `${t}: a dropped folder is read whole, hidden ones left out (${walked})`);
await sleep(1000);
check((await ev(`document.getElementById('s').textContent`)).includes('2 hidden left out'), `${t}: a dropped folder: the hidden ones counted on the page`);
await sleep(3000);
check((await dav('GET', t + 'dropped/x/y.txt')).status === 200 && (await dav('GET', t + 'dropped/z.txt')).status === 200 && (await dav('GET', t + 'dropped/empty/')).status === 200, `${t}: a dropped folder went up with its files and its empty folder`);
// A phone (390 px wide, Chrome's device mode): the viewport tag, no page wider than the screen,
// [rename] and [delete] tall enough for a finger and apart, a line of the listing in two (the name,
// its date and size; the links under it); on a computer, a line still one line.
const phone = on => send('Emulation.setDeviceMetricsOverride', on ? { width: 390, height: 844, deviceScaleFactor: 2, mobile: true } : { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false }, sessionId);
const visit = async url => { await send('Page.navigate', { url: base + url }, sessionId); await sleep(2500); };
const fits = () => ev(`(() => { const v = document.querySelector('meta[name=viewport]'), d = document.documentElement; return { vp: !!v && /width=device-width/.test(v.content), sw: d.scrollWidth, cw: d.clientWidth }; })()`);
// (ui-test/'s line: its [rename] and [delete], their height, the room between them.)
const tap = `(() => { const n = [...document.querySelectorAll('pre span > a')].find(a => a.textContent === 'ui-test/'), l = n && n.parentNode; if (!l) return null;
  const f = n => [...l.querySelectorAll('a')].find(a => a.textContent === n).getBoundingClientRect(), r = f('[rename]'), d = f('[delete]'), a = l.querySelector('a').getBoundingClientRect();
  return { h: Math.round(Math.min(r.height, d.height)), gap: Math.round(d.top >= r.bottom ? 99 : d.left - r.right), one: Math.abs(a.top - d.top) < 2 }; })()`;
// Recent: a link in the bar of every listing (not on its own page), to /_recent: the files last
// modified, listing lines like a folder's, [download] and [raw] on each, no upload line.
await show(t);
check(await ev(`(document.querySelector('a[href="/_recent"]') || {}).textContent === 'Recent'`), `${t}: a Recent link in the bar`);
await visit('/_recent');
const rec = await ev(`(() => { const l = [...document.querySelectorAll('#list span.r')]; return { n: l.length, dl: l.filter(s => [...s.querySelectorAll('a')].some(a => a.textContent === '[download]')).length, up: !!document.getElementById('w'), self: !!document.querySelector('a[href="/_recent"]'), count: document.getElementById('n').textContent }; })()`);
check(rec.n > 0 && rec.dl === rec.n && !rec.up && !rec.self, `/_recent: ${rec.n} lines, ${rec.dl} with [download], ${rec.count}, no upload line, no link to itself`);
await phone(true);
for (const [what, url] of [['/', '/'], [`/${rw}/`, `/${encodeURIComponent(rw)}/`], [`/${ro}/`, `/${encodeURIComponent(ro)}/`], ['the search', '/_search?q=txt&in='], ['/_recent', '/_recent'], ['/_login', '/_login']]) {
  await visit(url);
  const f = await fits();
  check(f.vp && f.sw <= f.cw, `390 px phone: ${what}: ${f.vp ? 'viewport tag' : 'NO viewport tag'}, ${f.sw} px wide in ${f.cw}`);
}
await visit(`/${encodeURIComponent(rw)}/`);
let taps = await ev(tap);
check(taps && taps.h >= 28 && taps.gap >= 12, `390 px phone: /${rw}/: [rename] and [delete] ${taps && taps.h} px tall, ${taps && taps.gap} px apart`);
// (e.pdf's line, a short name with [download] [raw] [rename] [delete]: under 2.6 times the name's line.)
await visit(`/${encodeURIComponent(rw)}/ui-test/`);
const two = await ev(`(() => { const n = [...document.querySelectorAll('pre span > a')].find(a => a.textContent === 'e.pdf'), l = n && n.parentNode; if (!l) return null;
  return { h: Math.round(l.getBoundingClientRect().height), lh: parseFloat(getComputedStyle(n).lineHeight), links: [...l.querySelectorAll('a')].slice(1).map(a => a.textContent).join(' ') }; })()`);
check(two && two.links === '[download] [raw] [rename] [delete]' && two.h < 2.6 * two.lh, `390 px phone: ${t}e.pdf: its line ${two && two.h} px tall, the name's line ${two && two.lh} px (${two && two.links})`);
await phone(false);
await visit(`/${encodeURIComponent(rw)}/`);
taps = await ev(tap);
check(taps && taps.one, `1400 px screen: /${rw}/: a line of the listing on one line`);
// (A smaller computer screen: the upload line wraps, the page never scrolls sideways.)
await send('Emulation.setDeviceMetricsOverride', { width: 1024, height: 768, deviceScaleFactor: 1, mobile: false }, sessionId);
await visit(`/${encodeURIComponent(rw)}/`);
const wide = await ev(`(() => { const w = innerWidth, over = [...document.querySelectorAll('body *')].filter(e => e.getBoundingClientRect().right > w + 1).map(e => e.tagName + (e.id ? '#' + e.id : '') + ' ' + (e.textContent || '').trim().slice(0, 30)); return [document.documentElement.scrollWidth, document.documentElement.clientWidth, over.slice(0, 3).join(' | ')]; })()`);
check(wide && wide[0] <= wide[1], `1024 px screen: /${rw}/: no sideways scroll (${wide && wide[0]} wide in ${wide && wide[1]}${wide && wide[2] ? ', over: ' + wide[2] : ''})`);
await send('Emulation.clearDeviceMetricsOverride', {}, sessionId);
await dav('DELETE', t);
ws.close();
process.exit(failed ? 1 : 0);
