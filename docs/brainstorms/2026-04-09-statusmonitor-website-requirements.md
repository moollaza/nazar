---
date: 2026-04-09
topic: statusmonitor-website
---

# StatusMonitor Marketing Website

## Problem Frame

StatusMonitor needs a web presence to explain what it does, build credibility, and provide a download path. The site serves users who found the project via GitHub, social media, or word of mouth. It should be fast to ship (no build toolchain) and easy to update.

## Requirements

**Structure & Tech**
- W1. Static HTML + Tailwind CSS (pinned CDN version with SRI integrity hash). No build step. GitHub Pages deployment.
- W2. Single page with anchor-linked sections. Custom domain supported later via CNAME.

**Content Sections**
- W3. Hero: app name, one-line tagline, macOS app screenshot, download CTA button.
- W4. Feature highlights: 3–4 named selling points with brief copy. Suggested copy: "Know before your users do", "100 services, zero config", "Native macOS — lives in your menu bar", "Open source, free forever". Not a generic icon grid.
- W5. Catalog preview: static grid of ~20 service logos with service name tooltips on hover. Purely illustrative — no links. Logos bundled as SVGs or PNGs in `website/assets/logos/`.
- W6. Download CTA: "Download for macOS" button linking to latest GitHub Release `.dmg`. Secondary link to GitHub repo.

**Quality**
- W7. Tailwind CDN `<link>` tag must include an `integrity` (SRI) attribute pinned to a specific Tailwind version.
- W8. No JavaScript required for core experience. Hover tooltips via CSS only if feasible.

## Success Criteria

- Visitor can understand what the app does and download it within 30 seconds.
- Page loads cleanly with no external requests except the pinned Tailwind CDN.

## Scope Boundaries

- No changelog or release notes page in v1.
- No contact form, email capture, or analytics in v1.
- No React, Next.js, or bundler. Plain HTML only.
- Service logos are a static asset — no runtime fetching.

## Key Decisions

- **Feature highlight copy defined upfront**: Prevents AI-generated generic card grid. Copy is the deliverable; layout follows from it.
- **Logos bundled as static assets**: The website cannot use the app's runtime favicon cache. ~20 logos need to be sourced manually (SVG preferred) and committed to `website/assets/logos/`.
- **SRI required**: Tailwind CDN reference must be pinned with integrity hash before the site goes live.

## Dependencies / Assumptions

- A macOS app screenshot exists before the site is published (required for W3 hero section).
- GitHub Releases will host the `.dmg` artifact before the download CTA is live.
- Logo assets for W5 sourced from each service's press kit or brand assets page.

## Outstanding Questions

### Resolve Before Planning
- None.

### Deferred to Planning
- [Affects W5][Needs research] Which ~20 services appear in the catalog preview? Should align with the top entries from the app catalog (R1 curation).
- [Affects W1][Technical] Confirm current Tailwind CDN version and generate SRI hash for the pinned `<link>` tag.
- [Affects W3][Asset] App screenshot: what screen state best represents the app (dashboard with a mix of green/yellow statuses)?

## Next Steps

→ This can be built in parallel with or after the native app ships. Sequence with app team.
→ `/ce:plan` when ready to implement.
