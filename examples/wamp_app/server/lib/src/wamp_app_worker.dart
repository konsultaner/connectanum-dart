import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';

import 'account_credential_provider.dart';
import 'account_store.dart';

const _workerConfigKey = 'wamp_app_worker';

Map<String, Object?> wampAppWorkerOptions({
  required String accountStorePath,
  required String serviceTicket,
}) {
  return {
    _workerConfigKey: {
      'account_store_path': accountStorePath,
      'service_ticket': serviceTicket,
    },
  };
}

@pragma('vm:entry-point')
void wampAppRouterWorkerEntryPoint(Map<String, Object?> init) {
  final settings = init['settings'];
  if (settings is! Map) {
    throw StateError('WampApp worker settings are unavailable.');
  }
  final authenticators = settings['authenticators'];
  final ticketAuthenticator = authenticators is Map
      ? authenticators['ticket-service']
      : null;
  final options = ticketAuthenticator is Map
      ? ticketAuthenticator['options']
      : null;
  final workerConfig = options is Map ? options[_workerConfigKey] : null;
  final accountStorePath = workerConfig is Map
      ? workerConfig['account_store_path']
      : null;
  final serviceTicket = workerConfig is Map
      ? workerConfig['service_ticket']
      : null;
  if (accountStorePath is! String || serviceTicket is! String) {
    throw StateError('WampApp worker credentials are incomplete.');
  }

  AuthCredentialRegistry.registerProvider(
    AccountCredentialProvider(
      store: AccountStore(accountStorePath),
      serviceTicket: serviceTicket,
    ),
  );
  defaultRouterWorkerEntryPoint(init);
}
