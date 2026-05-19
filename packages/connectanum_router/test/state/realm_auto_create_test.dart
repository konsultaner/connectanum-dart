import 'dart:isolate';

import 'package:connectanum_router/src/router/config/router_settings_builder.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/snapshot.dart';
import 'package:connectanum_router/src/router/state/store.dart';
import 'package:test/test.dart';

void main() {
  late RouterStateStore store;

  setUp(() {
    final settings = RouterSettingsBuilder()
      ..addRealmFromBuilder(
        RealmSettingsBuilder('static.realm')..addAuthMethod('anonymous'),
      )
      ..addRealmFromBuilder(
        RealmSettingsBuilder('lazy.realm')
          ..autoCreate = true
          ..addAuthMethod('anonymous'),
      );

    store = RouterStateStore(settings: settings.build())..start();
  });

  tearDown(() {
    store.dispose();
  });

  test(
    'starts configured static realms and only lazily creates allow-listed realms',
    () async {
      var metrics = await _metrics(store);
      expect(metrics.realmCount, 1);

      final staticSnapshot = await _snapshot(store, 'static.realm');
      expect(staticSnapshot, isA<RealmSnapshotResponse>());
      expect(
        (staticSnapshot as RealmSnapshotResponse).snapshot.realmUri,
        'static.realm',
      );

      metrics = await _metrics(store);
      expect(metrics.realmCount, 1);

      final lazySnapshot = await _snapshot(store, 'lazy.realm');
      expect(lazySnapshot, isA<RealmSnapshotResponse>());
      expect(
        (lazySnapshot as RealmSnapshotResponse).snapshot.realmUri,
        'lazy.realm',
      );

      metrics = await _metrics(store);
      expect(metrics.realmCount, 2);
    },
  );

  test('rejects unknown realms instead of auto-creating them', () async {
    final response = await _snapshot(store, 'unknown.realm');

    expect(response, isA<StoreErrorResponse>());
    expect(
      (response as StoreErrorResponse).message,
      contains('Realm unknown.realm is not configured'),
    );

    final metrics = await _metrics(store);
    expect(metrics.realmCount, 1);
  });
}

Future<RouterStateMetrics> _metrics(RouterStateStore store) async {
  final reply = ReceivePort();
  store.commandPort.send(MetricsSnapshotCommand(replyPort: reply.sendPort));
  final response = await reply.first as RouterStateMetrics;
  reply.close();
  return response;
}

Future<Object?> _snapshot(RouterStateStore store, String realmUri) async {
  final reply = ReceivePort();
  store.commandPort.send(
    RealmSnapshotCommand(
      realmUri: realmUri,
      knownVersion: null,
      replyPort: reply.sendPort,
    ),
  );
  final response = await reply.first;
  reply.close();
  return response;
}
