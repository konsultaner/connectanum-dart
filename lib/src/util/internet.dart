import 'dart:async';

import 'internet_stub.dart'
    if (dart.library.io) 'internet_io.dart'
    if (dart.library.js_interop) 'internet_web.dart';
export 'internet_stub.dart'
    if (dart.library.io) 'internet_io.dart'
    if (dart.library.js_interop) 'internet_web.dart';

Future<bool> waitForInternetConnection({
  Duration interval = const Duration(seconds: 5),
  int maxTries = -1,
  bool Function()? abortCheck,
  String lookupAddress = 'example.com',
  Future<bool> Function({Duration timeout, String lookupAddress}) checkInternet = hasInternet,
}) async {
  var attempts = 0;
  while (true) {
    if (abortCheck != null && abortCheck()) return false;
    if (await checkInternet(timeout: interval, lookupAddress: lookupAddress)) {
      return true;
    }
    attempts++;
    if (maxTries > 0 && attempts >= maxTries) {
      return false;
    }
    await Future.delayed(interval);
  }
}
