import 'dart:convert';

import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

import 'support/expect_valid.dart';

const _payload = '\u20ac\u{1f680}';
const _first = McpWampEvent(
  subscriptionId: 7,
  publicationId: 100,
  arguments: [_payload],
);
const _second = McpWampEvent(
  subscriptionId: 7,
  publicationId: 101,
  arguments: [_payload],
);
const _firstJson = <String, Object?>{
  'subscriptionId': 7,
  'publicationId': 100,
  'arguments': [_payload],
};
const _secondJson = <String, Object?>{
  'subscriptionId': 7,
  'publicationId': 101,
  'arguments': [_payload],
};

void main() {
  final encodedLength = utf8.encode(jsonEncode(_firstJson)).length;

  for (final adjustment in [-1, 0, 1]) {
    test('event at byte-limit boundary adjustment $adjustment', () async {
      final probe = await _subscribe(encodedLength + adjustment);
      probe.add(_first);
      final result = await probe.poll();
      expect(result['events'], adjustment < 0 ? isEmpty : [_firstJson]);
      expect(result['dropped'], adjustment < 0 ? 1 : 0);
      expect(result['remaining'], 0);
      expect(result['remainingBytes'], 0);
    });
  }

  test('UTF-8 byte limit is not a UTF-16 character limit', () async {
    final characterLength = jsonEncode(_firstJson).length;
    expect(encodedLength, greaterThan(characterLength));
    final probe = await _subscribe(characterLength);
    probe.add(_first);
    final result = await probe.poll();
    expect(result['events'], isEmpty);
    expect(result['dropped'], 1);
    expect(result['remainingBytes'], 0);
  });

  test('oversized event preserves a full valid queue', () async {
    final probe = await _subscribe(encodedLength);
    probe.add(_first);
    probe.add(
      const McpWampEvent(
        subscriptionId: 7,
        publicationId: 101,
        arguments: ['$_payload!'],
      ),
    );
    final result = await probe.poll();
    expect(result['events'], [_firstJson]);
    expect(result['dropped'], 1);
    expect(result['remainingBytes'], 0);
  });

  test('exact-limit replacement evicts only the oldest event', () async {
    final probe = await _subscribe(encodedLength);
    probe.add(_first);
    probe.add(_second);
    final result = await probe.poll();
    expect(result['events'], [_secondJson]);
    expect(result['dropped'], 1);
    expect(result['remaining'], 0);
    expect(result['remainingBytes'], 0);
  });

  test('partial drain frees exactly enough bytes for a refill', () async {
    final probe = await _subscribe(encodedLength * 2);
    probe.add(_first);
    probe.add(_second);
    final first = await probe.poll(limit: 1);
    expect(first['events'], [_firstJson]);
    expect(first['dropped'], 0);
    expect(first['remaining'], 1);
    expect(first['remainingBytes'], encodedLength);

    probe.add(_first);
    final remaining = await probe.poll();
    expect(remaining['events'], [_secondJson, _firstJson]);
    expect(remaining['dropped'], 0);
    expect(remaining['remaining'], 0);
    expect(remaining['remainingBytes'], 0);
  });

  test('event count still evicts when the byte budget has space', () async {
    final probe = await _subscribe(encodedLength * 2, queueLimit: 1);
    probe.add(_first);
    probe.add(_second);
    final result = await probe.poll();
    expect(result['events'], [_secondJson]);
    expect(result['dropped'], 1);
    expect(result['remaining'], 0);
    expect(result['remainingBytes'], 0);
  });
}

Future<_BufferProbe> _subscribe(int byteLimit, {int queueLimit = 10}) async {
  final probe = _BufferProbe(byteLimit);
  final result = await probe.call('subscribe', {
    'topic': 'app.events',
    'queueLimit': queueLimit,
  });
  expect(result['queueByteLimit'], byteLimit);
  probe.handle = result['handle'] as String;
  addTearDown(() async {
    final result = await probe.call('unsubscribe', {'handle': probe.handle});
    expect(result['unsubscribed'], isTrue);
    expect(probe.released, hasLength(1));
    expect(probe.released.single.subscriptionId, 7);
  });
  return probe;
}

class _BufferProbe {
  _BufferProbe(int byteLimit) {
    tools = McpWampApi(topics: [McpWampTopic(topic: 'app.events')]).toTools(
      subscribe: (request, onEvent) {
        _onEvent = onEvent;
        return McpWampSubscription(topic: request.topic, subscriptionId: 7);
      },
      unsubscribe: released.add,
      maxBufferedEventBytes: byteLimit,
    );
  }

  late final List<McpTool> tools;
  late final String handle;
  late void Function(McpWampEvent) _onEvent;
  final released = <McpWampSubscription>[];

  void add(McpWampEvent event) => expectValid(() => _onEvent(event));

  Future<Map<String, Object?>> call(
    String operation,
    Map<String, Object?> arguments,
  ) async {
    final name = 'connectanum.pubsub.$operation';
    final tool = tools.singleWhere((tool) => tool.name == name);
    final result = await expectValidAsync(
      () async =>
          tool.handler(McpToolRequest(name: name, arguments: arguments)),
    );
    expect(result.isError, isFalse);
    expect(result.structuredContent, isA<Map<String, Object?>>());
    return result.structuredContent as Map<String, Object?>;
  }

  Future<Map<String, Object?>> poll({int? limit}) => call('poll', {
    'handle': handle,
    'limit': ?limit,
  });
}
