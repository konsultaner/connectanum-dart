import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/mqtt.dart';

/// A bounded, anonymous MQTT QoS 0 broker for the first live-path checkpoint.
///
/// A later milestone stage will attach this session owner to native transport
/// negotiation and the protocol-neutral router publication boundary.
final class MqttQos0Broker {
  MqttQos0Broker._(this._server) {
    _server.listen(_accept);
  }

  static Future<MqttQos0Broker> bind(String host, int port) async =>
      MqttQos0Broker._(await ServerSocket.bind(host, port));

  final ServerSocket _server;
  final Set<_Peer> _peers = {};

  int get port => _server.port;

  void _accept(Socket socket) {
    final peer = _Peer(this, socket);
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
      peer.socket.add(encoded);
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
    await _server.close();
  }
}

final class _Peer {
  _Peer(this.broker, this.socket);

  final MqttQos0Broker broker;
  final Socket socket;
  final MqttFrameDecoder decoder = MqttFrameDecoder();
  final Set<String> filters = {};
  MqttVersion? version;
  bool connected = false;
  bool closed = false;

  void _onData(Uint8List data) {
    try {
      for (final frame in decoder.add(data)) {
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
        socket.add(
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
      socket.add(MqttPacketCodec.encodeConnack(connect.version, reasonCode: 0));
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
          final supported = subscribe.qos[i] == 0 && _validFilter(filter);
          if (supported) filters.add(filter);
          reasons.add(supported ? 0 : 0x80);
        }
        socket.add(
          MqttPacketCodec.encodeSuback(version!, subscribe.packetId, reasons),
        );
      case MqttPacketType.pingreq:
        if (frame.body.isNotEmpty) {
          throw const MqttProtocolException('PINGREQ has a body');
        }
        socket.add(
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
    broker._peers.remove(this);
    socket.destroy();
  }
}
