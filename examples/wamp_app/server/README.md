# WampApp Server

This standalone Dart package starts a Connectanum router and the registration
service used by WampApp. Configuration lives in `wamp_app_server.yaml`.

The account file stores `salt`, `stored_key`, `server_key`, KDF parameters,
identity metadata, and creation time. It never stores plaintext passwords.
Router worker isolates reconstruct the file-backed credential provider before
authentication, so newly registered accounts are available on reconnect.

See the [parent guide](../README.md) for setup and security boundaries.
