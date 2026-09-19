import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

Future<File> expectValidInstall(Future<File> Function() operation) async {
  File? installed;
  Object? failure;
  try {
    installed = await operation();
  } on TimeoutException {
    rethrow;
  } on ProcessException {
    rethrow;
  } on SocketException {
    rethrow;
  } catch (error) {
    failure = error;
  }
  expect(
    failure,
    isNull,
    reason: 'Installing a valid native artifact must succeed',
  );
  expect(installed, isNotNull);
  return installed!;
}
