## Goal

Refresh the public-facing docs so the current Connectanum behavior is obvious to
integrators: cancellation semantics, graceful drain behavior, lazy-payload /
zero-copy guarantees, and the shortest path to runnable examples.

## Scope

- update the root `README.md` so it links to the right examples and describes
  the current router/client runtime semantics accurately
- update the client and router package READMEs with concise guidance for
  progressive results, call cancellation, graceful shutdown, and lazy payload
  APIs
- tighten `docs/deployment.md` around graceful shutdown, `/healthz`, and drain
  expectations
- add one small checked-in examples gallery under `docs/` that links the repo's
  runnable example entrypoints and includes short snippets for progressive
  results and cancellation

## Non-goals

- changing runtime behavior or API contracts
- introducing new example applications beyond the existing checked-in entrypoints
- documenting unstable future work as if it were already implemented

## Verification

- `bin/test-fast`
- `bin/verify`

## Status

- completed

## Handoff

- Completed. The public docs surface now states the current runtime contracts
  directly instead of leaving them implied by tests or scattered project-state
  notes.
- `README.md`, `packages/connectanum_client/README.md`,
  `packages/connectanum_router/README.md`, and `docs/deployment.md` now
  document the supported cancellation modes (`skip`, `kill`, `killnowait`),
  graceful drain behavior, `/healthz` semantics, and the conditional
  lazy-payload / zero-copy boundaries.
- `docs/examples.md` is a new small public examples gallery that links the
  runnable client/router entrypoints and includes short walkthrough snippets for
  progressive results, call cancellation, lazy payload APIs, and graceful
  router shutdown.
- Verification passed with `bin/test-fast` and `bin/verify`.
