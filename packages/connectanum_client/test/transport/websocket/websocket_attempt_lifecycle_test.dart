@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'websocket_test_observer.dart';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:connectanum_client/src/transport/websocket/websocket_transport_web.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:connectanum_core/json_serializer.dart' as json_serializer;
import 'package:test/test.dart';
import 'package:logging/logging.dart';

@JS('eval')
external JSAny? _evaluate(JSString source);

extension type _Harness(JSObject _) implements JSObject {
  external JSArray<_Socket> get sockets;
  external void restore();
}

extension type _Socket(JSObject _) implements JSObject {
  external int get closeCalls;
  external int get messageListeners;
  external JSArray<JSAny?> get sent;
  external void frame(JSString data);
  external void binaryFrame(JSUint8Array bytes);
  external void opened();
  external void failed();
  external void closed(int code);
  external void deferredFrame();
  external void finishFrame(JSUint8Array bytes);
}

_Harness _installHarness() {
  final harness = _Harness(
    _evaluate(
          r'''
(() => {
  const Original = globalThis.WebSocket;
  const h = {sockets: [], restore() { globalThis.WebSocket = Original; }};
  globalThis.WebSocket = class extends EventTarget {
    static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
    constructor(url, protocols) {
      super(); this.url = url; this.protocol = protocols[0];
      this.readyState = 0; this.closeCalls = 0; this.sent = [];
      this.messageCallbacks = new Set();
      h.sockets.push(this);
    }
    get messageListeners() { return this.messageCallbacks.size; }
    addEventListener(type, callback, options) {
      if (type === 'message') this.messageCallbacks.add(callback);
      super.addEventListener(type, callback, options);
    }
    removeEventListener(type, callback, options) {
      if (type === 'message') this.messageCallbacks.delete(callback);
      super.removeEventListener(type, callback, options);
    }
    send(data) { this.sent.push(data); }
    frame(data) { this.dispatchEvent(new MessageEvent('message', {data})); }
    binaryFrame(bytes) {
      const blob = new Blob([]);
      blob.arrayBuffer = () => Promise.resolve(Uint8Array.from(bytes).buffer);
      this.dispatchEvent(new MessageEvent('message', {data: blob}));
    }
    close() { this.closeCalls++; this.readyState = 3; }
    opened() { if (this.readyState === 0) this.readyState = 1; this.dispatchEvent(new Event('open')); }
    failed() { this.dispatchEvent(new Event('error')); }
    closed(code) { this.readyState = 3; this.dispatchEvent(new CloseEvent('close', {code})); }
    deferredFrame() {
      const blob = new Blob([]);
      blob.arrayBuffer = () => new Promise(resolve => { this.finish = resolve; });
      this.dispatchEvent(new MessageEvent('message', {data: blob}));
    }
    finishFrame(bytes) { this.finish(Uint8Array.from(bytes).buffer); }
  };
  return h;
})()
'''
              .toJS,
        )
        as JSObject,
  );
  addTearDown(() => harness.restore());
  return harness;
}

Future<void> _drain() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Zone _observingZone(List<Object> uncaught) => Zone.current.fork(
  specification: ZoneSpecification(
    handleUncaughtError: (self, parent, zone, error, stack) {
      uncaught.add(error);
    },
  ),
);

class _CleanupObservingTransport extends WebSocketTransport {
  _CleanupObservingTransport()
    : super(
        'ws://test.invalid/wamp',
        json_serializer.Serializer(),
        'wamp.2.json',
      );

  final cleanupErrors = <Object?>[];

  @override
  Future<void> close({dynamic error}) {
    cleanupErrors.add(error);
    return super.close(error: error);
  }
}

void main() {
  for (final encoding in ['msgpack', 'cbor']) {
    test('$encoding cancel does not wait for a pending Blob', () async {
      final harness = _installHarness();
      final transport = encoding == 'msgpack'
          ? WebSocketTransport.withMsgpackSerializer('ws://test.invalid/wamp')
          : WebSocketTransport.withCborSerializer('ws://test.invalid/wamp');
      addTearDown(transport.close);
      final opening = transport.open();
      final socket = harness.sockets.toDart.single;
      socket.opened();
      await expectDeliveredCompletion(opening);
      JSUint8Array frame(int requestId) => Uint8List.fromList(
        encoding == 'msgpack'
            ? [0x93, 0x21, requestId, 100 + requestId]
            : [0x83, 0x18, 0x21, requestId, 0x18, 100 + requestId],
      ).toJS;
      final abandoned = <AbstractMessage?>[];
      final errors = <Object>[];
      final old = transport.receive().listen(
        abandoned.add,
        onError: errors.add,
      );
      addTearDown(old.cancel);
      socket.deferredFrame();
      await _drain();
      socket.binaryFrame(frame(2));
      await expectDeliveredCompletion(old.cancel());
      expect(socket.messageListeners, 0);
      final messages = <AbstractMessage?>[];
      final next = transport.receive().listen(
        messages.add,
        onError: errors.add,
      );
      addTearDown(next.cancel);
      socket.binaryFrame(frame(3));
      socket.finishFrame(frame(1));
      await _drain();
      socket.binaryFrame(frame(4));
      await _drain();
      expect(errors, isEmpty);
      expect(abandoned, isEmpty);
      expect(messages, hasLength(2));
      expect(
        messages.cast<Subscribed>().map(
          (message) => message.subscribeRequestId,
        ),
        [3, 4],
      );
      expect(transport.isReady, isTrue);
      expect(transport.onConnectionLost!.isCompleted, isFalse);
      expect(transport.onDisconnect!.isCompleted, isFalse);
    });

    test(
      '$encoding retains frames arriving while an earlier Blob is decoding',
      () async {
        final harness = _installHarness();
        final transport = encoding == 'msgpack'
            ? WebSocketTransport.withMsgpackSerializer('ws://test.invalid/wamp')
            : WebSocketTransport.withCborSerializer('ws://test.invalid/wamp');
        addTearDown(transport.close);
        final opening = transport.open();
        final socket = harness.sockets.toDart.single;
        socket.opened();
        await expectDeliveredCompletion(opening);
        final messages = <AbstractMessage?>[];
        final errors = <Object>[];
        final subscription = transport.receive().listen(
          messages.add,
          onError: errors.add,
        );
        addTearDown(subscription.cancel);
        socket.deferredFrame();
        await _drain();
        socket.binaryFrame(
          Uint8List.fromList(
            encoding == 'msgpack'
                ? [0x93, 0x21, 0x02, 0x66]
                : [0x83, 0x18, 0x21, 0x02, 0x18, 0x66],
          ).toJS,
        );
        await _drain();
        expect(
          messages,
          isEmpty,
          reason: 'later messages must not overtake the first',
        );
        socket.finishFrame(
          Uint8List.fromList(
            encoding == 'msgpack'
                ? [0x93, 0x21, 0x01, 0x65]
                : [0x83, 0x18, 0x21, 0x01, 0x18, 0x65],
          ).toJS,
        );
        await _drain();
        expect(errors, isEmpty);
        expect(messages, hasLength(2));
        expect(messages, everyElement(isA<Subscribed>()));
        expect(
          messages.cast<Subscribed>().map(
            (message) => message.subscribeRequestId,
          ),
          [1, 2],
        );
        expect(
          messages.cast<Subscribed>().map((message) => message.subscriptionId),
          [101, 102],
        );
        expect(transport.isReady, isTrue);
        expect(transport.onDisconnect!.isCompleted, isFalse);
        expect(transport.onConnectionLost!.isCompleted, isFalse);
      },
    );
  }

  for (final encoding in ['json', 'msgpack', 'cbor']) {
    WebSocketTransport transportForEncoding() => switch (encoding) {
      'json' => WebSocketTransport.withJsonSerializer('ws://test.invalid/wamp'),
      'msgpack' => WebSocketTransport.withMsgpackSerializer(
        'ws://test.invalid/wamp',
      ),
      _ => WebSocketTransport.withCborSerializer('ws://test.invalid/wamp'),
    };

    void deliver(_Socket socket, int requestId) {
      if (encoding == 'json') {
        socket.frame('[33,$requestId,${100 + requestId}]'.toJS);
      } else {
        socket.binaryFrame(
          Uint8List.fromList(
            encoding == 'msgpack'
                ? [0x93, 0x21, requestId, 100 + requestId]
                : [0x83, 0x18, 0x21, requestId, 0x18, 100 + requestId],
          ).toJS,
        );
      }
    }

    test('$encoding paused listeners retain frames in wire order', () async {
      final harness = _installHarness();
      final transport = transportForEncoding();
      addTearDown(transport.close);
      final opening = transport.open();
      final socket = harness.sockets.toDart.single;
      socket.opened();
      await expectDeliveredCompletion(opening);
      final messages = <AbstractMessage?>[];
      final errors = <Object>[];
      final subscription = transport.receive().listen(
        messages.add,
        onError: errors.add,
      );
      addTearDown(subscription.cancel);
      subscription.pause();
      for (var requestId = 1; requestId <= 8; requestId++) {
        deliver(socket, requestId);
      }
      await _drain();
      expect(messages, isEmpty);
      subscription.resume();
      await _drain();
      expect(errors, isEmpty);
      expect(messages, hasLength(8));
      expect(messages, everyElement(isA<Subscribed>()));
      expect(
        messages.cast<Subscribed>().map(
          (message) => message.subscribeRequestId,
        ),
        [1, 2, 3, 4, 5, 6, 7, 8],
      );
      expect(
        messages.cast<Subscribed>().map((message) => message.subscriptionId),
        [101, 102, 103, 104, 105, 106, 107, 108],
      );
      expect(transport.isReady, isTrue);
      expect(transport.onConnectionLost!.isCompleted, isFalse);
    });

    test('$encoding listener cancellation releases buffered input', () async {
      final harness = _installHarness();
      final transport = transportForEncoding();
      addTearDown(transport.close);
      final opening = transport.open();
      final socket = harness.sockets.toDart.single;
      socket.opened();
      await expectDeliveredCompletion(opening);
      final stream = transport.receive();
      expect(stream.isBroadcast, isTrue);
      final abandoned = <AbstractMessage?>[];
      final errors = <Object>[];
      final subscription = stream.listen(abandoned.add, onError: errors.add);
      subscription.pause();
      deliver(socket, 1);
      deliver(socket, 2);
      await _drain();
      await expectDeliveredCompletion(subscription.cancel());
      expect(socket.messageListeners, 0);
      deliver(socket, 3);
      final received = <AbstractMessage?>[];
      final next = stream.listen(received.add, onError: errors.add);
      addTearDown(next.cancel);
      deliver(socket, 4);
      await _drain();
      expect(errors, isEmpty);
      expect(abandoned, isEmpty);
      expect(received, hasLength(1));
      expect(
        received.single,
        isA<Subscribed>()
            .having((message) => message.subscribeRequestId, 'requestId', 4)
            .having((message) => message.subscriptionId, 'subscriptionId', 104),
      );
      expect(transport.isReady, isTrue);
      expect(transport.onDisconnect!.isCompleted, isFalse);
    });

    test('$encoding broadcast listeners have independent pauses', () async {
      final harness = _installHarness();
      final transport = transportForEncoding();
      addTearDown(transport.close);
      final opening = transport.open();
      final socket = harness.sockets.toDart.single;
      socket.opened();
      await expectDeliveredCompletion(opening);
      final stream = transport.receive();
      final paused = <AbstractMessage?>[];
      final active = <AbstractMessage?>[];
      final errors = <Object>[];
      final first = stream.listen(paused.add, onError: errors.add);
      final second = stream.listen(active.add, onError: errors.add);
      addTearDown(first.cancel);
      addTearDown(second.cancel);
      first.pause();
      deliver(socket, 1);
      deliver(socket, 2);
      await _drain();
      expect(paused, isEmpty);
      expect(active, hasLength(2));
      expect(
        active.cast<Subscribed>().map((message) => message.subscribeRequestId),
        [1, 2],
      );
      await expectDeliveredCompletion(second.cancel());
      first.resume();
      await _drain();
      expect(paused, active);
      deliver(socket, 3);
      await _drain();
      expect(errors, isEmpty);
      expect(paused, hasLength(3));
      expect(active, hasLength(2));
      expect(
        paused.last,
        isA<Subscribed>().having(
          (message) => message.subscribeRequestId,
          'requestId',
          3,
        ),
      );
      await expectDeliveredCompletion(first.cancel());
      expect(socket.messageListeners, 0);
    });

    test(
      '$encoding sends the correct wire type and complete WAMP frame',
      () async {
        final harness = _installHarness();
        final transport = switch (encoding) {
          'json' => WebSocketTransport.withJsonSerializer(
            'ws://test.invalid/wamp',
          ),
          'msgpack' => WebSocketTransport.withMsgpackSerializer(
            'ws://test.invalid/wamp',
          ),
          _ => WebSocketTransport.withCborSerializer('ws://test.invalid/wamp'),
        };
        addTearDown(transport.close);
        final opening = transport.open();
        final socket = harness.sockets.toDart.single;
        socket.opened();
        await expectDeliveredCompletion(opening);
        expect(
          () => transport.send(Goodbye(null, Goodbye.reasonNormal)),
          returnsNormally,
        );
        final sent = socket.sent.toDart;
        expect(sent, hasLength(1));
        final wire = sent.single!;
        if (encoding == 'json') {
          expect(wire.isA<JSString>(), isTrue);
          expect(jsonDecode((wire as JSString).toDart), [
            6,
            {},
            'wamp.close.normal',
          ]);
        } else {
          expect(wire.isA<JSUint8Array>(), isTrue);
          expect((wire as JSUint8Array).toDart, [
            ...encoding == 'msgpack'
                ? [0x93, 0x06, 0x80, 0xb1]
                : [0x83, 0x06, 0xa0, 0x71],
            ...utf8.encode('wamp.close.normal'),
          ]);
        }
        expect(transport.isReady, isTrue);
      },
    );
  }

  test(
    'current malformed input invokes overridable transport cleanup',
    () async {
      final harness = _installHarness();
      final transport = _CleanupObservingTransport();
      addTearDown(transport.close);
      final opening = transport.open();
      final socket = harness.sockets.toDart.single;
      socket.opened();
      await expectDeliveredCompletion(opening);
      final messages = <AbstractMessage?>[];
      final errors = <Object>[];
      final subscription = transport.receive().listen(
        messages.add,
        onError: errors.add,
      );
      addTearDown(subscription.cancel);
      socket.frame('[999]'.toJS);
      await _drain();
      expect(messages, [isNull]);
      expect(errors, isEmpty);
      expect(transport.cleanupErrors, [isA<FormatException>()]);
      expect(transport.onDisconnect!.isCompleted, isTrue);
      expect(transport.onConnectionLost!.isCompleted, isTrue);
      expect(transport.isOpen, isFalse);
    },
  );

  test(
    'buffered malformed frames settle loss once without stream errors',
    () async {
      final harness = _installHarness();
      final transport = WebSocketTransport.withJsonSerializer(
        'ws://test.invalid/wamp',
      );
      addTearDown(transport.close);
      final opening = transport.open();
      final socket = harness.sockets.toDart.single;
      socket.opened();
      await expectDeliveredCompletion(opening);
      final messages = <AbstractMessage?>[];
      final errors = <Object>[];
      final losses = <Object?>[];
      unawaited(transport.onConnectionLost!.future.then<void>(losses.add));
      final subscription = transport.receive().listen(
        messages.add,
        onError: errors.add,
      );
      addTearDown(subscription.cancel);
      // Both frames arrive before the first async decode requests socket closure.
      socket.frame('[999]'.toJS);
      socket.frame('[998]'.toJS);
      await _drain();
      expect(messages, [isNull, isNull]);
      expect(errors, isEmpty);
      expect(losses, [isA<FormatException>()]);
      expect(transport.onDisconnect!.isCompleted, isTrue);
      expect(transport.isOpen, isFalse);
    },
  );

  test(
    'error after opening settles loss without double completing open',
    () async {
      final harness = _installHarness();
      final uncaught = <Object>[];
      final transport = WebSocketTransport.withJsonSerializer(
        'ws://test.invalid/wamp',
      );
      addTearDown(transport.close);
      final opening = _observingZone(uncaught).run(transport.open);
      final socket = harness.sockets.toDart.single;
      socket.opened();
      await expectDeliveredCompletion(opening);
      await expectDeliveredCompletion(transport.onReady);
      socket.failed();
      socket.failed();
      await _drain();
      expect(uncaught, isEmpty);
      expect(transport.onConnectionLost!.isCompleted, isTrue);
    },
  );

  test('duplicate failed handshake events are contained', () async {
    final harness = _installHarness();
    final uncaught = <Object>[];
    final transport = WebSocketTransport.withJsonSerializer(
      'ws://test.invalid/wamp',
    );
    addTearDown(transport.close);
    final opening = _observingZone(uncaught).run(transport.open);
    final socket = harness.sockets.toDart.single;
    socket.failed();
    socket.failed();
    await expectDeliveredCompletion(opening);
    await _drain();
    expect(uncaught, isEmpty);
    expect(transport.isReady, isFalse);
    expect(transport.onConnectionLost!.isCompleted, isTrue);
  });

  test('old open event cannot mark a pending replacement ready', () async {
    final harness = _installHarness();
    final transport = WebSocketTransport.withJsonSerializer(
      'ws://test.invalid/wamp',
    );
    addTearDown(transport.close);
    final firstOpening = transport.open();
    final old = harness.sockets.toDart.single;
    final replacementOpening = transport.open();
    final replacement = harness.sockets.toDart.last;
    var replacementReady = 0;
    unawaited(transport.onReady.then((_) => replacementReady++));
    old.opened();
    await expectDeliveredCompletion(firstOpening);
    await _drain();
    final beforeOwnOpen = replacementReady;
    replacement.opened();
    await expectDeliveredCompletion(replacementOpening);
    await _drain();
    expect(beforeOwnOpen, 0);
    expect(replacementReady, 1);
    expect(transport.isOpen, isTrue);
    expect(transport.onConnectionLost!.isCompleted, isFalse);
  });

  test(
    'old handshake error cannot signal loss for a ready replacement',
    () async {
      final harness = _installHarness();
      final transport = WebSocketTransport.withJsonSerializer(
        'ws://test.invalid/wamp',
      );
      addTearDown(transport.close);
      final firstOpening = transport.open();
      final oldLoss = transport.onConnectionLost!;
      final old = harness.sockets.toDart.single;
      final replacementOpening = transport.open();
      final replacement = harness.sockets.toDart.last;
      replacement.opened();
      await expectDeliveredCompletion(replacementOpening);
      old.failed();
      await expectDeliveredCompletion(firstOpening);
      await _drain();
      expect(
        oldLoss.isCompleted,
        isFalse,
        reason: 'replacement retired the old attempt and its loss notification',
      );
      expect(transport.onConnectionLost!.isCompleted, isFalse);
      expect(transport.isOpen, isTrue);
      expect(replacement.closeCalls, 0);
    },
  );

  for (final malformed in [false, true]) {
    test('late Blob decode is isolated: malformed=$malformed', () async {
      final harness = _installHarness();
      final transport = WebSocketTransport.withMsgpackSerializer(
        'ws://test.invalid/wamp',
      );
      addTearDown(transport.close);
      final firstOpening = transport.open();
      final old = harness.sockets.toDart.single;
      old.opened();
      await expectDeliveredCompletion(firstOpening);
      final oldMessages = <AbstractMessage?>[];
      final oldSubscription = transport.receive().listen(oldMessages.add);
      addTearDown(oldSubscription.cancel);
      old.deferredFrame();
      await _drain();

      final replacementOpening = transport.open();
      final replacement = harness.sockets.toDart.last;
      replacement.opened();
      await expectDeliveredCompletion(replacementOpening);
      final newMessages = <AbstractMessage?>[];
      final newSubscription = transport.receive().listen(newMessages.add);
      addTearDown(newSubscription.cancel);
      old.finishFrame(
        (malformed
                ? Uint8List.fromList([0x91, 0xcd, 0x03, 0xe7])
                : msgpack.Serializer().serialize(
                    Goodbye(null, Goodbye.reasonNormal),
                  ))
            .toJS,
      );
      await _drain();
      expect(oldMessages, malformed ? [isNull] : [isA<Goodbye>()]);
      expect(newMessages, isEmpty);
      expect(transport.isOpen, isTrue);
      expect(replacement.closeCalls, 0);
      expect(transport.onConnectionLost!.isCompleted, isFalse);
      expect(transport.onDisconnect!.isCompleted, isFalse);

      replacement.closed(1001);
      await _drain();
      expect(transport.onConnectionLost!.isCompleted, isTrue);
      expect(transport.onDisconnect!.isCompleted, isFalse);
    });
  }

  test(
    'duplicate open events settle readiness once without callback errors',
    () async {
      final harness = _installHarness();
      final uncaught = <Object>[];
      final transport = WebSocketTransport.withJsonSerializer(
        'ws://test.invalid/wamp',
      );
      addTearDown(transport.close);
      final opening = _observingZone(uncaught).run(transport.open);
      final socket = harness.sockets.toDart.single;
      var readyCount = 0;
      unawaited(transport.onReady.then((_) => readyCount++));
      socket.opened();
      socket.opened();
      await expectDeliveredCompletion(opening);
      await _drain();
      expect(uncaught, isEmpty);
      expect(readyCount, 1);
      expect(transport.onConnectionLost!.isCompleted, isFalse);
    },
  );

  test(
    'explicit close prevents a pending open event from reporting readiness',
    () async {
      final harness = _installHarness();
      final transport = WebSocketTransport.withJsonSerializer(
        'ws://test.invalid/wamp',
      );
      addTearDown(transport.close);
      final opening = transport.open();
      final socket = harness.sockets.toDart.single;
      final disconnect = transport.onDisconnect!;
      var readyCount = 0;
      unawaited(transport.onReady.then((_) => readyCount++));
      await transport.close();
      socket.opened();
      await expectDeliveredCompletion(opening);
      await _drain();
      expect(readyCount, 0);
      expect(transport.isReady, isFalse);
      expect(disconnect.isCompleted, isTrue);
      expect(transport.onConnectionLost!.isCompleted, isFalse);
      expect(socket.closeCalls, 1);
    },
  );

  for (final received in [false, true]) {
    for (final goodbyeOnOld in [false, true]) {
      test(
        'late close uses its own Goodbye: old=$goodbyeOnOld received=$received',
        () async {
          final harness = _installHarness();
          final transport = WebSocketTransport.withMsgpackSerializer(
            'ws://test.invalid/wamp',
          );
          addTearDown(transport.close);
          final firstOpening = transport.open();
          final old = harness.sockets.toDart.single;
          old.opened();
          await expectDeliveredCompletion(firstOpening);
          final oldLoss = transport.onConnectionLost!;
          final oldDisconnect = transport.onDisconnect!;
          final oldSubscription = transport.receive().listen((_) {});
          addTearDown(oldSubscription.cancel);
          if (goodbyeOnOld) {
            if (received) {
              old.deferredFrame();
              await _drain();
              old.finishFrame(
                msgpack.Serializer()
                    .serialize(Goodbye(null, Goodbye.reasonNormal))
                    .toJS,
              );
              await _drain();
            } else {
              transport.send(Goodbye(null, Goodbye.reasonNormal));
            }
          }

          final replacementOpening = transport.open();
          final replacement = harness.sockets.toDart.last;
          replacement.opened();
          await expectDeliveredCompletion(replacementOpening);
          final newSubscription = transport.receive().listen((_) {});
          addTearDown(newSubscription.cancel);
          if (!goodbyeOnOld) {
            if (received) {
              replacement.deferredFrame();
              await _drain();
              replacement.finishFrame(
                msgpack.Serializer()
                    .serialize(Goodbye(null, Goodbye.reasonNormal))
                    .toJS,
              );
              await _drain();
            } else {
              transport.send(Goodbye(null, Goodbye.reasonNormal));
            }
          }
          old.closed(1001);
          await _drain();
          expect(oldDisconnect.isCompleted, goodbyeOnOld);
          expect(oldLoss.isCompleted, !goodbyeOnOld);
          expect(transport.onConnectionLost!.isCompleted, isFalse);
          expect(transport.onDisconnect!.isCompleted, isFalse);
          expect(transport.isOpen, isTrue);
          replacement.closed(1001);
          await _drain();
          expect(transport.onDisconnect!.isCompleted, !goodbyeOnOld);
          expect(transport.onConnectionLost!.isCompleted, goodbyeOnOld);
        },
      );
    }
  }
  for (final interval in [null, Duration.zero, const Duration(seconds: 1)]) {
    test('ping interval diagnostic preserves readiness: $interval', () async {
      final harness = _installHarness();
      final transport = WebSocketTransport.withJsonSerializer(
        'ws://test.invalid/wamp',
      );
      addTearDown(transport.close);
      final oldLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = oldLevel);
      final warnings = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen((record) {
        if (record.loggerName == 'Connectanum.WebSocketTransport') {
          warnings.add(record);
        }
      });
      addTearDown(subscription.cancel);
      final opening = transport.open(pingInterval: interval);
      final socket = harness.sockets.toDart.single;
      socket.opened();
      await expectDeliveredCompletion(opening);
      await _drain();
      expect(transport.isReady, isTrue);
      expect(transport.onConnectionLost!.isCompleted, isFalse);
      expect(
        warnings.map((record) => record.message),
        interval == null
            ? isEmpty
            : [
                'The browsers WebSocket API does not support ping interval configuration.',
              ],
      );
      if (interval != null) expect(warnings.single.level, Level.INFO);
    });
  }

  for (final receiving in [false, true]) {
    test(
      'ordinary message is not a graceful Goodbye: receiving=$receiving',
      () async {
        final harness = _installHarness();
        final transport = WebSocketTransport.withJsonSerializer(
          'ws://test.invalid/wamp',
        );
        addTearDown(transport.close);
        final opening = transport.open();
        final socket = harness.sockets.toDart.single;
        socket.opened();
        await expectDeliveredCompletion(opening);
        final messages = <AbstractMessage?>[];
        final subscription = transport.receive().listen(messages.add);
        addTearDown(subscription.cancel);
        if (receiving) {
          socket.frame('[2,42,{}]'.toJS);
          await _drain();
          expect(messages, [isA<Welcome>()]);
        } else {
          transport.send(Hello('realm1', Details()));
          expect(socket.sent.toDart.single.dartify(), '[1,"realm1",{}]');
        }
        socket.closed(1001);
        await _drain();
        expect(transport.onConnectionLost!.isCompleted, isTrue);
        expect(transport.onDisconnect!.isCompleted, isFalse);
      },
    );
  }
}
