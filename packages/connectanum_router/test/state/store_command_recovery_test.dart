import 'dart:isolate';

import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/snapshot.dart';
import 'package:connectanum_router/src/router/state/store.dart';
import 'package:test/test.dart';

void main() {
  late RouterStateStore store;

  setUp(() {
    final settings = RouterSettingsBuilder()
      ..addRealmFromBuilder(RealmSettingsBuilder('known'))
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('rawsocket', '127.0.0.1:0'),
      );
    store = RouterStateStore(settings: settings.build())..start();
  });

  tearDown(() => store.dispose());

  Future<Object?> request(Object Function(SendPort) command) async {
    final reply = ReceivePort();
    try {
      store.commandPort.send(command(reply.sendPort));
      return await reply.first.timeout(const Duration(seconds: 2));
    } finally {
      reply.close();
    }
  }

  Future<RealmSnapshotResponse> snapshot({int? version}) async =>
      (await request(
            (reply) => RealmSnapshotCommand(
              realmUri: 'known',
              knownVersion: version,
              replyPort: reply,
            ),
          ))
          as RealmSnapshotResponse;

  void expectEmpty(RealmSnapshotResponse response) {
    expect(response.snapshot.realmUri, 'known');
    expect(response.snapshot.sessions, isEmpty);
    expect(response.snapshot.registrations, isEmpty);
    expect(response.snapshot.subscriptions, isEmpty);
  }

  test('enveloped command failure replies and preserves valid realm', () async {
    final before = await snapshot();
    final error = await request(
      (reply) => [
        RealmEnsureCommand(realmUri: 'missing', options: const {}),
        reply,
      ],
    );
    expect(
      error,
      isA<StoreErrorResponse>().having(
        (value) => value.message,
        'message',
        'Bad state: Realm missing is not configured',
      ),
    );
    final after = await snapshot(version: before.snapshot.version);
    expect(after.isNew, isFalse);
    expect(after.snapshot.version, before.snapshot.version);
    expectEmpty(after);
  });

  test('bare and null-reply failures do not stop later commands', () async {
    store.commandPort.send(
      RealmEnsureCommand(realmUri: 'missing', options: const {}),
    );
    store.commandPort.send([
      RealmEnsureCommand(realmUri: 'missing', options: const {}),
      null,
    ]);
    store.commandPort.send(['not a command', null]);
    store.commandPort.send('not a command');
    final response = await snapshot();
    expect(response.isNew, isTrue);
    expectEmpty(response);
  });

  for (final operation in ['snapshot', 'complete', 'touch']) {
    test('$operation missing realm preserves its reply contract', () async {
      final error = await request(
        (reply) => switch (operation) {
          'snapshot' => RealmSnapshotCommand(
            realmUri: 'missing',
            knownVersion: null,
            replyPort: reply,
          ),
          'complete' => InvocationCompleteCommand(
            realmUri: 'missing',
            invocationId: 99,
            replyPort: reply,
          ),
          _ => InvocationTouchCommand(
            realmUri: 'missing',
            invocationId: 99,
            replyPort: reply,
          ),
        },
      );
      if (operation == 'snapshot') {
        expect(
          error,
          isA<StoreErrorResponse>().having(
            (value) => value.message,
            'message',
            'Bad state: Realm missing is not configured',
          ),
        );
      } else {
        expect(error, operation == 'complete' ? isNull : isFalse);
      }
      expectEmpty(await snapshot());
    });
  }

  test('known version works before and after a snapshot is cached', () async {
    final first = await snapshot(version: 0);
    expect(first.isNew, isFalse);
    expect(first.snapshot.version, 0);
    expectEmpty(first);
    final refreshed = await snapshot(version: -1);
    expect(refreshed.isNew, isTrue);
    expect(refreshed.snapshot.version, 0);
    final cached = await snapshot(version: refreshed.snapshot.version);
    expect(cached.isNew, isFalse);
    expect(cached.snapshot.version, refreshed.snapshot.version);
    expectEmpty(cached);
  });
}
