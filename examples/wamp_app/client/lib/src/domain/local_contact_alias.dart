import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class LocalContactAlias {
  factory LocalContactAlias({
    required String username,
    required String displayName,
    required DateTime importedAt,
  }) {
    final contact = LocalContactAlias._(
      AccountRegistration.normalizeUsername(username),
      displayName.trim(),
      importedAt.toUtc(),
    );
    contact.validate();
    return contact;
  }

  const LocalContactAlias._(this.username, this.displayName, this.importedAt);

  static const maxContacts = 500;
  static const maxDisplayNameCharacters = 80;
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9_.-]{2,63}$');
  static final RegExp _controlCharacterPattern = RegExp(
    r'[\u0000-\u001f\u007f]',
  );

  final String username;
  final String displayName;
  final DateTime importedAt;

  void validate() {
    if (!_usernamePattern.hasMatch(username)) {
      throw const FormatException('The contact username is invalid.');
    }
    if (displayName.isEmpty ||
        displayName.length > maxDisplayNameCharacters ||
        _controlCharacterPattern.hasMatch(displayName)) {
      throw const FormatException(
        'Contact names need 1-80 visible characters.',
      );
    }
  }

  LocalContactAlias withDisplayName(String value) => LocalContactAlias(
    username: username,
    displayName: value,
    importedAt: importedAt,
  );

  Map<String, dynamic> toJson() => {
    'username': username,
    'display_name': displayName,
    'imported_at': importedAt.toIso8601String(),
  };

  factory LocalContactAlias.fromJson(Object? value) {
    if (value case {
      'username': final String username,
      'display_name': final String displayName,
      'imported_at': final String rawImportedAt,
    }) {
      final importedAt = DateTime.tryParse(rawImportedAt);
      if (importedAt != null) {
        return LocalContactAlias(
          username: username,
          displayName: displayName,
          importedAt: importedAt,
        );
      }
    }
    throw const FormatException('A saved contact is invalid.');
  }

  static List<LocalContactAlias> validateList(
    Iterable<LocalContactAlias> contacts,
  ) {
    final result = contacts.toList(growable: false);
    if (result.length > maxContacts) {
      throw const FormatException('Too many contacts are saved.');
    }
    final usernames = <String>{};
    for (final contact in result) {
      contact.validate();
      if (!usernames.add(contact.username)) {
        throw const FormatException('Contact usernames must be unique.');
      }
    }
    return List<LocalContactAlias>.unmodifiable(result);
  }
}
