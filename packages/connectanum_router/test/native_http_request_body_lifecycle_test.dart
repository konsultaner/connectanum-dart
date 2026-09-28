import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  test('materialized streaming body replays without native rereads', () async {
    var reads = 0;
    var finishes = 0;
    final body = NativeHttpRequestBody.testStreaming(
      length: 0,
      onRead: (_) => ++reads == 1 ? Uint8List.fromList([7, 8]) : Uint8List(0),
      onFinish: () => finishes++,
    );
    final first = body.materializeOwnedBytes();
    expect(first, [7, 8]);
    first[0] = 99;
    expect(body.copy(), [7, 8]);
    for (var replay = 0; replay < 2; replay++) {
      expect(await body.openRead().toList(), [
        [7, 8],
      ]);
    }
    expect(reads, 2);
    expect(finishes, 1);
  });

  for (final materialize in [false, true]) {
    test(
      'read error after initial length is not hidden: $materialize',
      () async {
        final failure = StateError('late body error');
        var reads = 0;
        var finishes = 0;
        final body = NativeHttpRequestBody.testStreaming(
          length: 2,
          onRead: (_) {
            if (++reads == 1) return Uint8List.fromList([1, 2]);
            throw failure;
          },
          onFinish: () => finishes++,
        );
        if (materialize) {
          expect(body.materializeOwnedBytes, throwsA(same(failure)));
        } else {
          final received = <List<int>>[];
          await expectLater(
            body.openRead().forEach(received.add),
            throwsA(same(failure)),
          );
          expect(received, [
            [1, 2],
          ]);
        }
        expect(reads, 2);
        expect(finishes, 1);
      },
    );
  }
  for (final finishFirst in [false, true]) {
    test(
      'empty streaming body is not read after finish: $finishFirst',
      () async {
        var reads = 0;
        var finishes = 0;
        final body = NativeHttpRequestBody.testStreaming(
          length: 0,
          onRead: (_) {
            reads++;
            return Uint8List(0);
          },
          onFinish: () => finishes++,
        );
        if (finishFirst) body.finish();
        expect(body.materializeOwnedBytes(), isEmpty);
        expect(body.copy(), isEmpty);
        expect(await body.openRead().toList(), isEmpty);
        expect(reads, finishFirst ? 0 : 1);
        expect(finishes, 1);
      },
    );
  }
  for (final initialLength in [0, 2, 4]) {
    for (final materialize in [false, true]) {
      test(
        'stream drains beyond initial length $initialLength: $materialize',
        () async {
          var reads = 0;
          var finishes = 0;
          final chunks = [
            Uint8List.fromList([1, 2]),
            Uint8List.fromList([3, 4, 5]),
            Uint8List(0),
          ];
          final body = NativeHttpRequestBody.testStreaming(
            length: initialLength,
            onRead: (_) => chunks[reads++],
            onFinish: () => finishes++,
          );
          final actual = materialize
              ? body.materializeOwnedBytes()
              : (await body.openRead().toList()).expand((chunk) => chunk);
          expect(actual, [1, 2, 3, 4, 5]);
          expect(reads, 3);
          expect(finishes, 1);
          body.finish();
          expect(finishes, 1);
        },
      );
    }
  }
  test('cancelling after a chunk finishes without reading the rest', () async {
    var reads = 0;
    var finishes = 0;
    final body = NativeHttpRequestBody.testStreaming(
      length: 6,
      onRead: (size) {
        expect(size, 2);
        reads++;
        return Uint8List.fromList([11, 12]);
      },
      onFinish: () => finishes++,
    );
    expect(await body.openRead(chunkSize: 2).take(1).toList(), [
      [11, 12],
    ]);
    expect(reads, 1);
    expect(finishes, 1);
    body.finish();
    expect(finishes, 1);
  });

  test('a consumer failure finishes the source before propagating', () async {
    final failure = StateError('consumer failed');
    var finishes = 0;
    final body = NativeHttpRequestBody.testStreaming(
      length: 6,
      onRead: (_) => Uint8List.fromList([11, 12]),
      onFinish: () => finishes++,
    );
    Future<void> consume() async {
      await for (final chunk in body.openRead(chunkSize: 2)) {
        expect(chunk, [11, 12]);
        throw failure;
      }
    }

    await expectLater(consume(), throwsA(same(failure)));
    expect(finishes, 1);
  });

  for (final consumerThrows in [false, true]) {
    test('cancellation cleanup is best effort: $consumerThrows', () async {
      final failure = StateError('consumer failed');
      var reads = 0;
      var finishes = 0;
      final body = NativeHttpRequestBody.testStreaming(
        length: 6,
        onRead: (_) {
          reads++;
          return Uint8List.fromList([11, 12]);
        },
        onFinish: () {
          finishes++;
          throw StateError('cleanup failed');
        },
      );
      if (consumerThrows) {
        Future<void> consume() async {
          await for (final chunk in body.openRead(chunkSize: 2)) {
            expect(chunk, [11, 12]);
            throw failure;
          }
        }

        await expectLater(consume(), throwsA(same(failure)));
      } else {
        final reader = StreamIterator(body.openRead(chunkSize: 2));
        expect(await reader.moveNext(), isTrue);
        expect(reader.current, [11, 12]);
        await reader.cancel();
      }
      expect(reads, 1);
      expect(finishes, 1);
      body.finish();
      expect(finishes, 1);
    });
  }

  for (final materialize in [false, true]) {
    for (final cleanupFails in [false, true]) {
      test(
        'read failure finishes and remains primary: '
        'materialize=$materialize cleanupFails=$cleanupFails',
        () async {
          final failure = StateError('read failed');
          var reads = 0;
          var finishes = 0;
          final body = NativeHttpRequestBody.testStreaming(
            length: 6,
            onRead: (_) {
              if (++reads == 2) throw failure;
              return Uint8List.fromList([21, 22]);
            },
            onFinish: () {
              finishes++;
              if (cleanupFails) throw StateError('cleanup failed');
            },
          );
          if (materialize) {
            expect(body.materializeOwnedBytes, throwsA(same(failure)));
          } else {
            final received = <List<int>>[];
            await expectLater(
              body.openRead(chunkSize: 2).forEach(received.add),
              throwsA(same(failure)),
            );
            expect(received, [
              [21, 22],
            ]);
          }
          expect(reads, 2);
          expect(finishes, 1);
          body.finish();
          expect(finishes, 1);
        },
      );
    }
  }

  for (final (materialize, length) in [
    (false, 0),
    (false, 6),
    (true, 0),
    (true, 6),
  ]) {
    test(
      'normal completion reports finish failure: $materialize/$length',
      () async {
        final failure = StateError('finish failed');
        var finishes = 0;
        var failFinish = true;
        final body = NativeHttpRequestBody.testStreaming(
          length: length,
          onRead: (_) {
            return Uint8List(0);
          },
          onFinish: () {
            finishes++;
            if (failFinish) throw failure;
          },
        );
        if (materialize) {
          expect(body.materializeOwnedBytes, throwsA(same(failure)));
        } else {
          await expectLater(body.openRead().toList(), throwsA(same(failure)));
        }
        expect(finishes, 1);
        failFinish = false;
        body.finish();
        expect(finishes, 2);
        body.finish();
        expect(finishes, 2);
      },
    );
  }

  for (final materialize in [false, true]) {
    test('early EOF retains only received bytes: $materialize', () async {
      var reads = 0;
      var finishes = 0;
      final body = NativeHttpRequestBody.testStreaming(
        length: 6,
        onRead: (_) =>
            ++reads == 1 ? Uint8List.fromList([31, 32]) : Uint8List(0),
        onFinish: () => finishes++,
      );
      final actual = materialize
          ? body.materializeOwnedBytes()
          : (await body.openRead(chunkSize: 2).toList()).expand(
              (chunk) => chunk,
            );
      expect(actual, [31, 32]);
      expect(reads, 2);
      expect(finishes, 1);
    });
  }

  for (final chunkSize in [0, -4]) {
    test('nonpositive chunk size still makes progress: $chunkSize', () async {
      var reads = 0;
      var finishes = 0;
      final body = NativeHttpRequestBody.testStreaming(
        length: 3,
        onRead: (size) {
          expect(size, 1);
          reads++;
          return reads <= 3 ? Uint8List.fromList([reads]) : Uint8List(0);
        },
        onFinish: () => finishes++,
      );
      expect(await body.openRead(chunkSize: chunkSize).toList(), [
        [1],
        [2],
        [3],
      ]);
      expect(reads, 4);
      expect(finishes, 1);
    });
  }
}
