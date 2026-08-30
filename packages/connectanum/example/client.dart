import 'dart:async';

import 'package:connectanum/connectanum.dart';
import 'package:connectanum/json.dart';

Future<void> main() async {
  final client = Client(
    realm: 'com.example.app',
    transport: WebSocketTransport(
      'ws://localhost:8080/ws',
      Serializer(),
      WebSocketSerialization.serializationJson,
    ),
  );

  final session = await client.connect().first;
  final result = await session.callSingle(
    'com.example.add',
    arguments: const <Object?>[2, 3],
  );
  print(result.arguments?.first);

  await session.close();
  await client.disconnect();
}
