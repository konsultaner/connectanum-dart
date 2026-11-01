# Native MQTT FFI census

This isolated count-only diagnostic investigates the retained `11521160` MQTT
failures. It changes no Rust/Dart runtime, broker/client source, acceptance gate,
body verification, window, sample count, worker, SDK, GC or allocator policy.
It is neither a runtime candidate nor a performance acceptance rerun.

The original hosted job on EPYC 7763 fails native TCP 3.1.1 throughput/CPU and
two cleartext WebSocket throughput gates. Its complete native-source control
does not establish a benefit from TCP_NODELAY. CPU samples show pipe wakeup and
scheduling costs, but they do not prove the cause. Both the Linux WebSocket
reader and native MQTT polling layer already coalesce input; an actual census
must precede another optimization.

## Predeclared experiment

Use the exact retained native `10c9aaa7…`, AOT broker and client from original
run `41351945654`, not a rebuild. Verify the original source/attempt, all actual
byte hashes, matched source archive and Cargo.lock, profile provenance receipt,
and the recorded AOT SDK version. The native remains byte-for-byte unchanged.
Separate shared-CI, local canonical or predecessor libraries do not substitute.

Link a diagnostic shared library against that exact native dependency. Its
three wrappers count `ct_poll_mqtt_chunk`, `ct_send_mqtt_chunk` and
`ct_arm_message_ready_callback_v1`; every call forwards the original arguments,
pointer, return and errno. The wrappers never read or retain payload bytes.
Fixed relaxed-atomic counters/histograms have no per-message allocation or I/O.
Other FFI symbols resolve from the native dependency. Emit one new JSON file
after the existing graceful stdin shutdown, preserving partial data on failure.

Run all five original cleartext profiles with five repetitions each: WS 5,
WS 3.1.1, TCP 5, TCP 3.1.1 and large TCP. Preserve all 25 rows / 4,025,000 fresh
fully verified deliveries, budgets, stdout, counters, process exits and actual
inputs. Use original warmup 100 and unchanged messages/windows/payloads.
No Mosquitto acceptance comparison or passing performance classification runs.
Counter overhead is uncalibrated: recorded timings cannot establish a repair.
Counts cover each entire fresh broker lifetime, including handshake, warmup and
cleanup; they are not interior-window RAM/allocation measurements.

The existing manual `mqtt-profile.yml` workflow has an explicit separate
`ffi_census` mode. Other diagnostic modes remain separate. This mode does not
cancel an active run and records all original artifact metadata. It fails
before capture for additional original-source CI correctness failures. The
original numerical job and its dependent remain failed and untouched.

## Executable controls

Before any hosted data, seven local controls pass with actual compiled C
libraries. They verify pointer/argument/return/errno forwarding, output-buffer
bounds, signed error and zero results, callback-arm delegation, exact counter
conservation, dependency symbol resolution for an unwrapped API, missing-symbol
and missing-output failures, retained-output protection, source/attempt rejection,
duplicate/window/warmup rejection, and graceful process shutdown/reaping.
The hosted Linux job repeats these controls before loading retained bytes.

The mock native deliberately returns every requested result, including invalid
arguments. This proves that the shim preserves native behavior rather than
inventing validation. An unwrapped symbol resolves to the dependency while the
three counting entry points intentionally resolve to the shim.

This tool does not measure the two SDK-limited MessagePack allocation metrics
or answer the separate allocation-precision product question. Any actual
runtime fix still needs its own focused tests, canonical verification,
copy/lifetime proof, clean CI and complete strict 48-/50-case acceptance.
