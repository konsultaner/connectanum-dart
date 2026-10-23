# FlatBuffers validation memo keys

## Change and preserved contract

The structural validator creates a record `(offset, schema reference)` for every
table lookup. This follow-up stores common pairs as integer map keys, avoiding
those temporary records and their structural hashes. It changes no traversal,
table count, in-progress sentinel, cached height, depth/string/vector limit,
wire format, byte owner or copy instrumentation.

Offsets from zero through `0xffffffff` and references through `0xffff` use
`offset * 0x10000 + reference`. The maximum is `2^48-1`, exactly representable on
JavaScript as well as VM/Wasm. Multiplication avoids JavaScript's 32-bit bitwise
operations. Negative or larger components retain the original record key. Thus
schema growth and unusually large offsets do not introduce an acceptance limit.
Integer and record domains cannot alias, and distinct schema interpretations of
one physical offset remain separate validation entries.

## Private controls and measurement

The fixed baseline is `cb4bd8076a4fb35a51a5441b53a6a59c57e4c53f`, whose code and
four resolved inputs match fully verified diagnostic `f2dbdfa4`; only three docs
differ. Private baseline/candidate libraries differ only in the validator plus
explicit test/selection probes. Both pass 501 functional cases and 63 cases per
browser backend, JavaScript and Wasm. Checks include packed/fallback boundaries,
cached heights at exact depth limits and in-progress sentinels. A deliberately
unsafe offset-only key passes 498 cases and fails three, including the real
aliased-schema table-budget undercount. No unsafe source is adopted.

An initial fixture imported the wrong generated wire file and failed to load
before measurement. That failed attempt is retained, not counted as a runtime
regression. Corrected staging keeps separate logs and ledgers. Private probes do
not ship; production regression tests cover distinct-schema and repeated
same-schema table budgets through the public validator.

The balanced component retains 160 raw rows, 32 fresh workers and 128 measured
allocation windows. Independent audit verifies all source/resolution/private
hashes, package selections, exact wire bytes and payload aliases, worker identity,
heap-window evidence and nonoverlapping snapshot brackets. Raw SHA-256 is
`eb660a30672de96763e16fc48f4a2e26823e04cb7dd04dfbcfa518c92a40fafb`.

| Shape | Median candidate/baseline decode time | Managed bytes saved/decode |
| --- | ---: | ---: |
| RESULT | 0.98961 | 65.33 |
| CALL | 0.99163 | 63.02 |

CALL timing pairs include one regression. These are modest component results,
not causal end-to-end, RSS, Linux or complete parity acceptance. No result is
pooled with earlier runners or compounded into a total speedup.

## Review and resulting-source validation

GLM advisory review reports no confirmed correctness finding. Its wording about
out-of-domain rejection is corrected: the code falls back to records. Final
limits cannot change during synchronous private validation. An earlier review
attempt could not acquire the machine lease; the later attempt completes without
bypassing it. Qwen test planning hits its output limit; the retained GLM retry
supplies the memo-height/sentinel/depth checks.

Resulting-source formatting and analysis pass, as do all 3,457 serializer cases
and eight component-isolation contracts. All 3,203 tracked sources/four resolved
inputs stay fixed during those checks, and adopted runtime bytes equal the
audited private candidate exactly. The new component-isolation contract fails
before the tool accepts validator-only changes, then all eight pass. The tool
still restores the complete pinned baseline and restricts allowed core diffs.

Frozen full verification, hosted component/CI/copy proof and all unchanged
performance gates remain required. This change does not address the independently
reproduced large TLS receive-window stall.
