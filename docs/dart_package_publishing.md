# Dart package publishing

All eight workspace packages are published at `3.0.0-beta.9`, including the
merged native MQTT client, QoS 0 router and authorized MQTT ↔ WAMP gateway.
Publication and a fresh hosted-only consumer were verified on 2026-11-06.
The [release](https://github.com/konsultaner/connectanum-dart/releases/tag/v3.0.0-beta.9)
contains signed native assets, the checksum-verified benchmark/coverage archive
and a [publication receipt](https://github.com/konsultaner/connectanum-dart/releases/download/v3.0.0-beta.9/beta9-publication.json).
The [completed release plan](exec-plans/2026-11-06-3.0.0-beta.9-release.md)
records qualification and publication methods.

## Release requirements

- Synchronize package and Rust crate versions, internal dependency constraints,
  MCP runtime identity, changelogs and installation guidance.
- Pass `bin/test-fast`, `bin/verify` and
  `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`.
  Every package archive must report `Package has 0 warnings`.
- Pass hosted CI and every applicable performance/memory gate before publication.
  Keep the scoped 100% coverage requirements and numeric budgets unchanged.
- Publish matching signed native assets under `v3.0.0-beta.9` before publishing
  client/router packages. Hosted build hooks derive the native tag from the
  package version; validate fresh installation with
  `bin/validate-native-release-install --tag v3.0.0-beta.9`.

## Package order

| Order | Package | Pub.dev |
| --- | --- | --- |
| 1 | connectanum_core | <https://pub.dev/packages/connectanum_core> |
| 2 | connectanum_client | <https://pub.dev/packages/connectanum_client> |
| 3 | connectanum_mcp | <https://pub.dev/packages/connectanum_mcp> |
| 4 | connectanum_router | <https://pub.dev/packages/connectanum_router> |
| 5 | connectanum | <https://pub.dev/packages/connectanum> |
| 6 | connectanum_auth_server | <https://pub.dev/packages/connectanum_auth_server> |
| 7 | connectanum_bench | <https://pub.dev/packages/connectanum_bench> |
| 8 | connectanum_objectbox_adapter | <https://pub.dev/packages/connectanum_objectbox_adapter> |

The compatibility facade depends on the client. The ObjectBox adapter depends
on client/core and uses the router in its tests; retain its narrow beta version
band and publish it after its prerequisites.

## Automated publication

Seven packages use the verified `dart.konsultaner.de` publisher and GitHub OIDC.
ObjectBox remains individually owned and was published with the existing
authenticated Dart CLI. Do not push its package tag until automation is verified;
its checked-in workflow has no confirmed configuration. Each configured
`.github/workflows/pub-dev-*.yml` workflow triggers on the package-specific tag
`<package>-v<version>`, validates the tag against its pubspec, runs a strict
scoped dry-run, and calls Dart's reusable publishing workflow with the `pub.dev`
environment. Package version bumps and ordinary
master merges do not publish a package automatically.

After CI passes, tag the exact qualified source. Beta.9 was published from
`72c078f1` while the version-metadata PR remains under normal GitHub review;
publication was explicitly authorized separately. Push the coordinated version
tag for the native release. Require all five native platforms and production
consumer proofs to pass. Then push configured package tags in dependency order, waiting for each
publish workflow and pub.dev indexing before publishing dependents. Use the
existing authenticated `dart pub publish --force` path for individually owned
packages whose automation has not been verified. Keep all zero-warning and
source checks. Record the source commit, workflow results and package version
URLs in the release evidence, and verify a clean hosted consumer without workspace path overrides.

Pub.dev publication is immutable. Publish only after an explicit user decision
for the package names and version; do not move an existing release tag or replace
a published version. For a new package, the initial version must be published
manually before enabling automated publication. See the
[official automated publishing guide](https://dart.dev/tools/pub/automated-publishing).
