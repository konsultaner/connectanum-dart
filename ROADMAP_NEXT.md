# Next Session Overview

Fresh state:
- PUB/SUB routing runs end-to-end (filters + ACK logic) and now has regression coverage for zero-copy failure paths (handles released when native forwarding fails).
- RPC flow supports full invocation lifecycle, including `CANCEL` modes and zero-copy RESULT/ERROR forwarding with buffer-release tests.
- Router boss→worker drain pipeline is validated: stop() sends server-initiated GOODBYE frames, drains sessions, and workers signal completion.
- Analyzer still reports info-level issues isolated to `packages/connectanum_auth_server`; production packages are clean.
- JSON/MessagePack/CBOR serializers now preserve custom option/detail fields, keeping throttle/debounce metadata available across the stack.

Focus for the next session:
1. **Native Transport Multi-Protocol Refactor**
   - Build the shared streaming primitives first: `HttpBodyHandle` upgrades (slice/retain/release) plus matching `ct_ffi` APIs so Dart can read/write without copying.
   - Rework HTTP/1.1 ingress to consume those handles (no eager buffers), add chunked response writers, and wire early-response helpers (405/426/413) directly in Rust.
   - Stand up the HTTP/2 server (tokio + `h2`) with multi-stream routing, request queue integration, and response handles that respect flow control/backpressure.
   - Port HTTP/3 request/response handling onto the same primitives so QUIC uploads/downloads stay zero-copy and stream IDs are surfaced for diagnostics.
   - Implement WebSocket upgrade plumbing: accept/deny from Dart, negotiate serializers, forward frames with continuation + mask handling, and downgrade to RawSocket when possible.
   - Once the native pieces exist, extend `ct_ffi`/Dart (`NativeHttpRequestBody`, `HttpInvocationContext`, `HttpResponseUtil`) to default to streaming semantics and expose structured response sinks/file handles.
   - Add multi-megabyte regression suites (Rust `listen_flow`, Dart router_runtime/integration) that cover HTTP/1.1, HTTP/2, HTTP/3, and WebSocket flows, including pointer checks and temp-file cleanup.
2. **Pattern Routing & Shared Registrations**
   - Implement wildcard/prefix ordering + priority handling and un-skip the advanced-profile placeholder test.
   - Introduce shared registration policies (round-robin/first/last) and wire invocation dispatch to respect them.
3. **Authrole Filters & Analyzer Hygiene**
   - Enforce authrole include/exclude lists when broadcasting EVENTs and extend tests accordingly.
   - Resolve remaining analyzer warnings by fixing `packages/connectanum_auth_server` dependencies/imports or documenting follow-up tasks.
4. **HTTP Routing & Auth Pipeline**
   - Design the HTTP route translation table (path/method/protocol → realm/procedure) plus the reserved realm/namespace shortcuts.
   - Implement the reserved auth/refresh route (default `/auth`) with configurable overrides and build the CRA/SCRAM-to-token bridge.
   - Enforce endpoint-level auth defaults for HTTP, including realm selection via header/query parameter and short-lived access tokens.
   - Deliver HTTP response utilities (status/headers/body helpers) and metrics endpoint plumbing atop the new FFI path; include `HttpResponseUtil`/`HttpRequestContext` helpers for router sessions so handlers can choose between inline bodies and zero-copy file/stream adapters.
   - Capture adapter extensibility in the plan (static assets, PHP-FPM/FastCGI, reverse proxies) so the translation table can bind routes to pluggable responders once the zero-copy primitives land.

5. **Benchmark Readiness**
   - Draft the benchmarking plan (release build workflow, load generator scaffold, metrics hooks, automation scripts) and land the initial harness pieces.
6. **Documentation & Examples**
   - Update router/auth docs to capture cancellation semantics, drain behaviour, and zero-copy guarantees.
   - Expand the example gallery (progressive results + cancellation walkthrough) to help integrators.
7. **Serializer Interop Bridge**
   - Add translation pipelines so mixed clients (JSON ↔ MessagePack ↔ CBOR) can exchange EVENT/RESULT/ERROR frames seamlessly, with fallbacks that keep zero-copy semantics where possible.
   - Extend serializer/router tests to cover cross-encoding publish/call scenarios.
8. **E2EE Research Spike**
   - Outline options for end-to-end payload encryption without incurring Dart 64-bit object overhead (e.g. offloading to Rust FFI or dedicated binary isolates).
   - Identify handshake/key-management changes required in HELLO/CHALLENGE and how they interact with zero-copy routing.

Regression / validation to run after changes:
- `dart test packages/connectanum_router/test/router_worker_session_test.dart --chain-stack-traces`
- `dart test packages/connectanum_router/test/router_worker_auth_test.dart`
- `dart test packages/connectanum_router`
- `dart test packages/connectanum_core/test/serializer/json/serializer_test.dart`
- `dart analyze`
