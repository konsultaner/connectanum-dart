import 'dart:convert';
import 'dart:math';

import 'package:connectanum_client/connectanum.dart' hide Error;
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_credential_provider.dart';
import 'account_store.dart';
import 'attachment_service.dart';
import 'attachment_store.dart';
import 'device_service.dart';
import 'mailbox_store.dart';
import 'message_service.dart';
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
  }) : _runtime = runtime,
       _binding = binding,
       _serviceClients = List<Client>.unmodifiable(serviceClients),
       _serviceSessions = List<Session>.unmodifiable(serviceSessions);

  final Uri websocketUri;
  final NativeTransportRuntime _runtime;
  final RouterBinding _binding;
  final List<Client> _serviceClients;
  final List<Session> _serviceSessions;
  bool _closed = false;

  static Future<WampAppServer> start(WampAppServerConfig config) async {
    final store = AccountStore(config.accountStorePath);
    await store.initialize();
    final mailbox = MailboxStore(config.messageStorePath);
    await mailbox.initialize();
    final attachments = AttachmentStore(
      config.attachmentStorePath ?? '${config.messageStorePath}.attachments',
    );
    await attachments.initialize();
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
    try {
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
      );
      await _registerAttachmentHandlers(
        appServiceSession,
        AttachmentService(store: attachments, mailbox: mailbox),
      );
      await _registerMessageHandlers(
        appServiceSession,
        MessageService(
          accounts: store,
          mailbox: mailbox,
          attachments: attachments,
        ),
      );
      return WampAppServer._(
        websocketUri: websocketUri,
        runtime: runtime,
        binding: binding,
        serviceClients: serviceClients,
        serviceSessions: serviceSessions,
      );
    } catch (_) {
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
      invocation.respondWith(argumentsKeywords: device.toWampKeywords());
    } catch (error) {
      _respondWithDeviceError(invocation, error);
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

Future<void> _registerMessageHandlers(
  Session session,
  MessageService messages,
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
      );
      invocation.respondWith(
        argumentsKeywords: update.receipt.toWampKeywords(),
      );
    } catch (error) {
      _respondWithMessageError(invocation, error);
    }
  }, options: options);
}

Future<void> _publishMailboxWakeup(
  Session session,
  int cursor,
  Iterable<String> usernames,
) async {
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

class _CallerNotAuthorized implements Exception {
  const _CallerNotAuthorized();
}
