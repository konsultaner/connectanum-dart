@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

import 'discovery_test_expectations.dart';

Map<String, Object?> _server({String issuer = 'https://auth.example'}) => {
  'issuer': issuer,
  'authorization_endpoint': '$issuer/authorize',
  'token_endpoint': '$issuer/token',
  'response_types_supported': ['code'],
  'code_challenge_methods_supported': ['S256'],
};

void main() {
  const validScopeCharacters =
      '!#\$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ['
      ']^_`abcdefghijklmnopqrstuvwxyz{|}~';
  for (final character in validScopeCharacters.split('')) {
    test('scope accepts ASCII ${character.codeUnitAt(0)} unchanged', () {
      McpAuthorizationServerMetadata? metadata;
      expect(() {
        metadata = McpAuthorizationServerMetadata.fromJson(
          _server()..['scopes_supported'] = [character],
        );
      }, returnsNormally);
      expect(metadata!.scopesSupported, [character]);
      expect(metadata!.raw['scopes_supported'], [character]);
    });
  }
  for (final value in ['', ' ', '\t', '\n', '"', r'\', '\u007f', '\u0080']) {
    test('scope rejects separator/control ${jsonEncode(value)}', () {
      expect(
        () => McpAuthorizationServerMetadata.fromJson(
          _server()..['scopes_supported'] = [value],
        ),
        throwsA(isA<McpAuthorizationDiscoveryException>()),
      );
    });
  }
  for (final host in ['localhost', '127.0.0.1', '[::1]']) {
    test('loopback development issuer accepts $host', () {
      McpAuthorizationServerMetadata? metadata;
      expect(() {
        metadata = McpAuthorizationServerMetadata.fromJson(
          _server(issuer: 'http://$host:9876'),
        );
      }, returnsNormally);
      expect(metadata!.issuer, Uri.parse('http://$host:9876'));
      expect(metadata!.tokenEndpoint, Uri.parse('http://$host:9876/token'));
    });
  }
  for (final header in [
    'Bearer realm=',
    'Bearer realm="unterminated',
    'Bearer realm="trailing\\',
    'Bearer realm="one", REALM="two"',
    'Bearer realm="one", broken=',
    'Bearer realm="one", broken="unterminated',
  ]) {
    test('malformed challenge fails closed without throwing: $header', () {
      List<McpBearerChallenge>? result;
      expect(() {
        result = parseMcpBearerChallenges([
          header,
          'Basic realm="legacy", Bearer realm="valid", scope="read"',
        ]);
      }, returnsNormally);
      expect(result, hasLength(1));
      expect(result!.single.parameters, {'realm': 'valid', 'scope': 'read'});
    });
  }
  for (final header in [
    'Bearer realm="first", Basic realm="legacy", Bearer realm="second"',
    'Bearer realm=first,\tBasic realm=legacy,\tBearer realm=second',
    'Bearer realm="first",Basic realm="legacy",Bearer realm="second"',
  ]) {
    test('distinct valid challenge boundaries: $header', () {
      List<McpBearerChallenge>? result;
      expect(
        () => result = parseMcpBearerChallenges([header]),
        returnsNormally,
      );
      expect(result!.map((challenge) => challenge.parameters).toList(), [
        {'realm': 'first'},
        {'realm': 'second'},
      ]);
    });
  }

  for (final scope in <String?>[null, '!', '#', '[', ']', '~']) {
    test('accepts exact body byte budget and challenge scope $scope', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final resource = Uri.parse('http://127.0.0.1:${server.port}/mcp');
      final body = jsonEncode({
        'resource': resource.toString(),
        'authorization_servers': ['https://auth.example'],
      });
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        await request.drain<void>();
        if (scope != null && request.uri.path == '/mcp') {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Bearer scope="$scope", resource_metadata="${resource.resolve('/metadata')}"',
          );
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.add(utf8.encode(body));
        }
        await request.response.close();
      });
      final result = await expectDiscoverySuccess(
        discoverMcpProtectedResourceMetadata(
          resource,
          maxMetadataBytes: utf8.encode(body).length,
        ),
      );
      expect(result.metadata.resource, resource);
      expect(result.metadata.authorizationServers, [
        Uri.parse('https://auth.example'),
      ]);
      expect(result.challenge?.scopes, scope == null ? null : [scope]);
      expect(paths, scope == null ? ['/mcp'] : ['/mcp', '/metadata']);
    });
  }
}
