# Measure and normalize RawSocket input copies

The Dart SDK converts partial byte views before writing. Under backpressure it
can repeat this conversion for the remaining range. Connectanum now supplies
full backing storage: existing full `Uint8List` values pass through, validated
native ranges use the existing lifetime-safe bounded alias, and other inputs
are copied once into a full `Uint8List` before queueing. The fallback records
the actual number of copied bytes. It does not adopt foreign memory.

RawSocket headers now retain their original typed byte arrays rather than
converting to ordinary lists. Contiguous frame construction also records the
header bytes copied into the frame; previously it counted only payload bytes.
The existing wire layout and no-mutation-after-send contract are unchanged.

Twenty-four new fallback cases fail before the repair. Together with three
existing small-frame assertions exposing omitted header accounting, the
fail-first suite has 27 failures. The final socket and metrics suites pass all
81 cases on macOS and Linux arm64. The matrix covers CBOR, MessagePack and
FlatBuffers, two offsets, mutable/read-only views, and registered native,
unanchored native and Dart storage. It verifies bytes, allocation identity,
bounded backing storage and the exact counters.

For large FlatBuffers frames the partial control prefix is copied once; the
payload can retain its original native allocation. Freshly constructed vector
header/padding bytes are not a copy and are not counted. Initial test estimates
incorrectly included these eight bytes; the final assertion uses the control
prefix length and separately verifies the complete decoded message.

The updated Linux CI diagnostic step passes the existing SDK boundary probe,
36 real negotiated RawSocket cases, four SDK backpressure cases and the four
bounded-native cases in both VM and compiled AOT modes. Missing-interposer
controls still reject execution. These are diagnostic pointer and lifetime
checks; they do not establish total SDK, TLS or end-to-end copy accounting.

The bounded GLM review found no concrete defect. Its socket-null and byte-range
questions concern existing call-site contracts; synchronous transport sends
require an open socket and serializer output is bytes. The native helper's
lifetime contract is verified separately by the compiled backpressure probe.
The preceding Qwen review exceeded its output limit and is not review evidence.

Baseline `bin/test-fast` passes. The first canonical `bin/verify` exits 1:
4,957 router cases pass, but the existing FastCGI cumulative stdout-limit
fixture receives a connection reset where it expects clean closure. The
unchanged case passes its isolated repro and five further isolated repeats.
Local Qwen triage suggests an abort-close race; that is not a proven defect.
No assertion, timeout or product behavior was changed. The failed run remains
failed evidence. Fresh `bin/verify` passes at exit 0, including Rust/VM and
consumer checks, 1,563 benchmark, 4,958 router, 4,751 core browser and 2,829
client browser cases, with 20 unchanged native-only skips. The unchanged
FastCGI case passes in that complete run. Evidence:
`/tmp/connectanum-socket-normalization-final-verify.{log,exit}`. Keep #100–#104 and the strict performance gates open. The failed primary
campaign is recorded in [its research note](2026-10-07-primary-flatbuffers-campaign.md);
no build or test work may overlap the next campaign.

[The proof](2026-10-07-rawsocket-input-normalization-proof.json) records source
and log hashes, failed attempts, successful focused checks and review scope.
