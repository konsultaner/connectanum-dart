# WampApp

WampApp is a Flutter messaging application used to prove that a consumer can
build on the public Connectanum packages without depending on this repository's
private layout. It is intentionally developed in vertical slices: only
behaviour backed by a real router, storage, and tests appears as functional UI.

## Current Slice

The first slice provides:

- a standalone Connectanum router and YAML configuration;
- anonymous account registration over a narrowly authorized WAMP procedure;
- asynchronous Argon2id13 verifier derivation and WAMP-SCRAM login;
- a file-backed account store containing only SCRAM verifier material;
- a responsive Flutter onboarding flow and authenticated application shell;
- hosted `3.0.0-beta.2` dependencies for both client and server; and
- an end-to-end test covering registration, reconnect, server-signature
  verification, authenticated role metadata, and password non-persistence.

Encrypted conversations, offline sync, groups, media, backups, notifications,
WebRTC calling, and MCP application tools are planned but are not represented
by fake data in the current UI.

## Run Locally

Requirements: Flutter 3.47.1 or newer, Dart 3.13.1 or newer, and a Rust
toolchain. The hosted Connectanum build hooks compile or install the native
runtime during package builds.

Start the server:

```bash
cd examples/wamp_app/server
dart pub get
dart run wamp_app_server --config wamp_app_server.yaml
```

The default configuration listens at `ws://127.0.0.1:8080/ws` and stores
account verifiers in `server/data/accounts.json`.

In another terminal, start the Flutter client:

```bash
cd examples/wamp_app/client
flutter pub get
flutter run -d chrome
```

Keep the default local endpoint, create a username with at least three valid
characters, and use a password with at least twelve characters. Cleartext
`ws://` credentials are accepted only for loopback development. Remote
deployments must expose the endpoint through `wss://`; the included server
configuration is not yet a production TLS deployment recipe.

## Verify

```bash
cd examples/wamp_app/shared && dart analyze && dart test
cd examples/wamp_app/server && dart analyze && dart test
cd examples/wamp_app/client && flutter analyze && flutter test
```

The three packages are standalone on purpose. The Flutter SDK is not added to
the root Dart workspace or its package release graph.
