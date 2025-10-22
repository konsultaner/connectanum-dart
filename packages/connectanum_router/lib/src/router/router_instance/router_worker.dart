part of '../router_instance.dart';

/// Entry point signature for worker isolates. Custom entry points can be injected
/// in tests to observe scheduling behaviour.
typedef RouterWorkerEntryPoint = void Function(Map<String, Object?> init);

const int _workerCmdProcess = 1;
const int _workerCmdShutdown = 2;

const int _workerEventRegister = 1;
const int _workerEventReady = 2;
const int _workerEventError = 3;
const int _workerEventShutdown = 4;

/// Default worker entry point that materialises native message handles in an
/// isolate and hands them over to the router once available.
void _routerWorkerEntryPoint(Map<String, Object?> init) {
  final bossPort = init['bossPort'] as SendPort;
  final connectionId = init['connectionId'] as int;
  final listenerId = init['listenerId'] as int;
  final libraryPath = init['libraryPath'] as String?;
  final decoder = NativeMessageHandleDecoder(libraryPath: libraryPath);
  final commandPort = ReceivePort();

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
      final handle = raw[1] as int;
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
