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
        Event,
        Extra,
        LazyMessagePayload,
        LazyPayloadEncoding,
        MessageTypes,
        PPTPayload,
        Publish,
        PublishOptions,
        RegisterOptions;
import 'package:connectanum_core/connectanum_core.dart' show YieldOptions;
import 'package:connectanum_core/connectanum_core.dart'
    as core
    show CancelOptions, Error, Invocation, Result;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/config/auth_registry.dart';
import 'package:connectanum_router/src/router/config/authenticator.dart';
import 'package:connectanum_router/src/router/auth/security.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/sni_certificate.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;
import 'package:test/test.dart';

part 'support/http_edge_cases.dart';
part 'support/http_initial_auth_cases.dart';
part 'support/http_auth_abort_cases.dart';
part 'support/http_auth_provider_failure_cases.dart';
part 'support/native_message_watch_cases.dart';
part 'support/http_early_cleanup_cases.dart';
part 'support/http_boss_ownership_cases.dart';
part 'support/internal_close_cases.dart';
part 'support/internal_call_lifecycle_cases.dart';
part 'support/http_adapter_option_cases.dart';

const _certificatePem =
    '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----';
const _privateKeyPem =
    '-----BEGIN PRIVATE KEY-----\nMIIB\n-----END PRIVATE KEY-----';

SniCertificate _cert(String host) => SniCertificate(
  hostname: host,
  certificateChainPem: _certificatePem,
  privateKeyPem: _privateKeyPem,
);

const int _testFastCgiVersion = 1;
const int _testFastCgiBeginRequest = 1;
const int _testFastCgiEndRequest = 3;
const int _testFastCgiParams = 4;
const int _testFastCgiStdIn = 5;
const int _testFastCgiStdOut = 6;
const int _testFastCgiRequestId = 1;

class _TestFastCgiRequest {
  const _TestFastCgiRequest({required this.params, required this.body});

  final Map<String, String> params;
  final Uint8List body;
}

class _TestFastCgiRecordReader {
  _TestFastCgiRecordReader(Stream<List<int>> stream)
    : _iterator = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _iterator;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  Future<Uint8List> readExactly(int length) async {
    if (length == 0) {
      return Uint8List(0);
    }
    final builder = BytesBuilder(copy: false);
    var remaining = length;
    while (remaining > 0) {
      if (_offset >= _buffer.length) {
        if (!await _iterator.moveNext()) {
          throw StateError('Unexpected FastCGI EOF');
        }
        _buffer = Uint8List.fromList(_iterator.current);
        _offset = 0;
      }
      final available = _buffer.length - _offset;
      final take = available < remaining ? available : remaining;
      builder.add(Uint8List.sublistView(_buffer, _offset, _offset + take));
      _offset += take;
      remaining -= take;
    }
    return builder.takeBytes();
  }
}

Future<_TestFastCgiRequest> _readTestFastCgiRequest(
  Socket socket, {
  _TestFastCgiRecordReader? recordReader,
}) async {
  final reader = recordReader ?? _TestFastCgiRecordReader(socket);
  final paramsBytes = BytesBuilder(copy: false);
  final bodyBytes = BytesBuilder(copy: false);
  var paramsComplete = false;
  while (true) {
    final header = await reader.readExactly(8);
    expect(header[0], _testFastCgiVersion);
    expect((header[2] << 8) | header[3], _testFastCgiRequestId);
    final type = header[1];
    final contentLength = (header[4] << 8) | header[5];
    final paddingLength = header[6];
    final content = await reader.readExactly(contentLength);
    if (paddingLength > 0) {
      await reader.readExactly(paddingLength);
    }
    if (type == _testFastCgiBeginRequest) {
      continue;
    }
    if (type == _testFastCgiParams) {
      if (content.isEmpty) {
        paramsComplete = true;
      } else {
        paramsBytes.add(content);
      }
      continue;
    }
    if (type == _testFastCgiStdIn) {
      expect(paramsComplete, isTrue);
      if (content.isEmpty) {
        return _TestFastCgiRequest(
          params: _decodeTestFastCgiParams(paramsBytes.takeBytes()),
          body: bodyBytes.takeBytes(),
        );
      }
      bodyBytes.add(content);
    }
  }
}

Map<String, String> _decodeTestFastCgiParams(Uint8List bytes) {
  final params = <String, String>{};
  var offset = 0;
  while (offset < bytes.length) {
    final nameLength = _readTestFastCgiLength(bytes, offset);
    offset = nameLength.$2;
    final valueLength = _readTestFastCgiLength(bytes, offset);
    offset = valueLength.$2;
    final name = utf8.decode(
      Uint8List.sublistView(bytes, offset, offset + nameLength.$1),
    );
    offset += nameLength.$1;
    final value = utf8.decode(
      Uint8List.sublistView(bytes, offset, offset + valueLength.$1),
    );
    offset += valueLength.$1;
    params[name] = value;
  }
  return params;
}

(int, int) _readTestFastCgiLength(Uint8List bytes, int offset) {
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

Uint8List _testFastCgiRecord(int type, Uint8List content) {
  final header = ByteData(8)
    ..setUint8(0, _testFastCgiVersion)
    ..setUint8(1, type)
    ..setUint16(2, _testFastCgiRequestId)
    ..setUint16(4, content.length)
    ..setUint8(6, 0)
    ..setUint8(7, 0);
  final builder = BytesBuilder(copy: false)
    ..add(Uint8List.view(header.buffer))
    ..add(content);
  return builder.takeBytes();
}

class _FakeRuntime implements NativeRuntime {
  final List<String> listenCalls = [];
  Uint8List? appliedConfig;
  final List<int> closedListeners = [];
  final List<int> closedConnections = [];
  final Map<int, int> _ports = {};
  final Map<int, int> _http3Ports = {};
  int _nextId = 1;
  final Map<int, Queue<int>> _pendingConnections = {};
  final Map<int, Queue<Object>> _pollConnectionActions = {};
  bool throwOnEmptyPoll = false;
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
    final actions = _pollConnectionActions[listenerId];
    if (actions != null && actions.isNotEmpty) {
      final action = actions.removeFirst();
      if (action is int) {
        return action;
      }
      throw action;
    }
    final queue = _pendingConnections[listenerId];
    if (queue == null || queue.isEmpty) {
      if (throwOnEmptyPoll) {
        throw StateError('controlled empty poll');
      }
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

  void setPollConnectionActions(int listenerId, Iterable<Object> actions) {
    _pollConnectionActions[listenerId] = Queue<Object>.from(actions);
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

class _TrackedHttpHandshake implements NativeHttpHandshake {
  _TrackedHttpHandshake(this.handle)
    : _delegate = NativeHttpHandshake.synthetic(
        handle: handle,
        method: 'GET',
        target: '/api/stream',
        path: '/api/stream',
        protocol: 'http/1.1',
        realm: 'realm1',
        procedure: 'com.example.api.stream',
      );

  final NativeHttpHandshake _delegate;
  int releases = 0;
  @override
  final int handle;
  @override
  String get method => _delegate.method;
  @override
  String get target => _delegate.target;
  @override
  String get path => _delegate.path;
  @override
  String get protocol => _delegate.protocol;
  @override
  int get version => _delegate.version;
  @override
  Map<String, String> get headers => _delegate.headers;
  @override
  Map<String, List<String>> get headerValues => _delegate.headerValues;
  @override
  Set<String> get duplicateHeaderNames => _delegate.duplicateHeaderNames;
  @override
  NativeHttpRequestBody get body => _delegate.body;
  @override
  String? get query => _delegate.query;
  @override
  String? get realm => _delegate.realm;
  @override
  String? get procedure => _delegate.procedure;
  @override
  void release() {
    releases++;
    _delegate.release();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HttpCleanupRuntime extends _HandleRuntime {
  _HttpCleanupRuntime({required this.direct});
  final bool direct;
  final List<int> finishAttempts = [];
  final Object finishError = StateError(
    'controlled HTTP stream finish failure',
  );

  @override
  NativeHttpResponseStream openHttpResponseStream({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) => _FakeHttpResponseStream(
    handle: handshakeHandle,
    onChunk: (chunk) {
      responseStreamChunks.putIfAbsent(handshakeHandle, () => []).add(chunk);
    },
    onClose: () {
      finishAttempts.add(handshakeHandle);
      throw finishError;
    },
  );

  @override
  NativeHttpResponseStreamDescriptor openHttpResponseStreamDescriptor({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    if (!direct) {
      return super.openHttpResponseStreamDescriptor(
        handshakeHandle: handshakeHandle,
        status: status,
        headers: headers,
      );
    }
    // An unallocated handle deterministically fails on finish without depending
    // on socket timing. No native streams are allocated by this fake runtime.
    return NativeHttpResponseStreamDescriptor(
      handle: 0x7fffffff,
      libraryPath: Platform.environment['CONNECTANUM_NATIVE_LIB'],
    );
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
    String? callerAuthId,
    String? callerAuthRole,
    String? procedure,
    bool? receiveProgress,
    bool? progress,
  }) {
    forwardedInvocations.add({
      'handle': handle,
      'connectionId': connectionId,
      'invocationId': invocationId,
      'registrationId': registrationId,
      'callerSessionId': callerSessionId,
      'callerAuthId': callerAuthId,
      'callerAuthRole': callerAuthRole,
      'procedure': procedure,
      'receiveProgress': receiveProgress,
      'progress': progress,
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
      throw TimeoutException('Condition not met within $timeout', timeout);
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

Future<({NativeHttpResponse response, List<Map<String, Object?>> events})>
_fastCgiResponseFixture(
  Future<void> Function(Socket socket) respond, {
  Map<String, Object?> options = const {},
}) async {
  final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <Socket>[];
  final served = Completer<void>();
  final subscription = upstream.listen((socket) async {
    sockets.add(socket);
    try {
      final reader = _TestFastCgiRecordReader(socket);
      await _readTestFastCgiRequest(socket, recordReader: reader);
      await respond(socket);
      expect(reader._offset, reader._buffer.length);
      expect(
        await reader._iterator.moveNext().timeout(const Duration(seconds: 2)),
        isFalse,
        reason: 'Router must close the upstream socket after every response',
      );
      served.complete();
    } catch (error, stack) {
      served.completeError(error, stack);
    }
  });
  // Observe failures immediately, while the router's reply is still pending.
  final upstreamResult = served.future.then<Object?>(
    (_) => null,
    onError: (Object error, StackTrace stack) => error,
  );
  addTearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await subscription.cancel();
    await upstream.close();
  });
  final runtime = _HandleRuntime();
  final settings = RouterSettingsBuilder()
    ..addListenerFromBuilder(
      ListenerSettingsBuilder('http', '127.0.0.1:0')
        ..addProtocol(ListenerProtocol.http)
        ..setHttpOptions(
          HttpListenerSettings(
            routes: [
              HttpRouteSettings(
                match: const HttpRouteMatch(prefix: '/php'),
                action: HttpRouteAction(
                  type: HttpRouteActionType.fastCgi,
                  delegate: 'tcp://${upstream.address.host}:${upstream.port}',
                  options: {
                    'document_root': '/srv/consumer/public',
                    'strip_prefix': true,
                    'timeout_ms': 1000,
                    ...options,
                  },
                ),
              ),
            ],
          ),
        ),
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
    settings: settings.build(),
  );
  final events = <Map<String, Object?>>[];
  final binding = router.start(
    runtime,
    onEvent: (event) {
      if (event is Map<String, Object?>) events.add(event);
    },
  );
  addTearDown(binding.dispose);
  await Future<void>.delayed(Duration.zero);
  const connectionId = 146;
  runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
  runtime.enqueueHttpHandshake(
    binding.listeners.single.listenerId,
    connectionId,
    NativeHttpHandshake.synthetic(
      handle: 146,
      method: 'GET',
      target: '/php/index.php',
      path: '/php/index.php',
      protocol: 'http/1.1',
      headers: const {'host': 'consumer.example'},
      body: Uint8List(0),
      realm: 'router.http',
      procedure: 'router.http.fastcgi',
    ),
  );
  await _waitUntil(
    () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
    timeout: const Duration(seconds: 5),
  );
  expect(await upstreamResult.timeout(const Duration(seconds: 2)), isNull);
  return (
    response: runtime.httpResponses[connectionId]!.single,
    events: events,
  );
}

class _ProxyResponseFixture {
  _ProxyResponseFixture(this.runtime, this.binding, this.events);

  final _HandleRuntime runtime;
  final RouterBinding binding;
  final List<Map<String, Object?>> events;
  int nextId = 1900;

  static Future<_ProxyResponseFixture> start(
    Map<String, Object?> options,
  ) async {
    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: const HttpRouteMatch(prefix: '/api'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.reverseProxy,
                    options: options,
                  ),
                ),
              ],
            ),
          ),
      );
    final events = <Map<String, Object?>>[];
    final binding =
        Router(
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
          settings: settings.build(),
        ).start(
          runtime,
          onEvent: (event) {
            if (event is Map<String, Object?>) events.add(event);
          },
        );
    addTearDown(binding.dispose);
    await Future<void>.delayed(Duration.zero);
    return _ProxyResponseFixture(runtime, binding, events);
  }

  Future<NativeHttpResponse> request() async {
    final id = nextId++;
    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: binding.listeners.single.listenerId,
      connectionId: id,
      handle: id,
      method: 'GET',
      target: '/api/resource',
      headers: const {},
      body: null,
      realm: 'router.http',
      procedure: 'router.http.reverse_proxy',
    );
    await _waitUntil(
      () => runtime.httpResponses[id]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 5),
    );
    return runtime.httpResponses[id]!.single;
  }
}

class _ConfiguredFileFixture {
  _ConfiguredFileFixture(this.directory, this.file, this.runtime, this.binding);

  final Directory directory;
  final File file;
  final _HandleRuntime runtime;
  final RouterBinding binding;
  int _nextId = 1700;

  Future<NativeHttpResponse> request({
    String method = 'GET',
    String path = '/assets/hello.txt',
    Map<String, String> headers = const {},
  }) async {
    final id = _nextId++;
    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: binding.listeners.single.listenerId,
      connectionId: id,
      handle: id,
      method: method,
      target: path,
      headers: headers,
      body: null,
      realm: 'router.http',
      procedure: 'router.http.file',
    );
    await _waitUntil(
      () => runtime.httpResponses[id]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    return runtime.httpResponses[id]!.single;
  }
}

Future<_ConfiguredFileFixture> _configuredFileFixture({
  HttpRouteAction? action,
  HttpRouteAction Function(String directory)? actionBuilder,
}) async {
  final directory = await Directory.systemTemp.createTemp('router-file-test-');
  addTearDown(() => directory.delete(recursive: true));
  final file = await File(
    '${directory.path}/hello.txt',
  ).writeAsString('0123456789abcdef');
  await file.setLastModified(DateTime.utc(2024, 3, 4, 5, 6, 7, 125));
  final runtime = _HandleRuntime();
  final settings = RouterSettingsBuilder()
    ..addListenerFromBuilder(
      ListenerSettingsBuilder('http', '127.0.0.1:0')
        ..addProtocol(ListenerProtocol.http)
        ..setHttpOptions(
          HttpListenerSettings(
            routes: [
              HttpRouteSettings(
                match: const HttpRouteMatch(prefix: '/assets'),
                action:
                    action ??
                    actionBuilder?.call(directory.path) ??
                    HttpRouteAction(
                      type: HttpRouteActionType.file,
                      directory: directory.path,
                      cacheControl: 'max-age=60',
                    ),
              ),
            ],
          ),
        ),
    );
  final binding = Router(
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
    settings: settings.build(),
  ).start(runtime);
  addTearDown(binding.dispose);
  await Future<void>.delayed(Duration.zero);
  return _ConfiguredFileFixture(directory, file, runtime, binding);
}

void _enqueueSyntheticHttpRequest({
  required _HandleRuntime runtime,
  required int listenerId,
  required int connectionId,
  required int handle,
  required String method,
  required String target,
  String? query,
  required Map<String, String> headers,
  required Object? body,
  List<int>? rawBody,
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
      query: query,
      protocol: 'http/1.1',
      headers: headers,
      body: rawBody != null
          ? Uint8List.fromList(rawBody)
          : body == null
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
  String? realm = 'realm1',
  String ticket = 'signed-token',
  String authPath = '/auth',
}) => _issueHttpBridgeTokens(
  runtime: runtime,
  listenerId: listenerId,
  startConnectionId: startConnectionId,
  authId: authId,
  realm: realm,
  authMethod: 'ticket',
  authSecret: ticket,
  authPath: authPath,
);

Future<({String accessToken, String refreshToken})> _issueHttpBridgeTokens({
  required _HandleRuntime runtime,
  required int listenerId,
  required String authMethod,
  required String authSecret,
  int startConnectionId = 60,
  String authId = 'user-1',
  String? realm = 'realm1',
  String authPath = '/auth',
}) async {
  final startBody = <String, Object?>{
    'realm': ?realm,
    'authmethod': authMethod,
    'authid': authId,
  };
  ScramAuthentication? scramAuthentication;
  if (authMethod == 'scram') {
    final scramRealm = realm;
    if (scramRealm == null) {
      throw ArgumentError('SCRAM HTTP auth test grants require a realm');
    }
    scramAuthentication = ScramAuthentication(authSecret);
    final helloDetails = Details.forHello()
      ..authmethods = [authMethod]
      ..authid = authId;
    await scramAuthentication.hello(scramRealm, helloDetails);
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
    target: authPath,
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
    target: authPath,
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

RouterSettings _buildRouterSettingsWithHttpAuthBridge({
  int maxPendingAuth = 32,
  int maxFailedAuth = 5,
  int maxFailedAuthRecords = 4096,
  int maxHttpAuthGrants = 4096,
  int lockoutMs = 900000,
  int authTimeoutMs = 10000,
  int tokenTtlMs = 60000,
  int refreshTokenTtlMs = 300000,
  bool rotateRefreshTokens = true,
  Map<String, Object?> secureRouteOptions = const {},
  bool enableProtectedPublish = false,
  List<String> profileAuthMethods = const ['ticket', 'wampcra', 'scram'],
}) {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm1')
        ..setLimits(
          RealmLimitSettings(
            maxPendingAuth: maxPendingAuth,
            maxFailedAuth: maxFailedAuth,
            maxFailedAuthRecords: maxFailedAuthRecords,
            maxHttpAuthGrants: maxHttpAuthGrants,
            lockoutMs: lockoutMs,
            authTimeoutMs: authTimeoutMs,
          ),
        )
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
              ..allowOperations([
                'call',
                if (enableProtectedPublish) 'publish',
              ]),
          ),
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('com.example.')
              ..setMatchPolicy(PermissionMatchPolicy.prefix)
              ..allowOperations([
                'call',
                'register',
                'unregister',
                if (enableProtectedPublish) 'subscribe',
              ]),
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
        ..setAuthMethods(profileAuthMethods),
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
            HttpListenerSettings(
              sessionProfile: 'public-http',
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/auth'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.auth,
                    sessionProfile: 'http-ticket',
                    options: <String, Object?>{
                      'token_ttl_ms': tokenTtlMs,
                      'refresh_token_ttl_ms': refreshTokenTtlMs,
                      'rotate_refresh_tokens': rotateRefreshTokens,
                    },
                  ),
                ),
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/api/secure'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    procedure: 'com.example.api.secure',
                    sessionProfile: 'http-ticket',
                    options: secureRouteOptions,
                  ),
                ),
                if (enableProtectedPublish)
                  HttpRouteSettings(
                    match: const HttpRouteMatch(path: '/api/events'),
                    action: HttpRouteAction(
                      type: HttpRouteActionType.publish,
                      realm: 'realm1',
                      topic: 'com.example.events',
                      sessionProfile: 'http-ticket',
                      options: secureRouteOptions,
                    ),
                  ),
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp/secure'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'realm1',
                    sessionProfile: 'http-ticket',
                    options: <String, Object?>{
                      'protected_resource_metadata': <String, Object?>{
                        'metadata_url': 'https://mcp.example.test/mcp/secure',
                        'resource': 'https://mcp.example.test/mcp/secure',
                        'authorization_servers': <String>[
                          'https://auth.example.test',
                        ],
                      },
                    },
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
            'locked-user': <String, Object?>{
              'ticket': 'locked-user-token',
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

RouterSettings _buildRouterSettingsWithHttpAuthProfileIsolation() {
  final base = _buildRouterSettingsWithHttpAuthBridge();
  final listener = base.listeners.single;
  final http = listener.http!;

  return base.copyWith(
    sessionProfiles: <SessionProfileSettings>[
      ...base.sessionProfiles,
      const SessionProfileSettings(
        name: 'http-ticket-alternate',
        realm: 'realm1',
        auth: SessionProfileAuthSettings(
          methods: <String>['ticket', 'wampcra', 'scram'],
        ),
      ),
    ],
    listeners: <ListenerSettings>[
      ListenerSettings(
        type: listener.type,
        endpoint: listener.endpoint,
        authmethods: listener.authmethods,
        sessionProfile: listener.sessionProfile,
        path: listener.path,
        tls: listener.tls,
        options: listener.options,
        protocols: listener.protocols,
        rawsocket: listener.rawsocket,
        websocket: listener.websocket,
        http: HttpListenerSettings(
          alpn: http.alpn,
          http3: http.http3,
          sessionProfile: http.sessionProfile,
          options: http.options,
          routes: <HttpRouteSettings>[
            ...http.routes,
            const HttpRouteSettings(
              match: HttpRouteMatch(path: '/auth/unusable'),
              action: HttpRouteAction(
                type: HttpRouteActionType.auth,
                sessionProfile: 'http-ticket-alternate',
              ),
              methodActions: <String, HttpRouteAction>{
                'GET': HttpRouteAction(
                  type: HttpRouteActionType.rpc,
                  realm: 'realm1',
                  procedure: 'com.example.http.health',
                ),
              },
            ),
            const HttpRouteSettings(
              match: HttpRouteMatch(path: '/auth/alternate'),
              action: HttpRouteAction(
                type: HttpRouteActionType.rpc,
                realm: 'realm1',
                procedure: 'com.example.http.health',
              ),
              methodActions: <String, HttpRouteAction>{
                'POST': HttpRouteAction(
                  type: HttpRouteActionType.auth,
                  sessionProfile: 'http-ticket-alternate',
                ),
              },
            ),
            const HttpRouteSettings(
              match: HttpRouteMatch(path: '/mcp/secure-alternate'),
              action: HttpRouteAction(
                type: HttpRouteActionType.mcp,
                realm: 'realm1',
                sessionProfile: 'http-ticket-alternate',
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

RouterSettings _buildRouterSettingsWithHttpAuthRouteIsolation() {
  final base = _buildRouterSettingsWithHttpAuthBridge();
  final listener = base.listeners.single;
  final http = listener.http!;

  return base.copyWith(
    listeners: <ListenerSettings>[
      ListenerSettings(
        type: listener.type,
        endpoint: listener.endpoint,
        authmethods: listener.authmethods,
        sessionProfile: listener.sessionProfile,
        path: listener.path,
        tls: listener.tls,
        options: listener.options,
        protocols: listener.protocols,
        rawsocket: listener.rawsocket,
        websocket: listener.websocket,
        http: HttpListenerSettings(
          alpn: http.alpn,
          http3: http.http3,
          sessionProfile: http.sessionProfile,
          options: http.options,
          routes: <HttpRouteSettings>[
            ...http.routes,
            const HttpRouteSettings(
              match: HttpRouteMatch(path: '/auth/alternate'),
              action: HttpRouteAction(
                type: HttpRouteActionType.auth,
                sessionProfile: 'http-ticket',
                options: <String, Object?>{
                  'token_ttl_ms': 120000,
                  'refresh_token_ttl_ms': 600000,
                  'rotate_refresh_tokens': false,
                },
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

RouterSettings _buildRouterSettingsWithHttpAuthRealmPolicyBinding() {
  final base = _buildRouterSettingsWithHttpAuthBridge();

  return base.copyWith(
    realms: <RealmSettings>[
      ...base.realms,
      (RealmSettingsBuilder('realm2')
            ..setLimits(const RealmLimitSettings(maxPendingAuth: 1))
            ..addAuthMethod(
              'ticket',
              options: const {'authenticator': 'ticket-basic'},
            )
            ..addRoleFromBuilder(RoleSettingsBuilder('member')))
          .build(),
    ],
  );
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

RouterSettings _buildRouterSettingsWithHttpOAuthMcpProvider(
  Uri introspectionEndpoint,
) {
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
        ..addRoleFromBuilder(RoleSettingsBuilder('blocked'))
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
      SessionProfileSettingsBuilder('http-oauth')
        ..setRealm('realm1')
        ..setAuthMethods(const ['oauth'])
        ..setHttpProvider('oauth-introspection'),
    )
    ..addHttpAuthProvider(
      'oauth-introspection',
      HttpAuthProviderDefinition(
        type: 'oauth',
        options: <String, Object?>{
          'introspection_url': introspectionEndpoint.toString(),
          'issuer': 'https://issuer.example',
          'audience': const <String>['mcp-resource'],
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
              routes: <HttpRouteSettings>[
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp/oauth'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'realm1',
                    sessionProfile: 'http-oauth',
                    options: <String, Object?>{
                      'post_response_transport': 'json',
                      'protected_resource_metadata': <String, Object?>{
                        'metadata_url': 'https://mcp.example.test/mcp/oauth',
                        'resource': 'https://mcp.example.test/mcp/oauth',
                        'authorization_servers': <String>[
                          'https://issuer.example',
                        ],
                      },
                    },
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

RouterSettings _buildRouterSettingsWithCollidingHttpOAuthMcpScopes(
  Uri introspectionEndpoint,
) {
  RealmSettingsBuilder realm(String name) => RealmSettingsBuilder(name)
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
    );

  HttpAuthProviderDefinition oauthProvider() => HttpAuthProviderDefinition(
    type: 'oauth',
    options: <String, Object?>{
      'introspection_url': introspectionEndpoint.toString(),
      'issuer': 'https://issuer.example',
      'audience': const <String>['mcp-resource'],
      'auth_id_claim': 'sub',
      'auth_role_claim': 'role',
    },
  );

  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(realm('realm'))
    ..addRealmFromBuilder(realm('tenant'))
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('tenant:shared')
        ..setRealm('realm')
        ..setAuthMethods(const ['oauth'])
        ..setHttpProvider('external'),
    )
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('shared')
        ..setRealm('tenant')
        ..setAuthMethods(const ['oauth'])
        ..setHttpProvider('external:realm'),
    )
    ..addHttpAuthProvider('external', oauthProvider())
    ..addHttpAuthProvider('external:realm', oauthProvider())
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
              routes: <HttpRouteSettings>[
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp/realm'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'realm',
                    sessionProfile: 'tenant:shared',
                    options: <String, Object?>{
                      'post_response_transport': 'json',
                      'protected_resource_metadata': <String, Object?>{
                        'metadata_url': 'https://mcp.example.test/mcp/realm',
                        'resource': 'https://mcp.example.test/mcp/realm',
                        'authorization_servers': <String>[
                          'https://issuer.example',
                        ],
                      },
                    },
                  ),
                ),
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp/tenant'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'tenant',
                    sessionProfile: 'shared',
                    options: <String, Object?>{
                      'post_response_transport': 'json',
                      'protected_resource_metadata': <String, Object?>{
                        'metadata_url': 'https://mcp.example.test/mcp/tenant',
                        'resource': 'https://mcp.example.test/mcp/tenant',
                        'authorization_servers': <String>[
                          'https://issuer.example',
                        ],
                      },
                    },
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

RouterSettings _buildRouterSettingsWithCollidingAnonymousMcpRouteScopes() {
  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('realm')..addAuthMethod('anonymous'),
    )
    ..addRealmFromBuilder(
      RealmSettingsBuilder('tenant')..addAuthMethod('anonymous'),
    )
    ..addSessionProfileFromBuilder(SessionProfileSettingsBuilder('public-http'))
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('tenant:shared')
        ..setRealm('realm')
        ..setAuthMethods(const ['anonymous']),
    )
    ..addSessionProfileFromBuilder(
      SessionProfileSettingsBuilder('shared')
        ..setRealm('tenant')
        ..setAuthMethods(const ['anonymous']),
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
              routes: <HttpRouteSettings>[
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp/scope'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'realm',
                    sessionProfile: 'tenant:shared',
                    options: <String, Object?>{
                      'post_response_transport': 'json',
                    },
                  ),
                ),
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp/scope:realm'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'tenant',
                    sessionProfile: 'shared',
                    options: <String, Object?>{
                      'post_response_transport': 'json',
                    },
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
                  match: HttpRouteMatch(path: '/api/items', methods: ['GET']),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    procedure: 'com.example.api.items',
                  ),
                  methodActions: {
                    'POST': HttpRouteAction(
                      type: HttpRouteActionType.rpc,
                      procedure: 'com.example.api.items.create',
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

class _RoundAuthenticator extends Authenticator {
  final contexts = <AuthenticatorContext>[];
  final messages = <AuthenticateMessage>[];
  final abortReasons = <String?>[];
  final abortContexts = <AuthenticatorContext>[];
  bool failAbort = false;
  AuthenticatorContext? helloContext;
  Future<AuthResult> Function()? hello;
  Future<AuthResult> Function()? authenticate;

  @override
  String get method => 'test-http-rounds';

  static AuthResult challenge(int round) => AuthResult.challenge(
    AuthChallenge(
      challenge: <String, Object?>{'round': round},
      extra: <String, Object?>{'nonce': 'round-$round'},
    ),
  );

  static AuthResult success() => AuthResult.success(
    const AuthSuccess(
      authId: 'user-1',
      authRole: 'member',
      details: {'authprovider': 'round-provider', 'verified_rounds': 3},
    ),
  );

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    helloContext = context;
    return hello == null ? challenge(1) : await hello!();
  }

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) async {
    contexts.add(context);
    messages.add(message);
    return authenticate == null ? success() : await authenticate!();
  }

  @override
  Future<void> onAbort(AuthenticatorContext context, {String? reason}) async {
    if (helloContext != null) expect(context, same(helloContext));
    abortContexts.add(context);
    abortReasons.add(reason);
    if (failAbort) throw StateError('Authenticator cleanup failed');
  }
}

class _RoundAuthenticatorFactory extends AuthenticatorFactory {
  _RoundAuthenticatorFactory(
    Iterable<_RoundAuthenticator> authenticators,
    this.beforeCreate,
  ) : remaining = Queue.of(authenticators);

  final Queue<_RoundAuthenticator> remaining;
  final Future<void> Function()? beforeCreate;

  @override
  String get method => 'test-http-rounds';

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    expect(remaining, isNotEmpty, reason: 'Unexpected authentication attempt');
    await beforeCreate?.call();
    return remaining.removeFirst();
  }
}

class _HttpRoundFixture {
  _HttpRoundFixture(this.runtime, this.binding, this.events);

  final _HandleRuntime runtime;
  final RouterBinding binding;
  final List<Map<String, Object?>> events;
  int nextConnection = 9000;

  static Future<_HttpRoundFixture> start(
    List<_RoundAuthenticator> authenticators, {
    RouterSettings? settings,
    Future<void> Function()? beforeCreate,
  }) async {
    final factory = _RoundAuthenticatorFactory(authenticators, beforeCreate);
    AuthenticatorRegistry.registerFactory(factory);
    addTearDown(() => AuthenticatorRegistry.unregisterFactory(factory.method));
    final base = settings ?? _buildRouterSettingsWithHttpAuthBridge();
    final runtime = _HandleRuntime();
    final events = <Map<String, Object?>>[];
    final binding =
        Router(
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
          settings: base.copyWith(
            authenticators: {
              ...base.authenticators,
              'ticket-basic': AuthenticatorDefinition(type: factory.method),
            },
          ),
        ).start(
          runtime,
          onEvent: (event) {
            if (event is Map<String, Object?>) events.add(event);
          },
        );
    addTearDown(binding.dispose);
    await Future<void>.delayed(Duration.zero);
    return _HttpRoundFixture(runtime, binding, events);
  }

  Future<NativeHttpResponse> post(
    Map<String, Object?> body, {
    String target = '/auth',
  }) async {
    final connection = nextConnection++;
    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: binding.listeners.single.listenerId,
      connectionId: connection,
      handle: connection,
      method: 'POST',
      target: target,
      headers: const {'content-type': 'application/json'},
      body: body,
      realm: 'router.http',
      procedure: 'router.http.auth',
    );
    await _waitUntil(
      () => runtime.httpResponses[connection]?.isNotEmpty ?? false,
    );
    return runtime.httpResponses[connection]!.single;
  }

  Future<NativeHttpResponse> hello() => post(const {
    'realm': 'realm1',
    'authid': 'user-1',
    'authmethod': 'ticket',
    'authextra': {'origin': 'consumer'},
  });

  Future<NativeHttpResponse> reply(String state, {String target = '/auth'}) =>
      post({
        'state': state,
        'signature': 'round-proof',
        'extra': {'response': 'consumer'},
      }, target: target);
}

String _expectRoundChallenge(NativeHttpResponse response, int round) {
  expect(response.status, HttpStatus.unauthorized);
  expect(response.headers[HttpHeaders.wwwAuthenticateHeader], 'Bearer');
  final body = _jsonResponseBody(response);
  expect(body['state'], isA<String>());
  final state = body['state'] as String;
  expect(state, isNotEmpty);
  expect(body, {
    'status': 'challenge',
    'state': state,
    'realm': 'realm1',
    'authmethod': 'ticket',
    'challenge': {'round': round},
    'extra': {'nonce': 'round-$round'},
  });
  return state;
}

void _expectRoundError(
  NativeHttpResponse response,
  String reason, {
  int status = HttpStatus.unauthorized,
}) {
  expect(response.status, status);
  expect(
    _jsonResponseBody(response),
    allOf(
      containsPair('status', 'error'),
      containsPair('reason', reason),
      isNot(contains('state')),
      isNot(contains('access_token')),
      isNot(contains('refresh_token')),
    ),
  );
}

void _httpRoundAuthenticationTests() {
  group('HTTP authentication rounds', () {
    setUp(AuthSecurityTracker.reset);
    tearDown(AuthSecurityTracker.reset);

    test(
      'poll deadline is an uncredited timeout, not an assertion failure',
      () async {
        await expectLater(
          _waitUntil(() => false, timeout: Duration.zero),
          throwsA(isA<TimeoutException>()),
        );
      },
    );

    test('satisfied poll condition succeeds at a zero deadline', () async {
      await _waitUntil(() => true, timeout: Duration.zero);
    });

    for (final timeout in [0, 10000]) {
      test(
        'rotates states and preserves identity with timeout $timeout',
        () async {
          final auth = _RoundAuthenticator();
          auth.authenticate = () async => auth.messages.length < 3
              ? _RoundAuthenticator.challenge(auth.messages.length + 1)
              : _RoundAuthenticator.success();
          final fixture = await _HttpRoundFixture.start(
            [auth],
            settings: _buildRouterSettingsWithHttpAuthBridge(
              authTimeoutMs: timeout,
            ),
          );
          final states = <String>[
            _expectRoundChallenge(await fixture.hello(), 1),
          ];
          for (var round = 2; round <= 3; round++) {
            final state = _expectRoundChallenge(
              await fixture.reply(states.last),
              round,
            );
            expect(states, isNot(contains(state)));
            for (final previous in states) {
              _expectRoundError(await fixture.reply(previous), 'invalid_state');
            }
            expect(auth.messages, hasLength(round - 1));
            states.add(state);
          }
          final success = await fixture.reply(states.last);
          expect(success.status, HttpStatus.ok);
          expect(
            _jsonResponseBody(success),
            allOf([
              containsPair('status', 'ok'),
              containsPair('realm', 'realm1'),
              containsPair('authid', 'user-1'),
              containsPair('authrole', 'member'),
              containsPair('authmethod', 'ticket'),
              containsPair('authprovider', 'round-provider'),
              containsPair('details', {
                'authprovider': 'round-provider',
                'verified_rounds': 3,
              }),
              containsPair('access_token', isNotEmpty),
              containsPair('refresh_token', isNotEmpty),
              isNot(contains('state')),
            ]),
          );
          expect(auth.contexts, hasLength(3));
          for (final context in auth.contexts) {
            expect(context, same(auth.helloContext));
            expect(context.helloDetails, {
              'authid': 'user-1',
              'authmethods': ['ticket'],
              'authextra': {'origin': 'consumer'},
            });
          }
          for (final message in auth.messages) {
            expect(message.signature, 'round-proof');
            expect(message.extra, {'response': 'consumer'});
          }
          _expectRoundError(await fixture.reply(states.last), 'invalid_state');
          expect(auth.messages, hasLength(3));
          expect(auth.abortReasons, isEmpty);
        },
      );
    }

    for (final profile in [false, true]) {
      test(
        'preserves ${profile ? 'profile' : 'route'} binding after rotation',
        () async {
          final auth = _RoundAuthenticator()
            ..authenticate = () async => _RoundAuthenticator.challenge(2);
          final fixture = await _HttpRoundFixture.start(
            [auth],
            settings: profile
                ? _buildRouterSettingsWithHttpAuthProfileIsolation()
                : _buildRouterSettingsWithHttpAuthRouteIsolation(),
          );
          final first = _expectRoundChallenge(await fixture.hello(), 1);
          final second = _expectRoundChallenge(await fixture.reply(first), 2);
          final reason = profile ? 'wrong_session_profile' : 'wrong_auth_route';
          _expectRoundError(
            await fixture.reply(second, target: '/auth/alternate'),
            reason,
          );
          expect(auth.abortReasons, [reason]);
          expect(auth.messages, hasLength(1));
          _expectRoundError(await fixture.reply(second), 'invalid_state');
          expect(auth.abortReasons, [reason]);
        },
      );
    }

    test('consumes missing-signature state and releases capacity', () async {
      final auth = _RoundAuthenticator()
        ..authenticate = () async => _RoundAuthenticator.challenge(2);
      final replacement = _RoundAuthenticator();
      final fixture = await _HttpRoundFixture.start([
        auth,
        replacement,
      ], settings: _buildRouterSettingsWithHttpAuthBridge(maxPendingAuth: 1));
      final first = _expectRoundChallenge(await fixture.hello(), 1);
      final second = _expectRoundChallenge(await fixture.reply(first), 2);
      _expectRoundError(
        await fixture.post({'state': second}),
        'missing_signature',
        status: HttpStatus.badRequest,
      );
      expect(auth.abortReasons, ['missing_signature']);
      expect(auth.messages, hasLength(1));
      _expectRoundError(await fixture.reply(second), 'invalid_state');
      final next = _expectRoundChallenge(await fixture.hello(), 1);
      expect((await fixture.reply(next)).status, HttpStatus.ok);
    });

    for (final message in <String?>[null, 'Second factor rejected']) {
      test('cleans up failed rounds with message $message', () async {
        final auth = _RoundAuthenticator();
        auth.authenticate = () async => auth.messages.length == 1
            ? _RoundAuthenticator.challenge(2)
            : AuthResult.failure(
                AuthFailure(
                  reason: 'wamp.error.not_authorized',
                  message: message,
                ),
              );
        final fixture = await _HttpRoundFixture.start([auth]);
        final first = _expectRoundChallenge(await fixture.hello(), 1);
        final second = _expectRoundChallenge(await fixture.reply(first), 2);
        final failure = await fixture.reply(second);
        _expectRoundError(failure, 'wamp.error.not_authorized');
        expect(_jsonResponseBody(failure), {
          'status': 'error',
          'reason': 'wamp.error.not_authorized',
          'message': ?message,
        });
        expect(auth.abortReasons, ['authenticate_failed']);
        _expectRoundError(await fixture.reply(second), 'invalid_state');
        expect(auth.messages, hasLength(2));
      });
    }

    test('rejects concurrent replay while authenticator is awaiting', () async {
      final result = Completer<AuthResult>();
      addTearDown(() {
        if (!result.isCompleted) result.complete(_RoundAuthenticator.success());
      });
      final auth = _RoundAuthenticator()..authenticate = () => result.future;
      final fixture = await _HttpRoundFixture.start([auth]);
      final first = _expectRoundChallenge(await fixture.hello(), 1);
      final requests = <Future<NativeHttpResponse>>[];
      void observe(Future<NativeHttpResponse> request) {
        requests.add(request);
        unawaited(
          request.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      }

      addTearDown(() async {
        if (!result.isCompleted) result.complete(_RoundAuthenticator.success());
        await Future.wait(requests);
      });
      final pending = fixture.reply(first);
      observe(pending);
      await _waitUntil(() => auth.messages.length == 1);
      final replayConnection = fixture.nextConnection;
      final replay = fixture.reply(first);
      observe(replay);
      // A second provider invocation is already a replay violation; do not
      // deadlock awaiting its deliberately held authentication result.
      await _waitUntil(
        () =>
            auth.messages.length > 1 ||
            (fixture.runtime.httpResponses[replayConnection]?.isNotEmpty ??
                false),
      );
      expect(auth.messages, hasLength(1));
      _expectRoundError(await replay, 'invalid_state');
      result.complete(_RoundAuthenticator.challenge(2));
      final second = _expectRoundChallenge(await pending, 2);
      expect(second, isNot(first));
      auth.authenticate = null;
      expect((await fixture.reply(second)).status, HttpStatus.ok);
      expect(auth.abortReasons, isEmpty);
    });

    for (final grant in [false, true]) {
      test(
        'rechecks ${grant ? 'grant' : 'challenge'} capacity after async reply',
        () async {
          final result = Completer<AuthResult>();
          addTearDown(() {
            if (!result.isCompleted) {
              result.complete(_RoundAuthenticator.success());
            }
          });
          final auth = _RoundAuthenticator()
            ..authenticate = () => result.future;
          final competing = _RoundAuthenticator();
          final fixture = await _HttpRoundFixture.start(
            [auth, competing],
            settings: _buildRouterSettingsWithHttpAuthBridge(
              maxPendingAuth: grant ? 2 : 1,
              maxHttpAuthGrants: grant ? 1 : 2,
            ),
          );
          final first = _expectRoundChallenge(await fixture.hello(), 1);
          final pending = fixture.reply(first);
          await _waitUntil(() => auth.messages.length == 1);
          final other = _expectRoundChallenge(await fixture.hello(), 1);
          if (grant) expect((await fixture.reply(other)).status, HttpStatus.ok);
          result.complete(
            grant
                ? _RoundAuthenticator.success()
                : _RoundAuthenticator.challenge(2),
          );
          _expectRoundError(
            await pending,
            grant ? 'auth_grant_capacity_exhausted' : 'auth_capacity_exhausted',
            status: grant
                ? HttpStatus.serviceUnavailable
                : HttpStatus.tooManyRequests,
          );
          expect(auth.abortReasons, [
            grant
                ? 'http_auth_grant_capacity_exhausted'
                : 'http_auth_capacity_exhausted',
          ]);
          _expectRoundError(await fixture.reply(first), 'invalid_state');
          if (!grant) {
            expect((await fixture.reply(other)).status, HttpStatus.ok);
          }
          expect(competing.abortReasons, isEmpty);
        },
      );
    }

    test('expires rotated state and releases challenge capacity', () async {
      final auth = _RoundAuthenticator()
        ..authenticate = () async => _RoundAuthenticator.challenge(2);
      final replacement = _RoundAuthenticator();
      final fixture = await _HttpRoundFixture.start(
        [auth, replacement],
        settings: _buildRouterSettingsWithHttpAuthBridge(
          maxPendingAuth: 1,
          authTimeoutMs: 500,
        ),
      );
      final first = _expectRoundChallenge(await fixture.hello(), 1);
      final second = _expectRoundChallenge(await fixture.reply(first), 2);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      _expectRoundError(await fixture.reply(second), 'invalid_state');
      expect(auth.abortReasons, ['http_auth_timeout']);
      expect(auth.messages, hasLength(1));
      final next = _expectRoundChallenge(await fixture.hello(), 1);
      expect((await fixture.reply(next)).status, HttpStatus.ok);
    });

    test('applies identity lockout to rotated challenge', () async {
      final auth = _RoundAuthenticator()
        ..authenticate = () async => _RoundAuthenticator.challenge(2);
      final settings = _buildRouterSettingsWithHttpAuthBridge(maxFailedAuth: 1);
      final fixture = await _HttpRoundFixture.start([auth], settings: settings);
      final first = _expectRoundChallenge(await fixture.hello(), 1);
      final second = _expectRoundChallenge(await fixture.reply(first), 2);
      AuthSecurityTracker.recordFailure(
        'realm1',
        'user-1',
        settings.realms.single.limits,
      );
      _expectRoundError(
        await fixture.reply(second),
        'auth_locked_out',
        status: HttpStatus.tooManyRequests,
      );
      expect(auth.abortReasons, ['http_auth_locked_out']);
      expect(auth.messages, hasLength(1));
      _expectRoundError(await fixture.reply(second), 'invalid_state');
    });

    for (final duringHello in [false, true]) {
      for (final outcome in ['challenge', 'success', 'failure', 'error']) {
        test(
          'disposal rejects late $outcome during ${duringHello ? 'hello' : 'reply'}',
          () async {
            final result = Completer<AuthResult>();
            addTearDown(() {
              if (!result.isCompleted) {
                result.complete(_RoundAuthenticator.success());
              }
            });
            final auth = _RoundAuthenticator();
            if (duringHello) {
              auth.hello = () => result.future;
            } else {
              auth.authenticate = () => result.future;
            }
            final fixture = await _HttpRoundFixture.start([auth]);
            final pending = duringHello
                ? fixture.hello()
                : fixture.reply(
                    _expectRoundChallenge(await fixture.hello(), 1),
                  );
            await _waitUntil(
              () => duringHello
                  ? auth.helloContext != null
                  : auth.messages.isNotEmpty,
            );
            await fixture.binding.dispose();
            final abortsAtDisposal = List<String?>.of(auth.abortReasons);
            if (outcome == 'error') {
              result.completeError(StateError('Authenticator stopped'));
            } else {
              result.complete(switch (outcome) {
                'challenge' => _RoundAuthenticator.challenge(2),
                'success' => _RoundAuthenticator.success(),
                _ => AuthResult.failure(
                  const AuthFailure(reason: 'wamp.error.not_authorized'),
                ),
              });
            }
            final response = await pending;
            _expectRoundError(
              response,
              'binding_disposed',
              status: HttpStatus.serviceUnavailable,
            );
            expect(abortsAtDisposal, ['binding_dispose']);
            await fixture.binding.dispose();
            expect(auth.abortReasons, ['binding_dispose']);
          },
        );
      }
    }

    for (final duringHello in [false, true]) {
      test(
        'disposal contains cleanup errors during ${duringHello ? 'hello' : 'reply'}',
        () async {
          final result = Completer<AuthResult>();
          addTearDown(() {
            if (!result.isCompleted) {
              result.complete(_RoundAuthenticator.success());
            }
          });
          final auth = _RoundAuthenticator()..failAbort = true;
          if (duringHello) {
            auth.hello = () => result.future;
          } else {
            auth.authenticate = () => result.future;
          }
          final fixture = await _HttpRoundFixture.start([auth]);
          final pending = duringHello
              ? fixture.hello()
              : fixture.reply(_expectRoundChallenge(await fixture.hello(), 1));
          await _waitUntil(
            () => duringHello
                ? auth.helloContext != null
                : auth.messages.isNotEmpty,
          );
          await fixture.binding.dispose();
          result.complete(_RoundAuthenticator.success());
          _expectRoundError(
            await pending,
            'binding_disposed',
            status: HttpStatus.serviceUnavailable,
          );
          expect(auth.abortReasons, ['binding_dispose']);
          expect(
            fixture.events.where(
              (event) => event['type'] == 'http_auth_abort_failed',
            ),
            [
              {
                'source': 'binding',
                'type': 'http_auth_abort_failed',
                'reason': 'binding_dispose',
              },
            ],
          );
        },
      );
    }

    test(
      'does not start a late-created authenticator after disposal',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final auth = _RoundAuthenticator();
        final fixture = await _HttpRoundFixture.start(
          [auth],
          beforeCreate: () async {
            entered.complete();
            await release.future;
          },
        );
        final pending = fixture.hello();
        await entered.future.timeout(const Duration(seconds: 2));
        await fixture.binding.dispose();
        release.complete();
        _expectRoundError(
          await pending,
          'binding_disposed',
          status: HttpStatus.serviceUnavailable,
        );
        expect(auth.helloContext, isNull);
        expect(auth.messages, isEmpty);
        expect(auth.abortReasons, ['binding_dispose']);
        expect(auth.abortContexts.single.helloDetails['authid'], 'user-1');
        expect(auth.abortContexts.single.realm.name, 'realm1');
      },
    );

    test('disposes rotated challenge exactly once', () async {
      final auth = _RoundAuthenticator()
        ..authenticate = () async => _RoundAuthenticator.challenge(2);
      final fixture = await _HttpRoundFixture.start([auth]);
      final first = _expectRoundChallenge(await fixture.hello(), 1);
      _expectRoundChallenge(await fixture.reply(first), 2);
      await fixture.binding.dispose();
      expect(auth.abortReasons, ['binding_dispose']);
      await fixture.binding.dispose();
      expect(auth.abortReasons, ['binding_dispose']);
    });
  });
}

class _FileResponseCleanupRuntime extends _HandleRuntime {
  _FileResponseCleanupRuntime({required this.failAdd});
  final bool failAdd;
  final List<int> streamCloses = [];
  final List<Uint8List> chunks = [];
  late int Function() releases;
  final List<int> releasesAtOpen = [];
  final List<int> releasesAtSend = [];
  final List<int> responseAttempts = [];
  Object? sendError;
  final addError = StateError('controlled file stream add failure');

  @override
  NativeHttpResponseStream openHttpResponseStream({
    required int handshakeHandle,
    required int status,
    required Map<String, String> headers,
  }) {
    releasesAtOpen.add(releases());
    return _FakeHttpResponseStream(
      handle: handshakeHandle,
      onChunk: (chunk) {
        if (failAdd) throw addError;
        chunks.add(Uint8List.fromList(chunk));
      },
      onClose: () => streamCloses.add(handshakeHandle),
    );
  }

  @override
  void sendHttpResponse({
    required int handshakeHandle,
    int? connectionId,
    required NativeHttpResponse response,
  }) {
    responseAttempts.add(handshakeHandle);
    releasesAtSend.add(releases());
    final error = sendError;
    if (error != null) throw error;
    super.sendHttpResponse(
      handshakeHandle: handshakeHandle,
      connectionId: connectionId,
      response: response,
    );
  }
}

class _DeferredResponseFile implements File {
  _DeferredResponseFile({this.cancellation});

  final Completer<void>? cancellation;
  final checked = Completer<void>();
  final existence = Completer<bool>();
  final reading = Completer<void>();
  final cancelled = Completer<void>();
  late final body = StreamController<List<int>>(
    onListen: () => reading.complete(),
    onCancel: () {
      cancelled.complete();
      return cancellation?.future;
    },
  );
  int reads = 0;

  @override
  Future<bool> exists() {
    checked.complete();
    return existence.future;
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    reads++;
    return body.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _fileResponseCleanupTests() {
  for (final sameConnection in [false, true]) {
    for (final failCancellation in [false, true]) {
      for (final failRejection in [false, true]) {
        test(
          'file disposal admission sameConnection=$sameConnection '
          'failCancellation=$failCancellation failRejection=$failRejection',
          () async {
            final runtime = _FileResponseCleanupRuntime(failAdd: false);
            final original = _TrackedHttpHandshake(9601);
            final late = _TrackedHttpHandshake(9602);
            runtime.releases = () => original.releases;
            final cancellation = Completer<void>();
            final file = _DeferredResponseFile(cancellation: cancellation);
            const path = '/controlled-connectanum-disposal-admission';
            final parentZone = Zone.current;
            final lateConnection = sameConnection ? 56 : 57;
            final sendError = StateError('controlled rejected send');
            final handlerErrors = <Map<String, Object?>>[];
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
            final binding = IOOverrides.runZoned(
              () => router.start(
                runtime,
                onEvent: (event) {
                  if (event is Map<String, Object?> &&
                      event['type'] == 'http_request_handler_error') {
                    handlerErrors.add(event);
                  }
                },
              ),
              createFile: (name) =>
                  name == path ? file : parentZone.run(() => File(name)),
            );
            addTearDown(binding.dispose);
            final session = await binding.createInternalSession(
              realmUri: 'realm1',
            );
            final registration = await session.register(
              'com.example.api.stream',
            );
            var invocations = 0;
            registration.onInvoke((invocation) {
              invocations++;
              if (invocations == 1) {
                HttpInvocationContext.maybeFromInvocation(
                  invocation,
                )!.sendFile(path: path);
              } else {
                invocation.respondWith(
                  arguments: const ['unexpected admission'],
                );
              }
            });
            runtime.setConnectionProtocol(56, NativeConnectionProtocol.http);
            runtime.enqueueHttpHandshake(
              binding.listeners.single.listenerId,
              56,
              original,
            );
            await file.checked.future.timeout(const Duration(seconds: 2));
            file.existence.complete(true);
            await file.reading.future.timeout(const Duration(seconds: 2));
            final errors = <Object>[];
            final disposal = binding.dispose().then<void>(
              (_) {},
              onError: (Object error) => errors.add(error),
            );
            final cancellationError = StateError(
              'admission cancellation failure',
            );
            try {
              await file.cancelled.future.timeout(const Duration(seconds: 2));
              if (failRejection) runtime.sendError = sendError;
              if (sameConnection) {
                runtime.queueHttpRequestForConnection(56, late);
              } else {
                runtime.setConnectionProtocol(
                  57,
                  NativeConnectionProtocol.http,
                );
                runtime.enqueueHttpHandshake(
                  binding.listeners.single.listenerId,
                  57,
                  late,
                );
              }
              await _waitUntil(
                () =>
                    invocations > 1 ||
                    late.releases > 0 ||
                    runtime.responseAttempts.contains(late.handle),
              );
              expect(
                invocations,
                1,
                reason: 'Disposal must not admit new application work.',
              );
              expect(
                late.releases,
                1,
                reason: 'A rejected request must release its handshake.',
              );
              expect(runtime.responseAttempts, [late.handle]);
              if (failRejection) {
                expect(runtime.httpResponses, isEmpty);
                expect(handlerErrors, hasLength(1));
                expect(handlerErrors.single['connectionId'], lateConnection);
                expect(handlerErrors.single['error'], sendError.toString());
              } else {
                expect(runtime.httpResponses[lateConnection], hasLength(1));
                final response = runtime.httpResponses[lateConnection]!.single;
                expect(response.status, 503);
                expect(handlerErrors, isEmpty);
              }
            } finally {
              if (failCancellation) {
                cancellation.completeError(cancellationError);
              } else {
                cancellation.complete();
              }
              await disposal;
            }
            expect(
              errors,
              failCancellation ? [same(cancellationError)] : isEmpty,
            );
            expect(original.releases, 1);
            expect(late.releases, 1);
            expect(runtime.streamCloses, [original.handle]);
            expect(file.reads, 1);
            expect(invocations, 1);
            await file.body.close();
          },
        );
      }
    }
  }
  for (final throwObserver in [false, true]) {
    test(
      'file response cleanup disposal releases all calls observer=$throwObserver',
      () async {
        final runtime = _HttpCleanupRuntime(direct: false);
        final handshakes = [
          _TrackedHttpHandshake(9501),
          _TrackedHttpHandshake(9502),
        ];
        final observerErrors = [
          StateError('first cleanup observer'),
          StateError('second cleanup observer'),
        ];
        final finishEvents = <Map<String, Object?>>[];
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
        final binding = router.start(
          runtime,
          onEvent: (event) {
            if (event is Map<String, Object?> &&
                event['type'] == 'http_response_stream_finish_error') {
              finishEvents.add(event);
              if (throwObserver) throw observerErrors[finishEvents.length - 1];
            }
          },
        );
        addTearDown(binding.dispose);
        final session = await binding.createInternalSession(realmUri: 'realm1');
        final registration = await session.register('com.example.api.stream');
        final contexts = <HttpInvocationContext>[];
        registration.onInvoke((invocation) {
          contexts.add(HttpInvocationContext.maybeFromInvocation(invocation)!);
        });
        for (var index = 0; index < handshakes.length; index++) {
          runtime.setConnectionProtocol(
            56 + index,
            NativeConnectionProtocol.http,
          );
          runtime.enqueueHttpHandshake(
            binding.listeners.single.listenerId,
            56 + index,
            handshakes[index],
          );
        }
        await _waitUntil(() => contexts.length == 2);
        for (final context in contexts) {
          HttpResponseUtil.respond(
            context.invocation,
            HttpResponseUtil.bytes(
              requestId: context.requestId,
              status: 206,
              body: Uint8List.fromList([1]),
            ),
            progress: true,
          );
        }
        await _waitUntil(() => runtime.responseStreamChunks.length == 2);
        expect(handshakes.map((handshake) => handshake.releases), [0, 0]);
        if (throwObserver) {
          await expectLater(
            binding.dispose(),
            throwsA(same(observerErrors.first)),
          );
        } else {
          await binding.dispose();
        }
        expect(handshakes.map((handshake) => handshake.releases), [1, 1]);
        expect(runtime.finishAttempts, [9501, 9502]);
        expect(finishEvents, hasLength(2));
        expect(runtime.closedListeners, isNotEmpty);
        await binding.dispose();
        expect(handshakes.map((handshake) => handshake.releases), [1, 1]);
        expect(runtime.finishAttempts, [9501, 9502]);
      },
    );
  }
  for (final stage in [
    'exists',
    'chunk',
    'eof',
    'delayed-cancel',
    'delayed-cancel-error',
    'concurrent-cancel',
    'concurrent-cancel-error',
  ]) {
    test(
      'file response cleanup disposal during $stage cannot restart I/O',
      () async {
        final runtime = _FileResponseCleanupRuntime(failAdd: false);
        final handshake = _TrackedHttpHandshake(9401);
        runtime.releases = () => handshake.releases;
        final cancellation = stage.contains('cancel')
            ? Completer<void>()
            : null;
        final file = _DeferredResponseFile(cancellation: cancellation);
        const path = '/controlled-connectanum-file-response';
        final parentZone = Zone.current;
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
          settings: _buildRouterSettingsWithPendingProtocols(),
        );
        final binding = IOOverrides.runZoned(
          () => router.start(
            runtime,
            onEvent: (event) {
              if (event is Map<String, Object?>) events.add(event);
            },
          ),
          createFile: (name) =>
              name == path ? file : parentZone.run(() => File(name)),
        );
        addTearDown(binding.dispose);
        final session = await binding.createInternalSession(realmUri: 'realm1');
        final registration = await session.register('com.example.api.stream');
        registration.onInvoke((invocation) {
          HttpInvocationContext.maybeFromInvocation(
            invocation,
          )!.sendFile(path: path);
        });
        runtime.setConnectionProtocol(56, NativeConnectionProtocol.http);
        runtime.enqueueHttpHandshake(
          binding.listeners.single.listenerId,
          56,
          handshake,
        );
        await file.checked.future.timeout(const Duration(seconds: 2));
        // Let the final WAMP result's onDone run while file existence is pending.
        await Future<void>.delayed(Duration.zero);
        expect(handshake.releases, 0);
        if (stage != 'exists') {
          file.existence.complete(true);
          await file.reading.future.timeout(const Duration(seconds: 2));
          expect(runtime.releasesAtOpen, [0]);
        }
        if (cancellation != null) {
          var finishedDisposals = 0;
          final disposalErrors = <Object>[];
          final cancelError = stage.endsWith('-error')
              ? StateError('controlled asynchronous file cancellation')
              : null;
          Future<void> dispose() => binding.dispose().then(
            (_) => finishedDisposals++,
            onError: (Object error) {
              disposalErrors.add(error);
              finishedDisposals++;
            },
          );
          final disposals = [
            dispose(),
            if (stage.startsWith('concurrent')) dispose(),
          ];
          try {
            await file.cancelled.future.timeout(const Duration(seconds: 2));
            await Future<void>.delayed(const Duration(milliseconds: 50));
            expect(
              finishedDisposals,
              0,
              reason: 'Disposal must join asynchronous file-read cancellation.',
            );
          } finally {
            if (cancelError != null) {
              cancellation.completeError(cancelError);
            } else {
              cancellation.complete();
            }
            await Future.wait(disposals);
          }
          expect(finishedDisposals, disposals.length);
          expect(
            disposalErrors,
            cancelError == null ? isEmpty : everyElement(same(cancelError)),
          );
          expect(
            disposalErrors,
            hasLength(cancelError == null ? 0 : disposals.length),
          );
        } else {
          await binding.dispose();
        }
        expect(handshake.releases, 1);
        if (stage == 'exists') {
          file.existence.complete(true);
          await Future<void>.delayed(Duration.zero);
          expect(file.reads, 0);
          expect(runtime.releasesAtOpen, isEmpty);
          expect(runtime.streamCloses, isEmpty);
        } else {
          expect(
            file.cancelled.isCompleted,
            isTrue,
            reason:
                'Disposal must cancel the active file read before returning.',
          );
          await file.cancelled.future.timeout(const Duration(seconds: 2));
          if (stage == 'chunk') file.body.add([1, 2, 3]);
          await file.body.close().timeout(const Duration(seconds: 2));
          await file.cancelled.future.timeout(const Duration(seconds: 2));
          expect(runtime.streamCloses, [handshake.handle]);
        }
        expect(handshake.releases, 1);
        expect(runtime.chunks, isEmpty);
        expect(runtime.httpResponses, isEmpty);
        expect(
          events.where(
            (event) =>
                event['type'] == 'http_response_file_streamed' ||
                event['type'] == 'http_response_file_stream_error',
          ),
          isEmpty,
        );
      },
    );
  }
  for (final outcome in ['missing', 'stream-error', 'success']) {
    for (final throwObserver in [false, true]) {
      test(
        'file response cleanup outcome=$outcome observer=$throwObserver',
        () async {
          final runtime = _FileResponseCleanupRuntime(
            failAdd: outcome == 'stream-error',
          );
          final directory = await Directory.systemTemp.createTemp(
            'connectanum-file-cleanup-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final file = File('${directory.path}/payload');
          if (outcome != 'missing') {
            await file.writeAsString('file-response-payload');
          }
          final handshake = _TrackedHttpHandshake(9301);
          runtime.releases = () => handshake.releases;
          final observerError = StateError('controlled file observer failure');
          final errors = <Object>[];
          final releaseCountsAtError = <int>[];
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
            settings: _buildRouterSettingsWithPendingProtocols(),
          );
          final binding = runZonedGuarded(
            () => router.start(
              runtime,
              onEvent: (event) {
                if (event is! Map<String, Object?>) return;
                events.add(event);
                final type = outcome == 'success'
                    ? 'http_response_file_streamed'
                    : 'http_response_file_stream_error';
                if (throwObserver && event['type'] == type) throw observerError;
              },
            ),
            (error, _) {
              errors.add(error);
              releaseCountsAtError.add(handshake.releases);
            },
          )!;
          addTearDown(binding.dispose);
          final session = await binding.createInternalSession(
            realmUri: 'realm1',
          );
          final registration = await session.register('com.example.api.stream');
          registration.onInvoke((invocation) {
            final context = HttpInvocationContext.maybeFromInvocation(
              invocation,
            );
            expect(context, isNotNull);
            context!.sendFile(path: file.path, status: 206);
          });
          runtime.setConnectionProtocol(56, NativeConnectionProtocol.http);
          runtime.enqueueHttpHandshake(
            binding.listeners.single.listenerId,
            56,
            handshake,
          );
          await _waitUntil(() => handshake.releases != 0 || errors.isNotEmpty);
          expect(
            handshake.releases,
            1,
            reason: 'File response termination must release its handshake.',
          );
          expect(
            releaseCountsAtError,
            everyElement(1),
            reason: 'Cleanup must run before observer exceptions escape.',
          );
          if (outcome == 'missing') {
            expect(runtime.streamCloses, isEmpty);
            if (!throwObserver) {
              expect(
                runtime.releasesAtSend,
                [0],
                reason:
                    'The handshake must remain owned until the error is sent.',
              );
              final response = runtime.httpResponses[56]!.single;
              expect(response.status, HttpStatus.internalServerError);
              expect(
                _jsonResponseBody(response)['error'],
                'file_response_unavailable',
              );
            }
          } else {
            expect(
              runtime.releasesAtOpen,
              [0],
              reason:
                  'Opening the file stream must not use a released handshake.',
            );
            expect(runtime.streamCloses, [handshake.handle]);
            if (outcome == 'success') {
              expect(
                utf8.decode(runtime.chunks.expand((chunk) => chunk).toList()),
                'file-response-payload',
              );
            } else {
              expect(runtime.chunks, isEmpty);
            }
          }
          expect(
            events.where(
              (event) => event['type'] == 'http_response_file_stream_error',
            ),
            outcome == 'success' && !throwObserver ? isEmpty : isNotEmpty,
          );
          expect(
            errors,
            throwObserver && outcome != 'success' ? [observerError] : isEmpty,
          );
        },
      );
    }
  }
}

void main() {
  registerHttpAdapterOptionCases();
  _internalCallLifecycleCases();
  _internalCloseCases();
  _httpBossOwnershipCases();
  _httpEarlyCleanupCases();
  _httpEdgeCases();
  _fileResponseCleanupTests();
  _httpRoundAuthenticationTests();
  _httpInitialAuthenticationTests();
  _httpAuthAbortTests();
  _httpAuthProviderFailureTests();
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
        runtime.throwOnEmptyPoll = true;
        late RouterBinding binding;
        final drainStates = <bool>[];
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

        binding = router.start(
          runtime,
          onEvent: (event) {
            if (event is Map<String, Object?> &&
                event['type'] == 'drain_started') {
              drainStates.add(binding.isDraining);
            }
          },
        );
        addTearDown(binding.dispose);
        final listener = binding.listeners.single;
        runtime.enqueueConnection(listener.listenerId, 7001);

        await binding.drain();

        expect(runtime.closedListeners, contains(listener.listenerId));
        expect(runtime.closedConnections, contains(7001));
        expect(drainStates, [true]);
        expect(binding.isDraining, isFalse);
      },
    );

    test(
      'drain closes generated OpenMetrics listener after application listeners',
      () async {
        final runtime = _FakeRuntime();
        runtime.throwOnEmptyPoll = true;
        final events = <Map<String, Object?>>[];
        final settings = RouterSettings(
          realms: const [],
          listeners: const [
            ListenerSettings(type: 'rawsocket', endpoint: '127.0.0.1:9000'),
          ],
          metrics: const MetricsSettings(
            openMetrics: OpenMetricsSettings(
              enabled: true,
              listen: '127.0.0.1:9001',
            ),
          ),
        ).withOpenMetricsHttpRoutes();
        final router = Router(
          RouterConfig(
            endpoints: settings.listeners
                .map(Endpoint.fromListenerSettings)
                .toList(growable: false),
          ),
          settings: settings,
        );

        final binding = router.start(
          runtime,
          onEvent: (event) {
            if (event is Map<String, Object?> &&
                event['type'] == 'listeners_closed') {
              events.add(event);
            }
          },
        );
        addTearDown(binding.dispose);
        expect(binding.listeners, hasLength(2));

        await binding.drain();

        expect(
          runtime.closedListeners,
          equals([
            binding.listeners[0].listenerId,
            binding.listeners[1].listenerId,
          ]),
        );
        expect(
          events.map((event) => event['listeners_closed']),
          equals([1, 1]),
        );
      },
    );

    test('drain reports timeout metrics and can be started again', () async {
      final runtime = _FakeRuntime();
      runtime.throwOnEmptyPoll = true;
      final binding = Router(
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
      ).start(runtime);
      addTearDown(binding.dispose);

      await binding.drain(drainTimeout: Duration.zero);
      await binding.drain();

      expect(binding.shutdownMetrics.drainTotal, 2);
      expect(binding.shutdownMetrics.drainTimeouts, 1);
      expect(binding.shutdownMetrics.lastDrainDurationMs, isNotNull);
    });

    test('drain keeps an empty first metrics-only snapshot silent', () async {
      final runtime = _FakeRuntime();
      runtime.throwOnEmptyPoll = true;
      final events = <Map<String, Object?>>[];
      final settings = RouterSettings(
        realms: const [],
        listeners: const [],
        metrics: const MetricsSettings(
          openMetrics: OpenMetricsSettings(
            enabled: true,
            listen: '127.0.0.1:9001',
          ),
        ),
      ).withOpenMetricsHttpRoutes();
      final binding =
          Router(
            RouterConfig(
              endpoints: settings.listeners
                  .map(Endpoint.fromListenerSettings)
                  .toList(growable: false),
            ),
            settings: settings,
          ).start(
            runtime,
            onEvent: (event) {
              if (event is Map<String, Object?> &&
                  event['type'] == 'listeners_closed') {
                events.add(event);
              }
            },
          );
      addTearDown(binding.dispose);

      await binding.drain();

      expect(binding.listeners, hasLength(1));
      expect(runtime.closedListeners, [binding.listeners.single.listenerId]);
      expect(events.map((event) => event['listeners_closed']), equals([1]));
    });

    test('drain is a no-op before listeners activate', () async {
      final runtime = _FakeRuntime();
      runtime.throwOnEmptyPoll = true;
      final events = <Object>[];
      final binding =
          Router(
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
          ).start(
            runtime,
            activateListeners: false,
            onEvent: events.add,
          );
      addTearDown(binding.dispose);

      await binding.drain();

      expect(binding.isReady, isFalse);
      expect(binding.isDraining, isFalse);
      expect(runtime.listenCalls, isEmpty);
      expect(runtime.closedListeners, isEmpty);
      expect(runtime.closedConnections, isEmpty);
      expect(events, isEmpty);
    });

    test('drain treats zero pending connection ids as a sentinel', () async {
      final runtime = _FakeRuntime();
      final binding = Router(
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
      ).start(runtime);
      addTearDown(binding.dispose);
      final listener = binding.listeners.single;
      runtime.setPollConnectionActions(listener.listenerId, [
        0,
        StateError('controlled poll failure after the sentinel'),
      ]);

      await binding.drain();

      expect(runtime.closedConnections, isEmpty);
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

    test('encodes per-method HTTP route action overrides', () {
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
                      match: HttpRouteMatch(
                        prefix: '/tasks/',
                        methods: ['GET'],
                      ),
                      action: HttpRouteAction(
                        type: HttpRouteActionType.rpc,
                        realm: 'realm1',
                        procedure: 'com.example.tasks.read',
                      ),
                      methodActions: {
                        'POST': HttpRouteAction(
                          type: HttpRouteActionType.rpc,
                          realm: 'realm1',
                          procedure: 'com.example.tasks.create',
                        ),
                        'DELETE': HttpRouteAction(
                          type: HttpRouteActionType.reservedRealm,
                          namespace: 'tasks',
                          appendMethodSuffix: false,
                        ),
                        'PUT': HttpRouteAction(
                          type: HttpRouteActionType.publish,
                          realm: 'realm1',
                          topic: 'com.example.tasks.changed',
                        ),
                      },
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
      expect(routes, hasLength(1));

      final route = routes.single as Map<String, Object?>;
      expect(route['path'], '/tasks/');
      expect(route['match_kind'], 'prefix');
      expect(route.containsKey('default'), isFalse);

      final methods = route['methods'] as Map<String, Object?>;
      expect(
        methods.keys,
        containsAll(<String>['GET', 'POST', 'DELETE', 'PUT']),
      );

      final get = methods['GET'] as Map<String, Object?>;
      expect(get['type'], 'translation');
      expect(get['realm'], 'realm1');
      expect(get['procedure'], 'com.example.tasks.read');

      final post = methods['POST'] as Map<String, Object?>;
      expect(post['type'], 'translation');
      expect(post['realm'], 'realm1');
      expect(post['procedure'], 'com.example.tasks.create');

      final delete = methods['DELETE'] as Map<String, Object?>;
      expect(delete['type'], 'reserved_realm');
      expect(delete['namespace'], 'tasks');
      expect(delete['append_method_suffix'], isFalse);

      final put = methods['PUT'] as Map<String, Object?>;
      expect(put['type'], 'translation');
      expect(put['realm'], 'realm1');
      expect(put['procedure'], 'router.http.publish');
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

    _nativeMessageWatchCases();

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
    'dispatches session_proxy HTTP routes through internal sessions',
    () async {
      final runtime = _HandleRuntime();
      final settings =
          (RouterSettingsBuilder()
                ..addRealmFromBuilder(
                  RealmSettingsBuilder('router.http.bridge')
                    ..addAuthMethod('anonymous')
                    ..addRoleFromBuilder(
                      RoleSettingsBuilder('anonymous')
                        ..addPermissionFromBuilder(
                          PermissionSettingsBuilder('')
                            ..setMatchPolicy(PermissionMatchPolicy.prefix)
                            ..allowOperations(const [
                              'call',
                              'register',
                              'unregister',
                            ]),
                        ),
                    ),
                )
                ..addInternalRealmFromBuilder(
                  InternalRealmSettingsBuilder('router.http.bridge')
                    ..addService('consumer-proxy'),
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
                              match: HttpRouteMatch(path: '/proxy/tasks'),
                              action: HttpRouteAction(
                                type: HttpRouteActionType.sessionProxy,
                                delegate: 'consumer-proxy',
                                procedure: 'consumer.http.handle',
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
                ))
              .build();
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
      const connectionId = 54;

      final handlerSession = await binding.createInternalSession(
        realmUri: 'router.http.bridge',
      );
      addTearDown(handlerSession.close);
      final registered = await handlerSession.register('consumer.http.handle');
      registered.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull);
        final request = context!.request;
        expect(request.method, 'POST');
        expect(request.path, '/proxy/tasks');
        expect(request.query, 'source=consumer');
        context.sendJson(
          body: <String, Object?>{
            'accepted': true,
            'body': utf8.decode(request.body!),
          },
          status: HttpStatus.accepted,
          headers: const {'x-proxy': 'consumer'},
        );
      });

      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 54,
          method: 'POST',
          target: '/proxy/tasks?source=consumer',
          path: '/proxy/tasks',
          query: 'source=consumer',
          protocol: 'http/1.1',
          headers: const {'content-type': 'application/json'},
          body: Uint8List.fromList(utf8.encode('{"taskId":"42"}')),
          realm: 'router.http.bridge',
          procedure: 'consumer.http.handle',
        ),
      );

      await _waitUntil(
        () => events.any((event) => event['type'] == 'http_request_dispatched'),
        timeout: const Duration(seconds: 2),
      );
      final dispatchEvent = events.firstWhere(
        (event) => event['type'] == 'http_request_dispatched',
      );
      expect(dispatchEvent['realm'], 'router.http.bridge');
      expect(dispatchEvent['procedure'], 'consumer.http.handle');
      expect(dispatchEvent['listenerId'], listenerId);
      expect(dispatchEvent['connectionId'], connectionId);

      await _waitUntil(
        () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        timeout: const Duration(seconds: 2),
      );
      final response = runtime.httpResponses[connectionId]!.single;
      expect(response.status, HttpStatus.accepted);
      expect(response.headers['x-proxy'], 'consumer');
      final body = _jsonResponseBody(response);
      expect(body['accepted'], isTrue);
      expect(body['body'], '{"taskId":"42"}');
    },
  );

  test('publishes HTTP route requests through internal sessions', () async {
    final runtime = _HandleRuntime();
    final settings =
        (RouterSettingsBuilder()
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
                    ..addProtocol(ListenerProtocol.rawsocket)
                    ..addProtocol(ListenerProtocol.http)
                    ..setOptions(const {'max_rawsocket_size_exponent': 16})
                    ..setHttpOptions(
                      const HttpListenerSettings(
                        routes: [
                          HttpRouteSettings(
                            match: HttpRouteMatch(path: '/webhook/tasks'),
                            action: HttpRouteAction(
                              type: HttpRouteActionType.publish,
                              realm: 'realm1',
                              topic: 'com.example.webhooks.tasks',
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
              ))
            .build();
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
    const connectionId = 55;

    final subscriber = await binding.createInternalSession(realmUri: 'realm1');
    addTearDown(subscriber.close);
    final subscription = await subscriber.subscribe(
      'com.example.webhooks.tasks',
    );
    final eventCompleter = Completer<Event>();
    subscription.onEvent((event) {
      if (!eventCompleter.isCompleted) {
        eventCompleter.complete(event);
      }
    });

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 55,
        method: 'POST',
        target: '/webhook/tasks?source=consumer',
        path: '/webhook/tasks',
        query: 'source=consumer',
        protocol: 'http/1.1',
        headers: const {'content-type': 'application/json'},
        body: Uint8List.fromList(utf8.encode('{"taskId":"42"}')),
        realm: 'realm1',
        procedure: 'router.http.publish',
      ),
    );

    final published = await eventCompleter.future.timeout(
      const Duration(seconds: 2),
    );
    final kwargs = published.argumentsKeywords!;
    final http = Map<String, Object?>.from(kwargs['_http'] as Map);
    expect(http['method'], 'POST');
    expect(http['path'], '/webhook/tasks');
    expect(http['query'], 'source=consumer');
    expect(http['headers'], containsPair('content-type', 'application/json'));
    expect(utf8.decode(http['body'] as Uint8List), '{"taskId":"42"}');

    final connection = Map<String, Object?>.from(kwargs['_connection'] as Map);
    expect(connection['listenerId'], listenerId);
    expect(connection['connectionId'], connectionId);

    await _waitUntil(
      () => events.any((event) => event['type'] == 'http_publish_dispatched'),
      timeout: const Duration(seconds: 2),
    );
    final dispatchEvent = events.firstWhere(
      (event) => event['type'] == 'http_publish_dispatched',
    );
    expect(dispatchEvent['realm'], 'realm1');
    expect(dispatchEvent['topic'], 'com.example.webhooks.tasks');
    expect(dispatchEvent['listenerId'], listenerId);
    expect(dispatchEvent['connectionId'], connectionId);

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, HttpStatus.accepted);
    final body = _jsonResponseBody(response);
    expect(body['status'], 'accepted');
    expect(body['topic'], 'com.example.webhooks.tasks');
    expect(body['publicationId'], isA<int>());
  });

  test(
    'streams file-backed HTTP route responses using native streams',
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

      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum-file-response-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File('${tempDir.path}${Platform.pathSeparator}payload.txt');
      await file.writeAsString('file-backed-response');

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
        'com.example.api.health',
      );
      registered.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        expect(context, isNotNull);
        context!.sendFile(
          path: file.path,
          status: 206,
          headers: const {'x-file': 'true'},
        );
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
          target: '/api/health',
          path: '/api/health',
          protocol: 'http/1.1',
          headers: const {'x-test': 'file'},
          body: Uint8List.fromList(utf8.encode('{}')),
          realm: 'realm1',
          procedure: 'com.example.api.health',
        ),
      );

      await _waitUntil(
        () => events.any((event) => event['type'] == 'http_response_ready'),
        timeout: const Duration(seconds: 2),
      );
      final responseEvent = events.firstWhere(
        (event) => event['type'] == 'http_response_ready',
      );
      final response = responseEvent['response'] as Map;
      expect(response['status'], 206);
      expect(response['bodyKind'], 'file');
      expect(response['filePath'], file.path);

      await _waitUntil(
        () => events.any(
          (event) => event['type'] == 'http_response_file_streamed',
        ),
        timeout: const Duration(seconds: 2),
      );
      expect(runtime.httpResponses[connectionId], isNull);
      expect(runtime.responseStreamOpens, hasLength(1));
      final open = runtime.responseStreamOpens.single;
      expect(open.handshakeHandle, 2);
      expect(open.status, 206);
      expect(open.headers['x-file'], 'true');
      final handle = open.streamHandle;

      await _waitUntil(
        () => runtime.closedResponseStreams.contains(handle),
        timeout: const Duration(seconds: 2),
      );
      final chunks = runtime.responseStreamChunks[handle];
      expect(chunks, isNotNull);
      final bytes = chunks!.expand((chunk) => chunk).toList();
      expect(utf8.decode(bytes), 'file-backed-response');
      expect(runtime.closedResponseStreams.contains(handle), isTrue);
    },
  );

  test('serves configured file HTTP routes without WAMP fallback', () async {
    final runtime = _HandleRuntime();
    final tempDir = await Directory.systemTemp.createTemp(
      'connectanum-file-route-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final file = File('${tempDir.path}${Platform.pathSeparator}hello.txt');
    await file.writeAsString('0123456789abcdef');

    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: const HttpRouteMatch(
                    prefix: '/assets',
                    methods: ['GET'],
                  ),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.file,
                    directory: tempDir.path,
                    cacheControl: 'max-age=60',
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
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

    void enqueueFileRequest({
      required int connectionId,
      required int handle,
      required String method,
      required String path,
      Map<String, String> headers = const {},
    }) {
      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: handle,
          method: method,
          target: path,
          path: path,
          protocol: 'http/1.1',
          headers: headers,
          body: Uint8List(0),
          realm: 'router.http',
          procedure: 'router.http.file',
        ),
      );
    }

    enqueueFileRequest(
      connectionId: 144,
      handle: 44,
      method: 'GET',
      path: '/assets/hello.txt',
    );
    await _waitUntil(
      () => runtime.httpResponses[144]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final getResponse = runtime.httpResponses[144]!.single;
    expect(getResponse.status, HttpStatus.ok);
    expect(getResponse.headers[HttpHeaders.contentLengthHeader], '16');
    expect(getResponse.headers[HttpHeaders.cacheControlHeader], 'max-age=60');
    expect(
      getResponse.headers[HttpHeaders.contentTypeHeader],
      'text/plain; charset=utf-8',
    );
    expect(getResponse.headers[HttpHeaders.acceptRangesHeader], 'bytes');
    final getBody = getResponse.body;
    expect(getBody, isA<NativeHttpResponseFile>());
    expect(
      await File((getBody as NativeHttpResponseFile).path).readAsString(),
      '0123456789abcdef',
    );
    final etag = getResponse.headers[HttpHeaders.etagHeader]!;
    final lastModified = getResponse.headers[HttpHeaders.lastModifiedHeader]!;

    enqueueFileRequest(
      connectionId: 148,
      handle: 48,
      method: 'GET',
      path: '/assets/hello.txt',
      headers: {HttpHeaders.ifNoneMatchHeader: etag},
    );
    await _waitUntil(
      () => runtime.httpResponses[148]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final notModifiedResponse = runtime.httpResponses[148]!.single;
    expect(notModifiedResponse.status, HttpStatus.notModified);
    expect(
      notModifiedResponse.headers,
      isNot(contains(HttpHeaders.contentLengthHeader)),
    );

    enqueueFileRequest(
      connectionId: 149,
      handle: 49,
      method: 'GET',
      path: '/assets/hello.txt',
      headers: {
        HttpHeaders.ifNoneMatchHeader: '"stale"',
        HttpHeaders.ifModifiedSinceHeader: lastModified,
      },
    );
    await _waitUntil(
      () => runtime.httpResponses[149]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final staleEtagResponse = runtime.httpResponses[149]!.single;
    expect(staleEtagResponse.status, HttpStatus.ok);

    enqueueFileRequest(
      connectionId: 145,
      handle: 45,
      method: 'HEAD',
      path: '/assets/hello.txt',
    );
    await _waitUntil(
      () => runtime.httpResponses[145]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final headResponse = runtime.httpResponses[145]!.single;
    expect(headResponse.status, HttpStatus.ok);
    expect(headResponse.headers[HttpHeaders.contentLengthHeader], '16');
    final headBody = headResponse.body;
    expect(headBody, isA<NativeHttpResponseBytes>());
    expect((headBody as NativeHttpResponseBytes).bytes, isEmpty);

    enqueueFileRequest(
      connectionId: 146,
      handle: 46,
      method: 'GET',
      path: '/assets/hello.txt',
      headers: const {HttpHeaders.rangeHeader: 'bytes=2-5'},
    );
    await _waitUntil(
      () => runtime.httpResponses[146]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final rangeResponse = runtime.httpResponses[146]!.single;
    expect(rangeResponse.status, HttpStatus.partialContent);
    expect(
      rangeResponse.headers[HttpHeaders.contentRangeHeader],
      'bytes 2-5/16',
    );
    expect(rangeResponse.headers[HttpHeaders.contentLengthHeader], '4');
    final rangeBody = rangeResponse.body;
    expect(rangeBody, isA<NativeHttpResponseBytes>());
    expect(utf8.decode((rangeBody as NativeHttpResponseBytes).bytes), '2345');

    enqueueFileRequest(
      connectionId: 147,
      handle: 47,
      method: 'GET',
      path: '/assets/%2e%2e/secret.txt',
    );
    await _waitUntil(
      () => runtime.httpResponses[147]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final traversalResponse = runtime.httpResponses[147]!.single;
    expect(traversalResponse.status, HttpStatus.notFound);
    final traversalBody = traversalResponse.body;
    expect(traversalBody, isA<NativeHttpResponseJson>());
    expect(
      (traversalBody as NativeHttpResponseJson).value,
      containsPair('reason', 'file_not_found'),
    );

    expect(
      events.any((event) => event['type'] == 'http_request_dispatched'),
      isFalse,
    );
    expect(
      events.where((event) => event['type'] == 'http_file_route_response_sent'),
      hasLength(5),
    );
  });

  group('configured file contract', () {
    for (final range in ['bytes=2-5', 'bytes=100-', 'bytes=-0']) {
      test('HEAD ignores Range $range', () async {
        final fixture = await _configuredFileFixture();
        final response = await fixture.request(
          method: 'HEAD',
          headers: {HttpHeaders.rangeHeader: range},
        );
        expect(response.status, HttpStatus.ok);
        expect(response.headers[HttpHeaders.contentLengthHeader], '16');
        expect(
          response.headers,
          isNot(contains(HttpHeaders.contentRangeHeader)),
        );
        expect((response.body as NativeHttpResponseBytes).bytes, isEmpty);
      });
    }

    for (final validator in [
      'stale tag',
      'current weak tag',
      'strong-looking current tag',
      'current date',
      'stale date',
      'future date',
      'malformed date',
      'empty',
    ]) {
      test('If-Range $validator returns the complete representation', () async {
        final fixture = await _configuredFileFixture();
        final initial = await fixture.request();
        final etag = initial.headers[HttpHeaders.etagHeader]!;
        final value = switch (validator) {
          'stale tag' => '"stale"',
          'current weak tag' => etag,
          'strong-looking current tag' => etag.substring(2),
          'current date' => initial.headers[HttpHeaders.lastModifiedHeader]!,
          'stale date' => HttpDate.format(DateTime.utc(2023)),
          'future date' => HttpDate.format(DateTime.utc(2025)),
          'malformed date' => 'not-a-date',
          _ => '',
        };
        final response = await fixture.request(
          headers: {
            HttpHeaders.rangeHeader: 'bytes=2-5',
            HttpHeaders.ifRangeHeader: value,
          },
        );
        expect(response.status, HttpStatus.ok);
        expect(response.headers[HttpHeaders.contentLengthHeader], '16');
        expect(
          response.headers,
          isNot(contains(HttpHeaders.contentRangeHeader)),
        );
        expect(response.headers[HttpHeaders.etagHeader], etag);
        final body = response.body as NativeHttpResponseFile;
        expect(await File(body.path).readAsString(), '0123456789abcdef');
      });
    }

    for (final method in ['GET', 'HEAD']) {
      for (final tagKind in ['weak', 'strong-looking', 'list', 'wildcard']) {
        test(
          '$method If-None-Match uses weak comparison for $tagKind',
          () async {
            final fixture = await _configuredFileFixture();
            final initial = await fixture.request();
            final etag = initial.headers[HttpHeaders.etagHeader]!;
            final value = switch (tagKind) {
              'weak' => etag,
              'strong-looking' => etag.substring(2),
              'list' => '"stale", ${etag.substring(2)}, "other"',
              _ => '*',
            };
            final response = await fixture.request(
              method: method,
              headers: {
                HttpHeaders.ifNoneMatchHeader: value,
                HttpHeaders.rangeHeader: 'bytes=100-',
              },
            );
            expect(response.status, HttpStatus.notModified);
            expect(response.headers[HttpHeaders.etagHeader], etag);
            expect(
              response.headers[HttpHeaders.cacheControlHeader],
              'max-age=60',
            );
            expect(
              response.headers,
              isNot(contains(HttpHeaders.contentLengthHeader)),
            );
            expect(
              response.headers,
              isNot(contains(HttpHeaders.contentRangeHeader)),
            );
            expect((response.body as NativeHttpResponseBytes).bytes, isEmpty);
          },
        );
      }
    }

    for (final (header, expected, contentRange) in [
      ('bytes=0-0', '0', 'bytes 0-0/16'),
      ('bytes=15-15', 'f', 'bytes 15-15/16'),
      ('bytes=12-', 'cdef', 'bytes 12-15/16'),
      ('bytes=12-99', 'cdef', 'bytes 12-15/16'),
      ('bytes=-4', 'cdef', 'bytes 12-15/16'),
      ('bytes=-16', '0123456789abcdef', 'bytes 0-15/16'),
      ('bytes=-99', '0123456789abcdef', 'bytes 0-15/16'),
    ]) {
      test('GET serves exact range $header', () async {
        final fixture = await _configuredFileFixture();
        final response = await fixture.request(
          headers: {HttpHeaders.rangeHeader: header},
        );
        expect(response.status, HttpStatus.partialContent);
        expect(response.headers[HttpHeaders.contentRangeHeader], contentRange);
        expect(
          response.headers[HttpHeaders.contentLengthHeader],
          '${expected.length}',
        );
        expect(
          (response.body as NativeHttpResponseBytes).bytes,
          utf8.encode(expected),
        );
      });
    }

    for (final range in [
      'bytes=16-',
      'bytes=4-2',
      'bytes=-0',
      'bytes=-x',
      'bytes=x-3',
      'bytes=1-x',
      'bytes=3',
    ]) {
      test('GET rejects unsatisfiable or malformed range $range', () async {
        final fixture = await _configuredFileFixture();
        final response = await fixture.request(
          headers: {HttpHeaders.rangeHeader: range},
        );
        expect(response.status, HttpStatus.requestedRangeNotSatisfiable);
        expect(response.headers[HttpHeaders.contentRangeHeader], 'bytes */16');
        expect(response.headers[HttpHeaders.contentLengthHeader], '0');
        expect((response.body as NativeHttpResponseBytes).bytes, isEmpty);
      });
    }

    for (final range in ['', 'items=0-1', 'bytes=', 'bytes=0-1,4-5']) {
      test('GET ignores unsupported range $range', () async {
        final fixture = await _configuredFileFixture();
        final response = await fixture.request(
          headers: {HttpHeaders.rangeHeader: range},
        );
        expect(response.status, HttpStatus.ok);
        expect(response.headers[HttpHeaders.contentLengthHeader], '16');
        expect(
          response.headers,
          isNot(contains(HttpHeaders.contentRangeHeader)),
        );
        expect(response.body, isA<NativeHttpResponseFile>());
      });
    }

    test('empty file has no satisfiable byte range', () async {
      final fixture = await _configuredFileFixture();
      await fixture.file.writeAsBytes([]);
      final response = await fixture.request(
        headers: const {HttpHeaders.rangeHeader: 'bytes=0-0'},
      );
      expect(response.status, HttpStatus.requestedRangeNotSatisfiable);
      expect(response.headers[HttpHeaders.contentRangeHeader], 'bytes */0');
      expect((response.body as NativeHttpResponseBytes).bytes, isEmpty);
    });

    for (final path in [
      '/assets',
      '/assets/',
      '/assets/.',
      '/assets/..',
      '/assets/%2Fhello.txt',
      '/assets/%5Chello.txt',
      '/assets/%00hello.txt',
      '/assets/%1Fhello.txt',
      '/assets/%7Fhello.txt',
      '/assets/%ZZ',
      '/assets/%',
      '/assets/%C3%28',
      '/assets/missing.txt',
    ]) {
      test(
        'rejects unsafe or missing path $path without disclosing storage',
        () async {
          final fixture = await _configuredFileFixture();
          final response = await fixture.request(path: path);
          expect(response.status, HttpStatus.notFound);
          final error = (response.body as NativeHttpResponseJson).value;
          expect(error, containsPair('reason', 'file_not_found'));
          expect(jsonEncode(error), isNot(contains(fixture.directory.path)));
        },
      );
    }

    for (final (date, expectedStatus) in [
      ('Mon, 04 Mar 2024 05:06:07 GMT', HttpStatus.notModified),
      ('Mon, 04 Mar 2024 05:06:08 GMT', HttpStatus.notModified),
      ('Mon, 04 Mar 2024 05:06:06 GMT', HttpStatus.ok),
      ('not-a-date', HttpStatus.ok),
      ('', HttpStatus.ok),
    ]) {
      test('If-Modified-Since $date respects HTTP date precision', () async {
        final fixture = await _configuredFileFixture();
        final response = await fixture.request(
          headers: {
            HttpHeaders.ifModifiedSinceHeader: date,
          },
        );
        expect(response.status, expectedStatus);
        expect(
          response.headers[HttpHeaders.lastModifiedHeader],
          'Mon, 04 Mar 2024 05:06:07 GMT',
        );
        if (expectedStatus == HttpStatus.notModified) {
          expect(
            response.headers,
            isNot(contains(HttpHeaders.contentLengthHeader)),
          );
          expect((response.body as NativeHttpResponseBytes).bytes, isEmpty);
        } else {
          expect(response.headers[HttpHeaders.contentLengthHeader], '16');
          expect(response.body, isA<NativeHttpResponseFile>());
        }
      });
    }

    test(
      'nonmatching ETag takes precedence over a future cache date',
      () async {
        final fixture = await _configuredFileFixture();
        final response = await fixture.request(
          headers: {
            HttpHeaders.ifNoneMatchHeader: 'W/"unrelated"',
            HttpHeaders.ifModifiedSinceHeader: HttpDate.format(
              DateTime.utc(2030),
            ),
          },
        );
        expect(response.status, HttpStatus.ok);
        expect(response.headers[HttpHeaders.contentLengthHeader], '16');
        expect(response.body, isA<NativeHttpResponseFile>());
      },
    );

    test('If-Range cannot change an ordinary request without Range', () async {
      final fixture = await _configuredFileFixture();
      final response = await fixture.request(
        headers: const {HttpHeaders.ifRangeHeader: '"stale"'},
      );
      expect(response.status, HttpStatus.ok);
      expect(response.headers[HttpHeaders.contentLengthHeader], '16');
      expect(response.body, isA<NativeHttpResponseFile>());
    });

    for (final (name, contentType) in [
      ('file.HTML', 'text/html; charset=utf-8'),
      ('file.htm', 'text/html; charset=utf-8'),
      ('file.css', 'text/css; charset=utf-8'),
      ('file.js', 'text/javascript; charset=utf-8'),
      ('file.mjs', 'text/javascript; charset=utf-8'),
      ('file.json', 'application/json'),
      ('file.svg', 'image/svg+xml'),
      ('file.png', 'image/png'),
      ('file.jpg', 'image/jpeg'),
      ('file.jpeg', 'image/jpeg'),
      ('file.gif', 'image/gif'),
      ('file.webp', 'image/webp'),
      ('file.ico', 'image/x-icon'),
      ('file.wasm', 'application/wasm'),
      ('file.pdf', 'application/pdf'),
      ('file', null),
      ('file.', null),
      ('file.unknown', null),
    ]) {
      test('file content type and binary body for $name', () async {
        final fixture = await _configuredFileFixture();
        final bytes = [0, 1, 127, 128, 255];
        await File('${fixture.directory.path}/$name').writeAsBytes(bytes);
        final response = await fixture.request(path: '/assets/$name');
        expect(response.status, HttpStatus.ok);
        if (contentType == null) {
          expect(
            response.headers,
            isNot(contains(HttpHeaders.contentTypeHeader)),
          );
        } else {
          expect(response.headers[HttpHeaders.contentTypeHeader], contentType);
        }
        expect(response.headers[HttpHeaders.contentLengthHeader], '5');
        final body = response.body as NativeHttpResponseFile;
        expect(await File(body.path).readAsBytes(), bytes);
      });
    }

    test(
      'decoded filenames and nested separators retain their content',
      () async {
        final fixture = await _configuredFileFixture();
        final nested = await Directory(
          '${fixture.directory.path}/nested',
        ).create();
        await File('${nested.path}/a b.txt').writeAsString('nested');
        final response = await fixture.request(
          path: '/assets//nested/a%20b.txt',
        );
        expect(response.status, HttpStatus.ok);
        expect(response.headers[HttpHeaders.contentLengthHeader], '6');
        expect(
          await File(
            (response.body as NativeHttpResponseFile).path,
          ).readAsString(),
          'nested',
        );
      },
    );

    test(
      'symlinks stay inside the configured root',
      () async {
        final fixture = await _configuredFileFixture();
        final sibling = await Directory(
          '${fixture.directory.path}-sibling',
        ).create();
        addTearDown(() => sibling.delete(recursive: true));
        final secret = await File(
          '${sibling.path}/secret.txt',
        ).writeAsString('outside-secret');
        await Link('${fixture.directory.path}/outside.txt').create(secret.path);
        await Link(
          '${fixture.directory.path}/inside.txt',
        ).create(fixture.file.path);
        await Link(
          '${fixture.directory.path}/dangling.txt',
        ).create('${sibling.path}/missing');
        for (final name in ['outside', 'dangling']) {
          final response = await fixture.request(path: '/assets/$name.txt');
          expect(response.status, HttpStatus.notFound);
          final error = (response.body as NativeHttpResponseJson).value;
          expect(error, containsPair('reason', 'file_not_found'));
          expect(jsonEncode(error), isNot(contains('outside-secret')));
          expect(jsonEncode(error), isNot(contains(sibling.path)));
        }
        final inside = await fixture.request(path: '/assets/inside.txt');
        expect(inside.status, HttpStatus.ok);
        expect(
          await File(
            (inside.body as NativeHttpResponseFile).path,
          ).readAsString(),
          '0123456789abcdef',
        );
      },
      skip: Platform.isWindows
          ? 'Creating symlinks requires Windows privileges.'
          : false,
    );

    test('an inaccessible configured root returns a redacted error', () async {
      final parent = await Directory.systemTemp.createTemp(
        'router-file-missing-root-',
      );
      addTearDown(() => parent.delete(recursive: true));
      final fixture = await _configuredFileFixture(
        action: HttpRouteAction(
          type: HttpRouteActionType.file,
          directory: '${parent.path}/missing',
        ),
      );
      final response = await fixture.request();
      expect(response.status, HttpStatus.internalServerError);
      final error = (response.body as NativeHttpResponseJson).value;
      expect(error, containsPair('reason', 'file_route_misconfigured'));
      expect(jsonEncode(error), isNot(contains(parent.path)));
    });

    test('directories are not returned as files', () async {
      final fixture = await _configuredFileFixture();
      await Directory('${fixture.directory.path}/nested').create();
      final response = await fixture.request(path: '/assets/nested');
      expect(response.status, HttpStatus.notFound);
      expect(
        (response.body as NativeHttpResponseJson).value,
        containsPair('reason', 'file_not_found'),
      );
    });

    test(
      'POST file request is rejected with explicit allowed methods',
      () async {
        final fixture = await _configuredFileFixture();
        final response = await fixture.request(method: 'POST');
        expect(response.status, HttpStatus.methodNotAllowed);
        expect(response.headers[HttpHeaders.allowHeader], 'GET, HEAD');
        expect(
          (response.body as NativeHttpResponseJson).value,
          containsPair('reason', 'method_not_allowed'),
        );
      },
    );
  });

  test('dispatches handler HTTP routes without WAMP fallback', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/health'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.handler,
                    delegate: 'health',
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
    );

    final events = <Map<String, Object?>>[];
    final binding = router.start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          events.add(event);
        }
      },
      httpRouteHandlers: {
        'health': (request) async {
          expect(request.method, 'POST');
          expect(request.path, '/health');
          expect(request.headers['x-test'], 'true');
          final body = utf8.decode(request.body);
          return NativeHttpResponse(
            status: 202,
            headers: const {'x-handler': 'dart'},
            body: NativeHttpResponseJson(<String, Object?>{
              'status': 'ok',
              'body': body,
            }),
          );
        },
      },
    );
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    const connectionId = 44;
    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 3,
        method: 'POST',
        target: '/health',
        path: '/health',
        protocol: 'http/1.1',
        headers: const {'x-test': 'true'},
        body: Uint8List.fromList(utf8.encode('ping')),
        realm: 'router.http',
        procedure: 'router.http.handler',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );

    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, 202);
    expect(response.headers['x-handler'], 'dart');
    final body = response.body;
    expect(body, isA<NativeHttpResponseJson>());
    expect((body as NativeHttpResponseJson).value, {
      'status': 'ok',
      'body': 'ping',
    });
    expect(
      events.any((event) => event['type'] == 'http_request_dispatched'),
      isFalse,
    );
    expect(
      events.any(
        (event) =>
            event['type'] == 'http_handler_response_sent' &&
            event['handlerId'] == 'health' &&
            event['status'] == 202,
      ),
      isTrue,
    );
  });

  test('returns structured 501 for unregistered handler HTTP routes', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/health'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.handler,
                    options: <String, Object?>{'handler': 'missing'},
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
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
    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 4,
        method: 'GET',
        target: '/health',
        path: '/health',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'router.http',
        procedure: 'router.http.handler',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );

    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, HttpStatus.notImplemented);
    final body = response.body;
    expect(body, isA<NativeHttpResponseJson>());
    expect(
      (body as NativeHttpResponseJson).value,
      containsPair('reason', 'handler_not_registered'),
    );
    expect(
      events.any((event) => event['type'] == 'http_request_dispatched'),
      isFalse,
    );
    expect(
      events.any(
        (event) =>
            event['type'] == 'http_handler_missing' &&
            event['handlerId'] == 'missing',
      ),
      isTrue,
    );
  });

  test('forwards configured FastCGI adapter routes', () async {
    final upstreamRequests = <_TestFastCgiRequest>[];
    final upstreamDone = Completer<void>();
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((socket) async {
      final request = await _readTestFastCgiRequest(socket);
      upstreamRequests.add(request);
      final responseBody = utf8.encode(
        'fastcgi:${utf8.decode(request.body)}:${request.params['REQUEST_METHOD']}:${request.params['SCRIPT_FILENAME']}:${request.params['QUERY_STRING']}',
      );
      socket
        ..add(
          _testFastCgiRecord(
            _testFastCgiStdOut,
            Uint8List.fromList([
              ...utf8.encode(
                'Status: 201 Created\r\n'
                'Content-Type: text/plain\r\n'
                'X-FastCGI: ok\r\n'
                'Connection: close\r\n'
                '\r\n',
              ),
              ...responseBody,
            ]),
          ),
        )
        ..add(_testFastCgiRecord(_testFastCgiStdOut, Uint8List(0)))
        ..add(
          _testFastCgiRecord(
            _testFastCgiEndRequest,
            Uint8List.fromList(const [0, 0, 0, 0, 0, 0, 0, 0]),
          ),
        );
      await socket.flush();
      await socket.close();
      if (!upstreamDone.isCompleted) {
        upstreamDone.complete();
      }
    });
    addTearDown(() async {
      await upstreamSubscription.cancel();
      await upstream.close();
    });

    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: const HttpRouteMatch(prefix: '/php'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.fastCgi,
                    delegate: 'tcp://${upstream.address.host}:${upstream.port}',
                    options: const <String, Object?>{
                      'document_root': '/srv/app/public',
                      'strip_prefix': true,
                      'timeout_ms': 5000,
                      'max_response_bytes': 1024 * 1024,
                    },
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
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
    const connectionId = 46;
    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 5,
        method: 'POST',
        target: '/php/index.php?active=true',
        path: '/php/index.php',
        query: 'active=true',
        protocol: 'http/1.1',
        headers: const {
          'host': 'consumer.example:8443',
          'content-type': 'text/plain',
          'connection': 'x-remove',
          'x-remove': 'secret',
          'x-test': 'yes',
        },
        body: Uint8List.fromList(utf8.encode('ping')),
        realm: 'router.http',
        procedure: 'router.http.fastcgi',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 5),
    );
    await upstreamDone.future.timeout(const Duration(seconds: 2));

    expect(upstreamRequests, hasLength(1));
    final upstreamRequest = upstreamRequests.single;
    expect(utf8.decode(upstreamRequest.body), 'ping');
    expect(upstreamRequest.params, containsPair('REQUEST_METHOD', 'POST'));
    expect(
      upstreamRequest.params,
      containsPair('REQUEST_URI', '/php/index.php?active=true'),
    );
    expect(upstreamRequest.params, containsPair('SCRIPT_NAME', '/index.php'));
    expect(
      upstreamRequest.params,
      containsPair('SCRIPT_FILENAME', '/srv/app/public/index.php'),
    );
    expect(upstreamRequest.params, containsPair('QUERY_STRING', 'active=true'));
    expect(upstreamRequest.params, containsPair('CONTENT_LENGTH', '4'));
    expect(upstreamRequest.params, containsPair('CONTENT_TYPE', 'text/plain'));
    expect(
      upstreamRequest.params,
      containsPair('SERVER_NAME', 'consumer.example'),
    );
    expect(upstreamRequest.params, containsPair('SERVER_PORT', '8443'));
    expect(upstreamRequest.params, containsPair('HTTPS', 'on'));
    expect(
      upstreamRequest.params,
      containsPair('HTTP_HOST', 'consumer.example:8443'),
    );
    expect(upstreamRequest.params, containsPair('HTTP_X_TEST', 'yes'));
    expect(upstreamRequest.params.containsKey('HTTP_X_REMOVE'), isFalse);

    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, HttpStatus.created);
    expect(response.headers, containsPair('Content-Type', 'text/plain'));
    expect(response.headers, containsPair('X-FastCGI', 'ok'));
    expect(response.headers.containsKey(HttpHeaders.connectionHeader), isFalse);
    final responseBody = response.body;
    expect(responseBody, isA<NativeHttpResponseBytes>());
    expect(
      utf8.decode((responseBody as NativeHttpResponseBytes).bytes),
      'fastcgi:ping:POST:/srv/app/public/index.php:active=true',
    );
    expect(
      events.any((event) => event['type'] == 'http_request_dispatched'),
      isFalse,
    );
    expect(
      events.any(
        (event) =>
            event['type'] == 'http_fastcgi_response_sent' &&
            event['status'] == HttpStatus.created,
      ),
      isTrue,
    );
  });

  test('FastCGI keeps independent cookies instead of comma folding', () async {
    const first = 'sid=opaque; Expires=Wed, 09 Jun 2032 10:18:14 GMT; HttpOnly';
    const second = 'language=de; Path=/; Secure';
    final result = await _fastCgiResponseFixture((socket) async {
      socket
        ..add(
          _testFastCgiRecord(
            _testFastCgiStdOut,
            Uint8List.fromList(
              utf8.encode(
                'Content-Type: text/plain\r\n'
                'Set-Cookie: $first\r\nSet-Cookie: $second\r\n\r\nok',
              ),
            ),
          ),
        )
        ..add(_testFastCgiRecord(_testFastCgiEndRequest, Uint8List(8)));
      await socket.flush();
    });
    expect(result.response.status, HttpStatus.ok);
    expect(result.response.headers['Set-Cookie'], first);
    expect(
      result.response.additionalHeaders.map(
        (entry) => (entry.key, entry.value),
      ),
      [
        ('Set-Cookie', second),
      ],
    );
    expect(
      (result.response.body as NativeHttpResponseBytes).bytes,
      utf8.encode('ok'),
    );
  });

  test(
    'FastCGI preserves repeated fields and filters all Connection tokens',
    () async {
      final result = await _fastCgiResponseFixture((socket) async {
        socket
          ..add(
            _testFastCgiRecord(
              _testFastCgiStdOut,
              Uint8List.fromList(
                utf8.encode(
                  'Status: 202 Accepted\n'
                  'Set-Cookie: first=1\nset-cookie: second=2\nSET-COOKIE: third=3\n'
                  'X-List: first\nx-list: second\n'
                  'Connection: X-Secret\nconnection: X-Other\n'
                  'X-Secret: secret\nX-Other: secret\n'
                  'Transfer-Encoding: chunked\nContent-Length: 999\n\nbinary',
                ),
              ),
            ),
          )
          ..add(_testFastCgiRecord(_testFastCgiEndRequest, Uint8List(8)));
        await socket.flush();
      });
      expect(result.response.status, 202);
      expect(result.response.headers, {
        'Set-Cookie': 'first=1',
        'X-List': 'first',
      });
      expect(
        result.response.additionalHeaders.map(
          (entry) => (entry.key, entry.value),
        ),
        [
          ('set-cookie', 'second=2'),
          ('SET-COOKIE', 'third=3'),
          ('x-list', 'second'),
        ],
      );
      expect(
        (result.response.body as NativeHttpResponseBytes).bytes,
        utf8.encode('binary'),
      );
    },
  );

  for (final separator in ['\r\n', '\n']) {
    test(
      'FastCGI assembles padded records and binary body (${separator.length})',
      () async {
        final stdout = [
          ...utf8.encode(
            'Content-Type: application/octet-stream$separator$separator',
          ),
          0,
          255,
          128,
          10,
        ];
        final result = await _fastCgiResponseFixture((socket) async {
          for (final byte in stdout) {
            // Flush record fragments independently; neither padding nor stderr
            // belongs to the CGI stdout response or its size budget.
            final record = _testFastCgiRecord(
              _testFastCgiStdOut,
              Uint8List.fromList([byte]),
            );
            record[6] = 3;
            socket.add(record.sublist(0, 5));
            await socket.flush();
            socket.add([...record.sublist(5), 255, 254, 253]);
            await socket.flush();
          }
          socket
            ..add(
              _testFastCgiRecord(
                7,
                Uint8List.fromList(utf8.encode('private stderr secret')),
              ),
            )
            ..add(_testFastCgiRecord(_testFastCgiStdOut, Uint8List(0)))
            ..add(_testFastCgiRecord(_testFastCgiEndRequest, Uint8List(8)));
          await socket.flush();
        }, options: {'max_response_bytes': stdout.length});
        expect(result.response.status, 200);
        expect(result.response.headers, {
          'Content-Type': 'application/octet-stream',
        });
        expect(result.response.additionalHeaders, isEmpty);
        expect((result.response.body as NativeHttpResponseBytes).bytes, [
          0,
          255,
          128,
          10,
        ]);
        expect(jsonEncode(result.events), isNot(contains('secret')));
      },
    );
  }

  final malformedFastCgi = <String, ({List<int> bytes, String reason})>{
    'wrong version': (
      bytes: [2, 6, 0, 1, 0, 0, 0, 0],
      reason: 'invalid_record',
    ),
    'management request id': (
      bytes: [1, 6, 0, 0, 0, 0, 0, 0],
      reason: 'invalid_record',
    ),
    'foreign request id': (
      bytes: [1, 6, 1, 1, 0, 0, 0, 0],
      reason: 'invalid_record',
    ),
    'truncated record header': (bytes: [1, 6, 0, 1], reason: 'unexpected_eof'),
    'truncated content': (
      bytes: [1, 6, 0, 1, 0, 2, 0, 0, 65],
      reason: 'unexpected_eof',
    ),
    'truncated padding': (
      bytes: [1, 6, 0, 1, 0, 0, 2, 0, 65],
      reason: 'unexpected_eof',
    ),
    'short end record': (
      bytes: _testFastCgiRecord(3, Uint8List(7)),
      reason: 'request_failed',
    ),
    'failed end status': (
      bytes: _testFastCgiRecord(
        3,
        Uint8List.fromList([0, 0, 0, 0, 1, 0, 0, 0]),
      ),
      reason: 'request_failed',
    ),
    'empty stdout': (
      bytes: _testFastCgiRecord(3, Uint8List(8)),
      reason: 'missing_headers',
    ),
  };
  for (final fixture in malformedFastCgi.entries) {
    test(
      'FastCGI rejects ${fixture.key} without leaking upstream data',
      () async {
        final result = await _fastCgiResponseFixture((socket) async {
          socket.add(fixture.value.bytes);
          await socket.flush();
          await socket.close();
        });
        expect(result.response.status, HttpStatus.badGateway);
        expect(
          _jsonResponseBody(result.response)['reason'],
          'fastcgi_protocol_error',
        );
        final errors = result.events.where(
          (event) => event['type'] == 'http_fastcgi_error',
        );
        expect(errors.single['reason'], fixture.value.reason);
        expect(errors.single.containsKey('stackTrace'), isFalse);
        expect(
          result.events.any(
            (event) => event['type'] == 'http_fastcgi_response_sent',
          ),
          isFalse,
        );
      },
    );
  }

  for (final header in [
    'Broken secret',
    ': secret',
    ' : secret',
    'Status: secret',
    'Status: 99 secret',
    'Status: 600 secret',
    'Status: 999 secret',
    'Status: 1000 secret',
  ]) {
    test(
      'FastCGI rejects invalid CGI header ${header.split(':').first}',
      () async {
        final result = await _fastCgiResponseFixture((socket) async {
          socket
            ..add(
              _testFastCgiRecord(
                6,
                Uint8List.fromList(utf8.encode('$header\r\n\r\nprivate body')),
              ),
            )
            ..add(_testFastCgiRecord(3, Uint8List(8)));
          await socket.flush();
        });
        expect(result.response.status, 502);
        expect(
          _jsonResponseBody(result.response)['reason'],
          'fastcgi_protocol_error',
        );
        expect(
          jsonEncode(_jsonResponseBody(result.response)),
          isNot(contains('secret')),
        );
        expect(jsonEncode(result.events), isNot(contains('secret')));
      },
    );
  }

  for (final status in [100, 200, 599]) {
    test('FastCGI accepts valid status boundary $status', () async {
      final result = await _fastCgiResponseFixture((socket) async {
        socket
          ..add(
            _testFastCgiRecord(
              6,
              Uint8List.fromList(utf8.encode('sTaTuS: $status\n\n')),
            ),
          )
          ..add(_testFastCgiRecord(3, Uint8List(8)));
        await socket.flush();
      });
      expect(result.response.status, status);
      expect(result.response.headers, isEmpty);
      expect((result.response.body as NativeHttpResponseBytes).bytes, isEmpty);
    });
  }

  test(
    'FastCGI invalid header encoding fails closed without exposing bytes',
    () async {
      final result = await _fastCgiResponseFixture((socket) async {
        socket
          ..add(
            _testFastCgiRecord(
              6,
              Uint8List.fromList([88, 58, 255, 13, 10, 13, 10]),
            ),
          )
          ..add(_testFastCgiRecord(3, Uint8List(8)));
        await socket.flush();
      });
      expect(result.response.status, 502);
      expect(_jsonResponseBody(result.response), {
        'status': 'error',
        'reason': 'fastcgi_failed',
        'message': 'FastCGI upstream request failed',
      });
      final error = result.events
          .where((event) => event['type'] == 'http_fastcgi_error')
          .single;
      expect(error['reason'], 'upstream_failed');
      expect(error.containsKey('error'), isFalse);
      expect(error.containsKey('stackTrace'), isFalse);
    },
  );

  test('FastCGI enforces the cumulative stdout limit', () async {
    final result = await _fastCgiResponseFixture((socket) async {
      socket
        ..add(
          _testFastCgiRecord(6, Uint8List.fromList(utf8.encode('X: y\n\n'))),
        )
        ..add(_testFastCgiRecord(6, Uint8List.fromList([1, 2, 3, 4])))
        ..add(_testFastCgiRecord(3, Uint8List(8)));
      await socket.flush();
    }, options: {'max_response_bytes': 9});
    expect(result.response.status, 502);
    expect(
      _jsonResponseBody(result.response)['reason'],
      'fastcgi_response_too_large',
    );
    expect(
      result.events
          .where((event) => event['type'] == 'http_fastcgi_error')
          .single['reason'],
      'response_too_large',
    );
  });

  test(
    'FastCGI incomplete response expires without sending partial data',
    () async {
      final result = await _fastCgiResponseFixture((socket) async {
        socket.add(
          _testFastCgiRecord(
            6,
            Uint8List.fromList(utf8.encode('X: secret\n\npartial')),
          ),
        );
        await socket.flush();
      }, options: {'timeout_ms': 50});
      expect(result.response.status, 504);
      expect(_jsonResponseBody(result.response)['reason'], 'fastcgi_timeout');
      expect(jsonEncode(result.events), isNot(contains('secret')));
      expect(
        result.events.any(
          (event) => event['type'] == 'http_fastcgi_response_sent',
        ),
        isFalse,
      );
    },
  );

  test('native HTTP repeated headers own their immutable input snapshot', () {
    final headers = {'Set-Cookie': 'first=1'};
    final additional = [const MapEntry('set-cookie', 'second=2')];
    final response = NativeHttpResponse(
      status: 200,
      headers: headers,
      additionalHeaders: additional,
      body: NativeHttpResponseBytes(Uint8List(0)),
    );
    headers.clear();
    additional.clear();
    expect(response.headers, {'Set-Cookie': 'first=1'});
    expect(response.additionalHeaders.single.value, 'second=2');
    expect(() => response.additionalHeaders.clear(), throwsUnsupportedError);
    expect(() => response.headers.clear(), throwsUnsupportedError);
  });

  test('does not leak FastCGI target details when upstream fails', () async {
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamAccepted = Completer<void>();
    final upstreamSubscription = upstream.listen((socket) {
      if (!upstreamAccepted.isCompleted) {
        upstreamAccepted.complete();
      }
      socket.destroy();
    });
    addTearDown(() async {
      await upstreamSubscription.cancel();
      await upstream.close();
    });

    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: const HttpRouteMatch(prefix: '/php'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.fastCgi,
                    delegate:
                        'fastcgi://user:secret@${upstream.address.host}:${upstream.port}/private-secret',
                    options: const <String, Object?>{
                      'script_filename': '/srv/private-secret/index.php',
                      'timeout_ms': 1000,
                    },
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
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
    const connectionId = 47;
    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 6,
        method: 'GET',
        target: '/php/secret-check',
        path: '/php/secret-check',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'router.http',
        procedure: 'router.http.fastcgi',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 5),
    );
    await upstreamAccepted.future.timeout(const Duration(seconds: 2));

    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, HttpStatus.badGateway);
    final body = response.body;
    expect(body, isA<NativeHttpResponseJson>());
    final value =
        (body as NativeHttpResponseJson).value as Map<String, Object?>;
    expect(value['reason'], anyOf('fastcgi_failed', 'fastcgi_protocol_error'));

    final errorEvent = events.singleWhere(
      (event) => event['type'] == 'http_fastcgi_error',
    );
    expect(errorEvent.containsKey('error'), isFalse);
    expect(errorEvent.containsKey('stackTrace'), isFalse);

    final serialized = jsonEncode(<Object?>[value, errorEvent]);
    expect(serialized, isNot(contains('secret')));
    expect(serialized, isNot(contains('private-secret')));
  });

  test('forwards configured reverse proxy adapter routes', () async {
    final upstreamRequests = <Map<String, Object?>>[];
    final upstreamDone = Completer<void>();
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      upstreamRequests.add({
        'method': request.method,
        'uri': request.uri.toString(),
        'host': request.headers.value(HttpHeaders.hostHeader),
        'connection': request.headers.value(HttpHeaders.connectionHeader),
        'xRemove': request.headers.value('x-remove'),
        'xTest': request.headers.value('x-test'),
        'xForwardedHost': request.headers.value('x-forwarded-host'),
        'xForwardedProto': request.headers.value('x-forwarded-proto'),
        'body': body,
      });
      request.response
        ..statusCode = 207
        ..headers.set('x-upstream', 'ok')
        ..headers.set(HttpHeaders.connectionHeader, 'close')
        ..write('proxied:$body');
      await request.response.close();
      if (!upstreamDone.isCompleted) {
        upstreamDone.complete();
      }
    });
    addTearDown(() async {
      await upstreamSubscription.cancel();
      await upstream.close(force: true);
    });

    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: const HttpRouteMatch(prefix: '/api'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.reverseProxy,
                    options: <String, Object?>{
                      'upstream':
                          'http://${upstream.address.host}:${upstream.port}/backend',
                      'strip_prefix': true,
                      'timeout_ms': 5000,
                      'max_response_bytes': 1024 * 1024,
                    },
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
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
    const connectionId = 47;
    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 6,
        method: 'POST',
        target: '/api/users?active=true',
        path: '/api/users',
        query: 'active=true',
        protocol: 'http/1.1',
        headers: const {
          'host': 'consumer.example',
          'connection': 'x-remove',
          'x-remove': 'secret',
          'x-test': 'yes',
        },
        body: Uint8List.fromList(utf8.encode('ping')),
        realm: 'router.http',
        procedure: 'router.http.reverse_proxy',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 5),
    );
    await upstreamDone.future.timeout(const Duration(seconds: 2));

    expect(upstreamRequests, hasLength(1));
    expect(upstreamRequests.single, containsPair('method', 'POST'));
    expect(
      upstreamRequests.single,
      containsPair('uri', '/backend/users?active=true'),
    );
    expect(upstreamRequests.single, containsPair('host', 'consumer.example'));
    expect(upstreamRequests.single, containsPair('connection', isNull));
    expect(upstreamRequests.single, containsPair('xRemove', isNull));
    expect(upstreamRequests.single, containsPair('xTest', 'yes'));
    expect(
      upstreamRequests.single,
      containsPair('xForwardedHost', 'consumer.example'),
    );
    expect(upstreamRequests.single, containsPair('xForwardedProto', 'https'));
    expect(upstreamRequests.single, containsPair('body', 'ping'));

    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, 207);
    expect(response.headers, containsPair('x-upstream', 'ok'));
    expect(response.headers.containsKey(HttpHeaders.connectionHeader), isFalse);
    final responseBody = response.body;
    expect(responseBody, isA<NativeHttpResponseBytes>());
    expect(
      utf8.decode((responseBody as NativeHttpResponseBytes).bytes),
      'proxied:ping',
    );
    expect(
      events.any((event) => event['type'] == 'http_request_dispatched'),
      isFalse,
    );
    expect(
      events.any(
        (event) =>
            event['type'] == 'http_reverse_proxy_response_sent' &&
            event['status'] == 207,
      ),
      isTrue,
    );
  });

  test(
    'does not leak reverse proxy target details when upstream fails',
    () async {
      final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamAccepted = Completer<void>();
      final upstreamSubscription = upstream.listen((socket) {
        if (!upstreamAccepted.isCompleted) {
          upstreamAccepted.complete();
        }
        socket.destroy();
      });
      addTearDown(() async {
        await upstreamSubscription.cancel();
        await upstream.close();
      });

      final runtime = _HandleRuntime();
      final settings = RouterSettingsBuilder()
        ..addListenerFromBuilder(
          ListenerSettingsBuilder('http', '127.0.0.1:0')
            ..addProtocol(ListenerProtocol.http)
            ..setHttpOptions(
              HttpListenerSettings(
                routes: [
                  HttpRouteSettings(
                    match: const HttpRouteMatch(prefix: '/api'),
                    action: HttpRouteAction(
                      type: HttpRouteActionType.reverseProxy,
                      options: <String, Object?>{
                        'upstream':
                            'http://user:secret@${upstream.address.host}:${upstream.port}/private-secret?token=secret',
                        'timeout_ms': 1000,
                      },
                    ),
                  ),
                ],
              ),
            ),
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
        settings: settings.build(),
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
      const connectionId = 48;
      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 7,
          method: 'GET',
          target: '/api/secret-check',
          path: '/api/secret-check',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
          realm: 'router.http',
          procedure: 'router.http.reverse_proxy',
        ),
      );

      await _waitUntil(
        () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        timeout: const Duration(seconds: 5),
      );
      await upstreamAccepted.future.timeout(const Duration(seconds: 2));

      final response = runtime.httpResponses[connectionId]!.single;
      expect(response.status, HttpStatus.badGateway);
      final body = response.body;
      expect(body, isA<NativeHttpResponseJson>());
      final value =
          (body as NativeHttpResponseJson).value as Map<String, Object?>;
      expect(value, containsPair('reason', 'reverse_proxy_failed'));

      final errorEvent = events.singleWhere(
        (event) => event['type'] == 'http_reverse_proxy_error',
      );
      expect(errorEvent, containsPair('reason', 'upstream_failed'));
      expect(errorEvent.containsKey('error'), isFalse);
      expect(errorEvent.containsKey('stackTrace'), isFalse);

      final serialized = jsonEncode(<Object?>[value, errorEvent]);
      expect(serialized, isNot(contains('secret')));
      expect(serialized, isNot(contains('private-secret')));
    },
  );

  for (final mode in ['exact', 'oversize', 'headers-timeout', 'body-timeout']) {
    test(
      'reverse proxy response boundary $mode closes upstream and recovers',
      () async {
        final upstream = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final sockets = <Socket>[];
        final closed = <Completer<void>>[];
        final payload = utf8.encode('a\u{1f30d}b');
        final subscription = upstream.listen((socket) {
          sockets.add(socket);
          final finished = Completer<void>();
          closed.add(finished);
          var request = '';
          var sent = false;
          socket.listen(
            (bytes) {
              request += ascii.decode(bytes);
              if (sent || !request.contains('\r\n\r\n')) return;
              sent = true;
              final recovery = sockets.length > 1;
              if (!recovery && mode == 'headers-timeout') return;
              final body = recovery ? utf8.encode('ok') : payload;
              socket.write(
                'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\n\r\n',
              );
              socket.add(
                !recovery && mode == 'body-timeout' ? body.sublist(0, 1) : body,
              );
            },
            onDone: () {
              finished.complete();
              socket.destroy();
            },
          );
        });
        addTearDown(() async {
          for (final socket in sockets) {
            socket.destroy();
          }
          await subscription.cancel();
          await upstream.close();
        });
        final fixture = await _ProxyResponseFixture.start({
          'upstream': 'http://127.0.0.1:${upstream.port}/private?token=secret',
          'timeout_ms': mode.endsWith('timeout') ? 1000 : 2000,
          'max_response_bytes': mode == 'oversize'
              ? payload.length - 1
              : payload.length,
        });
        final response = await fixture.request();
        if (mode == 'exact') {
          expect(response.status, HttpStatus.ok);
          expect((response.body as NativeHttpResponseBytes).bytes, payload);
        } else {
          expect(
            response.status,
            mode == 'oversize'
                ? HttpStatus.badGateway
                : HttpStatus.gatewayTimeout,
          );
          final reason = mode == 'oversize' ? 'response_too_large' : 'timeout';
          expect(
            _jsonResponseBody(response)['reason'],
            'reverse_proxy_$reason',
          );
          final error = fixture.events.singleWhere(
            (event) => event['type'] == 'http_reverse_proxy_error',
          );
          expect(error['reason'], reason);
          final serialized = jsonEncode([_jsonResponseBody(response), error]);
          expect(serialized, isNot(contains('secret')));
          expect(serialized, isNot(contains('/private')));
          expect(error.containsKey('error'), isFalse);
          expect(error.containsKey('stackTrace'), isFalse);
          expect(
            fixture.events.where(
              (event) => event['type'] == 'http_reverse_proxy_response_sent',
            ),
            isEmpty,
          );
        }
        expect(sockets, hasLength(1));
        await closed.single.future.timeout(const Duration(seconds: 2));
        final recovered = await fixture.request();
        expect(recovered.status, HttpStatus.ok);
        expect(
          (recovered.body as NativeHttpResponseBytes).bytes,
          utf8.encode('ok'),
        );
        expect(sockets, hasLength(2));
        await closed.last.future.timeout(const Duration(seconds: 2));
      },
    );
  }

  for (final (key, value, reason) in <(String, Object, String)>[
    ('timeout_ms', 0, 'invalid_option'),
    ('timeoutMs', 0.5, 'invalid_option'),
    ('max_response_bytes', -1, 'invalid_option'),
    ('maxResponseBytes', ' 0 ', 'invalid_option'),
    ('upstream', 'ftp://private.example/secret', 'invalid_target'),
    ('upstream', '/private/secret', 'invalid_target'),
  ]) {
    test(
      'reverse proxy config rejects $key=$value before connecting',
      () async {
        final upstream = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        var connections = 0;
        final subscription = upstream.listen((socket) {
          connections++;
          socket.destroy();
        });
        addTearDown(() async {
          await subscription.cancel();
          await upstream.close();
        });
        final fixture = await _ProxyResponseFixture.start({
          'upstream': 'http://127.0.0.1:${upstream.port}/private?token=secret',
          key: value,
        });
        final response = await fixture.request();
        expect(response.status, HttpStatus.badGateway);
        expect(_jsonResponseBody(response)['reason'], 'reverse_proxy_$reason');
        final error = fixture.events.singleWhere(
          (event) => event['type'] == 'http_reverse_proxy_config_error',
        );
        expect(error['reason'], reason);
        expect(connections, 0);
        expect(
          fixture.events.where(
            (event) => event['type'] == 'http_reverse_proxy_request',
          ),
          isEmpty,
        );
        final serialized = jsonEncode([_jsonResponseBody(response), error]);
        expect(serialized, isNot(contains('secret')));
        expect(serialized, isNot(contains('private')));
      },
    );
  }

  test('rate limits handler HTTP routes before handler dispatch', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/limited'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.handler,
                    delegate: 'limited',
                    rateLimit: HttpRouteRateLimitSettings(
                      maxRequests: 1,
                      windowMs: 60000,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
    );

    var handlerCalls = 0;
    final events = <Map<String, Object?>>[];
    final binding = router.start(
      runtime,
      onEvent: (event) {
        if (event is Map<String, Object?>) {
          events.add(event);
        }
      },
      httpRouteHandlers: {
        'limited': (request) async {
          handlerCalls += 1;
          return NativeHttpResponse(
            status: HttpStatus.noContent,
            body: NativeHttpResponseText(''),
          );
        },
      },
    );
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    void enqueueRequest(int connectionId, int handle) {
      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: handle,
          method: 'GET',
          target: '/limited',
          path: '/limited',
          protocol: 'http/1.1',
          headers: const {},
          body: Uint8List(0),
          realm: 'router.http',
          procedure: 'router.http.handler',
        ),
      );
    }

    enqueueRequest(46, 5);
    await _waitUntil(
      () => runtime.httpResponses[46]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    expect(runtime.httpResponses[46]!.single.status, HttpStatus.noContent);
    expect(handlerCalls, 1);

    enqueueRequest(47, 6);
    await _waitUntil(
      () => runtime.httpResponses[47]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final limitedResponse = runtime.httpResponses[47]!.single;
    expect(limitedResponse.status, 429);
    expect(limitedResponse.headers[HttpHeaders.retryAfterHeader], '60');
    expect(limitedResponse.headers['x-ratelimit-limit'], '1');
    expect(limitedResponse.headers['x-ratelimit-remaining'], '0');
    final body = limitedResponse.body;
    expect(body, isA<NativeHttpResponseJson>());
    expect(
      (body as NativeHttpResponseJson).value,
      containsPair('reason', 'rate_limited'),
    );
    expect(handlerCalls, 1);
    expect(
      events.any(
        (event) =>
            event['type'] == 'http_route_rate_limited' &&
            event['rateLimitKey'] == 'global' &&
            event['limit'] == 1,
      ),
      isTrue,
    );
  });

  test('rate limited MCP routes validate authority and origins first', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'router.http',
                    rateLimit: HttpRouteRateLimitSettings(
                      maxRequests: 1,
                      windowMs: 60000,
                    ),
                    options: <String, Object?>{
                      'allowed_origins': ['https://agent.example'],
                      'require_bearer': true,
                    },
                  ),
                ),
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp-default-origin'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'router.http',
                    rateLimit: HttpRouteRateLimitSettings(
                      maxRequests: 1,
                      windowMs: 60000,
                    ),
                    options: <String, Object?>{'require_bearer': true},
                  ),
                ),
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp-normalized-origin'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'router.http',
                    options: <String, Object?>{
                      'allowed_origins': ['HTTPS://AGENT.EXAMPLE:443'],
                      'require_bearer': true,
                    },
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    void enqueueMcpRequest({
      required int connectionId,
      required int handle,
      required String method,
      required Map<String, String> headers,
      String target = '/mcp',
      Uint8List? body,
    }) {
      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: handle,
          method: method,
          target: target,
          path: target,
          protocol: 'http/1.1',
          headers: headers,
          body: body ?? Uint8List(0),
          realm: 'router.http',
          procedure: 'router.http.mcp',
        ),
      );
    }

    void enqueuePreflight(
      int connectionId,
      int handle, {
      String origin = 'https://agent.example',
      bool repeatedAuthorization = false,
    }) {
      enqueueMcpRequest(
        connectionId: connectionId,
        handle: handle,
        method: 'OPTIONS',
        headers: {
          'origin': origin,
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'MCP-Protocol-Version',
          if (repeatedAuthorization) ...const <String, String>{
            'Authorization': 'Bearer preflight-first',
            'authorization': 'Bearer preflight-second',
          },
        },
      );
    }

    const malformedOrigins = <String>[
      'https://agent.example/untrusted-path',
      'https://user@agent.example',
      'https://agent.example?untrusted=query',
      'https://agent.example#untrusted-fragment',
      'https://agent.example:invalid',
      '//agent.example',
      'https://agent.example https://other.example',
    ];
    for (var index = 0; index < malformedOrigins.length; index++) {
      final connectionId = 90 + index;
      enqueueMcpRequest(
        connectionId: connectionId,
        handle: connectionId,
        method: 'POST',
        target: '/mcp-default-origin',
        headers: <String, String>{
          'host': 'agent.example',
          'origin': malformedOrigins[index],
          'accept': 'application/json',
          'content-type': 'application/json',
          'mcp-protocol-version': '2025-11-25',
        },
        body: Uint8List.fromList(
          utf8.encode(
            '{"jsonrpc":"2.0","id":"malformed-origin-$index","method":"tools/list","params":{}}',
          ),
        ),
      );
      await _waitUntil(
        () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        timeout: const Duration(seconds: 2),
      );
      final malformedOrigin = runtime.httpResponses[connectionId]!.single;
      expect(malformedOrigin.status, HttpStatus.forbidden);
      expect(
        malformedOrigin.headers,
        isNot(contains('Access-Control-Allow-Origin')),
      );
      expect(malformedOrigin.headers, isNot(contains('www-authenticate')));
      expect(malformedOrigin.headers, isNot(contains('x-ratelimit-limit')));
      expect(malformedOrigin.headers, isNot(contains('MCP-Session-Id')));
      expect(
        _jsonResponseBody(malformedOrigin)['error'],
        containsPair('message', 'Invalid Origin for MCP endpoint'),
      );
    }

    enqueueMcpRequest(
      connectionId: 97,
      handle: 97,
      method: 'POST',
      target: '/mcp-default-origin',
      headers: const {
        'host': 'agent.example',
        'origin': 'app://agent.example',
        'accept': 'application/json',
        'content-type': 'application/json',
        'mcp-protocol-version': '2025-11-25',
      },
      body: Uint8List.fromList(
        utf8.encode(
          '{"jsonrpc":"2.0","id":"valid-origin-reuse","method":"tools/list","params":{}}',
        ),
      ),
    );
    await _waitUntil(
      () => runtime.httpResponses[97]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final validOriginReuse = runtime.httpResponses[97]!.single;
    expect(validOriginReuse.status, HttpStatus.unauthorized);
    expect(validOriginReuse.headers, contains('www-authenticate'));
    expect(validOriginReuse.headers, isNot(contains('x-ratelimit-limit')));
    expect(validOriginReuse.headers, isNot(contains('MCP-Session-Id')));

    enqueueMcpRequest(
      connectionId: 98,
      handle: 98,
      method: 'POST',
      target: '/mcp-normalized-origin',
      headers: const {
        'host': 'router.example',
        'origin': 'https://agent.example',
        'accept': 'application/json',
        'content-type': 'application/json',
        'mcp-protocol-version': '2025-11-25',
      },
      body: Uint8List.fromList(
        utf8.encode(
          '{"jsonrpc":"2.0","id":"normalized-origin","method":"tools/list","params":{}}',
        ),
      ),
    );
    await _waitUntil(
      () => runtime.httpResponses[98]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final normalizedOrigin = runtime.httpResponses[98]!.single;
    expect(normalizedOrigin.status, HttpStatus.unauthorized);
    expect(
      normalizedOrigin.headers['Access-Control-Allow-Origin'],
      'https://agent.example',
    );
    expect(normalizedOrigin.headers, contains('www-authenticate'));
    expect(normalizedOrigin.headers, isNot(contains('x-ratelimit-limit')));
    expect(normalizedOrigin.headers, isNot(contains('MCP-Session-Id')));

    enqueueMcpRequest(
      connectionId: 99,
      handle: 99,
      method: 'POST',
      target: '/mcp-normalized-origin',
      headers: const {
        'host': 'router.example',
        'origin': 'https://agent.example:444',
        'accept': 'application/json',
        'content-type': 'application/json',
        'mcp-protocol-version': '2025-11-25',
      },
      body: Uint8List.fromList(
        utf8.encode(
          '{"jsonrpc":"2.0","id":"different-origin-port","method":"tools/list","params":{}}',
        ),
      ),
    );
    await _waitUntil(
      () => runtime.httpResponses[99]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final differentOriginPort = runtime.httpResponses[99]!.single;
    expect(differentOriginPort.status, HttpStatus.forbidden);
    expect(
      differentOriginPort.headers,
      isNot(contains('Access-Control-Allow-Origin')),
    );
    expect(differentOriginPort.headers, isNot(contains('www-authenticate')));
    expect(differentOriginPort.headers, isNot(contains('x-ratelimit-limit')));
    expect(differentOriginPort.headers, isNot(contains('MCP-Session-Id')));

    enqueueMcpRequest(
      connectionId: 60,
      handle: 19,
      method: 'POST',
      headers: const {
        'Origin': 'https://agent.example',
        'origin': 'https://rejected.example',
        'accept': 'application/json',
        'content-type': 'application/json',
        'mcp-protocol-version': '2025-11-25',
      },
      body: Uint8List.fromList(
        utf8.encode(
          '{"jsonrpc":"2.0","id":"repeated-origin","method":"tools/list","params":{}}',
        ),
      ),
    );
    await _waitUntil(
      () => runtime.httpResponses[60]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final repeatedOrigin = runtime.httpResponses[60]!.single;
    expect(repeatedOrigin.status, HttpStatus.forbidden);
    expect(
      repeatedOrigin.headers,
      isNot(contains('Access-Control-Allow-Origin')),
    );
    expect(repeatedOrigin.headers, isNot(contains('www-authenticate')));
    expect(repeatedOrigin.headers, isNot(contains('x-ratelimit-limit')));
    expect(repeatedOrigin.headers, isNot(contains('MCP-Session-Id')));
    expect(
      _jsonResponseBody(repeatedOrigin)['error'],
      containsPair('message', 'Invalid Origin for MCP endpoint'),
    );

    enqueueMcpRequest(
      connectionId: 61,
      handle: 20,
      method: 'POST',
      headers: const {
        'Host': 'agent.example',
        'host': 'rejected.example',
        'origin': 'https://agent.example',
        'accept': 'application/json',
        'content-type': 'application/json',
        'mcp-protocol-version': '2025-11-25',
      },
      body: Uint8List.fromList(
        utf8.encode(
          '{"jsonrpc":"2.0","id":"repeated-host","method":"tools/list","params":{}}',
        ),
      ),
    );
    await _waitUntil(
      () => runtime.httpResponses[61]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final repeatedHost = runtime.httpResponses[61]!.single;
    expect(repeatedHost.status, HttpStatus.badRequest);
    expect(
      repeatedHost.headers,
      isNot(contains('Access-Control-Allow-Origin')),
    );
    expect(repeatedHost.headers, isNot(contains('www-authenticate')));
    expect(repeatedHost.headers, isNot(contains('x-ratelimit-limit')));
    expect(repeatedHost.headers, isNot(contains('MCP-Session-Id')));
    expect(
      _jsonResponseBody(repeatedHost)['error'],
      containsPair('message', 'Invalid Host header'),
    );

    enqueueMcpRequest(
      connectionId: 55,
      handle: 14,
      method: 'POST',
      headers: const {
        'origin': 'https://rejected.example',
        'accept': 'application/json, text/event-stream',
        'content-type': 'application/json',
        'mcp-protocol-version': '2025-11-25',
        'Authorization': 'Bearer rejected-origin-first',
        'authorization': 'Bearer rejected-origin-second',
      },
    );
    await _waitUntil(
      () => runtime.httpResponses[55]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final rejectedBeforeAuth = runtime.httpResponses[55]!.single;
    expect(rejectedBeforeAuth.status, HttpStatus.forbidden);
    expect(rejectedBeforeAuth.headers, isNot(contains('www-authenticate')));
    expect(rejectedBeforeAuth.headers, isNot(contains('x-ratelimit-limit')));

    const repeatedAuthorizationMethods = <String>['POST', 'GET', 'DELETE'];
    for (var index = 0; index < repeatedAuthorizationMethods.length; index++) {
      final method = repeatedAuthorizationMethods[index];
      final connectionId = 56 + index;
      enqueueMcpRequest(
        connectionId: connectionId,
        handle: 15 + index,
        method: method,
        headers: <String, String>{
          'origin': 'https://agent.example',
          'accept': method == 'GET'
              ? 'text/event-stream'
              : 'application/json, text/event-stream',
          if (method == 'POST') 'content-type': 'application/json',
          'mcp-session-id': 'caller-repeated-authorization-$method',
          'mcp-protocol-version': '2025-11-25',
          'Authorization': 'Bearer duplicate-first',
          'authorization': 'Bearer duplicate-second',
        },
      );
      await _waitUntil(
        () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        timeout: const Duration(seconds: 2),
      );
      final repeatedAuthorization = runtime.httpResponses[connectionId]!.single;
      expect(
        repeatedAuthorization.status,
        HttpStatus.badRequest,
        reason: '$method repeated Authorization status',
      );
      expect(
        repeatedAuthorization.headers['Access-Control-Allow-Origin'],
        'https://agent.example',
        reason: '$method repeated Authorization CORS origin',
      );
      expect(
        repeatedAuthorization.headers,
        isNot(contains('www-authenticate')),
        reason: '$method repeated Authorization challenge',
      );
      expect(
        repeatedAuthorization.headers,
        isNot(contains('x-ratelimit-limit')),
        reason: '$method repeated Authorization rate-limit mutation',
      );
      expect(
        repeatedAuthorization.headers,
        isNot(contains('MCP-Session-Id')),
        reason: '$method repeated Authorization session reflection',
      );
      expect(
        _jsonResponseBody(repeatedAuthorization)['error'],
        containsPair('message', 'Invalid Authorization header'),
        reason: '$method repeated Authorization payload',
      );
    }

    enqueuePreflight(53, 12, origin: 'https://rejected.example');
    await _waitUntil(
      () => runtime.httpResponses[53]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final rejectedBeforeLimit = runtime.httpResponses[53]!.single;
    expect(rejectedBeforeLimit.status, HttpStatus.forbidden);
    expect(rejectedBeforeLimit.headers, isNot(contains('x-ratelimit-limit')));
    expect(rejectedBeforeLimit.headers, isNot(contains('MCP-Session-Id')));

    enqueuePreflight(48, 7, repeatedAuthorization: true);
    await _waitUntil(
      () => runtime.httpResponses[48]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final repeatedPreflight = runtime.httpResponses[48]!.single;
    expect(repeatedPreflight.status, HttpStatus.badRequest);
    expect(
      repeatedPreflight.headers['Access-Control-Allow-Origin'],
      'https://agent.example',
    );
    expect(
      repeatedPreflight.headers['Access-Control-Allow-Methods'],
      contains('POST'),
    );
    expect(
      repeatedPreflight.headers['Access-Control-Allow-Headers'],
      'MCP-Protocol-Version',
    );
    expect(repeatedPreflight.headers, isNot(contains('x-ratelimit-limit')));
    expect(repeatedPreflight.headers, isNot(contains('MCP-Session-Id')));

    enqueuePreflight(59, 18);
    await _waitUntil(
      () => runtime.httpResponses[59]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    expect(runtime.httpResponses[59]!.single.status, HttpStatus.noContent);

    enqueuePreflight(54, 13, origin: 'https://rejected.example');
    await _waitUntil(
      () => runtime.httpResponses[54]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final rejectedAfterLimit = runtime.httpResponses[54]!.single;
    expect(rejectedAfterLimit.status, HttpStatus.forbidden);
    expect(rejectedAfterLimit.headers, isNot(contains('x-ratelimit-limit')));
    expect(rejectedAfterLimit.headers, isNot(contains('MCP-Session-Id')));

    enqueuePreflight(49, 8);
    await _waitUntil(
      () => runtime.httpResponses[49]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final limitedResponse = runtime.httpResponses[49]!.single;
    expect(limitedResponse.status, 429);
    expect(
      limitedResponse.headers['Access-Control-Allow-Origin'],
      'https://agent.example',
    );
    expect(
      limitedResponse.headers['Access-Control-Allow-Methods'],
      contains('POST'),
    );
    expect(
      limitedResponse.headers['Access-Control-Allow-Headers'],
      'MCP-Protocol-Version',
    );
    expect(limitedResponse.headers['MCP-Protocol-Version'], isNotEmpty);
    final body = limitedResponse.body;
    expect(body, isA<NativeHttpResponseJson>());
    expect(
      (body as NativeHttpResponseJson).value,
      containsPair('reason', 'rate_limited'),
    );

    final requestBody = Uint8List.fromList(
      utf8.encode(
        '{"jsonrpc":"2.0","id":"rate-limited","method":"tools/list","params":{}}',
      ),
    );
    const directStaleSessionId = 'caller-rate-limited-direct';
    enqueueMcpRequest(
      connectionId: 50,
      handle: 9,
      method: 'POST',
      headers: const {
        'accept': 'application/json',
        'content-type': 'application/json',
        'mcp-session-id': directStaleSessionId,
        'mcp-protocol-version': '2025-11-25',
      },
      body: requestBody,
    );
    await _waitUntil(
      () => runtime.httpResponses[50]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final directLimitedResponse = runtime.httpResponses[50]!.single;
    expect(directLimitedResponse.status, 429);
    expect(directLimitedResponse.headers, isNot(contains('MCP-Session-Id')));
    expect(directLimitedResponse.headers, isNot(contains('mcp-session-id')));

    const streamableSessionId = 'caller-rate-limited-streamable';
    enqueueMcpRequest(
      connectionId: 51,
      handle: 10,
      method: 'POST',
      headers: const {
        'accept': 'application/json, text/event-stream',
        'content-type': 'application/json',
        'mcp-session-id': streamableSessionId,
        'mcp-protocol-version': '2025-11-25',
        'mcp-method': 'tools/list',
      },
      body: requestBody,
    );
    await _waitUntil(
      () => runtime.httpResponses[51]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final streamableLimitedResponse = runtime.httpResponses[51]!.single;
    expect(streamableLimitedResponse.status, 429);
    expect(
      streamableLimitedResponse.headers,
      isNot(contains('MCP-Session-Id')),
    );
    expect(
      streamableLimitedResponse.headers,
      isNot(contains('mcp-session-id')),
    );

    const streamableGetSessionId = 'caller-rate-limited-streamable-get';
    enqueueMcpRequest(
      connectionId: 52,
      handle: 11,
      method: 'GET',
      headers: const {
        'accept': 'text/event-stream',
        'mcp-session-id': streamableGetSessionId,
        'mcp-protocol-version': '2025-11-25',
      },
    );
    await _waitUntil(
      () => runtime.httpResponses[52]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final streamableGetLimitedResponse = runtime.httpResponses[52]!.single;
    expect(streamableGetLimitedResponse.status, 429);
    expect(
      streamableGetLimitedResponse.headers,
      isNot(contains('MCP-Session-Id')),
    );
    expect(
      streamableGetLimitedResponse.headers,
      isNot(contains('mcp-session-id')),
    );
  });

  test('bounds MCP route rate-limit buckets and reclaims expiry', () async {
    final runtime = _HandleRuntime();
    final events = <Map<String, Object?>>[];
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'router.http',
                    options: <String, Object?>{
                      'allowed_origins': ['https://agent.example'],
                    },
                  ),
                  methodActions: <String, HttpRouteAction>{
                    'POST': HttpRouteAction(
                      type: HttpRouteActionType.mcp,
                      realm: 'router.http',
                      rateLimit: HttpRouteRateLimitSettings(
                        maxRequests: 1,
                        windowMs: 2000,
                        key: 'bearer',
                        maxBuckets: 2,
                      ),
                      options: <String, Object?>{
                        'allowed_origins': ['https://agent.example'],
                      },
                    ),
                  },
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
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
    void enqueuePreflight(int connectionId, int handle, String bucket) {
      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: handle,
          method: 'OPTIONS',
          target: '/mcp',
          path: '/mcp',
          protocol: 'http/1.1',
          headers: {
            'origin': 'https://agent.example',
            'access-control-request-method': 'POST',
            HttpHeaders.authorizationHeader: 'Bearer $bucket',
            HttpHeaders.cookieHeader: 'session=$bucket',
            'last-event-id': 'cursor-$bucket',
            'mcp-session-id': 'session-$bucket',
            'x-api-key': 'api-key-$bucket',
          },
          body: Uint8List(0),
          realm: 'router.http',
          procedure: 'router.http.mcp',
        ),
      );
    }

    enqueuePreflight(60, 20, 'consumer-a');
    enqueuePreflight(61, 21, 'consumer-b');
    enqueuePreflight(62, 22, 'consumer-c');
    await _waitUntil(
      () => [60, 61, 62].every(
        (connectionId) =>
            runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      ),
      timeout: const Duration(seconds: 2),
    );
    expect(runtime.httpResponses[60]!.single.status, HttpStatus.noContent);
    expect(runtime.httpResponses[61]!.single.status, HttpStatus.noContent);
    final capacityResponse = runtime.httpResponses[62]!.single;
    expect(capacityResponse.status, 429);
    expect(capacityResponse.headers, isNot(contains('MCP-Session-Id')));
    expect(capacityResponse.headers['x-ratelimit-limit'], '1');
    expect(
      events,
      contains(
        allOf(
          containsPair('type', 'http_route_rate_limited'),
          containsPair('bucketCapacityExhausted', true),
          containsPair('maxBuckets', 2),
        ),
      ),
    );

    enqueuePreflight(63, 23, 'consumer-a');
    await _waitUntil(
      () => runtime.httpResponses[63]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    expect(runtime.httpResponses[63]!.single.status, 429);
    final encodedEvents = jsonEncode(events);
    expect(encodedEvents, isNot(contains('consumer-a')));
    expect(encodedEvents, isNot(contains('consumer-b')));
    expect(encodedEvents, isNot(contains('consumer-c')));
    final firstRequestEvent = events.firstWhere(
      (event) =>
          event['type'] == 'listener_http_request' &&
          event['connectionId'] == 60,
    );
    expect(
      firstRequestEvent['headers'],
      allOf(
        containsPair(HttpHeaders.authorizationHeader, '<redacted>'),
        containsPair(HttpHeaders.cookieHeader, '<redacted>'),
        containsPair('last-event-id', '<redacted>'),
        containsPair('mcp-session-id', '<redacted>'),
        containsPair('x-api-key', '<redacted>'),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 2100));
    enqueuePreflight(64, 24, 'consumer-c');
    await _waitUntil(
      () => runtime.httpResponses[64]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    expect(runtime.httpResponses[64]!.single.status, HttpStatus.noContent);
  });

  test(
    'rejects repeated MCP CORS request methods before action selection',
    () async {
      final runtime = _HandleRuntime();
      final settings = RouterSettingsBuilder()
        ..addListenerFromBuilder(
          ListenerSettingsBuilder('http', '127.0.0.1:0')
            ..addProtocol(ListenerProtocol.http)
            ..setHttpOptions(
              const HttpListenerSettings(
                routes: [
                  HttpRouteSettings(
                    match: HttpRouteMatch(path: '/mcp', methods: ['GET']),
                    action: HttpRouteAction(
                      type: HttpRouteActionType.rpc,
                      realm: 'router.http',
                      procedure: 'com.example.http.health',
                    ),
                    methodActions: <String, HttpRouteAction>{
                      'POST': HttpRouteAction(
                        type: HttpRouteActionType.mcp,
                        realm: 'router.http',
                        options: <String, Object?>{
                          'allowed_origins': ['https://agent.example'],
                        },
                      ),
                    },
                  ),
                ],
              ),
            ),
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
        settings: settings.build(),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      void enqueuePreflight(
        int connectionId,
        int handle,
        Map<String, String> headers,
      ) {
        runtime.setConnectionProtocol(
          connectionId,
          NativeConnectionProtocol.http,
        );
        runtime.enqueueHttpHandshake(
          listenerId,
          connectionId,
          NativeHttpHandshake.synthetic(
            handle: handle,
            method: 'OPTIONS',
            target: '/mcp',
            path: '/mcp',
            protocol: 'http/1.1',
            headers: headers,
            body: Uint8List(0),
            realm: 'router.http',
            procedure: 'router.http.mcp',
          ),
        );
      }

      enqueuePreflight(65, 24, const <String, String>{
        'origin': 'https://agent.example',
        'access-control-request-method': 'POST',
        'Access-Control-Request-Method': 'DELETE',
        'access-control-request-headers': 'Content-Type, MCP-Protocol-Version',
      });
      await _waitUntil(
        () => runtime.httpResponses[65]?.isNotEmpty ?? false,
        timeout: const Duration(seconds: 2),
      );
      final rejected = runtime.httpResponses[65]!.single;
      expect(rejected.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(rejected)['error'],
        containsPair(
          'message',
          'Invalid Access-Control-Request-Method header',
        ),
      );
      expect(
        rejected.headers,
        isNot(contains('Access-Control-Allow-Methods')),
      );
      expect(rejected.headers, isNot(contains('MCP-Session-Id')));

      enqueuePreflight(66, 25, const <String, String>{
        'origin': 'https://agent.example',
        'access-control-request-method': 'POST',
        'access-control-request-headers': 'Content-Type, MCP-Protocol-Version',
      });
      await _waitUntil(
        () => runtime.httpResponses[66]?.isNotEmpty ?? false,
        timeout: const Duration(seconds: 2),
      );
      final valid = runtime.httpResponses[66]!.single;
      expect(valid.status, HttpStatus.noContent);
      expect(
        valid.headers['Access-Control-Allow-Methods'],
        contains('POST'),
      );
      expect(valid.headers, isNot(contains('MCP-Session-Id')));
    },
  );

  test('MCP wildcard CORS preflights vary by requested headers', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'router.http',
                    options: <String, Object?>{
                      'allowed_origins': ['*'],
                    },
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    runtime.setConnectionProtocol(52, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      52,
      NativeHttpHandshake.synthetic(
        handle: 11,
        method: 'OPTIONS',
        target: '/mcp',
        path: '/mcp',
        protocol: 'http/1.1',
        headers: const {
          'origin': 'https://consumer.example',
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'Authorization, Content-Type',
          'Access-Control-Request-Headers':
              'Mcp-Method, Mcp-Name, '
              'MCP-Protocol-Version, MCP-Session-Id',
        },
        body: Uint8List(0),
        realm: 'router.http',
        procedure: 'router.http.mcp',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[52]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final response = runtime.httpResponses[52]!.single;
    expect(response.status, HttpStatus.noContent);
    expect(response.headers['Access-Control-Allow-Origin'], '*');
    expect(
      response.headers['Access-Control-Allow-Headers'],
      'Authorization, Content-Type, Mcp-Method, Mcp-Name, '
      'MCP-Protocol-Version, MCP-Session-Id',
    );
    expect(
      response.headers[HttpHeaders.varyHeader],
      'Access-Control-Request-Headers',
    );
  });

  test('rate limited MCP routes allow Streamable DELETE cleanup', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addAuthenticator(
        'anonymous',
        const AuthenticatorDefinition(type: 'anonymous'),
      )
      ..addRealmFromBuilder(
        RealmSettingsBuilder('router.http')
          ..addAuthMethod('anonymous')
          ..addRoleFromBuilder(
            RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
              PermissionSettingsBuilder('')
                ..setMatchPolicy(PermissionMatchPolicy.prefix)
                ..allowOperations(const [
                  'call',
                  'publish',
                  'subscribe',
                  'unsubscribe',
                ]),
            ),
          ),
      )
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'router.http',
                    rateLimit: HttpRouteRateLimitSettings(
                      maxRequests: 1,
                      windowMs: 60000,
                    ),
                    options: <String, Object?>{
                      'allowed_origins': ['https://agent.example'],
                    },
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    void enqueueMcpRequest({
      required int connectionId,
      required int handle,
      required String method,
      required Map<String, String> headers,
      Uint8List? body,
    }) {
      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: handle,
          method: method,
          target: '/mcp',
          path: '/mcp',
          protocol: 'http/1.1',
          headers: headers,
          body: body ?? Uint8List(0),
          realm: 'router.http',
          procedure: 'router.http.mcp',
        ),
      );
    }

    final initializeBody = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 'initialize-rate-limited-session',
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
            'clientInfo': {
              'name': 'router-runtime-rate-limit-delete-test',
              'version': '0.1.0',
            },
          },
        }),
      ),
    );
    enqueueMcpRequest(
      connectionId: 52,
      handle: 11,
      method: 'POST',
      headers: const {
        'origin': 'https://agent.example',
        'accept': 'application/json, text/event-stream',
        'content-type': 'application/json',
        'mcp-protocol-version': '2025-11-25',
        'mcp-method': 'initialize',
      },
      body: initializeBody,
    );
    await _waitUntil(
      () => runtime.httpResponses[52]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final initializeResponse = runtime.httpResponses[52]!.single;
    expect(initializeResponse.status, HttpStatus.ok);
    final sessionId = initializeResponse.headers['MCP-Session-Id'];
    expect(sessionId, isNotNull);
    expect(sessionId, isNotEmpty);

    final toolsBody = Uint8List.fromList(
      utf8.encode(
        '{"jsonrpc":"2.0","id":"limited-tools","method":"tools/list","params":{}}',
      ),
    );
    enqueueMcpRequest(
      connectionId: 53,
      handle: 12,
      method: 'POST',
      headers: {
        'origin': 'https://agent.example',
        'accept': 'application/json, text/event-stream',
        'content-type': 'application/json',
        'mcp-session-id': sessionId!,
        'mcp-protocol-version': '2025-11-25',
        'mcp-method': 'tools/list',
      },
      body: toolsBody,
    );
    await _waitUntil(
      () => runtime.httpResponses[53]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final limitedResponse = runtime.httpResponses[53]!.single;
    expect(limitedResponse.status, 429);
    expect(limitedResponse.headers, isNot(contains('MCP-Session-Id')));
    expect(limitedResponse.headers, isNot(contains('mcp-session-id')));

    enqueueMcpRequest(
      connectionId: 54,
      handle: 13,
      method: 'DELETE',
      headers: {
        'origin': 'https://agent.example',
        'accept': 'application/json, text/event-stream',
        'mcp-session-id': sessionId,
        'mcp-protocol-version': '2025-11-25',
      },
    );
    await _waitUntil(
      () => runtime.httpResponses[54]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 2),
    );
    final deleteResponse = runtime.httpResponses[54]!.single;
    expect(deleteResponse.status, HttpStatus.accepted);
    expect(deleteResponse.headers['MCP-Session-Id'], sessionId);
    expect(deleteResponse.headers, isNot(contains('x-ratelimit-limit')));
  });

  test('refreshes and disables Streamable MCP idle expiry', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addAuthenticator(
        'anonymous',
        const AuthenticatorDefinition(type: 'anonymous'),
      )
      ..addRealmFromBuilder(
        RealmSettingsBuilder('router.http')
          ..addAuthMethod('anonymous')
          ..addRoleFromBuilder(
            RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
              PermissionSettingsBuilder('')
                ..setMatchPolicy(PermissionMatchPolicy.prefix)
                ..allowOperations(const [
                  'call',
                  'publish',
                  'subscribe',
                  'unsubscribe',
                ]),
            ),
          ),
      )
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'router.http',
                    options: <String, Object?>{
                      'post_response_transport': 'json',
                      'session_idle_timeout_ms': 1000,
                      'procedures': <Object?>[
                        <String, Object?>{
                          'procedure': 'app.safe.header_lookup',
                          'description': 'Lookup with mirrored parameter data.',
                          'input_schema': <String, Object?>{
                            'type': 'object',
                            'properties': <String, Object?>{
                              'taskId': <String, Object?>{
                                'type': 'string',
                                'x-mcp-header': 'task-id',
                              },
                            },
                          },
                        },
                      ],
                    },
                  ),
                ),
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp/no-expiry'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'router.http',
                    options: <String, Object?>{
                      'post_response_transport': 'json',
                      'session_idle_timeout_ms': 0,
                    },
                  ),
                ),
              ],
            ),
          ),
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
      settings: settings.build(),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    var connectionId = 150;
    var handle = 20;

    Future<NativeHttpResponse> sendMcpRequest({
      required String method,
      required Map<String, String> headers,
      String path = '/mcp',
      Uint8List? body,
    }) async {
      final requestConnectionId = connectionId++;
      runtime.setConnectionProtocol(
        requestConnectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        requestConnectionId,
        NativeHttpHandshake.synthetic(
          handle: handle++,
          method: method,
          target: path,
          path: path,
          protocol: 'http/1.1',
          headers: headers,
          body: body ?? Uint8List(0),
          realm: 'router.http',
          procedure: 'router.http.mcp',
        ),
      );
      await _waitUntil(
        () => runtime.httpResponses[requestConnectionId]?.isNotEmpty ?? false,
        timeout: const Duration(seconds: 2),
      );
      return runtime.httpResponses[requestConnectionId]!.single;
    }

    final initializeBody = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 'initialize-idle-session',
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
            'clientInfo': {
              'name': 'router-runtime-idle-session-test',
              'version': '0.1.0',
            },
          },
        }),
      ),
    );
    final initializeHeaders = <String, String>{
      'accept': 'application/json, text/event-stream',
      'content-type': 'application/json',
      'mcp-protocol-version': '2025-11-25',
      'mcp-method': 'initialize',
    };
    final initializeResponse = await sendMcpRequest(
      method: 'POST',
      headers: initializeHeaders,
      body: initializeBody,
    );
    expect(initializeResponse.status, HttpStatus.ok);
    final expiredSessionId = initializeResponse.headers['MCP-Session-Id'];
    expect(expiredSessionId, isNotNull);
    expect(expiredSessionId, isNotEmpty);

    final toolsBody = Uint8List.fromList(
      utf8.encode(
        '{"jsonrpc":"2.0","id":"expired-tools","method":"tools/list","params":{}}',
      ),
    );
    final sessionHeaders = <String, String>{
      'accept': 'application/json, text/event-stream',
      'content-type': 'application/json',
      'mcp-session-id': expiredSessionId!,
      'mcp-protocol-version': '2025-11-25',
      'mcp-method': 'tools/list',
    };

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final firstActiveResponse = await sendMcpRequest(
      method: 'POST',
      headers: sessionHeaders,
      body: toolsBody,
    );
    expect(firstActiveResponse.status, HttpStatus.ok);
    expect(firstActiveResponse.headers['MCP-Session-Id'], expiredSessionId);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final secondActiveResponse = await sendMcpRequest(
      method: 'POST',
      headers: sessionHeaders,
      body: toolsBody,
    );
    expect(secondActiveResponse.status, HttpStatus.ok);
    expect(secondActiveResponse.headers['MCP-Session-Id'], expiredSessionId);

    final invalidPollHeaders = <String, String>{
      'accept': 'text/event-stream',
      'mcp-session-id': expiredSessionId,
      'mcp-protocol-version': '2025-11-25',
      'last-event-id': 'cursor\nnext',
    };
    final unknownInvalidPollResponse = await sendMcpRequest(
      method: 'GET',
      headers: <String, String>{
        ...invalidPollHeaders,
        'mcp-session-id': 'unknown-session',
      },
    );
    expect(unknownInvalidPollResponse.status, HttpStatus.notFound);
    expect(
      unknownInvalidPollResponse.headers,
      isNot(contains('MCP-Session-Id')),
    );

    for (var attempt = 0; attempt < 2; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final invalidPollResponse = await sendMcpRequest(
        method: 'GET',
        headers: invalidPollHeaders,
      );
      expect(invalidPollResponse.status, HttpStatus.badRequest);
      expect(
        jsonEncode(_jsonResponseBody(invalidPollResponse)),
        contains('Invalid Last-Event-ID header'),
      );
    }

    final mismatchedToolResponse = await sendMcpRequest(
      method: 'POST',
      headers: <String, String>{
        ...sessionHeaders,
        'mcp-method': 'tools/call',
        'mcp-name': 'app.safe.header_lookup',
        'mcp-param-task-id': 'task-2',
      },
      body: Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 'mismatched-tool-headers',
            'method': 'tools/call',
            'params': <String, Object?>{
              'name': 'app.safe.header_lookup',
              'arguments': <String, Object?>{'taskId': 'task-1'},
            },
          }),
        ),
      ),
    );
    expect(mismatchedToolResponse.status, HttpStatus.badRequest);
    expect(
      jsonEncode(_jsonResponseBody(mismatchedToolResponse)),
      contains("does not match body value 'task-1'"),
    );

    await Future<void>.delayed(const Duration(milliseconds: 750));

    final expiredResponse = await sendMcpRequest(
      method: 'POST',
      headers: sessionHeaders,
      body: toolsBody,
    );
    expect(expiredResponse.status, HttpStatus.notFound);
    expect(
      jsonEncode(_jsonResponseBody(expiredResponse)),
      contains('Unknown MCP HTTP session'),
    );

    final replacementInitialize = await sendMcpRequest(
      method: 'POST',
      headers: initializeHeaders,
      body: initializeBody,
    );
    expect(replacementInitialize.status, HttpStatus.ok);
    final replacementSessionId =
        replacementInitialize.headers['MCP-Session-Id'];
    expect(replacementSessionId, isNotNull);
    expect(replacementSessionId, isNot(equals(expiredSessionId)));

    final replacementTools = await sendMcpRequest(
      method: 'POST',
      headers: {
        'accept': 'application/json, text/event-stream',
        'content-type': 'application/json',
        'mcp-session-id': replacementSessionId!,
        'mcp-protocol-version': '2025-11-25',
        'mcp-method': 'tools/list',
      },
      body: toolsBody,
    );
    expect(replacementTools.status, HttpStatus.ok);
    expect(replacementTools.headers['MCP-Session-Id'], replacementSessionId);

    final disabledInitialize = await sendMcpRequest(
      method: 'POST',
      path: '/mcp/no-expiry',
      headers: initializeHeaders,
      body: initializeBody,
    );
    expect(disabledInitialize.status, HttpStatus.ok);
    final disabledSessionId = disabledInitialize.headers['MCP-Session-Id'];
    expect(disabledSessionId, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 1150));

    final disabledTools = await sendMcpRequest(
      method: 'POST',
      path: '/mcp/no-expiry',
      headers: {
        'accept': 'application/json, text/event-stream',
        'content-type': 'application/json',
        'mcp-session-id': disabledSessionId!,
        'mcp-protocol-version': '2025-11-25',
        'mcp-method': 'tools/list',
      },
      body: toolsBody,
    );
    expect(disabledTools.status, HttpStatus.ok);
    expect(disabledTools.headers['MCP-Session-Id'], disabledSessionId);

    final disabledDelete = await sendMcpRequest(
      method: 'DELETE',
      path: '/mcp/no-expiry',
      headers: {
        'accept': 'application/json, text/event-stream',
        'mcp-session-id': disabledSessionId,
        'mcp-protocol-version': '2025-11-25',
      },
    );
    expect(disabledDelete.status, HttpStatus.accepted);
  });

  test('rejects repeated MCP request metadata headers', () async {
    final runtime = _HandleRuntime();
    final settings = RouterSettingsBuilder()
      ..addAuthenticator(
        'anonymous',
        const AuthenticatorDefinition(type: 'anonymous'),
      )
      ..addRealmFromBuilder(
        RealmSettingsBuilder('router.http')
          ..addAuthMethod('anonymous')
          ..addRoleFromBuilder(
            RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
              PermissionSettingsBuilder('')
                ..setMatchPolicy(PermissionMatchPolicy.prefix)
                ..allowOperations(const ['call']),
            ),
          ),
      )
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(
            const HttpListenerSettings(
              routes: <HttpRouteSettings>[
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'router.http',
                    options: <String, Object?>{
                      'post_response_transport': 'json',
                      'resources': <Object?>[
                        <String, Object?>{
                          'uri': 'app://mcp/context',
                          'name': 'context',
                          'text': 'consumer context',
                        },
                      ],
                    },
                  ),
                ),
              ],
            ),
          ),
      );
    final router = Router(
      RouterConfig(
        endpoints: <Endpoint>[
          Endpoint(
            host: '127.0.0.1',
            port: 0,
            tlsMode: TlsMode.native,
            maxRawSocketSizeExponent: 16,
            sniCertificates: <SniCertificate>[_cert('localhost')],
          ),
        ],
      ),
      settings: settings.build(),
    );
    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    var connectionId = 180;
    var handle = 40;

    Future<NativeHttpResponse> post(
      Object body,
      Map<String, String> metadataHeaders,
    ) async {
      final requestConnectionId = connectionId++;
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: requestConnectionId,
        handle: handle++,
        method: 'POST',
        target: '/mcp',
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.contentTypeHeader: 'application/json',
          'MCP-Protocol-Version': '2025-11-25',
          ...metadataHeaders,
        },
        body: body,
        realm: 'router.http',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(
        () => runtime.httpResponses[requestConnectionId]?.isNotEmpty ?? false,
        timeout: const Duration(seconds: 2),
      );
      return runtime.httpResponses[requestConnectionId]!.single;
    }

    final repeatedMethod = await post(
      const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'repeated-method',
        'method': 'tools/list',
        'params': <String, Object?>{},
      },
      const <String, String>{
        'Mcp-Method': 'tools/list',
        'mcp-method': 'resources/list',
      },
    );
    expect(repeatedMethod.status, HttpStatus.badRequest);
    expect(
      jsonEncode(_jsonResponseBody(repeatedMethod)),
      contains('Invalid Mcp-Method header'),
    );
    expect(repeatedMethod.headers, isNot(contains('MCP-Session-Id')));

    final repeatedName = await post(
      const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'repeated-name',
        'method': 'resources/read',
        'params': <String, Object?>{'uri': 'app://mcp/context'},
      },
      const <String, String>{
        'Mcp-Method': 'resources/read',
        'Mcp-Name': 'app://mcp/context',
        'mcp-name': 'app://mcp/other',
      },
    );
    expect(repeatedName.status, HttpStatus.badRequest);
    expect(
      jsonEncode(_jsonResponseBody(repeatedName)),
      contains('Invalid Mcp-Name header'),
    );
    expect(repeatedName.headers, isNot(contains('MCP-Session-Id')));

    final validResponse = await post(
      const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'valid-after-repeated-metadata',
        'method': 'resources/read',
        'params': <String, Object?>{'uri': 'app://mcp/context'},
      },
      const <String, String>{
        'Mcp-Method': 'resources/read',
        'Mcp-Name': 'app://mcp/context',
      },
    );
    expect(validResponse.status, HttpStatus.ok);
    expect(
      jsonEncode(_jsonResponseBody(validResponse)),
      contains('consumer context'),
    );
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

  for (final publish in [false, true]) {
    test(
      'HTTP profile auth guards ${publish ? 'publish' : 'RPC'} without transport bearer enforcement',
      () async {
        final runtime = _HandleRuntime();
        final events = <Map<String, Object?>>[];
        final binding =
            Router(
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
              settings: _buildRouterSettingsWithHttpAuthBridge(
                secureRouteOptions: const {'require_bearer': false},
                enableProtectedPublish: true,
              ),
            ).start(
              runtime,
              onEvent: (event) {
                if (event is Map<String, Object?>) events.add(event);
              },
            );
        addTearDown(binding.dispose);
        await Future<void>.delayed(Duration.zero);
        final listenerId = binding.listeners.single.listenerId;
        final service = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'service',
          authRole: 'internal',
        );
        addTearDown(service.close);
        var calls = 0;
        final publications = <Event>[];
        final registration = await service.register('com.example.api.secure');
        registration.onInvoke((invocation) {
          calls++;
          HttpInvocationContext.maybeFromInvocation(
            invocation,
          )!.sendText(body: 'authenticated', status: HttpStatus.ok);
        });
        final subscription = await service.subscribe('com.example.events');
        subscription.onEvent(publications.add);

        var nextConnection = 2400;
        Future<NativeHttpResponse> send(
          Map<String, String> headers, {
          bool expectDenied = false,
        }) async {
          final id = nextConnection++;
          _enqueueSyntheticHttpRequest(
            runtime: runtime,
            listenerId: listenerId,
            connectionId: id,
            handle: id,
            method: 'POST',
            target: publish ? '/api/events' : '/api/secure',
            headers: headers,
            body: const {'message': 'authorized-only'},
            realm: 'realm1',
            procedure: publish
                ? 'router.http.publish'
                : 'com.example.api.secure',
          );
          if (expectDenied) {
            Iterable<Map<String, Object?>> unexpectedActivity() => events.where(
              (event) =>
                  event['connectionId'] == id &&
                  const [
                    'http_request_session_error',
                    'http_publish_session_error',
                    'http_request_dispatched',
                    'http_publish_dispatched',
                  ].contains(event['type']),
            );
            await _waitUntil(
              () =>
                  (runtime.httpResponses[id]?.isNotEmpty ?? false) ||
                  unexpectedActivity().isNotEmpty,
            );
            expect(
              unexpectedActivity(),
              isEmpty,
              reason:
                  'Unauthenticated requests must be rejected before session creation or dispatch',
            );
          }
          await _waitUntil(
            () => runtime.httpResponses[id]?.isNotEmpty ?? false,
          );
          return runtime.httpResponses[id]!.single;
        }

        for (final headers in <Map<String, String>>[
          const {},
          const {'authorization': 'Basic credentials'},
          const {'authorization': 'Bearer '},
        ]) {
          final denied = await send(headers, expectDenied: true);
          expect(denied.status, HttpStatus.unauthorized);
          expect(
            _jsonResponseBody(denied),
            containsPair('message', 'Bearer token required'),
          );
          expect(calls, 0);
          expect(publications, isEmpty);
          expect(
            events.where(
              (event) =>
                  event['type'] == 'http_request_dispatched' ||
                  event['type'] == 'http_publish_dispatched',
            ),
            isEmpty,
          );
        }

        final tokens = await _issueTicketHttpTokens(
          runtime: runtime,
          listenerId: listenerId,
        );
        final allowed = await send({
          'authorization': 'Bearer ${tokens.accessToken}',
        });
        expect(allowed.status, publish ? HttpStatus.accepted : HttpStatus.ok);
        if (publish) {
          await _waitUntil(() => publications.isNotEmpty);
          expect(publications, hasLength(1));
          final http = publications.single.argumentsKeywords!['_http'] as Map;
          expect(jsonDecode(utf8.decode(http['body'] as Uint8List)), {
            'message': 'authorized-only',
          });
          expect(calls, 0);
        } else {
          expect(calls, 1);
          expect(
            (allowed.body as NativeHttpResponseText).text,
            'authenticated',
          );
          expect(publications, isEmpty);
        }
      },
    );
  }

  for (final restrictRealm in [false, true]) {
    test(
      'HTTP auth rejects method excluded by ${restrictRealm ? 'realm' : 'profile'} before challenge',
      () async {
        var settings = _buildRouterSettingsWithHttpAuthBridge(
          maxPendingAuth: 1,
          profileAuthMethods: restrictRealm
              ? const ['ticket', 'wampcra', 'scram']
              : const ['ticket'],
        );
        if (restrictRealm) {
          final realm = settings.realms.single;
          settings = settings.copyWith(
            realms: [
              RealmSettings(
                name: realm.name,
                auth: RealmAuthSettings(
                  methods: const ['ticket'],
                  methodOptions: realm.auth.methodOptions,
                ),
                roles: realm.roles,
                limits: realm.limits,
              ),
            ],
          );
        }
        final runtime = _HandleRuntime();
        final events = <Map<String, Object?>>[];
        final binding =
            Router(
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
            ).start(
              runtime,
              onEvent: (event) {
                if (event is Map<String, Object?>) events.add(event);
              },
            );
        addTearDown(binding.dispose);
        await Future<void>.delayed(Duration.zero);
        final listenerId = binding.listeners.single.listenerId;
        for (var id = 2500; id < 2503; id++) {
          _enqueueSyntheticHttpRequest(
            runtime: runtime,
            listenerId: listenerId,
            connectionId: id,
            handle: id,
            method: 'POST',
            target: '/auth',
            headers: const {'content-type': 'application/json'},
            body: const {
              'realm': 'realm1',
              'authmethod': 'wampcra',
              'authid': 'user-1',
            },
            realm: 'router.http',
            procedure: 'router.http.auth',
          );
          await _waitUntil(
            () => runtime.httpResponses[id]?.isNotEmpty ?? false,
          );
          final response = runtime.httpResponses[id]!.single;
          expect(response.status, HttpStatus.unauthorized);
          final body = _jsonResponseBody(response);
          expect(body['reason'], 'unsupported_authmethod');
          expect(
            body['message'],
            restrictRealm
                ? 'authmethod wampcra is not enabled for realm realm1'
                : 'authmethod wampcra is not allowed for this route',
          );
          expect(body, isNot(contains('state')));
          expect(body, isNot(contains('access_token')));
          expect(body, isNot(contains('challenge')));
        }
        expect(
          events.where(
            (event) =>
                event['type'] == 'http_auth_capacity_exhausted' ||
                event['type'] == 'http_auth_locked_out',
          ),
          isEmpty,
        );
        // Denied methods must neither consume pending capacity nor lock out a user.
        final tokens = await _issueTicketHttpTokens(
          runtime: runtime,
          listenerId: listenerId,
        );
        expect(tokens.accessToken, isNotEmpty);
        expect(tokens.refreshToken, isNotEmpty);
      },
    );
  }

  test(
    'HTTP grants recheck changed profile policy before use and refresh',
    () async {
      final methods = <String>['ticket', 'wampcra'];
      final base = _buildRouterSettingsWithHttpAuthBridge();
      final settings = base.copyWith(
        sessionProfiles: [
          for (final profile in base.sessionProfiles)
            if (profile.name == 'http-ticket')
              SessionProfileSettings(
                name: profile.name,
                realm: profile.realm,
                auth: SessionProfileAuthSettings(methods: methods),
              )
            else
              profile,
        ],
      );
      final runtime = _HandleRuntime();
      final binding = Router(
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
      ).start(runtime);
      addTearDown(binding.dispose);
      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      final service = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'service',
        authRole: 'internal',
      );
      addTearDown(service.close);
      var calls = 0;
      final registration = await service.register('com.example.api.secure');
      registration.onInvoke((invocation) {
        calls++;
        HttpInvocationContext.maybeFromInvocation(
          invocation,
        )!.sendText(body: 'authenticated', status: HttpStatus.ok);
      });
      final tokens = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
      );
      var nextConnection = 2600;
      Future<NativeHttpResponse> send({bool refresh = false}) async {
        final id = nextConnection++;
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: id,
          handle: id,
          method: 'POST',
          target: refresh ? '/auth' : '/api/secure',
          headers: {
            'content-type': 'application/json',
            if (!refresh) 'authorization': 'Bearer ${tokens.accessToken}',
          },
          body: refresh
              ? {
                  'grant_type': 'refresh_token',
                  'refresh_token': tokens.refreshToken,
                }
              : null,
          realm: 'realm1',
          procedure: refresh ? 'router.http.auth' : 'com.example.api.secure',
        );
        await _waitUntil(() => runtime.httpResponses[id]?.isNotEmpty ?? false);
        return runtime.httpResponses[id]!.single;
      }

      // Populate the internal-session cache before the profile becomes stricter.
      expect((await send()).status, HttpStatus.ok);
      expect(calls, 1);
      methods.remove('ticket');
      final deniedCall = await send();
      expect(deniedCall.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(deniedCall),
        containsPair('reason', 'wrong_authmethod'),
      );
      expect(calls, 1);
      final deniedRefresh = await send(refresh: true);
      expect(deniedRefresh.status, HttpStatus.unauthorized);
      final deniedBody = _jsonResponseBody(deniedRefresh);
      expect(deniedBody, containsPair('reason', 'wrong_authmethod'));
      expect(deniedBody, isNot(contains('access_token')));
      expect(deniedBody, isNot(contains('refresh_token')));
      expect(calls, 1);

      // A rejected refresh must not consume or rotate the existing grant.
      methods.add('ticket');
      expect((await send()).status, HttpStatus.ok);
      expect(calls, 2);
      final refreshed = await send(refresh: true);
      expect(refreshed.status, HttpStatus.ok);
      final body = _jsonResponseBody(refreshed);
      expect(body['access_token'], isNot(tokens.accessToken));
      expect(body['access_token'], isA<String>());
      expect(body['refresh_token'], isNot(tokens.refreshToken));
      expect(body['refresh_token'], isA<String>());
      expect(calls, 2);
    },
  );

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

  test(
    'rejects bearerless MCP metadata on insecure listeners before dispatch',
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
      const connectionId = 155;

      runtime.setConnectionProtocol(
        connectionId,
        NativeConnectionProtocol.http,
      );
      runtime.enqueueHttpHandshake(
        listenerId,
        connectionId,
        NativeHttpHandshake.synthetic(
          handle: 113,
          method: 'GET',
          target: '/mcp/secure',
          path: '/mcp/secure',
          protocol: 'http/1.1',
          headers: const {HttpHeaders.acceptHeader: 'application/json'},
          body: Uint8List(0),
          realm: 'realm1',
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
    const connectionId = 155;

    runtime.setConnectionProtocol(connectionId, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      listenerId,
      connectionId,
      NativeHttpHandshake.synthetic(
        handle: 114,
        method: 'DELETE',
        target: '/api/items',
        path: '/api/items',
        protocol: 'http/1.1',
        headers: const {},
        body: Uint8List(0),
        realm: 'realm1',
        procedure: 'com.example.api.items',
      ),
    );

    await _waitUntil(
      () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
    );
    final response = runtime.httpResponses[connectionId]!.single;
    expect(response.status, HttpStatus.methodNotAllowed);
    expect(response.headers[HttpHeaders.allowHeader], 'GET, POST');
    final jsonBody = _jsonResponseBody(response);
    expect(jsonBody['reason'], 'method_not_allowed');
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
      expect(response.headers[HttpHeaders.upgradeHeader], 'http2');
      final jsonBody = _jsonResponseBody(response);
      expect(jsonBody['reason'], 'protocol_not_allowed');
      expect(
        events.any((event) => event['type'] == 'http_request_dispatched'),
        isFalse,
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
          headers: {'authorization': 'bearer $jwt'},
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
    'serializes and invalidates protected MCP OAuth session contexts',
    () async {
      var currentRole = 'member';
      var introspectionActive = true;
      var introspectionExpired = false;
      var introspectionStatus = HttpStatus.ok;
      var introspectionRequests = 0;
      var queuedResponseRoles = <String>[];
      final queuedRequests = <HttpRequest>[];
      Completer<void>? queuedResponsesDone;
      const bearerToken = 'opaque-mcp-oauth-token';
      final introspectionServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => introspectionServer.close(force: true));

      Future<void> respondWithRole(HttpRequest request, String role) async {
        request.response.statusCode = introspectionStatus;
        if (introspectionStatus != HttpStatus.ok) {
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'active': introspectionActive,
            'sub': 'oauth-user',
            'role': role,
            'iss': 'https://issuer.example',
            'aud': const <String>['mcp-resource'],
            'exp':
                DateTime.now()
                    .toUtc()
                    .add(
                      introspectionExpired
                          ? const Duration(minutes: -1)
                          : const Duration(minutes: 5),
                    )
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        );
        await request.response.close();
      }

      introspectionServer.listen((request) async {
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(form['token'], bearerToken);
        introspectionRequests++;
        if (queuedResponseRoles.isEmpty) {
          await respondWithRole(request, currentRole);
          return;
        }

        queuedRequests.add(request);
        final responsesDone = queuedResponsesDone!;
        if (queuedRequests.length < queuedResponseRoles.length) {
          await responsesDone.future;
          return;
        }

        final requests = List<HttpRequest>.of(queuedRequests);
        final roles = List<String>.of(queuedResponseRoles);
        queuedRequests.clear();
        queuedResponseRoles = <String>[];
        for (var index = 0; index < requests.length; index++) {
          await respondWithRole(requests[index], roles[index]);
        }
        responsesDone.complete();
      });

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
        settings: _buildRouterSettingsWithHttpOAuthMcpProvider(
          Uri.parse(
            'http://${introspectionServer.address.address}:'
            '${introspectionServer.port}/introspect',
          ),
        ),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;

      final callee = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'svc-oauth',
        authRole: 'internal',
        roles: const {'callee': <String, Object?>{}},
      );
      addTearDown(callee.close);
      await callee.register(
        'com.example.oauth.echo',
        options: RegisterOptions(discloseCaller: true),
      );

      var nextConnectionId = 640;
      Future<NativeHttpResponse> sendMcp(
        Map<String, Object?> body, {
        String? sessionId,
      }) async {
        final connectionId = nextConnectionId++;
        runtime.setConnectionProtocol(
          connectionId,
          NativeConnectionProtocol.http,
        );
        final method = body['method']! as String;
        final params = body['params'];
        final name = params is Map ? params['name'] : null;
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId,
          method: 'POST',
          target: '/mcp/oauth',
          headers: <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            HttpHeaders.contentTypeHeader: 'application/json',
            'mcp-protocol-version': '2025-11-25',
            'mcp-method': method,
            if (name is String) 'mcp-name': name,
            'mcp-session-id': ?sessionId,
          },
          body: body,
          realm: 'realm1',
          procedure: 'router.http.mcp',
        );
        await _waitUntil(
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[connectionId]!.single;
      }

      Future<String> initialize(String requestId) async {
        final response = await sendMcp(<String, Object?>{
          'jsonrpc': '2.0',
          'id': requestId,
          'method': 'initialize',
          'params': const <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
            'clientInfo': <String, Object?>{
              'name': 'router-runtime-oauth-context-test',
              'version': '0.1.0',
            },
          },
        });
        expect(response.status, HttpStatus.ok);
        return response.headers['MCP-Session-Id']!;
      }

      Future<NativeHttpResponse> listTools(
        String requestId,
        String sessionId,
      ) => sendMcp(<String, Object?>{
        'jsonrpc': '2.0',
        'id': requestId,
        'method': 'tools/list',
        'params': const <String, Object?>{},
      }, sessionId: sessionId);

      final memberSessionId = await initialize('member-initialize');
      final memberTools = await listTools('member-tools', memberSessionId);
      expect(memberTools.status, HttpStatus.ok);
      expect(
        (_jsonResponseBody(memberTools)['result']! as Map)['tools'],
        contains(containsPair('name', 'com.example.oauth.echo')),
      );

      currentRole = 'blocked';
      final staleMemberTools = await listTools(
        'stale-member-tools',
        memberSessionId,
      );
      expect(staleMemberTools.status, HttpStatus.notFound);
      expect(
        _jsonResponseBody(staleMemberTools),
        containsPair(
          'error',
          containsPair('message', 'Unknown MCP HTTP session'),
        ),
      );
      expect(staleMemberTools.headers, isNot(contains('MCP-Session-Id')));

      final blockedSessionId = await initialize('blocked-initialize');
      final blockedTools = await listTools('blocked-tools', blockedSessionId);
      expect(blockedTools.status, HttpStatus.ok);
      final blockedResult = _jsonResponseBody(blockedTools)['result']! as Map;
      expect(
        blockedResult['tools'],
        isNot(contains(containsPair('name', 'com.example.oauth.echo'))),
      );

      currentRole = 'member';
      final staleBlockedTools = await listTools(
        'stale-blocked-tools',
        blockedSessionId,
      );
      expect(staleBlockedTools.status, HttpStatus.notFound);

      final replacementSessionId = await initialize('replacement-initialize');
      final replacementTools = await listTools(
        'replacement-tools',
        replacementSessionId,
      );
      expect(replacementTools.status, HttpStatus.ok);
      expect(
        (_jsonResponseBody(replacementTools)['result']! as Map)['tools'],
        contains(containsPair('name', 'com.example.oauth.echo')),
      );

      queuedResponseRoles = <String>['blocked', 'member'];
      queuedResponsesDone = Completer<void>();
      final concurrentlyStaleTools = listTools(
        'concurrently-stale-tools',
        replacementSessionId,
      );
      final concurrentMemberInitialization = initialize(
        'concurrent-member-initialize',
      );

      final staleTools = await concurrentlyStaleTools;
      expect(staleTools.status, HttpStatus.notFound);
      final concurrentMemberSessionId = await concurrentMemberInitialization;
      final concurrentMemberTools = await listTools(
        'concurrent-member-tools',
        concurrentMemberSessionId,
      );
      expect(concurrentMemberTools.status, HttpStatus.ok);
      expect(
        (_jsonResponseBody(concurrentMemberTools)['result']! as Map)['tools'],
        contains(containsPair('name', 'com.example.oauth.echo')),
      );

      introspectionStatus = HttpStatus.serviceUnavailable;
      final unavailableIntrospection = await listTools(
        'unavailable-introspection-tools',
        concurrentMemberSessionId,
      );
      expect(unavailableIntrospection.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(unavailableIntrospection),
        containsPair('reason', 'introspection_failed'),
      );

      introspectionStatus = HttpStatus.ok;
      final retainedAfterUnavailable = await listTools(
        'retained-after-unavailable-tools',
        concurrentMemberSessionId,
      );
      expect(retainedAfterUnavailable.status, HttpStatus.ok);

      introspectionActive = false;
      final inactiveSession = await listTools(
        'inactive-session-tools',
        concurrentMemberSessionId,
      );
      expect(inactiveSession.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(inactiveSession),
        containsPair('reason', 'invalid_token'),
      );
      expect(inactiveSession.headers, isNot(contains('MCP-Session-Id')));

      introspectionActive = true;
      final reactivatedStaleSession = await listTools(
        'reactivated-stale-session-tools',
        concurrentMemberSessionId,
      );
      expect(reactivatedStaleSession.status, HttpStatus.notFound);
      expect(
        _jsonResponseBody(reactivatedStaleSession),
        containsPair(
          'error',
          containsPair('message', 'Unknown MCP HTTP session'),
        ),
      );

      final reactivatedSessionId = await initialize(
        'reactivated-session-initialize',
      );
      final reactivatedTools = await listTools(
        'reactivated-session-tools',
        reactivatedSessionId,
      );
      expect(reactivatedTools.status, HttpStatus.ok);
      expect(
        (_jsonResponseBody(reactivatedTools)['result']! as Map)['tools'],
        contains(containsPair('name', 'com.example.oauth.echo')),
      );

      introspectionExpired = true;
      final expiredSession = await listTools(
        'expired-session-tools',
        reactivatedSessionId,
      );
      expect(expiredSession.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(expiredSession),
        containsPair('reason', 'expired_token'),
      );
      expect(expiredSession.headers, isNot(contains('MCP-Session-Id')));

      introspectionExpired = false;
      final reactivatedExpiredSession = await listTools(
        'reactivated-expired-session-tools',
        reactivatedSessionId,
      );
      expect(reactivatedExpiredSession.status, HttpStatus.notFound);
      expect(
        _jsonResponseBody(reactivatedExpiredSession),
        containsPair(
          'error',
          containsPair('message', 'Unknown MCP HTTP session'),
        ),
      );
      expect(introspectionRequests, greaterThanOrEqualTo(19));
    },
  );

  test(
    'isolates protected MCP sessions across delimiter-colliding auth scopes',
    () async {
      const bearerToken = 'opaque-colliding-scope-token';
      final introspectionServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => introspectionServer.close(force: true));
      introspectionServer.listen((request) async {
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(form['token'], bearerToken);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'active': true,
            'sub': 'scope-user',
            'role': 'member',
            'iss': 'https://issuer.example',
            'aud': const <String>['mcp-resource'],
            'exp':
                DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 5))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        );
        await request.response.close();
      });

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
        settings: _buildRouterSettingsWithCollidingHttpOAuthMcpScopes(
          Uri.parse(
            'http://${introspectionServer.address.address}:'
            '${introspectionServer.port}/introspect',
          ),
        ),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;

      Future<void> registerTool(
        String realm,
        String procedure,
        String response,
      ) async {
        final callee = await binding.createInternalSession(
          realmUri: realm,
          authId: 'svc-$realm',
          authRole: 'internal',
          roles: const {'callee': <String, Object?>{}},
        );
        addTearDown(callee.close);
        final registration = await callee.register(procedure);
        registration.onInvoke((invocation) {
          invocation.respondWith(arguments: <Object?>[response]);
        });
      }

      await registerTool(
        'realm',
        'com.example.realm.echo',
        'realm-response',
      );
      await registerTool(
        'tenant',
        'com.example.tenant.echo',
        'tenant-response',
      );

      var nextConnectionId = 650;
      Future<NativeHttpResponse> sendMcp(
        String path,
        Map<String, Object?> body, {
        String? sessionId,
      }) async {
        final connectionId = nextConnectionId++;
        final method = body['method']! as String;
        final params = body['params'];
        final name = params is Map ? params['name'] : null;
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId,
          method: 'POST',
          target: path,
          headers: <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            HttpHeaders.contentTypeHeader: 'application/json',
            'mcp-protocol-version': '2025-11-25',
            'mcp-method': method,
            if (name is String) 'mcp-name': name,
            'mcp-session-id': ?sessionId,
          },
          body: body,
          realm: path == '/mcp/realm' ? 'realm' : 'tenant',
          procedure: 'router.http.mcp',
        );
        await _waitUntil(
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[connectionId]!.single;
      }

      Future<String> initialize(String path, String requestId) async {
        final response = await sendMcp(path, <String, Object?>{
          'jsonrpc': '2.0',
          'id': requestId,
          'method': 'initialize',
          'params': const <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
            'clientInfo': <String, Object?>{
              'name': 'router-runtime-auth-scope-test',
              'version': '0.1.0',
            },
          },
        });
        expect(response.status, HttpStatus.ok);
        return response.headers['MCP-Session-Id']!;
      }

      Future<NativeHttpResponse> listTools(
        String path,
        String requestId,
        String sessionId,
      ) => sendMcp(path, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestId,
        'method': 'tools/list',
        'params': const <String, Object?>{},
      }, sessionId: sessionId);

      Future<NativeHttpResponse> callTool(
        String path,
        String requestId,
        String sessionId,
        String name,
      ) => sendMcp(path, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestId,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': name,
          'arguments': const <String, Object?>{},
        },
      }, sessionId: sessionId);

      final realmSessionId = await initialize(
        '/mcp/realm',
        'realm-initialize',
      );
      final realmTools = await listTools(
        '/mcp/realm',
        'realm-tools',
        realmSessionId,
      );
      expect(realmTools.status, HttpStatus.ok);
      final realmToolList =
          (_jsonResponseBody(realmTools)['result']! as Map)['tools']! as List;
      expect(
        realmToolList,
        contains(containsPair('name', 'com.example.realm.echo')),
      );
      expect(
        realmToolList,
        isNot(contains(containsPair('name', 'com.example.tenant.echo'))),
      );

      final tenantSessionId = await initialize(
        '/mcp/tenant',
        'tenant-initialize',
      );
      final tenantTools = await listTools(
        '/mcp/tenant',
        'tenant-tools',
        tenantSessionId,
      );
      expect(tenantTools.status, HttpStatus.ok);
      final tenantToolList =
          (_jsonResponseBody(tenantTools)['result']! as Map)['tools']! as List;
      expect(
        tenantToolList,
        contains(containsPair('name', 'com.example.tenant.echo')),
      );
      expect(
        tenantToolList,
        isNot(contains(containsPair('name', 'com.example.realm.echo'))),
      );

      final realmCall = await callTool(
        '/mcp/realm',
        'realm-call',
        realmSessionId,
        'com.example.realm.echo',
      );
      expect(realmCall.status, HttpStatus.ok);
      expect(
        ((_jsonResponseBody(realmCall)['result']! as Map)['structuredContent']!
            as Map)['arguments'],
        const ['realm-response'],
      );

      final tenantCall = await callTool(
        '/mcp/tenant',
        'tenant-call',
        tenantSessionId,
        'com.example.tenant.echo',
      );
      expect(tenantCall.status, HttpStatus.ok);
      expect(
        ((_jsonResponseBody(tenantCall)['result']! as Map)['structuredContent']!
            as Map)['arguments'],
        const ['tenant-response'],
      );
    },
  );

  test(
    'isolates anonymous MCP routes across delimiter-colliding session scopes',
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
        settings: _buildRouterSettingsWithCollidingAnonymousMcpRouteScopes(),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;

      Future<void> registerTool(
        String realm,
        String procedure,
        String response,
      ) async {
        final callee = await binding.createInternalSession(
          realmUri: realm,
          authId: 'svc-$realm',
          authRole: 'internal',
          roles: const {'callee': <String, Object?>{}},
        );
        addTearDown(callee.close);
        final registration = await callee.register(procedure);
        registration.onInvoke((invocation) {
          invocation.respondWith(arguments: <Object?>[response]);
        });
      }

      await registerTool(
        'realm',
        'com.example.realm.echo',
        'realm-response',
      );
      await registerTool(
        'tenant',
        'com.example.tenant.echo',
        'tenant-response',
      );

      var nextConnectionId = 675;
      Future<NativeHttpResponse> sendMcp(
        String path,
        Map<String, Object?> body,
      ) async {
        final connectionId = nextConnectionId++;
        final method = body['method']! as String;
        final params = body['params'];
        final name = params is Map ? params['name'] : null;
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId,
          method: 'POST',
          target: path,
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            HttpHeaders.contentTypeHeader: 'application/json',
            'mcp-protocol-version': '2026-07-28',
            'mcp-method': method,
            if (name is String) 'mcp-name': name,
          },
          body: body,
          realm: path == '/mcp/scope' ? 'realm' : 'tenant',
          procedure: 'router.http.mcp',
        );
        await _waitUntil(
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[connectionId]!.single;
      }

      Future<NativeHttpResponse> listTools(String path, String requestId) =>
          sendMcp(path, <String, Object?>{
            'jsonrpc': '2.0',
            'id': requestId,
            'method': 'tools/list',
            'params': const <String, Object?>{
              '_meta': <String, Object?>{
                'io.modelcontextprotocol/protocolVersion': '2026-07-28',
                'io.modelcontextprotocol/clientCapabilities':
                    <String, Object?>{},
              },
            },
          });

      Future<NativeHttpResponse> callTool(
        String path,
        String requestId,
        String name,
      ) => sendMcp(path, <String, Object?>{
        'jsonrpc': '2.0',
        'id': requestId,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': name,
          'arguments': const <String, Object?>{},
          '_meta': const <String, Object?>{
            'io.modelcontextprotocol/protocolVersion': '2026-07-28',
            'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
          },
        },
      });

      final realmTools = await listTools('/mcp/scope', 'realm-tools');
      expect(realmTools.status, HttpStatus.ok);
      expect(realmTools.headers, isNot(contains('MCP-Session-Id')));
      final realmToolList =
          (_jsonResponseBody(realmTools)['result']! as Map)['tools']! as List;
      expect(
        realmToolList,
        contains(containsPair('name', 'com.example.realm.echo')),
      );
      expect(
        realmToolList,
        isNot(contains(containsPair('name', 'com.example.tenant.echo'))),
      );

      final tenantTools = await listTools(
        '/mcp/scope:realm',
        'tenant-tools',
      );
      expect(tenantTools.status, HttpStatus.ok);
      expect(tenantTools.headers, isNot(contains('MCP-Session-Id')));
      final tenantToolList =
          (_jsonResponseBody(tenantTools)['result']! as Map)['tools']! as List;
      expect(
        tenantToolList,
        contains(containsPair('name', 'com.example.tenant.echo')),
      );
      expect(
        tenantToolList,
        isNot(contains(containsPair('name', 'com.example.realm.echo'))),
      );

      final realmCall = await callTool(
        '/mcp/scope',
        'realm-call',
        'com.example.realm.echo',
      );
      expect(realmCall.status, HttpStatus.ok);
      expect(
        ((_jsonResponseBody(realmCall)['result']! as Map)['structuredContent']!
            as Map)['arguments'],
        const ['realm-response'],
      );

      final tenantCall = await callTool(
        '/mcp/scope:realm',
        'tenant-call',
        'com.example.tenant.echo',
      );
      expect(tenantCall.status, HttpStatus.ok);
      expect(
        ((_jsonResponseBody(tenantCall)['result']! as Map)['structuredContent']!
            as Map)['arguments'],
        const ['tenant-response'],
      );
    },
  );

  test(
    'reuses one anonymous MCP WAMP session across concurrent first requests',
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
        settings: _buildRouterSettingsWithCollidingAnonymousMcpRouteScopes(),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      final baselineSessionCount =
          (await binding.collectMetrics()).sessionCount;

      var nextConnectionId = 690;
      Future<NativeHttpResponse> listTools(int requestIndex) async {
        final connectionId = nextConnectionId++;
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId,
          method: 'POST',
          target: '/mcp/scope',
          headers: const <String, String>{
            HttpHeaders.acceptHeader: 'application/json, text/event-stream',
            HttpHeaders.contentTypeHeader: 'application/json',
            'mcp-protocol-version': '2026-07-28',
            'mcp-method': 'tools/list',
          },
          body: <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'concurrent-tools-$requestIndex',
            'method': 'tools/list',
            'params': const <String, Object?>{
              '_meta': <String, Object?>{
                'io.modelcontextprotocol/protocolVersion': '2026-07-28',
                'io.modelcontextprotocol/clientCapabilities':
                    <String, Object?>{},
              },
            },
          },
          realm: 'realm',
          procedure: 'router.http.mcp',
        );
        await _waitUntil(
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[connectionId]!.single;
      }

      final responses = await Future.wait(
        List<Future<NativeHttpResponse>>.generate(12, listTools),
      );
      for (final response in responses) {
        expect(response.status, HttpStatus.ok);
        expect(response.headers, isNot(contains('MCP-Session-Id')));
      }

      final sessionCount = (await binding.collectMetrics()).sessionCount;
      expect(sessionCount, baselineSessionCount + 1);
    },
  );

  test(
    'auth bridge rejects mixed challenge and grant selectors without consuming state',
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

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 58,
        handle: 18,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );

      await _waitUntil(() => runtime.httpResponses[58]?.isNotEmpty ?? false);
      final challenge = runtime.httpResponses[58]!.single;
      expect(challenge.status, HttpStatus.unauthorized);
      final state = _jsonResponseBody(challenge)['state'] as String;
      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 59,
        handle: 19,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'state': state,
          'grant_type': 'refresh_token',
          'refresh_token': 'not-a-grant',
          'signature': authenticate.signature,
          'extra': authenticate.extra,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );

      await _waitUntil(() => runtime.httpResponses[59]?.isNotEmpty ?? false);
      final conflict = runtime.httpResponses[59]!.single;
      expect(conflict.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(conflict),
        allOf(
          containsPair('status', 'error'),
          containsPair('reason', 'conflicting_auth_operation'),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 60,
        handle: 20,
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

      await _waitUntil(() => runtime.httpResponses[60]?.isNotEmpty ?? false);
      final success = runtime.httpResponses[60]!.single;
      expect(success.status, HttpStatus.ok);
      expect(
        _jsonResponseBody(success),
        allOf(contains('access_token'), contains('refresh_token')),
      );
    },
  );

  test(
    'auth bridge rejects conflicting selector sources without consuming state',
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

      for (final conflict
          in <({int connectionId, String headerName, String headerValue})>[
            (
              connectionId: 65,
              headerName: 'x-connectanum-realm',
              headerValue: 'different-realm',
            ),
            (
              connectionId: 66,
              headerName: 'x-connectanum-auth-method',
              headerValue: 'wampcra',
            ),
            (
              connectionId: 67,
              headerName: 'x-connectanum-auth-id',
              headerValue: 'different-user',
            ),
          ]) {
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: conflict.connectionId,
          handle: conflict.connectionId - 40,
          method: 'POST',
          target: '/auth',
          headers: <String, String>{
            'content-type': 'application/json',
            conflict.headerName: conflict.headerValue,
          },
          body: const <String, Object?>{
            'realm': 'realm1',
            'authmethod': 'ticket',
            'authid': 'user-1',
          },
          realm: 'router.http',
          procedure: 'router.http.auth',
        );

        await _waitUntil(
          () =>
              runtime.httpResponses[conflict.connectionId]?.isNotEmpty ?? false,
        );
        final response = runtime.httpResponses[conflict.connectionId]!.single;
        expect(response.status, HttpStatus.badRequest);
        expect(
          _jsonResponseBody(response),
          allOf(
            containsPair('status', 'error'),
            containsPair('reason', 'conflicting_auth_parameter'),
            isNot(contains('state')),
            isNot(contains('access_token')),
            isNot(contains('refresh_token')),
          ),
        );
      }

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 64,
        handle: 24,
        method: 'POST',
        target: '/auth',
        headers: const {
          'content-type': 'application/json',
          'x-connectanum-grant-type': 'refresh_token',
        },
        body: const <String, Object?>{'grant_type': 'revoke'},
        realm: 'router.http',
        procedure: 'router.http.auth',
      );

      await _waitUntil(() => runtime.httpResponses[64]?.isNotEmpty ?? false);
      final grantConflict = runtime.httpResponses[64]!.single;
      expect(grantConflict.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(grantConflict),
        allOf(
          containsPair('status', 'error'),
          containsPair('reason', 'conflicting_auth_selector'),
          isNot(contains('state')),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 61,
        handle: 21,
        method: 'POST',
        target: '/auth',
        headers: const {
          'content-type': 'application/json',
          'x-connectanum-realm': 'realm1',
          'x-connectanum-auth-method': 'ticket',
          'x-connectanum-auth-id': 'user-1',
        },
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );

      await _waitUntil(() => runtime.httpResponses[61]?.isNotEmpty ?? false);
      final challenge = runtime.httpResponses[61]!.single;
      expect(challenge.status, HttpStatus.unauthorized);
      final state = _jsonResponseBody(challenge)['state'] as String;
      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 62,
        handle: 22,
        method: 'POST',
        target: '/auth',
        headers: const {
          'content-type': 'application/json',
          'x-connectanum-auth-state': 'different-state',
        },
        body: <String, Object?>{
          'state': state,
          'signature': authenticate.signature,
          'extra': authenticate.extra,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );

      await _waitUntil(() => runtime.httpResponses[62]?.isNotEmpty ?? false);
      final conflict = runtime.httpResponses[62]!.single;
      expect(conflict.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(conflict),
        allOf(
          containsPair('status', 'error'),
          containsPair('reason', 'conflicting_auth_selector'),
          isNot(contains('state')),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 68,
        handle: 28,
        method: 'POST',
        target: '/auth',
        headers: <String, String>{
          'content-type': 'application/json',
          'x-connectanum-auth-state': state,
          'x-connectanum-auth-signature': 'different-signature',
        },
        body: <String, Object?>{
          'state': state,
          'signature': authenticate.signature,
          'extra': authenticate.extra,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );

      await _waitUntil(() => runtime.httpResponses[68]?.isNotEmpty ?? false);
      final signatureConflict = runtime.httpResponses[68]!.single;
      expect(signatureConflict.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(signatureConflict),
        allOf(
          containsPair('status', 'error'),
          containsPair('reason', 'conflicting_auth_parameter'),
          isNot(contains('state')),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 63,
        handle: 23,
        method: 'POST',
        target: '/auth',
        headers: <String, String>{
          'content-type': 'application/json',
          'x-connectanum-auth-state': state,
          'x-connectanum-auth-signature': authenticate.signature!,
        },
        body: <String, Object?>{
          'state': state,
          'signature': authenticate.signature,
          'extra': authenticate.extra,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );

      await _waitUntil(() => runtime.httpResponses[63]?.isNotEmpty ?? false);
      final success = runtime.httpResponses[63]!.single;
      expect(success.status, HttpStatus.ok);
      expect(
        _jsonResponseBody(success),
        allOf(contains('access_token'), contains('refresh_token')),
      );
    },
  );

  test(
    'auth bridge rejects malformed parameter values without mutating state',
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
        settings: _buildRouterSettingsWithHttpAuthBridge(maxPendingAuth: 1),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      var nextConnectionId = 90;

      Future<NativeHttpResponse> postAuth({
        required Map<String, Object?> body,
        Map<String, String> headers = const <String, String>{},
        String target = '/auth',
        String? query,
        String? rawBody,
      }) async {
        final connectionId = nextConnectionId++;
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId + 1000,
          method: 'POST',
          target: target,
          query: query ?? Uri.parse(target).query,
          headers: <String, String>{
            'content-type': 'application/json',
            ...headers,
          },
          body: body,
          rawBody: rawBody == null ? null : utf8.encode(rawBody),
          realm: 'router.http',
          procedure: 'router.http.auth',
        );
        await _waitUntil(
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[connectionId]!.single;
      }

      void expectInvalidParameter(NativeHttpResponse response) {
        expect(response.status, HttpStatus.badRequest);
        expect(
          _jsonResponseBody(response),
          allOf(
            containsPair('status', 'error'),
            containsPair('reason', 'invalid_auth_parameter'),
            isNot(contains('state')),
            isNot(contains('access_token')),
            isNot(contains('refresh_token')),
          ),
        );
      }

      for (final malformed
          in <
            ({String key, Object? value, String headerName, String headerValue})
          >[
            (
              key: 'realm',
              value: 7,
              headerName: 'x-connectanum-realm',
              headerValue: 'realm1',
            ),
            (
              key: 'authmethod',
              value: false,
              headerName: 'x-connectanum-auth-method',
              headerValue: 'ticket',
            ),
            (
              key: 'authid',
              value: null,
              headerName: 'x-connectanum-auth-id',
              headerValue: 'user-1',
            ),
          ]) {
        expectInvalidParameter(
          await postAuth(
            body: <String, Object?>{
              'realm': 'realm1',
              'authmethod': 'ticket',
              'authid': 'user-1',
              malformed.key: malformed.value,
            },
            headers: <String, String>{
              malformed.headerName: malformed.headerValue,
            },
          ),
        );
      }

      for (final malformed
          in <
            ({
              Map<String, Object?> body,
              Map<String, String> headers,
              String target,
            })
          >[
            (
              body: const <String, Object?>{
                'realm': ' ',
                'authmethod': 'ticket',
                'authid': 'user-1',
              },
              headers: const <String, String>{'x-connectanum-realm': 'realm1'},
              target: '/auth',
            ),
            (
              body: const <String, Object?>{
                'realm': 'realm1',
                'authmethod': 'ticket',
                'authid': 'user-1',
              },
              headers: const <String, String>{},
              target: '/auth?authmethod=%20',
            ),
            (
              body: const <String, Object?>{
                'realm': 'realm1',
                'authmethod': 'ticket',
                'authid': 'user-1',
              },
              headers: const <String, String>{'x-connectanum-auth-id': ' '},
              target: '/auth',
            ),
          ]) {
        expectInvalidParameter(
          await postAuth(
            body: malformed.body,
            headers: malformed.headers,
            target: malformed.target,
          ),
        );
      }

      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{
            'authmethod': 'ticket',
            'authid': 'user-1',
          },
          query: 'realm=realm1&realm=realm2',
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{},
          rawBody:
              r'{"realm":"realm1","\u0072ealm":"realm2","authmethod":"ticket","authid":"user-1"}',
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{
            'realm': 'realm1',
            'authmethod': 'ticket',
            'authid': 'user-1',
          },
          query: 'realm=%',
        ),
      );

      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{
            'realm': 'realm1',
            'authmethod': 'ticket',
            'authid': 'user-1',
            'authextra': false,
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{},
          rawBody:
              '{"realm":"realm1","authmethod":"ticket","authid":"user-1",'
              '"authextra":{"source":"first"},'
              '"authextra":{"source":"second"}}',
        ),
      );

      final challenge = await postAuth(
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
          'authextra': <String, Object?>{'source': 'router-test'},
          'extra': false,
        },
      );
      expect(challenge.status, HttpStatus.unauthorized);
      final state = _jsonResponseBody(challenge)['state'] as String;
      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());

      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'state': 7,
            'signature': authenticate.signature,
            'extra': authenticate.extra,
          },
          headers: <String, String>{
            'x-connectanum-auth-state': state,
            'x-connectanum-auth-signature': authenticate.signature!,
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'state': ' ',
            'signature': authenticate.signature,
            'extra': authenticate.extra,
          },
          headers: <String, String>{'x-connectanum-auth-state': state},
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'state': state,
            'signature': authenticate.signature,
            'extra': authenticate.extra,
          },
          target: '/auth?state=%20',
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'signature': authenticate.signature,
            'extra': authenticate.extra,
          },
          query:
              'state=${Uri.encodeQueryComponent(state)}&state=${Uri.encodeQueryComponent(state)}',
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'state': state,
            'signature': authenticate.signature,
            'extra': authenticate.extra,
          },
          headers: const <String, String>{'x-connectanum-auth-signature': ' '},
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'state': state,
            'signature': <String>['not-a-string'],
            'extra': authenticate.extra,
          },
          headers: <String, String>{
            'x-connectanum-auth-state': state,
            'x-connectanum-auth-signature': authenticate.signature!,
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{},
          rawBody:
              '{"state":${jsonEncode(state)},'
              '"signature":${jsonEncode(authenticate.signature)},'
              '"signature":"ignored"}',
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'state': state,
            'signature': authenticate.signature,
            'extra': false,
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{},
          rawBody:
              '{"state":${jsonEncode(state)},'
              '"signature":${jsonEncode(authenticate.signature)},'
              '"extra":{"source":"first"},'
              '"extra":{"source":"second"}}',
        ),
      );

      final occupiedCapacity = await postAuth(
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
        },
      );
      expect(occupiedCapacity.status, HttpStatus.tooManyRequests);
      expect(
        _jsonResponseBody(occupiedCapacity),
        allOf(
          containsPair('reason', 'auth_capacity_exhausted'),
          isNot(contains('state')),
        ),
      );

      final authenticated = await postAuth(
        body: <String, Object?>{
          'state': state,
          'signature': authenticate.signature,
          'extra': <String, Object?>{
            ...?authenticate.extra,
            'source': 'router-test',
          },
          'authextra': false,
          'token': false,
        },
        headers: <String, String>{
          'x-connectanum-auth-state': state,
          'x-connectanum-auth-signature': authenticate.signature!,
        },
      );
      expect(authenticated.status, HttpStatus.ok);
      final grant = _jsonResponseBody(authenticated);
      final refreshToken = grant['refresh_token'] as String;

      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': <String, Object?>{'invalid': true},
            'refresh_token': refreshToken,
          },
          headers: const <String, String>{
            'x-connectanum-grant-type': 'refresh_token',
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': 'refresh_token',
            'refresh_token': refreshToken,
          },
          target: '/auth?grant_type=%20',
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': 'refresh_token',
            'refresh_token': refreshToken,
            'token': false,
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': 'refresh_token',
            'refresh_token': refreshToken,
            'token': ' ',
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{'grant_type': 'refresh_token'},
          query:
              'refresh_token=${Uri.encodeQueryComponent(refreshToken)}&refresh_token=${Uri.encodeQueryComponent(refreshToken)}',
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{},
          rawBody:
              '{"grant_type":"refresh_token",'
              '"refresh_token":${jsonEncode(refreshToken)},'
              '"refresh_token":"ignored"}',
        ),
      );

      final refreshed = await postAuth(
        body: const <String, Object?>{},
        rawBody:
            '{"grant_type":"refresh_token",'
            '"refresh_token":${jsonEncode(refreshToken)},'
            '"realm":"ignored-a","realm":"ignored-b",'
            '"signature":false}',
      );
      expect(refreshed.status, HttpStatus.ok);
      final refreshedToken =
          _jsonResponseBody(refreshed)['refresh_token'] as String;

      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': 'revoke',
            'token': refreshedToken,
            'refresh_token': 7,
            'token_type_hint': 'refresh_token',
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': 'revoke',
            'token': refreshedToken,
            'refresh_token': ' ',
            'token_type_hint': 'refresh_token',
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': 'revoke',
            'token': refreshedToken,
            'token_type_hint': null,
          },
          headers: const <String, String>{
            'x-connectanum-token-type-hint': 'refresh_token',
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': 'revoke',
            'token': refreshedToken,
            'token_type_hint': 'refresh_token',
          },
          headers: const <String, String>{'x-connectanum-token-type-hint': ' '},
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': 'revoke',
            'token': refreshedToken,
          },
          query: 'token_type_hint=refresh_token&token_type_hint=refresh_token',
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{},
          rawBody:
              '{"grant_type":"revoke",'
              '"token":${jsonEncode(refreshedToken)},'
              '"token_type_hint":"refresh_token",'
              '"token_type_hint":"access_token"}',
        ),
      );

      final preservedRefresh = await postAuth(
        body: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': refreshedToken,
        },
      );
      expect(preservedRefresh.status, HttpStatus.ok);
      expect(
        _jsonResponseBody(preservedRefresh),
        allOf(contains('access_token'), contains('refresh_token')),
      );
    },
  );

  test(
    'auth bridge rejects repeated operation-relevant headers',
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
        settings: _buildRouterSettingsWithHttpAuthBridge(maxPendingAuth: 1),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      var nextConnectionId = 189;

      Future<NativeHttpResponse> postAuth({
        required Map<String, Object?> body,
        Map<String, String> headers = const <String, String>{},
      }) async {
        final connectionId = nextConnectionId++;
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId + 1000,
          method: 'POST',
          target: '/auth',
          headers: <String, String>{
            'content-type': 'application/json',
            ...headers,
          },
          body: body,
          realm: 'router.http',
          procedure: 'router.http.auth',
        );
        await _waitUntil(
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[connectionId]!.single;
      }

      void expectInvalidParameter(NativeHttpResponse response) {
        expect(response.status, HttpStatus.badRequest);
        expect(
          _jsonResponseBody(response),
          allOf(
            containsPair('reason', 'invalid_auth_parameter'),
            isNot(contains('state')),
            isNot(contains('access_token')),
            isNot(contains('refresh_token')),
          ),
        );
      }

      expectInvalidParameter(
        await postAuth(
          body: const <String, Object?>{},
          headers: const <String, String>{
            'x-connectanum-realm': 'realm1',
            'X-Connectanum-Realm': 'realm1',
            'x-connectanum-auth-method': 'ticket',
            'x-connectanum-auth-id': 'user-1',
          },
        ),
      );

      final challenge = await postAuth(
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
        },
      );
      expect(challenge.status, HttpStatus.unauthorized);
      final state = _jsonResponseBody(challenge)['state'] as String;
      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());

      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'signature': authenticate.signature,
            'extra': authenticate.extra,
          },
          headers: <String, String>{
            'x-connectanum-auth-state': state,
            'X-Connectanum-Auth-State': state,
          },
        ),
      );
      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'state': state,
            'extra': authenticate.extra,
          },
          headers: <String, String>{
            'x-connectanum-auth-signature': authenticate.signature!,
            'X-Connectanum-Auth-Signature': authenticate.signature!,
          },
        ),
      );

      final occupiedCapacity = await postAuth(
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
        },
      );
      expect(occupiedCapacity.status, HttpStatus.tooManyRequests);
      expect(
        _jsonResponseBody(occupiedCapacity),
        containsPair('reason', 'auth_capacity_exhausted'),
      );

      final authenticated = await postAuth(
        body: <String, Object?>{
          'state': state,
          'signature': authenticate.signature,
          'extra': authenticate.extra,
        },
      );
      expect(authenticated.status, HttpStatus.ok);
      final refreshToken =
          _jsonResponseBody(authenticated)['refresh_token'] as String;

      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{'refresh_token': refreshToken},
          headers: const <String, String>{
            'x-connectanum-grant-type': 'refresh_token',
            'X-Connectanum-Grant-Type': 'refresh_token',
          },
        ),
      );

      final refreshed = await postAuth(
        body: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
        headers: const <String, String>{
          'x-connectanum-auth-signature': 'ignored-a',
          'X-Connectanum-Auth-Signature': 'ignored-b',
        },
      );
      expect(refreshed.status, HttpStatus.ok);
      final refreshedToken =
          _jsonResponseBody(refreshed)['refresh_token'] as String;

      expectInvalidParameter(
        await postAuth(
          body: <String, Object?>{
            'grant_type': 'revoke',
            'token': refreshedToken,
          },
          headers: const <String, String>{
            'x-connectanum-token-type-hint': 'refresh_token',
            'X-Connectanum-Token-Type-Hint': 'refresh_token',
          },
        ),
      );

      final preservedRefresh = await postAuth(
        body: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': refreshedToken,
        },
      );
      expect(preservedRefresh.status, HttpStatus.ok);
      expect(
        _jsonResponseBody(preservedRefresh),
        allOf(contains('access_token'), contains('refresh_token')),
      );
    },
  );

  test(
    'auth bridge rejects duplicate members inside selected auth objects',
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
        settings: _buildRouterSettingsWithHttpAuthBridge(maxPendingAuth: 1),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      var nextConnectionId = 190;

      Future<NativeHttpResponse> postAuth({required String rawBody}) async {
        final connectionId = nextConnectionId++;
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId + 1000,
          method: 'POST',
          target: '/auth',
          headers: const <String, String>{'content-type': 'application/json'},
          body: const <String, Object?>{},
          rawBody: utf8.encode(rawBody),
          realm: 'router.http',
          procedure: 'router.http.auth',
        );
        await _waitUntil(
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[connectionId]!.single;
      }

      void expectInvalidParameter(NativeHttpResponse response) {
        expect(response.status, HttpStatus.badRequest);
        expect(
          _jsonResponseBody(response),
          allOf(
            containsPair('reason', 'invalid_auth_parameter'),
            isNot(contains('state')),
            isNot(contains('access_token')),
            isNot(contains('refresh_token')),
          ),
        );
      }

      for (final rawBody in <String>[
        r'{"realm":"realm1","authmethod":"ticket","authid":"user-1","authextra":{"source":"first","\u0073ource":"second"}}',
        r'{"realm":"realm1","authmethod":"ticket","authid":"user-1","authextra":{"context":{"level":"first","\u006cevel":"second"}}}',
        r'{"realm":"realm1","authmethod":"ticket","authid":"user-1","authextra":{"contexts":[{"level":"first","\u006cevel":"second"}]}}',
      ]) {
        expectInvalidParameter(await postAuth(rawBody: rawBody));
      }

      final challenge = await postAuth(
        rawBody:
            '{"realm":"realm1","authmethod":"ticket",'
            '"authid":"user-1","authextra":null}',
      );
      expect(challenge.status, HttpStatus.unauthorized);
      final state = _jsonResponseBody(challenge)['state'] as String;
      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());

      for (final rawBody in <String>[
        '{"state":${jsonEncode(state)},'
            '"signature":${jsonEncode(authenticate.signature)},'
            r'"extra":{"source":"first","\u0073ource":"second"}}',
        '{"state":${jsonEncode(state)},'
            '"signature":${jsonEncode(authenticate.signature)},'
            r'"extra":{"context":{"level":"first","\u006cevel":"second"}}}',
      ]) {
        expectInvalidParameter(await postAuth(rawBody: rawBody));
      }

      final occupiedCapacity = await postAuth(
        rawBody: '{"realm":"realm1","authmethod":"ticket","authid":"user-1"}',
      );
      expect(occupiedCapacity.status, HttpStatus.tooManyRequests);
      expect(
        _jsonResponseBody(occupiedCapacity),
        allOf(
          containsPair('reason', 'auth_capacity_exhausted'),
          isNot(contains('state')),
        ),
      );

      final authenticated = await postAuth(
        rawBody:
            '{"state":${jsonEncode(state)},'
            '"signature":${jsonEncode(authenticate.signature)},'
            '"extra":null}',
      );
      expect(authenticated.status, HttpStatus.ok);
      final refreshToken =
          _jsonResponseBody(authenticated)['refresh_token'] as String;

      final refreshed = await postAuth(
        rawBody:
            '{"grant_type":"refresh_token",'
            '"refresh_token":${jsonEncode(refreshToken)},'
            '"authextra":{"source":"ignored-a","source":"ignored-b"},'
            '"extra":{"context":{"source":"ignored-a",'
            '"source":"ignored-b"}}}',
      );
      expect(refreshed.status, HttpStatus.ok);
      expect(
        _jsonResponseBody(refreshed),
        allOf(contains('access_token'), contains('refresh_token')),
      );
    },
  );

  test(
    'auth bridge rejects unsupported grant types before authentication',
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

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 59,
        handle: 19,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: const <String, Object?>{
          'grant_type': 'password',
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );

      await _waitUntil(() => runtime.httpResponses[59]?.isNotEmpty ?? false);
      final response = runtime.httpResponses[59]!.single;
      expect(response.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(response),
        allOf(
          containsPair('status', 'error'),
          containsPair('reason', 'unsupported_grant_type'),
        ),
      );
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

  test(
    'auth bridge bounds pending challenges and reclaims completed capacity',
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
        settings: _buildRouterSettingsWithHttpAuthBridge(maxPendingAuth: 1),
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
      void enqueueAuthStart(int connectionId, int handle) {
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: handle,
          method: 'POST',
          target: '/auth',
          headers: const {'content-type': 'application/json'},
          body: const <String, Object?>{
            'realm': 'realm1',
            'authmethod': 'ticket',
            'authid': 'user-1',
          },
          realm: 'router.http',
          procedure: 'router.http.auth',
        );
      }

      enqueueAuthStart(60, 20);
      await _waitUntil(() => runtime.httpResponses[60]?.isNotEmpty ?? false);
      final firstChallenge = runtime.httpResponses[60]!.single;
      expect(firstChallenge.status, HttpStatus.unauthorized);
      final firstChallengeBody = _jsonResponseBody(firstChallenge);
      final state = firstChallengeBody['state'] as String;

      enqueueAuthStart(61, 21);
      await _waitUntil(() => runtime.httpResponses[61]?.isNotEmpty ?? false);
      final capacityResponse = runtime.httpResponses[61]!.single;
      expect(capacityResponse.status, HttpStatus.tooManyRequests);
      final retryAfter = int.parse(
        capacityResponse.headers[HttpHeaders.retryAfterHeader]!,
      );
      expect(retryAfter, inInclusiveRange(1, 10));
      expect(
        _jsonResponseBody(capacityResponse),
        allOf(
          containsPair('reason', 'auth_capacity_exhausted'),
          isNot(contains('state')),
        ),
      );
      expect(
        events,
        contains(
          allOf(
            containsPair('type', 'http_auth_capacity_exhausted'),
            containsPair('realm', 'realm1'),
            containsPair('pendingAuthCount', 1),
            containsPair('maxPendingAuth', 1),
            isNot(contains('authid')),
          ),
        ),
      );

      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 62,
        handle: 22,
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
      await _waitUntil(() => runtime.httpResponses[62]?.isNotEmpty ?? false);
      final successResponse = runtime.httpResponses[62]!.single;
      expect(successResponse.status, HttpStatus.ok);
      expect(_jsonResponseBody(successResponse)['access_token'], isNotEmpty);

      enqueueAuthStart(63, 23);
      await _waitUntil(() => runtime.httpResponses[63]?.isNotEmpty ?? false);
      final recoveredChallenge = runtime.httpResponses[63]!.single;
      expect(recoveredChallenge.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(recoveredChallenge)['state'],
        isNot(equals(state)),
      );
    },
  );

  test(
    'auth bridge bounds active grant lineages and recovers after revocation',
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
        settings: _buildRouterSettingsWithHttpAuthBridge(maxHttpAuthGrants: 1),
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
      final firstGrant = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
        startConnectionId: 90,
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 92,
        handle: 52,
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
      await _waitUntil(() => runtime.httpResponses[92]?.isNotEmpty ?? false);
      final refreshResponse = runtime.httpResponses[92]!.single;
      expect(refreshResponse.status, HttpStatus.ok);
      final refreshedToken =
          _jsonResponseBody(refreshResponse)['refresh_token'] as String;

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 93,
        handle: 53,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'locked-user',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[93]?.isNotEmpty ?? false);
      final capacityResponse = runtime.httpResponses[93]!.single;
      expect(capacityResponse.status, HttpStatus.serviceUnavailable);
      final retryAfter = int.parse(
        capacityResponse.headers[HttpHeaders.retryAfterHeader]!,
      );
      expect(retryAfter, inInclusiveRange(1, 300));
      expect(
        _jsonResponseBody(capacityResponse),
        allOf(
          containsPair('reason', 'auth_grant_capacity_exhausted'),
          isNot(contains('state')),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
      );
      expect(
        events,
        contains(
          allOf(
            containsPair('type', 'http_auth_grant_capacity_exhausted'),
            containsPair('realm', 'realm1'),
            containsPair('activeGrantCount', 1),
            containsPair('maxHttpAuthGrants', 1),
            isNot(contains('authid')),
            isNot(contains('state')),
            isNot(contains('token')),
          ),
        ),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 94,
        handle: 54,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'grant_type': 'revoke',
          'token': refreshedToken,
          'token_type_hint': 'refresh_token',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[94]?.isNotEmpty ?? false);
      expect(runtime.httpResponses[94]!.single.status, HttpStatus.ok);

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 95,
        handle: 55,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'locked-user',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[95]?.isNotEmpty ?? false);
      final recoveredChallenge = runtime.httpResponses[95]!.single;
      expect(recoveredChallenge.status, HttpStatus.unauthorized);
      expect(_jsonResponseBody(recoveredChallenge)['state'], isNotEmpty);
    },
  );

  test(
    'auth bridge rechecks grant capacity after challenge completion',
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
        settings: _buildRouterSettingsWithHttpAuthBridge(maxHttpAuthGrants: 1),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      Future<String> startChallenge({
        required int connectionId,
        required String authId,
      }) async {
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId - 40,
          method: 'POST',
          target: '/auth',
          headers: const {'content-type': 'application/json'},
          body: <String, Object?>{
            'realm': 'realm1',
            'authmethod': 'ticket',
            'authid': authId,
          },
          realm: 'router.http',
          procedure: 'router.http.auth',
        );
        await _waitUntil(
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        final response = runtime.httpResponses[connectionId]!.single;
        expect(response.status, HttpStatus.unauthorized);
        return _jsonResponseBody(response)['state'] as String;
      }

      Future<NativeHttpResponse> completeChallenge({
        required int connectionId,
        required String state,
        required String ticket,
      }) async {
        final authenticate = await TicketAuthentication(
          ticket,
        ).challenge(Extra());
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId - 40,
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
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[connectionId]!.single;
      }

      final firstState = await startChallenge(
        connectionId: 100,
        authId: 'user-1',
      );
      final secondState = await startChallenge(
        connectionId: 101,
        authId: 'locked-user',
      );
      final firstResponse = await completeChallenge(
        connectionId: 102,
        state: firstState,
        ticket: 'signed-token',
      );
      expect(firstResponse.status, HttpStatus.ok);

      final secondResponse = await completeChallenge(
        connectionId: 103,
        state: secondState,
        ticket: 'locked-user-token',
      );
      expect(secondResponse.status, HttpStatus.serviceUnavailable);
      expect(
        _jsonResponseBody(secondResponse),
        allOf(
          containsPair('reason', 'auth_grant_capacity_exhausted'),
          isNot(contains('state')),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
      );
    },
  );

  test('auth bridge reclaims expired access-only grant capacity', () async {
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
      settings: _buildRouterSettingsWithHttpAuthBridge(
        maxHttpAuthGrants: 1,
        tokenTtlMs: 500,
        refreshTokenTtlMs: 0,
      ),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    Future<NativeHttpResponse> startAuth({
      required int connectionId,
      required String authId,
    }) async {
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: connectionId,
        handle: connectionId - 40,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': authId,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(
        () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
      );
      return runtime.httpResponses[connectionId]!.single;
    }

    final firstChallenge = await startAuth(connectionId: 110, authId: 'user-1');
    final state = _jsonResponseBody(firstChallenge)['state'] as String;
    final authenticate = await TicketAuthentication(
      'signed-token',
    ).challenge(Extra());
    _enqueueSyntheticHttpRequest(
      runtime: runtime,
      listenerId: listenerId,
      connectionId: 111,
      handle: 71,
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
    await _waitUntil(() => runtime.httpResponses[111]?.isNotEmpty ?? false);
    final firstGrant = runtime.httpResponses[111]!.single;
    expect(firstGrant.status, HttpStatus.ok);
    expect(_jsonResponseBody(firstGrant)['access_token'], isNotEmpty);
    expect(_jsonResponseBody(firstGrant), isNot(contains('refresh_token')));

    final capacityResponse = await startAuth(
      connectionId: 112,
      authId: 'locked-user',
    );
    expect(capacityResponse.status, HttpStatus.serviceUnavailable);

    await Future<void>.delayed(const Duration(milliseconds: 600));
    final recoveredChallenge = await startAuth(
      connectionId: 113,
      authId: 'locked-user',
    );
    expect(recoveredChallenge.status, HttpStatus.unauthorized);
    expect(_jsonResponseBody(recoveredChallenge)['state'], isNotEmpty);
  });

  test(
    'auth bridge enforces failed-attempt lockout without blocking another identity',
    () async {
      AuthSecurityTracker.reset();
      AuthAuditLogger.clearSink();
      addTearDown(() {
        AuthAuditLogger.clearSink();
        AuthSecurityTracker.reset();
      });

      final runtime = _HandleRuntime();
      final events = <Map<String, Object?>>[];
      final auditEvents = <AuthAuditEvent>[];
      AuthAuditLogger.registerSink(auditEvents.add);
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
        settings: _buildRouterSettingsWithHttpAuthBridge(
          maxFailedAuth: 2,
          lockoutMs: 5000,
        ),
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
      var connectionId = 70;
      Future<NativeHttpResponse> sendAuth(Map<String, Object?> body) async {
        final currentConnectionId = connectionId++;
        runtime.setConnectionProtocol(
          currentConnectionId,
          NativeConnectionProtocol.http,
        );
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: currentConnectionId,
          handle: currentConnectionId,
          method: 'POST',
          target: '/auth',
          headers: const {'content-type': 'application/json'},
          body: body,
          realm: 'router.http',
          procedure: 'router.http.auth',
        );
        await _waitUntil(
          () => runtime.httpResponses[currentConnectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[currentConnectionId]!.single;
      }

      final dormantChallenge = await sendAuth(const <String, Object?>{
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'locked-user',
      });
      expect(dormantChallenge.status, HttpStatus.unauthorized);
      final dormantState =
          _jsonResponseBody(dormantChallenge)['state'] as String;

      for (var attempt = 0; attempt < 2; attempt++) {
        final challenge = await sendAuth(const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'locked-user',
        });
        expect(challenge.status, HttpStatus.unauthorized);
        final state = _jsonResponseBody(challenge)['state'] as String;
        final rejected = await sendAuth(<String, Object?>{
          'state': state,
          'signature': 'wrong-ticket',
        });
        expect(rejected.status, HttpStatus.unauthorized);
      }

      final lockedContinuation = await sendAuth(<String, Object?>{
        'state': dormantState,
        'signature': 'locked-user-token',
      });
      expect(lockedContinuation.status, HttpStatus.tooManyRequests);
      expect(
        _jsonResponseBody(lockedContinuation),
        allOf(
          containsPair('reason', 'auth_locked_out'),
          isNot(contains('state')),
          isNot(contains('access_token')),
        ),
      );

      final locked = await sendAuth(const <String, Object?>{
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'locked-user',
      });
      expect(locked.status, HttpStatus.tooManyRequests);
      final lockedBody = _jsonResponseBody(locked);
      expect(lockedBody['reason'], 'auth_locked_out');
      expect(lockedBody, isNot(contains('state')));
      expect(
        int.parse(locked.headers[HttpHeaders.retryAfterHeader]!),
        inInclusiveRange(1, 5),
      );
      expect(
        events,
        contains(
          allOf(
            containsPair('type', 'http_auth_locked_out'),
            containsPair('realm', 'realm1'),
            containsPair('authMethod', 'ticket'),
            isNot(contains('authId')),
            isNot(contains('signature')),
            isNot(contains('state')),
          ),
        ),
      );
      expect(
        auditEvents
            .where(
              (event) =>
                  event.outcome == AuthAuditOutcome.failure &&
                  event.authId == 'locked-user',
            )
            .length,
        4,
      );

      final otherRejectedChallenge = await sendAuth(const <String, Object?>{
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'user-1',
      });
      final otherRejectedState =
          _jsonResponseBody(otherRejectedChallenge)['state'] as String;
      final otherRejected = await sendAuth(<String, Object?>{
        'state': otherRejectedState,
        'signature': 'wrong-ticket',
      });
      expect(otherRejected.status, HttpStatus.unauthorized);

      final otherChallenge = await sendAuth(const <String, Object?>{
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'user-1',
      });
      expect(otherChallenge.status, HttpStatus.unauthorized);
      final otherState = _jsonResponseBody(otherChallenge)['state'] as String;
      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());
      final success = await sendAuth(<String, Object?>{
        'state': otherState,
        'signature': authenticate.signature,
        'extra': authenticate.extra,
      });
      expect(success.status, HttpStatus.ok);
      expect(_jsonResponseBody(success)['access_token'], isNotEmpty);
      expect(
        auditEvents,
        contains(
          isA<AuthAuditEvent>()
              .having(
                (event) => event.outcome,
                'outcome',
                AuthAuditOutcome.success,
              )
              .having((event) => event.authId, 'authId', 'user-1'),
        ),
      );

      final postSuccessRejectedChallenge = await sendAuth(
        const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
        },
      );
      final postSuccessRejectedState =
          _jsonResponseBody(postSuccessRejectedChallenge)['state'] as String;
      final postSuccessRejected = await sendAuth(<String, Object?>{
        'state': postSuccessRejectedState,
        'signature': 'wrong-ticket',
      });
      expect(postSuccessRejected.status, HttpStatus.unauthorized);

      final postSuccessChallenge = await sendAuth(const <String, Object?>{
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'user-1',
      });
      expect(postSuccessChallenge.status, HttpStatus.unauthorized);
      expect(_jsonResponseBody(postSuccessChallenge)['state'], isNotEmpty);
    },
  );

  test(
    'auth bridge bounds failed-auth records and releases successful capacity',
    () async {
      AuthSecurityTracker.reset();
      AuthAuditLogger.clearSink();
      addTearDown(() {
        AuthAuditLogger.clearSink();
        AuthSecurityTracker.reset();
      });

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
        settings: _buildRouterSettingsWithHttpAuthBridge(
          maxFailedAuth: 3,
          maxFailedAuthRecords: 1,
          lockoutMs: 5000,
        ),
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
      var connectionId = 170;
      Future<NativeHttpResponse> sendAuth(Map<String, Object?> body) async {
        final currentConnectionId = connectionId++;
        runtime.setConnectionProtocol(
          currentConnectionId,
          NativeConnectionProtocol.http,
        );
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: currentConnectionId,
          handle: currentConnectionId,
          method: 'POST',
          target: '/auth',
          headers: const {'content-type': 'application/json'},
          body: body,
          realm: 'router.http',
          procedure: 'router.http.auth',
        );
        await _waitUntil(
          () => runtime.httpResponses[currentConnectionId]?.isNotEmpty ?? false,
        );
        return runtime.httpResponses[currentConnectionId]!.single;
      }

      final firstChallenge = await sendAuth(const <String, Object?>{
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'user-1',
      });
      final firstState = _jsonResponseBody(firstChallenge)['state'] as String;
      final firstFailure = await sendAuth(<String, Object?>{
        'state': firstState,
        'signature': 'wrong-ticket',
      });
      expect(firstFailure.status, HttpStatus.unauthorized);

      final capacityRejected = await sendAuth(const <String, Object?>{
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'locked-user',
      });
      expect(capacityRejected.status, HttpStatus.tooManyRequests);
      expect(
        _jsonResponseBody(capacityRejected),
        allOf(
          containsPair('reason', 'auth_failure_capacity_exhausted'),
          isNot(contains('state')),
          isNot(contains('access_token')),
        ),
      );
      expect(
        int.parse(capacityRejected.headers[HttpHeaders.retryAfterHeader]!),
        inInclusiveRange(1, 5),
      );
      expect(
        events,
        contains(
          allOf(
            containsPair('type', 'http_auth_failure_capacity_exhausted'),
            containsPair('realm', 'realm1'),
            containsPair('authMethod', 'ticket'),
            containsPair('maxFailedAuthRecords', 1),
            isNot(contains('authId')),
            isNot(contains('signature')),
            isNot(contains('state')),
          ),
        ),
      );

      final trackedChallenge = await sendAuth(const <String, Object?>{
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'user-1',
      });
      final trackedState =
          _jsonResponseBody(trackedChallenge)['state'] as String;
      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());
      final trackedSuccess = await sendAuth(<String, Object?>{
        'state': trackedState,
        'signature': authenticate.signature,
        'extra': authenticate.extra,
      });
      expect(trackedSuccess.status, HttpStatus.ok);

      final recovered = await sendAuth(const <String, Object?>{
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'locked-user',
      });
      expect(recovered.status, HttpStatus.unauthorized);
      final recoveredState = _jsonResponseBody(recovered)['state'];
      expect(
        recoveredState,
        isA<String>().having((value) => value, 'state', isNotEmpty),
      );
      final recoveredSuccess = await sendAuth(<String, Object?>{
        'state': recoveredState,
        'signature': 'locked-user-token',
      });
      expect(recoveredSuccess.status, HttpStatus.ok);
    },
  );

  test('auth bridge timeout contributes to failed-attempt lockout', () async {
    AuthSecurityTracker.reset();
    AuthAuditLogger.clearSink();
    addTearDown(() {
      AuthAuditLogger.clearSink();
      AuthSecurityTracker.reset();
    });

    final runtime = _HandleRuntime();
    final auditEvents = <AuthAuditEvent>[];
    AuthAuditLogger.registerSink(auditEvents.add);
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
      settings: _buildRouterSettingsWithHttpAuthBridge(
        maxFailedAuth: 1,
        lockoutMs: 5000,
        authTimeoutMs: 1,
      ),
    );

    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    await Future<void>.delayed(Duration.zero);
    final listenerId = binding.listeners.single.listenerId;
    var connectionId = 90;
    Future<NativeHttpResponse> sendAuth(Map<String, Object?> body) async {
      final currentConnectionId = connectionId++;
      runtime.setConnectionProtocol(
        currentConnectionId,
        NativeConnectionProtocol.http,
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: currentConnectionId,
        handle: currentConnectionId,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: body,
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(
        () => runtime.httpResponses[currentConnectionId]?.isNotEmpty ?? false,
      );
      return runtime.httpResponses[currentConnectionId]!.single;
    }

    final challenge = await sendAuth(const <String, Object?>{
      'realm': 'realm1',
      'authmethod': 'ticket',
      'authid': 'locked-user',
    });
    expect(challenge.status, HttpStatus.unauthorized);
    expect(_jsonResponseBody(challenge)['state'], isNotEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 20));

    final locked = await sendAuth(const <String, Object?>{
      'realm': 'realm1',
      'authmethod': 'ticket',
      'authid': 'locked-user',
    });
    expect(locked.status, HttpStatus.tooManyRequests);
    expect(
      _jsonResponseBody(locked),
      allOf(
        containsPair('reason', 'auth_locked_out'),
        isNot(contains('state')),
      ),
    );
    expect(
      int.parse(locked.headers[HttpHeaders.retryAfterHeader]!),
      inInclusiveRange(1, 5),
    );
    expect(
      auditEvents,
      contains(
        isA<AuthAuditEvent>()
            .having(
              (event) => event.outcome,
              'outcome',
              AuthAuditOutcome.failure,
            )
            .having((event) => event.realmUri, 'realmUri', 'realm1')
            .having((event) => event.method, 'method', 'ticket')
            .having((event) => event.authId, 'authId', 'locked-user')
            .having((event) => event.message, 'message', 'challenge timeout'),
      ),
    );
  });

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

  test('auth bridge accepts only one overlapping refresh token use', () async {
    for (final rotateRefreshTokens in <bool>[true, false]) {
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
        settings: _buildRouterSettingsWithHttpAuthBridge(
          maxHttpAuthGrants: 1,
          rotateRefreshTokens: rotateRefreshTokens,
        ),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      final callee = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'svc-refresh-concurrency',
        authRole: 'internal',
        roles: const {'callee': <String, Object?>{}},
      );
      addTearDown(callee.close);
      final registration = await callee.register('com.example.api.secure');
      registration.onInvoke((invocation) {
        final context = HttpInvocationContext.maybeFromInvocation(invocation);
        context!.sendText(body: 'secured', status: HttpStatus.ok);
      });
      final connectionBase = rotateRefreshTokens ? 110 : 130;
      final grant = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
        startConnectionId: connectionBase,
      );

      void enqueueRefresh(int connectionId) {
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId - 40,
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
      }

      enqueueRefresh(connectionBase + 2);
      enqueueRefresh(connectionBase + 3);
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: connectionBase + 4,
        handle: connectionBase - 36,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'capacity-user',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(
        () =>
            (runtime.httpResponses[connectionBase + 2]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[connectionBase + 3]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[connectionBase + 4]?.isNotEmpty ?? false),
      );

      final refreshResponses = <NativeHttpResponse>[
        runtime.httpResponses[connectionBase + 2]!.single,
        runtime.httpResponses[connectionBase + 3]!.single,
      ];
      expect(
        refreshResponses.map((response) => response.status),
        unorderedEquals(<int>[HttpStatus.ok, HttpStatus.unauthorized]),
        reason:
            'exactly one ${rotateRefreshTokens ? 'rotating' : 'reusable'} '
            'refresh request must win',
      );
      final accepted = refreshResponses.singleWhere(
        (response) => response.status == HttpStatus.ok,
      );
      final rejected = refreshResponses.singleWhere(
        (response) => response.status == HttpStatus.unauthorized,
      );
      final acceptedBody = _jsonResponseBody(accepted);
      final rejectedBody = _jsonResponseBody(rejected);
      expect(rejectedBody['reason'], 'invalid_refresh_token');
      expect(rejectedBody, isNot(contains('access_token')));
      expect(rejectedBody, isNot(contains('refresh_token')));
      final capacityResponse =
          runtime.httpResponses[connectionBase + 4]!.single;
      expect(capacityResponse.status, HttpStatus.serviceUnavailable);
      expect(
        _jsonResponseBody(capacityResponse),
        allOf(
          containsPair('reason', 'auth_grant_capacity_exhausted'),
          isNot(contains('state')),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
      );

      final winningAccessToken = acceptedBody['access_token'] as String;
      final winningRefreshToken = acceptedBody['refresh_token'] as String;
      expect(winningAccessToken, isNot(grant.accessToken));
      expect(
        winningRefreshToken,
        rotateRefreshTokens ? isNot(grant.refreshToken) : grant.refreshToken,
      );

      void enqueueProtectedRequest(int connectionId, String accessToken) {
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: connectionId - 40,
          method: 'GET',
          target: '/api/secure',
          headers: <String, String>{'authorization': 'Bearer $accessToken'},
          body: null,
          realm: 'realm1',
          procedure: 'com.example.api.secure',
        );
      }

      enqueueProtectedRequest(connectionBase + 5, winningAccessToken);
      await _waitUntil(
        () => runtime.httpResponses[connectionBase + 5]?.isNotEmpty ?? false,
      );
      expect(
        runtime.httpResponses[connectionBase + 5]!.single.status,
        HttpStatus.ok,
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: connectionBase + 6,
        handle: connectionBase - 34,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'grant_type': 'revoke',
          'token': winningRefreshToken,
          'token_type_hint': 'refresh_token',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(
        () => runtime.httpResponses[connectionBase + 6]?.isNotEmpty ?? false,
      );
      expect(
        runtime.httpResponses[connectionBase + 6]!.single.status,
        HttpStatus.ok,
      );

      enqueueProtectedRequest(connectionBase + 7, winningAccessToken);
      await _waitUntil(
        () => runtime.httpResponses[connectionBase + 7]?.isNotEmpty ?? false,
      );
      final revokedAccess = runtime.httpResponses[connectionBase + 7]!.single;
      expect(revokedAccess.status, HttpStatus.unauthorized);
      expect(_jsonResponseBody(revokedAccess)['reason'], 'invalid_token');

      final revocationRaceGrant = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
        startConnectionId: connectionBase + 10,
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: connectionBase + 12,
        handle: connectionBase - 28,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': revocationRaceGrant.refreshToken,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: connectionBase + 13,
        handle: connectionBase - 27,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'grant_type': 'revoke',
          'token': revocationRaceGrant.refreshToken,
          'token_type_hint': 'refresh_token',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(
        () =>
            (runtime.httpResponses[connectionBase + 12]?.isNotEmpty ?? false) &&
            (runtime.httpResponses[connectionBase + 13]?.isNotEmpty ?? false),
      );
      final refreshDuringRevocation =
          runtime.httpResponses[connectionBase + 12]!.single;
      expect(refreshDuringRevocation.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(refreshDuringRevocation),
        allOf(
          containsPair('reason', 'invalid_refresh_token'),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
      );
      expect(
        runtime.httpResponses[connectionBase + 13]!.single.status,
        HttpStatus.ok,
      );

      enqueueProtectedRequest(
        connectionBase + 14,
        revocationRaceGrant.accessToken,
      );
      await _waitUntil(
        () => runtime.httpResponses[connectionBase + 14]?.isNotEmpty ?? false,
      );
      expect(
        runtime.httpResponses[connectionBase + 14]!.single.status,
        HttpStatus.unauthorized,
      );
    }
  });

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
        connectionId: 76,
        handle: 36,
        method: 'POST',
        target: '/mcp/secure',
        headers: {
          'authorization': 'Bearer ${firstGrant.accessToken}',
          'Accept': 'application/json',
          'accept': 'text/event-stream',
          'content-type': 'application/json',
          'mcp-protocol-version': '2025-11-25',
          'mcp-method': 'initialize',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'refresh-session-initialize',
          'method': 'initialize',
          'params': <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
            'clientInfo': <String, Object?>{
              'name': 'router-runtime-auth-refresh-test',
              'version': '0.1.0',
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[76]?.isNotEmpty ?? false);
      final initializeResponse = runtime.httpResponses[76]!.single;
      expect(initializeResponse.status, HttpStatus.ok);
      final mcpSessionId = initializeResponse.headers['MCP-Session-Id'];
      expect(mcpSessionId, isNotNull);
      expect(mcpSessionId, isNotEmpty);

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 67,
        handle: 27,
        method: 'DELETE',
        target: '/mcp/secure',
        headers: {
          'MCP-Session-Id': mcpSessionId!,
          'mcp-session-id': 'conflicting-session-id',
          'mcp-protocol-version': '2025-11-25',
        },
        body: null,
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[67]?.isNotEmpty ?? false);
      final unauthenticatedRepeatedSession = runtime.httpResponses[67]!.single;
      expect(
        unauthenticatedRepeatedSession.status,
        HttpStatus.unauthorized,
      );
      expect(
        unauthenticatedRepeatedSession.headers,
        isNot(contains('MCP-Session-Id')),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 68,
        handle: 28,
        method: 'DELETE',
        target: '/mcp/secure',
        headers: {
          'authorization': 'Bearer ${firstGrant.accessToken}',
          'MCP-Session-Id': mcpSessionId,
          'mcp-session-id': 'conflicting-session-id',
          'mcp-protocol-version': '2025-11-25',
        },
        body: null,
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[68]?.isNotEmpty ?? false);
      final authenticatedRepeatedSession = runtime.httpResponses[68]!.single;
      expect(authenticatedRepeatedSession.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(authenticatedRepeatedSession).toString(),
        contains('Invalid MCP-Session-Id header'),
      );
      expect(
        authenticatedRepeatedSession.headers,
        isNot(contains('MCP-Session-Id')),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 79,
        handle: 39,
        method: 'DELETE',
        target: '/mcp/secure',
        headers: {
          'MCP-Session-Id': mcpSessionId,
          'MCP-Protocol-Version': '2025-11-25',
          'mcp-protocol-version': '2026-07-28',
        },
        body: null,
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[79]?.isNotEmpty ?? false);
      final unauthenticatedRepeatedProtocol = runtime.httpResponses[79]!.single;
      expect(
        unauthenticatedRepeatedProtocol.status,
        HttpStatus.unauthorized,
      );
      expect(
        unauthenticatedRepeatedProtocol.headers,
        isNot(contains('MCP-Session-Id')),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 80,
        handle: 40,
        method: 'DELETE',
        target: '/mcp/secure',
        headers: {
          'authorization': 'Bearer ${firstGrant.accessToken}',
          'MCP-Session-Id': mcpSessionId,
          'MCP-Protocol-Version': '2025-11-25',
          'mcp-protocol-version': '2026-07-28',
        },
        body: null,
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[80]?.isNotEmpty ?? false);
      final authenticatedRepeatedProtocol = runtime.httpResponses[80]!.single;
      expect(authenticatedRepeatedProtocol.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(authenticatedRepeatedProtocol).toString(),
        contains('Invalid MCP-Protocol-Version header'),
      );
      expect(
        authenticatedRepeatedProtocol.headers,
        isNot(contains('MCP-Session-Id')),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 81,
        handle: 41,
        method: 'GET',
        target: '/mcp/secure',
        headers: {
          'accept': 'text/event-stream',
          'MCP-Session-Id': mcpSessionId,
          'MCP-Protocol-Version': '2025-11-25',
          'Last-Event-ID': 'unknown-resume-cursor',
          'last-event-id': 'conflicting-resume-cursor',
        },
        body: null,
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[81]?.isNotEmpty ?? false);
      final unauthenticatedRepeatedLastEventId =
          runtime.httpResponses[81]!.single;
      expect(
        unauthenticatedRepeatedLastEventId.status,
        HttpStatus.unauthorized,
      );
      expect(
        unauthenticatedRepeatedLastEventId.headers,
        isNot(contains('MCP-Session-Id')),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 82,
        handle: 42,
        method: 'GET',
        target: '/mcp/secure',
        headers: {
          'accept': 'text/event-stream',
          'authorization': 'Bearer ${firstGrant.accessToken}',
          'MCP-Session-Id': mcpSessionId,
          'MCP-Protocol-Version': '2025-11-25',
          'Last-Event-ID': 'unknown-resume-cursor',
          'last-event-id': 'conflicting-resume-cursor',
        },
        body: null,
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[82]?.isNotEmpty ?? false);
      final authenticatedRepeatedLastEventId =
          runtime.httpResponses[82]!.single;
      expect(authenticatedRepeatedLastEventId.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(authenticatedRepeatedLastEventId).toString(),
        contains('Invalid Last-Event-ID header'),
      );
      expect(
        authenticatedRepeatedLastEventId.headers['MCP-Session-Id'],
        mcpSessionId,
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 83,
        handle: 43,
        method: 'POST',
        target: '/mcp/secure',
        headers: {
          'accept': 'application/json, text/event-stream',
          'MCP-Session-Id': mcpSessionId,
          'MCP-Protocol-Version': '2025-11-25',
          'Content-Type': 'application/json',
          'content-type': 'text/plain',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
          'params': <String, Object?>{},
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[83]?.isNotEmpty ?? false);
      final unauthenticatedRepeatedContentType =
          runtime.httpResponses[83]!.single;
      expect(
        unauthenticatedRepeatedContentType.status,
        HttpStatus.unauthorized,
      );
      expect(
        unauthenticatedRepeatedContentType.headers,
        isNot(contains('MCP-Session-Id')),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 84,
        handle: 44,
        method: 'POST',
        target: '/mcp/secure',
        headers: {
          'accept': 'application/json, text/event-stream',
          'authorization': 'Bearer ${firstGrant.accessToken}',
          'MCP-Session-Id': mcpSessionId,
          'MCP-Protocol-Version': '2025-11-25',
          'Content-Type': 'application/json',
          'content-type': 'text/plain',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
          'params': <String, Object?>{},
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[84]?.isNotEmpty ?? false);
      final authenticatedRepeatedContentType =
          runtime.httpResponses[84]!.single;
      expect(authenticatedRepeatedContentType.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(authenticatedRepeatedContentType).toString(),
        contains('Invalid Content-Type header'),
      );
      expect(
        authenticatedRepeatedContentType.headers['MCP-Session-Id'],
        mcpSessionId,
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 85,
        handle: 45,
        method: 'POST',
        target: '/mcp/secure',
        headers: {
          'accept': 'application/json, text/event-stream',
          'authorization': 'Bearer ${firstGrant.accessToken}',
          'MCP-Protocol-Version': '2025-11-25',
          'Content-Type': 'application/json',
          'content-type': 'text/plain',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'repeated-content-type-initialize',
          'method': 'initialize',
          'params': <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
            'clientInfo': <String, Object?>{
              'name': 'router-runtime-content-type-test',
              'version': '0.1.0',
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[85]?.isNotEmpty ?? false);
      final repeatedInitialContentType = runtime.httpResponses[85]!.single;
      expect(repeatedInitialContentType.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(repeatedInitialContentType).toString(),
        contains('Invalid Content-Type header'),
      );
      expect(
        repeatedInitialContentType.headers,
        isNot(contains('MCP-Session-Id')),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 86,
        handle: 46,
        method: 'POST',
        target: '/mcp/secure',
        headers: {
          'accept': 'application/json, text/event-stream',
          'authorization': 'Bearer ${firstGrant.accessToken}',
          'MCP-Session-Id': 'unknown-content-type-session',
          'MCP-Protocol-Version': '2025-11-25',
          'Content-Type': 'application/json',
          'content-type': 'text/plain',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'unknown-session-content-type',
          'method': 'ping',
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[86]?.isNotEmpty ?? false);
      final unknownSessionRepeatedContentType =
          runtime.httpResponses[86]!.single;
      expect(unknownSessionRepeatedContentType.status, HttpStatus.notFound);
      expect(
        unknownSessionRepeatedContentType.headers,
        isNot(contains('MCP-Session-Id')),
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 78,
        handle: 38,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': firstGrant.refreshToken,
          'token': 'different-refresh-token',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[78]?.isNotEmpty ?? false);
      final conflictingRefresh = runtime.httpResponses[78]!.single;
      expect(conflictingRefresh.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(conflictingRefresh),
        allOf(
          containsPair('status', 'error'),
          containsPair('reason', 'conflicting_auth_parameter'),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
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

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 77,
        handle: 37,
        method: 'DELETE',
        target: '/mcp/secure',
        headers: {
          'authorization': 'Bearer $refreshedAccessToken',
          'mcp-session-id': mcpSessionId,
          'mcp-protocol-version': '2025-11-25',
        },
        body: null,
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[77]?.isNotEmpty ?? false);
      final refreshedSessionDelete = runtime.httpResponses[77]!.single;
      expect(refreshedSessionDelete.status, HttpStatus.accepted);
      expect(refreshedSessionDelete.headers['MCP-Session-Id'], mcpSessionId);

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

  test(
    'auth bridge binds initial realm selectors to configured route policy',
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
        settings: _buildRouterSettingsWithHttpAuthRealmPolicyBinding(),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;

      for (var attempt = 0; attempt < 3; attempt++) {
        final connectionId = 120 + attempt;
        _enqueueSyntheticHttpRequest(
          runtime: runtime,
          listenerId: listenerId,
          connectionId: connectionId,
          handle: 80 + attempt,
          method: 'POST',
          target: '/auth',
          query: attempt == 1 ? 'realm=realm2' : null,
          headers: <String, String>{
            'content-type': 'application/json',
            if (attempt == 2) 'x-connectanum-realm': 'realm2',
          },
          body: <String, Object?>{
            if (attempt == 0) 'realm': 'realm2',
            'authmethod': 'ticket',
            'authid': 'user-1',
          },
          realm: 'router.http',
          procedure: 'router.http.auth',
        );
        await _waitUntil(
          () => runtime.httpResponses[connectionId]?.isNotEmpty ?? false,
        );
        final rejected = runtime.httpResponses[connectionId]!.single;
        expect(rejected.status, HttpStatus.unauthorized);
        expect(_jsonResponseBody(rejected)['reason'], 'wrong_realm');
        expect(
          _jsonResponseBody(rejected),
          isNot(anyOf(contains('state'), contains('access_token'))),
        );
      }

      final grant = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
        startConnectionId: 123,
        realm: null,
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 125,
        handle: 85,
        method: 'POST',
        target: '/mcp/secure',
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
          'mcp-protocol-version': '2026-07-28',
          'mcp-method': 'tools/list',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'configured-realm-access',
          'method': 'tools/list',
          'params': <String, Object?>{
            '_meta': <String, Object?>{
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[125]?.isNotEmpty ?? false);
      expect(runtime.httpResponses[125]!.single.status, HttpStatus.ok);
    },
  );

  test(
    'auth bridge binds challenge and refresh policy to the issuing route',
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
        settings: _buildRouterSettingsWithHttpAuthRouteIsolation(),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      final baselineSessionCount =
          (await binding.collectMetrics()).sessionCount;

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 90,
        handle: 50,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[90]?.isNotEmpty ?? false);
      final challengeResponse = runtime.httpResponses[90]!.single;
      expect(challengeResponse.status, HttpStatus.unauthorized);
      final challenge = _jsonResponseBody(challengeResponse);
      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 91,
        handle: 51,
        method: 'POST',
        target: '/auth/alternate',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'state': challenge['state'],
          'signature': authenticate.signature,
          'extra': authenticate.extra,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[91]?.isNotEmpty ?? false);
      final crossRouteCompletion = runtime.httpResponses[91]!.single;
      expect(crossRouteCompletion.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(crossRouteCompletion)['reason'],
        'wrong_auth_route',
      );
      expect(
        _jsonResponseBody(crossRouteCompletion),
        isNot(anyOf(contains('access_token'), contains('refresh_token'))),
      );

      final grant = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
        startConnectionId: 92,
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 94,
        handle: 54,
        method: 'POST',
        target: '/auth/alternate',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': grant.refreshToken,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[94]?.isNotEmpty ?? false);
      final crossRouteRefresh = runtime.httpResponses[94]!.single;
      expect(crossRouteRefresh.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(crossRouteRefresh)['reason'],
        'wrong_auth_route',
      );
      expect(
        _jsonResponseBody(crossRouteRefresh),
        isNot(anyOf(contains('access_token'), contains('refresh_token'))),
      );
      expect(
        (await binding.collectMetrics()).sessionCount,
        baselineSessionCount,
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 95,
        handle: 55,
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
      await _waitUntil(() => runtime.httpResponses[95]?.isNotEmpty ?? false);
      final refreshed = runtime.httpResponses[95]!.single;
      expect(refreshed.status, HttpStatus.ok);
      final refreshedBody = _jsonResponseBody(refreshed);
      final refreshedAccessToken = refreshedBody['access_token'] as String;
      expect(refreshedBody['refresh_token'], isNot(grant.refreshToken));

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 96,
        handle: 56,
        method: 'POST',
        target: '/mcp/secure',
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $refreshedAccessToken',
          'mcp-protocol-version': '2026-07-28',
          'mcp-method': 'tools/list',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'same-route-refreshed-access',
          'method': 'tools/list',
          'params': <String, Object?>{
            '_meta': <String, Object?>{
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[96]?.isNotEmpty ?? false);
      expect(runtime.httpResponses[96]!.single.status, HttpStatus.ok);
    },
  );

  test(
    'auth bridge binds challenges and grants to the issuing profile',
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
        settings: _buildRouterSettingsWithHttpAuthProfileIsolation(),
      );

      final binding = router.start(runtime);
      addTearDown(binding.dispose);
      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      final baselineSessionCount =
          (await binding.collectMetrics()).sessionCount;

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 89,
        handle: 49,
        method: 'POST',
        target: '/mcp/secure-alternate',
        headers: const <String, String>{
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          HttpHeaders.contentTypeHeader: 'application/json',
          'mcp-protocol-version': '2026-07-28',
          'mcp-method': 'tools/list',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'alternate-profile-auth-discovery',
          'method': 'tools/list',
          'params': <String, Object?>{
            '_meta': <String, Object?>{
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[89]?.isNotEmpty ?? false);
      final discoveryResponse = runtime.httpResponses[89]!.single;
      expect(discoveryResponse.status, HttpStatus.unauthorized);
      expect(
        discoveryResponse.headers['www-authenticate'],
        contains('auth_path="/auth/alternate"'),
      );
      expect(
        discoveryResponse.headers['www-authenticate'],
        isNot(contains('auth_path="/auth"')),
      );
      expect(discoveryResponse.headers, isNot(contains('mcp-session-id')));

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 90,
        handle: 50,
        method: 'POST',
        target: '/auth',
        headers: const {'content-type': 'application/json'},
        body: const <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'user-1',
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[90]?.isNotEmpty ?? false);
      final challenge = _jsonResponseBody(runtime.httpResponses[90]!.single);
      final authenticate = await TicketAuthentication(
        'signed-token',
      ).challenge(Extra());

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 91,
        handle: 51,
        method: 'POST',
        target: '/auth/alternate',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'state': challenge['state'],
          'signature': authenticate.signature,
          'extra': authenticate.extra,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[91]?.isNotEmpty ?? false);
      final crossProfileCompletion = runtime.httpResponses[91]!.single;
      expect(crossProfileCompletion.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(crossProfileCompletion)['reason'],
        'wrong_session_profile',
      );
      expect(
        _jsonResponseBody(crossProfileCompletion),
        isNot(anyOf(contains('access_token'), contains('refresh_token'))),
      );

      final grant = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
        startConnectionId: 92,
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 94,
        handle: 54,
        method: 'POST',
        target: '/mcp/secure-alternate',
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
          'mcp-protocol-version': '2026-07-28',
          'mcp-method': 'tools/list',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'cross-profile-access',
          'method': 'tools/list',
          'params': <String, Object?>{
            '_meta': <String, Object?>{
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[94]?.isNotEmpty ?? false);
      final crossProfileAccess = runtime.httpResponses[94]!.single;
      expect(crossProfileAccess.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(crossProfileAccess)['reason'],
        'wrong_session_profile',
      );
      expect(crossProfileAccess.headers, isNot(contains('MCP-Session-Id')));

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 95,
        handle: 55,
        method: 'POST',
        target: '/auth/alternate',
        headers: const {'content-type': 'application/json'},
        body: <String, Object?>{
          'grant_type': 'refresh_token',
          'refresh_token': grant.refreshToken,
        },
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(() => runtime.httpResponses[95]?.isNotEmpty ?? false);
      final crossProfileRefresh = runtime.httpResponses[95]!.single;
      expect(crossProfileRefresh.status, HttpStatus.unauthorized);
      expect(
        _jsonResponseBody(crossProfileRefresh)['reason'],
        'wrong_session_profile',
      );
      expect(
        _jsonResponseBody(crossProfileRefresh),
        isNot(anyOf(contains('access_token'), contains('refresh_token'))),
      );
      expect(
        (await binding.collectMetrics()).sessionCount,
        baselineSessionCount,
      );

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 96,
        handle: 56,
        method: 'POST',
        target: '/mcp/secure',
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer ${grant.accessToken}',
          'mcp-protocol-version': '2026-07-28',
          'mcp-method': 'tools/list',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'same-profile-access',
          'method': 'tools/list',
          'params': <String, Object?>{
            '_meta': <String, Object?>{
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[96]?.isNotEmpty ?? false);
      expect(runtime.httpResponses[96]!.single.status, HttpStatus.ok);

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 97,
        handle: 57,
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
      await _waitUntil(() => runtime.httpResponses[97]?.isNotEmpty ?? false);
      final refreshed = runtime.httpResponses[97]!.single;
      expect(refreshed.status, HttpStatus.ok);
      final refreshedAccessToken =
          _jsonResponseBody(refreshed)['access_token'] as String;

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 98,
        handle: 58,
        method: 'POST',
        target: '/mcp/secure',
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $refreshedAccessToken',
          'mcp-protocol-version': '2026-07-28',
          'mcp-method': 'tools/list',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'same-profile-refreshed-access',
          'method': 'tools/list',
          'params': <String, Object?>{
            '_meta': <String, Object?>{
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[98]?.isNotEmpty ?? false);
      expect(runtime.httpResponses[98]!.single.status, HttpStatus.ok);

      final alternateGrant = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
        startConnectionId: 100,
        authPath: '/auth/alternate',
      );
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: 102,
        handle: 62,
        method: 'POST',
        target: '/mcp/secure-alternate',
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader:
              'Bearer ${alternateGrant.accessToken}',
          'mcp-protocol-version': '2026-07-28',
          'mcp-method': 'tools/list',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'alternate-profile-access',
          'method': 'tools/list',
          'params': <String, Object?>{
            '_meta': <String, Object?>{
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );
      await _waitUntil(() => runtime.httpResponses[102]?.isNotEmpty ?? false);
      final alternateAccess = runtime.httpResponses[102]!.single;
      expect(alternateAccess.status, HttpStatus.ok);
      expect(alternateAccess.headers, isNot(contains('mcp-session-id')));
    },
  );

  test(
    'auth bridge revocation fences overlapping MCP session creation',
    () async {
      final runtime = _HandleRuntime();
      late int listenerId;
      late String accessToken;
      var revokeQueued = false;
      const protectedConnectionId = 88;
      const revokeConnectionId = 89;
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
          if (event is! Map<String, Object?> ||
              event['type'] != 'listener_http_request' ||
              event['connectionId'] != protectedConnectionId ||
              revokeQueued) {
            return;
          }
          revokeQueued = true;
          _enqueueSyntheticHttpRequest(
            runtime: runtime,
            listenerId: listenerId,
            connectionId: revokeConnectionId,
            handle: 49,
            method: 'POST',
            target: '/auth',
            headers: const {'content-type': 'application/json'},
            body: <String, Object?>{
              'grant_type': 'revoke',
              'token': accessToken,
              'token_type_hint': 'access_token',
            },
            realm: 'router.http',
            procedure: 'router.http.auth',
          );
        },
      );
      addTearDown(binding.dispose);

      await Future<void>.delayed(Duration.zero);
      listenerId = binding.listeners.single.listenerId;
      final grant = await _issueTicketHttpTokens(
        runtime: runtime,
        listenerId: listenerId,
        startConnectionId: 86,
      );
      accessToken = grant.accessToken;
      final baselineSessionCount =
          (await binding.collectMetrics()).sessionCount;

      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: protectedConnectionId,
        handle: 48,
        method: 'POST',
        target: '/mcp/secure',
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'application/json, text/event-stream',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $accessToken',
          'mcp-protocol-version': '2026-07-28',
          'mcp-method': 'tools/list',
        },
        body: const <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'revoked-first-request',
          'method': 'tools/list',
          'params': <String, Object?>{
            '_meta': <String, Object?>{
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
          },
        },
        realm: 'realm1',
        procedure: 'router.http.mcp',
      );

      await _waitUntil(
        () =>
            runtime.httpResponses[protectedConnectionId]?.isNotEmpty == true &&
            runtime.httpResponses[revokeConnectionId]?.isNotEmpty == true,
      );
      expect(revokeQueued, isTrue);
      expect(
        runtime.httpResponses[revokeConnectionId]!.single.status,
        HttpStatus.ok,
      );

      final protectedResponse =
          runtime.httpResponses[protectedConnectionId]!.single;
      expect(protectedResponse.status, HttpStatus.unauthorized);
      expect(protectedResponse.headers, isNot(contains('MCP-Session-Id')));
      expect(
        _jsonResponseBody(protectedResponse)['reason'],
        'invalid_token',
      );

      var finalSessionCount = (await binding.collectMetrics()).sessionCount;
      for (
        var attempt = 0;
        attempt < 50 && finalSessionCount != baselineSessionCount;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        finalSessionCount = (await binding.collectMetrics()).sessionCount;
      }
      expect(finalSessionCount, baselineSessionCount);
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

    for (final conflict
        in <
          ({
            int connectionId,
            Map<String, String> headers,
            Map<String, Object?> body,
          })
        >[
          (
            connectionId: 85,
            headers: const {'content-type': 'application/json'},
            body: <String, Object?>{
              'grant_type': 'revoke',
              'token': grant.refreshToken,
              'refresh_token': 'different-revoke-token',
              'token_type_hint': 'refresh_token',
            },
          ),
          (
            connectionId: 86,
            headers: const {
              'content-type': 'application/json',
              'x-connectanum-token-type-hint': 'access_token',
            },
            body: <String, Object?>{
              'grant_type': 'revoke',
              'token': grant.refreshToken,
              'token_type_hint': 'refresh_token',
            },
          ),
        ]) {
      _enqueueSyntheticHttpRequest(
        runtime: runtime,
        listenerId: listenerId,
        connectionId: conflict.connectionId,
        handle: conflict.connectionId - 40,
        method: 'POST',
        target: '/auth',
        headers: conflict.headers,
        body: conflict.body,
        realm: 'router.http',
        procedure: 'router.http.auth',
      );
      await _waitUntil(
        () => runtime.httpResponses[conflict.connectionId]?.isNotEmpty ?? false,
      );
      final response = runtime.httpResponses[conflict.connectionId]!.single;
      expect(response.status, HttpStatus.badRequest);
      expect(
        _jsonResponseBody(response),
        allOf(
          containsPair('status', 'error'),
          containsPair('reason', 'conflicting_auth_parameter'),
          isNot(contains('access_token')),
          isNot(contains('refresh_token')),
        ),
      );
    }

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

  for (final mode in ['fallback', 'direct', 'hybrid']) {
    final direct = mode != 'fallback';
    final fallback = mode != 'direct';
    for (final failCall in [false, true]) {
      for (final throwObserver in [false, true]) {
        test(
          'HTTP stream cleanup mode=$mode error=$failCall observer=$throwObserver',
          () async {
            final runtime = _HttpCleanupRuntime(direct: direct);
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
            final errors = <Object>[];
            final releasesWhenErrorEscapes = <List<int>>[];
            final handshakes = [
              _TrackedHttpHandshake(9001),
              _TrackedHttpHandshake(9002),
            ];
            final finishEvents = <Map<String, Object?>>[];
            final observerError = StateError('controlled diagnostic failure');
            final binding = runZonedGuarded(
              () => router.start(
                runtime,
                onEvent: (event) {
                  if (event is Map<String, Object?> &&
                      event['type'] == 'http_response_stream_finish_error') {
                    finishEvents.add(event);
                    if (throwObserver) throw observerError;
                  }
                },
              ),
              (error, _) {
                errors.add(error);
                releasesWhenErrorEscapes.add([
                  for (final handshake in handshakes) handshake.releases,
                ]);
              },
            )!;
            addTearDown(binding.dispose);
            final session = await binding.createInternalSession(
              realmUri: 'realm1',
            );
            final registration = await session.register(
              'com.example.api.stream',
            );
            final contexts = <HttpInvocationContext>[];
            registration.onInvoke((invocation) {
              contexts.add(
                HttpInvocationContext.maybeFromInvocation(invocation)!,
              );
            });
            for (var index = 0; index < handshakes.length; index++) {
              runtime.setConnectionProtocol(
                56 + index,
                NativeConnectionProtocol.http,
              );
              runtime.enqueueHttpHandshake(
                binding.listeners.single.listenerId,
                56 + index,
                handshakes[index],
              );
            }
            await _waitUntil(() => contexts.length == 2);
            final first = contexts[0];
            final second = contexts[1];
            expect(first.requestId, isNot(second.requestId));
            expect(handshakes.map((value) => value.releases), [0, 0]);

            Future<Map<Object?, Object?>> requestDescriptor() async {
              final reply = ReceivePort();
              try {
                final port =
                    first.invocation.details.custom[HttpInvocationKeys
                            .responseStreamControlPort]
                        as SendPort;
                port.send({
                  'type': HttpInvocationControlMessages.openResponseStream,
                  'requestId': first.requestId,
                  'status': 206,
                  'headers': <String, String>{'x-stream': 'cleanup'},
                  'replyPort': reply.sendPort,
                });
                return Map<Object?, Object?>.from(
                  await reply.first.timeout(const Duration(seconds: 2)) as Map,
                );
              } finally {
                reply.close();
              }
            }

            if (direct) {
              expect((await requestDescriptor())['handle'], 0x7fffffff);
            }
            if (fallback) {
              HttpResponseUtil.respond(
                first.invocation,
                HttpResponseUtil.bytes(
                  requestId: first.requestId,
                  status: 206,
                  body: Uint8List.fromList([1, 2, 3]),
                ),
                progress: true,
              );
              await _waitUntil(() => runtime.responseStreamChunks.isNotEmpty);
              expect(runtime.responseStreamChunks, {
                9001: [
                  [1, 2, 3],
                ],
              });
            }

            if (failCall) {
              first.invocation.respondWith(
                isError: true,
                errorUri: 'com.example.failed',
              );
            } else if (!fallback) {
              first.invocation.respondWith();
            } else {
              first.sendBytes(body: Uint8List.fromList([4, 5]));
            }
            final expectedFinishErrors = [
              if (fallback) runtime.finishError.toString(),
              if (direct && (fallback || failCall)) 'native handle unavailable',
            ];
            final expectsFinishError = expectedFinishErrors.isNotEmpty;
            await _waitUntil(
              () =>
                  handshakes.first.releases != 0 ||
                  finishEvents.isNotEmpty ||
                  errors.isNotEmpty,
            );
            // The control protocol is a public observable completion barrier:
            // no late stream may be opened for a completed HTTP request.
            expect(await requestDescriptor(), {
              'error': 'pending_http_request_not_found',
            });
            expect(handshakes.first.releases, 1);
            expect(
              releasesWhenErrorEscapes,
              throwObserver && expectsFinishError
                  ? [
                      [1, 0],
                    ]
                  : isEmpty,
              reason:
                  'Owned resources must be released before reporting an uncaught observer error',
            );
            expect(
              handshakes.last.releases,
              0,
              reason: 'Independent request is still active',
            );
            expect(runtime.finishAttempts, fallback ? [9001] : isEmpty);
            expect(
              errors,
              throwObserver && expectsFinishError
                  ? [same(observerError)]
                  : isEmpty,
            );
            expect(finishEvents, hasLength(expectedFinishErrors.length));
            for (var index = 0; index < finishEvents.length; index++) {
              final event = finishEvents[index];
              expect(event['httpRequestId'], first.requestId);
              expect(event['error'], contains(expectedFinishErrors[index]));
              expect(event['stackTrace'], isNotEmpty);
            }
            if (fallback) {
              expect(
                runtime.responseStreamChunks[9001],
                failCall
                    ? [
                        [1, 2, 3],
                      ]
                    : [
                        [1, 2, 3],
                        [4, 5],
                      ],
              );
            }

            second.sendText(body: 'independent response', status: 207);
            await _waitUntil(() => handshakes.last.releases != 0);
            expect(handshakes.map((value) => value.releases), [1, 1]);
            expect(runtime.httpResponses[57]!.single.status, 207);
            expect(finishEvents, hasLength(expectedFinishErrors.length));
          },
        );
      }
    }
  }

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

  test('applies caller disclosure policy across internal sessions', () async {
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
      authId: 'caller-a',
      authRole: 'member',
    );
    final callee = await binding.createInternalSession(
      realmUri: 'realm1',
      authId: 'callee-a',
      authRole: 'member',
    );
    addTearDown(caller.close);
    addTearDown(callee.close);

    final seenInvocation = Completer<void>();
    final registration = await callee.register(
      'com.example.disclose',
      options: RegisterOptions(discloseCaller: true),
    );
    registration.onInvoke((invocation) {
      expect(invocation.details.caller, caller.sessionId);
      expect(invocation.details.custom['caller_authid'], 'caller-a');
      expect(invocation.details.custom['caller_authrole'], 'member');
      expect(invocation.details.custom['trace_id'], 'trace-1');
      expect(invocation.details.custom.containsKey('authid'), isFalse);
      expect(invocation.details.custom.containsKey('caller'), isFalse);
      invocation.respondWith(arguments: const ['ok']);
      seenInvocation.complete();
    });

    final result = await caller
        .call(
          'com.example.disclose',
          arguments: const ['payload'],
          options: CallOptions(
            custom: const {
              'caller': 99,
              'caller_authid': 'spoofed',
              'authid': 'legacy-spoofed',
              'trace_id': 'trace-1',
            },
          ),
        )
        .first;

    expect(result.arguments, equals(const ['ok']));
    await seenInvocation.future;
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
