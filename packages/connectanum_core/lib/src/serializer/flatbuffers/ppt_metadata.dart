import 'dart:typed_data';

/// Matches the complete, untagged two-text PPT dictionary without allocating.
/// Other encodings and shapes require normal validation and metadata retention.
bool matchesFlatBufferPptMetadata(
  Uint8List bytes,
  String? scheme,
  String? serializer,
) {
  if (scheme == null ||
      serializer == null ||
      bytes.isEmpty ||
      bytes.length > 1048576 ||
      bytes[0] != 0xa2) {
    return false;
  }
  var offset = 1;
  var fields = 0;
  for (var index = 0; index < 2; index++) {
    var field = 1;
    var end = _asciiCborTextEnd(bytes, offset, 'ppt_scheme');
    String expected;
    if (end >= 0) {
      expected = scheme;
    } else {
      field = 2;
      end = _asciiCborTextEnd(bytes, offset, 'ppt_serializer');
      if (end < 0) return false;
      expected = serializer;
    }
    if (fields & field != 0) return false;
    fields |= field;
    offset = _asciiCborTextEnd(bytes, end, expected);
    if (offset < 0) return false;
  }
  return fields == 3 && offset == bytes.length;
}

int _asciiCborTextEnd(Uint8List bytes, int offset, String expected) {
  if (offset >= bytes.length) return -1;
  final header = bytes[offset++];
  if (header >> 5 != 3) return -1;
  var length = header & 31;
  if (length == 24) {
    if (offset >= bytes.length) return -1;
    length = bytes[offset++];
  } else if (length == 25) {
    if (offset + 2 > bytes.length) return -1;
    length = (bytes[offset] << 8) | bytes[offset + 1];
    offset += 2;
  } else if (length > 23) {
    return -1;
  }
  if (length != expected.length || offset + length > bytes.length) return -1;
  for (var index = 0; index < length; index++) {
    final unit = expected.codeUnitAt(index);
    if (unit > 127 || bytes[offset + index] != unit) return -1;
  }
  return offset + length;
}
