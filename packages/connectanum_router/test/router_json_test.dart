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

void _expectInvalidMcpOptions(Map<String, Object?> options, String message) {
  final router = _routerWithMcpOptions(options);
  expect(
    router.buildNativeConfigJson,
    throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        allOf(contains('Invalid MCP route options'), contains(message)),
      ),
    ),
  );
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

    test('validates MCP post response transport options while building native '
        'config', () {
      _expectInvalidMcpOptions({
        'post_response_transport': 'xml',
      }, 'MCP post_response_transport must be one of');

      _expectInvalidMcpOptions({
        'stream_post_responses': 'false',
      }, 'MCP stream_post_responses must be a boolean');
    });

    test('validates MCP route option shapes while building native config', () {
      _expectInvalidMcpOptions({
        'include_pubsub_tools': 'true',
      }, 'MCP include_pubsub_tools must be a boolean');
      _expectInvalidMcpOptions({
        'tool_list_page_size': 0,
      }, 'MCP tool_list_page_size must be a positive integer');
      _expectInvalidMcpOptions({
        'allowed_origins': ['https://agent.example', 7],
      }, 'MCP allowed_origins must be a string or list of strings');
      _expectInvalidMcpOptions({
        'resources': 'not-a-list',
      }, 'MCP resources must be a list of objects');
      _expectInvalidMcpOptions({
        'procedures': ['not-an-object'],
      }, 'MCP procedures[0] must be an object');
      _expectInvalidMcpOptions({
        'procedures': [
          {'procedure': 'app.lookup', 'allow_call': 'true'},
        ],
      }, 'MCP procedures[0].allow_call must be a boolean');
      _expectInvalidMcpOptions({
        'topics': [
          {'topic': 'app.events', 'allow_publish': 'true'},
        ],
      }, 'MCP topics[0].allow_publish must be a boolean');
      _expectInvalidMcpOptions({
        'topics': [
          {'topic': 'app.events', 'allowPublish': 'true'},
        ],
      }, 'MCP topics[0].allowPublish must be a boolean');
      _expectInvalidMcpOptions({
        'topics': [
          {'topic': 'app.events', 'allowSubscribe': 'true'},
        ],
      }, 'MCP topics[0].allowSubscribe must be a boolean');
      _expectInvalidMcpOptions({
        'resources': [
          {'uri': 'file:///context', 'text': 'context', 'size': '7'},
        ],
      }, 'MCP resources[0].size must be a non-negative integer');
      _expectInvalidMcpOptions({
        'prompts': [
          {'name': 'summarize', 'text': 'Summarize', 'arguments': 'taskId'},
        ],
      }, 'MCP prompts[0].arguments must be a list of objects');
      _expectInvalidMcpOptions({
        'prompts': [
          {
            'name': 'summarize',
            'text': 'Summarize {{taskId}}',
            'arguments': [
              {'name': 'taskId', 'required': 'true'},
            ],
          },
        ],
      }, 'MCP prompts[0].arguments[0].required must be a boolean');
      _expectInvalidMcpOptions({
        'prompts': [
          {
            'name': 'summarize',
            'messages': [
              {'role': 7, 'text': 'Summarize'},
            ],
          },
        ],
      }, 'MCP prompts[0].messages[0].role must be a string');
    });

    test('accepts MCP non-streaming post response options', () {
      for (final options in const <Map<String, Object?>>[
        {'post_response_transport': 'json'},
        {'post_response_transport': 'SSE'},
        {'stream_post_responses': false},
      ]) {
        expect(
          _routerWithMcpOptions(options).buildNativeConfigJson,
          returnsNormally,
        );
      }
    });
  });
}
