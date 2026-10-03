import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart'
    as runtime;
import 'package:test/test.dart';

import 'flatbuffers_fixture_data.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/validation.dart';

Uint8List fixture(String name) {
  final cases = (jsonDecode(flatBuffersFixtureJson) as List)
      .cast<Map<String, dynamic>>();
  return base64Decode(
    cases.singleWhere((row) => row['name'] == name)['base64'],
  );
}

int field(Uint8List bytes, int table, int slot) {
  final data = ByteData.sublistView(bytes);
  final vtable = table - data.getInt32(table, Endian.little);
  final relative = data.getUint16(vtable + 4 + slot * 2, Endian.little);
  expect(
    relative,
    greaterThan(0),
    reason: 'mutation must target an existing field',
  );
  return table + relative;
}

int target(Uint8List bytes, int offset) =>
    offset + ByteData.sublistView(bytes).getUint32(offset, Endian.little);

int root(Uint8List bytes) => target(bytes, 0);
int body(Uint8List bytes) => target(bytes, field(bytes, root(bytes), 1));

void set32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);

void absent(Uint8List bytes, int table, int slot) {
  final data = ByteData.sublistView(bytes);
  final vtable = table - data.getInt32(table, Endian.little);
  data.setUint16(vtable + 4 + slot * 2, 0, Endian.little);
}

Uint8List call({String procedure = 'com.example.proc', List<int>? args}) =>
    Uint8List.fromList(
      wire.MessageObjectBuilder(
        msgType: wire.AnyMessageTypeId.Call,
        msg: wire.CallObjectBuilder(
          request: 42,
          procedure: procedure,
          args: args,
        ),
      ).toBytes(),
    );

Uint8List hello() => Uint8List.fromList(
  wire.MessageObjectBuilder(
    msgType: wire.AnyMessageTypeId.Hello,
    msg: wire.HelloObjectBuilder(
      realm: 'realm',
      roles: wire.ClientRolesObjectBuilder(
        caller: wire.CallerFeaturesObjectBuilder(),
      ),
      authmethods: [wire.AuthMethod.TICKET],
    ),
  ).toBytes(),
);

void main() {
  final cases = (jsonDecode(flatBuffersFixtureJson) as List)
      .cast<Map<String, dynamic>>();
  for (final row in cases) {
    test('validates independently compiled ${row['name']}', () {
      final bytes = base64Decode(row['base64']);
      validateWampFlatBuffer(bytes);
      // Logical offsets remain relative to the supplied span, even when the
      // backing allocation has an odd prefix and suffix.
      final padded = Uint8List(bytes.length + 8)
        ..setRange(3, bytes.length + 3, bytes);
      validateWampFlatBuffer(
        Uint8List.sublistView(padded, 3, bytes.length + 3),
      );
    });
  }

  test('rejects roots outside the frame, including wrapped uint32 offsets', () {
    for (final offset in [0, 1, 2, 3, 5, 0xfffffff0, 0xffffffff]) {
      final bytes = fixture('call');
      set32(bytes, 0, offset);
      expect(() => validateWampFlatBuffer(bytes), throwsFormatException);
    }
    for (var length = 0; length < 4; length++) {
      expect(
        () => validateWampFlatBuffer(Uint8List(length)),
        throwsFormatException,
      );
    }
  });

  test('rejects invalid vtable and object bounds', () {
    for (final change in <void Function(Uint8List)>[
      (b) => set32(b, root(b), 0xffffffff),
      (b) {
        final table = root(b);
        final data = ByteData.sublistView(b);
        final vtable = table - data.getInt32(table, Endian.little);
        data.setUint16(vtable, 3, Endian.little);
      },
      (b) {
        final table = root(b);
        final data = ByteData.sublistView(b);
        final vtable = table - data.getInt32(table, Endian.little);
        data.setUint16(vtable + 2, 3, Endian.little);
      },
      (b) {
        final table = root(b);
        final data = ByteData.sublistView(b);
        final vtable = table - data.getInt32(table, Endian.little);
        data.setUint16(vtable + 6, 0xffff, Endian.little);
      },
    ]) {
      final bytes = fixture('call');
      change(bytes);
      expect(() => validateWampFlatBuffer(bytes), throwsFormatException);
    }
  });

  test('accepts deduplicated vtables stored after their table', () {
    final original = call();
    final table = root(original);
    final data = ByteData.sublistView(original);
    final oldVtable = table - data.getInt32(table, Endian.little);
    final size = data.getUint16(oldVtable, Endian.little);
    final bytes = Uint8List(original.length + size)
      ..setRange(0, original.length, original)
      ..setRange(original.length, original.length + size, original, oldVtable);
    ByteData.sublistView(
      bytes,
    ).setInt32(table, table - original.length, Endian.little);
    validateWampFlatBuffer(bytes);
    expect((wire.Message(bytes).msg as wire.Call).request, 42);
    // A signed offset pointing outside the allocation is rejected before read.
    set32(bytes, table, 0x80000000);
    expect(() => validateWampFlatBuffer(bytes), throwsFormatException);
  });

  test('rejects unaligned scalar fields before reading them', () {
    final bytes = call();
    final table = body(bytes);
    final data = ByteData.sublistView(bytes);
    final vtable = table - data.getInt32(table, Endian.little);
    final entry = vtable + 6;
    final relative = data.getUint16(entry, Endian.little);
    data.setUint16(entry, relative + 1, Endian.little);
    expect(() => validateWampFlatBuffer(bytes), throwsFormatException);
  });

  test('requires an existing discriminator and its required union table', () {
    final unknown = fixture('call');
    unknown[field(unknown, root(unknown), 0)] = 255;
    expect(() => validateWampFlatBuffer(unknown), throwsFormatException);
    final missingType = fixture('call');
    absent(missingType, root(missingType), 0);
    expect(() => validateWampFlatBuffer(missingType), throwsFormatException);
    final missingBody = fixture('call');
    absent(missingBody, root(missingBody), 1);
    expect(() => validateWampFlatBuffer(missingBody), throwsFormatException);
    final missingProcedure = fixture('call');
    absent(missingProcedure, body(missingProcedure), 2);
    expect(
      () => validateWampFlatBuffer(missingProcedure),
      throwsFormatException,
    );
  });

  test('bounds byte-vector lengths without scanning application contents', () {
    final bytes = call(args: List.filled(128 * 1024, 255));
    final original = Uint8List.fromList(bytes);
    validateWampFlatBuffer(
      bytes,
      limits: const WampFlatBufferValidationLimits(maxVectorElements: 0),
    );
    expect(bytes, original);
    final vector = target(bytes, field(bytes, body(bytes), 3));
    set32(bytes, vector, 0xffffffff);
    expect(() => validateWampFlatBuffer(bytes), throwsFormatException);
  });

  test('checks strings, enum vectors, booleans and WAMP uint64 limits', () {
    final brokenString = call();
    final string = target(
      brokenString,
      field(brokenString, body(brokenString), 2),
    );
    final length = ByteData.sublistView(
      brokenString,
    ).getUint32(string, Endian.little);
    brokenString[string + 4 + length] = 1;
    expect(() => validateWampFlatBuffer(brokenString), throwsFormatException);

    final methods = hello();
    final vector = target(methods, field(methods, body(methods), 3));
    methods[vector + 4] = 255;
    expect(() => validateWampFlatBuffer(methods), throwsFormatException);

    final integer = call();
    final request = field(integer, body(integer), 1);
    set32(integer, request, 0);
    set32(integer, request + 4, 0x200000);
    validateWampFlatBuffer(integer);
    set32(integer, request, 1);
    expect(() => validateWampFlatBuffer(integer), throwsFormatException);

    final boolean = fixture('publish');
    boolean[field(boolean, body(boolean), 10)] = 2;
    expect(() => validateWampFlatBuffer(boolean), throwsFormatException);
  });

  test('accepts every Unicode range and rejects malformed UTF-8', () {
    validateWampFlatBuffer(
      call(
        procedure: '\u0000é\u07ff\u0800\ud7ff\ue000\uffff\u{10000}\u{10ffff}',
      ),
    );
    for (final invalid in <List<int>>[
      [0x80],
      [0xc0, 0x80],
      [0xc1, 0xbf],
      [0xc2],
      [0xc2, 0x7f],
      [0xe0, 0x9f, 0xbf],
      [0xe1, 0x80],
      [0xed, 0xa0, 0x80],
      [0xef, 0xbf, 0x7f],
      [0xf0, 0x8f, 0xbf, 0xbf],
      [0xf1, 0x80, 0x80],
      [0xf4, 0x90, 0x80, 0x80],
      [0xf5, 0x80, 0x80, 0x80],
      [0xff],
    ]) {
      final bytes = call(procedure: 'xxxx');
      final string = target(bytes, field(bytes, body(bytes), 2));
      set32(bytes, string, invalid.length);
      bytes.setRange(string + 4, string + 4 + invalid.length, invalid);
      bytes[string + 4 + invalid.length] = 0;
      expect(
        () => validateWampFlatBuffer(bytes),
        throwsFormatException,
        reason: '$invalid',
      );
    }
  });

  test('allows aliased empty tables with distinct schema types', () {
    final builder = runtime.WampFlatBufferBuilder();
    final publisher = wire.PublisherFeaturesObjectBuilder().finish(builder);
    final roles = wire.ClientRolesBuilder(builder)..begin();
    roles.addPublisherOffset(publisher);
    // Both feature tables contain only optional bools, so one all-absent
    // object is a valid representation of either schema type.
    roles.addSubscriberOffset(publisher);
    final rolesOffset = roles.finish();
    final realm = builder.writeString('realm');
    final hello = wire.HelloBuilder(builder)..begin();
    hello.addRolesOffset(rolesOffset);
    hello.addRealmOffset(realm);
    final helloOffset = hello.finish();
    final message = wire.MessageBuilder(builder)..begin();
    message.addMsgType(wire.AnyMessageTypeId.Hello);
    message.addMsgOffset(helloOffset);
    builder.finish(message.finish());
    validateWampFlatBuffer(builder.buffer);
    expect(
      () => validateWampFlatBuffer(
        builder.buffer,
        limits: const WampFlatBufferValidationLimits(maxDepth: 3),
      ),
      throwsFormatException,
    );
  });

  test('applies frame, table, string and non-byte-vector budgets', () {
    final bytes = fixture('publish');
    for (final limits in [
      WampFlatBufferValidationLimits(maxBytes: bytes.length - 1),
      const WampFlatBufferValidationLimits(maxDepth: 1),
      const WampFlatBufferValidationLimits(maxTables: 1),
      const WampFlatBufferValidationLimits(maxStringBytes: 0),
    ]) {
      expect(
        () => validateWampFlatBuffer(bytes, limits: limits),
        throwsFormatException,
      );
    }
    expect(
      () => validateWampFlatBuffer(
        hello(),
        limits: const WampFlatBufferValidationLimits(maxVectorElements: 0),
      ),
      throwsFormatException,
    );
    expect(
      () => validateWampFlatBuffer(
        bytes,
        limits: const WampFlatBufferValidationLimits(maxDepth: 0),
      ),
      throwsArgumentError,
    );
  });

  test('truncation and random mutations never escape as unchecked reads', () {
    final random = Random(6103);
    for (final row in cases) {
      final original = base64Decode(row['base64']);
      for (var trial = 0; trial < 48; trial++) {
        final bytes = Uint8List.fromList(original);
        if (trial < 16) {
          final length = random.nextInt(bytes.length);
          try {
            validateWampFlatBuffer(Uint8List.sublistView(bytes, 0, length));
          } on FormatException {
            // Padding can be truncated without changing reachable data.
          }
        } else {
          bytes[random.nextInt(bytes.length)] = random.nextInt(256);
          try {
            validateWampFlatBuffer(bytes);
          } on FormatException {
            // Some mutations describe another valid frame.
          }
        }
      }
    }
    for (var trial = 0; trial < 256; trial++) {
      final bytes = Uint8List.fromList(
        List.generate(random.nextInt(256), (_) => random.nextInt(256)),
      );
      try {
        validateWampFlatBuffer(bytes);
      } on FormatException {
        // Any RangeError or other unexpected exception fails the test.
      }
    }
  });
}
