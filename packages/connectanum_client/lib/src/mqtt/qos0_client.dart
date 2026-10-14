import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/mqtt.dart';

/// A TCP MQTT client for the property-free QoS 0 interoperability profile.
final class MqttQos0Client {
  MqttQos0Client._(this._socket, this.version) {
    _socket.listen(_onData, onDone: _onDone, onError: _onError);
  }

  static Future<MqttQos0Client> connect(
    String host,
    int port, {
    required String clientId,
    MqttVersion version = MqttVersion.v5,
  }) async {
    final socket = await Socket.connect(host, port);
    socket.setOption(SocketOption.tcpNoDelay, true);
    final client = MqttQos0Client._(socket, version);
    client._socket.add(
      MqttPacketCodec.encodeConnect(
        MqttConnect(version: version, clientId: clientId),
      ),
    );
    final reason = await client._connack.future.timeout(
      const Duration(seconds: 10),
    );
    if (reason != 0) {
      await client.close();
      throw MqttProtocolException('broker rejected CONNECT: $reason');
    }
    return client;
  }

  final Socket _socket;
  final MqttVersion version;
  final MqttFrameDecoder _decoder = MqttFrameDecoder();
  final StreamController<MqttPublish> _messages = StreamController.broadcast();
  final Completer<int> _connack = Completer();
  final Map<int, Completer<List<int>>> _subacks = {};
  Completer<void>? _ping;
  int _nextId = 1;
  bool _closed = false;

  Stream<MqttPublish> get messages => _messages.stream;

  Future<void> subscribe(String filter) async {
    final id = _nextId;
    _nextId = id == 65535 ? 1 : id + 1;
    final complete = Completer<List<int>>();
    _subacks[id] = complete;
    _socket.add(
      MqttPacketCodec.encodeSubscribe(version, packetId: id, filter: filter),
    );
    late final List<int> granted;
    try {
      granted = await complete.future.timeout(const Duration(seconds: 10));
    } finally {
      // A timed-out request must not retain an uncompleted completer.
      if (identical(_subacks[id], complete)) _subacks.remove(id);
    }
    if (granted.length != 1 || granted.single != 0) {
      throw const MqttProtocolException('broker rejected QoS 0 subscription');
    }
  }

  Future<void> publish(String topic, Uint8List payload) async {
    _socket.add(
      MqttPacketCodec.encodePublish(version, topic: topic, payload: payload),
    );
    await _socket.flush();
  }

  /// Sends up to 512 QoS 0 publications in one write, preserving order.
  Future<void> publishBatch(String topic, Iterable<Uint8List> payloads) async {
    const maxPackets = 512;
    const maxWireBytes = 1024 * 1024;
    final wire = BytesBuilder(copy: false);
    var count = 0;
    for (final payload in payloads) {
      if (count == maxPackets) {
        throw RangeError('MQTT batch exceeds $maxPackets packets');
      }
      final packet = MqttPacketCodec.encodePublish(
        version,
        topic: topic,
        payload: payload,
      );
      if (wire.length + packet.length > maxWireBytes) {
        throw RangeError('MQTT batch exceeds $maxWireBytes wire bytes');
      }
      wire.add(packet);
      count++;
    }
    if (count == 0) return;
    _socket.add(wire.takeBytes());
    await _socket.flush();
  }

  Future<void> ping() async {
    if (_ping != null) throw StateError('PINGREQ is already outstanding');
    final response = _ping = Completer<void>();
    _socket.add(
      MqttFrame(MqttPacketType.pingreq, flags: 0, body: Uint8List(0)).encode(),
    );
    await response.future.timeout(const Duration(seconds: 10));
  }

  void _onData(Uint8List data) {
    try {
      for (final frame in _decoder.add(data)) {
        switch (frame.type) {
          case MqttPacketType.connack:
            final reason = MqttPacketCodec.decodeConnack(
              frame,
              version,
            ).reasonCode;
            if (!_connack.isCompleted) _connack.complete(reason);
          case MqttPacketType.suback:
            final packet = MqttPacketCodec.decodeSuback(frame, version);
            _subacks.remove(packet.packetId)?.complete(packet.grantedQos);
          case MqttPacketType.publish:
            _messages.add(MqttPacketCodec.decodePublish(frame, version));
          case MqttPacketType.pingresp:
            if (frame.body.isNotEmpty) {
              throw const MqttProtocolException('PINGRESP has a body');
            }
            _ping?.complete();
            _ping = null;
          default:
            throw const MqttProtocolException('unsupported broker packet');
        }
      }
    } on MqttProtocolException catch (error) {
      _onError(error);
      _socket.destroy();
    }
  }

  void _onError(Object error) {
    if (!_connack.isCompleted) _connack.completeError(error);
    for (final pending in _subacks.values) {
      pending.completeError(error);
    }
    _subacks.clear();
    _ping?.completeError(error);
    _ping = null;
    if (!_closed) _messages.addError(error);
  }

  void _onDone() {
    _onError(const MqttProtocolException('MQTT connection closed'));
    if (!_closed) {
      _closed = true;
      _messages.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.add(
      MqttFrame(
        MqttPacketType.disconnect,
        flags: 0,
        body: Uint8List(0),
      ).encode(),
    );
    await _socket.flush();
    await _socket.close();
    await _messages.close();
  }
}
