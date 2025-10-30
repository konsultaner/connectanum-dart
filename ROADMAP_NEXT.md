# Next Session Overview

Fresh state:
- PUB/SUB routing runs end-to-end (filters + ACK logic) and now has regression coverage for zero-copy failure paths (handles released when native forwarding fails).
- RPC flow supports full invocation lifecycle, including `CANCEL` modes and zero-copy RESULT/ERROR forwarding with buffer-release tests.
- Router boss→worker drain pipeline is validated: stop() sends server-initiated GOODBYE frames, drains sessions, and workers signal completion.
- Analyzer still reports info-level issues isolated to `packages/connectanum_auth_server`; production packages are clean.
- JSON/MessagePack/CBOR serializers now preserve custom option/detail fields, keeping throttle/debounce metadata available across the stack.

Focus for the next session:
1. **Pattern Routing & Shared Registrations**
   - Implement wildcard/prefix ordering + priority handling and un-skip the advanced-profile placeholder test.
   - Introduce shared registration policies (round-robin/first/last) and wire invocation dispatch to respect them.
2. **Authrole Filters & Analyzer Hygiene**
   - Enforce authrole include/exclude lists when broadcasting EVENTs and extend tests accordingly.
   - Resolve remaining analyzer warnings by fixing `packages/connectanum_auth_server` dependencies/imports or documenting follow-up tasks.
3. **Benchmark Readiness**
   - Draft the benchmarking plan (release build workflow, load generator scaffold, metrics hooks, automation scripts) and land the initial harness pieces.
4. **Documentation & Examples**
   - Update router/auth docs to capture cancellation semantics, drain behaviour, and zero-copy guarantees.
   - Expand the example gallery (progressive results + cancellation walkthrough) to help integrators.
5. **Serializer Interop Bridge**
   - Add translation pipelines so mixed clients (JSON ↔ MessagePack ↔ CBOR) can exchange EVENT/RESULT/ERROR frames seamlessly, with fallbacks that keep zero-copy semantics where possible.
   - Extend serializer/router tests to cover cross-encoding publish/call scenarios.
6. **E2EE Research Spike**
   - Outline options for end-to-end payload encryption without incurring Dart 64-bit object overhead (e.g. offloading to Rust FFI or dedicated binary isolates).
   - Identify handshake/key-management changes required in HELLO/CHALLENGE and how they interact with zero-copy routing.

Regression / validation to run after changes:
- `dart test packages/connectanum_router/test/router_worker_session_test.dart --chain-stack-traces`
- `dart test packages/connectanum_router/test/router_worker_auth_test.dart`
- `dart test packages/connectanum_router`
- `dart test packages/connectanum_core/test/serializer/json/serializer_test.dart`
- `dart analyze`
