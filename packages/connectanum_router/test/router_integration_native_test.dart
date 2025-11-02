@TestOn('vm')
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:connectanum_router/src/router/config/router_settings_builder.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/snapshot.dart';
import 'package:test/test.dart';

class _HybridRuntime implements NativeRuntimeWithHandles {
  _HybridRuntime(this._inner, List<int> connectionSequence)
    : _connections = Queue<int>.from(connectionSequence);

  final NativeTransportRuntime _inner;
  final Queue<int> _connections;
  final Map<int, int> _ports = {};
  int _nextListenerId = 1;

  @override
  void start() => _inner.start();

  @override
  void shutdown() => _inner.shutdown();

  @override
  int listen(String host, int port, {int backlog = 128}) {
    final id = _nextListenerId++;
    _ports[id] = port == 0 ? 7200 + id : port;
    return id;
  }

  @override
  int getLocalPort(int listenerId) => _ports[listenerId] ?? 0;

  @override
  int pollConnection(int listenerId) =>
      _connections.isEmpty ? 0 : _connections.removeFirst();

  @override
  int connectionMaxRawSocketExponent(int connectionId) => 16;

  @override
  String? get libraryPathHint => _inner.libraryPath;

  @override
  NativeIncomingMessage? pollMessage(int connectionId) =>
      _inner.pollMessage(connectionId);

  @override
  int pollMessageHandle(int connectionId) =>
      _safePollMessageHandle(connectionId);

  int _safePollMessageHandle(int connectionId) {
    try {
      return _inner.pollMessageHandle(connectionId);
    } on NativeTransportException catch (error) {
      if (error.code == NativeTransportErrorCode.connectionNotFound) {
        return 0;
      }
      rethrow;
    }
  }

  @override
  int retainMessageHandle(int handle) => _inner.retainMessageHandle(handle);

  @override
  void releaseMessageHandle(int handle) => _inner.releaseMessageHandle(handle);

  @override
  void forwardPublishEvent({
    required int handle,
    required int connectionId,
    required int subscriptionId,
    required int publicationId,
    int? publisherSessionId,
    String? topic,
  }) {
    _inner.releaseMessageHandle(handle);
  }

  @override
  void forwardCallInvocation({
    required int handle,
    required int connectionId,
    required int invocationId,
    required int registrationId,
    int? callerSessionId,
    String? procedure,
    bool? receiveProgress,
  }) {
    _inner.releaseMessageHandle(handle);
  }

  @override
  void forwardResultFromYield({
    required int handle,
    required int connectionId,
    required int requestId,
    required bool progress,
  }) {
    _inner.releaseMessageHandle(handle);
  }

  @override
  void forwardInvocationError({
    required int handle,
    required int connectionId,
    required int requestType,
    required int requestId,
  }) {
    _inner.releaseMessageHandle(handle);
  }

  @override
  void sendMessage(int connectionId, Uint8List payload) {
    // No-op: tests do not require sending data back to a client.
  }

  @override
  void applyRouterConfig(Uint8List config) => _inner.applyRouterConfig(config);

  int enqueueTestMessage({
    required int connectionId,
    required NativeMessageSerializer serializer,
    required Uint8List frame,
  }) => _inner.enqueueTestMessage(
    connectionId: connectionId,
    serializer: serializer,
    frame: frame,
  );

  void clearTestMessages() => _inner.clearTestMessages();
}

String? _resolveNativeLib() {
  final env = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return env;
  }
  const candidates = [
    'native/transport/target/ffi-test/release/libct_ffi.so',
    'native/transport/target/ffi-test/debug/libct_ffi.so',
    'native/transport/target/release/libct_ffi.so',
    'native/transport/target/debug/libct_ffi.so',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  return null;
}

RouterConfig _buildConfig() => RouterConfig(
  endpoints: [
    Endpoint(
      host: '127.0.0.1',
      port: 9093,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 16,
    ),
  ],
);

RouterSettings _buildSettings() {
  final realmBuilder = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')..allowOperations(const [
          'register',
          'unregister',
          'subscribe',
          'unsubscribe',
          'publish',
          'call',
          'cancel',
        ]),
      ),
    );

  final listener = ListenerSettingsBuilder('rawsocket', '127.0.0.1:9093')
    ..addAuthMethod('anonymous')
    ..setOptions(const {'max_rawsocket_size_exponent': 16});

  return RouterSettingsBuilder()
      .addRealmFromBuilder(realmBuilder)
      .addListenerFromBuilder(listener)
      .addAuthenticator(
        'anonymous',
        const AuthenticatorDefinition(type: 'anonymous'),
      )
      .build();
}

Future<Map<String, Object?>> _nextEvent(
  StreamQueue<Map<String, Object?>> queue,
  String type,
) async {
  while (await queue.hasNext) {
    final event = await queue.next;
    if (event['type'] == type) {
      return event;
    }
  }
  throw StateError('Unexpected end of stream while waiting for $type');
}

Future<int> _awaitSessionId(SendPort commandPort, int connectionId) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final snapshot = await _fetchSnapshot(commandPort);
    final match = snapshot.sessions
        .where((session) => session.connectionId == connectionId)
        .map((session) => session.id)
        .cast<int?>()
        .firstWhere((id) => id != null, orElse: () => null);
    if (match != null) {
      return match;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Session for connection $connectionId not found');
}

Future<RealmSnapshot> _fetchSnapshot(SendPort commandPort) async {
  final replyPort = ReceivePort();
  commandPort.send(
    RealmSnapshotCommand(
      realmUri: 'realm1',
      knownVersion: null,
      replyPort: replyPort.sendPort,
    ),
  );
  final response = await replyPort.first as RealmSnapshotResponse;
  replyPort.close();
  return response.snapshot;
}

Future<int> _registerProcedureWithRetry(
  SendPort commandPort,
  int sessionId,
) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final replyPort = ReceivePort();
    commandPort.send(
      ProcedureRegisterCommand(
        realmUri: 'realm1',
        sessionId: sessionId,
        procedure: 'com.example.proc',
        details: const {},
        replyPort: replyPort.sendPort,
      ),
    );
    final result = await replyPort.first;
    replyPort.close();
    if (result is int) {
      return result;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Timed out registering procedure for session $sessionId');
}

void _enqueueHello(_HybridRuntime runtime, int connectionId) {
  final frame = utf8.encode(
    '[1,"realm1",{"roles":{"caller":{"features":{}},"callee":{"features":{}}}}]',
  );
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueueCall(
  _HybridRuntime runtime,
  int connectionId, {
  required int requestId,
}) {
  final frame = utf8.encode(
    '[48,$requestId,{"receive_progress":true},"com.example.proc"]',
  );
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueueYield(
  _HybridRuntime runtime,
  int connectionId,
  int invocationId, {
  required bool progress,
  required List<dynamic> arguments,
}) {
  final details = progress ? '{"progress":true}' : '{}';
  final frame = utf8.encode(
    '[70,$invocationId,$details,${json.encode(arguments)}]',
  );
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void main() {
  final nativeLib = _resolveNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport with --features ffi-test first.'
      : null;

  group('Router + FFI test mode', () {
    test('worker forwards native RESULT events for enqueued yields', () async {
      const connectionId = 9102;
      final innerRuntime = NativeTransportRuntime(libraryPath: nativeLib);
      final runtime = _HybridRuntime(innerRuntime, const [connectionId]);
      addTearDown(() {
        runtime.shutdown();
        innerRuntime.dispose();
      });
      expect(
        innerRuntime.supportsTestHooks,
        isTrue,
        reason:
            'libct_ffi.so was built without the ffi-test feature; rebuild with cargo build -p ct_ffi --features ffi-test',
      );

      runtime.start();
      addTearDown(runtime.clearTestMessages);

      final events = StreamController<Map<String, Object?>>.broadcast();
      addTearDown(events.close);

      final observedEvents = <Map<String, Object?>>[];
      final eventSubscription = events.stream.listen(observedEvents.add);
      addTearDown(eventSubscription.cancel);

      final binding = Router(_buildConfig(), settings: _buildSettings()).start(
        runtime,
        onEvent: (event) {
          if (event is Map<String, Object?>) {
            events.add(event);
          }
        },
      );
      addTearDown(binding.dispose);

      final eventQueue = StreamQueue<Map<String, Object?>>(events.stream);
      addTearDown(eventQueue.cancel);

      await _nextEvent(eventQueue, 'worker_registered');
      await _nextEvent(eventQueue, 'worker_ready');

      _enqueueHello(runtime, connectionId);

      final statePort = binding.debugStatePort!;
      final sessionId = await _awaitSessionId(statePort, connectionId);

      final registrationId = await _registerProcedureWithRetry(
        statePort,
        sessionId,
      );
      expect(registrationId, greaterThan(0));

      const requestId = 42;
      _enqueueCall(runtime, connectionId, requestId: requestId);

      final invocationEvent = await _nextEvent(
        eventQueue,
        'worker_forward_native_invocation',
      );
      final invocationId = invocationEvent['invocationId'] as int;
      expect(invocationEvent['connectionId'], equals(connectionId));

      _enqueueYield(
        runtime,
        connectionId,
        invocationId,
        progress: true,
        arguments: const ['chunk'],
      );
      final progressEvent = await _nextEvent(
        eventQueue,
        'worker_forward_native_result',
      );
      expect(progressEvent['progress'], isTrue);
      expect(progressEvent['requestId'], equals(requestId));

      _enqueueYield(
        runtime,
        connectionId,
        invocationId,
        progress: false,
        arguments: const ['complete'],
      );
      final finalEvent = await _nextEvent(
        eventQueue,
        'worker_forward_native_result',
      );
      expect(finalEvent['progress'], isFalse);
      expect(finalEvent['requestId'], equals(requestId));

      final invocationReply = ReceivePort();
      statePort.send(
        InvocationGetCommand(
          realmUri: 'realm1',
          invocationId: invocationId,
          replyPort: invocationReply.sendPort,
        ),
      );
      final invocationRecord = await invocationReply.first;
      invocationReply.close();
      expect(invocationRecord, isNull);
    }, skip: skipReason);
  });
}
