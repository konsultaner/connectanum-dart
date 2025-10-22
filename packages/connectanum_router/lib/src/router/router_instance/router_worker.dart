part of '../router_instance.dart';

/// Entry point signature for worker isolates. Custom entry points can be injected
/// in tests to observe scheduling behaviour.
typedef RouterWorkerEntryPoint = void Function(Map<String, Object?> init);

const int _workerCmdProcess = 1;
const int _workerCmdShutdown = 2;
const int _workerCmdAddConnection = 3;
const int _workerCmdRemoveConnection = 4;

const int _workerEventRegister = 1;
const int _workerEventReady = 2;
const int _workerEventError = 3;
const int _workerEventShutdown = 4;
const int _workerEventConnectionAdded = 5;
const int _workerEventConnectionRemoved = 6;

/// Default worker entry point that materialises native message handles in an
/// isolate and hands them over to the router once available.
void _routerWorkerEntryPoint(Map<String, Object?> init) {
  final bossPort = init['bossPort'] as SendPort;
  final connectionId = init['connectionId'] as int;
  final listenerId = init['listenerId'] as int;
  final libraryPath = init['libraryPath'] as String?;
  final decoder = NativeMessageHandleDecoder(libraryPath: libraryPath);
  final commandPort = ReceivePort();
  final Map<int, int> connections = {connectionId: listenerId};

  bossPort.send({
    'type': _workerEventRegister,
    'connectionId': connectionId,
    'listenerId': listenerId,
    'commandPort': commandPort.sendPort,
  });
  bossPort.send({'type': _workerEventReady, 'connectionId': connectionId});

  bool shuttingDown = false;
  late final StreamSubscription<dynamic> subscription;
  subscription = commandPort.listen((dynamic raw) {
    if (raw is! List || raw.isEmpty) {
      return;
    }
    final command = raw[0];
    if (command == _workerCmdProcess) {
      if (shuttingDown) {
        return;
      }
      final connectionId = raw[1] as int;
      final handle = raw[2] as int;
      try {
        final incoming = decoder.materialize(handle);
        try {
          // TODO: invoke router session logic once available.
        } finally {
          incoming.dispose();
        }
      } catch (error, stackTrace) {
        bossPort.send({
          'type': _workerEventError,
          'connectionId': connectionId,
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        });
      } finally {
        if (!shuttingDown) {
          bossPort.send({
            'type': _workerEventReady,
            'connectionId': connectionId,
          });
        }
      }
    } else if (command == _workerCmdAddConnection) {
      final listenerId = raw[1] as int;
      final newConnectionId = raw[2] as int;
      connections[newConnectionId] = listenerId;
      bossPort.send({
        'type': _workerEventConnectionAdded,
        'connectionId': newConnectionId,
        'listenerId': listenerId,
      });
    } else if (command == _workerCmdRemoveConnection) {
      final removeId = raw[1] as int;
      connections.remove(removeId);
      bossPort.send({
        'type': _workerEventConnectionRemoved,
        'connectionId': removeId,
      });
    } else if (command == _workerCmdShutdown) {
      if (shuttingDown) {
        return;
      }
      shuttingDown = true;
      subscription.cancel();
      commandPort.close();
      bossPort.send({
        'type': _workerEventShutdown,
        'connectionId': connectionId,
      });
    }
  });
}
