# Changelog

## [1.3.0](https://github.com/Shroud-email/shroud.email/compare/v1.2.0...v1.3.0) (2026-06-23)


### Features

* add dark mode support with system preference detection ([#111](https://github.com/Shroud-email/shroud.email/issues/111)) ([cc10ef5](https://github.com/Shroud-email/shroud.email/commit/cc10ef5abc5d5b6d57a4500c04c85df0530b4273))
* add task to export failed emails for debugging ([#106](https://github.com/Shroud-email/shroud.email/issues/106)) ([b86bdd7](https://github.com/Shroud-email/shroud.email/commit/b86bdd75224c42105616b5ba36291eccc490e49b))
* replace 30-day trial with permanent free tier ([#112](https://github.com/Shroud-email/shroud.email/issues/112)) ([314318b](https://github.com/Shroud-email/shroud.email/commit/314318b6902bb3cf69ea0cfa38b77ede4881f6da))
* set up Sentry releases ([#143](https://github.com/Shroud-email/shroud.email/issues/143)) ([70265b2](https://github.com/Shroud-email/shroud.email/commit/70265b2e96d012e18ec8140b45c9fb6966afc7d3))
* track per-day counts of blocked tracking domains ([#140](https://github.com/Shroud-email/shroud.email/issues/140)) ([183d00c](https://github.com/Shroud-email/shroud.email/commit/183d00ca0cb72589078e3c9c1047e5a8877f349a))
* use mailex (experimental) ([#105](https://github.com/Shroud-email/shroud.email/issues/105)) ([6053f09](https://github.com/Shroud-email/shroud.email/commit/6053f09747bb6ee6208c4a9bb63ef04d1ee91c05))


### Bug Fixes

* add dark mode support to email report page ([#113](https://github.com/Shroud-email/shroud.email/issues/113)) ([2fa4654](https://github.com/Shroud-email/shroud.email/commit/2fa465419e07c394f1374d3507734ad42694bb27))
* add Oban v14 migration for missing 'suspended' enum value ([#142](https://github.com/Shroud-email/shroud.email/issues/142)) ([1fdd010](https://github.com/Shroud-email/shroud.email/commit/1fdd010c57df750de2b5e461433238b8d9592a46))
* align templates with AGENTS.md guidelines ([#147](https://github.com/Shroud-email/shroud.email/issues/147)) ([3025b8a](https://github.com/Shroud-email/shroud.email/commit/3025b8a211e93830a312de055ec2243bc8c67026))
* decode legacy-charset email headers to prevent SMTP encode crash ([#141](https://github.com/Shroud-email/shroud.email/issues/141)) ([247efe3](https://github.com/Shroud-email/shroud.email/commit/247efe36f3568f31c451f3594bdb5689208db915))
* deduplicate trackers in email reports ([#131](https://github.com/Shroud-email/shroud.email/issues/131)) ([b9b1f80](https://github.com/Shroud-email/shroud.email/commit/b9b1f80de883b1aced1e9526d254780f9c66e466)), closes [#20](https://github.com/Shroud-email/shroud.email/issues/20)
* fix KeyError when checking for admin ([#96](https://github.com/Shroud-email/shroud.email/issues/96)) ([08797de](https://github.com/Shroud-email/shroud.email/commit/08797de6b1add0fdafa4fcaed74be5f021a430b4))
* handle empty reply-to headers ([#107](https://github.com/Shroud-email/shroud.email/issues/107)) ([10fd0ec](https://github.com/Shroud-email/shroud.email/commit/10fd0eca7076553c668a4b47ade92bc4e0ac9010))
* handle invalid bracket domains in email addresses ([#109](https://github.com/Shroud-email/shroud.email/issues/109)) ([75ea13b](https://github.com/Shroud-email/shroud.email/commit/75ea13b75705a400e760e17a4b0f4a7618e211aa))
* handle invalid emails with spaces in local part ([#104](https://github.com/Shroud-email/shroud.email/issues/104)) ([36df157](https://github.com/Shroud-email/shroud.email/commit/36df157b3db950c4deda5768ce9abe34484b531f))
* handle non-UTF8 bytes in incoming emails ([17bbdf8](https://github.com/Shroud-email/shroud.email/commit/17bbdf8f04c353843fd153b90b6c1c2f07691474))
* handle parentheses in sender name ([0189458](https://github.com/Shroud-email/shroud.email/commit/0189458632bef916816b398c88a0dbad49213df6))
* handle quotes in email addresses ([ed04f41](https://github.com/Shroud-email/shroud.email/commit/ed04f4141359f20ab78ce42b392a7f8e74a3ea8e))
* ignore TLS when relaying to haraka ([#100](https://github.com/Shroud-email/shroud.email/issues/100)) ([8187006](https://github.com/Shroud-email/shroud.email/commit/8187006d164ac356a6fd3f34058313eabcab93d9))
* interpolate token in password reset form action ([#148](https://github.com/Shroud-email/shroud.email/issues/148)) ([6e36943](https://github.com/Shroud-email/shroud.email/commit/6e369435b5094e14ca7df941f9b052a6c5bc1e34))
* make debug email page readable in dark mode ([#138](https://github.com/Shroud-email/shroud.email/issues/138)) ([669a874](https://github.com/Shroud-email/shroud.email/commit/669a874ed8992611539de2bfb3e58fcf1c2233dc))
* revert gen_smtp update ([b84ca3d](https://github.com/Shroud-email/shroud.email/commit/b84ca3d079d4e27d59372981a462183ff56c7a81))
* serve digested favicon by allowing only_matching in Plug.Static ([#145](https://github.com/Shroud-email/shroud.email/issues/145)) ([bc055ad](https://github.com/Shroud-email/shroud.email/commit/bc055add226322cebde370c6ef2a5d1aed563854))
* stop enqueuing DnsChecker jobs inside a streaming transaction ([#136](https://github.com/Shroud-email/shroud.email/issues/136)) ([e4f9997](https://github.com/Shroud-email/shroud.email/commit/e4f999703dbebfee6604addb58688b25d8616d41))
* strip double quotes from parsed email addresses ([#139](https://github.com/Shroud-email/shroud.email/issues/139)) ([dc44cd4](https://github.com/Shroud-email/shroud.email/commit/dc44cd4035abb54ab8cde1b4dd53ab8ce5d20f7a))
* switch from emailoctopus to loops ([#101](https://github.com/Shroud-email/shroud.email/issues/101)) ([9fb17e8](https://github.com/Shroud-email/shroud.email/commit/9fb17e84be161fd68f88bd2a01fc4b39d952929f))
* use mailex to parse emails in spam check ([#108](https://github.com/Shroud-email/shroud.email/issues/108)) ([2e294dd](https://github.com/Shroud-email/shroud.email/commit/2e294ddb9faa4fa5139e4de5ee2e503d2c1e5a09))
* use the release input for the sentry-release action ([#144](https://github.com/Shroud-email/shroud.email/issues/144)) ([8217d14](https://github.com/Shroud-email/shroud.email/commit/8217d14a80d887f657b0cb2ae363099de7ae5943))

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
