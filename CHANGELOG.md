# Changelog

## [1.3.0](https://github.com/Shroud-email/shroud.email/compare/v1.2.0...v1.3.0) (2026-01-20)


### Features

* add task to export failed emails for debugging ([#106](https://github.com/Shroud-email/shroud.email/issues/106)) ([b86bdd7](https://github.com/Shroud-email/shroud.email/commit/b86bdd75224c42105616b5ba36291eccc490e49b))
* use mailex (experimental) ([#105](https://github.com/Shroud-email/shroud.email/issues/105)) ([6053f09](https://github.com/Shroud-email/shroud.email/commit/6053f09747bb6ee6208c4a9bb63ef04d1ee91c05))


### Bug Fixes

* fix KeyError when checking for admin ([#96](https://github.com/Shroud-email/shroud.email/issues/96)) ([08797de](https://github.com/Shroud-email/shroud.email/commit/08797de6b1add0fdafa4fcaed74be5f021a430b4))
* handle empty reply-to headers ([#107](https://github.com/Shroud-email/shroud.email/issues/107)) ([10fd0ec](https://github.com/Shroud-email/shroud.email/commit/10fd0eca7076553c668a4b47ade92bc4e0ac9010))
* handle invalid bracket domains in email addresses ([#109](https://github.com/Shroud-email/shroud.email/issues/109)) ([75ea13b](https://github.com/Shroud-email/shroud.email/commit/75ea13b75705a400e760e17a4b0f4a7618e211aa))
* handle invalid emails with spaces in local part ([#104](https://github.com/Shroud-email/shroud.email/issues/104)) ([36df157](https://github.com/Shroud-email/shroud.email/commit/36df157b3db950c4deda5768ce9abe34484b531f))
* handle non-UTF8 bytes in incoming emails ([17bbdf8](https://github.com/Shroud-email/shroud.email/commit/17bbdf8f04c353843fd153b90b6c1c2f07691474))
* handle parentheses in sender name ([0189458](https://github.com/Shroud-email/shroud.email/commit/0189458632bef916816b398c88a0dbad49213df6))
* handle quotes in email addresses ([ed04f41](https://github.com/Shroud-email/shroud.email/commit/ed04f4141359f20ab78ce42b392a7f8e74a3ea8e))
* ignore TLS when relaying to haraka ([#100](https://github.com/Shroud-email/shroud.email/issues/100)) ([8187006](https://github.com/Shroud-email/shroud.email/commit/8187006d164ac356a6fd3f34058313eabcab93d9))
* revert gen_smtp update ([b84ca3d](https://github.com/Shroud-email/shroud.email/commit/b84ca3d079d4e27d59372981a462183ff56c7a81))
* switch from emailoctopus to loops ([#101](https://github.com/Shroud-email/shroud.email/issues/101)) ([9fb17e8](https://github.com/Shroud-email/shroud.email/commit/9fb17e84be161fd68f88bd2a01fc4b39d952929f))
* use mailex to parse emails in spam check ([#108](https://github.com/Shroud-email/shroud.email/issues/108)) ([2e294dd](https://github.com/Shroud-email/shroud.email/commit/2e294ddb9faa4fa5139e4de5ee2e503d2c1e5a09))

## [1.2.0](https://github.com/Shroud-email/shroud.email/compare/v1.1.1...v1.2.0) (2025-03-23)


### Features

* add debug view for admins ([07ff176](https://github.com/Shroud-email/shroud.email/commit/07ff1761efb0c4e73e8857415e8b98c4fed924aa))
* **api:** API Endpoint to delete Alias ([#84](https://github.com/Shroud-email/shroud.email/issues/84)) ([2dc1caa](https://github.com/Shroud-email/shroud.email/commit/2dc1caa308918586a070ee050beb129ad7d66e76))
* store spamassassin headers ([#87](https://github.com/Shroud-email/shroud.email/issues/87)) ([b3364dd](https://github.com/Shroud-email/shroud.email/commit/b3364dde6950b434498a60784ea1e9395e1c9a0f))

## [1.1.1](https://github.com/Shroud-email/shroud.email/compare/v1.1.0...v1.1.1) (2023-11-07)


### Bug Fixes

* fix config error ([c46d7c8](https://github.com/Shroud-email/shroud.email/commit/c46d7c8c657b7ff79d401640a3ed0ed8be7c3fb6))

## [1.1.0](https://github.com/Shroud-email/shroud.email/compare/v1.0.3...v1.1.0) (2023-11-06)


### Features

* add ability to disable signups ([#78](https://github.com/Shroud-email/shroud.email/issues/78)) ([43d002a](https://github.com/Shroud-email/shroud.email/commit/43d002afd379f7bcdb5d32335178531d42166daa))

## [1.0.3](https://github.com/Shroud-email/shroud.email/compare/v1.0.2...v1.0.3) (2023-07-01)


### Miscellaneous Chores

* release 1.0.3 ([4b979c8](https://github.com/Shroud-email/shroud.email/commit/4b979c826ecefe205997d960cd23c01c7f817ca2))

## [1.0.2](https://github.com/Shroud-email/shroud.email/compare/v1.0.1...v1.0.2) (2023-06-29)


### Bug Fixes

* **emails:** move shroud.email notice to bottom of emails ([e575553](https://github.com/Shroud-email/shroud.email/commit/e575553d2e9d702f8c6ef76214fc72641b0899a0))

## [1.0.1](https://github.com/Shroud-email/shroud.email/compare/v1.0.0...v1.0.1) (2023-03-25)


### Bug Fixes

* **domains:** fix "add domain" button ([4ceef00](https://github.com/Shroud-email/shroud.email/commit/4ceef001daecea4afff5268d3a3916266ad9ff59))

## [1.0.0](https://github.com/Shroud-email/shroud.email/compare/v0.2.4...v1.0.0) (2023-03-11)


### ⚠ BREAKING CHANGES

* **aliases:** admins must manually run the `make_emails_case_insensitive` command before deploying this.

### Features

* **aliases:** use citext column for alias addresses ([#53](https://github.com/Shroud-email/shroud.email/issues/53)) ([8e7800a](https://github.com/Shroud-email/shroud.email/commit/8e7800a9a77827224527a6e231f0d76695697b06))

## [0.2.4](https://github.com/Shroud-email/shroud.email/compare/v0.2.2...v0.2.4) (2023-03-11)


### Miscellaneous Chores

* **main:** release 0.2.3 ([#58](https://github.com/Shroud-email/shroud.email/issues/58)) ([121ac5b](https://github.com/Shroud-email/shroud.email/commit/121ac5be666c95762a26fff4ad3fba4f019a9dbf))


### Continuous Integration

* only deploy on new tags ([10c94df](https://github.com/Shroud-email/shroud.email/commit/10c94df28bd54f88a81015bcf43c695c81abbaae))
* use different token to create releases ([c1a10df](https://github.com/Shroud-email/shroud.email/commit/c1a10df55286257a1e50c7588b0c5caef901377e))

## [0.2.3](https://github.com/Shroud-email/shroud.email/compare/v0.2.2...v0.2.3) (2023-03-11)


### Continuous Integration

* only deploy on new tags ([10c94df](https://github.com/Shroud-email/shroud.email/commit/10c94df28bd54f88a81015bcf43c695c81abbaae))

## [0.2.2](https://github.com/Shroud-email/shroud.email/compare/v0.2.1...v0.2.2) (2023-03-11)


### Continuous Integration

* fix releasing semver images ([43d0509](https://github.com/Shroud-email/shroud.email/commit/43d0509c7274a37fdebe500217a1e7182c9ab84e))

## [0.2.1](https://github.com/Shroud-email/shroud.email/compare/v0.2.0...v0.2.1) (2023-03-11)


### Continuous Integration

* deploy on new tags ([9d40c4f](https://github.com/Shroud-email/shroud.email/commit/9d40c4f8f670b57a0518782803ce9af660d8af1b))

## [0.2.1](https://github.com/Shroud-email/shroud.email/compare/v0.2.0...v0.2.1) (2023-03-11)


### Continuous Integration

* deploy on new tags ([9d40c4f](https://github.com/Shroud-email/shroud.email/commit/9d40c4f8f670b57a0518782803ce9af660d8af1b))

## [0.2.0](https://github.com/Shroud-email/shroud.email/compare/v0.1.0...v0.2.0) (2023-03-11)


### Features

* **aliases:** add command to deduplicate aliases with different cases ([b9d82a5](https://github.com/Shroud-email/shroud.email/commit/b9d82a5b2e0cf5ec28c9215f7210ca637ab188d0))


### Bug Fixes

* **aliases:** ensure we don't create more duplicate aliases ([1f319c8](https://github.com/Shroud-email/shroud.email/commit/1f319c80029ebd8be9ae0437335b23646e3c234a))

## 0.1.0 (2023-03-05)


### Build System

* set up release-please ([#50](https://github.com/Shroud-email/shroud.email/issues/50)) ([2cd7097](https://github.com/Shroud-email/shroud.email/commit/2cd7097b58389549f9bcd0a583a44e4a49a63b96))
