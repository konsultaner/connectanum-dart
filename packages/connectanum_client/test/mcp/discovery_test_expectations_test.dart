import 'dart:async';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

import 'discovery_test_expectations.dart';

void main() {
  test('successful discovery expectation returns the original value', () async {
    final value = Object();
    expect(await expectDiscoverySuccess(Future.value(value)), same(value));
    expect(await expectDiscoverySuccess(Future<Object?>.value()), isNull);
  });

  for (final error in <Object>[
    ArgumentError.value(1048576, 'maxMetadataBytes'),
    const McpAuthorizationDiscoveryException('Invalid metadata'),
  ]) {
    test('unexpected discovery rejection fails an assertion: $error', () async {
      await expectLater(
        expectDiscoverySuccess(Future<Object>.error(error)),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            contains('Well-formed discovery metadata must be accepted.'),
          ),
        ),
      );
    });
  }

  for (final error in <Object>[
    TimeoutException('Controlled deadline'),
    const McpAuthorizationDiscoveryException(
      'Protected Resource Metadata discovery timed out.',
    ),
    const McpAuthorizationDiscoveryException(
      'Authorization Server Metadata discovery timed out.',
    ),
  ]) {
    test('discovery deadline remains the original error: $error', () async {
      await expectLater(
        expectDiscoverySuccess(Future<Object>.error(error)),
        throwsA(same(error)),
      );
    });
  }
}
