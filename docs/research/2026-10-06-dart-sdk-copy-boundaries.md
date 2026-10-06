# Dart SDK copy boundaries for serializer benchmarks

Status: source audit and diagnostic only; counters and performance acceptance remain incomplete.

The local macOS SDK is 3.13.1, commit `852b3e3608906afbe6102573cfd4407aeedd1b78`; the Linux consumer SDK is 3.13.5, commit `04bcd1036cdc799ac6564988f159ee454d42c822`. Annotated tags are resolved to commits. The relevant four files below have identical bytes in these versions. Source hashes are retained in `/tmp/connectanum-dart-sdk-copy-research/sources.json`.

[Socket coercion](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/sdk/lib/io/common.dart#L123) retains a Uint8List only when its length equals its backing ByteBuffer length. Other lists and partial views allocate a new byte list and copy the requested range. Short-write retries can call this boundary repeatedly, so frame length alone cannot establish the total.

[Native socket write](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/runtime/bin/socket.cc#L738) acquires typed-data storage, applies the offset and delegates to SocketBase::Write. This identifies another boundary to verify; it is not a proof that all platform/API internals copy zero bytes.

[Binary WebSocket masking](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/sdk/lib/_http/websocket_impl.dart#L1085) first copies binary Uint8List data, then masks that new storage in place. Header storage and the returned reference list are separate from this body copy. Text and compression use different paths; the binary result cannot establish their counters.

[Secure-socket ring writes](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/sdk/lib/io/secure_socket.dart#L1372) copy into ring storage. The native filter subsequently calls SSL_write and BIO operations; accepted plaintext volume does not count their internal memory copies. TLS totals remain unavailable.

A commit-pinned `9b28c61c` public consumer diagnostic serializes ordinary CALL frames with binary body sizes 0, 1, 23, 256 and 65,536. All ten CBOR/MessagePack outputs have complete backing buffers. All five FlatBuffers outputs are partial views: for the 256-byte body, the frame is 384 bytes in 1,024 backing bytes at offset 640. Those outputs fail the pinned SDK's full-buffer condition. This is a layout observation and source-backed conditional-copy finding, not timed performance or an observed full transport total. Evidence: `/tmp/connectanum-dart-sdk-copy-research/serializer-views.jsonl` and `/tmp/connectanum-9b28c61c-public-consumer/bin/sdk_views.dart`.

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

Next instrumentation must distinguish per-attempt coercion copies, per-frame binary masking, explicit TLS ring copies and cryptographic/internal buffering. An optimization should remove the extra physical copy where ownership permits, or expose an unavoidable copy accurately; merely moving it into a serializer does not make a zero-copy path. Retain the existing missing-metric rejection and full primary matrix until independently verified counters cover the active paths.
