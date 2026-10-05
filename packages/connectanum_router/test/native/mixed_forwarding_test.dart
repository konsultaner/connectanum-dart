@TestOn('vm')
library;

import 'dart:ffi' as ffi;
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:connectanum_router/src/native/ffi_bindings.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

import '../support/native_lib.dart';

void main() {
  final path = resolveOrBuildNativeLib();
  final skip = path == null ? 'native library unavailable' : false;
  final codecs = <NativeMessageSerializer, AbstractSerializer>{
    NativeMessageSerializer.json: json.Serializer(),
    NativeMessageSerializer.messagePack: msgpack.Serializer(),
    NativeMessageSerializer.cbor: cbor.Serializer(),
    NativeMessageSerializer.flatbuffers: flat.Serializer(),
  };
  for (final source in codecs.keys) {
    test('native mixed eligibility $source retains lazy arguments', () {
      final runtime = NativeTransportRuntime(libraryPath: path!);
      addTearDown(runtime.dispose);
      runtime.start();
      addTearDown(runtime.shutdown);
      final decoder = NativeMessageHandleDecoder(libraryPath: path);
      final binary = Uint8List.fromList(List.generate(65536, (i) => i & 255));
      final encoded = codecs[source]!.serialize(
        Call(
          7,
          'com.mixed',
          arguments: [binary],
          argumentsKeywords: {'label': 'untouched'},
        ),
      );
      final handle = runtime.enqueueTestMessage(
        connectionId: 7101,
        serializer: source,
        frame: encoded is String
            ? Uint8List.fromList(utf8.encode(encoded))
            : encoded as Uint8List,
      );
      final incoming = decoder.materialize(handle);
      addTearDown(incoming.dispose);
      final call = incoming.message as Call;
      expect(call.debugEncodedArgumentsBytes, same(incoming.argumentsBytes));
      expect(incoming.bytes, isEmpty);
      for (final target in codecs.keys) {
        final sharedCbor =
            (source == NativeMessageSerializer.cbor &&
                target == NativeMessageSerializer.flatbuffers) ||
            (source == NativeMessageSerializer.flatbuffers &&
                target == NativeMessageSerializer.cbor);
        expect(incoming.canForwardTo(target), source == target || sharedCbor);
        expect(call.debugEncodedArgumentsBytes, same(incoming.argumentsBytes));
      }
      expect(call.arguments, [binary]);
      expect(call.argumentsKeywords, {'label': 'untouched'});
      incoming.dispose();
      expect(incoming.canForwardTo(source), isFalse);
    }, skip: skip);
  }
  test('older native library keeps homogeneous-only forwarding', () {
    final legacyPath = resolveOrBuildLegacyMessageHandleNativeLib();
    expect(legacyPath, isNotNull);
    final bindings = CtFfiBindings(ffi.DynamicLibrary.open(legacyPath!));
    expect(bindings.ctMessageCanForwardToV1, isNull);
    final incoming = NativeIncomingMessage.test(
      serializer: NativeMessageSerializer.cbor,
      message: Call(7, 'com.legacy'),
      handle: 7,
    );
    addTearDown(incoming.dispose);
    expect(incoming.canForwardTo(NativeMessageSerializer.cbor), isTrue);
    expect(incoming.canForwardTo(NativeMessageSerializer.flatbuffers), isFalse);
  }, skip: skip);
}
