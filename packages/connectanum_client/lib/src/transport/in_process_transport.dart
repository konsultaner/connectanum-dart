import 'dart:async';
import 'dart:collection';

import 'package:connectanum_core/connectanum_core.dart';

import 'abstract_transport.dart';

/// Paired in-process transports for tests and embedded router/client flows.
///
/// Messages stay as Dart WAMP message objects instead of crossing a socket or
/// serializer boundary. Each endpoint has a bounded inbound queue; sending into
/// a full peer queue throws [InProcessTransportBackpressureException].
final class InProcessTransportPair {
  InProcessTransportPair({
    int queueCapacity = InProcessTransport.defaultQueueCapacity,
    String clientName = 'client',
    String serverName = 'server',
  }) : client = InProcessTransport._(
         name: clientName,
         queueCapacity: queueCapacity,
       ),
       server = InProcessTransport._(
         name: serverName,
         queueCapacity: queueCapacity,
       ) {
    client._peer = server;
    server._peer = client;
  }

  final InProcessTransport client;
  final InProcessTransport server;
}

final class InProcessTransportBackpressureException implements Exception {
  const InProcessTransportBackpressureException({
    required this.source,
    required this.target,
    required this.capacity,
    required this.message,
  });

  final String source;
  final String target;
  final int capacity;
  final AbstractMessage message;

  @override
  String toString() {
    return 'InProcessTransportBackpressureException: "$source" could not send '
        '${message.runtimeType} to "$target"; inbound queue capacity '
        '$capacity is exhausted.';
  }
}

final class InProcessTransport extends AbstractTransport {
  InProcessTransport._({required this.name, required int queueCapacity})
    : queueCapacity = _validatedQueueCapacity(queueCapacity) {
    _receiveController = StreamController<AbstractMessage?>.broadcast(
      onListen: _scheduleDrain,
    );
  }

  static const int defaultQueueCapacity = 1024;

  final String name;
  final int queueCapacity;
  final Queue<AbstractMessage?> _pendingIncoming = Queue<AbstractMessage?>();
  late final StreamController<AbstractMessage?> _receiveController;
  final Completer<void> _onReady = Completer<void>();
  final Completer<void> _onDisconnect = Completer<void>();
  final Completer<void> _onConnectionLost = Completer<void>();

  InProcessTransport? _peer;
  bool _isOpen = false;
  bool _isClosed = false;
  bool _drainScheduled = false;

  int get pendingIncomingCount => _pendingIncoming.length;

  @override
  Completer<void> get onConnectionLost => _onConnectionLost;

  @override
  Completer<void> get onDisconnect => _onDisconnect;

  @override
  Future<void> get onReady => _onReady.future;

  @override
  bool get isOpen => _isOpen;

  @override
  bool get isReady => _isOpen;

  @override
  Future<void> open({Duration? pingInterval}) async {
    if (_isClosed) {
      throw StateError('Cannot reopen closed in-process transport "$name".');
    }
    _isOpen = true;
    if (!_onReady.isCompleted) {
      _onReady.complete();
    }
  }

  @override
  Stream<AbstractMessage?> receive() {
    return _receiveController.stream;
  }

  @override
  void send(AbstractMessage message) {
    if (!_isOpen || _isClosed) {
      throw StateError('In-process transport "$name" is not open.');
    }
    final peer = _peer;
    if (peer == null || !peer._isOpen || peer._isClosed) {
      throw StateError('In-process transport "$name" has no open peer.');
    }
    peer._enqueueIncoming(message, source: name);
  }

  void _enqueueIncoming(AbstractMessage message, {required String source}) {
    if (_pendingIncoming.length >= queueCapacity) {
      throw InProcessTransportBackpressureException(
        source: source,
        target: name,
        capacity: queueCapacity,
        message: message,
      );
    }
    _pendingIncoming.add(message);
    _scheduleDrain();
  }

  void _scheduleDrain() {
    if (_drainScheduled) {
      return;
    }
    _drainScheduled = true;
    scheduleMicrotask(_drainIncoming);
  }

  void _drainIncoming() {
    _drainScheduled = false;
    if (!_isOpen || _isClosed || _receiveController.isClosed) {
      _pendingIncoming.clear();
      return;
    }
    if (!_receiveController.hasListener) {
      return;
    }
    while (_pendingIncoming.isNotEmpty && _receiveController.hasListener) {
      _receiveController.add(_pendingIncoming.removeFirst());
    }
  }

  @override
  Future<void> close({dynamic error}) {
    return _close(error: error, notifyPeer: true);
  }

  Future<void> _close({dynamic error, required bool notifyPeer}) async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _isOpen = false;
    _pendingIncoming.clear();
    _complete(_onDisconnect);
    _complete(_onConnectionLost);
    if (!_receiveController.isClosed) {
      await _receiveController.close();
    }
    if (notifyPeer) {
      await _peer?._close(error: error, notifyPeer: false);
    }
  }

  static void _complete(Completer<void> completer) {
    if (completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  static int _validatedQueueCapacity(int value) {
    if (value <= 0) {
      throw RangeError.value(
        value,
        'queueCapacity',
        'must be greater than zero',
      );
    }
    return value;
  }
}
