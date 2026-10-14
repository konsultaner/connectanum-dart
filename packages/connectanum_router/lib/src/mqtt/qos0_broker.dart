import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/mqtt.dart';

import '../native/runtime.dart';

/// An anonymous MQTT QoS 0 broker with bounded incoming packet framing.
///
/// The provisional Dart listener and the native MQTT listener currently bind
/// only numeric loopback addresses. A protocol-neutral WAMP publication
/// boundary remains a later milestone stage.
final class MqttQos0Broker {
  MqttQos0Broker._(this._server) {
    _server?.listen(_accept);
  }

  /// Session owner for MQTT byte streams accepted by the native router listener.
  MqttQos0Broker.native() : this._(null);

  static Future<MqttQos0Broker> bind(String host, int port) async {
    final address = InternetAddress.tryParse(host);
    if (address == null || !address.isLoopback) {
      throw ArgumentError.value(
        host,
        'host',
        'the provisional anonymous broker is limited to loopback',
      );
    }
    return MqttQos0Broker._(await ServerSocket.bind(address, port));
  }

  final ServerSocket? _server;
  final Set<_Peer> _peers = {};
  final Map<int, _Peer> _nativePeers = {};

  int get port => _server?.port ?? 0;

  void attachNativeConnection(
    int connectionId, {
    required void Function(Uint8List) send,
    required void Function() close,
  }) {
    if (_nativePeers.containsKey(connectionId)) {
      throw StateError('MQTT connection $connectionId already attached');
    }
    final peer = _Peer(this, send, close, nativeConnectionId: connectionId);
    _nativePeers[connectionId] = peer;
    _peers.add(peer);
  }

  void receiveNativeChunk(int connectionId, Uint8List bytes) {
    _nativePeers[connectionId]?._onData(bytes);
  }

  void closeNativeConnection(int connectionId) {
    _nativePeers[connectionId]?._close();
  }

  Iterable<int> get nativeConnectionIds => _nativePeers.keys;

  void _accept(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final peer = _Peer(this, (bytes) => socket.add(bytes), socket.destroy);
    _peers.add(peer);
    socket.listen(
      peer._onData,
      onDone: peer._close,
      onError: peer._close,
    );
  }

  void _publish(_Peer sender, MqttPublish message) {
    Uint8List? encoded5;
    Uint8List? encoded311;
    for (final peer in _peers) {
      if (!peer.connected || peer == sender && peer.filters.isEmpty) continue;
      if (!peer.filters.any((filter) => _matches(filter, message.topic))) {
        continue;
      }
      final encoded = peer.version == MqttVersion.v5
          ? (encoded5 ??= MqttPacketCodec.encodePublish(
              MqttVersion.v5,
              topic: message.topic,
              payload: message.payload,
            ))
          : (encoded311 ??= MqttPacketCodec.encodePublish(
              MqttVersion.v311,
              topic: message.topic,
              payload: message.payload,
            ));
      peer._queuePublish(encoded);
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
  });

  final MqttQos0Broker broker;
  final void Function(Uint8List) _send;
  final void Function() _destroy;
  final int? nativeConnectionId;
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

  void _queuePublish(Uint8List encoded) {
    if (_publishOverflowed) return;
    if (_pendingOutboundBytes +
            _pendingPublishChunkBytes +
            _pendingPublishes.length +
            encoded.length >
        _maxPendingOutboundBytes) {
      _publishOverflowed = true;
      scheduleMicrotask(_close);
      return;
    }
    if (_pendingPublishes.length + encoded.length > _maxOutboundChunkBytes) {
      final chunk = _pendingPublishes.takeBytes();
      _pendingPublishChunks.addLast(chunk);
      _pendingPublishChunkBytes += chunk.length;
    }
    _pendingPublishes.add(encoded);
    if (_publishFlushScheduled) return;
    _publishFlushScheduled = true;
    // Coalesce frames decoded in one socket event before the next TCP write.
    scheduleMicrotask(() {
      _publishFlushScheduled = false;
      if (_publishOverflowed) {
        _close();
        return;
      }
      while (!closed && _pendingPublishChunks.isNotEmpty) {
        final chunk = _pendingPublishChunks.removeFirst();
        _pendingPublishChunkBytes -= chunk.length;
        _sendBytes(chunk);
      }
      if (!closed) _sendBytes(_pendingPublishes.takeBytes());
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
        _close();
      }
    } catch (_) {
      _close();
    }
  }

  void _queueOutbound(Uint8List bytes) {
    if (_pendingOutboundBytes + bytes.length > _maxPendingOutboundBytes) {
      _close();
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
          _close();
        }
        return;
      } catch (_) {
        _close();
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
        _handle(frame);
      }
    } on MqttProtocolException {
      _close();
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
        _close();
        return;
      }
      version = connect.version;
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
        _close();
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
    _outboundRetry?.cancel();
    _pendingOutbound.clear();
    _pendingOutboundBytes = 0;
    _pendingPublishChunks.clear();
    _pendingPublishChunkBytes = 0;
    _pendingPublishes.takeBytes();
    broker._peers.remove(this);
    final id = nativeConnectionId;
    if (id != null) broker._nativePeers.remove(id);
    try {
      _destroy();
    } catch (_) {
      // The native connection can close before the broker observes its EOF.
    }
  }
}
