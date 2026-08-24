import 'dart:typed_data';

import 'package:pointycastle/export.dart';

Uint8List deriveScramArgonSynchronously({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int memory,
  required int keyLength,
}) {
  final output = Uint8List(keyLength);
  Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: keyLength,
        iterations: iterations,
        memory: memory,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    )
    ..deriveKey(password, 0, output, 0);
  return output;
}
