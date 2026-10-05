import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/message/e2ee_copy_metrics.dart';
import 'package:test/test.dart';

void main() {
  final key = List<int>.filled(32, 7);
  final plaintext = Uint8List.fromList(List.generate(65, (i) => i));
  tearDown(PortableE2eeCopyMetrics.endWindow);
  for (final typed in [false, true]) {
    for (final aes in [false, true]) {
      test('${typed ? 'typed' : 'CBOR'} ${aes ? 'AES' : 'XSalsa'} '
          'avoids duplicate provider wrapping and AES assembly', () {
        final provider = _provider(typed, aes, key);
        final options = PublishOptions(pptScheme: 'wamp');
        PortableE2eeCopyMetrics.beginWindow();
        final packed = provider.packPayload([plaintext], null, options);
        final encrypted = packed.single as Uint8List;
        final recovered = provider.unpackPayload(packed, options);
        expect(recovered.arguments, [plaintext]);
        final metrics = PortableE2eeCopyMetrics.endWindow();
        expect(metrics.plaintextWrappingCopyBytes, 0);
        expect(metrics.ciphertextWrappingCopyBytes, aes ? 0 : encrypted.length);
        expect(metrics.ciphertextAssemblyCopyBytes, 0);
        expect(metrics.ciphertextCoercionCopyBytes, 0);
      });
    }
  }

  test('coercion counts successful and partial failed copies', () {
    final provider = _provider(true, true, key);
    final options = PublishOptions(
      pptScheme: 'wamp',
      pptSerializer: 'flatbuffers',
    );
    final packed = provider.packPayload([plaintext], null, options);
    final encrypted = packed.single as Uint8List;
    PortableE2eeCopyMetrics.beginWindow();
    expect(provider.unpackPayload([encrypted.toList()], options).arguments, [
      plaintext,
    ]);
    expect(
      () => provider.unpackPayload([
        [1, 'bad', 2],
      ], options),
      throwsA(isA<WampE2eeInvalidPayloadException>()),
    );
    expect(
      () => provider.unpackPayload([
        [1, 2, 3],
      ], options),
      throwsA(isA<WampE2eeDecryptionException>()),
    );
    final metrics = PortableE2eeCopyMetrics.endWindow();
    expect(metrics.ciphertextCoercionCopyBytes, encrypted.length + 1 + 3);
    expect(metrics.knownOwnCopyBytes, metrics.ciphertextCoercionCopyBytes);
  });

  test('windows exclude other work, reset counters and reject overlap', () {
    final provider = _provider(true, false, key);
    List<dynamic> pack() => provider.packPayload(
      [plaintext],
      null,
      PublishOptions(pptScheme: 'wamp'),
    );
    pack();
    PortableE2eeCopyMetrics.beginWindow();
    expect(PortableE2eeCopyMetrics.beginWindow, throwsStateError);
    final encrypted = pack().single as Uint8List;
    final first = PortableE2eeCopyMetrics.endWindow();
    expect(first.ciphertextWrappingCopyBytes, encrypted.length);
    pack();
    expect(
      PortableE2eeCopyMetrics.endWindow().knownOwnCopyBytes,
      first.knownOwnCopyBytes,
    );
    PortableE2eeCopyMetrics.beginWindow();
    expect(PortableE2eeCopyMetrics.endWindow().knownOwnCopyBytes, 0);
  });
}

WampE2eeProvider _provider(bool typed, bool aes, List<int> key) {
  final keys = {'key': key};
  if (typed) {
    return aes
        ? WampFlatBuffersAes256GcmProvider(keys: keys, defaultKeyId: 'key')
        : WampFlatBuffersXsalsa20Poly1305Provider(
            keys: keys,
            defaultKeyId: 'key',
          );
  }
  return aes
      ? WampCborAes256GcmProvider(keys: keys, defaultKeyId: 'key')
      : WampCborXsalsa20Poly1305Provider(keys: keys, defaultKeyId: 'key');
}
