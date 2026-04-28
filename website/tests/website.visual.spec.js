const { expect, test } = require('@playwright/test');
const { argosScreenshot } = require('@argos-ci/playwright');

async function capture(page, testInfo, name) {
  await page.evaluate(() => window.scrollTo(0, 0));
  await argosScreenshot(page, `${testInfo.project.name}-${name}`, {
    fullPage: true,
    ariaSnapshot: true,
  });
}

test.describe('Nazar website', () => {
  test('homepage and service catalog render', async ({ page }, testInfo) => {
    await page.goto('/');

    await expect(page.getByRole('heading', { name: 'Nazar watches the services you depend on.' })).toBeVisible();
    await expect(page.getByText('No account. No telemetry. Polls public status pages directly from your Mac.')).toBeVisible();
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
    await page.goto('/#services');
    await expect(page.locator('#catalog-list a').first()).toBeVisible();

    await page.locator('#catalog-search').fill('service-that-does-not-exist-argos-check');
    await expect(page.getByText('No services match.')).toBeVisible();
    await expect(page.locator('#catalog-empty-submit')).toBeVisible();

    await capture(page, testInfo, 'catalog-empty-state');
  });

  test('catalog service result opens its status page', async ({ page }, testInfo) => {
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
});
