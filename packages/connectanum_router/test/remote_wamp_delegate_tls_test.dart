@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test(
    'custom remote-auth CA replaces rather than extends default roots',
    () async {
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_router/connectanum_router.dart'),
      );
      final packageConfig = await Isolate.packageConfig;
      final testDirectory = source!.resolve('../test/');
      final fixtures = testDirectory.resolve('certs/').toFilePath();
      final child = await Process.start(Platform.resolvedExecutable, [
        '--root-certs-file=${fixtures}http3_ca_cert.pem',
        '--packages=${packageConfig!.toFilePath()}',
        testDirectory
            .resolve('support/remote_tls_trust_probe.dart')
            .toFilePath(),
        fixtures,
      ]);
      addTearDown(() async {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
      });
      final output = utf8.decoder.bind(child.stdout).join();
      final errors = utf8.decoder.bind(child.stderr).join();
      final exitCode = await child.exitCode.timeout(
        const Duration(seconds: 20),
      );
      if (exitCode != 0) {
        throw StateError(
          'TLS probe process failed ($exitCode): ${await errors}',
        );
      }
      expect(await errors, isEmpty);
      expect(jsonDecode(await output), {
        'customCa=false,clientCertificate=false': [false, true],
        'customCa=false,clientCertificate=true': [false, true],
        'customCa=true,clientCertificate=false': [true, false],
        'customCa=true,clientCertificate=true': [true, false],
      });
    },
  );
}
