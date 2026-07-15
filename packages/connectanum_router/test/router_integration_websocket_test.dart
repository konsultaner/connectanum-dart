@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library router_integration_websocket_test;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:async/async.dart' show StreamQueue;
import 'package:connectanum_client/connectanum.dart' as client_pkg;
import 'package:connectanum_client/src/transport/socket/socket_helper.dart'
    as socket_helper;
import 'package:connectanum_client/src/transport/socket/socket_transport.dart'
    as socket_transport;
import 'package:connectanum_core/connectanum_core.dart'
    as core_error
    show Error;
import 'package:connectanum_client/src/transport/websocket/websocket_transport_io.dart'
    as ws_transport;
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/connectanum_core.dart'
    show
        CallOptions,
        ConnectanumE2eeProfile,
        LazyPayloadEncoding,
        MessageTypes,
        PublishOptions,
        Result,
        WampCborAes256GcmProvider,
        YieldOptions;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

import 'support/native_lib.dart';

void main() {
  final nativeLib = resolveOrBuildNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport with --features ffi-test first.'
      : null;

  group('WebSocket WAMP integration', () {
    test(
      'negotiates subprotocols and routes publish/call with large payloads',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final events = <Map<String, Object?>>[];
        final binding =
            Router(
              _buildWebSocketConfig(),
              settings: _buildWebSocketSettings(),
            ).start(
              runtime,
              onEvent: (event) {
                if (event is Map<String, Object?>) {
                  events.add(event);
                }
              },
              workerPollInterval: const Duration(milliseconds: 1),
            );
        addTearDown(binding.dispose);

        final listener = binding.listeners.single;
        final url = 'ws://127.0.0.1:${listener.port}/ws';

        final clientA = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withMsgpackSerializer(url),
        );
        final sessionA = await clientA.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('clientA connect timeout'),
        );
        addTearDown(() => sessionA.close());

        final subscription = await sessionA.subscribe('com.example.ws.topic');
        final eventFuture = subscription.eventStream!.first;

        final registration = await sessionA.register('com.example.ws.proc');
        registration.onInvoke((invocation) async {
          final args = invocation.arguments ?? const [];
          final payload = _asBytes(args.isEmpty ? null : args.first);
          invocation.respondWith(
            arguments: [payload],
            argumentsKeywords: {'len': payload.length},
          );
        });

        final clientB = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withMsgpackSerializer(url),
        );
        final sessionB = await clientB.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('clientB connect timeout'),
        );
        addTearDown(() => sessionB.close());

        final payload = Uint8List.fromList(
          List<int>.generate(2 * 1024 * 1024 + 17, (index) => index % 251),
        );

        await sessionB
            .publish(
              'com.example.ws.topic',
              arguments: [payload],
              options: PublishOptions(acknowledge: true, excludeMe: false),
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('publish timeout'),
            );
        final event = await eventFuture.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('event timeout'),
        );
        final eventPayload = _asBytes(event.arguments?.first);
        expect(eventPayload.length, equals(payload.length));
        expect(eventPayload, orderedEquals(payload));

        final result = await sessionB
            .call('com.example.ws.proc', arguments: [payload])
            .first
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('call timeout'),
            );
        expect(result, isA<Result>());
        final resultPayload = _asBytes(result.arguments!.first);
        expect(resultPayload, orderedEquals(payload));
        expect(result.argumentsKeywords?['len'], equals(payload.length));

        await _waitForCondition(
          () =>
              events
                  .where(
                    (event) =>
                        event['type'] == 'listener_websocket_accepted' &&
                        event['protocol'] == 'wamp.2.msgpack' &&
                        event['serializer'] == 'msgpack',
                  )
                  .length >=
              2,
          timeout: const Duration(seconds: 5),
          reason: 'websocket acceptance events missing: $events',
        );
      },
      skip: skipReason,
    );

    test(
      'routes AES-256-GCM payload E2EE opaquely across websocket serializers',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final binding = Router(
          _buildWebSocketConfig(),
          settings: _buildWebSocketSettings(),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(binding.dispose);

        final listener = binding.listeners.single;
        final url = 'ws://127.0.0.1:${listener.port}/ws';
        final key = List<int>.generate(32, (index) => index + 1);
        final endpointAProvider = WampCborAes256GcmProvider.single(
          keyId: 'release-key',
          key: key,
        );
        final endpointBProvider = WampCborAes256GcmProvider.single(
          keyId: 'release-key',
          key: key,
        );

        final endpointAClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withJsonSerializer(url),
          e2eeProvider: endpointAProvider,
        );
        final endpointBClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withMsgpackSerializer(url),
          e2eeProvider: endpointBProvider,
        );
        final endpointASession = await endpointAClient.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('E2EE endpoint A connect timeout'),
        );
        final endpointBSession = await endpointBClient.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('E2EE endpoint B connect timeout'),
        );
        addTearDown(endpointASession.close);
        addTearDown(endpointBSession.close);

        final subscription = await endpointASession.subscribe(
          'com.example.ws.e2ee.topic',
        );
        final eventFuture = subscription.eventStream!.first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('E2EE event timeout'),
        );
        final registration = await endpointASession.register(
          'com.example.ws.e2ee.proc',
        );
        registration.onInvoke((invocation) {
          expect(invocation.arguments, equals(const ['encrypted-call']));
          invocation.respondWith(
            arguments: const ['encrypted-result'],
            argumentsKeywords: const {'endpoint': 'callee'},
            options: YieldOptions(
              pptScheme: ConnectanumE2eeProfile.scheme,
              pptSerializer: ConnectanumE2eeProfile.serializer,
              pptCipher: ConnectanumE2eeProfile.aes256Gcm,
              pptKeyId: 'release-key',
            ),
          );
        });

        await endpointBSession
            .publish(
              'com.example.ws.e2ee.topic',
              arguments: const ['encrypted-event'],
              argumentsKeywords: const {'endpoint': 'publisher'},
              options: PublishOptions(
                acknowledge: true,
                excludeMe: false,
                pptScheme: ConnectanumE2eeProfile.scheme,
                pptSerializer: ConnectanumE2eeProfile.serializer,
                pptCipher: ConnectanumE2eeProfile.aes256Gcm,
                pptKeyId: 'release-key',
              ),
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('E2EE publish timeout'),
            );
        final event = await eventFuture;
        expect(event.details.pptScheme, equals(ConnectanumE2eeProfile.scheme));
        expect(
          event.details.pptSerializer,
          equals(ConnectanumE2eeProfile.serializer),
        );
        expect(
          event.details.pptCipher,
          equals(ConnectanumE2eeProfile.aes256Gcm),
        );
        expect(event.details.pptKeyId, equals('release-key'));
        expect(event.e2eeProvider, same(endpointAProvider));
        expect(event.hasDecodedPptPayload, isFalse);
        expect(event.arguments, equals(const ['encrypted-event']));
        expect(
          event.argumentsKeywords,
          equals(const {'endpoint': 'publisher'}),
        );

        final result = await endpointBSession
            .call(
              'com.example.ws.e2ee.proc',
              arguments: const ['encrypted-call'],
              options: CallOptions(
                pptScheme: ConnectanumE2eeProfile.scheme,
                pptSerializer: ConnectanumE2eeProfile.serializer,
                pptCipher: ConnectanumE2eeProfile.aes256Gcm,
                pptKeyId: 'release-key',
              ),
            )
            .first
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('E2EE call timeout'),
            );
        expect(result.arguments, equals(const ['encrypted-result']));
        expect(result.argumentsKeywords, equals(const {'endpoint': 'callee'}));
      },
      skip: skipReason,
    );

    test(
      'routes progressive call invocations across websocket serializers',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final binding = Router(
          _buildWebSocketConfig(),
          settings: _buildWebSocketSettings(),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(binding.dispose);

        final listener = binding.listeners.single;
        final url = 'ws://127.0.0.1:${listener.port}/ws';
        final calleeClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withMsgpackSerializer(url),
        );
        final callerClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withJsonSerializer(url),
        );
        final callee = await calleeClient.connect().first.timeout(
          const Duration(seconds: 10),
        );
        final caller = await callerClient.connect().first.timeout(
          const Duration(seconds: 10),
        );
        addTearDown(callee.close);
        addTearDown(caller.close);

        final invocationIds = <int>[];
        final progress = <bool>[];
        final chunks = <String>[];
        final registration = await callee.register(
          'com.example.ws.progressive_upload',
        );
        registration.onInvoke((invocation) {
          invocationIds.add(invocation.requestId);
          progress.add(invocation.details.progress ?? false);
          chunks.add(invocation.arguments!.single as String);
          if (invocation.details.progress != true) {
            invocation.respondWith(arguments: [chunks.join('|')]);
          }
        });

        final call = caller.startProgressiveCall(
          'com.example.ws.progressive_upload',
          arguments: const ['one'],
        );
        call.sendChunk(arguments: const ['two']);
        call.finish(arguments: const ['three']);
        final result = await call.results.single.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('progressive invocation result timeout'),
        );

        expect(invocationIds, hasLength(3));
        expect(invocationIds.toSet(), hasLength(1));
        expect(progress, equals(const [true, true, false]));
        expect(chunks, equals(const ['one', 'two', 'three']));
        expect(result.arguments, equals(const ['one|two|three']));
      },
      skip: skipReason,
    );

    test('enforces call timeout and interrupts the Callee', () async {
      final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });

      final events = <Map<String, Object?>>[];
      final binding =
          Router(
            _buildWebSocketConfig(),
            settings: _buildWebSocketSettings(),
          ).start(
            runtime,
            onEvent: (event) {
              if (event is Map<String, Object?>) {
                events.add(event);
              }
            },
            workerPollInterval: const Duration(milliseconds: 1),
          );
      addTearDown(binding.dispose);

      final listener = binding.listeners.single;
      final url = 'ws://127.0.0.1:${listener.port}/ws';
      final calleeClient = client_pkg.Client(
        realm: 'realm1',
        transport: ws_transport.WebSocketTransport.withMsgpackSerializer(url),
      );
      final callerClient = client_pkg.Client(
        realm: 'realm1',
        transport: ws_transport.WebSocketTransport.withJsonSerializer(url),
      );
      final callee = await calleeClient.connect().first.timeout(
        const Duration(seconds: 10),
      );
      final caller = await callerClient.connect().first.timeout(
        const Duration(seconds: 10),
      );
      addTearDown(callee.close);
      addTearDown(caller.close);

      final invocationReceived = Completer<client_pkg.Invocation>();
      final registration = await callee.register('com.example.ws.timeout');
      registration.onInvoke((invocation) {
        invocationReceived.complete(invocation);
      });

      Object? callError;
      try {
        await caller.callSinglePayload(
          'com.example.ws.timeout',
          options: CallOptions(timeout: 80),
        );
      } catch (error) {
        callError = error;
      }
      expect(callError, isA<core_error.Error>());
      expect((callError! as core_error.Error).error, core_error.Error.timeout);

      final invocation = await invocationReceived.future.timeout(
        const Duration(seconds: 5),
      );
      await _waitForCondition(
        () => invocation.responseClosed,
        timeout: const Duration(seconds: 5),
        reason: 'timed-out Callee invocation was not interrupted',
      );
      await _waitForCondition(
        () => events.any((event) => event['type'] == 'invocation_timeout'),
        timeout: const Duration(seconds: 5),
        reason: 'router invocation_timeout event missing: $events',
      );
    }, skip: skipReason);

    test(
      'serves standard WAMP meta procedure calls to client sessions',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final binding = Router(
          _buildWebSocketConfig(),
          settings: _buildWebSocketSettings(),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(binding.dispose);

        final listener = binding.listeners.single;
        final url = 'ws://127.0.0.1:${listener.port}/ws';
        final client = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withJsonSerializer(url),
        );
        final session = await client.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('client connect timeout'),
        );
        addTearDown(session.close);

        await session
            .register('com.example.ws.meta.proc')
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('registration timeout'),
            );
        await session
            .subscribe('com.example.ws.meta.topic')
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('subscription timeout'),
            );

        final sessionList = await session
            .callSinglePayload('wamp.session.list')
            .timeout(const Duration(seconds: 10));
        expect(sessionList.arguments?.single as List, contains(session.id));

        final sessionGet = await session
            .callSinglePayload('wamp.session.get', arguments: [session.id])
            .timeout(const Duration(seconds: 10));
        expect(
          (sessionGet.arguments?.single as Map<String, Object?>)['session'],
          equals(session.id),
        );

        final registrationMatch = await session
            .callSinglePayload(
              'wamp.registration.match',
              arguments: const ['com.example.ws.meta.proc'],
            )
            .timeout(const Duration(seconds: 10));
        final registrationId = registrationMatch.arguments?.single as int;

        final registrationGet = await session
            .callSinglePayload(
              'wamp.registration.get',
              arguments: [registrationId],
            )
            .timeout(const Duration(seconds: 10));
        expect(
          (registrationGet.arguments?.single as Map<String, Object?>)['uri'],
          equals('com.example.ws.meta.proc'),
        );

        final callees = await session
            .callSinglePayload(
              'wamp.registration.list_callees',
              arguments: [registrationId],
            )
            .timeout(const Duration(seconds: 10));
        expect(callees.arguments?.single as List, contains(session.id));

        final subscriptionMatch = await session
            .callSinglePayload(
              'wamp.subscription.match',
              arguments: const ['com.example.ws.meta.topic'],
            )
            .timeout(const Duration(seconds: 10));
        final subscriptionId =
            (subscriptionMatch.arguments?.single as List).single as int;

        final subscriptionGet = await session
            .callSinglePayload(
              'wamp.subscription.get',
              arguments: [subscriptionId],
            )
            .timeout(const Duration(seconds: 10));
        expect(
          (subscriptionGet.arguments?.single as Map<String, Object?>)['uri'],
          equals('com.example.ws.meta.topic'),
        );

        final subscribers = await session
            .callSinglePayload(
              'wamp.subscription.list_subscribers',
              arguments: [subscriptionId],
            )
            .timeout(const Duration(seconds: 10));
        expect(subscribers.arguments?.single as List, contains(session.id));
      },
      skip: skipReason,
    );

    test(
      'publishes standard WAMP meta lifecycle events to client sessions',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final binding = Router(
          _buildWebSocketConfig(),
          settings: _buildWebSocketSettings(),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(binding.dispose);

        final listener = binding.listeners.single;
        final url = 'ws://127.0.0.1:${listener.port}/ws';
        final observerClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withJsonSerializer(url),
        );
        final observer = await observerClient.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('observer connect timeout'),
        );
        addTearDown(observer.close);

        final sessionJoin = Completer<List<dynamic>>();
        final sessionLeave = Completer<List<dynamic>>();
        final registrationCreate = Completer<List<dynamic>>();
        final registrationRegister = Completer<List<dynamic>>();
        final registrationUnregister = Completer<List<dynamic>>();
        final registrationDelete = Completer<List<dynamic>>();
        final subscriptionCreate = Completer<List<dynamic>>();
        final subscriptionSubscribe = Completer<List<dynamic>>();
        final subscriptionUnsubscribe = Completer<List<dynamic>>();
        final subscriptionDelete = Completer<List<dynamic>>();
        final joinedEvents = <List<dynamic>>[];
        int? actorSessionId;

        Future<void> observe(
          String topic,
          void Function(List<dynamic>) onArguments,
        ) async {
          final subscription = await observer
              .subscribe(topic)
              .timeout(const Duration(seconds: 10));
          subscription.onEvent((event) {
            final arguments = event.arguments;
            if (arguments != null) {
              onArguments(arguments);
            }
          });
        }

        await observe('wamp.session.on_join', (arguments) {
          joinedEvents.add(arguments);
          final details = arguments.firstOrNull;
          if (details is Map && details['session'] == actorSessionId) {
            if (!sessionJoin.isCompleted) sessionJoin.complete(arguments);
          }
        });
        await observe('wamp.session.on_leave', (arguments) {
          if (arguments.firstOrNull == actorSessionId) {
            if (!sessionLeave.isCompleted) sessionLeave.complete(arguments);
          }
        });
        await observe('wamp.registration.on_create', (arguments) {
          if (arguments.firstOrNull == actorSessionId) {
            if (!registrationCreate.isCompleted) {
              registrationCreate.complete(arguments);
            }
          }
        });
        await observe('wamp.registration.on_register', (arguments) {
          if (arguments.firstOrNull == actorSessionId) {
            if (!registrationRegister.isCompleted) {
              registrationRegister.complete(arguments);
            }
          }
        });
        await observe('wamp.registration.on_unregister', (arguments) {
          if (arguments.firstOrNull == actorSessionId) {
            if (!registrationUnregister.isCompleted) {
              registrationUnregister.complete(arguments);
            }
          }
        });
        await observe('wamp.registration.on_delete', (arguments) {
          if (arguments.firstOrNull == actorSessionId) {
            if (!registrationDelete.isCompleted) {
              registrationDelete.complete(arguments);
            }
          }
        });
        await observe('wamp.subscription.on_create', (arguments) {
          if (arguments.firstOrNull == actorSessionId) {
            if (!subscriptionCreate.isCompleted) {
              subscriptionCreate.complete(arguments);
            }
          }
        });
        await observe('wamp.subscription.on_subscribe', (arguments) {
          if (arguments.firstOrNull == actorSessionId) {
            if (!subscriptionSubscribe.isCompleted) {
              subscriptionSubscribe.complete(arguments);
            }
          }
        });
        await observe('wamp.subscription.on_unsubscribe', (arguments) {
          if (arguments.firstOrNull == actorSessionId) {
            if (!subscriptionUnsubscribe.isCompleted) {
              subscriptionUnsubscribe.complete(arguments);
            }
          }
        });
        await observe('wamp.subscription.on_delete', (arguments) {
          if (arguments.firstOrNull == actorSessionId) {
            if (!subscriptionDelete.isCompleted) {
              subscriptionDelete.complete(arguments);
            }
          }
        });

        final actorClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withJsonSerializer(url),
        );
        final actor = await actorClient.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('actor connect timeout'),
        );
        actorSessionId = actor.id;
        for (final arguments in joinedEvents) {
          final details = arguments.firstOrNull;
          if (details is Map && details['session'] == actorSessionId) {
            if (!sessionJoin.isCompleted) sessionJoin.complete(arguments);
          }
        }

        final joined = await sessionJoin.future.timeout(
          const Duration(seconds: 10),
        );
        expect((joined.single as Map)['session'], equals(actor.id));

        final registered = await actor
            .register('com.example.ws.meta.lifecycle.proc')
            .timeout(const Duration(seconds: 10));
        final createdRegistration = await registrationCreate.future.timeout(
          const Duration(seconds: 10),
        );
        final registrationDetails =
            createdRegistration[1] as Map<String, Object?>;
        expect(
          registrationDetails['uri'],
          equals('com.example.ws.meta.lifecycle.proc'),
        );
        expect(registrationDetails['created'], isA<String>());
        final registeredEvent = await registrationRegister.future.timeout(
          const Duration(seconds: 10),
        );
        expect(registeredEvent[1], equals(registrationDetails['id']));

        final subscribed = await actor
            .subscribe('com.example.ws.meta.lifecycle.topic')
            .timeout(const Duration(seconds: 10));
        final createdSubscription = await subscriptionCreate.future.timeout(
          const Duration(seconds: 10),
        );
        final subscriptionDetails =
            createdSubscription[1] as Map<String, Object?>;
        expect(
          subscriptionDetails['uri'],
          equals('com.example.ws.meta.lifecycle.topic'),
        );
        expect(subscriptionDetails['created'], isA<String>());
        final subscribedEvent = await subscriptionSubscribe.future.timeout(
          const Duration(seconds: 10),
        );
        expect(subscribedEvent[1], equals(subscriptionDetails['id']));

        await actor
            .unregister(registered.registrationId)
            .timeout(const Duration(seconds: 10));
        expect(
          (await registrationUnregister.future.timeout(
            const Duration(seconds: 10),
          ))[1],
          equals(registrationDetails['id']),
        );
        expect(
          (await registrationDelete.future.timeout(
            const Duration(seconds: 10),
          ))[1],
          equals(registrationDetails['id']),
        );

        await actor
            .unsubscribe(subscribed.subscriptionId)
            .timeout(const Duration(seconds: 10));
        expect(
          (await subscriptionUnsubscribe.future.timeout(
            const Duration(seconds: 10),
          ))[1],
          equals(subscriptionDetails['id']),
        );
        expect(
          (await subscriptionDelete.future.timeout(
            const Duration(seconds: 10),
          ))[1],
          equals(subscriptionDetails['id']),
        );

        await actor.close();
        final left = await sessionLeave.future.timeout(
          const Duration(seconds: 10),
        );
        expect(left.first, equals(actor.id));
        expect(left, hasLength(3));
      },
      skip: skipReason,
    );

    test(
      'preserves lazy payload bytes for internal session subscribers and callees',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final binding = Router(
          _buildWebSocketConfig(),
          settings: _buildWebSocketSettings(),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(binding.dispose);

        final internalSession = await binding.createInternalSession(
          realmUri: 'realm1',
          authId: 'lazy-internal',
          authRole: 'internal',
        );
        addTearDown(internalSession.close);

        final lazyEvents = <Map<String, Uint8List?>>[];
        final lazyInvocations = <Map<String, Uint8List?>>[];

        final subscription = await internalSession.subscribe(
          'com.example.ws.lazy.topic',
        );
        subscription.onLazyEventPayload((event) {
          expect(event.payload.encoding, LazyPayloadEncoding.messagePack);
          lazyEvents.add({
            'arguments': event.argumentsBytes,
            'argumentsKeywords': event.argumentsKeywordsBytes,
          });
        });

        final registration = await internalSession.register(
          'com.example.ws.lazy.proc',
        );
        registration.onLazyInvokePayload((invocation) {
          expect(invocation.payload.encoding, LazyPayloadEncoding.messagePack);
          lazyInvocations.add({
            'arguments': invocation.argumentsBytes,
            'argumentsKeywords': invocation.argumentsKeywordsBytes,
          });
          invocation.respondWith(arguments: const ['ok']);
        });

        final listener = binding.listeners.single;
        final url = 'ws://127.0.0.1:${listener.port}/ws';
        final client = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withMsgpackSerializer(url),
        );
        final session = await client.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('client connect timeout'),
        );
        addTearDown(session.close);

        final payload = Uint8List.fromList(
          List<int>.generate(128 * 1024 + 13, (index) => index % 251),
        );
        final kwargs = <String, Object?>{'len': payload.length, 'tag': 'lazy'};

        await session.publish(
          'com.example.ws.lazy.topic',
          arguments: [payload],
          argumentsKeywords: kwargs,
          options: PublishOptions(acknowledge: true, excludeMe: false),
        );
        final callResult = await session
            .call(
              'com.example.ws.lazy.proc',
              arguments: [payload],
              argumentsKeywords: kwargs,
            )
            .first;

        expect(callResult, isA<Result>());
        expect(callResult.arguments, equals(const ['ok']));

        await _waitForCondition(
          () => lazyEvents.isNotEmpty && lazyInvocations.isNotEmpty,
          timeout: const Duration(seconds: 10),
          reason:
              'lazy internal payloads missing: events=$lazyEvents invocations=$lazyInvocations',
        );

        expect(lazyEvents.single['arguments'], isNotNull);
        expect(lazyEvents.single['argumentsKeywords'], isNotNull);
        expect(lazyInvocations.single['arguments'], isNotNull);
        expect(lazyInvocations.single['argumentsKeywords'], isNotNull);
      },
      skip: skipReason,
    );

    test(
      'bridges events, results, and errors across rawsocket and websocket transports',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final binding = Router(
          _buildWebSocketConfig(),
          settings: _buildWebSocketSettings(),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(binding.dispose);

        final listener = binding.listeners.single;
        final websocketUrl = 'ws://127.0.0.1:${listener.port}/ws';

        final rawJsonClient = client_pkg.Client(
          realm: 'realm1',
          transport: socket_transport.SocketTransport(
            '127.0.0.1',
            listener.port,
            json_serializer.Serializer(),
            socket_helper.SocketHelper.serializationJson,
          ),
        );
        final websocketMsgpackClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withMsgpackSerializer(
            websocketUrl,
          ),
        );
        final rawCborClient = client_pkg.Client(
          realm: 'realm1',
          transport: socket_transport.SocketTransport(
            '127.0.0.1',
            listener.port,
            cbor_serializer.Serializer(),
            socket_helper.SocketHelper.serializationCbor,
          ),
        );

        final rawJsonSession = await rawJsonClient.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('raw json connect timeout'),
        );
        final websocketMsgpackSession = await websocketMsgpackClient
            .connect()
            .first
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('websocket msgpack connect timeout'),
            );
        final rawCborSession = await rawCborClient.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('raw cbor connect timeout'),
        );
        addTearDown(rawJsonSession.close);
        addTearDown(websocketMsgpackSession.close);
        addTearDown(rawCborSession.close);

        final subscription = await rawJsonSession.subscribe(
          'com.example.transport.mixed.topic',
        );
        final eventFuture = subscription.eventStream!.first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('transport mixed event timeout'),
        );

        final echoRegistration = await websocketMsgpackSession.register(
          'com.example.transport.mixed.proc',
        );
        echoRegistration.onInvoke((invocation) async {
          final payload = _asBytes(invocation.arguments?.first);
          final callNested = invocation.details.custom['nested'];
          invocation.respondWith(
            options: YieldOptions(
              custom: {
                'trace_id': 'yield-trace',
                'blob': Uint8List.fromList(const [13, 14, 15]),
                'nested': {
                  'payload': Uint8List.fromList(const [16, 17]),
                },
              },
            ),
            arguments: [payload],
            argumentsKeywords: {
              'transport': 'websocket',
              'serializer': 'msgpack',
              'len': payload.length,
              'source': invocation.argumentsKeywords?['source'],
              'call_trace_id': invocation.details.custom['trace_id'],
              'call_blob': invocation.details.custom['blob'],
              'call_nested': callNested is Map ? callNested['payload'] : null,
            },
          );
        });

        final errorRegistration = await websocketMsgpackSession.register(
          'com.example.transport.mixed.error',
        );
        errorRegistration.onInvoke((invocation) async {
          final payload = _asBytes(invocation.arguments?.first);
          invocation.respondWith(
            isError: true,
            errorUri: core_error.Error.runtimeError,
            arguments: [payload],
            argumentsKeywords: {
              'transport': 'websocket',
              'serializer': 'msgpack',
              'len': payload.length,
              'source': invocation.argumentsKeywords?['source'],
            },
          );
        });

        final payload = Uint8List.fromList(
          List<int>.generate(128 * 1024 + 29, (index) => index % 251),
        );

        await rawCborSession.publish(
          'com.example.transport.mixed.topic',
          arguments: [payload],
          argumentsKeywords: const {'source': 'raw-cbor', 'count': 1},
          options: PublishOptions(
            acknowledge: true,
            excludeMe: false,
            custom: {
              'trace_id': 'publish-trace',
              'blob': Uint8List.fromList(const [1, 2, 3]),
              'nested': {
                'payload': Uint8List.fromList(const [4, 5, 6]),
              },
            },
          ),
        );

        final event = await eventFuture;
        expect(_asBytes(event.arguments?.first), orderedEquals(payload));
        expect(
          event.argumentsKeywords,
          equals(const {'source': 'raw-cbor', 'count': 1}),
        );
        expect(event.details.custom['trace_id'], equals('publish-trace'));
        expect(
          event.details.custom['blob'],
          orderedEquals(Uint8List.fromList(const [1, 2, 3])),
        );
        expect(
          (event.details.custom['nested'] as Map)['payload'],
          orderedEquals(Uint8List.fromList(const [4, 5, 6])),
        );

        final result = await rawJsonSession
            .callSingle(
              'com.example.transport.mixed.proc',
              arguments: [payload],
              argumentsKeywords: const {'source': 'raw-json', 'count': 2},
              options: CallOptions(
                custom: {
                  'trace_id': 'call-trace',
                  'blob': Uint8List.fromList(const [7, 8, 9]),
                  'nested': {
                    'payload': Uint8List.fromList(const [10, 11, 12]),
                  },
                },
              ),
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('transport mixed result timeout'),
            );
        expect(result, isA<Result>());
        expect(_asBytes(result.arguments?.first), orderedEquals(payload));
        expect(result.argumentsKeywords?['transport'], equals('websocket'));
        expect(result.argumentsKeywords?['serializer'], equals('msgpack'));
        expect(result.argumentsKeywords?['len'], equals(131101));
        expect(result.argumentsKeywords?['source'], equals('raw-json'));
        expect(
          result.argumentsKeywords?['call_trace_id'],
          equals('call-trace'),
        );
        expect(
          result.argumentsKeywords?['call_blob'],
          orderedEquals(Uint8List.fromList(const [7, 8, 9])),
        );
        expect(
          result.argumentsKeywords?['call_nested'],
          orderedEquals(Uint8List.fromList(const [10, 11, 12])),
        );
        expect(result.details.custom['trace_id'], equals('yield-trace'));
        expect(
          result.details.custom['blob'],
          orderedEquals(Uint8List.fromList(const [13, 14, 15])),
        );
        expect(
          (result.details.custom['nested'] as Map)['payload'],
          orderedEquals(Uint8List.fromList(const [16, 17])),
        );

        await expectLater(
          rawCborSession
              .callSingle(
                'com.example.transport.mixed.error',
                arguments: [payload],
                argumentsKeywords: const {'source': 'raw-cbor', 'count': 3},
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => fail('transport mixed error timeout'),
              ),
          throwsA(
            isA<core_error.Error>()
                .having(
                  (error) => error.error,
                  'error',
                  core_error.Error.runtimeError,
                )
                .having(
                  (error) => _asBytes(error.arguments?.first),
                  'payload',
                  orderedEquals(payload),
                )
                .having(
                  (error) => error.argumentsKeywords,
                  'argumentsKeywords',
                  equals(const {
                    'transport': 'websocket',
                    'serializer': 'msgpack',
                    'len': 131101,
                    'source': 'raw-cbor',
                  }),
                ),
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'bridges events, results, and errors across mixed websocket serializers',
      () async {
        final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });

        final binding = Router(
          _buildWebSocketConfig(),
          settings: _buildWebSocketSettings(),
        ).start(runtime, workerPollInterval: const Duration(milliseconds: 1));
        addTearDown(binding.dispose);

        final listener = binding.listeners.single;
        final url = 'ws://127.0.0.1:${listener.port}/ws';

        final jsonClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withJsonSerializer(url),
        );
        final msgpackClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withMsgpackSerializer(url),
        );
        final cborClient = client_pkg.Client(
          realm: 'realm1',
          transport: ws_transport.WebSocketTransport.withCborSerializer(url),
        );

        final jsonSession = await jsonClient.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('json client connect timeout'),
        );
        final msgpackSession = await msgpackClient.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('msgpack client connect timeout'),
        );
        final cborSession = await cborClient.connect().first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('cbor client connect timeout'),
        );
        addTearDown(jsonSession.close);
        addTearDown(msgpackSession.close);
        addTearDown(cborSession.close);

        final subscription = await jsonSession.subscribe(
          'com.example.ws.mixed.topic',
        );
        final eventFuture = subscription.eventStream!.first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('mixed event timeout'),
        );

        final echoRegistration = await msgpackSession.register(
          'com.example.ws.mixed.proc',
        );
        echoRegistration.onInvoke((invocation) async {
          final payload = _asBytes(invocation.arguments?.first);
          final callNested = invocation.details.custom['nested'];
          invocation.respondWith(
            options: YieldOptions(
              custom: {
                'trace_id': 'yield-trace',
                'blob': Uint8List.fromList(const [13, 14, 15]),
                'nested': {
                  'payload': Uint8List.fromList(const [16, 17]),
                },
              },
            ),
            arguments: [payload],
            argumentsKeywords: {
              'serializer': 'msgpack',
              'len': payload.length,
              'source': invocation.argumentsKeywords?['source'],
              'call_trace_id': invocation.details.custom['trace_id'],
              'call_blob': invocation.details.custom['blob'],
              'call_nested': callNested is Map ? callNested['payload'] : null,
            },
          );
        });

        final errorRegistration = await msgpackSession.register(
          'com.example.ws.mixed.error',
        );
        errorRegistration.onInvoke((invocation) async {
          final payload = _asBytes(invocation.arguments?.first);
          invocation.respondWith(
            isError: true,
            errorUri: core_error.Error.runtimeError,
            arguments: [payload],
            argumentsKeywords: {
              'serializer': 'msgpack',
              'len': payload.length,
              'source': invocation.argumentsKeywords?['source'],
            },
          );
        });

        final payload = Uint8List.fromList(
          List<int>.generate(256 * 1024 + 29, (index) => index % 251),
        );

        await cborSession.publish(
          'com.example.ws.mixed.topic',
          arguments: [payload],
          argumentsKeywords: const {'source': 'cbor', 'count': 1},
          options: PublishOptions(
            acknowledge: true,
            excludeMe: false,
            custom: {
              'trace_id': 'publish-trace',
              'blob': Uint8List.fromList(const [1, 2, 3]),
              'nested': {
                'payload': Uint8List.fromList(const [4, 5, 6]),
              },
            },
          ),
        );

        final event = await eventFuture;
        expect(_asBytes(event.arguments?.first), orderedEquals(payload));
        expect(
          event.argumentsKeywords,
          equals(const {'source': 'cbor', 'count': 1}),
        );
        expect(event.details.custom['trace_id'], equals('publish-trace'));
        expect(
          event.details.custom['blob'],
          orderedEquals(Uint8List.fromList(const [1, 2, 3])),
        );
        expect(
          (event.details.custom['nested'] as Map)['payload'],
          orderedEquals(Uint8List.fromList(const [4, 5, 6])),
        );

        final result = await jsonSession
            .callSingle(
              'com.example.ws.mixed.proc',
              arguments: [payload],
              argumentsKeywords: const {'source': 'json', 'count': 2},
              options: CallOptions(
                custom: {
                  'trace_id': 'call-trace',
                  'blob': Uint8List.fromList(const [7, 8, 9]),
                  'nested': {
                    'payload': Uint8List.fromList(const [10, 11, 12]),
                  },
                },
              ),
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail('mixed result timeout'),
            );
        expect(result, isA<Result>());
        expect(_asBytes(result.arguments?.first), orderedEquals(payload));
        expect(result.argumentsKeywords?['serializer'], equals('msgpack'));
        expect(result.argumentsKeywords?['len'], equals(262173));
        expect(result.argumentsKeywords?['source'], equals('json'));
        expect(
          result.argumentsKeywords?['call_trace_id'],
          equals('call-trace'),
        );
        expect(
          result.argumentsKeywords?['call_blob'],
          orderedEquals(Uint8List.fromList(const [7, 8, 9])),
        );
        expect(
          result.argumentsKeywords?['call_nested'],
          orderedEquals(Uint8List.fromList(const [10, 11, 12])),
        );
        expect(result.details.custom['trace_id'], equals('yield-trace'));
        expect(
          result.details.custom['blob'],
          orderedEquals(Uint8List.fromList(const [13, 14, 15])),
        );
        expect(
          (result.details.custom['nested'] as Map)['payload'],
          orderedEquals(Uint8List.fromList(const [16, 17])),
        );

        await expectLater(
          cborSession
              .callSingle(
                'com.example.ws.mixed.error',
                arguments: [payload],
                argumentsKeywords: const {'source': 'cbor', 'count': 3},
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => fail('mixed error timeout'),
              ),
          throwsA(
            isA<core_error.Error>()
                .having(
                  (error) => error.error,
                  'error',
                  core_error.Error.runtimeError,
                )
                .having(
                  (error) => _asBytes(error.arguments?.first),
                  'payload',
                  orderedEquals(payload),
                )
                .having(
                  (error) => error.argumentsKeywords,
                  'argumentsKeywords',
                  equals(const {
                    'serializer': 'msgpack',
                    'len': 262173,
                    'source': 'cbor',
                  }),
                ),
          ),
        );
      },
      skip: skipReason,
    );

    test('reassembles continuation frames with large payloads', () async {
      final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });

      final events = <Map<String, Object?>>[];

      final binding =
          Router(
            _buildWebSocketConfig(),
            settings: _buildWebSocketSettings(),
          ).start(
            runtime,
            workerPollInterval: const Duration(milliseconds: 1),
            onEvent: (event) {
              if (event is Map<String, Object?>) {
                events.add(event);
              }
            },
          );
      addTearDown(binding.dispose);

      final internalSession = await binding.createInternalSession(
        realmUri: 'realm1',
        authId: 'ws-internal',
        authRole: 'internal',
      );
      addTearDown(internalSession.close);

      final largeResponse = 'Z' * (512 * 1024 + 33);
      final registration = await internalSession.register(
        'com.example.ws.large',
      );
      registration.onInvoke((invocation) async {
        invocation.respondWith(
          arguments: [largeResponse, invocation.arguments?.first ?? 'missing'],
        );
      });

      final listener = binding.listeners.single;
      final socket = await Socket.connect('127.0.0.1', listener.port);
      addTearDown(() => socket.destroy());

      final handshakeResponse = await _performWebSocketHandshake(
        socket,
        path: '/ws',
        host: '127.0.0.1:${listener.port}',
        protocols: const ['wamp.2.json'],
      );
      expect(
        handshakeResponse.toLowerCase(),
        contains('sec-websocket-protocol: wamp.2.json'),
      );
      await _waitForCondition(
        () => events.any(
          (event) => event['type'] == 'listener_websocket_accepted',
        ),
        timeout: const Duration(seconds: 5),
        reason: 'websocket handshake not accepted: $events',
      );
      await _waitForCondition(
        () => events.any((event) {
          final type = event['type'];
          return type == 'worker_connection_added' ||
              type == 'worker_registered';
        }),
        timeout: const Duration(seconds: 5),
        reason: 'websocket worker assignment missing: $events',
      );

      final hello = utf8.encode(
        jsonEncode([
          MessageTypes.codeHello,
          'realm1',
          {
            'roles': {
              'caller': {},
              'callee': {},
              'publisher': {},
              'subscriber': {},
            },
          },
        ]),
      );
      await _sendFragmentedMessage(socket, hello, chunkSize: 40);
      final welcomeFrame = await _readTextMessage(socket);
      final welcome = jsonDecode(utf8.decode(welcomeFrame)) as List<dynamic>;
      expect(welcome[0], equals(MessageTypes.codeWelcome));
      expect(welcome[1], isA<int>());

      const subscribeRequestId = 1001;
      final subscribe = utf8.encode(
        jsonEncode([
          MessageTypes.codeSubscribe,
          subscribeRequestId,
          {},
          'com.example.ws.topic',
        ]),
      );
      await _sendFragmentedMessage(socket, subscribe, chunkSize: 24);
      final subscribed =
          jsonDecode(utf8.decode(await _readTextMessage(socket)))
              as List<dynamic>;
      expect(subscribed[0], equals(MessageTypes.codeSubscribed));
      expect(subscribed[1], equals(subscribeRequestId));
      final subscriptionId = subscribed[2] as int;

      final largePayload = 'Y' * (512 * 1024 + 17);
      const publishRequestId = 1002;
      final publish = utf8.encode(
        jsonEncode([
          MessageTypes.codePublish,
          publishRequestId,
          {'acknowledge': true, 'exclude_me': false},
          'com.example.ws.topic',
          [largePayload],
        ]),
      );
      await _sendFragmentedMessage(socket, publish, chunkSize: 4096);
      final published =
          jsonDecode(utf8.decode(await _readTextMessage(socket)))
              as List<dynamic>;
      expect(published[0], equals(MessageTypes.codePublished));
      expect(published[1], equals(publishRequestId));
      final event =
          jsonDecode(utf8.decode(await _readTextMessage(socket)))
              as List<dynamic>;
      expect(event[0], equals(MessageTypes.codeEvent));
      expect(event[1], equals(subscriptionId));
      expect(
        event.length,
        greaterThanOrEqualTo(5),
        reason:
            'Unexpected EVENT message: len=${event.length} idx3=${event.length > 3 ? event[3].runtimeType : null} idx4=${event.length > 4 ? event[4].runtimeType : null}',
      );
      expect(
        event[3],
        isA<Map>(),
        reason:
            'Unexpected EVENT message: len=${event.length} idx3=${event[3].runtimeType}',
      );
      expect(
        event[4],
        isA<List>(),
        reason:
            'Unexpected EVENT message: len=${event.length} idx4=${event[4].runtimeType}',
      );
      expect((event[4] as List).first, equals(largePayload));

      const callRequestId = 4242;
      final callPayload = utf8.encode(
        jsonEncode([
          MessageTypes.codeCall,
          callRequestId,
          {},
          'com.example.ws.large',
          [largePayload],
        ]),
      );
      await _sendFragmentedMessage(socket, callPayload, chunkSize: 2048);
      final result =
          jsonDecode(utf8.decode(await _readTextMessage(socket)))
              as List<dynamic>;
      expect(result[0], equals(MessageTypes.codeResult));
      expect(result[1], equals(callRequestId));
      expect(result[2], isA<Map>());
      expect(result[3], isA<List>());
      final resultArgs = result[3] as List;
      expect(resultArgs.first, equals(largeResponse));
      expect(resultArgs[1], equals(largePayload));
    }, skip: skipReason);

    test('responds to ping and echoes empty close frames', () async {
      final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });

      final events = <Map<String, Object?>>[];
      final binding =
          Router(
            _buildWebSocketConfig(),
            settings: _buildWebSocketSettings(),
          ).start(
            runtime,
            workerPollInterval: const Duration(milliseconds: 1),
            onEvent: (event) {
              if (event is Map<String, Object?>) {
                events.add(event);
              }
            },
          );
      addTearDown(binding.dispose);

      final listener = binding.listeners.single;
      final socket = await Socket.connect('127.0.0.1', listener.port);
      addTearDown(() => socket.destroy());

      final handshakeResponse = await _performWebSocketHandshake(
        socket,
        path: '/ws',
        host: '127.0.0.1:${listener.port}',
        protocols: const ['wamp.2.json'],
      );
      expect(
        handshakeResponse.toLowerCase(),
        contains('sec-websocket-protocol: wamp.2.json'),
      );
      await _waitForCondition(
        () => events.any(
          (event) => event['type'] == 'listener_websocket_accepted',
        ),
        timeout: const Duration(seconds: 5),
        reason: 'websocket handshake not accepted: $events',
      );
      await _waitForCondition(
        () => events.any((event) {
          final type = event['type'];
          return type == 'worker_connection_added' ||
              type == 'worker_registered';
        }),
        timeout: const Duration(seconds: 5),
        reason: 'websocket worker assignment missing: $events',
      );

      const pingPayload = [1, 2, 3, 4, 5, 6];
      await _sendWebSocketFrame(
        socket,
        opcode: 0x9,
        fin: true,
        payload: pingPayload,
      );
      final pong = await _readFrame(socket);
      expect(pong.fin, isTrue);
      expect(pong.opcode, equals(0xA));
      expect(pong.payload, orderedEquals(pingPayload));

      await _sendWebSocketFrame(
        socket,
        opcode: 0x8,
        fin: true,
        payload: const [],
      );
      final close = await _readFrame(socket);
      expect(close.fin, isTrue);
      expect(close.opcode, equals(0x8));
      expect(close.payload, isEmpty);

      await _waitForCondition(
        () =>
            events.any((event) => event['type'] == 'worker_connection_removed'),
        timeout: const Duration(seconds: 5),
        reason: 'websocket close did not remove worker connection: $events',
      );
    }, skip: skipReason);
  });
}

Future<void> _waitForCondition(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 10),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? 'Condition not met', timeout);
    }
    await Future<void>.delayed(pollInterval);
  }
}

RouterConfig _buildWebSocketConfig() => RouterConfig(
  endpoints: [
    Endpoint(
      host: '127.0.0.1',
      port: 0,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 18,
      webSocketPath: '/ws',
    ),
  ],
);

RouterSettings _buildWebSocketSettings() {
  final realmBuilder = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'subscribe',
            'unsubscribe',
            'publish',
            'call',
          ]),
      ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('internal')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'subscribe',
            'unsubscribe',
            'publish',
            'call',
          ]),
      ),
    );

  final listener = ListenerSettingsBuilder('websocket', '127.0.0.1:0')
    ..addAuthMethod('anonymous')
    ..addProtocol(ListenerProtocol.rawsocket)
    ..setPath('/ws')
    ..addProtocol(ListenerProtocol.websocket)
    ..setRawSocketOptions(const RawSocketListenerSettings(maxFrameExponent: 18))
    ..setWebSocketOptions(
      const WebSocketListenerSettings(
        subprotocols: ['wamp.2.msgpack', 'wamp.2.json', 'wamp.2.cbor'],
      ),
    );

  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(realmBuilder)
    ..addListenerFromBuilder(listener)
    ..addAuthenticator(
      'anonymous',
      const AuthenticatorDefinition(type: 'anonymous'),
    )
    ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1));
  return builder.build();
}

Uint8List _asBytes(Object? value) {
  if (value is Uint8List) {
    return value;
  }
  if (value is ByteBuffer) {
    return value.asUint8List();
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  if (value is List) {
    return Uint8List.fromList(value.cast<int>());
  }
  if (value is String) {
    if (value.startsWith('\u0000')) {
      return Uint8List.fromList(base64.decode(value.substring(1)));
    }
    if (value.startsWith(r'\u0000')) {
      return Uint8List.fromList(base64.decode(value.substring(6)));
    }
    return Uint8List.fromList(utf8.encode(value));
  }
  throw ArgumentError.value(value, 'value', 'Unsupported payload type');
}

final Map<Socket, StreamQueue<List<int>>> _socketQueues = {};
final Map<Socket, List<int>> _socketLeftovers = {};
final _random = math.Random(7);

Future<String> _performWebSocketHandshake(
  Socket socket, {
  required String path,
  required String host,
  required List<String> protocols,
}) async {
  final keyBytes = List<int>.generate(16, (_) => _random.nextInt(256));
  final key = base64.encode(keyBytes);
  final lines = <String>[
    'GET $path HTTP/1.1',
    'Host: $host',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: $key',
    'Sec-WebSocket-Version: 13',
    'Sec-WebSocket-Protocol: ${protocols.join(',')}',
    '',
  ];
  final request = '${lines.join('\r\n')}\r\n';
  socket.add(utf8.encode(request));
  await socket.flush();
  return _readHttpResponse(socket);
}

Future<String> _readHttpResponse(Socket socket) async {
  final queue = _socketQueues.putIfAbsent(
    socket,
    () => StreamQueue(socket.asBroadcastStream()),
  );
  final leftovers = _socketLeftovers.putIfAbsent(socket, () => <int>[]);
  final buffer = <int>[];
  const terminator = [13, 10, 13, 10]; // \r\n\r\n

  while (true) {
    if (leftovers.isNotEmpty) {
      buffer.addAll(leftovers);
      leftovers.clear();
    } else {
      if (!await queue.hasNext) {
        break;
      }
      buffer.addAll(await queue.next);
    }
    final end = _indexOfSublist(buffer, terminator);
    if (end != -1) {
      final headerLength = end + terminator.length;
      final remaining = buffer.sublist(headerLength);
      leftovers
        ..clear()
        ..addAll(remaining);
      final headerBytes = buffer.sublist(0, headerLength);
      return utf8.decode(headerBytes);
    }
  }
  throw StateError('Handshake response incomplete');
}

int _indexOfSublist(List<int> data, List<int> pattern) {
  if (pattern.isEmpty) {
    return 0;
  }
  for (var i = 0; i <= data.length - pattern.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return i;
    }
  }
  return -1;
}

Future<void> _sendFragmentedMessage(
  Socket socket,
  List<int> payload, {
  required int chunkSize,
}) async {
  var offset = 0;
  var first = true;
  while (offset < payload.length) {
    final end = math.min(offset + chunkSize, payload.length);
    final slice = payload.sublist(offset, end);
    final fin = end >= payload.length;
    final opcode = first ? 0x1 : 0x0;
    await _sendWebSocketFrame(socket, opcode: opcode, fin: fin, payload: slice);
    offset = end;
    first = false;
  }
}

Future<void> _sendWebSocketFrame(
  Socket socket, {
  required int opcode,
  required bool fin,
  required List<int> payload,
}) async {
  final header = <int>[];
  header.add((fin ? 0x80 : 0x00) | (opcode & 0x0F));
  final maskKey = List<int>.generate(4, (_) => _random.nextInt(256));
  if (payload.length < 126) {
    header.add(0x80 | payload.length);
  } else if (payload.length <= 0xFFFF) {
    header.add(0x80 | 126);
    header.add((payload.length >> 8) & 0xFF);
    header.add(payload.length & 0xFF);
  } else {
    header.add(0x80 | 127);
    final view = ByteData(8)..setUint64(0, payload.length);
    header.addAll(view.buffer.asUint8List());
  }
  header.addAll(maskKey);
  final maskedPayload = List<int>.generate(
    payload.length,
    (index) => payload[index] ^ maskKey[index % 4],
  );
  socket
    ..add(header)
    ..add(maskedPayload);
  await socket.flush();
}

Future<List<int>> _readTextMessage(Socket socket) async {
  final buffer = BytesBuilder(copy: false);
  var fin = false;
  while (!fin) {
    final frame = await _readFrame(socket);
    buffer.add(frame.payload);
    fin = frame.fin;
  }
  return buffer.takeBytes();
}

Future<_WebSocketFrame> _readFrame(Socket socket) async {
  final header = await _readExact(socket, 2);
  final fin = (header[0] & 0x80) != 0;
  final opcode = header[0] & 0x0F;
  final masked = (header[1] & 0x80) != 0;
  var len = (header[1] & 0x7F);
  if (len == 126) {
    final extended = await _readExact(socket, 2);
    len = (extended[0] << 8) | extended[1];
  } else if (len == 127) {
    final extended = await _readExact(socket, 8);
    len = 0;
    for (final byte in extended) {
      len = (len << 8) | byte;
    }
  }
  List<int> mask = const [];
  if (masked) {
    mask = await _readExact(socket, 4);
  }
  final payload = len == 0 ? <int>[] : await _readExact(socket, len);
  if (masked && payload.isNotEmpty) {
    for (var i = 0; i < payload.length; i++) {
      payload[i] = payload[i] ^ mask[i % 4];
    }
  }
  return _WebSocketFrame(fin: fin, opcode: opcode, payload: payload);
}

Future<List<int>> _readExact(Socket socket, int length) async {
  final queue = _socketQueues.putIfAbsent(
    socket,
    () => StreamQueue(socket.asBroadcastStream()),
  );
  final leftovers = _socketLeftovers.putIfAbsent(socket, () => <int>[]);
  final buffer = <int>[];

  void drainLeftovers() {
    if (leftovers.isEmpty || buffer.length >= length) {
      return;
    }
    final remaining = length - buffer.length;
    if (leftovers.length <= remaining) {
      buffer.addAll(leftovers);
      leftovers.clear();
    } else {
      buffer.addAll(leftovers.sublist(0, remaining));
      leftovers.removeRange(0, remaining);
    }
  }

  drainLeftovers();

  while (buffer.length < length) {
    if (!await queue.hasNext) {
      break;
    }
    final chunk = await queue.next;
    final remaining = length - buffer.length;
    if (chunk.length <= remaining) {
      buffer.addAll(chunk);
    } else {
      buffer.addAll(chunk.sublist(0, remaining));
      leftovers
        ..clear()
        ..addAll(chunk.sublist(remaining));
    }
  }

  return buffer;
}

class _WebSocketFrame {
  _WebSocketFrame({
    required this.fin,
    required this.opcode,
    required this.payload,
  });

  final bool fin;
  final int opcode;
  final List<int> payload;
}
