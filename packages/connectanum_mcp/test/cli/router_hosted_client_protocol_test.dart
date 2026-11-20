@TestOn('vm')
@Timeout(Duration(seconds: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/src/cli/router_hosted_client.dart';
import 'package:test/test.dart';

import 'owned_http_client_test_support.dart';

final _fixture = _loadFixture();

Map<String, dynamic> _loadFixture() {
  var root = Directory.current.absolute;
  const path =
      'packages/connectanum_mcp/test/cli/fixtures/'
      'router_protocol_2025_06_18.json.gz';
  while (!File('${root.path}/$path').existsSync()) {
    if (root.parent.path == root.path) {
      throw StateError('Protocol fixture missing');
    }
    root = root.parent;
  }
  return jsonDecode(
        utf8.decode(gzip.decode(File('${root.path}/$path').readAsBytesSync())),
      )
      as Map<String, dynamic>;
}

const _options = [
  '--protocol-version',
  '2025-06-18',
  '--rejected-origin',
  'https://rejected.example',
  '--tool',
  'example.task.lookup',
  '--tool-arguments',
  '{"taskId":"T-cli-regression"}',
  '--resource-uri',
  'app://example/context/live',
  '--resource-update-topic',
  'example.events.context.updated',
  '--prompt',
  'summarize-task',
  '--prompt-arguments',
  '{"taskId":"T-cli-regression"}',
  '--wamp-procedure',
  'example.task.configured.lookup',
  '--wamp-topic',
  'example.events.task',
  '--pubsub-topic',
  'example.events.task',
  '--pubsub-event',
  '{"taskId":"T-cli-regression","status":"open"}',
];

void main() {
  test(
    'recorded real router protocol preserves every request and output field',
    () async {
      final peer = await _RecordedPeer.start();
      final output = _Output();
      try {
        try {
          await _run(peer, output);
        } on StateError catch (error) {
          fail('The valid recorded protocol was rejected: $error');
        }
        expect(output.text.toString(), _fixture['transcript']);
        expect(peer.next, (_fixture['requests'] as List).length);
      } finally {
        await peer.close();
      }
    },
  );

  for (final prefix in ['direct', 'streamable-active-direct']) {
    for (final kind in ['procedure', 'topic']) {
      for (final method in ['', '-method']) {
        final id = '$prefix-wamp-$kind-api-list$method-0';
        final field = kind == 'procedure' ? 'procedures' : 'topics';
        test('$id rejects a catalog missing the requested URI', () async {
          await _expectRejected(
            _Fault(
              id,
              ['result', 'structuredContent', field],
              const <Object?>[],
              'did not advertise',
            ),
          );
        });
      }
    }
  }
  for (final prefix in ['direct', 'streamable-active-direct']) {
    final trace = 'router-hosted-client-$prefix-batch';
    final row = (_fixture['requests'] as List).cast<Map>().singleWhere(
      (row) =>
          (row['headers'] as Map)['x-consumer-trace'] is List &&
          ((row['headers'] as Map)['x-consumer-trace'] as List).single == trace,
    );
    final responses = jsonDecode(row['responseBody'] as String) as List;
    test(
      '$prefix batch rejects a missing response before another request',
      () async {
        await _expectRejected(
          _Fault.http(
            trace,
            'batch returned ${responses.length - 1} responses for ${responses.length} requests',
            responseBody: jsonEncode(
              responses.take(responses.length - 1).toList(),
            ),
          ),
          exception: isA<FormatException>().having(
            (error) => error.message,
            'missing batch response',
            contains('JSON-RPC batch response missing response for id'),
          ),
        );
      },
    );
  }

  for (final prefix in ['direct', 'streamable-active-direct']) {
    for (final kind in ['procedure', 'topic']) {
      for (final catalog in <Object?>[const <Object?>[], null]) {
        final id = '$prefix-batch-wamp-$kind-api-list';
        test('$id rejects invalid catalog $catalog', () async {
          await _expectRejected(
            _Fault(
              id,
              [
                'result',
                'structuredContent',
                kind == 'procedure' ? 'procedures' : 'topics',
              ],
              catalog,
              catalog == null ? 'returned a non-list' : 'did not advertise',
            ),
          );
        });
      }
    }
  }

  final readRow = (_fixture['requests'] as List).cast<Map>().singleWhere(
    (row) =>
        row['body'] is String &&
        (row['body'] as String).contains('"id":"streamable-resource-read"'),
  );
  final readEnvelope = const LineSplitter()
      .convert(readRow['responseBody'] as String)
      .where((line) => line.startsWith('data: {'))
      .map((line) => jsonDecode(line.substring(6)) as Map)
      .single;
  final originalContent = (readEnvelope['result'] as Map)['contents'] as List;
  for (final (name, refreshed) in [
    (
      'appended content',
      [
        ...originalContent,
        {
          'uri': 'app://example/context/live',
          'mimeType': 'text/plain',
          'text': 'Additional context',
        },
      ],
    ),
    (
      'added annotations',
      [
        {
          ...originalContent.single as Map,
          'annotations': {'priority': 0.5},
        },
      ],
    ),
  ]) {
    test(
      'resource reread accepts $name while retaining existing values',
      () async {
        final peer = await _RecordedPeer.start(
          fault: _Fault(
            'streamable-resource-reread',
            ['result', 'contents'],
            refreshed,
            'valid resource growth',
          ),
        );
        final output = _Output();
        try {
          try {
            await _run(peer, output);
          } on StateError catch (error) {
            fail('A valid resource update was rejected: $error');
          }
          expect(peer.changed, 1);
          expect(peer.next, (_fixture['requests'] as List).length);
          final transcript = <String, dynamic>{
            for (final line in const LineSplitter().convert(
              output.text.toString(),
            ))
              ...(jsonDecode(line) as Map).cast<String, dynamic>(),
          };
          final streamable = transcript['streamable'] as Map;
          final subscription = streamable['resourceSubscription'] as Map;
          expect(subscription['refreshedContent'], refreshed);
        } finally {
          await peer.close();
        }
      },
    );
  }
  test('resource reread rejects structurally unchanged content', () async {
    await _expectRejected(
      _Fault(
        'streamable-resource-reread',
        ['result', 'contents'],
        originalContent,
        'Resource reread did not return updated content',
      ),
    );
  });
  for (final (field, value) in <(String, Object?)>[
    ('topic', 'other.topic'),
    ('acknowledged', false),
    ('publicationId', null),
  ]) {
    test('resource update rejects an invalid publication $field', () async {
      await _expectRejected(
        _Fault(
          'streamable-resource-update-publish',
          ['result', 'structuredContent', field],
          value,
          'Resource update publication was not acknowledged',
        ),
      );
    });
  }

  for (final prefix in [
    'direct-pubsub',
    'streamable-active-direct-pubsub',
    'streamable-pubsub',
  ]) {
    final label = switch (prefix) {
      'direct-pubsub' => 'Direct JSON pub/sub method publish',
      'streamable-active-direct-pubsub' =>
        'Streamable active direct JSON pub/sub method publish',
      _ => 'Streamable pub/sub method publish',
    };
    for (final (field, value, diagnostic) in <(String, Object?, String)>[
      ('topic', 'other.topic', 'returned topic other.topic'),
      ('acknowledged', false, 'did not acknowledge publication'),
      ('publicationId', null, 'acknowledged without a publication id'),
    ]) {
      final fault = _Fault(
        '$prefix-publish-method',
        ['result', 'structuredContent', field],
        value,
        '$label $diagnostic',
      );
      test(
        '$prefix rejects invalid method publication $field',
        () => _expectRejected(fault),
      );
    }
  }

  for (final (id, path, value, diagnostic)
      in <(String, List<Object>, Object?, String)>[
        (
          'streamable-active-direct-batch-error-tools',
          ['result', 'tools'],
          null,
          'batch error isolation lost tools result',
        ),
        for (final prefix in [
          'direct-batch',
          'streamable-active-direct-batch',
        ]) ...[
          ('$prefix-tools', ['result', 'tools'], [], 'did not advertise'),
          (
            '$prefix-resources',
            ['result', 'resources'],
            [],
            'did not advertise',
          ),
          ('$prefix-prompts', ['result', 'prompts'], [], 'did not advertise'),
        ],
        for (final prefix in [
          'direct-pubsub',
          'streamable-active-direct-pubsub',
          'streamable-pubsub',
        ]) ...[
          (
            '$prefix-${prefix == 'streamable-active-direct-pubsub' ? 'publish-poll' : 'poll'}',
            ['result', 'structuredContent', 'events', 0, 'argumentsKeywords'],
            {'taskId': 'T-cli-regression'},
            'Published event was not observed',
          ),
          (
            '$prefix-publish-method',
            ['result', 'isError'],
            true,
            'returned an error',
          ),
        ],
      ]) {
    final fault = _Fault(id, path, value, diagnostic);
    test(
      '$id rejects ${path.join('.')} = ${jsonEncode(value)}',
      () => _expectRejected(fault),
    );
  }
  test(
    'protocol layer rejects a non-integer batch error code',
    () => _expectRejected(
      const _Fault(
        'streamable-active-direct-batch-error-missing',
        ['error', 'code'],
        'bad-code',
        'JSON-RPC batch response item error code must be an integer',
      ),
      exception: isA<FormatException>().having(
        (e) => e.message,
        'specific protocol error',
        'JSON-RPC batch response item error code must be an integer',
      ),
    ),
  );
  for (final fault in [
    const _Fault.http(
      'router-hosted-client-streamable-invalid-last-event-id',
      'invalid Last-Event-ID returned 401',
      status: 401,
    ),
    const _Fault.http(
      'router-hosted-client-streamable-invalid-last-event-id',
      'invalid Last-Event-ID rejection did not name the header',
      responseBody: 'Other error',
    ),
    const _Fault.http(
      'router-hosted-client-streamable-empty-last-event-id',
      'empty Last-Event-ID returned no SSE events',
      responseBody: '',
    ),
    const _Fault.http(
      'router-hosted-client-direct-json-stale-session-id',
      'stale MCP-Session-Id returned 502',
      status: 502,
    ),
    const _Fault.http(
      'router-hosted-client-direct-json-stale-session-id',
      'stale MCP-Session-Id echoed a session id',
      headers: {'MCP-Session-Id': 'wrong-session'},
    ),
    for (final body in [
      'null',
      '{"id":"wrong-id","result":{}}',
      '{"id":"direct-json-stale-session-id","result":[]}',
    ])
      _Fault.http(
        'router-hosted-client-direct-json-stale-session-id',
        'Direct JSON stale MCP-Session-Id returned',
        responseBody: body,
      ),
    for (final method in ['post', 'get', 'delete'])
      for (final body in [
        'Unsupported MCP protocol version',
        'supportedVersions',
      ])
        _Fault.http(
          'router-hosted-client-streamable-unsupported-protocol-version-$method',
          'did not include the negotiated-version error',
          responseBody: body,
        ),
  ]) {
    test(
      '${fault.trace}: ${fault.status ?? fault.responseBody ?? fault.headers}',
      () => _expectRejected(fault),
    );
  }
  final poll =
      (_fixture['requests'] as List).cast<Map>().singleWhere(
            (row) =>
                (row['headers'] as Map)['x-consumer-trace']?.first ==
                'router-hosted-client-resource-update-poll',
          )['responseBody']
          as String;
  for (final (method, uri) in [
    ('notifications/other', 'app://example/context/live'),
    ('notifications/resources/updated', 'app://other/context'),
  ]) {
    test(
      'resource poll ignores $method for $uri before its matching event',
      () async {
        final irrelevant = jsonEncode({
          'jsonrpc': '2.0',
          'method': method,
          'params': {'uri': uri},
        });
        final fault = _Fault.http(
          'router-hosted-client-resource-update-poll',
          '',
          responseBody: 'id: unrelated-cursor\ndata: $irrelevant\n\n$poll',
        );
        final peer = await _RecordedPeer.start(fault: fault);
        final output = _Output();
        try {
          try {
            await _run(peer, output);
          } on StateError catch (error) {
            fail('A valid unrelated notification must be ignored: $error');
          }
          expect(peer.changed, 1);
          expect(peer._replayed.length, (_fixture['requests'] as List).length);
          expect(output.text.toString(), _fixture['transcript']);
        } finally {
          await peer.close();
        }
      },
    );
  }
  test(
    'resource update notification requires a nonempty SSE id',
    () => _expectRejected(
      _Fault.http(
        'router-hosted-client-resource-update-poll',
        'Resource update notification missed an SSE id.',
        responseBody: poll.replaceAll(
          RegExp(r'^id:.*$', multiLine: true),
          'id:',
        ),
      ),
    ),
  );
}

Future<void> _expectRejected(_Fault fault, {Matcher? exception}) async {
  final peer = await _RecordedPeer.start(fault: fault);
  try {
    await expectLater(
      _run(peer, _Output()),
      throwsA(
        exception ??
            isA<StateError>().having(
              (error) => error.message,
              'specific protocol diagnostic',
              contains(fault.diagnostic),
            ),
      ),
    );
    expect(peer.changed, 1);
    expect(
      peer.afterFault,
      everyElement(isTrue),
      reason: 'Only explicit cleanup may follow the rejected response',
    );
  } finally {
    await peer.close();
  }
}

Future<void> _run(_RecordedPeer peer, _Output output) => IOOverrides.runZoned(
  () => expectOwnedHttpClientsClosed(
    () => runRouterHostedClient([
      '--endpoint',
      'http://127.0.0.1:${peer.server.port}/mcp',
      ..._options,
    ]),
  ),
  stdout: () => output,
  stderr: _Output.new,
);

class _Fault {
  const _Fault(this.id, this.path, this.value, this.diagnostic)
    : trace = null,
      status = null,
      responseBody = null,
      headers = const {};
  const _Fault.http(
    this.trace,
    this.diagnostic, {
    this.status,
    this.responseBody,
    this.headers = const {},
  }) : id = '',
       path = const [],
       value = null;
  final String? trace;
  final int? status;
  final String? responseBody;
  final Map<String, String> headers;
  final String id;
  final List<Object> path;
  final Object? value;
  final String diagnostic;

  String apply(String body, bool sse, void Function() changed) {
    Object? change(Object? envelope) {
      if (envelope is List) return envelope.map(change).toList();
      if (envelope is! Map || envelope['id'] != id) return envelope;
      changed();
      dynamic parent = envelope;
      for (final key in path.take(path.length - 1)) {
        expect(
          parent,
          anyOf(isA<Map>(), isA<List>()),
          reason: 'Recorded fault path $path',
        );
        parent = parent[key];
      }
      expect(parent, anyOf(isA<Map>(), isA<List>()));
      parent[path.last] = value;
      return envelope;
    }

    if (!sse) return jsonEncode(change(jsonDecode(body)));
    return body
        .split('\n')
        .map((line) {
          if (!line.startsWith('data:')) return line;
          final data = line.substring(5).trim();
          return data.isEmpty
              ? line
              : 'data: ${jsonEncode(change(jsonDecode(data)))}';
        })
        .join('\n');
  }
}

class _RecordedPeer {
  _RecordedPeer(this.server, this.fault) {
    server.listen((request) {
      late Future<void> pending;
      pending = _handle(request).whenComplete(() => _pending.remove(pending));
      _pending.add(pending);
    });
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final message = body.isEmpty ? null : jsonDecode(body);
      final id = message is Map ? message['id'] : null;
      final cleanup =
          request.method == 'DELETE' &&
              request.headers.value('x-consumer-trace') == null ||
          id is String &&
              (id.endsWith('-unsubscribe') ||
                  id.endsWith('resource-unsubscribe'));
      if (changed != 0) afterFault.add(cleanup);
      final rows = (_fixture['requests'] as List).cast<Map<String, dynamic>>();
      var index = next;
      if (changed != 0 && cleanup) {
        index = rows.indexWhere(
          (row) =>
              row['method'] == request.method &&
              row['body'] == body &&
              jsonEncode((row['headers'] as Map)['mcp-session-id']) ==
                  jsonEncode(request.headers['mcp-session-id']) &&
              jsonEncode((row['headers'] as Map)['x-consumer-trace']) ==
                  jsonEncode(request.headers['x-consumer-trace']),
          next,
        );
      }
      expect(
        index,
        inInclusiveRange(0, rows.length - 1),
        reason: 'Complete recorded request inventory',
      );
      expect(
        _replayed.add(index),
        isTrue,
        reason: 'Each recorded request may be consumed only once',
      );
      final row = rows[index];
      expect(request.method, row['method']);
      expect(body, row['body']);
      for (final header in [
        'mcp-protocol-version',
        'mcp-session-id',
        'last-event-id',
        'origin',
        'accept',
        'content-type',
        'x-consumer-trace',
      ]) {
        expect(
          request.headers[header],
          (row['headers'] as Map)[header],
          reason: 'Request $index header $header',
        );
      }
      if (index == next) next++;
      final headers = row['responseHeaders'] as Map;
      for (final entry in headers.entries) {
        if (![
          'content-length',
          'transfer-encoding',
          'connection',
          'date',
        ].contains(entry.key)) {
          request.response.headers.set(
            entry.key as String,
            entry.value as List,
          );
        }
      }
      request.response.statusCode = row['status'] as int;
      var response = row['responseBody'] as String;
      final targetsFault =
          fault != null &&
          (fault!.trace != null
              ? request.headers.value('x-consumer-trace') == fault!.trace
              : (id == fault!.id ||
                    message is List &&
                        message.any(
                          (item) => item is Map && item['id'] == fault!.id,
                        )));
      if (targetsFault && changed == 0) {
        if (fault!.trace != null) {
          changed++;
          if (fault!.status case final status?) {
            request.response.statusCode = status;
          }
          for (final entry in fault!.headers.entries) {
            request.response.headers.set(entry.key, entry.value);
          }
          response = fault!.responseBody ?? response;
        } else if (response.isNotEmpty) {
          response = fault!.apply(
            response,
            (headers['content-type'] as List?)?.first.toString().startsWith(
                  'text/event-stream',
                ) ??
                false,
            () => changed++,
          );
        }
      }
      request.response.write(response);
      await request.response.close();
    } catch (error, stack) {
      failures.add((error, stack));
      try {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      } catch (closeError, closeStack) {
        failures.add((closeError, closeStack));
      }
    }
  }

  static Future<_RecordedPeer> start({_Fault? fault}) async => _RecordedPeer(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    fault,
  );
  final HttpServer server;
  final _Fault? fault;
  final failures = <(Object, StackTrace)>[];
  final _pending = <Future<void>>{};
  final afterFault = <bool>[];
  final _replayed = <int>{};
  int changed = 0;
  int next = 0;
  Future<void> close() async {
    await server.close(force: true);
    await Future.wait(List.of(_pending));
    expect(
      failures,
      isEmpty,
      reason: 'Fixture errors must not masquerade as CLI rejections',
    );
  }
}

class _Output implements Stdout {
  final text = StringBuffer();
  @override
  void writeln([Object? value = '']) => text.writeln(value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
