import 'dart:async';

import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';

void main() {
  for (final lazy in [false, true]) {
    for (final finish in [false, true]) {
      test('lazy=$lazy finish=$finish rejected send is retryable', () async {
        final transport = _Transport();
        final session = await _connect(transport);
        final call = _call(session);
        final failure = StateError('send rejected');
        transport.sendError = failure;
        expect(
          () => _send(call, lazy, finish, 'payload'),
          throwsA(same(failure)),
        );
        expect(call.isFinished, isFalse);
        expect(transport.sent.whereType<Call>(), hasLength(1));
        transport.sendError = null;
        expect(() => _send(call, lazy, finish, 'payload'), returnsNormally);
        final messages = transport.sent.whereType<Call>().toList();
        expect(messages, hasLength(2));
        expect(messages.last.requestId, call.requestId);
        expect(messages.last.options?.progress, !finish);
        expect(messages.last.arguments, ['payload']);
        expect(messages.last.argumentsKeywords, {'label': 'payload'});
        expect(call.isFinished, finish);
        if (finish) {
          for (final lateLazy in [false, true]) {
            for (final lateFinish in [false, true]) {
              expect(
                () => _send(call, lateLazy, lateFinish, 'late'),
                throwsStateError,
              );
            }
          }
          expect(transport.sent.whereType<Call>(), hasLength(2));
        }
      });
    }

    for (final nestedLazy in [false, true]) {
      for (final nestedFinish in [false, true]) {
        test(
          'final lazy=$lazy rejects nested lazy=$nestedLazy finish=$nestedFinish',
          () async {
            final transport = _Transport();
            final session = await _connect(transport);
            final call = _call(session);
            bool? closedDuringSend;
            Object? nestedFailure;
            var callbacks = 0;
            transport.afterSend = (message) {
              if (message is! Call || callbacks++ != 0) return;
              closedDuringSend = call.isFinished;
              try {
                _send(call, nestedLazy, nestedFinish, 'nested');
              } catch (error) {
                nestedFailure = error;
              }
            };
            expect(() => _send(call, lazy, true, 'final'), returnsNormally);
            expect(transport.sent.whereType<Call>(), hasLength(2));
            expect(callbacks, 1);
            expect(closedDuringSend, isTrue);
            expect(nestedFailure, isA<StateError>());
            expect(call.isFinished, isTrue);
            final message = transport.sent.whereType<Call>().last;
            expect(message.requestId, call.requestId);
            expect(message.options?.progress, isFalse);
            expect(message.arguments, ['final']);
            expect(message.argumentsKeywords, {'label': 'final'});
          },
        );
      }
    }
  }

  test(
    'progress callback failure cannot reopen a nested accepted final send',
    () async {
      final transport = _Transport();
      final session = await _connect(transport);
      final call = _call(session);
      final failure = StateError('progress callback rejected');
      var callbacks = 0;
      transport.afterSend = (message) {
        if (message is! Call || callbacks++ != 0) return;
        call.finish(arguments: ['nested-final']);
        throw failure;
      };
      expect(
        () => call.sendChunk(arguments: ['progress']),
        throwsA(same(failure)),
      );
      expect(call.isFinished, isTrue);
      final messages = transport.sent.whereType<Call>().toList();
      expect(messages, hasLength(3));
      expect(messages.map((message) => message.options?.progress), [
        true,
        true,
        false,
      ]);
      expect(messages.last.arguments, ['nested-final']);
      expect(() => call.finish(), throwsStateError);
      expect(transport.sent.whereType<Call>(), hasLength(3));
    },
  );

  test('progressive callbacks may send bounded nested progress', () async {
    final transport = _Transport();
    final session = await _connect(transport);
    final call = _call(session);
    var callbacks = 0;
    transport.afterSend = (message) {
      if (message is! Call || callbacks++ != 0) return;
      call.sendChunk(arguments: ['nested']);
    };
    expect(() => call.sendChunk(arguments: ['outer']), returnsNormally);
    final messages = transport.sent.whereType<Call>().toList();
    expect(messages, hasLength(3));
    expect(messages.skip(1).map((message) => message.arguments), [
      ['outer'],
      ['nested'],
    ]);
    expect(
      messages.map((message) => message.options?.progress),
      everyElement(isTrue),
    );
    expect(call.isFinished, isFalse);
    expect(() => call.finish(), returnsNormally);
    expect(call.isFinished, isTrue);
  });

  test('a finished call still drains its last local write', () async {
    final transport = _PacingTransport();
    final session = await _connect(transport);
    final call = _call(session);
    expect(() => call.finish(arguments: ['final']), returnsNormally);
    final pending = call.drain();
    expect(transport.drains, hasLength(1));
    transport.drains.single.complete();
    await expectLater(pending, completes);
    expect(call.isFinished, isTrue);
    expect(transport.sent.whereType<Call>(), hasLength(2));
  });

  test(
    'drain waits for local pacing without awaiting a remote result',
    () async {
      final transport = _PacingTransport();
      final session = await _connect(transport);
      final call = _call(session);
      var completed = false;
      final pending = call.drain().then((_) => completed = true);
      expect(transport.drains, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      transport.drains.single.complete();
      await expectLater(pending, completes);
      expect(completed, isTrue);
      expect(call.isFinished, isFalse);
      expect(transport.sent.whereType<Call>(), hasLength(1));
      expect(() => call.sendChunk(arguments: ['next']), returnsNormally);
      expect(() => call.finish(arguments: ['last']), returnsNormally);
      final sent = transport.sent.whereType<Call>().toList();
      expect(
        sent.map((message) => message.requestId),
        everyElement(call.requestId),
      );
      expect(sent.map((message) => message.options?.progress), [
        true,
        true,
        false,
      ]);
      expect(sent[1].arguments, ['next']);
      expect(sent[2].arguments, ['last']);
      expect(call.isFinished, isTrue);
    },
  );

  test(
    'drain propagates transport failure and permits a later retry',
    () async {
      final transport = _PacingTransport();
      final session = await _connect(transport);
      final call = _call(session);
      final failure = StateError('local pacing rejected');
      final pending = call.drain();
      final rejected = expectLater(pending, throwsA(same(failure)));
      expect(transport.drains, hasLength(1));
      transport.drains.single.completeError(failure);
      await rejected;
      expect(call.isFinished, isFalse);
      final retry = call.drain();
      expect(transport.drains, hasLength(2));
      transport.drains.last.complete();
      await expectLater(retry, completes);
      expect(() => call.finish(arguments: ['after-retry']), returnsNormally);
      expect(transport.sent.whereType<Call>().last.arguments, ['after-retry']);
      expect(call.isFinished, isTrue);
    },
  );

  test('concurrent drains retain their own transport futures', () async {
    final transport = _PacingTransport();
    final session = await _connect(transport);
    final first = _call(session);
    final second = _call(session);
    expect(first.requestId, isNot(second.requestId));
    final completed = <String>[];
    final one = first.drain().then((_) => completed.add('first'));
    final two = second.drain().then((_) => completed.add('second'));
    expect(transport.drains, hasLength(2));
    transport.drains[1].complete();
    await two;
    expect(completed, ['second']);
    transport.drains[0].complete();
    await one;
    expect(completed, ['second', 'first']);
    expect(first.isFinished, isFalse);
    expect(second.isFinished, isFalse);
    expect(transport.sent.whereType<Call>(), hasLength(2));
  });

  test(
    'transport without pacing supports an asynchronous no-op drain',
    () async {
      final transport = _Transport();
      final session = await _connect(transport);
      final call = _call(session);
      await expectLater(call.drain(), completes);
      expect(transport.sent.whereType<Call>(), hasLength(1));
      expect(call.isFinished, isFalse);
      expect(() => call.finish(arguments: ['done']), returnsNormally);
      expect(transport.sent.whereType<Call>().last.arguments, ['done']);
      expect(call.isFinished, isTrue);
    },
  );
}

void _send(ProgressiveCall call, bool lazy, bool finish, String label) {
  if (lazy) {
    final payload = LazyMessagePayload.materialized(
      arguments: [label],
      argumentsKeywords: {'label': label},
    );
    if (finish) {
      call.finishLazy(payload);
    } else {
      call.sendLazyChunk(payload);
    }
  } else if (finish) {
    call.finish(arguments: [label], argumentsKeywords: {'label': label});
  } else {
    call.sendChunk(arguments: [label], argumentsKeywords: {'label': label});
  }
}

Future<Session> _connect(_Transport transport) async {
  final client = Client(realm: 'test.realm', transport: transport);
  addTearDown(client.disconnect);
  final session = await client.connect().first;
  expect(session.isConnected(), isTrue);
  return session;
}

ProgressiveCall _call(Session session) {
  final call = session.startProgressiveCall('files.upload');
  final subscription = call.results.listen((_) {});
  addTearDown(subscription.cancel);
  return call;
}

class _Transport extends AbstractTransport {
  final inbound = StreamController<AbstractMessage>.broadcast();
  final sent = <AbstractMessage>[];
  Object? sendError;
  void Function(AbstractMessage)? afterSend;
  bool _open = false;
  @override
  final Completer<void> onDisconnect = Completer<void>();
  @override
  final Completer<void> onConnectionLost = Completer<void>();
  @override
  bool get isOpen => _open;
  @override
  bool get isReady => _open;
  @override
  Future<void> get onReady => Future<void>.value();
  @override
  Future<void> open({Duration? pingInterval}) async => _open = true;
  @override
  Future<void> close({dynamic error}) async {
    if (!_open) return;
    _open = false;
    unawaited(inbound.close());
    onDisconnect.complete();
  }

  @override
  Stream<AbstractMessage> receive() => inbound.stream;
  @override
  void send(AbstractMessage message) {
    if (sendError != null) throw sendError!;
    sent.add(message);
    afterSend?.call(message);
    if (message is Hello) inbound.add(Welcome(17, Details.forWelcome()));
  }
}

class _PacingTransport extends _Transport implements DrainableTransport {
  final drains = <Completer<void>>[];

  @override
  Future<void> drain() {
    final completion = Completer<void>();
    drains.add(completion);
    return completion.future;
  }
}
