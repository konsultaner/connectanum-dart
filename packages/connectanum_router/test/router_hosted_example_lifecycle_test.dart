@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/router_example.dart';

void main() {
  test('router example exits cleanly on SIGINT alone', () async {
    final router = await RouterExample.start();
    expect(router.sawSelfSmokeOutput, isFalse);
    await router.close(signal: ProcessSignal.sigint);
  });
}
