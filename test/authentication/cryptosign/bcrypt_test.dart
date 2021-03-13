import 'dart:typed_data';

import 'package:connectanum/src/authentication/cryptosign/bcrypt.dart';
import 'package:test/test.dart';

void main () {
  group('BCRYPT', () {
    var testVectors = <List<String>>[
      ['', '\$2a\$06\$DCq7YPn5Rq63x1Lad4cll.', '\$2a\$06\$DCq7YPn5Rq63x1Lad4cll.TV4S6ytwfsfvkgY8jIucDrjc8deX1s.'],
      ['', '\$2a\$08\$HqWuK6/Ng6sg9gQzbLrgb.', '\$2a\$08\$HqWuK6/Ng6sg9gQzbLrgb.Tl.ZHfXLhvt/SgVyWhQqgqcZ7ZuUtye'], 
      ['', '\$2a\$10\$k1wbIrmNyFAPwPVPSVa/ze', '\$2a\$10\$k1wbIrmNyFAPwPVPSVa/zecw2BCEnBwVS2GbrmgzxFUOqW9dk4TCW'],
      ['', '\$2a\$12\$k42ZFHFWqBp3vWli.nIn8u', '\$2a\$12\$k42ZFHFWqBp3vWli.nIn8uYyIkbvYRvodzbfbK18SSsY.CsIQPlxO'], 
      ['a', '\$2a\$06\$m0CrhHm10qJ3lXRY.5zDGO', '\$2a\$06\$m0CrhHm10qJ3lXRY.5zDGO3rS2KdeeWLuGmsfGlMfOxih58VYVfxe'], 
      ['a', '\$2a\$08\$cfcvVd2aQ8CMvoMpP2EBfe', '\$2a\$08\$cfcvVd2aQ8CMvoMpP2EBfeodLEkkFJ9umNEfPD18.hUF62qqlC/V.'], 
      ['a', '\$2a\$10\$k87L/MF28Q673VKh8/cPi.', '\$2a\$10\$k87L/MF28Q673VKh8/cPi.SUl7MU/rWuSiIDDFayrKk/1tBsSQu4u'], 
      ['a', '\$2a\$12\$8NJH3LsPrANStV6XtBakCe', '\$2a\$12\$8NJH3LsPrANStV6XtBakCez0cKHXVxmvxIlcz785vxAIZrihHZpeS'], 
      ['abc', '\$2a\$06\$If6bvum7DFjUnE9p2uDeDu', '\$2a\$06\$If6bvum7DFjUnE9p2uDeDu0YHzrHM6tf.iqN8.yx.jNN1ILEf7h0i'], 
      ['abc', '\$2a\$08\$Ro0CUfOqk6cXEKf3dyaM7O', '\$2a\$08\$Ro0CUfOqk6cXEKf3dyaM7OhSCvnwM9s4wIX9JeLapehKK5YdLxKcm'],
      ['abc', '\$2a\$10\$WvvTPHKwdBJ3uk0Z37EMR.', '\$2a\$10\$WvvTPHKwdBJ3uk0Z37EMR.hLA2W6N9AEBhEgrAOljy2Ae5MtaSIUi'], 
      ['abc', '\$2a\$12\$EXRkfkdmXn2gzds2SSitu.', '\$2a\$12\$EXRkfkdmXn2gzds2SSitu.MW9.gAVqa9eLS1//RYtYCmB1eLHg.9q'],
      ['abcdefghijklmnopqrstuvwxyz', '\$2a\$06\$.rCVZVOThsIa97pEDOxvGu', '\$2a\$06\$.rCVZVOThsIa97pEDOxvGuRRgzG64bvtJ0938xuqzv18d3ZpQhstC'], 
      ['abcdefghijklmnopqrstuvwxyz', '\$2a\$08\$aTsUwsyowQuzRrDqFflhge', '\$2a\$08\$aTsUwsyowQuzRrDqFflhgekJ8d9/7Z3GV3UcgvzQW3J5zMyrTvlz.'], 
      ['abcdefghijklmnopqrstuvwxyz', '\$2a\$10\$fVH8e28OQRj9tqiDXs1e1u', '\$2a\$10\$fVH8e28OQRj9tqiDXs1e1uxpsjN0c7II7YPKXua2NAKYvM6iQk7dq'], 
      ['abcdefghijklmnopqrstuvwxyz', '\$2a\$12\$D4G5f18o7aMMfwasBL7Gpu', '\$2a\$12\$D4G5f18o7aMMfwasBL7GpuQWuP3pkrZrOAnqP.bmezbMng.QwJ/pG'], 
      ['~!@#\$%^&*()      ~!@#\$%^&*()PNBFRD', '\$2a\$06\$fPIsBO8qRqkjj273rfaOI.', '\$2a\$06\$fPIsBO8qRqkjj273rfaOI.HtSV9jLDpTbZn782DC6/t7qT67P6FfO'], 
      ['~!@#\$%^&*()      ~!@#\$%^&*()PNBFRD', '\$2a\$08\$Eq2r4G/76Wv39MzSX262hu', '\$2a\$08\$Eq2r4G/76Wv39MzSX262huzPz612MZiYHVUJe/OcOql2jo4.9UxTW'], 
      ['~!@#\$%^&*()      ~!@#\$%^&*()PNBFRD', '\$2a\$10\$LgfYWkbzEvQ4JakH7rOvHe', '\$2a\$10\$LgfYWkbzEvQ4JakH7rOvHe0y8pHKF9OaFgwUZ2q7W2FFZmZzJYlfS'], 
      ['~!@#\$%^&*()      ~!@#\$%^&*()PNBFRD', '\$2a\$12\$WApznUOJfkEGSmYRfnkrPO', '\$2a\$12\$WApznUOJfkEGSmYRfnkrPOr466oFDCaj4b6HY3EXGvfxm43seyhgC']
    ];

    test('hash password', () async {
      for (var i = 0; i < testVectors.length; i++) {
        var plain = testVectors[i][0];
        var salt = testVectors[i][1];
        var expected = testVectors[i][2];
        var hashed = BCrypt.hashPassword(plain, salt);
        expect(hashed, equals(expected));
      }
    });

    test('generate salt initialized', () async {
      for (var i = 4; i <= 12; i++) {
        for (var j = 0; j < testVectors.length; j += 4) {
          var plain = testVectors[j][0];
          var salt = BCrypt.generateSalt(logRounds: i);
          var hashed1 = BCrypt.hashPassword(plain, salt);
          var hashed2 = BCrypt.hashPassword(plain, hashed1);
          expect(hashed1, equals(hashed2));
        }
      }
    });

    test('generate salt', () async {
      for (var i = 0; i < testVectors.length; i += 4) {
        var plain = testVectors[i][0];
        var salt = BCrypt.generateSalt();
        var hashed1 = BCrypt.hashPassword(plain, salt);
        var hashed2 = BCrypt.hashPassword(plain, hashed1);
        expect(hashed1, hashed2);
      }
    });

    test('check password', () async {
      for (var i = 0; i < testVectors.length; i++) {
        var plain = testVectors[i][0];
        var expected = testVectors[i][2];
        expect(BCrypt.checkPassword(plain, expected), equals(true));
      }
    });

    test('check password failed', () async {
      for (var i = 0; i < testVectors.length; i++) {
        var broken_index = (i + 4) % testVectors.length;
        var plain = testVectors[i][0];
        var expected = testVectors[broken_index][2];
        expect(BCrypt.checkPassword(plain, expected), equals(false));
      }
    });

    test('international characters', () async {
      var pw1 = '\u2605\u2605\u2605\u2605\u2605\u2605\u2605\u2605';
      var pw2 = '????????';

      var h1 = BCrypt.hashPassword(pw1, BCrypt.generateSalt());
      expect(BCrypt.checkPassword(pw2, h1), equals(false));

      var h2 = BCrypt.hashPassword(pw2, BCrypt.generateSalt());
      expect(BCrypt.checkPassword(pw1, h2), equals(false));
    });

    test('bcrypt hash', () {
      var password1 = Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
      var salt1 = Uint8List(password1.length)..setAll(0, password1);
      var hash1 = Uint8List.fromList([0x46, 0x02, 0x86, 0xe9, 0x72, 0xfa, 0x83, 0x3f, 0x8b, 0x12, 0x83, 0xad, 0x8f, 0xa9, 0x19, 0xfa, 0x29, 0xbd, 0xe2, 0x0e, 0x23, 0x32, 0x9e, 0x77, 0x4d, 0x84, 0x22, 0xba, 0xc0, 0xa7, 0x92, 0x6c]);
      expect(BCrypt().hash(password1, salt1), equals(hash1));
      var password2 = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f]);
      var salt2 = Uint8List(password2.length)..setAll(0, password2);
      var hash2 = Uint8List.fromList([0xc6, 0xa9, 0x5f, 0xe6, 0x41, 0x31, 0x15, 0xfb, 0x57, 0xe9, 0x9f, 0x75, 0x74, 0x98, 0xe8, 0x5d, 0xa3, 0xc6, 0xe1, 0xdf, 0x0c, 0x3c, 0x93, 0xaa, 0x97, 0x5c, 0x54, 0x8a, 0x34, 0x43, 0x26, 0xf8]);
      expect(BCrypt().hash(password2, salt2), equals(hash2));
    });
  });
}