import 'dart:async';
import 'dart:io';

class NetworkConnectivity {
  static final NetworkConnectivity instance = NetworkConnectivity._internal();
  NetworkConnectivity._internal();

  static const Duration _defaultTimeout = Duration(seconds: 2);

  Future<bool> isOnline({String? testAddress}) async {
    final target = testAddress ?? 'example.com:80';
    String host = target;
    int port = 80;
    try {
      if (target.contains(':')) {
        final lastColon = target.lastIndexOf(':');
        host = target.substring(0, lastColon);
        port = int.tryParse(target.substring(lastColon + 1)) ?? 80;
      }
      final socket = await Socket.connect(host, port, timeout: _defaultTimeout);
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> waitUntilOnline({
    Duration pollInterval = const Duration(seconds: 2),
    Duration? timeout,
    String? testAddress,
  }) async {
    if (await isOnline(testAddress: testAddress)) return;

    final Completer<void> completer = Completer<void>();
    final DateTime? deadline =
        timeout != null ? DateTime.now().add(timeout) : null;

    Timer? ticker;

    ticker = Timer.periodic(pollInterval, (t) async {
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        if (!completer.isCompleted) completer.complete();
        t.cancel();
        return;
      }
      final online = await isOnline(testAddress: testAddress);
      if (online) {
        if (!completer.isCompleted) completer.complete();
        t.cancel();
      }
    });

    if (deadline != null) {
      Timer(timeout!, () {
        if (!completer.isCompleted) completer.complete();
        ticker?.cancel();
      });
    }

    await completer.future;
  }
}
