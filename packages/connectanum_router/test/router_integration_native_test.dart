@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library router_integration_native_test;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:connectanum_router/src/native/runtime.dart';
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
  int pollMessageHandle(int connectionId) => _pollMessageHandleSafe(connectionId);

  int _pollMessageHandleSafe(int connectionId) {
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
    // Tests observe boss notifications; no outbound frame needed.
  }

  @override
  void applyRouterConfig(Uint8List config) => _inner.applyRouterConfig(config);

  int enqueueTestMessage({
    required int connectionId,
    required NativeMessageSerializer serializer,
    required Uint8List frame,
  }) =>
      _inner.enqueueTestMessage(
        connectionId: connectionId,
        serializer: serializer,
        frame: frame,
      );

  void clearTestMessages() => _inner.clearTestMessages();
}

class _RouterHarness {
  _RouterHarness._({
    required this.connectionId,
    required NativeTransportRuntime innerRuntime,
    required this.runtime,
    required this.binding,
    required StreamController<Map<String, Object?>> events,
    required StreamQueue<Map<String, Object?>> eventQueue,
  })  : _innerRuntime = innerRuntime,
        _events = events,
        _eventQueue = eventQueue,
        _statePort = binding.debugStatePort!;

  final int connectionId;
  final NativeTransportRuntime _innerRuntime;
  final _HybridRuntime runtime;
  final RouterBinding binding;
  final StreamController<Map<String, Object?>> _events;
  final StreamQueue<Map<String, Object?>> _eventQueue;
  final SendPort _statePort;
  int? _sessionId;
  bool _disposed = false;

  static Future<_RouterHarness> start({
    required int connectionId,
    required String? nativeLib,
  }) async {
    final innerRuntime = NativeTransportRuntime(libraryPath: nativeLib);
    final runtime = _HybridRuntime(innerRuntime, [connectionId]);
    runtime.start();
    runtime.clearTestMessages();

    final events = StreamController<Map<String, Object?>>.broadcast();
    final binding = Router(
      _buildConfig(),
      settings: _buildSettings(),
    ).start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          events.add(event);
        }
      },
    );
    final eventQueue = StreamQueue<Map<String, Object?>>(events.stream);

    final harness = _RouterHarness._(
      connectionId: connectionId,
      innerRuntime: innerRuntime,
      runtime: runtime,
      binding: binding,
      events: events,
      eventQueue: eventQueue,
    );
    await harness._awaitEvent('worker_registered');
    await harness._awaitEvent('worker_ready');
    return harness;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    runtime.clearTestMessages();
    await binding.dispose();
    await _eventQueue.cancel(immediate: true);
    await _events.close();
    runtime.shutdown();
    _innerRuntime.dispose();
  }

  Future<Map<String, Object?>> _awaitEvent(String type) =>
      _nextEvent(_eventQueue, type);

  Future<Map<String, Object?>> nextEvent(String type) =>
      _nextEvent(_eventQueue, type);

  Future<int> ensureSession() async {
    if (_sessionId != null) {
      return _sessionId!;
    }
    _enqueueHello(runtime, connectionId);
    _sessionId = await _awaitSessionId(_statePort, connectionId);
    return _sessionId!;
  }

  Future<int> registerProcedure({
    Map<String, Object?> details = const {},
  }) async {
    final sessionId = await ensureSession();
    return _registerProcedureWithRetry(
      _statePort,
      sessionId,
      details: details,
    );
  }

  void enqueueCall({
    required int requestId,
    bool receiveProgress = false,
  }) {
    _enqueueCall(
      runtime,
      connectionId,
      requestId,
      receiveProgress: receiveProgress,
    );
  }

  void enqueueYield({
    required int invocationId,
    required bool progress,
    required List<dynamic> arguments,
  }) {
    _enqueueYield(
      runtime,
      connectionId,
      invocationId,
      progress: progress,
      arguments: arguments,
    );
  }

  void enqueueInvocationError({
    required int invocationId,
    String errorUri = 'wamp.error.runtime_error',
  }) {
    _enqueueInvocationError(
      runtime,
      connectionId,
      invocationId,
      errorUri: errorUri,
    );
  }

  void enqueueCancel({
    required int requestId,
    String mode = 'killnowait',
  }) {
    _enqueueCancel(
      runtime,
      connectionId,
      requestId,
      mode: mode,
    );
  }

  Future<void> expectInvocationCleared(int invocationId) async {
    final replyPort = ReceivePort();
    _statePort.send(
      InvocationGetCommand(
        realmUri: 'realm1',
        invocationId: invocationId,
        replyPort: replyPort.sendPort,
      ),
    );
    final result = await replyPort.first;
    replyPort.close();
    expect(result, isNull, reason: 'Invocation $invocationId still present');
  }

  Future<List<dynamic>> nextWorkerSendPayload({int? expectedCode}) async {
    while (true) {
      final event = await nextEvent('worker_send');
      final payload = event['payload'];
      if (payload is! Uint8List) {
        continue;
      }
      final decoded = json.decode(utf8.decode(payload)) as List<dynamic>;
      if (expectedCode == null || decoded.first == expectedCode) {
        return decoded;
      }
    }
  }

  Future<int> subscribe({
    required String topic,
    required int requestId,
  }) async {
    await ensureSession();
    _enqueueSubscribe(runtime, connectionId, requestId, topic: topic);
    return _awaitSubscriptionId(
      _statePort,
      sessionId: _sessionId!,
      topic: topic,
    );
  }

  void publish({
    required int requestId,
    required String topic,
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
    bool acknowledge = false,
  }) {
    _enqueuePublish(
      runtime,
      connectionId,
      requestId,
      topic: topic,
      arguments: arguments,
      argumentsKeywords: argumentsKeywords,
      acknowledge: acknowledge,
    );
  }
}

void main() {
  final nativeLib = _resolveNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport with --features ffi-test first.'
      : null;

  group('Router + FFI test mode', () {
    test('forwards progressive and final results', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession();
      await harness.registerProcedure();

      const requestId = 42;
      harness.enqueueCall(requestId: requestId, receiveProgress: true);
      final invocationEvent = await harness.nextEvent(
        'worker_forward_native_invocation',
      );
      final invocationId = invocationEvent['invocationId'] as int;

      harness.enqueueYield(
        invocationId: invocationId,
        progress: true,
        arguments: const ['chunk'],
      );
      final progressEvent = await harness.nextEvent(
        'worker_forward_native_result',
      );
      expect(progressEvent['progress'], isTrue);
      expect(progressEvent['requestId'], equals(requestId));

      harness.enqueueYield(
        invocationId: invocationId,
        progress: false,
        arguments: const ['complete'],
      );
      final finalEvent = await harness.nextEvent(
        'worker_forward_native_result',
      );
      expect(finalEvent['progress'], isFalse);
      expect(finalEvent['requestId'], equals(requestId));

      await harness.expectInvocationCleared(invocationId);
    }, skip: skipReason);

    test('propagates callee errors', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession();
      await harness.registerProcedure();

      const requestId = 99;
      harness.enqueueCall(requestId: requestId);
      final invocationEvent = await harness.nextEvent(
        'worker_forward_native_invocation',
      );
      final invocationId = invocationEvent['invocationId'] as int;

      harness.enqueueInvocationError(
        invocationId: invocationId,
        errorUri: 'wamp.error.runtime_error',
      );

      final errorEvent = await harness.nextEvent(
        'worker_forward_native_error',
      );
      expect(errorEvent['connectionId'], equals(9102));
      expect(errorEvent['requestId'], equals(requestId));

      await harness.expectInvocationCleared(invocationId);
    }, skip: skipReason);

    test('handles caller cancellation', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession();
      await harness.registerProcedure();

      const requestId = 123;
      harness.enqueueCall(requestId: requestId);
      final invocationEvent = await harness.nextEvent(
        'worker_forward_native_invocation',
      );
      final invocationId = invocationEvent['invocationId'] as int;

      harness.enqueueCancel(requestId: requestId, mode: 'killnowait');

      await harness.nextEvent('worker_forward_message');

      await harness.expectInvocationCleared(invocationId);
    }, skip: skipReason);

    test('forwards native events to subscribers', () async {
      final harness = await _RouterHarness.start(
        connectionId: 9102,
        nativeLib: nativeLib,
      );
      addTearDown(harness.dispose);

      await harness.ensureSession();
      final subscriptionId = await harness.subscribe(
        topic: 'com.example.topic',
        requestId: 1,
      );
      // ignore: avoid_print
      print(' subscriptionId result: $subscriptionId');
      expect(subscriptionId, greaterThan(0));

      harness.publish(
        requestId: 2,
        topic: 'com.example.topic',
        arguments: const ['payload'],
        acknowledge: true,
      );

      final event = await harness.nextEvent('worker_forward_native_event');
      // ignore: avoid_print
      print('event map: $event');
      expect(event['connectionId'], equals(9102));
      expect(event['subscriptionId'], equals(subscriptionId));
      expect(event['handle'], isA<int>());
      expect(event['handle'], greaterThan(0));

    }, skip: skipReason);
  });
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
      RoleSettingsBuilder('anonymous')
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('')
            ..allowOperations(const [
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
  throw StateError('Stream ended while waiting for $type');
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
  int sessionId, {
  Map<String, Object?> details = const {},
  int maxAttempts = 50,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final replyPort = ReceivePort();
    commandPort.send(
      ProcedureRegisterCommand(
        realmUri: 'realm1',
        sessionId: sessionId,
        procedure: 'com.example.proc',
        details: Map<String, Object?>.from(details),
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

Future<int> _awaitSessionId(
  SendPort commandPort,
  int connectionId, {
  int maxAttempts = 100,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final snapshot = await _fetchSnapshot(commandPort);
    for (final session in snapshot.sessions) {
      if (session.connectionId == connectionId) {
        return session.id;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Session for connection $connectionId not found');
}

Future<int> _awaitSubscriptionId(
  SendPort commandPort, {
  required int sessionId,
  required String topic,
  int maxAttempts = 100,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final snapshot = await _fetchSnapshot(commandPort);
    for (final subscription in snapshot.subscriptions) {
      // ignore: avoid_print
      print('snapshot subscription: id=${subscription.id}, topic=${subscription.topic}, subs=${subscription.subscribers.map((s) => s.sessionId).toList()}');
      if (subscription.topic == topic) {
        final match = subscription.subscribers.any(
          (subscriber) => subscriber.sessionId == sessionId,
        );
        if (match) {
          return subscription.id;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Subscription for topic $topic not found');
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
  int connectionId,
  int requestId, {
  required bool receiveProgress,
}) {
  final options =
      receiveProgress ? '{"receive_progress":true}' : '{}';
  final frame = utf8.encode(
    '[48,$requestId,$options,"com.example.proc"]',
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

void _enqueueInvocationError(
  _HybridRuntime runtime,
  int connectionId,
  int invocationId, {
  required String errorUri,
}) {
  final frame = utf8.encode(
    '[8,68,$invocationId,{},"$errorUri"]',
  );
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueueCancel(
  _HybridRuntime runtime,
  int connectionId,
  int requestId, {
  required String mode,
}) {
  final frame = utf8.encode('[49,$requestId,{"mode":"$mode"}]');
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueueSubscribe(
  _HybridRuntime runtime,
  int connectionId,
  int requestId, {
  required String topic,
}) {
  final frame = utf8.encode('[32,$requestId,{},"$topic"]');
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(frame),
  );
}

void _enqueuePublish(
  _HybridRuntime runtime,
  int connectionId,
  int requestId, {
  required String topic,
  List<dynamic>? arguments,
  Map<String, Object?>? argumentsKeywords,
  required bool acknowledge,
}) {
  final options = <String, Object?>{
    if (acknowledge) 'acknowledge': true,
  };
  final buffer = StringBuffer()
    ..write('[16,$requestId,${json.encode(options)},"$topic"');
  if (arguments != null) {
    buffer
      ..write(',')
      ..write(json.encode(arguments));
    if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
      buffer
        ..write(',')
        ..write(json.encode(argumentsKeywords));
    }
  } else if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
    buffer.write(',[],${json.encode(argumentsKeywords)}');
  }
  buffer.write(']');
  runtime.enqueueTestMessage(
    connectionId: connectionId,
    serializer: NativeMessageSerializer.json,
    frame: Uint8List.fromList(utf8.encode(buffer.toString())),
  );
}
