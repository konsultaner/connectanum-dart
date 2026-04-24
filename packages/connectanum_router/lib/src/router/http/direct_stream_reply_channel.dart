import 'dart:async';
import 'dart:isolate';

class DirectStreamReplyChannel {
  RawReceivePort? _port;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  int _nextRequestId = 1;
  bool _closed = false;

  SendPort get sendPort => _ensurePort().sendPort;

  Future<Map<String, Object?>> request(
    SendPort controlPort,
    Map<String, Object?> message,
  ) {
    if (_closed) {
      throw StateError('Direct stream reply channel is closed');
    }
    final replyRequestId = _nextRequestId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[replyRequestId] = completer;
    try {
      final replyPort = _ensurePort().sendPort;
      controlPort.send({
        ...message,
        'replyPort': replyPort,
        'replyRequestId': replyRequestId,
      });
    } catch (_) {
      _pending.remove(replyRequestId);
      _closePortIfIdle();
      rethrow;
    }
    return completer.future;
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    final error = StateError('Direct stream reply channel is closed');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
    _port?.close();
    _port = null;
  }

  void _handleMessage(dynamic message) {
    if (message is! Map) {
      return;
    }
    final replyRequestId = message['replyRequestId'] as int?;
    if (replyRequestId == null) {
      return;
    }
    final completer = _pending.remove(replyRequestId);
    if (completer == null || completer.isCompleted) {
      _closePortIfIdle();
      return;
    }
    completer.complete(Map<String, Object?>.from(message));
    _closePortIfIdle();
  }

  RawReceivePort _ensurePort() {
    final existing = _port;
    if (existing != null) {
      return existing;
    }
    final port = RawReceivePort();
    port.handler = _handleMessage;
    _port = port;
    return port;
  }

  void _closePortIfIdle() {
    if (_pending.isNotEmpty) {
      return;
    }
    _port?.close();
    _port = null;
  }
}
