import 'dart:async';
import 'dart:isolate';

class DirectStreamReplyChannel {
  DirectStreamReplyChannel() : _port = RawReceivePort() {
    _port.handler = _handleMessage;
  }

  final RawReceivePort _port;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  int _nextRequestId = 1;
  bool _closed = false;

  SendPort get sendPort => _port.sendPort;

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
      controlPort.send({
        ...message,
        'replyPort': sendPort,
        'replyRequestId': replyRequestId,
      });
    } catch (_) {
      _pending.remove(replyRequestId);
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
    _port.close();
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
      return;
    }
    completer.complete(Map<String, Object?>.from(message));
  }
}
