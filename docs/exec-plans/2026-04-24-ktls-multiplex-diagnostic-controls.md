# kTLS Multiplex Diagnostic Controls

Status: completed

## Context

- Commit `2393a01` is green on the hosted push chain:
  - `CI` `24868963261`
  - `kTLS Validation` `24868963265`
  - `WAMP Profile Benchmarks` `24868963262`
- Manual hosted run `24869856621` (`kTLS HTTP/2 Benchmarks`) confirmed that
  required-kTLS is opening kernel software TX/RX sessions cleanly with no
  decrypt/rekey anomalies, but the dominant regression moved to
  `h2_multiplexed_streams`.
- The current helper and workflow are still wired around the canonical
  `h2_ktls_benchmark` artifact policy, which makes focused diagnostic reruns
  awkward even though the hotspot is now specific enough to justify them.

## Goals

1. Keep the canonical `h2_ktls_benchmark` release-decision path unchanged.
2. Let manual kTLS workflow runs opt into a focused diagnostic scenario with
   either an explicit artifact policy or an intentional no-gate mode.
3. Check in a dedicated HTTP/2 multiplex-only diagnostic scenario so the next
   hosted rerun can target the newly confirmed hotspot directly.

## Planned Changes

1. Add `bin/ktls-http2-bench` controls for explicit artifact policy selection
   and gate skipping, while preserving the current default behavior for the
   canonical benchmark.
2. Mirror those controls into `.github/workflows/ktls-http2-benchmarks.yml`.
3. Add a checked-in `native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
   scenario and refresh the kTLS research/state docs to reflect the latest
   hosted evidence and the narrower next investigation.

## Verification

- `bin/test-fast`
- `bash -n bin/ktls-http2-bench`
- workflow YAML parse validation
- `bin/verify`

## Outcome

- `bin/ktls-http2-bench` now supports explicit `--artifact-policy` selection
  plus `--skip-artifact-gate`, while preserving the canonical
  `h2_ktls_benchmark` default behavior.
- `.github/workflows/ktls-http2-benchmarks.yml` now exposes matching
  `artifact_policy` and `skip_artifact_gate` inputs for hosted reruns.
- `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` is checked in as the
  focused HTTP/2 multiplex-only diagnostic scenario for the next hosted kTLS
  investigation.
- Verification passed via `bin/test-fast`, `bash -n bin/ktls-http2-bench`,
  Ruby YAML parsing of `.github/workflows/ktls-http2-benchmarks.yml`,
  `bin/ktls-http2-bench --help`, and `bin/verify`.
