# ObjectBox C adapter contracts

The user authorizes a separate package and publication on 2026-10-19. The first
release targets received encoded entities, using published Connectanum beta.8
and ObjectBox 5.3.2. The unmerged performance branch is not a dependency.

## Native API and schema

The [ObjectBox C API](https://objectbox.io/docfiles/c/current/group__c.html)
and the exact header in the published `objectbox-5.3.2` archive define:

* `obx_box_put5(box, id, const uint8_t*, size, mode)` reads caller bytes. The ID
  must match the encoded ID. The adapter prepares nonzero IDs using
  `obx_box_id_for_put` and writes inside the same Store's write transaction.
* `obx_box_put_object4` returns an ID and may modify the supplied writable ID
  slot. It does not return a transaction-owned allocation. The adapter stages
  zero-ID inputs in its own allocation and never patches the caller's bytes.
* `obx_box_get` exposes bytes valid only within the active top transaction and
  before invalidating writes. A Dart reference does not extend that lifetime.
* The padding contract requires a length divisible by four under caller-padding
  mode. It does not state an eight-byte physical-pointer requirement.

ObjectBox's generated layout uses persisted property ID minus one as the
FlatBuffers slot. Matching names is insufficient. The adapter fingerprints
entity/property IDs and UIDs, types and flags, and requires the sender's exact
fingerprint. It verifies offsets, table extents, nonoverlapping inline fields,
scalar/vector bounds, UTF-8, ID and bounded work before native writes. Flex,
unknown nonempty slots and to-many/backlink synchronization are rejected. To-one
IDs require explicit opt-in and application-owned identity mapping.

## Input leases and observed copies

Connectanum's published producer registry and receive exports are different
mechanisms. The first implementation recognized producer malloc buffers but
staged real receives; all three native network tests reproduced that mistake.
The receive compatibility module follows the actual SDK message anchor, peeks
its native metadata, and acquires a new `NativeMessageBytes` ownership export.
It requires zero-copy export support before calling that API, so the SDK's
legacy copied fallback cannot be hidden. The exported owner's backing-store
finalizer retains the memory independently of the routing handle.

For encoded CBOR/MessagePack argument storage it accepts only a complete definite
binary value, optionally inside a single-element array. Other layouts fall back.
The complete leased payload must byte-match the supplied entity, so a modified
list or forged anchor cannot substitute another body. A `Finalizable` holder
roots the actual bytes and native lease across the synchronous non-leaf C call.
Database functions are not incorrectly marked leaf to obtain Dart heap pointers.

An initial eight-byte physical-pointer gate made real RawSocket FlatBuffers
receives copy unnecessarily. An independent direct C reader test inserts the
same entity at every physical offset modulo eight and verifies Unicode/NUL text,
IDs, numeric/byte/string vectors through ordinary ObjectBox reads. All offsets
pass on the local native 5.3.2 library. The gate is removed; logical FlatBuffers
field alignment remains checked. Cross-platform repetition is required before
publication. The upstream [FlatBuffers scalar reader](https://github.com/google/flatbuffers/blob/v25.9.23/include/flatbuffers/base.h)
also distinguishes its scalar access from a whole-buffer physical alignment
policy; this source is supporting context, not proof about a different engine.

Staging and snapshot counters describe adapter-owned body copies only. New-ID
assignment and caller padding share a single staging allocation. Padding writes
are reported separately. Native database internals and SDK/transport internals
remain unmeasured; no zero-copy database-insertion claim follows from C API use.

## Database reads

The first scoped-read draft incorrectly relied on the Dart transaction object's
mode to reject a read nested inside an outer write transaction. A real test
returns a readable view instead of rejecting the write context. Inspection of
ObjectBox 5.3.2's `_runInTransaction` finds `_tx` is cleared but not assigned in
that implementation; the native transaction can still be reentrant. Its Dart
mode therefore cannot establish the top native transaction's restrictions.
This is retained as a failed repro, not weakened into a passing lifetime claim.

The first release exposes only owned read snapshots, copied before transaction
closure. It exposes no guarded database-backed list or pointer, and it holds no
Dart transaction across `await`. A future asynchronous zero-copy read requires
a dedicated native transaction owner and a release dispatcher on its thread.

## Versions and native test evidence

Runtime dependencies are pinned to the tested ObjectBox and Connectanum
versions; their private native integration surface is isolated and documented.
The initial adapter version follows the workspace's `3.0.0-beta.8` release gate.
No transport crate, existing package version, ABI or acceptance budget changes.

The local ObjectBox engine is the official
`objectbox-macos-universal.zip` from tag `v5.3.2`; its SHA-256 is
`680c598573ede04b9762565d48d4e161ad286f786f159abb8da89353bfa1d0bc`.
It is test setup, excluded from the package archive. First failing runs, the
direct C alignment proof and subsequent 23-test pass are retained under
`out/objectbox-adapter-evidence/`. Full integrated verification and publication
must be recorded separately; the prototype pass is not a release confirmation.

## Dart wide-vector layout acceptance

A fail-first schema test shows the pinned Dart FlatBuffers 25.9.23 builder writes
64-bit vectors with their element range at a four-byte offset. An independent
ObjectBox 5.3.2 C put/read test confirms exact signed-64 values at that layout and
at every physical base offset modulo eight. Validate the four-byte vector offset
and full count/width bounds; requiring eight-byte vector-element alignment would
reject valid buffers produced by the actual Dart SDK. Inline scalar field
alignment remains validated. The real C probe and Dart entity roundtrip cover
this rule; it is not an inference from the FlatBuffers format alone.

## Published release and independent installation

The user authorizes this first publication.
[connectanum_objectbox_adapter 3.0.0-beta.8](https://pub.dev/packages/connectanum_objectbox_adapter/versions/3.0.0-beta.8)
is live, published on 2026-10-19 at 13:19:06.038111 UTC. Its
[version API](https://pub.dev/api/packages/connectanum_objectbox_adapter/versions/3.0.0-beta.8)
reports archive SHA-256
`810d80a0edde8b2b72095cd14e605173a1f0e27a3da8a54d8efe325ae8246f37`.
The archive is 19 KB and excludes native engine binaries.

Implementation source is `ce1d40b5f724b53ea83c26e611f3cfdc03722e76` in
[PR #133](https://github.com/konsultaner/connectanum-dart/pull/133); the package
tree is `d5978e694930cb6a93212bd1ab23f431faf2a818`. All six library files from
the freshly downloaded pub.dev package match that source byte-for-byte, and
Dart's fresh-cache archive hash matches the API digest above.

Canonical `bin/verify` passes at exit 0 with standard Dart 3.13.1 on macOS ARM64,
including Rust, VM/native, isolated consumers and Chrome/Dart2Wasm. The existing
20 native-only browser skips remain unchanged. The package's analysis and 32
tests also pass with independently resolved hosted SDK dependencies and the
published Connectanum beta.8 native runtime.
[Hosted adapter CI](https://github.com/konsultaner/connectanum-dart/actions/runs/39256225074)
passes all 32 tests on each of Linux x64, macOS ARM64 and Windows x64 using Dart
3.13.5 and ObjectBox 5.3.2. Adapter coverage is 354/368 lines (96.196%); the new
96.19% floor does not reduce existing package floors.

A standalone consumer with an empty pub cache resolves the actual published
package, passes analysis, reserves an ID, borrows explicitly caller-owned native
memory into a C write with zero additional adapter body copies, and verifies
normal ObjectBox entity interoperability. Its owned read snapshot remains valid
after closing the Store and awaiting. The native memory is freed by its caller
after the synchronous write.

Fast Checks and the hosted package archive dry run pass. The broader
[CI run](https://github.com/konsultaner/connectanum-dart/actions/runs/39256225137)
is still in progress without a known failure when this record is written; this
is not an assertion that every mutation or coverage lane has completed. The
original FlatBuffers performance gates and independent protected-master review
remain separate. Logs, failed-first repros, review dispositions and fresh-cache
proofs are retained under ignored `out/objectbox-adapter-evidence/`.
