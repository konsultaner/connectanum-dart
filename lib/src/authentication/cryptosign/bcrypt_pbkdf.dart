import 'dart:typed_data';
import 'dart:core';

import 'package:connectanum/src/authentication/cryptosign/bcrypt.dart';
import 'package:pointycastle/digests/sha512.dart';

class BcryptPbkdf {
  static void pbkdf(
      String password, Uint8List salt, int rounds, Uint8List output) {
    var sha512 = SHA512Digest();
    var nblocks = ((output.length + 31) / 32).truncate();
    var hpass = sha512.process(Uint8List.fromList(password.codeUnits));
    var hsalt = Uint8List(64);
    var block_b = Uint8List(4);
    Uint8List out;
    Uint8List tmp;

    for (var block = 1; block <= nblocks; block++) {
      // Block count is in big endian
      block_b[0] = ((block >> 24) & 0xFF);
      block_b[1] = ((block >> 16) & 0xFF);
      block_b[2] = ((block >> 8) & 0xFF);
      block_b[3] = (block & 0xFF);

      sha512.reset();
      sha512.update(salt, 0, salt.length);
      sha512.update(block_b, 0, block_b.length);
      sha512.doFinal(hsalt, 0);

      out = Uint8List.fromList(BCrypt().hash(hpass, hsalt));
      tmp = Uint8List(out.length)..setAll(0, out);

      for (var round = 1; round < rounds; round++) {
        sha512.reset();
        sha512.update(tmp, 0, tmp.length);
        sha512.doFinal(hsalt, 0);

        tmp = BCrypt().hash(hpass, hsalt);

        for (var i = 0; i < tmp.length; i++) {
          out[i] ^= tmp[i];
        }
      }

      for (var i = 0; i < out.length; i++) {
        var idx = i * nblocks + (block - 1);
        if (idx < output.length) {
          output[idx] = out[i];
        }
      }
    }
  }
}
