import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'biometric_session_store_contract.dart';

BiometricSessionStore createPlatformBiometricSessionStore() =>
    NativeBiometricSessionStore();

final class NativeBiometricSessionStore implements BiometricSessionStore {
  NativeBiometricSessionStore({
    LocalAuthentication? authentication,
    FlutterSecureStorage? storage,
  }) : _authentication = authentication ?? LocalAuthentication(),
       _storage =
           storage ??
           const FlutterSecureStorage(
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.unlocked_this_device,
             ),
           );

  static const _storageKey = 'wamp_app.biometric_login.v1';

  final LocalAuthentication _authentication;
  final FlutterSecureStorage _storage;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _authentication.isDeviceSupported()) return false;
      if (!await _authentication.canCheckBiometrics) return false;
      return (await _authentication.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasLogin() async {
    try {
      return await _storage.containsKey(key: _storageKey);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> save({
    required RememberedLogin login,
    required String localizedReason,
  }) async {
    if (!await _authenticate(localizedReason)) return false;
    await _storage.write(key: _storageKey, value: login.encode());
    return true;
  }

  @override
  Future<RememberedLogin?> unlock({required String localizedReason}) async {
    if (!await _authenticate(localizedReason)) return null;
    final encoded = await _storage.read(key: _storageKey);
    if (encoded == null) return null;
    try {
      return RememberedLogin.decode(encoded);
    } catch (_) {
      await clear();
      rethrow;
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: _storageKey);

  Future<bool> _authenticate(String localizedReason) async {
    if (!await isAvailable()) return false;
    return _authentication.authenticate(
      localizedReason: localizedReason,
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
  }
}
