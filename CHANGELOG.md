# Changelog

## [1.2.0](https://github.com/Shroud-email/shroud.email/compare/v1.1.1...v1.2.0) (2024-01-06)


### Features

* add debug view for admins ([07ff176](https://github.com/Shroud-email/shroud.email/commit/07ff1761efb0c4e73e8857415e8b98c4fed924aa))

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
