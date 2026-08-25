import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectanum_client/connectanum.dart' hide Error;
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_credential_provider.dart';
import 'account_store.dart';
import 'attachment_service.dart';
import 'attachment_retention.dart';
import 'attachment_store.dart';
import 'backup_service.dart';
import 'backup_store.dart' as backups;
import 'call_configuration_service.dart';
import 'call_service.dart';
import 'call_store.dart';
import 'device_service.dart';
import 'fcm_platform_push_gateway.dart';
import 'mailbox_store.dart';
import 'message_service.dart';
import 'platform_push_service.dart';
import 'profile_service.dart';
import 'push_subscription_store.dart';
import 'registration_service.dart';
import 'server_config.dart';
import 'wamp_app_worker.dart';

class WampAppServer {
  WampAppServer._({
    required this.websocketUri,
    required NativeTransportRuntime runtime,
    required RouterBinding binding,
    required List<Client> serviceClients,
    required List<Session> serviceSessions,
    required AttachmentRetentionController attachmentRetention,
    required PlatformPushDispatcher? pushDispatcher,
    required PlatformPushGateway? pushGateway,
  }) : _runtime = runtime,
       _binding = binding,
       _serviceClients = List<Client>.unmodifiable(serviceClients),
       _serviceSessions = List<Session>.unmodifiable(serviceSessions),
       _attachmentRetention = attachmentRetention,
       _pushDispatcher = pushDispatcher,
       _pushGateway = pushGateway;

  final Uri websocketUri;
  final NativeTransportRuntime _runtime;
  final RouterBinding _binding;
  final List<Client> _serviceClients;
  final List<Session> _serviceSessions;
  final AttachmentRetentionController _attachmentRetention;
  final PlatformPushDispatcher? _pushDispatcher;
  final PlatformPushGateway? _pushGateway;
  bool _closed = false;

  static Future<WampAppServer> start(
    WampAppServerConfig config, {
    PlatformPushGateway? pushGateway,
  }) async {
    final store = AccountStore(config.accountStorePath);
    await store.initialize();
    final mailbox = MailboxStore(config.messageStorePath);
    await mailbox.initialize();
    final pushStore = PlatformPushSubscriptionStore(
      config.pushStorePath ?? '${config.messageStorePath}.push.json',
    );
    await pushStore.initialize();
    final pushService = PlatformPushService(accounts: store, store: pushStore);
    final attachments = AttachmentStore(
      config.attachmentStorePath ?? '${config.messageStorePath}.attachments',
      maxTotalBytes: config.attachmentMaxTotalBytes,
      maxBytesPerSender: config.attachmentMaxBytesPerSender,
      stagingTtl: config.attachmentStagingTtl,
    );
    await attachments.initialize();
    final backupStore = backups.BackupStore(
      config.backupStorePath ?? '${config.messageStorePath}.backups',
      maximumTotalBytes: config.backupMaxTotalBytes,
    );
    await backupStore.initialize();
    final callStore = CallStore(
      config.callStorePath ?? '${config.messageStorePath}.calls.json',
    );
    await callStore.initialize();
    final random = Random.secure();
    final serviceTicket = base64Url.encode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );

    registerDefaultAuthenticators();
    AuthCredentialRegistry.registerProvider(
      AccountCredentialProvider(store: store, serviceTicket: serviceTicket),
    );

    final runtime = NativeTransportRuntime()..start();
    final router = Router(
      RouterConfig(
        endpoints: [
          Endpoint(
            host: config.host,
            port: config.port,
            tlsMode: TlsMode.disabled,
            maxRawSocketSizeExponent: 18,
            webSocketPath: config.websocketPath,
          ),
        ],
      ),
      settings: _buildSettings(config, serviceTicket),
    );
    final binding = router.start(
      runtime,
      workerEntryPoint: wampAppRouterWorkerEntryPoint,
    );
    final serviceClients = <Client>[];
    final serviceSessions = <Session>[];
    AttachmentRetentionController? attachmentRetention;
    PlatformPushGateway? activePushGateway;
    PlatformPushDispatcher? pushDispatcher;
    try {
      activePushGateway = pushGateway;
      final fcmPush = config.fcmPush;
      if (activePushGateway == null && fcmPush != null) {
        activePushGateway = await FcmPlatformPushGateway.fromConfig(fcmPush);
      }
      if (activePushGateway != null) {
        pushDispatcher = PlatformPushDispatcher(
          service: pushService,
          gateway: activePushGateway,
          onBackgroundFailure: (_) {
            stderr.writeln('WampApp platform push delivery failed.');
          },
        );
      }
      final listener = binding.listeners.single;
      final connectHost = switch (config.host) {
        '0.0.0.0' || '::' => '127.0.0.1',
        _ => config.host,
      };
      final websocketUri = Uri(
        scheme: 'ws',
        host: connectHost,
        port: listener.port,
        path: config.websocketPath,
      );
      final registrationServiceClient = Client(
        transport: WebSocketTransport.withCborSerializer(
          websocketUri.toString(),
        ),
        realm: WampAppProtocol.registrationRealm,
        authId: WampAppProtocol.serviceAuthId,
        authenticationMethods: [TicketAuthentication(serviceTicket)],
      );
      serviceClients.add(registrationServiceClient);
      final registrationServiceSession = await registrationServiceClient
          .connect(
            options: ClientConnectOptions(
              reconnectCount: 0,
              reconnectTime: const Duration(milliseconds: 100),
            ),
          )
          .first
          .timeout(const Duration(seconds: 15));
      serviceSessions.add(registrationServiceSession);
      final registrations = RegistrationService(
        store: store,
        iterations: config.argonIterations,
        memoryKiB: config.argonMemoryKiB,
      );
      await _registerAccountHandler(registrationServiceSession, registrations);

      final appServiceClient = Client(
        transport: WebSocketTransport.withCborSerializer(
          websocketUri.toString(),
        ),
        realm: WampAppProtocol.appRealm,
        authId: WampAppProtocol.serviceAuthId,
        authenticationMethods: [TicketAuthentication(serviceTicket)],
      );
      serviceClients.add(appServiceClient);
      final appServiceSession = await appServiceClient
          .connect(
            options: ClientConnectOptions(
              reconnectCount: 0,
              reconnectTime: const Duration(milliseconds: 100),
            ),
          )
          .first
          .timeout(const Duration(seconds: 15));
      serviceSessions.add(appServiceSession);
      await _registerDeviceHandlers(
        appServiceSession,
        DeviceService(store: store),
        pushService,
      );
      await _registerPushHandlers(
        appServiceSession,
        pushService,
        supportedProviders: activePushGateway?.providers ?? const {},
      );
      await _registerProfileHandlers(
        appServiceSession,
        ProfileService(store: store),
      );
      await _registerAttachmentHandlers(
        appServiceSession,
        AttachmentService(store: attachments, mailbox: mailbox),
      );
      await _registerBackupHandlers(
        appServiceSession,
        BackupService(store: backupStore),
      );
      await _registerCallHandlers(
        appServiceSession,
        CallService(accounts: store, store: callStore),
        CallConfigurationService(
          stunUrls: config.stunUrls,
          turnRest: config.turnRest,
        ),
      );
      await _registerMessageHandlers(
        appServiceSession,
        MessageService(
          accounts: store,
          mailbox: mailbox,
          attachments: attachments,
        ),
        pushDispatcher,
      );
      attachmentRetention = AttachmentRetentionController(
        store: attachments,
        mailbox: mailbox,
        interval: config.attachmentCleanupInterval,
        onBackgroundError: (_, _) {
          stderr.writeln('WampApp attachment retention cleanup failed.');
        },
      );
      await attachmentRetention.start();
      return WampAppServer._(
        websocketUri: websocketUri,
        runtime: runtime,
        binding: binding,
        serviceClients: serviceClients,
        serviceSessions: serviceSessions,
        attachmentRetention: attachmentRetention,
        pushDispatcher: pushDispatcher,
        pushGateway: activePushGateway,
      );
    } catch (_) {
      try {
        await pushDispatcher?.close();
      } catch (_) {
        // Preserve the startup failure while releasing remaining resources.
      }
      try {
        await activePushGateway?.close();
      } catch (_) {
        // Preserve the startup failure while releasing remaining resources.
      }
      try {
        await attachmentRetention?.close();
      } catch (_) {
        // Preserve the startup failure while releasing remaining resources.
      }
      for (final session in serviceSessions.reversed) {
        try {
          await session.close(timeout: Duration.zero);
        } catch (_) {
          // Preserve the startup failure while releasing remaining resources.
        }
      }
      for (final client in serviceClients.reversed) {
        try {
          await client.disconnect();
        } catch (_) {
          // Preserve the startup failure while releasing remaining resources.
        }
      }
      await binding.dispose();
      runtime.shutdown();
      runtime.dispose();
      AuthCredentialRegistry.reset();
      rethrow;
    }
  }

  static RouterSettings _buildSettings(
    WampAppServerConfig config,
    String serviceTicket,
  ) {
    final settings = RouterSettingsBuilder()
      ..addAuthenticator(
        'anonymous',
        const AuthenticatorDefinition(type: 'anonymous'),
      )
      ..addAuthenticator(
        'ticket-service',
        AuthenticatorDefinition(
          type: 'ticket',
          options: wampAppWorkerOptions(
            accountStorePath: config.accountStorePath,
            serviceTicket: serviceTicket,
          ),
        ),
      )
      ..addAuthenticator(
        'scram-account',
        const AuthenticatorDefinition(type: 'scram'),
      );

    settings.addRealmFromBuilder(
      RealmSettingsBuilder(WampAppProtocol.registrationRealm)
        ..addAuthMethod('anonymous', options: {'authenticator': 'anonymous'})
        ..addAuthMethod('ticket', options: {'authenticator': 'ticket-service'})
        ..addRoleFromBuilder(
          RoleSettingsBuilder(WampAppProtocol.anonymousRole)
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.accountRegister)
                ..setMatchPolicy(PermissionMatchPolicy.exact)
                ..allowOperations(const ['call']),
            ),
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder(WampAppProtocol.serviceRole)
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.accountRegister)
                ..setMatchPolicy(PermissionMatchPolicy.exact)
                ..allowOperations(const ['register', 'unregister']),
            ),
        )
        ..setLimits(
          const RealmLimitSettings(
            maxPendingAuth: 64,
            maxFailedAuth: 5,
            lockoutMs: 30000,
            callTimeoutMs: 65000,
          ),
        ),
    );
    settings.addRealmFromBuilder(
      RealmSettingsBuilder(WampAppProtocol.appRealm)
        ..addAuthMethod('ticket', options: {'authenticator': 'ticket-service'})
        ..addAuthMethod(
          WampAppProtocol.scramAuthMethod,
          options: {'authenticator': 'scram-account'},
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder(WampAppProtocol.memberRole)
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.deviceEnroll)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.deviceList)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.deviceRevoke)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.deviceLookup)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.pushRegister)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.pushUnregister)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.profileGet)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.profileUpdate)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.messageSend)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.messageSync)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.messageReceipt)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.messageConsume)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.attachmentChunkPut)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.attachmentUploadStatus)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.attachmentChunkGet)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupUploadBegin)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupChunkPut)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupUploadCommit)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupMetadataGet)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupChunkGet)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupDelete)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callConfiguration)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callStart)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callAccept)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callSignal)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callEnd)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callSync)
                ..allowOperations(const ['call']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callChanged)
                ..setMatchPolicy(PermissionMatchPolicy.exact)
                ..allowOperations(const ['subscribe', 'unsubscribe']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.mailboxChanged)
                ..setMatchPolicy(PermissionMatchPolicy.exact)
                ..allowOperations(const ['subscribe', 'unsubscribe']),
            ),
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder(WampAppProtocol.serviceRole)
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.deviceEnroll)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.deviceList)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.deviceRevoke)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.deviceLookup)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.pushRegister)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.pushUnregister)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.profileGet)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.profileUpdate)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.messageSend)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.messageSync)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.messageReceipt)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.messageConsume)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.attachmentChunkPut)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.attachmentUploadStatus)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.attachmentChunkGet)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupUploadBegin)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupChunkPut)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupUploadCommit)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupMetadataGet)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupChunkGet)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.backupDelete)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callConfiguration)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callStart)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callAccept)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callSignal)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callEnd)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callSync)
                ..allowOperations(const ['register', 'unregister']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.callChanged)
                ..setMatchPolicy(PermissionMatchPolicy.exact)
                ..allowOperations(const ['publish']),
            )
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder(WampAppProtocol.mailboxChanged)
                ..setMatchPolicy(PermissionMatchPolicy.exact)
                ..allowOperations(const ['publish']),
            ),
        )
        ..setLimits(
          const RealmLimitSettings(
            maxPendingAuth: 128,
            maxFailedAuth: 5,
            lockoutMs: 30000,
            callTimeoutMs: 30000,
          ),
        ),
    );
    settings.addListenerFromBuilder(
      ListenerSettingsBuilder('websocket', '${config.host}:${config.port}')
        ..setPath(config.websocketPath)
        ..addProtocol(ListenerProtocol.websocket)
        ..addAuthMethod('anonymous')
        ..addAuthMethod('ticket')
        ..addAuthMethod(WampAppProtocol.scramAuthMethod)
        ..setWebSocketOptions(
          const WebSocketListenerSettings(
            subprotocols: ['wamp.2.cbor', 'wamp.2.json'],
          ),
        ),
    );
    return settings.build();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    Object? failure;
    try {
      await _pushDispatcher?.close();
    } catch (error) {
      failure ??= error;
    }
    try {
      await _pushGateway?.close();
    } catch (error) {
      failure ??= error;
    }
    try {
      await _attachmentRetention.close();
    } catch (error) {
      failure ??= error;
    }
    for (final session in _serviceSessions.reversed) {
      try {
        await session.close(timeout: Duration.zero);
      } catch (error) {
        failure ??= error;
      }
    }
    for (final client in _serviceClients.reversed) {
      try {
        await client.disconnect();
      } catch (error) {
        failure ??= error;
      }
    }
    try {
      await _binding.dispose();
    } catch (error) {
      failure ??= error;
    } finally {
      _runtime.shutdown();
      _runtime.dispose();
      AuthCredentialRegistry.reset();
    }
    if (failure != null) {
      throw failure;
    }
  }
}

Future<void> _registerAccountHandler(
  Session session,
  RegistrationService registrations,
) {
  return session.registerHandler(WampAppProtocol.accountRegister, (
    invocation,
  ) async {
    try {
      final request = AccountRegistration.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final receipt = await registrations.register(request);
      invocation.respondWith(argumentsKeywords: receipt.toWampKeywords());
    } on AccountAlreadyExists {
      invocation.respondWith(
        isError: true,
        errorUri: WampAppProtocol.errorUsernameTaken,
        arguments: const ['That username is already registered.'],
      );
    } on FormatException catch (error) {
      invocation.respondWith(
        isError: true,
        errorUri: WampAppProtocol.errorInvalidRegistration,
        arguments: [error.message],
      );
    } catch (_) {
      invocation.respondWith(
        isError: true,
        errorUri: WampAppProtocol.errorRegistrationUnavailable,
        arguments: const ['Registration is temporarily unavailable.'],
      );
    }
  });
}

Future<void> _registerDeviceHandlers(
  Session session,
  DeviceService devices,
  PlatformPushService push,
) async {
  final options = RegisterOptions(discloseCaller: true);
  await session.registerHandler(WampAppProtocol.deviceEnroll, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final enrollment = DeviceEnrollment.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final device = await devices.enroll(username, enrollment);
      invocation.respondWith(argumentsKeywords: device.toWampKeywords());
    } catch (error) {
      _respondWithDeviceError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.deviceList, (invocation) async {
    try {
      final username = _callerUsername(invocation);
      final includeRevoked = switch (invocation
          .argumentsKeywords?['include_revoked']) {
        null => false,
        final bool value => value,
        _ => throw const FormatException('include_revoked must be a boolean.'),
      };
      final directory = await devices.list(
        username,
        includeRevoked: includeRevoked,
      );
      invocation.respondWith(argumentsKeywords: directory.toWampKeywords());
    } catch (error) {
      _respondWithDeviceError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.deviceRevoke, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final deviceId = invocation.argumentsKeywords?['device_id'];
      if (deviceId is! String) {
        throw const FormatException('device_id must be a string.');
      }
      final device = await devices.revoke(username, deviceId);
      try {
        await push.deviceRevoked(username, deviceId);
      } catch (_) {
        // Active-device checks prevent delivery even if eager cleanup fails.
      }
      invocation.respondWith(argumentsKeywords: device.toWampKeywords());
    } catch (error) {
      _respondWithDeviceError(invocation, error);
    }
  }, options: options);
}

Future<void> _registerPushHandlers(
  Session session,
  PlatformPushService push, {
  required Set<String> supportedProviders,
}) async {
  final options = RegisterOptions(discloseCaller: true);
  await session.registerHandler(WampAppProtocol.pushRegister, (
    invocation,
  ) async {
    try {
      if (supportedProviders.isEmpty) throw const _PlatformPushUnavailable();
      final username = _callerUsername(invocation);
      final request = PlatformPushSubscriptionRequest.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      if (!supportedProviders.contains(request.provider)) {
        throw const FormatException('Platform push provider is not supported.');
      }
      final receipt = await push.register(username, request);
      invocation.respondWith(argumentsKeywords: receipt.toWampKeywords());
    } catch (error) {
      _respondWithPushError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.pushUnregister, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final key = PlatformPushSubscriptionKey.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final removed = await push.unregister(username, key);
      invocation.respondWith(argumentsKeywords: {'removed': removed});
    } catch (error) {
      _respondWithPushError(invocation, error);
    }
  }, options: options);
}

Future<void> _registerProfileHandlers(
  Session session,
  ProfileService profiles,
) async {
  final options = RegisterOptions(discloseCaller: true);
  await session.registerHandler(WampAppProtocol.profileGet, (invocation) async {
    try {
      final caller = _callerUsername(invocation);
      final requested = invocation.argumentsKeywords?['username'];
      if (requested != null && requested is! String) {
        throw const FormatException('username must be a string.');
      }
      final username = requested == null
          ? caller
          : AccountRegistration.normalizeUsername(requested);
      final profile = await profiles.get(username);
      invocation.respondWith(argumentsKeywords: profile.toWampKeywords());
    } catch (error) {
      _respondWithProfileError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.profileUpdate, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final update = AccountProfileUpdate.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final profile = await profiles.update(username, update);
      invocation.respondWith(argumentsKeywords: profile.toWampKeywords());
    } catch (error) {
      _respondWithProfileError(invocation, error);
    }
  }, options: options);
}

Future<void> _registerAttachmentHandlers(
  Session session,
  AttachmentService attachments,
) async {
  final options = RegisterOptions(discloseCaller: true);
  await session.registerHandler(WampAppProtocol.attachmentChunkPut, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final chunk = EncryptedAttachmentChunk.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final result = await attachments.putChunk(username, chunk);
      invocation.respondWith(
        argumentsKeywords: result.receipt.toWampKeywords(),
      );
    } catch (error) {
      _respondWithAttachmentError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.attachmentUploadStatus, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final messageId = invocation.argumentsKeywords?['message_id'];
      final attachmentId = invocation.argumentsKeywords?['attachment_id'];
      final chunkCount = invocation.argumentsKeywords?['chunk_count'];
      if (messageId is! String ||
          attachmentId is! String ||
          chunkCount is! int) {
        throw const FormatException(
          'message_id, attachment_id, and chunk_count are required.',
        );
      }
      final status = await attachments.status(
        username,
        messageId: messageId,
        attachmentId: attachmentId,
        chunkCount: chunkCount,
      );
      invocation.respondWith(argumentsKeywords: status.toWampKeywords());
    } catch (error) {
      _respondWithAttachmentError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.attachmentChunkGet, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final messageId = invocation.argumentsKeywords?['message_id'];
      final attachmentId = invocation.argumentsKeywords?['attachment_id'];
      final chunkIndex = invocation.argumentsKeywords?['chunk_index'];
      if (messageId is! String ||
          attachmentId is! String ||
          chunkIndex is! int) {
        throw const FormatException(
          'message_id, attachment_id, and chunk_index are required.',
        );
      }
      final chunk = await attachments.getChunk(
        username,
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: chunkIndex,
      );
      invocation.respondWith(argumentsKeywords: chunk.toWampKeywords());
    } catch (error) {
      _respondWithAttachmentError(invocation, error);
    }
  }, options: options);
}

Future<void> _registerBackupHandlers(
  Session session,
  BackupService backups,
) async {
  final options = RegisterOptions(discloseCaller: true);
  await session.registerHandler(WampAppProtocol.backupUploadBegin, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final request = BackupUploadRequest.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final upload = await backups.begin(username, request);
      invocation.respondWith(argumentsKeywords: upload.toWampKeywords());
    } catch (error) {
      _respondWithBackupError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.backupChunkPut, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final chunk = EncryptedBackupChunk.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      await backups.putChunk(username, chunk);
      invocation.respondWith(
        argumentsKeywords: {
          'upload_id': chunk.uploadId,
          'chunk_index': chunk.chunkIndex,
        },
      );
    } catch (error) {
      _respondWithBackupError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.backupUploadCommit, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final uploadId = invocation.argumentsKeywords?['upload_id'];
      if (uploadId is! String) {
        throw const FormatException('upload_id must be a string.');
      }
      final metadata = await backups.commit(username, uploadId);
      invocation.respondWith(argumentsKeywords: metadata.toWampKeywords());
    } catch (error) {
      _respondWithBackupError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.backupMetadataGet, (
    invocation,
  ) async {
    try {
      final metadata = await backups.metadata(_callerUsername(invocation));
      invocation.respondWith(argumentsKeywords: metadata.toWampKeywords());
    } catch (error) {
      _respondWithBackupError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.backupChunkGet, (
    invocation,
  ) async {
    try {
      final revision = invocation.argumentsKeywords?['revision'];
      final chunkIndex = invocation.argumentsKeywords?['chunk_index'];
      if (revision is! int || chunkIndex is! int) {
        throw const FormatException(
          'revision and chunk_index must be integers.',
        );
      }
      final chunk = await backups.readChunk(
        username: _callerUsername(invocation),
        revision: revision,
        chunkIndex: chunkIndex,
      );
      invocation.respondWith(argumentsKeywords: chunk.toWampKeywords());
    } catch (error) {
      _respondWithBackupError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.backupDelete, (
    invocation,
  ) async {
    try {
      final expectedRevision =
          invocation.argumentsKeywords?['expected_revision'];
      if (expectedRevision is! int) {
        throw const FormatException('expected_revision must be an integer.');
      }
      final removed = await backups.delete(
        _callerUsername(invocation),
        expectedRevision,
      );
      invocation.respondWith(argumentsKeywords: {'removed': removed});
    } catch (error) {
      _respondWithBackupError(invocation, error);
    }
  }, options: options);
}

Future<void> _registerMessageHandlers(
  Session session,
  MessageService messages,
  PlatformPushDispatcher? pushDispatcher,
) async {
  final options = RegisterOptions(discloseCaller: true);
  await session.registerHandler(WampAppProtocol.deviceLookup, (
    invocation,
  ) async {
    try {
      _callerUsername(invocation);
      final username = invocation.argumentsKeywords?['username'];
      final includeRevoked =
          invocation.argumentsKeywords?['include_revoked'] ?? false;
      if (username is! String) {
        throw const FormatException('username must be a string.');
      }
      if (includeRevoked is! bool) {
        throw const FormatException('include_revoked must be a boolean.');
      }
      final directory = await messages.lookupDevices(
        username,
        includeRevoked: includeRevoked,
      );
      invocation.respondWith(argumentsKeywords: directory.toWampKeywords());
    } catch (error) {
      _respondWithMessageError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.messageSend, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final message = EncryptedChatMessage.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final receipt = await messages.send(username, message);
      await _publishMailboxWakeup(
        session,
        receipt.cursor,
        message.participantUsernames,
        pushDispatcher,
        presentationConversationId: message.conversationId,
        presentationUsernames: message.recipientUsernames,
      );
      invocation.respondWith(argumentsKeywords: receipt.toWampKeywords());
    } catch (error) {
      _respondWithMessageError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.messageSync, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final afterCursor = invocation.argumentsKeywords?['after_cursor'];
      final limit = invocation.argumentsKeywords?['limit'] ?? 100;
      if (afterCursor is! int || limit is! int) {
        throw const FormatException('after_cursor and limit must be integers.');
      }
      final batch = await messages.sync(
        username,
        afterCursor: afterCursor,
        limit: limit,
      );
      invocation.respondWith(argumentsKeywords: batch.toWampKeywords());
    } catch (error) {
      _respondWithMessageError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.messageReceipt, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final messageId = invocation.argumentsKeywords?['message_id'];
      final state = invocation.argumentsKeywords?['state'];
      if (messageId is! String || (state != 'delivered' && state != 'read')) {
        throw const FormatException(
          'message_id and a delivered/read state are required.',
        );
      }
      final update = await messages.markReceipt(
        username,
        messageId,
        read: state == 'read',
      );
      await _publishMailboxWakeup(
        session,
        update.receipt.cursor,
        update.participantUsernames,
        pushDispatcher,
      );
      invocation.respondWith(
        argumentsKeywords: update.receipt.toWampKeywords(),
      );
    } catch (error) {
      _respondWithMessageError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.messageConsume, (
    invocation,
  ) async {
    try {
      final username = _callerUsername(invocation);
      final consumption = OneTimeMessageConsumption.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final update = await messages.consumeOneTime(username, consumption);
      await _publishMailboxWakeup(
        session,
        update.receipt.cursor,
        update.participantUsernames,
        pushDispatcher,
      );
      invocation.respondWith(
        argumentsKeywords: update.receipt.toWampKeywords(),
      );
    } catch (error) {
      _respondWithMessageError(invocation, error);
    }
  }, options: options);
}

Future<void> _registerCallHandlers(
  Session session,
  CallService calls,
  CallConfigurationService configurations,
) async {
  final options = RegisterOptions(discloseCaller: true);
  await session.registerHandler(WampAppProtocol.callConfiguration, (
    invocation,
  ) async {
    try {
      final configuration = configurations.forAccount(
        _callerUsername(invocation),
      );
      invocation.respondWith(argumentsKeywords: configuration.toWampKeywords());
    } catch (error) {
      _respondWithCallError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.callStart, (invocation) async {
    try {
      final request = CallStartRequest.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final result = await calls.start(_callerUsername(invocation), request);
      await _publishCallWakeup(session, result.update);
      invocation.respondWith(
        argumentsKeywords: {
          ...result.update.toWampKeywords(),
          'duplicate': result.duplicate,
        },
      );
    } catch (error) {
      _respondWithCallError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.callAccept, (invocation) async {
    try {
      final answer = EncryptedCallSignal.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final result = await calls.accept(_callerUsername(invocation), answer);
      await _publishCallWakeup(session, result.update);
      invocation.respondWith(
        argumentsKeywords: {
          ...result.update.toWampKeywords(),
          'duplicate': result.duplicate,
        },
      );
    } catch (error) {
      _respondWithCallError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.callSignal, (invocation) async {
    try {
      final signal = EncryptedCallSignal.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final result = await calls.signal(_callerUsername(invocation), signal);
      await _publishCallWakeup(session, result.update);
      invocation.respondWith(
        argumentsKeywords: {
          ...result.update.toWampKeywords(),
          'duplicate': result.duplicate,
        },
      );
    } catch (error) {
      _respondWithCallError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.callEnd, (invocation) async {
    try {
      final signal = EncryptedCallSignal.fromWampKeywords(
        invocation.argumentsKeywords,
      );
      final result = await calls.end(_callerUsername(invocation), signal);
      await _publishCallWakeup(session, result.update);
      invocation.respondWith(
        argumentsKeywords: {
          ...result.update.toWampKeywords(),
          'duplicate': result.duplicate,
        },
      );
    } catch (error) {
      _respondWithCallError(invocation, error);
    }
  }, options: options);
  await session.registerHandler(WampAppProtocol.callSync, (invocation) async {
    try {
      final keywords = invocation.argumentsKeywords;
      final deviceId = keywords?['device_id'];
      final afterCursor = keywords?['after_cursor'];
      final limit = keywords?['limit'] ?? 100;
      if (deviceId is! String || afterCursor is! int || limit is! int) {
        throw const FormatException(
          'device_id, after_cursor, and limit are required.',
        );
      }
      final batch = await calls.sync(
        _callerUsername(invocation),
        deviceId,
        afterCursor: afterCursor,
        limit: limit,
      );
      invocation.respondWith(argumentsKeywords: batch.toWampKeywords());
    } catch (error) {
      _respondWithCallError(invocation, error);
    }
  }, options: options);
}

Future<void> _publishCallWakeup(Session session, CallUpdate update) async {
  try {
    await session.publish(
      WampAppProtocol.callChanged,
      argumentsKeywords: CallWakeup(cursor: update.cursor).toWampKeywords(),
      options: PublishOptions(
        eligibleAuthId: [
          update.call.callerUsername,
          update.call.calleeUsername,
        ],
      ),
    );
  } catch (_) {
    // Durable call cursor synchronization remains authoritative.
  }
}

Future<void> _publishMailboxWakeup(
  Session session,
  int cursor,
  Iterable<String> usernames,
  PlatformPushDispatcher? pushDispatcher, {
  String? presentationConversationId,
  Iterable<String> presentationUsernames = const [],
}) async {
  final eligibleAuthIds = usernames.toSet().toList(growable: false)..sort();
  try {
    await session.publish(
      WampAppProtocol.mailboxChanged,
      argumentsKeywords: MailboxWakeup(cursor: cursor).toWampKeywords(),
      options: PublishOptions(eligibleAuthId: eligibleAuthIds),
    );
  } catch (_) {
    // Durable cursor synchronization remains authoritative after a lost wakeup.
  }
  pushDispatcher?.enqueue(
    cursor,
    eligibleAuthIds,
    presentationConversationId: presentationConversationId,
    presentationUsernames: presentationUsernames,
  );
}

String _callerUsername(Invocation invocation) {
  final authId = invocation.details.custom['caller_authid'];
  if (authId is! String || authId.isEmpty) {
    throw const _CallerNotAuthorized();
  }
  return AccountRegistration.normalizeUsername(authId);
}

void _respondWithDeviceError(Invocation invocation, Object error) {
  final (uri, message) = switch (error) {
    DeviceRevoked() => (
      WampAppProtocol.errorDeviceRevoked,
      'That device has been revoked.',
    ),
    DeviceNotFound() => (
      WampAppProtocol.errorDeviceNotFound,
      'That device was not found.',
    ),
    DeviceConflict() || DeviceLimitExceeded() => (
      WampAppProtocol.errorDeviceConflict,
      'That device conflicts with the account device directory.',
    ),
    _CallerNotAuthorized() || StateError() => (
      WampAppProtocol.errorNotAuthorized,
      'The authenticated account cannot perform this operation.',
    ),
    FormatException(:final message) => (
      WampAppProtocol.errorInvalidDevice,
      message,
    ),
    _ => (
      WampAppProtocol.errorDeviceUnavailable,
      'The device service is temporarily unavailable.',
    ),
  };
  invocation.respondWith(isError: true, errorUri: uri, arguments: [message]);
}

void _respondWithProfileError(Invocation invocation, Object error) {
  final (uri, message, currentRevision) = switch (error) {
    ProfileNotFound() => (
      WampAppProtocol.errorProfileNotFound,
      'That profile was not found.',
      null,
    ),
    ProfileConflict(:final currentRevision) => (
      WampAppProtocol.errorProfileConflict,
      'The profile changed on another device.',
      currentRevision,
    ),
    _CallerNotAuthorized() || StateError() => (
      WampAppProtocol.errorNotAuthorized,
      'The authenticated account cannot perform this operation.',
      null,
    ),
    FormatException(:final message) => (
      WampAppProtocol.errorInvalidProfile,
      message,
      null,
    ),
    _ => (
      WampAppProtocol.errorProfileUnavailable,
      'The profile service is temporarily unavailable.',
      null,
    ),
  };
  invocation.respondWith(
    isError: true,
    errorUri: uri,
    arguments: [message],
    argumentsKeywords: {'current_revision': ?currentRevision},
  );
}

void _respondWithAttachmentError(Invocation invocation, Object error) {
  final (uri, message) = switch (error) {
    AttachmentConflict() => (
      WampAppProtocol.errorAttachmentConflict,
      'That attachment identifier is already used for different ciphertext.',
    ),
    AttachmentNotFound() => (
      WampAppProtocol.errorAttachmentNotFound,
      'That attachment chunk was not found.',
    ),
    AttachmentIncomplete() => (
      WampAppProtocol.errorAttachmentIncomplete,
      'The encrypted attachment upload is incomplete.',
    ),
    AttachmentQuotaExceeded() => (
      WampAppProtocol.errorAttachmentQuotaExceeded,
      'The encrypted attachment storage quota is exhausted.',
    ),
    _CallerNotAuthorized() || StateError() => (
      WampAppProtocol.errorNotAuthorized,
      'The authenticated account cannot perform this operation.',
    ),
    FormatException(:final message) => (
      WampAppProtocol.errorInvalidAttachment,
      message,
    ),
    AttachmentUnavailable() => (
      WampAppProtocol.errorAttachmentUnavailable,
      'The attachment service could not verify stored ciphertext.',
    ),
    _ => (
      WampAppProtocol.errorAttachmentUnavailable,
      'The attachment service is temporarily unavailable.',
    ),
  };
  invocation.respondWith(isError: true, errorUri: uri, arguments: [message]);
}

void _respondWithMessageError(Invocation invocation, Object error) {
  final (uri, message) = switch (error) {
    MessageConflict() => (
      WampAppProtocol.errorMessageConflict,
      'That message identifier is already used for different content.',
    ),
    MessageNotFound() => (
      WampAppProtocol.errorMessageNotFound,
      'That message was not found.',
    ),
    OneTimeMessageConsumed() => (
      WampAppProtocol.errorMessageConsumed,
      'That one-time message was already opened on another device.',
    ),
    AttachmentIncomplete() => (
      WampAppProtocol.errorAttachmentIncomplete,
      'Every encrypted attachment must finish uploading before the message.',
    ),
    _CallerNotAuthorized() || StateError() => (
      WampAppProtocol.errorNotAuthorized,
      'The authenticated account cannot perform this operation.',
    ),
    FormatException(:final message) => (
      WampAppProtocol.errorInvalidMessage,
      message,
    ),
    MailboxLimitExceeded() => (
      WampAppProtocol.errorMessageUnavailable,
      'The mailbox has reached its configured capacity.',
    ),
    _ => (
      WampAppProtocol.errorMessageUnavailable,
      'The message service is temporarily unavailable.',
    ),
  };
  invocation.respondWith(isError: true, errorUri: uri, arguments: [message]);
}

void _respondWithBackupError(Invocation invocation, Object error) {
  final (uri, message) = switch (error) {
    backups.BackupConflict() => (
      WampAppProtocol.errorBackupConflict,
      'The encrypted backup changed before this operation completed.',
    ),
    backups.BackupNotFound() || backups.BackupUploadNotFound() => (
      WampAppProtocol.errorBackupNotFound,
      'No matching encrypted backup or upload exists.',
    ),
    backups.BackupIncomplete() => (
      WampAppProtocol.errorBackupIncomplete,
      'Every encrypted backup chunk must upload before commit.',
    ),
    backups.BackupQuotaExceeded() => (
      WampAppProtocol.errorBackupQuotaExceeded,
      'The server backup upload limit has been reached.',
    ),
    _CallerNotAuthorized() || StateError() => (
      WampAppProtocol.errorNotAuthorized,
      'The authenticated account cannot perform this operation.',
    ),
    FormatException(:final message) => (
      WampAppProtocol.errorInvalidBackup,
      message,
    ),
    backups.BackupUnavailable() => (
      WampAppProtocol.errorBackupUnavailable,
      'The encrypted backup could not be verified.',
    ),
    _ => (
      WampAppProtocol.errorBackupUnavailable,
      'The encrypted backup service is temporarily unavailable.',
    ),
  };
  final conflictRevision = switch (error) {
    backups.BackupConflict(:final currentRevision) when currentRevision >= 0 =>
      currentRevision,
    _ => null,
  };
  invocation.respondWith(
    isError: true,
    errorUri: uri,
    arguments: [message],
    argumentsKeywords: conflictRevision == null
        ? null
        : {'current_revision': conflictRevision},
  );
}

void _respondWithCallError(Invocation invocation, Object error) {
  final (uri, message) = switch (error) {
    CallConflict() => (
      WampAppProtocol.errorCallConflict,
      'That call or signal identifier conflicts with existing state.',
    ),
    CallNotFound() => (
      WampAppProtocol.errorCallNotFound,
      'That call was not found.',
    ),
    CallAlreadyAnswered() => (
      WampAppProtocol.errorCallAnswered,
      'That call was already answered on another device.',
    ),
    CallAlreadyEnded() => (
      WampAppProtocol.errorCallEnded,
      'That call has already ended.',
    ),
    CallLimitExceeded() => (
      WampAppProtocol.errorCallUnavailable,
      'The call signaling capacity has been reached.',
    ),
    _CallerNotAuthorized() || StateError() => (
      WampAppProtocol.errorNotAuthorized,
      'The authenticated account or device cannot perform this operation.',
    ),
    FormatException(:final message) => (
      WampAppProtocol.errorInvalidCall,
      message,
    ),
    _ => (
      WampAppProtocol.errorCallUnavailable,
      'Call signaling is temporarily unavailable.',
    ),
  };
  invocation.respondWith(isError: true, errorUri: uri, arguments: [message]);
}

class _CallerNotAuthorized implements Exception {
  const _CallerNotAuthorized();
}

final class _PlatformPushUnavailable implements Exception {
  const _PlatformPushUnavailable();
}

void _respondWithPushError(Invocation invocation, Object error) {
  final (uri, message) = switch (error) {
    DeviceRevoked() => (
      WampAppProtocol.errorDeviceRevoked,
      'That device has been revoked.',
    ),
    DeviceNotFound() => (
      WampAppProtocol.errorDeviceNotFound,
      'That device was not found.',
    ),
    _CallerNotAuthorized() || StateError() => (
      WampAppProtocol.errorNotAuthorized,
      'The authenticated account cannot perform this operation.',
    ),
    FormatException(:final message) => (
      WampAppProtocol.errorInvalidPushSubscription,
      message,
    ),
    PushSubscriptionLimitExceeded() => (
      WampAppProtocol.errorInvalidPushSubscription,
      'The account push subscription limit has been reached.',
    ),
    _PlatformPushUnavailable() => (
      WampAppProtocol.errorPushSubscriptionUnavailable,
      'Platform push delivery is not configured on this server.',
    ),
    _ => (
      WampAppProtocol.errorPushSubscriptionUnavailable,
      'The platform push subscription service is temporarily unavailable.',
    ),
  };
  invocation.respondWith(isError: true, errorUri: uri, arguments: [message]);
}
