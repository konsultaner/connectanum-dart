import 'dart:async';
import 'dart:isolate';

import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:connectanum_router/src/router/config/router_settings_builder.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_listener.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/session.dart';
import 'package:connectanum_router/src/router/state/store.dart';
import 'package:test/test.dart';

void main() {
  const realm = 'realm1';
  late RouterStateStore store;
  late RealmContextCache realmContexts;
  late RealmContext context;

  setUp(() async {
    final settings = RouterSettingsBuilder()
      ..addRealmFromBuilder(
        RealmSettingsBuilder(realm)
          ..addAuthMethod('anonymous')
          ..addRoleFromBuilder(
            RoleSettingsBuilder('member')..addPermissionFromBuilder(
              PermissionSettingsBuilder('')
                ..setMatchPolicy(PermissionMatchPolicy.prefix)
                ..allowOperations(const ['call', 'register']),
            ),
          ),
      )
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addAuthMethod('anonymous'),
      );
    store = RouterStateStore(settings: settings.build())..start();
    realmContexts = RealmContextCache(statePort: store.commandPort);
    context = realmContexts.contextFor(realm);
    for (final session in [
      _session(1001, 11, 'caller-a'),
      _session(1002, 12, 'caller-b'),
      _session(2001, 21, 'callee-a'),
      _session(2002, 22, 'callee-b'),
    ]) {
      store.commandPort.send(
        SessionOpenCommand(realmUri: realm, session: session),
      );
    }
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    realmContexts.dispose();
    store.dispose();
  });

  test('throttle shares hashes and releases on completion', () async {
    const procedure = 'com.example.checkout';
    final details = {
      'invoke': 'roundrobin',
      'auto_deduplication': 0,
      'auto_deduplication_capacity': 4,
      'auto_deduplication_expiry': 1000,
    };
    await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: details,
    );
    await context.registerProcedure(
      sessionId: 2002,
      procedure: procedure,
      details: details,
    );

    final first = await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 1,
      procedure: procedure,
      options: const {'transaction_hash': 'order:42'},
    );
    await expectLater(
      context.dispatchInvocation(
        callerSessionId: 1002,
        requestId: 2,
        procedure: procedure,
        options: const {'transaction_hash': 'order:42'},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(wamp.Error.autoDeduplication),
        ),
      ),
    );

    var metrics = await _metrics(store);
    expect(metrics.retryDeduplicationActiveCount, 1);
    expect(metrics.totalRetryDeduplicationThrottleRejects, 1);
    expect(metrics.totalInvocationsDispatched, 1);

    await context.completeInvocation(first.invocationId);
    final retried = await context.dispatchInvocation(
      callerSessionId: 1002,
      requestId: 3,
      procedure: procedure,
      options: const {'transaction_hash': 'order:42'},
    );
    expect(retried.calleeSessionId, isNot(first.calleeSessionId));

    metrics = await _metrics(store);
    expect(metrics.retryDeduplicationActiveCount, 1);
    expect(metrics.totalInvocationsDispatched, 2);
  });

  test('progressive chunks reuse one throttle lease', () async {
    const procedure = 'com.example.upload';
    await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: const {
        'auto_deduplication': 0,
        'auto_deduplication_capacity': 2,
        'auto_deduplication_expiry': 1000,
      },
    );

    final first = await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 10,
      procedure: procedure,
      options: const {'progress': true, 'transaction_hash': 'upload:1'},
    );
    final finalChunk = await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 10,
      procedure: procedure,
      options: const {'progress': false, 'transaction_hash': 'upload:1'},
    );
    expect(finalChunk.invocationId, first.invocationId);
    await expectLater(
      context.dispatchInvocation(
        callerSessionId: 1002,
        requestId: 11,
        procedure: procedure,
        options: const {'transaction_hash': 'upload:1'},
      ),
      throwsA(isA<StateError>()),
    );
    expect((await _metrics(store)).retryDeduplicationActiveCount, 1);
  });

  test('debounce replaces older calls and dispatches the latest', () async {
    const procedure = 'com.example.search';
    await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: const {
        'auto_deduplication': 40,
        'auto_deduplication_capacity': 2,
        'auto_deduplication_expiry': 250,
      },
    );

    final first = context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 20,
      procedure: procedure,
      options: const {'transaction_hash': 'search:dart'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = context.dispatchInvocation(
      callerSessionId: 1002,
      requestId: 21,
      procedure: procedure,
      options: const {'transaction_hash': 'search:dart'},
    );

    await expectLater(
      first,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(wamp.Error.autoDeduplication),
        ),
      ),
    );
    final dispatched = await second.timeout(const Duration(seconds: 1));
    final pending = await context.getInvocation(dispatched.invocationId);
    expect(pending?.callerRequestId, 21);
    expect(pending?.callerSessionId, 1002);

    final metrics = await _metrics(store);
    expect(metrics.retryDeduplicationActiveCount, 0);
    expect(metrics.totalRetryDeduplicationDebounceReplacements, 1);
    expect(metrics.totalInvocationsDispatched, 1);
  });

  test(
    'capacity is bounded and expired throttle leases are reclaimed',
    () async {
      const procedure = 'com.example.capacity';
      await context.registerProcedure(
        sessionId: 2001,
        procedure: procedure,
        details: const {
          'auto_deduplication': 0,
          'auto_deduplication_capacity': 1,
          'auto_deduplication_expiry': 35,
        },
      );
      await context.dispatchInvocation(
        callerSessionId: 1001,
        requestId: 30,
        procedure: procedure,
        options: const {'transaction_hash': 'capacity:a'},
      );
      await expectLater(
        context.dispatchInvocation(
          callerSessionId: 1002,
          requestId: 31,
          procedure: procedure,
          options: const {'transaction_hash': 'capacity:b'},
        ),
        throwsA(isA<StateError>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 70));
      await context.dispatchInvocation(
        callerSessionId: 1002,
        requestId: 32,
        procedure: procedure,
        options: const {'transaction_hash': 'capacity:b'},
      );
      final metrics = await _metrics(store);
      expect(metrics.retryDeduplicationActiveCount, 1);
      expect(metrics.totalRetryDeduplicationCapacityRejects, 1);
      expect(metrics.totalRetryDeduplicationExpirations, 1);
    },
  );

  test('cancel and timeout release throttle leases', () async {
    const procedure = 'com.example.lifecycle';
    await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: const {
        'auto_deduplication': 0,
        'auto_deduplication_capacity': 2,
        'auto_deduplication_expiry': 1000,
      },
    );
    final canceled = await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 40,
      procedure: procedure,
      options: const {'transaction_hash': 'lifecycle:cancel'},
    );
    expect(
      await context.cancelInvocation(
        invocationId: canceled.invocationId,
        mode: 'killnowait',
        waitForAck: false,
      ),
      isTrue,
    );
    await context.dispatchInvocation(
      callerSessionId: 1002,
      requestId: 41,
      procedure: procedure,
      options: const {'transaction_hash': 'lifecycle:cancel'},
    );

    final timeoutEvent = store.invocationTimeoutEvents.first;
    await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 42,
      procedure: procedure,
      options: const {
        'transaction_hash': 'lifecycle:timeout',
        'timeout': 25,
      },
    );
    await timeoutEvent.timeout(const Duration(seconds: 1));
    await context.dispatchInvocation(
      callerSessionId: 1002,
      requestId: 43,
      procedure: procedure,
      options: const {'transaction_hash': 'lifecycle:timeout'},
    );
  });

  test('caller close cancels a pending debounce without dispatching', () async {
    const procedure = 'com.example.disconnect';
    await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: const {
        'auto_deduplication': 100,
        'auto_deduplication_capacity': 2,
        'auto_deduplication_expiry': 500,
      },
    );
    final pending = context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 50,
      procedure: procedure,
      options: const {'transaction_hash': 'disconnect:1'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    store.commandPort.send(
      SessionCloseCommand(realmUri: realm, sessionId: 1001),
    );

    await expectLater(
      pending.timeout(const Duration(seconds: 1)),
      throwsA(isA<StateError>()),
    );
    final metrics = await _metrics(store);
    expect(metrics.retryDeduplicationActiveCount, 0);
    expect(metrics.totalInvocationsDispatched, 0);
  });

  test('session close releases active throttle leases', () async {
    const procedure = 'com.example.disconnect.active';
    await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: const {
        'auto_deduplication': 0,
        'auto_deduplication_capacity': 2,
        'auto_deduplication_expiry': 1000,
      },
    );
    await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 55,
      procedure: procedure,
      options: const {'transaction_hash': 'disconnect:active'},
    );
    store.commandPort.send(
      SessionCloseCommand(realmUri: realm, sessionId: 1001),
    );
    await Future<void>.delayed(Duration.zero);

    await context.dispatchInvocation(
      callerSessionId: 1002,
      requestId: 56,
      procedure: procedure,
      options: const {'transaction_hash': 'disconnect:active'},
    );
    expect((await _metrics(store)).retryDeduplicationActiveCount, 1);
  });

  test('rejects malformed and mismatched registration policies', () async {
    const procedure = 'com.example.invalid';
    await expectLater(
      context.registerProcedure(
        sessionId: 2001,
        procedure: procedure,
        details: const {'auto_deduplication': -1},
      ),
      throwsA(isA<StateError>()),
    );
    await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: const {
        'invoke': 'roundrobin',
        'auto_deduplication': 0,
      },
    );
    await expectLater(
      context.registerProcedure(
        sessionId: 2002,
        procedure: procedure,
        details: const {
          'invoke': 'roundrobin',
          'auto_deduplication': 25,
        },
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      context.dispatchInvocation(
        callerSessionId: 1001,
        requestId: 60,
        procedure: procedure,
        options: const {'transaction_hash': ''},
      ),
      throwsA(isA<StateError>()),
    );
  });
}

Future<RouterStateMetrics> _metrics(RouterStateStore store) async {
  final reply = ReceivePort();
  store.commandPort.send(MetricsSnapshotCommand(replyPort: reply.sendPort));
  final metrics = await reply.first as RouterStateMetrics;
  reply.close();
  return metrics;
}

SessionRecord _session(int id, int connectionId, String authId) =>
    SessionRecord(
      id: id,
      authId: authId,
      authRole: 'member',
      roles: const {},
      workerId: 0,
      connectionId: connectionId,
      lastActivity: DateTime.now(),
      listener: _dummyListener(),
    );

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
