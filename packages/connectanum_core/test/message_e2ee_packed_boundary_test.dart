import 'dart:typed_data';

import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  for (final isError in [false, true]) {
    test('packed CBOR cannot bypass missing provider error=$isError', () {
      final invocation = Invocation(
        7,
        11,
        InvocationDetails(null, null, false),
      );
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      final payload = LazyMessagePayload.packed(
        encoding: LazyPayloadEncoding.cbor,
        packedPayloadBytes: Uint8List(1),
        packedPayloadDecoder: (_) =>
            (arguments: ['plain'], argumentsKeywords: null),
      );
      expect(
        () => invocation.respondWith(
          isError: isError,
          errorUri: isError ? 'com.error.missing' : null,
          lazyPayload: payload,
          options: YieldOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
        ),
        throwsA(isA<WampE2eeProviderUnavailableException>()),
      );
      expect(responses, isEmpty);
      expect(invocation.responseClosed, isFalse);
      invocation.respondWith(arguments: ['retry']);
      expect(responses.single.arguments, ['retry']);
    });
  }

  for (final aes in [false, true]) {
    for (final encryptedSource in [false, true]) {
      for (final isError in [false, true]) {
        test('outbound encryption owns packed CBOR boundary '
            'AES=$aes encryptedSource=$encryptedSource error=$isError', () {
          final arguments = ['private-value'];
          final keywords = {'n': 42};
          final outboundKey = List<int>.generate(32, (i) => i + 1);
          final sourceKey = List<int>.generate(32, (i) => 255 - i);
          WampE2eeProvider provider(String keyId, List<int> key) => aes
              ? WampCborAes256GcmProvider.single(keyId: keyId, key: key)
              : WampCborXsalsa20Poly1305Provider.single(keyId: keyId, key: key);
          final outboundProvider = provider('outbound-key', outboundKey);
          final sourceProvider = provider('source-key', sourceKey);
          final sourceOptions = YieldOptions(
            pptScheme: 'wamp',
            pptSerializer: 'cbor',
          );
          final plaintext = Uint8List.fromList(
            cbor.Serializer().serializePPT(
              PPTPayload(arguments: arguments, argumentsKeywords: keywords),
            ),
          );
          final sourceBytes = encryptedSource
              ? sourceProvider
                        .packPayload(arguments, keywords, sourceOptions)
                        .single
                    as Uint8List
              : plaintext;
          var decodes = 0;
          final payload = LazyMessagePayload.packed(
            encoding: LazyPayloadEncoding.cbor,
            packedPayloadBytes: sourceBytes,
            packedPayloadDecoder: (bytes) {
              decodes++;
              if (encryptedSource) {
                final decoded = sourceProvider.unpackPayload([
                  bytes,
                ], sourceOptions);
                return (
                  arguments: decoded.arguments,
                  argumentsKeywords: decoded.argumentsKeywords,
                );
              }
              final decoded = cbor.Serializer().deserializePPT(bytes)!;
              return (
                arguments: decoded.arguments,
                argumentsKeywords: decoded.argumentsKeywords,
              );
            },
          );
          final invocation = Invocation(
            7,
            11,
            InvocationDetails(null, 'com.encrypt', false),
          )..attachE2eeProvider(outboundProvider);
          final responses = <AbstractMessageWithPayload>[];
          invocation.onResponse(responses.add);
          final options = YieldOptions(
            pptScheme: 'wamp',
            pptSerializer: 'cbor',
          );
          invocation.respondWith(
            isError: isError,
            errorUri: isError ? 'com.error.encrypted' : null,
            lazyPayload: payload,
            options: options,
          );
          final response = responses.single;
          expect(response.arguments, hasLength(1));
          expect(response.arguments!.single, isNot(same(sourceBytes)));
          expect(response.arguments!.single, isNot(equals(plaintext)));
          expect(options.pptKeyId, 'outbound-key');
          expect(decodes, 1);
          final decoded = outboundProvider.unpackPayload(
            response.arguments,
            options,
          );
          expect(decoded.arguments, arguments);
          expect(decoded.argumentsKeywords, keywords);
        });
      }
    }
  }
}
