import 'package:test/test.dart';

import '../http_stream_diagnostics_regression_test.dart' as diagnostics;
import '../http_stream_handler_test.dart' as original;
import '../http_stream_response_regression_test.dart' as response;

void main() {
  group('existing HTTP handler contracts', original.main);
  group('HTTP diagnostic regression', diagnostics.main);
  group('HTTP response regression', response.main);
}
