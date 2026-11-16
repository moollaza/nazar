const { defineConfig, devices } = require('@playwright/test');
const { createArgosReporterOptions } = require('@argos-ci/playwright/reporter');

const isCI = Boolean(process.env.CI);
const uploadToArgos = Boolean(process.env.CI && process.env.ARGOS_TOKEN);

module.exports = defineConfig({
  testDir: './website/tests',
  timeout: 30_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  forbidOnly: isCI,
  retries: isCI ? 2 : 0,
  workers: isCI ? 1 : undefined,
  reporter: [
    isCI ? ['dot'] : ['list'],
    [
      '@argos-ci/playwright/reporter',
      createArgosReporterOptions({
        uploadToArgos,
        token: process.env.ARGOS_TOKEN,
        buildName: 'website',
      }),
    ],
  ],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:4173',
    // The hero demo auto-advances on a wall-clock timer, so which state is on
    // screen when a screenshot is taken depends on how fast the assertions
    // ran — that produced a spurious Argos diff on a Python-only commit. The
    // page already pins the hero to state 0 and drops every transition under
    // `prefers-reduced-motion: reduce`; this is what asks it to. It must sit in
    // `contextOptions`: as a top-level `use` key Playwright ignores it silently,
    // which left smooth scrolling on and shifted shots by a pixel run to run.
    contextOptions: { reducedMotion: 'reduce' },
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    bypassCSP: true,
  },
  webServer: {
    command: 'python3 -m http.server 4173 --directory website',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: !isCI,
  },
  projects: [
    {
      name: 'desktop',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1440, height: 1200 },
        // 'Desktop Chrome' is 1x, which looks blurry on a Retina screen in
        // the Argos viewer. Mobile (Pixel 7) is already 2.625x.
        deviceScaleFactor: 2,
      },
    },
    {
      name: 'mobile',
      use: {
        ...devices['Pixel 7'],
        browserName: 'chromium',
      },
    },
  ],
});
