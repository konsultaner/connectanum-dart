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

The resulting verification is recorded below; current CI and all unchanged
complete performance gates remain required. This change does not address the
independently reproduced large TLS receive-window stall.

## Resulting Linux evidence

Frozen full `bin/verify` on runtime `629001a648ebf178fbb5c983d9df831ff7dad9d5`
passes in 22m43s, including Chrome/Wasm. All 3,204 tracked source/four resolved
hashes stay fixed, with a clean tree. Log SHA-256 is
`0c686bf2a089e54fb278fb93ed8680ba64ec55864aad367da82fd1d35be000fb`.

The [hosted decoder component](https://github.com/konsultaner/connectanum-dart/actions/runs/39893890401)
passes independent audit of 3,204 sources/four retained resolved contents,
204 private artifact hashes, 492 cases per variant, 160 raw rows/32 fresh workers/
128 allocation windows, full wires/aliases and nonoverlapping snapshot brackets.
RESULT/CALL managed savings are 65.47/62.99 bytes. Linux time ratios are
1.00671/0.96892: RESULT is 0.67% slower on this runner, so this evidence does not
establish a universal speedup. Archive SHA is
`337247977c893f23fd461f14626ffa6b2ee30a7880e5807c85a2baeb991b139c`;
raw SHA is `8cae7632d07e6080702441f83902e6775f335e4634dcbb2f159b05ebd8bc7968`.

The renewed [production copy/lifetime proof](https://github.com/konsultaner/connectanum-dart/actions/runs/39893892910)
passes all source/content/binary/cleanup audits: 120 owned cases, 300 short rows/
all 32 no-copy observations, 36 snapshot groups/108 post-GC observations. Public
leases have zero native owners before forced GC. Four resolved contents are
recovered only from hash-identical current component files; native production
library comes from that component and the unchanged driver from retained primary
ad8 setup, each matching exact proof hashes. SDK/TLS/crypto internals stay
unmeasured. Archive SHA is
`8b4142a8416f29b2f3d431e7a2c55b5376f200b79549622e0dd5deab57e1faef`.

The [strict diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/39893895253)
has 90 valid rows/zero integrity findings and exact comparison recomputation, but
seven numerical costs remain. CPU/allocation pass all three cases. Dart-value
RSS ratio is 1.02049, native-buffer RSS 1.01069 and pre-encoded RSS 1.00670.
Dart-value GC confidence and throughput, plus pre-encoded p95/p99 also fail.
These are retained costs under the original policy, not complete acceptance.
Archive SHA is `cf60aa9dfce0e351dbfdcffa36b218715b907187f8d205a37ca1cc9091c6c225`;
raw SHA is `484559ececc429ba724401347269fcf0f574183df7937a91f6453e535eb830f9`.

Current CI and complete final-runtime primary/supplemental gates remain pending.
