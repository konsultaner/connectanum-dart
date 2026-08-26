final class ImportedContactCandidate {
  factory ImportedContactCandidate({required String displayName}) {
    final normalized = displayName.trim();
    if (normalized.isEmpty ||
        normalized.length > 80 ||
        _controlCharacterPattern.hasMatch(normalized)) {
      throw const ContactImportException(
        'The selected contact has no usable display name.',
      );
    }
    return ImportedContactCandidate._(normalized);
  }

  const ImportedContactCandidate._(this.displayName);

  static final RegExp _controlCharacterPattern = RegExp(
    r'[\u0000-\u001f\u007f]',
  );

  final String displayName;
}

abstract interface class ContactImporter {
  String get actionLabel;

  Future<List<ImportedContactCandidate>> pickContacts();
}

final class ContactImportException implements Exception {
  const ContactImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
