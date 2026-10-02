@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/auth_server.dart' as cli;

void main() {
  for (final flag in ['--help', '-h']) {
    test('$flag prints usage without reading configuration', () async {
      final result = await _invoke([flag]);
      expect(result.code, 0);
      expect(result.out, contains('Usage: auth_server --config <path>'));
      expect(result.out, contains('--help'));
      expect(result.out, contains('--config'));
      expect(result.err, isEmpty);
    });
  }

  for (final args in <List<String>>[
    [],
    ['--unknown'],
    ['--config'],
    ['--no-help'],
  ]) {
    test('invalid arguments $args fail before reading configuration', () async {
      final result = await _invoke(args);
      expect(result.code, 64);
      expect(result.out, contains('Usage: auth_server --config <path>'));
      expect(result.err, isNotEmpty);
      if (args.isEmpty) {
        expect(result.err, 'Missing --config <path>\n');
      }
      expect(result.out, isNot(contains('Instance hash:')));
    });
  }

  for (final extension in ['json', 'YAML', 'yml']) {
    for (final flag in ['--config', '-c']) {
      test('$flag loads $extension and reports the actual realms', () async {
        final file = _InputFile(
          extension == 'json'
              ? jsonEncode({
                  'router': {
                    'realms': [
                      for (final name in ['alpha', 'beta'])
                        {
                          'name': name,
                          'auth': {
                            'authmethods': ['anonymous'],
                          },
                        },
                    ],
                  },
                })
              : 'router:\n  realms:\n'
                    '    - name: alpha\n      auth:\n        authmethods: [anonymous]\n'
                    '    - name: beta\n      auth:\n        authmethods: [anonymous]\n',
        );
        final path = '/virtual/config.$extension';
        final result = await _invoke([flag, path], file: file);
        expect(result.code, 0, reason: result.err);
        expect(result.err, isEmpty);
        expect(
          result.out,
          startsWith(
            'Loaded configuration from $path for realms: alpha, beta\n',
          ),
        );
        expect(
          result.out,
          contains(
            'AuthServer instance created (integration with router runtime pending).\n',
          ),
        );
        expect(result.out, matches(RegExp(r'Instance hash: \d+\.\n$')));
        expect(file.reads, 1);
      });
    }
  }

  for (final entry in <(String, String)>[
    ('json', '{'),
    ('yaml', 'router: ['),
    ('json', '[]'),
    ('txt', '{}'),
  ]) {
    test('invalid ${entry.$1} configuration fails closed', () async {
      final file = _InputFile(entry.$2);
      final result = await _invoke([
        '-c',
        '/virtual/config.${entry.$1}',
      ], file: file);
      expect(result.code, 65);
      expect(result.out, isEmpty);
      expect(result.err, startsWith('Failed to parse configuration: '));
      expect(file.reads, 1);
    });
  }

  test('missing file reports no-input without reading it', () async {
    final file = _InputFile('', exists: false);
    final result = await _invoke(['-c', '/virtual/missing.json'], file: file);
    expect(result.code, 66);
    expect(result.out, isEmpty);
    expect(
      result.err,
      'Unable to read configuration: Configuration file not found\n',
    );
    expect(file.reads, 0);
  });

  test('read failure is distinguished from configuration syntax', () async {
    final file = _InputFile(
      '',
      failure: const FileSystemException('read denied'),
    );
    final result = await _invoke(['-c', '/virtual/config.json'], file: file);
    expect(result.code, 66);
    expect(result.out, isEmpty);
    expect(result.err, 'Unable to read configuration: read denied\n');
    expect(file.reads, 1);
  });

  test(
    'unexpected read failure reports error and stack, never success',
    () async {
      final file = _InputFile('', failure: StateError('fixture failure'));
      final result = await _invoke(['-c', '/virtual/config.json'], file: file);
      expect(result.code, 1);
      expect(result.out, isEmpty);
      expect(
        result.err,
        contains('Unexpected error: Bad state: fixture failure'),
      );
      expect(result.err, contains('_InputFile.readAsString'));
      expect(file.reads, 1);
    },
  );
}

Future<({int code, String out, String err})> _invoke(
  List<String> args, {
  _InputFile? file,
}) async {
  final output = _CapturedStdout();
  final errors = _CapturedStdout();
  final requestedPaths = <String>[];
  final previousCode = exitCode;
  exitCode = 0;
  try {
    await IOOverrides.runZoned(
      () => cli.main(args),
      stdout: () => output,
      stderr: () => errors,
      createFile: (path) {
        requestedPaths.add(path);
        return file ?? _InputFile('', exists: false);
      },
    );
    expect(requestedPaths, file == null ? isEmpty : equals([args.last]));
    return (
      code: exitCode,
      out: output.text.toString(),
      err: errors.text.toString(),
    );
  } finally {
    exitCode = previousCode;
  }
}

class _CapturedStdout implements Stdout {
  final text = StringBuffer();

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InputFile implements File {
  _InputFile(this.contents, {bool exists = true, this.failure})
    : _exists = exists;

  final String contents;
  final bool _exists;
  final Object? failure;
  int reads = 0;

  @override
  Future<bool> exists() async => _exists;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    reads++;
    if (failure != null) throw failure!;
    return contents;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
