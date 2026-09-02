import 'biometric_session_store_contract.dart';

BiometricSessionStore createPlatformBiometricSessionStore() =>
    const UnsupportedBiometricSessionStore();

final class UnsupportedBiometricSessionStore implements BiometricSessionStore {
  const UnsupportedBiometricSessionStore();

  @override
  Future<void> clear() async {}

  @override
  Future<bool> hasLogin() async => false;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> save({
    required RememberedLogin login,
    required String localizedReason,
  }) async => false;

  @override
  Future<RememberedLogin?> unlock({required String localizedReason}) async =>
      null;
}
