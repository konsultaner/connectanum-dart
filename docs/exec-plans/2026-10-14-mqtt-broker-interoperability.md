# MQTT broker interoperability

Status: active
Owner: Codex
Created: 2026-10-14
Last updated: 2026-10-14
Branch: `codex/mqtt-broker-interoperability` in a separate managed worktree
Milestone: [GitHub milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2); parent [#109](https://github.com/konsultaner/connectanum-dart/issues/109)
Baseline: GitHub master `73d840c9`; pre-change `bin/test-fast` passes on 2026-10-14

## Goal

Connectanum accepts standard MQTT clients and routes authorized publications among MQTT and WAMP participants. A public Connectanum MQTT client works against Connectanum and an independent broker. The advertised MQTT profile passes independent-client conformance, 100% in-scope executable-line coverage, complete automated regression rows, and numeric live-path performance gates before release.

## Scope

- MQTT 5.0 and 3.1.1; TCP/TLS and MQTT over WebSocket; bounded packet decoding and protocol negotiation.
- Connection identity, authentication, topic filters, QoS 0/1/2, retained publications, wills, persistent sessions and offline delivery.
- A protocol-neutral publication boundary with byte payloads and explicit MQTT↔WAMP topic, authorization, metadata and loop rules. WAMP `ppt_scheme: mqtt` remains opaque unless an authorized gateway API explicitly opts in.
- Public Connectanum MQTT client mode, Eclipse Paho side-by-side integration, and a Mosquitto reference-broker control.
- Benchmarks of real MQTT publish/subscribe paths, including secure transports, fan-out, mixed WAMP traffic, throughput, p95/p99 latency, CPU, RSS and overload behavior.

## Preconditions

- Preserve the existing WAMP CI chain and do not close any issue on unit-only or unrun evidence.
- Use OASIS MQTT 5.0 and 3.1.1 plus WAMP specifications as the protocol contract. Check source-backed research into `docs/research/` as choices become concrete.
- Keep one owner of MQTT session/QoS state. Start with a measurable live path, then integrate negotiation with the native transport; do not infer a zero-copy or performance benefit without matched measurements.

## Plan

1. **Contract and coverage foundation (#110–#111).** Define the advertised feature/rejection matrix, topic and principal mapping, packet fixtures, per-source 100% line-coverage gate, and automated regression row inventory. Begin with fail-first fixed-header/framing tests and a bounded shared codec.
2. **First live QoS 0 checkpoint (#112–#117, #125–#126).** Add MQTT listener and Connectanum client pub/sub paths, broker publication boundary, topic filters, and explicit WAMP gateway. Run Paho and Connectanum clients against the router in both directions and a Mosquitto control, asserting exact bytes and delivery counts.
3. **Measure before tuning (#127).** Capture the first immutable end-to-end QoS 0 baseline, define checked-in numeric throughput/latency/CPU/RSS budgets, and add failing CI artifact gates. Compare matched Mosquitto workloads and preserve raw evidence. Profile bottlenecks before moving framing or changing ownership boundaries.
4. **Complete protocol behavior (#118–#123).** Add MQTT 5 properties/capabilities, QoS 1/2, persisted sessions, retained publications/wills and MQTT 3.1.1 compatibility. Extend client, conformance and benchmark matrices after each feature.
5. **Release gate (#124).** Verify every advertised version × transport × QoS × direction row, authorization/negative/recovery cases, 100% in-scope line coverage, complete passing regression matrix, live benchmark budgets, hosted CI, consumer/package artifacts, operations docs and release notes. Close the milestone only after the evidence is linked.

## Verification

- Pre-change `bin/test-fast`: passed on 2026-10-14.
- Focused MQTT frame/packet tests pass on VM and Chrome; Paho 2.1.0 MQTT 5/3.1.1 binary side-by-side integration passes with the provisional broker.
- [First live QoS 0 baseline](../benchmarks/mqtt-qos0-2026-10-14.md): five matched local runs versus Mosquitto 2.1.2 with exact delivery checks.
- Provisional five-run relative throughput/p95/p99 budget passes locally and is wired to a dedicated Paho/Mosquitto CI lane. A 10,000-message unpaced Mosquitto reference burst did not meet exact-delivery deadline, so sustained/overload methodology remains open.
- The hosted MQTT lane passes on PR #128's first run with throughput ratio 1.168, p95 ratio 0.866 and p99 ratio 0.855; raw artifacts are attached to the job. The versioned topic URI mapper is implemented with focused 100% VM/Chrome coverage, but no MQTT/WAMP gateway routing exists yet.
- A second local `bin/test-fast` passes. The provisional anonymous broker is now loopback-only after a fail-first test. The [clean-tree AOT process-isolated baseline](../benchmarks/mqtt-qos0-aot-2026-10-14.md) passes five local runs at commit `078e85c7` for both the 2,000-message burst and the 200,000-message windowed sustained profile. The latter has throughput ratio 0.994, p95 ratio 1.012, p99 ratio 0.993, CPU ratio 1.184 and Connectanum broker RSS 19.8 MB; both brokers deliver 1,000,000/1,000,000 messages with no duplicates. Raw and summary JSON are checked in. Hosted AOT evidence remains pending.
- Focused current-source VM LCOV: frame codec 111/111, packet codec 161/161, topic mapper 37/37, client 75/75 and broker 94/94 executable lines. Focused Chrome/dart2js LCOV, after the repository's documented enum-declaration source-map classification: frame 116/116, packet 179/179 and mapper 45/45. The Paho 2.1.0 side-by-side integration passes again after the loopback guard.
- Hosted CI at `128b0db1` [failed in the MQTT job](https://github.com/konsultaner/connectanum-dart/actions/runs/38558800048/job/115835029990) while collecting provenance: Ubuntu Mosquitto exits 3 for `-h`, despite the version-bearing help output. The uploaded partial artifact has ten 2,000-message burst rows with exact delivery and no duplicates, but no completed summary or sustained run. A fail-first Python regression now covers exit 3 and parses the version without treating help's exit code as a benchmark failure. The hosted burst rows were too short and noisy for a stable relative performance gate, so it is now an exact-delivery smoke profile; numeric throughput, p95/p99, CPU and RSS gates remain on the 200,000-message sustained profile. Local Python controls and both live profiles pass after this fix; hosted rerun is pending.
- Hosted CI at `b8bc66e7` [fails the sustained numeric gate](https://github.com/konsultaner/connectanum-dart/actions/runs/38559526448/job/115837514562) after full exact delivery. Five matched Linux AOT runs have Connectanum median 28,893 delivered/s versus Mosquitto 107,651; p95 is 22.26 times the control and shows repeated 40–80 ms stalls. This hosted benchmark is the fail-first performance repro. Broker-side TCP_NODELAY alone lowered local absolute throughput to 264,947 delivered/s, versus 390,969 for Mosquitto; combining it with per-event publication batching restored 401,753 versus 399,762 delivered/s, p95 ratio 1.013 and broker CPU ratio 1.070. The Connectanum client setting remains unchanged so the reference workload is unaffected. Focused broker coverage is 102/102 lines; the numeric budget is unchanged until a hosted rerun proves it.
- Post-change `bin/verify`: passed on 2026-10-14 after the new MQTT lane was added to the CI prerequisite inventory. The first attempt failed at the pre-existing hardcoded CI job-set test; the job set and its negative control were updated, then the full rerun passed. A second `bin/verify` passes after the AOT benchmark, topic mapper and broker loopback guard changes.
- Focused fail-first and implementation tests for each packet/session/broker change.
- `bin/test-fast` during implementation and `bin/verify` before handoff.
- Hosted CI, independent Paho/Connectanum/Mosquitto integration, and benchmark artifact gates before issue or milestone closure.

## Decision log

- 2026-10-14: User explicitly reprioritized MQTT completion and performance. Work is isolated from the existing mutation branch. The first benchmark must measure real pub/sub and delivery correctness; synthetic packet echo is insufficient. Local architecture advice favors one Dart owner for MQTT state and measurement before native framing optimization; verify this against source, tests and benchmark data.

## Handoff

Open. Packet codec, provisional loopback TCP QoS 0 broker/client, Paho integration, focused 100% MQTT source coverage, reversible topic mapping, first hosted interoperability/burst gate, and a clean-tree local AOT sustained CPU/RSS baseline are in progress. Native negotiation, WAMP gateway, protocol completeness, final benchmark matrix and release gate remain open. Current post-change `bin/verify` passes; hosted sustained evidence is pending.
