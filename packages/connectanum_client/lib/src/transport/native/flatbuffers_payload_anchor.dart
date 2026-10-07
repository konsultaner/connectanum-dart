import 'dart:typed_data';

/// Internal payload anchor pairing a native owner with its exact exported view.
typedef NativeFlatBufferPptOwnerAnchor = ({
  Object buffer,
  Uint8List bytes,
});

final _pptSubmissions = Expando<_PptSubmissions>();

final class _PptSubmissions {
  int count = 0;
  int reusedBytes = 0;
}

/// Opts this owner into observation without resetting any prior submissions.
/// Normal application sends do not allocate observation objects.
void observeNativeFlatBufferPptSubmissions(Object owner) {
  _pptSubmissions[owner] ??= _PptSubmissions();
}

/// Isolate-local observations for this exact native owner. Weak keys do not
/// prolong native lifetime. This measures queue acceptance, not peer delivery.
({int submissions, int reusedBytes}) nativeFlatBufferPptSubmissionSnapshot(
  Object owner,
) {
  final observation = _pptSubmissions[owner];
  return (
    submissions: observation?.count ?? 0,
    reusedBytes: observation?.reusedBytes ?? 0,
  );
}

/// Called only after a native frame containing this owner's span is accepted.
void recordNativeFlatBufferPptSubmission(Object owner, int payloadBytes) {
  final observation = _pptSubmissions[owner];
  if (observation == null) return;
  RangeError.checkNotNegative(payloadBytes, 'payloadBytes');
  observation.count += 1;
  observation.reusedBytes += payloadBytes;
}
