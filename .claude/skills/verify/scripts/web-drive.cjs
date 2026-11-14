#!/usr/bin/env node
// Drive the website like a user and save proof. Run `web.sh up` first.
//
//   node .claude/skills/verify/scripts/web-drive.cjs <name> <path> [step ...] [--mobile]
//
// Selectors are Playwright selectors: CSS plus :has-text("...").
// Steps run in order. Each fails the run (exit 1) if it does not hold.
//   see:<text>                   text is visible
//   gone:<text>                  text is not on the page
//   fill:<selector>=<value>      type into a field (selector is CSS)
//   click:<selector>             click an element
//   attr:<selector>@<name>=<v>   first match has attribute name equal to v (waits up to 10s)
//   count:<selector>=<n>         selector matches exactly n elements (waits up to 10s)
//   shot:<label>                 screenshot + ARIA snapshot now
//
// Evidence goes to .verify/evidence/<run>/web-<name>-*.{png,aria.yml} and a
// web-<name>.log with every step and its result.
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

let chromium, devices;
try { ({ chromium, devices } = require('@playwright/test')); } catch { ({ chromium, devices } = require('playwright')); }

const root = execSync('git rev-parse --show-toplevel', { cwd: __dirname }).toString().trim();
const runDir = path.join(root, '.verify', 'run');
const runId = fs.existsSync(path.join(runDir, 'run_id'))
  ? fs.readFileSync(path.join(runDir, 'run_id'), 'utf8').trim()
  : new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
const outDir = path.join(root, '.verify', 'evidence', runId);
fs.mkdirSync(outDir, { recursive: true });

const argv = process.argv.slice(2);
const mobile = argv.includes('--mobile');
const [name, urlPath, ...steps] = argv.filter((a) => a !== '--mobile');
if (!name || !urlPath) { console.error('usage: web-drive.cjs <name> <path> [step ...] [--mobile]'); process.exit(2); }
const base = fs.existsSync(path.join(runDir, 'web.url')) ? fs.readFileSync(path.join(runDir, 'web.url'), 'utf8').trim() : null;
if (!base) { console.error('no server; run web.sh up'); process.exit(2); }

const logLines = [];
const log = (s) => { console.log(s); logLines.push(s); };

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext(mobile ? { ...devices['Pixel 7'] } : { viewport: { width: 1440, height: 1200 } });
  // Keep verification runs out of the production analytics (PostHog, Fathom).
  const analytics = /usefathom\.com|z\.usenazar\.com|posthog\.com/;
  await context.route(analytics, (r) => r.abort());
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  // A blocked Tailwind CDN still passes text checks but renders an unstyled
  // page with every hidden state visible. That is not what users see, so it
  // fails the run. Analytics requests are aborted on purpose, above.
  page.on('requestfailed', (r) => {
    if (!analytics.test(r.url())) errors.push(`request failed: ${r.url()} (${r.failure()?.errorText})`);
  });
  let n = 0;
  const prefix = `web-${name}${mobile ? '-mobile' : ''}`;
  const shot = async (label) => {
    const file = path.join(outDir, `${prefix}-${String(++n).padStart(2, '0')}-${label}`);
    await page.screenshot({ path: `${file}.png`, fullPage: false });
    fs.writeFileSync(`${file}.aria.yml`, await page.locator('body').ariaSnapshot());
    log(`  saved ${file}.png + .aria.yml`);
  };
  let failed = false;
  try {
    await page.goto(base + urlPath, { waitUntil: 'networkidle' });
    log(`open ${base + urlPath}`);
    for (const step of steps) {
      const i = step.indexOf(':');
      const op = step.slice(0, i); const arg = step.slice(i + 1);
      if (op === 'see') await page.getByText(arg).first().waitFor({ state: 'visible', timeout: 10_000 });
      else if (op === 'gone') { if (await page.getByText(arg).count()) throw new Error(`"${arg}" is on the page`); }
      else if (op === 'fill') { const [sel, ...v] = arg.split('='); await page.locator(sel).fill(v.join('=')); }
      else if (op === 'click') await page.locator(arg).first().click();
      else if (op === 'attr') {
        const [lhs, want] = [arg.slice(0, arg.lastIndexOf('=')), arg.slice(arg.lastIndexOf('=') + 1)];
        const [sel, attr] = lhs.split('@');
        const deadline = Date.now() + 10_000; let got;
        while ((got = await page.locator(sel).first().getAttribute(attr).catch(() => null)) !== want && Date.now() < deadline) await page.waitForTimeout(100);
        if (got !== want) throw new Error(`${sel}@${attr} is ${got}, want ${want}`);
      } else if (op === 'count') {
        const [sel, want] = [arg.slice(0, arg.lastIndexOf('=')), Number(arg.slice(arg.lastIndexOf('=') + 1))];
        const deadline = Date.now() + 10_000; let got;
        while ((got = await page.locator(sel).count()) !== want && Date.now() < deadline) await page.waitForTimeout(100);
        if (got !== want) throw new Error(`${sel} matches ${got}, want ${want}`);
      } else if (op === 'shot') await shot(arg);
      else throw new Error(`unknown step ${step}`);
      log(`ok   ${step}`);
    }
    if (errors.length) throw new Error(`page errors: ${errors.join(' | ')}`);
  } catch (e) {
    failed = true;
    log(`FAIL ${e.message.split('\n')[0]}`);
    await shot('failure').catch(() => {});
  } finally {
    fs.writeFileSync(path.join(outDir, `${prefix}.log`), logLines.join('\n') + '\n');
    await browser.close();
  }
  process.exit(failed ? 1 : 0);
})();
