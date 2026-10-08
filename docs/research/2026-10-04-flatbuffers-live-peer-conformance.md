# Independent live FlatBuffers peer findings

Date: 2026-10-04. Milestone issues #95, #99, #100 and #102 remain open.

## Profile and interoperability boundary

The vendored Autobahn schema is pinned at
`ca1e60c7f7dd78dc2df98a3b7bdc274ae197ae9c`. Its original seven schema hashes
verify against the manifest. Python readers/builders are freshly generated using
flatc 25.9.23 and the matching FlatBuffers runtime. The live negotiated-profile
peer additionally uses cbor2 5.7.1 and websockets 15.0.1.

The first upstream-only peer fails before CHALLENGE with `metadata presence`.
This is consistent with the current strict metadata-v1 profile. Generated
upstream-reader compatibility is weaker than successful upstream-only sessions.
`FlatBuffersSessionProfile` exposes client/router profiles requiring metadata-v1;
it has no public trusted upstream-subset constructor. Keep that limitation
explicit. Do not remove dictionary preservation or capability checks to pass the
upstream-only probe. The documented constraints for a future explicitly trusted,
lossless subset mode remain requirements, not evidence that one is implemented.

The separate live peer uses generated bindings from the derived schema and
independent socket/WebSocket/CBOR runtimes. It offers metadata-v1 in all applicable
roles and checks acknowledgement in both CHALLENGE and WELCOME. Missing/false
offers abort before credentials. A bare upstream HELLO is a negative control.
This is an independent implementation of Connectanum's negotiated profile; it
is not an Autobahn session implementation or a claim of arbitrary peer support.

## Cancellation defect and correction

The independent killnowait assertion expects `wamp.error.canceled`. The official
[WAMP cancellation specification](https://wamp-proto.org/wamp_latest_ietf.html)
uses that URI when the Dealer cancels a call. The
[Basic Profile standard error list](https://wamp-proto.org/wamp_bp_latest_ietf.html)
also defines it for call cancellation.

Actual native-router traffic instead returns request type 48, request 303 and
`wamp.error.invocation_canceled`, with an empty details dictionary. The source of
that URI is the shared `Error.errorInvocationCanceled` constant. Existing router
regressions compare the output against the same constant, so they do not detect
the mismatch. The isolated candidate changes the shared wire value to the
standard URI while preserving benchmark acceptance of incoming legacy URI values.
The public constant name remains available.

## Executed evidence and remaining work

- Initial upstream rejection: `/tmp/connectanum-flatbuffers-live-upstream-peer-initial.log`.
- Extended-profile cancellation failure and actual fields:
  `/tmp/connectanum-flatbuffers-live-metadata-peer-cancellation-diagnostic.log`.
- Passing strengthened production-library peer report on cleartext RawSocket and
  WebSocket: `/tmp/connectanum-flatbuffers-live-metadata-peer-production-expanded/report.json`.
- Legacy URI failure control:
  `/tmp/connectanum-flatbuffers-live-peer-cancellation-failure-control-proof.json`.
  Its underlying conformance report remains failed.
- Existing cancellation controls: 48 passing benchmark/router tests in
  `/tmp/connectanum-flatbuffers-live-cancel-focused-regressions.log`.

The peer exercises invalid/valid ticket authentication, distinct sessions,
zero/small/96-KiB fragmented RPC with wide IDs, binary and UTF-8 values and kwargs,
progressive/final results, callee error remapping, killnowait/interrupt,
acknowledged pub/sub, unsubscribe/unregister, missing procedure and goodbye.
These are protocol correctness checks, not throughput, latency or copy evidence.

The candidate and CI checker are now applied to the feature tree, after the
unchanged-setting complete benchmark reproduction passed all 1,366 cases. The
preceding full verification failure stays recorded; its cause is unestablished.
Actual feature/production-library peer proof is independently audited in
`/tmp/connectanum-flatbuffers-live-peer-feature-completed-audit.json`, including
all 1,458 frozen source files and 69 freshly regenerated binding files. Fresh
canonical and browser coverage runs remain pending before commit/push.
Hosted execution, other release platforms, secure transports, fuzzing and complete
milestone conformance acceptance remain unproven. No issue is closed by this probe.

## Hosted checkpoint (2026-10-06)

[PR CI run 37457588251](https://github.com/konsultaner/connectanum-dart/actions/runs/37457588251)
for feature source `5f1afae9` passes FlatBuffers Binding, including fresh upstream
reader/writer interoperability and the independent negotiated-profile live peer.
The [live peer report](https://github.com/konsultaner/connectanum-dart/actions/runs/37457588251/artifacts/11411135812)
records passing cleartext RawSocket and WebSocket flows: credential rejection,
distinct sessions, empty/small/fragmented RPC, wide IDs, binary/UTF-8/kwargs,
progressive/final results, errors, cancellation, acknowledged pub/sub, cleanup
and goodbye. It also passes the upstream-only negative control. This is the
generated-schema metadata-v1 peer, not an Autobahn session implementation.

The same run's [GuardMalloc evidence](https://github.com/konsultaner/connectanum-dart/actions/runs/37457588251/artifacts/11409896508)
passes 73 instrumented native cases. Its checkout is GitHub's PR merge commit
`2363f6e5`; all 140 source/configuration/schema hashes match the feature tree.
The report's retained Cargo lock and log hashes independently verify. Its
resolved dependency lock differs from the local lock, so the hosted result is
evidence for that recorded build, not an identical local native executable.

Fast Checks hits the separate 20-minute aggregate job limit, which skips Full
Verify and VM coverage. Their acceptance is still pending. These hosted probes
do not establish TLS, all-platform session conformance, complete malformed-input
coverage, full copy totals or serializer performance parity.
