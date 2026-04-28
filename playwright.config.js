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
