# Native FlatBuffers sparse reader

The native reader previously reserved every schema field and stored absent
optional references as internal null entries. The Dart reader already omits
these entries. The selected change omits them in native temporary storage while
retaining scalar defaults and decoding/validating every field. Tables with at
most four schema fields keep their original reservation to avoid a redundant
scan; larger tables reserve only scalar and present-reference entries after full
vtable/object bounds checks.

The public wire/schema, owners, byte aliases, ABI and limits are unchanged.
Missing metadata is treated like the former null entry only for the existing
no-dictionary message kinds. Missing Map.value still means CBOR Unit, including
contradiction checks. Known challenge methods still permit an omitted method_name.
Required fields, invalid offsets, enum/union checks, depth/cache/table/string and
vector limits remain unchanged.

## Correctness and actual-source proof

Fresh baseline `bin/test-fast` on `ca020025` passes in 894.909 seconds with all
3,204 source/four resolved hashes unchanged. Separate private baseline/candidate
builds each pass 399 unit and three integration tests. Both incomplete controls
are independently marked and built: removing the Map-null compatibility change
fails the contradictory-Map semantic assertion; removing the metadata change
fails metadata-presence assertions. Compiler failures do not count as controls.

The first private attempt used an invalid fixture: the normal encoder projects
only string-valued Map entries and explicitly writes method_name. The baseline
correctly accepted that fixture's authoritative metadata. That failure remains
retained. The corrected fixture explicitly writes a typed null Map and omits the
known method name. It covers all five known methods and contradictory/missing
CBOR keys. Three production test groups also retain no-dictionary controls,
required empty dictionaries, zero IDs and false acknowledge metadata.

Final GLM advisory review raises no confirmed defect after source inspection of
all Fields consumers, null construction and bounds; its speculative risks and
resolutions are retained separately.

Actual-source `cargo fmt --all --check`, all 398 unit/three integration tests and both
allocation examples pass. All 34 emitted allocator observations and wires match
the audited selected private candidate exactly. All 3,205 source/four resolved
hashes remain fixed. The initial formatter invocation lacked `--all` on the
virtual workspace and failed before native tests; that command failure is retained.

## Component observations and limits

Independent private audit verifies separate source/build targets, actual-core
variant markers, 12,828 private hashes, 76 allocator inputs and 836 cold/repeated
observations. All 56 wires match and no allocator request increases. Encoder
requests are unchanged. Common 1-KiB reads save 224 bytes for Error, 336 for
Result, 392 for Call, 616 for Publish and 560 for publish-exclude variants.
Cold schema initialization costs remain separate from steady observations.

Ten inputs are fixed before the timing observations. Eight balanced pairs rotate
case and variant order; each observation uses a fresh self-reported native PID,
1,024 warmup operations, batches of 64, at least 8,192 operations and 250 ms.
Both monotonic elapsed time and process CPU time are retained. Independent audit
verifies every source/input/binary hash, bracket, ordering and floor for all 160
rows. Self-reported PID is not an external Popen ownership witness.

Selected candidate/baseline paired CPU median ratios are 0.94072 Published,
1.00044 challenge, 0.90484 Hello, 0.95451 Welcome, 0.82024 metadata Call,
0.86270 typed Call, 0.78006 1-KiB Result, 0.79958 1-KiB Call,
0.87765 publish-exclude and 0.78083 1-MiB Result. Challenge's approximately
0.04% CPU cost is retained. No observations are removed or rerun to hunt noise.

The earlier all-table pre-count variant and subsequent early-skip variant both
retain their full correctness/allocation/timing observations. The latter has a
challenge CPU ratio of 1.01289 and is excluded; the selected simpler short-table
variant is used. These are component observations, not end-to-end parity or RSS
acceptance. The previous runtime's seven strict90 numerical costs remain open.
Final full verification, all CI, production copy/lifetime renewal and the original
complete primary/supplemental gates are required before milestone acceptance.

The approved copy scope uses the standard Dart SDK: Connectanum-owned boundaries
are measured and tested; dependency SDK/TLS/crypto internals remain explicitly
unmeasured. E2EE and transcode boundary proof must be renewed on the final runtime.

## Retained local evidence

Reports are under `out/flatbuffers-resume-20261022/` in the investigation worktree:
`native-sparse-baseline-fast-result.json`, `native-sparse-private-v5-result.json`,
`native-sparse-private-v5-independent-audit.json`,
`native-sparse-timing-v6-independent-audit.json`, and
`native-sparse-resulting-result.json`. Earlier attempts and excluded variants
remain alongside them. Local reports are provenance records; hosted acceptance
artifacts remain required for release decisions.
