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

  Call rawCall(
    Uint8List bytes, {
    bool eager = false,
    int flags = 17,
    String scheme = 'x_test',
    String serializer = 'flatbuffers',
    String? cipher,
    String? key,
  }) {
    final value =
        bindMessageFromMetadata(
              NativeMessageSerializer.flatbuffers,
              messageCode: 48,
              primaryId: 17,
              secondaryId: 0,
              detailNumberA: 123,
              flags: flags,
              detailsBytes: bytes,
              stringA: 'com.target',
              stringB: scheme,
              stringC: serializer,
              stringD: cipher,
              stringE: key,
              argsBytes: Uint8List.fromList([0xff]),
              kwargsBytes: Uint8List.fromList([0xff]),
              retainFlatBufferMetadata: !eager,
            )!
            as Call;
    if (eager) codec.retainMetadata(value, bytes);
    return value;
  }

  Uint8List dictionary(Map<String, Object?> value) => Uint8List.fromList(
    cbor.cbor.encode(cbor.CborValue(value)),
  ).asUnmodifiableView();

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
  test('known CALL metadata supports either key order and ASCII widths', () {
    for (final length in [0, 1, 23, 24, 25, 255, 256, 65535, 65536]) {
      final scheme = 'a' * length;
      for (final reversed in [false, true]) {
        final bytes = dictionary(
          reversed
              ? {'ppt_serializer': 'flatbuffers', 'ppt_scheme': scheme}
              : {'ppt_scheme': scheme, 'ppt_serializer': 'flatbuffers'},
        );
        final value = rawCall(bytes, scheme: scheme);
        expect(
          (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
          length > 65535,
        );
        expect(codec.metadataFor(value), {
          'ppt_scheme': scheme,
          'ppt_serializer': 'flatbuffers',
        });
        expect(value.debugEncodedArgumentsBytes, [0xff]);
        expect(value.debugEncodedArgumentsKeywordsBytes, [0xff]);
      }
    }
  });
  test(
    'known CALL metadata matches readonly subviews and nonminimal text lengths',
    () {
      final original = dictionary(ppt);
      for (var offset = 0; offset < 8; offset++) {
        final backing = Uint8List(original.length + offset + 7)
          ..fillRange(0, original.length + offset + 7, 255)
          ..setRange(offset, offset + original.length, original);
        final value = rawCall(
          Uint8List.sublistView(
            backing,
            offset,
            offset + original.length,
          ).asUnmodifiableView(),
        );
        expect(
          (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
          isFalse,
        );
        expect(codec.metadataFor(value), ppt);
      }
      List<int> text(String value, int width) => [
        if (width == 1) ...[
          0x78,
          value.length,
        ] else if (width == 2) ...[
          0x79,
          0,
          value.length,
        ] else ...[
          0x7a,
          0,
          0,
          0,
          value.length,
        ],
        ...value.codeUnits,
      ];
      for (final width in [1, 2, 4]) {
        final encoded = Uint8List.fromList([
          0xa2,
          ...text('ppt_scheme', width),
          ...text('x_test', width),
          ...text('ppt_serializer', width),
          ...text('flatbuffers', width),
        ]);
        expect(codec.deserializeMetadata(encoded), ppt);
        final value = rawCall(encoded);
        expect(
          (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
          width == 4,
        );
        expect(codec.metadataFor(value), ppt);
      }
      for (final bytes in [
        Uint8List.fromList([0xb8, 2, ...original.skip(1)]),
        Uint8List.fromList([0xbf, ...original.skip(1), 0xff]),
      ]) {
        final value = rawCall(bytes);
        expect(
          (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
          isTrue,
        );
        expect(codec.metadataFor(value), ppt);
      }
    },
  );
  test('incomplete extended text lengths keep immediate rejection', () {
    final key = cbor.cbor.encode(cbor.CborValue('ppt_scheme'));
    for (final suffix in [
      [0x78],
      [0x79],
      [0x79, 0],
      [0x7a],
      [0x7b],
    ]) {
      expect(
        () => rawCall(Uint8List.fromList([0xa2, ...suffix])),
        throwsFormatException,
      );
      expect(
        () => rawCall(Uint8List.fromList([0xa2, ...key, ...suffix])),
        throwsFormatException,
      );
    }
    final oversized = Uint8List(1048577)
      ..setRange(0, dictionary(ppt).length, dictionary(ppt));
    expect(() => rawCall(oversized), throwsFormatException);
  });

  test('known CALL metadata keeps all edits before first resend', () {
    for (final edit in [
      'timeout',
      'false',
      'clear scheme',
      'custom override',
      'transaction hash',
      'replace root',
    ]) {
      Map<String, dynamic> edited(bool eager) {
        final value = rawCall(dictionary(ppt), eager: eager);
        switch (edit) {
          case 'timeout':
            value.options!.timeout = 456;
          case 'false':
            value.options!.receiveProgress = false;
          case 'clear scheme':
            value.options!.pptScheme = null;
          case 'custom override':
            value.options!.custom['ppt_scheme'] = 'x_custom';
          case 'transaction hash':
            value.options!.transactionHash = 'tx-17';
          case 'replace root':
            value.options = CallOptions(custom: {'x_new': true});
        }
        return codec.metadataFor(value);
      }

      expect(edited(false), edited(true), reason: edit);
    }
  });
  test('other CALL controls keep the retained dictionary', () {
    final bytes = dictionary(ppt);
    for (final flag in [2, 8, 32, 64]) {
      final value = rawCall(bytes, flags: 17 | flag);
      expect(
        (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
        isTrue,
      );
      expect(
        codec.metadataFor(value),
        codec.metadataFor(rawCall(bytes, flags: 17 | flag, eager: true)),
      );
    }
    for (final cipher in [false, true]) {
      final value = rawCall(
        bytes,
        cipher: cipher ? 'x_cipher' : null,
        key: cipher ? null : 'key',
      );
      expect(
        (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
        isTrue,
      );
      expect(codec.metadataFor(value), ppt);
    }
    for (final changed in ['scheme', 'serializer']) {
      final value = rawCall(
        bytes,
        scheme: changed == 'scheme' ? 'x_other' : 'x_test',
        serializer: changed == 'serializer' ? 'cbor' : 'flatbuffers',
      );
      expect(
        (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
        isTrue,
      );
      expect(codec.metadataFor(value), ppt);
    }
  });
  test('canonical fast path never accepts matching invalid Latin1 UTF8', () {
    final key = 'ppt_scheme'.codeUnits;
    final tail = cbor.cbor.encode(cbor.CborValue('ppt_serializer'));
    final serializer = cbor.cbor.encode(cbor.CborValue('flatbuffers'));
    for (final byte in [128, 191, 192, 233, 255]) {
      final bytes = Uint8List.fromList([
        0xa2,
        0x6a,
        ...key,
        0x63,
        120,
        95,
        byte,
        ...tail,
        ...serializer,
      ]);
      expect(
        () => rawCall(bytes, scheme: String.fromCharCodes([120, 95, byte])),
        throwsFormatException,
      );
    }
    final value = rawCall(
      dictionary({'ppt_scheme': 'x_é', 'ppt_serializer': 'flatbuffers'}),
      scheme: 'x_é',
    );
    expect(
      (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
      isTrue,
    );
    expect(codec.metadataFor(value)['ppt_scheme'], 'x_é');
  });
  test(
    'canonical fast path rejects every incomplete prefix and trailing data',
    () {
      final bytes = dictionary(ppt);
      for (var end = 0; end < bytes.length; end++) {
        expect(
          () => rawCall(Uint8List.sublistView(bytes, 0, end)),
          throwsFormatException,
          reason: 'prefix $end',
        );
      }
      expect(
        () => rawCall(Uint8List.fromList([...bytes, 0])),
        throwsFormatException,
      );
      final key = cbor.cbor.encode(cbor.CborValue('ppt_scheme'));
      final value = cbor.cbor.encode(cbor.CborValue('x_test'));
      expect(
        () => rawCall(
          Uint8List.fromList([0xa2, ...key, ...value, ...key, ...value]),
        ),
        throwsFormatException,
      );
    },
  );
  test('canonical-looking tagged invalid date still rejects immediately', () {
    final key = cbor.cbor.encode(cbor.CborValue('ppt_scheme'));
    final tail = cbor.cbor.encode(cbor.CborValue('ppt_serializer'));
    final serializer = cbor.cbor.encode(cbor.CborValue('flatbuffers'));
    expect(
      () => rawCall(
        Uint8List.fromList([
          0xa2,
          ...key,
          0xc0,
          0x61,
          0x78,
          ...tail,
          ...serializer,
        ]),
        scheme: 'x',
      ),
      throwsFormatException,
    );
  });
  test(
    'mutated native CALL dictionaries agree with eager error phases and values',
    () {
      final original = dictionary(ppt);
      Object outcome(Uint8List bytes, bool eager) {
        Call value;
        try {
          value = rawCall(bytes, eager: eager);
        } catch (error) {
          return ('ingest', error.runtimeType);
        }
        try {
          value.options!.timeout = 456;
          value.options!.custom['x_added'] = 42;
          return codec.metadataFor(value);
        } catch (error) {
          return ('resend', error.runtimeType);
        }
      }

      for (var offset = 0; offset < original.length; offset++) {
        for (final byte in [
          0,
          0x1f,
          0x20,
          0x3f,
          0x5f,
          0x60,
          0x7f,
          0x80,
          0xbf,
          0xc0,
          0xdf,
          0xe0,
          0xff,
        ]) {
          final changed = Uint8List.fromList(original)..[offset] = byte;
          expect(
            outcome(changed, false),
            outcome(changed, true),
            reason: 'offset $offset byte $byte',
          );
        }
      }
    },
  );

  test('transaction hash metadata keeps its custom loader and value', () {
    final bytes = dictionary({
      ...ppt,
      CallOptions.transactionHashWireField: 'tx-17',
    });
    final value = rawCall(bytes);
    expect(
      (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
      isTrue,
    );
    expect(value.options!.transactionHash, 'tx-17');
    expect(
      codec.metadataFor(value),
      codec.metadataFor(rawCall(bytes, eager: true)),
    );
  });

  test('known-only native CALL has no unresolved custom dictionary', () {
    final value = bind(48, ppt) as Call;
    expect(
      (value.options!.custom as LazyStringKeyMap).hasPendingLoader,
      isFalse,
    );
    expect(value.options!.transactionHash, isNull);
    value.options!.custom['x_added'] = 42;
    value.options!.pptScheme = 'x_changed';
    expect(codec.metadataFor(value), {
      'ppt_scheme': 'x_changed',
      'ppt_serializer': 'flatbuffers',
      'x_added': 42,
    });
  });

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
