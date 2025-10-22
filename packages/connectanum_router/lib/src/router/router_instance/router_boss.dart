part of '../router_instance.dart';

/// Coordinates worker isolates and keeps track of which connection each worker
/// owns. The boss lives in the main isolate so all FFI calls remain in a single
/// thread, while workers materialise messages out-of-band.
class _RouterBoss {
  _RouterBoss({
    required this.runtime,
    required this.listeners,
    required this.pollInterval,
    required this.entryPoint,
    required this.libraryPathHint,
    this.debugEventCallback,
  }) : _eventPort = ReceivePort() {
    for (final listener in listeners) {
      _listenerById[listener.listenerId] = listener;
    }
    _eventSubscription = _eventPort.listen(_handleEvent);
  }

  final NativeRuntimeWithHandles runtime;
  final List<RouterListener> listeners;
  final Duration pollInterval;
  final RouterWorkerEntryPoint entryPoint;
  final String? libraryPathHint;
  final void Function(Object event)? debugEventCallback;

  final ReceivePort _eventPort;
  late final StreamSubscription<dynamic> _eventSubscription;
  final Map<int, RouterListener> _listenerById = {};
  final Map<int, _WorkerHandle> _workers = {};
  final Map<int, Isolate> _pendingIsolates = {};
  bool _running = false;
  bool _stopping = false;
  Future<void>? _loopFuture;

  void start() {
    if (_running) {
      return;
    }
    _running = true;
    _loopFuture = _loop();
  }

  Future<void> stop() async {
    if (_stopping) {
      return;
    }
    _stopping = true;
    _running = false;
    final loop = _loopFuture;
    if (loop != null) {
      await loop;
    }
    await _eventSubscription.cancel();
    _eventPort.close();
    for (final worker in _workers.values.toList()) {
      _shutdownWorker(worker.connectionId, terminateIsolate: true);
    }
    for (final isolate in _pendingIsolates.values) {
      isolate.kill(priority: Isolate.immediate);
    }
    _workers.clear();
    _pendingIsolates.clear();
  }

  Future<void> _loop() async {
    while (_running) {
      for (final listener in listeners) {
        await _acceptConnections(listener);
      }
      _dispatchMessages();
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<void> _acceptConnections(RouterListener listener) async {
    while (_running) {
      int connectionId;
      try {
        connectionId = runtime.pollConnection(listener.listenerId);
      } on NativeTransportException catch (error) {
        debugEventCallback?.call({
          'type': 'boss_error',
          'listenerId': listener.listenerId,
          'error': error.toString(),
        });
        break;
      }
      if (connectionId == 0) {
        break;
      }
      if (_workers.containsKey(connectionId) ||
          _pendingIsolates.containsKey(connectionId)) {
        continue;
      }
      await _spawnWorker(listener, connectionId);
    }
  }

  void _dispatchMessages() {
    final workersSnapshot = List<_WorkerHandle>.from(_workers.values);
    for (final worker in workersSnapshot) {
      if (worker.busy) {
        continue;
      }
      int handle;
      try {
        handle = runtime.pollMessageHandle(worker.connectionId);
      } on NativeTransportException catch (error) {
        debugEventCallback?.call({
          'type': 'boss_error',
          'connectionId': worker.connectionId,
          'error': error.toString(),
        });
        if (error.code == NativeTransportErrorCode.connectionNotFound) {
          _shutdownWorker(worker.connectionId);
        }
        continue;
      }
      if (handle == 0) {
        continue;
      }
      worker.busy = true;
      worker.commandPort.send(<Object?>[_workerCmdProcess, handle]);
    }
  }

  Future<void> _spawnWorker(RouterListener listener, int connectionId) async {
    final args = <String, Object?>{
      'bossPort': _eventPort.sendPort,
      'connectionId': connectionId,
      'listenerId': listener.listenerId,
      'libraryPath': libraryPathHint,
    };
    final isolate = await Isolate.spawn<Map<String, Object?>>(
      entryPoint,
      args,
      debugName: 'connectanum-router-worker-$connectionId',
    );
    _pendingIsolates[connectionId] = isolate;
  }

  void _handleEvent(dynamic message) {
    Object? debugPayload;
    if (message is! Map) {
      debugPayload = {'type': 'worker_unknown_event', 'payload': message};
    } else {
      final type = message['type'];
      if (type == _workerEventRegister) {
        final connectionId = message['connectionId'] as int;
        final listenerId = message['listenerId'] as int;
        final commandPort = message['commandPort'] as SendPort;
        final isolate = _pendingIsolates.remove(connectionId);
        final listener = _listenerById[listenerId];
        if (isolate == null || listener == null) {
          commandPort.send(<Object?>[_workerCmdShutdown]);
          isolate?.kill(priority: Isolate.immediate);
          debugPayload = {
            'type': 'worker_register_failed',
            'connectionId': connectionId,
            'listenerId': listenerId,
          };
        } else {
          _workers[connectionId] = _WorkerHandle(
            connectionId: connectionId,
            listener: listener,
            isolate: isolate,
            commandPort: commandPort,
          );
          debugPayload = {
            'type': 'worker_registered',
            'connectionId': connectionId,
            'listenerId': listenerId,
          };
        }
      } else if (type == _workerEventReady) {
        final connectionId = message['connectionId'] as int;
        final worker = _workers[connectionId];
        if (worker != null) {
          worker.busy = false;
        }
        debugPayload = {'type': 'worker_ready', 'connectionId': connectionId};
      } else if (type == _workerEventShutdown) {
        final connectionId = message['connectionId'] as int;
        _shutdownWorker(connectionId, terminateIsolate: false);
        debugPayload = {
          'type': 'worker_shutdown',
          'connectionId': connectionId,
        };
      } else if (type == _workerEventError) {
        final connectionId = message['connectionId'] as int?;
        if (connectionId != null) {
          final worker = _workers[connectionId];
          worker?.busy = false;
        }
        debugPayload = {
          'type': 'worker_error',
          'connectionId': connectionId,
          'error': message['error'],
          'stackTrace': message['stackTrace'],
        };
      } else {
        debugPayload = {'type': 'worker_unknown_event', 'payload': message};
      }
    }
    if (debugPayload != null) {
      debugEventCallback?.call(debugPayload);
    }
  }

  void _shutdownWorker(int connectionId, {bool terminateIsolate = false}) {
    final worker = _workers.remove(connectionId);
    if (worker != null) {
      worker.commandPort.send(<Object?>[_workerCmdShutdown]);
      if (terminateIsolate) {
        worker.isolate.kill(priority: Isolate.immediate);
      }
    } else {
      final isolate = _pendingIsolates.remove(connectionId);
      isolate?.kill(priority: Isolate.immediate);
    }
  }
}

class _WorkerHandle {
  _WorkerHandle({
    required this.connectionId,
    required this.listener,
    required this.isolate,
    required this.commandPort,
  });

  final int connectionId;
  final RouterListener listener;
  final Isolate isolate;
  final SendPort commandPort;
  bool busy = false;
}
