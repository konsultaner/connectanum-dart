@TestOn('vm')
library;

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  // RFC 9110 sections 11.3 and 11.6.1 permit bare schemes and empty list members.
  for (final separator in [',', ', ', ',\t', ', , ', ',\t,\t']) {
    for (final first in ['Bearer', 'Newauth']) {
      test('bare $first does not hide a later Bearer: $separator', () {
        List<McpBearerChallenge>? result;
        expect(() {
          result = parseMcpBearerChallenges([
            '$first${separator}Bearer realm="consumer", '
                'resource_metadata="https://api.example/metadata"',
          ]);
        }, returnsNormally);
        expect(result!.map((value) => value.parameters).toList(), [
          if (first == 'Bearer') <String, String>{},
          {
            'realm': 'consumer',
            'resource_metadata': 'https://api.example/metadata',
          },
        ]);
      });
    }
    test('empty parameter list members do not discard metadata: $separator', () {
      List<McpBearerChallenge>? result;
      expect(() {
        result = parseMcpBearerChallenges([
          'Bearer realm="consumer"${separator}resource_metadata="https://api.example/metadata"',
        ]);
      }, returnsNormally);
      expect(result, hasLength(1));
      expect(result!.single.parameters, {
        'realm': 'consumer',
        'resource_metadata': 'https://api.example/metadata',
      });
    });
    test('leading parameter list member is ignored: $separator', () {
      List<McpBearerChallenge>? result;
      expect(() {
        result = parseMcpBearerChallenges([
          'Bearer $separator realm="consumer"',
        ]);
      }, returnsNormally);
      expect(result, hasLength(1));
      expect(result!.single.parameters, {'realm': 'consumer'});
    });
  }
  for (final header in ['Bearer', 'Bearer ', 'Bearer\t']) {
    test('bare challenge remains visible: $header', () {
      List<McpBearerChallenge>? result;
      expect(
        () => result = parseMcpBearerChallenges([header]),
        returnsNormally,
      );
      expect(result, hasLength(1));
      expect(result!.single.parameters, isEmpty);
    });
  }
}
