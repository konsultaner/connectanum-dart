import 'dart:async';
import 'dart:isolate';

import 'package:connectanum_router/src/router/http/direct_stream_reply_channel.dart';
import 'package:test/test.dart';

void main() {
  test('routes out-of-order replies to matching waiters', () async {
    final channel = DirectStreamReplyChannel();
    addTearDown(channel.close);

    final controlPort = ReceivePort();
    addTearDown(controlPort.close);

    final seenMessages = <Map<String, Object?>>[];
    final messagesReady = Completer<void>();
    final subscription = controlPort.listen((dynamic message) {
      seenMessages.add(Map<String, Object?>.from(message as Map));
      if (seenMessages.length == 2 && !messagesReady.isCompleted) {
        messagesReady.complete();
      }
    });
    addTearDown(subscription.cancel);

    final first = channel.request(controlPort.sendPort, {
      'type': 'open',
      'requestId': 1,
    });
    final second = channel.request(controlPort.sendPort, {
      'type': 'open',
      'requestId': 2,
    });

    await messagesReady.future;
    final firstReplyRequestId = seenMessages[0]['replyRequestId'] as int;
    final secondReplyRequestId = seenMessages[1]['replyRequestId'] as int;
    expect(firstReplyRequestId, isNot(equals(secondReplyRequestId)));

    channel.sendPort.send({
      'replyRequestId': secondReplyRequestId,
      'handle': 22,
    });
    channel.sendPort.send({
      'replyRequestId': firstReplyRequestId,
      'handle': 11,
    });

    expect((await first)['handle'], 11);
    expect((await second)['handle'], 22);
  });

  test('close fails pending requests', () async {
    final channel = DirectStreamReplyChannel();
    final controlPort = ReceivePort();
    addTearDown(controlPort.close);

    final pending = channel.request(controlPort.sendPort, {
      'type': 'open',
      'requestId': 1,
    });
    channel.close();

    await expectLater(pending, throwsStateError);
  });

  test('recreates its reply port after becoming idle', () async {
    final channel = DirectStreamReplyChannel();
    addTearDown(channel.close);

    final controlPort = ReceivePort();
    addTearDown(controlPort.close);

    final seenMessages = <Map<String, Object?>>[];
    Completer<void>? ready;
    int expectedMessageCount = 0;
    Future<void> waitForMessageCount(int count) {
      if (seenMessages.length >= count) {
        return Future.value();
      }
      expectedMessageCount = count;
      ready = Completer<void>();
      return ready!.future;
    }

    final subscription = controlPort.listen((dynamic message) {
      seenMessages.add(Map<String, Object?>.from(message as Map));
      final pending = ready;
      if (pending != null &&
          !pending.isCompleted &&
          seenMessages.length >= expectedMessageCount) {
        pending.complete();
      }
    });
    addTearDown(subscription.cancel);

    final first = channel.request(controlPort.sendPort, {
      'type': 'open',
      'requestId': 1,
    });
    await waitForMessageCount(1);
    final firstMessage = seenMessages.removeAt(0);
    final firstReplyPort = firstMessage['replyPort'] as SendPort;
    firstReplyPort.send({
      'replyRequestId': firstMessage['replyRequestId'],
      'handle': 1,
    });
    expect((await first)['handle'], 1);

    final second = channel.request(controlPort.sendPort, {
      'type': 'open',
      'requestId': 2,
    });
    await waitForMessageCount(1);
    final secondMessage = seenMessages.removeAt(0);
    final secondReplyPort = secondMessage['replyPort'] as SendPort;
    expect(secondReplyPort, isNot(equals(firstReplyPort)));
    secondReplyPort.send({
      'replyRequestId': secondMessage['replyRequestId'],
      'handle': 2,
    });
    expect((await second)['handle'], 2);
  });
}
