# Bounded native views at the Dart socket boundary

The Dart Socket consumer passes a full `Uint8List` backing buffer directly to
the native writer. A partial view instead causes a copy of the remaining range
on each write attempt. Existing fragment serialization preserves the body view,
but that alone does not prevent the SDK copy. This follows the pinned Dart SDK
inspection in [the backpressure research](2026-10-07-dart-sdk-backpressure.md).

`nativeExternalByteView` now resolves an already registered native allocation,
checks its backing-buffer identity and bounds, and creates a read-only external
view whose backing storage covers exactly that range. Its address is unchanged.
Full views retain their existing identity. Foreign or unanchored storage returns
null and keeps the existing Socket fallback. The original allocation retains its
sole malloc finalizer; the alias does not own or free the pointer. RawSocket
fragment sending supplies the message's existing allocation anchor.

Both the mutable backing root and the read-only facade carry allocation metadata.
Registering only the facade is insufficient: a derived
view can keep the backing root alive after that facade is collected. A retained
negative prototype demonstrated the original allocation's native free while
the derived view remained reachable. No data was dereferenced after that failure.
The first repair retained the source in an otherwise unread metadata field.
It passed VM tests but failed an independently compiled AOT pressure check:
`rootAlive=false`, `nativeFrees=1` while a derived view remained reachable.
The check rejected the failure before dereferencing that view. The in-progress
full verification was stopped at exit 143; it is not accepted verification.

The final helper attaches a static Dart finalizer to the mutable backing root
with the original source as its finalization token. Its callback does nothing;
only the original malloc finalizer releases memory. This uses the documented
[Finalizer attachment contract](https://api.dart.dev/dart-core/Finalizer/attach.html)
to retain the source independently of unread metadata fields. The standalone
compiled pressure check now passes. The production helper passes actual-GC
derived-view and empty-view tests, including collection after the last owner
disappears.

Twelve transport regressions fail before this change: CBOR, MessagePack and
FlatBuffers, two nonzero offsets, and mutable/read-only sources all submit an
oversized backing buffer. The final 55-case socket suite verifies bounded input,
original pointer identity, decoded semantics and unchanged own-copy counters.
The combined 83 cases pass on Apple Silicon and without skips against the
production Linux arm64 library from `8503f31c`.
The baseline `bin/test-fast` and focused analysis pass.

The Linux/glibc diagnostic pauses a real loopback receiver and sends 16 MiB
bounded views in four mutable/read-only and direct/nested combinations. Each
case requires genuine EAGAIN, a pending flush, eight forced VM collections,
zero native frees while queued, positive progress after receiver resumption,
exact payload bytes, and the original address at every write/retry. Nested cases
also collect the parent facade before draining. All four pass and the final
allocation release is observed after completion.

The four cases also pass in an AOT snapshot using allocation pressure instead
of the unavailable VM service. Both modes require final collection/release and
collected parent facades, establishing that collection occurred. The diagnostic
labels each collection method separately; allocation pressure is not described
as a forced VM-service collection.

The native-free diagnostic watches one live allocation and disarms at its first
free. An earlier address-only counter incorrectly counted later reuse of that
address (`rootAlive=false`, `nativeFrees=3`); that failed evidence is retained.
Independent malloc/free and a single-call C address-reuse control now verify a single
release observation. This is a first-release oracle, not a double-free counter.
An interim Dart address-reuse control failed because intervening allocations
could consume the freed block; that failed run is retained. The C control keeps
both allocations within one native call on the same thread.
The exact CI step passes the three existing socket probes, the new queued-GC
probes in VM and AOT modes and both explicit missing-interposer rejection controls. CI uploads their
raw observations. [The proof](2026-10-07-bounded-native-socket-views-proof.json)
records final source hashes, observations and retained log hashes.

This generic change does not adopt foreign pointers or extend database
transaction lifetimes. It does not claim zero copies for TLS, SDK masking,
crypto or codec conversion, and does not satisfy the strict paired performance
campaign. Issues #100–#104 remain open. The bounded local review found no
concrete lifetime flaw. Its claim that derived views retain the parent facade
is contradicted by the collected-facade tests; its suggested Expando eviction
policy is unnecessary for weak keys. Final source inspection and GC/free
oracles verify the retention chain independently. An earlier broad review hit
its output limit and is not accepted review evidence. Restarted `bin/verify` passes at exit 0,
including Rust/VM/consumers, 1,563 benchmark, 4,958 router, 4,751 core browser
and 2,829 client browser cases with the unchanged 20 native-only skips.
Resulting-head hosted acceptance remains pending.
