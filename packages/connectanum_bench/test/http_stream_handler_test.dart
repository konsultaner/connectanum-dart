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
      await streamBenchHttpResponse(
        request: request,
        addChunk: emittedChunks.add,
        close: ([List<int>? _]) => closeCalls++,
      );

      expect(emittedChunks, hasLength(2));
      expect(identical(emittedChunks[0], firstChunk), isTrue);
      expect(identical(emittedChunks[1], secondChunk), isTrue);
      expect(closeCalls, 1);
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
      await streamBenchHttpResponse(
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
      await streamBenchHttpResponse(
        request: request,
        addChunk: emittedChunks.add,
        close: ([List<int>? _]) => closeCalls++,
      );

      expect(emittedChunks, hasLength(1));
      expect(emittedChunks.single, equals(Uint8List.fromList([9, 8, 7])));
      expect(closeCalls, 1);
    },
  );
}
