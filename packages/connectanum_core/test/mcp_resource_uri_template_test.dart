import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('McpResourceUriTemplate', () {
    test('expands and matches Level 1 variables with UTF-8 escaping', () {
      final template = McpResourceUriTemplate(
        'app://tasks/{taskId}/sections/{section}',
      );

      expect(template.template, 'app://tasks/{taskId}/sections/{section}');
      expect(template.variables, const <String>['taskId', 'section']);
      expect(template.literalLength, 22);
      expect(
        () => template.variables.add('other'),
        throwsUnsupportedError,
      );

      final uri = template.expand(const <String, String>{
        'taskId': 'T 1/✓',
        'section': 'a?b#c',
        'ignored': 'extra',
      });

      expect(
        uri,
        'app://tasks/T%201%2F%E2%9C%93/sections/a%3Fb%23c',
      );
      expect(template.match(uri), const <String, String>{
        'taskId': 'T 1/✓',
        'section': 'a?b#c',
      });
    });

    test('requires every declared variable during expansion', () {
      final template = McpResourceUriTemplate('app://tasks/{taskId}');

      expect(
        () => template.expand(const <String, String>{}),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'variables',
          ),
        ),
      );
    });

    test('does not let simple variables consume reserved delimiters', () {
      final template = McpResourceUriTemplate('app://tasks/{taskId}');

      expect(template.match('app://tasks/parent/child'), isNull);
      expect(template.match('app://tasks/parent%2Fchild'), {
        'taskId': 'parent/child',
      });
      expect(
        template.expand(const {'taskId': 'parent%2Fchild'}),
        'app://tasks/parent%252Fchild',
      );
    });

    test('rejects unsupported or ambiguous template syntax', () {
      for (final template in [
        '',
        'relative/{id}',
        'app://tasks/{first}{second}',
        'app://tasks/{id:2}',
        'app://tasks/{+id}',
        'app://tasks/{first}-{second}',
        'app://tasks/{id}/{id}',
        'app://tasks/{id',
        'app://tasks/id}',
      ]) {
        expect(
          () => McpResourceUriTemplate(template),
          throwsArgumentError,
          reason: template,
        );
      }
    });
  });
}
