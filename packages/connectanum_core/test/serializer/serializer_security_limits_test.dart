import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/src/message/result.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

const _maximumPayloadNestingDepth = 64;

void main() {
  group('serializer resource limits', () {
    test('accept the maximum payload nesting depth', () {
      expect(
        msgpack_serializer.Serializer().deserialize(
          _msgpackResultWithNestedArgument(_maximumPayloadNestingDepth),
        ),
        isA<Result>(),
      );
      expect(
        cbor_serializer.Serializer().deserialize(
          _cborResultWithNestedArgument(_maximumPayloadNestingDepth),
        ),
        isA<Result>(),
      );
      expect(
        cbor_serializer.Serializer().deserialize(
          _indefiniteCborResultWithNestedArgument(
            _maximumPayloadNestingDepth,
          ),
        ),
        isA<Result>(),
      );
      expect(
        json_serializer.Serializer().deserialize(
          _jsonResultWithNestedArgument(_maximumPayloadNestingDepth),
        ),
        isA<Result>(),
      );
    });

    test('reject excessive payload nesting before recursive decoding', () {
      expect(
        () => msgpack_serializer.Serializer().deserialize(
          _msgpackResultWithNestedArgument(_maximumPayloadNestingDepth + 1),
        ),
        throwsFormatException,
      );
      expect(
        () => cbor_serializer.Serializer().deserialize(
          _cborResultWithNestedArgument(_maximumPayloadNestingDepth + 1),
        ),
        throwsFormatException,
      );
      expect(
        () => cbor_serializer.Serializer().deserialize(
          _indefiniteCborResultWithNestedArgument(
            _maximumPayloadNestingDepth + 1,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => json_serializer.Serializer().deserialize(
          _jsonResultWithNestedArgument(_maximumPayloadNestingDepth + 1),
        ),
        throwsFormatException,
      );
    });

    test('reject excessive nesting outside a WAMP array envelope', () {
      expect(
        () => msgpack_serializer.Serializer().deserialize(
          _nestedMsgpackMap(_maximumPayloadNestingDepth + 2),
        ),
        throwsFormatException,
      );
      expect(
        () => cbor_serializer.Serializer().deserialize(
          _nestedCborMap(_maximumPayloadNestingDepth + 2),
        ),
        throwsFormatException,
      );
      expect(
        json_serializer.Serializer().deserialize(
          Uint8List.fromList(
            utf8.encode(
              '${'{"key":' * (_maximumPayloadNestingDepth + 2)}null'
              '${'}' * (_maximumPayloadNestingDepth + 2)}',
            ),
          ),
        ),
        isNull,
      );
    });

    test('apply nesting limits to PPT payload decoders', () {
      expect(
        () => msgpack_serializer.Serializer().deserializePPT(
          _nestedMsgpackMap(_maximumPayloadNestingDepth + 2),
        ),
        throwsFormatException,
      );
      expect(
        () => cbor_serializer.Serializer().deserializePPT(
          _nestedCborMap(_maximumPayloadNestingDepth + 2),
        ),
        throwsFormatException,
      );
      expect(
        () => json_serializer.Serializer().deserializePPT(
          _jsonPptWithNestedArgument(_maximumPayloadNestingDepth + 1),
        ),
        throwsFormatException,
      );
    });

    test('reject WAMP envelopes with more than seven fields', () {
      expect(
        () => msgpack_serializer.Serializer().deserialize(
          Uint8List.fromList(const [
            0x98,
            0x32,
            0x01,
            0x80,
            0xc0,
            0xc0,
            0xc0,
            0xc0,
            0xc0,
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => cbor_serializer.Serializer().deserialize(
          Uint8List.fromList(const [
            0x88,
            0x18,
            0x32,
            0x01,
            0xa0,
            0xf6,
            0xf6,
            0xf6,
            0xf6,
            0xf6,
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => cbor_serializer.Serializer().deserialize(
          Uint8List.fromList(const [
            0x9f,
            0x18,
            0x32,
            0x01,
            0xa0,
            0xf6,
            0xf6,
            0xf6,
            0xf6,
            0xf6,
            0xff,
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => json_serializer.Serializer().deserialize(
          Uint8List.fromList(utf8.encode('[50,1,{},null,null,null,null,null]')),
        ),
        throwsFormatException,
      );
      expect(
        () => json_serializer.Serializer().deserialize(
          Uint8List.fromList(
            utf8.encode('[1,null,{},null,null,null,null,null]'),
          ),
        ),
        throwsFormatException,
      );
    });

    test('reject trailing binary data after a WAMP envelope', () {
      expect(
        () => msgpack_serializer.Serializer().deserialize(
          Uint8List.fromList(const [0x93, 0x32, 0x01, 0x80, 0xc0]),
        ),
        throwsFormatException,
      );
      expect(
        () => cbor_serializer.Serializer().deserialize(
          Uint8List.fromList(const [0x83, 0x18, 0x32, 0x01, 0xa0, 0xf6]),
        ),
        throwsFormatException,
      );
      expect(
        () => cbor_serializer.Serializer().deserialize(
          Uint8List.fromList(const [
            0x9f,
            0x18,
            0x32,
            0x01,
            0xa0,
            0xf6,
            0xff,
            0xf6,
          ]),
        ),
        throwsFormatException,
      );
    });

    test('reject floating-point values in WAMP integer fields', () {
      expect(
        () => msgpack_serializer.Serializer().deserialize(
          msgpack.serialize([50, 1.5, <String, Object?>{}]),
        ),
        throwsFormatException,
      );
      expect(
        () => cbor_serializer.Serializer().deserialize(
          Uint8List.fromList(
            cbor.cbor.encode(cbor.CborValue([50, 1.5, <String, Object?>{}])),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => json_serializer.Serializer().deserialize(
          Uint8List.fromList(utf8.encode('[50,1.5,{}]')),
        ),
        throwsA(anything),
      );
    });

    test('ignore JSON structural characters inside strings', () {
      final result = json_serializer.Serializer().deserialize(
        Uint8List.fromList(
          utf8.encode('[50,1,{},["${'[' * 80}${']' * 80}"]]'),
        ),
      );

      expect(result, isA<Result>());
    });

    test('redact malformed JSON payloads from decoder errors', () {
      const secret = 'secret-value';
      const malformed = '{"password":"$secret",}';

      expect(
        () => json_serializer.Serializer().deserialize(
          Uint8List.fromList(utf8.encode(malformed)),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString(),
            'message',
            allOf(
              contains('${malformed.length} chars'),
              isNot(contains(secret)),
            ),
          ),
        ),
      );
    });
  });
}

Uint8List _msgpackResultWithNestedArgument(int depth) => Uint8List.fromList([
  0x94,
  0x32,
  0x01,
  0x80,
  ...List<int>.filled(depth, 0x91),
  0xc0,
]);

Uint8List _cborResultWithNestedArgument(int depth) => Uint8List.fromList([
  0x84,
  0x18,
  0x32,
  0x01,
  0xa0,
  ...List<int>.filled(depth, 0x81),
  0xf6,
]);

Uint8List _indefiniteCborResultWithNestedArgument(int depth) =>
    Uint8List.fromList([
      0x9f,
      0x18,
      0x32,
      0x01,
      0xa0,
      ...List<int>.filled(depth, 0x81),
      0xf6,
      0xff,
    ]);

Uint8List _jsonResultWithNestedArgument(int depth) => Uint8List.fromList(
  utf8.encode('[50,1,{},${'[' * depth}null${']' * depth}]'),
);

Uint8List _jsonPptWithNestedArgument(int depth) => Uint8List.fromList(
  utf8.encode('{"args":${'[' * depth}null${']' * depth}}'),
);

Uint8List _nestedMsgpackMap(int depth) => Uint8List.fromList([
  for (var index = 0; index < depth; index++) ...const [0x81, 0xc0],
  0xc0,
]);

Uint8List _nestedCborMap(int depth) => Uint8List.fromList([
  for (var index = 0; index < depth; index++) ...const [0xa1, 0xf6],
  0xf6,
]);
