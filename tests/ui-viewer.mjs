// The viewer (/_play), checked in a real browser: [raw] [download] [folder], previous / next with
// "n / N" and the arrow keys, a picture's line (pixels, size, and from Exif the date and the
// camera), a subtitle file next to a video in the subtitle list, text shown as text (a page as its source, an old file in
// Windows-1252, the first 1 MiB of a big one, no /_probe), a video resumed where it was left,
// "play next" moving on at the end of a sound file, and the viewer on a phone. Uses the demo
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

// Pictures: the links, "1 / 3", the right arrow to the next one and round to the first.
const pics = order(['Test Pattern.png', 'Gradient (2024).jpg', 'Beach Walk (2024).jpg']).map(n => '/pictures/' + n);
await view(pics[0]);
let s = await state();
check(s.raw === base + enc(pics[0]) && s.get === s.raw && s.download === pics[0].split('/').pop() && s.up === '/pictures/', `${pics[0]}: [raw] [download] [folder] (${s.raw}, ${s.download}, ${s.up})`);
check(s.rawTab === '_blank noopener' && s.getTab === '', `${pics[0]}: [raw] in a new tab, [download] in this one (${s.rawTab})`);
check(s.pn.includes('1 / 3') && s.next, `${pics[0]}: "1 / 3" and [next →] (${JSON.stringify(s.pn)})`);
check(!s.probe, `${pics[0]}: no /_probe for a picture`);
await key('ArrowRight');
s = await state();
check(s.f === pics[1] && s.pn.includes('2 / 3'), `ArrowRight: ${pics[1]}, "2 / 3" (got ${s.f}, ${JSON.stringify(s.pn)})`);
await key('ArrowRight');
await key('ArrowRight');
s = await state();
check(s.f === pics[0], `ArrowRight on the last picture: round to ${pics[0]} (got ${s.f})`);

// The picture's line: "W × H · size", and from a JPEG's Exif "taken YYYY-MM-DD HH:MM" and the
// camera (Model naming the maker already: "Demo Camera X1", not "Demo Demo Camera X1").
const line = async p => { await view(p); return ev(`document.getElementById('pi').hidden ? null : document.getElementById('pi').textContent`); };
let l = await line('/pictures/Beach Walk (2024).jpg');
check(/^1920 × 1080 · \d+(\.\d)? KB · taken 2024-07-14 18:32 · Demo Camera X1$/.test(l), `/pictures/Beach Walk (2024).jpg: pixels, size, date taken, camera (${JSON.stringify(l)})`);
l = await line('/pictures/Test Pattern.png');
check(/^1280 × 720 · \d+ KB$/.test(l), `/pictures/Test Pattern.png: pixels and size only (${JSON.stringify(l)})`);
l = await line('/pictures/Gradient (2024).jpg');
check(/^1280 × 720 · \d+(\.\d)? KB$/.test(l), `/pictures/Gradient (2024).jpg (no Exif): pixels and size only (${JSON.stringify(l)})`);
// The page's Exif reader itself: little-endian ("II") too, and never an exception on cut or
// damaged bytes (every length of the demo's segment, then random bytes changed).
const ex = await ev(`(() => {
  const jpeg = (le, make, model, date) => {
    const b = [], u16 = v => le ? b.push(v & 255, v >> 8) : b.push(v >> 8, v & 255), u32 = v => le ? (u16(v & 0xffff), u16(v >>> 16)) : (u16(v >>> 16), u16(v & 0xffff));
    const str = x => [...x].map(c => c.charCodeAt(0)).concat(0), pad = a => a.length % 2 ? a.concat(0) : a;
    const mk = str(make), md = str(model), dt = str(date), o1 = 50, o2 = o1 + pad(mk).length, o3 = o2 + pad(md).length, o4 = o3 + 18;
    b.push(...(le ? [0x49, 0x49] : [0x4d, 0x4d])); u16(42); u32(8);
    u16(3); u16(0x010f); u16(2); u32(mk.length); u32(o1); u16(0x0110); u16(2); u32(md.length); u32(o2); u16(0x8769); u16(4); u32(1); u32(o3); u32(0);
    b.push(...pad(mk), ...pad(md)); u16(1); u16(0x9003); u16(2); u32(dt.length); u32(o4); u32(0); b.push(...dt);
    const app = [0x45, 0x78, 0x69, 0x66, 0, 0, ...b], n = app.length + 2;
    return new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 4, 0, 0, 0xff, 0xe1, n >> 8, n & 255, ...app, 0xff, 0xda, 0, 2]);
  };
  const le = exif(jpeg(true, 'Maker', 'Phone 9', '2023:01:02 03:04:05').buffer), g = jpeg(false, 'A', 'B', '2024:01:01 00:00:00');
  let bad = 0;
  for (let i = 0; i <= g.length; i++) { try { exif(g.slice(0, i).buffer); } catch (e) { bad++; } }
  for (let k = 0; k < 3000; k++) { const c = g.slice(); for (let j = 0; j < 4; j++) c[Math.floor(Math.random() * c.length)] = Math.random() * 256; try { exif(c.buffer); } catch (e) { bad++; } }
  return { le, bad };
})()`);
check(ex.le.camera === 'Maker Phone 9' && ex.le.date === '2023-01-02 03:04' && ex.bad === 0, `Exif reader: little-endian read, no exception on cut or damaged bytes (${JSON.stringify(ex)})`);

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
