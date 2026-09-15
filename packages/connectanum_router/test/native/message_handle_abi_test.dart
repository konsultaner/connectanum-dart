@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/native_message_bytes.dart';
import 'package:connectanum_client/native_message_handles.dart';
import 'package:connectanum_client/src/transport/native/ffi_bindings.dart'
    as client;
import 'package:connectanum_router/src/native/ffi_bindings.dart' as router;
import 'package:ffi/ffi.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

import '../support/native_lib.dart';

typedef _EnqueueNative =
    ffi.Int64 Function(ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef _EnqueueDart = int Function(int, int, ffi.Pointer<ffi.Uint8>, int);
typedef _GetNative =
    ffi.Int32 Function(ffi.Int64, ffi.Pointer<router.CtMessageInfo>);
typedef _ReleaseNative = ffi.Void Function(ffi.Int64);

void main() {
  final path = resolveOrBuildNativeLib();
  final library = path == null ? null : ffi.DynamicLibrary.open(path);
  final wide = library?.providesSymbol('ct_test_message_enqueue_wide') ?? false;

  test('client, router and exporter select the same complete family', () {
    final expected = NativeMessageHandleAbi.detect(library!);
    expect(client.CtFfiBindings(library).messageHandleAbi, expected);
    expect(router.CtFfiBindings(library).messageHandleAbi, expected);
    expect(NativeMessageBytes(library).messageHandleAbi, expected);
  }, skip: library == null ? 'Native library unavailable' : false);

  for (final version in [1, 2]) {
    test(
      'invalid advertised ABI $version rejects before unrelated lookups',
      () {
        final fixture = [
          File('test/fixtures/message_abi_incomplete.c'),
          File(
            'packages/connectanum_router/test/fixtures/message_abi_incomplete.c',
          ),
        ].firstWhere((file) => file.existsSync());
        final directory = Directory.systemTemp.createTempSync(
          'connectanum-abi-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final output =
            '${directory.path}/fixture.${Platform.isMacOS ? 'dylib' : 'so'}';
        final build = Process.runSync('cc', [
          if (Platform.isMacOS) '-dynamiclib' else '-shared',
          '-fPIC',
          '-DABI_VERSION=$version',
          fixture.path,
          '-o',
          output,
        ]);
        expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
        final incomplete = ffi.DynamicLibrary.open(output);
        expect(
          () => NativeMessageHandleAbi.detect(incomplete),
          throwsUnsupportedError,
        );
        expect(() => client.CtFfiBindings(incomplete), throwsUnsupportedError);
        expect(() => router.CtFfiBindings(incomplete), throwsUnsupportedError);
        expect(() => NativeMessageBytes(incomplete), throwsUnsupportedError);
      },
      skip: Platform.isMacOS || Platform.isLinux
          ? false
          : 'Native runtime platform only',
    );
  }

  test(
    'legacy callbacks reject aliasing before the Int32 FFI boundary',
    () {
      final r = router.CtFfiBindings(library!);
      final c = client.CtFfiBindings(library);
      expect(r.ctStartRuntime(), 0);
      addTearDown(() => r.ctShutdown());
      final encoded = utf8.encode('[50,97,{},["legacy"]]');
      final frame = calloc<ffi.Uint8>(encoded.length);
      addTearDown(() => calloc.free(frame));
      frame.asTypedList(encoded.length).setAll(0, encoded);
      final handle = r.ctTestMessageEnqueue!(
        11982,
        1,
        frame,
        encoded.length,
      );
      expect(handle, inInclusiveRange(1, 0x7fffffff));
      final alias = handle + 0x100000000;
      final info = calloc<router.CtMessageInfo>();
      final clientInfo = calloc<client.CtMessageInfo>();
      addTearDown(() => calloc.free(info));
      addTearDown(() => calloc.free(clientInfo));
      final rawGet = library
          .lookupFunction<router.CtMessageGetNative, router.CtMessageGetDart>(
            'ct_message_get',
          );
      // This controlled live allocation proves the old unguarded FFI truncates.
      expect(rawGet(alias, info), 0);
      expect(info.ref.primaryId, 97);
      final callbacks = <String, void Function(int)>{
        'client get': (h) => c.ctMessageGet(h, clientInfo),
        'client peek': (h) => c.ctMessagePeek(h, clientInfo),
        'client retain': (h) => c.ctMessageRetain(h),
        'client release': (h) => c.ctMessageRelease(h),
        'client binary': (h) =>
            c.ctMessageDecodeSingleBinaryArgument(h, ffi.nullptr),
        'client hash': (h) => c.ctSha256UpdateMessageBinaryArgument(1, h),
        'client decrypt': (h) =>
            c.ctE2eeSessionDecryptMessageSingleBinaryArgument(
              1,
              ffi.nullptr,
              0,
              h,
              0,
              ffi.nullptr,
            ),
        'client consume': (h) => c.ctE2eeSessionDecryptMessagePayloadConsume!(
          1,
          ffi.nullptr,
          0,
          h,
          0,
          ffi.nullptr,
          ffi.nullptr,
        ),
        'router get': (h) => r.ctMessageGet(h, info),
        'router peek': (h) => r.ctMessagePeek(h, info),
        'router retain': (h) => r.ctMessageRetain(h),
        'router release': (h) => r.ctMessageRelease(h),
        'event': (h) =>
            r.ctForwardPublishEvent(h, 0, 0, 0, 0, 0, ffi.nullptr, 0),
        'invocation': (h) => r.ctForwardCallInvocation(
          h,
          0,
          0,
          0,
          0,
          0,
          ffi.nullptr,
          0,
          ffi.nullptr,
          0,
          ffi.nullptr,
          0,
          0,
        ),
        'invocation v2': (h) => r.ctForwardCallInvocationV2(
          h,
          0,
          0,
          0,
          0,
          0,
          ffi.nullptr,
          0,
          ffi.nullptr,
          0,
          ffi.nullptr,
          0,
          0,
          0,
        ),
        'yield': (h) => r.ctForwardResultFromYield(h, 0, 0, 0),
        'call result': (h) => r.ctForwardResultFromCall(h, 0, 0),
        'error': (h) => r.ctForwardErrorFromError(h, 0, 0, 0),
      };
      for (final entry in callbacks.entries) {
        expect(() => entry.value(alias), throwsRangeError, reason: entry.key);
        expect(
          () => entry.value(-0x100000000 + handle),
          throwsRangeError,
          reason: entry.key,
        );
        expect(r.ctMessageGet(handle, info), 0, reason: entry.key);
      }
      final bytes = NativeMessageBytes(library);
      expect(
        () => bytes.read(
          alias,
          NativeMessageBytePart.frame,
          borrowed: info.ref.framePtr,
          length: info.ref.frameLen,
        ),
        throwsRangeError,
      );
      expect(
        () => bytes.withCopiedBytes(
          alias,
          NativeMessageBytePart.frame,
          borrowed: info.ref.framePtr,
          length: info.ref.frameLen,
          consume: (value) => value,
        ),
        throwsRangeError,
      );
      r.ctMessageRelease(handle);
    },
    skip:
        library != null &&
            !library.providesSymbol('ct_message_handle_abi_version') &&
            library.providesSymbol('ct_test_message_enqueue')
        ? false
        : 'Requires a legacy native test library',
  );

  group('wide message handle bindings', () {
    late router.CtFfiBindings routerBindings;
    late client.CtFfiBindings clientBindings;
    late _EnqueueDart enqueue;
    late void Function(int) release;

    setUp(() {
      routerBindings = router.CtFfiBindings(library!);
      clientBindings = client.CtFfiBindings(library);
      enqueue = library.lookupFunction<_EnqueueNative, _EnqueueDart>(
        'ct_test_message_enqueue_wide',
      );
      release = library.lookupFunction<_ReleaseNative, void Function(int)>(
        'ct_message_release_wide',
      );
      expect(routerBindings.ctStartRuntime(), 0);
    });
    tearDown(() => routerBindings.ctShutdown());

    int seedBytes(List<int> encoded, {int serializer = 1}) {
      final pointer = calloc<ffi.Uint8>(encoded.length);
      try {
        pointer.asTypedList(encoded.length).setAll(0, encoded);
        final handle = enqueue(11981, serializer, pointer, encoded.length);
        expect(handle, greaterThan(0xffffffff));
        addTearDown(() => release(handle));
        return handle;
      } finally {
        calloc.free(pointer);
      }
    }

    int seed(String frame) => seedBytes(utf8.encode(frame));

    test('client get and retain preserve all handle bits', () {
      final handle = seed('[50,91,{},["payload"]]');
      final info = calloc<client.CtMessageInfo>();
      addTearDown(() => calloc.free(info));
      expect(clientBindings.ctMessageGet(handle, info), 0);
      expect(info.ref.primaryId, 91);
      final retained = clientBindings.ctMessageRetain(handle);
      expect(retained, greaterThan(handle));
      addTearDown(() => release(retained));
      clientBindings.ctMessageRelease(handle);
      expect(clientBindings.ctMessagePeek(retained, info), 0);
    });

    test('router get and retain preserve all handle bits', () {
      final handle = seed('[50,92,{},["payload"]]');
      final info = calloc<router.CtMessageInfo>();
      addTearDown(() => calloc.free(info));
      expect(routerBindings.ctMessageGet(handle, info), 0);
      expect(info.ref.primaryId, 92);
      final retained = routerBindings.ctMessageRetain(handle);
      expect(retained, greaterThan(handle));
      addTearDown(() => release(retained));
      routerBindings.ctMessageRelease(handle);
      expect(routerBindings.ctMessagePeek(retained, info), 0);
    });

    for (final isClient in [false, true]) {
      test(
        '${isClient ? 'client' : 'router'} poll preserves wide queue IDs',
        () {
          final handle = seed('[50,93,{},["payload"]]');
          final poll = isClient
              ? clientBindings.ctPollConnectionMessage
              : routerBindings.ctPollConnectionMessage;
          expect(poll(11981), handle);
        },
      );
    }

    test('shared byte exporter selects the same handle family', () {
      const frame = '[50,94,{},["payload"]]';
      final handle = seed(frame);
      final info = calloc<router.CtMessageInfo>();
      addTearDown(() => calloc.free(info));
      final get = library!.lookupFunction<_GetNative, router.CtMessageGetDart>(
        'ct_message_get_wide',
      );
      expect(get(handle, info), 0);
      final bytes = NativeMessageBytes(library).withCopiedBytes(
        handle,
        NativeMessageBytePart.frame,
        borrowed: info.ref.framePtr,
        length: info.ref.frameLen,
        consume: (bytes) => bytes,
      );
      release(handle);
      expect(utf8.decode(bytes), frame);
    });

    test('client binary decoder receives a full-width message handle', () {
      final handle = seed('[68,95,1,{},["\\u0000YWJj"]]');
      final out = calloc<client.CtExternalByteBuffer>();
      addTearDown(() => calloc.free(out));
      expect(
        clientBindings.ctMessageDecodeSingleBinaryArgument(handle, out),
        0,
      );
      try {
        expect(out.ref.ptr.asTypedList(out.ref.len), utf8.encode('abc'));
      } finally {
        clientBindings.ctExternalByteBufferFree(out.ref.owner);
      }
    });

    test('client SHA-256 receives a full-width message handle', () {
      final handle = seedBytes(
        msgpack.serialize([
          68,
          96,
          1,
          <String, Object?>{},
          [
            Uint8List.fromList([97, 98, 99]),
          ],
        ]),
        serializer: 2,
      );
      final hash = clientBindings.ctSha256New();
      expect(hash, greaterThan(0));
      addTearDown(() => clientBindings.ctSha256Release(hash));
      expect(
        clientBindings.ctSha256UpdateMessageBinaryArgument(hash, handle),
        3,
      );
      final digest = calloc<ffi.Uint8>(32);
      addTearDown(() => calloc.free(digest));
      expect(clientBindings.ctSha256Finalize(hash, digest, 32), 0);
      expect(
        digest
            .asTypedList(32)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    for (final cipher in [1, 2]) {
      test('client cipher $cipher decrypts and consumes full-width handles', () {
        final keyring = clientBindings.ctE2eeKeyringNew();
        expect(keyring, greaterThan(0));
        addTearDown(() => clientBindings.ctE2eeKeyringRelease(keyring));
        final keyId = 'file-key'.toNativeUtf8().cast<ffi.Char>();
        final key = calloc<ffi.Uint8>(32);
        addTearDown(() => calloc.free(keyId));
        addTearDown(() => calloc.free(key));
        key.asTypedList(32).setAll(0, List.generate(32, (i) => i + 1));
        expect(
          clientBindings.ctE2eeKeyringAddKey(keyring, keyId, 8, key, 32, 1),
          0,
        );
        final session = clientBindings.ctE2eeSessionNew(
          keyring,
          ffi.nullptr,
          0,
        );
        expect(session, greaterThan(0));
        addTearDown(() => clientBindings.ctE2eeSessionRelease(session));
        // CBOR {"args": [h'02030405'], "kwargs": null}, the standardized payload.
        final plaintext = <int>[
          0xa2,
          0x64,
          0x61,
          0x72,
          0x67,
          0x73,
          0x81,
          0x44,
          2,
          3,
          4,
          5,
          0x66,
          0x6b,
          0x77,
          0x61,
          0x72,
          0x67,
          0x73,
          0xf6,
        ];
        final input = calloc<ffi.Uint8>(plaintext.length);
        addTearDown(() => calloc.free(input));
        input.asTypedList(plaintext.length).setAll(0, plaintext);
        final encrypted = calloc<client.CtByteBuffer>();
        addTearDown(() => calloc.free(encrypted));
        final encrypt = cipher == 1
            ? clientBindings.ctE2eeSessionEncrypt
            : clientBindings.ctE2eeSessionEncryptAes256Gcm;
        expect(
          encrypt(session, keyId, 8, input, plaintext.length, encrypted),
          0,
        );
        late Uint8List ciphertext;
        try {
          ciphertext = Uint8List.fromList(
            encrypted.ref.ptr.asTypedList(encrypted.ref.len),
          );
        } finally {
          clientBindings.ctByteBufferFree(encrypted.ref.ptr, encrypted.ref.len);
        }
        final handle = seedBytes(
          msgpack.serialize([
            68,
            98,
            1,
            <String, Object?>{},
            [ciphertext],
          ]),
          serializer: 2,
        );
        final out = calloc<client.CtExternalByteBuffer>();
        final kind = calloc<ffi.Int32>();
        final info = calloc<client.CtMessageInfo>();
        addTearDown(() => calloc.free(out));
        addTearDown(() => calloc.free(kind));
        addTearDown(() => calloc.free(info));
        expect(
          clientBindings.ctE2eeSessionDecryptMessageSingleBinaryArgument(
            session,
            keyId,
            8,
            handle,
            cipher,
            out,
          ),
          0,
        );
        try {
          expect(out.ref.ptr.asTypedList(out.ref.len), [2, 3, 4, 5]);
        } finally {
          clientBindings.ctExternalByteBufferFree(out.ref.owner);
        }
        expect(clientBindings.ctMessagePeek(handle, info), 0);
        expect(
          clientBindings.ctE2eeSessionDecryptMessagePayloadConsume!(
            session,
            keyId,
            8,
            handle,
            cipher,
            out,
            kind,
          ),
          0,
        );
        try {
          expect(kind.value, 1);
          expect(clientBindings.ctMessageGet(handle, info), -4);
          expect(out.ref.ptr.asTypedList(out.ref.len), [2, 3, 4, 5]);
        } finally {
          clientBindings.ctExternalByteBufferFree(out.ref.owner);
        }
      });
    }
  }, skip: wide ? false : 'Requires the wide native test ABI');
}
