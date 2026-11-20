import { spawn } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';

const root = process.cwd().replaceAll('\\', '/');
const worktree = root;
const out = `${root}/tests/evidence/successor-ui`;
const edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const port = 9337;
mkdirSync(out, { recursive: true });

const css = readFileSync(`${worktree}/skills/openai/factory/assets/dashboard.css`, 'utf8');
const script = readFileSync(`${worktree}/skills/openai/factory/assets/dashboard.js`, 'utf8');
const html = readFileSync(`${worktree}/skills/openai/factory/assets/dashboard.html`, 'utf8');
const longReport = '<script>alert(1)</script> & literal sample text\n' + Array.from({length: 180}, (_, i) => 'Sample report line ' + i + ': keyboard scrolling evidence.').join('\n') + '\nLATER-CONTENT-MARKER';
const rows = [
  {
    id: 'sample-ready-' + 'long-identifier-'.repeat(5),
    stage: 'ready',
    round: '1',
    limit: '3',
    runner: 'codex',
    blocker: null,
    pr_url: 'https://github.com/example/armoury/pull/1',
    artifacts: { 'builder.md': longReport, 'resolved-blocker.md': 'Sample resolved blocker retained in history.' }
  },
  {
    id: 'sample-needs-human-' + 'long-identifier-'.repeat(5),
    stage: 'needs-human',
    round: '2',
    limit: '3',
    runner: 'codex',
    blocker: 'Sample blocker: ' + 'A long blocker explains the missing prerequisite and the action needed to resolve it. '.repeat(6),
    pr_url: '',
    artifacts: {}
  }
];
function page(data) {
  return html
    .replace('__FACTORY_STYLE__', css)
    .replace('__FACTORY_DATA__', JSON.stringify(data).replaceAll('<', '\\u003c'))
    .replace('__FACTORY_SCRIPT__', script);
}
writeFileSync(`${out}/populated.html`, page(rows));
writeFileSync(`${out}/empty.html`, page([]));

const profile = `${out}/edge-profile`;
mkdirSync(profile, { recursive: true });
const child = spawn(edge, [
  '--headless=new',
  `--remote-debugging-port=${port}`,
  `--user-data-dir=${profile}`,
  '--disable-gpu',
  '--no-first-run',
  'about:blank'
], { stdio: 'ignore' });

function die(error) {
  child.kill();
  throw error;
}
await delay(800);
let version;
for (let i = 0; i < 20; i++) {
  try {
    version = await fetch(`http://127.0.0.1:${port}/json/version`).then((response) => response.json());
    break;
  } catch {
    await delay(200);
  }
}
if (!version) die(new Error('Edge debugging port did not open'));

let id = 0;
const pending = new Map();
const ws = new WebSocket(version.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  ws.addEventListener('open', resolve);
  ws.addEventListener('error', reject);
});
ws.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
  }
});
function send(method, params = {}, sessionId) {
  const messageId = ++id;
  return new Promise((resolve, reject) => {
    pending.set(messageId, { resolve, reject });
    ws.send(JSON.stringify({ id: messageId, method, params, sessionId }));
  });
}
const target = await send('Target.createTarget', { url: 'about:blank' });
const session = await send('Target.attachToTarget', { targetId: target.targetId, flatten: true });
const sessionId = session.sessionId;
async function evaluate(expression) {
  const result = await send('Runtime.evaluate', { expression, returnByValue: true }, sessionId);
  return result.result.value;
}
async function shot(name) {
  const image = await send('Page.captureScreenshot', { format: 'png' }, sessionId);
  writeFileSync(path.join(out, name), Buffer.from(image.data, 'base64'));
}
async function key(keyName, code, windowsVirtualKeyCode, text) {
  const down = { type: 'keyDown', key: keyName, code, windowsVirtualKeyCode, nativeVirtualKeyCode: windowsVirtualKeyCode };
  if (text) down.text = text;
  await send('Input.dispatchKeyEvent', down, sessionId);
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: keyName, code, windowsVirtualKeyCode, nativeVirtualKeyCode: windowsVirtualKeyCode }, sessionId);
}
async function open(file) {
  const url = `file:///${file.replaceAll('\\', '/')}`;
  await send('Page.navigate', { url }, sessionId);
  await delay(300);
}
await send('Page.enable', {}, sessionId);
await send('Runtime.enable', {}, sessionId);
await send('Emulation.setFocusEmulationEnabled', { enabled: true }, sessionId);
await send('Target.activateTarget', { targetId: target.targetId });
const log = { browser: version.Browser, source: 'Working tree assets, no builder commit permitted', runs: [] };
function assert(value, message) { if (!value) throw new Error(message); }
async function active() { return evaluate('({id: document.activeElement.id, text: document.activeElement.textContent, focusVisible: document.activeElement.matches(":focus-visible")})'); }
async function state() { return evaluate('({open: document.querySelector("#artifact").open, heading: document.querySelector("#report-heading").textContent, scrollTop: document.querySelector("#report").scrollTop, scrollHeight: document.querySelector("#report").scrollHeight, clientHeight: document.querySelector("#report").clientHeight, active: document.activeElement.id})'); }
for (const [name, width] of [['desktop', 1280], ['narrow', 500]]) {
  await send('Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile: false }, sessionId);
  const run = { width, height: 900, tabs: [], keys: [] }; log.runs.push(run);
  await open(`${out}/empty.html`); await shot(`${name}-empty.png`);
  await open(`${out}/populated.html`); await shot(`${name}-populated.png`);
  for (let i = 0; i < 12; i++) {
    await key('Tab', 'Tab', 9); run.tabs.push(await active());
    if (run.tabs.at(-1).text === 'builder.md') break;
  }
  assert(run.tabs.at(-1).text === 'builder.md', 'Report button unreachable');
  await shot(`${name}-focus-report.png`);
  await key('Enter', 'Enter', 13, '\r'); await delay(200);
  run.opened = await state(); run.closeFocus = await active();
  assert(run.opened.open && run.closeFocus.id === 'close', 'Dialog did not autofocus Close');
  await shot(`${name}-dialog.png`);
  await key('Tab', 'Tab', 9); run.reportFocus = await active();
  assert(run.reportFocus.id === 'report', 'Report cannot receive keyboard focus');
  run.beforeScroll = await state();
  assert(run.beforeScroll.scrollHeight > run.beforeScroll.clientHeight, 'Report does not overflow');
  assert(run.beforeScroll.scrollTop === 0, 'Later marker must start hidden');
  await shot(`${name}-report-start.png`);
  for (let i = 0; i < 30; i++) {
    await key('PageDown', 'PageDown', 34); await delay(80);
    const position = await state(); run.keys.push({ key: 'PageDown', ...position });
    if (position.scrollTop + position.clientHeight >= position.scrollHeight - 1) break;
  }
  run.afterScroll = await state();
  assert(run.afterScroll.scrollTop > 0 && run.afterScroll.scrollTop + run.afterScroll.clientHeight >= run.afterScroll.scrollHeight - 1, 'Keyboard did not reach later marker');
  await shot(`${name}-later-content.png`);
  // Native dialog Tab wraps back to its Close control.
  await key('Tab', 'Tab', 9); await key('Tab', 'Tab', 9);
  run.reachableClose = await active();
  if (run.reachableClose.id !== 'close') { await key('Tab', 'Tab', 9); run.reachableClose = await active(); }
  assert(run.reachableClose.id === 'close', 'Close unreachable after scrolling');
  await shot(`${name}-close-after-scroll.png`);
  await key('Escape', 'Escape', 27); await delay(200);
  run.escape = { ...await state(), ...await active() };
  assert(!run.escape.open && run.escape.text === 'builder.md' && run.escape.focusVisible, 'Escape focus return failed');
  await shot(`${name}-escape-focus-return.png`);
  await key('Enter', 'Enter', 13, '\r'); await delay(100);
  await key('Enter', 'Enter', 13, '\r'); await delay(200);
  run.close = { ...await state(), ...await active() };
  assert(!run.close.open && run.close.text === 'builder.md' && run.close.focusVisible, 'Close focus return failed');
  await shot(`${name}-close-focus-return.png`);
  await key('Enter', 'Enter', 13, '\r'); await delay(100);
  run.literal = await evaluate('document.querySelector("#report").textContent.includes("<script>alert(1)</script>")');
  await evaluate('document.body.dataset.stayed = "yes"; document.querySelector("#refresh").click()');
  await delay(3000);
  run.refreshBlocked = await evaluate('document.querySelector("#artifact").open && document.body.dataset.stayed === "yes"');
  assert(run.literal && run.refreshBlocked, 'Literal display or dialog refresh behavior failed');
  await key('Escape', 'Escape', 27); await delay(100);
  await evaluate('scrollTo(0, 100); document.querySelector("#refresh").click()'); await delay(400);
  run.explicitRefresh = await evaluate('({active: document.activeElement.id, scrollY, reloaded: !document.body.dataset.stayed})');
  assert(run.explicitRefresh.reloaded && run.explicitRefresh.active === 'refresh', 'Explicit refresh focus failed');
}
writeFileSync(`${out}/keyboard-log.json`, JSON.stringify(log, null, 2));
console.log(JSON.stringify(log));
child.kill(); ws.close(); process.exit(0);
