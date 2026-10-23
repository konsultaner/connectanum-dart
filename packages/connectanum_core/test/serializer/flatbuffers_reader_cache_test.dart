import 'package:connectanum_core/src/serializer/flatbuffers/generated/validation_schema.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart'
    as runtime;
import 'package:connectanum_core/src/serializer/flatbuffers/wire_reader.dart';
import 'package:test/test.dart';

void main() {
  for (final topic in [
    '',
    'com.example.long_topic_without_string_interning_abcdefghijklmnopqrstuvwxyz',
  ]) {
    test('shared string/table views survive cache overflow, topic=$topic', () {
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
      final result = readWampFlatBufferFields(b.buffer)['msg'] as Map;
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
    });
  }

  test(
    'shared physical table offsets remain distinct for different schema types',
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
      final read = readWampFlatBufferFields(b.buffer)['msg'] as Map;
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
