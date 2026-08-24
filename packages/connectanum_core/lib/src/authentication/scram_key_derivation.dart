import 'dart:typed_data';

import 'scram_key_derivation_stub.dart'
    if (dart.library.io) 'scram_key_derivation_native.dart'
    if (dart.library.js_interop) 'scram_key_derivation_web.dart'
    as platform;

/// Inputs for a single SCRAM password-key derivation.
final class ScramKeyDerivationRequest {
  ScramKeyDerivationRequest({
    required Uint8List password,
    required Uint8List salt,
    required this.kdf,
    required this.iterations,
    required this.memory,
    required this.keyLength,
  }) : password = Uint8List.fromList(password),
       salt = Uint8List.fromList(salt) {
    if (iterations <= 0) {
      throw ArgumentError.value(iterations, 'iterations', 'must be positive');
    }
    if (memory <= 0) {
      throw ArgumentError.value(memory, 'memory', 'must be positive');
    }
    if (keyLength <= 0) {
      throw ArgumentError.value(keyLength, 'keyLength', 'must be positive');
    }
  }

  final Uint8List password;
  final Uint8List salt;
  final String kdf;
  final int iterations;
  final int memory;
  final int keyLength;
}

/// A running key derivation that can be terminated independently.
abstract interface class ScramKeyDerivationTask {
  Future<Uint8List> get result;

  Future<void> cancel();
}

/// Runs expensive SCRAM key derivation away from the caller's event loop.
abstract interface class ScramKeyDeriver {
  factory ScramKeyDeriver() = platform.PlatformScramKeyDeriver;

  ScramKeyDerivationTask start(
    ScramKeyDerivationRequest request, {
    Duration? timeout,
  });

  Future<void> dispose();
}

class ScramKeyDerivationException implements Exception {
  const ScramKeyDerivationException(this.message);

  final String message;

  @override
  String toString() => 'ScramKeyDerivationException: $message';
}

final class ScramKeyDerivationCancelledException
    extends ScramKeyDerivationException {
  const ScramKeyDerivationCancelledException()
    : super('key derivation was cancelled');
}

final class ScramKeyDerivationTimeoutException
    extends ScramKeyDerivationException {
  const ScramKeyDerivationTimeoutException()
    : super('key derivation timed out');
}
