# Dart SDK copy boundaries for serializer benchmarks

Status: source audit, layout diagnostic and Linux socket pointer verification; total copy counters and performance acceptance remain incomplete.

The local macOS SDK is 3.13.1, commit `852b3e3608906afbe6102573cfd4407aeedd1b78`; the Linux consumer SDK is 3.13.5, commit `04bcd1036cdc799ac6564988f159ee454d42c822`. Annotated tags are resolved to commits. The relevant four files below have identical bytes in these versions. Source hashes are retained in `/tmp/connectanum-dart-sdk-copy-research/sources.json`.

[Socket coercion](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/sdk/lib/io/common.dart#L123) retains a Uint8List only when its length equals its backing ByteBuffer length. Other lists and partial views allocate a new byte list and copy the requested range. Dart-level resumption after native backpressure can call this boundary again, so frame length alone cannot establish the total. The forced short-write diagnostic below exercises native retries and does not force that Dart resumption.

[Native socket write](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/runtime/bin/socket.cc#L738) acquires typed-data storage, applies the offset and delegates to SocketBase::Write. This identifies another boundary to verify; it is not a proof that all platform/API internals copy zero bytes.

The pinned Linux SDK's
[typed-data API](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/vm/dart_api_impl.cc#L4122)
normally returns the managed/external storage address, including view offsets,
inside a no-safepoint/no-callback scope. Its
[`verify_acquired_data` flag](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/vm/dart_api_impl.cc#L83)
defaults to false; the installed SDK's verbose help also reports that default.
When enabled, it copies managed data into temporary storage on acquisition and
copies it back on release through
[`AcquiredData`](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/vm/dart_api_impl.cc#L4091).
External data remains in place even with that flag. SDK flags must therefore
be retained when measuring this boundary. This is a source finding, not a new
measured managed-buffer or total-copy result. The Gemma summary omitted the
copying constructor outside its selected range; direct inspection supplies
that distinction.

[Binary WebSocket masking](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/sdk/lib/_http/websocket_impl.dart#L1085) first copies binary Uint8List data, then masks that new storage in place. Header storage and the returned reference list are separate from this body copy. Text and compression use different paths; the binary result cannot establish their counters.

[Secure-socket ring writes](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/sdk/lib/io/secure_socket.dart#L1372) copy into ring storage. The native filter subsequently calls SSL_write and BIO operations; accepted plaintext volume does not count their internal memory copies. TLS totals remain unavailable.

A commit-pinned `9b28c61c` public consumer diagnostic serializes ordinary CALL frames with binary body sizes 0, 1, 23, 256 and 65,536. All ten CBOR/MessagePack outputs have complete backing buffers. All five FlatBuffers outputs are partial views: for the 256-byte body, the frame is 384 bytes in 1,024 backing bytes at offset 640. Those outputs fail the pinned SDK's full-buffer condition if passed unchanged to a socket. The actual pre-segmentation FlatBuffers RawSocket path first builds a contiguous framed buffer, so this serializer-only observation does not demonstrate a subsequent SDK copy on that path. This is a layout observation and source-backed conditional-copy finding, not timed performance or an observed full transport total. Evidence: `/tmp/connectanum-dart-sdk-copy-research/serializer-views.jsonl` and `/tmp/connectanum-9b28c61c-public-consumer/bin/sdk_views.dart`.

Reproduce the layout diagnostic in a workspace Dart program with the public packages:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;

void main() {
  final codecs = {'cbor': cbor.Serializer(), 'msgpack': msgpack.Serializer(),
    'flatbuffers': flat.Serializer()};
  for (final size in [0, 1, 23, 256, 65536]) {
    for (final codec in codecs.entries) {
      final bytes = codec.value.serialize(
        Call(42, 'com.probe', arguments: [Uint8List(size)]),
      ) as Uint8List;
      print(jsonEncode({'codec': codec.key, 'body': size,
        'frame': bytes.length, 'backing': bytes.buffer.lengthInBytes,
        'offset': bytes.offsetInBytes,
        'sdkFullBufferCondition': bytes.buffer.lengthInBytes == bytes.length}));
    }
  }
}
```

## Observed Linux socket pointer boundary

On Linux arm64 with Dart 3.13.5, the checked-in
[Dart probe](../../packages/connectanum_client/tool/sdk_socket_copy_probe.dart)
uses `calloc` storage with a known input address. Its
[C interposer](../../tool/sdk_socket_copy_probe.c) delegates real socket writes
and records their buffer addresses, requested/submitted sizes, accepted bytes
and errors. It selects exactly one loopback peer port and never records payload
contents. The pinned SDK's
[POSIX implementation](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/bin/socket_base_posix.cc#L192)
calls this libc `write` boundary.

All eight SDK cases pass: mutable and read-only full 256-byte external views
reuse their original addresses; mutable and read-only 96-byte subviews at
offset 32 in 256-byte storage use different addresses. Each shape runs normally
and with actual writes capped at 31 bytes plus one injected `EINTR`. Full-view
addresses advance by accepted bytes inside the SDK's native
[SocketBase::Write loop](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/bin/socket_base.cc#L299).
This corrects the earlier attribution to the Dart stream consumer. The native
loop keeps calling WriteImpl until completion or actual backpressure. Capping
writes and injecting EINTR does not force Dart-level EAGAIN resumption. A temporary
fake-EAGAIN experiment timed out because it did not create a real readiness
transition; that failure is retained and is not retry evidence.
All received lengths and bytes match. Full retry cases each observe ten calls;
partial retry cases each observe five, including the one interrupted call.

An independent C write verifies the interposer and original address. A second
listening port proves unselected traffic produces no observations while its
payload still arrives. Running without `LD_PRELOAD` fails at the required
`probe_reset` lookup, so an inactive interposer cannot produce a false pass.
The compact [result](2026-10-06-dart-sdk-socket-pointer-proof.json) records these
cases and source hashes; complete raw observations remain in
`/tmp/connectanum-dart-sdk-copy-research/socket-probe.jsonl`.

Reproduce on Linux from the repository root after `bin/bootstrap`:

```bash
probe_dir="$(mktemp -d)"
cc -shared -fPIC -Wall -Wextra -Werror \
  -o "$probe_dir/socket_probe.so" tool/sdk_socket_copy_probe.c -ldl -pthread
(
  cd packages/connectanum_client
  CONNECTANUM_SKIP_NATIVE_BUILD=1 LD_PRELOAD="$probe_dir/socket_probe.so" \
    dart run tool/sdk_socket_copy_probe.dart
)
```

The FlatBuffers CI job runs this probe and the missing-interposer control,
then uploads `sdk-socket-pointer` observations and failure-control logs. The
exact workflow step passes locally in the isolated Linux consumer archive.
All 80 existing verification-tool regressions pass. Hosted execution passes on Dart 3.13.5 Linux x64 in PR run
37523101879; its downloaded eight cases and two controls match the local
arm64 boundary observations. This does not accept the entire CI run. The initial local step attempt passed its pointer
cases but failed because the minimal container lacks `rg`; the control now
uses Python and the complete step passes. Both attempts are retained.

Preload only this diagnostic process. Its selected test socket deliberately
receives short writes and an interrupted call. This is not a timing benchmark.
The input is explicitly `calloc` storage, not a database lease or a Rust-owned
model. Address reuse proves this boundary's behavior for these external views;
it does not measure kernel copies, TLS, masking, total SDK copy traffic or all
serializer/transport combinations. In particular, summing syscall requests
would double-count an interrupted retry and cannot serve as a copy counter.

The local Qwen review completed. Its FFI objection confused Dart's ordinary
`int` call signature with the correctly declared native `UintPtr` ABI. Its
retry objection contradicts the native loop and received payloads; it does not establish Dart-level backpressure resumption.
The proposed relaxation of the interrupted-call assertion would weaken the
positive control, so the exact assertion remains. No review finding required
a production change. A separate workflow review also completed. Its path
findings expand `$PWD` after `cd`, contrary to the actual assignment order.
The variable captures the root directory before changing directories; the exact
script passes and both evidence files exist at the root upload path. Its
preload/exit-code discussion identifies no source defect. No review suggestion
was used to relax the controls.

Next instrumentation must distinguish per-attempt coercion copies, per-frame binary masking, explicit TLS ring copies and cryptographic/internal buffering. An optimization should remove the extra physical copy where ownership permits, or expose an unavoidable copy accurately; merely moving it into a serializer does not make a zero-copy path. Retain the existing missing-metric rejection and full primary matrix until independently verified counters cover the active paths.


The [segmented Dart sending follow-up](2026-10-06-dart-flatbuffers-segmented-send.md)
checks the actual RawSocket pipeline separately. Large FlatBuffers opaque bodies
can be retained as send fragments; partial views still cross the pinned SDK's
copy boundary. Small fragments are joined directly into their framed buffer once.
None of these diagnostics establishes total SDK/TLS copies or benchmark parity.


The [real backpressure follow-up](2026-10-07-dart-sdk-backpressure.md) now
observes genuine EAGAIN, pending flush and later Dart socket resumption in all
four 16 MiB view cases. Full views retain original storage across resumed
writes; partial views use copied storage. This separately supplies the event-loop
boundary that forced native short writes/EINTR did not establish. It remains a
pointer diagnostic, with total SDK/TLS/transcode/crypto copies and parity open.
