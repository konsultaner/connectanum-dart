import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';

// A native WebSocket handshake must not block the isolate pumping the router.
class NativeReplyCallee {
  NativeReplyCallee._(
    this._isolate,
    this._port,
    this._subscription,
    this._control,
    this._closed,
  );

  final Isolate _isolate;
  final ReceivePort _port;
  final StreamSubscription<dynamic> _subscription;
  final SendPort _control;
  final Future<int> _closed;
  Future<int>? _closing;

  static Future<NativeReplyCallee> start({
    required bool webSocket,
    required String wireSerializer,
    required int rawPort,
    required String webUrl,
    required String nativeLib,
  }) async {
    final port = ReceivePort();
    final ready = Completer<SendPort>();
    final closed = Completer<int>();
    closed.future.ignore();
    final subscription = port.listen((dynamic event) {
      if (event is Map && event['type'] == 'ready') {
        ready.complete(event['control'] as SendPort);
      } else if (event is Map && event['type'] == 'closed') {
        closed.complete(event['count'] as int);
      } else {
        final error = StateError('Native reply callee failed: $event');
        if (!ready.isCompleted) ready.completeError(error);
        if (!closed.isCompleted) closed.completeError(error);
      }
    });
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(_run, <String, Object>{
        'status': port.sendPort,
        'webSocket': webSocket,
        'wireSerializer': wireSerializer,
        'rawPort': rawPort,
        'webUrl': webUrl,
        'nativeLib': nativeLib,
      }, onError: port.sendPort);
      final control = await ready.future.timeout(const Duration(seconds: 15));
      return NativeReplyCallee._(
        isolate,
        port,
        subscription,
        control,
        closed.future,
      );
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      await subscription.cancel();
      port.close();
      rethrow;
    }
  }

  Future<int> close() => _closing ??= _close();

  Future<int> _close() async {
    _control.send(null);
    try {
      return await _closed.timeout(const Duration(seconds: 15));
    } finally {
      _isolate.kill(priority: Isolate.immediate);
      await _subscription.cancel();
      _port.close();
    }
  }

  static Future<void> _run(Map<String, Object> config) async {
    final status = config['status'] as SendPort;
    final control = ReceivePort();
    final webUrl = config['webUrl'] as String;
    final port = config['rawPort'] as int;
    final lib = config['nativeLib'] as String;
    final serializer = config['wireSerializer'] as String;
    final AbstractTransport transport;
    if (config['webSocket'] == true) {
      transport = switch (serializer) {
        'msgpack' => NativeWebSocketTransport.withMsgpackSerializer(
          webUrl,
          null,
          false,
          lib,
        ),
        'cbor' => NativeWebSocketTransport.withCborSerializer(
          webUrl,
          null,
          false,
          lib,
        ),
        _ => NativeWebSocketTransport.withJsonSerializer(
          webUrl,
          null,
          false,
          lib,
        ),
      };
    } else {
      transport = switch (serializer) {
        'msgpack' => NativeRawSocketTransport.withMsgpackSerializer(
          '127.0.0.1',
          port,
          libraryPath: lib,
        ),
        'cbor' => NativeRawSocketTransport.withCborSerializer(
          '127.0.0.1',
          port,
          libraryPath: lib,
        ),
        _ => NativeRawSocketTransport.withJsonSerializer(
          '127.0.0.1',
          port,
          libraryPath: lib,
        ),
      };
    }
    final client = Client(
      realm: 'bench.secure',
      authId: 'bench-user',
      authenticationMethods: [TicketAuthentication('bench-ticket')],
      transport: transport,
      e2eeProvider: WampCborXsalsa20Poly1305Provider.single(
        keyId: 'native-reply',
        key: Uint8List.fromList(List.generate(32, (index) => index + 1)),
      ),
    );
    var received = 0;
    try {
      final session = await client.connect().first;
      await session.registerLazyPayloadHandler('bench.rpc.native_lazy', (
        invocation,
      ) {
        final representation = invocation.arguments![0] as String;
        final mode = invocation.arguments![1] as String;
        received++;
        final args = <dynamic>['reply', received];
        final kwargs = <String, dynamic>{'shape': representation};
        final payload = switch (representation) {
          'materialized' => LazyMessagePayload.materialized(
            arguments: args,
            argumentsKeywords: kwargs,
          ),
          'encoded' => LazyMessagePayload.encoded(
            encoding: LazyPayloadEncoding.json,
            argumentsBytes: Uint8List.fromList(utf8.encode(jsonEncode(args))),
            argumentsDecoder: (bytes) =>
                jsonDecode(utf8.decode(bytes)) as List<dynamic>,
            argumentsKeywordsBytes: Uint8List.fromList(
              utf8.encode(jsonEncode(kwargs)),
            ),
            argumentsKeywordsDecoder: (bytes) =>
                jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
          ),
          _ => null,
        };
        invocation.respondWith(
          lazyPayload: payload,
          arguments: representation == 'explicit' ? args : null,
          argumentsKeywords: representation == 'explicit' ? kwargs : null,
          options: YieldOptions(
            pptScheme: mode == 'wamp' ? 'wamp' : 'x_example',
            pptSerializer: mode == 'wamp' ? 'cbor' : mode,
          ),
        );
      });
      status.send({'type': 'ready', 'control': control.sendPort});
      await control.first;
    } finally {
      await client.disconnect();
      control.close();
    }
    status.send({'type': 'closed', 'count': received});
  }
}
