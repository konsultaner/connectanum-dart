## Goal

Add reusable negotiated and peer/trust policy adapters on top of the shared
WAMP E2EE key-selection hook so applications can compose `WELCOME.authextra`
fallbacks with peer-aware policy decisions without hand-writing ad hoc
callbacks for every session.

## Scope

- add reusable key-selection adapter helpers to `connectanum_core`
- cover negotiated-session fallback from `WampE2eeRuntimeContext.negotiated`
- cover peer identity and trust-based rule matching from
  `WampE2eePartyContext`
- wire the client-session negotiated wrapper to use the reusable adapter path
  instead of hardcoded key-id fallback logic
- add focused tests in core and client for negotiated fallback and policy
  override behavior

## Non-goals

- new ciphers or serializer support
- router-side payload decryption or policy execution
- changing the negotiated `authextra.e2ee` wire shape
- changing the native FFI contract

## Verification

- `bin/test-fast`
- focused Dart tests for E2EE adapter behavior in core and client
- `bin/verify`

## Status

- completed

## Handoff

- The main regression that landed here is session-wrapped provider behavior:
  explicit provider policy can now override negotiated key-id fallback while
  still inheriting negotiated serializer/cipher defaults.
- There is no follow-on E2EE exec plan queued right now. The next session
  should choose the next unfinished milestone from `ROADMAP_NEXT.md` unless a
  concrete application integration surfaces a need for higher-level E2EE
  policy presets.
