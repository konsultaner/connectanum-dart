# Native buffers and FlatBuffers ownership

This describes the implementation candidate in the [FlatBuffers milestone](https://github.com/konsultaner/connectanum-dart/milestone/1).
Supported release artifacts, conformance and benchmark gates must pass before
release claims. The wire schema and negotiation rules are in
[the binding document](flatbuffers_binding.md).

## Construction and sending

Ordinary Dart lists/maps use the regular serializers. To build in native memory,
use `NativeBufferAllocator`, its scoped writable buffer API, or its FlatBuffers
builder. A frozen buffer records its allocation and encoded subrange separately;
backward construction never transfers a slice pointer as an allocation base.
Builder growth can copy initialized bytes. Supplying an existing Dart byte list
to a vector writer also copies those input bytes into the builder.

[The native construction example](../packages/connectanum_client/example/native_flatbuffers_frame.dart)
builds a WAMP control table and a CBOR argument vector directly in native storage,
then composes them without flattening the application vector:

```sh
CONNECTANUM_NATIVE_LIB=/absolute/path/to/libct_ffi.dylib \
  dart run packages/connectanum_client/example/native_flatbuffers_frame.dart
```

Use the appropriate library filename for the host. This example constructs and
releases a frame; the real network cases in
`packages/connectanum_client/test/transport/native/native_flatbuffer_frame_test.dart`
exercise transport submission, receipts, reuse and disposal. An established
`NativeFrameTransport` accepts `sendNativeFrame` and `sendNativeFrameTracked`.
It applies the same FlatBuffers session profile as ordinary messages, including
bootstrap acknowledgement requirements. The allocator's connection-ID send API
is lower level; the caller owns the surrounding session protocol.

Low-level native receive streams are broadcast. Subscribe before sending HELLO
or a request that can produce a response. A local write receipt does not buffer
incoming responses or establish a receive subscription. With a `StreamIterator`,
start `moveNext()` before sending, then await the receipt and the pending receive.
The public Session path establishes its listener before the handshake.

`composeFlatBufferFrame` retains all supplied buffers, including present-empty
spans, on success. It consumes none on failure. Argument/keyword vectors are
encoded CBOR; a typed application FlatBuffer uses the opaque payload input and
PPT metadata. For an opaque control template, set its legitimate present-empty
transparent payload vector so the pinned flag/vector contract is satisfied;
composition then supplies the external opaque span. A frame has no implicit
contiguous byte getter. Its control view
has its own owner, and application spans retain their independent allocations.

| Operation | Caller ownership |
| --- | --- |
| Freeze a writable buffer | Writes stop; the returned immutable owner holds the allocation. |
| Compose a frame | Original control/application owners remain valid. |
| Send with `transfer: false` | Submission consumes a retained reference; the caller's owner remains valid. |
| Send with `transfer: true` | Native submission consumes the submitted reference on success or rejection. |
| Reject in Dart before native submission | Caller ownership remains valid. |
| Retain | Produces another independently disposable reference. |
| Dispose | Drops that reference; it does not invalidate independently owned views or recipients. |

Check optional capabilities before using native buffers, external tokens, frames
or write receipts. Complete symbol sets and ABI version 1 are required. Older or
incomplete native libraries reject the operation before transferring ownership;
there is no silent adoption or copying fallback for these APIs. Native FFI
ownership is unavailable in browser JavaScript/WASM. Ordinary browser WebSocket
serialization remains supported; browsers do not expose RawSocket TCP transport.

## External producer leases

Foreign memory is borrowed, never converted into a Rust `Vec`. The trusted native
producer must keep the whole declared region readable and immutable until final
release. Connectanum cannot revoke a writable pointer retained by that producer.
Dart adoption validates a frozen `NativeBufferToken` and its library identity.
Validation failure leaves the token intact; successful adoption clears it before
constructing the Dart owner, and construction failure releases the claimed handle.

Create `ct_external_owner_create` on the producer's native thread with explicit
byte and lease-count limits. Register immutable resources with
`ct_external_buffer_register`. Exceeding a limit rejects admission and leaves the
producer's resource reference unconsumed. Retained/fan-out references count toward
the same loan, whose budget stays reserved until its release is dispatched.

Final reference destruction queues cleanup. `ct_external_owner_wait` and
`ct_external_owner_dispatch` run on the owner thread; the transport worker does
not invoke a Dart callback or close a thread-bound resource. Close admission,
continue dispatching accepted releases, and destroy the owner only after its
outstanding resources and callbacks are settled. Wrong-thread operations and
premature destruction fail explicitly. The
[fake native producer fixture](../packages/connectanum_client/test/transport/native/support/external_lease_actor_fixture.c)
and its Dart tests exercise this contract without a database dependency.

Queue acceptance, local write completion, final owner release and peer
acknowledgement are different events. Tracked receipts settle after local
write/flush completion or a terminal error. A successful receipt is not a remote
application acknowledgement and may precede release of caller-held references.
Keep draining producer releases after cancellation, rejection or shutdown.
WebSocket close lets accepted writes and the normal Close frame progress, then
aborts a blocked writer after the local one-second grace; this policy bounds that
writer's retention and is not a deadline mandated by the WebSocket RFC.

A generic `LazyMessagePayload` also retains its original storage owner across
anchor replacement, forwarding and message mutation. Borrowed owners remain with
the owning message/views even after cached encoding is invalidated. `toOwned()`
copies byte/list/map graphs and omits their storage owner. Providers, contexts and
decoder callbacks remain shared and can independently retain resources they capture.

## Copy boundaries

| Boundary | Behavior |
| --- | --- |
| Ordinary Dart value encoding | Constructs encoded bytes; binary vectors copy supplied input bytes. |
| Native construction | Writes in native storage; growth copies are reported separately. |
| Immutable native frame composition | Retains application spans without flattening them; control assembly still writes bytes. |
| Owned/native frame submission | Transfers or retains ownership without a Dart-to-native application copy. |
| Ordinary Dart native send, including segmented send | Copies each supplied Dart segment into native storage. |
| Lazy receive/routing metadata access | Keeps encoded application views; reading application values can materialize them. |
| Native segmented routing/forwarding | Retains native application spans; mixed encodings may require conversion. |
| Fragmented incoming frames | Reassembly can allocate/copy; transport chunking alone proves no zero-copy property. |
| Client WebSocket masking | Transforms outbound bytes; account for its buffer/copy work separately. |
| TLS and E2EE | Cryptographic transformations have separate allocation/copy costs. |
| `toOwned()` | Explicitly copies retained binary/container graphs. |
| Native typed reader | Requires compatibility with the actual pointer, subrange and reader; alignment fallback may copy. |
| Database insertion | Depends on writable ID handling, padding and database internals; persistence is not promised copy-free. |

Construction counters describe their named input-binary and growth copies. They
are not a total memory-traffic or timing measurement. Performance gates must also
account for control encoding, transport conversions and transformations, and
compare the declared workloads with CBOR and MessagePack.

## Future ObjectBox adapter

`connectanum_objectbox_adapter` remains a separate package. It owns entity schema,
property IDs, defaults/evolution, entity identity, relations and synchronization.
Neither core, client nor router depends on ObjectBox or interprets its entity
schema.

The [ObjectBox C header at d701b03](https://github.com/objectbox/objectbox-c/blob/d701b03ff680b26da219f0cb8961f2ea1fdb3e3c/include/objectbox.h)
limits `obx_box_get` bytes to the active top-level transaction before invalidating
writes. A C adapter can manage that lifetime natively, retaining the transaction
through every transport consumer and closing it on the proper native thread.
Using C does not remove the lifetime constraint. It avoids relying on the
synchronous Dart transaction wrapper for an asynchronous send.

`obx_box_put_object4` accepts writable storage and can update a new entity's ID.
An immutable receive view is not that writable input. The const-data `obx_box_put5`
path requires an explicitly supplied ID matching the encoded ID. The adapter must
choose its policy and produce a writable copy where required.

ObjectBox insertion sizes must be divisible by four under caller-padding mode.
Automatic padding may copy; allowing extension requires actual accessible trailing
storage. A receive slice has no assumed writable slack. [FlatBuffers scalar
alignment](https://flatbuffers.dev/internals/) also requires checking the actual
native reader and payload pointer, including nonzero-offset views. This is not a
claim that ObjectBox requires a particular physical eight-byte pointer alignment.
The adapter must expose and measure any fallback copy.
