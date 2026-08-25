# WampApp

WampApp is a Flutter messaging application used to prove that a consumer can
build on the public Connectanum packages without depending on this repository's
private layout. It is intentionally developed in vertical slices: only
behaviour backed by a real router, storage, and tests appears as functional UI.

## Current Slice

The implemented slices provide:

- a standalone Connectanum router and YAML configuration;
- anonymous account registration over a narrowly authorized WAMP procedure;
- asynchronous Argon2id13 verifier derivation and WAMP-SCRAM login;
- a file-backed account store containing only SCRAM verifier material;
- encrypted, account-and-endpoint-bound local device identity storage;
- signed Ed25519/X25519 device enrollment, revocation, and safety numbers;
- direct-message keys wrapped independently for every active participant
  device;
- XSalsa20-Poly1305 message payloads carried as WAMP CBOR binary fields;
- a permission-restricted opaque mailbox with idempotent message IDs,
  monotonic reconnect cursors, expiry filtering, and durable delivery receipts;
- encrypted local message history and cursor persistence across reconnects;
- direct and immutable group conversations with read, expiry, one-time, and
  bounded durable retry/conflict recovery;
- encrypted file, image, and GIF attachments carried as bounded binary WAMP
  chunks on the existing authenticated session;
- upload-before-message publication, idempotent chunk retry, server-reported
  resume state, recipient-authorized download, and full ciphertext/plaintext
  integrity verification;
- encrypted-chunk caches backed by native files or browser IndexedDB, while
  names, MIME types, plaintext hashes, and attachment keys remain inside the
  encrypted message and device vault;
- a responsive Flutter onboarding, composer, history, sync, attachment picker,
  preview, and platform save flow;
- five-minute encrypted voice notes recorded as mono 16 kHz PCM16 WAV, with
  private duration metadata, bounded memory, explicit cancellation, and
  authenticated playback on the existing WAMP attachment path;
- in-memory playback on Android, Windows, and web, plus managed temporary
  playback files that are overwritten and deleted on iOS, macOS, and Linux;
- an optional server-side Firebase Cloud Messaging HTTP v1 gateway that sends
  only a data cursor, validates configured providers, retires invalid tokens,
  and bounds credentials and response bodies;
- optional FlutterFire FCM token acquisition after authenticated device
  enrollment, serialized token refresh replacement, APNs readiness, web VAPID
  and service-worker support, plus unregister-before-close lifecycle cleanup;
- hosted `3.0.0-beta.2` dependencies for both client and server; and
- end-to-end tests covering registration, device trust, encrypted two-account
  and group delivery, attachment authorization/resume, receipt propagation,
  reconnect deduplication, server-signature verification, and plaintext
  non-persistence.

A sticker/emoji picker, backups, OS background notification presentation,
WebRTC calling, and MCP application tools remain planned and are not represented
by fake data in the current UI.
View-once attachments are rejected until attachment consumption and deletion
can be made atomic.

## Run Locally

Requirements: Flutter 3.47.1 or newer, Dart 3.13.1 or newer, and a Rust
toolchain. The hosted Connectanum build hooks compile or install the native
runtime during package builds.

Linux voice recording also requires PulseAudio utilities and FFmpeg:

```bash
sudo apt install pulseaudio-utils ffmpeg
```

Android, iOS, and macOS microphone declarations are included in the client;
the operating system asks for access only when the microphone button is used.

Start the server:

```bash
cd examples/wamp_app/server
dart pub get
dart run wamp_app_server --config wamp_app_server.yaml
```

The default configuration listens at `ws://127.0.0.1:8080/ws`, stores account
verifiers and public device records in `server/data/accounts.json`, and stores
opaque encrypted mailbox records in `server/data/messages.json`. Encrypted
attachment chunks are stored separately under
`server/data/messages.json.attachments`; the server never receives attachment
names, MIME types, plaintext hashes, or content keys.

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

## Attachment Benchmark

Run the opt-in native benchmark from the repository root:

```bash
bin/benchmark-wamp-app-attachments
```

Defaults are a 4 MiB warmup followed by five 64 MiB iterations for both the
memory cache and the durable native-file cache. Override
`WAMP_APP_BENCH_SIZE_MIB`, `WAMP_APP_BENCH_ITERATIONS`, or
`WAMP_APP_BENCH_CACHES=memory,disk` when collecting a larger matrix. Each
machine-readable result includes MiB/s, Gbit/s, average duration, and p95.

The 2026-08-25 baseline on a 32-logical-core macOS host was:

| Cache | Encrypt Gbit/s | Decrypt Gbit/s | Encrypt p95 | Decrypt p95 |
| --- | ---: | ---: | ---: | ---: |
| Memory | 0.159 | 0.139 | 3.405 s | 3.897 s |
| Durable disk | 0.154 | 0.122 | 3.539 s | 4.534 s |

These application-level figures include chunking, XSalsa20-Poly1305, SHA-256,
cache copies, integrity verification, and disk flushes. They are a baseline,
not a release gate. The small memory-to-disk delta identifies client crypto,
hashing, and copies as the next optimization target; native and Web Worker
acceleration still need production evidence.
