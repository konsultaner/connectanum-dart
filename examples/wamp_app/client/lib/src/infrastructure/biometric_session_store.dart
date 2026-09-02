import 'biometric_session_store_contract.dart';
import 'biometric_session_store_stub.dart'
    if (dart.library.io) 'biometric_session_store_native.dart';

export 'biometric_session_store_contract.dart';

BiometricSessionStore createBiometricSessionStore() =>
    createPlatformBiometricSessionStore();
