# Website catalog

usenazar.com is a static page. Its catalog section loads `catalog.json` in the browser and lets visitors page through, filter by category, and search the supported services. Each result links to the service's status page.

## Sub-features

- `web-hero` the homepage hero and download links render.
- `web-catalog-page` the catalog shows 30 services on desktop and 12 on mobile, with `Showing N of …` and a pager.
- `web-catalog-search` `#catalog-search` filters results; GitHub links to `https://www.githubstatus.com`.
- `web-catalog-empty` a query with no hits shows `No services match.` and a request link (`#catalog-empty-submit`).
- `web-catalog-category` a category chip narrows the list to that category.
- `web-faq` the FAQ section opens and its text matches the FAQPage JSON-LD.

## How to get to it (user POV)

- Open https://usenazar.com/ and scroll to `Browse the list of supported services`.
- Open https://usenazar.com/#services directly.

## Driving it with web-drive.cjs

Preconditions:

- `$S/web.sh up` and `$S/web.sh doctor` pass. Network reaches `cdn.jsdelivr.net` (Tailwind).

- **Paging.** Run `node $S/web-drive.cjs catalog '/#services' 'see:Browse the list of supported services' 'count:#catalog-list a=30' shot:initial`. Add `--mobile` and expect `12`.
- **Search hit.** Append `'fill:#catalog-search=GitHub' 'attr:#catalog-list a:has-text("GitHub")@href=https://www.githubstatus.com' shot:github`.
- **Empty state.** Append `'fill:#catalog-search=zzz-no-such-service' 'see:No services match.' 'count:#catalog-list a=0' shot:empty`.
- **Category.** Append `'fill:#catalog-search=' 'click:button:has-text("AI & ML")' shot:category`; the screenshot shows only that category's services.
- **Regression suite.** `npm run test:visual` covers the same paths plus the FAQ JSON-LD check. It needs `npm ci` first.

## Gotchas

- The hero demo auto-advances on a timer. Screenshots of it differ run to run; do not compare them pixel for pixel.
- `fill` on `#catalog-search` triggers a debounced filter. Use `count:` or `attr:` (which wait) after it, not an immediate `shot:`.
- A blocked Tailwind CDN fails the run with `request failed: https://cdn.jsdelivr.net/...`. That is correct; the page would be unstyled.
- After a catalog edit, run `python3 scripts/check-service-count.py` too. The site's `N+` figures come from it, not from this driver.
