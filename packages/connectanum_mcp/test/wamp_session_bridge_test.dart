import 'dart:async';

import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  late _WampPeer peer;
  late client.Session session;

  setUp(() async {
    peer = _WampPeer();
    await peer.transport.open();
    session = await client.Session.start('app.realm', peer.transport);
  });
  tearDown(() async {
    await session.close();
    await session.onDisconnect.timeout(const Duration(seconds: 2));
    await peer.dispose();
  });

  test(
    'session tools forward RPC arguments, options and lossless results',
    () async {
      final api = McpWampApi(
        procedures: [
          McpWampProcedure(
            procedure: 'app.echo',
            toolName: 'echo',
            argumentsBuilder: (request) => McpWampCallPayload(
              arguments: [request.arguments['text']],
              argumentsKeywords: {'trace': 'request-1'},
              options: wamp.CallOptions(timeout: 1234, discloseMe: true),
            ),
          ),
        ],
      );
      final server = await _server(api.toSessionTools(session: session));
      final result = await _tool(server, 'echo', {'text': 'hello'});
      final call = peer.messages.whereType<wamp.Call>().single;
      expect(call.procedure, 'app.echo');
      expect(call.arguments, ['hello']);
      expect(call.argumentsKeywords, {'trace': 'request-1'});
      expect(call.options?.timeout, 1234);
      expect(call.options?.discloseMe, isTrue);
      expect(result['isError'], isFalse);
      final content = result['structuredContent'] as Map;
      expect(content['arguments'], ['reply']);
      expect(content['argumentsKeywords'], {'ok': true});
      server.shutdown();
    },
  );

  test(
    'session WAMP errors become MCP tool errors, not successful payloads',
    () async {
      peer.rejectCalls = true;
      final server = await _server(
        McpWampApi(
          procedures: [
            McpWampProcedure(procedure: 'app.echo', toolName: 'echo'),
          ],
        ).toSessionTools(session: session),
      );
      final result = await _tool(server, 'echo', {'text': 'hello'});
      expect(result['isError'], isTrue);
      expect(result['structuredContent'], isNull);
      expect(result['content'], [
        {'type': 'text', 'text': wamp.Error.notAuthorized},
      ]);
      expect(peer.messages.whereType<wamp.Call>().single.argumentsKeywords, {
        'text': 'hello',
      });
      server.shutdown();
    },
  );

  for (final acknowledge in [true, false]) {
    test('session publish honors acknowledge=$acknowledge', () async {
      final server = await _server(_api().toSessionTools(session: session));
      final observed = peer.transport.sentMessages.firstWhere(
        (message) => message is wamp.Publish,
      );
      final result = await _tool(server, 'connectanum.pubsub.publish', {
        'topic': 'app.events',
        'arguments': [7],
        'argumentsKeywords': {'text': 'hello'},
        'acknowledge': acknowledge,
        'options': {'exclude_me': false, 'retain': true},
      });
      final publish = await observed as wamp.Publish;
      expect(publish.topic, 'app.events');
      expect(publish.arguments, [7]);
      expect(publish.argumentsKeywords, {'text': 'hello'});
      expect(publish.options?.acknowledge, acknowledge);
      expect(publish.options?.excludeMe, isFalse);
      expect(publish.options?.retain, isTrue);
      expect(result['isError'], isFalse);
      final content = result['structuredContent'] as Map;
      expect(content['acknowledged'], acknowledge);
      expect(content['publicationId'], acknowledge ? 91 : null);
      server.shutdown();
    });
  }

  test(
    'session tools preserve event metadata and unsubscribe the final owner',
    () async {
      peer.emitRetained = true;
      final server = await _server(_api().toSessionTools(session: session));
      final result = await _tool(server, 'connectanum.pubsub.subscribe', {
        'topic': 'app.events',
        'queueLimit': 2,
        'options': {'match': 'prefix', 'get_retained': true},
      });
      final handle = (result['structuredContent'] as Map)['handle'];
      final subscribe = peer.messages.whereType<wamp.Subscribe>().single;
      expect(subscribe.topic, 'app.events');
      expect(subscribe.options?.match, 'prefix');
      expect(subscribe.options?.getRetained, isTrue);
      // The reply is queued after the retained event on the same WAMP stream.
      await session.callSinglePayload('app.barrier');
      final poll = await _tool(server, 'connectanum.pubsub.poll', {
        'handle': handle,
      });
      final content = poll['structuredContent'] as Map;
      expect((content['events'] as List).single, {
        'subscriptionId': 55,
        'publicationId': 92,
        'publisher': 17,
        'trustlevel': 3,
        'topic': 'app.events.changed',
        'details': {'x_trace': 'event-1'},
        'arguments': [7],
        'argumentsKeywords': {'text': 'retained'},
      });
      final unsubscribed = await _tool(
        server,
        'connectanum.pubsub.unsubscribe',
        {'handle': handle},
      );
      expect(unsubscribed['isError'], isFalse);
      expect(
        peer.messages.whereType<wamp.Unsubscribe>().single.subscriptionId,
        55,
      );
      expect(session.subscriptions, isEmpty);
      final stale = await _tool(server, 'connectanum.pubsub.poll', {
        'handle': handle,
      });
      expect(stale['isError'], isTrue);
      server.shutdown();
    },
  );

  test(
    'releasing an MCP handle preserves another consumer of the subscription',
    () async {
      final externalEvents = <wamp.EventPayload>[];
      final outside = await session.subscribePayloadHandler(
        'app.events',
        externalEvents.add,
      );
      final server = await _server(_api().toSessionTools(session: session));
      final result = await _tool(server, 'connectanum.pubsub.subscribe', {
        'topic': 'app.events',
      });
      final handle = (result['structuredContent'] as Map)['handle'];
      expect(peer.messages.whereType<wamp.Subscribe>(), hasLength(2));
      await _tool(server, 'connectanum.pubsub.unsubscribe', {'handle': handle});
      expect(peer.messages.whereType<wamp.Unsubscribe>(), isEmpty);
      expect(session.subscriptions.keys, contains(55));

      peer.event();
      // An RPC response follows the event on the same receive stream and provides
      // an ordering barrier without arbitrary sleeps.
      await session.callSinglePayload('app.barrier');
      expect(externalEvents, hasLength(1));
      expect(externalEvents.single.publicationId, 92);
      expect(
        (await _tool(server, 'connectanum.pubsub.poll', {
          'handle': handle,
        }))['isError'],
        isTrue,
      );
      await session.releaseSubscription(outside);
      expect(
        peer.messages.whereType<wamp.Unsubscribe>().single.subscriptionId,
        55,
      );
      expect(session.subscriptions, isEmpty);
      server.shutdown();
    },
  );
}

McpWampApi _api() => McpWampApi(topics: [McpWampTopic(topic: 'app.events')]);

Future<McpServer> _server(List<McpTool> tools) async {
  final server = McpServer(
    serverInfo: const McpServerInfo(name: 'session-bridge-test', version: '1'),
    tools: tools,
  );
  await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {'protocolVersion': mcpLatestSessionProtocolVersion},
  });
  await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
  return server;
}

Future<Map<String, Object?>> _tool(
  McpServer server,
  String name,
  Map<String, Object?> arguments,
) async {
  final response = await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 2,
    'method': 'tools/call',
    'params': {'name': name, 'arguments': arguments},
  });
  expect(response, isNot(contains('error')));
  return response!['result'] as Map<String, Object?>;
}

class _WampPeer {
  _WampPeer() {
    _sent = transport.sentMessages.listen(_handle);
  }

  final transport = client.LocalTransport();
  final messages = <wamp.AbstractMessage>[];
  late final StreamSubscription<wamp.AbstractMessage> _sent;
  bool rejectCalls = false;
  bool emitRetained = false;

  void _handle(wamp.AbstractMessage message) {
    messages.add(message);
    if (message is wamp.Call) {
      transport.injectIncomingMessage(
        rejectCalls
            ? wamp.Error(
                wamp.MessageTypes.codeCall,
                message.requestId,
                {'private': 'internal diagnostics'},
                wamp.Error.notAuthorized,
                arguments: ['private error context'],
                argumentsKeywords: {'token': 'not for MCP'},
              )
            : wamp.Result(
                message.requestId,
                wamp.ResultDetails(),
                arguments: ['reply'],
                argumentsKeywords: {'ok': true},
              ),
      );
    } else if (message is wamp.Publish &&
        message.options?.acknowledge == true) {
      transport.injectIncomingMessage(wamp.Published(message.requestId, 91));
    } else if (message is wamp.Subscribe) {
      transport.injectIncomingMessage(wamp.Subscribed(message.requestId, 55));
      if (emitRetained) event();
    } else if (message is wamp.Unsubscribe) {
      transport.injectIncomingMessage(
        wamp.Unsubscribed(message.requestId, null),
      );
    } else if (message is wamp.Goodbye) {
      transport.injectIncomingMessage(
        wamp.Goodbye(
          wamp.GoodbyeMessage('closed'),
          wamp.Goodbye.reasonGoodbyeAndOut,
        ),
      );
    }
  }

  void event() => transport.injectIncomingMessage(
    wamp.Event(
      55,
      92,
      wamp.EventDetails(
        publisher: 17,
        trustlevel: 3,
        topic: 'app.events.changed',
        custom: {'x_trace': 'event-1'},
      ),
      arguments: [7],
      argumentsKeywords: {'text': 'retained'},
    ),
  );

  Future<void> dispose() => _sent.cancel();
}
