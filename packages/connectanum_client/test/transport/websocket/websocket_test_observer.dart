import 'dart:async';
import 'dart:js_interop';

import 'package:connectanum_client/src/transport/websocket/websocket_transport_web.dart';
import 'package:test/test.dart';

@JS('eval')
external JSAny? _evaluate(JSString source);

extension type _Observer(JSObject _) implements JSObject {
  external JSArray<_ObservedSocket> get sockets;
  external void restore();
}

extension type _ObservedSocket(JSObject _) implements JSObject {
  external JSPromise<JSString> get deliveredHandshake;
  external JSPromise<JSNumber> get deliveredClose;
  external JSPromise<JSAny?> get decodeStarted;
  external void holdNextBinaryFrame();
  external JSPromise<JSAny?> releaseDecode();
  external JSPromise<JSAny?> nextMessage();
}

// Wait for event-loop turns, not an elapsed-time budget. The caller has already
// delivered or independently observed the event that must settle this future.
Future<T> expectDeliveredCompletion<T>(
  Future<T> pending, {
  String reason = 'The delivered event must settle the pending operation.',
}) async {
  var completed = false;
  final errors = <Object>[];
  unawaited(
    pending.then<void>(
      (_) {
        completed = true;
      },
      onError: (Object error, StackTrace stack) {
        errors.add(error);
        completed = true;
      },
    ),
  );
  for (var turn = 0; turn < 3; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(completed, isTrue, reason: reason);
  expect(errors, isEmpty, reason: reason);
  return await pending;
}

class WebSocketTestObserver {
  WebSocketTestObserver()
    : _observer = _Observer(
        _evaluate(
              r'''
(() => {
  const Original = globalThis.WebSocket;
  const observer = {sockets: [], restore() { globalThis.WebSocket = Original; }};
  globalThis.WebSocket = class extends Original {
    constructor(url, protocols) {
      super(url, protocols);
      this.deliveredHandshake = new Promise(resolve => {
        this.addEventListener('open', () => resolve('open'), {once: true});
        this.addEventListener('error', () => resolve('error'), {once: true});
      });
      this.deliveredClose = new Promise(resolve => {
        this.addEventListener('close', event => resolve(event.code), {once: true});
      });
      observer.sockets.push(this);
    }
    nextMessage() {
      return new Promise(resolve => {
        this.addEventListener('message', resolve, {once: true});
      });
    }
    holdNextBinaryFrame() {
      const binaryReads = [];
      this.decodeStarted = new Promise(started => {
        const capture = ({data}) => {
          const buffer = data.arrayBuffer();
          binaryReads.push(buffer);
          const first = binaryReads.length === 1;
          data.arrayBuffer = () => {
            if (!first) return buffer;
            started();
            return new Promise(resolve => {
              this.releaseDecode = async () => {
                // The oracle must not race either real browser Blob read.
                await Promise.all(binaryReads);
                resolve(await buffer);
              };
            });
          };
          if (binaryReads.length === 2) {
            this.removeEventListener('message', capture);
          }
        };
        this.addEventListener('message', capture);
      });
    }
  };
  return observer;
})()
'''
                  .toJS,
            )
            as JSObject,
      );

  final _Observer _observer;

  void restore() => _observer.restore();

  void holdNextBinaryFrame() =>
      _observer.sockets.toDart.last.holdNextBinaryFrame();

  Future<void> decodeStarted() async {
    await _observer.sockets.toDart.last.decodeStarted.toDart;
  }

  Future<void> releaseDecode() async {
    await _observer.sockets.toDart.last.releaseDecode().toDart;
  }

  Future<void> nextMessage() async {
    await _observer.sockets.toDart.last.nextMessage().toDart;
  }

  Future<void> open(
    WebSocketTransport transport, {
    Duration? pingInterval,
    bool rejected = false,
  }) async {
    final pending = transport.open(pingInterval: pingInterval);
    final socket = _observer.sockets.toDart.last;
    final event = (await socket.deliveredHandshake.toDart).toDart;
    expect(event, rejected ? 'error' : 'open');
    await expectDeliveredCompletion(
      pending,
      reason:
          'The browser delivered $event, but transport.open did not settle.',
    );
    if (!rejected) {
      await expectDeliveredCompletion(
        transport.onReady,
        reason: 'The browser delivered open, but onReady did not complete.',
      );
    }
  }

  Future<void> closed() async {
    await _observer.sockets.toDart.last.deliveredClose.toDart;
  }
}
