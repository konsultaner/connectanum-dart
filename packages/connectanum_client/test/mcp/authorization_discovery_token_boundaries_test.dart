import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  // Alphabet endpoints and HTTP token punctuation are valid auth parameters.
  const tokens = [
    '0',
    '9',
    'A',
    'Z',
    'a',
    'z',
    '!',
    '#',
    r'$',
    '%',
    '&',
    "'",
    '*',
    '+',
    '-',
    '.',
    '^',
    '_',
    '`',
    '|',
    '~',
  ];
  for (final token in tokens) {
    test('auth parameter preserves token value $token', () {
      List<McpBearerChallenge>? parsed;
      expect(() {
        parsed = parseMcpBearerChallenges([
          'Basic realm="other", Bearer hint=$token, scope="tools:call"',
        ]);
      }, returnsNormally);
      expect(parsed, hasLength(1));
      expect(parsed!.single.parameters, {'hint': token, 'scope': 'tools:call'});
    });
    test('auth parameter preserves token name $token', () {
      List<McpBearerChallenge>? parsed;
      expect(() {
        parsed = parseMcpBearerChallenges([
          'Bearer $token=V, resource_metadata="https://api.example/metadata"',
        ]);
      }, returnsNormally);
      expect(parsed, hasLength(1));
      expect(parsed!.single.parameters, {
        token.toLowerCase(): 'V',
        'resource_metadata': 'https://api.example/metadata',
      });
    });
  }
}
