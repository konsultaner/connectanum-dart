import 'package:connectanum/connectanum.dart';
import 'package:connectanum/json.dart';
import 'package:pedantic/pedantic.dart';

void main() async {
  // Start a client that connects without the usage of an authentication process
  final client1 = Client(
      // The realm to connect to
      realm: 'demo.connectanum.receive',
      // We choose WebSocket transport
      transport: WebSocketTransport(
        'wss://www.connectanum.com/wamp',
        // if you want to use msgpack instead of JSON just import the serializer
        // from package:connectanum/msgpack.dart and use WebSocketSerialization.SERIALIZATION_MSGPACK
        Serializer(),
        WebSocketSerialization.SERIALIZATION_JSON,
      ));
  Session session1;
  try {
    // connect to the router and start the wamp layer
    session1 = await client1.connect().first;
    // register a method that may be called by other clients
    final registered = await session1.register('demo.get.version');
    registered
        .onInvoke((invocation) => invocation.respondWith(arguments: ['1.1.0']));
    // subscribe to a topic that my be published by other clients
    final subscription = await session1.subscribe('demo.push');
    subscription.eventStream.listen((event) => print(event.arguments[0]));
    await subscription.onRevoke.then((reason) =>
        print('The server has killed my subscription due to: ' + reason));
  } on Abort catch (abort) {
    // if the serve does not allow this client to receive a session
    // the server will cancel the initializing process with an abort
    print(abort.message.message);
  }

  final client2 = Client(
      realm: 'demo.connectanum.receive',
      transport: WebSocketTransport(
        'wss://www.connectanum.com/wamp',
        Serializer(),
        WebSocketSerialization.SERIALIZATION_JSON,
      ));
  try {
    final session2 = await client2.connect().first;
    // call session 1 registered method and print the result
    session2
        .call('demo.get.version')
        .listen((result) => print(result.arguments[0]), onError: (e) {
      var error = e as Error; // type cast necessary
      print(error.error);
    });
    // push a message to session 1
    await session2.publish('demo.push', arguments: ['This is a push message']);
    // close both clients after everything is done
    unawaited(session1.close());
    unawaited(session2.close());
  } on Abort catch (abort) {
    print(abort.message.message);
  }
}
