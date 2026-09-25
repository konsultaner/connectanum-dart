@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_client/src/transport/native/message_binding.dart'
    show materializeSessionMessage;
import 'package:connectanum_client/src/transport/native/runtime.dart' as client;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_router/src/native/ffi_bindings.dart'
    show CtFfiBindings, CtMessageInfo;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:ffi/ffi.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

import '../support/native_lib.dart';

void main() {
  final path = resolveOrBuildNativeLib();
  final fields = <(int, String, bool? Function(AbstractMessage))>[
    (16, 'acknowledge', (m) => (m as Publish).options?.acknowledge),
    (16, 'exclude_me', (m) => (m as Publish).options?.excludeMe),
    (16, 'disclose_me', (m) => (m as Publish).options?.discloseMe),
    (16, 'retain', (m) => (m as Publish).options?.retain),
    (32, 'get_retained', (m) => (m as Subscribe).options?.getRetained),
    (48, 'progress', (m) => (m as Call).options?.progress),
    (48, 'receive_progress', (m) => (m as Call).options?.receiveProgress),
    (48, 'disclose_me', (m) => (m as Call).options?.discloseMe),
    (64, 'disclose_caller', (m) => (m as Register).options?.discloseCaller),
    (64, 'forward_timeout', (m) => (m as Register).options?.forwardTimeout),
    (50, 'progress', (m) => (m as Result).details.progress),
    (68, 'progress', (m) => (m as Invocation).details.progress),
    (68, 'receive_progress', (m) => (m as Invocation).details.receiveProgress),
    (70, 'progress', (m) => (m as Yield).options?.progress),
  ];
  for (final serializer in [
    NativeMessageSerializer.json,
    NativeMessageSerializer.messagePack,
    NativeMessageSerializer.cbor,
  ]) {
    for (final (code, key, read) in fields) {
      for (final value in [null, false, true]) {
        test('${serializer.name} code=$code $key=$value survives native binding '
            'and handle release', () {
          final runtime = NativeTransportRuntime(libraryPath: path);
          addTearDown(() {
            runtime.shutdown();
            runtime.dispose();
          });
          runtime.start();
          final details = <String, Object?>{
            key: ?value,
            'trace': {
              'nested': [false, null, 17],
            },
          };
          final payload = <Object?>[
            ['argument', 17],
            {'key': 'value'},
          ];
          final wire = <Object?>[
            code,
            41,
            if (code == 68) 62,
            details,
            if ([16, 32, 48, 64].contains(code)) 'com.test',
            if (![32, 64].contains(code)) ...payload,
          ];
          final handle = runtime.enqueueTestMessage(
            connectionId: 9717,
            serializer: serializer,
            frame: _encode(serializer, wire),
          );
          late AbstractMessage message;
          if (code == 50 || code == 68) {
            final consumer = client.NativeClientRuntime.instance(
              libraryPath: path,
            );
            addTearDown(consumer.shutdown);
            final incoming = consumer.materialize(handle);
            message = materializeSessionMessage(incoming.message);
            incoming.release();
          } else {
            final incoming = NativeMessageHandleDecoder(
              libraryPath: path,
            ).materialize(handle);
            message = incoming.message;
            incoming.dispose();
          }
          // Read lazy metadata and payload only after the explicit owner is released.
          expect(read(message), code == 70 ? value ?? false : value);
          final custom = switch (message) {
            Publish m => m.options!.custom,
            Subscribe m => m.options!.custom,
            Call m => m.options!.custom,
            Register m => m.options!.custom,
            Result m => m.details.custom,
            Invocation m => m.details.custom,
            Yield m => m.options!.custom,
            _ => throw StateError('Unexpected test message'),
          };
          expect(custom['trace'], {
            'nested': [false, null, 17],
          });
          if (message is AbstractMessageWithPayload) {
            expect(message.arguments, payload[0]);
            expect(message.argumentsKeywords, payload[1]);
          }
        }, skip: path == null ? 'Native library unavailable' : null);
      }
    }

    test(
      '${serializer.name} false fallback retains zero-copy payload metadata',
      () {
        final runtime = NativeTransportRuntime(libraryPath: path);
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });
        runtime.start();
        final decoder = NativeMessageHandleDecoder(libraryPath: path);
        final bindings = CtFfiBindings(ffi.DynamicLibrary.open(path!));
        final info = calloc<CtMessageInfo>();
        addTearDown(() => calloc.free(info));
        final handle = runtime.enqueueTestMessage(
          connectionId: 9718,
          serializer: serializer,
          frame: _encode(serializer, [
            48,
            41,
            {'receive_progress': false},
            'com.test',
            [17],
            {'key': 'value'},
          ]),
        );
        addTearDown(() => decoder.release(handle));
        expect(bindings.ctMessagePeek(handle, info), 0);
        expect(
          info.ref.flags & 1,
          0,
          reason: 'false cannot use a true-only direct flag',
        );
        expect(
          info.ref.flags & 16,
          16,
          reason: 'metadata fallback must remain available',
        );
        expect(
          info.ref.framePtr,
          ffi.nullptr,
          reason: 'peek must not flatten the frame',
        );
        expect(info.ref.frameLen, 0);
        expect(info.ref.argsLen, greaterThan(0));
        expect(info.ref.kwargsLen, greaterThan(0));
        expect(info.ref.detailsLen, greaterThan(0));
        expect(
          info.ref.argsPtr.asTypedList(info.ref.argsLen),
          _encode(serializer, [17]),
        );
        expect(
          info.ref.kwargsPtr.asTypedList(info.ref.kwargsLen),
          _encode(serializer, {'key': 'value'}),
        );
        expect(
          info.ref.detailsPtr.asTypedList(info.ref.detailsLen),
          _encode(serializer, {'receive_progress': false}),
        );
      },
      skip: path == null ? 'Native library unavailable' : null,
    );
  }
}

Uint8List _encode(NativeMessageSerializer serializer, Object value) =>
    switch (serializer) {
      NativeMessageSerializer.json => Uint8List.fromList(
        utf8.encode(jsonEncode(value)),
      ),
      NativeMessageSerializer.messagePack => msgpack.serialize(value),
      NativeMessageSerializer.cbor => Uint8List.fromList(
        cbor.cbor.encode(cbor.CborValue(value)),
      ),
      _ => throw StateError('Unsupported test serializer'),
    };
