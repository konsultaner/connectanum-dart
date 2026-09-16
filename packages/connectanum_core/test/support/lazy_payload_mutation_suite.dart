import 'package:test/test.dart';

import '../message_invocation_test.dart' as invocation;
import '../message_lazy_payload_regression_test.dart' as lazy_payload;
import '../message_result_test.dart' as result;

// Compile the complete browser mutation oracle once, retaining suite boundaries.
void main() {
  group('lazy payload', lazy_payload.main);
  group('invocation', invocation.main);
  group('result', result.main);
}
