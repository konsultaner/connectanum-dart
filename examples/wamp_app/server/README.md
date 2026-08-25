# WampApp Server

This standalone Dart package starts a Connectanum router and the registration
and opaque mailbox services used by WampApp. Configuration lives in
`wamp_app_server.yaml`.

The account file stores `salt`, `stored_key`, `server_key`, KDF parameters,
identity metadata, and creation time. It never stores plaintext passwords.
Router worker isolates reconstruct the file-backed credential provider before
authentication, so newly registered accounts are available on reconnect.

The separate message file contains routing metadata, encrypted payload bytes,
signed per-device wrapped keys, cursors, and receipts. Message send, sync,
receipt, and device-directory procedures derive account ownership from the
authenticated WAMP caller; plaintext and client private keys are never accepted
by those procedures.

## Platform Push

Firebase Cloud Messaging delivery is optional. Configure it with a
service-account file stored outside the repository:

```yaml
platform_push:
  fcm:
    service_account_file: /run/secrets/firebase-service-account.json
    # Optional; defaults to project_id in the credential file.
    project_id: your-firebase-project
```

The server uses the FCM HTTP v1 API and always sends only the durable mailbox
cursor as provider data. Each secret device registration also stores a bounded
set of muted conversation IDs. An incoming message for an unmuted device adds
only generic `WampApp` / `New message` notification text; muted conversations,
sender devices, delivery/read receipts, and one-time-consumption updates remain
silent cursor wakeups. FCM never receives a sender, account, conversation,
message ID, message body, attachment, ciphertext, or encryption material.
Android, APNs-backed Apple devices, and web push therefore share one delivery
path while the authenticated WAMP mailbox remains the canonical source of
message data.
Invalid provider tokens are retired;
quota, provider authentication, and transient service failures preserve the
token for a later mailbox wakeup.

See the [parent guide](../README.md) for setup and security boundaries.
