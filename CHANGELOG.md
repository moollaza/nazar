# Changelog

## [1.5.0](https://github.com/moollaza/nazar/compare/v1.4.0...v1.5.0) (2026-11-21)


### Features

* add a pagerduty parser and three PagerDuty-hosted services ([#104](https://github.com/moollaza/nazar/issues/104)) ([b88f60e](https://github.com/moollaza/nazar/commit/b88f60ecff4436ca4437843bf25ffa403420a302))
* **dashboard:** manage services from the menu bar panel ([#90](https://github.com/moollaza/nazar/issues/90)) ([ee6e4f9](https://github.com/moollaza/nazar/commit/ee6e4f9c5dfc36f11a3b3e74675c48562224cafd))
* **dashboard:** show 28-day incident history per service ([#108](https://github.com/moollaza/nazar/issues/108)) ([d1c7ac4](https://github.com/moollaza/nazar/commit/d1c7ac486d11da2a4d44620b1631fb547cd56731))
* datadog parser, audit failure classification, deterministic visual suite ([#78](https://github.com/moollaza/nazar/issues/78)) ([0f3cb9c](https://github.com/moollaza/nazar/commit/0f3cb9caaba50d8f5436ea4ae4b93ba5adb9eafa))
* **website:** add privacy policy page ([#94](https://github.com/moollaza/nazar/issues/94)) ([46aca6c](https://github.com/moollaza/nazar/commit/46aca6cce1cd06bbe7189fb1dd4aef3300d1b3e3))


### Bug Fixes

* **catalog:** repair or remove entries flagged by catalog audit ([#77](https://github.com/moollaza/nazar/issues/77)) ([77836d2](https://github.com/moollaza/nazar/commit/77836d2877917601e7fe5417d0492426c967cf6b))
* **catalog:** repair or remove entries flagged by the weekly audit ([#84](https://github.com/moollaza/nazar/issues/84)) ([329f3d9](https://github.com/moollaza/nazar/commit/329f3d9a215aa35ecb37f3765b6acf382084c07a))
* **ci:** drop package-name so release-please tags merged Release PRs ([#79](https://github.com/moollaza/nazar/issues/79)) ([5f3f0f5](https://github.com/moollaza/nazar/commit/5f3f0f50379acba2cf411b291ce69fc3d93e2ca9))
* close the panel when Settings opens; add Check for Updates to Settings ([#92](https://github.com/moollaza/nazar/issues/92)) ([8deeaaf](https://github.com/moollaza/nazar/commit/8deeaaf7adb68b0f3357766cb8bcebb3bf2890d6))
* draw menu bar icons in their status color ([#109](https://github.com/moollaza/nazar/issues/109)) ([de47bdf](https://github.com/moollaza/nazar/commit/de47bdff4251cae5b51441a51289118b6306c5a1))
* **release:** refuse to build unless HEAD is the release tag ([#76](https://github.com/moollaza/nazar/issues/76)) ([50bd1e8](https://github.com/moollaza/nazar/commit/50bd1e85dadec4aafe1a059f409aa78fcc9e26d0))
* **website:** make reduced motion apply in visual tests ([#101](https://github.com/moollaza/nazar/issues/101)) ([065313f](https://github.com/moollaza/nazar/commit/065313f8a833c56d44fded8b0b432cd494ce2caa))

## [1.4.0](https://github.com/moollaza/nazar/compare/v1.3.0...v1.4.0) (2026-09-25)


### Features

* Sparkle auto-updates for DMG build ([#73](https://github.com/moollaza/nazar/issues/73)) ([5372541](https://github.com/moollaza/nazar/commit/5372541c8bb558981d985960a9e4fcf46486e04e))

## [1.3.0](https://github.com/moollaza/nazar/compare/v1.2.0...v1.3.0) (2026-09-11)


### Features

* **catalog:** add 113 AI and agent services ([#56](https://github.com/moollaza/nazar/issues/56)) ([aebdb12](https://github.com/moollaza/nazar/commit/aebdb1204be55d22ad57dea07b0f75522bd4983c))
* **catalog:** add 17 statuspage services from candidate backlog ([#51](https://github.com/moollaza/nazar/issues/51)) ([0626165](https://github.com/moollaza/nazar/commit/0626165ed6ff1af6e2d937f36553b6f317c05d8d)), closes [#46](https://github.com/moollaza/nazar/issues/46)
* **catalog:** add 23 Better Stack status pages + betterstack discovery support ([97c3657](https://github.com/moollaza/nazar/commit/97c3657b55f5bb730344a3eb62e32e554c49c056)), closes [#41](https://github.com/moollaza/nazar/issues/41)
* rewrite website copy, add catalog pagination ([#54](https://github.com/moollaza/nazar/issues/54)) ([d5d7251](https://github.com/moollaza/nazar/commit/d5d72514a654188974aaab04915d9d28e87e9a2c))
* support Better Stack status pages ([#40](https://github.com/moollaza/nazar/issues/40)) ([fbb5751](https://github.com/moollaza/nazar/commit/fbb5751d80f2beeded30f4278c6632ca9bae5298)), closes [#38](https://github.com/moollaza/nazar/issues/38)
* **website:** add fathom analytics events ([#31](https://github.com/moollaza/nazar/issues/31)) ([958237d](https://github.com/moollaza/nazar/commit/958237dd317bd96591a43ae663f0dad88a6fb8c2))
* **website:** add PostHog analytics ([#55](https://github.com/moollaza/nazar/issues/55)) ([a7c89fb](https://github.com/moollaza/nazar/commit/a7c89fb3ccf429809121e8ccbd7b72f364a8fcd6))
* **website:** make PostHog cookieless, disable session recording ([#64](https://github.com/moollaza/nazar/issues/64)) ([98b32f0](https://github.com/moollaza/nazar/commit/98b32f06b48806d0214ed8a0e4c859945957ab2e))


### Bug Fixes

* port Instatus support to main and address review findings ([#62](https://github.com/moollaza/nazar/issues/62)) ([1d9cfaf](https://github.com/moollaza/nazar/commit/1d9cfaf3c39b138adb95136170b658eac6006e06))
* update stale service count to 1,800+ and add CI drift check ([#68](https://github.com/moollaza/nazar/issues/68)) ([41b6325](https://github.com/moollaza/nazar/commit/41b6325d187787df4ef78889f63ec0bbd694e04f))


### Documentation

* stop recording the catalog size in CLAUDE.md ([#65](https://github.com/moollaza/nazar/issues/65)) ([5d9c89b](https://github.com/moollaza/nazar/commit/5d9c89b04b345e0b9ad4b55bbf3890039f261c1a))
* switch issue tracking to GitHub Issues, fix stale deployment section ([#61](https://github.com/moollaza/nazar/issues/61)) ([aa8ae18](https://github.com/moollaza/nazar/commit/aa8ae185bb6490278fc85da086c1cf53213c95e4)), closes [#45](https://github.com/moollaza/nazar/issues/45)
* switch license to Apache-2.0 ([9f867b5](https://github.com/moollaza/nazar/commit/9f867b5914d4163c4b5dd55ed4b402051cef9a80))
