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

See the [parent guide](../README.md) for setup and security boundaries.
