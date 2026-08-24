import 'package:shared_preferences/shared_preferences.dart';

abstract interface class VaultStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class SharedPreferencesVaultStorage implements VaultStorage {
  Future<SharedPreferences>? _preferences;

  Future<SharedPreferences> get _instance =>
      _preferences ??= SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _instance).getString(key);

  @override
  Future<void> write(String key, String value) async {
    if (!await (await _instance).setString(key, value)) {
      throw StateError('Encrypted device storage rejected the write.');
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!await (await _instance).remove(key)) {
      throw StateError('Encrypted device storage rejected the delete.');
    }
  }
}
