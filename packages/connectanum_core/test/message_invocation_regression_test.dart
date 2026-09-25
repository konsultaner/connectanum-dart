import 'dart:convert';
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
  final keywords = <String, dynamic>{
    'nested': {'value': 42, 'empty': null},
  };

  for (final source in codecs) {
    for (var encodedFields = 0; encodedFields < 4; encodedFields++) {
      for (final target in [...codecs.map((codec) => codec.name), null]) {
        test(
          'fragmented ${source.name} fields=$encodedFields response=$target',
          () {
            final wire = source.codec.serialize(
              Invocation(
                7,
                11,
                InvocationDetails(null, null, false),
                arguments: arguments,
                argumentsKeywords: keywords,
              ),
            );
            final decoded =
                source.codec.deserialize(
                      wire is String
                          ? Uint8List.fromList(utf8.encode(wire))
                          : wire as Uint8List,
                    )
                    as Invocation;
            // JSON ingress is eager, but public callers can supply JSON fragments.
            final encoded = source.name == 'json'
                ? LazyMessagePayload.encoded(
                    encoding: source.encoding,
                    argumentsBytes: Uint8List.fromList(
                      utf8.encode(jsonEncode(arguments)),
                    ),
                    argumentsKeywordsBytes: Uint8List.fromList(
                      utf8.encode(jsonEncode(keywords)),
                    ),
                  )
                : decoded.toLazyPayload();
            expect(encoded.argumentsBytes, isNotNull);
            expect(encoded.argumentsKeywordsBytes, isNotNull);
            var argumentDecodes = 0;
            var keywordDecodes = 0;
            final argsEncoded = encodedFields & 1 != 0;
            final kwargsEncoded = encodedFields & 2 != 0;
            final lazy = LazyMessagePayload.encoded(
              encoding: source.encoding,
              argumentsBytes: argsEncoded ? encoded.argumentsBytes : null,
              argumentsKeywordsBytes: kwargsEncoded
                  ? encoded.argumentsKeywordsBytes
                  : null,
              argumentsDecoder: (bytes) {
                expect(bytes, same(encoded.argumentsBytes));
                argumentDecodes++;
                return arguments;
              },
              argumentsKeywordsDecoder: (bytes) {
                expect(bytes, same(encoded.argumentsKeywordsBytes));
                keywordDecodes++;
                return keywords;
              },
              arguments: argsEncoded ? null : arguments,
              argumentsKeywords: kwargsEncoded ? null : keywords,
            );
            final invocation = Invocation(
              7,
              11,
              InvocationDetails(null, null, false),
            );
            final responses = <AbstractMessageWithPayload>[];
            invocation.onResponse(responses.add);
            expect(
              () => invocation.respondWith(
                lazyPayload: lazy,
                options: target == null
                    ? null
                    : YieldOptions(
                        pptScheme: 'x_example',
                        pptSerializer: target,
                      ),
              ),
              returnsNormally,
            );
            final transcodes = target != null && target != source.name;
            expect(argumentDecodes, transcodes && argsEncoded ? 1 : 0);
            expect(keywordDecodes, transcodes && kwargsEncoded ? 1 : 0);
            expect(responses, hasLength(1));
            final response = responses.single as Yield;
            expect(response.invocationRequestId, 7);
            expect(invocation.responseClosed, isTrue);
            if (target == null) {
              expect(
                response.toLazyPayload().argumentsBytes,
                argsEncoded ? same(encoded.argumentsBytes) : isNull,
              );
              expect(
                response.toLazyPayload().argumentsKeywordsBytes,
                kwargsEncoded ? same(encoded.argumentsKeywordsBytes) : isNull,
              );
              expect(response.arguments, arguments);
              expect(response.argumentsKeywords, keywords);
              expect(response.arguments, arguments);
              expect(response.argumentsKeywords, keywords);
            } else {
              final decoder = codecs
                  .singleWhere((codec) => codec.name == target)
                  .codec;
              final unpacked = decoder.deserializePPT(
                Uint8List.fromList(response.arguments!.single as List<int>),
              )!;
              expect(unpacked.arguments, arguments);
              expect(unpacked.argumentsKeywords, keywords);
              expect(response.argumentsKeywords, isNull);
            }
            final readsLazy = target == null || transcodes;
            expect(argumentDecodes, readsLazy && argsEncoded ? 1 : 0);
            expect(keywordDecodes, readsLazy && kwargsEncoded ? 1 : 0);
          },
        );
      }
    }
  }

  for (final progress in [null, false, true]) {
    for (final hasCustom in [false, true]) {
      for (final explicitAnchor in [false, true]) {
        test(
          'views preserve progress=$progress custom=$hasCustom anchor=$explicitAnchor',
          () {
            final details = InvocationDetails(
              23,
              'com.example.work',
              true,
              null,
              null,
              null,
              null,
              hasCustom ? {'trace': 'value'} : null,
            )..progress = progress;
            final invocation = Invocation(
              7,
              11,
              details,
              arguments: arguments,
              argumentsKeywords: keywords,
            );
            final anchor = Object();
            final direct = invocation.toPayload();
            final lazy = invocation.toLazyInvocationPayload(
              anchor: explicitAnchor ? anchor : null,
            );
            final materialized = lazy.toPayload();
            expect(
              lazy.payload.anchor,
              same(explicitAnchor ? anchor : invocation),
            );
            for (final view in [direct, materialized]) {
              expect(view.requestId, 7);
              expect(view.registrationId, 11);
              expect(view.caller, 23);
              expect(view.procedure, 'com.example.work');
              expect(view.progress, progress == true);
              expect(view.receiveProgress, isTrue);
              expect(
                view.customDetails,
                hasCustom ? {'trace': 'value'} : isNull,
              );
              expect(view.arguments, arguments);
              expect(view.argumentsKeywords, keywords);
              expect(view.isResponseClosed(), isFalse);
            }
            expect(lazy.progress, progress == true);
            expect(lazy.customDetails, hasCustom ? {'trace': 'value'} : isNull);
            expect(invocation.arguments, arguments);
            expect(invocation.argumentsKeywords, keywords);
          },
        );
      }
    }
  }

  test('direct lazy invocation constructor defaults to a final invocation', () {
    final invocation = Invocation(7, 11, InvocationDetails(null, null, false));
    final payload = LazyInvocationPayload(
      requestId: 7,
      registrationId: 11,
      receiveProgress: false,
      respondWith: invocation.respondWith,
      isResponseClosed: () => invocation.responseClosed,
      payload: LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: keywords,
      ),
    );
    expect(payload.progress, isFalse);
    expect(payload.toPayload().progress, isFalse);
    expect(payload.arguments, arguments);
    expect(payload.argumentsKeywords, keywords);
  });

  for (final procedure in [null, 'com.example.resolved']) {
    test(
      'response E2EE context uses outbound direction and procedure=$procedure',
      () {
        final anchor = Object();
        final context = WampE2eeRuntimeContext(
          direction: WampE2eeDirection.inbound,
          messageType: WampE2eeMessageType.invocation,
          realm: 'realm1',
          uri: 'com.example.original',
          payloadAnchor: anchor,
        );
        final invocation = Invocation(
          7,
          11,
          InvocationDetails(null, procedure, false),
        )..attachE2eeRuntimeContext(context);
        final responses = <AbstractMessageWithPayload>[];
        invocation.onResponse(responses.add);
        invocation.respondWith(arguments: arguments);
        final responseContext = responses.single.e2eeRuntimeContext!;
        expect(responseContext.direction, WampE2eeDirection.outbound);
        expect(responseContext.messageType, WampE2eeMessageType.yield);
        expect(responseContext.realm, 'realm1');
        expect(responseContext.uri, procedure ?? 'com.example.original');
        expect(responseContext.payloadAnchor, same(anchor));
        expect(context.direction, WampE2eeDirection.inbound);
        expect(context.messageType, WampE2eeMessageType.invocation);
        expect(context.uri, 'com.example.original');
      },
    );
  }

  for (final hasPayloadProvider in [false, true]) {
    test(
      'plain response preserves E2EE provider preference $hasPayloadProvider',
      () {
        final fallback = WampCborXsalsa20Poly1305Provider(
          keys: {'fallback': Uint8List(32)},
        );
        final preferred = WampCborXsalsa20Poly1305Provider(
          keys: {'preferred': Uint8List(32)},
        );
        final invocation = Invocation(
          7,
          11,
          InvocationDetails(null, null, false),
        )..attachE2eeProvider(fallback);
        final responses = <AbstractMessageWithPayload>[];
        invocation.onResponse(responses.add);
        invocation.respondWith(
          lazyPayload: LazyMessagePayload.materialized(
            arguments: arguments,
            e2eeProvider: hasPayloadProvider ? preferred : null,
          ),
        );
        expect(
          responses.single.e2eeProvider,
          same(hasPayloadProvider ? preferred : fallback),
        );
        expect(responses.single.arguments, arguments);
        expect(invocation.e2eeProvider, same(fallback));
      },
    );
  }

  for (final positional in [false, true]) {
    test(
      'orphan response decoder cannot replace materialized fields positional=$positional',
      () {
        final response = Yield(
          7,
          arguments: arguments,
          argumentsKeywords: keywords,
        );
        var decodes = 0;
        response.setLazyPayload(
          argumentsDecoder: positional
              ? (_) {
                  decodes++;
                  return ['unexpected'];
                }
              : null,
          argumentsKeywordsDecoder: positional
              ? null
              : (_) {
                  decodes++;
                  return {'unexpected': true};
                },
          encoding: LazyPayloadEncoding.json,
        );
        final lazy = response.toLazyPayload();
        expect(lazy.argumentsBytes, isNull);
        expect(lazy.argumentsKeywordsBytes, isNull);
        expect(lazy.hasEncodedArguments, isFalse);
        expect(lazy.hasEncodedArgumentsKeywords, isFalse);
        expect(lazy.arguments, same(arguments));
        expect(lazy.argumentsKeywords, same(keywords));
        expect(response.arguments, same(arguments));
        expect(response.argumentsKeywords, same(keywords));
        expect(decodes, 0);
      },
    );
  }

  for (final receiveProgress in [null, false, true]) {
    test('progressive eligibility preserves $receiveProgress', () {
      final invocation = Invocation(
        7,
        11,
        InvocationDetails(null, null, receiveProgress),
      );
      expect(invocation.isProgressive(), receiveProgress == true);
      expect(invocation.toPayload().receiveProgress, receiveProgress == true);
      expect(
        invocation.toLazyInvocationPayload().receiveProgress,
        receiveProgress == true,
      );
    });
  }

  for (final timeout in [null, 0, 1, 9007199254740991]) {
    test('timeout $timeout is valid and retained in both invocation views', () {
      final details = InvocationDetails(23, 'com.example.work', true)
        ..timeout = timeout;
      late bool verified;
      expect(() => verified = details.verify(), returnsNormally);
      expect(verified, isTrue);
      final invocation = Invocation(7, 11, details);
      expect(invocation.toPayload().timeout, timeout);
      expect(invocation.toLazyInvocationPayload().timeout, timeout);
    });
  }
  for (final timeout in [-1, -9007199254740991]) {
    test('negative invocation timeout $timeout is rejected', () {
      final details = InvocationDetails(null, null, null)..timeout = timeout;
      expect(
        () => details.verify(),
        throwsA(
          isA<RangeError>().having(
            (error) => error.invalidValue,
            'invalidValue',
            timeout,
          ),
        ),
      );
    });
  }

  test(
    'error response closes every responder view and rejects later delivery',
    () {
      final invocation = Invocation(7, 11, InvocationDetails(null, null, true));
      final direct = invocation.toPayload();
      final lazy = invocation.toLazyInvocationPayload();
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      expect(
        () => lazy.respondWith(
          isError: true,
          errorUri: Error.notAuthorized,
          arguments: ['denied'],
          argumentsKeywords: {'retry': false},
          options: YieldOptions(progress: false),
        ),
        returnsNormally,
      );
      expect(invocation.responseClosed, isTrue);
      expect(direct.isResponseClosed(), isTrue);
      expect(lazy.isResponseClosed(), isTrue);
      final error = responses.single as Error;
      expect(error, isNot(isA<Yield>()));
      expect(error.error, Error.notAuthorized);
      expect(error.arguments, ['denied']);
      expect(error.argumentsKeywords, {'retry': false});
      expect(() => direct.respondWith(arguments: ['late']), throwsStateError);
      expect(responses, hasLength(1));
    },
  );
}
