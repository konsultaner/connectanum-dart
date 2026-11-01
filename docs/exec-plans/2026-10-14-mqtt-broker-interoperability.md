# MQTT broker interoperability

Status: active; direct QoS 0 merged, authorized gateway and translation gates in progress.
Owner: Codex. Started: 2026-10-14. Updated: 2026-11-01.
Tracking: [milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2),
[PR #128](https://github.com/konsultaner/connectanum-dart/pull/128).

## Current gateway implementation (#116, #117, #131)

Work starts from `ef822e08` on `codex/mqtt-wamp-gateway`. The merged required CI,
publishing and WAMP release-profile gate pass. Auxiliary kTLS validation lacks
kernel TLS ULP support; WAMP diagnostics have existing throughput-floor misses.
Keep their failures visible and their budgets unchanged; do not treat them as
gateway acceptance evidence.

1. Add an opt-in gateway on the native router binding, with realm isolation and
   explicitly configured MQTT principal/role. Anonymous loopback remains the
   advertised MQTT authentication profile; client IDs never confer identity.
2. Authorize incoming publications before any MQTT/WAMP delivery. Authorize
   concrete outgoing topics for MQTT recipients, including wildcard filters.
   Retain the synchronous direct-MQTT path when no gateway is installed.
3. Register `connectanum.mqtt.v1.publish` as the explicit WAMP API accepting a
   topic and application bytes. Resolve the original caller from trusted router
   invocation/session state, apply realm publication ACLs, and reject unsupported
   arguments/metadata. Ordinary mapped-topic publications and `ppt_scheme: mqtt`
   remain opaque and cause no MQTT delivery.
4. Keep per-peer ingress/outgoing gateway work bounded; preserve ordering,
   isolate policy failures, cancel work on disconnect/disposal, and expose queue
   byte/depth and delivery/error counters. Forward each gateway publication to
   WAMP once with origin metadata; never subscribe the gateway to its own output.
5. Add fail-first unit and live Paho/Connectanum/WAMP regressions for both MQTT
   versions and TCP/TLS/WS/WSS, realm isolation, deny/no-delivery, binary payloads,
   fan-out, no subscribers, caller spoofing, opaque PPT, loops, partial startup,
   slow peers, disconnects and repeated gateway lifecycle.
6. Extend exact 100% coverage to every new gateway source and executable changed
   shared line; preserve all existing MQTT/WAMP coverage and regression gates.
7. Measure real process-isolated translations in both directions against matched
   MQTT→MQTT and WAMP→WAMP controls. Include 128 B/1 KiB/64 KiB, fan-out, burst and
   sustained load, secure/cleartext and the four WAMP serializers in an explicit
   required profile inventory. Record throughput, p50/p95/p99, CPU, each process's
   warm/peak/drained RSS, queue bytes/depth, drops/errors and lifecycle recovery.
8. Lock numeric budgets only after live baseline measurements, then test every
   positive/negative gate decision. Publish smoke/release workflow artifacts and
   user-friendly README tables; keep raw histories out of the source tree.
9. Run focused checks, `bin/verify`, strict publishing and hosted regression /
   performance gates before claiming completion. The broader MQTT milestone and
   controlled-hardware release acceptance remain separate from this gateway PR.

## Current verification

`bin/test-fast` passed on the merged baseline. The focused router suite passed
184 tests; the expanded gateway suite passes 21 tests and the worker suite
passes 32 live transport/serializer/direction cases plus lifecycle/control tests.
The new gateway adapter, cancellation, broker, MQTT client and measurement
sources reach exact 100% line coverage. The current source receipt passes 679/679
gateway/shared executable lines, 758/758 MQTT lines and 270/270 gateway lines.
New Python benchmark, peer and coverage controls measure 642/642 executable lines
with zero exclusions. Worker state telemetry and the CLI have refreshed passing coverage.
Full final-source collection and hosted receipts supersede these incremental counts.

The first diagnostic campaign completed 120 samples: 10 profiles × six paths ×
two lifecycles, with exact delivery, per-process CPU/RSS and drained queues.
It is dirty-tree macOS evidence, not a release baseline. The initial CI lane
is explicitly a baseline recorder; after its immutable Linux artifacts exist,
lock budgets, make the lane required/strict, and publish current README tables.
No existing performance budget is relaxed. Remaining acceptance includes
a deliberately slow-consumer benchmark, numeric lifecycle memory gates, full verification and current hosted CI. Opaque-PPT regressions
and bounded slow-recipient regressions for both origins pass. The first full
verification stopped at the mutation inventory: adding the caller-state test
requires extending the complete state target inventory. This is fixed and all
93 inventory/runner tests pass; full verification is being rerun.

## Goal and contract

Accept standard MQTT clients, provide a Connectanum MQTT client, and route
explicitly authorized publications between MQTT and WAMP. Release requires
independent interoperability, 100% scoped executable-line coverage, complete
regression rows and numeric live-path performance gates.
The [MQTT contract](../mqtt.md) defines supported transports, ownership, topic
mapping and the still-pending gateway boundary. WAMP `ppt_scheme: mqtt` remains opaque.

## Milestone steps

| Step | State and acceptance |
| --- | --- |
| Contract and coverage foundation, #110–#111 | Bounded codec, topic mapper and scoped coverage implemented; full advertised protocol matrix remains a release prerequisite |
| Live QoS 0, #112–#117, #125–#126 | Native TCP/TLS/WS/WSS, Connectanum/Paho/Mosquitto integration implemented; authorized WAMP gateway remains open |
| Direct MQTT performance, #127 | 20 hosted profiles, exact delivery and unchanged latency/CPU/RSS/rate gates pass on accepted source; matched Intel improvement measured |
| MQTT↔WAMP translation, #131 after #116–#117 | Pending live gateway; require both directions and direct controls, throughput, p95/p99, CPU, peak/steady/post-drain RSS, allocations/queue growth and connect/drain cycles |
| Complete protocol, #118–#123 | QoS 1/2, retained publications/wills, persistence, authentication/authorization and full version-specific properties remain open |
| Release, #124 | Close only after every advertised version/transport/QoS/direction, negative/recovery, coverage, performance and package/operations acceptance passes |

## Accepted evidence

[Package README tables](../../packages/connectanum_bench/README.md) preserve current
results and earlier misses. [Benchmark evidence](../benchmarks/README.md) contains
coverage receipts and the complete archive. Accepted native source SHA-256 is
`f723505558d8ba530aef92f6e9373fc4831f4670517706d917942fa85159cf17`.

Before this cleanup, [CI 40968103538](https://github.com/konsultaner/connectanum-dart/actions/runs/40968103538)
passed all 37 jobs on `538e029c`. Full local `bin/verify`, strict package publishing,
882/882 native added production lines, 651/651 MQTT Dart lines and 268/268 gate
Python lines (zero exclusions) passed. These are scoped coverage counts.

The matched Intel 8370C baseline fails both WS versions twice; the accepted
candidate passes twice with lower CPU. EPYC 7763 passes all 20 profiles. Numeric
budgets are unchanged. Further optimization needs an actual measured failure.

## PR slimming evidence

- [x] Publish, download and independently verify original history, checksums and per-file manifest at the immutable archival tag.
- [x] Retain README tables, compact offline regression inputs, code/tests and current compressed coverage proof; consolidate the contract and working notes.
- [x] Pass focused README/gate regressions, independently compare every fixture field with its archived source, and recompute 882/882 native coverage from the retained traces.

Handoff requires `bin/verify`, strict publishing and green GitHub Actions on the
exact cleanup head. The [PR checks](https://github.com/konsultaner/connectanum-dart/pull/128/checks)
record current hosted acceptance. PR #128 is merged; do not close the broader milestone.

## Verification commands

Run `bin/test-fast` before substantial changes, focused README/gate regressions
during cleanup, then `bin/verify` and `bin/dart-package-publish-dry-run --strict-release-ready`.
CI must retain its existing performance and 100% scoped coverage gates.
Do not replace raw gate inputs with historical fixtures: fixtures check published
tables; CI benchmarks measure the live implementation.
