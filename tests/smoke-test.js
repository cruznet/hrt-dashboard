// tests/smoke-test.js — HRT Tracker pre-deploy smoke test
//
// Covers everything that's testable without a real Google OAuth login:
// the two pure-logic test suites, landing.html, and the unauthenticated
// state of index.html. Auth-gated paths (dashboard, logging, settings) are
// NOT covered here — see tests/PRE-DEPLOY-CHECKLIST.md for those.
//
// This project has no npm/build system (see CLAUDE.md), so Playwright isn't
// a local dependency. Run this via the playwright-skill's executor instead:
//
//   1. Start the local server:  python3 server.py   (serves on :3000)
//   2. cd ~/.claude/skills/playwright-skill && node run.js \
//        /path/to/hrt-dashboard/tests/smoke-test.js
//
// Set SMOKE_URL to point at a different host (e.g. a staging deploy).

const { chromium } = require('playwright');

const TARGET_URL = process.env.SMOKE_URL || 'http://localhost:3000';

let failures = 0;
const fail = (msg) => { failures++; console.log(`❌ ${msg}`); };
const pass = (msg) => console.log(`✅ ${msg}`);

async function runLogicSuite(page, path) {
  page.on('console', () => {});
  await page.goto(`${TARGET_URL}/${path}`, { waitUntil: 'load', timeout: 15000 });
  await page.waitForSelector('#results .pass, #results .fail', { timeout: 10000 }).catch(() => {});

  const failCount = await page.locator('#results .fail').count();
  const passCount = await page.locator('#results .pass').count();
  page.removeAllListeners('console');

  if (failCount > 0) {
    fail(`${path}: ${failCount} failing assertion(s) out of ${failCount + passCount}`);
    const failTexts = await page.locator('#results .fail').allTextContents();
    failTexts.slice(0, 5).forEach((t) => console.log(`   - ${t.trim()}`));
  } else if (passCount === 0) {
    fail(`${path}: no test results rendered (suite may not have run)`);
  } else {
    pass(`${path}: ${passCount} assertions passed`);
  }
}

// The local static dev server (server.py) has no /api/track handler — only the
// Cloudflare Worker does. The resulting 501 is a local-dev-only artifact, not
// a real bug, so it's filtered out here.
const isKnownLocalDevNoise = (text) => /api\/track.*501|501.*Unsupported method/i.test(text);

async function checkPageHealth(page, path, checks) {
  const consoleErrors = [];
  const handler = (m) => { if (m.type() === 'error' && !isKnownLocalDevNoise(m.text())) consoleErrors.push(m.text()); };
  page.on('console', handler);

  await page.goto(`${TARGET_URL}/${path}`, { waitUntil: 'networkidle', timeout: 15000 });
  await checks(page);

  page.off('console', handler);

  if (consoleErrors.length) {
    fail(`${path}: ${consoleErrors.length} console error(s)`);
    consoleErrors.slice(0, 5).forEach((e) => console.log(`   - ${e}`));
  } else {
    pass(`${path}: no console errors`);
  }
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  console.log(`\n— Logic test suites —`);
  await runLogicSuite(page, 'tests/protocol-logic.html');
  await runLogicSuite(page, 'tests/bloodwork-hevy-logic.html');

  console.log(`\n— landing.html —`);
  await checkPageHealth(page, 'landing.html', async (p) => {
    const title = await p.title();
    if (!title || title.trim() === '') fail('landing.html: empty <title>');
    else pass(`landing.html: title = "${title}"`);

    const ctaCount = await p.locator('a[href="/index.html"]').count();
    if (ctaCount === 0) fail('landing.html: no CTA links to /index.html found');
    else pass(`landing.html: ${ctaCount} CTA link(s) to /index.html found`);
  });

  console.log(`\n— index.html (unauthenticated) —`);
  await checkPageHealth(page, 'index.html', async (p) => {
    const overlay = p.locator('#auth-overlay');
    await overlay.waitFor({ state: 'visible', timeout: 10000 }).catch(() => {});
    const visible = await overlay.isVisible().catch(() => false);
    if (!visible) fail('index.html: #auth-overlay not visible for a signed-out user');
    else pass('index.html: #auth-overlay visible for signed-out user');

    const signInBtn = await p.locator('#auth-overlay button, #auth-overlay a').filter({ hasText: /google|sign in/i }).count();
    if (signInBtn === 0) fail('index.html: no Google sign-in control found in #auth-overlay');
    else pass('index.html: Google sign-in control present');
  });

  console.log(`\n— index.html mobile viewport (375px) —`);
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto(`${TARGET_URL}/index.html`, { waitUntil: 'networkidle', timeout: 15000 });
  const hasHScroll = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
  if (hasHScroll) fail('index.html: horizontal overflow at 375px viewport');
  else pass('index.html: no horizontal overflow at 375px viewport');

  await browser.close();

  console.log(`\n${'='.repeat(40)}`);
  if (failures > 0) {
    console.log(`❌ SMOKE TEST FAILED — ${failures} issue(s) found`);
    process.exit(1);
  } else {
    console.log(`✅ SMOKE TEST PASSED`);
    process.exit(0);
  }
})();
