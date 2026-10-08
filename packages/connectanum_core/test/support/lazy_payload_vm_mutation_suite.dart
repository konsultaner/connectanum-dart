import 'package:test/test.dart';

import '../message_invocation_test.dart' as invocation;
import '../message_lazy_payload_regression_test.dart' as lazy_payload;
import '../message_flatbuffers_ppt_view_test.dart' as flatbuffers_ppt;
import '../message_payload_contract_test.dart' as payload_contract;
import '../message_result_test.dart' as result;

// Check the explicit payload contract before fail-fast can stop at a dereference
// in a legacy integration test. All original suites remain in the inventory.
void main() {
  group('payload contract', payload_contract.main);
  group('FlatBuffers PPT view', flatbuffers_ppt.main);
  group('lazy payload', lazy_payload.main);
  group('invocation', invocation.main);
  group('result', result.main);
}
