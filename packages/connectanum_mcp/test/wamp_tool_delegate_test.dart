import 'dart:async';
import 'dart:convert';

import 'package:connectanum_client/connectanum.dart' hide Session;
import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpWampToolDelegate', () {
    test('forwards MCP tool arguments as WAMP kwargs by default', () async {
      late McpWampToolCall capturedCall;
      final delegate = McpWampToolDelegate(
        procedure: 'app.echo',
        call: (call) {
          capturedCall = call;
          return (
            callRequestId: 1,
            progress: false,
            pptScheme: null,
            pptSerializer: null,
            pptCipher: null,
            pptKeyId: null,
            customDetails: null,
            arguments: const ['ok'],
            argumentsKeywords: {'received': call.payload.argumentsKeywords},
          );
        },
      );
      final server = _server(delegate.toTool(name: 'echo'));
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 10,
        'method': 'tools/call',
        'params': {
          'name': 'echo',
          'arguments': {'text': 'hello'},
        },
      });

      expect(capturedCall.procedure, 'app.echo');
      expect(capturedCall.payload.arguments, isNull);
      expect(capturedCall.payload.argumentsKeywords, {'text': 'hello'});
      final result = response?['result'] as Map<String, Object?>;
      expect(result['isError'], isFalse);
      expect(result['structuredContent'], {
        'arguments': ['ok'],
        'argumentsKeywords': {
          'received': {'text': 'hello'},
        },
      });
    });

    test('supports custom WAMP payload and result mapping', () async {
      final delegate = McpWampToolDelegate(
        procedure: 'app.sum',
        argumentsBuilder: (request) => McpWampCallPayload(
          arguments: [request.arguments['left'], request.arguments['right']],
          options: CallOptions(timeout: 1000),
        ),
        resultMapper: (_, result) {
          final value = result.arguments?.first as int;
          return McpToolResult.text(
            '$value',
            structuredContent: {'value': value},
          );
        },
        call: (call) {
          expect(call.payload.arguments, [2, 3]);
          expect(call.payload.argumentsKeywords, isNull);
          expect(call.payload.options?.timeout, 1000);
          return (
            callRequestId: 2,
            progress: false,
            pptScheme: null,
            pptSerializer: null,
            pptCipher: null,
            pptKeyId: null,
            customDetails: null,
            arguments: [5],
            argumentsKeywords: null,
          );
        },
      );
      final server = _server(delegate.toTool(name: 'sum'));
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 11,
        'method': 'tools/call',
        'params': {
          'name': 'sum',
          'arguments': {'left': 2, 'right': 3},
        },
      });

      final result = response?['result'] as Map<String, Object?>;
      expect(result['content'], [
        {'type': 'text', 'text': '5'},
      ]);
      expect(result['structuredContent'], {'value': 5});
    });

    test('session adapter calls through connectanum_client Session', () async {
      final transport = _ImmediateCallTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final delegate = McpWampToolDelegate.session(
        session: session,
        procedure: 'app.echo',
      );
      final server = _server(delegate.toTool(name: 'echo'));
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 12,
        'method': 'tools/call',
        'params': {
          'name': 'echo',
          'arguments': {'text': 'hello'},
        },
      });

      expect(transport.calls.single.procedure, 'app.echo');
      expect(transport.calls.single.argumentsKeywords, {'text': 'hello'});
      final result = response?['result'] as Map<String, Object?>;
      expect(jsonDecode((result['content'] as List).single['text'] as String), {
        'argumentsKeywords': {
          'procedure': 'app.echo',
          'kwargs': {'text': 'hello'},
        },
      });
    });
  });
}

McpServer _server(McpTool tool) => McpServer(
  serverInfo: const McpServerInfo(name: 'connectanum-wamp', version: '0.1.0'),
  tools: [tool],
);

Future<void> _initializeAndStart(McpServer server) async {
  await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {'protocolVersion': mcpLatestProtocolVersion},
  });
  await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
}

class _ImmediateCallTransport extends AbstractTransport {
  final StreamController<AbstractMessage> _inbound = StreamController.broadcast(
    sync: true,
  );
  final List<Call> calls = [];
  Completer<void>? _onDisconnect;
  Completer<void>? _onConnectionLost;
  bool _open = false;

  @override
  Completer<void>? get onConnectionLost => _onConnectionLost;

  @override
  Completer<void>? get onDisconnect => _onDisconnect;

  @override
  bool get isOpen => _open;

  @override
  bool get isReady => _open;

  @override
  Future<void> get onReady => Future.value();

  @override
  Future<void> open({Duration? pingInterval}) {
    _open = true;
    _onDisconnect = Completer<void>();
    _onConnectionLost = Completer<void>();
    return Future.value();
  }

  @override
  Future<void> close({error}) {
    _open = false;
    complete(_onDisconnect, error);
    return Future.value();
  }

  @override
  Stream<AbstractMessage> receive() => _inbound.stream;

  @override
  void send(AbstractMessage message) {
    if (message is Hello) {
      _inbound.add(Welcome(42, Details.forWelcome()));
      return;
    }
    if (message is Call) {
      calls.add(message);
      _inbound.add(
        Result(
          message.requestId,
          ResultDetails(),
          argumentsKeywords: {
            'procedure': message.procedure,
            'kwargs': message.argumentsKeywords,
          },
        ),
      );
      return;
    }
    if (message is Goodbye) {
      unawaited(close());
    }
  }
}
