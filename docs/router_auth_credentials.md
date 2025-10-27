# Router Authentication Credential Guidelines

This project now treats credential storage as a security boundary.  Authenticators that rely on shared secrets (CRA and SCRAM) no longer require – or accept – plain-text passwords when credentials are injected through the router.  Instead, provide the derived values that the protocol uses during verification.

## WAMP-CRA (HMAC based)

- Store a derived key rather than the original secret.
- Provide the same hashing parameters that were used when the key was generated (salt, iterations, key length).
- Optional fields such as `challenge`, `role`, and `authextra` continue to work unchanged.

Example realm configuration:

```jsonc
{
  "authenticators": {
    "cra-members": {
      "type": "wampcra",
      "options": {
        "principals": [
          {
            "authid": "alice",
            "derived_key": "1W+7V6570qj5x1TRO9li2z8L4X/Td8ltpXQyFXX4X54=",
            "salt": "3q2+7w==",
            "iterations": 2000,
            "keylen": 32,
            "role": "member",
            "authextra": {"tier": "gold"}
          }
        ]
      }
    }
  }
}
```

To generate the `derived_key` programmatically:

```dart
import 'dart:convert';
import 'package:connectanum_core/authentication.dart';

final keyBytes = CraAuthentication.deriveKey(
  'alice-secret',
  base64.decode('3q2+7w=='),
  iterations: 2000,
  keylen: 32,
);
final derivedKey = base64.encode(keyBytes);
```

## SCRAM (Salted challenge/response)

- Provide either the plain secret (only for transitional testing) **or** the pair of `stored_key` and `server_key`.
- When `stored_key` is supplied, `salt` must also be present so the router can reconstruct the auth message.
- Include the same iteration count, memory cost, and KDF identifier that were used during key derivation.

Example principal entry using hashed material:

```jsonc
{
  "authid": "wendy",
  "stored_key": "Ef8k0VdQZefbWcHt5yx8I6rV9Fc1ajq1ZWjPkG+9Aag=",
  "server_key": "Stb86E/q0X6aG9L2VZGVw3qNU0mTMCncUGlYo0B+OqI=",
  "salt": "5tOHX1Y0p8aAYzFzl7dGgg==",
  "iterations": 4096,
  "kdf": "pbkdf2",
  "role": "member",
  "authextra": {"source": "users-db"}
}
```

Use the shared helper to derive both keys from an existing password when migrating data:

```dart
import 'dart:convert';
import 'package:connectanum_core/authentication.dart';

final secrets = ScramAuthentication.deriveServerSecrets(
  secret: 'wendy-secret',
  salt: '5tOHX1Y0p8aAYzFzl7dGgg==',
  iterations: 4096,
  kdf: ScramAuthentication.kdfPbkdf2,
);

print('stored_key: ${secrets.storedKey}');
print('server_key: ${secrets.serverKey}');
```

> **Tip:** Argon2id is fully supported.  Supply `kdf: "argon2id13"` alongside the memory cost you used during derivation.

## Credential providers

All credential providers registered through `AuthCredentialRegistry` must now respect the same contract:

- Return `CraCredential` with either `secret` (legacy) **or** `derivedKey`.
- Return `ScramCredential` with either `secret` (legacy) **or** both `storedKey` and `serverKey`.
- Always populate the hashing parameters (`salt`, `iterations`, `memory`, `kdf`) so the router can validate proofs deterministically.

The in-memory test provider has been updated to demonstrate the expected payloads.  Reference `_craCredentialFromSecret` and `_scramCredentialFromSecret` in `packages/connectanum_router/test/router_worker_auth_test.dart` when adapting your own storage layer.

### Signalling deliberate rejections

If a credential backend needs to reject a user without completing the challenge flow (expired subscription, account lock, etc.), throw a `CredentialRejection` from the relevant `load*` implementation. The worker converts the rejection into an immediate `AuthFailure`, preserving the reason, human readable message, and optional positional/keyword arguments in the outbound `ABORT` frame.

```dart
class BillingAwareProvider extends AuthCredentialProvider {
  @override
  Future<TicketCredential?> loadTicket({
    required String realmUri,
    required String authId,
  }) async {
    final customer = await fetchCustomer(authId);
    if (customer.subscriptionExpired) {
      throw CredentialRejection(
        reason: 'wamp.error.payment_required',
        message: 'Subscription expired on ${customer.expiry}',
        arguments: const ['PAYWALL'],
        argumentsKeywords: {
          'retry_after_ms': customer.retryAfter.inMilliseconds,
        },
      );
    }
    return TicketCredential(
      ticket: customer.ticket,
      role: 'member',
      provider: 'billing-db',
    );
  }
}
```

Every lookup (hit or miss) still emits a `CredentialLookupEvent`. Rejections include the propagated fields so that observability hooks can record the policy decision alongside the WAMP abort sent to the client.

## Migration checklist

1. Extract existing secrets from your database and run them through the helpers above to obtain derived keys.
2. Replace the plaintext values in your configuration/storage with the derived representations.
3. Ensure salts and iteration counts are preserved; configure Argon2 memory cost if used.
4. Remove any remaining plaintext copies once the router has been verified with hashed credentials.
5. (Optional) Extend your remote authenticator to enforce the same policy when delegating to external services.

For details on integrating with the legacy Java authentication service, see `docs/remote_auth_interop.md`.
