# Native eligibility for internal plaintext PPT loans

The marker-only implementation at `4738c452` is insufficient for raw nullable
metadata. CBOR/MessagePack accept an explicit null PPT option, while typed Dart
options expose the same null as an absent field. Native `binary_ppt_body` rejects
that original dictionary. The result-from-CALL encoder consequently omits the
PPT scheme when the marker-only Dart guard selects borrowing.

A fail-first Rust reproducer and a real CBOR socket reproducer both demonstrate
the lost `ppt_scheme`. The wire regression covers anonymous and ticket sessions;
its handler returns the original lazy body and typed PPT options. No application
transformation, benchmark verification or acceptance policy is changed.

Capability version 2 requires wide handles and the optional
`ct_internal_ppt_handoff_eligible_v1_wide` export. Dart checks the held native
CALL before lending and before forwarding a final reply. The predicate checks
the original metadata and binary body, refuses reserved `wamp`, encryption,
key IDs, explicit-null PPT fields, incompatible bodies and non-CALL messages.
It does not consume the alias or decode application data. Invalid or released
handles fail closed. Obvious typed mismatches are rejected before entering FFI.

New bindings reject missing queries and all marker versions other than 2. Older
marker-only bindings also reject version 2, preserving their existing copying
path rather than reintroducing the unsafe decision. The earlier marker-only
library remains a compatibility fixture, as does a derived version-2 Mach-O
fixture with only the optional query export renamed. The latter is explicitly
a test fixture, not a historical or production build.

Native tests cover both CBOR and MessagePack, 22 header/body combinations, a
non-CALL, invalid/expired IDs and alias lifetime. Dart native lifetime tests
cover all three nullable options and show that a retained alias remains usable
after the incoming reference is disposed. Live cases retain changed-body,
copied-body, changed-header, custom-detail and progressive fallbacks. Production
consumers also exercise empty, three-byte and 65,536-byte opaque replies and
retain their read-only body after session retirement. C layouts, other ABI
versions, wire schemas, library ownership and allocator contracts are unchanged.
