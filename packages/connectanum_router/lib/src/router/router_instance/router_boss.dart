part of '../router_instance.dart';

/// Coordinates worker isolates and round-robins connections across them.
class _RouterBoss {
  _RouterBoss({
    required this.runtime,
    required this.listeners,
    required this.pollInterval,
    required this.entryPoint,
    required this.libraryPathHint,
    required this.settings,
    this.onEvent,
  }) : _eventPort = ReceivePort(),
       _stateStore = RouterStateStore(settings: settings) {
    for (final listener in listeners) {
      _listenerById[listener.listenerId] = listener;
    }
    _eventSubscription = _eventPort.listen(_handleEvent);
    _stateStore.events.listen(_handleStateEvent);
    _stateStore.start();
  }

  final NativeRuntimeWithHandles runtime;
  final List<RouterListener> listeners;
  final Duration pollInterval;
  final RouterWorkerEntryPoint entryPoint;
  final String? libraryPathHint;
  final RouterSettings settings;
  final void Function(Object event)? onEvent;

  final ReceivePort _eventPort;
  late final StreamSubscription<dynamic> _eventSubscription;
  final Map<int, RouterListener> _listenerById = {};
  final List<_WorkerHandle> _workers = [];
  final Map<int, _WorkerHandle> _connectionOwners = {};
  final Map<int, Isolate> _pendingIsolates = {};
  final RouterStateStore _stateStore;
  bool _running = false;
  bool _stopping = false;
  Future<void>? _loopFuture;
  int _nextWorkerIndex = 0;
  int _nextWorkerId = 1;

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

    final drainFutures = <Future<void>>[];
    for (final worker in _workers) {
      worker.drainCompleter ??= Completer<void>();
      drainFutures.add(worker.drainCompleter!.future);
      worker.commandPort.send(<Object?>[
        _workerCmdDrainConnections,
        'wamp.close.system_shutdown',
      ]);
    }

    _running = false;
    final loop = _loopFuture;
    if (drainFutures.isNotEmpty) {
      await Future.wait(drainFutures);
    }
    if (loop != null) {
      await loop;
    }
    await _eventSubscription.cancel();
    _eventPort.close();
    _stateStore.dispose();
    for (final worker in _workers.toList()) {
      _shutdownWorker(worker, terminateIsolate: true);
    }
    for (final isolate in _pendingIsolates.values) {
      isolate.kill(priority: Isolate.immediate);
    }
    _workers.clear();
    _pendingIsolates.clear();
    _connectionOwners.clear();
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
        onEvent?.call({
          'source': 'boss',
          'type': 'boss_error',
          'listenerId': listener.listenerId,
          'error': error.toString(),
        });
        break;
      }
      if (connectionId == 0) {
        break;
      }
      await _assignConnection(listener, connectionId);
    }
  }

  Future<void> _assignConnection(
    RouterListener listener,
    int connectionId,
  ) async {
    final minWorkers = settings.workerPool.minWorkers;
    if (_workers.length < minWorkers) {
      await _spawnWorker(listener, connectionId);
      return;
    }

    final worker = _chooseWorker();
    if (worker == null) {
      await _spawnWorker(listener, connectionId);
      return;
    }
    worker.connections.add(connectionId);
    _connectionOwners[connectionId] = worker;
    worker.commandPort.send(<Object?>[
      _workerCmdAddConnection,
      listener.listenerId,
      connectionId,
    ]);
  }

  _WorkerHandle? _chooseWorker() {
    if (_workers.isEmpty) {
      return null;
    }
    if (_nextWorkerIndex >= _workers.length) {
      _nextWorkerIndex %= _workers.length;
    }
    final worker = _workers[_nextWorkerIndex];
    _nextWorkerIndex = (_nextWorkerIndex + 1) % _workers.length;
    return worker;
  }

  void _dispatchMessages() {
    final workersSnapshot = List<_WorkerHandle>.from(_workers);
    for (final worker in workersSnapshot) {
      if (worker.busy || worker.connections.isEmpty) {
        continue;
      }
      final connections = worker.connections;
      if (connections.isEmpty) {
        continue;
      }
      if (worker.connectionCursor >= connections.length) {
        worker.connectionCursor %= connections.length;
      }
      int? chosenConnection;
      int handle = 0;
      for (var i = 0; i < connections.length; i++) {
        final index = (worker.connectionCursor + i) % connections.length;
        final connectionId = connections[index];
        try {
          handle = runtime.pollMessageHandle(connectionId);
        } on NativeTransportException catch (error) {
          onEvent?.call({
            'source': 'boss',
            'type': 'boss_error',
            'connectionId': connectionId,
            'error': error.toString(),
          });
          if (error.code == NativeTransportErrorCode.connectionNotFound) {
            _detachConnection(connectionId, notifyWorker: true);
          }
          continue;
        }
        if (handle == 0) {
          continue;
        }
        chosenConnection = connectionId;
        worker.connectionCursor = (index + 1) % connections.length;
        break;
      }
      if (chosenConnection == null || handle == 0) {
        if (connections.isNotEmpty) {
          worker.connectionCursor =
              (worker.connectionCursor + 1) % connections.length;
        } else {
          worker.connectionCursor = 0;
        }
        continue;
      }
      worker.busy = true;
      worker.commandPort.send(<Object?>[
        _workerCmdProcess,
        chosenConnection,
        handle,
      ]);
    }
  }

  Future<void> _spawnWorker(RouterListener listener, int connectionId) async {
    final args = <String, Object?>{
      'bossPort': _eventPort.sendPort,
      'connectionId': connectionId,
      'listenerId': listener.listenerId,
      'libraryPath': libraryPathHint,
      'statePort': _stateStore.commandPort,
      'settings': RouterSettingsCodec.toMap(settings),
      'listener': {
        'listenerId': listener.listenerId,
        'port': listener.port,
        'endpoint': RouterSettingsCodec.endpointToMap(listener.endpoint),
      },
      'listeners': listeners
          .map(
            (entry) => {
              'listenerId': entry.listenerId,
              'port': entry.port,
              'endpoint': RouterSettingsCodec.endpointToMap(entry.endpoint),
            },
          )
          .toList(growable: false),
    };
    final isolate = await Isolate.spawn<Map<String, Object?>>(
      entryPoint,
      args,
      debugName: 'connectanum-router-worker-$connectionId',
    );
    _pendingIsolates[connectionId] = isolate;
  }

  void _handleEvent(dynamic message) {
    if (message is! Map) {
      onEvent?.call({
        'source': 'worker',
        'type': 'worker_unknown_event',
        'payload': message,
      });
      return;
    }

    final type = message['type'];
    final Map<String, Object?> payload = {'source': 'worker'};

    if (type == _workerEventRegister) {
      _handleWorkerRegister(message);
      payload
        ..['type'] = 'worker_registered'
        ..['connectionId'] = message['connectionId']
        ..['listenerId'] = message['listenerId'];
    } else if (type == 'worker_send') {
      final connectionId = message['connectionId'] as int;
      final Uint8List payloadBytes = message['payload'] as Uint8List;
      try {
        runtime.sendMessage(connectionId, payloadBytes);
        payload
          ..['type'] = 'worker_send'
          ..['connectionId'] = connectionId;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_send_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } on UnsupportedError catch (error) {
        payload
          ..['type'] = 'worker_send_unsupported'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      }
    } else if (type == 'worker_forward_message') {
      final connectionId = message['connectionId'] as int;
      final target = _connectionOwners[connectionId];
      if (target != null) {
        target.commandPort.send([
          _workerCmdSendMessage,
          connectionId,
          message['message'],
        ]);
      }
      payload
        ..['type'] = 'worker_forward_message'
        ..['connectionId'] = connectionId;
    } else if (type == 'worker_forward_native_event') {
      final connectionId = message['connectionId'] as int;
      final handle = message['handle'] as int;
      final subscriptionId = message['subscriptionId'] as int;
      final publicationId = message['publicationId'] as int;
      final publisherSessionId = message['publisherSessionId'] as int?;
      final topic = message['topic'] as String?;
      try {
        runtime.forwardPublishEvent(
          handle: handle,
          connectionId: connectionId,
          subscriptionId: subscriptionId,
          publicationId: publicationId,
          publisherSessionId: publisherSessionId,
          topic: topic,
        );
        payload
          ..['type'] = 'worker_forward_native_event'
          ..['connectionId'] = connectionId
          ..['subscriptionId'] = subscriptionId
          ..['publicationId'] = publicationId;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_forward_native_event_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } finally {
        runtime.releaseMessageHandle(handle);
      }
    } else if (type == 'worker_forward_native_invocation') {
      final connectionId = message['connectionId'] as int;
      final handle = message['handle'] as int;
      final invocationId = message['invocationId'] as int;
      final registrationId = message['registrationId'] as int;
      final callerSessionId = message['callerSessionId'] as int?;
      final procedure = message['procedure'] as String?;
      final receiveProgress = message['receiveProgress'] as bool?;
      try {
        runtime.forwardCallInvocation(
          handle: handle,
          connectionId: connectionId,
          invocationId: invocationId,
          registrationId: registrationId,
          callerSessionId: callerSessionId,
          procedure: procedure,
          receiveProgress: receiveProgress,
        );
        payload
          ..['type'] = 'worker_forward_native_invocation'
          ..['connectionId'] = connectionId
          ..['invocationId'] = invocationId
          ..['registrationId'] = registrationId;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_forward_native_invocation_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } finally {
        runtime.releaseMessageHandle(handle);
      }
    } else if (type == 'worker_forward_native_result') {
      final connectionId = message['connectionId'] as int;
      final handle = message['handle'] as int;
      final requestId = message['requestId'] as int;
      final progress = message['progress'] as bool? ?? false;
      try {
        runtime.forwardResultFromYield(
          handle: handle,
          connectionId: connectionId,
          requestId: requestId,
          progress: progress,
        );
        payload
          ..['type'] = 'worker_forward_native_result'
          ..['connectionId'] = connectionId
          ..['requestId'] = requestId
          ..['progress'] = progress;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_forward_native_result_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } finally {
        runtime.releaseMessageHandle(handle);
      }
    } else if (type == 'worker_forward_native_error') {
      final connectionId = message['connectionId'] as int;
      final handle = message['handle'] as int;
      final requestType = message['requestType'] as int;
      final requestId = message['requestId'] as int;
      try {
        runtime.forwardInvocationError(
          handle: handle,
          connectionId: connectionId,
          requestType: requestType,
          requestId: requestId,
        );
        payload
          ..['type'] = 'worker_forward_native_error'
          ..['connectionId'] = connectionId
          ..['requestId'] = requestId;
      } on NativeTransportException catch (error) {
        payload
          ..['type'] = 'worker_forward_native_error_error'
          ..['connectionId'] = connectionId
          ..['error'] = error.toString();
      } finally {
        runtime.releaseMessageHandle(handle);
      }
    } else if (type == _workerEventConnectionAdded) {
      payload
        ..['type'] = 'worker_connection_added'
        ..['connectionId'] = message['connectionId']
        ..['listenerId'] = message['listenerId'];
    } else if (type == _workerEventConnectionRemoved) {
      final connectionId = message['connectionId'] as int;
      final worker = _connectionOwners.remove(connectionId);
      worker?.connections.remove(connectionId);
      payload
        ..['type'] = 'worker_connection_removed'
        ..['connectionId'] = connectionId;
    } else if (type == _workerEventDrained) {
      final workerHash = message['workerHash'] as int?;
      _WorkerHandle? drainedWorker;
      if (workerHash != null) {
        for (final candidate in _workers) {
          if (candidate.isolateHash == workerHash) {
            drainedWorker = candidate;
            break;
          }
        }
      }
      final completer = drainedWorker?.drainCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      payload
        ..['type'] = 'worker_drained'
        ..['workerHash'] = workerHash;
    } else if (type == _workerEventReady) {
      final connectionId = message['connectionId'] as int;
      final worker = _connectionOwners[connectionId];
      worker?.busy = false;
      payload
        ..['type'] = 'worker_ready'
        ..['connectionId'] = connectionId;
    } else if (type == _workerEventShutdown) {
      final connectionId = message['connectionId'] as int;
      final worker = _connectionOwners[connectionId];
      if (worker != null) {
        _shutdownWorker(worker, terminateIsolate: false);
      }
      payload
        ..['type'] = 'worker_shutdown'
        ..['connectionId'] = connectionId;
    } else if (type == _workerEventError) {
      final connectionId = message['connectionId'] as int?;
      if (connectionId != null) {
        final worker = _connectionOwners[connectionId];
        worker?.busy = false;
      }
      payload
        ..['type'] = 'worker_error'
        ..['connectionId'] = connectionId
        ..['error'] = message['error']
        ..['stackTrace'] = message['stackTrace'];
    } else {
      payload
        ..['type'] = 'worker_unknown_event'
        ..['payload'] = message;
    }

    onEvent?.call(payload);
  }

  void _handleStateEvent(StateChangedEvent event) {
    onEvent?.call({
      'source': 'state',
      'type': 'state_changed',
      'realmUri': event.realmUri,
      'version': event.version,
    });
  }

  void forwardMessageToConnection(
    int connectionId,
    AbstractMessage message,
  ) {
    final worker = _connectionOwners[connectionId];
    if (worker == null) {
      throw StateError('Connection $connectionId not registered on router');
    }
    worker.commandPort.send(<Object?>[
      _workerCmdSendMessage,
      connectionId,
      message,
    ]);
  }

  void _handleWorkerRegister(Map<dynamic, dynamic> message) {
    final connectionId = message['connectionId'] as int;
    final listenerId = message['listenerId'] as int;
    final commandPort = message['commandPort'] as SendPort;
    final SendPort? statePort = message['statePort'] as SendPort?;
    final isolate = _pendingIsolates.remove(connectionId);
    final listener = _listenerById[listenerId];
    if (isolate == null || listener == null) {
      commandPort.send(<Object?>[_workerCmdShutdown]);
      isolate?.kill(priority: Isolate.immediate);
      return;
    }
    final worker = _WorkerHandle(
      id: _nextWorkerId++,
      isolate: isolate,
      commandPort: commandPort,
      statePort: statePort ?? _stateStore.commandPort,
      isolateHash: message['workerHash'] as int? ?? isolate.hashCode,
    )..connections.add(connectionId);
    _workers.add(worker);
    _connectionOwners[connectionId] = worker;
  }

  void _shutdownWorker(_WorkerHandle worker, {bool terminateIsolate = false}) {
    for (final connectionId in worker.connections.toList()) {
      _connectionOwners.remove(connectionId);
      worker.commandPort.send(<Object?>[
        _workerCmdRemoveConnection,
        connectionId,
      ]);
    }
    worker.commandPort.send(<Object?>[_workerCmdShutdown]);
    if (terminateIsolate) {
      worker.isolate.kill(priority: Isolate.immediate);
    }
    _workers.remove(worker);
  }

  void _detachConnection(int connectionId, {bool notifyWorker = false}) {
    final worker = _connectionOwners.remove(connectionId);
    if (worker == null) {
      final pending = _pendingIsolates.remove(connectionId);
      pending?.kill(priority: Isolate.immediate);
      return;
    }
    worker.connections.remove(connectionId);
    if (notifyWorker) {
      worker.commandPort.send(<Object?>[
        _workerCmdRemoveConnection,
        connectionId,
      ]);
    }
  }
}

class _WorkerHandle {
  _WorkerHandle({
    required this.id,
    required this.isolate,
    required this.commandPort,
    required this.statePort,
    required this.isolateHash,
  });

  final int id;
  final Isolate isolate;
  final SendPort commandPort;
  final SendPort statePort;
  final int isolateHash;
  final List<int> connections = [];
  int connectionCursor = 0;
  bool busy = false;
  Completer<void>? drainCompleter;
}
