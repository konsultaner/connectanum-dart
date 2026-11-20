import 'dart:io';

import 'package:test/test.dart';

/// Observe the real clients owned by one CLI invocation, including idle clients.
/// Cleanup prevents a detected leak from keeping the test process alive. An
/// infrastructure failure remains the original exception; it earns no credit.
Future<T> expectOwnedHttpClientsClosed<T>(Future<T> Function() body) {
  final tracker = _OwnedHttpOverrides(HttpOverrides.current);
  return HttpOverrides.runWithHttpOverrides(() async {
    var completed = false;
    try {
      final value = await body();
      completed = true;
      return value;
    } finally {
      final leaked = tracker.clients.where((client) => !client.closed).toList();
      for (final client in leaked) {
        client.close(force: true);
      }
      if (completed) {
        expect(
          leaked,
          isEmpty,
          reason: 'The CLI must close every owned HTTP client',
        );
      }
    }
  }, tracker);
}

class _OwnedHttpOverrides extends HttpOverrides {
  _OwnedHttpOverrides(this.parent);
  final HttpOverrides? parent;
  final clients = <_OwnedHttpClient>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _OwnedHttpClient(
      parent?.createHttpClient(context) ?? super.createHttpClient(context),
    );
    clients.add(client);
    return client;
  }
}

class _OwnedHttpClient implements HttpClient {
  _OwnedHttpClient(this.delegate);
  final HttpClient delegate;
  bool closed = false;

  @override
  void close({bool force = false}) {
    delegate.close(force: force);
    closed = true;
  }

  @override
  Duration get idleTimeout => delegate.idleTimeout;
  @override
  set idleTimeout(Duration value) => delegate.idleTimeout = value;
  @override
  Duration? get connectionTimeout => delegate.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;
  @override
  bool get autoUncompress => delegate.autoUncompress;
  @override
  set autoUncompress(bool value) => delegate.autoUncompress = value;
  @override
  String? get userAgent => delegate.userAgent;
  @override
  set userAgent(String? value) => delegate.userAgent = value;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      delegate.openUrl(method, url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => delegate.getUrl(url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => delegate.postUrl(url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => delegate.deleteUrl(url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => delegate.putUrl(url);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => delegate.patchUrl(url);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => delegate.headUrl(url);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
