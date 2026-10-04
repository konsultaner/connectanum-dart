import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart' hide Error;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:test/test.dart';

void main() {
  for (final isError in [false, true]) {
    test('plain reply decodes an explicitly packed payload error=$isError', () {
      var decodes = 0;
      final payload = LazyMessagePayload.packed(
        encoding: LazyPayloadEncoding.cbor,
        packedPayloadBytes: Uint8List(1),
        packedPayloadDecoder: (_) {
          decodes++;
          return (arguments: ['decoded'], argumentsKeywords: {'n': 42});
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
        isError: isError,
        errorUri: isError ? 'com.error.plain' : null,
        lazyPayload: payload,
      );
      final response = responses.single;
      expect(response.arguments, ['decoded']);
      expect(response.argumentsKeywords, {'n': 42});
      expect(decodes, 1);
      expect(response.toLazyPayload().packedPayloadBytes, isNull);
    });
  }

  for (final size in [0, 5]) {
    test('typed PPT ERROR reuses packed subview size=$size', () {
      final storage = Uint8List(size + 4);
      final bytes = Uint8List.sublistView(storage, 2, 2 + size);
      var decodes = 0;
      final payload = LazyMessagePayload.packed(
        encoding: LazyPayloadEncoding.flatbuffers,
        packedPayloadBytes: bytes,
        packedPayloadDecoder: (_) {
          decodes++;
          throw StateError('matching encoded payload must remain opaque');
        },
        anchor: Object(),
      );
      final invocation = Invocation(
        7,
        11,
        InvocationDetails(null, null, false),
      );
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      invocation.respondWith(
        isError: true,
        errorUri: 'com.error.typed',
        lazyPayload: payload,
        options: YieldOptions(
          pptScheme: 'x_typed',
          pptSerializer: 'flatbuffers',
          custom: {'_trace': 'fixture'},
        ),
      );
      final response = responses.single as core.Error;
      expect(response.requestTypeId, MessageTypes.codeInvocation);
      expect(response.requestId, 7);
      expect(response.error, 'com.error.typed');
      expect(response.details, {
        'ppt_scheme': 'x_typed',
        'ppt_serializer': 'flatbuffers',
        '_trace': 'fixture',
      });
      expect(response.arguments, hasLength(1));
      expect(response.arguments!.single, same(bytes));
      expect(response.argumentsKeywords, isNull);
      expect(decodes, 0);
      expect(invocation.responseClosed, isTrue);
    });
  }

  for (final aes in [false, true]) {
    test('encrypted ERROR selects an error-context key AES=$aes', () {
      WampE2eeRuntimeContext? selectedContext;
      String selectKey(WampE2eeRuntimeContext context, PPTOptions _) {
        selectedContext = context;
        return context.messageType == WampE2eeMessageType.error
            ? 'error-key'
            : 'wrong-key';
      }

      final key = Uint8List.fromList(List.generate(32, (index) => index + 1));
      final WampE2eeProvider provider = aes
          ? WampCborAes256GcmProvider(
              keys: {'error-key': key},
              keySelectionPolicy: selectKey,
            )
          : WampCborXsalsa20Poly1305Provider(
              keys: {'error-key': key},
              keySelectionPolicy: selectKey,
            );
      final invocation =
          Invocation(
              7,
              11,
              InvocationDetails(null, 'com.error.procedure', false),
            )
            ..attachE2eeProvider(provider)
            ..attachE2eeRuntimeContext(
              const WampE2eeRuntimeContext(
                direction: WampE2eeDirection.inbound,
                messageType: WampE2eeMessageType.invocation,
                uri: 'com.original',
                realm: 'test.realm',
              ),
            );
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);
      final options = YieldOptions(pptScheme: 'wamp', pptSerializer: 'cbor');
      invocation.respondWith(
        isError: true,
        errorUri: 'com.error.encrypted',
        arguments: const ['private'],
        argumentsKeywords: const {'code': 42},
        options: options,
      );
      final response = responses.single as core.Error;
      expect(selectedContext?.messageType, WampE2eeMessageType.error);
      expect(selectedContext?.direction, WampE2eeDirection.outbound);
      expect(selectedContext?.uri, 'com.error.procedure');
      expect(selectedContext?.realm, 'test.realm');
      expect(response.e2eeProvider, same(provider));
      expect(
        response.e2eeRuntimeContext?.messageType,
        WampE2eeMessageType.error,
      );
      expect(response.details['ppt_scheme'], 'wamp');
      expect(response.details['ppt_serializer'], 'cbor');
      expect(response.details['ppt_keyid'], 'error-key');
      expect(response.details['ppt_cipher'], options.pptCipher);
      expect(response.arguments, hasLength(1));
      expect(response.arguments!.single, isA<Uint8List>());
      expect(response.argumentsKeywords, isNull);
      final decoded = provider.unpackPayload(
        response.arguments,
        options,
        runtimeContext: selectedContext!.copyWith(
          direction: WampE2eeDirection.inbound,
        ),
      );
      expect(decoded.arguments, ['private']);
      expect(decoded.argumentsKeywords, {'code': 42});
    });
  }

  test('plain lazy ERROR preserves encoded spans until getter access', () {
    final argumentsBytes = Uint8List.fromList([0x81, 0x01]);
    final keywordBytes = Uint8List.fromList([0xa1, 0x61, 0x6e, 0x02]);
    var argumentDecodes = 0;
    var keywordDecodes = 0;
    final payload = LazyMessagePayload.encoded(
      encoding: LazyPayloadEncoding.cbor,
      argumentsBytes: argumentsBytes,
      argumentsKeywordsBytes: keywordBytes,
      argumentsDecoder: (_) {
        argumentDecodes++;
        return [1];
      },
      argumentsKeywordsDecoder: (_) {
        keywordDecodes++;
        return {'n': 2};
      },
    );
    final invocation = Invocation(7, 11, InvocationDetails(null, null, false));
    final responses = <AbstractMessageWithPayload>[];
    invocation.onResponse(responses.add);
    invocation.respondWith(
      isError: true,
      errorUri: 'com.error.lazy',
      lazyPayload: payload,
    );
    final response = responses.single as core.Error;
    final wire = response.toLazyPayload();
    expect(wire.argumentsBytes, same(argumentsBytes));
    expect(wire.argumentsKeywordsBytes, same(keywordBytes));
    expect(wire.encoding, LazyPayloadEncoding.cbor);
    expect(argumentDecodes, 0);
    expect(keywordDecodes, 0);
    expect(response.arguments, [1]);
    expect(response.argumentsKeywords, {'n': 2});
    expect(argumentDecodes, 1);
    expect(keywordDecodes, 1);
  });

  test('ERROR packing failure emits nothing and allows retry', () {
    final invocation = Invocation(7, 11, InvocationDetails(null, null, false));
    final responses = <AbstractMessageWithPayload>[];
    invocation.onResponse(responses.add);
    final failure = StateError('cannot decode source');
    final payload = LazyMessagePayload.packed(
      encoding: LazyPayloadEncoding.json,
      packedPayloadBytes: Uint8List(1),
      packedPayloadDecoder: (_) => throw failure,
    );
    expect(
      () => invocation.respondWith(
        isError: true,
        errorUri: 'com.error.failed',
        lazyPayload: payload,
        options: YieldOptions(pptScheme: 'x_typed', pptSerializer: 'cbor'),
      ),
      throwsA(same(failure)),
    );
    expect(responses, isEmpty);
    expect(invocation.responseClosed, isFalse);
    invocation.respondWith(isError: true, errorUri: 'com.error.retry');
    expect(invocation.responseClosed, isTrue);
    expect(responses, hasLength(1));
  });
}
