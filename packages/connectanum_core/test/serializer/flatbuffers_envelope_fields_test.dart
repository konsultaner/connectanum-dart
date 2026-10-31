import 'dart:typed_data';

import 'package:connectanum_core/src/serializer/flatbuffers/generated/validation_schema.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart'
    as runtime;
import 'package:connectanum_core/src/serializer/flatbuffers/wire_reader.dart';
import 'package:test/test.dart';

void main() {
  _readerCacheTests(
    'envelope',
    (bytes) => readWampFlatBufferEnvelope(bytes).body,
  );
  _envelopeTests();
}

void _readerCacheTests(
  String label,
  Map<String, Object?> Function(Uint8List) readBody,
) {
  for (final topic in [
    '',
    'com.example.long_topic_without_string_interning_abcdefghijklmnopqrstuvwxyz',
  ]) {
    test(
      '$label shared string/table views survive cache overflow, topic=$topic',
      () {
        final b = runtime.WampFlatBufferBuilder();
        final topicOffset = b.writeString(topic);
        final empty = b.writeString('');
        final second = b.writeString(
          'second_long_string_abcdefghijklmnopqrstuvwxyz',
        );
        final third = b.writeString(
          'third_long_string_abcdefghijklmnopqrstuvwxyz',
        );
        final excluded = b.writeList([
          empty,
          second,
          third,
          second,
          empty,
          topicOffset,
          third,
        ]);
        final principals = [
          for (var i = 0; i < 3; i++)
            wire.PrincipalObjectBuilder(
              session: i + 1,
              authid: 'principal$i',
              authrole: 'role$i',
            ).finish(b),
        ];
        final forward = b.writeList([...principals, ...principals]);
        final publish = wire.PublishBuilder(b)..begin();
        publish.addRequest(7);
        publish.addTopicOffset(topicOffset);
        publish.addExcludeAuthidOffset(excluded);
        publish.addForwardForOffset(forward);
        final body = publish.finish();
        final message = wire.MessageBuilder(b)..begin();
        message.addMsgType(wire.AnyMessageTypeId.Publish);
        message.addMsgOffset(body);
        b.finish(message.finish());
        final result = readBody(b.buffer);
        final strings = result['exclude_authid'] as List;
        expect(strings[0], '');
        expect(strings[1], 'second_long_string_abcdefghijklmnopqrstuvwxyz');
        expect(strings[2], 'third_long_string_abcdefghijklmnopqrstuvwxyz');
        expect(identical(strings[1], strings[3]), isTrue);
        expect(identical(strings[0], strings[4]), isTrue);
        expect(identical(result['topic'], strings[5]), isTrue);
        expect(identical(strings[2], strings[6]), isTrue);
        final tables = result['forward_for'] as List;
        for (var i = 0; i < 3; i++) {
          expect((tables[i] as Map)['session'], i + 1);
          expect(identical(tables[i], tables[i + 3]), isTrue);
          if (i < 2) expect(identical(tables[i], tables[i + 1]), isFalse);
        }
        (tables[0] as Map)['session'] = 99;
        expect((tables[3] as Map)['session'], 99);
      },
    );
  }

  test(
    '$label shared physical table offsets remain distinct for different schema types',
    () {
      final b = runtime.WampFlatBufferBuilder();
      final shared = wire.PublisherFeaturesObjectBuilder().finish(b);
      final roles = wire.ClientRolesBuilder(b)..begin();
      roles.addPublisherOffset(shared);
      roles.addSubscriberOffset(shared);
      final rolesOffset = roles.finish();
      final realm = b.writeString('realm');
      final hello = wire.HelloBuilder(b)..begin();
      hello.addRolesOffset(rolesOffset);
      hello.addRealmOffset(realm);
      final body = hello.finish();
      final root = wire.MessageBuilder(b)..begin();
      root.addMsgType(wire.AnyMessageTypeId.Hello);
      root.addMsgOffset(body);
      b.finish(root.finish());
      final read = readBody(b.buffer);
      final roleFields = read['roles'] as Map;
      final publisher = roleFields['publisher'] as Map;
      final subscriber = roleFields['subscriber'] as Map;
      expect(identical(publisher, subscriber), isFalse);
      for (final pair in [
        (publisher, 'PublisherFeatures'),
        (subscriber, 'SubscriberFeatures'),
      ]) {
        final spec = wampValidationTables.firstWhere((t) => t.name == pair.$2);
        expect(pair.$1.keys.toSet(), spec.fields.map((f) => f.name).toSet());
      }
    },
  );
}

void _envelopeTests() {
  for (final withMetadata in [false, true]) {
    test(
      'envelope fields and byte aliases match map, metadata=$withMetadata',
      () {
        final bytes = _resultEnvelope(withMetadata);
        final mapped = readWampFlatBufferFields(bytes);
        final envelope = readWampFlatBufferEnvelope(bytes);
        expect(envelope.tag, mapped['msg_type']);
        expect(envelope.body, mapped['msg']);
        expect(envelope.metadata, mapped['metadata']);
        final payload = envelope.body['payload'] as Uint8List;
        payload[0] = 99;
        expect(bytes[payload.offsetInBytes - bytes.offsetInBytes], 99);
        expect(((mapped['msg'] as Map)['payload'] as Uint8List)[0], 99);
        final metadata = envelope.metadata;
        if (metadata != null) {
          metadata[0] = 0xff;
          expect(bytes[metadata.offsetInBytes - bytes.offsetInBytes], 0xff);
          expect((mapped['metadata'] as Uint8List)[0], 0xff);
        }
      },
    );
  }

  test('envelope preserves validation rejection and decoded root fields', () {
    final original = _resultEnvelope(true);
    for (var index = 0; index < original.length; index++) {
      final bytes = Uint8List.fromList(original);
      bytes[index] ^= 0x80;
      Map<String, Object?>? mapped;
      Object? failure;
      try {
        mapped = readWampFlatBufferFields(bytes);
      } on Object catch (error) {
        failure = error;
      }
      if (failure != null) {
        expect(
          () => readWampFlatBufferEnvelope(bytes),
          throwsA(
            predicate(
              (Object error) => error.runtimeType == failure.runtimeType,
            ),
          ),
          reason: 'mutated byte $index',
        );
      } else {
        final envelope = readWampFlatBufferEnvelope(bytes);
        expect(
          envelope.tag,
          mapped!['msg_type'],
          reason: 'mutated byte $index',
        );
        expect(envelope.body, mapped['msg'], reason: 'mutated byte $index');
        expect(
          envelope.metadata,
          mapped['metadata'],
          reason: 'mutated byte $index',
        );
      }
    }
  });
}

Uint8List _resultEnvelope(bool withMetadata) {
  final builder = runtime.WampFlatBufferBuilder();
  final payload = builder.writeListUint8([1, 2, 3]);
  final metadata = withMetadata ? builder.writeListUint8([0xa0]) : null;
  final result = wire.ResultBuilder(builder)..begin();
  result.addRequest(7);
  result.addPayloadOffset(payload);
  final body = result.finish();
  final root = wire.MessageBuilder(builder)..begin();
  root.addMsgType(wire.AnyMessageTypeId.Result);
  root.addMsgOffset(body);
  if (metadata != null) root.addMetadataOffset(metadata);
  builder.finish(root.finish());
  return builder.buffer;
}
