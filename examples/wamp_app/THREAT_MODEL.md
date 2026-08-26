# WampApp Threat Model

## Scope And Claim

WampApp is a production-oriented example and beta-test application, not a
security-audited messenger. This threat model covers the checked-in client,
standalone server, router configuration, local vault, encrypted messaging and
attachments, local contact aliases, backup, push, calling, and MCP integration.
Platform signing, notarization, store review, operator credentials, TLS
termination, monitoring, and incident response belong to the deployment that
packages the example.

The design treats the router and application server as trusted for account
authentication, authorization, availability, and device-directory delivery,
but not for message, attachment, backup, or call-signaling plaintext. It
protects content from passive network observers, storage disclosure, and an
honest-but-curious service. It does not yet provide key transparency, a double
ratchet, or a defense against an active server that substitutes an unverified
participant device key.

## Assets And Trust Boundaries

| Asset | Intended location | Server visibility |
| --- | --- | --- |
| Account password | Client and registration/authentication memory only | Visible transiently during registration; never persisted |
| SCRAM verifier | Account store | `stored_key`, `server_key`, salt, and KDF parameters |
| Device signing/exchange private keys | Argon2id13-encrypted client vault | Never sent |
| Message and group plaintext | Client vault and active client memory | Never sent |
| Attachment plaintext and keys | Client cache/output and encrypted message | Never sent |
| Backup plaintext/recovery passphrase | Client memory | Never sent |
| WebRTC offer/answer/candidates | Intended devices after decryption | Ciphertext plus routing metadata |
| Push provider token | Client, server push store, and provider | Visible to server/provider; no chat content |
| MCP bearer grant | Client and router auth state | Visible to router; bounded and revocable |
| Local contact alias | Argon2id13-encrypted client vault | Username is verified; imported display name is never sent |

The server necessarily observes account/device identifiers, active device
records, conversation participants, message and attachment sizes, mailbox
cursors, timing, delivery/read state, call participants/state, IP addresses,
and push delivery timing. WampApp does not claim traffic-analysis resistance.

## Adversaries

- A passive network observer must not read credentials or application content
  on a production deployment. Remote deployments therefore require `wss://`
  and HTTPS; cleartext is restricted to loopback development.
- A database, attachment directory, backup directory, or log reader must not
  recover chat, media, backup, or call-signaling plaintext.
- An authenticated account must not read another account's mailbox,
  attachments, backup, push registration, call state, or MCP consent.
- A revoked device must not create new authorized state. Previously delivered
  ciphertext and plaintext already copied by that device cannot be recalled.
- Malformed, replayed, concurrent, or oversized inputs must fail closed without
  crossing account boundaries or creating inconsistent durable state.
- A compromised client process, browser origin, operating system, password, or
  unlocked device is outside the confidentiality boundary and can access
  plaintext available to that endpoint.

## Implemented Controls

### Identity And Authentication

- Remote registration requires transport security. The server derives
  Argon2id13 SCRAM verifier material and stores no plaintext password.
- WAMP-SCRAM verifies the server signature before authentication succeeds.
  Expensive derivation runs in a native isolate or a dedicated web worker.
- Device enrollment and revocation are caller-bound. Ed25519 signing and
  X25519 exchange keys are generated per device and private keys remain in the
  encrypted vault.
- Safety numbers support out-of-band identity verification. There is no public
  account discovery or key-transparency service. Contact import is opt-in and
  local: Android/iOS use the permissionless system picker without requesting
  properties, while other platforms use an explicit vCard. The parser decodes
  only `FN`/`N`, native IDs are discarded, selected bytes are wiped, and the
  user binds the display name to a WampApp username that is verified through
  the authenticated session before the bounded alias enters the vault.

### Stored And Transported Content

- Every direct or immutable-group message uses a random 256-bit content key,
  XSalsa20-Poly1305 authenticated encryption, and a signed sealed key wrap for
  every active participant device. Envelope metadata is validated against the
  decrypted payload.
- New attachment chunks use AES-256-GCM with versioned associated data and
  per-chunk derived keys. Legacy XSalsa20-Poly1305 chunks remain readable.
  Ciphertext and plaintext SHA-256 checks detect storage or transfer corruption.
- Local identity, contact aliases, preferences, mailbox state, and plaintext
  history are held in an Argon2id13-derived SecretBox vault bound to account
  and endpoint.
- Local and remote backup archives are encrypted client-side with a separate
  recovery passphrase. The server stores opaque revisioned bytes.
- WebRTC media uses DTLS-SRTP. Offers, answers, ICE candidates, and hangups are
  independently sealed and signed per selected recipient device before WAMP
  persistence.

### Authorization, Replay, And Concurrency

- Application procedures derive account identity from the authenticated WAMP
  session rather than caller-supplied identity fields.
- Mailbox IDs, cursors, send retries, attachment chunks, receipts, call signals,
  and backup commits are idempotent or compare-and-swap guarded where required.
- One-time consumption is an atomic recipient-device operation with a signed
  proof. Competing opens have one durable winner.
- Attachment and backup sizes, chunk counts, staging lifetime, account storage,
  request rates, concurrent operations, and tracked-account state are bounded.
- Push payloads carry a cursor and optional generic presentation text only. They
  exclude sender, conversation, message, attachment, and key metadata.
- MCP exposes an exact consent-gated profile allowlist. Chats, attachments,
  backups, devices, calls, keys, and avatars are outside the MCP surface.

## Security Invariants

1. A server-side durable store must not contain a test message, attachment
   name, attachment key, backup plaintext, call SDP/candidate, password, or
   device private key.
2. A WAMP procedure may authorize only from disclosed session identity; spoofed
   payload identity cannot expand access.
3. A message or chunk must authenticate all metadata needed to place or decode
   it, and any conflict must reject rather than overwrite.
4. Cancellation, timeout, worker failure, reconnect, disposal, and stale async
   completion must not publish plaintext or mutate a replacement session.
5. Revocation blocks future enrollment-bound operations and prunes push state,
   while never claiming retroactive deletion from a formerly authorized device.
6. Missing credentials, partial provider configuration, malformed policy, or
   missing benchmark evidence fails closed.
7. Contact import must not upload or retain phone numbers, email addresses,
   postal addresses, native contact IDs, or the selected address-book file.

These invariants are covered by focused unit tests, real native-router consumer
smokes, six-device conflict stress, real Chrome worker tests, cross-platform
artifact builds, and the production benchmark gate.

## Residual Risks And Non-Goals

- Device keys are not backed by a hardware keystore, Secure Enclave, or WebAuthn.
  Encryption at rest does not protect an unlocked or compromised endpoint.
- Static per-device exchange keys and independent per-message keys do not offer
  double-ratchet forward secrecy or post-compromise security. A stolen device
  private key can open retained wraps addressed to that device.
- Without key transparency, an active server can attempt device-key
  substitution. Out-of-band safety-number verification is the current
  detection mechanism and must be made mandatory for stronger active-server
  resistance.
- A saved contact alias is convenience metadata, not proof of identity. The
  operating-system picker or file chooser observes the selection, and wiping
  WampApp's selected vCard bytes does not erase the source file outside the
  application. Safety-number verification remains the identity check.
- Expiry and one-time semantics coordinate honest clients and server state;
  recipients can still copy plaintext, take screenshots, or retain decrypted
  bytes. Filesystems, flash storage, swap, browser caches, and cloud providers
  cannot promise cryptographic secure deletion.
- Push providers learn device tokens, timing, and that generic app activity
  occurred. WebRTC peers or TURN infrastructure learn network metadata.
- Rate limits are an application-instance control, not a distributed DDoS
  defense. Production deployments still need edge limits, capacity planning,
  metrics, alerting, backups, and tested disaster recovery.
- FCM delivery behavior has deterministic gateway and client coverage, but a
  credential-backed provider deployment requires operator-owned secrets and
  remains external release evidence.
- The application and its dependencies have not undergone an independent
  cryptographic or penetration-test audit.

## Deployment Checklist

- Terminate only modern TLS and expose remote WAMP/MCP endpoints through
  `wss://`/HTTPS. Do not publish the loopback development configuration.
- Store account, mailbox, attachment, backup, push, and call data on encrypted
  volumes with least-privilege filesystem ownership and protected backups.
- Supply FCM service-account and TURN REST secrets through operator-owned secret
  storage; never add them to YAML, build defines, artifacts, or logs.
- Configure application and edge rate limits, retention, quotas, monitoring,
  alerting, time synchronization, and log redaction for the expected load.
- Sign/notarize client artifacts and protect release credentials outside CI
  jobs that build unsigned beta artifacts.
- Run `bin/verify`, `bin/wamp-app-production-validate`, the cross-platform
  artifact matrix, and credential-backed push staging tests before a final
  release decision.
