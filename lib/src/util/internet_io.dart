import 'dart:async';
import 'dart:io';

Future<bool> hasInternet({
  Duration timeout = const Duration(seconds: 5),
  String lookupAddress = 'example.com',
}) async {
  try {
    final result = await InternetAddress.lookup(lookupAddress).timeout(timeout);
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on SocketException catch (_) {
    return false;
  } on TimeoutException catch (_) {
    return false;
  }
}
