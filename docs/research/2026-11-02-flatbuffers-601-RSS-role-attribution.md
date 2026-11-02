# Original601 primary RSS role attribution

This is read-only analysis of the original retained primary campaign. No new
workload, measurement, gate evaluation or runtime change ran. Both strict
campaigns remain failed; this analysis establishes no root cause or repair.

All48cases /336original pairs are retained:43failed RSS cases /301pairs and
5passing RSS control cases /35pairs. The five controls pass the original RSS
metric; this does not mean they pass every other metric. All2,016actual role
records, all three codec sums, each original baseline choice, every paired
ratio and case median verify independently. Nine original input files and
script/declaration/guard hashes rehash unchanged. Sixteen synthetic method
guards ran before original-data output. Source review claims are advisory,
qualified against actual source/control flow; no model approval is inferred.

The frozen source gate in [wamp_serializer_compare.py](../../tool/wamp_serializer_compare.py)
uses client plus server `peak_rss_during_bytes`. It uses the lower CBOR or
MessagePack sum for each repetition, with CBOR winning a tie. Current, before
and lifetime maxima are different fields; the driver is not a third role.

For each original pair, the analysis preserves both baseline codecs and checks:

- Each codec's two actual role peaks sum exactly to its recorded RSS value.
- FlatBuffers divided by that repetition's actual best baseline equals the
  original paired ratio exactly; no new tolerance or precision waiver is used.
- Signed client plus server differences equal the paired sum difference.

Among the301pairs belonging to failed RSS cases, both role differences are
positive in109pairs, only the client difference is positive in83, only the
server difference is positive in66, and neither is positive in43. The paired
sum is positive in216, negative in84 and zero in1. Every repetition remains;
negative individual gaps are not filtered out or treated as independent gate
passes. No role PIDs overlap in this retained dataset.

The largest original RSS median ratio is `rpc_rawsocket_clear_dart_native_buffer`
at1.0324864226. Its paired-sum difference median is25,432,064bytes; separate
client/server difference medians are24,928,256 /-405,504bytes. These statistics
do not add or reproduce the ratio: medians and ratios do not distribute.
All48case summaries and every pair remain in the complete files below.

Role peaks may occur at different times. Their gate sum is not simultaneous
physical memory, and RSS is not retained live heap or leak proof. Contributions
vary across cases/repetitions, so the table does not identify one process,
allocator, host, copy or production defect as the cause. Absolute costs are
scoped to this original EPYC9V45/Dart3.13.5 primary campaign. Next source
inspection will start with the actual Dart native-buffer client path of the
largest observed gap, while retaining both roles and all controls. No production
patch or new capture is ready.

[Complete336pairs](2026-11-02-flatbuffers-601-RSS-role-attribution-rows.jsonl),
[all48case summaries and original hashes](2026-11-02-flatbuffers-601-RSS-role-attribution-summary.json),
[independent read-back audit](2026-11-02-flatbuffers-601-RSS-role-attribution-audit.json).
The source-input audit digest in this summary refers to the retained original
primary audit; its public projection records that original digest in
[the complete primary audit](2026-11-02-mqtt-complete-pair-primary-audit.json).
No original evidence or failed acceptance result changed.
