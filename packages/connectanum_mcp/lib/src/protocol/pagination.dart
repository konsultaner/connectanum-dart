import 'dart:convert';

import 'errors.dart';

String encodeMcpCursor({
  required String prefix,
  required int revision,
  required int offset,
}) {
  final encoded = base64Url.encode(utf8.encode('$prefix$revision:$offset'));
  return encoded.replaceAll('=', '');
}

int decodeMcpCursor(
  String? cursor, {
  required String prefix,
  required int expectedRevision,
  required int maxOffset,
  required String errorMessage,
}) {
  if (cursor == null) {
    return 0;
  }
  try {
    final padding = (4 - cursor.length % 4) % 4;
    final normalized = cursor.padRight(cursor.length + padding, '=');
    final decoded = utf8.decode(base64Url.decode(normalized));
    if (!decoded.startsWith(prefix)) {
      throw const FormatException('wrong prefix');
    }
    final cursorParts = decoded.substring(prefix.length).split(':');
    if (cursorParts.length != 2) {
      throw const FormatException('wrong cursor shape');
    }
    final revision = int.parse(cursorParts[0]);
    final offset = int.parse(cursorParts[1]);
    if (revision != expectedRevision) {
      throw const FormatException('cursor revision is stale');
    }
    if (offset < 0 || offset > maxOffset) {
      throw const FormatException('cursor offset out of range');
    }
    return offset;
  } on FormatException {
    throw McpException(McpErrorCodes.invalidParams, errorMessage);
  }
}
