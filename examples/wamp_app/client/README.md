# WampApp Flutter Client

This package contains the WampApp Flutter client. It currently implements real
server-address onboarding, anonymous registration, asynchronous WAMP-SCRAM
login, secure remote-endpoint enforcement, encrypted device identity storage,
signed device enrollment, direct-message encryption, durable reconnect sync,
delivery receipts, encrypted local history, immutable encrypted group chats,
and resumable end-to-end encrypted attachments. Native clients cache only
ciphertext in application-support storage; web clients use IndexedDB. File
names, MIME types, plaintext hashes, and attachment keys stay inside encrypted
message/vault payloads.

See the [parent guide](../README.md) for setup, current limitations, attachment
benchmark instructions, and feature status.
