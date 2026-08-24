import 'package:flutter/foundation.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../infrastructure/wamp_account_gateway.dart';

enum WampAppStatus { signedOut, busy, connected, failed }

class WampAppController extends ChangeNotifier {
  WampAppController({AccountGateway? gateway})
    : _gateway = gateway ?? const WampAccountGateway();

  final AccountGateway _gateway;
  WampAppStatus _status = WampAppStatus.signedOut;
  AccountConnection? _connection;
  Object? _error;

  WampAppStatus get status => _status;
  bool get isBusy => _status == WampAppStatus.busy;
  AccountConnection? get connection => _connection;
  String? get errorMessage => switch (_error) {
    FormatException(:final message) => message,
    _ when _error != null =>
      'Could not connect. Check the address and credentials.',
    _ => null,
  };

  Future<void> registerAndConnect({
    required String serverAddress,
    required String username,
    required String displayName,
    required String password,
  }) async {
    await _run(() async {
      final endpoint = ServerEndpoint.parse(serverAddress);
      endpoint.requireSecureRegistration();
      final registration = AccountRegistration(
        username: username,
        password: password,
        displayName: displayName,
      );
      registration.validate();
      await _gateway.register(endpoint: endpoint, registration: registration);
      return _gateway.login(
        endpoint: endpoint,
        username: registration.username,
        password: password,
      );
    });
  }

  Future<void> login({
    required String serverAddress,
    required String username,
    required String password,
  }) async {
    await _run(() {
      final endpoint = ServerEndpoint.parse(serverAddress);
      endpoint.requireSecureRegistration();
      return _gateway.login(
        endpoint: endpoint,
        username: username,
        password: password,
      );
    });
  }

  Future<void> signOut() async {
    final connection = _connection;
    _connection = null;
    _error = null;
    _status = WampAppStatus.signedOut;
    notifyListeners();
    await connection?.close();
  }

  Future<void> _run(Future<AccountConnection> Function() action) async {
    if (isBusy) return;
    _error = null;
    _status = WampAppStatus.busy;
    notifyListeners();
    late final AccountConnection next;
    try {
      next = await action();
    } catch (error) {
      _error = error;
      _status = WampAppStatus.failed;
      notifyListeners();
      return;
    }

    final previous = _connection;
    _connection = next;
    _status = WampAppStatus.connected;
    notifyListeners();
    try {
      await previous?.close();
    } catch (_) {
      // The replacement connection remains valid even if stale cleanup fails.
    }
  }

  @override
  void dispose() {
    final connection = _connection;
    _connection = null;
    connection?.close();
    super.dispose();
  }
}
