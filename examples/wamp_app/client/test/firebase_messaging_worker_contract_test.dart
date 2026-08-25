import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'background worker keeps cursor relay alive without presenting content',
    () {
      final source = File('web/firebase-messaging-sw.js').readAsStringSync();

      expect(source, contains('return self.clients'));
      expect(source, contains(r'/^[1-9][0-9]{0,19}$/'));
      expect(source, isNot(contains('showNotification')));
      expect(source, isNot(contains('console.')));
    },
  );
}
