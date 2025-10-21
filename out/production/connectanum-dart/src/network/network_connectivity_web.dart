import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart';

class NetworkConnectivity {
  static final NetworkConnectivity instance = NetworkConnectivity._internal();
  NetworkConnectivity._internal();

  Future<bool> isOnline({String? testAddress}) async {
    try {
      return window.navigator.onLine;
    } catch (_) {
      return true;
    }
  }

  /// Stream of online state for the web. Emits immediately, then updates on browser events.
  Stream<bool> watch({
    Duration interval = const Duration(seconds: 2), // unused on web
    String? testAddress,
  }) {
    final controller = StreamController<bool>.broadcast();
    int listenerCount = 0;

    EventListener? onlineListener;
    EventListener? offlineListener;

    void addListeners() {
      if (onlineListener != null) return;
      onlineListener =
          (((Event _) {
                if (!controller.isClosed) controller.add(true);
              }).toJS)
              as EventListener;
      offlineListener =
          (((Event _) {
                if (!controller.isClosed) controller.add(false);
              }).toJS)
              as EventListener;
      window.addEventListener('online', onlineListener);
      window.addEventListener('offline', offlineListener);
    }

    void removeListeners() {
      if (onlineListener != null) {
        window.removeEventListener('online', onlineListener);
        onlineListener = null;
      }
      if (offlineListener != null) {
        window.removeEventListener('offline', offlineListener);
        offlineListener = null;
      }
    }

    controller.onListen = () {
      listenerCount++;
      // emit current state immediately
      () async {
        try {
          final online = await isOnline();
          if (!controller.isClosed) controller.add(online);
        } catch (_) {
          if (!controller.isClosed) controller.add(true);
        }
      }();
      addListeners();
    };

    controller.onCancel = () {
      listenerCount--;
      if (listenerCount <= 0) {
        removeListeners();
      }
    };

    return controller.stream;
  }

  Future<void> waitUntilOnline({
    Duration pollInterval = const Duration(seconds: 2),
    Duration? timeout,
    String? testAddress,
  }) async {
    if (await isOnline()) return;

    final completer = Completer<void>();

    EventListener? onlineListener;
    EventListener? offlineListener;

    onlineListener =
        (((Event _) {
              if (!completer.isCompleted) completer.complete();
              window.removeEventListener('online', onlineListener);
              window.removeEventListener('offline', offlineListener);
            }).toJS)
            as EventListener;

    offlineListener =
        (((Event _) {
              // no-op, but keep symmetry and potential future logging
            }).toJS)
            as EventListener;

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
