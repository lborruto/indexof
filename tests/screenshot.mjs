#!/usr/bin/env node
// The README's screenshots, taken from a running indexof on the demo data (tests/make-demo.sh):
// the listing of a folder and the player, 1400×900 each, as PNG in docs/screenshots/. Never
// point it at a real install: the pictures end up in the public repository.
//
// It drives a Chrome that is already running with remote debugging on, over the DevTools
// protocol, with nothing to install (Node 24: fetch, WebSocket and import.meta.dirname are
// built in). Start Chrome headless on a throwaway profile first (Chrome refuses remote
// debugging on its usual profile):
//
//   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
//     --remote-debugging-port=9222 --user-data-dir="$(mktemp -d)" \
//     --autoplay-policy=no-user-gesture-required about:blank &
//   (Linux: google-chrome or chromium with the same flags.)
//
// Then, with the demo stack up (the README's "Just looking?"):
//
//   INDEXOF_PASSWORD=… node tests/screenshot.mjs http://127.0.0.1:8098 "/movies/Amélie (2001)/Amélie.mkv"
//
//   argument 1  the page's address, as in the browser (scheme, host, port, no path);
//   argument 2  a video under one of the mounted folders, for the player: its path as the page
//               shows it, starting with the folder's name (spaces and symbols as they are).
//   INDEXOF_PASSWORD  the stack's password (the script logs in by setting the session cookie);
//   CDP_PORT          Chrome's debugging port (9222);
//   SETTLE            milliseconds to wait after a page has loaded, for the folder sizes and
//                     the player's track list to fill in (3000);
//   SCALE             device pixels per CSS pixel: 2 for a crisper picture (1).
//
// The PNGs are not committed (see .gitignore): convert them to WebP with cwebp, as the script
// prints at the end, and commit the .webp files the README links to.
import { mkdir, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const [base, video] = process.argv.slice(2);
const password = process.env.INDEXOF_PASSWORD;
if (!base || !video || !password || !/^https?:\/\/[^/]+$/.test(base) || !video.startsWith('/')) {
  console.error('usage: INDEXOF_PASSWORD=… node tests/screenshot.mjs http://host:port "/folder/a video.mkv"');
  process.exit(2);
}
const port = process.env.CDP_PORT || '9222';
const settle = Number(process.env.SETTLE) || 3000;
const scale = Number(process.env.SCALE) || 1;
const outDir = path.join(import.meta.dirname, '..', 'docs', 'screenshots');
const sleep = ms => new Promise(r => setTimeout(r, ms));
setTimeout(() => { console.error('screenshot: timed out after 90 s'); process.exit(1); }, 90_000).unref();

// A minimal DevTools client: one command at a time by id, events to whoever waits for them.
class Cdp {
  constructor(ws) { this.ws = ws; this.id = 0; this.pending = new Map(); this.waiting = []; ws.onmessage = e => this.receive(JSON.parse(e.data)); }
  send(method, params = {}, sessionId) {
    return new Promise((resolve, reject) => {
      const id = ++this.id;
      this.pending.set(id, { resolve, reject, method });
      this.ws.send(JSON.stringify({ id, method, params, sessionId }));
    });
  }
  receive(m) {
    if (m.id) {
      const p = this.pending.get(m.id); this.pending.delete(m.id);
      if (m.error) p.reject(new Error(`${p.method}: ${m.error.message}`)); else p.resolve(m.result);
      return;
    }
    this.waiting = this.waiting.filter(w => !(w.method === m.method && w.sessionId === m.sessionId && (w.resolve(m.params), true)));
  }
  once(method, sessionId) { return new Promise(resolve => this.waiting.push({ method, sessionId, resolve })); }
}

const connect = async () => {
  const r = await fetch(`http://127.0.0.1:${port}/json/version`).catch(() => null);
  if (!r || !r.ok) { console.error(`screenshot: no Chrome with --remote-debugging-port=${port} on 127.0.0.1 (see the top of this file)`); process.exit(1); }
  const { webSocketDebuggerUrl } = await r.json();
  const ws = new WebSocket(webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = () => reject(new Error('WebSocket to Chrome failed')); });
  return new Cdp(ws);
};

// One page: load it, let it settle, and (for the player) play the video muted for a moment so
// a frame is on screen (muted autoplay is always allowed), then capture the viewport.
const shoot = async (cdp, sessionId, url, file, player) => {
  const loaded = cdp.once('Page.loadEventFired', sessionId);
  await cdp.send('Page.navigate', { url }, sessionId);
  await loaded;
  if (player) {
    await cdp.send('Runtime.evaluate', {
      awaitPromise: true,
      expression: `(async () => {
        const v = document.querySelector('video'); if (!v) return 'no video on the page';
        v.muted = true; await v.play().catch(() => {}); await new Promise(r => setTimeout(r, 1500)); v.pause(); return 'ok';
      })()`,
    }, sessionId).then(r => { if (r.result.value !== 'ok') console.error(`player: ${r.result.value}`); });
  }
  await sleep(settle);
  const { data } = await cdp.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }, sessionId);
  await writeFile(file, Buffer.from(data, 'base64'));
  console.log(`wrote ${path.relative(process.cwd(), file)}  (${url})`);
};

const cdp = await connect();
const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
try {
  await cdp.send('Page.enable', {}, sessionId);
  await cdp.send('Network.enable', {}, sessionId);
  await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 900, deviceScaleFactor: scale, mobile: false }, sessionId);
  // Logged in, as login.html does it: the password in the session cookie (30 days, SameSite=Strict).
  await cdp.send('Network.setCookie', { name: 'session', value: encodeURIComponent(password), url: base, path: '/', sameSite: 'Strict' }, sessionId);
  await mkdir(outDir, { recursive: true });
  const folder = video.slice(0, video.indexOf('/', 1) + 1); // the first folder of the video's path
  await shoot(cdp, sessionId, base + folder.split('/').map(encodeURIComponent).join('/'), path.join(outDir, 'listing.png'), false);
  await shoot(cdp, sessionId, `${base}/_play?f=${encodeURIComponent(video)}`, path.join(outDir, 'player.png'), true);
} finally {
  await cdp.send('Target.closeTarget', { targetId }).catch(() => {});
  cdp.ws.close();
}

// To WebP (what the README links to): cwebp from libwebp, when it is installed.
let cwebp = true;
try { execFileSync('cwebp', ['-version'], { stdio: 'ignore' }); } catch { cwebp = false; }
const rel = path.relative(process.cwd(), outDir);
console.log(cwebp
  ? `Now convert them:\n  for f in listing player; do cwebp -q 85 "${rel}/$f.png" -o "${rel}/$f.webp"; done`
  : `Convert them to WebP with cwebp (brew install webp / apt install webp):\n  for f in listing player; do cwebp -q 85 "${rel}/$f.png" -o "${rel}/$f.webp"; done`);
