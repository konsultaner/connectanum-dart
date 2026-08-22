import 'dart:convert';
import 'dart:typed_data';

const _base64Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
final Int8List _base64DecodeTable = _createBase64DecodeTable();

Int8List _createBase64DecodeTable() {
  final table = Int8List(256)..fillRange(0, 256, -1);
  for (var index = 0; index < _base64Alphabet.length; index++) {
    table[_base64Alphabet.codeUnitAt(index)] = index;
  }
  return table;
}

Uint8List encodeBase64Bytes(Uint8List input) {
  final output = Uint8List(((input.length + 2) ~/ 3) * 4);
  var inputIndex = 0;
  var outputIndex = 0;
  while (inputIndex + 2 < input.length) {
    final bits =
        (input[inputIndex] << 16) |
        (input[inputIndex + 1] << 8) |
        input[inputIndex + 2];
    output[outputIndex] = _base64Alphabet.codeUnitAt((bits >> 18) & 0x3f);
    output[outputIndex + 1] = _base64Alphabet.codeUnitAt(
      (bits >> 12) & 0x3f,
    );
    output[outputIndex + 2] = _base64Alphabet.codeUnitAt((bits >> 6) & 0x3f);
    output[outputIndex + 3] = _base64Alphabet.codeUnitAt(bits & 0x3f);
    inputIndex += 3;
    outputIndex += 4;
  }

  final remaining = input.length - inputIndex;
  if (remaining == 1) {
    final byte = input[inputIndex];
    output[outputIndex] = _base64Alphabet.codeUnitAt(byte >> 2);
    output[outputIndex + 1] = _base64Alphabet.codeUnitAt((byte & 0x03) << 4);
    output[outputIndex + 2] = 0x3d;
    output[outputIndex + 3] = 0x3d;
  } else if (remaining == 2) {
    final bits = (input[inputIndex] << 8) | input[inputIndex + 1];
    output[outputIndex] = _base64Alphabet.codeUnitAt((bits >> 10) & 0x3f);
    output[outputIndex + 1] = _base64Alphabet.codeUnitAt((bits >> 4) & 0x3f);
    output[outputIndex + 2] = _base64Alphabet.codeUnitAt((bits & 0x0f) << 2);
    output[outputIndex + 3] = 0x3d;
  }
  return output;
}

Uint8List decodeBase64Bytes(String input, int start) {
  final end = RangeError.checkValidRange(start, null, input.length);
  final length = end - start;
  if (length == 0) {
    return Uint8List(0);
  }
  if ((length & 3) != 0) {
    return base64.decoder.convert(input, start);
  }

  var padding = 0;
  if (input.codeUnitAt(end - 1) == 0x3d) {
    padding++;
    if (input.codeUnitAt(end - 2) == 0x3d) {
      padding++;
    }
  }
  final output = Uint8List((length ~/ 4) * 3 - padding);
  var inputIndex = start;
  var outputIndex = 0;
  final finalQuartet = end - 4;
  while (inputIndex < finalQuartet) {
    final a = _decodeBase64CodeUnit(input.codeUnitAt(inputIndex));
    final b = _decodeBase64CodeUnit(input.codeUnitAt(inputIndex + 1));
    final c = _decodeBase64CodeUnit(input.codeUnitAt(inputIndex + 2));
    final d = _decodeBase64CodeUnit(input.codeUnitAt(inputIndex + 3));
    if ((a | b | c | d) < 0) {
      return base64.decoder.convert(input, start);
    }
    final bits = (a << 18) | (b << 12) | (c << 6) | d;
    output[outputIndex] = bits >> 16;
    output[outputIndex + 1] = bits >> 8;
    output[outputIndex + 2] = bits;
    inputIndex += 4;
    outputIndex += 3;
  }

  final a = _decodeBase64CodeUnit(input.codeUnitAt(inputIndex));
  final b = _decodeBase64CodeUnit(input.codeUnitAt(inputIndex + 1));
  if ((a | b) < 0) {
    return base64.decoder.convert(input, start);
  }
  if (padding == 2) {
    if (input.codeUnitAt(inputIndex + 2) != 0x3d ||
        input.codeUnitAt(inputIndex + 3) != 0x3d ||
        (b & 0x0f) != 0) {
      return base64.decoder.convert(input, start);
    }
    output[outputIndex] = (a << 2) | (b >> 4);
    return output;
  }

  final c = _decodeBase64CodeUnit(input.codeUnitAt(inputIndex + 2));
  if (c < 0) {
    return base64.decoder.convert(input, start);
  }
  output[outputIndex] = (a << 2) | (b >> 4);
  output[outputIndex + 1] = (b << 4) | (c >> 2);
  if (padding == 1) {
    if (input.codeUnitAt(inputIndex + 3) != 0x3d || (c & 0x03) != 0) {
      return base64.decoder.convert(input, start);
    }
    return output;
  }

  final d = _decodeBase64CodeUnit(input.codeUnitAt(inputIndex + 3));
  if (d < 0) {
    return base64.decoder.convert(input, start);
  }
  output[outputIndex + 2] = (c << 6) | d;
  return output;
}

/// Decodes canonical base64 directly from an ASCII byte range.
///
/// Returns `null` when the range uses a compatible noncanonical form that
/// should be handled by the SDK decoder instead.
Uint8List? tryDecodeCanonicalBase64Bytes(
  Uint8List input,
  int start,
  int end,
) {
  RangeError.checkValidRange(start, end, input.length);
  final length = end - start;
  if (length == 0) {
    return Uint8List(0);
  }
  if ((length & 3) != 0) {
    return null;
  }

  var padding = 0;
  if (input[end - 1] == 0x3d) {
    padding++;
    if (input[end - 2] == 0x3d) {
      padding++;
    }
  }
  final output = Uint8List((length ~/ 4) * 3 - padding);
  var inputIndex = start;
  var outputIndex = 0;
  final finalQuartet = end - 4;
  while (inputIndex < finalQuartet) {
    final a = _base64DecodeTable[input[inputIndex]];
    final b = _base64DecodeTable[input[inputIndex + 1]];
    final c = _base64DecodeTable[input[inputIndex + 2]];
    final d = _base64DecodeTable[input[inputIndex + 3]];
    if ((a | b | c | d) < 0) {
      return null;
    }
    final bits = (a << 18) | (b << 12) | (c << 6) | d;
    output[outputIndex] = bits >> 16;
    output[outputIndex + 1] = bits >> 8;
    output[outputIndex + 2] = bits;
    inputIndex += 4;
    outputIndex += 3;
  }

  final a = _base64DecodeTable[input[inputIndex]];
  final b = _base64DecodeTable[input[inputIndex + 1]];
  if ((a | b) < 0) {
    return null;
  }
  if (padding == 2) {
    if (input[inputIndex + 2] != 0x3d ||
        input[inputIndex + 3] != 0x3d ||
        (b & 0x0f) != 0) {
      return null;
    }
    output[outputIndex] = (a << 2) | (b >> 4);
    return output;
  }

  final c = _base64DecodeTable[input[inputIndex + 2]];
  if (c < 0) {
    return null;
  }
  output[outputIndex] = (a << 2) | (b >> 4);
  output[outputIndex + 1] = (b << 4) | (c >> 2);
  if (padding == 1) {
    if (input[inputIndex + 3] != 0x3d || (c & 0x03) != 0) {
      return null;
    }
    return output;
  }

  final d = _base64DecodeTable[input[inputIndex + 3]];
  if (d < 0) {
    return null;
  }
  output[outputIndex + 2] = (c << 6) | d;
  return output;
}

@pragma('vm:prefer-inline')
int _decodeBase64CodeUnit(int codeUnit) {
  if (codeUnit >= 0x41 && codeUnit <= 0x5a) {
    return codeUnit - 0x41;
  }
  if (codeUnit >= 0x61 && codeUnit <= 0x7a) {
    return codeUnit - 0x61 + 26;
  }
  if (codeUnit >= 0x30 && codeUnit <= 0x39) {
    return codeUnit - 0x30 + 52;
  }
  if (codeUnit == 0x2b) {
    return 62;
  }
  if (codeUnit == 0x2f) {
    return 63;
  }
  return -1;
}
