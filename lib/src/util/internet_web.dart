import 'package:web/web.dart';

Future<bool> hasInternet({
  Duration timeout = const Duration(seconds: 5),
  String lookupAddress = 'example.com',
}) async {
  try {
    return window.navigator.onLine;
  } catch (_) {
    return false;
  }
}
