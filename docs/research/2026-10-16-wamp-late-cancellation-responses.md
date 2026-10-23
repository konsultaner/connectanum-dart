# Late cancellation responses and encoded-volume accounting

The short supplemental protocol proof on `4dab389f` completed 180 rows, but
`ext_07_small_control_flatbuffers` recorded one rejected router submission. Its
encoded-volume observation correctly remained unavailable. This no-PPT native
WebSocket/TLS cancellation case does not use the new typed native-prefix path.

A repeated workload-sequence probe on `c15f2185` reproduces the rejection with
CBOR too. A separate temporary, local-only diagnostic captures the rejected
FlatBuffers frame. The normal pinned reader decodes it as
`ERROR(INVOCATION, 52, {}, "wamp.error.no_such_invocation")`. The native runtime
rejects it because the callee connection has already closed. The diagnostic is
restored before production edits and is not part of the implementation.

The router removes a non-waiting cancelled invocation immediately. It previously
answered late callee YIELD/ERROR messages with another error, including when
cancellation won an asynchronous completion or progressive-update race. That
extra response could reach the native queue after callee teardown. Existing
tests incorrectly required an error for a late YIELD after `killnowait`.

[WAMP's Call Canceling specification, section 11.4](https://wamp-proto.org/wamp_latest_ietf.html)
requires late results to be discarded for `skip` and `killnowait`. Its Caller
Leaving section also requires handling responses to defunct calls. The repair
discards a response when lookup, completion or progressive update confirms that
the invocation is gone. It preserves active invocation ownership checks, normal
forwarding and genuine state-store exception handling. It introduces no retained
cancelled-call records or timeout heuristic.

Nine assertions fail before the repair: final/progressive YIELD and ERROR after
each non-waiting cancellation mode, two completion races and a progressive-update
race. All nine pass after the repair, alongside the two existing store-exception
controls. Full resulting-source verification and renewed live proofs remain
required.

The rejected-submission counter and its fail-closed volume validation are
unchanged. Removing a protocol-invalid reply does not make its former failed
observations acceptable. This correction establishes no performance parity;
the unchanged paired campaign and copy-accounting gates still apply.

Local raw diagnostics, decoded frames, source hashes, fail-first and repaired
test logs are retained under `out/flatbuffers-milestone-finish/` with the
`cancel-volume-` prefix. The first out-of-tree test fixture had an invalid part
URI; its compile failure is retained separately and excluded from regression
evidence.
