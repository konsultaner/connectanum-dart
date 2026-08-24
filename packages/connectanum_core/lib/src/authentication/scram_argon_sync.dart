import 'dart:typed_data';

import 'scram_argon_sync_stub.dart'
    if (dart.library.io) 'scram_argon_sync_native.dart'
    as platform;

Uint8List deriveScramArgonSynchronously({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int memory,
  required int keyLength,
}) => platform.deriveScramArgonSynchronously(
  password: password,
  salt: salt,
  iterations: iterations,
  memory: memory,
  keyLength: keyLength,
);
