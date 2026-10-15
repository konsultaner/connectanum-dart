# Lazy-payload mutation proof refresh — 2026-10-15

Hosted source `b43a0a56` fails mutation startup in both `core-lazy-web` and the
`client-utils-vm` group because the `core-lazy-vm`/web equivalent records still
identify the preceding source offsets and hash. Neither job reaches its baseline
or score calculation. The [web job](https://github.com/konsultaner/connectanum-dart/actions/runs/38798736713/job/116642692547) and [VM job](https://github.com/konsultaner/connectanum-dart/actions/runs/38798736713/job/116642692770) expose the same stale first identifier.

The new owned-copy import and observations shift offsets. All eight previously
justified predicates are byte-for-byte unchanged. A UTF-16-aware mapping from the
prior source (SHA-256 `7e676c1df414f24568cbfddad44b739b4f7dd11110460b2e25255eb314f20000`)
finds each predicate uniquely in the complete current 356-mutant inventory.
The current source hash is `bc5d0bf5fdd8b16357ed98180bc4ee47dc20fa666ad79033df8dc18fe47a1c7b`.

The justifications are rechecked against actual writes: successful packed decoding
assigns the record and synchronously clears its decoder; constructors/copies
preserve that state. Positional and keyword bytes/decoder pairs are initialized,
set and cleared together. New observations in owned cloning and PPT coercion do
not write these fields. Thus the eight existing equivalence reasons still apply.
Their reasons and count stay unchanged in each target; only identifiers and
source hashes are refreshed. This does not add exemptions, drop mutants, or change
the 95% threshold. The runner's strict stale-proof rejection remains intact.

Both complete targets now pass: 356 selected per target, 268 killed, 68 compile
errors and twenty survivors (eight pre-existing equivalences), giving an adjusted
assertion score of 95.7142857143% against 95%. Both baseline/restored-baseline
executions succeed, with zero runner errors/timeouts. All 246 relevant core,
fixture, dependency and mutation-policy inputs plus HEAD remain unchanged.
Seven unrelated benchmark/reporting files change during execution; the original
3,076-file drift check is retained as failed and is not called a frozen full-tree
verification. The separate scoped audit passes against the actual target inputs.

A read-only preflight also finds sixteen older proof records in browser transport,
bounded router drain and router settings. Their unchanged predicates map uniquely
from hash-verified historical source to the current complete inventories (125,
2,491 and 345 mutations; the existing drain slice still selects 36). Reasons,
counts, ranges and thresholds stay unchanged. Review confirms browser certificate
options remain unused, the drain identity/list-snapshot invariants remain intact,
and private normalized metrics paths and protocol deduplication retain their
original guarantees. Metadata for all 154 proofs across thirteen targets and ten
sources validates. Thirteen preflight regressions pass; canonical verification
and CI fast checks now reject stale proofs before expensive tests.

Resulting-head hosted checks remain pending.
The source mapping audit is retained locally in
`out/flatbuffers-milestone-finish/owned-lazy-equivalence-rekey-audit.json`.
