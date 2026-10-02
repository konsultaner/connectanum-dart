@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_bench/src/http_auth_bench_harness.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  test(
    'equal listener addresses bind once and preserve all provider routes',
    () async {
      final reserved = await ServerSocket.bind('127.0.0.1', 0);
      final port = reserved.port;
      await reserved.close();
      final builder = RouterSettingsBuilder();
      for (final name in ['alpha', 'beta', 'gamma']) {
        builder.addHttpAuthProvider(
          name,
          HttpAuthProviderDefinition(
            type: 'oauth',
            options: {
              'url': 'http://127.0.0.1:$port/$name',
              'default_auth_id': '$name-user',
              'default_auth_role': '$name-role',
            },
          ),
        );
      }
      final outcome = await HttpAuthBenchHarness.maybeStart(
        settings: builder.build(),
      ).then<Object?>((value) => value, onError: (Object error) => error);
      // The supported configuration must start, not merely avoid an assertion.
      expect(outcome, isA<HttpAuthBenchHarness>());
      final harness = outcome as HttpAuthBenchHarness;
      addTearDown(harness.close);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      for (final name in ['alpha', 'beta', 'gamma']) {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/$name'),
        );
        request.write('token=${HttpAuthBenchHarness.defaultOAuthAccessToken}');
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        expect(
          jsonDecode(await utf8.decoder.bind(response).join()),
          containsPair('sub', '$name-user'),
        );
      }
    },
  );
}
