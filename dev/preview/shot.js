// headless Chrome 으로 미리보기 서버 화면 캡처
// node shot.js <outDir> <width> <height> <path:name> [<path:name> ...]
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const [outDir, width, height, ...targets] = process.argv.slice(2);
const BASE = 'http://127.0.0.1:8080';
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PORT = 9333;
const profile = path.join(__dirname, 'chrome-profile');
const password = fs.readFileSync(path.join(__dirname, '.owner_password'), 'utf8').trim();

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, `--window-size=${width},${height}`, '--hide-scrollbars', '--no-first-run', 'about:blank'], { stdio: 'ignore' });
  let wsUrl;
  for (let i = 0; i < 50 && !wsUrl; i++) {
    await sleep(200);
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      wsUrl = list.find((t) => t.type === 'page')?.webSocketDebuggerUrl;
    } catch {}
  }
  const ws = new WebSocket(wsUrl);
  await new Promise((r) => ws.addEventListener('open', r));
  let id = 0;
  const pending = new Map();
  ws.addEventListener('message', (e) => {
    const msg = JSON.parse(e.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  });
  const send = (method, params = {}) => new Promise((r) => { id += 1; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
  const evaluate = async (expression) => (await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result?.result?.value;

  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: +width, height: +height, deviceScaleFactor: 1, mobile: +width < 760 });

  await send('Page.navigate', { url: `${BASE}/auth/sign_in` });
  await sleep(2500);
  const onSignIn = await evaluate("!!document.querySelector('#user_email')");
  if (onSignIn) {
    await evaluate(`(() => { document.querySelector('#user_email').value = 'owner@preview.test'; document.querySelector('#user_password').value = ${JSON.stringify(password)}; document.querySelector('form#new_user, form.new_user').submit(); })()`);
    await sleep(3500);
  }

  fs.mkdirSync(outDir, { recursive: true });
  for (const target of targets) {
    const [p, name] = target.split(':');
    await send('Page.navigate', { url: `${BASE}${p}` });
    await sleep(4500);
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(path.join(outDir, `${name}.png`), Buffer.from(shot.result.data, 'base64'));
    console.log('saved', name);
    if (process.env.PROBE) console.log(JSON.stringify(await evaluate(fs.readFileSync(process.env.PROBE, 'utf8')), null, 1));
  }
  ws.close();
  chrome.kill();
}

main().catch((e) => { console.error(e); process.exit(1); });
