# Native-owned encoded buffers

Status: owned-buffer ABI v1 is implemented. The current milestone candidate also
includes guarded FlatBuffers transports, external leases, local write receipts
and native frame composition. Complete platform, conformance and performance
acceptance remains open. See [the current ownership and copy guide](native_buffer_ownership.md)
for composed frames, external producers and future adapter requirements.

Import `package:connectanum_client/native_buffers.dart` on the Dart VM. Native
RawSocket and WebSocket transports implement its `NativeBufferTransport`
capability. Its allocator is paired with the same loaded native library:

```dart
// Supply a transport from an established JSON WAMP session.
void sendOwnedCall(NativeBufferTransport transport) {
  final builder = transport.nativeBuffers.allocate(1024);
  NativeOwnedBuffer? encoded;
  try {
    const frame = '[48,42,{},"com.example.proc",[1]]';
    for (var index = 0; index < frame.length; index++) {
      builder.setUint8(16 + index, frame.codeUnitAt(index));
    }
    encoded = builder.freeze(offset: 16, length: frame.length);
    transport.sendEncodedNativeBuffer(encoded, transfer: true);
  } finally {
    encoded?.dispose();
    builder.dispose();
  }
}
```

This low-level ownership example assumes the caller manages the established
session and request IDs. The frame must match the negotiated serializer; opening
a transport alone does not complete a WAMP handshake. `nativeBuffers.buildFlatBuffer`
builds a fresh application/generated ObjectBuilder directly in native storage.
Select a guarded `.flatbuffers` transport factory for a FlatBuffers network
session; allocation alone does not negotiate that profile. Use a fresh
ObjectBuilder for each build because the upstream runtime caches offsets in model
instances.

## Storage and ownership

Storage is initialized to zero before any builder writes. FlatBuffers allocation
capacities are rounded to eight bytes: the builder aligns relative to the end,
so an odd physical capacity would otherwise misalign native uint64/float64
addresses. Pointer-based tests reproduce a 1023-byte misaligned allocation and
verify the rounded allocation and growth paths. Generic byte builders preserve
the requested length and can intentionally freeze arbitrary byte ranges.
Rust retains the
original allocation base, capacity and initialized length separately from the
frozen used offset/length. The native store validates ranges and adopts only
its own complete allocation. An interior pointer or foreign database allocation
is never reconstructed as a Vec.

Builders expose guarded writes, not a writable typed-data or pointer alias.
Freeze ends every write capability, including callbacks that retained the
FlatBuffers facade. Reentrant model/list callbacks cannot freeze or dispose a
buffer while it is being written. The original builder's disposal after freeze
does not dispose the buffer returned to the caller.

| Operation | Caller ownership after success | Ownership after failure |
| --- | --- | --- |
| allocate | Mutable builder | No handle escapes; setup failure releases storage |
| freeze | Immutable buffer | Invalid range preserves mutable builder |
| retain/slice | Independent frozen handle sharing original storage | Original handle remains valid |
| export bytes | SDK backing-store owner independent of the handle | Before SDK adoption, export token is released |
| retained send (default) | Original buffer remains valid | Temporary submission handle is consumed; original survives |
| transfer send | Buffer becomes disposed | Native submission consumes it even on runtime/connection/queue rejection |
| Dart validation/disconnected transport | Unchanged | Ownership is not submitted |
| dispose | Handle released once; exported views remain valid | Repeated disposal is harmless |

The native result reports queue acceptance. It does not establish a completed
write, final allocation release, or delivery to a peer. Queued writes and all
retained/exported owners hold the allocation independently. Empty retained
handles preserve ownership; exporting an empty list needs no native backing
memory. The native registry is independent of runtime startup/shutdown and does
not recycle IDs.

## Views and garbage collection

`buffer.bytes` is read-only, including its ByteBuffer, ByteData and derived
subviews. Its SDK external typed-data finalizer owns a native retained token.
Wrapper disposal or collection cannot invalidate a surviving view. After SDK
adoption, failure to construct a read-only facade must not explicitly release
that token a second time.

Builder/wrapper/allocator methods implement
[Dart Finalizable](https://api.dart.dev/dart-ffi/Finalizable-class.html), keeping
their owning objects alive during FFI calls and native-memory writes. Exported
views use the SDK [asTypedList finalizer](https://api.dart.dev/dart-ffi/Uint8Pointer/asTypedList.html),
not an Expando attached only to a root Dart list. One NativeFinalizer per loaded native library is retained for that library's
process lifetime, following the SDK [NativeFinalizer reachability contract](https://api.dart.dev/dart-ffi/NativeFinalizer-class.html).
An allocator and its wrappers can be collected together without discarding the
finalizer itself. Explicit disposal is encouraged;
GC timing is not a memory budget or a completion notification.

A VM-service child test forces collection with only a derived ByteData view
remaining. Weak references prove both wrappers and their ephemeral allocator are gone, native handle counts
reach zero, and the real allocation remains accessible. Dropping the derived
view then causes the native allocation count to reach zero. Test-only counters
are absent from production native libraries.

## Copies and compatibility

`growthCopiedBytes` counts bytes moved during downward FlatBuffers builder
growth. Preallocation avoids those copies. `inputCopiedBytes` counts existing
byte-vector/writeBytes input copied into the builder. Encoding scalar/string
values into fresh native storage is distinct from copying a finished frame.
Wrapping pre-encoded payload bytes with a normal vector builder still copies
that vector; zero frame handoff does not remove this copy. The ordinary Dart
send APIs remain copying paths.

Rust tests prove exact pointer identity at frozen-subrange submission and
release on controlled queue rejection. Live RawSocket/WebSocket peers verify
retained and transferred frames; WebSocket masking, TLS and kernel I/O may
perform additional transformation copies. These tests are not performance
parity evidence.

The public constructor borrows its supplied DynamicLibrary for process lifetime.
The caller must keep that library loaded: [DynamicLibrary.close](https://api.dart.dev/dart-ffi/DynamicLibrary/close.html)
can invalidate native function/finalizer pointers. Closing/reloading a borrowed
library is unsupported. Prefer NativeBufferAllocator.instance or the transport
allocator, which use the privately managed runtime library.

The complete optional ABI v1 is resolved together. Missing symbols or a different
version make `isSupported` false and reject allocation/sending explicitly.
Ordinary native APIs still work with older libraries. Buffers from a different
loaded native library cannot be submitted through this allocator.

Actual ObjectBox integration belongs in a separate `connectanum_objectbox_adapter`
package. Its transaction-borrowed memory must use a future external-owner lease
contract; it cannot be passed to this owned-allocation ABI. No ObjectBox
library or dependency is added here.
