import 'dart:isolate';

import 'package:connectanum_router/connectanum_router.dart' hide Error;
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/session.dart';
import 'package:connectanum_router/src/router/state/store.dart';
import 'package:test/test.dart';

void main() {
  test(
    'only an active invocation owner resolves its original caller',
    () async {
      final settings = RouterSettingsBuilder()
        ..addRealmFromBuilder(RealmSettingsBuilder('a'))
        ..addRealmFromBuilder(RealmSettingsBuilder('b'));
      final store = RouterStateStore(settings: settings.build())..start();
      addTearDown(store.dispose);
      Future<Object?> request(Object Function(SendPort) make) async {
        final reply = ReceivePort();
        try {
          store.commandPort.send(make(reply.sendPort));
          return await reply.first.timeout(const Duration(seconds: 2));
        } finally {
          reply.close();
        }
      }

      for (final id in [1, 2]) {
        store.commandPort.send(
          SessionOpenCommand(
            realmUri: 'a',
            session: SessionRecord(
              id: id,
              authId: 'original-$id',
              authRole: 'member',
              authMethod: 'ticket',
              authProvider: 'trusted',
              roles: const {},
              workerId: 3,
              connectionId: 100 + id,
              lastActivity: DateTime.utc(2026),
              listener: RouterListener(
                listenerId: 1,
                endpoint: Endpoint(
                  host: '127.0.0.1',
                  port: 0,
                  tlsMode: TlsMode.disabled,
                  maxRawSocketSizeExponent: 16,
                ),
                port: 0,
                http3Port: 0,
              ),
              protocol: ListenerProtocol.rawsocket,
            ),
          ),
        );
      }
      await request(
        (reply) => ProcedureRegisterCommand(
          realmUri: 'a',
          sessionId: 1,
          procedure: 'gateway.publish',
          details: const {},
          replyPort: reply,
        ),
      );
      final dispatch =
          await request(
                (reply) => InvocationDispatchCommand(
                  realmUri: 'a',
                  callerSessionId: 2,
                  requestId: 9,
                  procedure: 'gateway.publish',
                  options: const {
                    'caller': 1,
                    'caller_authrole': 'administrator',
                  },
                  replyPort: reply,
                ),
              )
              as InvocationDispatchResult;
      Future<Object?> caller({
        String realm = 'a',
        int? invocation,
        int callee = 1,
      }) => request(
        (reply) => InvocationCallerCommand(
          realmUri: realm,
          invocationId: invocation ?? dispatch.invocationId,
          calleeSessionId: callee,
          replyPort: reply,
        ),
      );
      final actual = await caller() as SessionInfo;
      expect(actual.id, 2);
      expect(actual.authId, 'original-2');
      expect(actual.authRole, 'member');
      expect(actual.authMethod, 'ticket');
      expect(actual.authProvider, 'trusted');
      expect(actual.connectionId, 102);
      expect(actual.protocol, ListenerProtocol.rawsocket);
      expect(await caller(callee: 2), isNull);
      expect(await caller(realm: 'b'), isNull);
      expect(await caller(invocation: -1), isNull);
      expect(await caller(realm: 'unknown'), isA<StoreErrorResponse>());
      store.commandPort.send(SessionCloseCommand(realmUri: 'a', sessionId: 2));
      expect(await caller(), isNull);
    },
  );
}
