// The root quick start intentionally imports a package from this pub workspace.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/json.dart';

Future<void> main() async {
  final client = Client(
    realm: 'realm1',
    transport: WebSocketTransport(
      'ws://127.0.0.1:8080/ws',
      Serializer(),
      WebSocketSerialization.serializationJson,
    ),
  );
  final session = await client.connect().first;

  final greeting = Completer<String>();
  final subscription = await session.subscribe('com.example.greeting');
  subscription.eventStream!.listen((event) {
    final arguments = event.arguments;
    final value = arguments == null || arguments.isEmpty
        ? null
        : arguments.first;
    if (value is String && !greeting.isCompleted) {
      greeting.complete(value);
    }
  });

  final registration = await session.register('com.example.add');
  registration.onInvoke((invocation) {
    final numbers = invocation.arguments!.cast<num>();
    invocation.respondWith(arguments: [numbers[0] + numbers[1]]);
  });

  await session.publish(
    'com.example.greeting',
    arguments: ['Hello from Connectanum'],
    options: PublishOptions(excludeMe: false),
  );
  final result = await session.callSingle('com.example.add', arguments: [2, 3]);

  print('Pub/Sub: ${await greeting.future}');
  print('RPC: 2 + 3 = ${result.arguments!.first}');

  await session.close();
  await client.disconnect();
}
