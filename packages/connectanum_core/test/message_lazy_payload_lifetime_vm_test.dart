@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  for (final mode in [
    'control',
    'reanchor',
    'clear',
    'restore',
    'metadata',
    'unwrap',
    'yield',
    'error',
    'progress',
    'plain',
    'mutation',
    'resnapshot',
    'mutation-owned',
    'owned',
  ]) {
    test('actual GC preserves lazy storage lifetime: $mode', () async {
      final package = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_core/connectanum_core.dart'),
      );
      final root = File.fromUri(package!).parent.parent;
      final config = (await Isolate.packageConfig)!;
      final result = await Process.run(Platform.resolvedExecutable, [
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
        '--packages=${config.toFilePath()}',
        '${root.path}/test/support/lazy_payload_gc_probe.dart',
        mode,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('ANCHOR_GC_OK $mode'));
    }, timeout: const Timeout(Duration(seconds: 45)));
  }
}
