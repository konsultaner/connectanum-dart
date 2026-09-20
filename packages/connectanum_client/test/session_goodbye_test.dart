import 'dart:async';

import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';

void main() {
  test('local close sends once and preserves the first message', () async {
    final transport = _GoodbyeTransport();
    addTearDown(transport.dispose);
    final session = await Session.start('test.realm', transport);
    expect(session.isConnected(), isTrue);
    final notifications = <Goodbye>[];
    unawaited(session.onGoodbye.then(notifications.add));

    await session.close(message: 'first');
    await session.close(message: 'second');
    final sent = transport.sent.whereType<Goodbye>().toList();
    expect(sent, hasLength(1));
    expect(sent.single.reason, Goodbye.reasonNormal);
    expect(sent.single.message?.message, 'first');
    expect(transport.closeCount, 0);
    expect(notifications, isEmpty);

    final reply = Goodbye(null, Goodbye.reasonGoodbyeAndOut);
    transport.inbound.add(reply);
    await _drain();
    expect(notifications, [same(reply)]);
    expect(transport.sent.whereType<Goodbye>(), hasLength(1));
    expect(transport.closeCount, 1);
    await transport.finishClose();
    expect(session.isConnected(), isFalse);
  });

  for (final localFirst in [false, true]) {
    test('queued duplicate GOODBYEs localFirst=$localFirst', () async {
      final transport = _GoodbyeTransport();
      addTearDown(transport.dispose);
      final dispatchErrors = <Object>[];
      final notifications = <Goodbye>[];
      final first = Goodbye(
        GoodbyeMessage('router stopping'),
        Goodbye.reasonSystemShutdown,
      );
      final second = Goodbye(null, Goodbye.reasonNormal);

      // Keep the receive listener's zone so duplicate-completion exceptions
      // become observable assertions rather than unclassified test errors.
      await _observeDispatch(() async {
        final session = await Session.start('test.realm', transport);
        expect(session.isConnected(), isTrue);
        unawaited(session.onGoodbye.then(notifications.add));
        if (localFirst) await session.close(message: 'local');

        // The transport deliberately defers physical closure, allowing frames
        // already queued by the peer to arrive before shutdown completes.
        transport.inbound.add(first);
        transport.inbound.add(second);
        await _drain();
        unawaited(session.onGoodbye.then(notifications.add));
        await _drain();
        await session.close(message: 'after peer');
        await transport.finishClose();
        expect(session.isConnected(), isFalse);
      }, dispatchErrors);

      expect(dispatchErrors, isEmpty);
      expect(notifications, [same(first), same(first)]);
      final sent = transport.sent.whereType<Goodbye>().toList();
      expect(sent, hasLength(1));
      expect(
        sent.single.reason,
        localFirst ? Goodbye.reasonNormal : Goodbye.reasonGoodbyeAndOut,
      );
      expect(sent.single.message?.message, localFirst ? 'local' : null);
      expect(transport.closeCount, greaterThanOrEqualTo(1));
    });
  }

  test('timed close closes transport once without a router reply', () async {
    final transport = _GoodbyeTransport()..closeImmediately = true;
    addTearDown(transport.dispose);
    final session = await Session.start('test.realm', transport);
    expect(session.isConnected(), isTrue);
    final notifications = <Goodbye>[];
    unawaited(session.onGoodbye.then(notifications.add));

    await session.close(message: 'timeout', timeout: Duration.zero);
    await session.close(message: 'duplicate', timeout: Duration.zero);
    await _drain();
    expect(session.isConnected(), isFalse);
    expect(transport.closeCount, 1);
    expect(transport.sent.whereType<Goodbye>(), hasLength(1));
    expect(notifications, isEmpty);
  });

  for (final error in [
    StateError('action failure'),
    TestFailure('assertion'),
  ]) {
    test('dispatch observer preserves ${error.runtimeType}', () async {
      final dispatchErrors = <Object>[];
      await expectLater(
        _observeDispatch(() async => throw error, dispatchErrors),
        throwsA(same(error)),
      );
      expect(dispatchErrors, isEmpty);
    });
  }
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

Future<void> _observeDispatch(
  Future<void> Function() action,
  List<Object> dispatchErrors,
) {
  final completion = Completer<void>();
  runZonedGuarded(() {
    unawaited(
      action().then<void>(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stack) {
          completion.completeError(error, stack);
        },
      ),
    );
  }, (error, stack) => dispatchErrors.add(error));
  return completion.future;
}

class _GoodbyeTransport extends AbstractTransport {
  final inbound = StreamController<AbstractMessage>();
  final sent = <AbstractMessage>[];
  var closeCount = 0;
  var closeImmediately = false;
  var _open = true;
  final _closed = Completer<void>();

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
  Stream<AbstractMessage> receive() => inbound.stream;

  @override
  void send(AbstractMessage message) {
    sent.add(message);
    if (message is Hello) {
      inbound.add(Welcome(42, Details.forWelcome(realm: 'test.realm')));
    }
  }

  @override
  Future<void> close({error}) {
    closeCount++;
    if (closeImmediately) unawaited(finishClose());
    return _closed.future;
  }

  Future<void> finishClose() async {
    if (!_open) return;
    _open = false;
    if (!onDisconnect.isCompleted) onDisconnect.complete();
    await inbound.close();
    if (!_closed.isCompleted) _closed.complete();
  }

  Future<void> dispose() => finishClose();
}
