# Native-owned encryption boundary preparation

Date: 2026-10-04. This is source-backed preparation for issues #96, #101 and #103;
no new crypto API or zero-copy acceptance is claimed. Finish current canonical
verification before implementing another feature. ObjectBox integration remains
outside core.

## Verified current behavior

`NativeOwnedBuffer.bytes` exports a read-only external typed-data view with an
independent native owner. That getter does not copy the payload. However,
`NativeClientRuntime.encryptE2ee` allocates input storage, copies the supplied
`Uint8List`, and copies the returned `CtByteBuffer` back to Dart. Supplying the
builder's view therefore does not eliminate these crypto boundary copies.
The same generic behavior applies to `decryptE2ee`; the separately implemented
consuming message-decrypt APIs have a different explicit ownership contract.

The native AES encryption routine already creates nonce, body and tag in a single
result vector. XSalsa currently allocates encrypted bytes and then assembles a
second nonce-prefixed vector. Distinguish any resulting crypto transformation
work from avoidable Dart/native transfers and subsequent framing copies.

`owned_buffers::borrow_frozen` retains the allocation and its encoded range,
including empty slices. Mutable/reserved handles are rejected. `reserve_frozen`
can reserve an unobservable result handle before publishing an immutable `Bytes`
allocation. Native `Bytes` and span ownership must remain intact through errors;
do not adopt foreign pointers as Rust vectors.

`composeFlatBufferFrame` already accepts an independently owned `opaquePayload`
and retains its inputs. This gives a concrete submission target for native
ciphertext without exporting it as a Dart array or flattening the whole frame.
Control metadata and the typed E2EE profile still need normal validation and
capability negotiation.

## Next implementation constraints

- Accept explicit immutable native-buffer handles, verifying library identity,
  live state, range, byte limits and typed-profile prerequisites before policy.
- Retain input on both success and failure. Any future consuming variant must be
  separately named and define every terminal ownership transition.
- Recheck validity after user key-policy callbacks. Callbacks may dispose handles
  or providers; a prior preflight alone cannot authorize later native access.
- Resolve optional ABI support explicitly. Older libraries must not accept an
  unsupported handle-based operation or silently claim a no-copy fallback.
- Return an owned native result that can be passed to frame composition and
  tracked submission without a native-to-Dart ciphertext copy.
- Keep dynamic CBOR behavior and cryptographic wire compatibility. Share generic
  native-buffer optimizations with binary baselines, not only FlatBuffers.
- Prove input pointer/range and output allocation identity with actual oracles,
  alongside key/cipher/error, alias/slice, release, cancellation, queue rejection
  and teardown cases. Report transformation copies separately.

These are planned contracts, not an implemented interface. The final API and
cross-language lifetime behavior need focused test planning and architecture
review before code changes. A local summary incorrectly inferred that a
read-only view avoids copies in existing encryption; direct runtime source
inspection disproves that inference.

## Focused test-planning dispositions

The local test companion proposed callback disposal, library identity, aliases
and allocation checks. These are useful areas, with three corrections verified
against the current ownership contract:

- A callback that disposes the supplied wrapper makes that wrapper invalid. The
  operation must reject it; an independently retained alias remains valid.
- Overlapping immutable slices are legal retained reads, so encryption must not
  invent an alias conflict. Test correct slice contents and lifetime instead.
- A native output address alone cannot disprove earlier input/output copies.
  Assert the actual input pointer and range used by crypto, result publication
  identity, boundary-copy instrumentation and retained ownership together.

Keep malformed ranges, mutable handles, missing keys, released sessions and
result-construction failure in the native tests. The public owner has no writable
view, and optional-ABI rejection must preserve both the original input and its
retained aliases.

## Architecture review dispositions

The local GLM judge accepts the borrowed-input design conditionally. Native entry
must call `borrow_frozen` itself: Dart checks cannot authorize a raw pointer or
replace native liveness/range validation. That function clones the immutable
allocation owner while the store entry is held, so encryption can retain bytes
without holding a store lock for the cryptographic operation.

`FrozenReservation` already removes an unpublished slot in `Drop`. Keep the
reservation scoped to native encryption after Dart callbacks; exercise every
native error and Dart result-construction error rather than assume this cleanup.
Never reach `take_frozen` for this API's input. Publish a new result owner only
after successful encryption, preserving actual capacity and initialized length.

Retained slices currently each declare their allocation capacity to Dart's
finalizer for GC pressure accounting. This can overcount shared memory; it is not
the logical payload byte limit or a distinct-allocation memory measurement.
Validate the selected input length and report unique retained allocations in
benchmarks.

Encryption is synchronous; it exposes no cancellable in-progress Dart future.
The returned buffer is independent of submission. Existing explicitly retained
versus transferred frame-send contracts govern queue rejection and connection
shutdown, and composing a frame must retain ciphertext even if the caller later
disposes its original wrapper.
