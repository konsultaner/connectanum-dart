import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor_serializer;
import 'package:test/test.dart';

void main() {
  group('Invocation', () {
    test('respondWith throws when no response handler is attached', () {
      final invocation = Invocation(1, 2, InvocationDetails(null, null, false));

      expect(
        () => invocation.respondWith(arguments: const ['payload']),
        throwsStateError,
      );
    });

    test('respondWith forwards yield and error responses directly', () {
      final invocation = Invocation(1, 2, InvocationDetails(null, null, true));
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);

      invocation.respondWith(
        arguments: const ['progress'],
        options: YieldOptions(progress: true),
      );
      invocation.respondWith(
        isError: true,
        errorUri: Error.notAuthorized,
        arguments: const ['denied'],
      );

      expect(responses, hasLength(2));
      expect(responses.first, isA<Yield>());
      expect((responses.first as Yield).options?.progress, isTrue);
      expect(responses.last, isA<Error>());
      expect((responses.last as Error).error, Error.notAuthorized);
    });

    test('respondWith closes after a final response', () {
      final invocation = Invocation(1, 2, InvocationDetails(null, null, false));
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);

      invocation.respondWith(arguments: const ['done']);

      expect(invocation.responseClosed, isTrue);
      expect(
        () => invocation.respondWith(arguments: const ['again']),
        throwsStateError,
      );
      expect(responses, hasLength(1));
      expect((responses.single as Yield).arguments, equals(const ['done']));
    });

    test('toPayload exposes a direct responder view', () {
      final invocation = Invocation(
        1,
        2,
        InvocationDetails(9, 'bench.proc', false),
        argumentsKeywords: const {'worker': 1},
      );
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);

      final payload = invocation.toPayload();
      payload.respondWith(arguments: const ['done']);

      expect(payload.requestId, 1);
      expect(payload.registrationId, 2);
      expect(payload.caller, 9);
      expect(payload.procedure, 'bench.proc');
      expect(payload.argumentsKeywords, equals(const {'worker': 1}));
      expect(payload.isResponseClosed(), isTrue);
      expect(responses, hasLength(1));
      expect((responses.single as Yield).arguments, equals(const ['done']));
    });

    test('toLazyPayload keeps encoded bytes and responder semantics', () {
      final invocation = Invocation(
        1,
        2,
        InvocationDetails(9, 'bench.proc', false),
      );
      invocation.setLazyPayload(
        argumentsBytes: Uint8List.fromList(utf8.encode('["done"]')),
        argumentsDecoder: (bytes) =>
            (jsonDecode(utf8.decode(bytes)) as List<dynamic>),
      );
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);

      final payload = invocation.toLazyInvocationPayload();
      payload.respondWith(arguments: const ['ok']);

      expect(payload.requestId, 1);
      expect(payload.registrationId, 2);
      expect(payload.argumentsBytes, isNotNull);
      expect(payload.arguments, equals(const ['done']));
      expect(payload.isResponseClosed(), isTrue);
      expect(responses, hasLength(1));
      expect((responses.single as Yield).arguments, equals(const ['ok']));
    });

    test(
      'toLazyPayload preserves materialized kwargs when only args are encoded',
      () {
        final invocation = Invocation(
          1,
          2,
          InvocationDetails(9, 'bench.proc', false),
        );
        invocation.setLazyPayload(
          argumentsBytes: Uint8List.fromList(utf8.encode('["done"]')),
          argumentsDecoder: (bytes) =>
              (jsonDecode(utf8.decode(bytes)) as List<dynamic>),
          encoding: LazyPayloadEncoding.json,
        );
        invocation.argumentsKeywords = const {'worker': 1};

        final payload = invocation.toLazyInvocationPayload();

        expect(payload.argumentsBytes, isNotNull);
        expect(payload.arguments, equals(const ['done']));
        expect(payload.argumentsKeywordsBytes, isNull);
        expect(payload.argumentsKeywords, equals(const {'worker': 1}));
      },
    );

    test('toPayload unpacks PPT payloads', () {
      final invocation = Invocation(
        1,
        2,
        InvocationDetails(9, 'bench.proc', false, 'x_custom_scheme', 'cbor'),
        arguments: PPTPayload.packPPTPayload(
          const ['ppt-invocation'],
          const {'worker': 5},
          InvocationDetails(9, 'bench.proc', false, 'x_custom_scheme', 'cbor'),
        ),
      );

      final payload = invocation.toPayload();
      expect(payload.arguments, equals(const ['ppt-invocation']));
      expect(payload.argumentsKeywords, equals(const {'worker': 5}));
    });

    test('toLazyPayload preserves packed PPT bytes until accessed', () {
      final invocation = Invocation(
        1,
        2,
        InvocationDetails(9, 'bench.proc', false, 'x_custom_scheme', 'cbor'),
        arguments: PPTPayload.packPPTPayload(
          const ['ppt-invocation'],
          const {'worker': 5},
          InvocationDetails(9, 'bench.proc', false, 'x_custom_scheme', 'cbor'),
        ),
      );

      final lazy = invocation.toLazyInvocationPayload();

      expect(lazy.packedPayloadBytes, isNotNull);
      expect(lazy.arguments, equals(const ['ppt-invocation']));
      expect(lazy.argumentsKeywords, equals(const {'worker': 5}));
    });

    test('toLazyPayload preserves packed wamp bytes until accessed', () {
      final serializer = cbor_serializer.Serializer();
      final packedBytes = Uint8List.fromList(
        serializer.serializePPT(
          PPTPayload(
            arguments: const ['wrapped-invocation'],
            argumentsKeywords: const {'worker': 12},
          ),
        ),
      );
      final invocation = Invocation(
        1,
        2,
        InvocationDetails(9, 'bench.proc', false, 'wamp', 'cbor'),
        arguments: <dynamic>[packedBytes],
      );

      final lazy = invocation.toLazyInvocationPayload();

      expect(lazy.packedPayloadBytes, orderedEquals(packedBytes));
    });

    test('respondWith reuses lazy PPT envelope bytes without decoding', () {
      final invocation = Invocation(1, 2, InvocationDetails(null, null, false));
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      var decodeCount = 0;
      final serializer = cbor_serializer.Serializer();
      final packedPayload = LazyMessagePayload.packed(
        encoding: LazyPayloadEncoding.cbor,
        packedPayloadBytes: Uint8List.fromList(
          serializer.serializePPT(
            PPTPayload(
              arguments: const ['ppt-response'],
              argumentsKeywords: const {'worker': 8},
            ),
          ),
        ),
        packedPayloadDecoder: (bytes) {
          decodeCount += 1;
          final decoded = serializer.deserializePPT(bytes)!;
          return (
            arguments: decoded.arguments,
            argumentsKeywords: decoded.argumentsKeywords,
          );
        },
      );

      invocation.respondWith(
        lazyPayload: packedPayload,
        options: YieldOptions(
          pptScheme: 'x_custom_scheme',
          pptSerializer: 'cbor',
        ),
      );

      expect(decodeCount, 0);
      expect(responses, hasLength(1));
      final response = responses.single as Yield;
      expect(response.arguments, hasLength(1));
      expect(
        response.arguments!.single,
        equals(packedPayload.packedPayloadBytes),
      );
      expect(response.argumentsKeywords, isNull);
    });

    test('respondWith reuses lazy wamp envelope bytes without decoding', () {
      final invocation = Invocation(1, 2, InvocationDetails(null, null, false));
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      var decodeCount = 0;
      final serializer = cbor_serializer.Serializer();
      final packedPayload = LazyMessagePayload.packed(
        encoding: LazyPayloadEncoding.cbor,
        packedPayloadBytes: Uint8List.fromList(
          serializer.serializePPT(
            PPTPayload(
              arguments: const ['wrapped-response'],
              argumentsKeywords: const {'worker': 11},
            ),
          ),
        ),
        packedPayloadDecoder: (bytes) {
          decodeCount += 1;
          final decoded = serializer.deserializePPT(bytes)!;
          return (
            arguments: decoded.arguments,
            argumentsKeywords: decoded.argumentsKeywords,
          );
        },
      );

      invocation.respondWith(
        lazyPayload: packedPayload,
        options: YieldOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
      );

      expect(decodeCount, 0);
      expect(responses, hasLength(1));
      final response = responses.single as Yield;
      expect(response.arguments, hasLength(1));
      expect(
        response.arguments!.single,
        equals(packedPayload.packedPayloadBytes),
      );
      expect(response.argumentsKeywords, isNull);
    });

    test('respondWith packs wamp payloads with the attached E2EE provider', () {
      final provider = _testWampE2eeProvider();
      final invocation = Invocation(1, 2, InvocationDetails(null, null, false));
      final responses = <AbstractMessageWithPayload>[];
      invocation.attachE2eeProvider(provider);
      invocation.onResponse(responses.add);

      invocation.respondWith(
        arguments: const ['wrapped-response'],
        argumentsKeywords: const {'worker': 11},
        options: YieldOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
      );

      expect(responses, hasLength(1));
      final response = responses.single as Yield;
      expect(response.options?.pptCipher, equals('xsalsa20poly1305'));
      expect(response.options?.pptKeyId, equals('test-key'));
      final decoded = provider.unpackPayload(
        response.arguments,
        response.options!,
      );
      expect(decoded.arguments, equals(const ['wrapped-response']));
      expect(decoded.argumentsKeywords, equals(const {'worker': 11}));
      expect(response.argumentsKeywords, isNull);
    });

    test('respondWith encrypts materialized lazy wamp payloads', () {
      final provider = _testWampE2eeProvider();
      final invocation = Invocation(1, 2, InvocationDetails(null, null, false));
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      final payload = LazyMessagePayload.materialized(
        encoding: LazyPayloadEncoding.cbor,
        arguments: const ['wrapped-response'],
        argumentsKeywords: const {'worker': 12},
        e2eeProvider: provider,
      );

      invocation.respondWith(
        lazyPayload: payload,
        options: YieldOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
      );

      expect(responses, hasLength(1));
      final response = responses.single as Yield;
      final decoded = provider.unpackPayload(
        response.arguments,
        response.options!,
      );
      expect(decoded.arguments, equals(const ['wrapped-response']));
      expect(decoded.argumentsKeywords, equals(const {'worker': 12}));
    });

    test(
      'copyPayloadTo preserves materialized kwargs alongside encoded args',
      () {
        final invocation = Invocation(
          1,
          2,
          InvocationDetails(null, null, false),
        );
        invocation.setLazyPayload(
          argumentsBytes: Uint8List.fromList(utf8.encode('["done"]')),
          argumentsDecoder: (bytes) =>
              (jsonDecode(utf8.decode(bytes)) as List<dynamic>),
          encoding: LazyPayloadEncoding.json,
        );
        invocation.argumentsKeywords = const {'worker': 9};
        final yield = Yield(1);

        invocation.copyPayloadTo(yield);

        expect(yield.debugEncodedArgumentsBytes, isNotNull);
        expect(yield.arguments, equals(const ['done']));
        expect(yield.argumentsKeywords, equals(const {'worker': 9}));
      },
    );

    test('Registered onInvokePayload unpacks PPT payloads', () async {
      final registered = Registered(1, 2);
      InvocationPayload? received;
      final responses = <AbstractMessageWithPayload>[];

      registered.onInvokePayload((invocation) {
        received = invocation;
        invocation.respondWith(arguments: const ['ok']);
      });

      final invocation = Invocation(
        1,
        2,
        InvocationDetails(9, 'bench.proc', false, 'x_custom_scheme', 'cbor'),
        arguments: PPTPayload.packPPTPayload(
          const ['ppt-invocation'],
          const {'worker': 6},
          InvocationDetails(9, 'bench.proc', false, 'x_custom_scheme', 'cbor'),
        ),
      );
      invocation.onResponse(responses.add);

      registered.addInvocation(invocation);
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotNull);
      expect(received!.arguments, equals(const ['ppt-invocation']));
      expect(received!.argumentsKeywords, equals(const {'worker': 6}));
      expect(responses, hasLength(1));
      expect((responses.single as Yield).arguments, equals(const ['ok']));
    });

    test('Registered onInvoke lazily unpacks PPT payloads on access', () async {
      final registered = Registered(1, 2);
      Invocation? received;
      final responses = <AbstractMessageWithPayload>[];

      registered.onInvoke((invocation) {
        received = invocation;
        expect(invocation.hasDecodedPptPayload, isFalse);
        expect(invocation.arguments, equals(const ['ppt-invocation']));
        expect(invocation.argumentsKeywords, equals(const {'worker': 6}));
        invocation.respondWith(arguments: const ['ok']);
      });

      final invocation = Invocation(
        1,
        2,
        InvocationDetails(9, 'bench.proc', false, 'x_custom_scheme', 'cbor'),
        arguments: PPTPayload.packPPTPayload(
          const ['ppt-invocation'],
          const {'worker': 6},
          InvocationDetails(9, 'bench.proc', false, 'x_custom_scheme', 'cbor'),
        ),
      );
      invocation.onResponse(responses.add);

      registered.addInvocation(invocation);
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotNull);
      expect(received!.hasDecodedPptPayload, isTrue);
      expect(responses, hasLength(1));
      expect((responses.single as Yield).arguments, equals(const ['ok']));
    });
  });
}

WampCborXsalsa20Poly1305Provider _testWampE2eeProvider() {
  return WampCborXsalsa20Poly1305Provider.single(
    keyId: 'test-key',
    key: Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
  );
}
