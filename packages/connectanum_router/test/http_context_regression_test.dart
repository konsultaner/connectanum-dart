import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/invocation.dart';
import 'package:connectanum_core/src/message/yield.dart';
import 'package:connectanum_router/src/router/http/http_context.dart';
import 'package:test/test.dart';

Map<String, Object?> _response(String kind, Object? body, {String? encoding}) =>
    {
      HttpInvocationKeys.requestId: 37,
      'status': 207,
      'headers': <String, String>{'x-response': 'yes'},
      HttpInvocationKeys.responseBodyKind: kind,
      HttpInvocationKeys.responseBody: body,
      HttpInvocationKeys.responseBodyEncoding: ?encoding,
    };

Invocation _invocation({int requestId = 37, int invocationId = 83}) =>
    Invocation(
      invocationId,
      91,
      InvocationDetails(null, 'com.example.http', true)
        ..custom.addAll({
          HttpInvocationKeys.requestId: requestId,
          HttpInvocationKeys.request: {
            'id': requestId,
            'method': 'POST',
            'target': '/tasks?q=one',
            'path': '/tasks',
            'query': 'q=one',
            'protocol': 'http/1.1',
            'version': 1,
            'headers': <String, String>{'x-request': 'yes'},
            'body': <int>[0, 128, 255],
          },
        }),
    );

void _expectChunk(Yield message, List<int>? bytes, {required bool progress}) {
  expect(message.invocationRequestId, 83);
  expect(message.options?.progress ?? false, progress);
  expect(message.arguments, isNull);
  expect(message.argumentsKeywords, {
    HttpInvocationKeys.requestId: 37,
    'status': 206,
    'headers': {'x-stream': 'original'},
    HttpInvocationKeys.responseBodyKind: 'bytes',
    HttpInvocationKeys.responseBody: bytes,
    'progress': progress,
  });
}

void main() {
  group('HTTP payload byte encoding', () {
    for (final kind in ['bytes', 'text']) {
      test('$kind absent body encodes to empty bytes', () {
        final payload = HttpResponsePayload.fromKeywordArguments(
          _response(kind, null),
        )!;
        expect(payload.encodeBodyBytes(), isEmpty);
        expect(payload.requestId, 37);
        expect(payload.status, 207);
        expect(payload.headers, {'x-response': 'yes'});
      });
    }

    for (final entry in <String, List<int>>{
      'latin1': [233],
      'utf8': [195, 169],
      'not-an-encoding': [195, 169],
    }.entries) {
      test('text uses ${entry.key} or UTF-8 fallback', () {
        final payload = HttpResponsePayload.fromKeywordArguments(
          _response('text', '\u00e9', encoding: entry.key),
        )!;
        expect(payload.encodeBodyBytes(), entry.value);
        expect(
          payload.toKeywordArguments(),
          _response('text', '\u00e9', encoding: entry.key)
            ..['progress'] = false,
        );
      });
    }

    test('unspecified encoding defaults to UTF-8', () {
      final payload = HttpResponsePayload.fromKeywordArguments(
        _response('text', '\u00e9'),
      )!;
      expect(payload.encodeBodyBytes(), [195, 169]);
      expect(
        payload.toKeywordArguments()[HttpInvocationKeys.responseBodyEncoding],
        'utf8',
      );
    });

    test('List<int> bytes round trip without aliasing encoded output', () {
      final input = <int>[0, 127, 128, 255];
      final payload = HttpResponsePayload.fromKeywordArguments(
        _response('bytes', input),
      )!;
      input[0] = 55;
      final first = payload.encodeBodyBytes()!;
      expect(first, [0, 127, 128, 255]);
      first[1] = 44;
      expect(payload.encodeBodyBytes(), [0, 127, 128, 255]);
      expect(payload.bodyBytes, [0, 127, 128, 255]);
    });

    test(
      'bytes utility copies caller buffer and encoder copies stored bytes',
      () {
        final input = Uint8List.fromList([1, 128, 255]);
        final payload = HttpResponseUtil.bytes(
          requestId: 37,
          status: 207,
          body: input,
        );
        input[0] = 99;
        expect(payload.encodeBodyBytes(), [1, 128, 255]);
        final encoded = payload.encodeBodyBytes()!..[1] = 22;
        expect(encoded, [1, 22, 255]);
        expect(payload.bodyBytes, [1, 128, 255]);
      },
    );

    test('JSON encoding preserves UTF-8 and null as JSON', () {
      expect(
        HttpResponseUtil.json(
          requestId: 37,
          status: 207,
          body: {'v': '\u00e9'},
        ).encodeBodyBytes(),
        [123, 34, 118, 34, 58, 34, 195, 169, 34, 125],
      );
      expect(
        HttpResponseUtil.json(
          requestId: 37,
          status: 207,
          body: null,
        ).encodeBodyBytes(),
        [110, 117, 108, 108],
      );
    });

    test('file remains a descriptor instead of reading filesystem bytes', () {
      final payload = HttpResponseUtil.file(
        requestId: 37,
        status: 207,
        path: '/not-opened/response.bin',
      );
      expect(payload.encodeBodyBytes(), isNull);
      expect(payload.toKeywordArguments(), {
        HttpInvocationKeys.requestId: 37,
        'status': 207,
        'headers': <String, String>{},
        HttpInvocationKeys.responseBodyKind: 'file',
        HttpInvocationKeys.responseFilePath: '/not-opened/response.bin',
        'progress': false,
      });
    });

    for (final invalid in <Object>[
      'not bytes',
      7,
      <Object>[1, 'two'],
    ]) {
      test('rejects nonbinary byte payload $invalid', () {
        expect(
          HttpResponsePayload.fromKeywordArguments(_response('bytes', invalid)),
          isNull,
        );
      });
    }

    test(
      'request snapshot converts List<int> without aliasing caller bytes',
      () {
        final invocation = _invocation();
        final context = HttpInvocationContext.maybeFromInvocation(invocation)!;
        final raw =
            invocation.details.custom[HttpInvocationKeys.request] as Map;
        (raw['body'] as List<int>)[0] = 77;
        expect(context.request.body, [0, 128, 255]);
        expect(context.request.method, 'POST');
        expect(context.request.path, '/tasks');
        expect(context.request.query, 'q=one');
        expect(context.request.headers, {'x-request': 'yes'});
        expect(context.requestId, 37);
      },
    );
  });

  group('HTTP fallback response streams', () {
    test(
      'callbacks surround first yield exactly once; chunks stay ordered',
      () async {
        final invocation = _invocation();
        final context = HttpInvocationContext.maybeFromInvocation(invocation)!;
        final events = <String>[];
        final messages = <Yield>[];
        invocation.onResponse((message) {
          events.add('yield');
          messages.add(message as Yield);
        });
        final headers = {'x-stream': 'original'};
        final stream = context.streamResponse(
          status: 206,
          headers: headers,
          onStreamOpened: () => events.add('opened'),
          onFirstBodyWrite: () => events.add('write'),
          onFirstBodyWriteCompleted: () => events.add('written'),
          onDirectStreamOpenRoundTrip: (_) =>
              fail('No direct stream requested'),
        );
        headers['x-stream'] = 'changed';
        expect(
          () => stream.headers['x-stream'] = 'changed',
          throwsUnsupportedError,
        );
        expect(stream.isClosed, isFalse);
        var doneCount = 0;
        final done = stream.done;
        done.then((_) => doneCount++);
        expect(stream.done, same(done));
        stream.add([]);
        expect(events, isEmpty);
        expect(messages, isEmpty);
        expect(doneCount, 0);

        final firstChunk = [0, 128, 255];
        stream.add(firstChunk);
        firstChunk[0] = 99;
        expect(events, ['opened', 'write', 'yield', 'written']);
        stream.add(Uint8List.fromList([42]));
        expect(events, ['opened', 'write', 'yield', 'written', 'yield']);
        expect(messages, hasLength(2));
        _expectChunk(messages[0], [0, 128, 255], progress: true);
        _expectChunk(messages[1], [42], progress: true);
        expect(invocation.responseClosed, isFalse);
        expect(doneCount, 0);

        stream.close([9, 8]);
        expect(stream.isClosed, isTrue);
        expect(invocation.responseClosed, isTrue);
        expect(messages, hasLength(3));
        _expectChunk(messages[2], [9, 8], progress: false);
        await Future<void>.value();
        expect(doneCount, 1);
        stream.close([100]);
        expect(messages, hasLength(3));
        expect(doneCount, 1);
        expect(() => stream.add([1]), throwsStateError);
        expect(() => stream.add([]), throwsStateError);
        expect(events, [
          'opened',
          'write',
          'yield',
          'written',
          'yield',
          'yield',
        ]);
      },
    );

    for (final (finalChunk, expected) in <(List<int>?, List<int>?)>[
      (null, null),
      ([], null),
      ([4, 5], [4, 5]),
      (Uint8List.fromList([6]), [6]),
    ]) {
      test(
        'close before add delivers exactly one final response $finalChunk',
        () async {
          final invocation = _invocation();
          final messages = <Yield>[];
          invocation.onResponse((message) => messages.add(message as Yield));
          final stream = HttpInvocationContext.maybeFromInvocation(
            invocation,
          )!.streamResponse(status: 206, headers: {'x-stream': 'original'});
          var doneCount = 0;
          stream.done.then((_) => doneCount++);
          stream.close(finalChunk);
          expect(stream.isClosed, isTrue);
          expect(messages, hasLength(1));
          _expectChunk(
            messages.single,
            expected,
            progress: false,
          );
          await Future<void>.value();
          expect(doneCount, 1);
          stream.close();
          expect(messages, hasLength(1));
        },
      );
    }

    test(
      'callbacks are optional for nonempty progress and final yields',
      () async {
        final invocation = _invocation();
        final messages = <Yield>[];
        invocation.onResponse((message) => messages.add(message as Yield));
        final stream = HttpInvocationContext.maybeFromInvocation(
          invocation,
        )!.streamResponse(status: 206, headers: {'x-stream': 'original'});
        var doneCount = 0;
        stream.done.then((_) => doneCount++);
        stream.add([1]);
        stream.add([2]);
        stream.close();
        await Future<void>.value();
        expect(doneCount, 1);
        expect(messages, hasLength(3));
        _expectChunk(messages[0], [1], progress: true);
        _expectChunk(messages[1], [2], progress: true);
        _expectChunk(messages[2], null, progress: false);
      },
    );
  });

  group('HTTP stream descriptor failure recovery', () {
    test(
      'concurrent descriptor replies cannot cross response streams',
      () async {
        final control = ReceivePort();
        addTearDown(control.close);
        final requests = control.take(2).cast<Map>().toList();
        final responses = <int, List<Yield>>{};
        final completed = <Future<void>>[];
        final queueDelays = <int, List<Duration>>{};
        for (final id in [201, 202]) {
          final invocation = _invocation(
            requestId: id,
            invocationId: id + 1000,
          );
          invocation.details.custom[HttpInvocationKeys
                  .responseStreamControlPort] =
              control.sendPort;
          final messages = responses[id] = <Yield>[];
          final finalResponse = Completer<void>();
          completed.add(finalResponse.future);
          invocation.onResponse((message) {
            final yielded = message as Yield;
            messages.add(yielded);
            if (yielded.options?.progress != true) finalResponse.complete();
          });
          final delays = queueDelays[id] = <Duration>[];
          final stream = HttpInvocationContext.maybeFromInvocation(invocation)!
              .streamResponse(
                status: id,
                onDirectStreamRequestQueueDelay: delays.add,
              );
          stream.add([id]);
          stream.close([id + 1]);
        }
        final pending = await requests;
        expect(pending, hasLength(2));
        expect(
          pending.map((request) => request['requestId']),
          unorderedEquals([201, 202]),
        );
        expect(
          pending.map((request) => request['replyRequestId']).toSet(),
          hasLength(2),
        );
        expect(responses.values, everyElement(isEmpty));
        for (final request in pending.reversed) {
          (request['replyPort'] as SendPort).send({
            'replyRequestId': request['replyRequestId'],
            'handle': 1,
            'libraryPath': 42,
            'requestQueueDelayUs': request['requestId'],
          });
        }
        await Future.wait(completed);
        for (final id in [201, 202]) {
          final messages = responses[id]!;
          expect(messages, hasLength(2));
          expect(messages.map((message) => message.invocationRequestId), [
            id + 1000,
            id + 1000,
          ]);
          expect(
            messages.map((message) => message.options?.progress ?? false),
            [true, false],
          );
          expect(
            messages.map(
              (message) =>
                  message.argumentsKeywords![HttpInvocationKeys.requestId],
            ),
            [id, id],
          );
          expect(
            messages.map((message) => message.argumentsKeywords!['status']),
            [id, id],
          );
          expect(
            messages.map(
              (message) =>
                  message.argumentsKeywords![HttpInvocationKeys.responseBody],
            ),
            [
              [id],
              [id + 1],
            ],
          );
          expect(queueDelays[id], [Duration(microseconds: id)]);
        }
      },
    );

    for (final (name, descriptor, timingExpected)
        in <(String, Map<String, Object?>, bool)>[
          ('unavailable', {'handle': 0}, false),
          ('missing handle', {}, false),
          ('wrong handle type', {'handle': '1'}, false),
          (
            'malformed descriptor with valid timings',
            {
              'handle': 1,
              'libraryPath': 42,
              'requestQueueDelayUs': 17,
              'descriptorOpenUs': 23,
              'replySentAtUs': 0,
            },
            true,
          ),
          (
            'malformed descriptor with rejected timings',
            {
              'handle': 1,
              'libraryPath': 42,
              'requestQueueDelayUs': -1,
              'descriptorOpenUs': '23',
              'replySentAtUs': 8640000000000000000,
            },
            false,
          ),
        ]) {
      test('$name falls back without losing queued or final chunks', () async {
        final control = ReceivePort();
        addTearDown(control.close);
        final requests = <Map>[];
        control.listen((dynamic message) {
          final request = message as Map;
          requests.add(request);
          (request['replyPort'] as SendPort).send({
            'replyRequestId': request['replyRequestId'],
            ...descriptor,
          });
        });
        final invocation = _invocation();
        invocation.details.custom[HttpInvocationKeys
                .responseStreamControlPort] =
            control.sendPort;
        final messages = <Yield>[];
        final finalResponse = Completer<void>();
        invocation.onResponse((message) {
          final yielded = message as Yield;
          messages.add(yielded);
          if (yielded.options?.progress != true) finalResponse.complete();
        });
        final callbacks = <String>[];
        final roundTrips = <Duration>[];
        final queueDelays = <Duration>[];
        final openDurations = <Duration>[];
        final replyDelays = <Duration>[];
        final stream = HttpInvocationContext.maybeFromInvocation(invocation)!
            .streamResponse(
              status: 206,
              headers: {'x-stream': 'original'},
              onStreamOpened: () => callbacks.add('opened'),
              onFirstBodyWrite: () => callbacks.add('write'),
              onFirstBodyWriteCompleted: () => callbacks.add('written'),
              onDirectStreamOpenRoundTrip: roundTrips.add,
              onDirectStreamRequestQueueDelay: queueDelays.add,
              onDirectStreamDescriptorOpenCall: openDurations.add,
              onDirectStreamReplyDeliveryDelay: replyDelays.add,
            );
        var doneCount = 0;
        stream.done.then((_) => doneCount++);
        stream.add([1, 2]);
        stream.add([3, 4]);
        stream.close([5, 6]);
        expect(stream.isClosed, isTrue);
        await finalResponse.future;
        await Future<void>.value();
        expect(doneCount, 1);
        expect(requests, hasLength(1));
        expect(
          requests.single['type'],
          HttpInvocationControlMessages.openResponseStream,
        );
        expect(requests.single['requestId'], 37);
        expect(requests.single['status'], 206);
        expect(requests.single['headers'], {'x-stream': 'original'});
        expect(requests.single['sentAtUs'], isPositive);
        expect(messages, hasLength(3));
        _expectChunk(messages[0], [1, 2], progress: true);
        _expectChunk(messages[1], [3, 4], progress: true);
        _expectChunk(messages[2], [5, 6], progress: false);
        expect(callbacks, ['opened', 'write', 'written']);
        expect(
          queueDelays,
          timingExpected ? [const Duration(microseconds: 17)] : isEmpty,
        );
        expect(
          openDurations,
          timingExpected ? [const Duration(microseconds: 23)] : isEmpty,
        );
        expect(replyDelays, hasLength(timingExpected ? 1 : 0));
        expect(roundTrips, hasLength(descriptor['handle'] == 1 ? 1 : 0));
        for (final duration in [...roundTrips, ...replyDelays]) {
          expect(duration.isNegative, isFalse);
        }
        stream.close([100]);
        expect(messages, hasLength(3));
        expect(() => stream.add([100]), throwsStateError);
      });
    }
  });
}
