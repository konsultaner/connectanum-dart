import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';

Future<void> main(List<String> args) async {
  final output = File(args[1]);
  if (output.existsSync()) {
    throw StateError('Child coverage output already exists');
  }
  final report = await collect(
    Uri.parse(args[0]),
    true,
    true,
    false,
    {'connectanum_bench'},
    timeout: const Duration(seconds: 10),
  );
  await writeChildCoverageReport(output, report);
}

Future<void> writeChildCoverageReport(File output, Object report) async {
  // Exclusive creation prevents competing collectors from replacing evidence.
  await output.create(exclusive: true);
  await output.writeAsString(jsonEncode(report), flush: true);
}
