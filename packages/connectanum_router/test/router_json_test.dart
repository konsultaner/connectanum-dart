import 'dart:convert';

import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/sni_certificate.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

const _certificatePem =
    '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----';
const _privateKeyPem =
    '-----BEGIN PRIVATE KEY-----\nMIIB\n-----END PRIVATE KEY-----';

SniCertificate _cert(String host) => SniCertificate(
  hostname: host,
  certificateChainPem: _certificatePem,
  privateKeyPem: _privateKeyPem,
);

Router _routerWithMcpOptions(Map<String, Object?> options) {
  final endpoint = Endpoint(
    host: '127.0.0.1',
    port: 0,
    tlsMode: TlsMode.disabled,
    maxRawSocketSizeExponent: 16,
  );
  final settings = RouterSettings(
    realms: [
      RealmSettings(
        name: 'realm1',
        auth: const RealmAuthSettings(methods: ['anonymous']),
        roles: const [],
        limits: const RealmLimitSettings(),
      ),
    ],
    listeners: [
      ListenerSettings(
        endpoint: '127.0.0.1:0',
        protocols: const [ListenerProtocol.http],
        http: HttpListenerSettings(
          routes: [
            HttpRouteSettings(
              match: const HttpRouteMatch(path: '/mcp'),
              action: HttpRouteAction(
                type: HttpRouteActionType.mcp,
                realm: 'realm1',
                options: options,
              ),
            ),
          ],
        ),
      ),
    ],
  );
  return Router(RouterConfig(endpoints: [endpoint]), settings: settings);
}

void main() {
  group('Router buildNativeConfigJson', () {
    test('encodes schema, version and endpoints', () {
      final endpoint = Endpoint(
        host: '127.0.0.1',
        port: 0,
        tlsMode: TlsMode.native,
        maxRawSocketSizeExponent: 16,
        sniCertificates: [_cert('example.com')],
      );
      final router = Router(RouterConfig(endpoints: [endpoint]));

      final bytes = router.buildNativeConfigJson();
      final map = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['schema'], RouterConfig.defaultSchema);
      expect(map['version'], RouterConfig.defaultVersion);
      final endpointsJson = map['endpoints'] as List;
      expect(endpointsJson, hasLength(1));
      expect((endpointsJson.first as Map)['host'], '127.0.0.1');
    });

    test('throws when using unsupported dart TLS mode', () {
      final endpoints = [
        Endpoint(
          host: '0.0.0.0',
          port: 0,
          tlsMode: TlsMode.dart,
          maxRawSocketSizeExponent: 16,
        ),
      ];
      expect(
        () => Router(RouterConfig(endpoints: endpoints)),
        throwsArgumentError,
      );
    });

    test('allows duplicate SNI host across distinct endpoints', () {
      final cert = _cert('example.com');
      final endpoints = [
        Endpoint(
          host: '0.0.0.0',
          port: 8080,
          tlsMode: TlsMode.native,
          maxRawSocketSizeExponent: 16,
          sniCertificates: [cert],
        ),
        Endpoint(
          host: '0.0.0.1',
          port: 8081,
          tlsMode: TlsMode.native,
          maxRawSocketSizeExponent: 16,
          sniCertificates: [cert],
        ),
      ];
      expect(() => Router(RouterConfig(endpoints: endpoints)), returnsNormally);
    });

    test('encodes MCP HTTP routes as router-hosted translation endpoints', () {
      final endpoint = Endpoint(
        host: '127.0.0.1',
        port: 0,
        tlsMode: TlsMode.disabled,
        maxRawSocketSizeExponent: 16,
      );
      final settings = RouterSettings(
        realms: [
          RealmSettings(
            name: 'realm1',
            auth: const RealmAuthSettings(methods: ['anonymous']),
            roles: const [],
            limits: const RealmLimitSettings(),
          ),
        ],
        listeners: const [
          ListenerSettings(
            endpoint: '127.0.0.1:0',
            protocols: [ListenerProtocol.http],
            http: HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(path: '/mcp'),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.mcp,
                    realm: 'realm1',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final router = Router(
        RouterConfig(endpoints: [endpoint]),
        settings: settings,
      );

      final map =
          json.decode(utf8.decode(router.buildNativeConfigJson())) as Map;
      final endpointJson = (map['endpoints'] as List).single as Map;
      final route = (endpointJson['http_routes'] as List).single as Map;
      final action = route['default'] as Map;
      expect(action['type'], 'translation');
      expect(action['realm'], 'realm1');
      expect(action['procedure'], 'connectanum.mcp.handle');
    });

    test('encodes method-specific HTTP route actions for native routing', () {
      final endpoint = Endpoint(
        host: '127.0.0.1',
        port: 0,
        tlsMode: TlsMode.disabled,
        maxRawSocketSizeExponent: 16,
      );
      final settings = RouterSettings(
        realms: [
          RealmSettings(
            name: 'realm1',
            auth: const RealmAuthSettings(methods: ['anonymous']),
            roles: const [],
            limits: const RealmLimitSettings(),
          ),
        ],
        listeners: const [
          ListenerSettings(
            endpoint: '127.0.0.1:0',
            protocols: [ListenerProtocol.http],
            http: HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(
                    path: '/api/items',
                    methods: ['GET', 'POST'],
                  ),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    realm: 'realm1',
                    procedure: 'com.example.items.list',
                  ),
                  methodActions: {
                    'POST': HttpRouteAction(
                      type: HttpRouteActionType.rpc,
                      realm: 'realm1',
                      procedure: 'com.example.items.create',
                    ),
                  },
                ),
              ],
            ),
          ),
        ],
      );
      final router = Router(
        RouterConfig(endpoints: [endpoint]),
        settings: settings,
      );

      final map =
          json.decode(utf8.decode(router.buildNativeConfigJson())) as Map;
      final endpointJson = (map['endpoints'] as List).single as Map;
      final route = (endpointJson['http_routes'] as List).single as Map;
      expect(route, isNot(contains('default')));
      final methods = route['methods'] as Map;
      expect((methods['GET'] as Map)['procedure'], 'com.example.items.list');
      expect((methods['POST'] as Map)['procedure'], 'com.example.items.create');
    });

    test('encodes catch-all HTTP routes as native prefix fallbacks', () {
      final endpoint = Endpoint(
        host: '127.0.0.1',
        port: 0,
        tlsMode: TlsMode.disabled,
        maxRawSocketSizeExponent: 16,
      );
      final settings = RouterSettings(
        realms: [
          RealmSettings(
            name: 'realm1',
            auth: const RealmAuthSettings(methods: ['anonymous']),
            roles: const [],
            limits: const RealmLimitSettings(),
          ),
        ],
        listeners: const [
          ListenerSettings(
            endpoint: '127.0.0.1:0',
            protocols: [ListenerProtocol.http],
            http: HttpListenerSettings(
              routes: [
                HttpRouteSettings(
                  match: HttpRouteMatch(catchAll: true),
                  action: HttpRouteAction(
                    type: HttpRouteActionType.rpc,
                    realm: 'realm1',
                    procedure: 'com.example.http.fallback',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final router = Router(
        RouterConfig(endpoints: [endpoint]),
        settings: settings,
      );

      final map =
          json.decode(utf8.decode(router.buildNativeConfigJson())) as Map;
      final endpointJson = (map['endpoints'] as List).single as Map;
      final route = (endpointJson['http_routes'] as List).single as Map;
      expect(route['path'], '/');
      expect(route['match_kind'], 'prefix');
      final action = route['default'] as Map;
      expect(action['realm'], 'realm1');
      expect(action['procedure'], 'com.example.http.fallback');
    });

    test(
      'keeps MCP auth failures in Dart binding for CORS-aware responses',
      () {
        final endpoint = Endpoint(
          host: '127.0.0.1',
          port: 0,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
        );
        final settings = RouterSettings(
          realms: [
            RealmSettings(
              name: 'realm1',
              auth: const RealmAuthSettings(methods: ['ticket']),
              roles: const [],
              limits: const RealmLimitSettings(),
            ),
          ],
          sessionProfiles: const [
            SessionProfileSettings(
              name: 'mcp-ticket',
              realm: 'realm1',
              auth: SessionProfileAuthSettings(methods: ['ticket']),
            ),
          ],
          listeners: const [
            ListenerSettings(
              endpoint: '127.0.0.1:0',
              protocols: [ListenerProtocol.http],
              http: HttpListenerSettings(
                routes: [
                  HttpRouteSettings(
                    match: HttpRouteMatch(path: '/mcp'),
                    action: HttpRouteAction(
                      type: HttpRouteActionType.mcp,
                      realm: 'realm1',
                      sessionProfile: 'mcp-ticket',
                      options: {'allow_insecure_transport': true},
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final router = Router(
          RouterConfig(endpoints: [endpoint]),
          settings: settings,
        );

        final map =
            json.decode(utf8.decode(router.buildNativeConfigJson())) as Map;
        final endpointJson = (map['endpoints'] as List).single as Map;
        final route = (endpointJson['http_routes'] as List).single as Map;
        expect(route, isNot(contains('transport_auth')));
        expect(
          (route['default'] as Map)['procedure'],
          'connectanum.mcp.handle',
        );
      },
    );

    test('validates MCP resource options while building native config', () {
      final router = _routerWithMcpOptions({
        'resources': [
          {'name': 'missing-uri', 'text': 'context'},
        ],
      });

      expect(
        router.buildNativeConfigJson,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('MCP resource config requires uri'),
          ),
        ),
      );
    });

    test('validates MCP WAMP API options while building native config', () {
      final router = _routerWithMcpOptions({
        'procedures': [
          {'name': 'missing-uri'},
        ],
      });

      expect(
        router.buildNativeConfigJson,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('MCP procedure config requires procedure or uri'),
          ),
        ),
      );
    });

    test('validates MCP prompt options while building native config', () {
      final router = _routerWithMcpOptions({
        'prompts': [
          {
            'name': 'summarize',
            'text': 'Summarize {{taskId}}',
            'arguments': [
              {'name': 'taskId'},
              {'name': 'taskId'},
            ],
          },
        ],
      });

      expect(
        router.buildNativeConfigJson,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Invalid MCP route options'),
              contains('Duplicate MCP prompt argument'),
            ),
          ),
        ),
      );
    });
  });
}
