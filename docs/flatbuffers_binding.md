# WAMP FlatBuffers binding

This is the wire contract for milestone [FlatBuffers and zero-copy native
buffers](https://github.com/konsultaner/connectanum-dart/milestone/1), starting
with [#95](https://github.com/konsultaner/connectanum-dart/issues/95).
It defines the implementation target. Checked-in bindings and fixtures currently
prove schema compatibility; they do not yet enable FlatBuffers transports.

## Pinned inputs and generation

The upstream source is Autobahn Python commit
`ca1e60c7f7dd78dc2df98a3b7bdc274ae197ae9c`, under
`src/autobahn/wamp/flatbuffers`. The seven original schemas and MIT license are
vendored unchanged in `schemas/wamp_flatbuffers/upstream`. Their SHA-256 hashes,
compiler binary checksums and runtime versions are in `manifest.json`.

Use flatc **25.9.23**, Dart `flat_buffers` **25.9.23**, Rust `flatbuffers`
**25.9.23** and Python `flatbuffers` **25.9.23**. The Dart formatter uses language
version 3.10, matching the package's lower SDK bound.

```sh
python3 tool/fetch_flatc.py --output /tmp/connectanum-flatc
python3 tool/generate_wamp_flatbuffers.py --flatc /tmp/connectanum-flatc/flatc
python3 tool/generate_wamp_flatbuffers.py --check --flatc /tmp/connectanum-flatc/flatc
python3 -m venv /tmp/connectanum-flatbuffers-python
/tmp/connectanum-flatbuffers-python/bin/python -m pip install flatbuffers==25.9.23
/tmp/connectanum-flatbuffers-python/bin/python tool/check_wamp_flatbuffers_interop.py --flatc /tmp/connectanum-flatc/flatc
```

Generation flattens include boundaries without changing upstream table fields,
enums or existing union ordinals. This avoids broken cross-namespace Dart imports
from flatc's multi-file generation. It then appends the extensions below.
Rust return types must explicitly name `core::result::Result`, because the WAMP
`Result` table shadows flatc's unqualified return type. Explicit root lifetimes
and generated Dart lint annotations are deterministic postprocessing. Python
uses `--python-typing` to generate imports for referenced tables. Generated
files must never be edited manually. WAMP uint64 getters use an internal reader
that combines two uint32 words, and generated convenience builders use a portable
allocator-backed builder with the same eight-byte integer layout. This avoids
unsupported dart2js ByteData uint64 operations without changing the schema to
float64 or losing IDs above 2^32. The WAMP ID upper bound is inclusive 2^53;
that exact value is supported, and larger uint64 values are rejected before
conversion to a potentially rounded JavaScript integer.
BufferContext construction respects the length and offset of an input Uint8List
view; it cannot extend into unrelated bytes of the underlying allocation.

The generator runs flatc's schema-conformance check against the original root.
The independent interop command compiles readers from the unmodified upstream
schemas, checks every upstream union alternative, sends a Python-produced CALL
to Dart and Rust, and reads their emitted CALLs with the upstream Python reader.
The typed-payload fixture nests a pre-encoded `wamp.proto.Message` FlatBuffer as
opaque application data, with `PPTScheme.OPAQUE`, `PPTSerializer.FLATBUFFERS` and
explicit schema metadata. It proves byte preservation without requiring a
database entity schema; actual typed/PPT session support remains issue #101.

Coverage reports keep the two compiler-generated Dart artifacts in raw file
totals and `generatedArtifacts`, separately from the handwritten-code gate.
The classification permits only these exact paths with flatc's provenance
header; it cannot exclude the portable runtime or other handwritten files.
The mandatory FlatBuffers Binding CI job checks exact regeneration and
independent fixtures. Existing handwritten coverage/mutation thresholds and
browser handling of VM-only ignore comments remain unchanged.

## Frame and discriminators

RawSocket uses assigned serializer ID **5**. WebSocket uses binary frames and
`wamp.2.flatbuffers`. One frame contains one ordinary, non-size-prefixed
FlatBuffer rooted at `wamp.proto.Message`, without a file identifier. RawSocket
framing supplies its network-order frame length separately. Batched FlatBuffers
and alternative schema revisions are not implicitly supported.

The root's slots are: union discriminator at vtable offset 4, union table at 6,
and optional extension metadata at 8. A union discriminator is **not** a WAMP
message ID. Use the following exact map:

| Message | Union tag | WAMP ID |
| --- | ---: | ---: |
| HELLO | 1 | 1 |
| WELCOME | 2 | 2 |
| ABORT | 3 | 3 |
| CHALLENGE | 4 | 4 |
| AUTHENTICATE | 5 | 5 |
| GOODBYE | 6 | 6 |
| ERROR | 7 | 8 |
| PUBLISH | 8 | 16 |
| PUBLISHED | 9 | 17 |
| SUBSCRIBE | 10 | 32 |
| SUBSCRIBED | 11 | 33 |
| UNSUBSCRIBE | 12 | 34 |
| UNSUBSCRIBED | 13 | 35 |
| EVENT | 14 | 36 |
| EVENT_RECEIVED | 15 | 37 |
| CALL | 16 | 48 |
| CANCEL | 17 | 49 |
| RESULT | 18 | 50 |
| REGISTER | 19 | 64 |
| REGISTERED | 20 | 65 |
| UNREGISTER | 21 | 66 |
| UNREGISTERED | 22 | 67 |
| INVOCATION | 23 | 68 |
| INTERRUPT | 24 | 69 |
| YIELD | 25 | 70 |
| HEARTBEAT (extension) | 26 | 7 |

EVENT_RECEIVED exists upstream even though Connectanum does not currently expose
its QoS feature; recognizing its table is not a claim to support that feature.
HEARTBEAT is already supported by Connectanum's native message model, so its
table is appended to the union. Never insert alternatives before existing ones.
Unknown union alternatives are rejected before table access. Arbitrary unknown
WAMP message codes cannot be invented under this binding.

The upstream schema history changed RPC union ordinals when EVENT_RECEIVED was
inserted. The generic serializer identifier does not identify a schema revision.
Interoperability claims therefore name this pinned revision and actual fixtures;
older incompatible layouts must fail explicitly. A genuinely incompatible
binding requires a separately registered WebSocket subprotocol, not reserved
RawSocket IDs 6–15.

## Options, details and authentication

Upstream tables carry the standard fields declared in each vendored schema.
Map camel-case Dart getters and snake-case schema fields to the existing WAMP
options/details keys without renaming public message APIs.

| Messages | Dictionary represented by metadata |
| --- | --- |
| HELLO, WELCOME | Complete details, including roles/features and authentication data |
| ABORT, GOODBYE | Complete details |
| CHALLENGE, AUTHENTICATE | Complete extra |
| ERROR, EVENT, RESULT, INVOCATION | Complete details |
| PUBLISH, SUBSCRIBE, CALL, CANCEL, REGISTER, INTERRUPT, YIELD | Complete options |
| HEARTBEAT | Complete Connectanum heartbeat details |
| PUBLISHED, SUBSCRIBED, UNSUBSCRIBE, REGISTERED, UNREGISTER | No dictionary; metadata must be absent |
| UNSUBSCRIBED, UNREGISTERED | Complete revocation details where supported |

The upstream `wamp.Map` is one string key/value pair, not a generic dictionary.
It cannot carry SCRAM challenge fields, binary crypto material or arbitrary
authentication extras faithfully. Other gaps include custom role features,
custom options/details, some Connectanum routing flags, generic PPT names and
absence versus explicit default/null values. These gaps are resolved by appending
`metadata: [ubyte]` to the root. It contains exactly one complete CBOR dictionary
for the message's existing options/details/extra position. It contains no
application args/kwargs and no full re-encoded WAMP message.

When metadata is present, it preserves dictionary semantics, key presence,
null/default distinctions and binary values. Standard upstream fields are also
written where representable. Receivers validate agreement between both
representations; metadata must not override a contradictory routing ID, URI,
authentication field or option. Omitted dictionary keys may use upstream
default/required-field placeholders only under negotiated extended semantics.
A required WELCOME string whose logical value is absent uses an empty wire
placeholder and remains absent in the metadata dictionary; it must not create
an authentication identity. WELCOME from an upstream-only peer must satisfy the
upstream required fields with real values.

A frame cannot carry metadata on a message with no dictionary. Non-map metadata,
non-string keys, duplicate keys, extra trailing CBOR values, oversized/deep data
and contradictory fields are errors. The codec applies the existing WAMP bounds
and explicit metadata byte/depth/item limits before materialization.

## Capabilities and fallback

The codec can parse the pinned upstream subset and the compatible extension.
Transport session state controls whether extension semantics may be sent:

1. HELLO advertises `_connectanum_flatbuffers_metadata_v1: true` in each applicable
   role's features, carried in its metadata dictionary. The basic HELLO fields
   remain valid for an upstream reader.
   The leading underscore follows WAMP's implementation-specific key convention.
2. WELCOME acknowledges the same feature for the selected router roles. The
   receiver records peer support before ordinary traffic is admitted.
3. Subsequent metadata and HEARTBEAT extension messages require this capability.
   HELLO/WELCOME metadata used for capability exchange is the bootstrap exception.
4. Without acknowledgement, an upstream-subset session may send only values
   represented losslessly by the pinned schema. Unsupported authentication
   extras, custom/nullable/default-sensitive fields or extension alternatives
   fail explicitly. No silent dictionary loss or encoding relabeling is allowed.
5. If a caller explicitly configured existing serializer alternatives, transport
   negotiation can use them according to the existing selection model. Selecting
   FlatBuffers alone produces a useful unsupported-peer error rather than
   inventing automatic reconnect or schema downgrade policy.

Low-level serialization can construct either form independently; transport
state still must enforce capability checks. An old native library must reject
FlatBuffers operations before connection establishment instead of accepting a
handshake it cannot parse. Native WebSocket and RawSocket advertisement is enabled
only after codec, metadata and routing support exist end to end.

General serializer preference negotiation
[#44](https://github.com/konsultaner/connectanum-dart/issues/44) and WAMP IDL
[#26](https://github.com/konsultaner/connectanum-dart/issues/26) remain separate
work. The new serializer requires neither a schema registry nor an IDL service.

## Dynamic, typed and encrypted payloads

Ordinary dynamic `args` and `kwargs` use CBOR inside the upstream byte-vector
fields, matching Autobahn's default FlatBuffers payload composition. An absent
vector remains absent; an empty list/map is a present vector containing its CBOR
encoding. Keep these boundaries when converting existing lazy payload models.
Label benchmarks using this path **FlatBuffers envelope + CBOR payload**.

Typed application FlatBuffers are already encoded bytes with a retained owner.
Carry them through the upstream transparent `payload` vector with explicit PPT
scheme/serializer metadata. The application chooses the schema; the transport
does not deserialize an unknown entity into List/Map or infer ObjectBox types.
Opaque data remains uninterpreted. Typed/PPT capability and schema identity must
be explicit at the application boundary; a routing serializer name alone cannot
turn ordinary dynamic values into a typed FlatBuffer.

Transport encoding, PPT payload encoding and encryption are independent. Preserve
the existing CBOR E2EE profile over a FlatBuffers envelope. Typed FlatBuffers E2EE
requires an explicit compatible/versioned payload profile; unsupported
combinations fail clearly. Encryption, JSON binary conversion, WebSocket masking,
TLS and necessary coalescing can introduce transformation copies. The metadata
extension and binding do not remove those copies.

## Ownership and performance requirements

Generated readers are internal implementation tools, not an untrusted-byte public
API. Rust verifies before accessing generated tables. Dart must validate bounded
offsets, tables, unions, strings, vectors and metadata before exposing a view;
generated factories alone do not provide this guarantee. Enforce WAMP's safe
integer bounds independently of the uint64 wire type and test VM/JS/WASM parity.

A borrowed vector must retain its entire input owner. Native builders must retain
the allocation base/capacity independently of FlatBuffers' backward-built used
subrange. Foreign storage must never be adopted as a Rust Vec. Mutable Dart views
cannot be revoked by changing a wrapper flag; direct builders must expose safe
writes/freeze/transfer operations rather than stale mutable aliases.

Generated numeric readers can allocate on eager access. The codec must use
verified byte ranges and retained lazy views for payloads, not eager generated
list conversion. Constructing a nested vector around pre-encoded bytes can also
copy; scatter/gather or direct native construction must preserve valid offsets,
length prefixes and alignment and account for any builder-growth copy.

The milestone requires actual allocation-identity and copied-byte evidence at
each claimed boundary, and representative throughput/latency/memory gates against
the better CBOR/MessagePack baseline. Schema conformance or a fast microbenchmark
does not establish these runtime requirements. Actual ObjectBox bindings,
transaction management, IDs and relations remain in a separate adapter; the core
provides generic owned/external-memory contracts.

## Research and verified limits

- [WAMP serializer discussion #72](https://github.com/wamp-proto/wamp-proto/issues/72#issuecomment-533780328)
- [Additional serializers #355](https://github.com/wamp-proto/wamp-proto/issues/355)
- [Zero-copy PPT sizing #427](https://github.com/wamp-proto/wamp-proto/issues/427)
- [RawSocket FlatBuffers assignment #469](https://github.com/wamp-proto/wamp-proto/pull/469)
- [WEP006](https://github.com/wamp-proto/wamp-proto/blob/master/wep/wep006/README.md):
  currently a heading, not a complete normative binding.
- [Current WAMP specification](https://wamp-proto.org/wamp_latest_ietf.html)
- [Autobahn schema reference](https://autobahn.readthedocs.io/en/stable/wamp/flatbuffers-schema.html)
- [Pinned schema source](https://github.com/crossbario/autobahn-python/tree/ca1e60c7f7dd78dc2df98a3b7bdc274ae197ae9c/src/autobahn/wamp/flatbuffers)
- [Pinned serializer source](https://github.com/crossbario/autobahn-python/blob/ca1e60c7f7dd78dc2df98a3b7bdc274ae197ae9c/src/autobahn/wamp/serializer.py)

The pinned Autobahn object serializer has an unimplemented object serialize
method and maps WAMP numeric IDs against a root union discriminator in its
unserialize dispatch. Do not use its successful import as proof of a working
live peer. Current independent evidence uses the original schema's generated
Python reader/writer. Later conformance work must provide a functioning external
peer or equally explicit bidirectional codec fixtures for supported session flows.
