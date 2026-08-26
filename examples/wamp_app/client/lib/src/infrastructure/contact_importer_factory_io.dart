import 'dart:io';

import 'contact_importer_contract.dart';
import 'native_contact_importer.dart';
import 'vcard_contact_importer.dart';

ContactImporter createContactImporter() => Platform.isAndroid || Platform.isIOS
    ? const NativeContactImporter()
    : const VCardContactImporter();
