import 'dart:io';

import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;

void main(List<String> arguments) {
  final directory = Directory(arguments.single);
  final python = wire.Message(
    File('${directory.path}/python_call.bin').readAsBytesSync(),
  );
  final received = python.msg as wire.Call;
  const args = [0x82, 1, 0x65, 104, 101, 108, 108, 111];
  if (received.request != 77 ||
      received.procedure != 'com.example.proc' ||
      received.args!.length != args.length ||
      !List.generate(
        args.length,
        (i) => received.args![i] == args[i],
      ).every((v) => v) ||
      python.metadata != null) {
    throw StateError('Upstream Python Call was not preserved');
  }
  final root = wire.MessageObjectBuilder(
    msgType: wire.AnyMessageTypeId.Call,
    msg: wire.CallObjectBuilder(
      request: 77,
      procedure: 'com.example.proc',
      args: args,
      caller: 9007199254740992,
    ),
    metadata: [0xa1, 0x61, 0x78, 0x18, 0x2a],
  );
  File(
    '${directory.path}/dart_call_metadata.bin',
  ).writeAsBytesSync(root.toBytes());
  final publication = wire.MessageObjectBuilder(
    msgType: wire.AnyMessageTypeId.Publish,
    msg: wire.PublishObjectBuilder(
      request: 42,
      topic: 'com.example.topic',
      exclude: [1, 4294967296, 9007199254740991, 9007199254740992],
    ),
  );
  File(
    '${directory.path}/dart_publish_ids.bin',
  ).writeAsBytesSync(publication.toBytes());
  final emptyPublication = wire.MessageObjectBuilder(
    msgType: wire.AnyMessageTypeId.Publish,
    msg: wire.PublishObjectBuilder(
      request: 42,
      topic: 'com.example.topic',
      exclude: [],
    ),
  );
  File(
    '${directory.path}/dart_publish_empty_ids.bin',
  ).writeAsBytesSync(emptyPublication.toBytes());
}
