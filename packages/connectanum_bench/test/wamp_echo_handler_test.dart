@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:connectanum_bench/src/bench_payload/codec.dart';
import 'package:connectanum_bench/src/wamp_echo_handler.dart';
import 'package:connectanum_client/native_buffers.dart' as native_buffers;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'support/native_library.dart';

void main() {
  final nativeLibrary = nativeBenchTestLibrary();
  group('respondEchoLazyInvocation', () {
    for (final level in [Level.INFO, Level.FINE]) {
      test('logging at $level preserves an unexported packed source', () async {
        final source = _TrackedPackedSource();
        final payload = wamp_core.LazyMessagePayload.packedSource(
          encoding: wamp_core.LazyPayloadEncoding.flatbuffers,
          source: source,
          packedPayloadDecoder: (_) => throw StateError('payload decoded'),
        );
        final logger = Logger.detached('echo-presence')..level = level;
        final records = <LogRecord>[];
        final subscription = logger.onRecord.listen(records.add);
        addTearDown(subscription.cancel);
        wamp_core.LazyMessagePayload? response;
        final invocation = wamp_core.LazyInvocationPayload(
          requestId: 1,
          registrationId: 2,
          receiveProgress: false,
          pptScheme: 'x_custom_scheme',
          pptSerializer: 'flatbuffers',
          payload: payload,
          isResponseClosed: () => false,
          respondWith:
              ({
                wamp_core.LazyMessagePayload? lazyPayload,
                List<dynamic>? arguments,
                Map<String, dynamic>? argumentsKeywords,
                bool isError = false,
                String? errorUri,
                wamp_core.YieldOptions? options,
              }) => response = lazyPayload,
        );

        respondEchoLazyInvocation(invocation, logger: logger);
        await Future<void>.value();

        expect(response, same(payload));
        expect(source.reads, 0);
        if (level == Level.FINE) {
          expect(records, hasLength(2));
          expect(records.first.message, contains('packed=true'));
        } else {
          expect(records, isEmpty);
        }
      });
    }

    test(
      'logging preserves an unexported native PPT lease',
      () {
        final allocator = native_buffers.NativeBufferAllocator.instance(
          libraryPath: nativeLibrary,
        );
        for (final level in [Level.INFO, Level.FINE]) {
          final producer = BenchPayloadCodec.encodeNative(
            allocator,
            worker: 0,
            iteration: 1,
            bodyBytes: 32,
          );
          addTearDown(producer.dispose);
          final lease = producer.leaseFlatBuffersPptPayload();
          addTearDown(lease.dispose);
          producer.dispose();
          var replies = 0;
          final invocation = wamp_core.LazyInvocationPayload(
            requestId: 1,
            registrationId: 2,
            receiveProgress: false,
            pptScheme: 'x_custom_scheme',
            pptSerializer: 'flatbuffers',
            payload: lease.payload,
            isResponseClosed: () => false,
            respondWith:
                ({
                  wamp_core.LazyMessagePayload? lazyPayload,
                  List<dynamic>? arguments,
                  Map<String, dynamic>? argumentsKeywords,
                  bool isError = false,
                  String? errorUri,
                  wamp_core.YieldOptions? options,
                }) {
                  expect(lazyPayload, same(lease.payload));
                  replies++;
                },
          );
          expect(lease.hasExportedByteView, isFalse);
          respondEchoLazyInvocation(
            invocation,
            logger: Logger.detached('native-echo-presence')..level = level,
          );
          expect(replies, 1);
          expect(lease.hasExportedByteView, isFalse);
          expect(lease.isDisposed, isFalse);
          lease.dispose();
        }
      },
      skip: nativeLibrary == null
          ? 'Native transport artifact unavailable'
          : false,
    );

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

    test('materializes E2EE payloads before producing a fresh response', () {
      var decodeCount = 0;
      final payload = wamp_core.LazyMessagePayload.packed(
        encoding: wamp_core.LazyPayloadEncoding.cbor,
        packedPayloadBytes: Uint8List.fromList(const [0x01, 0x02, 0x03]),
        packedPayloadDecoder: (_) {
          decodeCount += 1;
          return (
            arguments: const ['decrypted'],
            argumentsKeywords: const <String, dynamic>{'worker': 4},
          );
        },
        pptDecoded: true,
      );

      wamp_core.LazyMessagePayload? capturedLazyPayload;
      wamp_core.YieldOptions? capturedOptions;
      final invocation = wamp_core.LazyInvocationPayload(
        requestId: 1,
        registrationId: 2,
        receiveProgress: false,
        pptScheme: 'wamp',
        pptSerializer: 'cbor',
        pptCipher: 'aes256gcm',
        pptKeyId: 'benchmark-key',
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

      expect(decodeCount, 1);
      expect(capturedLazyPayload, isNot(same(payload)));
      expect(capturedLazyPayload!.arguments, const ['decrypted']);
      expect(capturedLazyPayload!.argumentsKeywords, const {'worker': 4});
      expect(capturedOptions!.pptScheme, 'wamp');
      expect(capturedOptions!.pptCipher, 'aes256gcm');
    });
  });
}

final class _TrackedPackedSource implements wamp_core.PackedPayloadSource {
  int reads = 0;

  @override
  Uint8List get bytes {
    reads++;
    return Uint8List.fromList([1, 2, 3]);
  }
}
