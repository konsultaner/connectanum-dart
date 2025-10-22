# connectanum-dart Monorepo

This repository hosts the next generation of the connectanum WAMP stack. It is
split into a Dart workspace that keeps the client and upcoming router code
side-by-side, and a Rust workspace that will provide the native transport
runtime.

- `packages/connectanum_dart` – Dart package containing the existing WAMP
  client and the new router modules (work in progress).
- `native/transport` – Rust workspace for the native networking runtime
  (currently a skeleton).

## Getting Started

1. Install the Dart SDK locally (or run `./codex.sh`).
2. Fetch dependencies and run tests from the Dart package:

   ```bash
   cd packages/connectanum_dart
   dart pub get
   dart test
   ```

3. Build or test the native workspace (Linux support is implemented first):

   ```bash
   cd native/transport
   cargo test
   cargo build -p ct_ffi --release
   # coverage (requires cargo-llvm-cov)
   cargo llvm-cov
   ```

For additional package level documentation see
`packages/connectanum_dart/README.md`.

## Router Data Flow

The router uses a multi-layered architecture combining the native transport
runtime, a boss/worker isolate model, and a central state store. The following
Mermaid diagram illustrates the main components and message flow in detail:

```mermaid
flowchart TD
    subgraph "Native Runtime (ct_ffi)"
        A[Listener Accept Loop]
        B[RawSocket Frame Parser]
        C[ct_message_get / pointers]
    end

    subgraph "Dart Boss Isolate"
        D[RouterBinding]
        E[_RouterBoss]
        F[RouterStateStore]
        G[RouterSettings / Realm Config]
        H[Authenticator Registry]
    end

    subgraph "Worker Isolates"
        I[_routerWorkerEntryPoint]
        J[RealmContext Cache]
        K[Authenticators]
        L[Message Handlers]
    end

    subgraph "Router Core"
        M[Router Config Builder]
        N[Router.start]
    end

    %% Native -> Boss
    A -->|accepts| B
    B -->|HELLO / CALL / SUBSCRIBE frames| C
    C -->|ct_poll_connection_message| D

    %% Boss flow
    N -->|listener activation| D
    N -->|pass settings| E
    D -->|spawn boss| E
    D -->|start workers| I
    E -->|state cmds| F
    E -->|realm configs| G
    G -->|auth policies| H

    %% Boss -> Workers
    E -->|assign connection| I
    E -->|send statePort| J

    %% Workers handshake/auth
    I -->|materialise message| L
    L -->|HELLO| K
    K -->|onHello| H
    H -->|factory->authenticator| K
    K -->|challenge/result| L
    L -->|AUTHENTICATE| K
    K -->|AuthResult.success| L
    L -->|SessionOpenCommand| F
    F -->|RealmSnapshot| J

    %% Publish/Call flow
    L -->|SUBSCRIBE/CALL| J
    J -->|addSubscription / registerProcedure| F
    F -->|StateChangedEvent| E
    E -->|invalidate| J
    F -->|InvocationDispatch| L
    L -->|RESULT/EVENT| C

    %% Shutdown
    D -->|dispose| E
    E -->|stop| F
    F -->|close| E
```

Key points:

- The native runtime accepts TCP connections, parses WAMP RawSocket frames, and
  exposes them via FFI callbacks.
- `Router.start` builds a router binding, passes in `RouterSettings`, and spawns
  `_RouterBoss` plus worker isolates.
- `_RouterBoss` owns the central `RouterStateStore`, manages connection
  assignment, and holds realm configuration plus the authenticator registry.
- Worker isolates materialize native messages, drive authentication using
  pluggable authenticators, and call into `RealmContext` to interact with the
  store (subscriptions, registrations, snapshots, etc.).
- All state mutations flow through `RouterStateStore`, which enforces realm
  limits, tracks sessions, subscriptions, procedures, and dispatches events back
  to the boss/metrics layer.

## Design Notes

- Advanced-profile call cancellation modes (`kill`, `killnowait`, `killall`) will
  be implemented so that cancellers can wait for the callee to perform any
  required cleanup. This guarantees that subsequent processing shuts down
  gracefully instead of leaving background work dangling.
```
