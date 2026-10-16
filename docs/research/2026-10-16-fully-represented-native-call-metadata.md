# Fully represented native CALL metadata

The [Linux CPU diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/38966607909)
at `65833214` passes independent source, PID, sampling-window, report, JIT-map
and retained native-library hash audits. Dart router stacks still capture
24 inclusive `retainNativeMetadata` ticks, including bounded validation and
retention-state construction. These overlapping samples are diagnostic, not
per-operation CPU costs or parity acceptance. The preceding 90-row strict
`b4e2b4ea` comparison passes allocation parity for all three constructions but
fails CPU and other latency/throughput/GC/RSS gates.

The router now recognizes a limited dictionary whose initial projection is
fully represented by a freshly constructed CALL model: exactly two ASCII text
entries, `ppt_scheme` and `ppt_serializer`, matching the model, with every other
nullable option field unset. Before any custom-field loader is attached, this
model has no custom fields. `WampDictionaryCodec.serializeCallOptions` therefore
projects exactly the original logical dictionary. Edits and root replacement
can be serialized normally, without retained history or assignment observation;
CALL's option fields are nullable and introduce no implicit boolean defaults.

The recognizer validates the whole limited CBOR grammar: a two-entry map, both
known keys exactly once, text major types, complete bounded one/two-byte lengths,
ASCII equality and no trailing data. Nonminimal text lengths are valid CBOR and
are explicitly compared with the existing decoder. Every other shape uses the
existing bounded/deferred or tagged-eager retention path. Non-ASCII data,
unknown/default/null fields and additional controls are preserved there. No
application vector is read. PUBLISH/YIELD keep their existing retention because
their model defaults require different presence handling.

A fail-first test observes an unnecessary unresolved custom loader on the
preceding source. A source-restored causal repeat confirms the assertion fails
before this change. Tests cover edits before first resend, custom/transaction
hash fields, both key orders, ASCII/Unicode boundaries, 16-bit and longer text,
unaligned read-only views, nonminimal/indefinite encodings, all incomplete
prefixes, 598 byte mutations against eager values/error phases, trailing bytes,
duplicates, matching invalid Latin-1 UTF-8 and tagged invalid dates. All 3,971
binding/metadata cases and both anonymous/ticket production consumers pass;
analysis is clean. The local model judgment finds no concrete counterexample
under these invariants; its nonminimal-length and transaction-hash notes have
explicit decoder and mutation coverage. Fresh parity and final full verification
remain required. No benchmark workload, serializer contract or budget changes.
