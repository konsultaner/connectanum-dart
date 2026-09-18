import 'dart:async';

import 'package:connectanum_router/src/router/config/router_config_loader.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:test/test.dart';

RouterSettings loadValidRouterConfig(Map<String, Object?> input) =>
    expectConfigSuccess(() => RouterConfigLoader.fromMap(input));

// Only parser-contract failures become assertions. I/O, timeouts and other
// infrastructure failures must remain errors in mutation evidence.
T expectConfigSuccess<T>(T Function() operation) {
  try {
    return operation();
  } catch (error) {
    if (!_isParserFailure(error)) rethrow;
    fail('A valid router configuration must load successfully: $error');
  }
}

Future<T> expectConfigLoad<T>(FutureOr<T> Function() operation) async {
  try {
    return await operation();
  } catch (error) {
    if (!_isParserFailure(error)) rethrow;
    fail('A valid router configuration must load successfully: $error');
  }
}

bool _isParserFailure(Object error) =>
    error is FormatException ||
    error is ArgumentError ||
    error is StateError ||
    error is TypeError;
