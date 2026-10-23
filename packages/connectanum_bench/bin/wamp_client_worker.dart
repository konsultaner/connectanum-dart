import 'dart:developer' as developer;
import 'dart:io';

import '../tool/wamp_client_main.dart' as wamp_client_main;

Future<void> main(List<String> args) async {
  final profileWorkerUriPath =
      Platform.environment['CONNECTANUM_BENCH_PROFILE_WORKER_URI'];
  if (profileWorkerUriPath != null && profileWorkerUriPath.isNotEmpty) {
    final serviceUri = (await developer.Service.getInfo()).serverUri;
    if (serviceUri == null) {
      throw StateError(
        'Dart VM service URI is unavailable to the profile worker',
      );
    }
    File(profileWorkerUriPath).writeAsStringSync(serviceUri.toString());
  }
  await wamp_client_main.main(args);
}
