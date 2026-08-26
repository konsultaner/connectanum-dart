import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/fcm_platform_push_token_source.dart';
import 'package:wamp_app/src/infrastructure/platform_push_token_source.dart';

void main() {
  test('compile-time configuration validates required web values', () {
    const valid = FcmCompileTimeConfiguration(
      apiKey: 'api-key',
      appId: 'app-id',
      messagingSenderId: 'sender-id',
      projectId: 'project-id',
      vapidKey: 'vapid-key',
    );
    expect(() => valid.validate(isWeb: true), returnsNormally);

    const missingVapid = FcmCompileTimeConfiguration(
      apiKey: 'api-key',
      appId: 'app-id',
      messagingSenderId: 'sender-id',
      projectId: 'project-id',
    );
    expect(
      () => missingVapid.validate(isWeb: true),
      throwsA(isA<FormatException>()),
    );

    const partial = FcmCompileTimeConfiguration(
      apiKey: 'api-key',
      appId: '',
      messagingSenderId: 'sender-id',
      projectId: 'project-id',
    );
    expect(
      () => partial.validate(isWeb: false),
      throwsA(isA<FormatException>()),
    );
  });

  test('unsupported and denied clients do not request a token', () async {
    final unsupported = _FakeFcmClient()..supported = false;
    final unsupportedSource = FcmPlatformPushTokenSource(
      client: unsupported,
      requiresApnsToken: false,
    );
    expect(await unsupportedSource.open(), isNull);
    expect(unsupported.permissionRequests, 0);
    expect(unsupported.tokenRequests, 0);
    await unsupportedSource.dispose();

    final denied = _FakeFcmClient()..permission = FcmPermissionStatus.denied;
    final deniedSource = FcmPlatformPushTokenSource(
      client: denied,
      requiresApnsToken: false,
    );
    expect(await deniedSource.open(), isNull);
    expect(denied.permissionRequests, 1);
    expect(denied.tokenRequests, 0);
    await deniedSource.dispose();
  });

  test('buffers refreshes behind the initial token and deduplicates', () async {
    final client = _FakeFcmClient();
    final initial = Completer<String?>();
    client.tokenResult = initial.future;
    final source = FcmPlatformPushTokenSource(
      client: client,
      requiresApnsToken: false,
      vapidKey: 'vapid-key',
      serviceWorkerScriptPath: 'worker.js',
    );

    final opening = source.open();
    await client.waitUntilRefreshListened();
    client.emitRefresh('token-2');
    client.emitRefresh('token-2');
    initial.complete('token-1');
    final session = (await opening)!;
    final tokens = await session.tokens.take(2).toList();

    expect(tokens.map((token) => token.provider), ['fcm', 'fcm']);
    expect(tokens.map((token) => token.token), ['token-1', 'token-2']);
    expect(client.lastVapidKey, 'vapid-key');
    expect(client.lastWorkerPath, 'worker.js');

    await session.close();
    await source.dispose();
  });

  test('waits for APNs before requesting an FCM token', () async {
    final client = _FakeFcmClient()
      ..apnsTokens.addAll([null, null, 'apns-token']);
    final source = FcmPlatformPushTokenSource(
      client: client,
      requiresApnsToken: true,
      apnsWaitTimeout: const Duration(seconds: 1),
      apnsPollInterval: Duration.zero,
    );

    final session = await source.open();

    expect(session, isNotNull);
    expect(client.apnsRequests, 3);
    expect(client.tokenRequests, 1);
    await session!.close();
    await source.dispose();
  });

  test('APNs and provider failures are sanitized and fail closed', () async {
    final apnsClient = _FakeFcmClient();
    final apnsSource = FcmPlatformPushTokenSource(
      client: apnsClient,
      requiresApnsToken: true,
      apnsWaitTimeout: Duration.zero,
      apnsPollInterval: Duration.zero,
    );
    await expectLater(
      apnsSource.open(),
      throwsA(
        isA<PlatformPushTokenSourceException>().having(
          (error) => error.message,
          'message',
          'APNs token acquisition timed out.',
        ),
      ),
    );
    expect(apnsClient.tokenRequests, 0);
    await apnsSource.dispose();

    final providerClient = _FakeFcmClient()
      ..tokenFailure = StateError('secret provider details');
    final providerSource = FcmPlatformPushTokenSource(
      client: providerClient,
      requiresApnsToken: false,
    );
    await expectLater(
      providerSource.open(),
      throwsA(
        isA<PlatformPushTokenSourceException>().having(
          (error) => error.message,
          'message',
          'FCM token acquisition failed.',
        ),
      ),
    );
    expect(_clientRefreshListenerCount(providerClient), 0);
    await providerSource.dispose();
  });

  test('token timeout and disposal reject late provider results', () async {
    final timeoutClient = _FakeFcmClient()
      ..tokenResult = Completer<String?>().future;
    final timeoutSource = FcmPlatformPushTokenSource(
      client: timeoutClient,
      requiresApnsToken: false,
      operationTimeout: Duration.zero,
    );
    await expectLater(
      timeoutSource.open(),
      throwsA(
        isA<PlatformPushTokenSourceException>().having(
          (error) => error.message,
          'message',
          'FCM token acquisition failed.',
        ),
      ),
    );
    expect(_clientRefreshListenerCount(timeoutClient), 0);
    await timeoutSource.dispose();

    final disposalClient = _FakeFcmClient();
    final lateToken = Completer<String?>();
    disposalClient.tokenResult = lateToken.future;
    final disposalSource = FcmPlatformPushTokenSource(
      client: disposalClient,
      requiresApnsToken: false,
    );
    final opening = disposalSource.open();
    await disposalClient.waitUntilRefreshListened();
    final disposal = disposalSource.dispose();
    lateToken.complete('late-token');
    await disposal;
    await expectLater(
      opening,
      throwsA(
        isA<PlatformPushTokenSourceException>().having(
          (error) => error.message,
          'message',
          'Push token acquisition has been disposed.',
        ),
      ),
    );
    expect(_clientRefreshListenerCount(disposalClient), 0);
  });

  test('close cancels refresh delivery and allows a new session', () async {
    final client = _FakeFcmClient();
    final source = FcmPlatformPushTokenSource(
      client: client,
      requiresApnsToken: false,
    );
    final first = (await source.open())!;
    await expectLater(
      source.open(),
      throwsA(isA<PlatformPushTokenSourceException>()),
    );
    await first.close();
    expect(_clientRefreshListenerCount(client), 0);

    final second = await source.open();
    expect(second, isNotNull);
    await source.dispose();
    expect(_clientRefreshListenerCount(client), 0);
    await expectLater(
      source.open(),
      throwsA(isA<PlatformPushTokenSourceException>()),
    );
  });

  test(
    'concurrent opens and cancellation failures cannot retain a session',
    () async {
      final client = _FakeFcmClient();
      final supported = Completer<bool>();
      client
        ..supportedResult = supported.future
        ..failRefreshCancellation = true;
      final source = FcmPlatformPushTokenSource(
        client: client,
        requiresApnsToken: false,
      );

      final firstOpening = source.open();
      await expectLater(
        source.open(),
        throwsA(isA<PlatformPushTokenSourceException>()),
      );
      supported.complete(true);
      final first = (await firstOpening)!;

      await expectLater(first.close(), throwsA(isA<StateError>()));
      expect(_clientRefreshListenerCount(client), 0);

      client
        ..failRefreshCancellation = false
        ..supportedResult = null;
      final second = await source.open();
      expect(second, isNotNull);
      await second!.close();
      await source.dispose();
    },
  );
}

int _clientRefreshListenerCount(_FakeFcmClient client) =>
    client.refreshListeners;

final class _FakeFcmClient implements FcmMessagingClient {
  final _refreshes = StreamController<String>.broadcast();
  final _refreshListened = Completer<void>();
  final apnsTokens = <String?>[];
  bool supported = true;
  Future<bool>? supportedResult;
  bool failRefreshCancellation = false;
  FcmPermissionStatus permission = FcmPermissionStatus.authorized;
  Future<String?> tokenResult = Future<String?>.value('token-1');
  Object? tokenFailure;
  int permissionRequests = 0;
  int tokenRequests = 0;
  int apnsRequests = 0;
  int refreshListeners = 0;
  String? lastVapidKey;
  String? lastWorkerPath;

  _FakeFcmClient() {
    _refreshes
      ..onListen = () {
        refreshListeners += 1;
        if (!_refreshListened.isCompleted) _refreshListened.complete();
      }
      ..onCancel = () => refreshListeners -= 1;
  }

  @override
  Stream<String> get onTokenRefresh => failRefreshCancellation
      ? _FailingCancelStream(_refreshes.stream)
      : _refreshes.stream;

  @override
  Future<String?> getApnsToken() async {
    apnsRequests += 1;
    return apnsTokens.isEmpty ? null : apnsTokens.removeAt(0);
  }

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) {
    tokenRequests += 1;
    lastVapidKey = vapidKey;
    lastWorkerPath = serviceWorkerScriptPath;
    final failure = tokenFailure;
    return failure == null ? tokenResult : Future<String?>.error(failure);
  }

  @override
  Future<bool> isSupported() =>
      supportedResult ?? Future<bool>.value(supported);

  @override
  Future<FcmPermissionStatus> requestPermission() async {
    permissionRequests += 1;
    return permission;
  }

  Future<void> waitUntilRefreshListened() => _refreshListened.future;

  void emitRefresh(String token) => _refreshes.add(token);
}

final class _FailingCancelStream extends Stream<String> {
  const _FailingCancelStream(this.delegate);

  final Stream<String> delegate;

  @override
  StreamSubscription<String> listen(
    void Function(String event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _FailingCancelSubscription(
    delegate.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
  );
}

final class _FailingCancelSubscription implements StreamSubscription<String> {
  const _FailingCancelSubscription(this.delegate);

  final StreamSubscription<String> delegate;

  @override
  Future<void> cancel() async {
    await delegate.cancel();
    throw StateError('refresh cancellation failed');
  }

  @override
  void onData(void Function(String data)? handleData) =>
      delegate.onData(handleData);

  @override
  void onError(Function? handleError) => delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => delegate.pause(resumeSignal);

  @override
  void resume() => delegate.resume();

  @override
  bool get isPaused => delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => delegate.asFuture(futureValue);
}
