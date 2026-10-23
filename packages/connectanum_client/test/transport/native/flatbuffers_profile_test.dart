@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart'
    hide NativeRawSocketTransport;
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_client/src/transport/native/flatbuffers_payload_anchor.dart'
    show
        nativeFlatBufferPptSubmissionSnapshot,
        observeNativeFlatBufferPptSubmissions;
import 'package:connectanum_client/src/transport/native/native_transports_io.dart'
    show NativeRawSocketTransport;
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_client/src/transport/socket/socket_helper.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:test/test.dart';

NativeOwnedBuffer _encodeNative(
  NativeRawSocketTransport transport,
  AbstractMessage message,
) {
  final builder = transport.nativeBuffers.flatBuffers(initialSize: 8192);
  try {
    builder.finish(flat.writeWampFlatBufferMessage(message, builder));
    return builder.freeze();
  } finally {
    builder.dispose();
  }
}

void main() {
  NativeRawSocketTransport transport(_Peer peer) => NativeRawSocketTransport(
    '127.0.0.1',
    peer.port,
    flat.Serializer(),
    SocketHelper.serializationFlatBuffers,
  );

  test(
    'leased FlatBuffers PPT survives producer disposal and repeated lazy sends',
    () async {
      final peer = await _Peer.start('ppt-echo');
      final client = transport(peer);
      NativeOwnedBuffer? producer;
      NativePptPayloadLease? lease;
      try {
        await client.open();
        await client.onReady.timeout(const Duration(seconds: 5));
        final session = await Session.start('realm', client);
        producer = _typedEntity(client.nativeBuffers, 61);
        lease = producer.leaseFlatBuffersPptPayload();
        producer.dispose();
        for (var iteration = 0; iteration < 2; iteration++) {
          final payload = lease.payload
              .withAnchor(Object())
              .withE2eeRuntimeContext(
                const WampE2eeRuntimeContext(
                  direction: WampE2eeDirection.outbound,
                  messageType: WampE2eeMessageType.call,
                  realm: 'realm',
                  uri: 'com.entity.read',
                ),
              );
          final result = await session
              .callLazyPayload(
                'com.entity.read',
                payload: payload,
                options: CallOptions(
                  pptScheme: 'x_flatbuffers',
                  pptSerializer: 'flatbuffers',
                ),
              )
              .first
              .timeout(const Duration(seconds: 5));
          final entity =
              wire.Message(result.arguments!.single as Uint8List).msg
                  as wire.Call;
          expect(entity.request, 61);
          expect(entity.procedure, 'com.example.entity');
          expect(lease.hasExportedByteView, isFalse);
        }
        lease.dispose();
        await session.close();
        await session.onGoodbye.timeout(const Duration(seconds: 5));
        expect(await peer.close(), [1, 48, 48, 6]);
      } finally {
        producer?.dispose();
        lease?.dispose();
        await client.close();
        await peer.dispose();
      }
    },
  );

  for (final foreign in [false, true]) {
    test(
      'leased payload safely falls back for ${foreign ? 'foreign library' : 'Dart transport'}',
      () async {
        final peer = await _Peer.start('ppt-echo');
        final AbstractTransport client = foreign
            ? transport(peer)
            : SocketTransport.withFlatBuffersSerializer('127.0.0.1', peer.port);
        Directory? directory;
        NativeOwnedBuffer? producer;
        NativePptPayloadLease? lease;
        try {
          var allocator = NativeBufferAllocator.instance();
          if (foreign) {
            directory = await Directory.systemTemp.createTemp(
              'connectanum-lease-foreign-',
            );
            final copied =
                await File(NativeClientRuntime.instance().libraryPath).copy(
                  '${directory.path}/native.${Platform.isMacOS ? 'dylib' : 'so'}',
                );
            allocator = NativeBufferAllocator(DynamicLibrary.open(copied.path));
          }
          await client.open();
          // Session starts receive() before waiting for the Dart socket's
          // negotiation. Native transports already pump during open().
          final session = await Session.start(
            'realm',
            client,
          ).timeout(const Duration(seconds: 5));
          producer = _typedEntity(allocator, 62);
          lease = producer.leaseFlatBuffersPptPayload();
          producer.dispose();
          final result = await session
              .callLazyPayload(
                'com.entity.read',
                payload: lease.payload,
                options: CallOptions(
                  pptScheme: 'x_flatbuffers',
                  pptSerializer: 'flatbuffers',
                ),
              )
              .first
              .timeout(const Duration(seconds: 5));
          final entity =
              wire.Message(result.arguments!.single as Uint8List).msg
                  as wire.Call;
          expect(entity.request, 62);
          expect(lease.hasExportedByteView, isTrue);
          expect(lease.isDisposed, isFalse);
          lease.dispose();
          await session.close();
          await session.onGoodbye.timeout(const Duration(seconds: 5));
          expect(await peer.close(), [1, 48, 6]);
        } finally {
          producer?.dispose();
          lease?.dispose();
          await client.close();
          await peer.dispose();
          await directory?.delete(recursive: true);
        }
      },
      skip: foreign && Platform.isWindows
          ? 'Private copied DLL remains loaded on Windows'
          : false,
    );
  }

  test(
    'typed native submission does not reparse canonical control strings',
    () async {
      const isolation = 'CONNECTANUM_TEST_NATIVE_CONTROL_COPY_ISOLATED';
      if (Platform.environment[isolation] != '1') {
        // Native codec counters are process-wide. Other test-file isolates
        // must not contribute copies to this synchronous submission window.
        final entry = await Isolate.resolvePackageUri(
          Uri.parse('package:connectanum_client/connectanum.dart'),
        );
        final packageRoot = entry!.resolve('../');
        final child = await Process.run(
          Platform.resolvedExecutable,
          [
            'test',
            packageRoot
                .resolve('test/transport/native/flatbuffers_profile_test.dart')
                .toFilePath(),
            '--name',
            '^typed native submission does not reparse canonical control strings\$',
            '--reporter',
            'json',
          ],
          workingDirectory: packageRoot.toFilePath(),
          environment: {
            ...Platform.environment,
            isolation: '1',
            'CONNECTANUM_SKIP_NATIVE_BUILD': '1',
          },
        );
        expect(child.exitCode, 0, reason: '${child.stdout}\n${child.stderr}');
        final events = (child.stdout as String)
            .split('\n')
            .where((line) => line.startsWith('{'))
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        expect(
          events.where(
            (event) =>
                event['type'] == 'testDone' &&
                event['hidden'] != true &&
                event['skipped'] != true &&
                event['result'] == 'success',
          ),
          hasLength(1),
        );
        expect(
          events.any(
            (event) => event['type'] == 'done' && event['success'] == true,
          ),
          true,
        );
        return;
      }
      final peer = await _Peer.start('ppt-echo');
      final client = transport(peer);
      NativeOwnedBuffer? owner;
      StreamIterator<AbstractMessage?>? messages;
      try {
        messages = StreamIterator<AbstractMessage?>(await _open(client));
        client.send(Hello('realm', Details.forHello()));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          true,
        );
        expect(messages.current, isA<Welcome>());
        owner = _typedEntity(client.nativeBuffers, 51);
        final expected = owner.bytes.toList(growable: false);
        observeNativeFlatBufferPptSubmissions(owner);
        final call = Call(
          7,
          'com.entity.read',
          options: CallOptions(
            pptScheme: 'x_flatbuffers',
            pptSerializer: 'flatbuffers',
          ),
        )..retainLazyPayload(owner.asFlatBuffersPptPayload());
        final runtime = NativeClientRuntime.instance();
        final before = runtime.codecCopyMetricsSnapshot()!;
        client.send(call);
        // The peer runs on this isolate and cannot reply until we yield. This
        // window measures only synchronous submission, excluding inbound parsing.
        final after = runtime.codecCopyMetricsSnapshot()!;
        final controlStringCopies =
            after['string_copy_bytes']! - before['string_copy_bytes']!;
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          true,
        );
        final result = messages.current as Result;
        expect(result.callRequestId, 7);
        expect(
          result.toLazyPayload().packedPayloadBytes ??
              result.transparentBinaryPayload,
          orderedEquals(expected),
        );
        expect(owner.isDisposed, false);
        expect(nativeFlatBufferPptSubmissionSnapshot(owner), (
          submissions: 1,
          reusedBytes: owner.length,
        ));
        final fallbackFixture =
            Platform.environment['CONNECTANUM_TEST_EXPECT_SEGMENT_FALLBACK'] ==
            '1';
        expect(client.nativeBuffers.supportsSegmentedBuffers, !fallbackFixture);
        expect(
          controlStringCopies,
          fallbackFixture ? greaterThan(0) : equals(0),
          reason: fallbackFixture
              ? 'the missing optional ABI must use validated frame composition'
              : 'canonical controls should use retained encoded spans',
        );
        client.send(Goodbye(null, 'wamp.close.normal'));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          true,
        );
        expect(messages.current, isA<Goodbye>());
        expect(await peer.close(), [1, 48, 6]);
      } finally {
        await messages?.cancel();
        owner?.dispose();
        await client.close();
        await peer.dispose();
      }
    },
  );

  test(
    'typed native prefix preserves full-frame bounds without consuming its owner',
    () async {
      final peer = await _Peer.start('anonymous');
      final client = transport(peer);
      StreamIterator<AbstractMessage?>? messages;
      try {
        messages = StreamIterator<AbstractMessage?>(await _open(client));
        client.send(Hello('realm', Details.forHello()));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          true,
        );
        expect(messages.current, isA<Welcome>());
        for (final length in [64 * 1024 * 1024, 64 * 1024 * 1024 + 1]) {
          final builder = client.nativeBuffers.allocate(length);
          late NativeOwnedBuffer owner;
          try {
            owner = builder.freeze();
          } finally {
            builder.dispose();
          }
          try {
            observeNativeFlatBufferPptSubmissions(owner);
            final call = Call(
              7,
              'com.entity.read',
              options: CallOptions(
                pptScheme: 'x_flatbuffers',
                pptSerializer: 'flatbuffers',
              ),
            )..retainLazyPayload(owner.asFlatBuffersPptPayload());
            expect(
              () => client.send(call),
              throwsA(isA<NativeBufferException>()),
            );
            expect(owner.isDisposed, false);
            expect(owner.length, length);
            expect(nativeFlatBufferPptSubmissionSnapshot(owner).submissions, 0);
          } finally {
            owner.dispose();
          }
        }
        client.send(Goodbye(null, 'wamp.close.normal'));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          true,
        );
        expect(messages.current, isA<Goodbye>());
        expect(await peer.close(), [1, 6]);
      } finally {
        await messages?.cancel();
        await client.close();
        await peer.dispose();
      }
    },
  );

  test(
    'native FlatBuffers selection rejects a mismatched codec before opening',
    () {
      expect(
        () => NativeRawSocketTransport(
          '127.0.0.1',
          1,
          cbor.Serializer(),
          SocketHelper.serializationFlatBuffers,
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeRawSocketTransport(
          '127.0.0.1',
          1,
          flat.Serializer(),
          SocketHelper.serializationCbor,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'native FlatBuffers anonymous session exchanges RPC and closes',
    () async {
      final peer = await _Peer.start('anonymous');
      final client = transport(peer);
      final messages = StreamIterator<AbstractMessage?>(await _open(client));
      try {
        client.send(Hello('realm', Details.forHello()));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(messages.current, isA<Welcome>());
        client.send(Call(1, 'com.echo', arguments: ['value']));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect((messages.current as Result).arguments, ['value']);
        client.send(Goodbye(null, 'wamp.close.normal'));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(messages.current, isA<Goodbye>());
        expect(await peer.close(), [1, 48, 6]);
      } finally {
        await messages.cancel();
        await client.close();
        await peer.dispose();
      }
    },
  );

  test(
    'native typed PPT cannot bypass the session profile state check',
    () async {
      final peer = await _Peer.start('anonymous');
      final client = transport(peer);
      NativeOwnedBuffer? owner;
      try {
        await client.open();
        await client.onReady.timeout(const Duration(seconds: 5));
        owner = _typedEntity(client.nativeBuffers, 51);
        observeNativeFlatBufferPptSubmissions(owner);
        final call = Call(
          1,
          'com.entity.read',
          options: CallOptions(
            pptScheme: 'x_flatbuffers',
            pptSerializer: 'flatbuffers',
          ),
        )..retainLazyPayload(owner.asFlatBuffersPptPayload());

        expect(() => client.send(call), throwsStateError);
        expect(nativeFlatBufferPptSubmissionSnapshot(owner).submissions, 0);
        expect(owner.isDisposed, isFalse);
      } finally {
        owner?.dispose();
        await client.close();
        await peer.dispose();
      }
    },
  );

  test(
    'typed native send rejects invalid metadata without consuming its owner',
    () async {
      final peer = await _Peer.start('ppt-echo');
      final client = transport(peer);
      NativeOwnedBuffer? owner;
      try {
        await client.open();
        await client.onReady.timeout(const Duration(seconds: 5));
        final session = await Session.start('realm', client);
        owner = _typedEntity(client.nativeBuffers, 51);
        observeNativeFlatBufferPptSubmissions(owner);
        final bytes = owner.bytes.toList(growable: false);
        for (final custom in <Map<String, dynamic>>[
          {'receive_progress': 'yes'},
          {
            'forward_for': [false],
          },
          {'_unsupported': Object()},
        ]) {
          final invalid = Call(
            1,
            'com.entity.read',
            options: CallOptions(
              pptScheme: 'x_flatbuffers',
              pptSerializer: 'flatbuffers',
              custom: custom,
            ),
          )..retainLazyPayload(owner.asFlatBuffersPptPayload());
          expect(
            () => client.send(invalid),
            custom.containsKey('_unsupported')
                ? throwsUnsupportedError
                : throwsArgumentError,
          );
          expect(owner.isDisposed, isFalse);
          expect(owner.bytes, bytes);
          expect(nativeFlatBufferPptSubmissionSnapshot(owner).submissions, 0);
        }
        final result = await session
            .callLazyPayload(
              'com.entity.read',
              payload: owner.asFlatBuffersPptPayload(),
              options: CallOptions(
                pptScheme: 'x_flatbuffers',
                pptSerializer: 'flatbuffers',
              ),
            )
            .first
            .timeout(const Duration(seconds: 5));
        expect(result.arguments, [bytes]);
        expect(nativeFlatBufferPptSubmissionSnapshot(owner), (
          submissions: 1,
          reusedBytes: owner.length,
        ));
        await session.close();
        await session.onGoodbye.timeout(const Duration(seconds: 5));
        expect(await peer.close(), [1, 48, 6]);
      } finally {
        owner?.dispose();
        await client.close();
        await peer.dispose();
      }
    },
  );

  test(
    'typed native send rejects a connection closed by a metadata loader',
    () async {
      final peer = await _Peer.start('ppt-echo');
      final client = transport(peer);
      NativeOwnedBuffer? owner;
      Future<void>? closing;
      try {
        await client.open();
        await client.onReady.timeout(const Duration(seconds: 5));
        await Session.start('realm', client);
        owner = _typedEntity(client.nativeBuffers, 51);
        observeNativeFlatBufferPptSubmissions(owner);
        final options =
            CallOptions(
              pptScheme: 'x_flatbuffers',
              pptSerializer: 'flatbuffers',
            )..setLazyCustomFieldsLoader(() {
              closing = client.close();
              return {};
            });
        final call = Call(1, 'com.entity.read', options: options)
          ..retainLazyPayload(owner.asFlatBuffersPptPayload());
        expect(() => client.send(call), throwsStateError);
        await closing;
        expect(owner.isDisposed, isFalse);
        expect(nativeFlatBufferPptSubmissionSnapshot(owner).submissions, 0);
        expect(await peer.close(), [1]);
      } finally {
        owner?.dispose();
        await closing;
        await client.close();
        await peer.dispose();
      }
    },
  );

  test(
    'Session sends native-owned encrypted CBOR without copying ciphertext',
    () async {
      final peer = await _Peer.start('ppt-echo');
      final client = transport(peer);
      final runtime = NativeClientRuntime.instance();
      final provider = NativeWampCborAes256GcmProvider.single(
        keyId: 'native-session-key',
        key: List<int>.generate(32, (index) => index + 1),
      );
      try {
        expect(client.nativeBuffers.supportsOwnedE2eeEncryption, isTrue);
        await client.open();
        await client.onReady.timeout(const Duration(seconds: 5));
        final session = await Session.start(
          'realm',
          client,
          e2eeProvider: provider,
        );
        final before = runtime.transportCopyMetricsSnapshot();
        final application = Uint8List.fromList(
          List<int>.generate(1024, (index) => index & 255),
        );
        final result = await session
            .callLazyPayload(
              'com.entity.read',
              payload: core.LazyMessagePayload.materialized(
                arguments: [application],
              ),
              options: CallOptions(
                pptScheme: 'wamp',
                pptSerializer: 'cbor',
              ),
            )
            .first
            .timeout(const Duration(seconds: 5));
        final copied = runtime.transportCopyMetricsSnapshot().deltaFrom(before);

        expect(result.arguments, [application]);
        expect(result.details.pptCipher, 'aes256gcm');
        expect(result.details.pptKeyId, 'native-session-key');
        expect(
          copied.dartToNativeCopiedBytesTotal,
          0,
          reason: 'native ciphertext and its FlatBuffers vector stay owned',
        );
        await session.close();
        await session.onGoodbye.timeout(const Duration(seconds: 5));
        expect(await peer.close(), [1, 48, 6]);
      } finally {
        provider.release();
        await client.close();
        await peer.dispose();
      }
    },
  );

  test(
    'Session sends native-owned typed FlatBuffers PPT as a retained frame',
    () async {
      final peer = await _Peer.start('ppt-echo');
      final client = transport(peer);
      NativeOwnedBuffer? typedOwner;
      NativeOwnedBuffer? fallbackOwner;
      try {
        await client.open();
        await client.onReady.timeout(const Duration(seconds: 5));
        final session = await Session.start('realm', client);
        typedOwner = _typedEntity(client.nativeBuffers, 51);
        observeNativeFlatBufferPptSubmissions(typedOwner);
        final typedBytes = typedOwner.bytes.toList(growable: false);
        final typedResultFuture = session
            .callLazyPayload(
              'com.entity.read',
              payload: typedOwner.asFlatBuffersPptPayload(),
              options: CallOptions(
                pptScheme: 'x_flatbuffers',
                pptSerializer: 'flatbuffers',
              ),
            )
            .first
            .timeout(const Duration(seconds: 5));
        final measuredTypedOwner = typedOwner;
        typedOwner.dispose();
        typedOwner = null;
        final typedResult = await typedResultFuture;
        expect(nativeFlatBufferPptSubmissionSnapshot(measuredTypedOwner), (
          submissions: 1,
          reusedBytes: measuredTypedOwner.length,
        ));
        expect(typedResult.arguments, [typedBytes]);

        fallbackOwner = _typedEntity(client.nativeBuffers, 52);
        observeNativeFlatBufferPptSubmissions(fallbackOwner);
        final nestedBytes = fallbackOwner.bytes.toList(growable: false);
        var nestedPayload = fallbackOwner.asFlatBuffersPptPayload();
        for (var depth = 0; depth < 6; depth++) {
          nestedPayload = core.LazyMessagePayload.packed(
            encoding: core.LazyPayloadEncoding.flatbuffers,
            packedPayloadBytes: nestedPayload.packedPayloadBytes!,
            packedPayloadDecoder: (bytes) => (
              arguments: <dynamic>[bytes],
              argumentsKeywords: null,
            ),
            anchor: nestedPayload,
          );
        }
        final nestedResultFuture = session
            .callLazyPayload(
              'com.entity.read',
              payload: nestedPayload,
              options: CallOptions(
                pptScheme: 'x_flatbuffers',
                pptSerializer: 'flatbuffers',
              ),
            )
            .first
            .timeout(const Duration(seconds: 5));
        final measuredNestedOwner = fallbackOwner;
        fallbackOwner.dispose();
        fallbackOwner = null;
        final nestedResult = await nestedResultFuture;
        expect(nativeFlatBufferPptSubmissionSnapshot(measuredNestedOwner), (
          submissions: 1,
          reusedBytes: measuredNestedOwner.length,
        ));
        expect(nestedResult.arguments, [nestedBytes]);

        fallbackOwner = _typedEntity(client.nativeBuffers, 53);
        observeNativeFlatBufferPptSubmissions(fallbackOwner);
        final fallbackBytes = fallbackOwner.bytes.toList(growable: false);
        final fallbackResult = await session
            .callLazyPayload(
              'com.entity.read',
              payload: fallbackOwner.asFlatBuffersPptPayload(),
              options: CallOptions(
                pptScheme: 'x_flatbuffers',
                pptSerializer: 'cbor',
              ),
            )
            .first
            .timeout(const Duration(seconds: 5));
        fallbackOwner.dispose();
        expect(nativeFlatBufferPptSubmissionSnapshot(fallbackOwner), (
          submissions: 0,
          reusedBytes: 0,
        ));
        expect(fallbackResult.arguments, [fallbackBytes]);

        await session.close();
        await session.onGoodbye.timeout(const Duration(seconds: 5));
        expect(await peer.close(), [1, 48, 48, 48, 6]);
      } finally {
        typedOwner?.dispose();
        fallbackOwner?.dispose();
        await client.close();
        await peer.dispose();
      }
    },
  );

  for (final scenario in ['missing-challenge', 'missing-welcome']) {
    test(
      'native $scenario rejects before delivering unsupported bootstrap',
      () async {
        final peer = await _Peer.start(scenario);
        final client = transport(peer);
        final outcome = Completer<Object>();
        var credentials = 0;
        final stream = await _open(client);
        final subscription = stream.listen(
          (message) {
            if (message is Challenge) {
              credentials++;
              client.send(Authenticate(signature: 'secret'));
            } else if (!outcome.isCompleted && message is Welcome) {
              outcome.complete(message);
            }
          },
          onError: (Object error) {
            if (!outcome.isCompleted) outcome.complete(error);
          },
        );
        try {
          final offer = Hello('realm', Details.forHello());
          // Offer explicitly so the baseline probe isolates peer acknowledgement.
          const flat.FlatBuffersSessionProfile.client().prepareOutgoing(offer);
          client.send(offer);
          expect(
            await outcome.future.timeout(const Duration(seconds: 5)),
            isA<UnsupportedError>(),
          );
          final codes = await peer.close();
          expect(credentials, scenario == 'missing-challenge' ? 0 : 1);
          expect(codes, scenario == 'missing-challenge' ? [1] : [1, 5]);
        } finally {
          await subscription.cancel();
          await client.close();
          await peer.dispose();
        }
      },
    );
  }

  for (final tracked in [false, true]) {
    test(
      'native pre-encoded sends obey the profile, tracked=$tracked',
      () async {
        final peer = await _Peer.start('anonymous');
        final client = transport(peer);
        final messages = StreamIterator<AbstractMessage?>(await _open(client));
        try {
          final earlyCall = _encodeNative(client, Call(1, 'com.echo'));
          final credentials = _encodeNative(
            client,
            Authenticate(signature: 'secret'),
          );
          final unoffered = _encodeNative(
            client,
            Hello('realm', Details.forHello()),
          );
          for (final buffer in [earlyCall, credentials]) {
            expect(
              () => tracked
                  ? client.sendEncodedNativeBufferTracked(
                      buffer,
                      transfer: true,
                    )
                  : client.sendEncodedNativeBuffer(buffer, transfer: true),
              throwsStateError,
            );
            expect(buffer.isDisposed, isFalse);
            buffer.dispose();
          }
          expect(
            () => tracked
                ? client.sendEncodedNativeBufferTracked(
                    unoffered,
                    transfer: true,
                  )
                : client.sendEncodedNativeBuffer(unoffered, transfer: true),
            throwsUnsupportedError,
          );
          expect(unoffered.isDisposed, isFalse);
          unoffered.dispose();

          final offer = Hello('realm', Details.forHello());
          const flat.FlatBuffersSessionProfile.client().prepareOutgoing(offer);
          final encodedOffer = _encodeNative(client, offer);
          // StreamIterator subscribes lazily; start before awaiting a receipt.
          final welcome = messages.moveNext();
          if (tracked) {
            final receipt = client.sendEncodedNativeBufferTracked(
              encodedOffer,
              transfer: true,
            );
            expect(
              await receipt.wait(timeout: const Duration(seconds: 5)),
              NativeWriteOutcome.written,
            );
            receipt.dispose();
          } else {
            client.sendEncodedNativeBuffer(encodedOffer, transfer: true);
          }
          expect(encodedOffer.isDisposed, isTrue);
          expect(await welcome.timeout(const Duration(seconds: 5)), isTrue);
          expect(messages.current, isA<Welcome>());
          final encodedCall = _encodeNative(
            client,
            Call(1, 'com.echo', arguments: ['owned']),
          );
          client.sendEncodedNativeBuffer(encodedCall, transfer: true);
          expect(
            await messages.moveNext().timeout(const Duration(seconds: 5)),
            isTrue,
          );
          expect((messages.current as Result).arguments, ['owned']);
          expect(await peer.close(), [1, 48]);
        } finally {
          await messages.cancel();
          await client.close();
          await peer.dispose();
        }
      },
    );
    test('native composed sends obey the profile, tracked=$tracked', () async {
      final peer = await _Peer.start('anonymous');
      final client = transport(peer);
      final messages = StreamIterator<AbstractMessage?>(await _open(client));
      NativeFlatBufferFrame frame(
        AbstractMessage message, {
        NativeOwnedBuffer? arguments,
      }) {
        final control = _encodeNative(client, message);
        try {
          return client.nativeBuffers.composeFlatBufferFrame(
            control,
            arguments: arguments,
          );
        } finally {
          control.dispose();
        }
      }

      NativeWriteReceipt? send(NativeFlatBufferFrame value) {
        if (tracked) {
          return client.sendNativeFrameTracked(value, transfer: true);
        }
        client.sendNativeFrame(value, transfer: true);
        return null;
      }

      try {
        for (final message in [
          Call(1, 'com.echo'),
          Authenticate(signature: 'secret'),
        ]) {
          final value = frame(message);
          expect(() => send(value), throwsStateError);
          expect(value.isDisposed, isFalse);
          value.dispose();
        }
        final unoffered = frame(Hello('realm', Details.forHello()));
        expect(() => send(unoffered), throwsUnsupportedError);
        expect(unoffered.isDisposed, isFalse);
        unoffered.dispose();
        final offer = Hello('realm', Details.forHello());
        const flat.FlatBuffersSessionProfile.client().prepareOutgoing(offer);
        final offered = frame(offer);
        // Listen before the tracked write can yield to a fast WELCOME reply.
        final welcome = messages.moveNext();
        final helloReceipt = send(offered);
        if (helloReceipt != null) {
          expect(
            await helloReceipt.wait(timeout: const Duration(seconds: 5)),
            NativeWriteOutcome.written,
          );
          helloReceipt.dispose();
        }
        expect(offered.isDisposed, isTrue);
        expect(await welcome.timeout(const Duration(seconds: 5)), isTrue);
        expect(messages.current, isA<Welcome>());
        final builder = client.nativeBuffers.allocate(4);
        final NativeOwnedBuffer arguments;
        try {
          builder.setUint8(0, 0x83);
          builder.setUint8(1, 1);
          builder.setUint8(2, 2);
          builder.setUint8(3, 3);
          arguments = builder.freeze();
        } finally {
          builder.dispose();
        }
        expect(arguments.inputCopiedBytes, 0);
        final invocation = frame(Call(1, 'com.echo'), arguments: arguments);
        arguments.dispose();
        final callReceipt = send(invocation);
        if (callReceipt != null) {
          expect(
            await callReceipt.wait(timeout: const Duration(seconds: 5)),
            NativeWriteOutcome.written,
          );
          callReceipt.dispose();
        }
        expect(invocation.isDisposed, isTrue);
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect((messages.current as Result).arguments, [1, 2, 3]);
        expect(await peer.close(), [1, 48]);
      } finally {
        await messages.cancel();
        await client.close();
        await peer.dispose();
      }
    });
  }
}

Future<Stream<AbstractMessage?>> _open(NativeRawSocketTransport client) async {
  await client.open();
  await client.onReady.timeout(const Duration(seconds: 5));
  return client.receive();
}

NativeOwnedBuffer _typedEntity(NativeBufferAllocator allocator, int request) =>
    allocator.buildFlatBuffer(
      wire.MessageObjectBuilder(
        msgType: wire.AnyMessageTypeId.Call,
        msg: wire.CallObjectBuilder(
          request: request,
          procedure: 'com.example.entity',
        ),
      ),
      initialSize: 128,
    );

class _Peer {
  _Peer(
    this.isolate,
    this.port,
    this.control,
    this.receivePort,
    this.exited,
    this.closed,
    this.subscription,
  );
  final Isolate isolate;
  final int port;
  final SendPort control;
  final ReceivePort receivePort;
  final Future<void> exited;
  final Completer<List<int>> closed;
  final StreamSubscription<dynamic> subscription;

  static Future<_Peer> start(String scenario) async {
    final receive = ReceivePort();
    final exit = ReceivePort();
    final exited = exit.first.then<void>((_) => exit.close());
    final ready = Completer<Map>();
    final closed = Completer<List<int>>();
    final subscription = receive.listen((dynamic event) {
      final message = event as Map;
      if (message['type'] == 'ready') ready.complete(message);
      if (message['type'] == 'closed') {
        closed.complete((message['codes'] as List).cast<int>());
      }
      if (message['type'] == 'error') {
        final error = StateError(message['error'] as String);
        if (!ready.isCompleted) ready.completeError(error);
        if (!closed.isCompleted) closed.completeError(error);
      }
    });
    final isolate = await Isolate.spawn(_peerMain, {
      'send': receive.sendPort,
      'scenario': scenario,
    }, onExit: exit.sendPort);
    final config = await ready.future.timeout(const Duration(seconds: 5));
    return _Peer(
      isolate,
      config['port'] as int,
      config['control'] as SendPort,
      receive,
      exited,
      closed,
      subscription,
    );
  }

  Future<List<int>> close() {
    if (!closed.isCompleted) control.send(null);
    return closed.future.timeout(const Duration(seconds: 5));
  }

  Future<void> dispose() async {
    if (!closed.isCompleted) await close();
    await exited.timeout(const Duration(seconds: 5));
    await subscription.cancel();
    receivePort.close();
  }
}

Future<void> _peerMain(Map<String, Object?> config) async {
  final send = config['send'] as SendPort;
  final scenario = config['scenario'] as String;
  final control = ReceivePort();
  final server = await ServerSocket.bind('127.0.0.1', 0);
  Socket? connection;
  final codes = <int>[];
  control.listen((_) async {
    connection?.destroy();
    await server.close();
    control.close();
    send.send({'type': 'closed', 'codes': codes});
  });
  server.listen((socket) {
    connection = socket;
    var bytes = Uint8List(0);
    var handshake = false;
    var profile = const flat.FlatBuffersSessionProfile.router();
    final codec = flat.Serializer();
    void write(AbstractMessage message, {bool acknowledge = true}) {
      if (acknowledge) profile = profile.prepareOutgoing(message);
      final encoded = codec.serialize(message);
      socket.add([
        0,
        (encoded.length >> 16) & 255,
        (encoded.length >> 8) & 255,
        encoded.length & 255,
        ...encoded,
      ]);
    }

    socket.listen(
      (chunk) {
        try {
          bytes = Uint8List.fromList([...bytes, ...chunk]);
          if (!handshake) {
            if (bytes.length < 4) return;
            if (bytes[0] != 0x7f || (bytes[1] & 15) != 5) {
              throw StateError('Incorrect FlatBuffers negotiation');
            }
            socket.add([0x7f, bytes[1], 0, 0]);
            bytes = Uint8List.sublistView(bytes, 4);
            handshake = true;
          }
          while (bytes.length >= 4) {
            final length = (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
            if (bytes.length < 4 + length) return;
            final message = codec.deserialize(
              Uint8List.sublistView(bytes, 4, 4 + length),
            )!;
            bytes = Uint8List.sublistView(bytes, 4 + length);
            codes.add(message.id);
            // A deliberately unacknowledged challenge cannot establish a profile.
            if (scenario != 'missing-challenge' || message is Hello) {
              profile = profile.acceptIncoming(message);
            }
            if (message is Hello) {
              if (scenario == 'anonymous' || scenario == 'ppt-echo') {
                write(Welcome(42, Details.forWelcome()));
              } else {
                write(
                  Challenge('ticket', Extra()),
                  acknowledge: scenario != 'missing-challenge',
                );
              }
            } else if (message is Authenticate) {
              write(
                Welcome(42, Details.forWelcome()),
                acknowledge: scenario != 'missing-welcome',
              );
            } else if (message is Call) {
              if (scenario == 'ppt-echo') {
                final result = Result(
                  message.requestId,
                  ResultDetails(
                    pptScheme: message.options?.pptScheme,
                    pptSerializer: message.options?.pptSerializer,
                    pptCipher: message.options?.pptCipher,
                    pptKeyId: message.options?.pptKeyId,
                  ),
                  arguments: message.arguments,
                  argumentsKeywords: message.argumentsKeywords,
                )..transparentBinaryPayload = message.transparentBinaryPayload;
                write(result);
              } else {
                write(
                  Result(
                    message.requestId,
                    ResultDetails(),
                    arguments: message.arguments,
                  ),
                );
              }
            } else if (message is Goodbye) {
              write(Goodbye(null, 'wamp.close.goodbye_and_out'));
            }
          }
        } catch (error) {
          send.send({'type': 'error', 'error': error.toString()});
        }
      },
      onError: (Object error) =>
          send.send({'type': 'error', 'error': error.toString()}),
    );
  });
  send.send({
    'type': 'ready',
    'port': server.port,
    'control': control.sendPort,
  });
}
