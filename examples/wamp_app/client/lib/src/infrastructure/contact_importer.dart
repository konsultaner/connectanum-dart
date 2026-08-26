import 'contact_importer_contract.dart';
import 'contact_importer_factory_stub.dart'
    if (dart.library.io) 'contact_importer_factory_io.dart'
    as platform;

export 'contact_importer_contract.dart';

ContactImporter createContactImporter() => platform.createContactImporter();
