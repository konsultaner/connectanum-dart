import 'dart:async';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

Future<T> expectDiscoverySuccess<T>(Future<T> operation) async {
  late T value;
  Object? failure;
  try {
    value = await operation;
  } on TimeoutException {
    rethrow;
  } on McpAuthorizationDiscoveryException catch (error) {
    // Preserve deadline failures as errors, not assertion-backed detections.
    if (error.message.contains('discovery timed out')) rethrow;
    failure = error;
  } catch (error) {
    failure = error;
  }
  expect(
    failure,
    isNull,
    reason: 'Well-formed discovery metadata must be accepted.',
  );
  return value;
}
