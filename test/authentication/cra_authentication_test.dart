import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_dart/src/authentication/cra_authentication.dart';
import 'package:test/test.dart';

void main() {
  group('CRA', () {
    String salt = "gbnk5ji1b0dgoeavu31er567nb";
    String secret = "3614";
    String keyValue = "pjyujtcFkRES8z9jUqvPjokWp2G6xBh7QhtB0tMV6YA=";

    String challenge = "{\"authid\":\"11111111\",\"authrole\":\"client\",\"authmethod\":\"wampcra\",\"authprovider\":\"mssql\",\"nonce\":\"1280303478343404\",\"timestamp\":\"2015-10-27T14:28Z\",\"session\":586844620777222}";
    String hmac = "APO4Z6Z0sfpJ8DStwj+XgwJkHkeSw+eD9URKSHf+FKQ=";

    test("derive key", () {
      final key = CraAuthentication.deriveKey(secret, salt, iterations: 1000, keylen: 32);
      String encodedKey = base64.encode(key);
      expect(encodedKey, equals(keyValue));
    });

    test("hmac encode", () {
      final mac = CraAuthentication.encodeHmac(Uint8List.fromList(keyValue.codeUnits), 32, Uint8List.fromList(challenge.codeUnits));
      expect(mac, equals(hmac));
    });
  });
}