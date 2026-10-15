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

Complete new VM/browser execution and resulting-head hosted checks are pending.
The source mapping audit is retained locally in
`out/flatbuffers-milestone-finish/owned-lazy-equivalence-rekey-audit.json`.
