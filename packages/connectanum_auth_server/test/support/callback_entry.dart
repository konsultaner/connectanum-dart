import 'package:test/test.dart';

/// Fails on an early result instead of waiting for a callback that cannot run.
Future<void> expectCallbackEntry(
  Future<void> entry,
  Future<Object?> operation,
) => Future.any([
  entry,
  operation.then<void>(
    (_) => fail('Operation completed before required callback entry'),
    onError: (Object error, StackTrace stack) =>
        fail('Operation failed before required callback entry'),
  ),
]);
