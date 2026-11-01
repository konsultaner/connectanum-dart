import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/mqtt.dart';

import '../native/runtime.dart';
import 'gateway_policy.dart';

/// An anonymous MQTT QoS 0 broker with bounded incoming packet framing.
///
/// The provisional Dart listener and the native MQTT listener currently bind
/// only numeric loopback addresses. A protocol-neutral WAMP publication
/// boundary remains a later milestone stage.
final class MqttQos0Broker {
  MqttQos0Broker._(this._server, {this.onNativeClose, String? realm})
    : _realm = realm {
    _server?.listen(_accept);
  }

  /// Session owner for MQTT byte streams accepted by the native router listener.
  MqttQos0Broker.native({void Function(int, String)? onNativeClose})
    : this._(null, onNativeClose: onNativeClose);

  static Future<MqttQos0Broker> bind(
    String host,
    int port, {
    String? realm,
  }) async {
    final address = InternetAddress.tryParse(host);
    if (address == null || !address.isLoopback) {
      throw ArgumentError.value(
        host,
        'host',
        'the provisional anonymous broker is limited to loopback',
      );
    }
    return MqttQos0Broker._(
      await ServerSocket.bind(address, port),
      realm: realm,
    );
  }

  final ServerSocket? _server;
  final String? _realm;
  final void Function(int connectionId, String reason)? onNativeClose;
  final Set<_Peer> _peers = {};
  final Map<int, _Peer> _nativePeers = {};
  final Map<String, MqttBrokerGatewayPolicy> _gateways = {};
  final Set<_Peer> _gatewayPeers = {};
  int _gatewayQueuedBytes = 0;

  /// Install a realm policy before accepting gateway traffic. A failed/closed
  /// gateway remains deny-only until explicitly replaced.
  void installGateway(String realm, MqttBrokerGatewayPolicy policy) {
    if (realm.isEmpty) throw ArgumentError.value(realm, 'realm');
    final previous = _gateways[realm];
    if (previous != null && !previous.isClosed) {
      throw StateError('MQTT gateway already installed for $realm');
    }
    _gateways[realm] = policy;
    closeRealm(realm);
  }

  void closeRealm(String realm) {
    for (final peer in _peers.where((peer) => peer.realm == realm).toList()) {
      peer._close('gateway_policy_changed');
    }
  }

  Map<String, int> get gatewayMetrics => {
    'pending_bytes': _gatewayPeers.fold(0, (sum, p) => sum + p._gatewayBytes),
    'pending_tasks': _gatewayPeers.fold(
      0,
      (sum, p) =>
          sum + p._gatewayTasks.length + (p._gatewayActiveBytes > 0 ? 1 : 0),
    ),
    'outbound_bytes': _peers.fold(
      0,
      (sum, p) =>
          sum +
          p._pendingOutboundBytes +
          p._pendingPublishChunkBytes +
          p._pendingPublishes.length,
    ),
    'connected_peers': _peers.length,
  };

  /// The host-owned gateway has already authorized this publication. Identity
  /// checking prevents a disposed or replaced gateway from injecting traffic.
  void publishFromGateway(
    String realm,
    MqttBrokerGatewayPolicy policy,
    MqttGatewayPublication publication,
  ) {
    if (!identical(_gateways[realm], policy) || policy.isClosed) {
      throw StateError('MQTT gateway is not active for $realm');
    }
    _deliver(realm, publication.topic, publication.payload);
  }

  int get port => _server?.port ?? 0;

  void attachNativeConnection(
    int connectionId, {
    required void Function(Uint8List) send,
    required void Function() close,
    String? realm,
  }) {
    if (_nativePeers.containsKey(connectionId)) {
      throw StateError('MQTT connection $connectionId already attached');
    }
    final peer = _Peer(
      this,
      send,
      close,
      nativeConnectionId: connectionId,
      realm: realm,
    );
    _nativePeers[connectionId] = peer;
    _peers.add(peer);
  }

  void receiveNativeChunk(int connectionId, Uint8List bytes) {
    _nativePeers[connectionId]?._onData(bytes);
  }

  void closeNativeConnection(
    int connectionId, {
    String reason = 'native_closed',
  }) {
    _nativePeers[connectionId]?._close(reason);
  }

  Iterable<int> get nativeConnectionIds => _nativePeers.keys;

  void _accept(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final peer = _Peer(
      this,
      (bytes) => socket.add(bytes),
      socket.destroy,
      realm: _realm,
    );
    _peers.add(peer);
    socket.listen(
      peer._onData,
      onDone: peer._close,
      onError: peer._close,
    );
  }

  void _publish(_Peer sender, MqttPublish message) {
    _deliver(sender.realm, message.topic, message.payload);
  }

  void _deliver(String? realm, String topic, Uint8List payload) {
    Uint8List? encoded5;
    Uint8List? encoded311;
    for (final peer in _peers) {
      if (!peer.connected || peer.realm != realm) continue;
      if (!peer.filters.any((filter) => _matches(filter, topic))) {
        continue;
      }
      final encoded = peer.version == MqttVersion.v5
          ? (encoded5 ??= MqttPacketCodec.encodePublish(
              MqttVersion.v5,
              topic: topic,
              payload: payload,
            ))
          : (encoded311 ??= MqttPacketCodec.encodePublish(
              MqttVersion.v311,
              topic: topic,
              payload: payload,
            ));
      final policy = _gateways[realm];
      if (policy == null) {
        peer._queuePublish(encoded);
      } else {
        peer._queueGatewayTask(encoded.length, () async {
          if (!policy.isClosed &&
              await policy.receive(peer._context, topic) &&
              !peer.closed) {
            peer._queuePublish(encoded);
          }
        });
      }
    }
  }

  static bool _matches(String filter, String topic) {
    if (topic.startsWith(r'$') && !filter.startsWith(r'$')) return false;
    final f = filter.split('/');
    final t = topic.split('/');
    for (var i = 0; i < f.length; i++) {
      if (f[i] == '#') return i == f.length - 1;
      if (i >= t.length) return false;
      if (f[i] != '+' && f[i] != t[i]) return false;
    }
    return f.length == t.length;
  }

  Future<void> close() async {
    for (final peer in _peers.toList()) {
      peer._close();
    }
    await Future.wait(
      _gatewayPeers.toList().map((p) => p._gatewayDrained!.future),
    );
    _gateways.clear();
    await _server?.close();
  }
}

final class _Peer {
  static const int _maxPendingOutboundBytes = 4 * 1024 * 1024;
  static const int _maxOutboundChunkBytes = 1 << 20;

  _Peer(
    this.broker,
    this._send,
    this._destroy, {
    this.nativeConnectionId,
    this.realm,
  });

  final MqttQos0Broker broker;
  final void Function(Uint8List) _send;
  final void Function() _destroy;
  final int? nativeConnectionId;
  final String? realm;
  String _clientId = '';
  final MqttGatewayCancellation _gatewayClosed = MqttGatewayCancellation();
  MqttPeerContext? _gatewayContext;
  final Queue<({int bytes, Future<void> Function() action})> _gatewayTasks =
      Queue();
  int _gatewayBytes = 0;
  int _gatewayActiveBytes = 0;
  bool _gatewayRunning = false;
  bool _gatewayOverflowed = false;
  Completer<void>? _gatewayDrained;
  final MqttFrameDecoder decoder = MqttFrameDecoder();
  final Set<String> filters = {};
  final BytesBuilder _pendingPublishes = BytesBuilder(copy: false);
  final Queue<Uint8List> _pendingPublishChunks = Queue<Uint8List>();
  int _pendingPublishChunkBytes = 0;
  bool _publishOverflowed = false;
  final Queue<Uint8List> _pendingOutbound = Queue<Uint8List>();
  int _pendingOutboundBytes = 0;
  Timer? _outboundRetry;
  MqttVersion? version;
  bool connected = false;
  bool closed = false;
  bool _publishFlushScheduled = false;

  MqttPeerContext get _context => _gatewayContext ??= MqttPeerContext(
    realm: realm!,
    clientId: _clientId,
    version: version!,
    connectionId: nativeConnectionId,
    cancellation: _gatewayClosed,
  );

  void _queueGatewayTask(int bytes, Future<void> Function() action) {
    if (closed || _gatewayOverflowed) return;
    if (_gatewayBytes + bytes > _maxPendingOutboundBytes ||
        broker._gatewayQueuedBytes + bytes > 16 * 1024 * 1024 ||
        _gatewayTasks.length >= 256) {
      _gatewayOverflowed = true;
      scheduleMicrotask(() => _close('gateway_buffer_full'));
      return;
    }
    _gatewayTasks.add((bytes: bytes, action: action));
    _gatewayBytes += bytes;
    broker._gatewayQueuedBytes += bytes;
    if (_gatewayRunning) return;
    _gatewayRunning = true;
    _gatewayDrained = Completer<void>();
    broker._gatewayPeers.add(this);
    scheduleMicrotask(() => unawaited(_drainGatewayTasks()));
  }

  Future<void> _drainGatewayTasks() async {
    try {
      while (!closed && _gatewayTasks.isNotEmpty) {
        final task = _gatewayTasks.removeFirst();
        _gatewayActiveBytes = task.bytes;
        try {
          await _gatewayClosed.waitFor(task.action());
        } catch (_) {
          _close('gateway_policy_error');
        } finally {
          _gatewayBytes -= task.bytes;
          broker._gatewayQueuedBytes -= task.bytes;
          _gatewayActiveBytes = 0;
        }
      }
    } finally {
      _gatewayRunning = false;
      broker._gatewayPeers.remove(this);
      _gatewayDrained!.complete();
    }
  }

  Future<void> _handleGatewayFrame(
    MqttFrame frame,
    MqttBrokerGatewayPolicy policy,
  ) async {
    if (policy.isClosed) {
      _close('gateway_closed');
      return;
    }
    if (frame.type == MqttPacketType.publish) {
      final message = MqttPacketCodec.decodePublish(frame, version!);
      if (message.retain) {
        throw const MqttProtocolException('retain is unsupported');
      }
      final allowed = await policy.publish(_context, message);
      if (closed) return;
      if (!allowed) {
        _close('not_authorized');
        return;
      }
      broker._publish(this, message);
    } else if (frame.type == MqttPacketType.subscribe) {
      final subscription = MqttPacketCodec.decodeSubscribe(frame, version!);
      final reasons = <int>[];
      for (final filter in subscription.filters) {
        final allowed =
            _validFilter(filter) && await policy.subscribe(_context, filter);
        if (closed) return;
        if (allowed) filters.add(filter);
        reasons.add(allowed ? 0 : 0x80);
      }
      _sendBytes(
        MqttPacketCodec.encodeSuback(version!, subscription.packetId, reasons),
      );
    } else {
      _handle(frame);
    }
  }

  void _queuePublish(Uint8List encoded) {
    if (_publishOverflowed) return;
    if (_pendingOutboundBytes +
            _pendingPublishChunkBytes +
            _pendingPublishes.length +
            encoded.length >
        _maxPendingOutboundBytes) {
      _publishOverflowed = true;
      scheduleMicrotask(() => _close('publication_buffer_full'));
      return;
    }
    if (encoded.length >= 64 * 1024) {
      if (_pendingPublishes.isNotEmpty) {
        final chunk = _pendingPublishes.takeBytes();
        _pendingPublishChunks.addLast(chunk);
        _pendingPublishChunkBytes += chunk.length;
      }
      _pendingPublishChunks.addLast(encoded);
      _pendingPublishChunkBytes += encoded.length;
    } else if (_pendingPublishes.length + encoded.length >
        _maxOutboundChunkBytes) {
      final chunk = _pendingPublishes.takeBytes();
      _pendingPublishChunks.addLast(chunk);
      _pendingPublishChunkBytes += chunk.length;
      _pendingPublishes.add(encoded);
    } else {
      _pendingPublishes.add(encoded);
    }
    if (_publishFlushScheduled) return;
    _publishFlushScheduled = true;
    // Coalesce frames decoded in one socket event before the next TCP write.
    scheduleMicrotask(() {
      _publishFlushScheduled = false;
      if (_publishOverflowed) {
        _close('publication_buffer_full');
        return;
      }
      while (!closed && _pendingPublishChunks.isNotEmpty) {
        final chunk = _pendingPublishChunks.removeFirst();
        _pendingPublishChunkBytes -= chunk.length;
        _sendBytes(chunk);
      }
      if (!closed && _pendingPublishes.isNotEmpty) {
        _sendBytes(_pendingPublishes.takeBytes());
      }
    });
  }

  void _sendBytes(Uint8List bytes) {
    if (closed) return;
    if (_pendingOutbound.isNotEmpty) {
      // Fresh traffic is another opportunity for the native writer to drain.
      _drainOutbound();
      if (closed) return;
      if (_pendingOutbound.isNotEmpty) {
        _queueOutbound(bytes);
        return;
      }
    }
    try {
      _send(bytes);
    } on NativeTransportException catch (error) {
      if (error.code == NativeTransportErrorCode.sendQueueFull) {
        _queueOutbound(bytes);
      } else {
        _close('send_error:${error.code}');
      }
    } catch (_) {
      _close('send_error');
    }
  }

  void _queueOutbound(Uint8List bytes) {
    if (_pendingOutboundBytes + bytes.length > _maxPendingOutboundBytes) {
      _close('outbound_buffer_full');
      return;
    }
    _pendingOutbound.addLast(bytes);
    _pendingOutboundBytes += bytes.length;
    _outboundRetry ??= Timer(const Duration(milliseconds: 1), _drainOutbound);
  }

  void _drainOutbound() {
    _outboundRetry?.cancel();
    _outboundRetry = null;
    while (!closed && _pendingOutbound.isNotEmpty) {
      final bytes = _pendingOutbound.first;
      try {
        _send(bytes);
      } on NativeTransportException catch (error) {
        if (error.code == NativeTransportErrorCode.sendQueueFull) {
          _outboundRetry = Timer(
            const Duration(milliseconds: 1),
            _drainOutbound,
          );
        } else {
          _close('send_error:${error.code}');
        }
        return;
      } catch (_) {
        _close('send_error');
        return;
      }
      _pendingOutbound.removeFirst();
      _pendingOutboundBytes -= bytes.length;
    }
  }

  void _onData(Uint8List data) {
    try {
      for (final frame in decoder.add(data)) {
        if (closed) break;
        final policy = connected ? broker._gateways[realm] : null;
        if (policy == null) {
          _handle(frame);
        } else {
          _queueGatewayTask(
            frame.body.length + 5,
            () => _handleGatewayFrame(frame, policy),
          );
        }
      }
    } on MqttProtocolException catch (error) {
      _close('protocol_error:${error.message}');
    }
  }

  void _handle(MqttFrame frame) {
    if (!connected) {
      if (frame.type != MqttPacketType.connect) {
        throw const MqttProtocolException('CONNECT must be first');
      }
      final connect = MqttPacketCodec.decodeConnect(frame);
      if (connect.username != null || connect.password != null) {
        _sendBytes(
          MqttPacketCodec.encodeConnack(
            connect.version,
            reasonCode: connect.version == MqttVersion.v5 ? 0x87 : 5,
          ),
        );
        _close('credentials_rejected');
        return;
      }
      version = connect.version;
      _clientId = connect.clientId;
      connected = true;
      _sendBytes(
        MqttPacketCodec.encodeConnack(
          connect.version,
          reasonCode: 0,
          advertiseQos0Limits: true,
        ),
      );
      return;
    }
    switch (frame.type) {
      case MqttPacketType.publish:
        final message = MqttPacketCodec.decodePublish(frame, version!);
        if (message.retain) {
          throw const MqttProtocolException(
            'retained PUBLISH is not supported yet',
          );
        }
        broker._publish(this, message);
      case MqttPacketType.subscribe:
        final subscribe = MqttPacketCodec.decodeSubscribe(frame, version!);
        final reasons = <int>[];
        for (var i = 0; i < subscribe.filters.length; i++) {
          final filter = subscribe.filters[i];
          final supported = _validFilter(filter);
          if (supported) filters.add(filter);
          reasons.add(supported ? 0 : 0x80);
        }
        _sendBytes(
          MqttPacketCodec.encodeSuback(version!, subscribe.packetId, reasons),
        );
      case MqttPacketType.pingreq:
        if (frame.body.isNotEmpty) {
          throw const MqttProtocolException('PINGREQ has a body');
        }
        _sendBytes(
          MqttFrame(
            MqttPacketType.pingresp,
            flags: 0,
            body: Uint8List(0),
          ).encode(),
        );
      case MqttPacketType.disconnect:
        _close('client_disconnect');
      default:
        throw const MqttProtocolException('unsupported MQTT packet');
    }
  }

  bool _validFilter(String filter) {
    if (filter.isEmpty) return false;
    final levels = filter.split('/');
    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      if (level.contains('#') && (level != '#' || i != levels.length - 1)) {
        return false;
      }
      if (level.contains('+') && level != '+') return false;
    }
    return true;
  }

  void _close([Object? error]) {
    if (closed) return;
    closed = true;
    _gatewayClosed.cancel();
    _gatewayTasks.clear();
    broker._gatewayQueuedBytes -= _gatewayBytes - _gatewayActiveBytes;
    _gatewayBytes = _gatewayActiveBytes;
    _outboundRetry?.cancel();
    _pendingOutbound.clear();
    _pendingOutboundBytes = 0;
    _pendingPublishChunks.clear();
    _pendingPublishChunkBytes = 0;
    _pendingPublishes.takeBytes();
    broker._peers.remove(this);
    final id = nativeConnectionId;
    if (id != null) {
      broker._nativePeers.remove(id);
      try {
        broker.onNativeClose?.call(id, error?.toString() ?? 'closed');
      } catch (_) {
        // An observer must not prevent transport cleanup.
      }
    }
    try {
      _destroy();
    } catch (_) {
      // The native connection can close before the broker observes its EOF.
    }
  }
}
