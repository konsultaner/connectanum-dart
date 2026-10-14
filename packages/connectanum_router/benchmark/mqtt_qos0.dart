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
  final broker = args.isEmpty
      ? await MqttQos0Broker.bind('127.0.0.1', 0)
      : null;
  final host = args.isEmpty ? '127.0.0.1' : args[0];
  final port = broker?.port ?? int.parse(args[1]);
  final subscriber = await MqttQos0Client.connect(
    host,
    port,
    clientId: 'bench-sub',
    version: MqttVersion.v5,
  );
  final publisher = await MqttQos0Client.connect(
    host,
    port,
    clientId: 'bench-pub',
    version: MqttVersion.v5,
  );
  try {
    await subscriber.subscribe('bench/one');
    const warmup = 100;
    final count =
        int.tryParse(Platform.environment['MQTT_BENCH_MESSAGES'] ?? '') ?? 2000;
    if (count < 100) {
      throw ArgumentError.value(count, 'MQTT_BENCH_MESSAGES', 'minimum 100');
    }
    const payloadSize = 128;
    final sentAt = Int64List(count);
    final latencies = Int64List(count);
    final seen = Uint8List(count);
    final completed = Completer<void>();
    final warmupDone = Completer<void>();
    var warmupReceived = 0;
    var received = 0;
    var duplicate = 0;
    final stopwatch = Stopwatch()..start();
    final subscription = subscriber.messages.listen((message) {
      if (message.topic != 'bench/one' ||
          message.payload.length != payloadSize) {
        if (!completed.isCompleted) {
          completed.completeError(StateError('unexpected publication'));
        }
        return;
      }
      final id = ByteData.sublistView(message.payload).getUint32(0);
      if (id >= count) {
        warmupReceived++;
        if (warmupReceived == warmup) warmupDone.complete();
        return;
      }
      if (seen[id] != 0) {
        duplicate++;
        return;
      }
      seen[id] = 1;
      latencies[id] = stopwatch.elapsedMicroseconds - sentAt[id];
      received++;
      if (received == count && !completed.isCompleted) completed.complete();
    });
    final payload = Uint8List(payloadSize);
    final data = ByteData.sublistView(payload);
    for (var i = 0; i < warmup; i++) {
      data.setUint32(0, count + i);
      await publisher.publish('bench/one', payload);
    }
    await warmupDone.future.timeout(const Duration(seconds: 10));
    stopwatch.reset();
    for (var i = 0; i < count; i++) {
      data.setUint32(0, i);
      sentAt[i] = stopwatch.elapsedMicroseconds;
      await publisher.publish('bench/one', payload);
    }
    try {
      await completed.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw StateError(
        'timed out after delivering $received/$count; '
        'duplicates $duplicate',
      );
    }
    final elapsedUs = stopwatch.elapsedMicroseconds;
    await subscription.cancel();
    stopwatch.stop();
    if (received != count || duplicate != 0) {
      throw StateError('delivered $received/$count; duplicates $duplicate');
    }
    final sorted = latencies.toList()..sort();
    stdout.writeln(
      jsonEncode({
        'broker': broker == null ? '$host:$port' : 'connectanum-qos0',
        'profile': 'mqtt5-tcp-qos0-one-subscriber-128B',
        'warmup': warmup,
        'sent': count,
        'received': received,
        'duplicates': duplicate,
        'elapsed_us': elapsedUs,
        'throughput_delivered_per_sec': count * 1000000 / elapsedUs,
        'latency_p50_us': sorted[(count * 0.50).ceil() - 1],
        'latency_p95_us': sorted[(count * 0.95).ceil() - 1],
        'latency_p99_us': sorted[(count * 0.99).ceil() - 1],
        'runner_rss_bytes': ProcessInfo.currentRss,
      }),
    );
  } finally {
    await publisher.close();
    await subscriber.close();
    await broker?.close();
  }
}
