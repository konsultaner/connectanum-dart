import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_client/src/transport/native/message_binding.dart'
    as client;
import 'package:connectanum_client/src/transport/native/message_protocol.dart'
    as protocol;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_core/src/serializer/flatbuffers/frame.dart'
    show readWampFlatBufferFrame;
import 'package:connectanum_router/src/native/ffi_bindings.dart' as router_ffi;
import 'package:connectanum_router/src/native/message_binding.dart' as router;
import 'package:connectanum_router/src/native/runtime.dart' as router_native;
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

const _dictionarySlots = {
  1: 2,
  2: 2,
  3: 1,
  4: 2,
  5: 2,
  6: 1,
  7: 1,
  8: 3,
  16: 2,
  32: 2,
  35: 2,
  36: 3,
  48: 2,
  49: 2,
  50: 2,
  64: 2,
  67: 2,
  68: 3,
  69: 2,
  70: 2,
};
const _clientMetadataKinds = {
  2,
  3,
  4,
  6,
  7,
  8,
  17,
  33,
  35,
  36,
  50,
  65,
  67,
  68,
  69,
};
const _routerMetadataKinds = {
  1,
  3,
  5,
  6,
  7,
  8,
  16,
  32,
  34,
  35,
  48,
  49,
  64,
  66,
  69,
  70,
};

/// Exercise the real C ABI between the native parser and both Dart consumers.
/// JSON model equality alone cannot detect lost closing/revocation dictionaries.
void flatbuffersMessageBindingContracts(ffi.DynamicLibrary? library) {
  final available =
      library?.providesSymbol('ct_test_message_enqueue_wide') ?? false;
  final file = [
    File('schemas/wamp_flatbuffers/codec_cases.json'),
    File('../../schemas/wamp_flatbuffers/codec_cases.json'),
  ].firstWhere((f) => f.existsSync());
  final cases = (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  cases.add({
    'name': 'call_large_payload',
    'message': [
      48,
      79,
      {'x_vendor': 'call'},
      'com.proc',
      [
        9007199254740992,
        {'nested': 9007199254740992},
        '\u0000AQID',
      ],
      {'value': 9007199254740992},
    ],
  });
  final codec = flat.Serializer();
  final jsonCodec = json.Serializer();
  group('FlatBuffers native dictionary and lazy payload binding', () {
    late router_ffi.CtFfiBindings bindings;
    setUp(() {
      bindings = router_ffi.CtFfiBindings(library!);
      expect(bindings.ctStartRuntime(), 0);
    });
    tearDown(() => bindings.ctShutdown());
    for (final entry in cases) {
      for (final consumer in ['client', 'router']) {
        for (final metadataOnly in [false, true]) {
          final fields = entry['message'] as List;
          final code = fields.first as int;
          if (metadataOnly &&
              !(consumer == 'client'
                      ? _clientMetadataKinds
                      : _routerMetadataKinds)
                  .contains(code)) {
            continue;
          }
          test('${entry['name']} $consumer metadataOnly=$metadataOnly', () {
            final model = code == 7
                ? core.Heartbeat(ping: 0, incoming: 0, outgoing: 0)
                : jsonCodec.deserialize(
                    Uint8List.fromList(utf8.encode(jsonEncode(fields))),
                  )!;
            final slot = _dictionarySlots[code];
            if (slot != null) {
              // Preserve the complete protocol dictionary from the independent
              // fixture, including fields absent from a public Dart model.
              codec.retainMetadata(
                model,
                Uint8List.fromList(
                  cbor.cbor.encode(cbor.CborValue(fields[slot])),
                ),
              );
            }
            final frame = codec.serialize(model);
            final reference = codec.deserialize(frame)!;
            final input = calloc<ffi.Uint8>(frame.length);
            final info = calloc<router_ffi.CtMessageInfo>();
            int? handle;
            try {
              input.asTypedList(frame.length).setAll(0, frame);
              handle = bindings.ctTestMessageEnqueue!(
                11791,
                5,
                input,
                frame.length,
              );
              expect(handle, greaterThan(0));
              expect(bindings.ctMessageGet(handle, info), 0);
              final value = info.ref;
              Uint8List? view(ffi.Pointer<ffi.Uint8> p, int length) =>
                  p.address == 0 ? null : p.asTypedList(length);
              String? string(ffi.Pointer<ffi.Uint8> p, int length) =>
                  p.address == 0 ? null : utf8.decode(p.asTypedList(length));
              final args = view(value.argsPtr, value.argsLen);
              final kwargs = view(value.kwargsPtr, value.kwargsLen);
              final details = view(value.detailsPtr, value.detailsLen);
              final metadata = protocol.NativeMessageMetadata(
                messageCode: value.messageCode,
                primaryId: value.primaryId,
                secondaryId: value.secondaryId,
                detailNumberA: value.detailNumberA,
                detailNumberB: value.detailNumberB,
                flags: value.flags,
                detailsBytes: details,
                stringA: string(value.stringAPtr, value.stringALen),
                stringB: string(value.stringBPtr, value.stringBLen),
                stringC: string(value.stringCPtr, value.stringCLen),
                stringD: string(value.stringDPtr, value.stringDLen),
                stringE: string(value.stringEPtr, value.stringELen),
              );
              if (metadataOnly) {
                expect(
                  metadata.hasFlag(
                    protocol.NativeMessageMetadata.flagMetadataBind,
                  ),
                  isTrue,
                );
              }
              final fullFrame = metadataOnly
                  ? Uint8List(0)
                  : value.framePtr.asTypedList(value.frameLen);
              final bound = consumer == 'client'
                  ? client.materializeSessionMessage(
                      client.bindSessionMessage(
                        protocol.NativeMessageSerializer.flatbuffers,
                        fullFrame,
                        argsBytes: args,
                        kwargsBytes: kwargs,
                        metadata: metadata,
                      ),
                    )
                  : router.bindMessage(
                      router_native.NativeMessageSerializer.flatbuffers,
                      fullFrame,
                      argsBytes: args,
                      kwargsBytes: kwargs,
                      metadataMessageCode: metadata.messageCode,
                      metadataPrimaryId: metadata.primaryId,
                      metadataSecondaryId: metadata.secondaryId,
                      metadataDetailNumberA: metadata.detailNumberA,
                      metadataFlags: metadata.flags,
                      metadataDetailsBytes: metadata.detailsBytes,
                      metadataStringA: metadata.stringA,
                      metadataStringB: metadata.stringB,
                      metadataStringC: metadata.stringC,
                      metadataStringD: metadata.stringD,
                      metadataStringE: metadata.stringE,
                    );
              if (bound is core.AbstractMessageWithPayload) {
                expect(
                  identical(bound.debugEncodedArgumentsBytes, args),
                  isTrue,
                );
                expect(
                  identical(bound.debugEncodedArgumentsKeywordsBytes, kwargs),
                  isTrue,
                );
              }
              Object? canonical(core.AbstractMessage m) => m is core.Heartbeat
                  ? {
                      'ping': m.ping,
                      'incoming': m.incoming,
                      'outgoing': m.outgoing,
                      'details': m.details,
                    }
                  : jsonDecode(jsonCodec.serialize(m));
              expect(canonical(bound), canonical(reference));
              expect(
                readWampFlatBufferFrame(codec.serialize(bound)).dictionary,
                readWampFlatBufferFrame(frame).dictionary,
              );
              // Repeated retention on the actual returned instance must not
              // duplicate extensions on the materialized message identity.
              if (details != null && code != 7) {
                codec.retainMetadata(bound, details);
                codec.retainMetadata(bound, details);
                expect(
                  readWampFlatBufferFrame(codec.serialize(bound)).dictionary,
                  readWampFlatBufferFrame(frame).dictionary,
                );
              }
              if (bound is core.Call) {
                bound.options!.timeout = 321;
                final changed = readWampFlatBufferFrame(
                  codec.serialize(bound),
                ).dictionary!;
                expect(changed['timeout'], 321);
                expect(changed['x_vendor'], 'call');
              }
            } finally {
              if (handle != null && handle > 0) {
                bindings.ctMessageRelease(handle);
              }
              calloc.free(info);
              calloc.free(input);
            }
          });
        }
      }
    }
  }, skip: available ? false : 'Requires current ffi-test native library');
}
