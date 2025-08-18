import 'dart:async';

/// Fallback connectivity for platforms where neither web nor io is available.
/// Always assumes online to avoid blocking behavior.
class NetworkConnectivity {
  static final NetworkConnectivity instance = NetworkConnectivity._internal();
  NetworkConnectivity._internal();

  Future<bool> isOnline({String? testAddress}) async => true;

  Future<void> waitUntilOnline({
    Duration pollInterval = const Duration(seconds: 2),
    Duration? timeout,
    String? testAddress,
  }) async {
    // Immediately resolve since we assume online.
    return;
  }
}
