import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/vault_storage.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  final argonIterations = _positiveEnvironment(
    'WAMP_APP_BENCH_ARGON_ITERATIONS',
    3,
  );
  final argonMemoryKiB = _positiveEnvironment(
    'WAMP_APP_BENCH_ARGON_MEMORY_KIB',
    65536,
  );
  final messageCount = _positiveEnvironment('WAMP_APP_BENCH_MESSAGE_COUNT', 20);

  test('production application benchmark', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'wamp-app-production-bench-',
    );
    final server = await WampAppServer.start(
      WampAppServerConfig(
        host: '127.0.0.1',
        port: 0,
        websocketPath: '/ws',
        accountStorePath: '${temporary.path}/accounts.json',
        messageStorePath: '${temporary.path}/messages.json',
        argonIterations: argonIterations,
        argonMemoryKiB: argonMemoryKiB,
      ),
    );
    final aliceStorage = _MemoryVaultStorage();
    final bobStorage = _MemoryVaultStorage();
    final alice = _controller(
      storage: aliceStorage,
      deviceName: 'Benchmark Alice device',
      argonIterations: argonIterations,
      argonMemoryKiB: argonMemoryKiB,
    );
    final bob = _controller(
      storage: bobStorage,
      deviceName: 'Benchmark Bob device',
      argonIterations: argonIterations,
      argonMemoryKiB: argonMemoryKiB,
    );
    addTearDown(() async {
      alice.dispose();
      bob.dispose();
      await server.close();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    final endpoint = server.websocketUri.toString();
    const alicePassword = 'benchmark alice password';
    const bobPassword = 'benchmark bob password';
    final onboardingSamples = <double>[];
    onboardingSamples.add(
      await _measure(() async {
        await alice.registerAndConnect(
          serverAddress: endpoint,
          username: 'alice',
          displayName: 'Benchmark Alice',
          password: alicePassword,
        );
        _expectConnected(alice);
      }),
    );
    onboardingSamples.add(
      await _measure(() async {
        await bob.registerAndConnect(
          serverAddress: endpoint,
          username: 'bob',
          displayName: 'Benchmark Bob',
          password: bobPassword,
        );
        _expectConnected(bob);
      }),
    );

    final reconnectSamples = <double>[];
    await alice.signOut();
    reconnectSamples.add(
      await _measure(() async {
        await alice.login(
          serverAddress: endpoint,
          username: 'alice',
          password: alicePassword,
        );
        _expectConnected(alice);
      }),
    );
    await bob.signOut();
    reconnectSamples.add(
      await _measure(() async {
        await bob.login(
          serverAddress: endpoint,
          username: 'bob',
          password: bobPassword,
        );
        _expectConnected(bob);
      }),
    );

    await _sendAndAwait(alice: alice, bob: bob, text: 'benchmark warmup');
    final acceptedSamples = <double>[];
    final deliveredSamples = <double>[];
    final messageWatch = Stopwatch()..start();
    for (var index = 0; index < messageCount; index += 1) {
      final sample = await _sendAndAwait(
        alice: alice,
        bob: bob,
        text: 'benchmark message ${index.toString().padLeft(6, '0')}',
      );
      acceptedSamples.add(sample.acceptedMilliseconds);
      deliveredSamples.add(sample.deliveredMilliseconds);
    }
    messageWatch.stop();

    final result = {
      'schema_version': 1,
      'benchmark': 'wamp_app_application',
      'platform': Platform.operatingSystem,
      'processors': Platform.numberOfProcessors,
      'workload': {
        'argon_iterations': argonIterations,
        'argon_memory_kib': argonMemoryKiB,
        'accounts': 2,
        'messages': messageCount,
        'message_bytes': utf8.encode('benchmark message 000000').length,
        'transport': 'websocket-cbor',
        'vault_storage': 'isolated-memory',
      },
      'onboarding': _summarize(onboardingSamples),
      'reconnect': _summarize(reconnectSamples),
      'direct_message': {
        'accepted': _summarize(acceptedSamples),
        'delivered': _summarize(deliveredSamples),
        'messages_per_second': _round(
          messageCount /
              (messageWatch.elapsedMicroseconds /
                  Duration.microsecondsPerSecond),
        ),
      },
    };
    // This line intentionally contains only workload metadata and timings.
    debugPrint('WAMP_APP_PRODUCTION_BENCHMARK ${jsonEncode(result)}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

WampAppController _controller({
  required VaultStorage storage,
  required String deviceName,
  required int argonIterations,
  required int argonMemoryKiB,
}) => WampAppController(
  trustStore: EncryptedDeviceVault(
    storage: storage,
    iterations: argonIterations,
    memoryKiB: argonMemoryKiB,
  ),
  deviceName: deviceName,
);

void _expectConnected(WampAppController controller) {
  expect(
    controller.status,
    WampAppStatus.connected,
    reason: '${controller.errorMessage} / ${controller.messageError}',
  );
}

Future<_MessageSample> _sendAndAwait({
  required WampAppController alice,
  required WampAppController bob,
  required String text,
}) async {
  final watch = Stopwatch()..start();
  expect(await alice.sendMessage(recipientUsername: 'bob', text: text), isTrue);
  expect(alice.messageError, isNull);
  final sent = alice.messages.singleWhere((message) => message.text == text);
  final acceptedMilliseconds = watch.elapsedMicroseconds / 1000;
  await _waitFor(
    () =>
        bob.messages.any((message) => message.messageId == sent.messageId) &&
        alice.messages
                .singleWhere((message) => message.messageId == sent.messageId)
                .deliveredAt !=
            null,
  );
  watch.stop();
  return _MessageSample(
    acceptedMilliseconds: acceptedMilliseconds,
    deliveredMilliseconds: watch.elapsedMicroseconds / 1000,
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Timed out waiting for benchmark message delivery.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<double> _measure(Future<void> Function() action) async {
  final watch = Stopwatch()..start();
  await action();
  watch.stop();
  return watch.elapsedMicroseconds / 1000;
}

Map<String, Object> _summarize(List<double> samples) {
  final sorted = [...samples]..sort();
  final p95Index = ((sorted.length * 0.95).ceil() - 1).clamp(
    0,
    sorted.length - 1,
  );
  return {
    'samples': sorted.length,
    'average_ms': _round(
      sorted.reduce((left, right) => left + right) / sorted.length,
    ),
    'p95_ms': _round(sorted[p95Index]),
    'maximum_ms': _round(sorted.last),
  };
}

double _round(double value) => double.parse(value.toStringAsFixed(3));

int _positiveEnvironment(String name, int fallback) {
  final raw = Platform.environment[name];
  if (raw == null || raw.isEmpty) return fallback;
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw ArgumentError.value(raw, name, 'must be a positive integer');
  }
  return value;
}

final class _MemoryVaultStorage implements VaultStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _MessageSample {
  const _MessageSample({
    required this.acceptedMilliseconds,
    required this.deliveredMilliseconds,
  });

  final double acceptedMilliseconds;
  final double deliveredMilliseconds;
}
