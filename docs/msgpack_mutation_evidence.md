# MessagePack mutation evidence

The portable backend is the production fallback for runtimes without exact
64-bit byte-data accessors. VM and Chrome tests exercise that same stateless
backend, including exact signed/unsigned word boundaries against a BigInt
reference, malformed lengths, trailing data, nested containers, binary ownership
and one-shot iterables. The normal VM delegate path retains native integer
precision. JavaScript selects portable encoding before consuming an iterable.

The complete prepublication VM run for codec source SHA256
`f2effede0149a6f61faa51f08e575d0f31b210f7379afcc86a8f4c1a4bf379db`
contains 205 generated/selected mutants, 196 viable mutants, 182 assertion kills,
14 observed survivors and nine compile errors. Clean and restored baselines
pass. The raw assertion score remains **92.8571%**. Five hash-pinned functional
equivalence proofs, using the existing adjusted-score policy, yield
**95.2880%** against the unchanged **95%** gate. All raw mutants and outcomes
remain in the report; no operator or source range is filtered. Hosted final-head
qualification is recorded separately in the repair plan/PR.


The browser coverage repair pairs each marker's length width with its exact
byte-data reader in a private, immutable reader object. All six string/binary
and extension width selections remain covered by the same boundary tests;
unsupported internal width requests are no longer representable by the reader
API. The complete current VM campaign still inventories all 205 mutants and
passes clean/restored baselines with the counts above. A real Chrome coverage
probe covers 178/182 executable lines (97.8022%), above the unchanged 97.29%
file floor. The remaining four lines are the VM delegate's serialization path.
The same five functional proofs are rechecked and rebound to this source hash;
no new equivalence class is added.

## Functional proofs

The five entries are pinned independently for VM and web in
`tool/mutation_equivalents.json`. Every change to the codec invalidates their
source hash. They preserve output bytes, input ownership and input traversal;
they do **not** assert equal allocation cost or waive any performance gate.

- `28a038302ac94298a3e4` and `6df36a52729b8d698c5c` change the private map/iterable
  BytesBuilder's copy setting. Each added chunk is a private encoding or header,
  never modified after addition. The delegate also returns owned encoding
  storage: binary headers and bodies are coalesced before its result escapes,
  and its scratch buffer is detached by `takeBytes`. Copying at addition versus
  coalescing at completion changes allocation timing, not returned bytes or
  caller ownership.
- `2bbad549520ff41f565b` changes only the growability of the private list created
  from a non-List iterable. Both variants enumerate the input exactly once.
  Subsequent code reads length/elements, never writes, grows, exposes or
  inspects the capacity of that private list.
- `72b040f96bbb34d187e0` changes the first OR to AND in the availability guard.
  Every private call supplies an offset at least one and a nonnegative length.
  Both negative-input terms are therefore false; their conjunction and
  disjunction are equal. The final end-of-buffer check is unchanged.
- `f06bee2ec19ce04d0306` additionally rejects offset zero, which no private caller
  supplies. Collection/scalar readers add one or two to a validated offset;
  length-prefixed/extension readers also add their positive header width.
  Lengths are unsigned byte-data values, marker lengths or nonnegative constants.
  These invariants also hold for malformed/truncated wire inputs.

The custom-List conversion survivor and runtime-specific capability guards are
not excluded. Existing wire assertions, complete inventories, deadlines, the
strict kill classifier and independent memory/performance budgets remain in
force. A bounded local judge checked the three proof classes; source inspection
and complete mutation evidence, rather than the advisory opinion, establish the
accepted result.
