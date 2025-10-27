# Remote Authentication Interoperability Guide

The legacy Java authentication service (`connectanum-authentication`) implements remote authentication as a dedicated WAMP realm.  This document summarises the contract so the Dart router (and any new delegates) can interoperate without reading the Java sources in depth.

## Realm & Procedures

| Item | Value | Notes |
| --- | --- | --- |
| Authentication realm | `connectanum.authenticate` | The router connects here as a WAMP client using its own service credentials. |
| Challenge RPC | `authenticate.hello` | Invoked when a user sends `HELLO` to the edge router. |
| Authenticate RPC | `authenticate.authenticate` | Invoked when the user replies with `AUTHENTICATE`. |
| Abort RPC | `authenticate.abort` | Called when the edge connection drops mid-handshake to allow cleanup. |

Each RPC expects keyword arguments (`argumentsKeywords`) containing the payload described below. Positional arguments are unused.

## Request/Response Payloads

### Router Configuration

Realm authenticator entries may include the following options in addition to `method`:

```jsonc
{
  "authenticators": {
    "remote-basic": {
      "type": "remote",
      "options": {
        "method": "remote",
        "allowed_roles": ["member", "service"],
        "allowed_providers": ["remote-db", "remote-cache"],
        "rate_limit_max_attempts": 5,
        "rate_limit_window_ms": 10000,
        "backoff_base_ms": 500,
        "backoff_factor": 2.0,
        "backoff_max_ms": 30000
      }
    }
  }
}
```

- `allowed_roles` (optional): only these roles are accepted from the remote service.  Empty list means “allow all”.
- `allowed_providers` (optional): only these provider identifiers are accepted (`authprovider` or `provider` field in the success payload).
- `rate_limit_max_attempts` (optional, default `5`): number of remote failures within the window before backoff kicks in.
- `rate_limit_window_ms` (optional, default `10000`): sliding window for counting failures.
- `backoff_base_ms` / `backoff_factor` / `backoff_max_ms` (optional): exponential backoff parameters applied once the max attempts threshold is exceeded.  The router refuses further attempts until the backoff expires.


### `authenticate.hello`

Request keywords:

```jsonc
{
  "hello": { /* raw HELLO message as materialised by the router */ },
  "transactionId": "opaque-transaction-id"
}
```

The router must generate a cryptographically secure `transactionId` per handshake.  The same ID is echoed in all follow-up calls (`authenticate.authenticate` and `authenticate.abort`).

Response options:

| Status | Java class | Fields |
| --- | --- | --- |
| Success | `HelloResult` | `ArgumentsKeywords.signature` (optional), `ArgumentsKeywords.extra` (challenge map) |
| Failure | `ErrorMessageException` | `error` contains reason; Java executor synthesises a “fake challenge” so the client cannot distinguish remote failures from local ones. |

For a successful challenge the router should forward:

```jsonc
{
  "challenge": {
    "nonce": "...",        // server nonce appended to client's nonce
    "salt": "...",         // optional depending on method
    "iterations": 4096,
    "memory": 64,          // SCRAM Argon2 optional
    "kdf": "pbkdf2"        // or "argon2id13"
  },
  "extra": {}               // additional authextra values (usually empty)
}
```

### `authenticate.authenticate`

Request keywords:

```jsonc
{
  "authenticate": { /* AUTHENTICATE message */ },
  "transactionId": "same-id-as-HELLO"
}
```

Responses:

| Status | Java class | Fields |
| --- | --- | --- |
| Success | `WelcomeResult` | `ArgumentsKeywords` contains the negotiated session attributes. |
| Failure | `ErrorMessageException` | router should send `ABORT`. |

Successful payload example:

```jsonc
{
  "authId": "alice",
  "authRole": "member",
  "authProvider": "remote-db",
  "authMethod": "scram",
  "challenge": null,        // optional server proof if required
  "sessionId": 4242,
  "details": { /* extra fields for authextra */ }
}
```

The Dart router validates the returned role/provider against optional allow-lists (`allowed_roles`, `allowed_providers`) defined in realm authenticator options.  Responses outside those sets are rejected with `wamp.error.not_authorized`.  After validation the router forwards the `details` map into the `WELCOME` message.

### `authenticate.abort`

Sent on best-effort basis when the edge connection is terminated before completion:

```jsonc
{
  "transactionId": "same-id-as-HELLO"
}
```

The remote service is expected to clean up any stored transaction state associated with the ID.

## Error Handling Expectations

* When the remote service rejects a `HELLO`, it should throw an error (`wamp.error.not_authorized` or similar). The Java executor mirrors this rejection by emitting a synthetic challenge so clients always see the same protocol flow.
* If the remote service does not respond (timeout, network issue), the edge router should abort the session and treat it as a failed authentication (the Java implementation does so after 60 seconds).
* Always log remote failures with enough context (`transactionId`, `authId`, reason) for operators.

## Data-Minimisation Guidelines

Only the following fields are required for remote RPCs:

* From `HELLO`: `realm`, `details.authid`, `details.authmethods`, and `details.authextra`.  Avoid sending role negotiation data or large option maps unless the remote service explicitly depends on them.
* From `AUTHENTICATE`: `signature` and any extra fields carrying nonces/proofs.

Future work will formalise these reduced payloads on the Dart side; for now ensure your delegate ignores extraneous fields.

## Fake Challenge Behaviour

The Java executor generates a “fake” SCRAM/Cra challenge when the remote server rejects a user so client timing stays uniform.  When porting or replacing the Java service, reproduce this behaviour:

1. Create HMAC/SCRAM parameters that look legitimate (nonce, iterations, salt).
2. Return them in an error payload (or let the Java executor do it by throwing `ErrorMessageException` with a `fakeChallengeExtra` map).
3. The router will forward this fake challenge; the client’s subsequent `AUTHENTICATE` will fail, preventing user enumeration.

## Implementation Checklist for Dart Delegates

1. Connect to `connectanum.authenticate` with service credentials (mutual TLS recommended).
2. Register RPC handlers for the three procedures above.
3. Persist transaction metadata keyed by `transactionId` and expire entries on `authenticate.abort` or timeout.
4. Produce deterministic challenge / welcome payloads adhering to the schema.
5. Return hashed credentials (CRA derived keys, SCRAM stored/server keys) and avoid exposing secrets in responses.
6. Surface deliberate denials via `AuthFailure` (incl. `arguments` / `argumentsKeywords`) so the edge router can forward the exact `ABORT` payload to the client.
7. Emit audit logs on success/failure to integrate with `AuthAuditLogger`.

### Delegate registration & failover

Register each remote delegate with a stable identifier before starting the router:

```dart
RemoteAuthenticatorRegistry.register(primaryDelegate, id: 'primary');
RemoteAuthenticatorRegistry.register(fallbackDelegate, id: 'secondary');
```

Realm authenticator options can then reference those identifiers in priority order:

```jsonc
{
  "type": "remote",
  "options": {
    "method": "remote",
    "delegates": ["primary", "secondary"],
    "delegate_retry_ms": 10000,
    "allowed_roles": ["remote-member"]
  }
}
```

If a delegate throws a `RemoteDelegateUnavailableException` (or any other exception), the router marks it unavailable for `delegate_retry_ms` milliseconds and tries the next delegate in the list. Once a delegate responds successfully it is marked healthy again.

Use `RemoteDelegateUnavailableException` when the backing service is down or unreachable so the router knows to fail over without logging the attempt as an authentication failure.

Refer to `packages/connectanum_router/lib/src/router/auth/remote_authenticator.dart` for the Dart-side expectations and `packages/connectanum_router/test/router_worker_auth_test.dart` for end-to-end examples.
