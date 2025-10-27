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

    test(
      'handles CANCEL by interrupting callee and notifying caller',
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
          ..mode = cancel_msg.CancelOptions.modeKill;
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
          equals(cancel_msg.CancelOptions.modeKill),
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

  group('Roadmap coverage placeholders', () {
    test(
      'emits subscription meta events on SUBSCRIBE/UNSUBSCRIBE',
      () async {},
      skip:
          'Meta event plumbing not implemented yet; add once RouterStateStore exposes meta event stream.',
    );

    test(
      'emits registration meta events on REGISTER/UNREGISTER',
      () async {},
      skip:
          'Registration meta events (meta procedures) tracked in ROADMAP; implement after meta infrastructure lands.',
    );

    test(
      'sends GOODBYE to client on router-initiated shutdown',
      () async {},
      skip:
          'Server initiated GOODBYE drainage flow not implemented; add when boss isolates support graceful close.',
    );
  });

  group('Advanced profile placeholders', () {
    test(
      'routes wildcard subscriptions respecting priority order',
      () async {},
      skip:
          'Wildcard/prefix order enforcement pending pattern subscription implementation.',
    );

    test(
      'dispatches shared registrations using round-robin policy',
      () async {},
      skip: 'Shared registration policies not implemented yet.',
    );

    test(
      'enforces authrole include/exclude lists for EVENT delivery',
      () async {},
      skip:
          'Authrole filtering hooks missing; align with publish options once authorization layer is added.',
    );
  });
}

void _openSession(
  RouterStateStore store, {
  required int sessionId,
  required RouterListener listener,
  int connectionId = 99,
}) {
  final session = SessionRecord(
    id: sessionId,
    authId: 'tester',
    authRole: 'member',
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
