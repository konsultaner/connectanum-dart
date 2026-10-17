# Preserve UTF-8 and present empty native metadata strings

The router's five native metadata string slots used `String.fromCharCodes`,
which interpreted the UTF-8 bytes as Latin-1. Its length-zero shortcut also
collapsed present empty strings into null. The client reader already uses
UTF-8 decoding and distinguishes absence through the null pointer.

Rust `option_str_ptr` exposes `Some(&str)` as its pointer and UTF-8 byte length;
`None` is `(null, 0)`. Strings have validated Rust UTF-8 storage, and lengths
reach Dart as unsigned pointer-sized fields. The router reader is used only by
the five CtMessageInfo slots. It now matches the client: null pointer yields
null; a nonnull zero-length view yields an empty string; other strings decode
as UTF-8. No ABI, protocol schema, application-buffer ownership or copy scope
changes. Validating route names remains separate from preserving decoded text.

A real-native fail-first run covers CALL and PUBLISH across JSON, MessagePack,
CBOR and FlatBuffers: two-, three- and four-byte characters, combined Unicode,
present empty strings, absence and null. All five string slots are checked
after releasing the original message. Before the repair, 40 of 56 cases fail
and 16 pass; afterward the complete 185-case native metadata suite passes.
The empty/absent/null cases use an ASCII URI so Unicode does not mask their
result. FlatBuffers fixtures encode the complete WAMP array through the normal
model, including dictionaries with null values; the root is never a null literal.
Focused analysis is clean. Evidence is `native-metadata-utf8-*` under the managed
worktree's `out/flatbuffers-milestone-finish`.

Local review suggestions are checked against the actual contract and results.
There is no signed negative length to guard, and the old zero-length check
provided no allocation-bound protection for a positive length. Mapping null
pointers to empty strings would break absence. The full native tests exercise
nonnull empty pointers and null pointers directly; all five callers are covered.
No permissive UTF-8 fallback or swallowed range error is introduced. Full
resulting-source verification and hosted checks remain required.
