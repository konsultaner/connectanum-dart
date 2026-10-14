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
- Provisional five-run relative throughput/p95/p99 budget passes locally and is wired to a dedicated Paho/Mosquitto CI lane; hosted result remains pending. A 10,000-message unpaced Mosquitto reference burst did not meet exact-delivery deadline, so sustained/overload methodology remains open.
- Post-change `bin/verify`: passed on 2026-10-14 after the new MQTT lane was added to the CI prerequisite inventory. The first attempt failed at the pre-existing hardcoded CI job-set test; the job set and its negative control were updated, then the full rerun passed.
- Focused fail-first and implementation tests for each packet/session/broker change.
- `bin/test-fast` during implementation and `bin/verify` before handoff.
- Hosted CI, independent Paho/Connectanum/Mosquitto integration, and benchmark artifact gates before issue or milestone closure.

## Decision log

- 2026-10-14: User explicitly reprioritized MQTT completion and performance. Work is isolated from the existing mutation branch. The first benchmark must measure real pub/sub and delivery correctness; synthetic packet echo is insufficient. Local architecture advice favors one Dart owner for MQTT state and measurement before native framing optimization; verify this against source, tests and benchmark data.

## Handoff

Open. Packet codec, provisional TCP QoS 0 broker/client, Paho integration, focused 100% MQTT source coverage, first local performance gate and full repository verification pass locally. Native negotiation, WAMP gateway, protocol completeness, final CPU/RSS and transport budgets, and hosted CI remain open.
