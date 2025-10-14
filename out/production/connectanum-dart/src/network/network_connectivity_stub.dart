import 'dart:async';

/// Fallback connectivity for platforms where neither web nor io is available.
/// Always assumes online to avoid blocking behavior.
class NetworkConnectivity {
  static final NetworkConnectivity instance = NetworkConnectivity._internal();
  NetworkConnectivity._internal();

  Future<bool> isOnline({String? testAddress}) async => true;

  /// Stream of online state; on stub we emit `true` immediately and periodically.
  Stream<bool> watch({
    Duration interval = const Duration(seconds: 2),
    String? testAddress,
  }) {
    final controller = StreamController<bool>.broadcast();
    Timer? timer;

    void emit() {
      if (!controller.isClosed) controller.add(true);
    }

    controller.onListen = () {
      emit();
      timer = Timer.periodic(interval, (_) => emit());
    };
    controller.onCancel = () {
      if (!controller.hasListener) {
        timer?.cancel();
        timer = null;
      }
    };

    return controller.stream;
  }

  Future<void> waitUntilOnline({
    Duration pollInterval = const Duration(seconds: 2),
    Duration? timeout,
    String? testAddress,
  }) async {
    // Immediately resolve since we assume online.
    return;
  }
}
