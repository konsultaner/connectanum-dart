@TestOn('vm')
library;

import 'dart:async';

import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_client/mcp.dart' as mcp;
import 'package:connectanum_client/src/transport/socket/socket_helper.dart';
import 'package:connectanum_client/src/transport/socket/socket_transport.dart'
    as socket_transport;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

import 'support/native_lib.dart';

typedef _MetaResult = ({List<Object?> args, Map<String, Object?> details});
typedef _MetaCall =
    Future<_MetaResult> Function(String procedure, List<Object?> arguments);

void main() {
  setUpAll(
    () => AuthorizationProviderFactoryRegistry.registerFactory(
      const _MetaPolicyFactory(),
    ),
  );
  tearDownAll(
    () => AuthorizationProviderFactoryRegistry.unregisterFactory('meta-policy'),
  );
  final nativeLib = resolveOrBuildNativeLib();
  for (final dynamicPolicy in [false, true]) {
    for (final transport in [
      'websocket',
      'rawsocket',
      'mcp-json',
      'mcp-stream',
    ]) {
      test(
        '$transport Meta discovery enforces ${dynamicPolicy ? 'dynamic' : 'static'} action permissions',
        () async {
          final runtime = NativeTransportRuntime(libraryPath: nativeLib)
            ..start();
          addTearDown(() {
            runtime.shutdown();
            runtime.dispose();
          });
          final binding = Router(
            RouterConfig(
              endpoints: [
                Endpoint(
                  host: '127.0.0.1',
                  port: 0,
                  tlsMode: TlsMode.disabled,
                  maxRawSocketSizeExponent: 16,
                  webSocketPath: '/ws',
                ),
              ],
            ),
            settings: _settings(dynamicPolicy),
          ).start(runtime, workerEntryPoint: _workerEntryPoint);
          addTearDown(binding.dispose);
          final service = await binding.createInternalSession(
            realmUri: 'realm1',
            authId: 'service',
            authRole: 'service',
          );
          addTearDown(service.close);

          final registrations = <String, int>{};
          final subscriptions = <String, int>{};
          for (final scope in ['allowed', 'blocked', 'write', 'dynamic']) {
            final registered = await service.register('app.$scope.procedure');
            registrations[scope] = registered.registrationId;
            registered.onInvoke(
              (invocation) => invocation.respondWith(arguments: ['ok']),
            );
            final subscribed = await service.subscribe('app.$scope.topic');
            subscriptions[scope] = subscribed.subscriptionId;
          }
          final patterns = <String, int>{};
          for (final match in ['exact', 'prefix', 'wildcard']) {
            final subscription = await service.subscribe(
              match == 'wildcard' ? 'app.pattern.' : 'app.pattern',
              options: core.SubscribeOptions(match: match),
            );
            patterns[match] = subscription.subscriptionId;
          }

          final port = binding.listeners.single.port;
          late final _MetaCall call;
          if (transport.startsWith('mcp')) {
            final http = mcp.McpStreamableHttpClient(
              Uri.parse('http://127.0.0.1:$port/mcp'),
            );
            addTearDown(() => http.close(force: true));
            final direct = transport == 'mcp-json';
            if (!direct) await http.initialize();
            call = (procedure, arguments) async {
              final result = await http.callWampMetaProcedure(
                procedure,
                arguments: arguments,
                directJson: direct,
              );
              return (
                args: result.arguments,
                details: result.argumentsKeywords,
              );
            };
          } else {
            final peer = client.Client(
              realm: 'realm1',
              transport: transport == 'websocket'
                  ? client.WebSocketTransport.withJsonSerializer(
                      'ws://127.0.0.1:$port/ws',
                    )
                  : socket_transport.SocketTransport(
                      '127.0.0.1',
                      port,
                      json_serializer.Serializer(),
                      SocketHelper.serializationJson,
                    ),
            );
            final session = await peer.connect().first.timeout(
              const Duration(seconds: 10),
            );
            addTearDown(session.close);
            // Meta-call permission is not permission to use the discovered URI.
            await expectLater(
              session.subscribe('app.write.topic'),
              throwsA(
                isA<core.Error>().having(
                  (e) => e.error,
                  'error',
                  core.Error.notAuthorized,
                ),
              ),
            );
            await session.publish(
              'app.write.topic',
              options: core.PublishOptions(acknowledge: true),
            );
            await expectLater(
              session.call('app.write.procedure').first,
              throwsA(
                isA<core.Error>().having(
                  (e) => e.error,
                  'error',
                  core.Error.notAuthorized,
                ),
              ),
            );
            expect(
              (await session.call('app.allowed.procedure').first).arguments,
              ['ok'],
            );
            await session.subscribe('app.allowed.topic');
            call = (procedure, arguments) async {
              try {
                final result = await session
                    .call(procedure, arguments: arguments)
                    .first;
                final args = List<Object?>.from(result.arguments ?? const []);
                if (args.length == 1 && args.single is Map) {
                  return (
                    args: const [],
                    details: Map<String, Object?>.from(args.single as Map),
                  );
                }
                return (args: args, details: <String, Object?>{});
              } on core.Error catch (error) {
                return (args: [error.error], details: <String, Object?>{});
              }
            };
          }

          for (final kind in ['registration', 'subscription']) {
            final ids = kind == 'registration' ? registrations : subscriptions;
            final uriSuffix = kind == 'registration' ? 'procedure' : 'topic';
            final listing = await call('wamp.$kind.list', []);
            final exact = (listing.details['exact'] as List).cast<int>();
            expect(exact, contains(ids['allowed']));
            expect(exact, isNot(contains(ids['blocked'])));
            expect(exact, isNot(contains(ids['write'])));
            expect(exact.contains(ids['dynamic']), !dynamicPolicy);
            final allowedDetails = await call('wamp.$kind.get', [
              ids['allowed'],
            ]);
            expect(allowedDetails.details['uri'], 'app.allowed.$uriSuffix');
            for (final method in ['lookup', 'match']) {
              final allowed = await call('wamp.$kind.$method', [
                'app.allowed.$uriSuffix',
              ]);
              expect(
                allowed.args.expand(
                  (value) => value is List ? value : [value],
                ),
                contains(ids['allowed']),
              );
            }
            for (final scope in [
              'blocked',
              'write',
              if (dynamicPolicy) 'dynamic',
            ]) {
              for (final method in ['lookup', 'match']) {
                final result = await call('wamp.$kind.$method', [
                  'app.$scope.$uriSuffix',
                ]);
                expect(result.args.where((value) => value != null), isEmpty);
              }
              // Guessing an ID must not distinguish a denied entry from absence.
              for (final method in [
                'get',
                kind == 'registration' ? 'list_callees' : 'list_subscribers',
                kind == 'registration' ? 'count_callees' : 'count_subscribers',
              ]) {
                final denied = await call('wamp.$kind.$method', [ids[scope]]);
                final missing = await call('wamp.$kind.$method', [
                  9007199254740990,
                ]);
                expect(denied.args, equals(missing.args));
                expect(denied.details, equals(missing.details));
              }
            }
          }
          final subscriptionList = await call('wamp.subscription.list', []);
          expect(
            subscriptionList.details['exact'],
            contains(patterns['exact']),
          );
          for (final match in ['prefix', 'wildcard']) {
            expect(
              (subscriptionList.details[match] as List).contains(
                patterns[match],
              ),
              !dynamicPolicy,
            );
          }
          if (transport.startsWith('mcp')) {
            for (final entry in [
              ('registration', 'app.blocked.documented'),
              ('subscription', 'app.write.configured'),
              ('subscription', 'app.allowed.disabled'),
            ]) {
              final result = await call('wamp.${entry.$1}.lookup', [entry.$2]);
              expect(result.args, isEmpty);
            }
            final allowed = await call('wamp.subscription.lookup', [
              'app.allowed.configured',
            ]);
            expect(allowed.args, hasLength(1));
          }
        },
        skip: nativeLib == null ? 'Native transport library unavailable' : null,
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }
  }
}

RouterSettings _settings(bool dynamicPolicy) {
  final realm = RealmSettingsBuilder('realm1')
    ..addAuthMethod('anonymous')
    ..addRoleFromBuilder(
      RoleSettingsBuilder('service')..addPermissionFromBuilder(
        PermissionSettingsBuilder('')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations([
            'call',
            'register',
            'unregister',
            'subscribe',
            'unsubscribe',
            'publish',
          ]),
      ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('wamp.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(['call']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(['publish', 'register']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.blocked.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..denyOperations(['call', 'subscribe']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.allowed.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(['call', 'subscribe']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.dynamic.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(['call', 'subscribe']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('app.pattern')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(['subscribe']),
        ),
    );
  if (dynamicPolicy) realm.setAuthorizationProvider('meta-policy');
  return (RouterSettingsBuilder()
        ..addRealmFromBuilder(realm)
        ..addAuthorizationProvider(
          'meta-policy',
          const AuthorizationProviderDefinition(type: 'meta-policy'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('mcp')
            ..setRealm('realm1')
            ..addAuthMethod('anonymous'),
        )
        ..addListenerFromBuilder(
          ListenerSettingsBuilder('mixed', '127.0.0.1:0')
            ..addAuthMethod('anonymous')
            ..setPath('/ws')
            ..addProtocol(ListenerProtocol.websocket)
            ..addProtocol(ListenerProtocol.rawsocket)
            ..addProtocol(ListenerProtocol.http)
            ..setWebSocketOptions(
              const WebSocketListenerSettings(subprotocols: ['wamp.2.json']),
            )
            ..setHttpOptions(
              HttpListenerSettings(
                routes: [
                  HttpRouteSettings(
                    match: const HttpRouteMatch(path: '/mcp'),
                    action: const HttpRouteAction(
                      type: HttpRouteActionType.mcp,
                      realm: 'realm1',
                      sessionProfile: 'mcp',
                      options: {
                        'procedures': [
                          {
                            'procedure': 'app.blocked.documented',
                            'allow_call': false,
                          },
                        ],
                        'topics': [
                          {
                            'topic': 'app.write.configured',
                            'allowPublish': true,
                            'allowSubscribe': false,
                          },
                          {
                            'topic': 'app.allowed.disabled',
                            'allowSubscribe': false,
                          },
                          {
                            'topic': 'app.allowed.configured',
                            'allowSubscribe': true,
                          },
                        ],
                      },
                    ),
                  ),
                ],
              ),
            ),
        )
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        )
        ..setWorkerPool(const WorkerPoolSettings(minWorkers: 1)))
      .build();
}

void _workerEntryPoint(Map<String, Object?> init) {
  AuthorizationProviderFactoryRegistry.registerFactory(
    const _MetaPolicyFactory(),
  );
  defaultRouterWorkerEntryPoint(init);
}

class _MetaPolicyFactory extends AuthorizationProviderFactory {
  const _MetaPolicyFactory();
  @override
  String get type => 'meta-policy';
  @override
  Future<AuthorizationProvider> create(Map<String, Object?> options) async =>
      _MetaPolicy();
}

class _MetaPolicy implements AuthorizationProvider {
  @override
  AuthorizationDecision? authorize(AuthorizationRequest request) {
    if (request.authRole != 'anonymous') return null;
    if (request.uri.startsWith('app.dynamic.') &&
        (request.action == AuthorizationAction.call ||
            request.action == AuthorizationAction.subscribe)) {
      return const AuthorizationDecision.deny();
    }
    if (request.action == AuthorizationAction.subscribe &&
        request.uri.startsWith('app.pattern') &&
        request.targetMatchPolicy != null &&
        request.targetMatchPolicy != PermissionMatchPolicy.exact) {
      return const AuthorizationDecision.deny();
    }
    return null;
  }
}
