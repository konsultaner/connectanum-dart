# connectanum_core

`connectanum_core` is the shared protocol and serializer layer used by the
Connectanum client, router, and benchmark packages.

It contains:

- WAMP message models
- JSON, MessagePack, and CBOR serializers
- authentication helpers and primitives
- payload passthrough and E2EE provider support
- conformance and serializer regression coverage

Most applications should depend on `connectanum_client` or
`connectanum_router` instead of using this package directly.

## When To Use It Directly

Use `connectanum_core` directly when you need to:

- work with raw WAMP message models
- build custom serializers or protocol tooling
- reuse authentication or payload utilities outside the full client/router

## Related Packages

- client package:
  [../connectanum_client/README.md](../connectanum_client/README.md)
- router package:
  [../connectanum_router/README.md](../connectanum_router/README.md)
- repo overview: [../../README.md](../../README.md)
