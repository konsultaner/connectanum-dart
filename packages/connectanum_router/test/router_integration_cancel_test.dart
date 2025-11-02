@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library router_integration_cancel_test;

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:connectanum_core/src/message/cancel.dart' as cancel_msg;
import 'package:connectanum_core/src/message/error.dart' as error_msg;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/session.dart';
import 'package:test/test.dart';

class _QueueRuntime implements NativeRuntimeWithHandles {
  _QueueRuntime(List<int> connectionSequence, {String? libraryPathHint})
    : _connections = Queue<int>.from(connectionSequence),
      _libraryPathHint = libraryPathHint;

  final Queue<int> _connections;
  final Map<int, int> _ports = {};
  int _nextListenerId = 1;
  final String? _libraryPathHint;

  @override
  void applyRouterConfig(Uint8List config) {}

  @override
  int connectionMaxRawSocketExponent(int connectionId) => 16;

  @override
  String? get libraryPathHint => _libraryPathHint;

  @override
  int getLocalPort(int listenerId) => _ports[listenerId] ?? 0;

  @override
  int listen(String host, int port, {int backlog = 128}) {
    final id = _nextListenerId++;
    _ports[id] = port == 0 ? 7200 + id : port;
    return id;
  }

  @override
  int pollConnection(int listenerId) =>
      _connections.isEmpty ? 0 : _connections.removeFirst();

  @override
  NativeIncomingMessage? pollMessage(int connectionId) => null;

  @override
  int pollMessageHandle(int connectionId) => 0;

  @override
  int retainMessageHandle(int handle) => handle;

  @override
  void releaseMessageHandle(int handle) {}

  @override
  void forwardPublishEvent({
    required int handle,
    required int connectionId,
    required int subscriptionId,
    required int publicationId,
    int? publisherSessionId,
    String? topic,
  }) {}

  @override
  void forwardCallInvocation({
    required int handle,
    required int connectionId,
    required int invocationId,
    required int registrationId,
    int? callerSessionId,
    String? procedure,
    bool? receiveProgress,
  }) {}

  @override
  void forwardResultFromYield({
    required int handle,
    required int connectionId,
    required int requestId,
    required bool progress,
  }) {}

  @override
  void forwardInvocationError({
    required int handle,
    required int connectionId,
    required int requestType,
    required int requestId,
  }) {}

  @override
  void sendMessage(int connectionId, Uint8List payload) {}

  @override
  void shutdown() {}

  @override
  void start() {}
}

RouterConfig _buildConfig() => RouterConfig(
  endpoints: [
    Endpoint(
      host: '127.0.0.1',
      port: 9090,
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

  final listener = ListenerSettingsBuilder('rawsocket', '127.0.0.1:9090')
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

String? _resolveNativeLib() {
  final env = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return env;
  }
  const candidates = [
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

void main() {
  final nativeLib = _resolveNativeLib();

  group('Router integration', () {
    final skipReason = nativeLib == null
        ? 'libct_ffi.so missing; build native transport first.'
        : null;

    test(
      'internal caller cancels external callee and router forwards',
      () async {
        final runtime = _QueueRuntime([9101], libraryPathHint: nativeLib);
        final events = StreamController<Map<String, Object?>>.broadcast();
        addTearDown(events.close);

        final binding = Router(_buildConfig(), settings: _buildSettings())
            .start(
              runtime,
              onEvent: (event) {
                if (event is Map<String, Object?>) {
                  events.add(event);
                }
              },
            );
        addTearDown(binding.dispose);

        final eventQueue = StreamQueue(events.stream);
        addTearDown(() => eventQueue.cancel());

        await _nextEvent(eventQueue, 'worker_registered');

        final statePort = binding.debugStatePort!;
        final listener = binding.listeners.first;
        final externalSession = SessionRecord(
          id: 8801,
          authId: null,
          authRole: null,
          roles: const {},
          workerId: 1,
          connectionId: 9101,
          lastActivity: DateTime.now(),
          listener: listener,
        );
        statePort.send(
          SessionOpenCommand(realmUri: 'realm1', session: externalSession),
        );

        final registerReply = ReceivePort();
        statePort.send(
          ProcedureRegisterCommand(
            realmUri: 'realm1',
            sessionId: 8801,
            procedure: 'com.example.proc',
            details: const {},
            replyPort: registerReply.sendPort,
          ),
        );
        await registerReply.first;
        registerReply.close();

        final caller = await binding.createInternalSession(realmUri: 'realm1');
        addTearDown(caller.close);

        final errorCompleter = Completer<error_msg.Error>();
        final cancelCompleter = Completer<String>();
        final subscription = caller
            .call('com.example.proc', cancelCompleter: cancelCompleter)
            .listen(
              (_) {},
              onError: (Object error, StackTrace stackTrace) {
                if (error is error_msg.Error && !errorCompleter.isCompleted) {
                  errorCompleter.complete(error);
                }
              },
            );
        addTearDown(subscription.cancel);

        final firstForward = await _nextEvent(eventQueue, 'worker_send');
        expect(firstForward['connectionId'], equals(9101));

        cancelCompleter.complete(cancel_msg.CancelOptions.modeKillNoWait);

        final secondForward = await _nextEvent(eventQueue, 'worker_send');
        expect(secondForward['connectionId'], equals(9101));

        final error = await errorCompleter.future;
        expect(error.error, equals(error_msg.Error.errorInvocationCanceled));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
