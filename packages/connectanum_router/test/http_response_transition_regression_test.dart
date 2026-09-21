@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/invocation.dart';
import 'package:connectanum_core/src/message/yield.dart';
import 'package:connectanum_router/src/router/http/http_context.dart';
import 'package:test/test.dart';

Invocation _invocation({SendPort? control}) => Invocation(
  83,
  91,
  InvocationDetails(null, 'com.example.http', true)
    ..custom.addAll({
      HttpInvocationKeys.requestId: 37,
      HttpInvocationKeys.request: {
        'id': 37,
        'method': 'POST',
        'target': '/tasks',
        'path': '/tasks',
        'protocol': 'http/1.1',
        'version': 1,
        'headers': <String, String>{},
      },
      HttpInvocationKeys.responseStreamControlPort: ?control,
    }),
);

HttpResponsePayload? _parse(Map<String, Object?> data) {
  HttpResponsePayload? result;
  expect(
    () => result = HttpResponsePayload.fromKeywordArguments(data),
    returnsNormally,
  );
  return result;
}

Map<String, Object?> _response(String kind, Object? body) => {
  HttpInvocationKeys.requestId: 37,
  'status': 206,
  'headers': <String, String>{'x-response': 'original'},
  HttpInvocationKeys.responseBodyKind: kind,
  HttpInvocationKeys.responseBody: body,
};

void _expectYield(Yield message, List<int>? body, bool progress) {
  expect(message.invocationRequestId, 83);
  expect(message.options?.progress ?? false, progress);
  expect(message.arguments, isNull);
  expect(message.argumentsKeywords, {
    HttpInvocationKeys.requestId: 37,
    'status': 206,
    'headers': {'x-response': 'original'},
    HttpInvocationKeys.responseBodyKind: 'bytes',
    HttpInvocationKeys.responseBody: body,
    'progress': progress,
  });
}

void main() {
  group('HTTP response event metadata', () {
    for (final progress in [false, true]) {
      for (final (kind, body, encoding, path, fields)
          in <(String, Object?, String?, String?, Map<String, Object?>)>[
            ('bytes', null, null, null, {}),
            ('bytes', <int>[], null, null, {'bodyBytes': <int>[]}),
            (
              'bytes',
              <int>[0, 128, 255],
              null,
              null,
              {
                'bodyBytes': [0, 128, 255],
              },
            ),
            ('text', null, null, null, {}),
            ('text', '', null, null, {'bodyText': ''}),
            (
              'text',
              'hello',
              '',
              null,
              {'bodyText': 'hello', 'bodyEncoding': ''},
            ),
            (
              'text',
              'hello',
              'utf8',
              null,
              {'bodyText': 'hello', 'bodyEncoding': 'utf8'},
            ),
            ('json', null, null, null, {}),
            ('json', false, null, null, {'bodyJson': false}),
            (
              'json',
              <String, Object?>{},
              null,
              null,
              {'bodyJson': <String, Object?>{}},
            ),
            ('file', null, null, '', {'filePath': ''}),
            (
              'file',
              null,
              null,
              '/public/report.bin',
              {'filePath': '/public/report.bin'},
            ),
          ]) {
        test(
          '$kind body=$body encoding=$encoding path=$path progress=$progress',
          () {
            final input = _response(kind, body)..['progress'] = progress;
            if (encoding != null) {
              input[HttpInvocationKeys.responseBodyEncoding] = encoding;
            }
            if (path != null) input[HttpInvocationKeys.responseFilePath] = path;
            final payload = _parse(input);
            expect(payload, isNotNull);
            expect(payload!.toEventPayload(), {
              'requestId': 37,
              'status': 206,
              'headers': {'x-response': 'original'},
              'bodyKind': kind,
              ...fields,
              'progress': progress,
            });
            for (final override in <bool?>[null, false, true]) {
              final invocation = _invocation();
              final messages = <Yield>[];
              invocation.onResponse(
                (message) => messages.add(message as Yield),
              );
              if (override == null) {
                HttpResponseUtil.respond(invocation, payload);
              } else {
                HttpResponseUtil.respond(
                  invocation,
                  payload,
                  progress: override,
                );
              }
              expect(messages, hasLength(1));
              expect(
                messages.single.argumentsKeywords!['progress'],
                override ?? false,
              );
              expect(
                messages.single.options?.progress ?? false,
                override ?? false,
              );
              expect(invocation.responseClosed, !(override ?? false));
              expect(payload.progress, progress);
            }
          },
        );
      }
    }

    for (final body in <Object>[
      0,
      false,
      <int>[],
      <int>[1],
      <String, Object?>{},
      Uint8List(1),
    ]) {
      test('malformed text body ${body.runtimeType}=$body returns null', () {
        expect(_parse(_response('text', body)), isNull);
      });
    }

    test('byte factory preserves supplied headers and copies bytes', () {
      final bytes = Uint8List.fromList([1, 2]);
      final payload = HttpResponseUtil.bytes(
        requestId: 37,
        status: 206,
        headers: {'x-response': 'original'},
        body: bytes,
      );
      bytes[0] = 99;
      expect(payload.toEventPayload(), {
        'requestId': 37,
        'status': 206,
        'headers': {'x-response': 'original'},
        'bodyKind': 'bytes',
        'bodyBytes': [1, 2],
        'progress': false,
      });
    });

    test('request snapshot alone is not an HTTP invocation marker', () {
      final invocation = _invocation();
      invocation.details.custom.remove(HttpInvocationKeys.requestId);
      HttpInvocationContext? context;
      expect(
        () => context = HttpInvocationContext.maybeFromInvocation(invocation),
        returnsNormally,
      );
      expect(context, isNull);
    });
  });

  group('HTTP descriptor timing boundaries', () {
    for (final field in [
      'requestQueueDelayUs',
      'descriptorOpenUs',
      'replySentAtUs',
    ]) {
      for (final value in <Object?>[null, '0', -1, 0, 17, 1000000000000]) {
        test('$field=$value', () async {
          final control = ReceivePort();
          addTearDown(control.close);
          var requests = 0;
          control.listen((dynamic message) {
            final request = message as Map;
            requests++;
            (request['replyPort'] as SendPort).send({
              'replyRequestId': request['replyRequestId'],
              'handle': 1,
              // Fails before loading any FFI library, after reporting timings.
              'libraryPath': 42,
              field: value,
            });
          });
          final invocation = _invocation(control: control.sendPort);
          final messages = <Yield>[];
          invocation.onResponse((message) => messages.add(message as Yield));
          final roundTrips = <Duration>[];
          final timings = <String, List<Duration>>{
            for (final key in [
              'requestQueueDelayUs',
              'descriptorOpenUs',
              'replySentAtUs',
            ])
              key: [],
          };
          final before = DateTime.now().microsecondsSinceEpoch;
          final stream = HttpInvocationContext.maybeFromInvocation(invocation)!
              .streamResponse(
                status: 206,
                headers: {'x-response': 'original'},
                onDirectStreamOpenRoundTrip: roundTrips.add,
                onDirectStreamRequestQueueDelay:
                    timings['requestQueueDelayUs']!.add,
                onDirectStreamDescriptorOpenCall:
                    timings['descriptorOpenUs']!.add,
                onDirectStreamReplyDeliveryDelay: timings['replySentAtUs']!.add,
              );
          stream.close([7]);
          await stream.done;
          final after = DateTime.now().microsecondsSinceEpoch;
          expect(requests, 1);
          expect(messages, hasLength(1));
          _expectYield(messages.single, [7], false);
          expect(roundTrips, hasLength(1));
          expect(roundTrips.single.isNegative, isFalse);
          for (final key in timings.keys) {
            final expected = key == field && value is int && value >= 0;
            expect(timings[key], hasLength(expected ? 1 : 0));
            if (!expected) continue;
            if (key == 'replySentAtUs') {
              expect(
                timings[key]!.single.inMicroseconds,
                inInclusiveRange(before - value, after - value),
              );
            } else {
              expect(timings[key], [Duration(microseconds: value)]);
            }
          }
        });
      }
    }
  });

  group('HTTP failed direct stream transitions', () {
    for (final descriptor in <Map<String, Object?>>[
      {'handle': 0},
      {'handle': 1, 'libraryPath': 42},
    ]) {
      for (final finalChunk in <List<int>?>[
        null,
        [],
        Uint8List(0),
        [7, 8],
        Uint8List.fromList([7, 8]),
      ]) {
        test(
          'final-only $descriptor ${finalChunk.runtimeType}=$finalChunk',
          () async {
            final control = ReceivePort();
            addTearDown(control.close);
            var requests = 0;
            control.listen((dynamic message) {
              final request = message as Map;
              requests++;
              (request['replyPort'] as SendPort).send({
                'replyRequestId': request['replyRequestId'],
                ...descriptor,
              });
            });
            final invocation = _invocation(control: control.sendPort);
            final messages = <Yield>[];
            final events = <String>[];
            final firstYield = Completer<void>();
            invocation.onResponse((message) {
              messages.add(message as Yield);
              events.add('yield');
              if (!firstYield.isCompleted) firstYield.complete();
            });
            final stream =
                HttpInvocationContext.maybeFromInvocation(
                  invocation,
                )!.streamResponse(
                  status: 206,
                  headers: {'x-response': 'original'},
                  onStreamOpened: () => events.add('opened'),
                  onFirstBodyWrite: () => events.add('write'),
                  onFirstBodyWriteCompleted: () => events.add('written'),
                );
            var completions = 0;
            stream.done.then((_) => completions++);
            stream.close(finalChunk);
            stream.close([99]);
            await firstYield.future;
            // Observe completion queued by the same response delivery, not a deadline.
            await Future<void>.value();
            expect(completions, 1);
            expect(stream.isClosed, isTrue);
            expect(invocation.responseClosed, isTrue);
            expect(requests, 1);
            expect(messages, hasLength(1));
            final hasBody = finalChunk != null && finalChunk.isNotEmpty;
            _expectYield(messages.single, hasBody ? [7, 8] : null, false);
            expect(
              events,
              hasBody ? ['opened', 'write', 'yield', 'written'] : ['yield'],
            );
            expect(() => stream.add([1]), throwsStateError);
            await stream.done;
          },
        );
      }

      test(
        'later chunks after $descriptor notify the first write only once',
        () async {
          final control = ReceivePort();
          addTearDown(control.close);
          var requests = 0;
          control.listen((dynamic message) {
            final request = message as Map;
            requests++;
            (request['replyPort'] as SendPort).send({
              'replyRequestId': request['replyRequestId'],
              ...descriptor,
            });
          });
          final invocation = _invocation(control: control.sendPort);
          final firstYield = Completer<void>();
          final messages = <Yield>[];
          final events = <String>[];
          invocation.onResponse((message) {
            messages.add(message as Yield);
            events.add('yield');
            if (!firstYield.isCompleted) firstYield.complete();
          });
          final stream = HttpInvocationContext.maybeFromInvocation(invocation)!
              .streamResponse(
                status: 206,
                headers: {'x-response': 'original'},
                onStreamOpened: () => events.add('opened'),
                onFirstBodyWrite: () => events.add('write'),
                onFirstBodyWriteCompleted: () => events.add('written'),
              );
          var completions = 0;
          stream.done.then((_) => completions++);
          stream.add([1]);
          await firstYield.future;
          expect(events, ['opened', 'write', 'yield', 'written']);
          expect(invocation.responseClosed, isFalse);
          expect(completions, 0);
          stream.add([2]);
          stream.close([3]);
          await Future<void>.value();
          expect(completions, 1);
          expect(requests, 1);
          expect(messages, hasLength(3));
          _expectYield(messages[0], [1], true);
          _expectYield(messages[1], [2], true);
          _expectYield(messages[2], [3], false);
          expect(events, [
            'opened',
            'write',
            'yield',
            'written',
            'yield',
            'yield',
          ]);
          await stream.done;
        },
      );

      test(
        'fallback headers keep the construction snapshot for $descriptor',
        () async {
          final control = ReceivePort();
          addTearDown(control.close);
          final requestFuture = control.first;
          final invocation = _invocation(control: control.sendPort);
          final messages = <Yield>[];
          invocation.onResponse((message) => messages.add(message as Yield));
          final headers = {'x-response': 'original'};
          final stream = HttpInvocationContext.maybeFromInvocation(invocation)!
              .streamResponse(
                status: 206,
                headers: headers,
              );
          headers['x-response'] = 'changed';
          stream.add([1]);
          stream.close([2]);
          final request = await requestFuture as Map;
          expect(request['headers'], {'x-response': 'original'});
          (request['replyPort'] as SendPort).send({
            'replyRequestId': request['replyRequestId'],
            ...descriptor,
          });
          await stream.done;
          expect(messages, hasLength(2));
          _expectYield(messages[0], [1], true);
          _expectYield(messages[1], [2], false);
          expect(stream.headers, {'x-response': 'original'});
        },
      );
    }
  });
}
