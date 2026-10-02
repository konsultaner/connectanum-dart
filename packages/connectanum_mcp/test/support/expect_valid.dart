import 'dart:async';

import 'package:test/test.dart';

// For synchronous operations with known-valid inputs, assert acceptance before
// checking their exact value. Keep negative-input checks at the call site.
T expectValid<T>(T Function() operation) {
  late T value;
  Object? failure;
  try {
    value = operation();
  } on TimeoutException {
    rethrow;
  } catch (error) {
    failure = error;
  }
  expect(failure, isNull, reason: 'The valid operation must succeed');
  return value;
}

Future<T> expectValidAsync<T>(Future<T> Function() operation) async {
  late T value;
  Object? failure;
  try {
    value = await operation();
  } on TimeoutException {
    rethrow;
  } catch (error) {
    failure = error;
  }
  // completes forwards Future errors instead of asserting successful completion.
  expect(failure, isNull, reason: 'The valid operation must succeed');
  return value;
}
