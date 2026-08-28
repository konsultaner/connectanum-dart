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
- direct and immutable group conversations with read, one-time, and bounded
  durable retry/conflict recovery;
- persistent per-chat disappearing-message policies for new encrypted
  envelopes, with proactive local-history and encrypted-vault pruning;
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
  a data cursor plus, only for unmuted incoming messages, generic notification
  text with no sender, conversation, message, attachment, or key metadata;
- optional FlutterFire FCM token acquisition after authenticated device
  enrollment, serialized token refresh replacement, APNs readiness, web VAPID
  and service-worker support, per-device mute-policy refresh, background OS
  presentation, plus unregister-before-close lifecycle cleanup;
- encrypted local export/import and revisioned remote backup transfer through
  the authenticated WAMP session;
- opt-in local contacts that use the permissionless Android/iOS system picker
  or an explicit desktop/web vCard, retain only a display-name-to-WampApp-
  username alias in the encrypted vault, and verify that username through the
  authenticated server before saving;
- direct voice and video calls with WebRTC DTLS-SRTP media and encrypted,
  durable, device-selected WAMP signaling;
- consent-gated Streamable HTTP and direct JSON MCP profile access with an
  exact allowlist and no chat, key, backup, or attachment disclosure;
- bounded anonymous registration, control-operation, and binary-transfer abuse
  guards, plus six-device live conflict stress;
- hosted `3.0.0-beta.2` dependencies for both client and server; and
- end-to-end tests covering registration, device trust, encrypted two-account
  and group delivery, attachment authorization/resume, receipt propagation,
  reconnect deduplication, server-signature verification, and plaintext
  non-persistence.

Contact import deliberately provides no account discovery: the user selects a
single native contact or vCard display name and explicitly enters the matching
WampApp username. Phone numbers, email addresses, postal addresses, native
contact IDs, and address-book files are never uploaded or retained by WampApp.
Credential-backed FCM deployment evidence requires operator-owned secrets and
remains before a final release. The reviewed security boundaries and residual
risks are explicit in [THREAT_MODEL.md](THREAT_MODEL.md).
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
Android and iOS contact selection uses the permissionless system contact
picker without requesting contact properties. macOS, Linux, Windows, and web
use an explicit `.vcf`/`.vcard` file picker; selected bytes are wiped from
WampApp memory after only `FN`/`N` display names have been extracted.

On macOS, the supported two-device lab starts an isolated loopback router,
boots an Android emulator when needed, reuses or boots an iOS simulator,
installs the client on both, and keeps the router attached to the terminal:

```bash
bin/run-wamp-app-lab
```

Use `bin/run-wamp-app-lab --dry-run` to inspect device selection and commands
without changing the machine. Lab account, mailbox, attachment, backup, call,
push, and MCP-consent state persists under `.dart_tool/wamp_app_lab`; it never
uses the example server's normal `data` directory. Android reaches the same
`localhost` endpoint through a temporary `adb reverse`, which is removed with
the router when Ctrl+C is pressed. Router output and auto-boot diagnostics are
retained in that state directory. The emulators and installed apps remain open
for UI inspection.

Run the same lab as a deterministic native acceptance test with:

```bash
bin/run-wamp-app-lab --smoke
```

Smoke mode drives the real Android and iOS Flutter UIs concurrently. Each
client registers a unique account through 64 MiB Argon2id SCRAM, waits for the
other device directory, sends one encrypted direct message, receives and
decrypts the peer message through mailbox pub/sub, and renders both bubbles.
The launcher also rejects the run if either plaintext token appears in the
router message store. Run-scoped router state and platform logs remain under
`.dart_tool/wamp_app_smoke` for inspection; the router and Android reverse
tunnel are removed when the run finishes.

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

When another local service owns port `8080`, start the client with the server
address selected at build time:

```bash
flutter run -d <device-id> \
  --dart-define=WAMP_APP_SERVER_ADDRESS=ws://localhost:18080/ws
```

The onboarding field remains editable, so one build can still connect to a
different local or remote endpoint at runtime.

Keep the default local endpoint, create a username with at least three valid
characters, and use a password with at least twelve characters. Cleartext
`ws://` credentials are accepted only for loopback development. Remote
deployments must expose the endpoint through `wss://`; the included server
configuration is not yet a production TLS deployment recipe.

## Build Beta Artifacts

The platform packager creates a clean archive, SHA-256 checksum, and
machine-readable manifest. Every manifest is explicitly marked
`artifact_role: beta-testing` and `store_ready: false`:

```bash
bin/package-wamp-app --target web
bin/package-wamp-app --target android
bin/package-wamp-app --target ios
bin/package-wamp-app --target macos
bin/package-wamp-app --target linux
bin/package-wamp-app --target windows
bin/package-wamp-app --target server
```

Host-specific targets fail before invoking Flutter when run on the wrong host.
Artifacts are written under `out/wamp-app-artifacts/` by default.

| Target | Beta payload | Production boundary |
| --- | --- | --- |
| Web | Release static site | Serve over HTTPS or loopback. |
| Android | Release AAB plus debug-key APK | The APK is for testers; configure an upload keystore for store signing. |
| iOS | Release device app | Unsigned; provision and sign before installation. |
| macOS | Release app | Local build; operator signing and notarization remain required. |
| Linux | Release bundle | Unsigned; install declared audio/runtime libraries. |
| Windows | Release bundle | Unsigned; normal code signing avoids SmartScreen friction. |
| Server | Host-native CLI plus YAML | Review YAML, TLS, secrets, and filesystem permissions before deployment. |

For Android release signing, copy
`client/android/key.properties.example` to the ignored
`client/android/key.properties` and point it at an operator-owned upload
keystore. Missing fields fail during Gradle configuration, and absent signing
configuration produces an unsigned AAB instead of silently using the debug key.
CI intentionally supplies no release signing credentials.

The path-filtered `WampApp Artifacts` GitHub workflow builds and uploads all six
client targets plus a Linux server bundle. Hosted artifacts are retained for 14
days so beta testers can exercise the current exact commit.

## Verify

```bash
cd examples/wamp_app/shared && dart analyze && dart test
cd examples/wamp_app/server && dart analyze && dart test
cd examples/wamp_app/client && flutter analyze && flutter test
```

The three packages are standalone on purpose. The Flutter SDK is not added to
the root Dart workspace or its package release graph.

## Production Benchmarks

Run the release gate from the repository root:

```bash
bin/wamp-app-production-validate
```

It measures full 64 MiB Argon2id13 account onboarding and reconnect, real
two-account encrypted message acceptance and delivery over WebSocket/CBOR, and
five 64 MiB attachment encrypt/decrypt iterations against both memory and
durable native-file caches. The checked-in policy fails closed when a workload
or metric is missing, duplicated, malformed, non-finite, or outside its budget.
Logs, host metadata, raw benchmark records, and `summary.json` are written to
`out/wamp-app-production-benchmarks/`.

The 2026-08-26 local production-gate baseline on a 32-logical-core macOS host
was:

| Workload | Result | Shared-runner gate |
| --- | ---: | ---: |
| Account onboarding p95 | 2.479 s | <= 10 s |
| SCRAM reconnect p95 | 1.358 s | <= 8 s |
| Encrypted delivery p95 | 99 ms | <= 1 s |
| Encrypted direct messages | 11.753 messages/s | >= 2 messages/s |
| 64 MiB memory-cache encrypt/decrypt | 0.115 / 0.117 Gbit/s | >= 0.025 Gbit/s |
| 64 MiB durable-disk encrypt/decrypt | 0.113 / 0.107 Gbit/s | >= 0.025 Gbit/s |

The `WampApp Artifacts` workflow runs the same gates on a pinned Flutter Linux
runner and retains the machine-readable evidence with the beta bundles. These
budgets are intentionally conservative across shared runners; they are
regression/deadlock gates, not hardware-independent throughput promises.

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

The 2026-08-26 five-iteration baseline on a 32-logical-core macOS host was:

| Cache | Encrypt Gbit/s | Decrypt Gbit/s | Encrypt p95 | Decrypt p95 |
| --- | ---: | ---: | ---: | ---: |
| Memory | 0.115 | 0.117 | 4.679 s | 4.597 s |
| Durable disk | 0.113 | 0.107 | 4.780 s | 5.100 s |

These application-level figures include chunking, AES-256-GCM worker execution,
SHA-256, cache copies, integrity verification, and disk flushes. The standalone
command remains useful for exploratory matrices; the production command above
owns the enforced 64 MiB release gate.
