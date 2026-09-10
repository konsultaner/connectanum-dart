import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_router/src/native/runtime.dart';

Uint8List _retainSubview(
  String library,
  int handle, {
  required bool payloadOnly,
}) {
  final decoder = NativeMessageHandleDecoder(
    libraryPath: library,
  );
  if (payloadOnly) {
    final payload = decoder.readRetainedCallPayload(
      handle,
      serializer: NativeMessageSerializer.json,
    );
    return Uint8List.sublistView(payload.argumentsBytes!, 1);
  }
  final incoming = decoder.materializeRetained(handle);
  try {
    return Uint8List.sublistView(incoming.argumentsBytes!, 1);
  } finally {
    incoming.dispose();
  }
}

Future<void> main(List<String> args, SendPort parent) async {
  final bytes = _retainSubview(
    args[0],
    int.parse(args[1]),
    payloadOnly: args.length > 2 && args[2] == 'payload-only',
  );
  final commands = ReceivePort();
  parent.send(commands.sendPort);
  await for (final command in commands) {
    if (command == 'read') {
      parent.send(bytes);
    } else if (command == 'finish') {
      commands.close();
    }
  }
}
