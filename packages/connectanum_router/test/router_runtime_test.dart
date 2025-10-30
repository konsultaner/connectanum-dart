@TestOn('vm')
import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart'
    show MessageTypes, Publish;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:connectanum_router/src/router/config/router_settings_builder.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

class _FakeRuntime implements NativeRuntime {
  final List<String> listenCalls = [];
  Uint8List? appliedConfig;
  final Map<int, int> _ports = {};
  int _nextId = 1;
  final Map<int, Queue<int>> _pendingConnections = {};
  final Map<int, Queue<NativeIncomingMessage>> _pendingMessages = {};
  final Map<int, List<Uint8List>> sentMessages = {};

  @override
  void applyRouterConfig(Uint8List config) {
    appliedConfig = config;
  }

  @override
  int getLocalPort(int listenerId) => _ports[listenerId] ?? listenerId;

  @override
  int listen(String host, int port, {int backlog = 128}) {
    final id = _nextId++;
    listenCalls.add('$host:$port:$backlog');
    _ports[id] = port == 0 ? 5000 + id : port;
    return id;
  }

  @override
  int pollConnection(int listenerId) {
    final queue = _pendingConnections[listenerId];
    if (queue == null || queue.isEmpty) {
      return 0;
    }
    return queue.removeFirst();
  }

  @override
  int connectionMaxRawSocketExponent(int connectionId) => 16;

  @override
  void sendMessage(int connectionId, Uint8List payload) {
    sentMessages.putIfAbsent(connectionId, () => []).add(payload);
  }

  @override
  NativeIncomingMessage? pollMessage(int connectionId) {
    final queue = _pendingMessages[connectionId];
    if (queue == null || queue.isEmpty) {
      return null;
    }
    return queue.removeFirst();
  }

  @override
  void shutdown() {}

  @override
  void start() {}

  void enqueueMessage(
    int listenerId,
    int connectionId,
    NativeIncomingMessage message,
  ) {
    _pendingConnections.putIfAbsent(listenerId, Queue.new).add(connectionId);
    _pendingMessages.putIfAbsent(connectionId, Queue.new).add(message);
  }
}

class _UnsupportedConfigRuntime extends _FakeRuntime {
  @override
  void applyRouterConfig(Uint8List config) {
    throw UnsupportedError('no-op');
  }
}

class _HandleRuntime extends _FakeRuntime implements NativeRuntimeWithHandles {
  final Map<int, Queue<int>> _pendingHandles = {};
  int _nextHandle = 1;
  NativeTransportException? _scheduledError;
  final Set<int> _knownConnections = {};
  final List<Map<String, Object?>> forwardedEvents = [];
  final List<Map<String, Object?>> forwardedInvocations = [];
  final List<Map<String, Object?>> forwardedResults = [];
  final List<Map<String, Object?>> forwardedErrors = [];

  @override
  int pollMessageHandle(int connectionId) {
    final error = _scheduledError;
    if (error != null) {
      _scheduledError = null;
      throw error;
    }
    final queue = _pendingHandles[connectionId];
    if (queue == null || queue.isEmpty) {
      return 0;
    }
    return queue.removeFirst();
  }

  @override
  String? get libraryPathHint => null;

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
  }) {
    forwardedEvents.add({
      'handle': handle,
      'connectionId': connectionId,
      'subscriptionId': subscriptionId,
      'publicationId': publicationId,
      'publisherSessionId': publisherSessionId,
      'topic': topic,
    });
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
    forwardedInvocations.add({
      'handle': handle,
      'connectionId': connectionId,
      'invocationId': invocationId,
      'registrationId': registrationId,
      'callerSessionId': callerSessionId,
      'procedure': procedure,
      'receiveProgress': receiveProgress,
    });
  }

  @override
  void forwardResultFromYield({
    required int handle,
    required int connectionId,
    required int requestId,
    required bool progress,
  }) {
    forwardedResults.add({
      'handle': handle,
      'connectionId': connectionId,
      'requestId': requestId,
      'progress': progress,
    });
  }

  @override
  void forwardInvocationError({
    required int handle,
    required int connectionId,
    required int requestType,
    required int requestId,
  }) {
    forwardedErrors.add({
      'handle': handle,
      'connectionId': connectionId,
      'requestType': requestType,
      'requestId': requestId,
    });
  }

  int enqueueHandle(int listenerId, int connectionId) {
    final handle = _nextHandle++;
    if (_knownConnections.add(connectionId)) {
      _pendingConnections.putIfAbsent(listenerId, Queue.new).add(connectionId);
    }
    _pendingHandles.putIfAbsent(connectionId, Queue.new).add(handle);
    return handle;
  }

  void scheduleErrorOnce(int code, String message) {
    _scheduledError = NativeTransportException(code, message);
  }
}

const int kWorkerCmdProcess = 1;
const int kWorkerCmdShutdown = 2;
const int kWorkerCmdAddConnection = 3;
const int kWorkerCmdRemoveConnection = 4;
const int kWorkerEventRegister = 1;
const int kWorkerEventReady = 2;
const int kWorkerEventError = 3;
const int kWorkerEventShutdown = 4;
const int kWorkerEventConnectionAdded = 5;
const int kWorkerEventConnectionRemoved = 6;
const int kWorkerEventDrained = 7;
const int _workerCmdDrainConnections = 6;

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(milliseconds: 500),
  Duration pollInterval = const Duration(milliseconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(pollInterval);
  }
}

void _testWorkerEntryPoint(Map<String, Object?> init) {
  final bossPort = init['bossPort'] as SendPort;
  final connectionId = init['connectionId'] as int;
  final listenerId = init['listenerId'] as int;
  final commandPort = ReceivePort();
  final Map<int, int> connections = {connectionId: listenerId};
  final workerHash = Isolate.current.hashCode;

  bossPort.send({
    'type': kWorkerEventRegister,
    'connectionId': connectionId,
    'listenerId': listenerId,
    'commandPort': commandPort.sendPort,
    'workerHash': workerHash,
  });
  bossPort.send({'type': kWorkerEventReady, 'connectionId': connectionId});

  commandPort.listen((dynamic raw) {
    if (raw is! List || raw.isEmpty) {
      return;
    }
    final command = raw[0];
    if (command == kWorkerCmdProcess) {
      final assignedConnection = raw[1] as int;
      final handle = raw[2] as int;
      bossPort.send({
        'type': 'test_processed',
        'connectionId': assignedConnection,
        'handle': handle,
      });
      bossPort.send({
        'type': kWorkerEventReady,
        'connectionId': assignedConnection,
      });
    } else if (command == kWorkerCmdAddConnection) {
      final newListener = raw[1] as int;
      final newConnection = raw[2] as int;
      connections[newConnection] = newListener;
      bossPort.send({
        'type': kWorkerEventConnectionAdded,
        'connectionId': newConnection,
        'listenerId': newListener,
      });
      bossPort.send({'type': kWorkerEventReady, 'connectionId': newConnection});
    } else if (command == kWorkerCmdRemoveConnection) {
      final removeConnection = raw[1] as int;
      connections.remove(removeConnection);
      bossPort.send({
        'type': kWorkerEventConnectionRemoved,
        'connectionId': removeConnection,
      });
    } else if (command == kWorkerCmdShutdown) {
      commandPort.close();
      bossPort.send({
        'type': kWorkerEventShutdown,
        'connectionId': connectionId,
      });
    } else if (command == _workerCmdDrainConnections) {
      final reason = raw.length > 1 && raw[1] is String
          ? raw[1] as String
          : 'wamp.close.system_shutdown';
      bossPort.send({
        'type': 'test_drain',
        'reason': reason,
      });
      for (final entry in connections.entries.toList()) {
        bossPort.send({
          'type': 'worker_send',
          'connectionId': entry.key,
          'payload': Uint8List.fromList(
            utf8.encode(jsonEncode([MessageTypes.codeGoodbye, {}, reason])),
          ),
        });
        bossPort.send({
          'type': kWorkerEventConnectionRemoved,
          'connectionId': entry.key,
        });
        connections.remove(entry.key);
      }
      bossPort.send({
        'type': kWorkerEventDrained,
        'workerHash': workerHash,
      });
    }
  });
}

void _parallelWorkerEntryPoint(Map<String, Object?> init) {
  final bossPort = init['bossPort'] as SendPort;
  final connectionId = init['connectionId'] as int;
  final listenerId = init['listenerId'] as int;
  final commandPort = ReceivePort();
  final Map<int, int> connections = {connectionId: listenerId};
  final workerHash = Isolate.current.hashCode;
  final processedDelayed = <int>{};

  bossPort.send({
    'type': kWorkerEventRegister,
    'connectionId': connectionId,
    'listenerId': listenerId,
    'commandPort': commandPort.sendPort,
    'workerHash': workerHash,
  });
  bossPort.send({'type': kWorkerEventReady, 'connectionId': connectionId});

  commandPort.listen((dynamic raw) {
    if (raw is! List || raw.isEmpty) {
      return;
    }
    final command = raw[0];
    if (command == kWorkerCmdProcess) {
      final assignedConnection = raw[1] as int;
      final handle = raw[2] as int;

      void emitProcessed() {
        bossPort.send({
          'type': 'test_processed',
          'connectionId': assignedConnection,
          'handle': handle,
          'processedAt': DateTime.now().microsecondsSinceEpoch,
        });
        bossPort.send({
          'type': kWorkerEventReady,
          'connectionId': assignedConnection,
        });
      }

      final shouldDelay =
          assignedConnection % 10 == 1 &&
          !processedDelayed.contains(assignedConnection);
      if (shouldDelay) {
        processedDelayed.add(assignedConnection);
        Future<void>.delayed(const Duration(milliseconds: 200))
            .then((_) => emitProcessed());
      } else {
        emitProcessed();
      }
    } else if (command == kWorkerCmdAddConnection) {
      final newListener = raw[1] as int;
      final newConnection = raw[2] as int;
      connections[newConnection] = newListener;
      bossPort.send({
        'type': kWorkerEventConnectionAdded,
        'connectionId': newConnection,
        'listenerId': newListener,
      });
      bossPort.send({'type': kWorkerEventReady, 'connectionId': newConnection});
    } else if (command == kWorkerCmdRemoveConnection) {
      final removeConnection = raw[1] as int;
      connections.remove(removeConnection);
      bossPort.send({
        'type': kWorkerEventConnectionRemoved,
        'connectionId': removeConnection,
      });
    } else if (command == kWorkerCmdShutdown) {
      commandPort.close();
      bossPort.send({
        'type': kWorkerEventShutdown,
        'connectionId': connectionId,
      });
    } else if (command == _workerCmdDrainConnections) {
      final reason = raw.length > 1 && raw[1] is String
          ? raw[1] as String
          : 'wamp.close.system_shutdown';
      bossPort.send({
        'type': 'test_drain',
        'reason': reason,
      });
      for (final entry in connections.entries.toList()) {
        bossPort.send({
          'type': 'worker_send',
          'connectionId': entry.key,
          'payload': Uint8List.fromList(
            utf8.encode(jsonEncode([MessageTypes.codeGoodbye, {}, reason])),
          ),
        });
        bossPort.send({
          'type': kWorkerEventConnectionRemoved,
          'connectionId': entry.key,
        });
        connections.remove(entry.key);
      }
      bossPort.send({
        'type': kWorkerEventDrained,
        'workerHash': workerHash,
      });
    }
  });
}

void _erroringWorkerEntryPoint(Map<String, Object?> init) {
  final bossPort = init['bossPort'] as SendPort;
  final connectionId = init['connectionId'] as int;
  final listenerId = init['listenerId'] as int;
  final commandPort = ReceivePort();
  final Map<int, int> connections = {connectionId: listenerId};
  final workerHash = Isolate.current.hashCode;

  bossPort.send({
    'type': kWorkerEventRegister,
    'connectionId': connectionId,
    'listenerId': listenerId,
    'commandPort': commandPort.sendPort,
    'workerHash': workerHash,
  });
  bossPort.send({'type': kWorkerEventReady, 'connectionId': connectionId});

  var emittedError = false;
  commandPort.listen((dynamic raw) {
    if (raw is! List || raw.isEmpty) {
      return;
    }
    final command = raw[0];
    if (command == kWorkerCmdProcess) {
      final assignedConnection = raw[1] as int;
      final handle = raw[2] as int;
      if (!emittedError) {
        emittedError = true;
        bossPort.send({
          'type': kWorkerEventError,
          'connectionId': assignedConnection,
          'error': 'synthetic-error',
          'stackTrace': 'trace',
        });
        bossPort.send({
          'type': kWorkerEventReady,
          'connectionId': assignedConnection,
        });
      } else {
        bossPort.send({
          'type': 'test_processed',
          'connectionId': assignedConnection,
          'handle': handle,
        });
        bossPort.send({
          'type': kWorkerEventReady,
          'connectionId': assignedConnection,
        });
      }
    } else if (command == kWorkerCmdAddConnection) {
      final newListener = raw[1] as int;
      final newConnection = raw[2] as int;
      connections[newConnection] = newListener;
      bossPort.send({
        'type': kWorkerEventConnectionAdded,
        'connectionId': newConnection,
        'listenerId': newListener,
      });
      bossPort.send({'type': kWorkerEventReady, 'connectionId': newConnection});
    } else if (command == kWorkerCmdRemoveConnection) {
      final removeConnection = raw[1] as int;
      connections.remove(removeConnection);
      bossPort.send({
        'type': kWorkerEventConnectionRemoved,
        'connectionId': removeConnection,
      });
    } else if (command == kWorkerCmdShutdown) {
      commandPort.close();
      bossPort.send({
        'type': kWorkerEventShutdown,
        'connectionId': connectionId,
      });
    } else if (command == _workerCmdDrainConnections) {
      final reason = raw.length > 1 && raw[1] is String
          ? raw[1] as String
          : 'wamp.close.system_shutdown';
      bossPort.send({
        'type': 'test_drain',
        'reason': reason,
      });
      for (final entry in connections.entries.toList()) {
        bossPort.send({
          'type': kWorkerEventConnectionRemoved,
          'connectionId': entry.key,
        });
        connections.remove(entry.key);
      }
      bossPort.send({
        'type': kWorkerEventDrained,
        'workerHash': workerHash,
      });
    }
  });
}

RouterSettings _buildRouterSettingsWithMinWorkers(int minWorkers) {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('anonymous')
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder('')
                ..setMatchPolicy(PermissionMatchPolicy.prefix)
                ..allowOperations(const [
                  'subscribe',
                  'publish',
                  'call',
                  'register',
                  'unregister',
                ]),
            ),
        )
        ..setLimits(const RealmLimitSettings()),
    )
    ..addListenerFromBuilder(
      ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
        ..addAuthMethod('anonymous')
        ..setOptions(const {
          'max_rawsocket_size_exponent': 16,
        }),
    )
    ..addAuthenticator(
      'anonymous',
      const AuthenticatorDefinition(type: 'anonymous'),
    )
    ..setWorkerPool(WorkerPoolSettings(minWorkers: minWorkers));
  return builder.build();
}

void main() {
  group('Router start', () {
    test('binds endpoints to runtime and applies config', () {
      final runtime = _FakeRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      expect(runtime.appliedConfig, isNotNull);
      expect(runtime.listenCalls, ['127.0.0.1:0:128']);
      expect(binding.listeners, hasLength(1));
      final listener = binding.listeners.single;
      expect(listener.listenerId, 1);
      expect(listener.port, greaterThan(0));
    });

    test('continues when runtime does not support config application', () {
      final runtime = _UnsupportedConfigRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '0.0.0.0',
              port: 8080,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      expect(binding.listeners, hasLength(1));
      expect(runtime.listenCalls, ['0.0.0.0:8080:128']);
    });

    test('pollNativeMessages drains pending connections and messages', () {
      final runtime = _FakeRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      final listener = binding.listeners.single;

      final publish = Publish(1, 'com.example.topic')..arguments = ['payload'];
      runtime.enqueueMessage(
        listener.listenerId,
        42,
        NativeIncomingMessage.synthetic(
          serializer: NativeMessageSerializer.json,
          message: publish,
          bytes: Uint8List.fromList([MessageTypes.codePublish]),
        ),
      );

      final messages = binding.pollNativeMessages();
      expect(messages, hasLength(1));
      final routerMessage = messages.single;
      expect(routerMessage.listener, same(listener));
      expect(routerMessage.connectionId, 42);
      expect(routerMessage.message.message, same(publish));
      routerMessage.message.dispose();
    });

    test('watchNativeMessages streams messages', () async {
      final runtime = _FakeRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      final listener = binding.listeners.single;

      final publish = Publish(7, 'com.example.topic');
      runtime.enqueueMessage(
        listener.listenerId,
        84,
        NativeIncomingMessage.synthetic(
          serializer: NativeMessageSerializer.json,
          message: publish,
          bytes: Uint8List.fromList([MessageTypes.codePublish]),
        ),
      );

      final collected = <RouterMessage>[];
      final subscription = binding
          .watchNativeMessages(
            pollInterval: Duration.zero,
            maxMessagesPerTick: 16,
          )
          .listen((routerMessage) {
            collected.add(routerMessage);
            routerMessage.message.dispose();
          });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await subscription.cancel();

      expect(collected, hasLength(1));
      final message = collected.single;
      expect(message.listener, same(listener));
      expect(message.connectionId, 84);
      expect(message.message.message, same(publish));
    });
  });

  group('Router boss/worker', () {
    test('dispatches handles sequentially to a worker isolate', () async {
      final runtime = _HandleRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final events = <Object>[];
      final binding = router.start(
        runtime,
        workerEntryPoint: _testWorkerEntryPoint,
        onEvent: events.add,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(binding.dispose);
      final listener = binding.listeners.single;
      final firstHandle = runtime.enqueueHandle(listener.listenerId, 9001);

      await _waitUntil(() {
        return events.any((event) {
          return event is Map &&
              event['type'] == 'worker_unknown_event' &&
              event['payload'] is Map &&
              (event['payload'] as Map)['type'] == 'test_processed';
        });
      });

      final processedEvent =
          events.firstWhere((event) {
                return event is Map &&
                    event['type'] == 'worker_unknown_event' &&
                    event['payload'] is Map &&
                    (event['payload'] as Map)['type'] == 'test_processed';
              })
              as Map;
      final payload = processedEvent['payload'] as Map;
      expect(payload['handle'], firstHandle);
      expect(payload['connectionId'], 9001);

      final firstProcessedIndex = events.indexOf(processedEvent);
      final readyAfterFirst = events.indexWhere(
        (event) =>
            event is Map &&
            event['type'] == 'worker_ready' &&
            event['connectionId'] == 9001,
        firstProcessedIndex + 1,
      );
      expect(readyAfterFirst, greaterThan(firstProcessedIndex));

      final secondHandle = runtime.enqueueHandle(listener.listenerId, 9002);

      await _waitUntil(() {
        return events.whereType<Map>().any(
          (event) =>
              event['type'] == 'worker_connection_added' &&
              event['connectionId'] == 9002,
        );
      });

      await _waitUntil(() {
        final processed = events.whereType<Map>().where((event) {
          return event['type'] == 'worker_unknown_event' &&
              event['payload'] is Map &&
              (event['payload'] as Map)['type'] == 'test_processed' &&
              (event['payload'] as Map)['handle'] == secondHandle;
        });
        return processed.isNotEmpty;
      });

      final processedEvents = events
          .whereType<Map>()
          .where(
            (event) =>
                event['type'] == 'worker_unknown_event' &&
                event['payload'] is Map &&
                (event['payload'] as Map)['type'] == 'test_processed',
          )
          .toList();
      final processedHandles = processedEvents
          .map((event) => (event['payload'] as Map)['handle'])
          .toList();
      expect(processedHandles, containsAll([firstHandle, secondHandle]));
    });

    test(
      'spawns additional workers until minimum worker count is satisfied',
      () async {
        final runtime = _HandleRuntime();
        final router = Router(
          RouterConfig(
            endpoints: [
              Endpoint(
                host: '127.0.0.1',
                port: 0,
                tlsMode: TlsMode.native,
                maxRawSocketSizeExponent: 16,
              ),
            ],
          ),
          settings: _buildRouterSettingsWithMinWorkers(2),
        );

        final events = <Object>[];
        final binding = router.start(
          runtime,
          workerEntryPoint: _testWorkerEntryPoint,
          onEvent: events.add,
          workerPollInterval: const Duration(milliseconds: 1),
        );
        addTearDown(binding.dispose);
        final listener = binding.listeners.single;

        runtime.enqueueHandle(listener.listenerId, 6101);
        runtime.enqueueHandle(listener.listenerId, 6102);

        await _waitUntil(
          () =>
              events
                  .whereType<Map>()
                  .where((event) => event['type'] == 'worker_registered')
                  .length >=
              2,
        );

        final registeredConnections = events
            .whereType<Map>()
            .where((event) => event['type'] == 'worker_registered')
            .map((event) => event['connectionId'] as int)
            .toSet();
        expect(registeredConnections, containsAll({6101, 6102}));

        final workerCounts = events
            .whereType<Map>()
            .where((event) => event['type'] == 'worker_registered')
            .length;
        expect(workerCounts, equals(2));
      },
    );

    test(
      'processes connections on different workers without blocking each other',
      () async {
        final runtime = _HandleRuntime();
        final router = Router(
          RouterConfig(
            endpoints: [
              Endpoint(
                host: '127.0.0.1',
                port: 0,
                tlsMode: TlsMode.native,
                maxRawSocketSizeExponent: 16,
              ),
            ],
          ),
          settings: _buildRouterSettingsWithMinWorkers(2),
        );

        final events = <Object>[];
        final binding = router.start(
          runtime,
          workerEntryPoint: _parallelWorkerEntryPoint,
          onEvent: events.add,
          workerPollInterval: const Duration(milliseconds: 1),
        );
        addTearDown(binding.dispose);
        final listener = binding.listeners.single;

        runtime.enqueueHandle(listener.listenerId, 7101);
        runtime.enqueueHandle(listener.listenerId, 7102);

        await _waitUntil(
          () =>
              events
                  .whereType<Map>()
                  .where((event) => event['type'] == 'worker_registered')
                  .length >=
              2,
        );

        await _waitUntil(() {
          final processed = events.whereType<Map>().where((event) {
            if (event['type'] != 'worker_unknown_event') {
              return false;
            }
            final payload = event['payload'];
            return payload is Map && payload['type'] == 'test_processed';
          }).length;
          return processed >= 2;
        });

        final processedEvents = events.whereType<Map>().where((event) {
          if (event['type'] != 'worker_unknown_event') {
            return false;
          }
          final payload = event['payload'];
          return payload is Map && payload['type'] == 'test_processed';
        }).map((event) => event['payload'] as Map<String, Object?>).toList();

        expect(processedEvents, hasLength(greaterThanOrEqualTo(2)));

        final fastEvent = processedEvents.firstWhere(
          (event) => event['connectionId'] == 7102,
        );
        final slowEvent = processedEvents.firstWhere(
          (event) => event['connectionId'] == 7101,
        );
        final fastTime = fastEvent['processedAt'] as int?;
        final slowTime = slowEvent['processedAt'] as int?;
        expect(fastTime, isNotNull);
        expect(slowTime, isNotNull);
        final fastProcessed = fastTime!;
        final slowProcessed = slowTime!;
        expect(fastProcessed, lessThan(slowProcessed));
        expect(slowProcessed - fastProcessed, greaterThanOrEqualTo(100000));
      },
    );

    test('shuts down worker when runtime reports missing connection', () async {
      final runtime = _HandleRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final events = <Object>[];
      final binding = router.start(
        runtime,
        workerEntryPoint: _testWorkerEntryPoint,
        onEvent: events.add,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(binding.dispose);
      final listener = binding.listeners.single;
      runtime.enqueueHandle(listener.listenerId, 4001);

      await _waitUntil(() {
        return events.any(
          (event) => event is Map && event['type'] == 'worker_unknown_event',
        );
      });

      runtime.scheduleErrorOnce(
        NativeTransportErrorCode.connectionNotFound,
        'connection gone',
      );

      await _waitUntil(() {
        final errors = events.whereType<Map>().any(
          (event) =>
              event['type'] == 'boss_error' &&
              event['connectionId'] == 4001 &&
              (event['error'] as String).contains('connection gone'),
        );
        final removed = events.whereType<Map>().any(
          (event) =>
              event['type'] == 'worker_connection_removed' &&
              event['connectionId'] == 4001,
        );
        return errors && removed;
      }, timeout: const Duration(seconds: 2));
    });

    test('continues dispatching after worker error', () async {
      final runtime = _HandleRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final events = <Object>[];
      final binding = router.start(
        runtime,
        workerEntryPoint: _erroringWorkerEntryPoint,
        onEvent: events.add,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(binding.dispose);
      final listener = binding.listeners.single;

      final firstHandle = runtime.enqueueHandle(listener.listenerId, 5001);
      await _waitUntil(() {
        final errorEvent = events.whereType<Map>().any(
          (event) =>
              event['type'] == 'worker_error' && event['connectionId'] == 5001,
        );
        final readyEvent = events.whereType<Map>().any(
          (event) =>
              event['type'] == 'worker_ready' && event['connectionId'] == 5001,
        );
        return errorEvent && readyEvent;
      });

      final secondHandle = runtime.enqueueHandle(listener.listenerId, 5001);
      await _waitUntil(() {
        return events.whereType<Map>().any(
          (event) =>
              event['type'] == 'worker_unknown_event' &&
              event['payload'] is Map &&
              (event['payload'] as Map)['handle'] == secondHandle,
        );
      });

      final processedHandles = events
          .whereType<Map>()
          .where(
            (event) =>
                event['type'] == 'worker_unknown_event' &&
                event['payload'] is Map &&
                (event['payload'] as Map)['type'] == 'test_processed',
          )
          .map((event) => (event['payload'] as Map)['handle'])
          .toList();
      expect(processedHandles, contains(secondHandle));
      expect(processedHandles, isNot(contains(firstHandle)));
    });

    test('stop drains workers with system shutdown reason', () async {
      final runtime = _HandleRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );

      final events = <Object>[];
      final binding = router.start(
        runtime,
        workerEntryPoint: _testWorkerEntryPoint,
        onEvent: events.add,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(binding.dispose);
      final listener = binding.listeners.single;
      runtime.enqueueHandle(listener.listenerId, 6001);

      await _waitUntil(() {
        return events.whereType<Map>().any(
          (event) =>
              event['type'] == 'worker_ready' &&
              event['connectionId'] == 6001,
        );
      });

      await binding.dispose();

      await _waitUntil(() {
        return events.whereType<Map>().any(
          (event) => event['type'] == 'worker_drained',
        );
      });

      final drainEvents = events.whereType<Map>().where((event) {
        if (event['type'] != 'worker_unknown_event') {
          return false;
        }
        final payload = event['payload'];
        return payload is Map && payload['type'] == 'test_drain';
      }).toList();

      expect(drainEvents, hasLength(1));
      final drainPayload = drainEvents.single['payload'] as Map;
      expect(drainPayload['reason'], equals('wamp.close.system_shutdown'));

      final sentFrames = runtime.sentMessages[6001];
      expect(sentFrames, isNotNull);
      final decodedGoodbyes = sentFrames!
          .map(
            (payload) => jsonDecode(utf8.decode(payload)) as List<dynamic>,
          )
          .toList();
      expect(decodedGoodbyes, isNotEmpty);
      final goodbyeFrame = decodedGoodbyes.last;
      expect(goodbyeFrame.first, equals(MessageTypes.codeGoodbye));
      expect(goodbyeFrame.last, equals('wamp.close.system_shutdown'));
      expect(goodbyeFrame[1], isA<Map>());

      final workerDrained = events.whereType<Map>().where(
        (event) => event['type'] == 'worker_drained',
      );
      expect(workerDrained.length, equals(1));
    });
  });
}
