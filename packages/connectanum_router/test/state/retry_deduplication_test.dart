import 'dart:async';
import 'dart:isolate';

import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:connectanum_router/src/router/models/endpoint.dart';
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
  var disposed = false;

  setUp(() async {
    disposed = false;
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
    if (!disposed) store.dispose();
  });

  for (final (callerOption, calleeOption, disclosed)
      in <(Object?, Object?, bool)>[
        (false, false, false),
        (true, false, true),
        (false, true, true),
        (true, true, true),
        (null, null, false),
        ('true', null, false),
        (null, 'true', false),
        (1, null, false),
        (null, 1, false),
      ]) {
    test(
      'caller disclosure $callerOption/$calleeOption stays frozen across chunks',
      () async {
        const procedure = 'com.example.disclosure';
        final registration = await context.registerProcedure(
          sessionId: 2001,
          procedure: procedure,
          details: {'disclose_caller': ?calleeOption},
        );
        final options = <String, Object?>{
          'disclose_me': ?callerOption,
          'receive_progress': true,
          'trace_id': 'initial',
        };
        final first = await context.dispatchInvocation(
          callerSessionId: 1001,
          requestId: 80,
          procedure: procedure,
          options: {...options, 'progress': true},
        );
        final expectedIdentity = <Object?>[
          disclosed ? 1001 : null,
          disclosed ? 'caller-a' : null,
          disclosed ? 'member' : null,
        ];
        expect(first.registrationId, registration);
        expect(first.calleeSessionId, 2001);
        expect([
          first.disclosedCallerSessionId,
          first.disclosedCallerAuthId,
          first.disclosedCallerAuthRole,
        ], expectedIdentity);
        expect(first.initiatingOptions, options);
        expect(first.progressiveInvocation, isTrue);
        expect(first.progress, isTrue);

        final last = await context.dispatchInvocation(
          callerSessionId: 1001,
          requestId: 80,
          procedure: procedure,
          options: {
            'progress': false,
            'disclose_me': !disclosed,
            'receive_progress': false,
            'trace_id': 'changed',
          },
        );
        expect(last.invocationId, first.invocationId);
        expect(last.registrationId, registration);
        expect(last.calleeSessionId, 2001);
        expect([
          last.disclosedCallerSessionId,
          last.disclosedCallerAuthId,
          last.disclosedCallerAuthRole,
        ], expectedIdentity);
        expect(last.initiatingOptions, options);
        expect(last.progressiveInvocation, isTrue);
        expect(last.progress, isFalse);
        final record = await context.getInvocation(first.invocationId);
        expect(record, isNotNull);
        expect([
          record!.disclosedCallerSessionId,
          record.disclosedCallerAuthId,
          record.disclosedCallerAuthRole,
        ], expectedIdentity);
        expect(record.initiatingOptions, options);
        expect(record.allowProgress, isTrue);
        expect(record.progressiveInvocationOpen, isFalse);
        expect((await _metrics(store)).totalInvocationsDispatched, 1);
        await context.completeInvocation(first.invocationId);
        expect(await context.getInvocation(first.invocationId), isNull);
      },
    );
  }

  test('progressive rejection preserves the original invocation', () async {
    const procedure = 'com.example.progressive.recovery';
    const otherProcedure = 'com.example.progressive.other';
    final registration = await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: const {},
    );
    await context.registerProcedure(
      sessionId: 2002,
      procedure: otherProcedure,
      details: const {},
    );
    final first = await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 81,
      procedure: procedure,
      options: const {'progress': true, 'trace_id': 'initial'},
    );
    await expectLater(
      context.dispatchInvocation(
        callerSessionId: 1001,
        requestId: 81,
        procedure: otherProcedure,
        options: const {'progress': false, 'trace_id': 'rejected'},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Bad state: Invalid progressive invocation: procedure changed from '
              '$procedure to $otherProcedure',
        ),
      ),
    );
    var record = await context.getInvocation(first.invocationId);
    expect(record, isNotNull);
    expect(record!.procedure, procedure);
    expect(record.progressiveInvocationOpen, isTrue);
    expect(record.initiatingOptions, {'trace_id': 'initial'});
    expect(record.registrationId, registration);
    expect(record.calleeSessionId, 2001);
    expect((await _metrics(store)).pendingInvocationCount, 1);

    final last = await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 81,
      procedure: procedure,
      options: const {'progress': false},
    );
    expect(last.invocationId, first.invocationId);
    expect(last.registrationId, registration);
    expect(last.calleeSessionId, 2001);
    expect(last.progressiveInvocation, isTrue);
    expect(last.progress, isFalse);
    await expectLater(
      context.dispatchInvocation(
        callerSessionId: 1001,
        requestId: 81,
        procedure: procedure,
        options: const {'progress': true},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Bad state: Invalid progressive invocation: invocation '
              '${first.invocationId} is not accepting more chunks',
        ),
      ),
    );
    record = await context.getInvocation(first.invocationId);
    expect(record, isNotNull);
    expect(record!.progressiveInvocationOpen, isFalse);
    expect(record.initiatingOptions, {'trace_id': 'initial'});
    expect((await _metrics(store)).totalInvocationsDispatched, 1);
    await context.completeInvocation(first.invocationId);
    final next = await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 82,
      procedure: procedure,
      options: const {},
    );
    expect(next.invocationId, isNot(first.invocationId));
    expect(next.registrationId, registration);
    expect(next.calleeSessionId, 2001);
    expect(next.progressiveInvocation, isFalse);
    expect((await _metrics(store)).totalInvocationsDispatched, 2);
    await context.completeInvocation(next.invocationId);
    expect((await _metrics(store)).pendingInvocationCount, 0);
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

  for (final capacity in [1, 2, 3]) {
    for (final debounce in [false, true]) {
      test(
        'capacity $capacity is registration-local with debounce=$debounce',
        () async {
          for (final procedure in [
            'com.example.capacity.a',
            'com.example.capacity.b',
          ]) {
            await context.registerProcedure(
              sessionId: 2001,
              procedure: procedure,
              details: {
                'auto_deduplication': debounce ? 50000 : 0,
                'auto_deduplication_capacity': capacity,
                'auto_deduplication_expiry': 60000,
              },
            );
          }
          final pending = <Future<Object>>[];
          Future<void> admit(String procedure, int caller, int request) async {
            final result = context
                .dispatchInvocation(
                  callerSessionId: caller,
                  requestId: request,
                  procedure: procedure,
                  options: {'transaction_hash': 'capacity:$request'},
                )
                .then<Object>(
                  (value) => value,
                  onError: (Object error) => error,
                );
            if (debounce) {
              pending.add(result);
            } else {
              expect(await result, isA<InvocationDispatchResult>());
            }
          }

          for (var index = 0; index < capacity; index++) {
            await admit('com.example.capacity.a', 1001, 300 + index);
            expect(
              (await _metrics(store)).retryDeduplicationActiveCount,
              index + 1,
            );
          }
          final rejected = context
              .dispatchInvocation(
                callerSessionId: 1001,
                requestId: 400,
                procedure: 'com.example.capacity.a',
                options: const {'transaction_hash': 'over-capacity'},
              )
              .then<Object>((value) => value, onError: (Object error) => error);
          final boundary = await _metrics(store);
          expect(boundary.totalRetryDeduplicationCapacityRejects, 1);
          expect(boundary.retryDeduplicationActiveCount, capacity);
          expect(
            await rejected.timeout(const Duration(seconds: 2)),
            isA<StateError>().having(
              (error) => error.message,
              'capacity reason',
              contains('${wamp.Error.autoDeduplication}: capacity exceeded'),
            ),
          );
          await admit('com.example.capacity.b', 1002, 500);
          final full = await _metrics(store);
          expect(full.retryDeduplicationActiveCount, capacity + 1);
          expect(full.totalRetryDeduplicationCapacityRejects, 1);
          expect(full.pendingInvocationCount, debounce ? 0 : capacity + 1);
          store.commandPort.send(
            SessionCloseCommand(realmUri: realm, sessionId: 1001),
          );
          expect((await _metrics(store)).retryDeduplicationActiveCount, 1);
          await admit('com.example.capacity.a', 1002, 501);
          expect((await _metrics(store)).retryDeduplicationActiveCount, 2);
          store.commandPort.send(
            SessionCloseCommand(realmUri: realm, sessionId: 1002),
          );
          final cleared = await _metrics(store);
          expect(cleared.retryDeduplicationActiveCount, 0);
          expect(cleared.pendingInvocationCount, 0);
          for (final result in pending) {
            expect(
              await result.timeout(const Duration(seconds: 2)),
              isA<StateError>(),
            );
          }
        },
      );
    }
  }

  for (final waitForAck in [false, true]) {
    test(
      'cancel retains a throttle lease only while awaiting ack=$waitForAck',
      () async {
        const procedure = 'com.example.cancel.ack';
        await context.registerProcedure(
          sessionId: 2001,
          procedure: procedure,
          details: const {'auto_deduplication': 0},
        );
        final first = await context.dispatchInvocation(
          callerSessionId: 1001,
          requestId: 90,
          procedure: procedure,
          options: const {'transaction_hash': 'cancel-ack'},
        );
        final mode = waitForAck ? 'kill' : 'killnowait';
        expect(
          await context.cancelInvocation(
            invocationId: first.invocationId,
            mode: mode,
            waitForAck: waitForAck,
          ),
          isTrue,
        );
        final record = await context.getInvocation(first.invocationId);
        if (waitForAck) {
          expect(record, isNotNull);
          expect(record!.cancelRequested, isTrue);
          expect(record.cancelMode, 'kill');
          expect(record.waitForCancelAck, isTrue);
          await expectLater(
            context.dispatchInvocation(
              callerSessionId: 1002,
              requestId: 91,
              procedure: procedure,
              options: const {'transaction_hash': 'cancel-ack'},
            ),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains(wamp.Error.autoDeduplication),
              ),
            ),
          );
        } else {
          expect(record, isNull);
        }
        final metrics = await _metrics(store);
        expect(metrics.pendingInvocationCount, waitForAck ? 1 : 0);
        expect(metrics.retryDeduplicationActiveCount, waitForAck ? 1 : 0);
        if (waitForAck) {
          await context.completeInvocation(first.invocationId);
        }
        final recovered = await context.dispatchInvocation(
          callerSessionId: 1002,
          requestId: 92,
          procedure: procedure,
          options: const {'transaction_hash': 'cancel-ack'},
        );
        expect(recovered.invocationId, isNot(first.invocationId));
        await context.completeInvocation(recovered.invocationId);
        expect((await _metrics(store)).retryDeduplicationActiveCount, 0);
      },
    );
  }

  test(
    'closing a callee releases only its invocations and retry leases',
    () async {
      final calls = <InvocationDispatchResult>[];
      for (final callee in [2001, 2002]) {
        final procedure = 'com.example.callee.$callee';
        await context.registerProcedure(
          sessionId: callee,
          procedure: procedure,
          details: const {'auto_deduplication': 0},
        );
        calls.add(
          await context.dispatchInvocation(
            callerSessionId: 1001,
            requestId: callee,
            procedure: procedure,
            options: const {'transaction_hash': 'same-hash'},
          ),
        );
      }
      expect((await _metrics(store)).pendingInvocationCount, 2);
      expect((await _metrics(store)).retryDeduplicationActiveCount, 2);
      store.commandPort.send(
        SessionCloseCommand(realmUri: realm, sessionId: 2001),
      );
      expect(await context.getInvocation(calls.first.invocationId), isNull);
      final remaining = await context.getInvocation(calls.last.invocationId);
      expect(remaining, isNotNull);
      expect(remaining!.calleeSessionId, 2002);
      expect(remaining.callerSessionId, 1001);
      expect((await _metrics(store)).pendingInvocationCount, 1);
      expect((await _metrics(store)).retryDeduplicationActiveCount, 1);
      expect(await context.touchInvocation(calls.first.invocationId), isFalse);
      expect(await context.touchInvocation(calls.last.invocationId), isTrue);
      await context.completeInvocation(calls.last.invocationId);
      expect((await _metrics(store)).pendingInvocationCount, 0);
      expect((await _metrics(store)).retryDeduplicationActiveCount, 0);
    },
  );

  for (final forwarded in [false, true]) {
    test(
      'touch preserves an existing invocation with forwarding $forwarded',
      () async {
        const procedure = 'com.example.touch';
        await context.registerProcedure(
          sessionId: 2001,
          procedure: procedure,
          details: {'forward_timeout': forwarded},
        );
        final call = await context.dispatchInvocation(
          callerSessionId: 1001,
          requestId: 98,
          procedure: procedure,
          options: forwarded ? const {'timeout': 50000} : const {},
        );
        expect(await context.touchInvocation(call.invocationId), isTrue);
        final record = await context.getInvocation(call.invocationId);
        expect(record, isNotNull);
        expect(record!.timeout, forwarded ? 50000 : isNull);
        expect(record.timeoutForwarded, forwarded);
        expect(record.callerSessionId, 1001);
        expect(record.calleeSessionId, 2001);
        await context.completeInvocation(call.invocationId);
        expect(await context.touchInvocation(call.invocationId), isFalse);
        expect(await context.getInvocation(call.invocationId), isNull);
        expect((await _metrics(store)).pendingInvocationCount, 0);
      },
    );
  }

  for (final (forwarding, expected) in <(Object?, bool)>[
    (null, false),
    (false, false),
    (true, true),
    ('true', false),
    (1, false),
  ]) {
    test('timeout forwarding requires exact true: $forwarding', () async {
      const procedure = 'com.example.timeout.forward';
      await context.registerProcedure(
        sessionId: 2001,
        procedure: procedure,
        details: {'forward_timeout': ?forwarding},
      );
      final dispatched = await context.dispatchInvocation(
        callerSessionId: 1001,
        requestId: 93,
        procedure: procedure,
        options: const {'timeout': 50000},
      );
      expect(dispatched.timeoutForwarded, expected);
      final record = await context.getInvocation(dispatched.invocationId);
      expect(record, isNotNull);
      expect(record!.timeoutForwarded, expected);
      expect(record.timeout, 50000);
      expect(record.cancelRequested, isFalse);
      expect(record.waitForCancelAck, isFalse);
      await context.completeInvocation(dispatched.invocationId);
      expect(await context.getInvocation(dispatched.invocationId), isNull);
    });
  }

  test(
    'forwarded timeout stays callee-owned while a local timer expires',
    () async {
      for (final procedure in ['com.example.forwarded', 'com.example.local']) {
        await context.registerProcedure(
          sessionId: 2001,
          procedure: procedure,
          details: {'forward_timeout': procedure == 'com.example.forwarded'},
        );
      }
      final events = <InvocationTimeoutEvent>[];
      final localExpired = Completer<InvocationTimeoutEvent>();
      final subscription = store.invocationTimeoutEvents.listen((event) {
        events.add(event);
        if (event.callerRequestId == 97 && !localExpired.isCompleted) {
          localExpired.complete(event);
        }
      });
      addTearDown(subscription.cancel);
      final forwarded = await context.dispatchInvocation(
        callerSessionId: 1001,
        requestId: 96,
        procedure: 'com.example.forwarded',
        options: const {'timeout': 10},
      );
      final local = await context.dispatchInvocation(
        callerSessionId: 1002,
        requestId: 97,
        procedure: 'com.example.local',
        options: const {'timeout': 50},
      );
      final expired = await localExpired.future.timeout(
        const Duration(seconds: 2),
      );
      expect(expired.invocationId, local.invocationId);
      expect(expired.callerSessionId, 1002);
      expect(events.map((event) => event.invocationId), [local.invocationId]);
      expect(await context.getInvocation(local.invocationId), isNull);
      final retained = await context.getInvocation(forwarded.invocationId);
      expect(retained, isNotNull);
      expect(retained!.timeoutForwarded, isTrue);
      expect(retained.timeout, 10);
      await context.completeInvocation(forwarded.invocationId);
      expect((await _metrics(store)).pendingInvocationCount, 0);
    },
  );

  test(
    'closing one caller preserves another caller pending debounce',
    () async {
      const procedure = 'com.example.debounce.isolation';
      await context.registerProcedure(
        sessionId: 2001,
        procedure: procedure,
        details: const {
          'auto_deduplication': 500,
          'auto_deduplication_expiry': 2000,
        },
      );
      Future<Object> start(int caller, int request, String hash) => context
          .dispatchInvocation(
            callerSessionId: caller,
            requestId: request,
            procedure: procedure,
            options: {'transaction_hash': hash},
          )
          .then<Object>((value) => value, onError: (Object error) => error);
      final first = start(1001, 94, 'caller-a');
      final second = start(1002, 95, 'caller-b');
      expect((await _metrics(store)).retryDeduplicationActiveCount, 2);
      store.commandPort.send(
        SessionCloseCommand(realmUri: realm, sessionId: 1001),
      );
      expect(
        await first.timeout(const Duration(seconds: 2)),
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Bad state: Caller session 1001 closed',
        ),
      );
      final surviving = await second.timeout(const Duration(seconds: 2));
      expect(surviving, isA<InvocationDispatchResult>());
      final dispatch = surviving as InvocationDispatchResult;
      final record = await context.getInvocation(dispatch.invocationId);
      expect(record, isNotNull);
      expect(record!.callerSessionId, 1002);
      expect(record.callerRequestId, 95);
      expect((await _metrics(store)).totalInvocationsDispatched, 1);
      await context.completeInvocation(dispatch.invocationId);
      expect((await _metrics(store)).pendingInvocationCount, 0);
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

  for (final policy in <String?>[null, 'single', 'roundrobin']) {
    test('registration failure preserves state for policy=$policy', () async {
      const procedure = 'com.example.registration.recovery';
      int? registration;
      if (policy != null) {
        registration = await context.registerProcedure(
          sessionId: 2001,
          procedure: procedure,
          details: {'invoke': policy},
        );
      }
      final expectedError = switch (policy) {
        null => 'Bad state: Session 9999 not found in realm realm1',
        'single' => 'Bad state: Procedure $procedure already registered',
        _ =>
          'Bad state: Procedure $procedure already registered with policy roundRobin',
      };
      await expectLater(
        context.registerProcedure(
          sessionId: policy == null ? 9999 : 2002,
          procedure: procedure,
          details: {if (policy == 'roundrobin') 'invoke': 'first'},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            expectedError,
          ),
        ),
      );
      final rejected = await _metrics(store);
      expect(rejected.registrationCount, policy == null ? 0 : 1);
      expect(rejected.pendingInvocationCount, 0);
      expect(rejected.totalInvocationsDispatched, 0);
      registration ??= await context.registerProcedure(
        sessionId: 2001,
        procedure: procedure,
      );
      final dispatched = await context.dispatchInvocation(
        callerSessionId: 1001,
        requestId: 69,
        procedure: procedure,
        options: const {},
      );
      expect(dispatched.registrationId, registration);
      expect(dispatched.calleeSessionId, 2001);
      expect((await _metrics(store)).registrationCount, 1);
      await context.completeInvocation(dispatched.invocationId);
      expect((await _metrics(store)).pendingInvocationCount, 0);
    });
  }

  for (final throttled in [false, true]) {
    for (final timeout in <Object>['1', 1.5, true, -1]) {
      test(
        'invalid timeout $timeout recovers with throttle=$throttled',
        () async {
          const procedure = 'com.example.timeout.recovery';
          final registration = await context.registerProcedure(
            sessionId: 2001,
            procedure: procedure,
            details: {if (throttled) 'auto_deduplication': 0},
          );
          await expectLater(
            context.dispatchInvocation(
              callerSessionId: 1001,
              requestId: 70,
              procedure: procedure,
              options: {'transaction_hash': 'same-call', 'timeout': timeout},
            ),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                timeout is int
                    ? 'Bad state: CALL timeout must be >= 0'
                    : 'Bad state: CALL timeout must be an integer',
              ),
            ),
          );
          final rejected = await _metrics(store);
          expect(rejected.totalInvocationsDispatched, 0);
          expect(rejected.pendingInvocationCount, 0);
          expect(rejected.retryDeduplicationActiveCount, 0);
          expect(rejected.registrationCount, 1);

          final dispatched = await context.dispatchInvocation(
            callerSessionId: 1001,
            requestId: 71,
            procedure: procedure,
            options: const {'transaction_hash': 'same-call', 'timeout': 0},
          );
          expect(dispatched.registrationId, registration);
          expect(dispatched.calleeSessionId, 2001);
          final pending = await context.getInvocation(dispatched.invocationId);
          expect(pending, isNotNull);
          expect(pending?.callerRequestId, 71);
          expect(pending?.callerSessionId, 1001);
          expect(pending?.timeout, isNull);
          final accepted = await _metrics(store);
          expect(accepted.totalInvocationsDispatched, 1);
          expect(accepted.pendingInvocationCount, 1);
          expect(accepted.retryDeduplicationActiveCount, throttled ? 1 : 0);
          await context.completeInvocation(dispatched.invocationId);
          expect(await context.getInvocation(dispatched.invocationId), isNull);
          final completed = await _metrics(store);
          expect(completed.pendingInvocationCount, 0);
          expect(completed.retryDeduplicationActiveCount, 0);
        },
      );
    }
  }

  for (final invalid in [
    (field: 'invoke', value: 42, message: 'must be a String'),
    (
      field: 'invoke',
      value: 'invalid',
      message: 'Unsupported invocation policy',
    ),
    (field: 'match', value: false, message: 'must be a String'),
    (field: 'match', value: 'regex', message: 'unsupported match policy'),
  ]) {
    test(
      'rejects ${invalid.field}=${invalid.value} without poisoning registration',
      () async {
        const procedure = 'com.example.policy.recovery';
        await expectLater(
          context.registerProcedure(
            sessionId: 2001,
            procedure: procedure,
            details: {invalid.field: invalid.value},
          ),
          throwsA(
            isA<ArgumentError>()
                .having((error) => error.name, 'name', invalid.field)
                .having((error) => error.invalidValue, 'value', invalid.value)
                .having((error) => error.message, 'message', invalid.message),
          ),
        );
        final registration = await context.registerProcedure(
          sessionId: 2002,
          procedure: procedure,
        );
        final dispatched = await context.dispatchInvocation(
          callerSessionId: 1001,
          requestId: 49,
          procedure: procedure,
          options: const {},
        );
        expect(dispatched.registrationId, registration);
        expect(dispatched.calleeSessionId, 2002);
        expect((await _metrics(store)).totalInvocationsDispatched, 1);
      },
    );
  }

  test('store disposal rejects a pending debounce promptly', () async {
    await context.registerProcedure(
      sessionId: 2001,
      procedure: 'com.example.dispose',
      details: const {'auto_deduplication': 1000},
    );
    final pending = context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 51,
      procedure: 'com.example.dispose',
      options: const {'transaction_hash': 'dispose:1'},
    );
    final rejected = expectLater(
      pending.timeout(const Duration(seconds: 2)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Router state store disposed'),
        ),
      ),
    );
    final metrics = await _metrics(store);
    expect(metrics.retryDeduplicationActiveCount, 1);
    expect(metrics.totalInvocationsDispatched, 0);
    store.dispose();
    disposed = true;
    await rejected;
  });

  test('unregister cancels pending debounce without a late dispatch', () async {
    const procedure = 'com.example.unregister.pending';
    final registration = await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: const {'auto_deduplication': 1000},
    );
    final pending = context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 52,
      procedure: procedure,
      options: const {'transaction_hash': 'unregister:pending'},
    );
    final rejected = expectLater(
      pending.timeout(const Duration(seconds: 2)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Registration $registration removed'),
        ),
      ),
    );
    expect((await _metrics(store)).retryDeduplicationActiveCount, 1);
    await context.unregisterProcedure(
      sessionId: 2001,
      registrationId: registration,
    );
    await rejected;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final metrics = await _metrics(store);
    expect(metrics.retryDeduplicationActiveCount, 0);
    expect(metrics.totalInvocationsDispatched, 0);
  });

  test('unregister releases throttle state before re-registration', () async {
    const procedure = 'com.example.unregister.active';
    const otherProcedure = 'com.example.unregister.unrelated';
    const details = {'auto_deduplication': 0};
    final registration = await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: details,
    );
    await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 53,
      procedure: procedure,
      options: const {'transaction_hash': 'unregister:active'},
    );
    await context.registerProcedure(
      sessionId: 2002,
      procedure: otherProcedure,
      details: details,
    );
    await context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 530,
      procedure: otherProcedure,
      options: const {'transaction_hash': 'unregister:active'},
    );
    expect((await _metrics(store)).retryDeduplicationActiveCount, 2);
    await context.unregisterProcedure(
      sessionId: 2001,
      registrationId: registration,
    );
    expect((await _metrics(store)).retryDeduplicationActiveCount, 1);
    await expectLater(
      context.dispatchInvocation(
        callerSessionId: 1002,
        requestId: 531,
        procedure: otherProcedure,
        options: const {'transaction_hash': 'unregister:active'},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(wamp.Error.autoDeduplication),
        ),
      ),
    );
    final replacement = await context.registerProcedure(
      sessionId: 2002,
      procedure: procedure,
      details: details,
    );
    final dispatched = await context.dispatchInvocation(
      callerSessionId: 1002,
      requestId: 54,
      procedure: procedure,
      options: const {'transaction_hash': 'unregister:active'},
    );
    expect(dispatched.registrationId, replacement);
    expect(dispatched.calleeSessionId, 2002);
    expect((await _metrics(store)).retryDeduplicationActiveCount, 2);
  });

  test('removing one shared callee preserves a pending debounce', () async {
    const procedure = 'com.example.unregister.shared';
    const details = {
      'invoke': 'roundrobin',
      'auto_deduplication': 1000,
    };
    final registration = await context.registerProcedure(
      sessionId: 2001,
      procedure: procedure,
      details: details,
    );
    final remainingRegistration = await context.registerProcedure(
      sessionId: 2002,
      procedure: procedure,
      details: details,
    );
    final pending = context.dispatchInvocation(
      callerSessionId: 1001,
      requestId: 532,
      procedure: procedure,
      options: const {'transaction_hash': 'shared:pending'},
    );
    final dispatched = expectLater(
      pending.timeout(const Duration(seconds: 3)),
      completion(
        isA<InvocationDispatchResult>()
            .having(
              (value) => value.registrationId,
              'registration',
              remainingRegistration,
            )
            .having((value) => value.calleeSessionId, 'callee', 2002),
      ),
    );
    expect((await _metrics(store)).retryDeduplicationActiveCount, 1);
    await context.unregisterProcedure(
      sessionId: 2001,
      registrationId: registration,
    );
    expect((await _metrics(store)).retryDeduplicationActiveCount, 1);
    await dispatched;
    final metrics = await _metrics(store);
    expect(metrics.retryDeduplicationActiveCount, 0);
    expect(metrics.totalInvocationsDispatched, 1);
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
  try {
    store.commandPort.send(MetricsSnapshotCommand(replyPort: reply.sendPort));
    return await reply.first.timeout(const Duration(seconds: 2))
        as RouterStateMetrics;
  } finally {
    reply.close();
  }
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
