import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectanum_router/connectanum_router.dart';

enum BenchHttpStreamResponseMode { synthetic, nativeForwarded, buffered }

class BenchHttpStreamResponseStats {
  const BenchHttpStreamResponseStats({
    required this.responseMode,
    required this.requestBodyDrain,
    required this.requestBodyDrainFirstChunkWait,
    required this.requestBodyDrainTailRead,
    required this.requestBodyDrainSecondChunkWait,
    required this.requestBodyDrainRemainingTailRead,
    required this.requestBodyDrainChunkCount,
    required this.firstChunkQueued,
    required this.emittedChunkCount,
    required this.firstChunkBytes,
    required this.handlerElapsed,
  });

  final BenchHttpStreamResponseMode responseMode;
  final Duration requestBodyDrain;
  final Duration? requestBodyDrainFirstChunkWait;
  final Duration? requestBodyDrainTailRead;
  final Duration? requestBodyDrainSecondChunkWait;
  final Duration? requestBodyDrainRemainingTailRead;
  final int requestBodyDrainChunkCount;
  final Duration? firstChunkQueued;
  final int emittedChunkCount;
  final int firstChunkBytes;
  final Duration handlerElapsed;
}

class BenchHttpStreamDrainStats {
  const BenchHttpStreamDrainStats({
    required this.total,
    required this.firstChunkWait,
    required this.tailRead,
    required this.secondChunkWait,
    required this.remainingTailRead,
    required this.chunkCount,
  });

  const BenchHttpStreamDrainStats.zero()
    : total = Duration.zero,
      firstChunkWait = null,
      tailRead = null,
      secondChunkWait = null,
      remainingTailRead = null,
      chunkCount = 0;

  final Duration total;
  final Duration? firstChunkWait;
  final Duration? tailRead;
  final Duration? secondChunkWait;
  final Duration? remainingTailRead;
  final int chunkCount;
}

class BenchHttpStreamWriteTracker {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration? _streamOpened;
  Duration? _firstBodyWrite;
  Duration? _firstBodyWriteCompleted;
  Duration? _directStreamOpenRoundTrip;
  Duration? _directStreamRequestQueueDelay;
  Duration? _directStreamDescriptorOpenCall;
  Duration? _directStreamReplyDeliveryDelay;

  Duration? get streamOpened => _streamOpened;
  Duration? get firstBodyWrite => _firstBodyWrite;
  Duration? get firstBodyWriteCompleted => _firstBodyWriteCompleted;
  Duration? get directStreamOpenRoundTrip => _directStreamOpenRoundTrip;
  Duration? get directStreamRequestQueueDelay => _directStreamRequestQueueDelay;
  Duration? get directStreamDescriptorOpenCall =>
      _directStreamDescriptorOpenCall;
  Duration? get directStreamReplyDeliveryDelay =>
      _directStreamReplyDeliveryDelay;

  void markStreamOpened() {
    _streamOpened ??= _stopwatch.elapsed;
  }

  void markFirstBodyWrite() {
    _firstBodyWrite ??= _stopwatch.elapsed;
  }

  void markFirstBodyWriteCompleted() {
    _firstBodyWriteCompleted ??= _stopwatch.elapsed;
  }

  void markDirectStreamOpenRoundTrip(Duration duration) {
    _directStreamOpenRoundTrip ??= duration;
  }

  void markDirectStreamRequestQueueDelay(Duration duration) {
    _directStreamRequestQueueDelay ??= duration;
  }

  void markDirectStreamDescriptorOpenCall(Duration duration) {
    _directStreamDescriptorOpenCall ??= duration;
  }

  void markDirectStreamReplyDeliveryDelay(Duration duration) {
    _directStreamReplyDeliveryDelay ??= duration;
  }
}

class BenchHttpStreamDiagnostics {
  int _requestsTotal = 0;
  int _syntheticResponsesTotal = 0;
  int _nativeForwardedResponsesTotal = 0;
  int _bufferedResponsesTotal = 0;
  int _requestBodyDrainSamplesTotal = 0;
  int _requestBodyDrainFirstChunkWaitSamplesTotal = 0;
  int _requestBodyDrainTailReadSamplesTotal = 0;
  int _requestBodyDrainSecondChunkWaitSamplesTotal = 0;
  int _requestBodyDrainRemainingTailReadSamplesTotal = 0;
  int _requestBodyDrainChunkCountSamplesTotal = 0;
  int _streamOpenSamplesTotal = 0;
  int _firstChunkQueuedSamplesTotal = 0;
  int _firstBodyWriteSamplesTotal = 0;
  int _firstBodyWriteCompletedSamplesTotal = 0;
  int _headersToFirstBodyWriteSamplesTotal = 0;
  int _headersToFirstBodyWriteCompletedSamplesTotal = 0;
  int _queueToFirstBodyWriteSamplesTotal = 0;
  int _queueToFirstBodyWriteCompletedSamplesTotal = 0;
  int _firstBodyWriteCallSamplesTotal = 0;
  int _directStreamOpenRoundTripSamplesTotal = 0;
  int _directStreamRequestQueueDelaySamplesTotal = 0;
  int _directStreamDescriptorOpenCallSamplesTotal = 0;
  int _directStreamReplyDeliveryDelaySamplesTotal = 0;
  int _handlerSamplesTotal = 0;
  int _requestBodyDrainUsTotal = 0;
  int _requestBodyDrainFirstChunkWaitUsTotal = 0;
  int _requestBodyDrainTailReadUsTotal = 0;
  int _requestBodyDrainSecondChunkWaitUsTotal = 0;
  int _requestBodyDrainRemainingTailReadUsTotal = 0;
  int _requestBodyDrainChunkCountTotal = 0;
  int _streamOpenUsTotal = 0;
  int _firstChunkQueuedUsTotal = 0;
  int _firstBodyWriteUsTotal = 0;
  int _firstBodyWriteCompletedUsTotal = 0;
  int _headersToFirstBodyWriteUsTotal = 0;
  int _headersToFirstBodyWriteCompletedUsTotal = 0;
  int _queueToFirstBodyWriteUsTotal = 0;
  int _queueToFirstBodyWriteCompletedUsTotal = 0;
  int _firstBodyWriteCallUsTotal = 0;
  int _directStreamOpenRoundTripUsTotal = 0;
  int _directStreamRequestQueueDelayUsTotal = 0;
  int _directStreamDescriptorOpenCallUsTotal = 0;
  int _directStreamReplyDeliveryDelayUsTotal = 0;
  int _handlerUsTotal = 0;

  void record({
    required BenchHttpStreamResponseStats response,
    Duration? streamOpened,
    Duration? firstBodyWrite,
    Duration? firstBodyWriteCompleted,
    Duration? directStreamOpenRoundTrip,
    Duration? directStreamRequestQueueDelay,
    Duration? directStreamDescriptorOpenCall,
    Duration? directStreamReplyDeliveryDelay,
  }) {
    _requestsTotal++;
    switch (response.responseMode) {
      case BenchHttpStreamResponseMode.synthetic:
        _syntheticResponsesTotal++;
        _requestBodyDrainSamplesTotal++;
        _requestBodyDrainUsTotal += response.requestBodyDrain.inMicroseconds;
        final firstChunkWait = response.requestBodyDrainFirstChunkWait;
        if (firstChunkWait != null) {
          _requestBodyDrainFirstChunkWaitSamplesTotal++;
          _requestBodyDrainFirstChunkWaitUsTotal +=
              firstChunkWait.inMicroseconds;
        }
        final tailRead = response.requestBodyDrainTailRead;
        if (tailRead != null) {
          _requestBodyDrainTailReadSamplesTotal++;
          _requestBodyDrainTailReadUsTotal += tailRead.inMicroseconds;
        }
        final secondChunkWait = response.requestBodyDrainSecondChunkWait;
        if (secondChunkWait != null) {
          _requestBodyDrainSecondChunkWaitSamplesTotal++;
          _requestBodyDrainSecondChunkWaitUsTotal +=
              secondChunkWait.inMicroseconds;
        }
        final remainingTailRead = response.requestBodyDrainRemainingTailRead;
        if (remainingTailRead != null) {
          _requestBodyDrainRemainingTailReadSamplesTotal++;
          _requestBodyDrainRemainingTailReadUsTotal +=
              remainingTailRead.inMicroseconds;
        }
        _requestBodyDrainChunkCountSamplesTotal++;
        _requestBodyDrainChunkCountTotal += response.requestBodyDrainChunkCount;
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
    if (directStreamOpenRoundTrip != null) {
      _directStreamOpenRoundTripSamplesTotal++;
      _directStreamOpenRoundTripUsTotal +=
          directStreamOpenRoundTrip.inMicroseconds;
    }
    if (directStreamRequestQueueDelay != null) {
      _directStreamRequestQueueDelaySamplesTotal++;
      _directStreamRequestQueueDelayUsTotal +=
          directStreamRequestQueueDelay.inMicroseconds;
    }
    if (directStreamDescriptorOpenCall != null) {
      _directStreamDescriptorOpenCallSamplesTotal++;
      _directStreamDescriptorOpenCallUsTotal +=
          directStreamDescriptorOpenCall.inMicroseconds;
    }
    if (directStreamReplyDeliveryDelay != null) {
      _directStreamReplyDeliveryDelaySamplesTotal++;
      _directStreamReplyDeliveryDelayUsTotal +=
          directStreamReplyDeliveryDelay.inMicroseconds;
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
      'request_body_drain_first_chunk_wait_samples_total':
          _requestBodyDrainFirstChunkWaitSamplesTotal,
      'request_body_drain_tail_read_samples_total':
          _requestBodyDrainTailReadSamplesTotal,
      'request_body_drain_second_chunk_wait_samples_total':
          _requestBodyDrainSecondChunkWaitSamplesTotal,
      'request_body_drain_remaining_tail_read_samples_total':
          _requestBodyDrainRemainingTailReadSamplesTotal,
      'request_body_drain_chunk_count_samples_total':
          _requestBodyDrainChunkCountSamplesTotal,
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
      'direct_stream_open_round_trip_samples_total':
          _directStreamOpenRoundTripSamplesTotal,
      'direct_stream_request_queue_delay_samples_total':
          _directStreamRequestQueueDelaySamplesTotal,
      'direct_stream_descriptor_open_call_samples_total':
          _directStreamDescriptorOpenCallSamplesTotal,
      'direct_stream_reply_delivery_delay_samples_total':
          _directStreamReplyDeliveryDelaySamplesTotal,
      'handler_samples_total': _handlerSamplesTotal,
      'request_body_drain_us_total': _requestBodyDrainUsTotal,
      'request_body_drain_first_chunk_wait_us_total':
          _requestBodyDrainFirstChunkWaitUsTotal,
      'request_body_drain_tail_read_us_total': _requestBodyDrainTailReadUsTotal,
      'request_body_drain_second_chunk_wait_us_total':
          _requestBodyDrainSecondChunkWaitUsTotal,
      'request_body_drain_remaining_tail_read_us_total':
          _requestBodyDrainRemainingTailReadUsTotal,
      'request_body_drain_chunk_count_total': _requestBodyDrainChunkCountTotal,
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
      'direct_stream_open_round_trip_us_total':
          _directStreamOpenRoundTripUsTotal,
      'direct_stream_request_queue_delay_us_total':
          _directStreamRequestQueueDelayUsTotal,
      'direct_stream_descriptor_open_call_us_total':
          _directStreamDescriptorOpenCallUsTotal,
      'direct_stream_reply_delivery_delay_us_total':
          _directStreamReplyDeliveryDelayUsTotal,
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
  var requestBodyDrainStats = const BenchHttpStreamDrainStats.zero();
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
    requestBodyDrainStats = await _drainRequestBody(request);
    requestBodyDrain = requestBodyDrainStats.total;
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
      requestBodyDrainFirstChunkWait: requestBodyDrainStats.firstChunkWait,
      requestBodyDrainTailRead: requestBodyDrainStats.tailRead,
      requestBodyDrainSecondChunkWait: requestBodyDrainStats.secondChunkWait,
      requestBodyDrainRemainingTailRead:
          requestBodyDrainStats.remainingTailRead,
      requestBodyDrainChunkCount: requestBodyDrainStats.chunkCount,
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
      requestBodyDrainFirstChunkWait: requestBodyDrainStats.firstChunkWait,
      requestBodyDrainTailRead: requestBodyDrainStats.tailRead,
      requestBodyDrainSecondChunkWait: requestBodyDrainStats.secondChunkWait,
      requestBodyDrainRemainingTailRead:
          requestBodyDrainStats.remainingTailRead,
      requestBodyDrainChunkCount: requestBodyDrainStats.chunkCount,
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
    requestBodyDrainFirstChunkWait: requestBodyDrainStats.firstChunkWait,
    requestBodyDrainTailRead: requestBodyDrainStats.tailRead,
    requestBodyDrainSecondChunkWait: requestBodyDrainStats.secondChunkWait,
    requestBodyDrainRemainingTailRead: requestBodyDrainStats.remainingTailRead,
    requestBodyDrainChunkCount: requestBodyDrainStats.chunkCount,
    firstChunkQueued: firstChunkQueued,
    emittedChunkCount: emittedChunkCount,
    firstChunkBytes: firstChunkBytes,
    handlerElapsed: stopwatch.elapsed,
  );
}

Future<BenchHttpStreamDrainStats> _drainRequestBody(
  HttpRequestSnapshot request,
) async {
  final stopwatch = Stopwatch()..start();
  var chunkCount = 0;
  Duration? firstChunkWait;
  Duration? firstChunkAt;
  Duration? secondChunkAt;
  Duration? secondChunkWait;
  final nativeBody = request.nativeBody;
  if (nativeBody == null) {
    request.body;
    return BenchHttpStreamDrainStats(
      total: stopwatch.elapsed,
      firstChunkWait: null,
      tailRead: null,
      secondChunkWait: null,
      remainingTailRead: null,
      chunkCount: 0,
    );
  }
  await for (final chunk in nativeBody.openRead()) {
    if (chunk.isEmpty) {
      continue;
    }
    final chunkAt = stopwatch.elapsed;
    if (firstChunkWait == null) {
      firstChunkWait = chunkAt;
      firstChunkAt = chunkAt;
    } else if (secondChunkWait == null) {
      secondChunkAt = chunkAt;
      secondChunkWait = chunkAt - firstChunkAt!;
    }
    chunkCount++;
  }
  final total = stopwatch.elapsed;
  final first = firstChunkWait;
  return BenchHttpStreamDrainStats(
    total: total,
    firstChunkWait: first,
    tailRead: first == null ? null : total - first,
    secondChunkWait: secondChunkWait,
    remainingTailRead: secondChunkAt == null ? null : total - secondChunkAt,
    chunkCount: chunkCount,
  );
}
