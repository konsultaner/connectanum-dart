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

For Session sends, call `NativeOwnedBuffer.asFlatBuffersPptPayload()` and pass
that lazy payload to `Session.callLazyPayload` or
`Session.publishLazyPayload` with matching opaque FlatBuffers PPT options. An
established native FlatBuffers transport can then reuse the exact frozen
application span for eligible CALL/PUBLISH messages, rebuilding only the
control envelope and retaining the payload in a native frame. The fast path
requires a nonempty PPT scheme other than the reserved `wamp` transparent mode,
`pptSerializer: 'flatbuffers'`, and no PPT cipher or key ID. It also validates
the negotiated session profile before submission. Other payloads continue
through the regular serializer. The payload schema and its identity remain the
application's responsibility.

`NativeOwnedBuffer.asPptPayload` also retains encoded CBOR/MessagePack PPT with
an explicit lazy decoder. Native CBOR/MessagePack CALL/PUBLISH paths now reuse
that exact span through the optional owned-segment ABI. Only newly serialized
metadata fragments are copied at submission; copied/replaced payload views
continue through the serializer. See [encoded native segments](native_owned_buffers.md#encoded-native-segments)
for the capability, bounds, compatibility and receipt contract.

The native frame retains its input owners after queue acceptance and through
the asynchronous write. The caller may dispose its own buffer handle after the
Session send call returns; the frame's retained handle remains valid. This path
avoids materializing the encoded payload in a Dart serialization buffer. It
does not promise that WebSocket masking, TLS or other lower transport stages
avoid their own copies.

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

The legacy native transport `drain()` only yields an event-loop turn. Use
`drainWrites()` for a FIFO local write/flush barrier, and producer release dispatch
for the final external-resource boundary. Disposing a write receipt stops
observation; it does not cancel an accepted send or release its buffer.

The [native network tests](../native/transport/ct_ffi/src/runtime/external_network_tests.rs)
register transaction-like memory on a separate producer thread. They check the
original pointer, byte integrity, release count, callback thread and retained
byte/lease budgets. Their terminal-path coverage is:

| Path | Checked boundary |
| --- | --- |
| Successful RawSocket/WebSocket write with disposed receipt observer | The sole native writer keeps the loan; the peer receives the complete original payload, then a FIFO barrier completes and the producer releases once. |
| Full native transport queue | A separate rejected producer handle is consumed and releases once while the stalled accepted send keeps its own loan. |
| Peer reset after a verified payload prefix | The partially written frame is abandoned; cleanup occurs on the producer thread. |
| Local connection cancellation after partial progress | RawSocket cancellation or WebSocket's bounded close abandons the stalled frame and releases its loan. |
| Runtime shutdown with an exported view | The write is abandoned while the view remains readable; dropping the final view permits producer cleanup. |
| Missing destination | Submission consumes the foreign handle, returns the connection error and releases the loan. |

The [lease FFI tests](../native/transport/ct_ffi/src/runtime/external_lease_ffi.rs)
also cover handle-construction failure without consuming the producer reference,
wrong-thread rejection, empty loans, fan-out/slices and pending-release quota.
The [core writer tests](../native/transport/ct_core/src/write_completion_tests.rs)
separately check partial-write/flush errors and cancellation of deferred
preparation. These are ownership and local-completion proofs; transport masking,
framing or encryption can still copy bytes.

A generic `LazyMessagePayload` also retains its original storage owner across
anchor replacement, forwarding and message mutation. Borrowed owners remain with
the owning message/views even after cached encoding is invalidated. `toOwned()`
copies byte/list/map graphs and omits their storage owner. Providers, contexts and
decoder callbacks remain shared and can independently retain resources they capture.

`LazyMessagePayload.deferred(loader: ...)` defers already-decoded application
values without inventing an encoded byte representation. Related views share one
loader result, including null/empty values, or the original terminal error and
stack. Recursive loading fails. Previously returned views retain their captured
provider/context and values when a message is subsequently changed. `toOwned()`
evaluates the loader and copies the resulting graph.

## Copy boundaries

| Boundary | Behavior |
| --- | --- |
| Ordinary Dart value encoding | Constructs encoded bytes; binary vectors copy supplied input bytes. |
| Native construction | Writes in native storage; growth copies are reported separately. |
| Immutable native frame composition | Retains application spans without flattening them; control assembly still writes bytes. |
| Owned/native frame submission | Transfers or retains ownership without a Dart-to-native application copy. |
| Session typed FlatBuffers PPT send from a frozen native owner | Reuses the exact application span in a retained native frame; only the FlatBuffers control envelope is rebuilt. |
| Ordinary Dart native send, including segmented send | Copies each supplied Dart segment into native storage. |
| Lazy receive/routing metadata access | Keeps encoded application views; reading application values can materialize them. |
| Native segmented routing/forwarding | Retains native application spans for homogeneous routes, eligible ordinary CBOR/FlatBuffers routes and valid opaque PPT between CBOR/MessagePack/FlatBuffers; other encodings require conversion. |
| Fragmented incoming frames | Reassembly can allocate/copy; transport chunking alone proves no zero-copy property. |
| Client WebSocket masking | Transforms outbound bytes; account for its buffer/copy work separately. |
| Generic native E2EE with Dart values | Copies Dart input into native storage and copies the encrypted/decrypted result back to Dart. |
| Native-owned typed FlatBuffers E2EE | Borrows a frozen native input and returns frozen native-owned ciphertext without exporting payload bytes through Dart; encryption allocates the ciphertext. |
| Native consuming E2EE receive | Returns an owned native plaintext view; unique contiguous AES inputs can reuse storage. Eager exported receive views currently force its safe copied fallback. |
| TLS | Cryptographic transformations have separate allocation/copy costs. |
| `toOwned()` | Explicitly copies retained binary/container graphs. |
| Native typed reader | Requires compatibility with the actual pointer, subrange and reader; alignment fallback may copy. |
| Database insertion | Depends on writable ID handling, padding and database internals; persistence is not promised copy-free. |

Ordinary FlatBuffers argument vectors contain CBOR. Native EVENT, INVOCATION,
RESULT and ERROR replacement envelopes can therefore share the exact argument
and keyword spans with a CBOR connection in either direction. The optional v1
eligibility queries return `1` for reusable payload representation, `0` for the
ordinary conversion path, and a negative status for invalid input or an unavailable
connection. They borrow the message handle without consuming it. The connection
query reads the actual negotiated destination and enables a retained-handle
handoff between router workers without exporting the application vectors.
Libraries without these optional symbols keep the earlier forwarding behavior.

For PPT between CBOR, MessagePack and FlatBuffers, the native path retains the
single binary body and rebuilds only the outer list/bin wrapper or FlatBuffers
control envelope. It requires a nonempty string `ppt_scheme`, string-valued
optional serializer/cipher/key metadata, and absent or valid empty outer CBOR/
MessagePack keyword maps. Complete empty-map spans are recognized without
allocating a map and normalized to absent for mixed binary envelopes. FlatBuffers
transparent bodies still exclude keyword vectors. Application
schemes and encrypted bytes stay opaque; the reserved `wamp` scheme also uses
native RPC forwarding. Empty bodies remain present and retain their producer
until the last send segment is released. Native echo replies retain the four PPT
metadata fields without copying CALL routing options. JSON and unsupported PPT
shapes keep their conversion path; this boundary alone proves no whole-pipeline
copy count or benchmark parity.

An ordinary CBOR-to-FlatBuffers query checks the destination's bounded argument-container
rules without reconstructing the application value graph; keyword-key validation
may allocate temporary keys. Eligibility does not bypass message-kind, routing
metadata, session/profile, queue or connection checks. Custom INVOCATION details
still require the ordinary envelope-building path, and submission rechecks the
destination serializer. Small controls, metadata and validation allocations are
separate from retaining the original argument spans.

JSON encoding now preserves the caller's binary lists/maps and uses the existing
recursive encoder to produce its Base64 representation. Typed and immutable
containers holding Uint8List remain reusable for subsequent binary-codec encoding.
TransferableTypedData remains one-shot: one payload-local identity cache shares
its encoded value across aliases in arguments and keywords during serialization,
without replacing caller-owned entries. It does not permit a second consumption.
JSON conversion, ordinary Dart submission, framing/masking, coalescing and TLS
still have their
documented allocation/copy boundaries; this routing optimization does not provide
complete end-to-end copy totals.

Construction counters describe their named input-binary and growth copies. They
are not a total memory-traffic or timing measurement. Performance gates must also
account for control encoding, transport conversions and transformations, and
compare the declared workloads with CBOR and MessagePack.

The typed E2EE candidate provides
`NativeWampFlatBuffersXsalsa20Poly1305Provider` and
`NativeWampFlatBuffersAes256GcmProvider` beside the portable typed and CBOR
providers. Its whole-span format selector is independent of the outer WAMP
serializer, and older native libraries use generic raw decryption. Typed results
are read-only. Automatic finalization preserves independently derived views;
when `releaseOwnedExternalBytes` returns true, the root and every derived view
become unusable immediately. This differs from disposing a `NativeOwnedBuffer`
wrapper, whose already-exported views hold independent native references.
Typed file-prefix/E2EE segment framing is unsupported and rejects explicitly.
Both native FlatBuffers providers expose `packNativeTypedPayload` for callers
that already hold one encoded FlatBuffers application payload in a frozen
`NativeOwnedBuffer`. The optional owned-buffer E2EE ABI borrows that buffer,
leaves its owner with the caller, and returns ciphertext in a separate frozen
native buffer. Callers can pass that result as `opaquePayload` when composing a
`NativeFlatBufferFrame`, then submit the frame through `NativeFrameTransport`.
The FFI path copies no payload bytes through Dart typed data; the cipher still
allocates ciphertext, and ordinary Dart-value E2EE keeps its existing copies.
This ownership path does not establish full-session copy counts or representative
throughput parity.

The API has no ObjectBox schema or transaction behavior. A future C adapter may
present compatible immutable bytes through the generic producer-lease contract.
It must keep those bytes valid through the synchronous encryption call and release
the producer-backed input before the database's own lifetime ends; the returned
ciphertext has an independent native owner.

Typed native providers validate ciphertext shape and length before key-policy
callbacks. The optional `ct_message_single_binary_argument_length_wide` export
inspects a live message without exporting, copying or consuming its payload. It
accepts one binary argument and rejects keyword containers, including an empty
one. JSON inspection validates the canonical base64 spelling without decoding
it. The caller must check the return code; the output length is zero on errors.
Inspection does not authenticate bytes or extend their lifetime. Provider limits
are 28 bytes minimum for AES, 40 for XSalsa and 64 MiB maximum. Older native
libraries materialize the wire payload for the same validation, which can retain
an exported view and force the safe copied decryption path. Cached authenticated
typed results retain the same length checks; explicitly released native outputs
cannot be reused. Empty plaintext is Dart-owned and needs no native release.

## Future ObjectBox adapter

`connectanum_objectbox_adapter` remains a separate package. It owns entity schema,
property IDs, defaults/evolution, entity identity, relations and synchronization.
Neither core, client nor router depends on ObjectBox or interprets its entity
schema.

The Dart path is different from borrowing stored bytes. In ObjectBox Dart
[`Box.get`](https://github.com/objectbox/objectbox-dart/blob/d189611e638e192594baee0b99e4bd78a3ef8b61/objectbox/lib/src/native/box.dart)
reads inside a transaction; the
[generated reader](https://github.com/objectbox/objectbox-dart/blob/d189611e638e192594baee0b99e4bd78a3ef8b61/generator/lib/src/code_chunks.dart)
constructs an entity and populates its fields. Sending that entity through a
normal serializer re-encodes application values. A C adapter can instead borrow
the stored FlatBuffer and avoid this entity reconstruction/re-encoding boundary.
The Dart
[transaction wrapper](https://github.com/objectbox/objectbox-dart/blob/d189611e638e192594baee0b99e4bd78a3ef8b61/objectbox/lib/src/native/transaction.dart)
is thread-bound and cannot remain open across `await`; running work on a background
isolate does not turn returned Dart entities into retained raw database memory.

The [ObjectBox C header at d701b03](https://github.com/objectbox/objectbox-c/blob/d701b03ff680b26da219f0cb8961f2ea1fdb3e3c/include/objectbox.h)
limits `obx_box_get` bytes to the active top-level transaction before invalidating
writes. A C adapter can manage that lifetime natively, retaining the transaction
through every transport consumer and closing it on the proper native thread.
Using C does not remove the lifetime constraint. It avoids relying on the
synchronous Dart transaction wrapper for an asynchronous send.

The adapter's borrowing policy is therefore a producer-thread read transaction
plus an external lease. Register the immutable byte range, keep the transaction
open while any submitted frame or exported byte view retains the lease, and close it
only when final cleanup is dispatched on the producer thread. The fake producer
and native network fixtures above demonstrate this ownership sequence without
ObjectBox. If retaining that transaction is disallowed, exceeds the adapter's
backpressure budget or conflicts with required writes, copy into a Connectanum
owned buffer before closing it. Expose that fallback copy explicitly.

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
Borrow a range only when the actual native reader accepts its pointer and bounds;
otherwise use an explicit alignment fallback. The adapter must expose and measure
any fallback copy.

## Opt-in receive materialization before consuming decryption

`NativeClientRuntime.materialize(handle, deferPayloadExports: true)` takes the
message handle without exporting frame or payload views. The first read of any
incoming payload getter materializes and memoizes all views. The default stays
eager.

Native RawSocket and WebSocket transports also expose
`consumeTypedE2eePayloads`, disabled by default. Set it before opening the
transport or calling `Client.connect()`:

```dart
transport.consumeTypedE2eePayloads = true;
```

For RESULT, EVENT and INVOCATION with the exact `wamp` / `flatbuffers` typed
E2EE metadata, Session receives a metadata wrapper and a deferred application
payload. Metadata inspection exports no ciphertext. Reading the application
payload selects consuming native decryption before exporting wire views. Other
messages retain their ordinary behavior. Enabling this mode permits consumption
of the original ciphertext; applications that need to forward that wire message
must materialize it first. Browser native-transport stubs reject this setting.

Provider/context changes affect newly obtained payload views; existing views
keep their captured processing contract. Wire mutation removes the native anchor
so the changed ciphertext is decoded normally. A key-policy callback that mutates
the deferred wire payload is rejected before consuming decryption. Policy-driven
wire export remains valid and forces the safe copied path.

Advanced consumers can call native consuming decrypt before reading those getters.
Unique contiguous AES storage can then be reused; shared storage, segmented frames
and XSalsa retain the documented safe fallbacks. Explicit release or consuming
decrypt makes every never-exported getter throw `StateError`. Views exported before
that terminal action remain valid and force copied decryption. Consuming decryption
also consumes the original handle on authentication failure. Older runtimes without
the typed format API return no typed native result without consuming the handle;
the caller can materialize ciphertext and use raw decrypt.

This is an opt-in consumption contract.
Original ciphertext cannot be read after its unexported storage was consumed.
The actual Session matrix proves allocation reuse for contiguous RawSocket AES
receives across the three binary outer serializers. WebSocket exercised copied
fallbacks; enabling the setting does not guarantee reuse for every receive.
Native Weak observers and VM-service GC tests verify abandoned incoming finalization,
retained handles, immutable exported ciphertext and derived plaintext views. Weak
observers track StoredMessage lifetime; they are not allocation-address or copied-
byte counters. Separate native tests verify unique AES allocation identity.

## Native memory instrumentation

The repeatable native ownership runner is included in the macOS memory CI job.
GuardMalloc exercises the selected ownership, typed E2EE, frame, lease and network
cases; each report records the executed case count and exact source inventory.
This is not ASan/Miri or coverage of every supported platform.
Each process must report the actual loaded GuardMalloc library and a positive
Rust test count. Missing instrumentation, empty filters, failed cases or timeouts
fail the check. The CI job uploads the exact dependency lock, source and
executable hashes, commands, per-group logs and failure records. If the workspace
has no Cargo lock, dependency resolution precedes its frozen native inventory;
the subsequent build uses `--locked`.

Run `python3 tool/run_native_guardmalloc.py --output out/native-guardmalloc` on
macOS to generate `out/native-guardmalloc/report.json` and the per-group logs.
The CI job publishes these records as the `native-ownership-guardmalloc` artifact.
Hosted acceptance requires a successful execution on the feature commit.
