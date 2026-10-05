# connectanum_bench

`connectanum_bench` contains the Dart-side benchmark harness for the
Connectanum router.

It is used together with the Rust orchestrator under
[`native/bench`](https://github.com/konsultaner/connectanum-dart/tree/master/native/bench)
to run:

- HTTP/1.1, HTTP/2, and HTTP/3 workloads
- RawSocket and WebSocket WAMP workloads
- auth, authz, and transport comparison scenarios
- router metrics capture through the bench control endpoints

This package is an internal workspace tool, not an end-user runtime package.

## Typed FlatBuffers workload fixture

`schemas/bench_payload/workload_payload.fbs` defines an application payload with
worker and iteration identity plus a deterministic binary body. Its checked-in
Dart reader/object builder is generated with the compiler version pinned in
`schemas/wamp_flatbuffers/manifest.json`:

```bash
python3 tool/fetch_flatc.py --output /tmp/connectanum-flatc
python3 tool/generate_bench_flatbuffers.py \
  --flatc /tmp/connectanum-flatc/flatc
python3 tool/generate_bench_flatbuffers.py \
  --flatc /tmp/connectanum-flatc/flatc --check
```

The fixture codec checks exact identity and body contents and can build the same
payload in Dart or directly in native-owned storage. These are correctness and
construction primitives; they do not establish typed-payload performance parity.

Typed RPC and pub/sub workloads can compare the `values`, `native_buffer`, and
`pre_encoded_span` construction groups. For example:

```toml
[[workloads]]
name = "rawsocket_rpc_flatbuffers_native_buffer"
protocol = "wamp_rawsocket_rpc"
client_impl = "dart"
serializer = "cbor" # WAMP envelope serializer
path = "bench.rpc.echo"
iterations = 1000
concurrency = 1
request_bytes = 65536
ppt_scheme = "x_connectanum_bench_typed"
ppt_serializer = "flatbuffers"
payload_construction = "native_buffer"
```

`values` constructs the application value in Dart. `native_buffer` builds a
FlatBuffer in native-owned memory; for CBOR/MessagePack PPT it stores the binary
body in native-owned memory before ordinary PPT serialization. `pre_encoded_span`
serializes the PPT value first, copies those bytes into a frozen native owner, and
submits them through the lazy packed-payload path. The runner retains that owner
through the RPC result or all matching pub/sub deliveries, validates the body and
identity, then disposes it. These paths expose construction choices; they do not
claim zero copies across the whole codec and transport pipeline. They still use
the ordinary WAMP Session send path; the native segmented-send path copies its
submitted fragments into native-owned allocations. A future zero-copy acceptance
needs a typed Session-to-transport ownership path plus allocation or copy-count
evidence.

`latency_ms` includes payload preparation and the complete request/result or
publish/delivery path. `payload_preparation_us` is a separate construction timing;
for `values` and `native_buffer` with dynamic CBOR/MessagePack PPT, the later PPT
serialization is outside that field but remains inside `latency_ms`. The two
`native_builder_*_copied_bytes` counters cover builder input and growth only, not
all codec, transport, security or receive copies. The current 18-case typed-runner
matrix checks RawSocket with the Dart caller and CBOR WAMP envelope across
RPC/pub/sub, all three PPT codecs and construction groups. A separate 12-case
matrix covers typed FlatBuffers PPT across RawSocket/WebSocket, Dart/native callers
and outer serializers, without the runner construction groups. Neither is
performance evidence, and typed runner groups still lack WebSocket, TLS and
native-caller live coverage. See the
[acceptance contract](../../docs/flatbuffers_performance_acceptance.md) before
claiming parity.

## Current Results

The current complete production-gate snapshot covers 78 workloads and passes
every throughput, lifecycle, transport, and zero-copy policy. Each cell reports
**sustained data-window / full-lifecycle throughput** in Gbit/s; lifecycle
throughput includes connection, session, routing, and teardown costs.

### 64 MiB file transfer

| Transport and path | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) |
| --- | ---: | ---: | ---: |
| Native RawSocket | 16.102 / 14.913 | 18.242 / 16.843 | 19.174 / 17.180 |
| Dart RawSocket, buffered | 5.292 / 4.804 | 9.491 / 8.013 | 12.007 / 9.630 |
| Native RawSocket TLS | 13.262 / 12.504 | 18.340 / 16.943 | 17.324 / 15.966 |
| Native WebSocket | 15.663 / 14.437 | 19.407 / 17.748 | 19.057 / 17.180 |
| Dart WebSocket, buffered | 2.351 / 2.239 | 9.430 / 7.697 | 9.370 / 7.483 |
| Native WebSocket TLS | 12.874 / 12.014 | 18.155 / 16.424 | 16.951 / 15.203 |
| Native RawSocket + E2EE | 8.725 / 8.397 | 20.843 / 19.131 | 21.182 / 19.303 |
| Native RawSocket TLS + E2EE | 8.592 / 8.244 | 18.097 / 16.777 | 17.853 / 16.487 |
| Native WebSocket + E2EE | 8.516 / 8.142 | 20.891 / 18.921 | 19.218 / 17.424 |
| Native WebSocket TLS + E2EE | 8.329 / 7.932 | 17.339 / 15.704 | 15.701 / 14.413 |

The file scenario uses 64 MiB files and 4 MiB binary chunks. Clear RawSocket
MessagePack and CBOR can preserve file identity through kernel `sendfile`;
JSON, TLS, WebSocket masking, and E2EE use bounded copy-minimized transforms.

### Large RPC frames

| Transport and path | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) |
| --- | ---: | ---: | ---: |
| Native RawSocket | 13.612 / 4.965 | 21.246 / 6.638 | 19.525 / 4.914 |
| Native WebSocket | 6.816 / 5.949 | 9.132 / 7.809 | 6.644 / 5.674 |
| Native RawSocket TLS | 8.820 / 4.146 | 11.417 / 5.150 | 10.798 / 4.067 |
| Native WebSocket TLS | 5.578 / 4.965 | 6.613 / 5.828 | 5.276 / 4.628 |
| Dart RawSocket | 2.411 / 1.851 | 19.749 / 6.547 | 18.651 / 4.810 |
| Dart WebSocket | 2.616 / 2.475 | 7.886 / 6.883 | 7.306 / 6.216 |
| Dart RawSocket TLS reference[^dart-tls] | 0.741 / 0.678 | 0.989 / 0.896 | 0.987 / 0.858 |
| Dart WebSocket TLS reference[^dart-tls] | 0.717 / 0.706 | 0.934 / 0.917 | 0.929 / 0.906 |

RawSocket frames are 64 MiB and WebSocket frames are 8 MiB. Native TLS and
WebSocket TLS are the production secure paths.

### WebSocket fragmentation and Pub/Sub

| Transport and workload | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) |
| --- | ---: | ---: | ---: |
| WebSocket RPC, contiguous | 18.156 / 14.364 | 26.577 / 19.089 | 12.631 / 10.154 |
| WebSocket RPC, 4 KiB fragments | 8.761 / 7.683 | 11.047 / 9.460 | 7.444 / 6.557 |
| WebSocket Pub/Sub, contiguous | 6.962 / 6.032 | 11.818 / 9.673 | 4.229 / 3.825 |
| WebSocket Pub/Sub, 4 KiB fragments | 6.706 / 5.884 | 7.232 / 6.363 | 4.515 / 4.090 |
| WebSocket TLS RPC, contiguous | 9.469 / 8.212 | 12.251 / 10.399 | 7.977 / 6.961 |
| WebSocket TLS RPC, 4 KiB fragments | 8.134 / 7.206 | 8.981 / 7.954 | 6.969 / 6.180 |
| WebSocket TLS Pub/Sub, contiguous | 3.472 / 3.208 | 4.715 / 4.265 | 2.725 / 2.540 |
| WebSocket TLS Pub/Sub, 4 KiB fragments | 3.635 / 3.363 | 4.620 / 4.215 | 2.517 / 2.355 |

Fragmentation workloads use 4 MiB payloads, 4 KiB continuation frames, and
four concurrent in-flight messages. The snapshot is the local completion
artifact from 2026-08-24; the latest
[hosted profile run](https://github.com/konsultaner/connectanum-dart/actions/runs/29580331118)
passes its progressive invocation, call-timeout, Meta API, transport-counter,
and performance policies. Results describe the measured configuration, not a
cross-project comparison or a substitute for workload-specific load testing.

See the
[benchmark contract](https://github.com/konsultaner/connectanum-dart/blob/master/docs/wamp_profile_benchmarks.md)
for reproduction commands, budgets, and limitations, and the checked-in
scenarios for
[file transfer](https://github.com/konsultaner/connectanum-dart/blob/master/native/bench/scenarios/wamp_file_transfer_throughput.toml),
[large frames](https://github.com/konsultaner/connectanum-dart/blob/master/native/bench/scenarios/wamp_large_transport_frames_heavy.toml),
and
[WebSocket fragmentation](https://github.com/konsultaner/connectanum-dart/blob/master/native/bench/scenarios/wamp_websocket_fragmentation_throughput.toml).

[^dart-tls]: Pure-Dart TLS is constrained by the Dart SDK's asynchronous 8/10 KiB TLS staging and is retained as an explicit reference, not a production-gated secure path.

## Main Entry Point

The Dart bench runner is exposed as a package executable:

```bash
dart run connectanum_bench:bench_router_service
```

In practice it is usually started by the Rust orchestrator and scenario files
under `native/bench/scenarios/`. The package also exposes the helper worker as
`connectanum_bench:wamp_client_worker` so a consumer package can run the same
WAMP worker path without relying on repo-local `tool/` paths.

Secure WAMP scenarios are selected explicitly with `secure_transport = true`
in the workload definition; the Dart bench runner keeps separate cleartext and
TLS listener targets so secure workloads do not silently fall back to the
cleartext WAMP listener.

When the shipped bench router config includes `oauth` HTTP auth providers, the
Dart runner also starts a local introspection endpoint for them. That keeps the
HTTP bearer-provider scenarios self-contained instead of depending on an
external OAuth service during local or CI bench runs.

The shipped HTTP auth bridge smoke scenario now also covers challenge-response
login for `ticket`, `wampcra`, and `scram`, so the Rust orchestrator exercises
both multi-step HTTP auth bridge flows and the separate bearer-provider route
path from the same checked-in bench config.

## Related Docs

- [Native orchestrator overview](https://github.com/konsultaner/connectanum-dart/tree/master/native/bench)
- [Connectanum repository overview](https://github.com/konsultaner/connectanum-dart)
