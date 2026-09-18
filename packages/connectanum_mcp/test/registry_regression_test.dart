import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

import 'support/expect_valid.dart';

McpTool _tool(String name) => McpTool(
  name: name,
  handler: (_) => McpToolResult.text(name),
);

McpPrompt _prompt(String name) => McpPrompt(
  name: name,
  handler: (_) => McpPromptResult.text(name),
);

McpResource _resource(String name) => McpResource(
  uri: 'app:///$name',
  name: name,
  read: (request) => [McpTextResourceContent(uri: request.uri, text: name)],
);

McpResourceTemplate _template(String name) => McpResourceTemplate(
  uriTemplate: 'app:///$name/{id}',
  name: name,
  read: (request, variables) => [
    McpTextResourceContent(uri: request.uri, text: variables['id']!),
  ],
);

final _invalidCursor = throwsA(
  isA<McpException>().having(
    (error) => error.code,
    'code',
    McpErrorCodes.invalidParams,
  ),
);

void main() {
  for (final reverse in [false, true]) {
    test(
      'unrelated specific templates cannot hide a readable match, reverse=$reverse',
      () async {
        final reads = <Map<String, String>>[];
        final matching = McpResourceTemplate(
          uriTemplate: 'app:///item/{id}',
          name: 'matching',
          read: (request, variables) {
            reads.add(variables);
            return [
              McpTextResourceContent(uri: request.uri, text: variables['id']!),
            ];
          },
        );
        final candidates = [
          matching,
          McpResourceTemplate(
            uriTemplate: 'app:///unrelated/more/specific/{id}',
            name: 'unrelated',
            read: (_, _) => fail('An unrelated resource must not be read'),
          ),
          McpResourceTemplate(
            uriTemplate: 'app:///item/A%20B',
            name: 'not readable',
          ),
        ];
        final registry = McpResourceRegistry(
          templates: reverse ? candidates.reversed : candidates,
        );
        final match = registry.matchReadableTemplate('app:///item/A%20B');
        expect(match, isNotNull);
        expect(match!.template, same(matching));
        expect(match.variables, {'id': 'A B'});
        expect(reads, isEmpty);
        final content = await registry.read(
          const McpResourceRequest(uri: 'app:///item/A%20B'),
        );
        expect(content, hasLength(1));
        expect(content.single.toJson(), {
          'uri': 'app:///item/A%20B',
          'text': 'A B',
        });
        expect(reads, [
          {'id': 'A B'},
        ]);
      },
    );
  }

  test(
    'template ties use lexical order independently of registration order',
    () async {
      final candidates = [
        McpResourceTemplate(
          uriTemplate: 'app:///{id}/fixed',
          name: 'first variable',
          read: (request, _) => [
            McpTextResourceContent(uri: request.uri, text: 'first'),
          ],
        ),
        McpResourceTemplate(
          uriTemplate: 'app:///fixed/{id}',
          name: 'second variable',
          read: (request, _) => [
            McpTextResourceContent(uri: request.uri, text: 'second'),
          ],
        ),
      ];
      for (final templates in [candidates, candidates.reversed]) {
        final registry = expectValid(
          () => McpResourceRegistry(templates: templates),
        );
        final match = expectValid(
          () => registry.matchReadableTemplate('app:///fixed/fixed'),
        );
        expect(match, isNotNull);
        expect(match!.template, same(candidates[1]));
        expect(match.variables, {'id': 'fixed'});
        final content = await registry.read(
          const McpResourceRequest(uri: 'app:///fixed/fixed'),
        );
        expect(content.single.toJson(), {
          'uri': 'app:///fixed/fixed',
          'text': 'second',
        });
      }
    },
  );

  for (final size in [0, -1]) {
    test('rejects invalid page size $size in every registry', () {
      expect(() => McpToolRegistry([], size), throwsArgumentError);
      expect(() => McpPromptRegistry([], size), throwsArgumentError);
      expect(() => McpResourceRegistry(pageSize: size), throwsArgumentError);
      expect(
        () => McpResourceRegistry(templatePageSize: size),
        throwsArgumentError,
      );
    });
  }

  test('tool replacement invalidates cursors and removes stale handlers', () {
    final registry = McpToolRegistry([_tool('z'), _tool('a')], 1);
    final page = registry.listPage();
    expect(page.tools.single.name, 'a');
    expect(() => page.tools.clear(), throwsUnsupportedError);
    expect(registry.list(cursor: page.nextCursor).single.name, 'z');
    expect(() => registry.register(_tool('z')), throwsArgumentError);
    final replacement = _tool('new');
    registry.replaceAll([replacement]);
    expect(registry['z'], isNull);
    expect(registry['new'], same(replacement));
    expect(registry.listPage().nextCursor, isNull);
    expect(() => registry.list(cursor: page.nextCursor), _invalidCursor);
    registry.replaceAll([]);
    expect(registry.isNotEmpty, isFalse);
    expect(registry.list(), isEmpty);
  });

  test('prompt replacement invalidates cursors and removes stale handlers', () {
    final registry = McpPromptRegistry([_prompt('z'), _prompt('a')], 1);
    final page = registry.listPage();
    expect(page.prompts.single.name, 'a');
    expect(registry.list(cursor: page.nextCursor).single.name, 'z');
    expect(() => registry.register(_prompt('z')), throwsArgumentError);
    final replacement = _prompt('new');
    registry.replaceAll([replacement]);
    expect(registry['z'], isNull);
    expect(registry['new'], same(replacement));
    expect(registry.listPage().nextCursor, isNull);
    expect(() => registry.list(cursor: page.nextCursor), _invalidCursor);
    registry.replaceAll([]);
    expect(registry.isNotEmpty, isFalse);
    expect(registry.list(), isEmpty);
  });

  test(
    'unpaginated registries reject cursors rather than silently ignoring them',
    () {
      expect(() => McpToolRegistry().list(cursor: 'bad'), _invalidCursor);
      expect(() => McpPromptRegistry().list(cursor: 'bad'), _invalidCursor);
      expect(
        () => McpResourceRegistry().listPage(cursor: 'bad'),
        _invalidCursor,
      );
      expect(
        () => McpResourceRegistry().listTemplatePage(cursor: 'bad'),
        _invalidCursor,
      );
    },
  );

  test(
    'resource and template replacement preserve the other collection',
    () async {
      final concrete = _resource('z');
      final template = _template('users');
      final registry = McpResourceRegistry(
        resources: [concrete, _resource('a')],
        templates: [template, _template('articles')],
        pageSize: 1,
        templatePageSize: 1,
      );
      final resourceCursor = registry.listPage().nextCursor!;
      final templateCursor = registry.listTemplatePage().nextCursor!;
      expect(() => registry.register(concrete), throwsArgumentError);
      expect(() => registry.registerTemplate(template), throwsArgumentError);
      registry.replaceAll([_resource('replacement')]);
      expect(registry[concrete.uri], isNull);
      expect(registry.template(template.uriTemplate), same(template));
      expect(() => registry.listPage(cursor: resourceCursor), _invalidCursor);
      expect(
        () => registry.listTemplatePage(cursor: templateCursor),
        _invalidCursor,
      );
      registry.replaceTemplates([_template('new')]);
      expect(registry['app:///replacement'], isNotNull);
      expect(registry.template(template.uriTemplate), isNull);
      final match = registry.matchReadableTemplate('app:///new/42');
      expect(match, isNotNull);
      expect(match!.variables, {'id': '42'});
      final contents = await registry.read(
        const McpResourceRequest(uri: 'app:///new/42'),
      );
      expect(contents.single.toJson(), {'uri': 'app:///new/42', 'text': '42'});
      registry.replaceAll([]);
      expect(registry.isNotEmpty, isTrue);
      registry.replaceTemplates([]);
      expect(registry.isNotEmpty, isFalse);
      expect(registry.listPage().resources, isEmpty);
      expect(registry.listTemplatePage().templates, isEmpty);
    },
  );

  test('template resolution ignores descriptions without a reader', () async {
    final registry = McpResourceRegistry(
      templates: [
        McpResourceTemplate(uriTemplate: 'app:///users/42', name: 'advertised'),
        _template('users'),
      ],
    );
    final contents = await registry.read(
      const McpResourceRequest(uri: 'app:///users/42'),
    );
    expect(contents.single.toJson(), {'uri': 'app:///users/42', 'text': '42'});
  });

  test('resource constructors reject unusable public metadata', () {
    for (final uri in ['', 'relative', 'http://[']) {
      expect(
        () => McpResource(uri: uri, name: 'valid', read: (_) => []),
        throwsArgumentError,
      );
    }
    expect(
      () => McpResource(uri: 'app:///ok', name: '', read: (_) => []),
      throwsArgumentError,
    );
    expect(
      () =>
          McpResource(uri: 'app:///ok', name: 'ok', size: -1, read: (_) => []),
      throwsArgumentError,
    );
    expect(
      () => McpResourceTemplate(uriTemplate: 'app:///{id}', name: ''),
      throwsArgumentError,
    );
    for (final priority in [-0.01, 1.01]) {
      expect(
        () => McpResourceAnnotations(priority: priority).toJson(),
        throwsArgumentError,
      );
    }
    for (final priority in [0.0, 1.0]) {
      expect(McpResourceAnnotations(priority: priority).toJson(), {
        'priority': priority,
      });
    }
  });

  test('template annotations and URI variables round trip', () {
    final template = McpResourceTemplate(
      uriTemplate: 'app:///users/{id}',
      name: 'users',
      annotations: const McpResourceAnnotations(priority: 1),
    );
    expect(template.variables, ['id']);
    expect(template.expandUri({'id': 'a b'}), 'app:///users/a%20b');
    expect(template.toJson()['annotations'], {'priority': 1});
  });
}
