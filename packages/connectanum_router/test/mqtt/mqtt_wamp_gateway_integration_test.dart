@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart' as wamp_client;
import 'package:connectanum_client/mqtt.dart';
import 'package:connectanum_client/src/transport/socket/socket_transport.dart'
    as socket;
import 'package:connectanum_client/src/transport/socket/socket_helper.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:connectanum_core/mqtt.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart' as cbor;
import 'package:connectanum_core/src/serializer/json/serializer.dart' as json;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack;
import 'package:connectanum_router/connectanum_router.dart' hide Error;
import 'package:connectanum_router/src/router/router_instance.dart'
    as worker_api;
import 'package:test/test.dart';

import '../support/native_lib.dart';

const _realm = 'gateway.test';
final _deniedUri = MqttTopicUriMapper.toWampUri('forbidden');

socket.SocketTransport _publicationTransport(int port, String codec) =>
    switch (codec) {
      'flatbuffers' => socket.SocketTransport.withFlatBuffersSerializer(
        '127.0.0.1',
        port,
      ),
      'json' => socket.SocketTransport(
        '127.0.0.1',
        port,
        json.Serializer(),
        SocketHelper.serializationJson,
      ),
      'msgpack' => socket.SocketTransport(
        '127.0.0.1',
        port,
        msgpack.Serializer(),
        SocketHelper.serializationMsgpack,
      ),
      _ => socket.SocketTransport(
        '127.0.0.1',
        port,
        cbor.Serializer(),
        SocketHelper.serializationCbor,
      ),
    };

// Observe actual worker commands without retaining application payloads.
void _observePublicationWorker(Map<String, Object?> init) {
  _observePublicationCommands(init, legacy: false, injectFailures: false);
}

void _observeLegacyPublicationWorker(Map<String, Object?> init) {
  _observePublicationCommands(init, legacy: true, injectFailures: false);
}

void _observeFailingPublicationWorker(Map<String, Object?> init) {
  _observePublicationCommands(init, legacy: false, injectFailures: true);
}

void _observeBatchOnlyPublicationWorker(Map<String, Object?> init) {
  _observePublicationCommands(
    init,
    legacy: false,
    injectFailures: false,
    binarySupport: false,
  );
}

worker_api.RouterWorkerEntryPoint _mixedCapabilityPublicationWorker(
  SendPort allocator,
) => (init) {
  final reply = ReceivePort();
  allocator.send(reply.sendPort);
  reply.first.then((supported) {
    reply.close();
    _observePublicationCommands(
      init,
      legacy: false,
      injectFailures: false,
      binarySupport: supported as bool,
    );
  });
};

void _observePublicationCommands(
  Map<String, Object?> init, {
  required bool legacy,
  required bool injectFailures,
  bool binarySupport = true,
}) {
  final boss = init['bossPort'] as SendPort;
  final events = ReceivePort();
  ReceivePort? commands;
  events.listen((raw) {
    final event = Map<Object?, Object?>.from(raw as Map);
    if (event['type'] == 1 && event['commandPort'] is SendPort) {
      final target = event['commandPort'] as SendPort;
      commands = ReceivePort()
        ..listen((rawCommand) {
          final command = rawCommand as List;
          final List? entries = switch (command[0]) {
            5 => [
              [command[1], command[2]],
            ],
            7 => command[1] as List,
            8 => command[1] as List,
            _ => null,
          };
          Uint8List? transferredBytes;
          if (command[0] == 8) {
            transferredBytes = (command[2] as TransferableTypedData)
                .materialize()
                .asUint8List();
            for (final entry in entries!) {
              (entry[1] as wamp.Event).arguments = [transferredBytes];
            }
          }
          final publications = [
            for (final entry in entries ?? const [])
              if (entry[1] case final wamp.Event event
                  when event.wireArguments?.length == 1 &&
                      event.wireArguments!.single is Uint8List &&
                      (event.wireArguments!.single as Uint8List).isNotEmpty)
                event,
          ];
          if (publications.isNotEmpty) {
            final bytes = publications.first.wireArguments!.single;
            boss.send({
              'type': 'worker_debug',
              'stage': 'publication_transfer',
              'recipients': publications.length,
              'binary_transfer': command[0] == 8,
              'shared_payload': publications.every(
                (e) => identical(e.wireArguments!.single, bytes),
              ),
            });
          }
          if (command[0] == 8) {
            for (final entry in entries!) {
              (entry[1] as wamp.Event).arguments = null;
            }
          }
          if (injectFailures && (command[0] == 7 || command[0] == 8)) {
            final injected = [
              [0x7fffffff, publications.first],
              [
                entries!.first[0],
                wamp.Event(
                  1,
                  1,
                  wamp.EventDetails()..custom['unsupported'] = Object(),
                ),
              ],
              ...entries,
            ];
            target.send(
              command[0] == 8
                  ? [
                      8,
                      injected,
                      TransferableTypedData.fromList([transferredBytes!]),
                    ]
                  : [7, injected],
            );
          } else if (command[0] == 8) {
            target.send([
              8,
              entries,
              TransferableTypedData.fromList([transferredBytes!]),
            ]);
          } else {
            target.send(rawCommand);
          }
        });
      event['commandPort'] = commands!.sendPort;
      event['supportsMessageBatches'] = !legacy;
      if (binarySupport) {
        event['supportsTransferredBinaryEvents'] = !legacy;
      } else {
        event.remove('supportsTransferredBinaryEvents');
      }
    }
    boss.send(event);
    if (event['type'] == 4) {
      commands?.close();
      events.close();
    }
  });
  worker_api.defaultRouterWorkerEntryPoint({
    ...init,
    'bossPort': events.sendPort,
  });
}

void main() {
  setUp(AuthorizationProviderRegistry.clear);
  tearDown(AuthorizationProviderRegistry.clear);

  Future<
    ({
      RouterBinding binding,
      MqttWampGateway gateway,
      wamp_client.Session session,
      MqttQos0Client mqtt,
    })
  >
  start({
    int maxPendingBytes = 8 * 1024 * 1024,
    int maxPendingOperations = 256,
    Duration operationTimeout = const Duration(seconds: 5),
    RouterSettings Function(RouterSettings)? transformSettings,
    bool activateListeners = true,
    Future<MqttWampGateway> Function(RouterBinding)? enable,
    void Function(RouterBinding, Object)? onEvent,
    worker_api.RouterWorkerEntryPoint? workerEntryPoint,
    String wampSerializer = 'cbor',
  }) async {
    final runtime = NativeTransportRuntime(
      libraryPath: resolveOrBuildNativeLib()!,
    )..start();
    addTearDown(() {
      runtime.shutdown();
      runtime.dispose();
    });
    final settings = RouterSettingsBuilder()
      ..addRealmFromBuilder(
        RealmSettingsBuilder(_realm)
          ..addAuthMethod('anonymous')
          ..addRole(
            RoleSettings(
              name: 'anonymous',
              permissions: [
                const PermissionSettings(
                  uri: MqttTopicUriMapper.prefix,
                  matchPolicy: PermissionMatchPolicy.prefix,
                  allow: ['publish', 'subscribe', 'unsubscribe'],
                ),
                const PermissionSettings(
                  uri: MqttWampGateway.publishProcedure,
                  allow: ['call'],
                ),
                PermissionSettings(
                  uri: _deniedUri,
                  deny: ['publish', 'subscribe'],
                ),
              ],
            ),
          )
          ..addRole(
            RoleSettings(
              name: 'mqtt',
              permissions: [
                const PermissionSettings(
                  uri: MqttTopicUriMapper.prefix,
                  matchPolicy: PermissionMatchPolicy.prefix,
                  allow: ['publish', 'subscribe'],
                ),
                PermissionSettings(
                  uri: _deniedUri,
                  deny: ['publish', 'subscribe'],
                ),
              ],
            ),
          )
          ..addRole(
            const RoleSettings(
              name: 'mqtt-gateway',
              permissions: [
                PermissionSettings(
                  uri: '',
                  matchPolicy: PermissionMatchPolicy.prefix,
                  allow: ['register', 'unregister', 'publish'],
                ),
              ],
            ),
          ),
      )
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('mqtt', '127.0.0.1:0')
          ..addAuthMethod('anonymous')
          ..addProtocol(ListenerProtocol.mqtt)
          ..addProtocol(ListenerProtocol.rawsocket)
          ..addProtocol(ListenerProtocol.websocket),
      )
      ..addAuthenticator(
        'anonymous',
        const AuthenticatorDefinition(type: 'anonymous'),
      );
    RouterBinding? active;
    final binding =
        Router(
          RouterConfig(
            endpoints: [
              Endpoint(
                host: '127.0.0.1',
                port: 0,
                tlsMode: TlsMode.disabled,
                maxRawSocketSizeExponent: 24,
              ),
            ],
          ),
          settings:
              transformSettings?.call(settings.build()) ?? settings.build(),
        ).start(
          runtime,
          workerEntryPoint:
              workerEntryPoint ?? worker_api.defaultRouterWorkerEntryPoint,
          activateListeners: activateListeners,
          onEvent: (e) {
            final owner = active;
            if (owner != null) onEvent?.call(owner, e);
          },
        );
    active = binding;
    addTearDown(binding.dispose);
    final gateway =
        await (enable?.call(binding) ??
            binding.enableMqttGateway(
              realmUri: _realm,
              mqttAuthRole: 'mqtt',
              maxPendingBytes: maxPendingBytes,
              maxPendingOperations: maxPendingOperations,
              operationTimeout: operationTimeout,
            ));
    final port = binding.listeners.single.port;
    final session = await wamp_client.Client(
      realm: _realm,
      transport: _publicationTransport(port, wampSerializer),
    ).connect().first.timeout(const Duration(seconds: 5));
    addTearDown(session.close);
    final mqtt = await MqttQos0Client.connect(
      '127.0.0.1',
      port,
      clientId: 'untrusted-service-role',
    );
    addTearDown(mqtt.close);
    return (binding: binding, gateway: gateway, session: session, mqtt: mqtt);
  }

  for (final (workers, size, mode, codec) in [
    for (final workers in [1, 2])
      for (final size in [128, 16383, 16384, 65536])
        for (final mode in ['batch', 'legacy', 'batch-only'])
          (workers, size, mode, 'cbor'),
    (1, 65536, 'failures', 'cbor'),
    (1, 65536, 'mixed', 'cbor'),
    (2, 65536, 'single', 'cbor'),
    (2, 65536, 'single-batch-only', 'cbor'),
    (2, 65536, 'mixed-workers', 'cbor'),
    for (final codec in ['json', 'msgpack', 'flatbuffers', 'mixed'])
      (1, 65536, 'batch', codec),
  ]) {
    test(
      'MQTT fanout worker transfers: workers=$workers bytes=$size mode=$mode codec=$codec',
      () async {
        final observations = <Map>[];
        final errors = <Map>[];
        final nativeRecipients = mode.startsWith('single') ? 2 : 4;
        ReceivePort? capabilities;
        if (mode == 'mixed-workers') {
          capabilities = ReceivePort();
          var ordinal = 0;
          capabilities.listen((reply) {
            (reply as SendPort).send(ordinal++ == 0);
          });
          addTearDown(capabilities.close);
        }
        final fixture = await start(
          wampSerializer: codec == 'mixed' ? 'cbor' : codec,
          transformSettings: (s) =>
              s.copyWith(workerPool: WorkerPoolSettings(minWorkers: workers)),
          workerEntryPoint: switch (mode) {
            'legacy' => _observeLegacyPublicationWorker,
            'failures' => _observeFailingPublicationWorker,
            'batch-only' ||
            'single-batch-only' => _observeBatchOnlyPublicationWorker,
            'mixed-workers' => _mixedCapabilityPublicationWorker(
              capabilities!.sendPort,
            ),
            _ => _observePublicationWorker,
          },
          onEvent: (_, e) {
            if (e is Map && e['type'] == 'worker_error') errors.add(e);
            final observed = e is Map && e['payload'] is Map ? e['payload'] : e;
            if (observed is Map &&
                observed['stage'] == 'publication_transfer') {
              observations.add(observed);
            }
          },
        );
        const topic = 'sensors/fanout';
        final sessions = [fixture.session];
        for (var i = 1; i < nativeRecipients; i++) {
          final session = await wamp_client.Client(
            realm: _realm,
            transport: _publicationTransport(
              fixture.binding.listeners.single.port,
              codec == 'mixed'
                  ? ['cbor', 'json', 'msgpack', 'flatbuffers'][i]
                  : codec,
            ),
          ).connect().first.timeout(const Duration(seconds: 5));
          addTearDown(session.close);
          sessions.add(session);
        }
        final received = <Future<wamp.Event>>[];
        final subscriptions = <int>[];
        for (final session in sessions) {
          final subscribed = await session.subscribe(
            MqttTopicUriMapper.toWampUri(topic),
          );
          final event = Completer<wamp.Event>();
          subscriptions.add(subscribed.subscriptionId);
          subscribed.onEvent(event.complete);
          received.add(event.future.timeout(const Duration(seconds: 5)));
        }
        if (mode == 'mixed') {
          final internal = await fixture.binding.createInternalSession(
            realmUri: _realm,
            authId: 'mixed-internal-subscriber',
            authRole: 'anonymous',
            indexByRealm: false,
          );
          addTearDown(internal.close);
          final subscribed = await internal.subscribe(
            MqttTopicUriMapper.toWampUri(topic),
          );
          final event = Completer<wamp.Event>();
          subscriptions.add(subscribed.subscriptionId);
          subscribed.onEvent(event.complete);
          received.add(event.future.timeout(const Duration(seconds: 5)));
        }
        final storage = Uint8List(2 * 1024 * 1024);
        final bytes = Uint8List.sublistView(storage, 32, 32 + size);
        bytes.setAll(0, List.generate(size, (i) => i % 251));
        await fixture.mqtt.publish(topic, bytes);
        storage.fillRange(0, storage.length, 0);
        final events = await Future.wait(received);
        for (var index = 0; index < events.length; index++) {
          final event = events[index];
          expect(event.subscriptionId, subscriptions[index]);
          expect(event.arguments!.single, List.generate(size, (i) => i % 251));
          expect(event.details.custom['mqtt_topic'], topic);
        }
        expect(
          events.map((event) => event.publicationId).toSet(),
          hasLength(1),
        );
        expect(
          observations,
          hasLength(
            size >= 16384 && mode != 'legacy' ? workers : nativeRecipients,
          ),
        );
        expect(
          observations.fold<int>(0, (sum, e) => sum + (e['recipients'] as int)),
          nativeRecipients,
        );
        if (mode == 'mixed-workers') {
          expect(
            observations.map((e) => e['binary_transfer']),
            unorderedEquals([true, false]),
          );
        } else {
          final binaryExpected =
              size >= 16384 &&
              mode != 'legacy' &&
              mode != 'batch-only' &&
              mode != 'single-batch-only';
          expect(
            observations.every((e) => e['binary_transfer'] == binaryExpected),
            isTrue,
          );
        }
        expect(errors, hasLength(mode == 'failures' ? 1 : 0));
        expect(observations.every((e) => e['shared_payload'] == true), isTrue);
      },
    );
  }

  test(
    'native MQTT to WAMP preserves application bytes and topic identity',
    () async {
      final h = await start();
      final events = <wamp.Event>[];
      final subscription = await h.session.subscribe(
        MqttTopicUriMapper.toWampUri('sensor/é'),
      );
      final got = Completer<void>();
      subscription.onEvent((event) {
        events.add(event);
        if (!got.isCompleted) got.complete();
      });
      final payload = Uint8List.fromList([0, 255, 0x10, 0xff, 3]);
      await h.mqtt.publish('sensor/é', payload);
      await got.future.timeout(const Duration(seconds: 3));
      expect(events.single.arguments, [payload]);
      expect(events.single.details.custom['mqtt_topic'], 'sensor/é');
      expect(events.single.details.custom['mqtt_origin'], 'mqtt');
      expect(h.gateway.metrics['mqtt_publications'], 1);
    },
  );

  test('explicit WAMP API sends MQTT once and emits one WAMP event', () async {
    final h = await start();
    await h.mqtt.subscribe('sensors/#');
    final mqttEvents = <MqttPublish>[];
    final done = Completer<void>();
    final listener = h.mqtt.messages.listen((e) {
      mqttEvents.add(e);
      if (!done.isCompleted) done.complete();
    });
    addTearDown(listener.cancel);
    final events = <wamp.Event>[];
    final subscription = await h.session.subscribe(
      MqttTopicUriMapper.toWampUri('sensors/a'),
    );
    subscription.onEvent(events.add);
    final payload = Uint8List.fromList([0, 255, 0x10, 0]);
    final result = await h.session
        .call(
          MqttWampGateway.publishProcedure,
          arguments: ['sensors/a', payload],
        )
        .first;
    expect(result.arguments!.single, isA<int>());
    await done.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(mqttEvents, hasLength(1));
    expect(mqttEvents.single.payload, payload);
    expect(events, hasLength(1));
    expect(events.single.arguments, [payload]);
    expect(events.single.details.custom['mqtt_origin'], 'wamp');
    expect(h.gateway.metrics['wamp_publications'], 1);
  });

  test(
    'WAMP arguments and CALL metadata cannot impersonate a privileged caller',
    () async {
      final h = await start();
      await h.mqtt.subscribe('#');
      final events = <MqttPublish>[];
      final listener = h.mqtt.messages.listen(events.add);
      addTearDown(listener.cancel);
      await expectLater(
        h.session
            .call(
              MqttWampGateway.publishProcedure,
              arguments: [
                'forbidden',
                Uint8List.fromList([1]),
              ],
              options: wamp.CallOptions(
                custom: {
                  'caller_authrole': 'mqtt-gateway',
                  'caller_authid': 'administrator',
                  'caller': 1,
                },
              ),
            )
            .first,
        throwsA(isA<wamp.Error>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, isEmpty);
      expect(h.gateway.metrics['denied'], greaterThan(0));
    },
  );

  test(
    'ordinary mapped WAMP publication does not execute MQTT bytes',
    () async {
      final h = await start();
      await h.mqtt.subscribe('#');
      final events = <MqttPublish>[];
      final listener = h.mqtt.messages.listen(events.add);
      addTearDown(listener.cancel);
      await h.session.publish(
        MqttTopicUriMapper.toWampUri('ordinary'),
        arguments: [
          Uint8List.fromList([0x10, 0, 0]),
        ],
        options: wamp.PublishOptions(acknowledge: true),
      );
      await h.session.publishLazyPayload(
        MqttTopicUriMapper.toWampUri('opaque'),
        payload: wamp.LazyMessagePayload.materialized(
          transparentBinaryPayload: Uint8List.fromList([0x10, 0, 0xff]),
          pptDecoded: false,
        ),
        options: wamp.PublishOptions(
          acknowledge: true,
          pptScheme: 'mqtt',
          pptSerializer: 'unregistered.mqtt',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(events, isEmpty);
      expect(h.gateway.metrics['wamp_publications'], 0);
    },
  );

  test('explicit API rejects unknown MQTT PPT without decoding it', () async {
    final h = await start();
    await expectLater(
      h.session
          .callLazyPayload(
            MqttWampGateway.publishProcedure,
            payload: wamp.LazyMessagePayload.materialized(
              transparentBinaryPayload: Uint8List.fromList([0x10, 0, 0xff]),
              pptDecoded: false,
            ),
            options: wamp.CallOptions(
              pptScheme: 'mqtt',
              pptSerializer: 'unregistered.mqtt',
            ),
          )
          .first,
      throwsA(
        isA<wamp.Error>().having(
          (e) => e.error,
          'reason',
          'wamp.error.invalid_argument',
        ),
      ),
    );
    expect(h.gateway.metrics['errors'], 1);
    expect(h.gateway.metrics['wamp_publications'], 0);
  });

  test(
    'gateway close is idempotent, cancels peers and permits a fresh gateway',
    () async {
      final h = await start();
      await h.gateway.close();
      await h.gateway.close();
      expect(h.gateway.isClosed, isTrue);
      expect(h.gateway.metrics['topic_cache_bytes'], 0);
      final replacement = await h.binding.enableMqttGateway(
        realmUri: _realm,
        mqttAuthRole: 'mqtt',
      );
      expect(replacement.isClosed, isFalse);
      await replacement.close();
    },
  );

  test(
    'invalid principal, limits and duplicate activation fail closed',
    () async {
      final h = await start();
      await expectLater(
        h.binding.enableMqttGateway(realmUri: _realm, mqttAuthRole: 'mqtt'),
        throwsStateError,
      );
      await h.gateway.close();
      for (final options in [
        {'realmUri': 'missing', 'mqttAuthRole': 'mqtt'},
        {'realmUri': _realm, 'mqttAuthRole': 'missing'},
        {
          'realmUri': _realm,
          'mqttAuthRole': 'mqtt',
          'serviceAuthRole': 'missing',
        },
        {'realmUri': _realm, 'mqttAuthRole': 'mqtt', 'mqttAuthId': ''},
        {'realmUri': _realm, 'mqttAuthRole': 'mqtt', 'maxPendingBytes': 0},
        {'realmUri': _realm, 'mqttAuthRole': 'mqtt', 'maxPendingOperations': 0},
        {
          'realmUri': _realm,
          'mqttAuthRole': 'mqtt',
          'operationTimeout': Duration.zero,
        },
      ]) {
        await expectLater(
          Function.apply(h.binding.enableMqttGateway, [], {
            for (final e in options.entries) Symbol(e.key): e.value,
          }),
          throwsArgumentError,
        );
      }
      await h.binding.dispose();
      await expectLater(
        h.binding.enableMqttGateway(realmUri: _realm, mqttAuthRole: 'mqtt'),
        throwsStateError,
      );
    },
  );

  test(
    'explicit API rejects malformed data and packet-size overflow',
    () async {
      final h = await start();
      for (final args in <List<dynamic>?>[
        null,
        [],
        ['topic'],
        [123, Uint8List(0)],
        [
          'topic',
          [1, 2],
        ],
        ['topic', Uint8List(0), 'extra'],
        ['bad/+', Uint8List(0)],
        ['', Uint8List(0)],
        ['topic', Uint8List(1024 * 1024)],
      ]) {
        await expectLater(
          h.session
              .call(MqttWampGateway.publishProcedure, arguments: args)
              .first,
          throwsA(
            isA<wamp.Error>().having(
              (e) => e.error,
              'reason',
              'wamp.error.invalid_argument',
            ),
          ),
        );
      }
      await expectLater(
        h.session
            .call(
              MqttWampGateway.publishProcedure,
              arguments: ['topic', Uint8List(0)],
              argumentsKeywords: {'injected': true},
            )
            .first,
        throwsA(isA<wamp.Error>()),
      );
      expect(h.gateway.metrics['wamp_publications'], 0);
      expect(h.gateway.metrics['pending_operations'], 0);
    },
  );

  test(
    'capacity refusal does not retain a publication or close the gateway',
    () async {
      final h = await start(maxPendingBytes: 1);
      await expectLater(
        h.session
            .call(
              MqttWampGateway.publishProcedure,
              arguments: ['topic', Uint8List(2)],
            )
            .first,
        throwsA(isA<wamp.Error>()),
      );
      expect(h.gateway.metrics['pending_bytes'], 0);
      expect(h.gateway.metrics['pending_operations'], 0);
      expect(h.gateway.isClosed, isFalse);
      await h.session
          .call(
            MqttWampGateway.publishProcedure,
            arguments: ['topic', Uint8List(1)],
          )
          .first;
      expect(h.gateway.metrics['wamp_publications'], 1);
    },
  );

  test('lazy listeners activate with an explicitly assigned realm', () async {
    final h = await start(
      activateListeners: false,
      transformSettings: (s) => s.copyWith(
        listeners: [
          ListenerSettings(
            endpoint: s.listeners.single.endpoint,
            authmethods: ['anonymous'],
            protocols: s.listeners.single.protocols,
            options: {'realm': ' gateway.test '},
          ),
        ],
      ),
    );
    expect(h.gateway.isClosed, isFalse);
  });

  test('gateway requires a native runtime that owns router isolates', () async {
    final binding = RouterBinding(
      runtime: _NoHandleRuntime(),
      endpoints: [],
      configJson: Uint8List(0),
      settings: const RouterSettings(
        realms: [
          RealmSettings(
            name: _realm,
            auth: RealmAuthSettings(methods: ['anonymous']),
            limits: RealmLimitSettings(),
            roles: [
              RoleSettings(
                name: 'mqtt',
                permissions: [
                  PermissionSettings(uri: '', allow: ['publish']),
                ],
              ),
              RoleSettings(name: 'mqtt-gateway', permissions: []),
            ],
          ),
        ],
        listeners: [],
      ),
    );
    addTearDown(binding.dispose);
    await expectLater(
      binding.enableMqttGateway(realmUri: _realm, mqttAuthRole: 'mqtt'),
      throwsStateError,
    );
  });

  test(
    'single-isolate MQTT listeners preserve their configured realm',
    () async {
      final runtime = _FallbackMqttRuntime();
      final settings = RouterSettings(
        realms: const [
          RealmSettings(
            name: _realm,
            auth: RealmAuthSettings(methods: ['anonymous']),
            roles: [],
            limits: RealmLimitSettings(),
          ),
        ],
        listeners: const [
          ListenerSettings(
            endpoint: '127.0.0.1:0',
            protocols: [ListenerProtocol.mqtt],
            options: {'realm': _realm},
          ),
        ],
      );
      final binding = Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.disabled,
              maxRawSocketSizeExponent: 24,
            ),
          ],
        ),
        settings: settings,
      ).start(runtime);
      addTearDown(binding.dispose);
      expect(binding.pollNativeMessages(), isEmpty);
      final frame = MqttFrameDecoder().add(runtime.sent.single).single;
      expect(
        MqttPacketCodec.decodeConnack(frame, MqttVersion.v5).reasonCode,
        0,
      );
    },
  );

  test('disposal cancels an accepted gateway start without deadlock', () async {
    await expectLater(
      start(
        enable: (binding) async {
          final opening = binding.enableMqttGateway(
            realmUri: _realm,
            mqttAuthRole: 'mqtt',
          );
          final rejected = expectLater(opening, throwsStateError);
          await binding.dispose();
          await rejected;
          return await opening;
        },
      ).timeout(const Duration(seconds: 3)),
      throwsStateError,
    );
  });

  for (final version in [1, 2]) {
    test(
      'disposal during owned gateway startup stage $version releases state',
      () async {
        Future<void>? cleanup;
        await expectLater(
          start(
            onEvent: (binding, event) {
              if (event is Map &&
                  event['type'] == 'state_changed' &&
                  event['version'] == version) {
                cleanup ??= binding.dispose();
              }
            },
          ).timeout(const Duration(seconds: 3)),
          throwsStateError,
        );
        await cleanup;
      },
    );
  }

  test(
    'missing MQTT listener is rejected',
    () async {
      await expectLater(
        start(
          transformSettings: (s) => s.copyWith(
            listeners: [
              ListenerSettings(
                endpoint: s.listeners.single.endpoint,
                authmethods: ['anonymous'],
                protocols: [ListenerProtocol.rawsocket],
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'ambiguous MQTT realm is rejected',
    () async {
      await expectLater(
        start(
          transformSettings: (s) => s.copyWith(
            realms: [
              ...s.realms,
              RealmSettings(
                name: 'other',
                auth: s.realms.single.auth,
                roles: s.realms.single.roles,
                limits: s.realms.single.limits,
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'implicit gateway authorization policy is rejected',
    () async {
      await expectLater(
        start(
          transformSettings: (s) => s.copyWith(
            realms: [
              RealmSettings(
                name: _realm,
                auth: s.realms.single.auth,
                limits: s.realms.single.limits,
                roles: [
                  for (final r in s.realms.single.roles)
                    RoleSettings(name: r.name, permissions: []),
                ],
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('topic cache is bounded and closes without retained names', () async {
    final h = await start();
    for (var i = 0; i < 258; i++) {
      await h.session
          .call(
            MqttWampGateway.publishProcedure,
            arguments: ['topic/$i', Uint8List(0)],
          )
          .first;
    }
    expect(h.gateway.metrics['topic_cache_entries'], 256);
    expect(
      h.gateway.metrics['topic_cache_bytes'],
      lessThanOrEqualTo(1024 * 1024),
    );
    await h.gateway.close();
    expect(h.gateway.metrics['topic_cache_entries'], 0);
    expect(h.gateway.metrics['pending_policy_futures'], 0);
  });

  test(
    'MQTT uses the configured principal and denies before either delivery',
    () async {
      final requests = <AuthorizationRequest>[];
      AuthorizationProviderRegistry.registerProvider(
        _Policy((request) {
          if (request.options['mqtt_direction'] != 'mqtt_to_wamp') return null;
          requests.add(request);
          return const AuthorizationDecision.deny();
        }),
      );
      final h = await start();
      final events = <wamp.Event>[];
      final subscription = await h.session.subscribe(
        MqttTopicUriMapper.toWampUri('denied'),
      );
      subscription.onEvent(events.add);
      final closed = Completer<void>();
      final mqttListener = h.mqtt.messages.listen(
        (_) => fail('denied MQTT delivery'),
        onError: (Object e) {},
        onDone: closed.complete,
      );
      addTearDown(mqttListener.cancel);
      await h.mqtt.subscribe('#');
      await h.mqtt.publish('denied', Uint8List(1));
      await closed.future.timeout(const Duration(seconds: 3));
      expect(events, isEmpty);
      final request = requests.single;
      expect(request.sessionId, 0);
      expect(request.connectionId, isNotNull);
      expect(request.authId, 'mqtt:anonymous');
      expect(request.authRole, 'mqtt');
      expect(request.authMethod, 'anonymous');
      expect(request.authProvider, 'mqtt-gateway');
      expect(request.protocol, ListenerProtocol.mqtt);
      expect(request.isInternal, isFalse);
      expect(request.options['mqtt_client_id'], 'untrusted-service-role');
      expect(h.gateway.metrics['mqtt_publications'], 0);
    },
  );

  test(
    'gateway close replies to an admitted RPC before closing its service',
    () async {
      final entered = Completer<void>();
      final decision = Completer<AuthorizationDecision?>();
      AuthorizationProviderRegistry.registerProvider(
        _Policy((request) {
          if (request.options['mqtt_direction'] != 'wamp_to_mqtt') return null;
          entered.complete();
          return decision.future;
        }),
      );
      addTearDown(() {
        if (!decision.isCompleted) decision.complete(null);
      });
      final h = await start(operationTimeout: const Duration(seconds: 10));
      final response = h.session
          .call(
            MqttWampGateway.publishProcedure,
            arguments: ['blocked-close', Uint8List(1)],
          )
          .first;
      await entered.future.timeout(const Duration(seconds: 2));
      final closing = h.gateway.close();
      await expectLater(
        response.timeout(const Duration(seconds: 2)),
        throwsA(isA<wamp.Error>()),
      );
      await closing.timeout(const Duration(seconds: 2));
      expect(h.gateway.metrics['pending_operations'], 0);
      expect(h.gateway.metrics['pending_bytes'], 0);
      expect(h.gateway.metrics['pending_policy_futures'], 1);
      expect(h.gateway.metrics['wamp_publications'], 0);
      decision.complete(const AuthorizationDecision.allow());
    },
  );

  test(
    'a timed-out policy closes admission and retains only bounded provider work',
    () async {
      final entered = Completer<void>();
      final decision = Completer<AuthorizationDecision?>();
      AuthorizationProviderRegistry.registerProvider(
        _Policy((request) {
          if (request.options['mqtt_direction'] != 'wamp_to_mqtt') return null;
          entered.complete();
          return decision.future;
        }),
      );
      addTearDown(() {
        if (!decision.isCompleted) decision.complete(null);
      });
      final h = await start(
        maxPendingOperations: 1,
        operationTimeout: const Duration(milliseconds: 100),
      );
      final result = expectLater(
        h.session
            .call(
              MqttWampGateway.publishProcedure,
              arguments: ['blocked', Uint8List(1)],
            )
            .first,
        throwsA(
          isA<wamp.Error>().having(
            (error) => error.error,
            'error URI',
            wamp.Error.timeout,
          ),
        ),
      );
      await entered.future.timeout(const Duration(seconds: 2));
      expect(h.gateway.metrics['pending_policy_futures'], 1);
      await result;
      expect(h.gateway.isClosed, isTrue);
      expect(h.gateway.metrics['pending_bytes'], 0);
      expect(h.gateway.metrics['pending_policy_futures'], 1);
      await expectLater(
        h.binding.enableMqttGateway(
          realmUri: _realm,
          mqttAuthRole: 'mqtt',
          maxPendingOperations: 1,
        ),
        throwsStateError,
      );
      decision.complete(const AuthorizationDecision.allow());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(h.gateway.metrics['pending_policy_futures'], 0);
      expect(h.gateway.metrics['wamp_publications'], 0);
    },
  );

  test(
    'provider failure releases bytes without publishing and allows recovery',
    () async {
      var broken = true;
      AuthorizationProviderRegistry.registerProvider(
        _Policy((request) {
          if (broken && request.options['mqtt_direction'] == 'wamp_to_mqtt') {
            throw StateError('provider unavailable');
          }
          return null;
        }),
      );
      final h = await start();
      await expectLater(
        h.session
            .call(
              MqttWampGateway.publishProcedure,
              arguments: ['topic', Uint8List(1)],
            )
            .first,
        throwsA(isA<wamp.Error>()),
      );
      expect(h.gateway.metrics['pending_policy_futures'], 0);
      expect(h.gateway.metrics['pending_operations'], 0);
      expect(h.gateway.metrics['wamp_publications'], 0);
      broken = false;
      await h.session
          .call(
            MqttWampGateway.publishProcedure,
            arguments: ['topic', Uint8List(1)],
          )
          .first;
      expect(h.gateway.metrics['wamp_publications'], 1);
    },
  );

  test(
    'disconnected WAMP caller cannot publish after delayed authorization',
    () async {
      final entered = Completer<void>();
      final decision = Completer<AuthorizationDecision?>();
      AuthorizationProviderRegistry.registerProvider(
        _Policy((request) {
          if (request.options['mqtt_direction'] != 'wamp_to_mqtt') return null;
          entered.complete();
          return decision.future;
        }),
      );
      addTearDown(() {
        if (!decision.isCompleted) decision.complete(null);
      });
      final h = await start();
      final events = <MqttPublish>[];
      final listener = h.mqtt.messages.listen(events.add);
      addTearDown(listener.cancel);
      await h.mqtt.subscribe('#');
      final call = h.session
          .call(
            MqttWampGateway.publishProcedure,
            arguments: ['topic', Uint8List(1)],
          )
          .listen((_) => fail('closed caller result'), onError: (Object e) {});
      addTearDown(call.cancel);
      await entered.future.timeout(const Duration(seconds: 2));
      final initialSessions = (await h.binding.collectMetrics()).sessionCount;
      await h.session.close(timeout: Duration.zero);
      await h.session.onDisconnect.timeout(const Duration(seconds: 2));
      await (() async {
        while ((await h.binding.collectMetrics()).sessionCount >=
            initialSessions) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      })().timeout(const Duration(seconds: 2));
      decision.complete(const AuthorizationDecision.allow());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(events, isEmpty);
      expect(h.gateway.metrics['wamp_publications'], 0);
      expect(h.gateway.metrics['pending_operations'], 0);
    },
  );
}

final class _Policy implements AuthorizationProvider {
  _Policy(this.callback);
  final FutureOr<AuthorizationDecision?> Function(AuthorizationRequest)
  callback;
  @override
  FutureOr<AuthorizationDecision?> authorize(AuthorizationRequest request) =>
      callback(request);
}

final class _NoHandleRuntime implements NativeRuntime {
  @override
  dynamic noSuchMethod(Object invocation) => null;
}

final class _FallbackMqttRuntime extends _NoHandleRuntime
    implements NativeRuntimeWithMqtt {
  bool accepted = false;
  Uint8List? chunk = MqttPacketCodec.encodeConnect(
    MqttConnect(version: MqttVersion.v5, clientId: 'fallback'),
  );
  final sent = <Uint8List>[];
  @override
  int listen(String host, int port, {int backlog = 128}) => 1;
  @override
  int getLocalPort(int listenerId) => 1883;
  @override
  int getHttp3Port(int listenerId) => 0;
  @override
  int pollConnection(int listenerId) {
    if (accepted) return 0;
    accepted = true;
    return 1;
  }

  @override
  NativeConnectionProtocol connectionProtocol(int id) =>
      NativeConnectionProtocol.mqtt;
  @override
  int mqttVersion(int id) => 5;
  @override
  Uint8List? pollMqttChunk(int id) {
    final bytes = chunk;
    chunk = null;
    return bytes;
  }

  @override
  void sendMqttChunk(int id, Uint8List bytes) => sent.add(bytes);
  @override
  void setMqttWake(int id, void Function(int)? wake) {}
}
