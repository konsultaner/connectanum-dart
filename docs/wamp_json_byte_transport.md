# Large JSON messages over Dart IO WebSockets

The file-transfer workload sends four 64-MiB files with 4-MiB binary chunks.
Its WAMP JSON representation expands each chunk to base64. The ordinary SDK
text accumulator decodes the complete JSON UTF-8 body to a String; the canonical
binary decoder then reads the same base64 bytes again. The original native
router sends small WAMP metadata fragments, a large argument continuation and
a final closing continuation. Optimizing only complete WebSocket frames misses
that production path.

## Public SDK boundary

`WebSocket.connect` still performs HTTP upgrade, redirects, TLS, authentication,
subprotocol negotiation, compression, masking and control-frame handling. An
internal delegating HttpClient wraps only the detached, uncompressed Socket.
Compressed sockets and custom serializers keep the ordinary SDK path. This
uses public Dart interfaces; it does not implement a second WebSocket transport.

The input adapter stages at most 4,096 wire bytes of small ASCII WAMP metadata.
It forwards controls immediately, including PING while waiting for arguments.
On a matching large continuation (64 KiB through 8 MiB), it changes only the
internal first text opcode to binary. The original wire payload remains intact
and the SDK accumulates it as bytes. Other shapes fall back unchanged. Invalid
headers are forwarded immediately to the SDK for its normal rejection.

A strict standard UTF-8 streaming decoder checks any non-ASCII suffix before
final data can reach the SDK, including an empty final continuation. It retains
the first failure until FIN, matching the SDK's message-completion boundary;
Close, invalid headers or EOF before FIN keep their original SDK handling. The SDK
then retains its 1007 close behavior. A per-socket FIFO records original wire
text/binary provenance before message completion; original binary JSON frames
remain rejected. The serializer decodes adapted text eagerly, preserving the
String path's public payload shape and avoiding retention of encoded arguments.
RawSocket byte decoding keeps its existing lazy-payload behavior.

## Native buffer ownership

Optional synchronous Handle FFI calls use the public Dart TypedData
AcquireData/ReleaseData APIs. Only uint8/clamped bytes are accepted. A native
RAII guard releases every successfully acquired input exactly once; no Dart
allocation or code execution occurs during a borrow. Output always has separate
native ownership. These rules follow the Dart 3.14 SDK `include/dart_api.h`
Typed Data contract; no VM object layouts, allocator defaults or GC settings
are changed. Missing native exports or public APIs retain the ordinary codec.

Outgoing canonical JSON reserves the exact metadata prefix/suffix around the
owned base64 result. One private frame view fills those reserved bytes and can
be consumed once; the SDK masks that aligned private allocation. User input
and later serializations remain independent. Other fragmented binary messages
use fully initialized private external storage instead of a zero-filled managed
allocation followed by another full payload copy. Small staging/header copies
are included in the existing WebSocket coalesce counter; SDK copy coverage
continues to be explicitly partial.

## Verification status

The focused suite checks byte/header splits, actual metadata continuation
sequences, PING before the large body, Unicode across fragments, original binary
provenance, strict SDK close 1007, compression/subprotocol handling, custom
serializers, eager text ownership, exact/aligned/single-use output and native
borrow release on success/failure. Original workloads, repetitions, deadlines
and throughput gates are unchanged.

The frozen local alternating comparison is investigative evidence: WebSocket
JSON lifecycle median 678 to 427.5 ms, with matching file contents. The matched
Linux three-way comparison records 1,504.5 / 1,213 / 944.5 ms
for baseline / borrowed output / complete receive. Every candidate sample
clears the original file workload floor. Complete final diagnostics remain
pending; this document does not claim that all CI workflows are qualified.
