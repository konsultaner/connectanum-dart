import 'package:flutter_contacts/flutter_contacts.dart';

import 'contact_importer_contract.dart';

final class NativeContactImporter implements ContactImporter {
  const NativeContactImporter();

  @override
  String get actionLabel => 'Choose contact';

  @override
  Future<List<ImportedContactCandidate>> pickContacts() async {
    try {
      // Omitting properties keeps the platform picker permissionless and
      // returns only the opaque platform id plus the display name. The id is
      // deliberately discarded here.
      final contact = await FlutterContacts.native.showPicker();
      if (contact == null) return const [];
      return [ImportedContactCandidate(displayName: contact.displayName ?? '')];
    } catch (error) {
      if (error is ContactImportException) rethrow;
      throw const ContactImportException(
        'The system contact picker is unavailable.',
      );
    }
  }
}
