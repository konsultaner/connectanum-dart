# Exec Plan: Router Image MCP HTTP-Auth Method Parity

Status: completed
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Prove that the loaded router image and the globally activated public MCP client
interoperate through every router-supported HTTP-auth method. Retain the
existing ticket and official-client coverage, add WAMP-CRA on the compatibility
Streamable HTTP path, and add SCRAM on the modern stateless path.

## Scope

- In scope:
  - expose ticket, WAMP-CRA, and SCRAM from the neutral Router Image smoke
    session profile and realm;
  - configure neutral image-smoke credentials for all three authenticators;
  - exercise WAMP-CRA through the compatibility package-client smoke;
  - exercise SCRAM through the modern stateless package-client smoke;
  - require method-specific, lifecycle, direct JSON, WAMP meta, resource,
    prompt, and pub/sub evidence without printing credentials;
  - retain the ticket, JSON-response, Python black-box, and official MCP SDK
    coverage already protecting the image.
- Out of scope:
  - changing public auth APIs or router authentication semantics;
  - OAuth browser authorization;
  - storing deployment credentials or publishing an unapproved release tag.

## Files Expected To Change

- `deploy/docker/router_mcp_smoke.yaml`
- `bin/router-image-mcp-smoke`
- `tool/test_router_image_mcp_smoke.py`
- `docs/project_state.md`

## Preconditions

- The scheduled launchd wrapper and its current Codex child are the expected
  run; no unrelated process is editing this repository.
- Local, GitLab, and GitHub `master` start at `8ebccad4`.
- The inherited documentation-only hosted evidence for commit `8ebccad4`
  remains intentional and will be bundled with this implementation.
- The exact-head GitHub deployment chain and strict audit are green before the
  change.

## Plan

1. Run pre-change `bin/test-fast`.
2. Add fail-first Router Image smoke-boundary expectations for WAMP-CRA and
   SCRAM configuration, invocations, method evidence, and secret redaction.
3. Extend the loaded-image smoke configuration and public-client runner with
   WAMP-CRA compatibility and SCRAM stateless lifecycle runs.
4. Run focused smoke contracts and, when available, a local loaded-image smoke.
5. Run canonical verification, record the milestone, publish it, and collect
   exact-head Router Image plus deployment-chain evidence.

## Verification

- `python3 -m unittest tool.test_router_image_mcp_smoke`
- `bash -n bin/router-image-mcp-smoke`
- loaded Router Image MCP runtime smoke where Docker is available
- `bin/test-fast`
- `bin/verify`
- exact-head Router Image workflow and strict deployment-chain audit after
  publication

## Decision Log

- 2026-08-16: Selected this deployment boundary because the public client and
  source/global real-router smokes now cover ticket, WAMP-CRA, and SCRAM, while
  the loaded-image gate still configures and proves ticket only.
- 2026-08-16: Use WAMP-CRA for the compatibility run and SCRAM for the modern
  stateless run. Together they cover both added authentication methods and both
  Streamable HTTP protocol eras without duplicating every expensive image
  scenario.

## Progress

- 2026-08-16: Serena preflight, overlap checks, worktree inspection, and
  exact-head hosted-health checks passed. Only the preceding checkpoint's two
  documentation-evidence files were modified at startup.
- 2026-08-16: Pre-change `bin/test-fast` passes the complete fast regression,
  package, benchmark, router, generated-consumer, and globally activated
  executable matrix, including all 97 benchmark tests and 37 live WAMP
  workloads.
- 2026-08-16: The fail-first Router Image contracts report the missing
  WAMP-CRA/SCRAM profile methods, authenticators, method evidence, redaction,
  and two lifecycle invocations before implementation.
- 2026-08-16: The neutral image profile now exposes ticket, WAMP-CRA, and
  SCRAM. The isolated public-package runner retains all ticket and official SDK
  checks, adds a WAMP-CRA compatibility lifecycle run and a SCRAM modern
  stateless lifecycle run, requires the selected method in lifecycle evidence,
  and rejects summaries containing the configured ticket or shared secret.
- 2026-08-16: Shell syntax and all 34 Router Image boundary tests pass. The
  current router binary loads and starts the modified profile. Focused live
  WAMP-CRA compatibility and SCRAM stateless runs pass authentication,
  refresh/revoke, Streamable/sessionless behavior, direct JSON, WAMP meta,
  resources, prompts, pub/sub, and credential redaction against that profile.
- 2026-08-16: A cached local image correctly proved too old for the current MCP
  completions contract. A fresh local image build was attempted but Docker's
  external Dockerfile-frontend resolution stalled before the first stage; the
  exact-head hosted Router Image build and runtime smoke remains the
  authoritative fresh-artifact check after publication.
- 2026-08-16: Canonical `bin/verify` passes on retry with zero formatting
  changes, 117 Rust core/serializer tests, 52 FFI tests, all Python contracts,
  366 core tests, 116 MCP tests, the complete 296-case MCP/client suite, all 97
  benchmark tests including 37 live WAMP workloads, every maintained consumer
  and global-activation smoke, all 454 router cases, six remote-auth tests, 13
  native follow-ups, Chrome, and Dart2Wasm. The first run had one isolated
  multi-megabyte HTTP/3 handshake timeout after the preceding suites; the exact
  case passed immediately in isolation and passed again in the complete retry.
- 2026-08-16: Commit `ec53a327` is published to both maintained `master`
  branches. Exact-head CI `31962764195` passes Fast Checks, Full Verify, and
  Dart VM Coverage; Router Image dry run `31962779317` passes the fresh amd64
  image build, expanded loaded-image MCP smoke, and dry-run multi-architecture
  build. Coverage artifact `9267901890`, Router Image preview `9267671173`, and
  Docker build records `9267681408` and `9267681075` are available.
- 2026-08-16: The comprehensive strict deployment-chain audit exits zero with
  exact-head CI and clean logs, current Router Image runtime and metadata
  evidence, relevant package/native/WAMP gates, branch protection, workflow
  visibility, and public router-package visibility ready. Its non-gating RC
  summary remains intentionally not ready because no approved numeric RC tag
  points at this implementation.

## Handoff

- Completed. Implementation, focused and canonical local verification,
  publication to both maintained branches, exact-head hosted CI and image
  evidence, and the comprehensive strict deployment-chain audit pass.
