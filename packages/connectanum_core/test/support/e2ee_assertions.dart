import 'dart:async';

import 'package:test/test.dart';

T expectE2eeSuccess<T>(T Function() operation) {
  late T result;
  Object? failure;
  try {
    result = operation();
  } on TimeoutException {
    rethrow;
  } catch (error) {
    failure = error;
  }
  expect(failure, isNull, reason: 'A valid E2EE operation must succeed');
  return result;
}
