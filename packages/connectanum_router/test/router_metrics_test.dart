import 'dart:isolate';

import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:connectanum_router/src/router/config/router_settings_builder.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_listener.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/session.dart';
import 'package:connectanum_router/src/router/state/store.dart';
import 'package:connectanum_router/src/router/state/subscription.dart';
import 'package:test/test.dart';

void main() {
  late RouterStateStore store;

  setUp(() {
    final settings = RouterSettingsBuilder()
      ..addRealmFromBuilder(
        RealmSettingsBuilder('realm1')
          ..addAuthMethod('anonymous')
          ..addRoleFromBuilder(
            RoleSettingsBuilder('member')..addPermissionFromBuilder(
              PermissionSettingsBuilder('')
                ..setMatchPolicy(PermissionMatchPolicy.prefix)
                ..allowOperations(const [
                  'subscribe',
                  'publish',
                  'call',
                  'register',
                ]),
            ),
          ),
      )
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addAuthMethod('anonymous')
          ..setOptions(const {'max_rawsocket_size_exponent': 16}),
      );
    store = RouterStateStore(settings: settings.build())..start();
  });

  tearDown(() {
    store.dispose();
  });

  test('collects state metrics snapshot', () async {
    final now = DateTime.now();
    final session1 = SessionRecord(
      id: 1001,
      authId: 'caller',
      authRole: 'member',
      roles: const {},
      workerId: 0,
      connectionId: 10,
      lastActivity: now,
      listener: _dummyListener(),
    );
    final session2 = SessionRecord(
      id: 1002,
      authId: 'callee',
      authRole: 'member',
      roles: const {},
      workerId: 0,
      connectionId: 11,
      lastActivity: now,
      listener: _dummyListener(),
    );

    store.commandPort.send(
      SessionOpenCommand(realmUri: 'realm1', session: session1),
    );
    store.commandPort.send(
      SessionOpenCommand(realmUri: 'realm1', session: session2),
    );
    await Future<void>.delayed(Duration.zero);

    final subscriptionReply = ReceivePort();
    store.commandPort.send(
      SubscriptionAddCommand(
        realmUri: 'realm1',
        sessionId: session1.id,
        topic: 'com.example.topic',
        matchPolicy: TopicMatchPolicy.exact,
        details: const {},
        replyPort: subscriptionReply.sendPort,
      ),
    );
    final subscriptionId = await subscriptionReply.first as int;
    subscriptionReply.close();
    expect(subscriptionId, greaterThan(0));

    final registrationReply = ReceivePort();
    store.commandPort.send(
      ProcedureRegisterCommand(
        realmUri: 'realm1',
        sessionId: session2.id,
        procedure: 'com.example.proc',
        details: const {},
        replyPort: registrationReply.sendPort,
      ),
    );
    final registrationId = await registrationReply.first as int;
    registrationReply.close();
    expect(registrationId, greaterThan(0));

    final matchReply = ReceivePort();
    store.commandPort.send(
      SubscriptionMatchCommand(
        realmUri: 'realm1',
        topic: 'com.example.topic',
        publisherSessionId: session1.id,
        options: const {},
        replyPort: matchReply.sendPort,
      ),
    );
    await matchReply.first;
    matchReply.close();

    final invocationReply = ReceivePort();
    store.commandPort.send(
      InvocationDispatchCommand(
        realmUri: 'realm1',
        callerSessionId: session1.id,
        requestId: 5001,
        procedure: 'com.example.proc',
        options: const {},
        replyPort: invocationReply.sendPort,
      ),
    );
    final dispatch = await invocationReply.first;
    invocationReply.close();
    expect(dispatch, isA<InvocationDispatchResult>());
    final invocationId = (dispatch as InvocationDispatchResult).invocationId;

    final metricsReply = ReceivePort();
    store.commandPort.send(
      MetricsSnapshotCommand(replyPort: metricsReply.sendPort),
    );
    final metrics = await metricsReply.first as RouterStateMetrics;
    metricsReply.close();

    expect(metrics.realmCount, 1);
    expect(metrics.sessionCount, 2);
    expect(metrics.subscriptionCount, 1);
    expect(metrics.registrationCount, 1);
    expect(metrics.pendingInvocationCount, 1);
    expect(metrics.totalInvocationsDispatched, 1);
    expect(metrics.totalPublicationsRouted, 1);

    final completionReply = ReceivePort();
    store.commandPort.send(
      InvocationCompleteCommand(
        realmUri: 'realm1',
        invocationId: invocationId,
        replyPort: completionReply.sendPort,
      ),
    );
    await completionReply.first;
    completionReply.close();

    final metricsReply2 = ReceivePort();
    store.commandPort.send(
      MetricsSnapshotCommand(replyPort: metricsReply2.sendPort),
    );
    final metricsAfter = await metricsReply2.first as RouterStateMetrics;
    metricsReply2.close();

    expect(metricsAfter.pendingInvocationCount, 0);
    expect(metricsAfter.totalInvocationsDispatched, 1);
    expect(metricsAfter.totalPublicationsRouted, 1);
    expect(metricsAfter.subscriptionCount, 1);
    expect(metricsAfter.registrationCount, 1);
    expect(metricsAfter.sessionCount, 2);
    expect(metricsAfter.realmCount, 1);
    expect(metricsAfter, isA<RouterStateMetrics>());
  });
}

RouterListener _dummyListener() => RouterListener(
  listenerId: -1,
  endpoint: Endpoint(
    host: '127.0.0.1',
    port: 0,
    tlsMode: TlsMode.disabled,
    maxRawSocketSizeExponent: 16,
  ),
  port: 0,
  http3Port: 0,
);
