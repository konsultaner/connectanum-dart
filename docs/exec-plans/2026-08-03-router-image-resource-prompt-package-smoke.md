# Exec Plan: Router Image Resource and Prompt Package Smoke

## Status

Completed.

## Goal

Make the canonical loaded Router Image prove that a neutral consumer using the
shipped `connectanum_mcp:router_hosted_client` executable can discover and
consume router-configured resources, resource templates, and prompts through
both modern stateless direct JSON and compatibility-era Streamable HTTP.

## Scope

- Add neutral static context, one resource template, and one parameterized
  prompt to the public and bearer-protected Router Image MCP routes.
- Pass those selectors through the public package executable in both protocol
  eras and require direct resource/template/prompt evidence.
- Require compatibility-era Streamable resource/template/prompt evidence in
  addition to the existing lifecycle, WAMP Meta API, pub/sub, and auth gates.
- Preserve the raw Python protocol probe and final non-publishing
  multi-architecture image build.

## Non-Goals

- Add a new MCP protocol extension or change router dispatch semantics.
- Add dynamic resource subscriptions; the existing downstream consumer smoke
  already owns that lifecycle.
- Add application-specific data, credentials, or filesystem assumptions.
- Publish or retag a Router Image.

## Verification

- Focused Router Image source-contract regressions, first failing on the
  missing resource/prompt package-client contract.
- Router configuration validation and public/protected package-client runs
  against a real local native router.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head CI, package dry run, Router Image dry run, WAMP benchmarks, and
  strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-03: Selected after the preceding stateless public-client image plan
  completed with clean local and hosted evidence. The executable already
  exercises typed direct and Streamable resources, resource templates, and
  prompts when selectors are supplied, but the canonical image route and
  runner do not configure or require that public-package evidence.
- 2026-08-03: Pre-change `bin/test-fast` passed on the current checkout,
  including the native/router integration matrix, all MCP/client suites,
  generated and globally activated package smokes, and live WAMP workloads.
- 2026-08-03: Focused source-contract regressions first failed with 22 missing
  resource/template/prompt assertions across the runner and both configured
  routes. The canonical image configuration now supplies one neutral resource,
  one resource template, and one required-argument prompt on each route.
- 2026-08-03: The image runner now passes `--resource-uri`, `--prompt`, and
  `--prompt-arguments` to the shipped executable. Both protocol eras require
  direct resource, resource-template, prompt-list, and rendered-prompt markers;
  compatibility mode additionally requires the corresponding Streamable HTTP
  markers. All 14 focused Python contracts and shell syntax checks pass.
- 2026-08-03: Public and ticket-protected package-client runs pass against a
  real local native router for both `2026-07-28` stateless mode and `2025-11-25`
  compatibility mode. The rendered prompt contains the supplied neutral
  argument, and protected compatibility mode also completes issue, refresh,
  direct/Streamable use, and access/refresh revocation.
- 2026-08-03: Post-change `bin/test-fast` passes end to end, including 360 core
  tests, all 94 MCP tests, the complete 193-case MCP/client suite, all 96
  benchmark tests with 36 live WAMP workloads, and every generated/globally
  activated consumer and router CLI package smoke.
- 2026-08-03: Final local `bin/verify` passes formatting, analysis, 113 Rust
  core tests, 52 Rust FFI tests, both native integration groups, 360 Dart core
  tests, all 94 MCP tests, the complete 193-case MCP/client suite, all 96
  benchmark tests with 36 live WAMP workloads, the complete 380-case router
  suite, the 13-case native follow-up, all package smokes, and Chrome/Dart2Wasm.
- 2026-08-03: Commit `093e032` was pushed to GitLab and GitHub. Exact-head CI
  `30799920053`, Dart Package Publish Dry Run `30799932547`, Router Image dry
  run `30799932602`, and WAMP Profile Benchmarks `30799932723` all passed. CI
  uploaded coverage artifact `8850823884`, Router Image uploaded preview
  artifact `8850398719`, and WAMP uploaded benchmark artifact `8850584445`.
- 2026-08-03: Hosted Router Image logs visibly contain the configured resource
  URI, template URI, prompt name, rendered neutral prompt, and public/protected
  stateless pass markers. The successful compatibility runs gated the required
  direct and Streamable resource/template/prompt markers before the final
  non-publishing multi-architecture build.
- 2026-08-03: The comprehensive strict deployment-chain audit exited clean
  with exact-head CI and log cleanliness, package dry run, relevant native
  release evidence, Router Image dry run, WAMP artifacts, workflow visibility,
  branch protection, and public router-package visibility ready. Selecting a
  follow-up RC tag remains an approval-gated release action outside this plan.
