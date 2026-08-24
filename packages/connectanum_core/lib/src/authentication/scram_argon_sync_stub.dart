import 'dart:typed_data';

Uint8List deriveScramArgonSynchronously({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int memory,
  required int keyLength,
}) => throw UnsupportedError(
  'Synchronous Argon2id13 is disabled on web; use a ScramKeyDeriver',
);
