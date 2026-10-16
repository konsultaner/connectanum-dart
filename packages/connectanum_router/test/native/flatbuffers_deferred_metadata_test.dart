@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';
import 'package:connectanum_router/src/native/message_binding.dart';
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  final codec = flatbuffers.Serializer();
  AbstractMessage bind(
    int code,
    Map<String, Object?> dictionary, {
    bool eager = false,
    int extraFlags = 0,
    Uint8List? opaque,
  }) {
    final bytes = Uint8List.fromList(
      cbor.cbor.encode(cbor.CborValue(dictionary)),
    ).asUnmodifiableView();
    final result = bindMessageFromMetadata(
      NativeMessageSerializer.flatbuffers,
      messageCode: code,
      primaryId: 17,
      secondaryId: 0,
      detailNumberA: dictionary['timeout'] as int? ?? 0,
      flags:
          17 |
          extraFlags |
          (dictionary.containsKey('timeout') ? 2 : 0) |
          (opaque != null ? 256 : 0),
      detailsBytes: bytes,
      stringA: code == 70 ? 'x_test' : 'com.target',
      stringB: code == 70 ? 'flatbuffers' : 'x_test',
      stringC: code == 70 ? null : 'flatbuffers',
      transparentPayloadBytes: opaque,
      retainFlatBufferMetadata: !eager,
    )!;
    if (eager) codec.retainMetadata(result, bytes);
    return result;
  }

  const ppt = {'ppt_scheme': 'x_test', 'ppt_serializer': 'flatbuffers'};
  for (final code in [16, 48, 70]) {
    for (final edit in [
      'unchanged',
      'nested',
      'replace root',
      'clear custom',
      'set null',
      'change scheme',
    ]) {
      test(
        'native $code deferred metadata matches eager retention after $edit',
        () {
          final dictionary = <String, Object?>{
            ...ppt,
            'ppt_cipher': null,
            if (code == 48) 'timeout': 123,
            'x_vendor': {
              'nested': [1, 2],
              'binary': Uint8List.fromList([3, 4]),
            },
          };
          Map<String, dynamic> apply(bool eager) {
            final value = bind(code, dictionary, eager: eager);
            final PPTOptions options = switch (value) {
              Call() => value.options!,
              Publish() => value.options!,
              Yield() => value.options!,
              _ => throw StateError('unexpected message'),
            };
            final custom = switch (value) {
              Call() => value.options!.custom,
              Publish() => value.options!.custom,
              Yield() => value.options!.custom,
              _ => throw StateError('unexpected message'),
            };
            if (edit == 'nested') {
              ((custom['x_vendor'] as Map)['nested'] as List)[0] = 9;
              ((custom['x_vendor'] as Map)['binary'] as Uint8List)[1] = 8;
              if (value is Call) value.options!.timeout = 456;
            } else if (edit == 'replace root') {
              switch (value) {
                case Call():
                  value.options = CallOptions(
                    pptScheme: 'x_test',
                    pptSerializer: 'flatbuffers',
                  );
                case Publish():
                  value.options = PublishOptions(
                    pptScheme: 'x_test',
                    pptSerializer: 'flatbuffers',
                  );
                case Yield():
                  value.options = YieldOptions(
                    pptScheme: 'x_test',
                    pptSerializer: 'flatbuffers',
                  );
              }
            } else if (edit == 'clear custom') {
              custom.clear();
            } else if (edit == 'set null') {
              options.pptCipher = null;
            } else if (edit == 'change scheme') {
              options.pptScheme = 'x_changed';
            }
            return codec.metadataFor(value);
          }

          final expected = apply(true);
          final actual = apply(false);
          expect(actual, expected);
          if (edit == 'nested') {
            expect(actual['x_vendor'], {
              'nested': [9, 2],
              'binary': Uint8List.fromList([3, 8]),
            });
            if (code == 48) expect(actual['timeout'], 456);
          }
          if (edit == 'replace root' || edit == 'clear custom') {
            expect(actual.containsKey('x_vendor'), isFalse);
          }
          if (edit == 'unchanged') {
            expect(actual.containsKey('ppt_cipher'), isTrue);
          }
          if (edit == 'set null') {
            expect(actual.containsKey('ppt_cipher'), isTrue);
          }
        },
      );
    }
    test(
      'native $code opaque payload is excluded from the initial projection',
      () {
        final body = Uint8List.fromList([1, 2, 3]).asUnmodifiableView();
        final value =
            bind(code, {...ppt, 'x_vendor': 42}, opaque: body)
                as AbstractMessageWithPayload;
        expect(
          codec.metadataFor(value),
          codec.metadataFor(
            bind(code, {...ppt, 'x_vendor': 42}, eager: true, opaque: body),
          ),
        );
        expect(codec.metadataFor(value)['x_vendor'], 42);
        expect(value.transparentBinaryPayload, same(body));
        expect(codec.deserialize(codec.serialize(value))!.id, code);
      },
    );
    for (var combination = 0; combination < 32; combination++) {
      final flags = [2, 8, 32, 64, 128].asMap().entries.fold<int>(
        0,
        (v, e) => v | (combination & (1 << e.key) != 0 ? e.value : 0),
      );
      test(
        'native $code original flag combination $combination survives defer',
        () {
          final dictionary = <String, Object?>{
            ...ppt,
            if (code == 48 && flags & 2 != 0) 'timeout': 123,
            if (code == 48) 'receive_progress': flags & 8 != 0,
            if (code == 48 || code == 70)
              'progress': flags & (code == 48 ? 64 : 8) != 0,
            if (code == 16) 'acknowledge': flags & 8 != 0,
            if (code == 16) 'exclude_me': flags & 32 != 0,
            if (code == 16) 'retain': flags & 128 != 0,
            if (code != 70) 'disclose_me': flags & (code == 16 ? 64 : 32) != 0,
            'x_vendor': {'flag_index': combination},
          };
          expect(
            codec.metadataFor(bind(code, dictionary, extraFlags: flags)),
            codec.metadataFor(
              bind(code, dictionary, eager: true, extraFlags: flags),
            ),
          );
        },
      );
    }
    test('native $code rejects malformed metadata immediately', () {
      for (final bytes in [
        Uint8List.fromList([0x80]),
        Uint8List.fromList([0xa1]),
        Uint8List.fromList([0xa1, 1, 0]),
        Uint8List.fromList([0xa2, 0x61, 0x78, 1, 0x61, 0x78, 2]),
        Uint8List.fromList([0xa0, 0]),
        Uint8List(1048577),
      ]) {
        expect(
          () => bindMessageFromMetadata(
            NativeMessageSerializer.flatbuffers,
            messageCode: code,
            primaryId: 17,
            secondaryId: 0,
            detailNumberA: 0,
            flags: 17,
            detailsBytes: bytes,
            stringA: code == 70 ? 'x_test' : 'com.target',
          ),
          throwsFormatException,
        );
      }
    });
  }
  test(
    'explicit default assignment before first resend preserves presence',
    () {
      final value = bind(70, ppt) as Yield;
      expect(codec.metadataFor(value).containsKey('progress'), isFalse);
      final edited = bind(70, ppt) as Yield;
      edited.options!.progress = false;
      expect(codec.metadataFor(edited)['progress'], isFalse);
    },
  );
  for (final code in [16, 48, 70]) {
    test('native $code metadata stays encoded before a Dart resend', () {
      final bytes = Uint8List.fromList(
        cbor.cbor.encode(
          cbor.CborValue({
            'ppt_scheme': 'x_test',
            'ppt_serializer': 'flatbuffers',
            'x_future': Uint8List(4096),
          }),
        ),
      ).asUnmodifiableView();
      OwnedCopyMetrics.enable();
      final before = OwnedCopyMetrics.snapshot()!;
      final message = bindMessageFromMetadata(
        NativeMessageSerializer.flatbuffers,
        messageCode: code,
        primaryId: 17,
        secondaryId: 0,
        detailNumberA: 0,
        flags: 17,
        detailsBytes: bytes,
        stringA: code == 70 ? 'x_test' : 'com.target',
        stringB: code == 70 ? 'flatbuffers' : 'x_test',
        stringC: code == 70 ? null : 'flatbuffers',
        argsBytes: Uint8List.fromList([0xff]),
        kwargsBytes: Uint8List.fromList([0xff]),
      )!;
      final after = OwnedCopyMetrics.snapshot()!;
      expect(
        after['clone_copy_bytes']! - before['clone_copy_bytes']!,
        0,
        reason: 'Forwarding must not snapshot binary control metadata eagerly',
      );
      final payload = message as AbstractMessageWithPayload;
      expect(payload.debugEncodedArgumentsBytes, [0xff]);
      expect(payload.debugEncodedArgumentsKeywordsBytes, [0xff]);
      expect(
        codec.metadataFor(message)['x_future'],
        orderedEquals(Uint8List(4096)),
      );
      expect(payload.debugEncodedArgumentsBytes, [0xff]);
      expect(payload.debugEncodedArgumentsKeywordsBytes, [0xff]);
    });
  }
}
