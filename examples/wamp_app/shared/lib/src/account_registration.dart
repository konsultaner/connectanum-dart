import 'protocol.dart';

class AccountRegistration {
  AccountRegistration({
    required String username,
    required this.password,
    required String displayName,
  }) : username = normalizeUsername(username),
       displayName = displayName.trim();

  final String username;
  final String password;
  final String displayName;

  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9_.-]{2,63}$');

  static String normalizeUsername(String value) => value.trim().toLowerCase();

  void validate() {
    if (!_usernamePattern.hasMatch(username)) {
      throw const FormatException(
        'Usernames need 3-64 lowercase letters, numbers, dots, dashes, or underscores.',
      );
    }
    if (displayName.isEmpty || displayName.length > 80) {
      throw const FormatException('Display names need 1-80 characters.');
    }
    if (password.length < 12 || password.length > 1024) {
      throw const FormatException('Passwords need 12-1024 characters.');
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'username': username,
      'password': password,
      'display_name': displayName,
    };
  }

  factory AccountRegistration.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Registration details are required.');
    }
    final username = value['username'];
    final password = value['password'];
    final displayName = value['display_name'];
    if (username is! String || password is! String || displayName is! String) {
      throw const FormatException('Registration fields must be strings.');
    }
    final registration = AccountRegistration(
      username: username,
      password: password,
      displayName: displayName,
    );
    registration.validate();
    return registration;
  }
}

class RegistrationReceipt {
  const RegistrationReceipt({
    required this.username,
    required this.displayName,
    required this.createdAt,
  });

  final String username;
  final String displayName;
  final DateTime createdAt;

  Map<String, dynamic> toWampKeywords() => {
    'username': username,
    'display_name': displayName,
    'created_at': createdAt.toUtc().toIso8601String(),
    'realm': WampAppProtocol.appRealm,
    'auth_method': 'scram',
  };

  factory RegistrationReceipt.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException(
        'The server returned no registration receipt.',
      );
    }
    final username = value['username'];
    final displayName = value['display_name'];
    final createdAt = DateTime.tryParse(value['created_at'] as String? ?? '');
    if (username is! String || displayName is! String || createdAt == null) {
      throw const FormatException(
        'The server returned an invalid registration receipt.',
      );
    }
    return RegistrationReceipt(
      username: username,
      displayName: displayName,
      createdAt: createdAt.toUtc(),
    );
  }
}
