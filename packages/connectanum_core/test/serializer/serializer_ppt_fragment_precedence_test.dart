import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

void main() {
  final harnesses = <_Harness>[
    _Harness(
      'json',
      json_serializer.Serializer(),
      (value) => Uint8List.fromList(utf8.encode(jsonEncode(value))),
      (bytes) => jsonDecode(utf8.decode(bytes)),
    ),
    _Harness(
      'msgpack',
      msgpack_serializer.Serializer(),
      msgpack.serialize,
      msgpack.deserialize,
    ),
    _Harness(
      'cbor',
      cbor_serializer.Serializer(),
      (value) => Uint8List.fromList(cbor.cbor.encode(cbor.CborValue(value))),
      (bytes) => cbor.cbor.decode(bytes).toObject(),
    ),
  ];
  const materializedArgs = <Object?>['fallback', 17];
  const materializedKwargs = <String, Object?>{'fallback': false};
  for (final harness in harnesses) {
    final argumentCases = <(String, Uint8List?, Object?)>[
      ('materialized', null, materializedArgs),
      ('null', harness.encode(null), null),
      ('empty list', harness.encode(<Object?>[]), <Object?>[]),
      (
        'values',
        harness.encode(['encoded', null, false]),
        ['encoded', null, false],
      ),
      (
        'nested',
        harness.encode([
          {
            'key': [13, 'text'],
          },
        ]),
        [
          {
            'key': [13, 'text'],
          },
        ],
      ),
    ];
    final keywordCases = <(String, Uint8List?, Object?)>[
      ('materialized', null, materializedKwargs),
      ('null', harness.encode(null), null),
      ('empty map', harness.encode(<String, Object?>{}), <String, Object?>{}),
      (
        'values',
        harness.encode({'encoded': 42, 'empty': null}),
        {'encoded': 42, 'empty': null},
      ),
      (
        'escaped',
        harness.encode({
          'key"\\\n\u00e4': [false],
        }),
        {
          'key"\\\n\u00e4': [false],
        },
      ),
    ];
    group('${harness.name} independent PPT fragment precedence', () {
      for (final (argName, argBytes, expectedArgs) in argumentCases) {
        for (final (kwargName, kwargBytes, expectedKwargs) in keywordCases) {
          test('$argName arguments with $kwargName keywords', () {
            final originalArgs = argBytes?.toList();
            final originalKwargs = kwargBytes?.toList();
            final guardedArgs = _guardedView(argBytes, 7);
            final guardedKwargs = _guardedView(kwargBytes, 11);
            final expected = {'args': expectedArgs, 'kwargs': expectedKwargs};
            Uint8List? direct;
            expect(
              () => direct = harness.serializer.serializePPTFragments(
                argumentsBytes: guardedArgs?.view,
                argumentsKeywordsBytes: guardedKwargs?.view,
                arguments: materializedArgs,
                argumentsKeywords: materializedKwargs,
              ),
              returnsNormally,
            );
            expect(harness.decode(direct!), expected);
            final public = PPTPayload.packSerializedPayload(
              harness.name,
              argumentsBytes: guardedArgs?.view,
              argumentsKeywordsBytes: guardedKwargs?.view,
              arguments: materializedArgs,
              argumentsKeywords: materializedKwargs,
            );
            expect(public, isNotNull);
            expect(harness.decode(public!), expected);
            expect(argBytes?.toList(), originalArgs);
            expect(kwargBytes?.toList(), originalKwargs);
            expect(guardedArgs?.storage, guardedArgs?.original);
            expect(guardedKwargs?.storage, guardedKwargs?.original);
            final decoded = harness.serializer.deserializePPT(direct!);
            expect(decoded, isNotNull);
            expect(decoded!.arguments, expectedArgs);
            expect(decoded.argumentsKeywords, expectedKwargs);
          });
        }
      }
      test('absent payload emits two explicit null fields', () {
        expect(harness.decode(harness.serializer.serializePPTFragments()), {
          'args': null,
          'kwargs': null,
        });
      });
    });
  }
}

({Uint8List view, Uint8List storage, List<int> original})? _guardedView(
  Uint8List? input,
  int prefix,
) {
  if (input == null) return null;
  final original = [...List.filled(prefix, 0xff), ...input, 0xee, 0xdd];
  final storage = Uint8List.fromList(original);
  return (
    view: Uint8List.sublistView(storage, prefix, prefix + input.length),
    storage: storage,
    original: original,
  );
}

class _Harness {
  const _Harness(this.name, this.serializer, this.encode, this.decode);
  final String name;
  final AbstractSerializer serializer;
  final Uint8List Function(dynamic) encode;
  final dynamic Function(Uint8List) decode;
}
