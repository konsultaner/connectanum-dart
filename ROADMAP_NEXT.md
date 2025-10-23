# Next Session Overview

We now have:
- RouterSettings loader/builder wired through to the worker isolates (Crossbar-style configs parsed once, serialized for isolate init).
- RouterStateStore integrated with session allocation; workers open sessions via commands when anonymous HELLO completes.
- Outbound FFI bridge (`ct_send_message`) in place so Dart can emit CHALLENGE/WELCOME/EVENT frames.
- Anonymous/no-auth handshake path implemented (HELLO → WELCOME, state store update, outbound send).

Focus for the next session:
1. Complete the authentication workflow:
   - Wire authenticator registry lookups in the worker (ticket, CRA, SCRAM, cryptosign stubs).
   - Support challenge/response (`CHALLENGE`/`AUTHENTICATE`) including success/abort paths.
   - Persist auth metadata in `SessionRecord` and ensure ABORT is emitted on failures.
2. Harden the session lifecycle:
   - Handle GOODBYE reception/cleanup and heartbeat/timeout scaffolding.
   - Add tests covering multiple sequential messages over the same socket (reuse the StreamQueue helpers).
3. Start subscription/registration plumbing:
   - Use RealmContext/StateStore to track SUBSCRIBE/REGISTER commands.
   - Sketch outbound EVENT/RESULT dispatching once auth succeeds.
4. Document the runtime build and describe new configuration fields (router settings, outbound bridge) for contributors.
5. Code clean up. put the authentication unit tests in the right place.

Regression suite to run after changes:
`dart test packages/connectanum_core`
`dart test packages/connectanum_client/test/authentication`
`dart test packages/connectanum_router`
