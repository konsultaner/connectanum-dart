import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/abstract_message.dart';
import 'package:connectanum_core/src/message/call.dart';
import 'package:connectanum_core/src/message/invocation.dart';
import 'package:connectanum_core/src/message/register.dart';
import 'package:connectanum_core/src/serializer/abstract_serializer.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart' as cbor;
import 'package:connectanum_core/src/serializer/json/serializer.dart' as json;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack;
import 'package:test/test.dart';

void main() {
  final serializers = <String, AbstractSerializer>{
    'json': json.Serializer(),
    'cbor': cbor.Serializer(),
    'msgpack': msgpack.Serializer(),
  };

  for (final entry in serializers.entries) {
    test('${entry.key} round-trips call timeout ownership fields', () {
      final call = Call(
        1001,
        'com.example.slow',
        options: CallOptions(timeout: 250),
      );
      final decodedCall = _roundTrip(entry.value, call) as Call;
      expect(decodedCall.options?.timeout, 250);

      final register = Register(
        2001,
        'com.example.slow',
        options: RegisterOptions(forwardTimeout: true),
      );
      final decodedRegister = _roundTrip(entry.value, register) as Register;
      expect(decodedRegister.options?.forwardTimeout, isTrue);

      final details = InvocationDetails(null, 'com.example.slow', false)
        ..timeout = 250;
      final invocation = Invocation(3001, 4001, details);
      final decodedInvocation =
          _roundTrip(entry.value, invocation) as Invocation;
      expect(decodedInvocation.details.timeout, 250);
      expect(decodedInvocation.toPayload().timeout, 250);
      expect(decodedInvocation.toLazyInvocationPayload().timeout, 250);
    });
  }
}

Object _roundTrip(AbstractSerializer serializer, AbstractMessage message) {
  final encoded = serializer.serialize(message);
  final bytes = encoded is String
      ? Uint8List.fromList(utf8.encode(encoded))
      : encoded as Uint8List;
  return serializer.deserialize(bytes)!;
}
