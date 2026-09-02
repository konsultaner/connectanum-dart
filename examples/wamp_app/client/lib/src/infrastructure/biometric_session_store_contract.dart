import 'dart:convert';

final class RememberedLogin {
  RememberedLogin({
    required this.serverAddress,
    required this.username,
    required String password,
  }) {
    _password = password;
    _validate();
  }

  static const maxServerAddressLength = 2048;
  static const maxUsernameLength = 200;
  static const maxPasswordLength = 4096;

  final String serverAddress;
  final String username;
  String _password = '';

  String get password => _password;

  Map<String, String> toJson() => {
    'server_address': serverAddress,
    'username': username,
    'password': _password,
  };

  factory RememberedLogin.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('The saved biometric sign-in is invalid.');
    }
    final serverAddress = value['server_address'];
    final username = value['username'];
    final password = value['password'];
    if (serverAddress is! String ||
        username is! String ||
        password is! String) {
      throw const FormatException('The saved biometric sign-in is invalid.');
    }
    return RememberedLogin(
      serverAddress: serverAddress,
      username: username,
      password: password,
    );
  }

  static RememberedLogin decode(String value) {
    try {
      return RememberedLogin.fromJson(jsonDecode(value));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('The saved biometric sign-in is invalid.');
    }
  }

  String encode() => jsonEncode(toJson());

  void dispose() {
    _password = '';
  }

  void _validate() {
    if (serverAddress.trim().isEmpty ||
        serverAddress.length > maxServerAddressLength ||
        username.trim().isEmpty ||
        username.length > maxUsernameLength ||
        _password.isEmpty ||
        _password.length > maxPasswordLength) {
      throw const FormatException('The biometric sign-in values are invalid.');
    }
  }
}

abstract interface class BiometricSessionStore {
  Future<bool> isAvailable();

  Future<bool> hasLogin();

  Future<bool> save({
    required RememberedLogin login,
    required String localizedReason,
  });

  Future<RememberedLogin?> unlock({required String localizedReason});

  Future<void> clear();
}
