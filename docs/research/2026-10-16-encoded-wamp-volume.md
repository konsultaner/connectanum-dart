# Serialized WAMP message volume

Issue: [#103](https://github.com/konsultaner/connectanum-dart/issues/103).

## Reproduced reporting error

The former comparison evidence key `wire_bytes` summed application bytes from
operation samples. A fail-first reference campaign reports request/response
30,000/30,000 under that label without observing any encoded message length.
Those observations are now labelled `application_bytes`; they cannot certify
encoding size. Existing performance budgets, primary cases, sample counts,
durations, repetitions and coverage/mutation floors are unchanged.

## Independent observation

`accepted_wamp_message_bytes_v1` measures serialized message volume accepted by
Connectanum's send queue. It excludes RawSocket/WebSocket framing, TLS records
and network packet headers. It is not completed network delivery. Failed
workloads cannot establish successful benchmark acceptance. Deferred/file frames
contribute their validated advertised encoded message size at acceptance.

Dart RawSocket counts the payload once after all fragments are accepted, or when
the pre-handshake queue accepts the payload. Flushing that queue does not count
again. Dart WebSocket counts the serialized bytes after submission; browser
strings use UTF-8 length including replacement of malformed surrogates. Rust
observes the common data-frame enqueue paths, counts successful payload lengths,
and records rejected submissions. Protocol controls and write barriers do not
contribute. Native transports are counted in Rust and are not counted again in
the Dart transport observer.

Two optional versioned scalar C getters expose native accepted bytes and
rejections. The existing six-u64/48-byte copy ABI and its capability versions
are unchanged. Both new symbols must exist to advertise volume observation;
older native libraries remain usable with encoded volume unavailable.

Snapshots retain four disjoint process components: client Dart, client native,
router Dart (main isolate plus stable workers), and router native. Existing
quiescence, worker identity and boss generation checks apply. Every counter must
be an exact nonnegative integer within the JSON-safe range, monotonic and
versioned. Rejections, missing components, overflow, rewinds and unavailable
symbols prevent complete measurement. Observed zero remains a valid component.

The human comparison reports the median accepted serialized bytes per application
operation for every case/codec, retaining every repetition. A missing observation
renders unmeasured rather than dropping that repetition. Raw totals and all four
process components remain in the JSON report.

Encoded volume is reported separately and never added to E2EE, transcode or
other buffer-copy totals. The comparison independently verifies the four
components, total, failure count, scope and transport exclusions.

## Verification

Focused verification passes: 825 combined ownership/volume/pipeline cases,
38 Python comparison cases, 85 VM transport cases, 122 native ABI/provider/runtime
cases, the native send-queue and 48-byte ABI regressions, and 25 core / two client
browser cases under both JavaScript and WebAssembly. Analysis has no errors or
warnings (30 existing informational lints). All 154 source-bound mutation proofs
validate; four unchanged unused-browser-parameter proofs were mapped to their
shifted AST positions and rechecked without changing inventories or floors.
The first browser invocation from the workspace root used conflicting package
routes and failed loading; the canonical package-root invocations pass.
The prior production library without either new symbol passes the same isolated
ABI probe, with volume explicitly unavailable. Copy-only snapshot map shapes
remain unchanged; separate boundary snapshot methods carry the new observations.
Resulting-source full verification and live encoded-volume proof remain pending.
Regression coverage includes every
UTF-16 code unit, valid/invalid surrogate boundaries, exact actual transport
message sizes, fragmented RawSocket and WebSocket sends, full/closed/missing/
unsupported native queues, deferred sizes, protocol-control exclusion, optional
ABI compatibility and malformed or forged aggregate observations.

## Latest performance baseline

Source `f2dc00f09975a54fd2597923ad084620e9c99b8e` completes the
[90-row Linux diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/38859076426).
CPU ratios against the better baseline are 1.09915 / 1.11761 / 1.09437 for
Dart values / native buffers / pre-encoded spans. Allocation ratios are
0.94740 / 1.05324 / 0.94827. Numerical parity still fails; the campaign is
also explicitly ineligible for primary acceptance.

An independent audit recomputes all 180 allocation observations without
findings. All sample/duration boundaries and all measured RSS endpoints are
valid. Two warmup lifetime-RSS endpoints remain unavailable after three actual
contradictory reads; their observations are retained, not inferred. No result
is silently omitted or accepted as a full primary campaign. All 120 live copy
cases and 170 five-platform native consumer cases pass for that source.

Actual encoded-volume reporting and the extension diagnostics must accompany a
fresh primary campaign once credible diagnostic parity is demonstrated.

A quiet macOS CPU probe at `f2dc00f0` records 419 FlatBuffers versus 463
MessagePack client Dart samples, and 81 versus 104 routing-worker Dart samples.
The byte-vector loop is no longer a dominant function. Native active samples
are too sparse to identify a Rust bottleneck, and this platform-specific probe
does not establish Linux parity. Raw VM/native stacks and unchanged-source
hashes are retained for follow-up profiling.

The 120 live cases at `1b751b72` pass independent encoded-volume and copy
audits with all 3,108 inputs unchanged. The production library SHA-256 is
`a7117d6f08b353269d1ebd689adc5bbe03c73629e2f3b3ef1ef5fc67d4adecbe`.
Whole-source verification and hosted Fast Checks both reproduce 16 failures
in an older synthetic fixture producer that lacks the new volume carriers.
The fixture producer now uses explicit synthetic observations through the
real delta/merge helpers; the independent Python test recomputes their disjoint
components and corrupts a subtotal to require rejection. This repair does not
substitute synthetic evidence for the separately passing live matrix.
