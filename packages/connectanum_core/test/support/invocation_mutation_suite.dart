import 'package:test/test.dart';

import '../message_invocation_test.dart' as invocation;
import '../message_invocation_regression_test.dart' as regression;
import '../message_invocation_response_lifecycle_test.dart' as lifecycle;
import '../message_invocation_transcoding_test.dart' as transcoding;
import '../message_lazy_payload_regression_test.dart' as lazy_payload;
import '../message_registered_regression_test.dart' as registration;

void main() {
  group('invocation', invocation.main);
  group('invocation regression', regression.main);
  group('response lifecycle', lifecycle.main);
  group('transcoding', transcoding.main);
  group('lazy payload', lazy_payload.main);
  group('registration', registration.main);
}
