import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('toPayload unpacks PPT payloads', () {
      final details = ResultDetails(
        pptScheme: 'x_custom_scheme',
        pptSerializer: 'cbor',
      );
      final result = Result(
        1,
        details,
        arguments: PPTPayload.packPPTPayload(
          const ['ppt-result'],
          const {'worker': 10},
          details,
        ),
      );

      final payload = result.toPayload();
      expect(payload.arguments, equals(const ['ppt-result']));
      expect(payload.argumentsKeywords, equals(const {'worker': 10}));
    });
  });
}
