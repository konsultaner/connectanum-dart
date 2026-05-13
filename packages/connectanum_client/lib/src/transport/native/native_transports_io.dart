import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/cbor_serializer.dart' as serializer_cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/json_serializer.dart' as serializer_json;
import 'package:connectanum_core/msgpack_serializer.dart' as serializer_msgpack;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../abstract_transport.dart';
import '../socket/socket_helper.dart';
import '../websocket/websocket_transport_serialization.dart';
import 'message_binding.dart';
import 'message_protocol.dart';
import 'runtime.dart';

final _nativeMessageAnchor = Expando<NativeIncomingMessage>(
  'connectanum.native.message',
);

const _nativeReceiveBatchSize = 32;

@visibleForTesting
List<int> collectNativeReceiveBatch(
  int firstHandle,
  int Function() pollHandle, {
  int maxBatchSize = _nativeReceiveBatchSize,
}) {
  final batch = <int>[firstHandle];
  while (batch.length < maxBatchSize) {
    final nextHandle = pollHandle();
    if (nextHandle <= 0) {
      break;
    }
    batch.add(nextHandle);
  }
  return batch;
}

abstract class _NativeTransportBase extends AbstractTransport
    implements SessionOptimizedTransport {
  _NativeTransportBase(
    this._serializer,
    this._nativeSerializer, {
    String? libraryPath,
  }) : _libraryPath = libraryPath;

  final AbstractSerializer _serializer;
  final NativeMessageSerializer _nativeSerializer;
  final String? _libraryPath;
  late final NativeClientRuntime _runtime = NativeClientRuntime.instance(
    libraryPath: _libraryPath,
  );

  StreamController<Object?>? _messageController;
  Completer<void>? _onReadyCompleter;
  Completer<dynamic>? _onConnectionLostCompleter;
  Completer<dynamic>? _onDisconnectCompleter;
  int? _connectionId;
  _NativeReceiveWorker? _receiveWorker;
  bool _pumpStarted = false;
  bool _closeRequested = false;
  bool _goodbyeSent = false;
  bool _goodbyeReceived = false;

  Future<int> openNativeConnection(Duration? pingInterval);

  Logger get logger;

  @override
  Completer? get onConnectionLost => _onConnectionLostCompleter;

  @override
  Completer? get onDisconnect => _onDisconnectCompleter;

  @override
  bool get isOpen =>
      _connectionId != null &&
      !(_onConnectionLostCompleter?.isCompleted ?? true) &&
      !(_onDisconnectCompleter?.isCompleted ?? true);

  @override
  bool get isReady => isOpen && (_onReadyCompleter?.isCompleted ?? false);

  @override
  Future<void> get onReady => _onReadyCompleter!.future;

  int? get connectionId => _connectionId;

  @override
  Future<void> open({Duration? pingInterval}) async {
    if (isOpen) {
      return;
    }
    _closeRequested = false;
    _goodbyeSent = false;
    _goodbyeReceived = false;
    _pumpStarted = false;
    _messageController = StreamController<Object?>.broadcast();
    _onReadyCompleter = Completer<void>();
    _onConnectionLostCompleter = Completer<dynamic>();
    _onDisconnectCompleter = Completer<dynamic>();
    try {
      final connectionId = await openNativeConnection(pingInterval);
      _connectionId = connectionId;
      _onReadyCompleter!.complete();
    } catch (error, stackTrace) {
      if (!(_onReadyCompleter?.isCompleted ?? true)) {
        _onReadyCompleter!.completeError(error, stackTrace);
      }
      if (!(_onConnectionLostCompleter?.isCompleted ?? true)) {
        _onConnectionLostCompleter!.complete(error);
      }
    }
  }

  @override
  Stream<AbstractMessage?> receive() {
    return receiveSessionMessages().map(_materializePublicMessage);
  }

  @override
  Stream<Object?> receiveSessionMessages() {
    final controller = _messageController;
    if (controller == null) {
      throw StateError('Transport must be opened before receive() is used.');
    }
    final connectionId = _connectionId;
    if (!_pumpStarted && connectionId != null) {
      _pumpStarted = true;
      unawaited(_pumpMessages(connectionId));
    }
    return controller.stream;
  }

  @override
  Future<void> close({error}) async {
    _closeRequested = true;
    final connectionId = _connectionId;
    _connectionId = null;
    if (connectionId != null) {
      try {
        _runtime.closeConnection(connectionId);
      } catch (_) {
        // The connection might already be gone.
      }
    }
    await _disposeReceiveWorker();
    final controller = _messageController;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    complete(_onDisconnectCompleter, error);
  }

  @override
  void send(AbstractMessage message) {
    final connectionId = _connectionId;
    if (connectionId == null) {
      throw StateError('Transport is not connected.');
    }
    if (message is Goodbye) {
      _goodbyeSent = true;
    }
    _runtime.sendMessage(connectionId, _encodeMessage(message));
  }

  Future<void> _pumpMessages(int connectionId) async {
    _NativeReceiveWorker? worker;
    try {
      worker = await _NativeReceiveWorker.start(
        connectionId: connectionId,
        libraryPath: _runtime.libraryPath,
      );
      _receiveWorker = worker;
      await for (final batch in worker.handleBatches) {
        for (var index = 0; index < batch.length; index += 1) {
          final handle = batch[index];
          if (_connectionId != connectionId) {
            _runtime.releaseMessageHandle(handle);
            continue;
          }
          final incoming = _runtime.materialize(handle);
          final message = incoming.message;
          _nativeMessageAnchor[message] = incoming;
          if (_isGoodbyeMessage(message)) {
            _goodbyeReceived = true;
          }
          final controller = _messageController;
          if (controller == null || controller.isClosed) {
            for (
              var remaining = index + 1;
              remaining < batch.length;
              remaining += 1
            ) {
              _runtime.releaseMessageHandle(batch[remaining]);
            }
            return;
          }
          controller.add(message);
        }
      }
      if (_connectionId == connectionId &&
          !_closeRequested &&
          !_goodbyeSent &&
          !_goodbyeReceived) {
        throw StateError(
          'Native transport receive worker exited unexpectedly.',
        );
      }
    } catch (error, stackTrace) {
      final controller = _messageController;
      if (controller != null && !controller.isClosed) {
        controller.addError(error, stackTrace);
        await controller.close();
      }
      _connectionId = null;
      if (_closeRequested || _goodbyeSent || _goodbyeReceived) {
        complete(_onDisconnectCompleter, error);
      } else if (!(_onConnectionLostCompleter?.isCompleted ?? true)) {
        _onConnectionLostCompleter!.complete(error);
      } else {
        logger.fine('Native transport receive loop ended: $error');
      }
    } finally {
      if (worker != null && identical(_receiveWorker, worker)) {
        _receiveWorker = null;
      }
      await worker?.close();
    }
  }

  Future<void> _disposeReceiveWorker() async {
    final worker = _receiveWorker;
    _receiveWorker = null;
    if (worker != null) {
      await worker.close();
    }
  }

  Uint8List _encodeMessage(AbstractMessage message) {
    final serialized = _serializer.serialize(message);
    if (serialized is Uint8List) {
      return serialized;
    }
    if (serialized is String) {
      return Uint8List.fromList(utf8.encode(serialized));
    }
    if (serialized is List<int>) {
      return Uint8List.fromList(serialized);
    }
    throw UnsupportedError(
      'Serializer ${_nativeSerializer.name} returned unsupported payload ${serialized.runtimeType}',
    );
  }
}

AbstractMessage? _materializePublicMessage(Object? message) {
  if (message == null) {
    return null;
  }
  final materialized = materializeSessionMessage(message);
  final anchored = _nativeMessageAnchor[message];
  if (anchored != null && !identical(materialized, message)) {
    _nativeMessageAnchor[materialized] = anchored;
  }
  return materialized;
}

bool _isGoodbyeMessage(Object message) {
  if (message is Goodbye) {
    return true;
  }
  if (message is NativeSessionMessage) {
    return message.metadata.messageCode == MessageTypes.codeGoodbye;
  }
  return false;
}

class NativeRawSocketTransport extends _NativeTransportBase {
  NativeRawSocketTransport(
    this._host,
    this._port,
    AbstractSerializer serializer,
    this._serializerType, {
    bool ssl = false,
    bool allowInsecureCertificates = false,
    int messageLengthExponent = SocketHelper.maxMessageLengthExponent,
    String? libraryPath,
  }) : _ssl = ssl,
       _allowInsecureCertificates = allowInsecureCertificates,
       _messageLengthExponent = messageLengthExponent,
       super(
         serializer,
         _nativeSerializerForRawSocket(_serializerType),
         libraryPath: libraryPath,
       );

  final String _host;
  final int _port;
  final int _serializerType;
  final bool _ssl;
  final bool _allowInsecureCertificates;
  int _messageLengthExponent;

  static final _logger = Logger('Connectanum.NativeRawSocketTransport');

  factory NativeRawSocketTransport.withJsonSerializer(
    String host,
    int port, {
    bool ssl = false,
    bool allowInsecureCertificates = false,
    int messageLengthExponent = SocketHelper.maxMessageLengthExponent,
    String? libraryPath,
  }) => NativeRawSocketTransport(
    host,
    port,
    serializer_json.Serializer(),
    SocketHelper.serializationJson,
    ssl: ssl,
    allowInsecureCertificates: allowInsecureCertificates,
    messageLengthExponent: messageLengthExponent,
    libraryPath: libraryPath,
  );

  factory NativeRawSocketTransport.withMsgpackSerializer(
    String host,
    int port, {
    bool ssl = false,
    bool allowInsecureCertificates = false,
    int messageLengthExponent = SocketHelper.maxMessageLengthExponent,
    String? libraryPath,
  }) => NativeRawSocketTransport(
    host,
    port,
    serializer_msgpack.Serializer(),
    SocketHelper.serializationMsgpack,
    ssl: ssl,
    allowInsecureCertificates: allowInsecureCertificates,
    messageLengthExponent: messageLengthExponent,
    libraryPath: libraryPath,
  );

  factory NativeRawSocketTransport.withCborSerializer(
    String host,
    int port, {
    bool ssl = false,
    bool allowInsecureCertificates = false,
    int messageLengthExponent = SocketHelper.maxMessageLengthExponent,
    String? libraryPath,
  }) => NativeRawSocketTransport(
    host,
    port,
    serializer_cbor.Serializer(),
    SocketHelper.serializationCbor,
    ssl: ssl,
    allowInsecureCertificates: allowInsecureCertificates,
    messageLengthExponent: messageLengthExponent,
    libraryPath: libraryPath,
  );

  bool get isUpgradedProtocol => _messageLengthExponent > 24;

  int get headerLength => isUpgradedProtocol ? 5 : 4;

  int? get maxMessageLength => 1 << _messageLengthExponent;

  @override
  Logger get logger => _logger;

  @override
  Future<int> openNativeConnection(Duration? pingInterval) async {
    final connectionId = _runtime.connectRawSocket(
      host: _host,
      port: _port,
      useTls: _ssl,
      allowInsecure: _allowInsecureCertificates,
      serializer: _nativeSerializerForRawSocket(_serializerType),
      maxMessageLengthExponent: _messageLengthExponent,
      heartbeatInterval: pingInterval,
      heartbeatTimeout: pingInterval == null ? null : pingInterval * 2,
    );
    _messageLengthExponent = _runtime.connectionMaxRawSocketExponent(
      connectionId,
    );
    return connectionId;
  }
}

class NativeWebSocketTransport extends _NativeTransportBase {
  NativeWebSocketTransport(
    this._url,
    AbstractSerializer serializer,
    this._serializerType, [
    Map<String, dynamic>? headers,
    this._allowInsecureCertificates = false,
    String? libraryPath,
    this._fragmentSize,
  ]) : _headers = headers,
       super(
         serializer,
         _nativeSerializerForWebSocket(_serializerType),
         libraryPath: libraryPath,
       );

  final String _url;
  final String _serializerType;
  final Map<String, dynamic>? _headers;
  final bool _allowInsecureCertificates;
  final int? _fragmentSize;

  static final _logger = Logger('Connectanum.NativeWebSocketTransport');

  factory NativeWebSocketTransport.withJsonSerializer(
    String url, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    String? libraryPath,
    int? fragmentSize,
  ]) => NativeWebSocketTransport(
    url,
    serializer_json.Serializer(),
    WebSocketSerialization.serializationJson,
    headers,
    allowInsecureCertificates,
    libraryPath,
    fragmentSize,
  );

  factory NativeWebSocketTransport.withMsgpackSerializer(
    String url, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    String? libraryPath,
    int? fragmentSize,
  ]) => NativeWebSocketTransport(
    url,
    serializer_msgpack.Serializer(),
    WebSocketSerialization.serializationMsgpack,
    headers,
    allowInsecureCertificates,
    libraryPath,
    fragmentSize,
  );

  factory NativeWebSocketTransport.withCborSerializer(
    String url, [
    Map<String, dynamic>? headers,
    bool allowInsecureCertificates = false,
    String? libraryPath,
    int? fragmentSize,
  ]) => NativeWebSocketTransport(
    url,
    serializer_cbor.Serializer(),
    WebSocketSerialization.serializationCbor,
    headers,
    allowInsecureCertificates,
    libraryPath,
    fragmentSize,
  );

  @override
  void send(AbstractMessage message) {
    final connectionId = _connectionId;
    if (connectionId == null) {
      throw StateError('Transport is not connected.');
    }
    if (message is Goodbye) {
      _goodbyeSent = true;
    }
    final encoded = _encodeMessage(message);
    final fragmentSize = _fragmentSize;
    if (fragmentSize != null &&
        fragmentSize > 0 &&
        encoded.length > fragmentSize) {
      _runtime.sendMessageFragmented(
        connectionId,
        encoded,
        fragmentSize: fragmentSize,
      );
      return;
    }
    _runtime.sendMessage(connectionId, encoded);
  }

  @override
  Logger get logger => _logger;

  @override
  Future<int> openNativeConnection(Duration? pingInterval) async {
    final uri = Uri.parse(_url);
    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      throw ArgumentError(
        'NativeWebSocketTransport requires a ws:// or wss:// URL.',
      );
    }
    final useTls = uri.scheme == 'wss';
    final port = uri.hasPort ? uri.port : (useTls ? 443 : 80);
    var target = uri.path.isEmpty ? '/' : uri.path;
    if (uri.hasQuery) {
      target = '$target?${uri.query}';
    }
    return _runtime.connectWebSocket(
      host: uri.host,
      port: port,
      target: target,
      useTls: useTls,
      allowInsecure: _allowInsecureCertificates,
      serializer: _nativeSerializerForWebSocket(_serializerType),
      headers: _flattenHeaders(_headers),
      heartbeatInterval: pingInterval,
      heartbeatTimeout: pingInterval == null ? null : pingInterval * 2,
    );
  }
}

NativeMessageSerializer _nativeSerializerForRawSocket(int serializerType) {
  return switch (serializerType) {
    SocketHelper.serializationJson => NativeMessageSerializer.json,
    SocketHelper.serializationMsgpack => NativeMessageSerializer.messagePack,
    SocketHelper.serializationCbor => NativeMessageSerializer.cbor,
    SocketHelper.serializationUbJson => NativeMessageSerializer.ubjson,
    SocketHelper.serializationFlatBuffers =>
      NativeMessageSerializer.flatbuffers,
    _ => throw ArgumentError(
      'Unsupported rawsocket serializer id $serializerType',
    ),
  };
}

NativeMessageSerializer _nativeSerializerForWebSocket(String serializerType) {
  return switch (serializerType) {
    WebSocketSerialization.serializationJson => NativeMessageSerializer.json,
    WebSocketSerialization.serializationMsgpack =>
      NativeMessageSerializer.messagePack,
    WebSocketSerialization.serializationCbor => NativeMessageSerializer.cbor,
    _ => throw ArgumentError(
      'Unsupported websocket serializer protocol $serializerType',
    ),
  };
}

Map<String, String> _flattenHeaders(Map<String, dynamic>? headers) {
  if (headers == null || headers.isEmpty) {
    return const <String, String>{};
  }
  final flattened = <String, String>{};
  headers.forEach((key, value) {
    if (value is String) {
      flattened[key] = value;
      return;
    }
    if (value is Iterable) {
      flattened[key] = value.map((item) => item.toString()).join(', ');
      return;
    }
    flattened[key] = value.toString();
  });
  return flattened;
}

class _NativeReceiveWorker {
  _NativeReceiveWorker._(
    this._isolate,
    this._eventsPort,
    this._exitPort,
    this.handleBatches,
    this._controlPort,
  );

  static const _waitTimeout = Duration(milliseconds: 50);

  final Isolate _isolate;
  final ReceivePort _eventsPort;
  final ReceivePort _exitPort;
  final Stream<List<int>> handleBatches;
  final SendPort _controlPort;
  Future<void>? _closeFuture;

  static Future<_NativeReceiveWorker> start({
    required int connectionId,
    required String libraryPath,
  }) async {
    final eventsPort = ReceivePort();
    final exitPort = ReceivePort();
    final events = eventsPort.asBroadcastStream();
    final controlPortFuture = events
        .firstWhere((event) => event is SendPort)
        .then((event) => event as SendPort);
    final isolate =
        await Isolate.spawn(_nativeReceiveWorkerMain, <String, Object?>{
          'connectionId': connectionId,
          'libraryPath': libraryPath,
          'sendPort': eventsPort.sendPort,
          'timeoutMs': _waitTimeout.inMilliseconds,
        }, onExit: exitPort.sendPort);
    final controlPort = await controlPortFuture;
    return _NativeReceiveWorker._(
      isolate,
      eventsPort,
      exitPort,
      events.where((event) => event is int || event is List).map<List<int>>((
        event,
      ) {
        if (event is int) {
          return <int>[event];
        }
        return (event as List<dynamic>).cast<int>();
      }),
      controlPort,
    );
  }

  Future<void> close() {
    return _closeFuture ??= _closeImpl();
  }

  Future<void> _closeImpl() async {
    _controlPort.send(null);
    try {
      await _exitPort.first.timeout(const Duration(milliseconds: 200));
    } on TimeoutException {
      _isolate.kill(priority: Isolate.immediate);
    } finally {
      _eventsPort.close();
      _exitPort.close();
    }
  }
}

@pragma('vm:entry-point')
Future<void> _nativeReceiveWorkerMain(Map<String, Object?> config) async {
  final sendPort = config['sendPort']! as SendPort;
  final controlPort = ReceivePort();
  sendPort.send(controlPort.sendPort);
  var stopped = false;
  final subscription = controlPort.listen((_) {
    stopped = true;
  });
  try {
    final runtime = NativeClientRuntime.instance(
      libraryPath: config['libraryPath']! as String,
    );
    final connectionId = config['connectionId']! as int;
    final timeout = Duration(milliseconds: config['timeoutMs']! as int);
    while (!stopped) {
      final handle = runtime.waitMessageHandle(connectionId, timeout: timeout);
      if (handle > 0) {
        final batch = collectNativeReceiveBatch(
          handle,
          () => runtime.pollMessageHandle(connectionId),
        );
        sendPort.send(batch.length == 1 ? handle : batch);
      }
    }
  } on NativeTransportException catch (error) {
    if (!stopped && error.code != NativeTransportErrorCode.connectionNotFound) {
      rethrow;
    }
  } finally {
    await subscription.cancel();
    controlPort.close();
  }
}
