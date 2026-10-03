import 'dart:typed_data';

import 'cbor_validation.dart';
import 'generated/validation_schema.dart';
import 'generated/wamp_wamp.proto_generated.dart' as wire;
import 'message_projection.dart';
import 'validation_types.dart';
import 'wire_reader.dart';

class FlatBufferFrame {
  const FlatBufferFrame(this.bytes, this.name, this.fields, this.dictionary);
  final Uint8List bytes;
  final String name;
  final Map<String, Object?> fields;
  final Map<String, dynamic>? dictionary;

  String get challengeMethod {
    final method = fields['method'] as int;
    final original = flatBufferAuthMethods.entries
        .singleWhere((entry) => entry.value == method)
        .key;
    final name = fields['method_name'] as String?;
    if (name == null) return original;
    if (name.isEmpty ||
        (flatBufferAuthMethods.containsKey(name) && name != original) ||
        (!flatBufferAuthMethods.containsKey(name) && method != 0)) {
      throw const FormatException('Contradictory FlatBuffers CHALLENGE method');
    }
    return name;
  }
}

FlatBufferFrame readWampFlatBufferFrame(Uint8List bytes) {
  final root = readWampFlatBufferFields(bytes);
  final tag = root['msg_type'] as int;
  final name = wire.AnyMessageTypeId.values
      .singleWhere((value) => value.value == tag)
      .name;
  final body = root['msg'] as Map<String, Object?>;
  final encoded = root['metadata'] as Uint8List?;
  final dictionary = encoded == null ? null : decodeFlatBufferMetadata(encoded);
  if (name != 'Welcome' && name != 'Heartbeat' && body['session'] != 0) {
    throw const FormatException('Non-WELCOME FlatBuffers session must be zero');
  }
  if (dictionary != null) {
    if (_noDictionary.contains(name)) {
      throw const FormatException(
        'FlatBuffers message has no metadata dictionary',
      );
    }
    if (name != 'Heartbeat') {
      try {
        _agree(
          name,
          body,
          projectFlatBufferDictionary(name, dictionary),
          dictionary,
        );
      } on ArgumentError {
        throw const FormatException('Invalid FlatBuffers metadata field type');
      }
    }
  }
  final frame = FlatBufferFrame(bytes, name, body, dictionary);
  if (name == 'Challenge') frame.challengeMethod;
  if (name == 'Error' &&
      !{16, 32, 34, 48, 64, 66, 68}.contains(body['request_type'])) {
    throw const FormatException('Unsupported ERROR request type');
  }
  if (name == 'Heartbeat') {
    final presence = body['presence'] as int;
    if ((presence & ~7) != 0) {
      throw const FormatException('Reserved HEARTBEAT presence bits');
    }
    for (final entry in {'ping': 1, 'incoming': 2, 'outgoing': 4}.entries) {
      if ((presence & entry.value) == 0 && body[entry.key] != 0) {
        throw const FormatException('Absent HEARTBEAT control is nonzero');
      }
    }
  }
  if (body.containsKey('payload')) {
    final payload = body['payload'];
    if (payload != null && (body['args'] != null || body['kwargs'] != null)) {
      throw const FormatException(
        'FlatBuffers payload conflicts with args/kwargs',
      );
    }
    if (body['args'] case final Uint8List args) {
      validateFlatBufferCbor(args, rootMajor: 4);
    }
    if (body['kwargs'] case final Uint8List kwargs) {
      validateFlatBufferCbor(kwargs, rootMajor: 5);
    }
  }
  return frame;
}

const _noDictionary = {
  'Published',
  'Subscribed',
  'Unsubscribe',
  'Registered',
  'Unregister',
  'EventReceived',
};

void _agree(
  String name,
  Map<String, Object?> actual,
  Map<String, Object?> expected,
  Map<String, dynamic> dictionary,
) {
  final ignored =
      switch (name) {
        'Hello' => {'realm'},
        'Authenticate' => {'signature'},
        'Abort' || 'Goodbye' => {'reason'},
        'Error' => {'request_type', 'error'},
        'Publish' || 'Subscribe' => {'topic'},
        'Event' => {'subscription', 'publication'},
        'Call' || 'Register' => {'procedure'},
        'Invocation' => {'registration'},
        _ => <String>{},
      }..addAll({
        'session',
        'request',
        'args',
        'kwargs',
        'payload',
        'method',
        'method_name',
      });
  final spec = wampValidationTables.singleWhere((table) => table.name == name);
  for (final field in spec.fields) {
    if (ignored.contains(field.name)) continue;
    final value = actual[field.name];
    final target = expected[field.name];
    if (field.kind == FlatBufferFieldKind.table &&
        wampValidationTables[field.reference].name == 'Map' &&
        value != null) {
      final source =
          field.name == 'extra' &&
              (name == 'Challenge' || name == 'Authenticate')
          ? dictionary
          : dictionary[field.name];
      final pair = value as Map<String, Object?>;
      if (source is! Map ||
          !source.containsKey(pair['key']) ||
          source[pair['key']] != pair['value']) {
        _conflict(field.name);
      }
    } else if (!_matches(field, value, target, name)) {
      _conflict(field.name);
    }
  }
}

bool _matches(
  FlatBufferFieldSpec field,
  Object? actual,
  Object? expected,
  String tableName,
) {
  if (field.kind == FlatBufferFieldKind.scalar) {
    final fallback = switch ((tableName, field.name)) {
      ('Publish', 'exclude_me') || ('Interrupt', 'mode') => 1,
      _ => 0,
    };
    final isBool =
        field.width == 1 &&
        field.values.length == 2 &&
        field.values[0] == 0 &&
        field.values[1] == 1;
    return actual == (expected ?? (isBool ? fallback != 0 : fallback));
  }
  if (field.kind == FlatBufferFieldKind.table) {
    if (actual == null || expected == null) return actual == expected;
    final spec = wampValidationTables[field.reference];
    return _tableMatches(
      spec,
      actual as Map<String, Object?>,
      expected as Map<String, Object?>,
    );
  }
  if (actual is List && expected is List) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (field.kind == FlatBufferFieldKind.tableVector) {
        if (!_tableMatches(
          wampValidationTables[field.reference],
          actual[i] as Map<String, Object?>,
          expected[i] as Map<String, Object?>,
        )) {
          return false;
        }
      } else if (actual[i] != expected[i]) {
        return false;
      }
    }
    return true;
  }
  return actual == expected;
}

bool _tableMatches(
  FlatBufferTableSpec spec,
  Map<String, Object?> actual,
  Map<String, Object?> expected,
) => spec.fields.every(
  (field) =>
      _matches(field, actual[field.name], expected[field.name], spec.name),
);

Never _conflict(String field) =>
    throw FormatException('Contradictory FlatBuffers metadata field $field');
