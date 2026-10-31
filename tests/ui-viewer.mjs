// The viewer (/_play), checked in a real browser: [raw] [download] [folder], previous / next with
// "n / N" and the arrow keys, no line under a picture, a subtitle file next to a video in the
// subtitle list, text shown as text (a page as its source, an old file in Windows-1252, the first
// 1 MiB of a big one, no /_probe), a video resumed where it was left, "play next" moving on at
// the end of a sound file, the version in the corner, and the viewer on a phone. Uses the demo
// data's pictures/, music/ and movies/ (tests/make-demo.sh) and a folder of text files given
// here. Drives a Chrome already running with --remote-debugging-port, over the DevTools protocol
// (Node 24, nothing to install).
//
//   INDEXOF_PASSWORD=… CDP_PORT=9333 node tests/ui-viewer.mjs http://127.0.0.1:18099 'My Stuff/text'
//   argument 1  the page's address; 2  a folder holding readme.txt, page.html (with <b>),
//   old.nfo (Windows-1252, "Café crème") and big.log (more than 1 MiB).
const [base, text] = process.argv.slice(2);
process.on('unhandledRejection', e => { console.log('FAIL  viewer: ' + (e && e.message || e)); process.exit(1); });
const password = process.env.INDEXOF_PASSWORD, port = process.env.CDP_PORT || '9222';
if (!base || !text || !password) { console.error('usage: INDEXOF_PASSWORD=… node tests/ui-viewer.mjs BASE TEXT_FOLDER'); process.exit(2); }
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

const enc = p => p.split('/').map(encodeURIComponent).join('/');
const order = names => names.sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }));
const ev = async (expression, gesture = false) => {
  const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true, userGesture: gesture }, sessionId);
  if (r.result.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description || 'evaluate failed');
  return r.result.result.value;
};
const go = async (url, wait = 2500) => { await send('Page.navigate', { url }, sessionId); await sleep(wait); };
const view = (path, wait) => go(base + '/_play?f=' + encodeURIComponent(path), wait);
const key = async k => {
  for (const type of ['keyDown', 'keyUp']) await send('Input.dispatchKeyEvent', { type, key: k, code: k, windowsVirtualKeyCode: k === 'ArrowRight' ? 39 : 37 }, sessionId);
  await sleep(2500);
};
// What the page shows: the file it is on, the links, the counter, the text, the player.
const state = () => ev(`(() => {
  const $ = id => document.getElementById(id), v = [$('v'), $('au')].find(x => !x.hidden);
  return { f: new URLSearchParams(location.search).get('f'), raw: $('raw').href, rawTab: $('raw').target + ' ' + $('raw').rel, getTab: $('get').target, get: $('get').href, download: $('get').getAttribute('download'),
    up: $('up').getAttribute('href'), pn: $('pn').textContent, next: !![...$('pn').querySelectorAll('a')].find(a => a.textContent.includes('next')),
    tx: $('tx').hidden ? null : $('tx').textContent, txElements: $('tx').children.length, m: $('m').textContent,
    rs: $('rs').hidden ? null : $('rs').textContent, auto: $('pl2').hidden ? null : $('auto').checked,
    t: v ? v.currentTime : null, paused: v ? v.paused : null,
    probe: performance.getEntriesByType('resource').some(e => e.name.includes('/_probe')) };
})()`);
let failed = 0;
const check = (cond, what) => { console.log((cond ? 'ok    ' : 'FAIL  ') + 'viewer: ' + what); if (!cond) failed++; };

// Pictures: the links, "1 / 2", the right arrow to the next one and round to the first.
const pics = order(['Test Pattern.png', 'Gradient (2024).jpg']).map(n => '/pictures/' + n);
await view(pics[0]);
let s = await state();
check(s.raw === base + enc(pics[0]) && s.get === s.raw && s.download === pics[0].split('/').pop() && s.up === '/pictures/', `${pics[0]}: [raw] [download] [folder] (${s.raw}, ${s.download}, ${s.up})`);
check(s.rawTab === '_blank noopener' && s.getTab === '', `${pics[0]}: [raw] in a new tab, [download] in this one (${s.rawTab})`);
check(s.pn.includes('1 / 2') && s.next, `${pics[0]}: "1 / 2" and [next →] (${JSON.stringify(s.pn)})`);
check(!s.probe, `${pics[0]}: no /_probe for a picture`);
await key('ArrowRight');
s = await state();
check(s.f === pics[1] && s.pn.includes('2 / 2'), `ArrowRight: ${pics[1]}, "2 / 2" (got ${s.f}, ${JSON.stringify(s.pn)})`);
await key('ArrowRight');
s = await state();
check(s.f === pics[0], `ArrowRight on the last picture: round to ${pics[0]} (got ${s.f})`);

// No line under a picture (its details are gone): after it, the text view (hidden here). The
// version in the corner, on the right, linking to the project (a test build, not a release).
const under = await ev(`(() => { const im = document.getElementById('im'), n = im.nextElementSibling, v = document.getElementById('ver'); return { next: n && n.id, ver: v && v.textContent, href: v && v.getAttribute('href'), right: v && Math.round(innerWidth - v.getBoundingClientRect().right) }; })()`);
check(under.next === 'tx' && !(await ev(`!!document.getElementById('pi')`)), `${pics[0]}: no line under the picture (${JSON.stringify(under.next)} after it)`);
check(under.ver === 'indexof test' && under.href === 'https://github.com/lborruto/indexof' && under.right < 20, `${pics[0]}: "${under.ver}" in the bottom right corner, linking to ${under.href}`);

// A subtitle file next to a video: in the list after the file's own tracks ("fr (file)" for
// Short (2023).fr.srt), and chosen, a track of the player's with its cues.
const short = '/movies/Short (2023).mp4';
await view(short, 3000);
const opts = await ev(`[...document.getElementById('s').options].map(o => o.textContent)`);
check(JSON.stringify(opts) === '["off","fr (file)"]', `${short}: the subtitle list is off, fr (file) (${JSON.stringify(opts)})`);
await ev(`(() => { const s = document.getElementById('s'); s.value = [...s.options].find(o => o.textContent === 'fr (file)').value; s.dispatchEvent(new Event('change')); return 1; })()`);
await sleep(2000);
const tt = await ev(`(() => { const t = [...document.getElementById('v').textTracks].map(t => ({ mode: t.mode, cues: t.cues ? t.cues.length : -1, first: t.cues && t.cues.length ? [t.cues[0].startTime, t.cues[0].text] : null })); return { t, n: document.getElementById('n').textContent }; })()`);
check(tt.t.length === 1 && tt.t[0].mode === 'showing' && tt.t[0].cues === 2 && tt.t[0].first[0] === 1 && /^Un fichier/.test(tt.t[0].first[1]), `${short}: fr (file) chosen, a track showing its 2 cues (${JSON.stringify(tt)})`);
const mkvOpts = await (async () => { await view('/movies/Big Buck Test (2024)/Big Buck Test (2024).mkv', 3000); return ev(`[...document.getElementById('s').options].map(o => o.textContent)`); })();
check(JSON.stringify(mkvOpts) === '["off","fre Français (subrip)","eng English (subrip)"]', `the mkv (no file next to it): its own tracks only (${JSON.stringify(mkvOpts)})`);

// Text: as text, a page as its source, Windows-1252 when it is not UTF-8, the first 1 MiB only.
const texts = order(['readme.txt', 'page.html', 'old.nfo', 'big.log']), at = n => `/${text}/${n}`;
await view(at('readme.txt'));
s = await state();
check(s.tx === 'Plain text for the viewer.\n', `${at('readme.txt')}: its text (${JSON.stringify(s.tx)})`);
check(s.pn.includes(`${texts.indexOf('readme.txt') + 1} / ${texts.length}`), `${at('readme.txt')}: "${texts.indexOf('readme.txt') + 1} / ${texts.length}" (${JSON.stringify(s.pn)})`);
check(!s.probe && s.t === null, `${at('readme.txt')}: no player, no /_probe`);
await view(at('page.html'));
s = await state();
check(s.tx && s.tx.includes('<b>shown as source</b>') && s.txElements === 0, `${at('page.html')}: shown as source, <b> as text (${JSON.stringify(s.tx)})`);
await view(at('old.nfo'));
s = await state();
check(s.tx === 'Café crème\n', `${at('old.nfo')}: Windows-1252, the byte E9 as é (${JSON.stringify(s.tx)})`);
await view(at('big.log'));
s = await state();
check(s.tx && s.tx.length === 1048576 && s.tx.startsWith('line 00001') && s.m.includes('first 1 MiB shown') && s.m.includes('[raw]'), `${at('big.log')}: the first 1 MiB, "first 1 MiB shown — [raw]" (${s.tx && s.tx.length} characters, ${JSON.stringify(s.m)})`);

// Resume: a saved position of 40 s on a 2:30 video, used at load, "resumed at 0:40", then
// [start over] back to 0 and forgotten.
const long = '/movies/Long Take (2022).mp4', posKey = 'indexof:pos:' + long;
await go(base + '/movies/', 1000); // (the same origin, for its localStorage)
await ev(`localStorage.setItem(${JSON.stringify(posKey)}, JSON.stringify({ t: 40, at: Date.now() })), 1`);
await view(long, 3000);
s = await state();
check(Math.abs(s.t - 40) < 5 && s.rs && s.rs.startsWith('resumed at 0:40 — [start over]'), `${long}: resumed at 40 s (currentTime ${s.t}, ${JSON.stringify(s.rs)})`);
await ev(`document.querySelector('#rs a').click(), 1`);
await sleep(1000);
s = await state();
const left = await ev(`localStorage.getItem(${JSON.stringify(posKey)})`);
check(s.t < 5 && s.rs === null && left === null, `${long}: [start over] goes back to 0 and forgets (currentTime ${s.t}, saved ${left})`);

// Play next: near the end of the first sound file of music/, the page moves on to the second
// (no wrap for sound: the last one stops).
const songs = order(['Demo Song.mp3', 'Démo (lossless).flac']).map(n => '/music/' + n);
await view(songs[0]);
s = await state();
check(s.auto === true && s.pn.includes('1 / 2'), `${songs[0]}: "play next" on by default, "1 / 2" (${s.auto}, ${JSON.stringify(s.pn)})`);
await ev(`(() => { const v = document.getElementById('au'); v.currentTime = Math.max(0, v.duration - 1.5); return v.play().then(() => 1, () => 0); })()`, true);
await sleep(5000);
s = await state();
check(s.f === songs[1], `the end of ${songs[0]}: on to ${songs[1]} (got ${s.f})`);
check(s.pn.includes('2 / 2') && !s.next, `${songs[1]}: "2 / 2", no [next →] (no wrap for sound) (${JSON.stringify(s.pn)})`);
console.log(`note  viewer: ${songs[1]} ${s.paused ? 'waits for play (this browser blocks autoplay)' : 'plays by itself'}`);

// A phone (390 px wide, Chrome's device mode): the viewport tag, and no page wider than the screen.
await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: true }, sessionId);
for (const p of [long, short, pics[0], at('readme.txt'), at('big.log')]) {
  await view(p);
  const f = await ev(`(() => { const v = document.querySelector('meta[name=viewport]'), d = document.documentElement; return { vp: !!v && /width=device-width/.test(v.content), sw: d.scrollWidth, cw: d.clientWidth }; })()`);
  check(f.vp && f.sw <= f.cw, `390 px phone: ${p}: ${f.vp ? 'viewport tag' : 'NO viewport tag'}, ${f.sw} px wide in ${f.cw}`);
}
await send('Emulation.clearDeviceMetricsOverride', {}, sessionId);

ws.close();
process.exit(failed ? 1 : 0);
