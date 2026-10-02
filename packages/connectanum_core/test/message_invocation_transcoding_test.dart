import 'dart:typed_data';

import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:test/test.dart';

void main() {
  final codecs =
      <({String name, LazyPayloadEncoding encoding, AbstractSerializer codec})>[
        (
          name: 'json',
          encoding: LazyPayloadEncoding.json,
          codec: json.Serializer(),
        ),
        (
          name: 'msgpack',
          encoding: LazyPayloadEncoding.messagePack,
          codec: msgpack.Serializer(),
        ),
        (
          name: 'cbor',
          encoding: LazyPayloadEncoding.cbor,
          codec: cbor.Serializer(),
        ),
      ];
  final arguments = <dynamic>['response', 0, false, null];
  final kwargs = <String, dynamic>{
    'value': 42,
    'nested': {'empty': null},
  };

  for (final source in codecs) {
    for (final target in [...codecs.map((codec) => codec.name), null]) {
      test('lazy PPT response ${source.name} to $target preserves payload', () {
        final packed = Uint8List.fromList(
          source.codec.serializePPT(
            PPTPayload(arguments: arguments, argumentsKeywords: kwargs),
          ),
        );
        var decodes = 0;
        final lazy = LazyMessagePayload.packed(
          encoding: source.encoding,
          packedPayloadBytes: packed,
          packedPayloadDecoder: (bytes) {
            decodes++;
            final decoded = source.codec.deserializePPT(bytes)!;
            return (
              arguments: decoded.arguments,
              argumentsKeywords: decoded.argumentsKeywords,
            );
          },
        );
        final invocation = Invocation(
          7,
          11,
          InvocationDetails(null, null, false),
        );
        final responses = <AbstractMessageWithPayload>[];
        invocation.onResponse(responses.add);
        invocation.respondWith(
          lazyPayload: lazy,
          options: YieldOptions(pptScheme: 'x_example', pptSerializer: target),
        );
        expect(responses, hasLength(1));
        expect(invocation.responseClosed, isTrue);
        expect(decodes, source.name == target ? 0 : 1);
        final response = responses.single as Yield;
        expect(response.invocationRequestId, 7);
        expect(response.options!.pptScheme, 'x_example');
        expect(response.options!.pptSerializer, target);
        expect(response.argumentsKeywords, isNull);
        if (source.name == target) {
          expect(response.arguments!.single, same(packed));
        }
        if (target == null) {
          expect(response.arguments, [
            {'args': arguments, 'kwargs': kwargs},
          ]);
        } else {
          final decoder = codecs
              .singleWhere((codec) => codec.name == target)
              .codec;
          final decoded = decoder.deserializePPT(
            Uint8List.fromList(response.arguments!.single as List<int>),
          )!;
          expect(decoded.arguments, arguments);
          expect(decoded.argumentsKeywords, kwargs);
        }
      });
    }
  }

  for (final target in [...codecs.map((codec) => codec.name), null]) {
    test('materialized lazy PPT response to $target preserves payload', () {
      final invocation = Invocation(
        7,
        11,
        InvocationDetails(null, null, false),
      );
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      invocation.respondWith(
        lazyPayload: LazyMessagePayload.materialized(
          arguments: arguments,
          argumentsKeywords: kwargs,
        ),
        options: YieldOptions(pptScheme: 'x_example', pptSerializer: target),
      );
      final response = responses.single as Yield;
      if (target == null) {
        expect(response.arguments, [
          {'args': arguments, 'kwargs': kwargs},
        ]);
      } else {
        final decoder = codecs
            .singleWhere((codec) => codec.name == target)
            .codec;
        final decoded = decoder.deserializePPT(
          Uint8List.fromList(response.arguments!.single as List<int>),
        )!;
        expect(decoded.arguments, arguments);
        expect(decoded.argumentsKeywords, kwargs);
      }
    });
  }

  test(
    'transcoding failure emits no response and permits explicit recovery',
    () {
      final failure = StateError('synthetic decode failure');
      final invocation = Invocation(
        7,
        11,
        InvocationDetails(null, null, false),
      );
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      final lazy = LazyMessagePayload.packed(
        encoding: LazyPayloadEncoding.json,
        packedPayloadBytes: Uint8List.fromList([0]),
        packedPayloadDecoder: (_) => throw failure,
      );
      expect(
        () => invocation.respondWith(
          lazyPayload: lazy,
          options: YieldOptions(pptScheme: 'x_example', pptSerializer: 'cbor'),
        ),
        throwsA(same(failure)),
      );
      expect(responses, isEmpty);
      expect(invocation.responseClosed, isFalse);
      invocation.respondWith(arguments: ['recovered']);
      expect((responses.single as Yield).arguments, ['recovered']);
      expect(invocation.responseClosed, isTrue);
    },
  );

  for (final target in [...codecs.map((codec) => codec.name), null]) {
    for (final lazyArguments in [false, true]) {
      test(
        'partial lazy payload uses explicit fallback, $target args=$lazyArguments',
        () {
          final invocation = Invocation(
            7,
            11,
            InvocationDetails(null, null, false),
          );
          final responses = <AbstractMessageWithPayload>[];
          invocation.onResponse(responses.add);
          final expectedArguments = lazyArguments ? ['lazy'] : ['explicit'];
          final expectedKeywords = lazyArguments
              ? {'explicit': true}
              : {'lazy': true};
          invocation.respondWith(
            lazyPayload: LazyMessagePayload.materialized(
              arguments: lazyArguments ? ['lazy'] : null,
              argumentsKeywords: lazyArguments ? null : {'lazy': true},
            ),
            arguments: ['explicit'],
            argumentsKeywords: {'explicit': true},
            options: YieldOptions(
              pptScheme: 'x_example',
              pptSerializer: target,
            ),
          );
          final response = responses.single as Yield;
          if (target == null) {
            expect(response.arguments, [
              {'args': expectedArguments, 'kwargs': expectedKeywords},
            ]);
          } else {
            final decoder = codecs
                .singleWhere((codec) => codec.name == target)
                .codec;
            final decoded = decoder.deserializePPT(
              Uint8List.fromList(response.arguments!.single as List<int>),
            )!;
            expect(decoded.arguments, expectedArguments);
            expect(decoded.argumentsKeywords, expectedKeywords);
          }
        },
      );
    }
  }
}
