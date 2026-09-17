import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_bench/src/http_stream_handler.dart';
import 'package:connectanum_router/connectanum_router.dart' hide Invocation;
import 'package:test/test.dart';

HttpRequestSnapshot _request({
  Map<String, String> headers = const {},
  Uint8List? body,
  NativeHttpRequestBody? nativeBody,
  bool copyBody = true,
}) => HttpRequestSnapshot(
  id: 1,
  method: 'POST',
  target: '/bench/stream',
  path: '/bench/stream',
  protocol: 'http/1.1',
  version: 1,
  headers: headers,
  body: body,
  nativeBody: nativeBody,
  copyBody: copyBody,
);

// Exercises the public streaming body contract, including empty async chunks.
// Unexpected materialization or native handle access fails via noSuchMethod.
class _StreamBody implements NativeHttpRequestBody {
  _StreamBody(this.length, this.stream);
  @override
  final int length;
  final Stream<List<int>> stream;
  var opens = 0;

  @override
  Stream<List<int>> openRead({int chunkSize = 64 * 1024}) {
    opens++;
    return stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _expectTiming(BenchHttpStreamResponseStats stats) {
  expect(stats.firstChunkQueued, isNotNull);
  expect(stats.firstChunkQueued, greaterThanOrEqualTo(Duration.zero));
  expect(stats.handlerElapsed, greaterThanOrEqualTo(stats.firstChunkQueued!));
}

void main() {
  group('benchmark header and pattern contracts', () {
    test(
      'matches header names case-insensitively and ignores unrelated keys',
      () {
        expect(
          parseBenchHeaderInt({
            'other': '99',
            'X-Bench-Response-Bytes': '17',
          }, 'x-BENCH-response-BYTES'),
          17,
        );
        expect(parseBenchHeaderInt({'other': '17'}, 'missing'), isNull);
        expect(parseBenchHeaderInt({}, 'missing'), isNull);
        expect(
          parseBenchHeaderInt({'SIZE': '3', 'size': '7'}, 'size'),
          3,
        );
      },
    );

    const inputs = <String, int?>{
      '0': 0,
      '-7': -7,
      '+17': 17,
      ' 42 ': 42,
      '0xff': 255,
      '': null,
      'abc': null,
      '1.5': null,
      '1e3': null,
      '1,2': null,
      'NaN': null,
      '99999999999999999999999999999999999': null,
    };
    for (final entry in inputs.entries) {
      test('integer header ${entry.key}', () {
        expect(parseBenchHeaderInt({'size': entry.key}, 'size'), entry.value);
      });
    }

    for (final length in [0, 1, 8, 9, 255, 256, 257, 65537]) {
      test('pattern bytes length $length', () {
        final bytes = buildPatternChunk(length);
        expect(bytes, hasLength(length));
        var expectedByte = 0;
        for (final byte in bytes) {
          expect(byte, expectedByte);
          expectedByte = (expectedByte + 31) % 256;
        }
        if (bytes.isNotEmpty) {
          bytes[0] = 255;
          expect(buildPatternChunk(length)[0], 0);
        }
      });
    }
    test('negative pattern size is rejected', () {
      expect(() => buildPatternChunk(-1), throwsArgumentError);
    });
  });

  group('synthetic response boundaries', () {
    for (final responseBytes in [1, 3, 4, 5, 9]) {
      for (final requestedChunk in <int?>[null, -1, 0, 1, 2, 3, 4, 6, 8]) {
        test('$responseBytes bytes with chunk $requestedChunk', () async {
          final body = Uint8List.fromList([99, 98, 97]);
          final chunks = <List<int>>[];
          var closes = 0;
          var emittedBytes = 0;
          final stats = await streamBenchHttpResponse(
            request: _request(
              body: body,
              headers: {
                'X-Bench-Response-Bytes': '$responseBytes',
                if (requestedChunk != null)
                  'X-Bench-Response-Chunk-Bytes': '$requestedChunk',
              },
            ),
            addChunk: (chunk) {
              emittedBytes += chunk.length;
              expect(
                emittedBytes,
                lessThanOrEqualTo(responseBytes),
                reason:
                    'Synthetic output must never exceed the requested byte budget',
              );
              chunks.add(chunk);
            },
            close: ([finalChunk]) {
              expect(finalChunk, isNull);
              closes++;
            },
          );
          final chunkSize = requestedChunk == null
              ? 3
              : requestedChunk < 1
              ? 1
              : requestedChunk;
          final expectedLengths = <int>[];
          var remaining = responseBytes;
          while (remaining != 0) {
            final count = remaining < chunkSize ? remaining : chunkSize;
            expectedLengths.add(count);
            remaining -= count;
          }
          expect(chunks.map((chunk) => chunk.length), expectedLengths);
          for (final chunk in chunks) {
            expect(chunk, List.generate(chunk.length, (i) => (i * 31) % 256));
          }
          expect(chunks.expand((chunk) => chunk), hasLength(responseBytes));
          expect(body, [99, 98, 97]);
          expect(closes, 1);
          expect(stats.responseMode, BenchHttpStreamResponseMode.synthetic);
          expect(stats.emittedChunkCount, expectedLengths.length);
          expect(stats.firstChunkBytes, expectedLengths.first);
          expect(stats.requestBodyDrainChunkCount, 0);
          expect(stats.requestBodyDrainFirstChunkWait, isNull);
          expect(stats.requestBodyDrainTailRead, isNull);
          expect(stats.requestBodyDrainSecondChunkWait, isNull);
          expect(stats.requestBodyDrainRemainingTailRead, isNull);
          _expectTiming(stats);
        });
      }
    }

    for (final requestLength in [0, 1, 65535, 65536, 65537]) {
      test('default chunk cap for request length $requestLength', () async {
        final chunks = <List<int>>[];
        final responseLength = requestLength == 0 ? 3 : 65537;
        await streamBenchHttpResponse(
          request: _request(
            body: Uint8List(requestLength),
            headers: {'x-bench-response-bytes': '$responseLength'},
          ),
          addChunk: chunks.add,
          close: ([finalChunk]) {},
        );
        final expectedSize = requestLength == 0
            ? 1
            : requestLength > 65536
            ? 65536
            : requestLength;
        expect(chunks.first.length, expectedSize);
        expect(chunks.length, (responseLength / expectedSize).ceil());
        expect(chunks.expand((chunk) => chunk), hasLength(responseLength));
      });
    }
  });

  for (final responseHeader in <String?>[null, '0', '-1', 'invalid']) {
    for (final bodyKind in [
      'absent',
      'empty',
      'buffered',
      'borrowed',
      'native',
    ]) {
      test('echo $bodyKind with response header $responseHeader', () async {
        final backing = Uint8List.fromList([99, 11, 22, 33, 98]);
        final payload = Uint8List.sublistView(backing, 1, 4);
        final chunks = <List<int>>[];
        var closes = 0;
        final request = _request(
          headers: {
            'x-bench-response-bytes': ?responseHeader,
            'x-bench-response-chunk-bytes': 'invalid',
          },
          body: bodyKind == 'empty'
              ? Uint8List(0)
              : bodyKind == 'buffered' || bodyKind == 'borrowed'
              ? payload
              : null,
          nativeBody: bodyKind == 'native'
              ? NativeHttpRequestBody.synthetic(payload)
              : null,
          copyBody: bodyKind != 'borrowed',
        );
        final stats = await streamBenchHttpResponse(
          request: request,
          addChunk: chunks.add,
          close: ([finalChunk]) => closes++,
        );
        expect(chunks, [
          bodyKind == 'absent' || bodyKind == 'empty'
              ? [98, 101, 110, 99, 104]
              : [11, 22, 33],
        ]);
        if (bodyKind == 'borrowed' || bodyKind == 'native') {
          expect(chunks.single, same(payload));
          chunks.single[0] = 77;
          expect(backing, [99, 77, 22, 33, 98]);
        } else if (bodyKind == 'buffered') {
          expect(chunks.single, same(request.body));
          expect(chunks.single, isNot(same(payload)));
          chunks.single[0] = 77;
          expect(request.body, [77, 22, 33]);
          expect(backing, [99, 11, 22, 33, 98]);
        }
        expect(
          stats.responseMode,
          bodyKind == 'native'
              ? BenchHttpStreamResponseMode.nativeForwarded
              : BenchHttpStreamResponseMode.buffered,
        );
        expect(stats.requestBodyDrain, Duration.zero);
        expect(stats.requestBodyDrainChunkCount, 0);
        expect(stats.requestBodyDrainFirstChunkWait, isNull);
        expect(stats.requestBodyDrainTailRead, isNull);
        expect(stats.requestBodyDrainSecondChunkWait, isNull);
        expect(stats.requestBodyDrainRemainingTailRead, isNull);
        expect(stats.emittedChunkCount, 1);
        expect(stats.firstChunkBytes, chunks.single.length);
        expect(closes, 1);
        _expectTiming(stats);
      });
    }
  }

  for (final synthetic in [false, true]) {
    for (final count in [0, 1, 2, 3]) {
      test(
        'drain/forward $count nonempty chunks, synthetic=$synthetic',
        () async {
          final payloads = List.generate(
            count,
            (i) => Uint8List.fromList([i + 1]),
          );
          final events = <String>[];
          final body = _StreamBody(count, () async* {
            events.add('open');
            yield Uint8List(0);
            for (final payload in payloads) {
              yield payload;
              yield Uint8List(0);
            }
            events.add('drained');
          }());
          final chunks = <List<int>>[];
          final stats = await streamBenchHttpResponse(
            request: _request(
              nativeBody: body,
              headers: {
                if (synthetic) 'x-bench-response-bytes': '2',
              },
            ),
            addChunk: (chunk) {
              events.add('write');
              chunks.add(chunk);
            },
            close: ([finalChunk]) => events.add('close'),
          );
          expect(body.opens, 1);
          expect(events.first, 'open');
          expect(events.last, 'close');
          if (synthetic) {
            expect(
              events.indexOf('drained'),
              lessThan(events.indexOf('write')),
            );
            expect(stats.requestBodyDrainChunkCount, count);
            expect(
              stats.requestBodyDrainFirstChunkWait,
              count == 0 ? isNull : isNotNull,
            );
            expect(
              stats.requestBodyDrainTailRead,
              count == 0 ? isNull : isNotNull,
            );
            expect(
              stats.requestBodyDrainSecondChunkWait,
              count < 2 ? isNull : isNotNull,
            );
            expect(
              stats.requestBodyDrainRemainingTailRead,
              count < 2 ? isNull : isNotNull,
            );
            if (count > 0) {
              expect(
                stats.requestBodyDrainFirstChunkWait! +
                    stats.requestBodyDrainTailRead!,
                stats.requestBodyDrain,
              );
            }
            if (count > 1) {
              expect(
                stats.requestBodyDrainFirstChunkWait! +
                    stats.requestBodyDrainSecondChunkWait! +
                    stats.requestBodyDrainRemainingTailRead!,
                stats.requestBodyDrain,
              );
            }
          } else if (count == 0) {
            expect(chunks.single, [98, 101, 110, 99, 104]);
            expect(stats.firstChunkBytes, 5);
          } else {
            expect(
              events.indexOf('write'),
              lessThan(events.indexOf('drained')),
            );
            expect(chunks, hasLength(count));
            for (var i = 0; i < count; i++) {
              expect(chunks[i], same(payloads[i]));
            }
          }
          expect(stats.emittedChunkCount, chunks.length);
          expect(stats.firstChunkBytes, chunks.first.length);
          _expectTiming(stats);
        },
      );
    }

    test(
      'read failure does not close successfully, synthetic=$synthetic',
      () async {
        final failure = StateError('read failure');
        final body = _StreamBody(3, Stream.error(failure));
        var writes = 0;
        var closes = 0;
        await expectLater(
          streamBenchHttpResponse(
            request: _request(
              nativeBody: body,
              headers: {
                if (synthetic) 'x-bench-response-bytes': '2',
              },
            ),
            addChunk: (_) => writes++,
            close: ([finalChunk]) => closes++,
          ),
          throwsA(same(failure)),
        );
        expect(body.opens, 1);
        expect(writes, 0);
        expect(closes, 0);
      },
    );
  }

  for (final mode in ['synthetic', 'native', 'buffered']) {
    for (final failingCallback in ['write', 'close']) {
      test('$mode propagates $failingCallback failure', () async {
        final failure = StateError('$failingCallback failed');
        var writes = 0;
        var closes = 0;
        final request = _request(
          headers: {if (mode == 'synthetic') 'x-bench-response-bytes': '3'},
          body: mode == 'native' ? null : Uint8List.fromList([1]),
          nativeBody: mode == 'native'
              ? NativeHttpRequestBody.synthetic(Uint8List.fromList([2]))
              : null,
        );
        await expectLater(
          streamBenchHttpResponse(
            request: request,
            addChunk: (_) {
              writes++;
              if (failingCallback == 'write') throw failure;
            },
            close: ([finalChunk]) {
              closes++;
              throw failure;
            },
          ),
          throwsA(same(failure)),
        );
        expect(
          writes,
          failingCallback == 'close' && mode == 'synthetic' ? 3 : 1,
        );
        expect(closes, failingCallback == 'close' ? 1 : 0);
      });
    }
  }

  test(
    'interleaved requests cannot mix chunks or response accounting',
    () async {
      final a = StreamController<List<int>>();
      final b = StreamController<List<int>>();
      final aFirst = Completer<void>();
      final bFirst = Completer<void>();
      final aChunks = <List<int>>[];
      final bChunks = <List<int>>[];
      var aCloses = 0;
      var bCloses = 0;
      addTearDown(() async {
        await a.close();
        await b.close();
      });
      final aResult = streamBenchHttpResponse(
        request: _request(nativeBody: _StreamBody(3, a.stream)),
        addChunk: (chunk) {
          aChunks.add(chunk);
          if (!aFirst.isCompleted) aFirst.complete();
        },
        close: ([finalChunk]) => aCloses++,
      );
      final bResult = streamBenchHttpResponse(
        request: _request(nativeBody: _StreamBody(5, b.stream)),
        addChunk: (chunk) {
          bChunks.add(chunk);
          if (!bFirst.isCompleted) bFirst.complete();
        },
        close: ([finalChunk]) => bCloses++,
      );
      a.add([1]);
      await aFirst.future;
      b.add([7, 8, 9, 10, 11]);
      await bFirst.future;
      expect(aCloses, 0);
      expect(bCloses, 0);
      await b.close();
      final bStats = await bResult;
      expect(bCloses, 1);
      expect(aCloses, 0);
      a.add([2, 3]);
      await a.close();
      final aStats = await aResult;
      expect(aChunks, [
        [1],
        [2, 3],
      ]);
      expect(bChunks, [
        [7, 8, 9, 10, 11],
      ]);
      expect((aStats.emittedChunkCount, aStats.firstChunkBytes), (2, 1));
      expect((bStats.emittedChunkCount, bStats.firstChunkBytes), (1, 5));
      expect(aCloses, 1);
    },
  );

  test('drain timing anchors the second chunk, not the last chunk', () async {
    var thirdChunkDelay = Duration.zero;
    final body = _StreamBody(3, () async* {
      yield [1];
      yield [2];
      // Resuming the producer means the consumer processed the second chunk.
      final afterSecond = Stopwatch()..start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      thirdChunkDelay = afterSecond.elapsed;
      yield [3];
    }());
    final stats = await streamBenchHttpResponse(
      request: _request(
        nativeBody: body,
        headers: {
          'x-bench-response-bytes': '1',
        },
      ),
      addChunk: (_) {},
      close: ([finalChunk]) {},
    );
    expect(stats.requestBodyDrainChunkCount, 3);
    expect(
      stats.requestBodyDrainRemainingTailRead,
      greaterThanOrEqualTo(thirdChunkDelay),
    );
    expect(
      stats.requestBodyDrainFirstChunkWait! +
          stats.requestBodyDrainSecondChunkWait! +
          stats.requestBodyDrainRemainingTailRead!,
      stats.requestBodyDrain,
    );
  });

  test('write failure cancels its source subscription', () async {
    var cancellations = 0;
    var closes = 0;
    final controller = StreamController<List<int>>(
      onCancel: () => cancellations++,
    );
    addTearDown(controller.close);
    final failure = StateError('writer disconnected');
    final expectation = expectLater(
      streamBenchHttpResponse(
        request: _request(nativeBody: _StreamBody(3, controller.stream)),
        addChunk: (_) => throw failure,
        close: ([finalChunk]) => closes++,
      ),
      throwsA(same(failure)),
    );
    controller.add([1]);
    await expectation;
    expect(cancellations, 1);
    expect(closes, 0);
  });
}
