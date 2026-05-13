# Exec Plan: MCP Client Package Catalog Pagination Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-11

## Goal

Make the standalone MCP client-only consumer smoke prove that downstream
applications can follow opaque MCP catalog cursors through the public
Streamable HTTP client helpers, both for session-bound Streamable requests and
lifecycle-free direct JSON requests.

## Scope

- In scope: `bin/common.sh` generated MCP client-only consumer smoke and its
  fake MCP endpoint cursor pages.
- Out of scope: public API changes, router runtime catalog pagination changes,
  and unrelated benchmark/doc cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-10-mcp-client-package-catalog-pagination-smoke.md`
- Prior docs-only hosted evidence from the previous slice may be bundled.

## Preconditions

- Serena project onboarding is complete for this repository.
- Pre-change `bin/test-fast` must pass before editing the generated smoke.

## Plan

1. Confirm the current MCP readiness context and run the pre-change fast gate.
2. Add deterministic fake cursor pages for tools, resources, resource templates,
   and prompts in the generated client-only endpoint.
3. Extend the generated consumer app to follow those cursors through typed
   helpers over Streamable HTTP and direct JSON where supported.
4. Run the focused generated smoke, `bin/test-fast`, and `bin/verify`; then
   push and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `bash -lc 'source bin/common.sh; run_mcp_client_package_smoke'`
  passed on 2026-05-10.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-11.
- Commit `3e00cb1` (`test: follow mcp catalog cursors in client smoke`) is
  pushed to both remotes. GitHub `CI` run `25658297818` completed
  successfully for `3e00cb1` with `Fast Checks` and `Full Verify` green, and
  the hosted CI log scan was clean. GitHub `Dart Package Publish Dry Run` run
  `25635686773` remains clean and relevant because no publish-sensitive
  package inputs changed after `90a27ca`.
- The deployment-chain audit passed with clean latest CI, clean hosted CI logs,
  and a clean relevant Dart package publish dry-run. The strict audit still
  reports only known operator-side release-hardening gaps: branch
  protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Continue client-only package smoke hardening because catalog
  cursor handling is a downstream agent-readiness contract exposed by the
  public `McpStreamableHttpClient` helpers, and current generated smokes only
  proved single-page catalog calls.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side
release-hardening items.
