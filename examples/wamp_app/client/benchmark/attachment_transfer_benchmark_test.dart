import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/attachment_chunk_cache_base.dart';
import 'package:wamp_app/src/infrastructure/attachment_chunk_cache_factory_io.dart';
import 'package:wamp_app/src/infrastructure/attachment_cipher.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

const _mebibyte = 1024 * 1024;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sizeMiB = _positiveEnvironment('WAMP_APP_BENCH_SIZE_MIB', 64);
  final iterations = _positiveEnvironment('WAMP_APP_BENCH_ITERATIONS', 5);
  final cacheModes = _cacheModes();

  for (final cacheMode in cacheModes) {
    test('$cacheMode attachment transfer benchmark', () async {
      await _runIteration(cacheMode, 4 * _mebibyte, -1);
      final samples = <_TransferSample>[];
      for (var iteration = 0; iteration < iterations; iteration += 1) {
        samples.add(
          await _runIteration(cacheMode, sizeMiB * _mebibyte, iteration),
        );
      }
      final result = {
        'schema_version': 1,
        'benchmark': 'wamp_app_attachment_transfer',
        'cache': cacheMode,
        'size_mib': sizeMiB,
        'iterations': iterations,
        'chunk_mib': WampAppAttachmentLimits.defaultChunkBytes / _mebibyte,
        'platform': Platform.operatingSystem,
        'processors': Platform.numberOfProcessors,
        'encrypt': _summarize(
          samples.map((sample) => sample.encryptSeconds),
          sizeMiB * _mebibyte,
        ),
        'decrypt': _summarize(
          samples.map((sample) => sample.decryptSeconds),
          sizeMiB * _mebibyte,
        ),
      };
      // One machine-readable line is easy to retain as benchmark evidence.
      // It deliberately excludes attachment identifiers and cryptographic data.
      debugPrint('WAMP_APP_ATTACHMENT_BENCHMARK ${jsonEncode(result)}');
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}

Future<_TransferSample> _runIteration(
  String cacheMode,
  int byteCount,
  int iteration,
) async {
  final temporary = cacheMode == 'disk'
      ? await Directory.systemTemp.createTemp('wamp-app-attachment-bench-')
      : null;
  final cache = switch (cacheMode) {
    'memory' => MemoryAttachmentChunkCache(),
    'disk' => NativeAttachmentChunkCache(rootDirectory: () async => temporary!),
    _ => throw StateError('Unsupported attachment cache benchmark mode.'),
  };
  final cipher = AttachmentCipher();
  final messageId = 'benchmark_message_${cacheMode}_$iteration';
  try {
    final encryptWatch = Stopwatch()..start();
    final attachment = (await cipher.encryptSources(
      scope: 'benchmark',
      senderUsername: 'benchmark-user',
      messageId: messageId,
      sources: [
        AttachmentPlaintextSource(
          name: 'benchmark.bin',
          contentType: 'application/octet-stream',
          kind: ChatAttachmentKind.file,
          byteCount: byteCount,
          openRead: () => _plaintextStream(byteCount),
        ),
      ],
      cache: cache,
    )).single;
    encryptWatch.stop();

    var writtenBytes = 0;
    final decryptWatch = Stopwatch()..start();
    await cipher.decryptToSink(
      scope: 'benchmark',
      senderUsername: 'benchmark-user',
      messageId: messageId,
      attachment: attachment,
      cache: cache,
      write: (bytes) => writtenBytes += bytes.length,
    );
    decryptWatch.stop();
    expect(writtenBytes, byteCount);
    return _TransferSample(
      encryptSeconds: encryptWatch.elapsedMicroseconds / 1000000,
      decryptSeconds: decryptWatch.elapsedMicroseconds / 1000000,
    );
  } finally {
    await cipher.dispose();
    await cache.dispose();
    if (temporary != null && await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  }
}

Stream<List<int>> _plaintextStream(int byteCount) async* {
  final block = Uint8List(64 * 1024);
  for (var index = 0; index < block.length; index += 1) {
    block[index] = (index * 31) % 251;
  }
  var remaining = byteCount;
  while (remaining > 0) {
    final length = remaining < block.length ? remaining : block.length;
    yield length == block.length
        ? block
        : Uint8List.sublistView(block, 0, length);
    remaining -= length;
  }
}

Map<String, double> _summarize(Iterable<double> values, int byteCount) {
  final seconds = values.toList(growable: false)..sort();
  final median = seconds[seconds.length ~/ 2];
  final p95 = seconds[((seconds.length - 1) * 0.95).ceil()];
  final average =
      seconds.reduce((left, right) => left + right) / seconds.length;
  return {
    'average_seconds': _round(average),
    'median_mib_per_second': _round(byteCount / _mebibyte / median),
    'median_gbit_per_second': _round(byteCount * 8 / median / 1000000000),
    'p95_seconds': _round(p95),
  };
}

double _round(double value) => double.parse(value.toStringAsFixed(4));

int _positiveEnvironment(String name, int fallback) {
  final value = int.tryParse(Platform.environment[name] ?? '');
  return value != null && value > 0 ? value : fallback;
}

List<String> _cacheModes() {
  final configured = Platform.environment['WAMP_APP_BENCH_CACHES'];
  if (configured == null || configured.trim().isEmpty) {
    return const ['memory', 'disk'];
  }
  final modes = configured
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (modes.isEmpty ||
      modes.any((mode) => mode != 'memory' && mode != 'disk')) {
    throw const FormatException(
      'WAMP_APP_BENCH_CACHES must contain memory and/or disk.',
    );
  }
  return modes;
}

final class _TransferSample {
  const _TransferSample({
    required this.encryptSeconds,
    required this.decryptSeconds,
  });

  final double encryptSeconds;
  final double decryptSeconds;
}
