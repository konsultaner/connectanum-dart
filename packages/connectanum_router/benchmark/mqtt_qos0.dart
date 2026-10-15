import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/mqtt.dart';
import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_router/mqtt.dart';

/// Run from this package: `dart run benchmark/mqtt_qos0.dart [host port]`.
/// With no target, starts a local Connectanum QoS 0 broker. A supplied host and
/// port allow the identical client workload to run against Mosquitto.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.length != 2) {
    throw ArgumentError('use no arguments or host port');
  }
  final versionLabel = Platform.environment['MQTT_BENCH_VERSION'] ?? '5';
  final version = switch (versionLabel) {
    '5' => MqttVersion.v5,
    '311' => MqttVersion.v311,
    _ => throw ArgumentError.value(
      versionLabel,
      'MQTT_BENCH_VERSION',
      'expected 5 or 311',
    ),
  };
  final broker = args.isEmpty
      ? await MqttQos0Broker.bind('127.0.0.1', 0)
      : null;
  final host = args.isEmpty ? '127.0.0.1' : args[0];
  final port = broker?.port ?? int.parse(args[1]);
  final tlsCa = Platform.environment['MQTT_BENCH_TLS_CA'];
  final transport =
      Platform.environment['MQTT_BENCH_TRANSPORT'] ??
      (tlsCa == null ? 'tcp' : 'tls');
  if (!['tcp', 'tls', 'ws', 'wss'].contains(transport)) {
    throw ArgumentError.value(transport, 'MQTT_BENCH_TRANSPORT');
  }
  final tlsContext = tlsCa == null
      ? null
      : (SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates(tlsCa));
  Future<MqttQos0Client> connectClient(String clientId) => switch (transport) {
    'ws' || 'wss' => MqttQos0Client.connectWebSocket(
      Uri.parse('$transport://$host:$port/mqtt'),
      clientId: clientId,
      version: version,
      context: tlsContext,
    ),
    'tls' => MqttQos0Client.connectSecure(
      host,
      port,
      clientId: clientId,
      version: version,
      context: tlsContext,
    ),
    _ => MqttQos0Client.connect(
      host,
      port,
      clientId: clientId,
      version: version,
    ),
  };
  final subscriberCount =
      int.tryParse(Platform.environment['MQTT_BENCH_SUBSCRIBERS'] ?? '') ?? 1;
  if (subscriberCount < 1 || subscriberCount > 16) {
    throw ArgumentError.value(
      subscriberCount,
      'MQTT_BENCH_SUBSCRIBERS',
      'expected 1 through 16',
    );
  }
  final subscribers = <MqttQos0Client>[];
  MqttQos0Client? publisher;
  try {
    for (var i = 0; i < subscriberCount; i++) {
      final subscriber = await connectClient('bench-sub-$i');
      subscribers.add(subscriber);
      await subscriber.subscribe('bench/one');
    }
    publisher = await connectClient('bench-pub');
    const warmup = 100;
    final count =
        int.tryParse(Platform.environment['MQTT_BENCH_MESSAGES'] ?? '') ?? 2000;
    final window =
        int.tryParse(Platform.environment['MQTT_BENCH_WINDOW'] ?? '') ?? 0;
    final publishMode = Platform.environment['MQTT_BENCH_MODE'] ?? 'single';
    if (count < 100) {
      throw ArgumentError.value(count, 'MQTT_BENCH_MESSAGES', 'minimum 100');
    }
    if (window < 0 || window > count) {
      throw ArgumentError.value(window, 'MQTT_BENCH_WINDOW', 'invalid window');
    }
    if (publishMode != 'single' && publishMode != 'batch') {
      throw ArgumentError.value(publishMode, 'MQTT_BENCH_MODE', 'invalid mode');
    }
    if (publishMode == 'batch' && (window == 0 || window > 512)) {
      throw ArgumentError.value(window, 'MQTT_BENCH_WINDOW', 'batch window');
    }
    final payloadSize =
        int.tryParse(Platform.environment['MQTT_BENCH_PAYLOAD_BYTES'] ?? '') ??
        128;
    if (payloadSize < 4 || payloadSize > 65536) {
      throw ArgumentError.value(
        payloadSize,
        'MQTT_BENCH_PAYLOAD_BYTES',
        'expected 4 through 65536',
      );
    }
    final payload = Uint8List(payloadSize);
    for (var i = 4; i < payloadSize; i++) {
      payload[i] = (i * 29 + 7) & 0xff;
    }
    final data = ByteData.sublistView(payload);
    final sentAt = Int64List(count);
    final latencies = Int64List(count * subscriberCount);
    final seen = List.generate(subscriberCount, (_) => Uint8List(count));
    final completed = Completer<void>();
    final warmupDone = Completer<void>();
    final warmupReceived = List.filled(subscriberCount, 0);
    var warmupWindowTarget = 0;
    Completer<void>? warmupWindowDone;
    final receivedPerSubscriber = List.filled(subscriberCount, 0);
    var received = 0;
    var duplicate = 0;
    var windowTarget = 0;
    Completer<void>? windowDone;
    final stopwatch = Stopwatch()..start();
    final subscriptions = <StreamSubscription<MqttPublish>>[];
    for (
      var subscriberIndex = 0;
      subscriberIndex < subscriberCount;
      subscriberIndex++
    ) {
      final index = subscriberIndex;
      subscriptions.add(
        subscribers[index].messages.listen((message) {
          if (message.topic != 'bench/one' ||
              message.payload.length != payloadSize) {
            if (!completed.isCompleted) {
              completed.completeError(StateError('unexpected publication'));
            }
            return;
          }
          for (var i = 4; i < payloadSize; i++) {
            if (message.payload[i] != payload[i]) {
              if (!completed.isCompleted) {
                completed.completeError(StateError('corrupt payload byte $i'));
              }
              return;
            }
          }
          final id = ByteData.sublistView(message.payload).getUint32(0);
          if (id >= count) {
            if (id != count + warmupReceived[index] ||
                warmupReceived[index] == warmup) {
              if (!completed.isCompleted) {
                completed.completeError(
                  StateError('unexpected warmup publication'),
                );
              }
              return;
            }
            warmupReceived[index]++;
            final waiting = warmupWindowDone;
            if (waiting != null &&
                warmupReceived.every((value) => value >= warmupWindowTarget) &&
                !waiting.isCompleted) {
              waiting.complete();
            }
            if (warmupReceived.every((value) => value == warmup) &&
                !warmupDone.isCompleted) {
              warmupDone.complete();
            }
            return;
          }
          if (seen[index][id] != 0) {
            duplicate++;
            return;
          }
          if (id != receivedPerSubscriber[index]) {
            if (!completed.isCompleted) {
              completed.completeError(
                StateError('out-of-order publication $id'),
              );
            }
            return;
          }
          seen[index][id] = 1;
          latencies[index * count + id] =
              stopwatch.elapsedMicroseconds - sentAt[id];
          receivedPerSubscriber[index]++;
          received++;
          if (windowDone != null &&
              receivedPerSubscriber.every((value) => value >= windowTarget) &&
              !windowDone.isCompleted) {
            windowDone.complete();
          }
          if (received == count * subscriberCount && !completed.isCompleted) {
            completed.complete();
          }
        }),
      );
    }
    await publishMqttBenchmarkWarmup(
      messageCount: warmup,
      windowMessages: window,
      publish: (index) async {
        data.setUint32(0, count + index);
        await publisher!.publish('bench/one', payload);
      },
      waitForDelivery: (target) async {
        warmupWindowTarget = target;
        if (warmupReceived.any((value) => value < warmupWindowTarget)) {
          final waiting = Completer<void>();
          warmupWindowDone = waiting;
          await waiting.future.timeout(const Duration(seconds: 10));
        }
        warmupWindowDone = null;
      },
    );
    await warmupDone.future.timeout(const Duration(seconds: 10));
    stopwatch.reset();
    final pendingPayloads = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      data.setUint32(0, i);
      sentAt[i] = stopwatch.elapsedMicroseconds;
      if (publishMode == 'single') {
        await publisher.publish('bench/one', payload);
      } else {
        pendingPayloads.add(Uint8List.fromList(payload));
        if ((i + 1) % window == 0 || i + 1 == count) {
          await publisher.publishBatch('bench/one', pendingPayloads);
          pendingPayloads.clear();
        }
      }
      if (window > 0 && ((i + 1) % window == 0 || i + 1 == count)) {
        windowTarget = i + 1;
        if (receivedPerSubscriber.any((value) => value < windowTarget)) {
          windowDone = Completer<void>();
          await windowDone.future.timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw StateError(
              'window target $windowTarget, received $receivedPerSubscriber '
              'of $count publications, duplicates $duplicate',
            ),
          );
        }
        windowDone = null;
      }
    }
    try {
      await completed.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw StateError(
        'timed out after delivering $received/${count * subscriberCount}; '
        'duplicates $duplicate',
      );
    }
    final elapsedUs = stopwatch.elapsedMicroseconds;
    stopwatch.stop();
    // Keep observing briefly after the last distinct ID for late duplicates.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    if (received != count * subscriberCount ||
        duplicate != 0 ||
        receivedPerSubscriber.any((value) => value != count)) {
      throw StateError(
        'delivered $received/${count * subscriberCount}; '
        'per subscriber $receivedPerSubscriber; duplicates $duplicate',
      );
    }
    final sorted = latencies.toList()..sort();
    stdout.writeln(
      jsonEncode({
        'broker': broker == null ? '$host:$port' : 'connectanum-qos0',
        'profile':
            'mqtt$versionLabel-$transport-qos0-${subscriberCount == 1 ? 'one-subscriber' : 'fanout$subscriberCount'}-${payloadSize}B'
            '${window == 0 ? '' : '-window$window'}'
            '${publishMode == 'batch' ? '-batch$window' : ''}',
        'transport': transport,
        'publish_mode': publishMode,
        'mqtt_version': versionLabel,
        'window_messages': window,
        'subscribers': subscriberCount,
        'payload_bytes': payloadSize,
        'warmup': warmup,
        'sent': count,
        'received': received,
        'received_per_subscriber': receivedPerSubscriber,
        'duplicates': duplicate,
        'elapsed_us': elapsedUs,
        'throughput_delivered_per_sec':
            count * subscriberCount * 1000000 / elapsedUs,
        'latency_p50_us': sorted[(sorted.length * 0.50).ceil() - 1],
        'latency_p95_us': sorted[(sorted.length * 0.95).ceil() - 1],
        'latency_p99_us': sorted[(sorted.length * 0.99).ceil() - 1],
        'runner_rss_bytes': ProcessInfo.currentRss,
      }),
    );
  } finally {
    await publisher?.close();
    for (final subscriber in subscribers) {
      await subscriber.close();
    }
    await broker?.close();
  }
}

/// Sends warmup traffic under the same in-flight window as the measured run.
Future<void> publishMqttBenchmarkWarmup({
  required int messageCount,
  required int windowMessages,
  required Future<void> Function(int index) publish,
  required Future<void> Function(int target) waitForDelivery,
}) async {
  for (var index = 0; index < messageCount; index++) {
    await publish(index);
    if (windowMessages > 0 &&
        ((index + 1) % windowMessages == 0 || index + 1 == messageCount)) {
      await waitForDelivery(index + 1);
    }
  }
}
