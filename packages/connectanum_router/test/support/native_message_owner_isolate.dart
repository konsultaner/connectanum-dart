import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_router/src/native/runtime.dart';

Uint8List _retainSubview(String library, int handle) {
  final incoming = NativeMessageHandleDecoder(
    libraryPath: library,
  ).materializeRetained(handle);
  try {
    return Uint8List.sublistView(incoming.argumentsBytes!, 1);
  } finally {
    incoming.dispose();
  }
}

Future<void> main(List<String> args, SendPort parent) async {
  final bytes = _retainSubview(args[0], int.parse(args[1]));
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
