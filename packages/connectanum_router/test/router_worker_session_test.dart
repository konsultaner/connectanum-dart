@TestOn('vm')
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp_core show Error;
import 'package:connectanum_core/src/message/goodbye.dart' as goodbye_msg;
import 'package:connectanum_core/src/message/publish.dart' as publish_msg;
import 'package:connectanum_core/src/message/event.dart' as event_msg;
import 'package:connectanum_core/src/message/call.dart' as call_msg;
import 'package:connectanum_core/src/message/cancel.dart' as cancel_msg;
import 'package:connectanum_core/src/message/invocation.dart' as invocation_msg;
import 'package:connectanum_core/src/message/interrupt.dart' as interrupt_msg;
import 'package:connectanum_core/src/message/yield.dart' as yield_msg;
import 'package:connectanum_core/src/message/result.dart' as result_msg;
import 'package:connectanum_core/src/message/error.dart' as error_msg;
import 'package:connectanum_core/src/message/register.dart' as register_msg;
import 'package:connectanum_core/src/message/subscribe.dart' as subscribe_msg;
import 'package:connectanum_core/src/message/unregister.dart' as unregister_msg;
import 'package:connectanum_core/src/message/unsubscribe.dart'
    as unsubscribe_msg;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_listener.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/session.dart';
import 'package:connectanum_router/src/router/state/snapshot.dart';
import 'package:connectanum_router/src/router/state/store.dart';
import 'package:connectanum_router/src/router/state/subscription.dart';
import 'package:test/test.dart';

void main() {
  late RouterSettings routerSettings;
  late RouterStateStore stateStore;

  setUp(() {
    routerSettings = _buildRouterSettings();
    stateStore = RouterStateStore(settings: routerSettings)..start();
  });

  tearDown(() {
    stateStore.dispose();
  });

  group('Router worker session handling', () {
    test('responds to GOODBYE and closes session', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 42;

      _openSession(stateStore, sessionId: 42, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final goodbye = goodbye_msg.Goodbye(
        goodbye_msg.GoodbyeMessage('shutting down'),
        'wamp.close.system_shutdown',
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: goodbye,
        connectionId: 7,
      );

      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeGoodbye));
      expect(frame[2], equals('wamp.close.goodbye_and_out'));

      final snapshot = await _fetchSnapshot(stateStore.commandPort);
      expect(snapshot.sessions, isEmpty);
      expect(workerState.sessionId, isNull);
      expect(workerState.phase, equals(HandshakePhase.aborted));
    });

    test('server initiated GOODBYE sends system shutdown reason', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 43;

      _openSession(stateStore, sessionId: 43, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      await initiateServerGoodbyeForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        connectionId: 8,
        reason: 'wamp.close.system_shutdown',
      );

      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeGoodbye));
      expect(frame[2], equals('wamp.close.system_shutdown'));

      final snapshot = await _fetchSnapshot(stateStore.commandPort);
      expect(snapshot.sessions, isEmpty);
      expect(workerState.sessionId, isNull);
      expect(workerState.phase, equals(HandshakePhase.aborted));
    });

    test(
      'handles CANCEL killnowait by interrupting callee and notifying caller',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final callerState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        callerState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 761;
        final calleeState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        calleeState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 762;

        _openSession(
          stateStore,
          sessionId: 761,
          listener: listener,
          connectionId: 121,
        );
        _openSession(
          stateStore,
          sessionId: 762,
          listener: listener,
          connectionId: 122,
        );
        await Future<void>.delayed(Duration.zero);

        final registerReply = ReceivePort();
        stateStore.commandPort.send(
          ProcedureRegisterCommand(
            realmUri: 'realm1',
            sessionId: 762,
            procedure: 'com.example.cancelable',
            details: const {},
            replyPort: registerReply.sendPort,
          ),
        );
        await registerReply.first;
        registerReply.close();

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );
        final call = call_msg.Call(9701, 'com.example.cancelable');

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: call,
          connectionId: 121,
        );
        await Future<void>.delayed(Duration.zero);

        final invocationForward = _extractForwardMessages(bossMessages);
        expect(invocationForward, hasLength(1));
        final invocationEnvelope = invocationForward.single;
        expect(invocationEnvelope['connectionId'], equals(122));
        final invocation =
            invocationEnvelope['message'] as invocation_msg.Invocation;
        final invocationId = invocation.requestId;
        bossMessages.clear();

        final cancelOptions = cancel_msg.CancelOptions()
          ..mode = cancel_msg.CancelOptions.modeKillNoWait;
        final cancel = cancel_msg.Cancel(9701, options: cancelOptions);

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: cancel,
          connectionId: 121,
        );
        await Future<void>.delayed(Duration.zero);

        final interruptForward = _extractForwardMessages(bossMessages);
        expect(interruptForward, hasLength(1));
        final interruptEnvelope = interruptForward.single;
        expect(interruptEnvelope['connectionId'], equals(122));
        final interrupt =
            interruptEnvelope['message'] as interrupt_msg.Interrupt;
        expect(interrupt.requestId, equals(invocationId));
        expect(
          interrupt.options?.mode,
          equals(cancel_msg.CancelOptions.modeKillNoWait),
        );

        final workerSends = _collectWorkerSends(bossMessages);
        expect(workerSends, hasLength(1));
        final cancelFrame =
            jsonDecode(utf8.decode(workerSends.single['payload'] as Uint8List))
                as List<dynamic>;
        expect(cancelFrame.first, equals(MessageTypes.codeError));
        expect(cancelFrame[1], equals(MessageTypes.codeCall));
        expect(cancelFrame[2], equals(9701));
        expect(cancelFrame[4], equals(error_msg.Error.errorInvocationCanceled));

        final remainingInvocation = await realmContexts
            .contextFor('realm1')
            .getInvocation(invocationId);
        expect(remainingInvocation, isNull);

        bossMessages.clear();
        final lateYield = yield_msg.Yield(invocationId);

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: lateYield,
          connectionId: 122,
        );
        await Future<void>.delayed(Duration.zero);

        final calleeError = _collectWorkerSends(bossMessages);
        expect(calleeError, hasLength(1));
        final calleeFrame =
            jsonDecode(utf8.decode(calleeError.single['payload'] as Uint8List))
                as List<dynamic>;
        expect(calleeFrame.first, equals(MessageTypes.codeError));
        expect(calleeFrame[1], equals(MessageTypes.codeInvocation));
        expect(calleeFrame[2], equals(invocationId));
        expect(calleeFrame[4], equals('wamp.error.no_such_invocation'));
      },
    );

    test(
      'dispatches calls across workers and returns result to caller',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final calleeState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        calleeState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 901;

        final callerState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        callerState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 902;

        _openSession(
          stateStore,
          sessionId: calleeState.sessionId!,
          listener: listener,
          connectionId: 31,
        );
        _openSession(
          stateStore,
          sessionId: callerState.sessionId!,
          listener: listener,
          connectionId: 32,
        );
        await Future<void>.delayed(Duration.zero);

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );

        final register = register_msg.Register(2101, 'com.parallel.proc');
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: register,
          connectionId: 31,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();

        final call = call_msg.Call(
          2102,
          'com.parallel.proc',
          arguments: ['input'],
        );
        final callIncoming = NativeIncomingMessage.test(
          serializer: NativeMessageSerializer.json,
          message: call,
          handle: 321,
          onRetain: (handle) => handle,
        );
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: call,
          connectionId: 32,
          incomingMessage: callIncoming,
        );
        await Future<void>.delayed(Duration.zero);

        final invocationCommands = bossMessages.where(
          (message) => message['type'] == 'worker_forward_native_invocation',
        );
        expect(invocationCommands.length, equals(1));
        final invocationCommand = invocationCommands.single;
        expect(invocationCommand['connectionId'], equals(31));
        expect(invocationCommand['handle'], equals(321));
        final invocationId = invocationCommand['invocationId'] as int;
        bossMessages.clear();

        final yieldMessage = yield_msg.Yield(
          invocationId,
          arguments: ['result'],
        );
        final yieldIncoming = NativeIncomingMessage.test(
          serializer: NativeMessageSerializer.json,
          message: yieldMessage,
          handle: 322,
          onRetain: (handle) => handle,
        );
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: yieldMessage,
          connectionId: 31,
          incomingMessage: yieldIncoming,
        );
        await Future<void>.delayed(Duration.zero);

        final resultCommands = bossMessages.where(
          (message) => message['type'] == 'worker_forward_native_result',
        );
        expect(resultCommands.length, equals(1));
        final resultCommand = resultCommands.single;
        expect(resultCommand['connectionId'], equals(32));
        expect(resultCommand['handle'], equals(322));
        expect(resultCommand['progress'], isFalse);

        expect(
          bossMessages.where(
            (message) => message['type'] == 'worker_forward_message',
          ),
          isEmpty,
        );
      },
    );

    test('closing session removes subscriptions and registrations', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 915;

      _openSession(
        stateStore,
        sessionId: workerState.sessionId!,
        listener: listener,
        connectionId: 41,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      final subscribe = subscribe_msg.Subscribe(1301, 'com.cleanup.topic');
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: subscribe,
        connectionId: 41,
      );
      await Future<void>.delayed(Duration.zero);
      bossMessages.clear();

      final register = register_msg.Register(1302, 'com.cleanup.proc');
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: register,
        connectionId: 41,
      );
      await Future<void>.delayed(Duration.zero);
      bossMessages.clear();

      var snapshot = await _fetchSnapshot(stateStore.commandPort);
      expect(snapshot.subscriptions, hasLength(1));
      expect(snapshot.registrations, hasLength(1));

      final goodbye = goodbye_msg.Goodbye(
        goodbye_msg.GoodbyeMessage('bye'),
        'wamp.close.goodbye_and_out',
      );
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: goodbye,
        connectionId: 41,
      );
      await Future<void>.delayed(Duration.zero);

      snapshot = await _fetchSnapshot(stateStore.commandPort);
      expect(snapshot.sessions, isEmpty);
      expect(snapshot.subscriptions, isEmpty);
      expect(snapshot.registrations, isEmpty);
    });

    test('handles CANCEL kill by waiting for callee acknowledgement', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 771;
      final calleeState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 772;

      _openSession(
        stateStore,
        sessionId: 771,
        listener: listener,
        connectionId: 131,
      );
      _openSession(
        stateStore,
        sessionId: 772,
        listener: listener,
        connectionId: 132,
      );
      await Future<void>.delayed(Duration.zero);

      final registerReply = ReceivePort();
      stateStore.commandPort.send(
        ProcedureRegisterCommand(
          realmUri: 'realm1',
          sessionId: 772,
          procedure: 'com.example.killable',
          details: const {},
          replyPort: registerReply.sendPort,
        ),
      );
      await registerReply.first;
      registerReply.close();

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final call = call_msg.Call(9801, 'com.example.killable');

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: call,
        connectionId: 131,
      );
      await Future<void>.delayed(Duration.zero);

      final invocationForward = _extractForwardMessages(bossMessages);
      expect(invocationForward, hasLength(1));
      final invocationEnvelope = invocationForward.single;
      expect(invocationEnvelope['connectionId'], equals(132));
      final invocation =
          invocationEnvelope['message'] as invocation_msg.Invocation;
      final invocationId = invocation.requestId;
      bossMessages.clear();

      final cancelOptions = cancel_msg.CancelOptions()
        ..mode = cancel_msg.CancelOptions.modeKill;
      final cancel = cancel_msg.Cancel(9801, options: cancelOptions);

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: cancel,
        connectionId: 131,
      );
      await Future<void>.delayed(Duration.zero);

      final interruptForward = _extractForwardMessages(bossMessages);
      expect(interruptForward, hasLength(1));
      final interruptEnvelope = interruptForward.single;
      expect(interruptEnvelope['connectionId'], equals(132));
      final interrupt = interruptEnvelope['message'] as interrupt_msg.Interrupt;
      expect(
        interrupt.options?.mode,
        equals(cancel_msg.CancelOptions.modeKill),
      );

      final cancelAckMessages = _collectWorkerSends(bossMessages);
      expect(cancelAckMessages, isEmpty);
      bossMessages.clear();

      final cancelAckFromCallee = error_msg.Error(
        MessageTypes.codeInvocation,
        invocationId,
        const {},
        error_msg.Error.errorInvocationCanceled,
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeState,
        message: cancelAckFromCallee,
        connectionId: 132,
      );
      await Future<void>.delayed(Duration.zero);

      final forwarded = _extractForwardMessages(bossMessages);
      expect(forwarded, hasLength(1));
      final callerEnvelope = forwarded.single;
      expect(callerEnvelope['connectionId'], equals(131));
      final routedError = callerEnvelope['message'] as error_msg.Error;
      expect(routedError.requestTypeId, equals(MessageTypes.codeCall));
      expect(routedError.requestId, equals(9801));
      expect(
        routedError.error,
        equals(error_msg.Error.errorInvocationCanceled),
      );
    });

    test('returns no_such_invocation on CANCEL store failure', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final callerState =
          createWorkerStateForTest(
                listener: _buildListener(),
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 8801;

      final snapshot = RealmSnapshot(
        realmUri: 'realm1',
        version: 1,
        sessions: [
          SessionInfo(
            id: 8801,
            authId: null,
            authRole: null,
            roles: const {},
            workerId: 1,
            connectionId: 301,
            lastActivity: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          SessionInfo(
            id: 8802,
            authId: null,
            authRole: null,
            roles: const {},
            workerId: 1,
            connectionId: 302,
            lastActivity: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ],
        subscriptions: const [],
        registrations: const [],
      );

      final context = _StateErrorRealmContext(
        realmUri: 'realm1',
        statePort: stateStore.commandPort,
        snapshot: snapshot,
        invocationId: 9901,
        registrationId: 551,
        callerRequestId: 7101,
        callerSessionId: 8801,
        calleeSessionId: 8802,
        allowProgress: false,
        cancelThrows: true,
        cancelFailureMessage: 'cancel failure',
      );
      final realmContexts = _StaticRealmContextCache(
        statePort: stateStore.commandPort,
        overrides: {'realm1': context},
      );

      final cancelOptions = cancel_msg.CancelOptions()
        ..mode = cancel_msg.CancelOptions.modeKill;
      final cancel = cancel_msg.Cancel(7101, options: cancelOptions);

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: cancel,
        connectionId: 301,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeCancel));
      expect(frame[2], equals(7101));
      expect(frame[4], equals('wamp.error.no_such_invocation'));
      final details = frame[3] as Map<String, Object?>;
      expect(details['message'], contains('cancel failure'));
    });

    test(
      'uses native forwarding for yield responses when handle is present',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final callerState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        callerState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 9811;

        final calleeState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        calleeState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 9812;

        _openSession(
          stateStore,
          sessionId: 9811,
          listener: listener,
          connectionId: 141,
        );
        _openSession(
          stateStore,
          sessionId: 9812,
          listener: listener,
          connectionId: 142,
        );
        await Future<void>.delayed(Duration.zero);

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: register_msg.Register(9813, 'com.zero.result'),
          connectionId: 142,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();

        final call = call_msg.Call(
          9814,
          'com.zero.result',
          arguments: ['start'],
        );
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: call,
          connectionId: 141,
        );
        await Future<void>.delayed(Duration.zero);
        final invocationForward = _extractForwardMessages(bossMessages);
        expect(invocationForward, hasLength(1));
        final invocationMessage =
            invocationForward.single['message'] as invocation_msg.Invocation;
        final invocationId = invocationMessage.requestId;
        bossMessages.clear();

        final yieldMessage = yield_msg.Yield(
          invocationId,
          arguments: ['finished'],
        );
        final retainedHandles = <int>[];
        final incoming = NativeIncomingMessage.test(
          serializer: NativeMessageSerializer.json,
          message: yieldMessage,
          handle: 105,
          onRetain: (handle) {
            retainedHandles.add(handle);
            return handle;
          },
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: yieldMessage,
          connectionId: 142,
          incomingMessage: incoming,
        );

        await Future<void>.delayed(Duration.zero);

        final nativeCommands = bossMessages
            .where(
              (message) => message['type'] == 'worker_forward_native_result',
            )
            .toList();
        expect(retainedHandles, equals([105]));
        expect(bossMessages, isNotEmpty);
        expect(nativeCommands, hasLength(1));
        expect(nativeCommands.single['handle'], equals(105));
        expect(nativeCommands.single['progress'], isFalse);
        expect(
          bossMessages.where(
            (message) => message['type'] == 'worker_forward_message',
          ),
          isEmpty,
        );
      },
    );

    test(
      'uses native forwarding for invocation errors when handle is present',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final callerState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        callerState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 9911;

        final calleeState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        calleeState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 9912;

        _openSession(
          stateStore,
          sessionId: 9911,
          listener: listener,
          connectionId: 151,
        );
        _openSession(
          stateStore,
          sessionId: 9912,
          listener: listener,
          connectionId: 152,
        );
        await Future<void>.delayed(Duration.zero);

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: register_msg.Register(9913, 'com.zero.error'),
          connectionId: 152,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();

        final call = call_msg.Call(9914, 'com.zero.error', arguments: ['call']);
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: call,
          connectionId: 151,
        );
        await Future<void>.delayed(Duration.zero);
        final invocationForward = _extractForwardMessages(bossMessages);
        expect(invocationForward, hasLength(1));
        final invocationMessage =
            invocationForward.single['message'] as invocation_msg.Invocation;
        bossMessages.clear();

        final errorMessage = error_msg.Error(
          MessageTypes.codeInvocation,
          invocationMessage.requestId,
          const {'detail': 'oops'},
          'wamp.error.runtime_error',
          arguments: ['fail'],
        );
        final retainedHandles = <int>[];
        final incoming = NativeIncomingMessage.test(
          serializer: NativeMessageSerializer.json,
          message: errorMessage,
          handle: 115,
          onRetain: (handle) {
            retainedHandles.add(handle);
            return handle;
          },
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: errorMessage,
          connectionId: 152,
          incomingMessage: incoming,
        );

        await Future<void>.delayed(Duration.zero);

        final nativeCommands = bossMessages
            .where(
              (message) => message['type'] == 'worker_forward_native_error',
            )
            .toList();
        expect(retainedHandles, equals([115]));
        expect(bossMessages, isNotEmpty);
        expect(nativeCommands, hasLength(1));
        expect(nativeCommands.single['handle'], equals(115));
        expect(
          bossMessages.where(
            (message) => message['type'] == 'worker_forward_message',
          ),
          isEmpty,
        );
      },
    );

    test('releases publish handles when boss forwarding throws', () async {
      final listener = _buildListener();
      final subscriberOne =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      subscriberOne
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9901;
      final subscriberTwo =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      subscriberTwo
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9902;
      final publisherState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      publisherState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9903;

      _openSession(
        stateStore,
        sessionId: subscriberOne.sessionId!,
        listener: listener,
        connectionId: 71,
      );
      _openSession(
        stateStore,
        sessionId: subscriberTwo.sessionId!,
        listener: listener,
        connectionId: 72,
      );
      _openSession(
        stateStore,
        sessionId: publisherState.sessionId!,
        listener: listener,
        connectionId: 73,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      final setupBossMessages = <Map<String, Object?>>[];
      final setupBoss = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            setupBossMessages.add(message);
          }
        });
      addTearDown(setupBoss.close);

      await handleSessionMessageForTest(
        bossPort: setupBoss.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: subscriberOne,
        message: subscribe_msg.Subscribe(7101, 'com.throw.topic'),
        connectionId: 71,
      );
      await Future<void>.delayed(Duration.zero);
      setupBossMessages.clear();

      await handleSessionMessageForTest(
        bossPort: setupBoss.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: subscriberTwo,
        message: subscribe_msg.Subscribe(7102, 'com.throw.topic'),
        connectionId: 72,
      );
      await Future<void>.delayed(Duration.zero);
      setupBossMessages.clear();

      final retainOrder = <int>[];
      final releasedHandles = <int>[];
      final forwardedCommands = <Object?>[];
      final throwPort = _ThrowingSendPort(onSend: forwardedCommands.add);

      final publish =
          publish_msg.Publish(
              7103,
              'com.throw.topic',
              arguments: const ['hello'],
            )
            ..options = publish_msg.PublishOptions(
              acknowledge: false,
              discloseMe: true,
            );
      final incoming = NativeIncomingMessage.test(
        serializer: NativeMessageSerializer.json,
        message: publish,
        handle: 901,
        onRetain: (handle) {
          final retainedHandle = handle + retainOrder.length;
          retainOrder.add(retainedHandle);
          return retainedHandle;
        },
        onRelease: releasedHandles.add,
      );

      await expectLater(
        handleSessionMessageForTest(
          bossPort: throwPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: publisherState,
          message: publish,
          connectionId: 73,
          incomingMessage: incoming,
        ),
        throwsA(isA<StateError>()),
      );

      final eventCommand = forwardedCommands
          .whereType<Map<String, Object?>>()
          .where((command) => command['type'] == 'worker_forward_native_event')
          .single;
      expect(eventCommand['type'], equals('worker_forward_native_event'));
      expect(retainOrder.length, equals(2));
      expect(releasedHandles, equals(retainOrder));
    });

    test('releases invocation handle when zero-copy boss send fails', () async {
      final listener = _buildListener();
      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 12001;
      final calleeState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 12002;

      _openSession(
        stateStore,
        sessionId: callerState.sessionId!,
        listener: listener,
        connectionId: 81,
      );
      _openSession(
        stateStore,
        sessionId: calleeState.sessionId!,
        listener: listener,
        connectionId: 82,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final setupBossMessages = <Map<String, Object?>>[];
      final setupBoss = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            setupBossMessages.add(message);
          }
        });
      addTearDown(setupBoss.close);

      await handleSessionMessageForTest(
        bossPort: setupBoss.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeState,
        message: register_msg.Register(12003, 'com.zero.copy.fail'),
        connectionId: 82,
      );
      await Future<void>.delayed(Duration.zero);
      setupBossMessages.clear();

      final retained = <int>[];
      final released = <int>[];
      final forwarded = <Object?>[];
      final throwingBoss = _ThrowingSendPort(onSend: forwarded.add);

      final call = call_msg.Call(
        12004,
        'com.zero.copy.fail',
        arguments: const ['payload'],
      );
      final incoming = NativeIncomingMessage.test(
        serializer: NativeMessageSerializer.json,
        message: call,
        handle: 120,
        onRetain: (handle) {
          retained.add(handle);
          return handle;
        },
        onRelease: released.add,
      );

      await expectLater(
        handleSessionMessageForTest(
          bossPort: throwingBoss,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: call,
          connectionId: 81,
          incomingMessage: incoming,
        ),
        throwsA(isA<StateError>()),
      );

      final invocationCommand = forwarded
          .whereType<Map<String, Object?>>()
          .where(
            (command) => command['type'] == 'worker_forward_native_invocation',
          )
          .single;
      expect(
        invocationCommand['type'],
        equals('worker_forward_native_invocation'),
      );
      expect(retained, equals([120]));
      expect(released, equals([120]));
    });

    test('releases yield handle when boss send fails', () async {
      final listener = _buildListener();
      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 13001;
      final calleeState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 13002;

      _openSession(
        stateStore,
        sessionId: callerState.sessionId!,
        listener: listener,
        connectionId: 83,
      );
      _openSession(
        stateStore,
        sessionId: calleeState.sessionId!,
        listener: listener,
        connectionId: 84,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final setupBossMessages = <Map<String, Object?>>[];
      final setupBoss = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            setupBossMessages.add(message);
          }
        });
      addTearDown(setupBoss.close);

      await handleSessionMessageForTest(
        bossPort: setupBoss.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeState,
        message: register_msg.Register(13003, 'com.zero.copy.yield'),
        connectionId: 84,
      );
      await Future<void>.delayed(Duration.zero);
      setupBossMessages.clear();

      final call = call_msg.Call(13004, 'com.zero.copy.yield');
      await handleSessionMessageForTest(
        bossPort: setupBoss.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: call,
        connectionId: 83,
      );
      await Future<void>.delayed(Duration.zero);

      final invocationForward = setupBossMessages
          .where((message) => message['type'] == 'worker_forward_message')
          .toList();
      expect(invocationForward, hasLength(1));
      final invocation =
          invocationForward.single['message'] as invocation_msg.Invocation;
      final invocationId = invocation.requestId;
      setupBossMessages.clear();

      final retained = <int>[];
      final released = <int>[];
      final forwarded = <Object?>[];
      final throwingBoss = _ThrowingSendPort(onSend: forwarded.add);

      final yieldMessage = yield_msg.Yield(
        invocationId,
        arguments: const ['done'],
      );
      final incoming = NativeIncomingMessage.test(
        serializer: NativeMessageSerializer.json,
        message: yieldMessage,
        handle: 130,
        onRetain: (handle) {
          retained.add(handle);
          return handle;
        },
        onRelease: released.add,
      );

      await expectLater(
        handleSessionMessageForTest(
          bossPort: throwingBoss,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: yieldMessage,
          connectionId: 84,
          incomingMessage: incoming,
        ),
        throwsA(isA<StateError>()),
      );

      final resultCommand = forwarded
          .whereType<Map<String, Object?>>()
          .where((command) => command['type'] == 'worker_forward_native_result')
          .single;
      expect(resultCommand['type'], equals('worker_forward_native_result'));
      expect(retained, equals([130]));
      expect(released, equals([130]));
    });

    test('releases invocation error handle when boss send fails', () async {
      final listener = _buildListener();
      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 14001;
      final calleeState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 14002;

      _openSession(
        stateStore,
        sessionId: callerState.sessionId!,
        listener: listener,
        connectionId: 85,
      );
      _openSession(
        stateStore,
        sessionId: calleeState.sessionId!,
        listener: listener,
        connectionId: 86,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final setupBossMessages = <Map<String, Object?>>[];
      final setupBoss = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            setupBossMessages.add(message);
          }
        });
      addTearDown(setupBoss.close);

      await handleSessionMessageForTest(
        bossPort: setupBoss.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeState,
        message: register_msg.Register(14003, 'com.zero.copy.error'),
        connectionId: 86,
      );
      await Future<void>.delayed(Duration.zero);
      setupBossMessages.clear();

      final call = call_msg.Call(14004, 'com.zero.copy.error');
      await handleSessionMessageForTest(
        bossPort: setupBoss.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: call,
        connectionId: 85,
      );
      await Future<void>.delayed(Duration.zero);

      final invocationForward = setupBossMessages
          .where((message) => message['type'] == 'worker_forward_message')
          .toList();
      expect(invocationForward, hasLength(1));
      final invocation =
          invocationForward.single['message'] as invocation_msg.Invocation;
      final invocationId = invocation.requestId;
      setupBossMessages.clear();

      final retained = <int>[];
      final released = <int>[];
      final forwarded = <Object?>[];
      final throwingBoss = _ThrowingSendPort(onSend: forwarded.add);

      final errorMessage = error_msg.Error(
        MessageTypes.codeInvocation,
        invocationId,
        const {},
        'com.failure',
      );
      final incoming = NativeIncomingMessage.test(
        serializer: NativeMessageSerializer.json,
        message: errorMessage,
        handle: 140,
        onRetain: (handle) {
          retained.add(handle);
          return handle;
        },
        onRelease: released.add,
      );

      await expectLater(
        handleSessionMessageForTest(
          bossPort: throwingBoss,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: errorMessage,
          connectionId: 86,
          incomingMessage: incoming,
        ),
        throwsA(isA<StateError>()),
      );

      final errorCommand = forwarded
          .whereType<Map<String, Object?>>()
          .where((command) => command['type'] == 'worker_forward_native_error')
          .single;
      expect(errorCommand['type'], equals('worker_forward_native_error'));
      expect(retained, equals([140]));
      expect(released, equals([140]));
    });

    test('returns no_such_invocation when YIELD completion fails', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final calleeState =
          createWorkerStateForTest(
                listener: _buildListener(),
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9301;

      final snapshot = RealmSnapshot(
        realmUri: 'realm1',
        version: 1,
        sessions: [
          SessionInfo(
            id: 9301,
            authId: null,
            authRole: null,
            roles: const {},
            workerId: 1,
            connectionId: 411,
            lastActivity: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          SessionInfo(
            id: 9302,
            authId: null,
            authRole: null,
            roles: const {},
            workerId: 1,
            connectionId: 412,
            lastActivity: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ],
        subscriptions: const [],
        registrations: const [],
      );

      final context = _StateErrorRealmContext(
        realmUri: 'realm1',
        statePort: stateStore.commandPort,
        snapshot: snapshot,
        invocationId: 12001,
        registrationId: 901,
        callerRequestId: 12002,
        callerSessionId: 9302,
        calleeSessionId: 9301,
        allowProgress: false,
        completeThrows: true,
        completeFailureMessage: 'completion failure',
      );

      final realmContexts = _StaticRealmContextCache(
        statePort: stateStore.commandPort,
        overrides: {'realm1': context},
      );

      final yieldMessage = yield_msg.Yield(12001, arguments: const ['payload']);

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeState,
        message: yieldMessage,
        connectionId: 411,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeInvocation));
      expect(frame[2], equals(12001));
      expect(frame[4], equals('wamp.error.no_such_invocation'));
      final details = frame[3] as Map<String, Object?>;
      expect(details['message'], contains('completion failure'));
    });

    test(
      'returns no_such_invocation when invocation ERROR completion fails',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final calleeState =
            createWorkerStateForTest(
                  listener: _buildListener(),
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        calleeState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 9401;

        final snapshot = RealmSnapshot(
          realmUri: 'realm1',
          version: 1,
          sessions: [
            SessionInfo(
              id: 9401,
              authId: null,
              authRole: null,
              roles: const {},
              workerId: 1,
              connectionId: 421,
              lastActivity: DateTime.fromMillisecondsSinceEpoch(0),
            ),
            SessionInfo(
              id: 9402,
              authId: null,
              authRole: null,
              roles: const {},
              workerId: 1,
              connectionId: 422,
              lastActivity: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          ],
          subscriptions: const [],
          registrations: const [],
        );

        final context = _StateErrorRealmContext(
          realmUri: 'realm1',
          statePort: stateStore.commandPort,
          snapshot: snapshot,
          invocationId: 13001,
          registrationId: 902,
          callerRequestId: 13002,
          callerSessionId: 9402,
          calleeSessionId: 9401,
          allowProgress: false,
          completeThrows: true,
          completeFailureMessage: 'error completion failure',
        );

        final realmContexts = _StaticRealmContextCache(
          statePort: stateStore.commandPort,
          overrides: {'realm1': context},
        );

        final invocationError = error_msg.Error(
          MessageTypes.codeInvocation,
          13001,
          const {},
          'com.example.failure',
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: invocationError,
          connectionId: 421,
        );
        await Future<void>.delayed(Duration.zero);

        final workerSend = _extractWorkerSend(bossMessages);
        final payload = workerSend['payload'] as Uint8List;
        final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
        expect(frame.first, equals(MessageTypes.codeError));
        expect(frame[1], equals(MessageTypes.codeInvocation));
        expect(frame[2], equals(13001));
        expect(frame[4], equals('wamp.error.no_such_invocation'));
        final details = frame[3] as Map<String, Object?>;
        expect(details['message'], contains('error completion failure'));
      },
    );

    test('handles SUBSCRIBE by registering subscription', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 21;

      _openSession(stateStore, sessionId: 21, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final subscribe = subscribe_msg.Subscribe(1001, 'com.myapp.topic');
      subscribe.options = subscribe_msg.SubscribeOptions(
        match: subscribe_msg.SubscribeOptions.matchPrefix,
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: subscribe,
        connectionId: 11,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeSubscribed));
      expect(frame[1], equals(1001));
      final subscriptionId = frame[2] as int;
      expect(subscriptionId, isPositive);

      final snapshot = await _fetchSnapshot(stateStore.commandPort);
      expect(snapshot.subscriptions, hasLength(1));
      expect(snapshot.subscriptions.single.id, equals(subscriptionId));
    });

    test('returns error when SUBSCRIBE uses invalid URI', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 311;

      _openSession(stateStore, sessionId: 311, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final subscribe = subscribe_msg.Subscribe(4101, 'invalid uri spaces');

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: subscribe,
        connectionId: 44,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeSubscribe));
      expect(frame[2], equals(4101));
      expect(frame[4], equals(wamp_core.Error.errorInvalidUri));
    });

    test('returns error when SUBSCRIBE references unknown session', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 512;

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final subscribe = subscribe_msg.Subscribe(5101, 'com.missing.session');

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: subscribe,
        connectionId: 45,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeSubscribe));
      expect(frame[2], equals(5101));
      expect(frame[4], equals(wamp_core.Error.noSuchSession));
      final details = frame[3] as Map<String, Object?>;
      expect(details['message'], contains('Session 512 not found'));
    });

    test('handles REGISTER by registering procedure', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 77;

      _openSession(stateStore, sessionId: 77, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final register = register_msg.Register(2001, 'com.myapp.procedure');
      register.options = register_msg.RegisterOptions(
        match: register_msg.RegisterOptions.matchPrefix,
        discloseCaller: true,
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: register,
        connectionId: 14,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeRegistered));
      expect(frame[1], equals(2001));
      final registrationId = frame[2] as int;
      expect(registrationId, isPositive);

      final snapshot = await _fetchSnapshot(stateStore.commandPort);
      expect(snapshot.registrations, hasLength(1));
      expect(
        snapshot.registrations.single.registrationId,
        equals(registrationId),
      );
    });

    test('returns error when REGISTER uses invalid URI', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 207;

      _openSession(stateStore, sessionId: 207, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      final register = register_msg.Register(2201, 'invalid procedure uri');

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: register,
        connectionId: 26,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeRegister));
      expect(frame[2], equals(2201));
      expect(frame[4], equals(wamp_core.Error.errorInvalidUri));
    });

    test('returns error when CALL targets missing procedure', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 701;

      _openSession(stateStore, sessionId: 701, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      final call = call_msg.Call(4102, 'com.missing.proc');

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: call,
        connectionId: 45,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeCall));
      expect(frame[2], equals(4102));
      expect(frame[4], equals(wamp_core.Error.noSuchProcedure));
    });

    test('rejects second REGISTER for non-shared procedure', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final firstState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      firstState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 601;

      final secondState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      secondState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 602;

      _openSession(stateStore, sessionId: 601, listener: listener);
      _openSession(stateStore, sessionId: 602, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: firstState,
        message: register_msg.Register(6301, 'com.demo.proc'),
        connectionId: 31,
      );
      await Future<void>.delayed(Duration.zero);
      bossMessages.clear();

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: secondState,
        message: register_msg.Register(6302, 'com.demo.proc'),
        connectionId: 32,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final frame =
          jsonDecode(utf8.decode(workerSend['payload'] as Uint8List))
              as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeRegister));
      expect(frame[2], equals(6302));
      expect(frame[4], equals(wamp_core.Error.procedureAlreadyExists));
    });

    test('round-robin registrations alternate callees', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final calleeOne =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeOne
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 703;

      final calleeTwo =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeTwo
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 704;

      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 705;

      _openSession(
        stateStore,
        sessionId: 703,
        listener: listener,
        connectionId: 41,
      );
      _openSession(
        stateStore,
        sessionId: 704,
        listener: listener,
        connectionId: 42,
      );
      _openSession(
        stateStore,
        sessionId: 705,
        listener: listener,
        connectionId: 43,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final roundRobinOptions = register_msg.RegisterOptions(
        invoke: register_msg.RegisterOptions.invocationPolicyRoundRobin,
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeOne,
        message: register_msg.Register(
          6401,
          'com.shared.proc',
          options: roundRobinOptions,
        ),
        connectionId: 41,
      );
      await Future<void>.delayed(Duration.zero);
      bossMessages.clear();

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeTwo,
        message: register_msg.Register(
          6402,
          'com.shared.proc',
          options: roundRobinOptions,
        ),
        connectionId: 42,
      );
      await Future<void>.delayed(Duration.zero);
      bossMessages.clear();

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: call_msg.Call(8401, 'com.shared.proc'),
        connectionId: 43,
      );
      await Future<void>.delayed(Duration.zero);

      var forwards = _extractForwardMessages(bossMessages);
      expect(forwards, hasLength(1));
      expect(forwards.single['connectionId'], equals(41));
      var invocation = forwards.single['message'] as invocation_msg.Invocation;
      final invocationIdFirst = invocation.requestId;
      bossMessages.clear();

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeOne,
        message: yield_msg.Yield(invocationIdFirst),
        connectionId: 41,
      );
      await Future<void>.delayed(Duration.zero);
      bossMessages.clear();

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: call_msg.Call(8402, 'com.shared.proc'),
        connectionId: 43,
      );
      await Future<void>.delayed(Duration.zero);

      forwards = _extractForwardMessages(bossMessages);
      expect(forwards, hasLength(1));
      expect(forwards.single['connectionId'], equals(42));
      invocation = forwards.single['message'] as invocation_msg.Invocation;
      final invocationIdSecond = invocation.requestId;
      bossMessages.clear();

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeTwo,
        message: yield_msg.Yield(invocationIdSecond),
        connectionId: 42,
      );
      await Future<void>.delayed(Duration.zero);
    });

    test(
      'uses native forwarding for invocations when handle is present',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final callerState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        callerState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 801;

        final calleeState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        calleeState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 802;

        _openSession(
          stateStore,
          sessionId: 801,
          listener: listener,
          connectionId: 21,
        );
        _openSession(
          stateStore,
          sessionId: 802,
          listener: listener,
          connectionId: 22,
        );
        await Future<void>.delayed(Duration.zero);

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: register_msg.Register(7001, 'com.zero.proc'),
          connectionId: 22,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();

        final call = call_msg.Call(8001, 'com.zero.proc', arguments: ['arg']);
        final retainedHandles = <int>[];
        final incoming = NativeIncomingMessage.test(
          serializer: NativeMessageSerializer.json,
          message: call,
          handle: 88,
          onRetain: (handle) {
            retainedHandles.add(handle);
            return handle;
          },
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: call,
          connectionId: 21,
          incomingMessage: incoming,
        );

        await Future<void>.delayed(Duration.zero);

        final nativeCommands = bossMessages
            .where(
              (message) =>
                  message['type'] == 'worker_forward_native_invocation',
            )
            .toList();
        expect(nativeCommands, hasLength(1));
        expect(nativeCommands.single['handle'], equals(88));
        expect(retainedHandles, equals([88]));
        expect(
          bossMessages.where(
            (message) => message['type'] == 'worker_forward_message',
          ),
          isEmpty,
        );
      },
    );

    test(
      'handles PUBLISH by routing events and acknowledging publisher',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final publisherState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        publisherState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 501;

        _openSession(
          stateStore,
          sessionId: 501,
          listener: listener,
          connectionId: 11,
        );
        _openSession(
          stateStore,
          sessionId: 502,
          listener: listener,
          connectionId: 21,
        );
        await Future<void>.delayed(Duration.zero);

        final subscribeReply = ReceivePort();
        stateStore.commandPort.send(
          SubscriptionAddCommand(
            realmUri: 'realm1',
            sessionId: 502,
            topic: 'com.example.topic',
            matchPolicy: TopicMatchPolicy.exact,
            details: const {},
            replyPort: subscribeReply.sendPort,
          ),
        );
        final subscriptionId = await subscribeReply.first as int;
        subscribeReply.close();

        final snapshotBeforePublish = await _fetchSnapshot(
          stateStore.commandPort,
        );
        final subscriptionRecord = snapshotBeforePublish.subscriptions
            .firstWhere((entry) => entry.id == subscriptionId);
        expect(
          subscriptionRecord.subscribers.map((record) => record.sessionId),
          contains(502),
        );

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );
        final publish =
            publish_msg.Publish(9001, 'com.example.topic', arguments: ['hello'])
              ..options = publish_msg.PublishOptions(
                acknowledge: true,
                discloseMe: true,
              );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: publisherState,
          message: publish,
          connectionId: 11,
        );
        await Future<void>.delayed(Duration.zero);

        final forwards = _extractForwardMessages(bossMessages);
        expect(forwards, hasLength(1));
        final forward = forwards.single;
        expect(forward['connectionId'], equals(21));
        final event = forward['message'] as event_msg.Event;
        expect(event.subscriptionId, equals(subscriptionId));
        expect(event.publicationId, isPositive);
        expect(event.arguments, equals(['hello']));
        expect(event.details.publisher, equals(501));
        expect(event.details.topic, isNull);

        final workerSend = _extractWorkerSend(bossMessages);
        final payload = workerSend['payload'] as Uint8List;
        final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
        expect(frame.first, equals(MessageTypes.codePublished));
        expect(frame[1], equals(9001));
        expect(frame[2], equals(event.publicationId));
      },
    );

    test(
      'uses native forwarding for publish payloads when handle is present',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final publisherState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        publisherState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 551;

        _openSession(
          stateStore,
          sessionId: 551,
          listener: listener,
          connectionId: 11,
        );
        _openSession(
          stateStore,
          sessionId: 552,
          listener: listener,
          connectionId: 12,
        );
        await Future<void>.delayed(Duration.zero);

        final subscribeReply = ReceivePort();
        stateStore.commandPort.send(
          SubscriptionAddCommand(
            realmUri: 'realm1',
            sessionId: 552,
            topic: 'com.zero.topic',
            matchPolicy: TopicMatchPolicy.exact,
            details: const {},
            replyPort: subscribeReply.sendPort,
          ),
        );
        await subscribeReply.first;
        subscribeReply.close();

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );

        final publish =
            publish_msg.Publish(9601, 'com.zero.topic', arguments: ['payload'])
              ..options = publish_msg.PublishOptions(
                acknowledge: false,
                discloseMe: true,
              );

        final retainedHandles = <int>[];
        final incoming = NativeIncomingMessage.test(
          serializer: NativeMessageSerializer.json,
          message: publish,
          handle: 77,
          onRetain: (handle) {
            retainedHandles.add(handle);
            return handle;
          },
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: publisherState,
          message: publish,
          connectionId: 11,
          incomingMessage: incoming,
        );

        await Future<void>.delayed(Duration.zero);

        final nativeCommands = bossMessages
            .where(
              (message) => message['type'] == 'worker_forward_native_event',
            )
            .toList();
        expect(nativeCommands, hasLength(1));
        expect(nativeCommands.single['handle'], equals(77));
        expect(retainedHandles, equals([77]));
        expect(
          bossMessages.where(
            (message) => message['type'] == 'worker_forward_message',
          ),
          isEmpty,
        );
      },
    );

    test(
      'routes events to prefix subscription with disclosed topic when requested',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final publisherState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        publisherState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 611;

        _openSession(
          stateStore,
          sessionId: 611,
          listener: listener,
          connectionId: 71,
        );
        _openSession(
          stateStore,
          sessionId: 612,
          listener: listener,
          connectionId: 72,
        );
        await Future<void>.delayed(Duration.zero);

        final subscribeReply = ReceivePort();
        stateStore.commandPort.send(
          SubscriptionAddCommand(
            realmUri: 'realm1',
            sessionId: 612,
            topic: 'com.example.',
            matchPolicy: TopicMatchPolicy.prefix,
            details: const {'match': 'prefix'},
            replyPort: subscribeReply.sendPort,
          ),
        );
        await subscribeReply.first;
        subscribeReply.close();

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );
        final publish =
            publish_msg.Publish(
                9101,
                'com.example.topic',
                arguments: ['payload'],
              )
              ..options = publish_msg.PublishOptions(
                acknowledge: false,
                discloseMe: false,
              );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: publisherState,
          message: publish,
          connectionId: 71,
        );
        await Future<void>.delayed(Duration.zero);

        final forwards = _extractForwardMessages(bossMessages);
        expect(forwards, hasLength(1));
        final event = forwards.single['message'] as event_msg.Event;
        expect(event.subscriptionId, isPositive);
        expect(event.details.topic, equals('com.example.topic'));
        expect(event.details.publisher, isNull);
        expect(event.arguments, equals(['payload']));

        final workerSends = _collectWorkerSends(bossMessages);
        expect(workerSends, isEmpty);
      },
    );

    test('routes publish across workers to existing subscription', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final subscriberState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      subscriberState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 801;

      final publisherState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      publisherState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 802;

      _openSession(
        stateStore,
        sessionId: subscriberState.sessionId!,
        listener: listener,
        connectionId: 21,
      );
      _openSession(
        stateStore,
        sessionId: publisherState.sessionId!,
        listener: listener,
        connectionId: 22,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      final subscribe = subscribe_msg.Subscribe(1101, 'com.parallel.topic');
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: subscriberState,
        message: subscribe,
        connectionId: 21,
      );
      await Future<void>.delayed(Duration.zero);
      bossMessages.clear();

      final publish =
          publish_msg.Publish(
              1102,
              'com.parallel.topic',
              arguments: ['payload'],
            )
            ..options = publish_msg.PublishOptions(
              acknowledge: false,
              discloseMe: true,
            );
      final incoming = NativeIncomingMessage.test(
        serializer: NativeMessageSerializer.json,
        message: publish,
        handle: 211,
        onRetain: (handle) => handle,
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: publisherState,
        message: publish,
        connectionId: 22,
        incomingMessage: incoming,
      );
      await Future<void>.delayed(Duration.zero);

      final nativeEvents = bossMessages.where(
        (message) => message['type'] == 'worker_forward_native_event',
      );
      expect(nativeEvents.length, equals(1));
      final eventCommand = nativeEvents.single;
      expect(eventCommand['connectionId'], equals(21));
      expect(eventCommand['handle'], equals(211));
      expect(eventCommand['publicationId'], isPositive);
      expect(eventCommand['publisherSessionId'], equals(802));

      expect(
        bossMessages.where((message) => message['type'] == 'worker_send'),
        isEmpty,
      );
    });

    test('respects exclude_me option when publishing', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 821;

      _openSession(
        stateStore,
        sessionId: workerState.sessionId!,
        listener: listener,
        connectionId: 31,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final subscribe = subscribe_msg.Subscribe(1301, 'com.exclude.me');
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: subscribe,
        connectionId: 31,
      );
      await Future<void>.delayed(Duration.zero);
      bossMessages.clear();

      final publish =
          publish_msg.Publish(
              1302,
              'com.exclude.me',
              arguments: const ['payload'],
            )
            ..options = publish_msg.PublishOptions(
              acknowledge: false,
              excludeMe: true,
              discloseMe: true,
            );
      final incoming = NativeIncomingMessage.test(
        serializer: NativeMessageSerializer.json,
        message: publish,
        handle: 312,
        onRetain: (handle) => handle,
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: publish,
        connectionId: 31,
        incomingMessage: incoming,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        bossMessages.where(
          (message) => message['type'] == 'worker_forward_native_event',
        ),
        isEmpty,
      );
      expect(
        bossMessages.where(
          (message) => message['type'] == 'worker_forward_message',
        ),
        isEmpty,
      );
    });

    test(
      'releases retained handles when native publish cloning fails',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final subscriberOne =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        subscriberOne
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 8803;
        final subscriberTwo =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        subscriberTwo
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 8804;
        final publisherState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        publisherState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 8805;

        _openSession(
          stateStore,
          sessionId: subscriberOne.sessionId!,
          listener: listener,
          connectionId: 61,
        );
        _openSession(
          stateStore,
          sessionId: subscriberTwo.sessionId!,
          listener: listener,
          connectionId: 62,
        );
        _openSession(
          stateStore,
          sessionId: publisherState.sessionId!,
          listener: listener,
          connectionId: 63,
        );
        await Future<void>.delayed(Duration.zero);

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: subscriberOne,
          message: subscribe_msg.Subscribe(6101, 'com.zero.copy'),
          connectionId: 61,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: subscriberTwo,
          message: subscribe_msg.Subscribe(6102, 'com.zero.copy'),
          connectionId: 62,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();

        final publish =
            publish_msg.Publish(
                6103,
                'com.zero.copy',
                arguments: const ['payload'],
              )
              ..options = publish_msg.PublishOptions(
                acknowledge: false,
                discloseMe: true,
              );

        var retainCount = 0;
        final releasedHandles = <int>[];
        final incoming = NativeIncomingMessage.test(
          serializer: NativeMessageSerializer.json,
          message: publish,
          handle: 901,
          onRetain: (_) {
            retainCount += 1;
            if (retainCount == 1) {
              return 777;
            }
            return 0;
          },
          onRelease: releasedHandles.add,
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: publisherState,
          message: publish,
          connectionId: 63,
          incomingMessage: incoming,
        );
        await Future<void>.delayed(Duration.zero);

        expect(releasedHandles, equals([777]));
        final forwarded = bossMessages
            .where((message) => message['type'] == 'worker_forward_message')
            .toList();
        expect(forwarded, hasLength(2));
        expect(
          bossMessages.where(
            (message) => message['type'] == 'worker_forward_native_event',
          ),
          isEmpty,
        );
      },
    );

    test('respects eligible session filter when publishing', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final subscriberOne =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      subscriberOne
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 831;

      final subscriberTwo =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      subscriberTwo
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 832;

      final publisherState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      publisherState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 833;

      _openSession(
        stateStore,
        sessionId: subscriberOne.sessionId!,
        listener: listener,
        connectionId: 41,
      );
      _openSession(
        stateStore,
        sessionId: subscriberTwo.sessionId!,
        listener: listener,
        connectionId: 42,
      );
      _openSession(
        stateStore,
        sessionId: publisherState.sessionId!,
        listener: listener,
        connectionId: 43,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      Future<void> subscribe({
        required WorkerConnectionState state,
        required int connectionId,
        required int requestId,
      }) async {
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: state,
          message: subscribe_msg.Subscribe(requestId, 'com.eligible.topic'),
          connectionId: connectionId,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();
      }

      await subscribe(state: subscriberOne, connectionId: 41, requestId: 1401);
      await subscribe(state: subscriberTwo, connectionId: 42, requestId: 1402);

      final publish =
          publish_msg.Publish(
              1403,
              'com.eligible.topic',
              arguments: const ['payload'],
            )
            ..options = publish_msg.PublishOptions(
              eligible: [subscriberTwo.sessionId!],
              discloseMe: true,
            );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: publisherState,
        message: publish,
        connectionId: 43,
      );
      await Future<void>.delayed(Duration.zero);

      final nativeEvents = bossMessages
          .where((message) => message['type'] == 'worker_forward_native_event')
          .toList();
      final serializedEvents = bossMessages
          .where((message) => message['type'] == 'worker_forward_message')
          .where((message) => message['message'] is event_msg.Event)
          .toList();
      final totalEvents = nativeEvents.length + serializedEvents.length;
      expect(totalEvents, equals(1));
      if (nativeEvents.isNotEmpty) {
        final eventCommand = nativeEvents.single;
        expect(eventCommand['connectionId'], equals(42));
        expect(eventCommand['subscriptionId'], isPositive);
      } else {
        final forward = serializedEvents.single;
        expect(forward['connectionId'], equals(42));
        final event = forward['message'] as event_msg.Event;
        expect(event.subscriptionId, isPositive);
      }
    });

    test(
      'acknowledged publish sends PUBLISHED response to publisher',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final subscriberState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        subscriberState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 811;

        final publisherState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        publisherState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 812;

        _openSession(
          stateStore,
          sessionId: subscriberState.sessionId!,
          listener: listener,
          connectionId: 23,
        );
        _openSession(
          stateStore,
          sessionId: publisherState.sessionId!,
          listener: listener,
          connectionId: 24,
        );
        await Future<void>.delayed(Duration.zero);

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );

        final subscribe = subscribe_msg.Subscribe(1201, 'com.ack.topic');
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: subscriberState,
          message: subscribe,
          connectionId: 23,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();

        final publish =
            publish_msg.Publish(1202, 'com.ack.topic', arguments: ['payload'])
              ..options = publish_msg.PublishOptions(
                acknowledge: true,
                discloseMe: true,
              );
        final incoming = NativeIncomingMessage.test(
          serializer: NativeMessageSerializer.json,
          message: publish,
          handle: 311,
          onRetain: (handle) => handle,
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: publisherState,
          message: publish,
          connectionId: 24,
          incomingMessage: incoming,
        );
        await Future<void>.delayed(Duration.zero);

        final nativeEvents = bossMessages.where(
          (message) => message['type'] == 'worker_forward_native_event',
        );
        expect(nativeEvents.length, equals(1));
        final eventCommand = nativeEvents.single;
        final publicationId = eventCommand['publicationId'];
        expect(eventCommand['connectionId'], equals(23));

        final workerSends = _collectWorkerSends(bossMessages);
        expect(workerSends, hasLength(1));
        final publishReply =
            jsonDecode(utf8.decode(workerSends.single['payload'] as Uint8List))
                as List<dynamic>;
        expect(publishReply.first, MessageTypes.codePublished);
        expect(publishReply[1], equals(1202));
        expect(publishReply[2], equals(publicationId));
        expect(workerSends.single['connectionId'], equals(24));
      },
    );

    test(
      'routes events to wildcard subscription and exposes actual topic',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final publisherState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        publisherState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 613;

        final subscriberState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        subscriberState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 614;

        _openSession(
          stateStore,
          sessionId: 613,
          listener: listener,
          connectionId: 71,
        );
        _openSession(
          stateStore,
          sessionId: 614,
          listener: listener,
          connectionId: 72,
        );
        await Future<void>.delayed(Duration.zero);

        final subscribeReply = ReceivePort();
        stateStore.commandPort.send(
          SubscriptionAddCommand(
            realmUri: 'realm1',
            sessionId: 614,
            topic: 'com.example.*.topic',
            matchPolicy: TopicMatchPolicy.wildcard,
            details: const {'match': 'wildcard'},
            replyPort: subscribeReply.sendPort,
          ),
        );
        await subscribeReply.first;
        subscribeReply.close();

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );
        final publish = publish_msg.Publish(
          9121,
          'com.example.weather.topic',
          arguments: ['rain'],
        );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: publisherState,
          message: publish,
          connectionId: 71,
        );
        await Future<void>.delayed(Duration.zero);

        final forwards = _extractForwardMessages(bossMessages);
        expect(forwards, hasLength(1));
        expect(forwards.single['connectionId'], equals(72));
        final event = forwards.single['message'] as event_msg.Event;
        expect(event.details.topic, equals('com.example.weather.topic'));
        expect(event.arguments, equals(['rain']));
      },
    );

    test('exclude_me prevents publisher receiving own event', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 621;

      _openSession(
        stateStore,
        sessionId: 621,
        listener: listener,
        connectionId: 81,
      );
      await Future<void>.delayed(Duration.zero);

      final subscribeReply = ReceivePort();
      stateStore.commandPort.send(
        SubscriptionAddCommand(
          realmUri: 'realm1',
          sessionId: 621,
          topic: 'com.example.topic',
          matchPolicy: TopicMatchPolicy.exact,
          details: const {},
          replyPort: subscribeReply.sendPort,
        ),
      );
      await subscribeReply.first;
      subscribeReply.close();

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final publish =
          publish_msg.Publish(9201, 'com.example.topic', arguments: ['self'])
            ..options = publish_msg.PublishOptions(
              acknowledge: true,
              excludeMe: true,
            );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: publish,
        connectionId: 81,
      );
      await Future<void>.delayed(Duration.zero);

      final forwards = _extractForwardMessages(bossMessages);
      expect(forwards, isEmpty);

      final workerSend = _extractWorkerSend(bossMessages);
      final frame =
          jsonDecode(utf8.decode(workerSend['payload'] as Uint8List))
              as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codePublished));
    });

    test('exclude list filters specific subscribers', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final publisherState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      publisherState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 631;

      _openSession(
        stateStore,
        sessionId: 631,
        listener: listener,
        connectionId: 91,
      );
      _openSession(
        stateStore,
        sessionId: 632,
        listener: listener,
        connectionId: 92,
      );
      _openSession(
        stateStore,
        sessionId: 633,
        listener: listener,
        connectionId: 93,
      );
      await Future<void>.delayed(Duration.zero);

      for (final sessionId in [632, 633]) {
        final reply = ReceivePort();
        stateStore.commandPort.send(
          SubscriptionAddCommand(
            realmUri: 'realm1',
            sessionId: sessionId,
            topic: 'com.example.topic',
            matchPolicy: TopicMatchPolicy.exact,
            details: const {},
            replyPort: reply.sendPort,
          ),
        );
        await reply.first;
        reply.close();
      }

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final publish =
          publish_msg.Publish(9301, 'com.example.topic', arguments: ['hello'])
            ..options = publish_msg.PublishOptions(
              acknowledge: false,
              exclude: [632],
            );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: publisherState,
        message: publish,
        connectionId: 91,
      );
      await Future<void>.delayed(Duration.zero);

      final forwards = _extractForwardMessages(bossMessages);
      expect(forwards, hasLength(1));
      expect(forwards.single['connectionId'], equals(93));

      final workerSends = _collectWorkerSends(bossMessages);
      expect(workerSends, isEmpty);
    });

    test('eligible list limits recipients', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final publisherState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      publisherState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 641;

      _openSession(
        stateStore,
        sessionId: 641,
        listener: listener,
        connectionId: 101,
      );
      _openSession(
        stateStore,
        sessionId: 642,
        listener: listener,
        connectionId: 102,
      );
      _openSession(
        stateStore,
        sessionId: 643,
        listener: listener,
        connectionId: 103,
      );
      await Future<void>.delayed(Duration.zero);

      for (final sessionId in [642, 643]) {
        final reply = ReceivePort();
        stateStore.commandPort.send(
          SubscriptionAddCommand(
            realmUri: 'realm1',
            sessionId: sessionId,
            topic: 'com.example.topic',
            matchPolicy: TopicMatchPolicy.exact,
            details: const {},
            replyPort: reply.sendPort,
          ),
        );
        await reply.first;
        reply.close();
      }

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final publish =
          publish_msg.Publish(9401, 'com.example.topic', arguments: ['hi'])
            ..options = publish_msg.PublishOptions(
              acknowledge: false,
              eligible: [642],
            );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: publisherState,
        message: publish,
        connectionId: 101,
      );
      await Future<void>.delayed(Duration.zero);

      final forwards = _extractForwardMessages(bossMessages);
      expect(forwards, hasLength(1));
      expect(forwards.single['connectionId'], equals(102));

      final workerSends = _collectWorkerSends(bossMessages);
      expect(workerSends, isEmpty);
    });

    test(
      'handles CALL by dispatching invocation and forwarding RESULT',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final callerState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        callerState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 601;
        final calleeState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        calleeState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 602;

        _openSession(
          stateStore,
          sessionId: 601,
          listener: listener,
          connectionId: 31,
        );
        _openSession(
          stateStore,
          sessionId: 602,
          listener: listener,
          connectionId: 32,
        );
        await Future<void>.delayed(Duration.zero);

        final registerReply = ReceivePort();
        stateStore.commandPort.send(
          ProcedureRegisterCommand(
            realmUri: 'realm1',
            sessionId: 602,
            procedure: 'com.example.sum',
            details: const {},
            replyPort: registerReply.sendPort,
          ),
        );
        final registrationId = await registerReply.first as int;
        registerReply.close();

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );
        final call = call_msg.Call(7001, 'com.example.sum', arguments: [1, 2])
          ..options = call_msg.CallOptions(
            receiveProgress: false,
            discloseMe: true,
          );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: call,
          connectionId: 31,
        );
        await Future<void>.delayed(Duration.zero);

        final invocationForward = _extractForwardMessages(bossMessages);
        expect(invocationForward, hasLength(1));
        final invocationEnvelope = invocationForward.single;
        expect(invocationEnvelope['connectionId'], equals(32));
        final invocation =
            invocationEnvelope['message'] as invocation_msg.Invocation;
        final invocationId = invocation.requestId;
        expect(invocation.registrationId, equals(registrationId));
        expect(invocation.details.caller, equals(601));
        expect(invocation.details.receiveProgress, isFalse);
        bossMessages.clear();

        final yieldMessage = yield_msg.Yield(invocationId, arguments: [3]);

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: calleeState,
          message: yieldMessage,
          connectionId: 32,
        );
        await Future<void>.delayed(Duration.zero);

        final resultForward = _extractForwardMessages(bossMessages);
        expect(resultForward, hasLength(1));
        final resultEnvelope = resultForward.single;
        expect(resultEnvelope['connectionId'], equals(31));
        final result = resultEnvelope['message'] as result_msg.Result;
        expect(result.callRequestId, equals(7001));
        expect(result.details.progress, isFalse);
        expect(result.arguments, equals([3]));
      },
    );

    test('forwards invocation ERROR back to caller', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 701;
      final calleeState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 702;

      _openSession(
        stateStore,
        sessionId: 701,
        listener: listener,
        connectionId: 41,
      );
      _openSession(
        stateStore,
        sessionId: 702,
        listener: listener,
        connectionId: 42,
      );
      await Future<void>.delayed(Duration.zero);

      final registerReply = ReceivePort();
      stateStore.commandPort.send(
        ProcedureRegisterCommand(
          realmUri: 'realm1',
          sessionId: 702,
          procedure: 'com.example.fail',
          details: const {},
          replyPort: registerReply.sendPort,
        ),
      );
      final registrationId = await registerReply.first as int;
      registerReply.close();

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final call = call_msg.Call(8001, 'com.example.fail');

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: call,
        connectionId: 41,
      );
      await Future<void>.delayed(Duration.zero);

      final invocationForward = _extractForwardMessages(bossMessages);
      expect(invocationForward, hasLength(1));
      final invocation =
          invocationForward.single['message'] as invocation_msg.Invocation;
      expect(invocation.registrationId, equals(registrationId));
      final invocationId = invocation.requestId;
      bossMessages.clear();

      final invocationError = error_msg.Error(
        MessageTypes.codeInvocation,
        invocationId,
        {},
        'wamp.error.runtime_error',
        arguments: ['boom'],
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeState,
        message: invocationError,
        connectionId: 42,
      );
      await Future<void>.delayed(Duration.zero);

      final errorForward = _extractForwardMessages(bossMessages);
      expect(errorForward, hasLength(1));
      final forwarded = errorForward.single;
      expect(forwarded['connectionId'], equals(41));
      final error = forwarded['message'] as error_msg.Error;
      expect(error.requestTypeId, equals(MessageTypes.codeCall));
      expect(error.requestId, equals(8001));
      expect(error.error, equals('wamp.error.runtime_error'));
      expect(error.arguments, equals(['boom']));
    });

    test('supports progressive call results when caller opts in', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 751;
      final calleeState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 752;

      _openSession(
        stateStore,
        sessionId: 751,
        listener: listener,
        connectionId: 111,
      );
      _openSession(
        stateStore,
        sessionId: 752,
        listener: listener,
        connectionId: 112,
      );
      await Future<void>.delayed(Duration.zero);

      final registerReply = ReceivePort();
      stateStore.commandPort.send(
        ProcedureRegisterCommand(
          realmUri: 'realm1',
          sessionId: 752,
          procedure: 'com.example.progress',
          details: const {},
          replyPort: registerReply.sendPort,
        ),
      );
      await registerReply.first;
      registerReply.close();

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final call = call_msg.Call(9601, 'com.example.progress')
        ..options = call_msg.CallOptions(receiveProgress: true);

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: callerState,
        message: call,
        connectionId: 111,
      );
      await Future<void>.delayed(Duration.zero);

      final invocationForward = _extractForwardMessages(bossMessages);
      expect(invocationForward, hasLength(1));
      final invocation =
          invocationForward.single['message'] as invocation_msg.Invocation;
      final invocationId = invocation.requestId;
      bossMessages.clear();

      final progressiveYield = yield_msg.Yield(
        invocationId,
        options: yield_msg.YieldOptions(progress: true),
        arguments: [1],
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeState,
        message: progressiveYield,
        connectionId: 112,
      );
      await Future<void>.delayed(Duration.zero);

      var forwarded = _extractForwardMessages(bossMessages);
      expect(forwarded, hasLength(1));
      var result = forwarded.single['message'] as result_msg.Result;
      expect(result.callRequestId, equals(9601));
      expect(result.details.progress, isTrue);
      expect(result.arguments, equals([1]));
      bossMessages.clear();

      final finalYield = yield_msg.Yield(invocationId, arguments: [2]);

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: calleeState,
        message: finalYield,
        connectionId: 112,
      );
      await Future<void>.delayed(Duration.zero);

      forwarded = _extractForwardMessages(bossMessages);
      expect(forwarded, hasLength(1));
      result = forwarded.single['message'] as result_msg.Result;
      expect(result.details.progress, isFalse);
      expect(result.arguments, equals([2]));

      final invocationRecord = await realmContexts
          .contextFor('realm1')
          .getInvocation(invocationId);
      expect(invocationRecord, isNull);
    });

    test('handles UNSUBSCRIBE by removing subscription', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 88;

      _openSession(stateStore, sessionId: 88, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final subscribe = subscribe_msg.Subscribe(3001, 'com.myapp.topic');
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: subscribe,
        connectionId: 55,
      );
      await Future<void>.delayed(Duration.zero);

      final subscribedSend = _extractWorkerSend(bossMessages);
      final subscribedPayload = subscribedSend['payload'] as Uint8List;
      final subscribedFrame =
          jsonDecode(utf8.decode(subscribedPayload)) as List<dynamic>;
      final subscriptionId = subscribedFrame[2] as int;
      bossMessages.clear();

      final unsubscribe = unsubscribe_msg.Unsubscribe(3002, subscriptionId);
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: unsubscribe,
        connectionId: 55,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeUnsubscribed));
      expect(frame[1], equals(3002));

      final snapshot = await _fetchSnapshot(stateStore.commandPort);
      expect(snapshot.subscriptions, isEmpty);
    });

    test('returns error when unsubscribing foreign subscription', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 99;

      _openSession(stateStore, sessionId: 99, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      final unsubscribe = unsubscribe_msg.Unsubscribe(3010, 4242);
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: unsubscribe,
        connectionId: 56,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeUnsubscribe));
      expect(frame[2], equals(3010));
      expect(frame[4], equals(wamp_core.Error.noSuchSubscription));
    });

    test('handles UNREGISTER by removing registration', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 111;

      _openSession(stateStore, sessionId: 111, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      final register = register_msg.Register(6001, 'com.myapp.proc');
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: register,
        connectionId: 57,
      );
      await Future<void>.delayed(Duration.zero);

      final registeredSend = _extractWorkerSend(bossMessages);
      final registeredPayload = registeredSend['payload'] as Uint8List;
      final registeredFrame =
          jsonDecode(utf8.decode(registeredPayload)) as List<dynamic>;
      final registrationId = registeredFrame[2] as int;
      bossMessages.clear();

      final unregister = unregister_msg.Unregister(6002, registrationId);
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: unregister,
        connectionId: 57,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeUnregistered));
      expect(frame[1], equals(6002));

      final snapshot = await _fetchSnapshot(stateStore.commandPort);
      expect(snapshot.registrations, isEmpty);
    });

    test('returns error when unregistering foreign registration', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 222;

      _openSession(stateStore, sessionId: 222, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );

      final unregister = unregister_msg.Unregister(7001, 5150);
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: unregister,
        connectionId: 58,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeUnregister));
      expect(frame[2], equals(7001));
      expect(frame[4], equals(wamp_core.Error.noSuchRegistration));
    });

    test('responds with unknown error when SUBSCRIBE handler throws', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 301;

      _openSession(stateStore, sessionId: 301, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = _ThrowingRealmContextCache.subscribe();
      addTearDown(realmContexts.dispose);

      final subscribe = subscribe_msg.Subscribe(4001, 'com.myapp.fail');
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: subscribe,
        connectionId: 33,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeSubscribe));
      expect(frame[2], equals(4001));
      expect(frame[4], equals('wamp.error.unknown'));
      final details = frame[3] as Map<String, dynamic>;
      expect(details['message'], contains('subscribe failure'));
    });

    test('responds with unknown error when REGISTER handler throws', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 302;

      _openSession(stateStore, sessionId: 302, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = _ThrowingRealmContextCache.register();
      addTearDown(realmContexts.dispose);

      final register = register_msg.Register(5001, 'com.myapp.fail');
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: register,
        connectionId: 34,
      );
      await Future<void>.delayed(Duration.zero);

      final workerSend = _extractWorkerSend(bossMessages);
      final payload = workerSend['payload'] as Uint8List;
      final frame = jsonDecode(utf8.decode(payload)) as List<dynamic>;
      expect(frame.first, equals(MessageTypes.codeError));
      expect(frame[1], equals(MessageTypes.codeRegister));
      expect(frame[2], equals(5001));
      expect(frame[4], equals('wamp.error.unknown'));
      final details = frame[3] as Map<String, dynamic>;
      expect(details['message'], contains('register failure'));
    });
  });

  group('Meta events', () {
    test('emits subscription meta events on subscribe/unsubscribe', () async {
      final subscriptionEvents = <SubscriptionMetaEvent>[];
      final sub = stateStore.subscriptionMetaEvents.listen(
        subscriptionEvents.add,
      );
      addTearDown(sub.cancel);

      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 901;

      _openSession(stateStore, sessionId: 901, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: subscribe_msg.Subscribe(5001, 'com.meta.topic'),
        connectionId: 51,
      );
      await Future<void>.delayed(Duration.zero);

      final subscribedFrame =
          jsonDecode(
                utf8.decode(
                  _extractWorkerSend(bossMessages)['payload'] as Uint8List,
                ),
              )
              as List<dynamic>;
      final subscriptionId = subscribedFrame[2] as int;
      bossMessages.clear();

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: unsubscribe_msg.Unsubscribe(5002, subscriptionId),
        connectionId: 51,
      );
      await Future<void>.delayed(Duration.zero);

      expect(subscriptionEvents, hasLength(4));
      expect(
        subscriptionEvents.map((event) => event.type),
        orderedEquals([
          SubscriptionMetaEventType.created,
          SubscriptionMetaEventType.subscribed,
          SubscriptionMetaEventType.unsubscribed,
          SubscriptionMetaEventType.deleted,
        ]),
      );
      expect(subscriptionEvents.first.subscriptionId, equals(subscriptionId));
      expect(subscriptionEvents.first.sessionId, equals(901));
    });

    test('emits registration meta events on register/unregister', () async {
      final registrationEvents = <RegistrationMetaEvent>[];
      final sub = stateStore.registrationMetaEvents.listen(
        registrationEvents.add,
      );
      addTearDown(sub.cancel);

      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final workerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      workerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 902;

      _openSession(stateStore, sessionId: 902, listener: listener);
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: register_msg.Register(5101, 'com.meta.proc'),
        connectionId: 61,
      );
      await Future<void>.delayed(Duration.zero);

      final registeredFrame =
          jsonDecode(
                utf8.decode(
                  _extractWorkerSend(bossMessages)['payload'] as Uint8List,
                ),
              )
              as List<dynamic>;
      final registrationId = registeredFrame[2] as int;
      bossMessages.clear();

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: workerState,
        message: unregister_msg.Unregister(5102, registrationId),
        connectionId: 61,
      );
      await Future<void>.delayed(Duration.zero);

      expect(registrationEvents, hasLength(4));
      expect(
        registrationEvents.map((event) => event.type),
        orderedEquals([
          RegistrationMetaEventType.created,
          RegistrationMetaEventType.registered,
          RegistrationMetaEventType.unregistered,
          RegistrationMetaEventType.deleted,
        ]),
      );
      expect(registrationEvents.first.registrationId, equals(registrationId));
      expect(registrationEvents.first.sessionId, equals(902));
    });
  });

  group('Advanced profile placeholders', () {
    test('routes wildcard subscriptions respecting priority order', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final publisherState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      publisherState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9011;

      _openSession(
        stateStore,
        sessionId: 9011,
        listener: listener,
        connectionId: 111,
      );
      _openSession(
        stateStore,
        sessionId: 9012,
        listener: listener,
        connectionId: 112,
      );
      _openSession(
        stateStore,
        sessionId: 9013,
        listener: listener,
        connectionId: 113,
      );
      _openSession(
        stateStore,
        sessionId: 9014,
        listener: listener,
        connectionId: 114,
      );
      _openSession(
        stateStore,
        sessionId: 9015,
        listener: listener,
        connectionId: 115,
      );
      _openSession(
        stateStore,
        sessionId: 9016,
        listener: listener,
        connectionId: 116,
      );
      await Future<void>.delayed(Duration.zero);

      Future<int> addSubscription({
        required int sessionId,
        required String topic,
        required TopicMatchPolicy policy,
        Map<String, Object?> details = const {},
      }) async {
        final reply = ReceivePort();
        stateStore.commandPort.send(
          SubscriptionAddCommand(
            realmUri: 'realm1',
            sessionId: sessionId,
            topic: topic,
            matchPolicy: policy,
            details: details,
            replyPort: reply.sendPort,
          ),
        );
        final id = await reply.first as int;
        reply.close();
        return id;
      }

      final exactId = await addSubscription(
        sessionId: 9012,
        topic: 'com.advanced.topic',
        policy: TopicMatchPolicy.exact,
      );
      final prefixLongId = await addSubscription(
        sessionId: 9013,
        topic: 'com.advanced.',
        policy: TopicMatchPolicy.prefix,
        details: const {'match': 'prefix'},
      );
      final prefixShortId = await addSubscription(
        sessionId: 9014,
        topic: 'com.',
        policy: TopicMatchPolicy.prefix,
        details: const {'match': 'prefix'},
      );
      final wildcardSpecificId = await addSubscription(
        sessionId: 9015,
        topic: 'com.advanced.*',
        policy: TopicMatchPolicy.wildcard,
        details: const {'match': 'wildcard'},
      );
      final wildcardGenericId = await addSubscription(
        sessionId: 9016,
        topic: '*.advanced.*',
        policy: TopicMatchPolicy.wildcard,
        details: const {'match': 'wildcard'},
      );

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      addTearDown(realmContexts.dispose);

      final publish = publish_msg.Publish(
        99001,
        'com.advanced.topic',
        arguments: const ['payload'],
      );

      await handleSessionMessageForTest(
        bossPort: bossPort.sendPort,
        statePort: stateStore.commandPort,
        realmContexts: realmContexts,
        state: publisherState,
        message: publish,
        connectionId: 111,
      );
      await Future<void>.delayed(Duration.zero);

      final forwards = _extractForwardMessages(bossMessages);
      expect(forwards, hasLength(5));
      final connectionOrder = forwards
          .map((forward) => forward['connectionId'])
          .toList();
      expect(connectionOrder, equals([112, 113, 114, 115, 116]));

      final subscriptionOrder = forwards
          .map(
            (forward) => (forward['message'] as event_msg.Event).subscriptionId,
          )
          .toList();
      expect(
        subscriptionOrder,
        equals([
          exactId,
          prefixLongId,
          prefixShortId,
          wildcardSpecificId,
          wildcardGenericId,
        ]),
      );
    });

    test('dispatches shared registrations using round-robin policy', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9101;

      final calleeA =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeA
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9102;

      final calleeB =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeB
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9103;

      final calleeC =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      calleeC
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9104;

      _openSession(
        stateStore,
        sessionId: 9101,
        listener: listener,
        connectionId: 121,
      );
      _openSession(
        stateStore,
        sessionId: 9102,
        listener: listener,
        connectionId: 122,
      );
      _openSession(
        stateStore,
        sessionId: 9103,
        listener: listener,
        connectionId: 123,
      );
      _openSession(
        stateStore,
        sessionId: 9104,
        listener: listener,
        connectionId: 124,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      addTearDown(realmContexts.dispose);

      final roundRobinOptions = register_msg.RegisterOptions(
        invoke: register_msg.RegisterOptions.invocationPolicyRoundRobin,
      );

      Future<void> registerCallee(
        WorkerConnectionState callee,
        int connectionId,
        int requestId,
      ) async {
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callee,
          message: register_msg.Register(
            requestId,
            'com.advanced.shared',
            options: roundRobinOptions,
          ),
          connectionId: connectionId,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();
      }

      await registerCallee(calleeA, 122, 9501);
      await registerCallee(calleeB, 123, 9502);
      await registerCallee(calleeC, 124, 9503);

      Future<int> placeCall(int requestId, int expectedConnectionId) async {
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: call_msg.Call(requestId, 'com.advanced.shared'),
          connectionId: 121,
        );
        await Future<void>.delayed(Duration.zero);
        final forwards = _extractForwardMessages(bossMessages);
        expect(forwards, hasLength(1));
        final forward = forwards.single;
        expect(forward['connectionId'], equals(expectedConnectionId));
        final invocation = forward['message'] as invocation_msg.Invocation;
        bossMessages.clear();
        return invocation.requestId;
      }

      Future<void> completeInvocation(
        int invocationId,
        WorkerConnectionState callee,
        int connectionId,
      ) async {
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callee,
          message: yield_msg.Yield(invocationId),
          connectionId: connectionId,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();
      }

      final firstInvocation = await placeCall(9601, 122); // callee A
      await completeInvocation(firstInvocation, calleeA, 122);

      final secondInvocation = await placeCall(9602, 123); // callee B
      await completeInvocation(secondInvocation, calleeB, 123);

      final thirdInvocation = await placeCall(9603, 124); // callee C
      await completeInvocation(thirdInvocation, calleeC, 124);

      final fourthInvocation = await placeCall(
        9604,
        122,
      ); // cycle back to callee A
      await completeInvocation(fourthInvocation, calleeA, 122);
    });

    test('prefers first/last invocation policies', () async {
      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((dynamic message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final listener = _buildListener();
      final callerState =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      callerState
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9201;

      final firstCallee =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      firstCallee
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9202;

      final secondCallee =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      secondCallee
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9203;

      final thirdCallee =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as WorkerConnectionState;
      thirdCallee
        ..serializer = NativeMessageSerializer.json
        ..phase = HandshakePhase.open
        ..realmUri = 'realm1'
        ..realmSettings = routerSettings.realms.first
        ..sessionId = 9204;

      _openSession(
        stateStore,
        sessionId: 9201,
        listener: listener,
        connectionId: 131,
      );
      _openSession(
        stateStore,
        sessionId: 9202,
        listener: listener,
        connectionId: 132,
      );
      _openSession(
        stateStore,
        sessionId: 9203,
        listener: listener,
        connectionId: 133,
      );
      _openSession(
        stateStore,
        sessionId: 9204,
        listener: listener,
        connectionId: 134,
      );
      await Future<void>.delayed(Duration.zero);

      final realmContexts = RealmContextCache(
        statePort: stateStore.commandPort,
      );
      addTearDown(realmContexts.dispose);

      Future<void> registerProcedure({
        required WorkerConnectionState callee,
        required int connectionId,
        required int requestId,
        required String procedure,
        required register_msg.RegisterOptions options,
      }) async {
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callee,
          message: register_msg.Register(
            requestId,
            procedure,
            options: options,
          ),
          connectionId: connectionId,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();
      }

      Future<int> invokeAndExpect({
        required int requestId,
        required String procedure,
        required int expectedConnectionId,
      }) async {
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callerState,
          message: call_msg.Call(requestId, procedure),
          connectionId: 131,
        );
        await Future<void>.delayed(Duration.zero);
        final forwards = _extractForwardMessages(bossMessages);
        expect(forwards, hasLength(1));
        final forward = forwards.single;
        expect(forward['connectionId'], equals(expectedConnectionId));
        final invocation = forward['message'] as invocation_msg.Invocation;
        bossMessages.clear();
        return invocation.requestId;
      }

      Future<void> completeInvocation({
        required int invocationId,
        required WorkerConnectionState callee,
        required int connectionId,
      }) async {
        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: callee,
          message: yield_msg.Yield(invocationId),
          connectionId: connectionId,
        );
        await Future<void>.delayed(Duration.zero);
        bossMessages.clear();
      }

      // First policy: always choose first callee.
      const procedureFirst = 'com.advanced.policy.first';
      final firstPolicyOptions = register_msg.RegisterOptions(
        invoke: register_msg.RegisterOptions.invocationPolicyFirst,
      );
      await registerProcedure(
        callee: firstCallee,
        connectionId: 132,
        requestId: 9701,
        procedure: procedureFirst,
        options: firstPolicyOptions,
      );
      await registerProcedure(
        callee: secondCallee,
        connectionId: 133,
        requestId: 9702,
        procedure: procedureFirst,
        options: firstPolicyOptions,
      );

      var invocationId = await invokeAndExpect(
        requestId: 9711,
        procedure: procedureFirst,
        expectedConnectionId: 132,
      );
      await completeInvocation(
        invocationId: invocationId,
        callee: firstCallee,
        connectionId: 132,
      );

      invocationId = await invokeAndExpect(
        requestId: 9712,
        procedure: procedureFirst,
        expectedConnectionId: 132,
      );
      await completeInvocation(
        invocationId: invocationId,
        callee: firstCallee,
        connectionId: 132,
      );

      // Last policy: choose most recently registered callee.
      const procedureLast = 'com.advanced.policy.last';
      final lastPolicyOptions = register_msg.RegisterOptions(
        invoke: register_msg.RegisterOptions.invocationPolicyLast,
      );

      await registerProcedure(
        callee: secondCallee,
        connectionId: 133,
        requestId: 9722,
        procedure: procedureLast,
        options: lastPolicyOptions,
      );

      await registerProcedure(
        callee: thirdCallee,
        connectionId: 134,
        requestId: 9723,
        procedure: procedureLast,
        options: lastPolicyOptions,
      );

      invocationId = await invokeAndExpect(
        requestId: 9724,
        procedure: procedureLast,
        expectedConnectionId: 134,
      );
      await completeInvocation(
        invocationId: invocationId,
        callee: thirdCallee,
        connectionId: 134,
      );

      invocationId = await invokeAndExpect(
        requestId: 9725,
        procedure: procedureLast,
        expectedConnectionId: 134,
      );
      await completeInvocation(
        invocationId: invocationId,
        callee: thirdCallee,
        connectionId: 134,
      );
    });

    test(
      'enforces authrole include/exclude lists for EVENT delivery',
      () async {
        final bossMessages = <Map<String, Object?>>[];
        final bossPort = ReceivePort()
          ..listen((dynamic message) {
            if (message is Map<String, Object?>) {
              bossMessages.add(message);
            }
          });
        addTearDown(bossPort.close);

        final listener = _buildListener();
        final publisherState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        publisherState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 9300;

        final memberState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        memberState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 9301;

        final guestState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        guestState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 9302;

        final adminState =
            createWorkerStateForTest(
                  listener: listener,
                  listenerSettings: routerSettings.listeners.first,
                )
                as WorkerConnectionState;
        adminState
          ..serializer = NativeMessageSerializer.json
          ..phase = HandshakePhase.open
          ..realmUri = 'realm1'
          ..realmSettings = routerSettings.realms.first
          ..sessionId = 9303;

        _openSession(
          stateStore,
          sessionId: 9300,
          listener: listener,
          connectionId: 150,
          authRole: 'publisher',
        );
        _openSession(
          stateStore,
          sessionId: 9301,
          listener: listener,
          connectionId: 151,
          authRole: 'member',
        );
        _openSession(
          stateStore,
          sessionId: 9302,
          listener: listener,
          connectionId: 152,
          authRole: 'guest',
        );
        _openSession(
          stateStore,
          sessionId: 9303,
          listener: listener,
          connectionId: 153,
          authRole: 'admin',
        );
        await Future<void>.delayed(Duration.zero);

        final realmContexts = RealmContextCache(
          statePort: stateStore.commandPort,
        );
        addTearDown(realmContexts.dispose);

        Future<int> subscribe({
          required WorkerConnectionState state,
          required int connectionId,
          required int requestId,
        }) async {
          await handleSessionMessageForTest(
            bossPort: bossPort.sendPort,
            statePort: stateStore.commandPort,
            realmContexts: realmContexts,
            state: state,
            message: subscribe_msg.Subscribe(requestId, 'com.filters.topic'),
            connectionId: connectionId,
          );
          await Future<void>.delayed(Duration.zero);
          final frame =
              jsonDecode(
                    utf8.decode(
                      _extractWorkerSend(bossMessages)['payload'] as Uint8List,
                    ),
                  )
                  as List<dynamic>;
          bossMessages.clear();
          return frame[2] as int;
        }

        final memberSubscription = await subscribe(
          state: memberState,
          connectionId: 151,
          requestId: 9801,
        );
        final guestSubscription = await subscribe(
          state: guestState,
          connectionId: 152,
          requestId: 9802,
        );
        final adminSubscription = await subscribe(
          state: adminState,
          connectionId: 153,
          requestId: 9803,
        );

        final publish =
            publish_msg.Publish(
                99001,
                'com.filters.topic',
                arguments: const ['payload'],
              )
              ..options = publish_msg.PublishOptions(
                excludeAuthRole: ['guest'],
                eligibleAuthRole: ['member', 'guest'],
              );

        await handleSessionMessageForTest(
          bossPort: bossPort.sendPort,
          statePort: stateStore.commandPort,
          realmContexts: realmContexts,
          state: publisherState,
          message: publish,
          connectionId: 150,
        );
        await Future<void>.delayed(Duration.zero);

        final forwards = _extractForwardMessages(bossMessages);
        expect(forwards, hasLength(1));
        final forward = forwards.single;
        expect(forward['connectionId'], equals(151));
        final event = forward['message'] as event_msg.Event;
        expect(event.subscriptionId, equals(memberSubscription));
        expect(event.arguments, equals(['payload']));

        final workerSends = _collectWorkerSends(bossMessages);
        expect(workerSends, isEmpty);

        expect(guestSubscription, isNotNull);
        expect(adminSubscription, isNotNull);
      },
    );
  });
}

void _openSession(
  RouterStateStore store, {
  required int sessionId,
  required RouterListener listener,
  int connectionId = 99,
  String authRole = 'member',
  String authId = 'tester',
}) {
  final session = SessionRecord(
    id: sessionId,
    authId: authId,
    authRole: authRole,
    roles: const {},
    workerId: 1,
    connectionId: connectionId,
    lastActivity: DateTime.now(),
    listener: listener,
  );
  store.commandPort.send(
    SessionOpenCommand(realmUri: 'realm1', session: session),
  );
}

Future<RealmSnapshot> _fetchSnapshot(SendPort commandPort) async {
  final replyPort = ReceivePort();
  commandPort.send(
    RealmSnapshotCommand(
      realmUri: 'realm1',
      knownVersion: null,
      replyPort: replyPort.sendPort,
    ),
  );
  final response = await replyPort.first as RealmSnapshotResponse;
  replyPort.close();
  return response.snapshot;
}

Map<String, Object?> _extractWorkerSend(List<Map<String, Object?>> messages) {
  final workerSend = messages
      .where((message) => message['type'] == 'worker_send')
      .toList();
  expect(workerSend, hasLength(1));
  return workerSend.single;
}

List<Map<String, Object?>> _collectWorkerSends(
  List<Map<String, Object?>> messages,
) => messages
    .where((message) => message['type'] == 'worker_send')
    .cast<Map<String, Object?>>()
    .toList();

List<Map<String, Object?>> _extractForwardMessages(
  List<Map<String, Object?>> messages,
) => messages
    .where((message) => message['type'] == 'worker_forward_message')
    .cast<Map<String, Object?>>()
    .toList();

RouterSettings _buildRouterSettings() {
  final realm = RealmSettings(
    name: 'realm1',
    autoCreate: false,
    auth: const RealmAuthSettings(methods: [], methodOptions: {}),
    roles: const [],
    limits: const RealmLimitSettings(),
  );

  final listener = ListenerSettings(
    type: 'rawsocket',
    endpoint: '127.0.0.1:8000',
    authmethods: const [],
    options: const {},
  );

  return RouterSettings(
    realms: [realm],
    listeners: [listener],
    metrics: null,
    authenticators: const <String, AuthenticatorDefinition>{},
  );
}

RouterListener _buildListener() => RouterListener(
  listenerId: 1,
  endpoint: Endpoint(
    host: '127.0.0.1',
    port: 8000,
    tlsMode: TlsMode.disabled,
    maxRawSocketSizeExponent: 16,
  ),
  port: 8000,
);

enum _ThrowMode { subscribe, register }

class _ThrowingRealmContextCache extends RealmContextCache {
  _ThrowingRealmContextCache._(this._dummyPort, this._mode)
    : super(statePort: _dummyPort.sendPort);

  factory _ThrowingRealmContextCache.subscribe() =>
      _ThrowingRealmContextCache._(ReceivePort(), _ThrowMode.subscribe);

  factory _ThrowingRealmContextCache.register() =>
      _ThrowingRealmContextCache._(ReceivePort(), _ThrowMode.register);

  final ReceivePort _dummyPort;
  final _ThrowMode _mode;
  final Map<String, RealmContext> _overrides = {};

  @override
  RealmContext contextFor(String realmUri) => _overrides.putIfAbsent(
    realmUri,
    () => _ThrowingRealmContext(
      mode: _mode,
      realmUri: realmUri,
      statePort: _dummyPort.sendPort,
    ),
  );

  @override
  void invalidate(String realmUri) {
    super.invalidate(realmUri);
    _overrides.remove(realmUri);
  }

  void dispose() {
    _dummyPort.close();
  }
}

class _ThrowingRealmContext extends RealmContext {
  _ThrowingRealmContext({
    required this.mode,
    required super.realmUri,
    required super.statePort,
  });

  final _ThrowMode mode;

  @override
  Future<int> addSubscription({
    required int sessionId,
    required String topic,
    required TopicMatchPolicy matchPolicy,
    Map<String, Object?> details = const {},
  }) {
    if (mode == _ThrowMode.subscribe) {
      return Future<int>.error(Exception('subscribe failure'));
    }
    return Future<int>.error(UnsupportedError('addSubscription not supported'));
  }

  @override
  Future<int> registerProcedure({
    required int sessionId,
    required String procedure,
    Map<String, Object?> details = const {},
  }) {
    if (mode == _ThrowMode.register) {
      return Future<int>.error(Exception('register failure'));
    }
    return Future<int>.error(
      UnsupportedError('registerProcedure not supported'),
    );
  }
}

class _StaticRealmContextCache extends RealmContextCache {
  _StaticRealmContextCache({
    required SendPort statePort,
    required Map<String, RealmContext> overrides,
  }) : _overrides = Map<String, RealmContext>.from(overrides),
       super(statePort: statePort);

  final Map<String, RealmContext> _overrides;

  @override
  RealmContext contextFor(String realmUri) {
    final override = _overrides[realmUri];
    if (override == null) {
      throw StateError('No context override registered for $realmUri');
    }
    return override;
  }

  @override
  void invalidate(String realmUri) {
    // Tests control the contexts explicitly; nothing to invalidate.
  }

  @override
  void dispose() {
    _overrides.clear();
    super.dispose();
  }
}

class _StateErrorRealmContext extends RealmContext {
  _StateErrorRealmContext({
    required super.realmUri,
    required super.statePort,
    required this.snapshot,
    required this.invocationId,
    required this.registrationId,
    required this.callerRequestId,
    required this.callerSessionId,
    required this.calleeSessionId,
    required this.allowProgress,
    this.cancelThrows = false,
    this.cancelFailureMessage = 'cancel failure',
    this.completeThrows = false,
    this.completeFailureMessage = 'completion failure',
  });

  final RealmSnapshot snapshot;
  final int invocationId;
  final int registrationId;
  final int callerRequestId;
  final int callerSessionId;
  final int calleeSessionId;
  final bool allowProgress;
  final bool cancelThrows;
  final String cancelFailureMessage;
  final bool completeThrows;
  final String completeFailureMessage;

  PendingInvocation _buildInvocation() => PendingInvocation(
    invocationId: invocationId,
    registrationId: registrationId,
    callerRequestId: callerRequestId,
    calleeSessionId: calleeSessionId,
    allowProgress: allowProgress,
    callerSessionId: callerSessionId,
  );

  @override
  Future<RealmSnapshot> ensureSnapshot({bool forceRefresh = false}) async =>
      snapshot;

  @override
  Future<PendingInvocation?> findInvocationByCaller({
    required int callerSessionId,
    required int requestId,
  }) async {
    if (callerSessionId == this.callerSessionId &&
        requestId == callerRequestId) {
      return _buildInvocation();
    }
    return null;
  }

  @override
  Future<bool> cancelInvocation({
    required int invocationId,
    required String mode,
    required bool waitForAck,
  }) {
    if (cancelThrows) {
      return Future<bool>.error(StateError(cancelFailureMessage));
    }
    return Future.value(true);
  }

  @override
  Future<PendingInvocation?> getInvocation(int invocationId) async {
    if (invocationId == this.invocationId) {
      return _buildInvocation();
    }
    return null;
  }

  @override
  Future<PendingInvocation?> completeInvocation(int invocationId) {
    if (completeThrows) {
      return Future<PendingInvocation?>.error(
        StateError(completeFailureMessage),
      );
    }
    return Future.value(_buildInvocation());
  }
}

class _ThrowingSendPort implements SendPort {
  _ThrowingSendPort({this.onSend, String? message})
    : _message = message ?? 'zero-copy forwarding failed';

  final void Function(Object? message)? onSend;
  final String _message;

  @override
  void send(Object? message) {
    onSend?.call(message);
    throw StateError(_message);
  }

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);

  @override
  String toString() => 'ThrowingSendPort($_message)';
}
