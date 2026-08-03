# Exec Plan: Readable Router Image MCP Evidence

## Status

Active.

## Goal

Make the canonical Router Image dry-run logs provide concise, human-readable
proof for every public/protected and modern/compatibility package-client run
without weakening the existing direct JSON, Streamable HTTP, WAMP Meta API,
pub/sub, resource/prompt, session, or authentication gates.

## Scope

- Replace successful full client-summary replay in the image runner with
  bounded evidence lines that name the endpoint class, protocol era, and
  validated capability families.
- Retain the full captured client summary on failures so missing evidence stays
  diagnosable.
- Require explicit modern stateless and compatibility Streamable evidence for
  both public and bearer-protected endpoints in focused source contracts.
- Preserve the raw protocol probe and final non-publishing multi-architecture
  image build.

## Non-Goals

- Change the public `router_hosted_client` output or package API.
- Change MCP protocol, authorization, session, resource, prompt, or pub/sub
  behavior.
- Publish or retag a Router Image.

## Verification

- Focused Router Image source-contract regressions, first failing on the
  missing bounded evidence contract.
- Public/protected package-client runs in both protocol eras against a real
  local native router, with captured output checked for concise evidence.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head CI, package dry run, Router Image dry run, WAMP benchmarks, hosted
  log inspection, and strict deployment-chain audit after the implementation
  push.

## Progress

- 2026-08-03: Selected after the resource/prompt package checkpoint completed
  with clean local and hosted evidence. Its compatibility marker loop is
  complete, but replaying the full client summary emits oversized WAMP metadata
  lines that obscure the later compatibility/protected success evidence in
  GitHub logs.
- 2026-08-03: A focused source contract failed against the old successful
  full-summary replay, then passed after the runner gained bounded evidence
  lines for public/protected stateless and compatibility runs. The evidence
  names protocol version, authentication class, lifecycle mode, direct JSON,
  resources/templates/prompts, WAMP Meta API, pub/sub, and the configured
  resource/prompt selectors. All three failure paths still print the captured
  full summary to standard error.
- 2026-08-03: The pre-change `bin/test-fast`, all 15 focused Router Image MCP
  smoke contracts, shell syntax validation, and full post-change `bin/verify`
  passed. The only locally cached image predates the current protected-session
  fix and reproduces that already-fixed leak; rebuilding a current image was
  blocked while Docker resolved its remote build frontend. The exact fresh
  image build, four bounded package evidence lines, hosted workflows, and
  strict audit remain for the pushed commit.
