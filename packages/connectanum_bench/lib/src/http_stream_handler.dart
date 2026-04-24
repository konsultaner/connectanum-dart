import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectanum_router/connectanum_router.dart';

enum BenchHttpStreamResponseMode { synthetic, nativeForwarded, buffered }

class BenchHttpStreamResponseStats {
  const BenchHttpStreamResponseStats({
    required this.responseMode,
    required this.requestBodyDrain,
    required this.firstChunkQueued,
    required this.emittedChunkCount,
    required this.firstChunkBytes,
    required this.handlerElapsed,
  });

  final BenchHttpStreamResponseMode responseMode;
  final Duration requestBodyDrain;
  final Duration? firstChunkQueued;
  final int emittedChunkCount;
  final int firstChunkBytes;
  final Duration handlerElapsed;
}

class BenchHttpStreamWriteTracker {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration? _streamOpened;
  Duration? _firstBodyWrite;
  Duration? _firstBodyWriteCompleted;

  Duration? get streamOpened => _streamOpened;
  Duration? get firstBodyWrite => _firstBodyWrite;
  Duration? get firstBodyWriteCompleted => _firstBodyWriteCompleted;

  void markStreamOpened() {
    _streamOpened ??= _stopwatch.elapsed;
  }

  void markFirstBodyWrite() {
    _firstBodyWrite ??= _stopwatch.elapsed;
  }

  void markFirstBodyWriteCompleted() {
    _firstBodyWriteCompleted ??= _stopwatch.elapsed;
  }
}

class BenchHttpStreamDiagnostics {
  int _requestsTotal = 0;
  int _syntheticResponsesTotal = 0;
  int _nativeForwardedResponsesTotal = 0;
  int _bufferedResponsesTotal = 0;
  int _requestBodyDrainSamplesTotal = 0;
  int _streamOpenSamplesTotal = 0;
  int _firstChunkQueuedSamplesTotal = 0;
  int _firstBodyWriteSamplesTotal = 0;
  int _firstBodyWriteCompletedSamplesTotal = 0;
  int _headersToFirstBodyWriteSamplesTotal = 0;
  int _headersToFirstBodyWriteCompletedSamplesTotal = 0;
  int _queueToFirstBodyWriteSamplesTotal = 0;
  int _queueToFirstBodyWriteCompletedSamplesTotal = 0;
  int _firstBodyWriteCallSamplesTotal = 0;
  int _handlerSamplesTotal = 0;
  int _requestBodyDrainUsTotal = 0;
  int _streamOpenUsTotal = 0;
  int _firstChunkQueuedUsTotal = 0;
  int _firstBodyWriteUsTotal = 0;
  int _firstBodyWriteCompletedUsTotal = 0;
  int _headersToFirstBodyWriteUsTotal = 0;
  int _headersToFirstBodyWriteCompletedUsTotal = 0;
  int _queueToFirstBodyWriteUsTotal = 0;
  int _queueToFirstBodyWriteCompletedUsTotal = 0;
  int _firstBodyWriteCallUsTotal = 0;
  int _handlerUsTotal = 0;

  void record({
    required BenchHttpStreamResponseStats response,
    Duration? streamOpened,
    Duration? firstBodyWrite,
    Duration? firstBodyWriteCompleted,
  }) {
    _requestsTotal++;
    switch (response.responseMode) {
      case BenchHttpStreamResponseMode.synthetic:
        _syntheticResponsesTotal++;
        _requestBodyDrainSamplesTotal++;
        _requestBodyDrainUsTotal += response.requestBodyDrain.inMicroseconds;
        break;
      case BenchHttpStreamResponseMode.nativeForwarded:
        _nativeForwardedResponsesTotal++;
        break;
      case BenchHttpStreamResponseMode.buffered:
        _bufferedResponsesTotal++;
        break;
    }

    final firstChunkQueued = response.firstChunkQueued;
    if (streamOpened != null) {
      _streamOpenSamplesTotal++;
      _streamOpenUsTotal += streamOpened.inMicroseconds;
    }
    if (firstChunkQueued != null) {
      _firstChunkQueuedSamplesTotal++;
      _firstChunkQueuedUsTotal += firstChunkQueued.inMicroseconds;
    }
    if (firstBodyWrite != null) {
      _firstBodyWriteSamplesTotal++;
      _firstBodyWriteUsTotal += firstBodyWrite.inMicroseconds;
    }
    if (firstBodyWriteCompleted != null) {
      _firstBodyWriteCompletedSamplesTotal++;
      _firstBodyWriteCompletedUsTotal += firstBodyWriteCompleted.inMicroseconds;
    }
    if (streamOpened != null &&
        firstBodyWrite != null &&
        firstBodyWrite >= streamOpened) {
      _headersToFirstBodyWriteSamplesTotal++;
      _headersToFirstBodyWriteUsTotal +=
          (firstBodyWrite - streamOpened).inMicroseconds;
    }
    if (streamOpened != null &&
        firstBodyWriteCompleted != null &&
        firstBodyWriteCompleted >= streamOpened) {
      _headersToFirstBodyWriteCompletedSamplesTotal++;
      _headersToFirstBodyWriteCompletedUsTotal +=
          (firstBodyWriteCompleted - streamOpened).inMicroseconds;
    }
    if (firstChunkQueued != null &&
        firstBodyWrite != null &&
        firstBodyWrite >= firstChunkQueued) {
      _queueToFirstBodyWriteSamplesTotal++;
      _queueToFirstBodyWriteUsTotal +=
          (firstBodyWrite - firstChunkQueued).inMicroseconds;
    }
    if (firstChunkQueued != null &&
        firstBodyWriteCompleted != null &&
        firstBodyWriteCompleted >= firstChunkQueued) {
      _queueToFirstBodyWriteCompletedSamplesTotal++;
      _queueToFirstBodyWriteCompletedUsTotal +=
          (firstBodyWriteCompleted - firstChunkQueued).inMicroseconds;
    }
    if (firstBodyWrite != null &&
        firstBodyWriteCompleted != null &&
        firstBodyWriteCompleted >= firstBodyWrite) {
      _firstBodyWriteCallSamplesTotal++;
      _firstBodyWriteCallUsTotal +=
          (firstBodyWriteCompleted - firstBodyWrite).inMicroseconds;
    }
    _handlerSamplesTotal++;
    _handlerUsTotal += response.handlerElapsed.inMicroseconds;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requests_total': _requestsTotal,
      'synthetic_responses_total': _syntheticResponsesTotal,
      'native_forwarded_responses_total': _nativeForwardedResponsesTotal,
      'buffered_responses_total': _bufferedResponsesTotal,
      'request_body_drain_samples_total': _requestBodyDrainSamplesTotal,
      'stream_open_samples_total': _streamOpenSamplesTotal,
      'first_chunk_queued_samples_total': _firstChunkQueuedSamplesTotal,
      'first_body_write_samples_total': _firstBodyWriteSamplesTotal,
      'first_body_write_completed_samples_total':
          _firstBodyWriteCompletedSamplesTotal,
      'headers_to_first_body_write_samples_total':
          _headersToFirstBodyWriteSamplesTotal,
      'headers_to_first_body_write_completed_samples_total':
          _headersToFirstBodyWriteCompletedSamplesTotal,
      'queue_to_first_body_write_samples_total':
          _queueToFirstBodyWriteSamplesTotal,
      'queue_to_first_body_write_completed_samples_total':
          _queueToFirstBodyWriteCompletedSamplesTotal,
      'first_body_write_call_samples_total': _firstBodyWriteCallSamplesTotal,
      'handler_samples_total': _handlerSamplesTotal,
      'request_body_drain_us_total': _requestBodyDrainUsTotal,
      'stream_open_us_total': _streamOpenUsTotal,
      'first_chunk_queued_us_total': _firstChunkQueuedUsTotal,
      'first_body_write_us_total': _firstBodyWriteUsTotal,
      'first_body_write_completed_us_total': _firstBodyWriteCompletedUsTotal,
      'headers_to_first_body_write_us_total': _headersToFirstBodyWriteUsTotal,
      'headers_to_first_body_write_completed_us_total':
          _headersToFirstBodyWriteCompletedUsTotal,
      'queue_to_first_body_write_us_total': _queueToFirstBodyWriteUsTotal,
      'queue_to_first_body_write_completed_us_total':
          _queueToFirstBodyWriteCompletedUsTotal,
      'first_body_write_call_us_total': _firstBodyWriteCallUsTotal,
      'handler_us_total': _handlerUsTotal,
    };
  }
}

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

Future<BenchHttpStreamResponseStats> streamBenchHttpResponse({
  required HttpRequestSnapshot request,
  required void Function(List<int> chunk) addChunk,
  required void Function([List<int>? finalChunk]) close,
}) async {
  final stopwatch = Stopwatch()..start();
  final responseBytes = parseBenchHeaderInt(
    request.headers,
    'x-bench-response-bytes',
  );
  final requestLength = request.nativeBody?.length ?? request.body?.length ?? 0;
  final responseChunkBytes =
      parseBenchHeaderInt(request.headers, 'x-bench-response-chunk-bytes') ??
      math.min(requestLength, 64 * 1024);
  var requestBodyDrain = Duration.zero;
  Duration? firstChunkQueued;
  var emittedChunkCount = 0;
  var firstChunkBytes = 0;

  void emitChunk(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }
    firstChunkQueued ??= stopwatch.elapsed;
    if (emittedChunkCount == 0) {
      firstChunkBytes = chunk.length;
    }
    emittedChunkCount++;
    addChunk(chunk);
  }

  if (responseBytes != null && responseBytes > 0) {
    final drainStopwatch = Stopwatch()..start();
    await _drainRequestBody(request);
    requestBodyDrain = drainStopwatch.elapsed;
    final chunk = buildPatternChunk(math.max(1, responseChunkBytes));
    var remaining = responseBytes;
    while (remaining > 0) {
      final sliceLength = math.min(remaining, chunk.length);
      emitChunk(Uint8List.sublistView(chunk, 0, sliceLength));
      remaining -= sliceLength;
    }
    close();
    return BenchHttpStreamResponseStats(
      responseMode: BenchHttpStreamResponseMode.synthetic,
      requestBodyDrain: requestBodyDrain,
      firstChunkQueued: firstChunkQueued,
      emittedChunkCount: emittedChunkCount,
      firstChunkBytes: firstChunkBytes,
      handlerElapsed: stopwatch.elapsed,
    );
  }

  final nativeBody = request.nativeBody;
  if (nativeBody != null) {
    var forwardedAny = false;
    await for (final chunk in nativeBody.openRead()) {
      if (chunk.isEmpty) {
        continue;
      }
      forwardedAny = true;
      emitChunk(chunk);
    }
    if (!forwardedAny) {
      emitChunk(Uint8List.fromList('bench'.codeUnits));
    }
    close();
    return BenchHttpStreamResponseStats(
      responseMode: BenchHttpStreamResponseMode.nativeForwarded,
      requestBodyDrain: requestBodyDrain,
      firstChunkQueued: firstChunkQueued,
      emittedChunkCount: emittedChunkCount,
      firstChunkBytes: firstChunkBytes,
      handlerElapsed: stopwatch.elapsed,
    );
  }

  final payload = request.body ?? Uint8List(0);
  if (payload.isEmpty) {
    emitChunk(Uint8List.fromList('bench'.codeUnits));
  } else {
    emitChunk(payload);
  }
  close();
  return BenchHttpStreamResponseStats(
    responseMode: BenchHttpStreamResponseMode.buffered,
    requestBodyDrain: requestBodyDrain,
    firstChunkQueued: firstChunkQueued,
    emittedChunkCount: emittedChunkCount,
    firstChunkBytes: firstChunkBytes,
    handlerElapsed: stopwatch.elapsed,
  );
}

Future<void> _drainRequestBody(HttpRequestSnapshot request) async {
  final nativeBody = request.nativeBody;
  if (nativeBody == null) {
    request.body;
    return;
  }
  await for (final _ in nativeBody.openRead()) {}
}
