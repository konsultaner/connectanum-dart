# Connectanum ObjectBox adapter

Persist received entity FlatBuffers through the ObjectBox C API without
constructing Dart entities. This is a VM-only package for Dart and Flutter.

```yaml
dependencies:
  connectanum_objectbox_adapter: ^3.0.0-beta.8
```

Use the normal ObjectBox setup and generated model in your application. Dart
applications need the [ObjectBox native library](https://docs.objectbox.io/getting-started);
Flutter applications supply it through the matching ObjectBox Flutter libraries.
The adapter uses the same library instance as your existing `Store`.

## Receive directly into ObjectBox

```dart
import 'package:connectanum_objectbox_adapter/connectanum_objectbox_adapter.dart';

final adapter = ObjectBoxFlatBufferAdapter<MyEntity>(store);
await session.subscribeLazyPayloadHandler('com.example.entity', (event) {
  final written = adapter.putEvent(event);
  print('Stored ${written.id}; adapter copied ${written.copiedBytes} bytes');
});
```

The sender publishes an **ObjectBox-compatible entity FlatBuffer** using typed
PPT scheme `x_connectanum_objectbox`, serializer `flatbuffers`, and custom option
`x_objectbox_schema` containing the sender adapter's `schema.fingerprint`.
`adapter.publishOptions()` creates these options. The WAMP envelope can use
FlatBuffers, CBOR or MessagePack; the entity payload remains unchanged.

Both peers must share the persisted ObjectBox entity/property IDs and UIDs,
types and flags. Use the same version-controlled ObjectBox model. An unrelated
`.fbs` with similarly named fields or a complete WAMP frame is not an entity
buffer. The adapter checks the announced fingerprint and validates table,
vtable, scalar, vector, UTF-8, ID and length bounds before native insertion.

For other receive APIs, pass the decoded entity bytes explicitly:

```dart
final written = adapter.putBytes(
  entityBytes,
  schemaFingerprint: announcedSchemaFingerprint,
  storageOwner: lazyPayload.storageOwner,
);
```

Use the authenticated plaintext entity range after E2EE decryption. `putEvent`
accepts the plaintext ObjectBox PPT scheme and rejects encrypted envelopes.
The adapter performs no encryption or key management.

## Copies and ownership

* A matching retained native receive range goes directly to synchronous
  `obx_box_put5`. The adapter retains an independent native byte lease and
  verifies its complete contents against the supplied bytes. No Dart entity is
  created, and the adapter copies no body bytes on this path.
* Ordinary Dart arrays and ranges without a usable native lease take one
  explicit native staging copy. A modified list or unrelated owner cannot
  substitute a different payload.
* A zero ID requires a private writable copy for `obx_box_put_object4` to assign
  an ID. The input remains unchanged; use the returned ID. Set
  `assignIdIfZero: false` to reject this fallback.
* Non-four-byte lengths are padded in the same staging allocation. Padding is
  initialized; writable slack is never assumed.
* Native byte ranges at nonzero physical offsets are supported. Logical
  FlatBuffers field alignment is still validated. The real C reader is tested
  at every physical offset modulo eight.

`adapter.copyMetrics` reports staging and snapshot copy bytes separately.
`knownCopyBytes` adds those two disjoint counters. Padding, selected borrowed
input bytes and successful/failed native write attempts are separate observations.
ObjectBox storage-engine, Dart SDK and transport internals are not measured by
these counters; this package makes no zero-copy database-insertion claim.

`putNative(pointer, length, lifetimeOwner: ..., schemaFingerprint: ...)` is the
advanced C integration path. The caller must supply valid, immutable native
memory and keep its actual owner alive throughout the synchronous call. The
adapter never adopts, frees or modifies that memory.

## Reads, IDs and relations

`adapter.getBytes(id)` returns an owned snapshot, copied before its read
transaction closes. It is safe across `await`, later database writes and Store
closure. Missing IDs return `null`. Database-backed views are not exposed.

Nonzero IDs are preserved and prepared through ObjectBox's ID API. Use
assignable IDs and a shared identity policy for replicated entities.
`reserveId()` reserves an ID before building a new encoded entity.
`PutMode.insert` and `PutMode.update` retain native collision/not-found behavior;
`ObjectBoxAdapterException` preserves native error codes and messages.

To-many relations and backlinks require a separate relation synchronization
policy and are rejected. To-one numeric IDs require `allowRelationIds: true`;
the application owns their mapping. Flex properties are currently unsupported.
Unknown nonempty slots, including retired data still present in an older row,
are rejected. Regenerate/rewrite such rows using the agreed current model.

Close the adapter when finished; it does not close the application's Store.
This release restricts compatibility to ObjectBox 5.3.x and the Connectanum
beta.8 band because its isolated compatibility layer uses their native
integration interfaces. Tests use ObjectBox 5.3.2 and Connectanum 3.0.0-beta.8.
