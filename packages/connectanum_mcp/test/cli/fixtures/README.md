# Real router protocol fixture

`router_protocol_2025_06_18.json.gz` retains all 208 HTTP exchanges and the exact
CLI output of a complete public router session, including both direct JSON and
Streamable/SSE operations. Compression only reduces repository size; no request,
response body, semantic header, catalog item or output field is omitted.
The replay supplements the unchanged native integration suite. Its success case
checks every request and every printed output field. Fault cases alter one
response, require the specific rejection, and allow only explicit cleanup after
that rejection. Fixture failures remain separate assertion failures.

Captured from commit `f604a27e580a8b7d70f05b8a1cd418bd7e70d61e` on 2026-11-19,
using protocol 2025-06-18 and the public, unauthenticated `/mcp` endpoint.
Source and artifact SHA256 receipts:

| Input | SHA256 |
| --- | --- |
| CLI | `9c9a5da69a30f9386fb7f4fa3dfa9fb653df6eed433d53e6b3296019989daea4` |
| HTTP client | `ebb9a73fdab5b2edc7dddced9f023777ab217126c9510fe2161c559ffcfde9b0` |
| Public example | `e928b225bfc50654cd2ba9a466015a07f8214f959cf795445bced97e32cd92b3` |
| Fresh macOS ffi-test library | `dd2376322a67eac5fc8ef47b98bd5d871233d44e01b236b63d18aaf6110920ec` |
| Compressed fixture | `a124c485befd826c3e07cae22b3996db64697f37723099e2dbd3194296b36f13` |

Regenerate deliberately from the repository root after `bin/bootstrap` and a
fresh ffi-test build:

```sh
dart run packages/connectanum_mcp/tool/record_router_protocol_fixture.dart \
  packages/connectanum_mcp/test/cli/fixtures/router_protocol_2025_06_18.json.gz
```

`CONNECTANUM_NATIVE_LIB` can select the freshly built library. Dynamic session,
subscription and publication identifiers are intentionally recorded consistently
across requests, replies and the expected output. Inspect the complete text with
`gzip -dc packages/connectanum_mcp/test/cli/fixtures/router_protocol_2025_06_18.json.gz`.
All four mutation targets that execute CLI tests hash and snapshot this fixture
as an explicit support input. Final mutation qualification still uses each
complete configured source/operator/test inventory and the original 95% policy.
