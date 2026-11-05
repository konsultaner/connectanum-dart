# Uncompiled native bootstrap source contract

## 2026-11-05 — Record an uncompiled native source contract

Three new private specification artifacts now define a draft C header, data initializer and source contract. The candidate requests a 512-byte layout with 64-byte alignment and separate decision/parent/child regions. Its assertions have not been compiled. The initializer requires valid owned writable storage and no concurrent access; its shape checks and data result supply no mapping, actor, lease or admission authority.

The draft start function returns UNIMPLEMENTED in source. There is no main, creator, decision publisher, child prefix, finite refusal, wait/collector or lease implementation. No compiler, disassembler, C helper or test ran. The files were generated under official EX and match their declared bytes; that readback is data, not original-runtime or atomic identity proof. Current twenty-helper and runtime source remain untouched and unimported.

Qwen's complete source review is ROOT-qualified. It missed existing alignment checks/assertions, conflated the explicitly native decision word with little-endian header bytes, and treated a documented caller precondition as an executed failure. No code was changed from that advice. New C11 draft research also leaves the byte-walk character-type alias as an actual-target binding obligation. Compiler/ABI, mapping, atomics, signal prefix, native ownership and physical EX remain unproved. Provider is absent, flags false, and RAM repair, original-runtime admission, final strict 48/50 and clean final CI remain incomplete.


The exact initial artifacts are retained in the evidence archive:

- Header: `315328fcf25ddf8c30dcf8cf2057b1e60ab905e87728737b93e24c20435913e6`.
- C source: `dbf19fd4a947124bdd93ab450a6d07e98d5806afd017a617ac14358954de33e4`.
- Contract: `94fd7bf020723247a66948bceca68c130c99d1e9ff15351c49cd58bd31f25f4e`.

These are new specification artifacts outside the production helper bundle and runtime checkout, not a behavior repair or adopted source epoch. The 512-byte object proposal establishes no process footprint, heap/RSS magnitude, growth, allocation volume or timing result. The data initializer was not called and its source return value is not an observed native status or accepted receipt.

The [C11 committee draft N1570](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf), clauses 6.2.8, 6.7.2.1 and 6.7.5, bounds the alignment discussion. Its effective-type and exact-width rules (6.5 and 7.20.1.1) leave a separate target typedef/character-access obligation for the draft's byte walk. This is a source-level portability inference, not a target counterexample, compiler result or runtime failure. The artifacts remain unchanged; no source fix was justified from model advice. Full primary tool returns stay local, with saved-return SHA/size indexed rather than a full PDF body hash.

The source explicitly separates little-endian header arrays from a proposed target-native decision word. It initializes only WAIT before any concurrent access. No atomic or signal-safe child implementation is supplied. Mapping ownership cannot be replaced with a token, pointer alignment, format tag, memory flag or successful initializer result. Parent/child region labels also do not enforce memory isolation.

The prospective refusal protocol requires complete actual creator registration before any finite-only decision and independently known SAME-child collection before considering original-context release. Those interfaces and mechanisms are absent. C0-C3 remain prospective, X1-X2 remain static exclusions, and zero native cases are ready.

The initial source-generation outer tool return objects were not separately serialized. Actual per-file O_EXCL/open/write/close journals, the source-generation receipt and source bytes are preserved; no omitted outer API object was reconstructed. New review returns and both raw streams are retained. This is not a full physical or transitive actor-closure claim.

Next work must bind native creator/collector interfaces, target character-byte access/alignment, compiler/runtime inputs and the original physical-lease preflight before any compilation, inspection or native execution. Original SDK transitive actors and independent generated-output/cohort authority remain unresolved. No original SDK, adoption or strict dispatch is authorized.

[Assessment](2026-11-05-flatbuffers-native-perf-native-bootstrap-source-contract-assessment.json), [evidence](2026-11-05-flatbuffers-native-perf-native-bootstrap-source-contract-evidence.tar.gz).
