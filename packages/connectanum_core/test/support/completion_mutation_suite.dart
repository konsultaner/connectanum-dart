import 'package:test/test.dart';

import '../mcp_completion_regression_test.dart' as regression;
import '../mcp_completion_test.dart' as protocol;

// Keep one browser compilation while retaining both independent test suites.
void main() {
  group('protocol', protocol.main);
  group('regression', regression.main);
}
