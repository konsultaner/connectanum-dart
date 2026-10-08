part of '../router_runtime_test.dart';

class _EnqueueAcceptanceRuntime extends _HandleRuntime {
  _EnqueueAcceptanceRuntime(this.failure);
  final Object? failure;
  @override
  void sendMessage(int connectionId, Uint8List payload) {
    final error = failure;
    if (error != null) throw error;
    super.sendMessage(connectionId, payload);
  }
}

void _enqueueAcceptanceWorker(Map<String, Object?> init) {
  final boss = init['bossPort'] as SendPort;
  final connectionId = init['connectionId'] as int;
  final listenerId = init['listenerId'] as int;
  final commands = ReceivePort();
  boss.send({
    'type': kWorkerEventRegister,
    'connectionId': connectionId,
    'listenerId': listenerId,
    'commandPort': commands.sendPort,
    'workerHash': Isolate.current.hashCode,
  });
  boss.send({'type': kWorkerEventReady, 'connectionId': connectionId});
  commands.listen((dynamic raw) async {
    if (raw is! List || raw.isEmpty) return;
    if (raw[0] == kWorkerCmdProcess) {
      final target = raw[1] as int;
      final receipt = ReceivePort();
      try {
        boss.send({
          'type': 'worker_send',
          'connectionId': target,
          'payload': Uint8List.fromList(
            utf8.encode('[6,{},"wamp.close.normal"]'),
          ),
          'acceptedReply': receipt.sendPort,
        });
        final result = await receipt.first.timeout(const Duration(seconds: 2));
        boss.send({
          'type': 'test_enqueue_acceptance',
          'connectionId': target,
          'result': result,
        });
      } catch (error) {
        boss.send({
          'type': 'test_enqueue_acceptance',
          'connectionId': target,
          'error': error.toString(),
        });
      } finally {
        receipt.close();
        boss.send({'type': kWorkerEventReady, 'connectionId': target});
      }
    } else if (raw[0] == kWorkerCmdAddConnection) {
      boss.send({
        'type': kWorkerEventConnectionAdded,
        'connectionId': raw[2],
        'listenerId': raw[1],
      });
      boss.send({'type': kWorkerEventReady, 'connectionId': raw[2]});
    } else if (raw[0] == kWorkerCmdRemoveConnection) {
      boss.send({
        'type': kWorkerEventConnectionRemoved,
        'connectionId': raw[1],
      });
    } else if (raw[0] == kWorkerCmdShutdown) {
      commands.close();
      boss.send({'type': kWorkerEventShutdown, 'connectionId': connectionId});
    } else if (raw[0] == _workerCmdDrainConnections) {
      boss.send({
        'type': kWorkerEventDrained,
        'workerHash': Isolate.current.hashCode,
      });
    }
  });
}

void _flatbuffersWorkerAckTests() {
  final failures = <String, Object?>{
    'accepted': null,
    'queue rejected': NativeTransportException(
      -1,
      'controlled queue rejection',
    ),
    'unsupported': UnsupportedError('controlled unsupported send'),
  };
  for (final entry in failures.entries) {
    test('native worker enqueue acknowledgement: ${entry.key}', () async {
      final runtime = _EnqueueAcceptanceRuntime(entry.value);
      final router = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.disabled,
              maxRawSocketSizeExponent: 16,
            ),
          ],
        ),
      );
      final events = <Object>[];
      final binding = router.start(
        runtime,
        workerEntryPoint: _enqueueAcceptanceWorker,
        onEvent: events.add,
        workerPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(binding.dispose);
      runtime.enqueueHandle(binding.listeners.single.listenerId, 9001);
      for (var attempt = 0; attempt < 600; attempt++) {
        binding.pollNativeMessages();
        if (_enqueueAcceptanceResults(events).isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final acknowledgement = _enqueueAcceptanceResults(events).single;
      expect(
        acknowledgement.containsKey('error'),
        isFalse,
        reason: acknowledgement.toString(),
      );
      expect(acknowledgement['result'], {'accepted': entry.value == null});
      expect(
        runtime.sentMessages[9001] ?? const [],
        hasLength(entry.value == null ? 1 : 0),
      );
    });
  }
}

Iterable<Map> _enqueueAcceptanceResults(List<Object> events) sync* {
  for (final event in events.whereType<Map>()) {
    final payload = event['type'] == 'worker_unknown_event'
        ? event['payload']
        : event;
    if (payload is Map && payload['type'] == 'test_enqueue_acceptance')
      yield payload;
  }
}
