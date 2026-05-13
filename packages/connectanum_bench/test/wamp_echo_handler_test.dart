@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:connectanum_bench/src/wamp_echo_handler.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:test/test.dart';

void main() {
  group('respondEchoLazyInvocation', () {
    test('reuses plain lazy payload without forcing decode', () {
      final payload = wamp_core.LazyMessagePayload.encoded(
        encoding: wamp_core.LazyPayloadEncoding.cbor,
        argumentsBytes: Uint8List.fromList(const [0x81, 0x01]),
        argumentsDecoder: (_) => throw StateError('arguments decoded'),
        argumentsKeywordsBytes: Uint8List.fromList(const [
          0xA1,
          0x61,
          0x61,
          0x01,
        ]),
        argumentsKeywordsDecoder: (_) => throw StateError('kwargs decoded'),
      );

      wamp_core.LazyMessagePayload? capturedLazyPayload;
      List<dynamic>? capturedArguments;
      Map<String, dynamic>? capturedArgumentsKeywords;
      wamp_core.YieldOptions? capturedOptions;

      final invocation = wamp_core.LazyInvocationPayload(
        requestId: 1,
        registrationId: 2,
        receiveProgress: false,
        respondWith:
            ({
              wamp_core.LazyMessagePayload? lazyPayload,
              List<dynamic>? arguments,
              Map<String, dynamic>? argumentsKeywords,
              bool isError = false,
              String? errorUri,
              wamp_core.YieldOptions? options,
            }) {
              capturedLazyPayload = lazyPayload;
              capturedArguments = arguments;
              capturedArgumentsKeywords = argumentsKeywords;
              capturedOptions = options;
            },
        isResponseClosed: () => false,
        payload: payload,
      );

      respondEchoLazyInvocation(invocation);

      expect(capturedLazyPayload, same(payload));
      expect(capturedArguments, isNull);
      expect(capturedArgumentsKeywords, isNull);
      expect(capturedOptions, isNull);
    });

    test('preserves PPT response options while reusing lazy payload', () {
      final payload = wamp_core.LazyMessagePayload.packed(
        encoding: wamp_core.LazyPayloadEncoding.cbor,
        packedPayloadBytes: Uint8List.fromList(const [0x58, 0x01, 0x01]),
        packedPayloadDecoder: (_) => throw StateError('packed payload decoded'),
        pptDecoded: true,
      );

      wamp_core.LazyMessagePayload? capturedLazyPayload;
      wamp_core.YieldOptions? capturedOptions;

      final invocation = wamp_core.LazyInvocationPayload(
        requestId: 1,
        registrationId: 2,
        receiveProgress: false,
        pptScheme: 'x_custom_scheme',
        pptSerializer: 'cbor',
        pptCipher: 'cipher',
        pptKeyId: 'key',
        customDetails: const {'trace': 1},
        respondWith:
            ({
              wamp_core.LazyMessagePayload? lazyPayload,
              List<dynamic>? arguments,
              Map<String, dynamic>? argumentsKeywords,
              bool isError = false,
              String? errorUri,
              wamp_core.YieldOptions? options,
            }) {
              capturedLazyPayload = lazyPayload;
              capturedOptions = options;
            },
        isResponseClosed: () => false,
        payload: payload,
      );

      respondEchoLazyInvocation(invocation);

      expect(capturedLazyPayload, same(payload));
      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.pptScheme, 'x_custom_scheme');
      expect(capturedOptions!.pptSerializer, 'cbor');
      expect(capturedOptions!.pptCipher, 'cipher');
      expect(capturedOptions!.pptKeyId, 'key');
      expect(capturedOptions!.custom, const {'trace': 1});
    });
  });
}
