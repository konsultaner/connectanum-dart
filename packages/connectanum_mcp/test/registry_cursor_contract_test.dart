import 'dart:convert';

import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

import 'support/expect_valid.dart';

void main() {
  for (final kind in ['tools', 'prompts', 'resources', 'templates']) {
    group('$kind cursor boundary', () {
      for (final (offset, expectedLength) in [(0, 1), (1, 1), (2, 0)]) {
        test('accepts offset $offset including both closed boundaries', () {
          final fixture = expectValid(() => _registry(kind));
          final page = expectValid(
            () => fixture.read(
              _rewrite(fixture.cursor, offset: '$offset'),
            ),
          );
          expect(page, hasLength(expectedLength));
          if (offset == 0) expect(page.single, same(fixture.first));
          if (offset == 1) expect(page.single, same(fixture.second));
          final next = expectValid(
            () => fixture.next(
              _rewrite(fixture.cursor, offset: '$offset'),
            ),
          );
          if (offset == 0) {
            expect(next, isNotNull);
            expect(fixture.read(next).single, same(fixture.second));
          } else {
            expect(next, isNull);
          }
        });
      }
      for (final offset in ['-1', '3', 'x']) {
        test('rejects invalid offset $offset', () {
          final fixture = _registry(kind);
          expect(
            () => fixture.read(_rewrite(fixture.cursor, offset: offset)),
            throwsA(
              isA<McpException>().having(
                (error) => error.code,
                'code',
                McpErrorCodes.invalidParams,
              ),
            ),
          );
        });
      }
      for (final shape in ['wrong namespace', 'extra field']) {
        test('rejects $shape despite valid revision and offset', () {
          final fixture = _registry(kind);
          final decoded = utf8.decode(
            base64Url.decode(base64Url.normalize(fixture.cursor)),
          );
          final forged = shape == 'wrong namespace'
              ? '!${decoded.substring(1)}'
              : '$decoded:extra';
          expect(
            () => fixture.read(base64Url.encode(utf8.encode(forged))),
            throwsA(
              isA<McpException>().having(
                (error) => error.code,
                'code',
                McpErrorCodes.invalidParams,
              ),
            ),
          );
        });
      }
      test('returned pages reject growth without altering the registry', () {
        final fixture = _registry(kind);
        final page = fixture.read(null);
        expect(() => page.add(fixture.second), throwsUnsupportedError);
        expect(() => page[0] = fixture.second, throwsUnsupportedError);
        expect(fixture.read(null).single, same(fixture.first));
      });
    });
  }

  test('zero-length resources and links retain their explicit size', () {
    final resource = expectValid(
      () => McpResource(
        uri: 'app:///empty',
        name: 'empty',
        size: 0,
        read: (_) => [],
      ),
    );
    final link = expectValid(
      () => McpResourceLinkContent(
        uri: 'app:///empty',
        name: 'empty',
        size: 0,
      ),
    );
    expect(resource.toJson()['size'], 0);
    expect(link.toJson()['size'], 0);
  });

  for (final (annotations, expected)
      in <(McpResourceAnnotations, Map<String, Object?>)>[
        (const McpResourceAnnotations(), {}),
        (const McpResourceAnnotations(priority: 0), {'priority': 0.0}),
        (const McpResourceAnnotations(priority: 1), {'priority': 1.0}),
        (
          const McpResourceAnnotations(audience: ['user']),
          {
            'audience': ['user'],
          },
        ),
        (
          McpResourceAnnotations(lastModified: DateTime.utc(2026)),
          {
            'lastModified': '2026-01-01T00:00:00.000Z',
          },
        ),
      ]) {
    test('resource annotations preserve isolated fields $expected', () {
      expect(annotations.isEmpty, expected.isEmpty);
      expect(expectValid(annotations.toJson), expected);
      final json = McpResource(
        uri: 'app:///resource',
        name: 'resource',
        annotations: annotations,
        read: (_) => [],
      ).toJson();
      if (expected.isEmpty) {
        expect(json, isNot(contains('annotations')));
      } else {
        expect(json['annotations'], expected);
      }
    });
  }

  test('unrelated readable URI template is never selected', () async {
    var invoked = false;
    final registry = McpResourceRegistry(
      templates: [
        McpResourceTemplate(
          uriTemplate: 'app:///items/{id}',
          name: 'items',
          read: (_, _) {
            invoked = true;
            return [];
          },
        ),
      ],
    );
    expect(registry.matchReadableTemplate('app:///users/1'), isNull);
    await expectLater(
      registry.read(const McpResourceRequest(uri: 'app:///users/1')),
      throwsA(
        isA<McpException>().having(
          (error) => error.code,
          'code',
          McpErrorCodes.resourceNotFound,
        ),
      ),
    );
    expect(invoked, isFalse);
  });
}

String _cursor(String? value) {
  expect(value, isA<String>(), reason: 'A non-final page must offer a cursor');
  return value!;
}

String _rewrite(String cursor, {required String offset}) {
  final decoded = utf8.decode(base64Url.decode(base64Url.normalize(cursor)));
  return base64Url.encode(
    utf8.encode('${decoded.substring(0, decoded.lastIndexOf(':') + 1)}$offset'),
  );
}

({
  String cursor,
  List<dynamic> Function(String?) read,
  String? Function(String?) next,
  Object first,
  Object second,
})
_registry(String kind) {
  switch (kind) {
    case 'tools':
      final first = McpTool(name: 'a', handler: (_) => McpToolResult.text('a'));
      final second = McpTool(
        name: 'b',
        handler: (_) => McpToolResult.text('b'),
      );
      final registry = McpToolRegistry([first, second], 1);
      return (
        cursor: _cursor(registry.listPage().nextCursor),
        read: (cursor) => registry.listPage(cursor: cursor).tools,
        next: (cursor) => registry.listPage(cursor: cursor).nextCursor,
        first: first,
        second: second,
      );
    case 'prompts':
      final first = McpPrompt(
        name: 'a',
        handler: (_) => McpPromptResult.text('a'),
      );
      final second = McpPrompt(
        name: 'b',
        handler: (_) => McpPromptResult.text('b'),
      );
      final registry = McpPromptRegistry([first, second], 1);
      return (
        cursor: _cursor(registry.listPage().nextCursor),
        read: (cursor) => registry.listPage(cursor: cursor).prompts,
        next: (cursor) => registry.listPage(cursor: cursor).nextCursor,
        first: first,
        second: second,
      );
    case 'resources':
      final first = McpResource(uri: 'app:///a', name: 'a', read: (_) => []);
      final second = McpResource(uri: 'app:///b', name: 'b', read: (_) => []);
      final registry = McpResourceRegistry(
        resources: [first, second],
        pageSize: 1,
      );
      return (
        cursor: _cursor(registry.listPage().nextCursor),
        read: (cursor) => registry.listPage(cursor: cursor).resources,
        next: (cursor) => registry.listPage(cursor: cursor).nextCursor,
        first: first,
        second: second,
      );
    case 'templates':
      final first = McpResourceTemplate(
        uriTemplate: 'app:///a/{id}',
        name: 'a',
      );
      final second = McpResourceTemplate(
        uriTemplate: 'app:///b/{id}',
        name: 'b',
      );
      final registry = McpResourceRegistry(
        templates: [first, second],
        templatePageSize: 1,
      );
      return (
        cursor: _cursor(registry.listTemplatePage().nextCursor),
        read: (cursor) => registry.listTemplatePage(cursor: cursor).templates,
        next: (cursor) => registry.listTemplatePage(cursor: cursor).nextCursor,
        first: first,
        second: second,
      );
    default:
      throw ArgumentError.value(kind);
  }
}
