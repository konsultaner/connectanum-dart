# MQTT hot-path diagnostics on macOS — 2026-10-15

These are exploratory Apple M3 Ultra measurements against Mosquitto 2.1.2. They do not replace the hosted Linux release gate. All 50 broker/client raw rows delivered exact bytes and counts with zero duplicates. The complete summaries, provenance and raw rows are in [the diagnostic record](mqtt-local-hot-path-diagnostics-2026-10-15.json). Every five-pair profile sent 200,000 MQTT 5 QoS 0 messages per broker.

| Experiment | Native delivered/s | Mosquitto delivered/s | Ratio | Result |
| --- | ---: | ---: | ---: | --- |
| WS baseline | 135,990 | 152,388 | 0.8924 | Control |
| WS exact-filter equality fast path | 135,337 | 150,811 | 0.8974 | No absolute gain; reverted |
| TCP baseline | 416,663 | 429,657 | 0.9698 | Control |
| TCP exact-filter equality fast path | 415,420 | 426,838 | 0.9733 | No absolute gain; reverted |
| WS writer merge of already queued chunks, bounded at 64 KiB | 133,938 | 153,342 | 0.8735 | Regressed; reverted |

The fast path avoided splitting equal topic/filter strings. The writer candidate merged only MQTT chunks already waiting in the native outbound queue, without a timer. Both kept exact delivery and passed the unchanged local numeric budgets, but neither produced a meaningful improvement over the controls. They are absent from the branch. The writer comparison uses the same normal-release feature set as the baseline; an earlier `ffi-test` candidate run was excluded because its build profile differed. The normal release library was rebuilt from the reverted source afterward.

The hosted Linux result remains the release decision. Do not adjust the 0.75 TCP or 0.70 WS throughput floors based on these local experiments.
