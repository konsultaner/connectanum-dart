@TestOn('vm')
library;

import 'package:connectanum_bench/src/bench_payload/codec.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:test/test.dart';

import 'support/native_library.dart';

void main() {
  final libraryPath = nativeBenchTestLibrary();
  group('benchmark E2EE provider factory', () {
    test('ordinary scenarios do not create an encryption provider', () {
      expect(e2eeProviderFactoryForScenario(_scenario(scheme: null)), isNull);
    });

    for (final implementation in WampClientImplementation.values) {
      for (final invalid in [
        (serializer: 'json', cipher: 'aes256gcm', mode: WampMode.rpc),
        (serializer: 'flatbuffers', cipher: 'unsupported', mode: WampMode.rpc),
        (
          serializer: 'flatbuffers',
          cipher: 'aes256gcm',
          mode: WampMode.fileTransfer,
        ),
      ]) {
        test('rejects direct $implementation profile $invalid', () {
          expect(
            () => e2eeProviderFactoryForScenario(
              _scenario(
                implementation: implementation,
                serializer: invalid.serializer,
                cipher: invalid.cipher,
                mode: invalid.mode,
              ),
            ),
            throwsStateError,
          );
        });
      }
      for (final keyId in [null, '']) {
        test('rejects direct $implementation profile with key ID $keyId', () {
          expect(
            () => e2eeProviderFactoryForScenario(
              _scenario(
                implementation: implementation,
                keyId: keyId,
              ),
            ),
            throwsStateError,
          );
        });
      }
    }

    for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
      test(
        'native typed $cipher factory interoperates with the Dart factory',
        () {
          final native = e2eeProviderFactoryForScenario(
            _scenario(
              implementation: WampClientImplementation.native,
              cipher: cipher,
            ),
            nativeLibraryPath: libraryPath,
          )!();
          addTearDown((native as core.DisposableWampE2eeProvider).release);
          expect(
            native,
            cipher == 'aes256gcm'
                ? isA<client.NativeWampFlatBuffersAes256GcmProvider>()
                : isA<client.NativeWampFlatBuffersXsalsa20Poly1305Provider>(),
          );
          final portable = e2eeProviderFactoryForScenario(
            _scenario(cipher: cipher),
          )!();
          final bytes = BenchPayloadCodec.encodeDart(
            worker: 7,
            iteration: 19,
            bodyBytes: 1024,
          );
          for (final (sender, receiver) in [
            (native, portable),
            (portable, native),
          ]) {
            final options = core.PublishOptions(pptScheme: 'wamp');
            final packed = sender.packPayload([bytes], null, options);
            final clear = receiver.unpackPayload(packed, options);
            expect(options.pptSerializer, 'flatbuffers');
            expect(options.pptCipher, cipher);
            expect(options.pptKeyId, 'benchmark-key');
            expect(clear.arguments, [bytes]);
            expect(clear.argumentsKeywords, isNull);
            BenchPayloadCodec.verify(
              bytes: clear.arguments!.single as List<int>,
              worker: 7,
              iteration: 19,
              bodyBytes: 1024,
            );
          }
        },
        skip: libraryPath == null
            ? 'Native transport artifact unavailable'
            : false,
      );
    }
  });

  group('direct workload construction guards', () {
    for (final construction in [
      WampPayloadConstruction.nativeBuffer,
      WampPayloadConstruction.preEncodedSpan,
    ]) {
      test(
        '$construction requires typed PPT before opening a session',
        () async {
          await _expectRejectedBeforeConnect(
            _scenario(scheme: null, construction: construction),
            'payloadConstruction',
          );
        },
      );
    }
    for (final mode in [
      WampMode.authenticate,
      WampMode.progressiveRpc,
      WampMode.fileTransfer,
    ]) {
      test('typed workload rejects $mode before opening a session', () async {
        await _expectRejectedBeforeConnect(
          _scenario(scheme: 'x_connectanum_bench_typed', mode: mode),
          'mode',
        );
      });
    }
    for (final serializer in [null, 'json']) {
      test(
        'typed workload rejects $serializer before opening a session',
        () async {
          await _expectRejectedBeforeConnect(
            _scenario(
              scheme: 'x_connectanum_bench_typed',
              serializer: serializer,
            ),
            'pptSerializer',
          );
        },
      );
    }
    test('negative duration is rejected before opening a session', () async {
      await _expectRejectedBeforeConnect(
        _scenario().copyWith(minimumDurationMs: -1),
        'minimumDurationMs',
      );
    });
  });
}

Future<void> _expectRejectedBeforeConnect(
  WampScenario scenario,
  String argumentName,
) async {
  var opened = 0;
  final runner = WampWorkloadRunner(
    sessionFactory: (_) async {
      opened++;
      throw StateError('Invalid workloads must not open sessions');
    },
  );
  await expectLater(
    runner.run(scenario),
    throwsA(isA<ArgumentError>().having((e) => e.name, 'name', argumentName)),
  );
  expect(opened, 0);
}

WampScenario _scenario({
  WampClientImplementation implementation = WampClientImplementation.dart,
  WampMode mode = WampMode.rpc,
  WampPayloadConstruction construction = WampPayloadConstruction.dartValues,
  String? scheme = 'wamp',
  String? serializer = 'flatbuffers',
  String cipher = 'aes256gcm',
  String? keyId = 'benchmark-key',
}) => WampScenario(
  transport: WampTransport.rawsocket,
  clientImplementation: implementation,
  serializer: WampSerializer.flatbuffers,
  mode: mode,
  uri: 'bench.rpc.echo',
  iterations: 1,
  concurrency: 1,
  payloadBytes: 1024,
  payloadConstruction: construction,
  pptScheme: scheme,
  pptSerializer: serializer,
  pptCipher: cipher,
  pptKeyId: keyId,
);
