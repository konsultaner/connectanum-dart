# Dart FlatBuffers payload fragments and RawSocket framing

The existing Rust segmented writer provides a valid FlatBuffers layout that
retains an already encoded application vector. The Dart writer now follows that
layout through the ordinary `serializeFragments` API. The normal `serialize`
output and pinned wire schema remain unchanged. Control messages and messages
without application vectors return null from `serializeFragments`, preserving
the ordinary serialization path and custom encoder rejection behavior.

The writer builds a small routing envelope containing empty vector placeholders.
After finishing the backwards builder, it finds each table using its end-relative
offset, follows the signed vtable offset and patches the table field's forward
uoffset. It appends a four-byte vector length and padding so vector data starts
at an eight-byte boundary, followed by the exact original Uint8List. It checks
internal table/slot bounds and the aggregate 64 MiB wire limit. Metadata stays
inside the envelope. Existing CBOR validation applies to args and kwargs;
opaque application schemas remain the caller's responsibility.

The retained fragments are ordinary borrowed byte views. They never adopt a
foreign allocation or reinterpret database storage as a Rust Vec. The caller
must preserve immutable contents and a valid owner until transmission completes.
An ObjectBox adapter still needs its own transaction/lease policy. The generic
core adds no ObjectBox dependency. Encoding ordinary Dart arguments as CBOR still
allocates; forwarding already encoded args/kwargs or an opaque body does not
require application List/Map materialization.

Two public fragment-identity regressions fail on `a9907161` before the change.
The focused core suite now covers all seven payload-bearing message families,
encoded args plus kwargs without decoder calls, opaque mutable/read-only/subviews,
empty bodies, presence, alignment, malformed CBOR and aggregate bounds. Rust and
independent pinned Python readers check both contiguous and segmented public
codec output. There is no byte-for-byte layout equality requirement between
these two valid encodings; normal serialization is used as the canonical model
round-trip oracle in the focused tests.

Small RawSocket fragments previously became a payload buffer, then a framed
buffer, copying payload bytes twice. The transport now allocates the negotiated
header plus payload once and writes each fragment directly into it. It records
one frame-payload copy, no intermediate fragment copy. Large frames retain the
existing header-plus-original-fragments sending path. CBOR, MessagePack and
FlatBuffers share this framing repair. Three small-copy regressions fail before
it; the same six codec/size cases also check complete wire bytes, decoded values,
large-body identity and copy counters. Existing negotiation, upgrade, fragmented
receive, malformed-message and queued-send tests remain required.

## Physical pointer diagnostic

The Linux-only [RawSocket probe](../../packages/connectanum_client/tool/rawsocket_copy_probe.dart)
uses the existing [C interposer](../../tool/sdk_socket_copy_probe.c) and a real
loopback peer. It establishes the FlatBuffers HELLO/WELCOME profile before
recording CALL bytes. Its 36 PPT cases cover CBOR/MessagePack/FlatBuffers, 23 and
65,536-byte bodies, full/read-only/partial/read-only-partial calloc storage,
normal writes and large writes capped at 4,096 bytes plus one EINTR. It checks
exact wire bytes, decoded routing/body values, accepted-byte totals, buffer
addresses, active interposition and the isolate-local transport copy counters.
The existing SDK probe supplies independent C and excluded-port controls.
All 36 resulting-source cases pass on Dart 3.13.5 Linux arm64; the
[checked result](2026-10-06-dart-rawsocket-pointer-proof.json) records their
source hashes, routing/body equality, original-body write bytes and copy counters.

Large full/read-only FlatBuffers body views reach libc with the original
65,536-byte allocation and no Connectanum framing copy. Partial views still use
different SDK storage despite zero transport-owned copies. Small sends require
one framed-payload copy. The ordinary pure-Dart CBOR/MessagePack opaque-PPT paths
currently serialize contiguously; this is a different mode from their existing
single-binary-argument segmented support and native owned-PPT submission.

The forced short writes and EINTR exercise `SocketBase::Write`'s native loop,
not a forced Dart-level resumption after EAGAIN. No kernel, TLS, masking, total
SDK/crypto-copy or timing acceptance follows from address identity. Performance
acceptance remains the full declared paired CBOR/MessagePack campaign, including
small frames, ordinary construction and secure/transcoding paths.

After `bin/bootstrap`, reproduce only this diagnostic process on Linux:

```bash
probe_dir="$(mktemp -d)"
cc -shared -fPIC -Wall -Wextra -Werror \
  -o "$probe_dir/socket_probe.so" tool/sdk_socket_copy_probe.c -ldl -pthread
(
  cd packages/connectanum_client
  CONNECTANUM_SKIP_NATIVE_BUILD=1 LD_PRELOAD="$probe_dir/socket_probe.so" \
    dart run tool/sdk_socket_copy_probe.dart
  CONNECTANUM_SKIP_NATIVE_BUILD=1 LD_PRELOAD="$probe_dir/socket_probe.so" \
    dart run tool/rawsocket_copy_probe.dart
)
```

The FlatBuffers Binding CI step runs both probes and uploads their separate
observations in the SDK socket artifact. Resulting-head hosted acceptance and
fresh canonical verification must be recorded independently of earlier passing
prototype checks.


Local companion reviews remain advisory. Pinned `BufferContext.derefObject`
adds a uoffset to the field position, and `_VTable` stores size plus table size
before its schema-indexed entries, including absent entries. These sources and
independent readers disprove the proposed table-relative offset and compacted-slot
changes. The RawSocket large branch returns before the small builder, and `_send0`
only calls Socket.add; adding a frame-copy count there would falsely count a copy
that does not occur. Defensive internal table/slot bounds were added and tested.
The first canonical fast run fails only the exact serializer mutation inventory;
the new test is now included in all four existing VM/browser codec inventories
and the shared suite, with unchanged thresholds. All 80 workflow regressions
pass afterward. Fresh canonical fast/full verification remains required.


The next fast attempt reproduces two failures in the unchanged transport profile
suite: a codec subclass's HELLO/GOODBYE serialization errors were bypassed by the
fragment method. Controls and absent-vector messages now keep the normal
serialization path. All 22 existing profile tests and all 61 fragment tests pass
with that repair. The public interoperability driver falls back to normal output
when fragments are unavailable, while retaining separate files for both modes.
The exact updated Linux workflow step passes the SDK probe, all 36 RawSocket PPT
cases and the absent-interposer control. The checked source hashes match that
executed tree. These focused repairs do not replace canonical full verification.


Final quiet `bin/verify` passes at exit 0, including the unchanged worker
readiness case in all 1,563 benchmark cases, 4,958 router cases, 4,751 core
Chrome/Dart2Wasm cases and 2,829 client browser cases with 20 declared native-only
skips. The final independent interop command passes after the control fallback
repair: 33 upstream fixtures, 42 extended fixtures and all 25 public messages
in contiguous and segmented Dart output. The earlier inventory, control-path
and worker-deadline failures remain failed evidence. Final sequential
`bin/test-fast` also passes at exit 0, including all 1,563 benchmark cases and
the unchanged readiness regression. Publication awaits the existing hosted
mutation run; no whole-copy or performance acceptance is claimed.
