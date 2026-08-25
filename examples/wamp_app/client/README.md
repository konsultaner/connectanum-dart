# WampApp Flutter Client

This package contains the WampApp Flutter client. It currently implements real
server-address onboarding, anonymous registration, asynchronous WAMP-SCRAM
login, secure remote-endpoint enforcement, encrypted device identity storage,
signed device enrollment, direct-message encryption, durable reconnect sync,
delivery receipts, encrypted local history, immutable encrypted group chats,
and resumable end-to-end encrypted attachments. Native clients cache only
ciphertext in application-support storage; web clients use IndexedDB. File
names, MIME types, plaintext hashes, and attachment keys stay inside encrypted
message/vault payloads. Five-minute voice notes use the same authenticated WAMP
session and attachment encryption path, with bounded mono PCM16 recording and
securely managed playback resources on every Flutter target. Optional Firebase
Cloud Messaging token acquisition starts only after authenticated device
enrollment, follows token refreshes, and unregisters before sign-out or session
replacement.

## Configure FCM

FCM is disabled when no Firebase compile-time values are present. Supply the
Firebase identifiers when running or building the client; these identify the
operator's Firebase application and are deliberately not checked in:

```bash
flutter run -d chrome \
  --dart-define=WAMP_APP_FIREBASE_API_KEY=... \
  --dart-define=WAMP_APP_FIREBASE_APP_ID=... \
  --dart-define=WAMP_APP_FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=WAMP_APP_FIREBASE_PROJECT_ID=... \
  --dart-define=WAMP_APP_FIREBASE_AUTH_DOMAIN=... \
  --dart-define=WAMP_APP_FIREBASE_VAPID_KEY=...
```

Web builds must also create `web/firebase-config.js` from
`web/firebase-config.js.example`. The ignored operator-owned file initializes
the FCM service worker, is copied into `build/web`, and must be served beside
`firebase-messaging-sw.js`. The pinned worker SDK matches the pinned FlutterFire
packages. Android requires API 23 or newer. Apple builds require
the normal Push Notifications capability, an APNs authentication key uploaded
to Firebase, and a physical device; token acquisition waits for APNs readiness
instead of racing it. Provider denial or initialization failure leaves the
authenticated WAMP session connected and reports push as unavailable.

The server sends data-only cursor wakeups, so Firebase cannot bypass encrypted
per-chat mute preferences with provider-rendered message content. Background
OS presentation remains a separate slice; reconnect and durable mailbox cursors
remain the lossless fallback.

See the [parent guide](../README.md) for setup, current limitations, attachment
benchmark instructions, and feature status.
