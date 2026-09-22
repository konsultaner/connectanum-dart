import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
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
            expect(length, 6);
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
          return Uint8List.fromList([++reads]);
        },
        onFinish: () => finishes++,
      );
      expect(await body.openRead(chunkSize: chunkSize).toList(), [
        [1],
        [2],
        [3],
      ]);
      expect(reads, 3);
      expect(finishes, 1);
    });
  }
}
