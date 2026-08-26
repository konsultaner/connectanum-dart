import 'contact_importer_contract.dart';
import 'vcard_contact_importer.dart';

ContactImporter createContactImporter() => const VCardContactImporter();
