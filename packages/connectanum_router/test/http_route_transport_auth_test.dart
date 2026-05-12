import 'package:connectanum_router/src/router/config/http_route_transport_auth.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:test/test.dart';

void main() {
  group('deriveHttpRouteTransportAuth', () {
    test('requires bearer and tls for protected provider-backed routes', () {
      final requirements = deriveHttpRouteTransportAuth(
        action: const HttpRouteAction(
          type: HttpRouteActionType.rpc,
          procedure: 'com.example.secure',
          sessionProfile: 'http-jwt',
        ),
        sessionProfile: const SessionProfileSettings(
          name: 'http-jwt',
          realm: 'realm1',
          auth: SessionProfileAuthSettings(
            methods: ['jwt'],
            httpProvider: 'edge-jwt',
          ),
        ),
      );

      expect(requirements.requireBearer, isTrue);
      expect(requirements.requireTls, isTrue);
      expect(requirements.requireMutualTls, isFalse);
      expect(requirements.allowUnauthenticatedCorsPreflight, isFalse);
      expect(
        requirements.toNativeMap(),
        isNot(contains('allow_unauthenticated_cors_preflight')),
      );
    });

    test('mcp routes allow unauthenticated CORS preflight', () {
      final requirements = deriveHttpRouteTransportAuth(
        action: const HttpRouteAction(
          type: HttpRouteActionType.mcp,
          sessionProfile: 'http-jwt',
        ),
        sessionProfile: const SessionProfileSettings(
          name: 'http-jwt',
          realm: 'realm1',
          auth: SessionProfileAuthSettings(
            methods: ['jwt'],
            httpProvider: 'edge-jwt',
          ),
        ),
      );

      expect(requirements.requireBearer, isTrue);
      expect(requirements.requireTls, isTrue);
      expect(requirements.requireMutualTls, isFalse);
      expect(requirements.allowUnauthenticatedCorsPreflight, isTrue);
      expect(
        requirements.toNativeMap(),
        containsPair('allow_unauthenticated_cors_preflight', true),
      );
    });

    test('mcp routes can opt out of unauthenticated CORS preflight', () {
      final requirements = deriveHttpRouteTransportAuth(
        action: const HttpRouteAction(
          type: HttpRouteActionType.mcp,
          sessionProfile: 'http-jwt',
          options: <String, Object?>{
            'allow_unauthenticated_cors_preflight': false,
          },
        ),
        sessionProfile: const SessionProfileSettings(
          name: 'http-jwt',
          realm: 'realm1',
          auth: SessionProfileAuthSettings(
            methods: ['jwt'],
            httpProvider: 'edge-jwt',
          ),
        ),
      );

      expect(requirements.requireBearer, isTrue);
      expect(requirements.allowUnauthenticatedCorsPreflight, isFalse);
      expect(
        requirements.toNativeMap(),
        isNot(contains('allow_unauthenticated_cors_preflight')),
      );
    });

    test('auth routes require tls but not bearer by default', () {
      final requirements = deriveHttpRouteTransportAuth(
        action: const HttpRouteAction(
          type: HttpRouteActionType.auth,
          sessionProfile: 'http-ticket',
        ),
        sessionProfile: const SessionProfileSettings(
          name: 'http-ticket',
          realm: 'realm1',
          auth: SessionProfileAuthSettings(methods: ['ticket']),
        ),
      );

      expect(requirements.requireBearer, isFalse);
      expect(requirements.requireTls, isTrue);
      expect(requirements.requireMutualTls, isFalse);
      expect(requirements.allowUnauthenticatedCorsPreflight, isFalse);
    });

    test('public profiles remain on the unauthenticated fast path', () {
      final requirements = deriveHttpRouteTransportAuth(
        action: const HttpRouteAction(
          type: HttpRouteActionType.rpc,
          procedure: 'com.example.public',
          sessionProfile: 'public-http',
        ),
        sessionProfile: const SessionProfileSettings(
          name: 'public-http',
          auth: SessionProfileAuthSettings(methods: []),
        ),
      );

      expect(requirements.isConfigured, isFalse);
    });

    test('explicit overrides allow insecure transport and require mTLS', () {
      final requirements = deriveHttpRouteTransportAuth(
        action: const HttpRouteAction(
          type: HttpRouteActionType.rpc,
          procedure: 'com.example.mtls',
          options: <String, Object?>{
            'allow_insecure_transport': true,
            'require_mtls': true,
          },
        ),
        sessionProfile: const SessionProfileSettings(name: 'public-http'),
      );

      expect(requirements.requireBearer, isFalse);
      expect(requirements.requireTls, isTrue);
      expect(requirements.requireMutualTls, isTrue);
    });
  });
}
