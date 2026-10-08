# Empty outer keyword maps in native PPT forwarding

Status: implemented; focused, GuardMalloc and canonical fast/full checks pass locally. Resulting-head hosted acceptance remains pending.

The [WAMP Payload Passthru message structure](https://wamp-proto.org/wamp_latest_ietf.html) permits an absent or empty outer keyword map alongside the single binary argument. [Empty arguments and keyword arguments](https://wamp-proto.org/wamp_latest_ietf.html) recommends omitting empty outer maps. These are outer routing containers; they do not change the opaque application's inner arguments.

The current native body bridge rejects all present keyword maps. Validate the exact CBOR or MessagePack empty-map span, including legal length encodings, without decoding an application value or allocating a map. Normalize it to absent when rebuilding a different binary envelope. Retain nonempty, wrong-kind, truncated or trailing-byte containers on the existing fallback. FlatBuffers transparent bodies still exclude argument/keyword vectors; accepting encoded CBOR/MessagePack empty maps must not relax that validator.

Regression coverage must prove all four mixed directions from CBOR/MessagePack, the five existing forwarding kinds, metadata, nonempty pointer identity, empty-body lifetime and exactly one final fan-out release. Invalid-shape eligibility checks must leave the original source handle available. These are routing/ownership checks, not whole-pipeline copy counts or performance acceptance.

Baseline `bin/test-fast` exits 0. Four new direction regressions first fail at eligibility (exit 101). The repair passes all 26 segmented tests. Nine body sizes, five forwarding kinds, four mixed directions and six CBOR/three MessagePack empty-map forms add 810 identity/lifetime combinations to the prior 405. Each header form also parses from a complete CALL frame through the actual native decoder. CBOR length headers and the exact empty indefinite map are accepted; MessagePack fixmap/map16/map32 are accepted. The recognizer is bounded to the header and checks the complete span, without allocating or decoding a map. Malformed, trailing and wrong-kind controls retain source-handle availability; FlatBuffers transparent-plus-keywords remains rejected.

Evidence: `/tmp/connectanum-empty-ppt-kwargs-{baseline-fast,before,segmented-with-wire}.{log,exit}`.

GuardMalloc observes and passes 87 ownership cases; all 141 native/schema input hashes match. Local Qwen test planning and review completed. Source and the 810-case matrix disprove its suggested logic inversion, missing indefinite-map acceptance and wrong-kind acceptance. The early return recognizes only the exact empty indefinite CBOR map; definite headers must consume the entire span, and MessagePack accepts only the three complete empty-map encodings. Normalizing empty outer keywords removes no inner application data. FlatBuffers mixed-vector rejection preserves its existing profile contract. Evidence: `/tmp/connectanum-empty-ppt-kwargs-guardmalloc/report.json`. Fresh `bin/verify` passes at exit 0, including Rust, VM, consumer/live
checks, 1,563 benchmark, 4,958 router, 4,690 core Chrome/Dart2Wasm and 2,829
client browser cases (20 declared native-only skips). Final native input hashes
are unchanged. Evidence: `/tmp/connectanum-empty-ppt-kwargs-verify.{log,exit}`.
