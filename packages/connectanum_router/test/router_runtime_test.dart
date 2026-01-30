@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library router_runtime_test;

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart'
    show MessageTypes, Publish;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/sni_certificate.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

const _certificatePem =
    '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----';
const _privateKeyPem =
    '-----BEGIN PRIVATE KEY-----\nMIIB\n-----END PRIVATE KEY-----';

SniCertificate _cert(String host) => SniCertificate(
  hostname: host,
  certificateChainPem: _certificatePem,
  privateKeyPem: _privateKeyPem,
);

class _FakeRuntime implements NativeRuntime {
  final List<String> listenCalls = [];
  Uint8List? appliedConfig;
  final List<int> closedConnections = [];
  final Map<int, int> _ports = {};
  final Map<int, int> _http3Ports = {};
  int _nextId = 1;
  final Map<int, Queue<int>> _pendingConnections = {};
  final Map<int, Queue<NativeIncomingMessage>> _pendingMessages = {};
  final Map<int, List<Uint8List>> sentMessages = {};
  final Map<int, NativeConnectionProtocol> _protocols = {};
  final Map<int, Queue<NativeHttpHandshake>> _httpHandshakes = {};
  final Map<int, Queue<NativeHttp2Handshake>> _http2Handshakes = {};
  final Map<int, Queue<NativeHttp3Handshake>> _http3Handshakes = {};
  final Map<int, Queue<NativeHttpHandshake>> _http3Requests = {};
  final Queue<NativeHttpConnectionEvent> _httpConnectionEvents =
      Queue<NativeHttpConnectionEvent>();
  final Queue<NativeRouterMetrics> _routerMetricsQueue =
      Queue<NativeRouterMetrics>();
  final Map<int, Queue<NativeWebSocketHandshake>> _webSocketHandshakes = {};
  final List<Map<String, Object?>> acceptedWebSockets = [];
  final List<Map<String, Object?>> rejectedWebSockets = [];
  final Map<int, List<Uint8List>> responseStreamChunks = {};
  final Set<int> closedResponseStreams = {};
  final List<_FakeStreamOpen> responseStreamOpens = [];
  int _nextStreamHandle = 1;

  @override
  void applyRouterConfig(Uint8List config) {
    appliedConfig = config;
  }

  @override
  int reloadTls() => 0;

  @override
  int getLocalPort(int listenerId) => _ports[listenerId] ?? listenerId;

  @override
  int getHttp3Port(int listenerId) => _http3Ports[listenerId] ?? 0;

  @override
  int listen(String host, int port, {int backlog = 128}) {
    final id = _nextId++;
    listenCalls.add('$host:$port:$backlog');
    _ports[id] = port == 0 ? 5000 + id : port;
    _http3Ports[id] = _ports[id]! + 1;
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
  NativeConnectionProtocol connectionProtocol(int connectionId) {
    return _protocols[connectionId] ?? NativeConnectionProtocol.rawsocket;
  }

  @override
  void closeConnection(int connectionId) {
    closedConnections.add(connectionId);
    _protocols.remove(connectionId);
    _pendingMessages.remove(connectionId);
  }

  @override
  String? connectionWebSocketProtocol(int connectionId) => null;

  @override
  NativeHttpHandshake? takeHttpHandshake(int connectionId) {
    final queue = _httpHandshakes[connectionId];
    if (queue == null || queue.isEmpty) {
      return null;
    }
    return queue.removeFirst();
  }

  @override
  void releaseHttpHandshake(int handle) {}

  @override
  NativeHttp2Handshake? takeHttp2Handshake(int connectionId) {
    final queue = _http2Handshakes[connectionId];
    if (queue == null || queue.isEmpty) {
      return null;
    }
    return queue.removeFirst();
  }

  @override
  void releaseHttp2Handshake(int handle) {}

  @override
  NativeWebSocketHandshake? takeWebSocketHandshake(int connectionId) {
    final queue = _webSocketHandshakes[connectionId];
    if (queue == null || queue.isEmpty) {
      return null;
    }
    return queue.removeFirst();
  }

  @override
  void acceptWebSocket({
    required int connectionId,
    required int handshakeHandle,
    required NativeMessageSerializer serializer,
    required String protocol,
  }) {
    acceptedWebSockets.add({
      'connectionId': connectionId,
      'handshakeHandle': handshakeHandle,
      'serializer': serializer,
      'protocol': protocol,
    });
  }

  @override
  void rejectWebSocket({
    required int connectionId,
    required int handshakeHandle,
    int status = 400,
    String reason = '',
  }) {
    rejectedWebSockets.add({
      'connectionId': connectionId,
      'handshakeHandle': handshakeHandle,
      'status': status,
      'reason': reason,
    });
  }

  @override
  NativeHttp3Handshake? takeHttp3Handshake(int connectionId) {
    final queue = _http3Handshakes[connectionId];
    if (queue == null || queue.isEmpty) {
      return null;
    }
    return queue.removeFirst();
  }

  @override
  void releaseHttp3Handshake(int handle) {}

  @override
  NativeHttpHandshake? pollHttp3Request(int connectionId) {
    final queue = _http3Requests[connectionId];
    if (queue == null || queue.isEmpty) {
      return null;
    }
    return queue.removeFirst();
  }

  @override
  NativeHttp3Connection? takeHttp3Connection(int connectionId) => null;

  @override
  NativeHttp3Stream? pollHttp3Stream(int connectionId) => null;

  @override
  void sendHttpResponse({
    required int handshakeHandle,
    int? connectionId,
    required NativeHttpResponse response,
  }) {
    throw UnsupportedError('HTTP responses not supported');
  }

  @override
  NativeHttpResponseStream openHttpResponseStream({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    final handle = _nextStreamHandle++;
    responseStreamOpens.add(
      _FakeStreamOpen(
        streamHandle: handle,
        handshakeHandle: handshakeHandle,
        status: status,
        headers: Map.unmodifiable(headers),
      ),
    );
    return _FakeHttpResponseStream(
      handle: handle,
      onChunk: (chunk) {
        responseStreamChunks
            .putIfAbsent(handle, () => [])
            .add(Uint8List.fromList(chunk));
      },
      onClose: () {
        closedResponseStreams.add(handle);
      },
    );
  }

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

  void setConnectionProtocol(
    int connectionId,
    NativeConnectionProtocol protocol,
  ) {
    _protocols[connectionId] = protocol;
  }

  void enqueueHttp2Handshake(int connectionId, NativeHttp2Handshake handshake) {
    _http2Handshakes.putIfAbsent(connectionId, Queue.new).add(handshake);
  }

  void enqueueHttp3Handshake(int connectionId, NativeHttp3Handshake handshake) {
    _http3Handshakes.putIfAbsent(connectionId, Queue.new).add(handshake);
  }

  void enqueueHttp3Request(int connectionId, NativeHttpHandshake handshake) {
    _http3Requests.putIfAbsent(connectionId, Queue.new).add(handshake);
  }

  void enqueueWebSocketHandshake(
    int listenerId,
    int connectionId,
    NativeWebSocketHandshake handshake,
  ) {
    _pendingConnections.putIfAbsent(listenerId, Queue.new).add(connectionId);
    _webSocketHandshakes.putIfAbsent(connectionId, Queue.new).add(handshake);
  }

  void enqueueHttpHandshake(
    int listenerId,
    int connectionId,
    NativeHttpHandshake handshake,
  ) {
    _pendingConnections.putIfAbsent(listenerId, Queue.new).add(connectionId);
    _httpHandshakes.putIfAbsent(connectionId, Queue.new).add(handshake);
  }

  void queueHttpRequestForConnection(
    int connectionId,
    NativeHttpHandshake handshake,
  ) {
    _httpHandshakes.putIfAbsent(connectionId, Queue.new).add(handshake);
  }

  void enqueueConnection(int listenerId, int connectionId) {
    _pendingConnections.putIfAbsent(listenerId, Queue.new).add(connectionId);
  }

  @override
  NativeHttpConnectionEvent? pollHttpConnectionEvent() {
    if (_httpConnectionEvents.isEmpty) {
      return null;
    }
    return _httpConnectionEvents.removeFirst();
  }

  @override
  NativeRouterMetrics? pollRouterMetrics() {
    if (_routerMetricsQueue.isEmpty) {
      return null;
    }
    return _routerMetricsQueue.removeFirst();
  }

  void enqueueHttpConnectionEvent(NativeHttpConnectionEvent event) {
    _httpConnectionEvents.add(event);
  }

  void enqueueRouterMetrics(NativeRouterMetrics metrics) {
    _routerMetricsQueue.add(metrics);
  }
}

class _FakeStreamOpen {
  _FakeStreamOpen({
    required this.streamHandle,
    required this.handshakeHandle,
    required this.status,
    required this.headers,
  });

  final int streamHandle;
  final int handshakeHandle;
  final int status;
  final Map<String, String> headers;
}

class _FakeHttpResponseStream implements NativeHttpResponseStream {
  _FakeHttpResponseStream({
    required this.handle,
    required void Function(Uint8List chunk) onChunk,
    required void Function() onClose,
  }) : _onChunk = onChunk,
       _onClose = onClose;

  final int handle;
  final void Function(Uint8List chunk) _onChunk;
  final void Function() _onClose;
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  void add(Uint8List chunk) {
    if (_closed) {
      throw StateError('HTTP response stream already closed');
    }
    if (chunk.isEmpty) {
      return;
    }
    _onChunk(Uint8List.fromList(chunk));
  }

  @override
  void close([Uint8List? finalChunk]) {
    if (_closed) {
      return;
    }
    if (finalChunk != null && finalChunk.isNotEmpty) {
      add(finalChunk);
      if (_closed) {
        return;
      }
    }
    _closed = true;
    _onClose();
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
  final Map<int, List<NativeHttpResponse>> httpResponses = {};

  @override
  void closeConnection(int connectionId) {
    super.closeConnection(connectionId);
    _pendingHandles.remove(connectionId);
    _knownConnections.remove(connectionId);
  }

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
  int pollWebSocketMessageHandle(int connectionId) =>
      pollMessageHandle(connectionId);

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

  int enqueueHandleOnly(int connectionId) {
    final handle = _nextHandle++;
    _pendingHandles.putIfAbsent(connectionId, Queue.new).add(handle);
    return handle;
  }

  void scheduleErrorOnce(int code, String message) {
    _scheduledError = NativeTransportException(code, message);
  }

  @override
  void sendHttpResponse({
    required int handshakeHandle,
    int? connectionId,
    required NativeHttpResponse response,
  }) {
    final key = connectionId ?? handshakeHandle;
    httpResponses.putIfAbsent(key, () => []).add(response);
  }
}

class _WebSocketHandleRuntime extends _HandleRuntime {
  @override
  int pollMessageHandle(int connectionId) {
    final protocol = _protocols[connectionId];
    if (protocol == NativeConnectionProtocol.websocket) {
      final error = _scheduledError;
      if (error != null) {
        _scheduledError = null;
        throw error;
      }
      return 0;
    }
    return super.pollMessageHandle(connectionId);
  }

  @override
  int pollWebSocketMessageHandle(int connectionId) {
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
const int kWorkerEventSessionOpened = 14;
const int _workerCmdDrainConnections = 6;

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
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
      bossPort.send({'type': 'test_drain', 'reason': reason});
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
      bossPort.send({'type': kWorkerEventDrained, 'workerHash': workerHash});
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
        Future<void>.delayed(
          const Duration(milliseconds: 200),
        ).then((_) => emitProcessed());
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
      bossPort.send({'type': 'test_drain', 'reason': reason});
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
      bossPort.send({'type': kWorkerEventDrained, 'workerHash': workerHash});
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
      bossPort.send({'type': 'test_drain', 'reason': reason});
      for (final entry in connections.entries.toList()) {
        bossPort.send({
          'type': kWorkerEventConnectionRemoved,
          'connectionId': entry.key,
        });
        connections.remove(entry.key);
      }
      bossPort.send({'type': kWorkerEventDrained, 'workerHash': workerHash});
    }
  });
}

void _idleWorkerEntryPoint(Map<String, Object?> init) {
  final bossPort = init['bossPort'] as SendPort;
  final connectionId = init['connectionId'] as int;
  final listenerId = init['listenerId'] as int;
  final commandPort = ReceivePort();
  final workerHash = Isolate.current.hashCode;

  bossPort.send({
    'type': kWorkerEventRegister,
    'connectionId': connectionId,
    'listenerId': listenerId,
    'commandPort': commandPort.sendPort,
    'statePort': init['statePort'],
    'workerHash': workerHash,
  });
  bossPort.send({
    'type': kWorkerEventSessionOpened,
    'connectionId': connectionId,
    'sessionId': 1,
    'realmUri': 'realm1',
  });
  bossPort.send({'type': kWorkerEventReady, 'connectionId': connectionId});

  commandPort.listen((dynamic raw) {
    if (raw is! List || raw.isEmpty) {
      return;
    }
    final command = raw[0];
    if (command == kWorkerCmdRemoveConnection) {
      final removeConnection = raw[1] as int;
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
    }
  });
}

RouterSettings _buildRouterSettingsWithMinWorkers(int minWorkers) {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
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
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    )
    ..addAuthenticator(
      'anonymous',
      const AuthenticatorDefinition(type: 'anonymous'),
    )
    ..setWorkerPool(WorkerPoolSettings(minWorkers: minWorkers));
  return builder.build();
}

RouterSettings _buildRouterSettingsWithPendingProtocols() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
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
        ),
    )
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addAuthMethod('anonymous')
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..addProtocol(ListenerProtocol.rawsocket)
          ..addProtocol(ListenerProtocol.http)
          ..addProtocol(ListenerProtocol.http2)
          ..addProtocol(ListenerProtocol.http3)
          ..setHttpOptions(
            const HttpListenerSettings(
              alpn: ['http/1.1', 'h2'],
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(prefix: '/api/'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    procedure: 'com.example.api.{path}',
                  ),
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    )
    ..addAuthenticator(
      'anonymous',
      const AuthenticatorDefinition(type: 'anonymous'),
    );
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
              sniCertificates: [_cert('localhost')],
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
              sniCertificates: [_cert('localhost')],
            ),
          ],
        ),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      expect(binding.listeners, hasLength(1));
      expect(runtime.listenCalls, ['0.0.0.0:8080:128']);
    });

    test('encodes reserved realm and namespace HTTP routes', () {
      final builder = RouterSettingsBuilder()
        ..addRealmFromBuilder(
          RealmSettingsBuilder('realm1')
            ..addAuthMethod('anonymous')
            ..addRoleFromBuilder(
              RoleSettingsBuilder('member')..addPermissionFromBuilder(
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
            ),
        )
        ..addListenerFromBuilder(
          (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
              ..addAuthMethod('anonymous')
              ..addProtocol(ListenerProtocol.rawsocket)
              ..addProtocol(ListenerProtocol.http)
              ..setOptions(const {'max_rawsocket_size_exponent': 16})
              ..setHttpOptions(
                const HttpListenerSettings(
                  routes: [
                    HttpRouteSettings(
                      match: HttpRouteMatch(path: '/metrics'),
                      action: HttpRouteAction(
                        type: HttpRouteActionType.reservedRealm,
                        namespace: 'metrics',
                        appendMethodSuffix: false,
                      ),
                    ),
                    HttpRouteSettings(
                      match: HttpRouteMatch(prefix: '/api/'),
                      action: HttpRouteAction(
                        type: HttpRouteActionType.namespace,
                        realm: 'realm1',
                        namespace: 'api',
                      ),
                    ),
                  ],
                ),
              ))
            ..setRawSocketOptions(
              const RawSocketListenerSettings(maxFrameExponent: 16),
            ),
        )
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        );
      final settings = builder.build();

      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
              sniCertificates: [_cert('localhost')],
            ),
          ],
        ),
        settings: settings,
      );

      final jsonBytes = router.buildNativeConfigJson();
      final config =
          json.decode(utf8.decode(jsonBytes)) as Map<String, Object?>;
      final endpoints = config['endpoints'] as List<dynamic>;
      final first = endpoints.first as Map<String, Object?>;
      final routes = first['http_routes'] as List<dynamic>;
      expect(routes, hasLength(2));

      final reservedRoute =
          routes.firstWhere(
                (entry) =>
                    (entry as Map<String, Object?>)['path'] == '/metrics',
              )
              as Map<String, Object?>;
      final reserved = reservedRoute['default'] as Map<String, Object?>;
      expect(reserved['type'], 'reserved_realm');
      expect(reserved['namespace'], 'metrics');
      expect(reserved['append_method_suffix'], isFalse);

      final namespaceRoute =
          routes.firstWhere(
                (entry) => (entry as Map<String, Object?>)['path'] == '/api/',
              )
              as Map<String, Object?>;
      final namespace = namespaceRoute['default'] as Map<String, Object?>;
      expect(namespace['type'], 'namespace');
      expect(namespace['realm'], 'realm1');
      expect(namespace['namespace'], 'api');
      expect(namespace['append_method_suffix'], isTrue);
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
              sniCertificates: [_cert('localhost')],
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
              sniCertificates: [_cert('localhost')],
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

    test('emits listener_protocol_pending for unsupported protocols', () async {
      final runtime = _FakeRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
              sniCertificates: [_cert('localhost')],
            ),
          ],
        ),
        settings: _buildRouterSettingsWithPendingProtocols(),
      );

      final events = <Map<String, Object?>>[];
      final binding = router.start(
        runtime,
        onEvent: (event) {
          if (event is Map<String, Object?>) {
            events.add(event);
          }
        },
      );
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);

      final pendingEvents = events.where((event) {
        return event['type'] == 'listener_protocol_pending';
      }).toList();

      expect(pendingEvents.length, greaterThanOrEqualTo(1));
      expect(
        pendingEvents.map((event) => event['source']).toSet(),
        contains('binding'),
      );
      final listener = binding.listeners.single;
      expect(listener.settings?.protocols, [
        ListenerProtocol.rawsocket,
        ListenerProtocol.http,
        ListenerProtocol.http2,
        ListenerProtocol.http3,
      ]);
      for (final event in pendingEvents) {
        expect(event['endpoint'], '127.0.0.1:0');
        expect(
          (event['protocols'] as List?)?.toSet(),
          containsAll(<String>{'http', 'http2', 'http3'}),
        );
      }
    });
  });

  group('Router boss/worker', () {
    test('closes idle sessions based on session_idle_ms', () async {
      final runtime = _HandleRuntime();
      final settings = RouterSettingsBuilder()
          .addRealmFromBuilder(
            RealmSettingsBuilder('realm1')
              ..addAuthMethod('anonymous')
              ..addRoleFromBuilder(
                RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
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
              ..setLimits(const RealmLimitSettings(sessionIdleMs: 50)),
          )
          .addListenerFromBuilder(
            ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
              ..addAuthMethod('anonymous')
              ..setOptions(const {'max_rawsocket_size_exponent': 16}),
          )
          .addAuthenticator(
            'anonymous',
            const AuthenticatorDefinition(type: 'anonymous'),
          )
          .build();

      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.disabled,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
        settings: settings,
      );

      final binding = router.start(
        runtime,
        workerEntryPoint: _idleWorkerEntryPoint,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(binding.dispose);

      final listener = binding.listeners.single;
      const connectionId = 9901;
      runtime.enqueueConnection(listener.listenerId, connectionId);

      await _waitUntil(
        () => runtime.closedConnections.contains(connectionId),
        timeout: const Duration(seconds: 3),
      );
    });

    test('accepts WebSocket handshakes with supported subprotocols', () async {
      final runtime = _FakeRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
              sniCertificates: [_cert('localhost')],
              webSocketPath: '/ws',
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
      runtime.setConnectionProtocol(9101, NativeConnectionProtocol.websocket);
      runtime.enqueueWebSocketHandshake(
        listener.listenerId,
        9101,
        NativeWebSocketHandshake.synthetic(
          handle: 77,
          key: 'dGVzdEtleQ==',
          protocols: const ['wamp.2.msgpack', 'wamp.2.json'],
          extensions: const ['permessage-deflate'],
        ),
      );

      var attempts = 0;
      while (runtime.acceptedWebSockets.isEmpty && attempts < 600) {
        binding.pollNativeMessages();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        attempts++;
      }
      expect(
        runtime.acceptedWebSockets,
        isNotEmpty,
        reason: 'websocket was not accepted; events=$events',
      );
      final addedEvents = events
          .whereType<Map<String, Object?>>()
          .where(
            (event) =>
                event['type'] == 'worker_connection_added' &&
                event['connectionId'] == 9101,
          )
          .toList();
      if (addedEvents.isNotEmpty) {
        final added = addedEvents.first;
        expect(added['protocol'], 'websocket');
        expect(added['websocketProtocol'], 'wamp.2.msgpack');
        expect(added['websocketSerializer'], 'msgpack');
      }
      final accepted = runtime.acceptedWebSockets.single;
      expect(accepted['connectionId'], 9101);
      // `wamp.2.msgpack` is the first supported subprotocol in the proposals.
      expect(accepted['serializer'], NativeMessageSerializer.messagePack);
      expect(accepted['protocol'], 'wamp.2.msgpack');
    });

    test('dispatches WebSocket message handles to workers', () async {
      final runtime = _WebSocketHandleRuntime();
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.native,
              maxRawSocketSizeExponent: 16,
              sniCertificates: [_cert('localhost')],
              webSocketPath: '/ws',
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
      runtime.setConnectionProtocol(9201, NativeConnectionProtocol.websocket);
      runtime.enqueueWebSocketHandshake(
        listener.listenerId,
        9201,
        NativeWebSocketHandshake.synthetic(
          handle: 80,
          key: 'dGVzdEtleVdz',
          protocols: const ['wamp.2.json'],
        ),
      );

      await _waitUntil(() => runtime.acceptedWebSockets.isNotEmpty);

      final handle = runtime.enqueueHandleOnly(9201);

      await _waitUntil(() {
        return events.any((event) {
          if (event is! Map) {
            return false;
          }
          if (event['type'] != 'worker_unknown_event') {
            return false;
          }
          final payload = event['payload'];
          return payload is Map &&
              payload['type'] == 'test_processed' &&
              payload['connectionId'] == 9201;
        });
      });

      final processed =
          events.whereType<Map>().firstWhere(
                (event) =>
                    event['type'] == 'worker_unknown_event' &&
                    event['payload'] is Map &&
                    (event['payload'] as Map)['type'] == 'test_processed' &&
                    (event['payload'] as Map)['connectionId'] == 9201,
              )['payload']
              as Map;
      expect(processed['handle'], handle);
    });

    test(
      'rejects WebSocket handshakes without supported subprotocols',
      () async {
        final runtime = _FakeRuntime();
        final router = Router(
          RouterConfig(
            endpoints: [
              Endpoint(
                host: '127.0.0.1',
                port: 0,
                tlsMode: TlsMode.native,
                maxRawSocketSizeExponent: 16,
                sniCertificates: [_cert('localhost')],
                webSocketPath: '/ws',
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
        runtime.setConnectionProtocol(9102, NativeConnectionProtocol.websocket);
        runtime.enqueueWebSocketHandshake(
          listener.listenerId,
          9102,
          NativeWebSocketHandshake.synthetic(
            handle: 78,
            key: 'dGVzdEtleTI=',
            protocols: const ['unsup'],
          ),
        );

        var attempts = 0;
        while (runtime.rejectedWebSockets.isEmpty && attempts < 600) {
          binding.pollNativeMessages();
          await Future<void>.delayed(const Duration(milliseconds: 5));
          attempts++;
        }
        expect(
          runtime.rejectedWebSockets,
          isNotEmpty,
          reason: 'websocket was not rejected; events=$events',
        );
        final rejected = runtime.rejectedWebSockets.single;
        expect(rejected['connectionId'], 9102);
        expect(rejected['status'], 426);
        expect((rejected['reason'] as String?)?.isNotEmpty, isTrue);

        final errors = events.whereType<Map>().where(
          (event) => event['type'] == 'listener_websocket_handshake_missing',
        );
        expect(errors, isEmpty);
      },
    );

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
              sniCertificates: [_cert('localhost')],
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
                sniCertificates: [_cert('localhost')],
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
                sniCertificates: [_cert('localhost')],
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

        final processedEvents = events
            .whereType<Map>()
            .where((event) {
              if (event['type'] != 'worker_unknown_event') {
                return false;
              }
              final payload = event['payload'];
              return payload is Map && payload['type'] == 'test_processed';
            })
            .map((event) => event['payload'] as Map<String, Object?>)
            .toList();

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
              sniCertificates: [_cert('localhost')],
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
              sniCertificates: [_cert('localhost')],
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
      }, timeout: const Duration(seconds: 2));

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
              sniCertificates: [_cert('localhost')],
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
              event['type'] == 'worker_ready' && event['connectionId'] == 6001,
        );
      }, timeout: const Duration(seconds: 2));

      await binding.dispose();

      await _waitUntil(() {
        return events.whereType<Map>().any(
          (event) => event['type'] == 'worker_drained',
        );
      }, timeout: const Duration(seconds: 2));

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
          .map((payload) => jsonDecode(utf8.decode(payload)) as List<dynamic>)
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

  test('emits listener_http_request when HTTP route resolved', () async {
    final runtime = _HandleRuntime();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
            sniCertificates: [_cert('localhost')],
          ),
        ],
      ),
      settings: _buildRouterSettingsWithPendingProtocols(),
    );

    final events = <Map<String, Object?>>[];
    final binding = router.start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          events.add(event);
        }
      },
    );
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    const connectionId = 42;

    final internalSession = await binding.createInternalSession(
      realmUri: 'realm1',
    );
    final registered = await internalSession.register('com.example.api.health');
    registered.onInvoke((invocation) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      expect(context, isNotNull);
      final request = context!.request;
      expect(request.method, 'GET');
      expect(request.path, '/api/health');
      context.sendText(
        body: 'OK',
        status: 201,
        headers: const {'x-handler': 'true'},
      );
    });

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 1,
        method: 'GET',
        target: '/api/health?check=true',
        path: '/api/health',
        query: 'check=true',
        protocol: 'http/1.1',
        headers: const {'x-test': 'true'},
        body: Uint8List.fromList(utf8.encode('{}')),
        realm: 'realm1',
        procedure: 'com.example.api.health',
      ),
    );
    await _waitUntil(
      () => events.any((event) => event['type'] == 'listener_http_request'),
      timeout: const Duration(seconds: 2),
    );

    final httpEvents = events.where((event) {
      return event['type'] == 'listener_http_request';
    }).toList();

    expect(httpEvents, isNotEmpty);
    final httpEvent = httpEvents.first;
    expect(httpEvent['listenerId'], listenerId);
    expect(httpEvent['connectionId'], connectionId);
    expect(httpEvent['method'], 'GET');
    expect(httpEvent['path'], '/api/health');
    expect(httpEvent['query'], 'check=true');
    expect(httpEvent['realm'], 'realm1');
    expect(httpEvent['procedure'], 'com.example.api.health');
    expect(httpEvent['headers'], containsPair('x-test', 'true'));

    await _waitUntil(
      () => events.any((event) => event['type'] == 'http_request_dispatched'),
      timeout: const Duration(seconds: 2),
    );
    final dispatchEvent = events.firstWhere(
      (event) => event['type'] == 'http_request_dispatched',
    );
    expect(dispatchEvent['realm'], 'realm1');
    expect(dispatchEvent['procedure'], 'com.example.api.health');
    expect(dispatchEvent['listenerId'], listenerId);
    expect(dispatchEvent['connectionId'], connectionId);

    await _waitUntil(
      () => events.any((event) => event['type'] == 'http_response_ready'),
      timeout: const Duration(seconds: 2),
    );
    final responseEvent = events.firstWhere(
      (event) => event['type'] == 'http_response_ready',
    );
    expect(responseEvent['listenerId'], listenerId);
    expect(responseEvent['connectionId'], connectionId);
    final response = responseEvent['response'] as Map;
    expect(response['status'], 201);
    final headers = response['headers'] as Map;
    expect(headers['x-handler'], 'true');
    expect(response['bodyKind'], 'text');
    expect(response['bodyText'], 'OK');

    final recorded = runtime.httpResponses[connectionId];
    expect(recorded, isNotNull);
    expect(recorded, hasLength(1));
    final nativeResponse = recorded!.single;
    expect(nativeResponse.status, 201);
    expect(nativeResponse.headers['x-handler'], 'true');
    final body = nativeResponse.body;
    expect(body, isA<NativeHttpResponseText>());
    expect((body as NativeHttpResponseText).text, 'OK');
  });

  test(
    'streams HTTP response chunks when progressive results emitted',
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
              sniCertificates: [_cert('localhost')],
            ),
          ],
        ),
        settings: _buildRouterSettingsWithPendingProtocols(),
      );

      final events = <Map<String, Object?>>[];
      final binding = router.start(
        runtime,
        onEvent: (event) {
          if (event is Map<String, Object?>) {
            events.add(event);
          }
        },
      );
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      const connectionId = 43;

      final internalSession = await binding.createInternalSession(
        realmUri: 'realm1',
      );
      final registered = await internalSession.register(
        'com.example.api.stream',
      );
      registered.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull);
        final stream = context!.streamResponse(
          status: 206,
          headers: const {'x-stream': 'true'},
        );
        stream.add(utf8.encode('part-a'));
        stream.add(utf8.encode('part-b'));
        stream.close(utf8.encode('final'));
      });

      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 2,
          method: 'GET',
          target: '/api/stream',
          path: '/api/stream',
          protocol: 'http/1.1',
          headers: const {'x-test': 'stream'},
          body: Uint8List.fromList(utf8.encode('{}')),
          realm: 'realm1',
          procedure: 'com.example.api.stream',
        ),
      );

      await _waitUntil(
        () => runtime.responseStreamOpens.isNotEmpty,
        timeout: const Duration(seconds: 2),
      );

      final open = runtime.responseStreamOpens.single;
      expect(open.handshakeHandle, 2);
      expect(open.status, 206);
      expect(open.headers['x-stream'], 'true');
      final handle = open.streamHandle;
      await _waitUntil(
        () => runtime.closedResponseStreams.contains(handle),
        timeout: const Duration(seconds: 2),
      );
      final chunks = runtime.responseStreamChunks[handle];
      expect(chunks, isNotNull);
      expect(chunks, hasLength(3));
      expect(utf8.decode(chunks![0]), 'part-a');
      expect(utf8.decode(chunks[1]), 'part-b');
      expect(utf8.decode(chunks[2]), 'final');
      expect(runtime.closedResponseStreams.contains(handle), isTrue);
    },
  );

  test('streams HTTP/2 response chunks using native streams', () async {
    final runtime = _HandleRuntime();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
            sniCertificates: [_cert('localhost')],
          ),
        ],
      ),
      settings: _buildRouterSettingsWithPendingProtocols(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    const connectionId = 44;

    final internalSession = await binding.createInternalSession(
      realmUri: 'realm1',
    );
    final registered = await internalSession.register('com.example.api.stream');
    registered.onInvoke((invocation) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      expect(context, isNotNull);
      final stream = context!.streamResponse(
        status: 207,
        headers: const {'x-http2': 'true'},
      );
      stream.add(utf8.encode('h2-a'));
      stream.add(utf8.encode('h2-b'));
      stream.close(utf8.encode('done'));
    });

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http2);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 11,
        method: 'GET',
        target: '/api/stream',
        path: '/api/stream',
        protocol: 'http/2',
        headers: const {'x-test': 'h2'},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.stream',
      ),
    );

    await _waitUntil(
      () => runtime.responseStreamOpens.isNotEmpty,
      timeout: const Duration(seconds: 2),
    );

    final open = runtime.responseStreamOpens.single;
    expect(open.handshakeHandle, 11);
    expect(open.status, 207);
    expect(open.headers['x-http2'], 'true');
    final handle = open.streamHandle;
    await _waitUntil(
      () => runtime.closedResponseStreams.contains(handle),
      timeout: const Duration(seconds: 2),
    );
    final chunks = runtime.responseStreamChunks[handle];
    expect(chunks, isNotNull);
    expect(chunks, hasLength(3));
    expect(utf8.decode(chunks![0]), 'h2-a');
    expect(utf8.decode(chunks[1]), 'h2-b');
    expect(utf8.decode(chunks[2]), 'done');
  });

  test('streams HTTP/3 response chunks using native streams', () async {
    final runtime = _HandleRuntime();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
            sniCertificates: [_cert('localhost')],
          ),
        ],
      ),
      settings: _buildRouterSettingsWithPendingProtocols(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    const connectionId = 45;

    final internalSession = await binding.createInternalSession(
      realmUri: 'realm1',
    );
    final registered = await internalSession.register('com.example.api.stream');
    registered.onInvoke((invocation) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      expect(context, isNotNull);
      final stream = context!.streamResponse(
        status: 208,
        headers: const {'x-http3': 'true'},
      );
      stream.add(utf8.encode('h3-a'));
      stream.close(utf8.encode('final-h3'));
    });

    runtime.enqueueConnection(listenerId, connectionId);
    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http3);
    runtime.enqueueHttp3Handshake(
      connectionId,
      NativeHttp3Handshake.synthetic(
        handle: 21,
        protocol: 'http/3',
        listenerProtocols: const ['rawsocket', 'http', 'http2', 'http3'],
      ),
    );
    runtime.enqueueHttp3Request(
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 22,
        method: 'GET',
        target: '/api/stream',
        path: '/api/stream',
        protocol: 'http/3',
        headers: const {'x-test': 'h3'},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.stream',
      ),
    );

    await _waitUntil(
      () => runtime.responseStreamOpens.isNotEmpty,
      timeout: const Duration(seconds: 2),
    );

    final open = runtime.responseStreamOpens.single;
    expect(open.handshakeHandle, 22);
    expect(open.status, 208);
    expect(open.headers['x-http3'], 'true');
    final handle = open.streamHandle;
    await _waitUntil(
      () => runtime.closedResponseStreams.contains(handle),
      timeout: const Duration(seconds: 2),
    );
    final chunks = runtime.responseStreamChunks[handle];
    expect(chunks, isNotNull);
    expect(chunks, hasLength(2));
    expect(utf8.decode(chunks![0]), 'h3-a');
    expect(utf8.decode(chunks[1]), 'final-h3');
  });

  test(
    'emits http_connection_event when runtime reports lifecycle event',
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
              sniCertificates: [_cert('localhost')],
            ),
          ],
        ),
        settings: _buildRouterSettingsWithPendingProtocols(),
      );

      final events = <Map<String, Object?>>[];
      final binding = router.start(
        runtime,
        onEvent: (event) {
          if (event is Map<String, Object?>) {
            events.add(event);
          }
        },
      );
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      const connectionId = 73;

      final internalSession = await binding.createInternalSession(
        realmUri: 'realm1',
      );
      final registered = await internalSession.register('com.example.http2');
      registered.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull);
        context!.sendText(body: 'OK');
      });

      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http2,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 9,
          method: 'GET',
          target: '/metrics',
          path: '/metrics',
          protocol: 'http/2',
          headers: const {'x-test': 'lifecycle'},
          body: Uint8List.fromList(utf8.encode('{}')),
          realm: 'realm1',
          procedure: 'com.example.http2',
        ),
      );

      await _waitUntil(
        () => events.any((event) => event['type'] == 'listener_http_request'),
        timeout: const Duration(seconds: 2),
      );

      runtime.enqueueHttpConnectionEvent(
        NativeHttpConnectionEvent(
          connectionId: connectionId,
          protocol: NativeConnectionProtocol.http2,
          reason: NativeHttpConnectionCloseReason.idleTimeout,
          requestCount: 2,
          idleTimeouts: 1,
          bodyTimeouts: 0,
          backpressureEvents: 0,
          maxBackpressureDepth: 0,
          goAwayEvents: 1,
          detail: 'idle timeout triggered',
        ),
      );

      await _waitUntil(
        () => events.any((event) => event['type'] == 'http_connection_event'),
        timeout: const Duration(seconds: 2),
      );

      final lifecycle = events.firstWhere(
        (event) => event['type'] == 'http_connection_event',
      );
      expect(lifecycle['connectionId'], connectionId);
      expect(lifecycle['protocol'], 'http2');
      expect(lifecycle['reason'], 'idle_timeout');
      expect(lifecycle['requestCount'], 2);
      expect(lifecycle['backpressureEvents'], 0);
      expect(lifecycle['maxBackpressureDepth'], 0);
      expect(lifecycle['goAwayEvents'], greaterThanOrEqualTo(1));
      expect(lifecycle['detail'], 'idle timeout triggered');
    },
  );

  test(
    'emits http_connection_event with body timeout reason and detail',
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
              sniCertificates: [_cert('localhost')],
            ),
          ],
        ),
        settings: _buildRouterSettingsWithPendingProtocols(),
      );

      final events = <Map<String, Object?>>[];
      final binding = router.start(
        runtime,
        onEvent: (event) {
          if (event is Map<String, Object?>) {
            events.add(event);
          }
        },
      );
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      const connectionId = 97;
      runtime.enqueueHttpConnectionEvent(
        NativeHttpConnectionEvent(
          connectionId: connectionId,
          protocol: NativeConnectionProtocol.http3,
          reason: NativeHttpConnectionCloseReason.bodyTimeout,
          requestCount: 1,
          idleTimeouts: 0,
          bodyTimeouts: 1,
          backpressureEvents: 0,
          maxBackpressureDepth: 0,
          goAwayEvents: 1,
          detail: 'body timeout triggered',
        ),
      );

      await _waitUntil(
        () => events.any((event) => event['type'] == 'http_connection_event'),
        timeout: const Duration(seconds: 2),
      );

      final lifecycle = events.firstWhere(
        (event) => event['type'] == 'http_connection_event',
      );
      expect(lifecycle['connectionId'], connectionId);
      expect(lifecycle['protocol'], 'http3');
      expect(lifecycle['reason'], 'body_timeout');
      expect(lifecycle['requestCount'], 1);
      expect(lifecycle['goAwayEvents'], equals(1));
      expect(lifecycle['detail'], 'body timeout triggered');
    },
  );

  test('emits http_connection_event with GOAWAY reason and detail', () async {
    final runtime = _HandleRuntime();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
            sniCertificates: [_cert('localhost')],
          ),
        ],
      ),
      settings: _buildRouterSettingsWithPendingProtocols(),
    );

    final events = <Map<String, Object?>>[];
    final binding = router.start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          events.add(event);
        }
      },
    );
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    const connectionId = 88;
    runtime.enqueueHttpConnectionEvent(
      NativeHttpConnectionEvent(
        connectionId: connectionId,
        protocol: NativeConnectionProtocol.http3,
        reason: NativeHttpConnectionCloseReason.goAway,
        requestCount: 1,
        idleTimeouts: 0,
        bodyTimeouts: 0,
        backpressureEvents: 0,
        maxBackpressureDepth: 0,
        goAwayEvents: 2,
        detail: 'remote GOAWAY: idle timeout',
      ),
    );

    await _waitUntil(
      () => events.any((event) => event['type'] == 'http_connection_event'),
      timeout: const Duration(seconds: 2),
    );

    final lifecycle = events.firstWhere(
      (event) => event['type'] == 'http_connection_event',
    );
    expect(lifecycle['connectionId'], connectionId);
    expect(lifecycle['protocol'], 'http3');
    expect(lifecycle['reason'], 'goaway');
    expect(lifecycle['goAwayEvents'], equals(2));
    expect(lifecycle['detail'], 'remote GOAWAY: idle timeout');
  });

  test('dispatches HTTP/3 request when stream queued', () async {
    final runtime = _HandleRuntime();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
            sniCertificates: [_cert('localhost')],
          ),
        ],
      ),
      settings: _buildRouterSettingsWithPendingProtocols(),
    );

    final events = <Map<String, Object?>>[];
    final binding = router.start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          events.add(event);
        }
      },
    );
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    const connectionId = 66;

    final internalSession = await binding.createInternalSession(
      realmUri: 'realm1',
    );
    final registered = await internalSession.register('com.example.api.health');
    registered.onInvoke((invocation) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      expect(context, isNotNull);
      expect(context!.request.protocol, 'http/3');
      context.sendText(
        body: 'OK',
        status: 202,
        headers: const {'x-http3': 'true'},
      );
    });

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http3);
    runtime.enqueueHttp3Handshake(
      connectionId,
      NativeHttp3Handshake.synthetic(
        handle: 3,
        protocol: 'http/3',
        alpn: 'h3',
        listenerProtocols: const ['rawsocket', 'http', 'http2', 'http3'],
      ),
    );
    runtime.enqueueHandle(listenerId, connectionId);

    await _waitUntil(
      () => events.any(
        (event) =>
            event['type'] == 'listener_protocol_pending' &&
            event['connectionId'] == connectionId,
      ),
      timeout: const Duration(seconds: 2),
    );

    runtime.enqueueHttp3Request(
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 11,
        method: 'GET',
        target: '/metrics',
        path: '/metrics',
        protocol: 'http/3',
        headers: const {'x-test': 'true'},
        body: Uint8List.fromList(utf8.encode('{}')),
        realm: 'realm1',
        procedure: 'com.example.api.health',
      ),
    );
    await _waitUntil(
      () => events.any(
        (event) =>
            event['type'] == 'listener_http_request' &&
            event['connectionId'] == connectionId,
      ),
      timeout: const Duration(seconds: 2),
    );

    final httpEvent = events.firstWhere(
      (event) =>
          event['type'] == 'listener_http_request' &&
          event['connectionId'] == connectionId,
    );
    expect(httpEvent['protocol'], 'http/3');
    expect(httpEvent['method'], 'GET');
    expect(httpEvent['path'], '/metrics');
    expect(httpEvent['realm'], 'realm1');
    expect(httpEvent['procedure'], 'com.example.api.health');

    await _waitUntil(
      () => events.any(
        (event) =>
            event['type'] == 'http_response_ready' &&
            event['connectionId'] == connectionId,
      ),
      timeout: const Duration(seconds: 2),
    );

    final responseEvent = events.firstWhere(
      (event) => event['type'] == 'http_response_ready',
    );
    final response = responseEvent['response'] as Map;
    expect(response['status'], 202);
    final headers = response['headers'] as Map;
    expect(headers['x-http3'], 'true');

    final recorded = runtime.httpResponses[connectionId];
    expect(recorded, isNotNull);
    expect(recorded!.single.status, 202);
    final body = recorded.single.body;
    expect(body, isA<NativeHttpResponseText>());
    expect((body as NativeHttpResponseText).text, 'OK');
  });

  test('emits listener_protocol_pending for HTTP/2 handshake', () async {
    final runtime = _HandleRuntime();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
            sniCertificates: [_cert('localhost')],
          ),
        ],
      ),
      settings: _buildRouterSettingsWithPendingProtocols(),
    );

    final events = <Map<String, Object?>>[];
    final binding = router.start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          events.add(event);
        }
      },
    );
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    const connectionId = 84;

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http2);
    runtime.enqueueHttp2Handshake(
      connectionId,
      NativeHttp2Handshake.synthetic(
        handle: 1,
        protocol: 'http/2',
        alpn: 'h2',
        listenerProtocols: const <String>['rawsocket', 'http', 'http2'],
      ),
    );

    runtime.enqueueHandle(listenerId, connectionId);

    await _waitUntil(
      () => events.any(
        (event) =>
            event['type'] == 'listener_protocol_pending' &&
            event['connectionId'] == connectionId,
      ),
    );

    final pending = events.firstWhere(
      (event) =>
          event['type'] == 'listener_protocol_pending' &&
          event['connectionId'] == connectionId,
    );
    expect(pending['protocol'], equals('http2'));
    final details = pending['details'] as Map?;
    expect(details?['protocol'], equals('http/2'));
    expect(details?['alpn'], equals('h2'));
    expect(
      (details?['listenerProtocols'] as List?)?.cast<String>(),
      equals(<String>['rawsocket', 'http', 'http2']),
    );
  });

  test('emits listener_protocol_pending for HTTP/3 handshake', () async {
    final runtime = _HandleRuntime();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
            sniCertificates: [_cert('localhost')],
          ),
        ],
      ),
      settings: _buildRouterSettingsWithPendingProtocols(),
    );

    final events = <Map<String, Object?>>[];
    final binding = router.start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          events.add(event);
        }
      },
    );
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    const connectionId = 85;

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http3);
    runtime.enqueueHttp3Handshake(
      connectionId,
      NativeHttp3Handshake.synthetic(
        handle: 2,
        protocol: 'http/3',
        alpn: 'h3',
        listenerProtocols: const <String>[
          'rawsocket',
          'http',
          'http2',
          'http3',
        ],
      ),
    );

    runtime.enqueueHandle(listenerId, connectionId);

    await _waitUntil(
      () => events.any(
        (event) =>
            event['type'] == 'listener_protocol_pending' &&
            event['connectionId'] == connectionId,
      ),
    );

    final pending = events.firstWhere(
      (event) =>
          event['type'] == 'listener_protocol_pending' &&
          event['connectionId'] == connectionId,
    );
    expect(pending['protocol'], equals('http3'));
    final details = pending['details'] as Map?;
    expect(details?['protocol'], equals('http/3'));
    expect(details?['alpn'], equals('h3'));
    expect(details?['http3Port'], equals(binding.listeners.single.http3Port));
    expect(
      (details?['listenerProtocols'] as List?)?.cast<String>(),
      equals(<String>['rawsocket', 'http', 'http2', 'http3']),
    );
  });

  test('http2 connections are drained for additional requests', () async {
    final runtime = _HandleRuntime();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
            sniCertificates: [_cert('localhost')],
          ),
        ],
      ),
      settings: _buildRouterSettingsWithPendingProtocols(),
    );

    final events = <Map<String, Object?>>[];
    final binding = router.start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          events.add(event);
        }
      },
    );
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    const connectionId = 99;

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http2);
    runtime.enqueueHttp2Handshake(
      connectionId,
      NativeHttp2Handshake.synthetic(
        handle: 700,
        protocol: 'http/2',
        alpn: 'h2',
        listenerProtocols: const <String>['rawsocket', 'http', 'http2'],
      ),
    );
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 701,
        method: 'POST',
        target: '/alpha',
        path: '/alpha',
        protocol: 'http/2',
        headers: const {},
        body: Uint8List(0),
      ),
    );
    runtime.enqueueHandle(listenerId, connectionId);

    await _waitUntil(
      () => events.any(
        (event) =>
            event['type'] == 'listener_http_request' &&
            event['connectionId'] == connectionId &&
            event['path'] == '/alpha',
      ),
      timeout: const Duration(seconds: 2),
    );

    runtime.queueHttpRequestForConnection(
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 702,
        method: 'POST',
        target: '/beta',
        path: '/beta',
        protocol: 'http/2',
        headers: const {},
        body: Uint8List(0),
      ),
    );

    await _waitUntil(
      () => events.any(
        (event) =>
            event['type'] == 'listener_http_request' &&
            event['connectionId'] == connectionId &&
            event['path'] == '/beta',
      ),
      timeout: const Duration(seconds: 2),
    );

    final betaEvents = events.where(
      (event) =>
          event['type'] == 'listener_http_request' &&
          event['connectionId'] == connectionId &&
          event['path'] == '/beta',
    );
    expect(betaEvents, isNotEmpty);
  });
}
