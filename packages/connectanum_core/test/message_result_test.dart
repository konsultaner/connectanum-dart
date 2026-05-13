import 'dart:typed_data';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('arguments lazily unpack PPT payloads on access', () {
      final details = ResultDetails(
        pptScheme: 'x_custom_scheme',
        pptSerializer: 'cbor',
      );
      final result = Result(
        1,
        details,
        arguments: PPTPayload.packPPTPayload(
          const ['ppt-result'],
          const {'worker': 10},
          details,
        ),
      );

      expect(result.hasDecodedPptPayload, isFalse);
      expect(result.arguments, equals(const ['ppt-result']));
      expect(result.argumentsKeywords, equals(const {'worker': 10}));
      expect(result.hasDecodedPptPayload, isTrue);
    });

    test('toPayload unpacks PPT payloads', () {
      final details = ResultDetails(
        pptScheme: 'x_custom_scheme',
        pptSerializer: 'cbor',
      );
      final result = Result(
        1,
        details,
        arguments: PPTPayload.packPPTPayload(
          const ['ppt-result'],
          const {'worker': 10},
          details,
        ),
      );

      final payload = result.toPayload();
      expect(payload.arguments, equals(const ['ppt-result']));
      expect(payload.argumentsKeywords, equals(const {'worker': 10}));
    });

    test('already materialized PPT payloads do not unpack twice', () {
      final result = Result(
        1,
        ResultDetails(pptScheme: 'x_custom_scheme', pptSerializer: 'cbor'),
        arguments: const ['ok'],
        argumentsKeywords: const {'worker': 12},
      );

      expect(result.arguments, equals(const ['ok']));
      expect(result.argumentsKeywords, equals(const {'worker': 12}));
      expect(result.hasDecodedPptPayload, isTrue);
    });

    test('fallback map PPT payloads still unpack on access', () {
      final result = Result(
        1,
        ResultDetails(pptScheme: 'x_custom_scheme'),
        arguments: const [
          {
            'args': ['ppt-result'],
            'kwargs': {'worker': 13},
          },
        ],
      );

      expect(result.arguments, equals(const ['ppt-result']));
      expect(result.argumentsKeywords, equals(const {'worker': 13}));
      expect(result.hasDecodedPptPayload, isTrue);
    });

    test('resultFromLazyPayload preserves packed PPT bytes until access', () {
      final details = ResultDetails(
        pptScheme: 'x_custom_scheme',
        pptSerializer: 'cbor',
      );
      final source = Result(
        1,
        details,
        arguments: PPTPayload.packPPTPayload(
          const ['ppt-result'],
          const {'worker': 10},
          details,
        ),
      );

      final rebuilt = resultFromLazyPayload(source.toLazyResultPayload());

      expect(rebuilt.hasDecodedPptPayload, isFalse);
      expect(
        rebuilt.toLazyResultPayload().packedPayloadBytes,
        orderedEquals(source.toLazyResultPayload().packedPayloadBytes!),
      );
      expect(rebuilt.arguments, equals(const ['ppt-result']));
      expect(rebuilt.argumentsKeywords, equals(const {'worker': 10}));
      expect(rebuilt.hasDecodedPptPayload, isTrue);
    });

    test('resultFromLazyPayload preserves non-PPT encoded payload bytes', () {
      final source = Result(1, ResultDetails());
      source.setLazyPayload(
        argumentsBytes: Uint8List.fromList(const [1, 2, 3]),
        argumentsDecoder: (_) => const ['lazy-result'],
        argumentsKeywordsBytes: Uint8List.fromList(const [4, 5]),
        argumentsKeywordsDecoder: (_) => const {'worker': 11},
        encoding: LazyPayloadEncoding.cbor,
      );

      final rebuilt = resultFromLazyPayload(source.toLazyResultPayload());

      expect(
        rebuilt.debugEncodedArgumentsBytes,
        orderedEquals(const [1, 2, 3]),
      );
      expect(
        rebuilt.debugEncodedArgumentsKeywordsBytes,
        orderedEquals(const [4, 5]),
      );
      expect(rebuilt.arguments, equals(const ['lazy-result']));
      expect(rebuilt.argumentsKeywords, equals(const {'worker': 11}));
    });

    test('wamp payload access throws when no E2EE provider is attached', () {
      final provider = _testWampE2eeProvider();
      final details = ResultDetails(pptScheme: 'wamp', pptSerializer: 'cbor');
      final result = Result(
        1,
        details,
        arguments: provider.packPayload(
          const ['wrapped-result'],
          const {'worker': 10},
          details,
        ),
      );

      expect(
        () => result.arguments,
        throwsA(isA<WampE2eeProviderUnavailableException>()),
      );
    });

    test('wamp payload access decodes with an attached E2EE provider', () {
      final provider = _testWampE2eeProvider();
      final details = ResultDetails(pptScheme: 'wamp', pptSerializer: 'cbor');
      final result = Result(
        1,
        details,
        arguments: provider.packPayload(
          const ['wrapped-result'],
          const {'worker': 10},
          details,
        ),
      );
      result.attachE2eeProvider(provider);

      expect(details.pptCipher, equals('xsalsa20poly1305'));
      expect(details.pptKeyId, equals('test-key'));
      expect(result.arguments, equals(const ['wrapped-result']));
      expect(result.argumentsKeywords, equals(const {'worker': 10}));
      expect(result.hasDecodedPptPayload, isTrue);
    });
  });
}

WampCborXsalsa20Poly1305Provider _testWampE2eeProvider() {
  return WampCborXsalsa20Poly1305Provider.single(
    keyId: 'test-key',
    key: Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
  );
}
