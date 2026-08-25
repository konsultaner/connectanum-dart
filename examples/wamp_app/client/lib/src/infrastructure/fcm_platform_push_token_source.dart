import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'platform_push_token_source.dart';

enum FcmPermissionStatus { authorized, provisional, denied, notDetermined }

abstract interface class FcmMessagingClient {
  Stream<String> get onTokenRefresh;

  Future<bool> isSupported();

  Future<FcmPermissionStatus> requestPermission();

  Future<String?> getApnsToken();

  Future<String?> getToken({String? vapidKey, String? serviceWorkerScriptPath});
}

final class FcmPlatformPushTokenSource implements PlatformPushTokenSource {
  FcmPlatformPushTokenSource({
    required this._client,
    required this.requiresApnsToken,
    this.vapidKey,
    this.serviceWorkerScriptPath,
    this.operationTimeout = const Duration(seconds: 15),
    this.permissionTimeout = const Duration(minutes: 1),
    this.apnsWaitTimeout = const Duration(seconds: 10),
    this.apnsPollInterval = const Duration(milliseconds: 100),
  });

  final FcmMessagingClient _client;
  final bool requiresApnsToken;
  final String? vapidKey;
  final String? serviceWorkerScriptPath;
  final Duration operationTimeout;
  final Duration permissionTimeout;
  final Duration apnsWaitTimeout;
  final Duration apnsPollInterval;
  _FcmPlatformPushTokenSession? _activeSession;
  bool _opening = false;
  bool _disposed = false;

  @override
  Future<PlatformPushTokenSession?> open() async {
    if (_disposed) {
      throw const PlatformPushTokenSourceException(
        'Push token acquisition has been disposed.',
      );
    }
    if (_opening || _activeSession != null) {
      throw const PlatformPushTokenSourceException(
        'Push token acquisition is already active.',
      );
    }
    _opening = true;
    try {
      try {
        if (!await _client.isSupported().timeout(operationTimeout)) return null;
        _ensureOpen();
        final permission = await _client.requestPermission().timeout(
          permissionTimeout,
        );
        _ensureOpen();
        if (permission != FcmPermissionStatus.authorized &&
            permission != FcmPermissionStatus.provisional) {
          return null;
        }
        if (requiresApnsToken) await _waitForApnsToken();
        _ensureOpen();

        late final _FcmPlatformPushTokenSession session;
        session = _FcmPlatformPushTokenSession(
          refreshTokens: _client.onTokenRefresh,
          onClosed: () {
            if (identical(_activeSession, session)) _activeSession = null;
          },
        );
        _activeSession = session;
        try {
          final token = await _client
              .getToken(
                vapidKey: vapidKey,
                serviceWorkerScriptPath: serviceWorkerScriptPath,
              )
              .timeout(operationTimeout);
          if (_disposed || !identical(_activeSession, session)) {
            await session.close();
            throw const PlatformPushTokenSourceException(
              'Push token acquisition has been disposed.',
            );
          }
          session.completeInitialToken(token);
          return session;
        } on PlatformPushTokenSourceException {
          rethrow;
        } catch (_) {
          await session.close();
          throw const PlatformPushTokenSourceException(
            'FCM token acquisition failed.',
          );
        }
      } on PlatformPushTokenSourceException {
        rethrow;
      } catch (_) {
        throw const PlatformPushTokenSourceException(
          'FCM token acquisition failed.',
        );
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _waitForApnsToken() async {
    final deadline = DateTime.now().add(apnsWaitTimeout);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw const PlatformPushTokenSourceException(
          'APNs token acquisition timed out.',
        );
      }
      if ((await _client.getApnsToken().timeout(remaining))?.isNotEmpty ??
          false) {
        return;
      }
      _ensureOpen();
      await Future<void>.delayed(apnsPollInterval);
    }
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const PlatformPushTokenSourceException(
        'Push token acquisition has been disposed.',
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _activeSession?.close();
    _activeSession = null;
  }
}

final class FcmCompileTimeConfiguration {
  const FcmCompileTimeConfiguration({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    this.authDomain,
    this.storageBucket,
    this.measurementId,
    this.vapidKey,
    this.serviceWorkerScriptPath = 'firebase-messaging-sw.js',
  });

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String? authDomain;
  final String? storageBucket;
  final String? measurementId;
  final String? vapidKey;
  final String serviceWorkerScriptPath;

  static FcmCompileTimeConfiguration? fromEnvironment() {
    const apiKey = String.fromEnvironment('WAMP_APP_FIREBASE_API_KEY');
    const appId = String.fromEnvironment('WAMP_APP_FIREBASE_APP_ID');
    const senderId = String.fromEnvironment(
      'WAMP_APP_FIREBASE_MESSAGING_SENDER_ID',
    );
    const projectId = String.fromEnvironment('WAMP_APP_FIREBASE_PROJECT_ID');
    const authDomain = String.fromEnvironment('WAMP_APP_FIREBASE_AUTH_DOMAIN');
    const storageBucket = String.fromEnvironment(
      'WAMP_APP_FIREBASE_STORAGE_BUCKET',
    );
    const measurementId = String.fromEnvironment(
      'WAMP_APP_FIREBASE_MEASUREMENT_ID',
    );
    const vapidKey = String.fromEnvironment('WAMP_APP_FIREBASE_VAPID_KEY');
    const workerPath = String.fromEnvironment(
      'WAMP_APP_FIREBASE_SERVICE_WORKER',
      defaultValue: 'firebase-messaging-sw.js',
    );
    final requiredValues = [apiKey, appId, senderId, projectId];
    if (requiredValues.every((value) => value.isEmpty)) return null;
    final configuration = FcmCompileTimeConfiguration(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      measurementId: measurementId.isEmpty ? null : measurementId,
      vapidKey: vapidKey.isEmpty ? null : vapidKey,
      serviceWorkerScriptPath: workerPath,
    );
    configuration.validate(isWeb: kIsWeb);
    return configuration;
  }

  void validate({required bool isWeb}) {
    final requiredValues = {
      'API key': apiKey,
      'app ID': appId,
      'messaging sender ID': messagingSenderId,
      'project ID': projectId,
    };
    for (final MapEntry(key: name, value: value) in requiredValues.entries) {
      if (value.isEmpty || value != value.trim()) {
        throw FormatException('Firebase $name is missing or malformed.');
      }
    }
    if (serviceWorkerScriptPath.isEmpty ||
        serviceWorkerScriptPath != serviceWorkerScriptPath.trim()) {
      throw const FormatException(
        'The Firebase service-worker path is malformed.',
      );
    }
    if (isWeb && (vapidKey == null || vapidKey!.trim().isEmpty)) {
      throw const FormatException('The Firebase web VAPID key is required.');
    }
  }

  FirebaseOptions toFirebaseOptions() => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: authDomain,
    storageBucket: storageBucket,
    measurementId: measurementId,
  );
}

final class _ConfiguredFcmPlatformPushTokenSource
    implements PlatformPushTokenSource {
  _ConfiguredFcmPlatformPushTokenSource(this.configuration);

  final FcmCompileTimeConfiguration configuration;
  PlatformPushTokenSource? _delegate;
  Future<PlatformPushTokenSource>? _initialization;
  bool _disposed = false;

  @override
  Future<PlatformPushTokenSession?> open() async {
    if (_disposed) {
      throw const PlatformPushTokenSourceException(
        'Push token acquisition has been disposed.',
      );
    }
    final delegate =
        _delegate ??
        await (_initialization ??= _initializeConfiguredFcmSource(
          configuration,
        ));
    if (_disposed) {
      await delegate.dispose();
      throw const PlatformPushTokenSourceException(
        'Push token acquisition has been disposed.',
      );
    }
    _delegate = delegate;
    return delegate.open();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final initialization = _initialization;
    final delegate = initialization == null ? _delegate : await initialization;
    await delegate?.dispose();
    _delegate = null;
  }
}

Future<PlatformPushTokenSource> _initializeConfiguredFcmSource(
  FcmCompileTimeConfiguration configuration,
) async {
  try {
    FirebaseApp app;
    try {
      app = Firebase.app();
    } on FirebaseException {
      app = await Firebase.initializeApp(
        options: configuration.toFirebaseOptions(),
      ).timeout(const Duration(seconds: 15));
    }
    if (!_matchesConfiguration(app.options, configuration)) {
      return const UnavailablePlatformPushTokenSource(
        'Firebase push configuration conflicts with the active app.',
      );
    }
    return FcmPlatformPushTokenSource(
      client: _FirebaseMessagingClient(FirebaseMessaging.instance),
      requiresApnsToken:
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS),
      vapidKey: kIsWeb ? configuration.vapidKey : null,
      serviceWorkerScriptPath: kIsWeb
          ? configuration.serviceWorkerScriptPath
          : null,
    );
  } catch (_) {
    return const UnavailablePlatformPushTokenSource(
      'Firebase push initialization failed.',
    );
  }
}

PlatformPushTokenSource createConfiguredPlatformPushTokenSource() {
  FcmCompileTimeConfiguration? configuration;
  try {
    configuration = FcmCompileTimeConfiguration.fromEnvironment();
  } catch (_) {
    return const UnavailablePlatformPushTokenSource(
      'Firebase push configuration is invalid.',
    );
  }
  if (configuration == null) {
    return const DisabledPlatformPushTokenSource();
  }
  return _ConfiguredFcmPlatformPushTokenSource(configuration);
}

bool _matchesConfiguration(
  FirebaseOptions options,
  FcmCompileTimeConfiguration configuration,
) =>
    options.apiKey == configuration.apiKey &&
    options.appId == configuration.appId &&
    options.messagingSenderId == configuration.messagingSenderId &&
    options.projectId == configuration.projectId;

final class _FirebaseMessagingClient implements FcmMessagingClient {
  const _FirebaseMessagingClient(this.messaging);

  final FirebaseMessaging messaging;

  @override
  Stream<String> get onTokenRefresh => messaging.onTokenRefresh;

  @override
  Future<String?> getApnsToken() => messaging.getAPNSToken();

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) => messaging.getToken(
    vapidKey: vapidKey,
    serviceWorkerScriptPath: serviceWorkerScriptPath,
  );

  @override
  Future<bool> isSupported() => messaging.isSupported();

  @override
  Future<FcmPermissionStatus> requestPermission() async {
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => FcmPermissionStatus.authorized,
      AuthorizationStatus.provisional => FcmPermissionStatus.provisional,
      AuthorizationStatus.denied ||
      AuthorizationStatus.deniedPermanently => FcmPermissionStatus.denied,
      AuthorizationStatus.notDetermined => FcmPermissionStatus.notDetermined,
    };
  }
}

final class _FcmPlatformPushTokenSession implements PlatformPushTokenSession {
  _FcmPlatformPushTokenSession({
    required Stream<String> refreshTokens,
    required this.onClosed,
  }) {
    _controller.onListen = () => _listened = true;
    _refreshSubscription = refreshTokens.listen(
      _recordRefresh,
      onError: (_) => _controller.addError(
        const PlatformPushTokenSourceException('FCM token refresh failed.'),
      ),
    );
  }

  final void Function() onClosed;
  final _controller = StreamController<PlatformPushToken>();
  final _pendingRefreshes = <String>[];
  StreamSubscription<String>? _refreshSubscription;
  String? _lastToken;
  bool _initialComplete = false;
  bool _listened = false;
  bool _closed = false;

  @override
  Stream<PlatformPushToken> get tokens => _controller.stream;

  void completeInitialToken(String? token) {
    if (_closed || _initialComplete) return;
    _initialComplete = true;
    if (token != null) _emit(token);
    for (final refresh in _pendingRefreshes) {
      _emit(refresh);
    }
    _pendingRefreshes.clear();
  }

  void _recordRefresh(String token) {
    if (_closed) return;
    if (!_initialComplete) {
      _pendingRefreshes.add(token);
      return;
    }
    _emit(token);
  }

  void _emit(String token) {
    if (_closed || token == _lastToken) return;
    final pushToken = PlatformPushToken(provider: 'fcm', token: token);
    try {
      pushToken.validate();
    } catch (_) {
      _controller.addError(
        const PlatformPushTokenSourceException(
          'FCM returned an invalid registration token.',
        ),
      );
      return;
    }
    _lastToken = token;
    _controller.add(pushToken);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    Object? closeError;
    StackTrace? closeStackTrace;
    try {
      await _refreshSubscription?.cancel();
    } catch (error, stackTrace) {
      closeError = error;
      closeStackTrace = stackTrace;
    }
    _refreshSubscription = null;
    _pendingRefreshes.clear();
    _lastToken = null;
    try {
      final closed = _controller.close();
      if (_listened) await closed;
    } catch (error, stackTrace) {
      closeError ??= error;
      closeStackTrace ??= stackTrace;
    }
    onClosed();
    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace!);
    }
  }
}
