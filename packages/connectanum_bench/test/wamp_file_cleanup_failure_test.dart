@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:test/test.dart';

void main() {
  for (final phase in ['cancel', 'receiver_close', 'sender_close']) {
    test(
      '$phase failure still attempts every acquired file resource cleanup',
      () async {
        final error = StateError('injected $phase failure');
        final receiver = _CleanupSession(
          cancelError: phase == 'cancel' ? error : null,
          closeError: phase == 'receiver_close' ? error : null,
        );
        final sender = _CleanupSession(
          closeError: phase == 'sender_close' ? error : null,
        );
        final result = await _run(sender, receiver);
        expect(result, same(error));
        expect(receiver.cancelCount, 1);
        expect(receiver.closeCount, 1);
        expect(sender.closeCount, 1);
        expect(sender.cancelCount, 0);
        expect(sender.sendCount, 1);
      },
    );
  }

  for (final phase in ['register', 'send']) {
    test('$phase failure stays primary when file cleanup also fails', () async {
      final primary = StateError('injected $phase failure');
      final secondary = StateError('injected cleanup failure');
      final receiver = _CleanupSession(
        registerError: phase == 'register' ? primary : null,
        cancelError: phase == 'send' ? secondary : null,
        closeError: secondary,
      );
      final sender = _CleanupSession(
        sendError: phase == 'send' ? primary : null,
        closeError: secondary,
      );
      final result = await _run(sender, receiver);
      expect(result, same(primary));
      expect(receiver.cancelCount, phase == 'send' ? 1 : 0);
      expect(receiver.closeCount, 1);
      expect(sender.closeCount, 1);
      expect(sender.cancelCount, 0);
      expect(sender.sendCount, phase == 'send' ? 1 : 0);
    });
  }
}

Future<Object> _run(_CleanupSession sender, _CleanupSession receiver) {
  var opened = 0;
  return WampWorkloadRunner(
        sessionFactory: (_) async => opened++ == 0 ? sender : receiver,
      )
      .run(
        WampScenario(
          transport: WampTransport.rawsocket,
          serializer: WampSerializer.cbor,
          mode: WampMode.fileTransfer,
          uri: 'bench.file_cleanup',
          iterations: 1,
          concurrency: 1,
          payloadBytes: 1,
          eventTimeoutMs: 1000,
        ),
      )
      .then<Object>((value) => value, onError: (Object error) => error);
}

class _CleanupSession implements WampSession, WampFileSession {
  _CleanupSession({
    this.registerError,
    this.sendError,
    this.cancelError,
    this.closeError,
  });
  final Object? registerError;
  final Object? sendError;
  final Object? cancelError;
  final Object? closeError;
  int cancelCount = 0;
  int closeCount = 0;
  int sendCount = 0;

  @override
  int get id => 11;
  @override
  Future<dynamic> get onDisconnect => Completer<void>().future;
  @override
  Future<void> close() async {
    closeCount++;
    if (closeError != null) throw closeError!;
  }

  @override
  Future<WampRegistration> registerFileReceiver(
    String procedure, {
    required int maxConcurrentTransfers,
    required int maxChunkSize,
    required Duration idleTimeout,
  }) async {
    if (registerError != null) throw registerError!;
    return WampRegistration(
      cancel: () async {
        cancelCount++;
        if (cancelError != null) throw cancelError!;
      },
    );
  }

  @override
  Future<void> sendFile(
    String procedure,
    client.WampFileSource source, {
    required int chunkSize,
    required Duration timeout,
    core.CallOptions? options,
  }) async {
    sendCount++;
    if (sendError != null) throw sendError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
