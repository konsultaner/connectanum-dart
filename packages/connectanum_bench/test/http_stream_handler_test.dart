import 'dart:typed_data';

import 'package:connectanum_bench/src/http_stream_handler.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  test(
    'streams native request chunks back without aggregating them first',
    () async {
      final firstChunk = Uint8List.fromList([1, 2]);
      final secondChunk = Uint8List.fromList([3, 4]);
      final queue = <Uint8List>[firstChunk, secondChunk];
      final request = HttpRequestSnapshot(
        id: 1,
        method: 'POST',
        target: '/bench/stream',
        path: '/bench/stream',
        protocol: 'http/1.1',
        version: 1,
        headers: const {'content-type': 'application/octet-stream'},
        nativeBody: NativeHttpRequestBody.testStreaming(
          length: 4,
          onRead: (_) => queue.isNotEmpty ? queue.removeAt(0) : Uint8List(0),
        ),
      );

      final emittedChunks = <List<int>>[];
      var closeCalls = 0;
      final stats = await streamBenchHttpResponse(
        request: request,
        addChunk: emittedChunks.add,
        close: ([List<int>? _]) => closeCalls++,
      );

      expect(emittedChunks, hasLength(2));
      expect(identical(emittedChunks[0], firstChunk), isTrue);
      expect(identical(emittedChunks[1], secondChunk), isTrue);
      expect(closeCalls, 1);
      expect(stats.responseMode, BenchHttpStreamResponseMode.nativeForwarded);
      expect(stats.requestBodyDrain, Duration.zero);
      expect(stats.emittedChunkCount, 2);
      expect(stats.firstChunkBytes, 2);
      expect(stats.firstChunkQueued, isNotNull);
    },
  );

  test(
    'drains native request bodies before generating synthetic responses',
    () async {
      final queue = <Uint8List>[
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3, 4]),
      ];
      var reads = 0;
      var finishCalls = 0;
      final request = HttpRequestSnapshot(
        id: 2,
        method: 'POST',
        target: '/bench/stream',
        path: '/bench/stream',
        protocol: 'http/2',
        version: 2,
        headers: const {
          'content-type': 'application/octet-stream',
          'x-bench-response-bytes': '6',
          'x-bench-response-chunk-bytes': '4',
        },
        nativeBody: NativeHttpRequestBody.testStreaming(
          length: 4,
          onRead: (_) {
            reads++;
            return queue.isNotEmpty ? queue.removeAt(0) : Uint8List(0);
          },
          onFinish: () => finishCalls++,
        ),
      );

      final emittedChunks = <List<int>>[];
      var closeCalls = 0;
      final stats = await streamBenchHttpResponse(
        request: request,
        addChunk: emittedChunks.add,
        close: ([List<int>? _]) => closeCalls++,
      );

      expect(reads, 2);
      expect(finishCalls, 1);
      expect(emittedChunks, hasLength(2));
      expect(emittedChunks[0], hasLength(4));
      expect(emittedChunks[1], hasLength(2));
      expect(closeCalls, 1);
      expect(stats.responseMode, BenchHttpStreamResponseMode.synthetic);
      expect(stats.requestBodyDrain, isNot(Duration.zero));
      expect(stats.requestBodyDrainFirstChunkWait, isNotNull);
      expect(stats.requestBodyDrainTailRead, isNotNull);
      expect(stats.requestBodyDrainSecondChunkWait, isNotNull);
      expect(stats.requestBodyDrainRemainingTailRead, isNotNull);
      expect(stats.requestBodyDrainChunkCount, 2);
      expect(stats.emittedChunkCount, 2);
      expect(stats.firstChunkBytes, 4);
      expect(stats.firstChunkQueued, isNotNull);
    },
  );

  test(
    'falls back to copied request bytes when no native body is available',
    () async {
      final request = HttpRequestSnapshot(
        id: 3,
        method: 'POST',
        target: '/bench/stream',
        path: '/bench/stream',
        protocol: 'http/1.1',
        version: 1,
        headers: const {'content-type': 'application/octet-stream'},
        body: Uint8List.fromList([9, 8, 7]),
      );

      final emittedChunks = <List<int>>[];
      var closeCalls = 0;
      final stats = await streamBenchHttpResponse(
        request: request,
        addChunk: emittedChunks.add,
        close: ([List<int>? _]) => closeCalls++,
      );

      expect(emittedChunks, hasLength(1));
      expect(emittedChunks.single, equals(Uint8List.fromList([9, 8, 7])));
      expect(closeCalls, 1);
      expect(stats.responseMode, BenchHttpStreamResponseMode.buffered);
      expect(stats.requestBodyDrain, Duration.zero);
      expect(stats.emittedChunkCount, 1);
      expect(stats.firstChunkBytes, 3);
      expect(stats.firstChunkQueued, isNotNull);
    },
  );

  test('aggregates server-side stream timing diagnostics', () {
    final diagnostics = BenchHttpStreamDiagnostics();
    diagnostics.record(
      response: const BenchHttpStreamResponseStats(
        responseMode: BenchHttpStreamResponseMode.synthetic,
        requestBodyDrain: Duration(milliseconds: 3),
        requestBodyDrainFirstChunkWait: Duration(milliseconds: 1),
        requestBodyDrainTailRead: Duration(milliseconds: 2),
        requestBodyDrainSecondChunkWait: Duration(milliseconds: 1),
        requestBodyDrainRemainingTailRead: Duration(milliseconds: 1),
        requestBodyDrainChunkCount: 4,
        firstChunkQueued: Duration(milliseconds: 7),
        emittedChunkCount: 2,
        firstChunkBytes: 4,
        handlerElapsed: Duration(milliseconds: 11),
      ),
      streamOpened: const Duration(milliseconds: 5),
      firstBodyWrite: const Duration(milliseconds: 9),
      firstBodyWriteCompleted: const Duration(milliseconds: 10),
      directStreamOpenRoundTrip: const Duration(milliseconds: 4),
      directStreamRequestQueueDelay: const Duration(milliseconds: 1),
      directStreamDescriptorOpenCall: const Duration(milliseconds: 2),
      directStreamReplyDeliveryDelay: const Duration(milliseconds: 3),
    );

    expect(diagnostics.toJson(), containsPair('synthetic_responses_total', 1));
    expect(
      diagnostics.toJson(),
      containsPair('headers_to_first_body_write_us_total', 4000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('request_body_drain_first_chunk_wait_us_total', 1000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('request_body_drain_tail_read_us_total', 2000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('request_body_drain_second_chunk_wait_us_total', 1000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('request_body_drain_remaining_tail_read_us_total', 1000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('request_body_drain_chunk_count_total', 4),
    );
    expect(
      diagnostics.toJson(),
      containsPair('queue_to_first_body_write_us_total', 2000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('headers_to_first_body_write_completed_us_total', 5000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('queue_to_first_body_write_completed_us_total', 3000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('first_body_write_call_us_total', 1000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('direct_stream_open_round_trip_us_total', 4000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('direct_stream_request_queue_delay_us_total', 1000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('direct_stream_descriptor_open_call_us_total', 2000),
    );
    expect(
      diagnostics.toJson(),
      containsPair('direct_stream_reply_delivery_delay_us_total', 3000),
    );
  });
}
