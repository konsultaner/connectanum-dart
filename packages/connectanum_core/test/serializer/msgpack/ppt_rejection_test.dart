import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart' show PPTPayload;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart';
import 'package:logging/logging.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

void main() {
  const secret = 'private-payload-marker';

  void expectRecovery(Serializer serializer) {
    PPTPayload? payload;
    expect(
      () => payload = serializer.deserializePPT(
        msgpack.serialize({
          'args': [null, 7, 'recovered'],
          'kwargs': {'ok': true, 'optional': null},
        }),
      ),
      returnsNormally,
    );
    expect(payload, isNotNull);
    expect(payload!.arguments, [null, 7, 'recovered']);
    expect(payload!.argumentsKeywords, {'ok': true, 'optional': null});
  }

  group('MessagePack PPT rejection and recovery', () {
    for (final field in ['args', 'kwargs']) {
      for (final (name, value) in <(String, Object?)>[
        ('nil', null),
        ('boolean', false),
        ('integer', 7),
        ('string', secret),
        if (field == 'kwargs') ('binary', Uint8List.fromList([1, 2])),
        if (field == 'args') ('map', {'key': secret}),
        if (field == 'kwargs') ('list', [secret]),
      ]) {
        test('$field $name is ignored without losing the valid sibling', () {
          final serializer = Serializer();
          PPTPayload? payload;
          expect(
            () => payload = serializer.deserializePPT(
              msgpack.serialize({
                'args': ['retained'],
                'kwargs': {'retained': true},
                field: value,
              }),
            ),
            returnsNormally,
          );
          expect(payload, isNotNull);
          expect(payload!.arguments, field == 'args' ? isNull : ['retained']);
          expect(
            payload!.argumentsKeywords,
            field == 'kwargs' ? isNull : {'retained': true},
          );
          expectRecovery(serializer);
        });
      }
    }

    for (final (name, value) in <(String, Object?)>[
      ('nil', null),
      ('boolean', true),
      ('integer', 42),
      ('float', 1.25),
      ('string', secret),
      ('binary', Uint8List.fromList(utf8.encode(secret))),
      (
        'list',
        [
          secret,
          {'kwargs': secret},
        ],
      ),
    ]) {
      test('non-map $name logs only its size and returns no payload', () async {
        final serializer = Serializer();
        final records = <LogRecord>[];
        final subscription = Logger('Connectanum.Serializer').onRecord.listen(
          records.add,
        );
        addTearDown(subscription.cancel);
        final bytes = msgpack.serialize(value);
        final original = Uint8List.fromList(bytes);

        expect(serializer.deserializePPT(bytes), isNull);
        expect(bytes, original);
        expect(records, hasLength(1));
        final record = records.single;
        expect(record.level, Level.SHOUT);
        expect(
          record.message,
          'Could not deserialize MessagePack PPT payload (${bytes.length} bytes)',
        );
        expect(record.message, isNot(contains(secret)));
        expect(record.error, isNull);
        expect(record.stackTrace, isNull);
        expect(record.object, isNull);

        expectRecovery(serializer);
        expect(records, hasLength(1));
      });
    }

    final valid = msgpack.serialize({
      'args': [secret],
      'kwargs': {'private': secret},
    });
    final malformed = <(String, List<int>)>[
      ('empty', []),
      ('reserved marker', [0xc1]),
      ('truncated map header', [0xde, 0]),
      ('truncated string header', [0xdb, 0, 0]),
      ('truncated binary', [0xc4, 2, 1]),
      ('truncated map value', valid.sublist(0, valid.length - 1)),
      ('trailing nil', [...valid, 0xc0]),
      ('concatenated envelopes', [...valid, ...valid]),
    ];
    for (final (name, values) in malformed) {
      test('$name fails without exposing bytes and permits recovery', () {
        final serializer = Serializer();
        final bytes = Uint8List.fromList(values);
        expect(
          () => serializer.deserializePPT(bytes),
          throwsA(
            isA<FormatException>()
                .having((error) => error.source, 'source', isNull)
                .having((error) => error.offset, 'offset', isNull)
                .having(
                  (error) => error.toString(),
                  'redacted diagnostic',
                  isNot(contains(secret)),
                ),
          ),
        );
        expect(bytes, values);
        expectRecovery(serializer);
      });
    }
  });
}
