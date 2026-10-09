# E2EE profile and key revalidation after policy callbacks

Started 2026-10-04; verification completed 2026-10-05. Follow-up for issue #101
after the locally accepted and pushed `0cf9e65e` checkpoint. This repair adds no
native-owned crypto API or new wire format. Local canonical, browser coverage and
portable VM/Chrome mutation acceptance pass; exact-head hosted CI and benchmark
acceptance remain pending.

## Reproduction and repair

A four-case direct native probe proves that both ciphers still produce ciphertext
when policy changes `ppt_scheme` to `json` or the typed serializer to `cbor` after
initial validation. The probe exits 255 and its output/source/library hashes are
preserved in `/tmp/connectanum-flatbuffers-native-pack-policy-initial-repro-proof.json`.
The bytes retain their provider-selected framing despite the changed metadata.

The permanent matrix covers packing/unpacking, CBOR/typed profiles and both
ciphers for portable and native providers. It tests invalid scheme, serializer,
cipher and key mutations; a different configured key; and native release inside
policy. Before repair, all 40 portable and 48 native cases execute, with 36
assertion failures in each backend. Twelve native and four portable existing
controls already pass. Proof: `/tmp/connectanum-flatbuffers-policy-contracts-fail-first-proof.json`.
Initial fixture compile errors from omitted `Cbor` in four factory names are
preserved separately; they are not those behavioral reproductions.

The repair checks the constructor-fixed profile again after policy, rechecks
native provider state, and resolves/validates the current options key before
using it for crypto and metadata. Native preparation returns that validated key
snapshot. Existing native wire-mutation rejection retains its earlier ordering.
Typed malformed-byte and length preflight remains before policy. No callback
mutation is rolled back, and selecting another configured key remains allowed.

The original 88 contracts pass after repair. Eight additional reuse controls
preserve the existing behavior: resolving a key fills `PPTOptions.pptKeyId`, so
reusing those options keeps that explicit key and skips another policy selection.
Clearing the key requests selection again. This is a compatibility contract,
not a newly introduced policy cache.

The GLM review questioned this write-back because a shared options object pins
the first selected key for later calls. The behavior is present in the pushed
0cf9e65e source and existing CBOR/native regression tests assert that packing
populates `ppt_keyid`. The follow-up keeps that public behavior and now tests
reuse for all four typed/CBOR and AES/XSalsa combinations. A later caller can
clear the key to request selection again. Removing write-back would change the
existing API contract and requires a separate product decision. During a single
callback invocation, any key ID the policy writes into the mutable options takes
precedence over its returned key and is validated against the configured keyring
before encryption/decryption.

Complete focused verification passes 174 portable cases on VM, Chrome JS and
Chrome WASM, and 2,468 client/native cases run sequentially on each current and
older library. A first
parallel six-file native command has one unavailable-keyring-handle error during
provider construction; its failed log remains preserved. These test files invoke
process-global native shutdown, and the canonical scripts run them in separate
sequential commands. The corrected serial invocation passes every case with
unchanged deadlines. Do not relabel the parallel failure as passing or infer a
production repair from its reproduction.

Fresh canonical verification runs sequentially under
`/tmp/connectanum-flatbuffers-policy-revalidation-canonical-*`, freezing 1,458
product files at snapshot SHA256
`c5d9f125ffd422b5a82b4173c4510a0e0690acb3c7ab7186b35cb66dcb54d2ba`.
Independent inventory generation selects 308 core E2EE mutants. It is not a
scored campaign by itself; final scored results follow below.

## Completed local acceptance (2026-10-05)

Fresh `bin/test-fast` and `bin/verify` complete at exit 0 against the same frozen
1,458-file product snapshot. The first verify attempt remains recorded as
incomplete; the resumed result is separately audited with the earlier fast pass
at `/tmp/connectanum-flatbuffers-policy-revalidation-canonical-resumed-completed-audit.json`.
Fresh `bin/test-browser-coverage` passes on that product source set. All 99
coverage artifacts and summary hashes verify; handwritten Dart Chrome line
coverage is 96.2473% overall (core 96.1862%, client 96.4297%). This command leaves
164 library files outside measured coverage and measures the two generated
FlatBuffers artifacts separately. Audit:
`/tmp/connectanum-flatbuffers-policy-revalidation-browser-coverage-completed-audit.json`.

The regenerated 308-mutant core E2EE VM and Chrome campaigns both pass the
unchanged 95% adjusted assertion-score gate at 95.9839%. Each records 239
killed, 10 surviving and 59 compile-error mutants, zero equivalents, and
matching 167-test clean/restored baselines. The independent auditors verify the
mutation inventory, source/test/support inputs, native library and per-mutant
logs:
`/tmp/connectanum-flatbuffers-policy-revalidation-core-e2ee-vm-completed-audit.json`
and `/tmp/connectanum-flatbuffers-policy-revalidation-core-e2ee-web-completed-audit.json`.
The surviving mutations do not change observable protocol or key-policy results;
byte-copy cases remain subject to issue #103's allocation and copy-count benchmark.
These local results do not establish hosted, all-platform or performance acceptance.

## Local companion dispositions

The test companion suggested accepting mismatched profiles and byte-identical
fresh-nonce encryption. Both conflict with the constructor-fixed serializer/
cipher and randomized encryption; direct source and the fail-first tests reject
that advice. The GLM judge requests key reuse, metadata consistency and native
liveness controls; those are covered, with existing key write-back preserved.
Native entry independently validates its session handle; synchronous Dart checks
do not replace that native validation.

A broad review request hit its output-token limit; a narrower production-only
review completed. Its proposed removal of repeated validation is rejected:
packing resolves the cipher once after policy, and unpacking intentionally checks
both before and after potentially mutating policy. The verification helpers only
read/check fields and throw; they do not alter the options. All advisory outputs
remain under `/tmp/connectanum-flatbuffers-policy-*`. No backend outage is claimed.
