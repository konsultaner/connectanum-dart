## 3.0.0-beta.9

- Advance the adapter compatibility band to beta.9 client/core packages and the matching router test dependency.
- Preserve ObjectBox 5.3.x compatibility and native buffer ownership behavior.

## 3.0.0-beta.8

* Initial ObjectBox C API adapter for encoded entity FlatBuffers.
* Retain native Connectanum receive spans for synchronous writes without an
  additional adapter body copy. Validate schema fingerprints and entity layout.
* Count fallback staging, ID assignment, padding and owned read snapshots.
* Keep database reads as owned snapshots with transaction-safe lifetimes.
