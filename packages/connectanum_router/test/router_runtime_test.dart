@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library router_runtime_test;

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart'
    show CraAuthentication, ScramAuthentication, TicketAuthentication;
import 'package:connectanum_core/connectanum_core.dart'
    show
        CallOptions,
        Details,
        Extra,
        LazyMessagePayload,
        LazyPayloadEncoding,
        MessageTypes,
        PPTPayload,
        Publish,
        PublishOptions;
import 'package:connectanum_core/connectanum_core.dart' show YieldOptions;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/sni_certificate.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;
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
  final List<int> closedListeners = [];
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
  final List<int> http3HandshakePolls = [];
  final List<int> http3RequestPolls = [];
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
  void closeListener(int listenerId) {
    closedListeners.add(listenerId);
  }

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
    http3HandshakePolls.add(connectionId);
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
    http3RequestPolls.add(connectionId);
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
  NativeHttpResponseStreamDescriptor openHttpResponseStreamDescriptor({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    throw UnsupportedError('HTTP response stream descriptors not supported');
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

Map<String, Object?> _jsonResponseBody(NativeHttpResponse response) {
  final body = response.body;
  if (body is NativeHttpResponseJson) {
    return Map<String, Object?>.from(body.value as Map);
  }
  if (body is NativeHttpResponseText) {
    return Map<String, Object?>.from(json.decode(body.text) as Map);
  }
  if (body is NativeHttpResponseBytes) {
    return Map<String, Object?>.from(
      json.decode(utf8.decode(body.bytes)) as Map,
    );
  }
  throw StateError('Unsupported HTTP response body: ${body.runtimeType}');
}

void _enqueueSyntheticHttpRequest({
  required _HandleRuntime runtime,
  required int listenerId,
  required int connectionId,
  required int handle,
  required String method,
  required String target,
  String protocol = 'http/1.1',
  required Map<String, String> headers,
  required Object? body,
  required String realm,
  required String procedure,
}) {
  runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
  runtime.enqueueHttpHandshake(
    listenerId,
    connectionId,
    NativeHttpHandshake.synthetic(
      handle: handle,
      method: method,
      target: target,
      path: target.split('?').first,
      protocol: protocol,
      headers: headers,
      body: body == null
          ? Uint8List(0)
          : Uint8List.fromList(utf8.encode(json.encode(body))),
      realm: realm,
      procedure: procedure,
    ),
  );
}

Future<({String accessToken, String refreshToken})> _issueTicketHttpTokens({
  required _HandleRuntime runtime,
  required int listenerId,
  int startConnectionId = 60,
  String authId = 'user-1',
  String realm = 'realm1',
  String ticket = 'signed-token',
}) => _issueHttpBridgeTokens(
  runtime: runtime,
  listenerId: listenerId,
  startConnectionId: startConnectionId,
  authId: authId,
  realm: realm,
  authMethod: 'ticket',
  authSecret: ticket,
);

Future<({String accessToken, String refreshToken})> _issueHttpBridgeTokens({
  required _HandleRuntime runtime,
  required int listenerId,
  required String authMethod,
  required String authSecret,
  int startConnectionId = 60,
  String authId = 'user-1',
  String realm = 'realm1',
}) async {
  final startBody = <String, Object?>{
    'realm': realm,
    'authmethod': authMethod,
    'authid': authId,
  };
  ScramAuthentication? scramAuthentication;
  if (authMethod == 'scram') {
    scramAuthentication = ScramAuthentication(authSecret);
    final helloDetails = Details.forHello()
      ..authmethods = [authMethod]
      ..authid = authId;
    await scramAuthentication.hello(realm, helloDetails);
    startBody['authextra'] = Map<String, Object?>.from(
      helloDetails.authextra ?? const <String, Object?>{},
    );
  }

  _enqueueSyntheticHttpRequest(
    runtime: runtime,
    listenerId: listenerId,
    connectionId: startConnectionId,
    handle: startConnectionId - 40,
    method: 'POST',
    target: '/auth',
    headers: const {'content-type': 'application/json'},
    body: startBody,
    realm: 'router.http',
    procedure: 'router.http.auth',
  );

  await _waitUntil(
    () => runtime.httpResponses[startConnectionId]?.isNotEmpty ?? false,
  );
  final challengeBody = _jsonResponseBody(
    runtime.httpResponses[startConnectionId]!.single,
  );
  final state = challengeBody['state'] as String;
  final authenticate = switch (authMethod) {
    'ticket' => await TicketAuthentication(authSecret).challenge(Extra()),
    'wampcra' => await CraAuthentication(
      authSecret,
    ).challenge(_httpAuthChallengeExtraFromBody(challengeBody)),
    'scram' => await scramAuthentication!.challenge(
      _httpAuthChallengeExtraFromBody(challengeBody),
    ),
    _ => throw UnsupportedError('Unsupported HTTP auth method $authMethod'),
  };

  _enqueueSyntheticHttpRequest(
    runtime: runtime,
    listenerId: listenerId,
    connectionId: startConnectionId + 1,
    handle: startConnectionId - 39,
    method: 'POST',
    target: '/auth',
    headers: const {'content-type': 'application/json'},
    body: <String, Object?>{
      'state': state,
      'signature': authenticate.signature,
      'extra': authenticate.extra,
    },
    realm: 'router.http',
    procedure: 'router.http.auth',
  );

  await _waitUntil(
    () => runtime.httpResponses[startConnectionId + 1]?.isNotEmpty ?? false,
  );
  final success = _jsonResponseBody(
    runtime.httpResponses[startConnectionId + 1]!.single,
  );
  return (
    accessToken: success['access_token'] as String,
    refreshToken: success['refresh_token'] as String,
  );
}

Extra _httpAuthChallengeExtraFromBody(Map<String, Object?> body) {
  final rawChallenge = body['challenge'];
  final challenge = rawChallenge is Map<String, Object?>
      ? rawChallenge
      : rawChallenge is Map
      ? Map<String, Object?>.from(rawChallenge)
      : const <String, Object?>{};
  return Extra(
    challenge: challenge['challenge'] as String?,
    nonce: challenge['nonce'] as String?,
    salt: challenge['salt'] as String?,
    keyLen: challenge['keylen'] as int?,
    iterations: challenge['iterations'] as int?,
    memory: challenge['memory'] as int?,
    kdf: challenge['kdf'] as String?,
  );
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

void _delayedDrainWorkerEntryPoint(Map<String, Object?> init) {
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
    if (command == kWorkerCmdAddConnection) {
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
      Timer(const Duration(milliseconds: 250), () {
        for (final entry in connections.entries.toList()) {
          bossPort.send({
            'type': kWorkerEventConnectionRemoved,
            'connectionId': entry.key,
          });
          connections.remove(entry.key);
        }
        bossPort.send({'type': kWorkerEventDrained, 'workerHash': workerHash});
      });
    }
  });
}

Future<(int, String)> _getHealth(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

const _fakeFastCgiHeaderLength = 8;
const _fakeFastCgiParams = 4;
const _fakeFastCgiStdin = 5;
const _fakeFastCgiStdout = 6;
const _fakeFastCgiEndRequest = 3;

class _FakeFastCgiRequest {
  const _FakeFastCgiRequest({required this.params, required this.stdin});

  final Map<String, String> params;
  final Uint8List stdin;
}

Future<_FakeFastCgiRequest> _readFakeFastCgiRequest(Socket socket) async {
  final params = BytesBuilder(copy: false);
  final stdin = BytesBuilder(copy: false);
  var paramsComplete = false;
  var stdinComplete = false;
  var pending = <int>[];
  final completer = Completer<_FakeFastCgiRequest>();
  late final StreamSubscription<List<int>> subscription;

  void completeIfReady() {
    if (paramsComplete && stdinComplete && !completer.isCompleted) {
      subscription.pause();
      completer.complete(
        _FakeFastCgiRequest(
          params: _decodeFakeFastCgiParams(params.takeBytes()),
          stdin: stdin.takeBytes(),
        ),
      );
    }
  }

  subscription = socket.listen(
    (chunk) {
      if (completer.isCompleted) {
        return;
      }
      pending.addAll(chunk);
      while (pending.length >= _fakeFastCgiHeaderLength) {
        final type = pending[1];
        final contentLength = (pending[4] << 8) | pending[5];
        final paddingLength = pending[6];
        final recordLength =
            _fakeFastCgiHeaderLength + contentLength + paddingLength;
        if (pending.length < recordLength) {
          break;
        }
        final content = Uint8List.fromList(
          pending.sublist(
            _fakeFastCgiHeaderLength,
            _fakeFastCgiHeaderLength + contentLength,
          ),
        );
        pending = pending.sublist(recordLength);
        if (type == _fakeFastCgiParams) {
          if (content.isEmpty) {
            paramsComplete = true;
          } else {
            params.add(content);
          }
        } else if (type == _fakeFastCgiStdin) {
          if (content.isEmpty) {
            stdinComplete = true;
          } else {
            stdin.add(content);
          }
        }
        completeIfReady();
      }
    },
    onError: completer.completeError,
    onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('FastCGI request ended before stdin completed'),
        );
      }
    },
    cancelOnError: true,
  );
  return completer.future;
}

Map<String, String> _decodeFakeFastCgiParams(Uint8List bytes) {
  final result = <String, String>{};
  var offset = 0;
  while (offset < bytes.length) {
    final (nameLength, nameOffset) = _readFakeFastCgiLength(bytes, offset);
    final (valueLength, valueOffset) = _readFakeFastCgiLength(
      bytes,
      nameOffset,
    );
    final nameEnd = valueOffset + nameLength;
    final valueEnd = nameEnd + valueLength;
    final name = utf8.decode(
      Uint8List.sublistView(bytes, valueOffset, nameEnd),
    );
    final value = utf8.decode(Uint8List.sublistView(bytes, nameEnd, valueEnd));
    result[name] = value;
    offset = valueEnd;
  }
  return result;
}

(int, int) _readFakeFastCgiLength(Uint8List bytes, int offset) {
  final first = bytes[offset];
  if ((first & 0x80) == 0) {
    return (first, offset + 1);
  }
  final length =
      ((first & 0x7f) << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  return (length, offset + 4);
}

void _writeFakeFastCgiRecord(
  Socket socket,
  int type,
  int requestId,
  List<int> content,
) {
  final paddingLength = (8 - (content.length % 8)) % 8;
  socket.add([
    1,
    type,
    (requestId >> 8) & 0xff,
    requestId & 0xff,
    (content.length >> 8) & 0xff,
    content.length & 0xff,
    paddingLength,
    0,
  ]);
  if (content.isNotEmpty) {
    socket.add(content);
  }
  if (paddingLength > 0) {
    socket.add(Uint8List(paddingLength));
  }
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

RouterSettings _buildRouterSettingsWithSessionProfiles() {
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
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
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
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('public-wamp')..addAuthMethod('anonymous'),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('http-handler')
        ..setRealm('realm1')
        ..setAuthId('http-handler')
        ..setAuthRole('internal')
        ..putRole('callee', const {'features': <String, Object?>{}}),
    )
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..setSessionProfile('public-wamp')
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
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/api/health'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    procedure: 'com.example.api.health',
                    sessionProfile: 'http-handler',
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

RouterSettings _buildRouterSettingsWithHttpAuthBridge() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod(
          'ticket',
          options: const {'authenticator': 'ticket-basic'},
        )
        ..addAuthMethod(
          'wampcra',
          options: const {'authenticator': 'cra-basic'},
        )
        ..addAuthMethod(
          'scram',
          options: const {'authenticator': 'scram-basic'},
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('member')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call']),
          ),
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('public-wamp')..addAuthMethod('anonymous'),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('http-ticket')
        ..setRealm('realm1')
        ..setAuthMethods(const ['ticket', 'wampcra', 'scram']),
    )
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..setSessionProfile('public-wamp')
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..addProtocol(ListenerProtocol.rawsocket)
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/auth'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.auth,
                    sessionProfile: 'http-ticket',
                    options: <String, Object?>{
                      'token_ttl_ms': 60000,
                      'refresh_token_ttl_ms': 300000,
                      'rotate_refresh_tokens': true,
                    },
                  ),
                ),
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/api/secure'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    procedure: 'com.example.api.secure',
                    sessionProfile: 'http-ticket',
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
    )
    ..addAuthenticator(
      'ticket-basic',
      const AuthenticatorDefinition(
        type: 'ticket',
        options: <String, Object?>{
          'secrets': <String, Object?>{
            'user-1': <String, Object?>{
              'ticket': 'signed-token',
              'role': 'member',
              'provider': 'ticket-db',
            },
          },
        },
      ),
    )
    ..addAuthenticator(
      'cra-basic',
      const AuthenticatorDefinition(
        type: 'wampcra',
        options: <String, Object?>{
          'secrets': <String, Object?>{
            'user-1': <String, Object?>{
              'secret': 'secret-1',
              'salt': 'bench-cra-salt',
              'iterations': 1000,
              'keylen': 32,
              'role': 'member',
              'provider': 'cra-db',
              'challenge': <String, Object?>{'scope': 'http-auth'},
            },
          },
        },
      ),
    )
    ..addAuthenticator(
      'scram-basic',
      const AuthenticatorDefinition(
        type: 'scram',
        options: <String, Object?>{
          'secrets': <String, Object?>{
            'user-1': <String, Object?>{
              'secret': 'pencil',
              'salt': 'CgsMDQ4PEBESExQVFhcYGQ==',
              'iterations': 4096,
              'role': 'member',
              'provider': 'scram-db',
            },
          },
        },
      ),
    );
  return builder.build();
}

RouterSettings _buildRouterSettingsWithHttpJwtProvider() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('member')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call']),
          ),
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('http-jwt')
        ..setRealm('realm1')
        ..setAuthMethods(const ['jwt'])
        ..setHttpProvider('edge-jwt'),
    )
    ..addHttpAuthProvider(
      'edge-jwt',
      const HttpAuthProviderDefinition(
        type: 'jwt',
        options: <String, Object?>{
          'hmac_secret': 'jwt-secret',
          'issuer': 'https://issuer.example',
          'audience': <String>['connectanum-http'],
          'auth_id_claim': 'sub',
          'auth_role_claim': 'role',
        },
      ),
    )
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addAuthMethod('anonymous')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/api/jwt'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    procedure: 'com.example.api.jwt',
                    sessionProfile: 'http-jwt',
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

RouterSettings _buildRouterSettingsWithHttpMtlsRoute() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/api/mtls'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    procedure: 'com.example.api.mtls',
                    options: <String, Object?>{'require_mtls': true},
                  ),
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    );
  return builder.build();
}

RouterSettings _buildRouterSettingsWithHttpProtocolRoute() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(
                    path: '/api/h2-only',
                    protocols: ['http/2'],
                  ),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    procedure: 'com.example.api.h2',
                  ),
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    );
  return builder.build();
}

RouterSettings _buildRouterSettingsWithHttpMethodRoute() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(
                    path: '/api/get-only',
                    methods: ['GET'],
                  ),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    procedure: 'com.example.api.get',
                  ),
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    );
  return builder.build();
}

RouterSettings _buildRouterSettingsWithHttpMethodActionRoute() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/api/items', methods: ['GET']),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    realm: 'realm1',
                    procedure: 'com.example.items.list',
                  ),
                  methodActions: {
                    'POST': HttpRouteAction(
                      type: HttpRouteActionType.rpc,
                      realm: 'realm1',
                      procedure: 'com.example.items.create',
                    ),
                  },
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    );
  return builder.build();
}

RouterSettings _buildRouterSettingsWithHttpRateLimitRoute() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/api/limited'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    realm: 'realm1',
                    procedure: 'com.example.api.limited',
                    rateLimit: HttpRouteRateLimitSettings(
                      maxRequests: 1,
                      window: Duration(seconds: 30),
                    ),
                  ),
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    );
  return builder.build();
}

RouterSettings _buildRouterSettingsWithHttpConcurrencyLimitRoute() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
            PermissionSettingsBuilder('')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/api/throttled'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    realm: 'realm1',
                    procedure: 'com.example.api.throttled',
                    concurrencyLimit: HttpRouteConcurrencyLimitSettings(
                      maxConcurrent: 1,
                    ),
                  ),
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    );
  return builder.build();
}

RouterSettings _buildRouterSettingsWithHttpAccessLogRoute() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
            PermissionSettingsBuilder('')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/api/logged'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    realm: 'realm1',
                    procedure: 'com.example.api.logged',
                    accessLog: HttpRouteAccessLogSettings(
                      includeQuery: true,
                      includeHeaders: true,
                    ),
                  ),
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    );
  return builder.build();
}

RouterSettings _buildRouterSettingsWithHttpCatchAllRoute() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register', 'unregister']),
          ),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(catchAll: true),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    realm: 'realm1',
                    procedure: 'com.example.http.fallback',
                  ),
                ),
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/auth'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.auth,
                    sessionProfile: 'public-http',
                  ),
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    );
  return builder.build();
}

RouterSettings _buildRouterSettingsWithHttpShorthandRoutes() {
  PermissionSettingsBuilder allowBridgeOperations() =>
      PermissionSettingsBuilder('')
        ..setMatchPolicy(PermissionMatchPolicy.prefix)
        ..allowOperations(const ['call', 'register', 'unregister']);
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('router.http')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('anonymous')
            ..addPermissionFromBuilder(allowBridgeOperations()),
        ),
    )
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('anonymous')
            ..addPermissionFromBuilder(allowBridgeOperations()),
        ),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setRawSocketOptions(
            const RawSocketListenerSettings(maxFrameExponent: 16),
          )
          ..setHttpOptions(
            const HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.reservedRealm,
                  ),
                ),
                HttpRouteSettings(
                  match: HttpRouteMatch(prefix: '/tasks/'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.namespace,
                    realm: 'realm1',
                    namespace: 'consumer.api',
                  ),
                ),
              ],
            ),
          ))
        ..setOptions(const {'max_rawsocket_size_exponent': 16}),
    );
  return builder.build();
}

String _encodeHs256Jwt({
  required Map<String, Object?> claims,
  required String secret,
}) {
  final header = <String, Object?>{'alg': 'HS256', 'typ': 'JWT'};
  final encodedHeader = base64Url
      .encode(utf8.encode(jsonEncode(header)))
      .replaceAll('=', '');
  final encodedClaims = base64Url
      .encode(utf8.encode(jsonEncode(claims)))
      .replaceAll('=', '');
  final signingInput = '$encodedHeader.$encodedClaims';
  final signature = CraAuthentication.encodeByteHmac(
    Uint8List.fromList(utf8.encode(secret)),
    32,
    utf8.encode(signingInput),
  );
  final encodedSignature = base64Url.encode(signature).replaceAll('=', '');
  return '$signingInput.$encodedSignature';
}

RouterSettings _buildRestrictedInternalSessionSettings() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('member')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations(const ['call', 'register']),
          ),
        ),
    )
    ..addListenerFromBuilder(
      (ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
        ..addAuthMethod('anonymous')
        ..setRawSocketOptions(
          const RawSocketListenerSettings(maxFrameExponent: 16),
        )),
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

    test(
      'drain closes listeners and pending connections without boss',
      () async {
        final runtime = _FakeRuntime();
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
        );

        final binding = router.start(runtime);
        addTearDown(binding.dispose);
        final listener = binding.listeners.single;
        runtime.enqueueConnection(listener.listenerId, 7001);

        await binding.drain();

        expect(runtime.closedListeners, contains(listener.listenerId));
        expect(runtime.closedConnections, contains(7001));
      },
    );

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

  group('Router boss pacing', () {
    test('uses zero delay when a loop pass processed work', () {
      expect(
        routerBossLoopDelay(
          didWork: true,
          pollInterval: const Duration(milliseconds: 25),
        ),
        Duration.zero,
      );
      expect(
        routerBossLoopDelay(
          didWork: false,
          pollInterval: const Duration(milliseconds: 25),
        ),
        const Duration(milliseconds: 25),
      );
    });

    test('waits for the poll interval only when idle', () async {
      final pacer = RouterBossLoopPacer();
      final stopwatch = Stopwatch()..start();
      await pacer.waitForNextTick(
        didWork: false,
        pollInterval: const Duration(milliseconds: 20),
      );
      stopwatch.stop();
      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 10)),
      );
    });

    test('yields immediately after a busy loop pass', () async {
      final pacer = RouterBossLoopPacer();
      await pacer
          .waitForNextTick(
            didWork: true,
            pollInterval: const Duration(seconds: 1),
          )
          .timeout(const Duration(milliseconds: 200));
    });

    test('wakes an idle wait from queued or in-flight work', () async {
      final preSignaled = RouterBossLoopPacer()..requestWake();
      await preSignaled
          .waitForNextTick(
            didWork: false,
            pollInterval: const Duration(seconds: 1),
          )
          .timeout(const Duration(milliseconds: 200));

      final pacer = RouterBossLoopPacer();
      final wait = pacer.waitForNextTick(
        didWork: false,
        pollInterval: const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      pacer.requestWake();
      await wait.timeout(const Duration(milliseconds: 200));
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

    test('rawsocket connections do not probe for http3 handshakes', () async {
      final runtime = _FakeRuntime();
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
      );

      final binding = router.start(
        runtime,
        workerEntryPoint: _testWorkerEntryPoint,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(binding.dispose);

      final listener = binding.listeners.single;
      const connectionId = 9103;
      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.rawsocket,
      );
      runtime.enqueueConnection(listener.listenerId, connectionId);

      binding.pollNativeMessages();

      expect(runtime.http3HandshakePolls, isEmpty);
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

        await _waitUntil(
          () =>
              events
                  .whereType<Map>()
                  .where((event) => event['type'] == 'worker_registered')
                  .length >=
              2,
        );

        runtime.enqueueHandle(listener.listenerId, 6101);
        runtime.enqueueHandle(listener.listenerId, 6102);

        await _waitUntil(
          () =>
              events
                  .whereType<Map>()
                  .where((event) => event['type'] == 'worker_connection_added')
                  .length >=
              2,
        );

        final registeredConnections = events
            .whereType<Map>()
            .where((event) => event['type'] == 'worker_connection_added')
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

      expect(drainEvents, isNotEmpty);
      for (final drainEvent in drainEvents) {
        final drainPayload = drainEvent['payload'] as Map;
        expect(drainPayload['reason'], equals('wamp.close.system_shutdown'));
      }

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
      expect(workerDrained, isNotEmpty);
    });

    test('healthz returns draining while drain in progress', () async {
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
        workerEntryPoint: _delayedDrainWorkerEntryPoint,
        onEvent: events.add,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(binding.dispose);
      final listener = binding.listeners.single;
      runtime.enqueueHandle(listener.listenerId, 8001);

      await _waitUntil(() {
        return events.whereType<Map>().any(
          (event) =>
              event['type'] == 'worker_ready' && event['connectionId'] == 8001,
        );
      }, timeout: const Duration(seconds: 2));

      final server = await binding.startOpenMetricsHttpServer(
        settingsOverride: const OpenMetricsSettings(
          enabled: true,
          listen: '127.0.0.1:0',
        ),
      );
      expect(server, isNotNull);
      final base = Uri(scheme: 'http', host: '127.0.0.1', port: server!.port);

      final drainFuture = binding.drain(
        drainTimeout: const Duration(seconds: 2),
      );

      final (status, body) = await _getHealth(base.replace(path: '/healthz'));
      expect(status, equals(503));
      expect(body, contains('draining'));

      await drainFuture;

      final (finalStatus, finalBody) = await _getHealth(
        base.replace(path: '/healthz'),
      );
      expect(finalStatus, equals(200));
      expect(finalBody, contains('ok'));
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

  test('maps HTTP response helper bodies into native responses', () async {
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
      settings: _buildRouterSettingsWithSessionProfiles(),
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

    final tempDir = await Directory.systemTemp.createTemp(
      'connectanum-http-file-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final staticFile = File(
      '${tempDir.path}${Platform.pathSeparator}contract.txt',
    );
    await staticFile.writeAsString('file-contract-ok');

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;

    final internalSession = await binding.createInternalSession(
      realmUri: 'realm1',
    );
    addTearDown(internalSession.close);
    final registered = await internalSession.register('com.example.api.health');
    registered.onInvoke((invocation) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      expect(context, isNotNull);
      switch (context!.request.target) {
        case '/api/health?kind=bytes':
          context.sendBytes(
            body: Uint8List.fromList([0, 1, 2, 255]),
            status: 202,
            headers: const {'content-type': 'application/octet-stream'},
          );
          break;
        case '/api/health?kind=json':
          context.sendJson(
            body: const {'ok': true, 'kind': 'json'},
            status: 201,
            headers: const {'x-contract': 'json'},
          );
          break;
        case '/api/health?kind=file':
          context.sendFile(
            path: staticFile.path,
            status: 203,
            headers: const {'content-type': 'text/plain'},
          );
          break;
        default:
          fail('Unexpected HTTP target ${context.request.target}');
      }
    });

    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: listenerId,
      connectionId: 301,
      handle: 3010,
      method: 'GET',
      target: '/api/health?kind=bytes',
      headers: const {'x-test': 'bytes'},
      body: null,
      realm: 'realm1',
      procedure: 'com.example.api.health',
    );
    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: listenerId,
      connectionId: 302,
      handle: 3020,
      method: 'GET',
      target: '/api/health?kind=json',
      headers: const {'x-test': 'json'},
      body: null,
      realm: 'realm1',
      procedure: 'com.example.api.health',
    );
    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: listenerId,
      connectionId: 303,
      handle: 3030,
      method: 'GET',
      target: '/api/health?kind=file',
      headers: const {'x-test': 'file'},
      body: null,
      realm: 'realm1',
      procedure: 'com.example.api.health',
    );

    await _waitUntil(
      () =>
          (runtime.httpResponses[301]?.isNotEmpty ?? false) &&
          (runtime.httpResponses[302]?.isNotEmpty ?? false) &&
          (runtime.httpResponses[303]?.isNotEmpty ?? false),
    );

    final bytesResponse = runtime.httpResponses[301]!.single;
    expect(bytesResponse.status, 202);
    expect(bytesResponse.headers['content-type'], 'application/octet-stream');
    final bytesBody = bytesResponse.body;
    expect(bytesBody, isA<NativeHttpResponseBytes>());
    expect(
      (bytesBody as NativeHttpResponseBytes).bytes,
      orderedEquals([0, 1, 2, 255]),
    );

    final jsonResponse = runtime.httpResponses[302]!.single;
    expect(jsonResponse.status, 201);
    expect(
      jsonResponse.headers['content-type'],
      'application/json; charset=utf-8',
    );
    expect(jsonResponse.headers['x-contract'], 'json');
    final jsonBody = jsonResponse.body;
    expect(jsonBody, isA<NativeHttpResponseJson>());
    expect((jsonBody as NativeHttpResponseJson).value, {
      'ok': true,
      'kind': 'json',
    });

    final fileResponse = runtime.httpResponses[303]!.single;
    expect(fileResponse.status, 203);
    expect(fileResponse.headers['content-type'], 'text/plain');
    final fileBody = fileResponse.body;
    expect(fileBody, isA<NativeHttpResponseFile>());
    expect((fileBody as NativeHttpResponseFile).path, staticFile.path);

    final readyEvents = events
        .where((event) => event['type'] == 'http_response_ready')
        .map((event) => event['response'] as Map)
        .toList(growable: false);
    expect(
      readyEvents,
      contains(
        allOf(
          containsPair('status', 203),
          containsPair('bodyKind', 'file'),
          containsPair('filePath', staticFile.path),
        ),
      ),
    );
  });

  test(
    'serves configured HTTP file routes directly from the binding',
    () async {
      final runtime = _HandleRuntime();
      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum-http-static-route-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final staticFile = File(
        '${tempDir.path}${Platform.pathSeparator}hello.txt',
      );
      const fileContents = 'static route ok';
      await staticFile.writeAsString(fileContents);
      final outsideDir = await Directory.systemTemp.createTemp(
        'connectanum-http-static-outside-',
      );
      addTearDown(() async {
        if (await outsideDir.exists()) {
          await outsideDir.delete(recursive: true);
        }
      });
      final outsideFile = File(
        '${outsideDir.path}${Platform.pathSeparator}secret.txt',
      );
      await outsideFile.writeAsString('outside static root');
      await Link(
        '${tempDir.path}${Platform.pathSeparator}escape.txt',
      ).create(outsideFile.path);

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
        settings: RouterSettings(
          realms: const [],
          listeners: [
            ListenerSettings(
              endpoint: '127.0.0.1:0',
              protocols: const [ListenerProtocol.http],
              http: HttpListenerSettings(
                routes: [
                  HttpRouteSettings(
                    match: const HttpRouteMatch(prefix: '/static/'),
                    action: HttpRouteAction(
                      type: HttpRouteActionType.file,
                      directory: tempDir.path,
                      cacheControl: 'public, max-age=3600',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 304,
        handle: 3040,
        method: 'GET',
        target: '/static/hello.txt',
        headers: const {'x-test': 'file-route'},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 305,
        handle: 3050,
        method: 'GET',
        target: '/static/../secret.txt',
        headers: const {'x-test': 'file-route-traversal'},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 306,
        handle: 3060,
        method: 'GET',
        target: '/static/escape.txt',
        headers: const {'x-test': 'file-route-symlink-escape'},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 307,
        handle: 3070,
        method: 'HEAD',
        target: '/static/hello.txt',
        headers: const {'x-test': 'file-route-head'},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );

      await _waitUntil(
        () =>
            (runtime.httpResponses[304]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[305]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[306]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[307]?.isNotEmpty ?? false),
      );

      final ok = runtime.httpResponses[304]!.single;
      expect(ok.status, HttpStatus.ok);
      expect(
        ok.headers[HttpHeaders.contentTypeHeader],
        'text/plain; charset=utf-8',
      );
      expect(
        ok.headers[HttpHeaders.cacheControlHeader],
        'public, max-age=3600',
      );
      expect(
        ok.headers[HttpHeaders.contentLengthHeader],
        utf8.encode(fileContents).length.toString(),
      );
      expect(ok.headers['accept-ranges'], 'bytes');
      final etag = ok.headers[HttpHeaders.etagHeader]!;
      final lastModified = ok.headers[HttpHeaders.lastModifiedHeader]!;
      expect(etag, startsWith('W/"'));
      expect(ok.body, isA<NativeHttpResponseFile>());
      expect(
        (ok.body as NativeHttpResponseFile).path,
        staticFile.resolveSymbolicLinksSync(),
      );

      final traversal = runtime.httpResponses[305]!.single;
      expect(traversal.status, HttpStatus.notFound);
      expect(_jsonResponseBody(traversal)['reason'], 'file_not_found');

      final symlinkEscape = runtime.httpResponses[306]!.single;
      expect(symlinkEscape.status, HttpStatus.forbidden);
      expect(_jsonResponseBody(symlinkEscape)['reason'], 'file_forbidden');

      final head = runtime.httpResponses[307]!.single;
      expect(head.status, HttpStatus.ok);
      expect(
        head.headers[HttpHeaders.contentLengthHeader],
        utf8.encode(fileContents).length.toString(),
      );
      expect(head.body, isA<NativeHttpResponseBytes>());
      expect((head.body as NativeHttpResponseBytes).bytes, isEmpty);

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 310,
        handle: 3100,
        method: 'GET',
        target: '/static/hello.txt',
        headers: const {'range': 'bytes=7-11'},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 311,
        handle: 3110,
        method: 'HEAD',
        target: '/static/hello.txt',
        headers: const {'range': 'bytes=-2'},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 312,
        handle: 3120,
        method: 'GET',
        target: '/static/hello.txt',
        headers: const {'range': 'bytes=99-100'},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 313,
        handle: 3130,
        method: 'GET',
        target: '/static/hello.txt',
        headers: {'range': 'bytes=0-5', 'if-range': lastModified},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 314,
        handle: 3140,
        method: 'GET',
        target: '/static/hello.txt',
        headers: {'range': 'bytes=0-5', 'if-range': etag},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 315,
        handle: 3150,
        method: 'GET',
        target: '/static/hello.txt',
        headers: const {
          'range': 'bytes=0-5',
          'if-range': 'Wed, 21 Oct 2015 07:28:00 GMT',
        },
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      await _waitUntil(
        () =>
            (runtime.httpResponses[310]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[311]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[312]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[313]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[314]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[315]?.isNotEmpty ?? false),
      );

      final partial = runtime.httpResponses[310]!.single;
      expect(partial.status, HttpStatus.partialContent);
      expect(partial.headers[HttpHeaders.contentLengthHeader], '5');
      expect(partial.headers['content-range'], 'bytes 7-11/15');
      expect(partial.headers['accept-ranges'], 'bytes');
      expect(partial.body, isA<NativeHttpResponseBytes>());
      expect(
        utf8.decode((partial.body as NativeHttpResponseBytes).bytes),
        'route',
      );

      final partialHead = runtime.httpResponses[311]!.single;
      expect(partialHead.status, HttpStatus.partialContent);
      expect(partialHead.headers[HttpHeaders.contentLengthHeader], '2');
      expect(partialHead.headers['content-range'], 'bytes 13-14/15');
      expect(partialHead.body, isA<NativeHttpResponseBytes>());
      expect((partialHead.body as NativeHttpResponseBytes).bytes, isEmpty);

      final unsatisfiable = runtime.httpResponses[312]!.single;
      expect(unsatisfiable.status, HttpStatus.requestedRangeNotSatisfiable);
      expect(unsatisfiable.headers[HttpHeaders.contentLengthHeader], '0');
      expect(unsatisfiable.headers['content-range'], 'bytes */15');
      expect(unsatisfiable.body, isA<NativeHttpResponseBytes>());
      expect((unsatisfiable.body as NativeHttpResponseBytes).bytes, isEmpty);

      final dateIfRange = runtime.httpResponses[313]!.single;
      expect(dateIfRange.status, HttpStatus.partialContent);
      expect(dateIfRange.headers[HttpHeaders.contentLengthHeader], '6');
      expect(dateIfRange.headers['content-range'], 'bytes 0-5/15');
      expect(dateIfRange.body, isA<NativeHttpResponseBytes>());
      expect(
        utf8.decode((dateIfRange.body as NativeHttpResponseBytes).bytes),
        'static',
      );

      final weakEtagIfRange = runtime.httpResponses[314]!.single;
      expect(weakEtagIfRange.status, HttpStatus.ok);
      expect(
        weakEtagIfRange.headers[HttpHeaders.contentLengthHeader],
        utf8.encode(fileContents).length.toString(),
      );
      expect(weakEtagIfRange.headers.containsKey('content-range'), isFalse);
      expect(weakEtagIfRange.body, isA<NativeHttpResponseFile>());

      final staleDateIfRange = runtime.httpResponses[315]!.single;
      expect(staleDateIfRange.status, HttpStatus.ok);
      expect(
        staleDateIfRange.headers[HttpHeaders.contentLengthHeader],
        utf8.encode(fileContents).length.toString(),
      );
      expect(staleDateIfRange.headers.containsKey('content-range'), isFalse);
      expect(staleDateIfRange.body, isA<NativeHttpResponseFile>());

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 308,
        handle: 3080,
        method: 'GET',
        target: '/static/hello.txt',
        headers: {'if-none-match': etag},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 309,
        handle: 3090,
        method: 'HEAD',
        target: '/static/hello.txt',
        headers: {'if-modified-since': lastModified},
        body: null,
        realm: 'router.http',
        procedure: 'router.http.file',
      );
      await _waitUntil(
        () =>
            (runtime.httpResponses[308]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[309]?.isNotEmpty ?? false),
      );

      final etagNotModified = runtime.httpResponses[308]!.single;
      expect(etagNotModified.status, HttpStatus.notModified);
      expect(etagNotModified.headers[HttpHeaders.etagHeader], etag);
      expect(
        etagNotModified.headers.containsKey(HttpHeaders.contentLengthHeader),
        isFalse,
      );
      expect(etagNotModified.body, isA<NativeHttpResponseBytes>());
      expect((etagNotModified.body as NativeHttpResponseBytes).bytes, isEmpty);

      final dateNotModified = runtime.httpResponses[309]!.single;
      expect(dateNotModified.status, HttpStatus.notModified);
      expect(
        dateNotModified.headers[HttpHeaders.lastModifiedHeader],
        lastModified,
      );
      expect(dateNotModified.body, isA<NativeHttpResponseBytes>());
      expect((dateNotModified.body as NativeHttpResponseBytes).bytes, isEmpty);
      expect(
        events.map((event) => event['type']),
        contains('http_file_response_sent'),
      );
      expect(
        events.map((event) => event['type']),
        contains('http_file_not_modified'),
      );
      expect(
        events.map((event) => event['type']),
        contains('http_file_partial_response_sent'),
      );
      expect(
        events.map((event) => event['type']),
        contains('http_file_range_not_satisfiable'),
      );
      expect(
        events.map((event) => event['type']),
        isNot(contains('http_request_dispatched')),
      );
    },
  );

  test('forwards configured HTTP reverse proxy routes', () async {
    final upstreamRequests = <Map<String, Object?>>[];
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => upstream.close(force: true));
    final subscription = upstream.listen((request) async {
      final body = utf8.decode(await request.expand((chunk) => chunk).toList());
      upstreamRequests.add({
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.query,
        'xTest': request.headers.value('x-test'),
        'xHop': request.headers.value('x-hop'),
        'xForwardedHost': request.headers.value('x-forwarded-host'),
        'xForwardedProto': request.headers.value('x-forwarded-proto'),
        'body': body,
      });
      request.response.statusCode = HttpStatus.created;
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('x-upstream', 'ok');
      request.response.write(
        json.encode({
          'ok': true,
          'method': request.method,
          'path': request.uri.path,
          'query': request.uri.query,
          'body': body,
        }),
      );
      await request.response.close();
    });
    addTearDown(subscription.cancel);

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
      settings: RouterSettings(
        realms: const [],
        listeners: [
          ListenerSettings(
            endpoint: '127.0.0.1:0',
            protocols: const [ListenerProtocol.http],
            http: HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: const HttpRouteMatch(prefix: '/proxy/'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.reverseProxy,
                    options: {
                      'target': 'http://127.0.0.1:${upstream.port}/upstream',
                      'strip_prefix': true,
                      'timeout_ms': 5000,
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: listenerId,
      connectionId: 314,
      handle: 3140,
      method: 'POST',
      target: '/proxy/service?debug=true',
      protocol: 'https',
      headers: const {
        'host': 'consumer.example',
        'content-type': 'application/json',
        'connection': 'x-hop',
        'x-hop': 'secret',
        'x-test': 'reverse-proxy',
      },
      body: const {'request': true},
      realm: 'router.http',
      procedure: 'router.http.reverse_proxy',
    );

    await _waitUntil(
      () =>
          runtime.httpResponses[314]?.isNotEmpty == true &&
          upstreamRequests.isNotEmpty,
      timeout: const Duration(seconds: 2),
    );

    final upstreamRequest = upstreamRequests.single;
    expect(upstreamRequest['method'], 'POST');
    expect(upstreamRequest['path'], '/upstream/service');
    expect(upstreamRequest['query'], 'debug=true');
    expect(upstreamRequest['xTest'], 'reverse-proxy');
    expect(upstreamRequest['xHop'], isNull);
    expect(upstreamRequest['xForwardedHost'], 'consumer.example');
    expect(upstreamRequest['xForwardedProto'], 'https');
    expect(json.decode(upstreamRequest['body']! as String), {'request': true});

    final response = runtime.httpResponses[314]!.single;
    final responseBody = _jsonResponseBody(response);
    expect(response.status, HttpStatus.created);
    expect(response.headers['x-upstream'], 'ok');
    expect(responseBody['ok'], isTrue);
    expect(responseBody['path'], '/upstream/service');
    expect(responseBody['query'], 'debug=true');
    expect(json.decode(responseBody['body']! as String), {'request': true});

    expect(
      events.map((event) => event['type']),
      contains('http_reverse_proxy_response_sent'),
    );
    expect(
      events.map((event) => event['type']),
      isNot(contains('http_request_dispatched')),
    );
  });

  test('forwards configured FastCGI adapter routes', () async {
    final fastCgiRequests = <_FakeFastCgiRequest>[];
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(upstream.close);
    final subscription = upstream.listen((socket) async {
      final fastCgiRequest = await _readFakeFastCgiRequest(socket);
      fastCgiRequests.add(fastCgiRequest);
      final responseBody = json.encode({
        'ok': true,
        'script': fastCgiRequest.params['SCRIPT_FILENAME'],
        'query': fastCgiRequest.params['QUERY_STRING'],
        'body': utf8.decode(fastCgiRequest.stdin),
      });
      _writeFakeFastCgiRecord(
        socket,
        _fakeFastCgiStdout,
        1,
        utf8.encode(
          'Status: 202 Accepted\r\n'
          'Content-Type: application/json\r\n'
          'X-FastCGI: ok\r\n'
          '\r\n'
          '$responseBody',
        ),
      );
      _writeFakeFastCgiRecord(socket, _fakeFastCgiStdout, 1, const []);
      _writeFakeFastCgiRecord(socket, _fakeFastCgiEndRequest, 1, Uint8List(8));
      await socket.flush();
      await socket.close();
    });
    addTearDown(subscription.cancel);

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
      settings: RouterSettings(
        realms: const [],
        listeners: [
          ListenerSettings(
            endpoint: '127.0.0.1:0',
            protocols: const [ListenerProtocol.http],
            http: HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: const HttpRouteMatch(prefix: '/php/'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.fastCgi,
                    options: {
                      'target': 'fastcgi://127.0.0.1:${upstream.port}',
                      'document_root': '/srv/app/public',
                      'strip_prefix': true,
                      'timeout_ms': 5000,
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: listenerId,
      connectionId: 315,
      handle: 3150,
      method: 'POST',
      target: '/php/index.php?debug=true',
      protocol: 'https',
      headers: const {
        'host': 'consumer.example',
        'content-type': 'application/json',
        'x-test': 'fastcgi',
      },
      body: const {'request': true},
      realm: 'router.http',
      procedure: 'router.http.fastcgi',
    );

    await _waitUntil(
      () =>
          runtime.httpResponses[315]?.isNotEmpty == true &&
          fastCgiRequests.isNotEmpty,
      timeout: const Duration(seconds: 2),
    );

    final fastCgiRequest = fastCgiRequests.single;
    expect(fastCgiRequest.params['REQUEST_METHOD'], 'POST');
    expect(fastCgiRequest.params['REQUEST_URI'], '/php/index.php?debug=true');
    expect(fastCgiRequest.params['SCRIPT_NAME'], '/index.php');
    expect(
      fastCgiRequest.params['SCRIPT_FILENAME'],
      '/srv/app/public/index.php',
    );
    expect(fastCgiRequest.params['QUERY_STRING'], 'debug=true');
    expect(fastCgiRequest.params['CONTENT_TYPE'], 'application/json');
    expect(fastCgiRequest.params['HTTP_X_TEST'], 'fastcgi');
    expect(fastCgiRequest.params['HTTPS'], 'on');
    expect(json.decode(utf8.decode(fastCgiRequest.stdin)), {'request': true});

    final response = runtime.httpResponses[315]!.single;
    final responseBody = _jsonResponseBody(response);
    expect(
      response.status,
      HttpStatus.accepted,
      reason: '$responseBody $events',
    );
    expect(response.headers['Content-Type'], 'application/json');
    expect(response.headers['X-FastCGI'], 'ok');
    expect(responseBody['ok'], isTrue);
    expect(responseBody['script'], '/srv/app/public/index.php');
    expect(responseBody['query'], 'debug=true');
    expect(json.decode(responseBody['body']! as String), {'request': true});

    expect(
      events.map((event) => event['type']),
      contains('http_fastcgi_response_sent'),
    );
    expect(
      events.map((event) => event['type']),
      isNot(contains('http_request_dispatched')),
    );
  });

  test('routes HTTP session proxy actions through internal sessions', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettings(
      realms: [
        RealmSettings(
          name: 'realm1',
          auth: const RealmAuthSettings(methods: ['anonymous']),
          roles: [
            RoleSettings(
              name: 'anonymous',
              permissions: [
                PermissionSettings(
                  uri: '',
                  matchPolicy: PermissionMatchPolicy.prefix,
                  allow: const ['call', 'register', 'unregister'],
                  deny: const [],
                  disclose: const DiscloseSettings(),
                ),
              ],
            ),
          ],
          limits: const RealmLimitSettings(),
        ),
      ],
      listeners: const [
        ListenerSettings(
          endpoint: '127.0.0.1:0',
          protocols: [ListenerProtocol.rawsocket, ListenerProtocol.http],
          http: HttpListenerSettings(
            routes: [
              HttpRouteSettings(
                match: HttpRouteMatch(path: '/proxy/task'),
                action: HttpRouteAction(
                  type: HttpRouteActionType.sessionProxy,
                  procedure: 'com.example.proxy.task',
                ),
              ),
            ],
          ),
        ),
      ],
      authenticators: const {
        'anonymous': AuthenticatorDefinition(type: 'anonymous'),
      },
    );
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
    const connectionId = 44;

    final internalSession = await binding.createInternalSession(
      realmUri: 'realm1',
    );
    addTearDown(internalSession.close);
    final registered = await internalSession.register('com.example.proxy.task');
    registered.onInvoke((invocation) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      expect(context, isNotNull);
      expect(context!.request.path, '/proxy/task');
      context.sendJson(body: const {'proxied': true}, status: 202);
    });

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 3,
        method: 'POST',
        target: '/proxy/task',
        path: '/proxy/task',
        protocol: 'http/1.1',
        headers: const {'x-proxy': 'session'},
        body: Uint8List.fromList(utf8.encode('{"task":true}')),
      ),
    );

    await _waitUntil(
      () => events.any((event) => event['type'] == 'http_request_dispatched'),
      timeout: const Duration(seconds: 2),
    );
    final dispatchEvent = events.firstWhere(
      (event) => event['type'] == 'http_request_dispatched',
    );
    expect(dispatchEvent['realm'], 'realm1');
    expect(dispatchEvent['procedure'], 'com.example.proxy.task');
    expect(dispatchEvent['listenerId'], listenerId);
    expect(dispatchEvent['connectionId'], connectionId);

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty == true,
      timeout: const Duration(seconds: 2),
    );
    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, 202);
    expect(response.body, isA<NativeHttpResponseJson>());
    expect((response.body as NativeHttpResponseJson).value, {'proxied': true});
  });

  test('routes HTTP publish actions through internal sessions', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettings(
      realms: [
        RealmSettings(
          name: 'realm1',
          auth: const RealmAuthSettings(methods: ['anonymous']),
          roles: [
            RoleSettings(
              name: 'anonymous',
              permissions: [
                PermissionSettings(
                  uri: '',
                  matchPolicy: PermissionMatchPolicy.prefix,
                  allow: const ['publish', 'subscribe'],
                  deny: const [],
                  disclose: const DiscloseSettings(),
                ),
              ],
            ),
          ],
          limits: const RealmLimitSettings(),
        ),
      ],
      listeners: const [
        ListenerSettings(
          endpoint: '127.0.0.1:0',
          protocols: [ListenerProtocol.rawsocket, ListenerProtocol.http],
          http: HttpListenerSettings(
            routes: [
              HttpRouteSettings(
                match: HttpRouteMatch(path: '/events/task'),
                action: HttpRouteAction(
                  type: HttpRouteActionType.publish,
                  topic: 'com.example.http.events',
                ),
              ),
            ],
          ),
        ),
      ],
      authenticators: const {
        'anonymous': AuthenticatorDefinition(type: 'anonymous'),
      },
    );
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
    const connectionId = 45;

    final subscriber = await binding.createInternalSession(realmUri: 'realm1');
    addTearDown(subscriber.close);
    final publishedEvents = <Map<String, Object?>>[];
    final subscription = await subscriber.subscribe('com.example.http.events');
    subscription.onEvent((event) {
      publishedEvents.add(
        Map<String, Object?>.from(event.argumentsKeywords ?? const {}),
      );
    });

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 4,
        method: 'POST',
        target: '/events/task',
        path: '/events/task',
        protocol: 'http/1.1',
        headers: const {'x-event': 'task'},
        body: Uint8List.fromList(utf8.encode('{"task":true}')),
      ),
    );

    await _waitUntil(
      () => events.any((event) => event['type'] == 'http_request_published'),
      timeout: const Duration(seconds: 2),
    );
    final publishEvent = events.firstWhere(
      (event) => event['type'] == 'http_request_published',
    );
    expect(publishEvent['realm'], 'realm1');
    expect(publishEvent['topic'], 'com.example.http.events');
    expect(publishEvent['listenerId'], listenerId);
    expect(publishEvent['connectionId'], connectionId);
    expect(publishEvent['publicationId'], isA<int>());

    await _waitUntil(
      () => publishedEvents.isNotEmpty,
      timeout: const Duration(seconds: 2),
    );
    final published = publishedEvents.single;
    final http = published['_http'] as Map;
    expect(http['method'], 'POST');
    expect(http['path'], '/events/task');
    expect(http['procedure'], 'com.example.http.events');
    final connection = published['_connection'] as Map;
    expect(connection['listenerId'], listenerId);
    expect(connection['connectionId'], connectionId);

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty == true,
      timeout: const Duration(seconds: 2),
    );
    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, HttpStatus.accepted);
    expect(response.body, isA<NativeHttpResponseJson>());
    final body = (response.body as NativeHttpResponseJson).value as Map;
    expect(body['status'], 'published');
    expect(body['topic'], 'com.example.http.events');
    expect(body['publicationId'], isA<int>());
  });

  test('creates internal sessions from session profile defaults', () async {
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
      settings: _buildRouterSettingsWithSessionProfiles(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);

    final session = await binding.createInternalSession(
      realmUri: 'ignored.realm',
      sessionProfile: 'http-handler',
    );
    addTearDown(session.close);

    expect(session.realmUri, 'realm1');
    expect(session.authId, 'http-handler');
    expect(session.authRole, 'internal');
    expect(session.roles, contains('callee'));
  });

  test('uses HTTP route session profile realm for dispatch', () async {
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
      settings: _buildRouterSettingsWithSessionProfiles(),
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
    addTearDown(internalSession.close);
    final registered = await internalSession.register('com.example.api.health');
    registered.onInvoke((invocation) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      expect(context, isNotNull);
      expect(context!.request.path, '/api/health');
      context.sendText(body: 'OK', status: 200);
    });

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 2,
        method: 'GET',
        target: '/api/health',
        path: '/api/health',
        protocol: 'http/1.1',
        headers: const {'x-test': 'true'},
        body: Uint8List(0),
        realm: 'wrong.realm',
        procedure: 'com.example.api.health',
      ),
    );

    await _waitUntil(
      () => events.any((event) => event['type'] == 'http_request_dispatched'),
      timeout: const Duration(seconds: 2),
    );
    final dispatchEvent = events.firstWhere(
      (event) => event['type'] == 'http_request_dispatched',
    );
    expect(dispatchEvent['realm'], 'realm1');
    expect(dispatchEvent['procedure'], 'com.example.api.health');

    await _waitUntil(
      () => events.any((event) => event['type'] == 'http_response_ready'),
      timeout: const Duration(seconds: 2),
    );
    final response = runtime.httpResponses[connectionId];
    expect(response, isNotNull);
    expect(response!.single.status, 200);
  });

  test('requires bearer token for protected HTTP routes', () async {
    final runtime = _HandleRuntime();
    final events = <Map<String, Object?>>[];
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
      settings: _buildRouterSettingsWithHttpAuthBridge(),
    );

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
    const connectionId = 52;

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 12,
        method: 'GET',
        target: '/api/secure',
        path: '/api/secure',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.secure',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
    );
    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, HttpStatus.unauthorized);
    final jsonBody = _jsonResponseBody(response);
    expect(jsonBody['reason'], 'unauthorized');
    expect(jsonBody['message'], contains('Bearer token required'));
    expect(
      events.any((event) => event['type'] == 'http_request_dispatched'),
      isFalse,
    );
  });

  test(
    'rejects protected HTTP routes on insecure listeners before dispatch',
    () async {
      final runtime = _HandleRuntime();
      final events = <Map<String, Object?>>[];
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
        settings: _buildRouterSettingsWithHttpAuthBridge(),
      );

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
      const connectionId = 153;

      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 112,
          method: 'GET',
          target: '/api/secure',
          path: '/api/secure',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.secure',
        ),
      );

      await _waitUntil(
        () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      );
      final response = runtime.httpResponses[connectionId]!.single;
      expect(response.status, HttpStatus.forbidden);
      final jsonBody = _jsonResponseBody(response);
      expect(jsonBody['reason'], 'tls_required');
      expect(jsonBody['message'], contains('TLS is required'));
      expect(
        events.any((event) => event['type'] == 'http_request_dispatched'),
        isFalse,
      );
    },
  );

  test('rejects mTLS-gated HTTP routes before dispatch', () async {
    final runtime = _HandleRuntime();
    final events = <Map<String, Object?>>[];
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
      settings: _buildRouterSettingsWithHttpMtlsRoute(),
    );

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
    const connectionId = 154;

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 113,
        method: 'GET',
        target: '/api/mtls',
        path: '/api/mtls',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.mtls',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
    );
    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, HttpStatus.forbidden);
    final jsonBody = _jsonResponseBody(response);
    expect(jsonBody['reason'], 'mutual_tls_required');
    expect(jsonBody['message'], contains('Mutual TLS is required'));
    expect(
      events.any((event) => event['type'] == 'http_request_dispatched'),
      isFalse,
    );
  });

  test(
    'honors typed HTTP route protocol restrictions before dispatch',
    () async {
      final runtime = _HandleRuntime();
      final events = <Map<String, Object?>>[];
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
        settings: _buildRouterSettingsWithHttpProtocolRoute(),
      );

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
      const connectionId = 155;

      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 114,
          method: 'GET',
          target: '/api/h2-only',
          path: '/api/h2-only',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.h2',
        ),
      );

      await _waitUntil(
        () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      );
      final response = runtime.httpResponses[connectionId]!.single;
      expect(response.status, HttpStatus.upgradeRequired);
      expect(response.headers['x-connectanum-allowed-protocols'], 'http/2');
      expect(response.headers[HttpHeaders.upgradeHeader], 'h2');
      final jsonBody = _jsonResponseBody(response);
      expect(jsonBody['reason'], 'upgrade_required');
      expect(jsonBody['allowedProtocols'], const ['http/2']);
      expect(
        events.any((event) => event['type'] == 'http_request_dispatched'),
        isFalse,
      );
    },
  );

  test('honors typed HTTP route method restrictions before dispatch', () async {
    final runtime = _HandleRuntime();
    final events = <Map<String, Object?>>[];
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
      settings: _buildRouterSettingsWithHttpMethodRoute(),
    );

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
    const connectionId = 156;

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 115,
        method: 'POST',
        target: '/api/get-only',
        path: '/api/get-only',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.get',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
    );
    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, HttpStatus.methodNotAllowed);
    expect(response.headers[HttpHeaders.allowHeader], 'GET');
    final jsonBody = _jsonResponseBody(response);
    expect(jsonBody['reason'], 'method_not_allowed');
    expect(
      events.any((event) => event['type'] == 'http_request_dispatched'),
      isFalse,
    );
  });

  test(
    'honors method-specific HTTP route actions in runtime matching',
    () async {
      final runtime = _HandleRuntime();
      final events = <Map<String, Object?>>[];
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
        settings: _buildRouterSettingsWithHttpMethodActionRoute(),
      );

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
      const connectionId = 157;

      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 116,
          method: 'POST',
          target: '/api/items',
          path: '/api/items',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.items.create',
        ),
      );

      await _waitUntil(
        () => events.any((event) => event['type'] == 'http_request_dispatched'),
      );
      final dispatchEvent = events.firstWhere(
        (event) => event['type'] == 'http_request_dispatched',
      );
      expect(dispatchEvent['realm'], 'realm1');
      expect(dispatchEvent['procedure'], 'com.example.items.create');
      expect(
        runtime.httpResponses[connectionId]?.any(
              (response) => response.status == HttpStatus.methodNotAllowed,
            ) ??
            false,
        isFalse,
      );
    },
  );

  test('rate-limits HTTP routes before dispatch', () async {
    final runtime = _HandleRuntime();
    final events = <Map<String, Object?>>[];
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
      settings: _buildRouterSettingsWithHttpRateLimitRoute(),
    );

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

    runtime.setConnectionProtocol(158, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      158,
      NativeHttpHandshake.synthetic(
        handle: 117,
        method: 'GET',
        target: '/api/limited',
        path: '/api/limited',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.limited',
      ),
    );

    await _waitUntil(
      () => events.any((event) => event['type'] == 'http_request_dispatched'),
    );

    runtime.setConnectionProtocol(159, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      159,
      NativeHttpHandshake.synthetic(
        handle: 118,
        method: 'GET',
        target: '/api/limited',
        path: '/api/limited',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.limited',
      ),
    );

    await _waitUntil(() => runtime.httpResponses[159]?.isNotEmpty ?? false);
    final response = runtime.httpResponses[159]!.single;
    expect(response.status, HttpStatus.tooManyRequests);
    expect(response.headers[HttpHeaders.retryAfterHeader], isNotNull);
    expect(response.headers['x-ratelimit-limit'], '1');
    expect(response.headers['x-ratelimit-remaining'], '0');
    final jsonBody = _jsonResponseBody(response);
    expect(jsonBody['reason'], 'rate_limited');
    expect(
      events.where((event) => event['type'] == 'http_request_dispatched'),
      hasLength(1),
    );
    expect(
      events.any((event) => event['type'] == 'http_route_rate_limited'),
      isTrue,
    );
  });

  test(
    'throttles concurrent HTTP routes and releases completed slots',
    () async {
      final runtime = _HandleRuntime();
      final events = <Map<String, Object?>>[];
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
        settings: _buildRouterSettingsWithHttpConcurrencyLimitRoute(),
      );

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

      final releaseFirst = Completer<void>();
      var invocationCount = 0;
      final internalSession = await binding.createInternalSession(
        realmUri: 'realm1',
      );
      final registered = await internalSession.register(
        'com.example.api.throttled',
      );
      registered.onInvoke((invocation) async {
        invocationCount += 1;
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull);
        await releaseFirst.future;
        context!.sendText(body: 'OK');
      });

      runtime.setConnectionProtocol(160, NativeConnectionProtocol.http);
      runtime.enqueueHttpHandshake(
        listenerId,
        160,
        NativeHttpHandshake.synthetic(
          handle: 120,
          method: 'GET',
          target: '/api/throttled',
          path: '/api/throttled',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.throttled',
        ),
      );

      await _waitUntil(
        () => events.any((event) => event['type'] == 'http_request_dispatched'),
      );
      await _waitUntil(() => invocationCount == 1);

      runtime.setConnectionProtocol(161, NativeConnectionProtocol.http);
      runtime.enqueueHttpHandshake(
        listenerId,
        161,
        NativeHttpHandshake.synthetic(
          handle: 121,
          method: 'GET',
          target: '/api/throttled',
          path: '/api/throttled',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.throttled',
        ),
      );

      await _waitUntil(() => runtime.httpResponses[161]?.isNotEmpty ?? false);
      final throttled = runtime.httpResponses[161]!.single;
      expect(throttled.status, HttpStatus.tooManyRequests);
      expect(throttled.headers['x-concurrency-limit'], '1');
      expect(throttled.headers['x-concurrency-current'], '1');
      expect(_jsonResponseBody(throttled)['reason'], 'concurrency_limited');
      expect(invocationCount, 1);
      expect(
        events.where((event) => event['type'] == 'http_request_dispatched'),
        hasLength(1),
      );
      expect(
        events.any(
          (event) => event['type'] == 'http_route_concurrency_limited',
        ),
        isTrue,
      );

      releaseFirst.complete();
      await _waitUntil(() => runtime.httpResponses[160]?.isNotEmpty ?? false);
      expect(runtime.httpResponses[160]!.single.status, HttpStatus.ok);

      runtime.setConnectionProtocol(162, NativeConnectionProtocol.http);
      runtime.enqueueHttpHandshake(
        listenerId,
        162,
        NativeHttpHandshake.synthetic(
          handle: 122,
          method: 'GET',
          target: '/api/throttled',
          path: '/api/throttled',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.throttled',
        ),
      );

      await _waitUntil(() => runtime.httpResponses[162]?.isNotEmpty ?? false);
      expect(runtime.httpResponses[162]!.single.status, HttpStatus.ok);
      expect(invocationCount, 2);
    },
  );

  test('logs HTTP route access start and completion events', () async {
    final runtime = _HandleRuntime();
    final events = <Map<String, Object?>>[];
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
      settings: _buildRouterSettingsWithHttpAccessLogRoute(),
    );

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

    final internalSession = await binding.createInternalSession(
      realmUri: 'realm1',
    );
    final registered = await internalSession.register('com.example.api.logged');
    registered.onInvoke((invocation) async {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      expect(context, isNotNull);
      context!.sendJson(body: const {'ok': true}, status: HttpStatus.created);
    });

    runtime.setConnectionProtocol(163, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      163,
      NativeHttpHandshake.synthetic(
        handle: 123,
        method: 'GET',
        target: '/api/logged?trace=1',
        path: '/api/logged',
        protocol: 'http/1.1',
        headers: const {
          HttpHeaders.cookieHeader: 'session=secret-token',
          'x-request-id': 'req-1',
        },
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.logged',
        query: 'trace=1',
      ),
    );

    await _waitUntil(() => runtime.httpResponses[163]?.isNotEmpty ?? false);
    expect(runtime.httpResponses[163]!.single.status, HttpStatus.created);

    final started = events.firstWhere(
      (event) => event['type'] == 'http_route_access_started',
    );
    expect(started['method'], 'GET');
    expect(started['path'], '/api/logged');
    expect(started['query'], 'trace=1');
    expect(started['action'], 'rpc');
    expect(started['procedure'], 'com.example.api.logged');
    final headers = (started['headers'] as Map).cast<String, String>();
    expect(headers[HttpHeaders.cookieHeader], '<redacted>');
    expect(headers['x-request-id'], 'req-1');

    final completed = events.firstWhere(
      (event) => event['type'] == 'http_route_access_completed',
    );
    expect(completed['status'], HttpStatus.created);
    expect(completed['outcome'], 'completed');
    expect(completed['durationMs'], isA<int>());
    expect(completed['procedure'], 'com.example.api.logged');
  });

  test('uses catch-all HTTP routes only after more specific matches', () async {
    final runtime = _HandleRuntime();
    final events = <Map<String, Object?>>[];
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
      settings: _buildRouterSettingsWithHttpCatchAllRoute(),
    );

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

    runtime.setConnectionProtocol(211, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      211,
      NativeHttpHandshake.synthetic(
        handle: 2110,
        method: 'GET',
        target: '/auth',
        path: '/auth',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.http.fallback',
      ),
    );

    runtime.setConnectionProtocol(212, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      212,
      NativeHttpHandshake.synthetic(
        handle: 2120,
        method: 'GET',
        target: '/unknown/path',
        path: '/unknown/path',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.http.fallback',
      ),
    );

    await _waitUntil(
      () =>
          (runtime.httpResponses[211]?.any(
                (response) => response.status == HttpStatus.methodNotAllowed,
              ) ??
              false) &&
          events.any(
            (event) =>
                event['type'] == 'http_request_dispatched' &&
                event['connectionId'] == 212,
          ),
    );
    expect(
      events.any(
        (event) =>
            event['type'] == 'http_request_dispatched' &&
            event['connectionId'] == 211,
      ),
      isFalse,
    );
    final fallbackDispatch = events.firstWhere(
      (event) =>
          event['type'] == 'http_request_dispatched' &&
          event['connectionId'] == 212,
    );
    expect(fallbackDispatch['procedure'], 'com.example.http.fallback');
  });

  test(
    'derives deterministic HTTP shorthand targets in Dart runtime',
    () async {
      final runtime = _HandleRuntime();
      final events = <Map<String, Object?>>[];
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
        settings: _buildRouterSettingsWithHttpShorthandRoutes(),
      );

      final binding = router.start(
        runtime,
        onEvent: (event) {
          if (event is Map<String, Object?>) {
            events.add(event);
          }
        },
      );
      addTearDown(binding.dispose);

      final reservedSession = await binding.createInternalSession(
        realmUri: 'router.http',
      );
      final reservedRegistration = await reservedSession.register('index.get');
      reservedRegistration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull);
        expect(context!.request.realm, 'router.http');
        expect(context.request.procedure, 'index.get');
        context.sendJson(body: {'ok': true, 'route': 'reserved'});
      });

      final namespaceSession = await binding.createInternalSession(
        realmUri: 'realm1',
      );
      final namespaceRegistration = await namespaceSession.register(
        'consumer.api.tasks.42.post',
      );
      namespaceRegistration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull);
        expect(context!.request.realm, 'realm1');
        expect(context.request.procedure, 'consumer.api.tasks.42.post');
        context.sendJson(body: {'ok': true, 'route': 'namespace'});
      });

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;

      runtime.setConnectionProtocol(221, NativeConnectionProtocol.http);
      runtime.enqueueHttpHandshake(
        listenerId,
        221,
        NativeHttpHandshake.synthetic(
          handle: 2210,
          method: 'GET',
          target: '/',
          path: '/',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
        ),
      );

      runtime.setConnectionProtocol(222, NativeConnectionProtocol.http);
      runtime.enqueueHttpHandshake(
        listenerId,
        222,
        NativeHttpHandshake.synthetic(
          handle: 2220,
          method: 'POST',
          target: '/tasks/42',
          path: '/tasks/42',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
        ),
      );

      await _waitUntil(
        () =>
            events
                .where((event) => event['type'] == 'http_request_dispatched')
                .length >=
            2,
      );

      final dispatches = events
          .where((event) => event['type'] == 'http_request_dispatched')
          .toList();
      expect(
        dispatches,
        contains(
          allOf(
            containsPair('connectionId', 221),
            containsPair('realm', 'router.http'),
            containsPair('procedure', 'index.get'),
          ),
        ),
      );
      expect(
        dispatches,
        contains(
          allOf(
            containsPair('connectionId', 222),
            containsPair('realm', 'realm1'),
            containsPair('procedure', 'consumer.api.tasks.42.post'),
          ),
        ),
      );
      await _waitUntil(
        () =>
            (runtime.httpResponses[221]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[222]?.isNotEmpty ?? false),
      );
    },
  );

  test(
    'validates protected HTTP bearer routes through configured JWT provider',
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
        settings: _buildRouterSettingsWithHttpJwtProvider(),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;

      final callee = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'svc-http',
        authRole: 'internal',
        roles: const {'callee': <String, Object?>{}},
      );
      addTearDown(callee.close);
      final registration = await callee.register('com.example.api.jwt');
      registration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull);
        expect(context!.request.path, '/api/jwt');
        context.sendText(body: 'jwt-secured', status: HttpStatus.ok);
      });

      final jwt = _encodeHs256Jwt(
        secret: 'jwt-secret',
        claims: <String, Object?>{
          'sub': 'jwt-user',
          'role': 'member',
          'iss': 'https://issuer.example',
          'aud': <String>['connectanum-http'],
          'exp':
              DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch ~/
              1000,
        },
      );

      const connectionId = 63;
      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 23,
          method: 'GET',
          target: '/api/jwt',
          path: '/api/jwt',
          protocol: 'http/1.1',
          headers: {'authorization': 'Bearer $jwt'},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.jwt',
        ),
      );

      await _waitUntil(
        () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      );
      final response = runtime.httpResponses[connectionId]!.single;
      expect(response.status, HttpStatus.ok);
      expect(response.body, isA<NativeHttpResponseText>());
      expect((response.body as NativeHttpResponseText).text, 'jwt-secured');
    },
  );

  test(
    'auth bridge issues bearer token for ticket and dispatches secure route',
    () async {
      final runtime = _HandleRuntime();
      final events = <Map<String, Object?>>[];
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
        settings: _buildRouterSettingsWithHttpAuthBridge(),
      );

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

      final callee = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'svc-http',
        authRole: 'internal',
        roles: const {'callee': <String, Object?>{}},
      );
      addTearDown(callee.close);
      final registration = await callee.register('com.example.api.secure');
      registration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull);
        expect(context!.request.path, '/api/secure');
        context.sendText(body: 'secured', status: 200);
      });

      final tokens = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
      );

      const thirdConnectionId = 62;
      runtime.setConnectionProtocol(
        thirdConnectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        thirdConnectionId,
        NativeHttpHandshake.synthetic(
          handle: 22,
          method: 'GET',
          target: '/api/secure',
          path: '/api/secure',
          protocol: 'http/1.1',
          headers: {'authorization': 'Bearer ${tokens.accessToken}'},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.secure',
        ),
      );

      await _waitUntil(
        () => runtime.httpResponses[thirdConnectionId]?.isNotEmpty ?? false,
      );
      final protectedResponse =
          runtime.httpResponses[thirdConnectionId]!.single;
      expect(protectedResponse.status, HttpStatus.ok);
      final protectedBody = protectedResponse.body;
      expect(protectedBody, isA<NativeHttpResponseText>());
      expect((protectedBody as NativeHttpResponseText).text, 'secured');
      expect(tokens.refreshToken, isNotEmpty);
      expect(
        events.any(
          (event) =>
              event['type'] == 'http_request_dispatched' &&
              event['connectionId'] == thirdConnectionId,
        ),
        isTrue,
      );
    },
  );

  for (final authCase in const <({String method, String secret})>[
    (method: 'wampcra', secret: 'secret-1'),
    (method: 'scram', secret: 'pencil'),
  ]) {
    test(
      'auth bridge issues bearer token for ${authCase.method} and dispatches secure route',
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
          settings: _buildRouterSettingsWithHttpAuthBridge(),
        );

        final binding = router.start(runtime);
        addTearDown(binding.dispose);

        await Future<void>.delayed(Duration.zero);
        final listenerId = binding.listeners.single.listenerId;

        final callee = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'svc-http',
          authRole: 'internal',
          roles: const {'callee': <String, Object?>{}},
        );
        addTearDown(callee.close);
        final registration = await callee.register('com.example.api.secure');
        registration.onInvoke((invocation) {
          final context = HttpInvocationContext.maybeFromInvocation(invocation);
          expect(context, isNotNull);
          expect(context!.request.path, '/api/secure');
          context.sendText(body: authCase.method, status: HttpStatus.ok);
        });

        final tokens = await _issueHttpBridgeTokens(
          runtime: runtime,
          listenerId: listenerId,
          startConnectionId: 90,
          authMethod: authCase.method,
          authSecret: authCase.secret,
        );

        const protectedConnectionId = 92;
        runtime.setConnectionProtocol(
          protectedConnectionId,
          NativeConnectionProtocol.http,
        );
        runtime.enqueueHttpHandshake(
          listenerId,
          protectedConnectionId,
          NativeHttpHandshake.synthetic(
            handle: 52,
            method: 'GET',
            target: '/api/secure',
            path: '/api/secure',
            protocol: 'http/1.1',
            headers: {'authorization': 'Bearer ${tokens.accessToken}'},
            body: Uint8List(0),
            realm: 'realm1',
            procedure: 'com.example.api.secure',
          ),
        );

        await _waitUntil(
          () =>
              runtime.httpResponses[protectedConnectionId]?.isNotEmpty ?? false,
        );
        final protectedResponse =
            runtime.httpResponses[protectedConnectionId]!.single;
        expect(protectedResponse.status, HttpStatus.ok);
        expect(protectedResponse.body, isA<NativeHttpResponseText>());
        expect(
          (protectedResponse.body as NativeHttpResponseText).text,
          authCase.method,
        );
        expect(tokens.refreshToken, isNotEmpty);
      },
    );
  }

  test(
    'auth bridge rotates refresh tokens and rejects old credentials',
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
        settings: _buildRouterSettingsWithHttpAuthBridge(),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;

      final callee = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'svc-http',
        authRole: 'internal',
        roles: const {'callee': <String, Object?>{}},
      );
      addTearDown(callee.close);
      final registration = await callee.register('com.example.api.secure');
      registration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        context!.sendText(body: 'secured', status: 200);
      });

      final firstGrant = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
        startConnectionId: 70,
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 72,
        handle: 32,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': firstGrant.refreshToken,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );

      await _waitUntil(() => runtime.httpResponses[72]?.isNotEmpty ?? false);
      final refreshResponse = runtime.httpResponses[72]!.single;
      expect(refreshResponse.status, HttpStatus.ok);
      final refreshedBody = _jsonResponseBody(refreshResponse);
      expect(refreshedBody['status'], 'ok');
      final refreshedAccessToken = refreshedBody['access_token'] as String;
      final refreshedRefreshToken = refreshedBody['refresh_token'] as String;
      expect(refreshedAccessToken, isNot(firstGrant.accessToken));
      expect(refreshedRefreshToken, isNot(firstGrant.refreshToken));

      runtime.setConnectionProtocol(73, NativeConnectionProtocol.http);
      runtime.enqueueHttpHandshake(
        listenerId,
        73,
        NativeHttpHandshake.synthetic(
          handle: 33,
          method: 'GET',
          target: '/api/secure',
          path: '/api/secure',
          protocol: 'http/1.1',
          headers: {'authorization': 'Bearer ${firstGrant.accessToken}'},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.secure',
        ),
      );
      await _waitUntil(() => runtime.httpResponses[73]?.isNotEmpty ?? false);
      final revokedAccess = runtime.httpResponses[73]!.single;
      expect(revokedAccess.status, HttpStatus.unauthorized);
      expect(_jsonResponseBody(revokedAccess)['reason'], 'invalid_token');

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 74,
        handle: 34,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': firstGrant.refreshToken,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[74]?.isNotEmpty ?? false);
      final staleRefresh = runtime.httpResponses[74]!.single;
      expect(staleRefresh.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(staleRefresh)['reason'],
        'invalid_refresh_token',
      );

      runtime.setConnectionProtocol(75, NativeConnectionProtocol.http);
      runtime.enqueueHttpHandshake(
        listenerId,
        75,
        NativeHttpHandshake.synthetic(
          handle: 35,
          method: 'GET',
          target: '/api/secure',
          path: '/api/secure',
          protocol: 'http/1.1',
          headers: {'authorization': 'Bearer $refreshedAccessToken'},
          body: Uint8List(0),
          realm: 'realm1',
          procedure: 'com.example.api.secure',
        ),
      );
      await _waitUntil(() => runtime.httpResponses[75]?.isNotEmpty ?? false);
      final activeAccess = runtime.httpResponses[75]!.single;
      expect(activeAccess.status, HttpStatus.ok);
    },
  );

  test('auth bridge revokes refresh and access tokens', () async {
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
      settings: _buildRouterSettingsWithHttpAuthBridge(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;

    final callee = await binding.createInternalSession(
      realmUri: 'realm1',
      authId: 'svc-http',
      authRole: 'internal',
      roles: const {'callee': <String, Object?>{}},
    );
    addTearDown(callee.close);
    final registration = await callee.register('com.example.api.secure');
    registration.onInvoke((invocation) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation);
      context!.sendText(body: 'secured', status: 200);
    });

    final grant = await _issueTicketHttpTokens(
      runtime: runtime,
      listenerId: listenerId,
      startConnectionId: 80,
    );

    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: listenerId,
      connectionId: 82,
      handle: 42,
      method: 'POST',
      target: '/auth',
      headers: const {'content-type': 'application/json'},
      body: <String, Object?>{
        'grant_type': 'revoke',
        'token': grant.refreshToken,
        'token_type_hint': 'refresh_token',
      },
      realm: 'router.http',
      procedure: 'router.http.auth',
    );
    await _waitUntil(() => runtime.httpResponses[82]?.isNotEmpty ?? false);
    final revokeResponse = runtime.httpResponses[82]!.single;
    expect(revokeResponse.status, HttpStatus.ok);
    expect(_jsonResponseBody(revokeResponse)['status'], 'revoked');

    runtime.setConnectionProtocol(83, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      83,
      NativeHttpHandshake.synthetic(
        handle: 43,
        method: 'GET',
        target: '/api/secure',
        path: '/api/secure',
        protocol: 'http/1.1',
        headers: {'authorization': 'Bearer ${grant.accessToken}'},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.secure',
      ),
    );
    await _waitUntil(() => runtime.httpResponses[83]?.isNotEmpty ?? false);
    final revokedAccess = runtime.httpResponses[83]!.single;
    expect(revokedAccess.status, HttpStatus.unauthorized);
    expect(_jsonResponseBody(revokedAccess)['reason'], 'invalid_token');

    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: listenerId,
      connectionId: 84,
      handle: 44,
      method: 'POST',
      target: '/auth',
      headers: const {'content-type': 'application/json'},
      body: <String, Object?>{
        'grant_type': 'refresh_token',
        'refresh_token': grant.refreshToken,
      },
      realm: 'router.http',
      procedure: 'router.http.auth',
    );
    await _waitUntil(() => runtime.httpResponses[84]?.isNotEmpty ?? false);
    final revokedRefresh = runtime.httpResponses[84]!.single;
    expect(revokedRefresh.status, HttpStatus.unauthorized);
    expect(
      _jsonResponseBody(revokedRefresh)['reason'],
      anyOf('invalid_refresh_token', 'expired_refresh_token'),
    );
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

  test(
    'HTTP/2 stream response callbacks fire once in open-write-complete order',
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

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      const connectionId = 144;
      final callbackEvents = <String>[];
      Future<void>? doneFuture;

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
          status: 207,
          headers: const {'x-http2': 'true'},
          onStreamOpened: () => callbackEvents.add('open'),
          onFirstBodyWrite: () => callbackEvents.add('write'),
          onFirstBodyWriteCompleted: () => callbackEvents.add('write-complete'),
        );
        doneFuture = stream.done.then((_) => callbackEvents.add('done'));
        stream.add(utf8.encode('h2-a'));
        stream.close(utf8.encode('done'));
      });

      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http2,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 111,
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
        () => callbackEvents.length == 4,
        timeout: const Duration(seconds: 2),
      );

      await doneFuture;
      expect(callbackEvents, ['open', 'write', 'write-complete', 'done']);
    },
  );

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
    runtime.enqueueConnection(listenerId, connectionId);

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
        target: '/api/health',
        path: '/api/health',
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
    expect(httpEvent['path'], '/api/health');
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

  test(
    'http3 connections are drained fairly across tracked requests',
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
      const firstConnectionId = 301;
      const secondConnectionId = 302;

      runtime.setConnectionProtocol(
        firstConnectionId,
        NativeConnectionProtocol.http3,
      );
      runtime.setConnectionProtocol(
        secondConnectionId,
        NativeConnectionProtocol.http3,
      );
      runtime.enqueueConnection(listenerId, firstConnectionId);
      runtime.enqueueHttp3Handshake(
        firstConnectionId,
        NativeHttp3Handshake.synthetic(
          handle: 901,
          protocol: 'http/3',
          listenerProtocols: const ['rawsocket', 'http', 'http2', 'http3'],
        ),
      );
      runtime.enqueueConnection(listenerId, secondConnectionId);
      runtime.enqueueHttp3Handshake(
        secondConnectionId,
        NativeHttp3Handshake.synthetic(
          handle: 902,
          protocol: 'http/3',
          listenerProtocols: const ['rawsocket', 'http', 'http2', 'http3'],
        ),
      );

      await _waitUntil(
        () =>
            events
                .where(
                  (event) =>
                      event['type'] == 'listener_protocol_pending' &&
                      (event['connectionId'] == firstConnectionId ||
                          event['connectionId'] == secondConnectionId),
                )
                .length ==
            2,
        timeout: const Duration(seconds: 2),
      );

      runtime.enqueueHttp3Request(
        firstConnectionId,
        NativeHttpHandshake.synthetic(
          handle: 911,
          method: 'GET',
          target: '/a1',
          path: '/a1',
          protocol: 'http/3',
          headers: const {},
          body: Uint8List(0),
        ),
      );
      runtime.enqueueHttp3Request(
        firstConnectionId,
        NativeHttpHandshake.synthetic(
          handle: 912,
          method: 'GET',
          target: '/a2',
          path: '/a2',
          protocol: 'http/3',
          headers: const {},
          body: Uint8List(0),
        ),
      );
      runtime.enqueueHttp3Request(
        secondConnectionId,
        NativeHttpHandshake.synthetic(
          handle: 913,
          method: 'GET',
          target: '/b1',
          path: '/b1',
          protocol: 'http/3',
          headers: const {},
          body: Uint8List(0),
        ),
      );
      runtime.enqueueHttp3Request(
        secondConnectionId,
        NativeHttpHandshake.synthetic(
          handle: 914,
          method: 'GET',
          target: '/b2',
          path: '/b2',
          protocol: 'http/3',
          headers: const {},
          body: Uint8List(0),
        ),
      );

      await _waitUntil(
        () =>
            events
                .where((event) => event['type'] == 'listener_http_request')
                .length ==
            4,
        timeout: const Duration(seconds: 2),
      );

      final paths = events
          .where((event) => event['type'] == 'listener_http_request')
          .map((event) => event['path'])
          .toList(growable: false);
      expect(paths, equals(const ['/a1', '/b1', '/a2', '/b2']));
      expect(
        runtime.http3RequestPolls,
        equals(const [
          firstConnectionId,
          secondConnectionId,
          firstConnectionId,
          secondConnectionId,
        ]),
      );
    },
  );

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

  test(
    'http1 keep-alive connections are drained for additional requests',
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
      const connectionId = 100;

      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 801,
          method: 'POST',
          target: '/alpha',
          path: '/alpha',
          protocol: 'http/1.1',
          headers: const {'connection': 'keep-alive'},
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
          handle: 802,
          method: 'POST',
          target: '/beta',
          path: '/beta',
          protocol: 'http/1.1',
          headers: const {'connection': 'close'},
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
    },
  );

  test('applies realm permissions to internal session actions', () async {
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
      settings: _buildRestrictedInternalSessionSettings(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    final caller = await binding.createInternalSession(
      realmUri: 'realm1',
      authId: 'member-1',
      authRole: 'member',
    );
    final callee = await binding.createInternalSession(
      realmUri: 'realm1',
      authId: 'member-2',
      authRole: 'member',
    );
    addTearDown(caller.close);
    addTearDown(callee.close);

    final registration = await callee.register('com.example.proc');
    registration.onInvoke((invocation) {
      invocation.respondWith(arguments: const ['ok']);
    });

    final result = await caller.call('com.example.proc').first;
    expect(result.arguments, equals(const ['ok']));

    await expectLater(
      caller.publish(
        'com.example.topic',
        arguments: const ['blocked'],
        options: PublishOptions(acknowledge: true),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('publish'),
        ),
      ),
    );
  });

  test(
    'routes lazy call payloads across internal sessions without decoding',
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

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      final callee = await binding.createInternalSession(realmUri: 'realm1');
      final caller = await binding.createInternalSession(realmUri: 'realm1');
      addTearDown(callee.close);
      addTearDown(caller.close);

      final encodedArguments = Uint8List.fromList(
        msgpack_dart.serialize([
          'payload',
          [1, 2, 3],
        ]),
      );
      final encodedArgumentsKeywords = Uint8List.fromList(
        msgpack_dart.serialize({'flag': true, 'count': 2}),
      );
      final invocationPayloads = <Map<String, Uint8List?>>[];

      final registration = await callee.register('com.example.lazy.proc');
      registration.onLazyInvokePayload((invocation) {
        invocationPayloads.add({
          'arguments': invocation.argumentsBytes,
          'argumentsKeywords': invocation.argumentsKeywordsBytes,
        });
        expect(invocation.payload.encoding, LazyPayloadEncoding.messagePack);
        invocation.respondWith(arguments: const ['ok']);
      });

      final result = await caller
          .callLazyPayload(
            'com.example.lazy.proc',
            payload: LazyMessagePayload.encoded(
              encoding: LazyPayloadEncoding.messagePack,
              argumentsBytes: encodedArguments,
              argumentsKeywordsBytes: encodedArgumentsKeywords,
            ),
          )
          .first;

      expect(result.arguments, equals(const ['ok']));
      expect(invocationPayloads, hasLength(1));
      expect(
        invocationPayloads.single['arguments'],
        orderedEquals(encodedArguments),
      );
      expect(
        invocationPayloads.single['argumentsKeywords'],
        orderedEquals(encodedArgumentsKeywords),
      );
    },
  );

  test(
    'routes lazy publish payloads across internal sessions without decoding',
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

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      final subscriber = await binding.createInternalSession(
        realmUri: 'realm1',
      );
      final publisher = await binding.createInternalSession(realmUri: 'realm1');
      addTearDown(subscriber.close);
      addTearDown(publisher.close);

      final encodedArguments = Uint8List.fromList(
        msgpack_dart.serialize([
          'event',
          [4, 5, 6],
        ]),
      );
      final encodedArgumentsKeywords = Uint8List.fromList(
        msgpack_dart.serialize({'stream': 'alpha'}),
      );
      final eventPayloads = <Map<String, Uint8List?>>[];

      final subscription = await subscriber.subscribe('com.example.lazy.topic');
      subscription.onLazyEventPayload((event) {
        eventPayloads.add({
          'arguments': event.argumentsBytes,
          'argumentsKeywords': event.argumentsKeywordsBytes,
        });
        expect(event.payload.encoding, LazyPayloadEncoding.messagePack);
      });

      await publisher.publishLazyPayload(
        'com.example.lazy.topic',
        payload: LazyMessagePayload.encoded(
          encoding: LazyPayloadEncoding.messagePack,
          argumentsBytes: encodedArguments,
          argumentsKeywordsBytes: encodedArgumentsKeywords,
        ),
        options: PublishOptions(acknowledge: true),
      );

      await _waitUntil(
        () => eventPayloads.isNotEmpty,
        timeout: const Duration(seconds: 2),
      );
      expect(
        eventPayloads.single['arguments'],
        orderedEquals(encodedArguments),
      );
      expect(
        eventPayloads.single['argumentsKeywords'],
        orderedEquals(encodedArgumentsKeywords),
      );
    },
  );

  test(
    'preserves packed PPT lazy payloads across internal session publish',
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

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      final subscriber = await binding.createInternalSession(
        realmUri: 'realm1',
      );
      final publisher = await binding.createInternalSession(realmUri: 'realm1');
      addTearDown(subscriber.close);
      addTearDown(publisher.close);

      final packedBytes =
          PPTPayload.packPPTPayload(
                const ['ppt-event'],
                const {'worker': 7},
                PublishOptions(
                  acknowledge: true,
                  pptScheme: 'x_custom_scheme',
                  pptSerializer: 'msgpack',
                ),
              ).single
              as Uint8List;
      Uint8List? seenPackedBytes;
      List<dynamic>? seenArguments;
      Map<String, dynamic>? seenArgumentsKeywords;

      final subscription = await subscriber.subscribe('com.example.ppt.topic');
      subscription.onLazyEventPayload((event) {
        seenPackedBytes = event.packedPayloadBytes;
        seenArguments = event.arguments;
        seenArgumentsKeywords = event.argumentsKeywords;
      });

      await publisher.publishLazyPayload(
        'com.example.ppt.topic',
        payload: LazyMessagePayload.packed(
          encoding: LazyPayloadEncoding.messagePack,
          packedPayloadBytes: packedBytes,
          packedPayloadDecoder: (_) => (
            arguments: const ['ppt-event'],
            argumentsKeywords: const {'worker': 7},
          ),
        ),
        options: PublishOptions(
          acknowledge: true,
          pptScheme: 'x_custom_scheme',
          pptSerializer: 'msgpack',
        ),
      );

      await _waitUntil(
        () => seenPackedBytes != null,
        timeout: const Duration(seconds: 2),
      );
      expect(seenPackedBytes, orderedEquals(packedBytes));
      expect(seenArguments, equals(const ['ppt-event']));
      expect(seenArgumentsKeywords, equals(const {'worker': 7}));
    },
  );

  test(
    'preserves packed PPT lazy payloads across internal session calls',
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

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      final caller = await binding.createInternalSession(realmUri: 'realm1');
      final callee = await binding.createInternalSession(realmUri: 'realm1');
      addTearDown(caller.close);
      addTearDown(callee.close);

      final packedBytes =
          PPTPayload.packPPTPayload(
                const ['ppt-call'],
                const {'worker': 7},
                CallOptions(
                  pptScheme: 'x_custom_scheme',
                  pptSerializer: 'msgpack',
                ),
              ).single
              as Uint8List;
      Uint8List? seenPackedBytes;

      final registration = await callee.register('com.example.ppt.proc');
      registration.onLazyInvokePayload((invocation) {
        seenPackedBytes = invocation.packedPayloadBytes;
        invocation.respondWith(
          lazyPayload: invocation.payload,
          options: YieldOptions(
            pptScheme: invocation.pptScheme,
            pptSerializer: invocation.pptSerializer,
          ),
        );
      });

      final result = await caller
          .callLazyPayload(
            'com.example.ppt.proc',
            payload: LazyMessagePayload.packed(
              encoding: LazyPayloadEncoding.messagePack,
              packedPayloadBytes: packedBytes,
              packedPayloadDecoder: (_) => (
                arguments: const ['ppt-call'],
                argumentsKeywords: const {'worker': 7},
              ),
            ),
            options: CallOptions(
              pptScheme: 'x_custom_scheme',
              pptSerializer: 'msgpack',
            ),
          )
          .first;

      expect(seenPackedBytes, orderedEquals(packedBytes));
      expect(
        result.toLazyResultPayload().packedPayloadBytes,
        orderedEquals(packedBytes),
      );
      expect(result.arguments, equals(const ['ppt-call']));
      expect(result.argumentsKeywords, equals(const {'worker': 7}));
    },
  );

  test(
    'preserves packed wamp lazy payloads across internal session publish',
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

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      final subscriber = await binding.createInternalSession(
        realmUri: 'realm1',
      );
      final publisher = await binding.createInternalSession(realmUri: 'realm1');
      addTearDown(subscriber.close);
      addTearDown(publisher.close);

      final packedBytes = Uint8List.fromList(const [9, 8, 7, 6]);
      Uint8List? seenPackedBytes;
      String? seenPptCipher;
      String? seenPptKeyId;
      var decodeCount = 0;

      final subscription = await subscriber.subscribe('com.example.wamp.topic');
      subscription.onLazyEventPayload((event) {
        seenPackedBytes = event.packedPayloadBytes;
        seenPptCipher = event.pptCipher;
        seenPptKeyId = event.pptKeyId;
      });

      await publisher.publishLazyPayload(
        'com.example.wamp.topic',
        payload: LazyMessagePayload.packed(
          encoding: LazyPayloadEncoding.cbor,
          packedPayloadBytes: packedBytes,
          packedPayloadDecoder: (_) {
            decodeCount += 1;
            return (
              arguments: const ['should-not-decode'],
              argumentsKeywords: const <String, dynamic>{},
            );
          },
        ),
        options: PublishOptions(
          acknowledge: true,
          pptScheme: 'wamp',
          pptSerializer: 'cbor',
          pptCipher: 'xsalsa20poly1305',
          pptKeyId: 'test-key',
        ),
      );

      await _waitUntil(
        () => seenPackedBytes != null,
        timeout: const Duration(seconds: 2),
      );
      expect(seenPackedBytes, orderedEquals(packedBytes));
      expect(seenPptCipher, equals('xsalsa20poly1305'));
      expect(seenPptKeyId, equals('test-key'));
      expect(decodeCount, 0);
    },
  );

  test(
    'preserves packed wamp lazy payloads across internal session calls',
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

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      final caller = await binding.createInternalSession(realmUri: 'realm1');
      final callee = await binding.createInternalSession(realmUri: 'realm1');
      addTearDown(caller.close);
      addTearDown(callee.close);

      final packedBytes = Uint8List.fromList(const [4, 5, 6, 7]);
      Uint8List? seenPackedBytes;
      var decodeCount = 0;

      final registration = await callee.register('com.example.wamp.proc');
      registration.onLazyInvokePayload((invocation) {
        seenPackedBytes = invocation.packedPayloadBytes;
        invocation.respondWith(
          lazyPayload: invocation.payload,
          options: YieldOptions(
            pptScheme: invocation.pptScheme,
            pptSerializer: invocation.pptSerializer,
            pptCipher: invocation.pptCipher,
            pptKeyId: invocation.pptKeyId,
          ),
        );
      });

      final result = await caller
          .callLazyPayload(
            'com.example.wamp.proc',
            payload: LazyMessagePayload.packed(
              encoding: LazyPayloadEncoding.cbor,
              packedPayloadBytes: packedBytes,
              packedPayloadDecoder: (_) {
                decodeCount += 1;
                return (
                  arguments: const ['should-not-decode'],
                  argumentsKeywords: const <String, dynamic>{},
                );
              },
            ),
            options: CallOptions(
              pptScheme: 'wamp',
              pptSerializer: 'cbor',
              pptCipher: 'xsalsa20poly1305',
              pptKeyId: 'test-key',
            ),
          )
          .first;

      expect(seenPackedBytes, orderedEquals(packedBytes));
      expect(
        result.toLazyResultPayload().packedPayloadBytes,
        orderedEquals(packedBytes),
      );
      expect(result.details.pptCipher, equals('xsalsa20poly1305'));
      expect(result.details.pptKeyId, equals('test-key'));
      expect(decodeCount, 0);
    },
  );
}
