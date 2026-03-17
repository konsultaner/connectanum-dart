import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectanum_router/connectanum_router.dart';

int? parseBenchHeaderInt(Map<String, String> headers, String headerName) {
  final lower = headerName.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) {
      return int.tryParse(entry.value);
    }
  }
  return null;
}

Uint8List buildPatternChunk(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = (i * 31) & 0xFF;
  }
  return bytes;
}

Future<void> streamBenchHttpResponse({
  required HttpRequestSnapshot request,
  required void Function(List<int> chunk) addChunk,
  required void Function([List<int>? finalChunk]) close,
}) async {
  final responseBytes = parseBenchHeaderInt(
    request.headers,
    'x-bench-response-bytes',
  );
  final requestLength = request.nativeBody?.length ?? request.body?.length ?? 0;
  final responseChunkBytes =
      parseBenchHeaderInt(request.headers, 'x-bench-response-chunk-bytes') ??
      math.min(requestLength, 64 * 1024);

  if (responseBytes != null && responseBytes > 0) {
    await _drainRequestBody(request);
    final chunk = buildPatternChunk(math.max(1, responseChunkBytes));
    var remaining = responseBytes;
    while (remaining > 0) {
      final sliceLength = math.min(remaining, chunk.length);
      addChunk(Uint8List.sublistView(chunk, 0, sliceLength));
      remaining -= sliceLength;
    }
    close();
    return;
  }

  final nativeBody = request.nativeBody;
  if (nativeBody != null) {
    var forwardedAny = false;
    await for (final chunk in nativeBody.openRead()) {
      if (chunk.isEmpty) {
        continue;
      }
      forwardedAny = true;
      addChunk(chunk);
    }
    if (!forwardedAny) {
      addChunk(Uint8List.fromList('bench'.codeUnits));
    }
    close();
    return;
  }

  final payload = request.body ?? Uint8List(0);
  if (payload.isEmpty) {
    addChunk(Uint8List.fromList('bench'.codeUnits));
  } else {
    addChunk(payload);
  }
  close();
}

Future<void> _drainRequestBody(HttpRequestSnapshot request) async {
  final nativeBody = request.nativeBody;
  if (nativeBody == null) {
    request.body;
    return;
  }
  await for (final _ in nativeBody.openRead()) {}
}
