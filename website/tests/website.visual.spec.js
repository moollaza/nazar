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

    await expect(page.getByRole('heading', { name: 'Know when the services you rely on go down.' })).toBeVisible();
    await expect(page.getByText('No accounts. Open-Source. Requires macOS 14.6 or later.')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Browse the list of supported services' })).toBeVisible();
    // Guards the copy pass: no unverifiable claims may return to the page.
    await expect(page.getByText('No app telemetry')).toHaveCount(0);
    await expect(page.getByText('proxy server')).toHaveCount(0);
    await expect(page.getByText('Failed to load catalog')).toHaveCount(0);
    await expect(page.locator('#catalog-list a').first()).toBeVisible();
    const initialCatalogCount = testInfo.project.name === 'mobile' ? 12 : 30;
    await expect(page.locator('#catalog-list a')).toHaveCount(initialCatalogCount);
    await expect(page.locator('#catalog-showing')).toContainText(`Showing ${initialCatalogCount} of `);
    await expect(page.locator('#catalog-pager')).toBeVisible();
    await expect(page.locator('#catalog-prev')).toBeDisabled();
    await expect(page.locator('#catalog-next')).toBeEnabled();

    await capture(page, testInfo, 'homepage');
  });

  test('FAQ structured data matches the visible copy', async ({ page }) => {
    await page.goto('/');
    const blocks = await page.locator('script[type="application/ld+json"]').allTextContents();
    const faq = blocks.map((b) => JSON.parse(b)).find((d) => d['@type'] === 'FAQPage');
    expect(faq, 'FAQPage JSON-LD is present').toBeTruthy();

    const details = page.locator('#faq details');
    await expect(details).toHaveCount(faq.mainEntity.length);

    const norm = (s) => s.replace(/\s+/g, ' ').trim().replace(/\s*\+$/, '').trim();
    for (const [i, entry] of faq.mainEntity.entries()) {
      const item = details.nth(i);
      expect(norm(await item.locator('summary').textContent())).toBe(norm(entry.name));
      expect(norm(await item.locator('div').textContent())).toBe(norm(entry.acceptedAnswer.text));
    }
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
