# Native external-buffer allocation provenance

An anchor previously selected a native allocation using only matching offsets
and lengths. An unrelated Dart or native allocation with the same bounds could
therefore resolve to the anchor's pointer. Six fail-first regressions reproduce
this: three Dart view shapes, two foreign native view shapes, and a real native
SHA-256 call hashing the anchor's bytes instead of its requested input. The
observed defect is a read from the wrong allocation within accepted bounds.

The repair retains the original ByteBuffer in allocation metadata and rejects
views whose backing buffer differs before exposing the pointer. Existing range
checks and the caller's copying fallback remain intact. It adds no ownership
transfer or foreign-memory adoption. Matching byte contents are insufficient;
two additional controls use equal contents in separate Dart/native allocations.
Legitimate nested read-only views still resolve to the original allocation.

ByteBuffer getter wrappers need not be identical. The pinned
[Dart VM implementation](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/sdk/lib/_internal/vm/lib/typed_data_patch.dart#L1818)
compares their underlying typed-data storage. The
[Expando contract](https://api.dart.dev/dart-core/Expando-class.html)
permits attached values to be collected after their keys become inaccessible.
A subprocess using the VM service forces collection while the anchor is live,
then after it is dropped. Its weak reference stays live before release and
clears afterward, with exactly one managed finalizer notification. This checks
retention and collection of the Dart root; it does not count native frees or
claim cross-isolate ownership. The existing malloc finalizer is unchanged.

The final 20-case suite passes without skips on macOS (Dart 3.13.1) and Linux
arm64 (Dart 3.13.5), including SHA-256 and actual GC. Linux uses the previously
verified b8096fd6 production library. Before repair, 11 cases pass and six fail;
earlier 17/18-case runs are retained separately. Source and log hashes are in
[the evidence record](2026-10-07-native-external-buffer-provenance-proof.json).

Local Qwen test planning, GLM judgment and Qwen review completed. Their useful
allocation and lifetime leads were verified by the tests and source. Suggestions
to compare wrapper identity are contradicted by legitimate-view checks and VM
source. The review's proposed GC-loop failure contradicts the boolean condition;
loosening the finalizer count would weaken the isolated single-attachment check.
No out-of-bounds read or use-after-free was observed by these regressions.

Fresh quiet `bin/verify` passes at exit 0, including Rust, VM and live consumers,
1,563 benchmark, 4,958 router, 4,751 Chrome/Dart2Wasm core and 2,829 browser
client tests with 20 unchanged native-only skips. The preceding d8cfaa5f
`bin/test-fast` pass supplies the pre-change baseline. Publication
and resulting-head hosted checks remain pending. This repair does not establish
complete socket/TLS copy attribution, benchmark parity or unresolved milestone
acceptance criteria. Master 3bac4cf5 was fetched from both remotes and is already
an ancestor of the feature branch; merging github/master changed nothing.
