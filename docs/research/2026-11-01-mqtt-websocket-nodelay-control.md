# MQTT WebSocket TCP_NODELAY control

The isolated `codex/mqtt-websocket-nodelay-control` starts at `7476ff6e`,
excluding the unadopted scheduler, validated-forwarding and shared-frame
prototypes. Native TCP acceptance already enables TCP_NODELAY. Cleartext MQTT
WebSocket upgrade then explicitly set it false, whereas TLS and ordinary
WebSocket paths retain it. The correction keeps it true after MQTT upgrade.
It changes neither framing nor the bounded ready-turn batching, control priority,
permits through flush, ownership/copy boundaries or error handling.

The real socket regression observes the registered connection through a
separately owned duplicated descriptor after complete native negotiation. With
only the test added, exactly one test fails at the actual TCP_NODELAY assertion
(exit 101); after the option correction all 470 Rust core tests and three codec
integrations pass. The observation descriptor does not replace ownership of the
reader/writer socket and the registered connection is explicitly closed.
Malformed negotiation, fragmented input, backpressure and shutdown regressions
remain in the full native suite.

Fresh pre-change bootstrap and full `bin/test-fast` pass on clean `7476ff6e`,
with all three dependency locks unchanged. After the change, a newly built own
ffi-test library passes 36 core MQTT cases and 115 router MQTT cases, including
all seven actual Paho cases across clear and encrypted transports. Its focused
native SHA is `4b77cb823852e2dce3e04b35541c828bf686b0a1c9b82d9beb2a2c92a317ba14`;
tracked source/HEAD, locks and that native binary remain unchanged through those
tests. This is correctness evidence, not a transport/RSS acceptance result.

The independently verified `290eae37` startup repair and matched-native input
retention are ported exactly in three tooling files. All 21 probe and 23 CI
contracts pass. It preserves the sixty-second living-process deadline, all
positive/negative lifetime controls, copy/inventory/body checks and cleanup.
Linux port-range settings are read only; no phase/workload retry is introduced.
Future matched diagnostics retain both actual libraries, both source archives
and the shared lock before collecting rows.

Only the native option/test correction from existing `61bba1c4` is reused;
other gateway, client, host-qualification and budget changes are excluded. Its
prior external run 41322497967 reproduces 120 rows/twelve passing summaries at the
original budgets on EPYC 9V74, but every labelled leg reports the same native
hash. That is not a different-source controlled comparison and cannot prove a
causal repair for this source or the older EPYC 7763 failures.

Before adoption, require own full frozen canonical verification and one complete
predeclared source-controlled comparison: identical compiled Dart broker/client,
both actual native libraries, five original profiles/five interleaved AB/BA pairs,
all 50 rows and 8.05 million fresh fully verified deliveries retained. Preserve
original budgets, windows, warm-up, samples, worker counts and standard SDK,
GC and allocator policy. Full current-source CI/copy and final-runtime strict
48-/50-case acceptance remain required; no failed unchanged numerical gate is
rerun to seek a favorable result. Running predecessor campaigns finish untouched.

RAM and broad WAMP parity remain unresolved. The separate 1% allocation precision
decision for two native MessagePack 1 MiB cases is not waived by the earlier
standard-SDK copy-scope approval. PR #132 stays draft at `40ddcb3f`, based on #130, with no
adoption, retargeting, merge or issue/milestone closure before complete acceptance.

[Correctness audit and exact hashes](2026-11-01-mqtt-websocket-nodelay-correctness-audit.json).
