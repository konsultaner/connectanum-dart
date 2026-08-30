import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/connectanum_router.dart';

void main() {
  final settings =
      (RouterSettingsBuilder()
            ..addRealmFromBuilder(RealmSettingsBuilder('com.example.app')))
          .build();
  final server = AuthServer(settings: settings);

  print('Remote authentication ready for ${server.settings.realms.first.name}');
}
