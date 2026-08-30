const path = require('path');
const { expect, test } = require('@playwright/test');
const { argosScreenshot } = require('@argos-ci/playwright');

// Visual tests run against a FROZEN catalog fixture so catalog-content PRs
// (adding/removing services) don't trip Argos: the page renders the service
// count (#catalog-total), the "Showing X of all Y" footer, the search
// placeholder, and the first 60 alphabetical grid items from catalog.json —
// all of which change pixels on every catalog addition.
// Regenerate the fixture only on intentional website redesigns:
//   cp Resources/catalog.json website/tests/fixture-catalog.json
const FIXTURE = path.join(__dirname, 'fixture-catalog.json');

async function freezeCatalog(page) {
  await page.route('**/catalog.json', (route) =>
    route.fulfill({ path: FIXTURE, contentType: 'application/json' }),
  );
}

async function capture(page, testInfo, name) {
  await page.evaluate(() => window.scrollTo(0, 0));
  await argosScreenshot(page, `${testInfo.project.name}-${name}`, {
    fullPage: true,
    ariaSnapshot: true,
  });
}


test.describe('Nazar website', () => {
  test('homepage and service catalog render', async ({ page }, testInfo) => {
    await freezeCatalog(page);
    await page.goto('/');

    await expect(page.getByRole('heading', { name: 'Nazar watches the services you depend on.' })).toBeVisible();
    await expect(page.getByText('No account. No app telemetry. Polls public status pages directly from your Mac.')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Find the services you rely on' })).toBeVisible();
    await expect(page.getByText('Failed to load catalog')).toHaveCount(0);
    await expect(page.locator('#catalog-list a').first()).toBeVisible();
    const initialCatalogCount = testInfo.project.name === 'mobile' ? 12 : 60;
    await expect(page.locator('#catalog-list a')).toHaveCount(initialCatalogCount);
    await expect(page.locator('#catalog-showing')).toContainText(`Showing ${initialCatalogCount} of all`);
    await expect(page.locator('#catalog-more')).toBeVisible();

    await capture(page, testInfo, 'homepage');
  });

  test('catalog search empty state renders', async ({ page }, testInfo) => {
    await freezeCatalog(page);
    await page.goto('/#services');
    await expect(page.locator('#catalog-list a').first()).toBeVisible();

    await page.locator('#catalog-search').fill('service-that-does-not-exist-argos-check');
    await expect(page.getByText('No services match.')).toBeVisible();
    await expect(page.locator('#catalog-empty-submit')).toBeVisible();

    await capture(page, testInfo, 'catalog-empty-state');
  });

  test('catalog service result opens its status page', async ({ page }, testInfo) => {
    await freezeCatalog(page);
    await page.goto('/#services');
    await expect(page.locator('#catalog-list a').first()).toBeVisible();

    await page.locator('#catalog-search').fill('GitHub');
    const github = page.locator('#catalog-list a', { hasText: 'GitHub' }).first();
    await expect(github).toBeVisible();
    await expect(github).toHaveAttribute('href', 'https://www.githubstatus.com');

    await capture(page, testInfo, 'catalog-service-result');

    const [popup] = await Promise.all([
      page.waitForEvent('popup'),
      github.click(),
    ]);
    await expect(popup).toHaveURL('https://www.githubstatus.com/');
    await popup.close();
  });

  test('real catalog loads and renders (no screenshot — data coverage, growth-proof)', async ({ page }, testInfo) => {
    // No freezeCatalog() here: this test exercises the REAL catalog.json so
    // catalog-content PRs are still functionally covered. It takes no Argos
    // screenshot, so catalog growth can never trip the visual check.
    await page.goto('/');
    await expect(page.locator('#catalog-list a').first()).toBeVisible();
    await expect(page.getByText('Failed to load catalog')).toHaveCount(0);
    const initialCatalogCount = testInfo.project.name === 'mobile' ? 12 : 60;
    await expect(page.locator('#catalog-list a')).toHaveCount(initialCatalogCount);
    await expect(page.locator('#catalog-showing')).toContainText('of all');
    await expect(page.locator('#catalog-total')).toHaveText(/^\d[\d,]*$/);

    await page.locator('#catalog-search').fill('GitHub');
    const github = page.locator('#catalog-list a', { hasText: 'GitHub' }).first();
    await expect(github).toBeVisible();
  });
});
