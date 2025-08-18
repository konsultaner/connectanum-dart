import 'dart:async';
import 'package:web/web.dart';

class NetworkConnectivity {
  static final NetworkConnectivity instance = NetworkConnectivity._internal();
  NetworkConnectivity._internal();

  Future<bool> isOnline({String? testAddress}) async {
    // Browser-provided online status
    try {
      return window.navigator.onLine ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> waitUntilOnline({
    Duration pollInterval = const Duration(seconds: 2),
    Duration? timeout,
    String? testAddress,
  }) async {
    // If already online, return immediately
    if (await isOnline()) return;

    final completer = Completer<void>();
    void onlineListener(Event _) {
      if (!completer.isCompleted) completer.complete();
      window.removeEventListener('online', onlineListener);
      window.removeEventListener('offline', offlineListener);
    }

    void offlineListener(Event _) {
      // no-op, but keep symmetry and potential future logging
    }

    window.addEventListener('online', onlineListener);
    window.addEventListener('offline', offlineListener);

    Timer? timeoutTimer;
    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
        window.removeEventListener('online', onlineListener);
        window.removeEventListener('offline', offlineListener);
      });
    }

    await completer.future;
    timeoutTimer?.cancel();
  }
}
