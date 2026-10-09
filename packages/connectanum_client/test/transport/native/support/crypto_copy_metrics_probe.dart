// A fresh VM isolates the process-wide native counters from parallel tests.
import 'dart:typed_data';

import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';

void _equal(Object? actual, Object? expected, String label) {
  if (actual != expected) throw StateError('$label: $actual != $expected');
}

void main(List<String> args) {
  final runtime = NativeClientRuntime.instance(
    libraryPath: args.isEmpty ? null : args.single,
  );
  if (args.isNotEmpty) {
    final metrics = runtime.e2eeCopyMetricsSnapshot();
    _equal(metrics.plaintextStagingCopyBytesTotal, null, 'old ABI plaintext');
    _equal(metrics.ciphertextStagingCopyBytesTotal, null, 'old ABI ciphertext');
    print('crypto-copy-metrics: unsupported ABI safely unavailable');
    return;
  }
  final keyring = runtime.createE2eeKeyring();
  int? session;
  try {
    runtime.addE2eeKey(
      keyring,
      'metrics',
      Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
      makeDefault: true,
    );
    session = runtime.createE2eeSession(keyring);
    for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
      for (final size in [0, 1, 65536]) {
        final input = Uint8List.fromList(
          List<int>.generate(size, (index) => (index * 29) & 255),
        );
        final before = runtime.e2eeCopyMetricsSnapshot();
        final encrypted = runtime.encryptE2ee(session, input, cipher: cipher);
        final decrypted = runtime.decryptE2ee(
          session,
          encrypted,
          cipher: cipher,
        );
        final delta = runtime.e2eeCopyMetricsSnapshot().deltaFrom(before);
        _equal(delta.plaintextStagingCopyBytesTotal, size, '$cipher plaintext');
        _equal(
          delta.ciphertextStagingCopyBytesTotal,
          size + (cipher == 'aes256gcm' ? 16 : 0),
          '$cipher ciphertext',
        );
        _equal(
          delta.dartToNativeCopiedBytesTotal,
          size + encrypted.length,
          '$cipher bridge input',
        );
        _equal(
          delta.nativeToDartCopiedBytesTotal,
          size + encrypted.length,
          '$cipher bridge output',
        );
        for (var index = 0; index < size; index++) {
          _equal(
            decrypted[index],
            (index * 29) & 255,
            '$cipher decrypted byte',
          );
          _equal(input[index], decrypted[index], '$cipher immutable input');
        }

        final builder = NativeBufferAllocator.instance().allocate(size);
        builder.writeBytes(0, input);
        final owned = builder.freeze();
        builder.dispose();
        try {
          final beforeOwned = runtime.e2eeCopyMetricsSnapshot();
          final output = runtime.encryptE2eeBuffer(
            session,
            owned,
            cipher: cipher,
          );
          try {
            final ownedDelta = runtime.e2eeCopyMetricsSnapshot().deltaFrom(
              beforeOwned,
            );
            _equal(
              ownedDelta.dartToNativeCopiedBytesTotal,
              0,
              'owned bridge input',
            );
            _equal(
              ownedDelta.nativeToDartCopiedBytesTotal,
              0,
              'owned bridge output',
            );
            _equal(
              ownedDelta.plaintextStagingCopyBytesTotal,
              size,
              'owned staging',
            );
            _equal(
              ownedDelta.ciphertextStagingCopyBytesTotal,
              0,
              'owned decrypt',
            );
            _equal(output.length, encrypted.length, 'owned wire length');
            for (var index = 0; index < size; index++) {
              _equal(owned.bytes[index], input[index], 'owned input retained');
            }
          } finally {
            output.dispose();
          }
        } finally {
          owned.dispose();
        }
      }
    }
    print('crypto-copy-metrics: exact native and Dart bridge deltas passed');
  } finally {
    if (session != null) runtime.releaseE2eeSession(session);
    runtime.releaseE2eeKeyring(keyring);
    NativeClientRuntime.shutdownShared();
  }
}
