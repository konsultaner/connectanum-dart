// A fresh VM isolates the process-wide native counters from parallel tests.
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';

void _equal(Object? actual, Object? expected, String label) {
  if (actual != expected) throw StateError('$label: $actual != $expected');
}

void main(List<String> args) {
  final runtime = NativeClientRuntime.instance(
    libraryPath: args.isEmpty ? null : args.last,
  );
  if (args.length == 2 && args.first == '--missing-nonce-tag') {
    _equal(
      runtime.e2eeCopyMetricsSnapshot().nonceTagCopyBytesTotal,
      null,
      'old scalar unavailable',
    );
    print('crypto-copy-metrics: optional nonce/tag scalar safely unavailable');
    return;
  }
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
        _equal(delta.nonceTagCopyBytesTotal, 40, '$cipher nonce/tag framing');
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
              ownedDelta.nonceTagCopyBytesTotal,
              cipher == 'aes256gcm' ? 28 : 40,
              'owned nonce/tag framing',
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
    final provider = NativeWampCborXsalsa20Poly1305Provider.single(
      keyId: 'metrics',
      key: Uint8List(32),
    );
    try {
      final options = PublishOptions(pptScheme: 'wamp');
      final data = Uint8List.fromList([0, 128, 255]);
      final encrypted =
          provider.packPayload([data], null, options).single as Uint8List;
      for (final wrap in [false, true]) {
        final input = wrap
            ? encrypted.map((byte) => byte + 256).toList()
            : encrypted;
        final before = runtime.e2eeCopyMetricsSnapshot();
        final result = provider.unpackPayload([input], options);
        _equal(
          (result.arguments!.single as List).join(','),
          data.join(','),
          'legacy integer wrapping',
        );
        _equal(
          runtime
              .e2eeCopyMetricsSnapshot()
              .deltaFrom(before)
              .ciphertextCoercionCopyBytesTotal,
          wrap ? encrypted.length : 0,
          'legacy successful coercion',
        );
      }
      for (final copied in [0, 1, 3]) {
        final malformed = <dynamic>[...List<int>.filled(copied, 257), 'bad'];
        final before = runtime.e2eeCopyMetricsSnapshot();
        try {
          provider.unpackPayload([
            malformed,
          ], PublishOptions(pptScheme: 'wamp'));
          throw StateError('Malformed legacy ciphertext was accepted');
        } on TypeError {
          // Preserve the legacy cast failure, while observing successful writes.
        }
        final delta = runtime.e2eeCopyMetricsSnapshot().deltaFrom(before);
        _equal(
          delta.ciphertextCoercionCopyBytesTotal,
          copied,
          'legacy partial coercion',
        );
        _equal(
          delta.dartToNativeCopiedBytesTotal,
          0,
          'rejected coercion never reaches FFI',
        );
      }
    } finally {
      provider.release();
    }
    print('crypto-copy-metrics: exact native and Dart bridge deltas passed');
  } finally {
    if (session != null) runtime.releaseE2eeSession(session);
    runtime.releaseE2eeKeyring(keyring);
    NativeClientRuntime.shutdownShared();
  }
}
