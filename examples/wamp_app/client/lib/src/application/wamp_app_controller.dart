import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../infrastructure/device_vault.dart';
import '../infrastructure/wamp_account_gateway.dart';

enum WampAppStatus { signedOut, busy, connected, failed }

class WampAppController extends ChangeNotifier {
  WampAppController({
    AccountGateway? gateway,
    DeviceTrustStore? trustStore,
    this.deviceName = 'This device',
  }) : _gateway = gateway ?? const WampAccountGateway(),
       _trustStore = trustStore ?? EncryptedDeviceVault();

  final AccountGateway _gateway;
  final DeviceTrustStore _trustStore;
  final String deviceName;
  WampAppStatus _status = WampAppStatus.signedOut;
  AccountConnection? _connection;
  DeviceTrustSession? _trustSession;
  DeviceRecord? _localDevice;
  Object? _error;
  int _operationGeneration = 0;
  bool _disposed = false;

  WampAppStatus get status => _status;
  bool get isBusy => _status == WampAppStatus.busy;
  AccountConnection? get connection => _connection;
  DeviceRecord? get localDevice => _localDevice;
  String? get safetyNumber => _trustSession?.safetyNumber;
  String? get errorMessage => switch (_error) {
    FormatException(:final message) => message,
    VaultUnlockException() => 'Could not unlock encrypted device storage.',
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
    await _run(password: password, () async {
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
    await _run(password: password, () {
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
    _operationGeneration += 1;
    final connection = _connection;
    final trustSession = _trustSession;
    _connection = null;
    _trustSession = null;
    _localDevice = null;
    _error = null;
    _status = WampAppStatus.signedOut;
    if (!_disposed) notifyListeners();
    await _closeState(connection, trustSession);
  }

  Future<void> _run(
    Future<AccountConnection> Function() action, {
    required String password,
  }) async {
    if (_disposed || isBusy) return;
    final generation = ++_operationGeneration;
    _error = null;
    _status = WampAppStatus.busy;
    notifyListeners();
    AccountConnection? next;
    DeviceTrustSession? nextTrust;
    DeviceRecord? nextDevice;
    try {
      next = await action();
      nextTrust = await _trustStore.openOrCreate(
        endpoint: next.endpoint,
        username: next.username,
        password: password,
        deviceName: deviceName,
      );
      nextDevice = await next.enrollDevice(nextTrust.enrollment);
      if (nextDevice.isRevoked ||
          nextDevice.username != next.username ||
          nextDevice.deviceId != nextTrust.deviceId) {
        throw const FormatException(
          'The server returned an invalid local device record.',
        );
      }
    } catch (error) {
      try {
        await _closeState(next, nextTrust);
      } catch (_) {
        // Preserve the connection or trust failure that triggered cleanup.
      }
      if (generation != _operationGeneration || _disposed) return;
      _error = error;
      _status = _connection != null && _trustSession != null
          ? WampAppStatus.connected
          : WampAppStatus.failed;
      notifyListeners();
      return;
    }

    if (generation != _operationGeneration || _disposed) {
      await _closeState(next, nextTrust);
      return;
    }

    final previous = _connection;
    final previousTrust = _trustSession;
    _connection = next;
    _trustSession = nextTrust;
    _localDevice = nextDevice;
    _status = WampAppStatus.connected;
    notifyListeners();
    try {
      await _closeState(previous, previousTrust);
    } catch (_) {
      // The replacement connection remains valid even if stale cleanup fails.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration += 1;
    final connection = _connection;
    final trustSession = _trustSession;
    _connection = null;
    _trustSession = null;
    _localDevice = null;
    unawaited(_closeState(connection, trustSession).catchError((_) {}));
    super.dispose();
  }
}

Future<void> _closeState(
  AccountConnection? connection,
  DeviceTrustSession? trustSession,
) async {
  Object? failure;
  StackTrace? failureStack;
  try {
    await connection?.close();
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }
  try {
    await trustSession?.dispose();
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
}
