import 'dart:async';
import 'dart:io';

import 'oauth_authorization.dart';

const _defaultCallbackPath = '/oauth/callback';
const _defaultCallbackTimeout = Duration(minutes: 2);
const _defaultMaxRequests = 16;
const _successPage = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Authorization complete</title></head>
<body><p>Authorization complete. You can close this window.</p></body></html>''';
const _failurePage = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Authorization failed</title></head>
<body><p>Authorization failed. Return to the application for details.</p></body></html>''';
const _invalidRequestPage = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Invalid request</title></head>
<body><p>This request cannot complete authorization.</p></body></html>''';

/// A redacted failure from the native OAuth loopback callback listener.
final class McpOAuthLoopbackCallbackException implements Exception {
  const McpOAuthLoopbackCallbackException(this.message, {this.redirectUri});

  final String message;
  final Uri? redirectUri;

  @override
  String toString() => 'McpOAuthLoopbackCallbackException: $message';
}

/// Receives one native OAuth authorization response on a loopback IP literal.
final class McpOAuthLoopbackCallbackListener {
  McpOAuthLoopbackCallbackListener._(this._server, this.redirectUri);

  final HttpServer _server;

  /// The exact redirect URI to register and use for the authorization request.
  final Uri redirectUri;

  bool _started = false;
  bool _closed = false;

  /// Whether this listener has released its bound socket.
  bool get isClosed => _closed;

  /// Binds an RFC 8252 loopback redirect listener.
  ///
  /// The default address tries the IPv4 loopback IP literal, then IPv6 when
  /// IPv4 is unavailable; the default port is ephemeral. Pass an explicit
  /// loopback address when one IP family is required.
  static Future<McpOAuthLoopbackCallbackListener> bind({
    InternetAddress? address,
    int port = 0,
    String path = _defaultCallbackPath,
  }) async {
    if (address != null && !address.isLoopback) {
      throw ArgumentError.value(
        address,
        'address',
        'OAuth callbacks may bind only a loopback IP address.',
      );
    }
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Must be between 0 and 65535.');
    }
    if (!_validCallbackPath(path)) {
      throw ArgumentError.value(
        path,
        'path',
        'Must be an absolute, authority-free callback path without a query.',
      );
    }

    late final HttpServer server;
    if (address != null) {
      server = await HttpServer.bind(address, port, shared: false);
    } else {
      try {
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          port,
          shared: false,
        );
      } on SocketException {
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv6,
          port,
          shared: false,
        );
      }
    }
    final redirectUri = Uri(
      scheme: 'http',
      host: server.address.address,
      port: server.port,
      path: path,
    );
    return McpOAuthLoopbackCallbackListener._(server, redirectUri);
  }

  /// Waits once for the authorization response that matches [request].
  ///
  /// Unrelated local requests receive a static rejection and do not complete
  /// the flow, but they consume [maxRequests]. The [timeout] is a total deadline
  /// shared by every request. The listener closes on every terminal outcome.
  Future<McpAuthorizationCode> waitForAuthorizationCode({
    required McpAuthorizationRequest request,
    Duration timeout = _defaultCallbackTimeout,
    int maxRequests = _defaultMaxRequests,
  }) async {
    if (_started || _closed) {
      throw McpOAuthLoopbackCallbackException(
        'The loopback callback listener can be awaited only once.',
        redirectUri: redirectUri,
      );
    }
    _started = true;
    final requests = StreamIterator<HttpRequest>(_server);
    final stopwatch = Stopwatch()..start();
    try {
      if (timeout <= Duration.zero) {
        throw ArgumentError.value(
          timeout,
          'timeout',
          'Must be greater than zero.',
        );
      }
      if (maxRequests <= 0) {
        throw ArgumentError.value(
          maxRequests,
          'maxRequests',
          'Must be greater than zero.',
        );
      }
      if (request.redirectUri != redirectUri) {
        throw McpOAuthLoopbackCallbackException(
          'The authorization request uses a different redirect URI.',
          redirectUri: redirectUri,
        );
      }

      for (var attempt = 0; attempt < maxRequests; attempt += 1) {
        final remaining = timeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('OAuth loopback callback timed out.');
        }
        final hasRequest = await requests.moveNext().timeout(remaining);
        if (!hasRequest) {
          throw McpOAuthLoopbackCallbackException(
            'The loopback callback listener closed before authorization.',
            redirectUri: redirectUri,
          );
        }
        final incoming = requests.current;
        if (incoming.method != 'GET') {
          await _respond(
            incoming,
            statusCode: HttpStatus.methodNotAllowed,
            body: _invalidRequestPage,
            allow: 'GET',
          );
          continue;
        }
        if (incoming.uri.path != redirectUri.path) {
          await _respond(
            incoming,
            statusCode: HttpStatus.notFound,
            body: _invalidRequestPage,
          );
          continue;
        }

        final states = incoming.uri.queryParametersAll['state'];
        if (states == null ||
            states.length != 1 ||
            states.single != request.state) {
          await _respond(
            incoming,
            statusCode: HttpStatus.badRequest,
            body: _invalidRequestPage,
          );
          continue;
        }

        final callbackUri = redirectUri.replace(
          query: incoming.uri.hasQuery ? incoming.uri.query : null,
        );
        try {
          final code = parseMcpAuthorizationCallback(
            callbackUri,
            request: request,
          );
          await _respond(
            incoming,
            statusCode: HttpStatus.ok,
            body: _successPage,
          );
          return code;
        } on McpAuthorizationFlowException catch (error) {
          await _respond(
            incoming,
            statusCode: HttpStatus.badRequest,
            body: _failurePage,
          );
          throw McpAuthorizationFlowException(
            'Authorization callback was rejected.',
            uri: redirectUri,
            oauthError: error.oauthError,
            errorDescription: error.errorDescription,
            errorUri: error.errorUri,
          );
        }
      }

      throw McpOAuthLoopbackCallbackException(
        'Too many unrelated requests reached the loopback callback listener.',
        redirectUri: redirectUri,
      );
    } on TimeoutException {
      throw McpOAuthLoopbackCallbackException(
        'Timed out waiting for the OAuth authorization response.',
        redirectUri: redirectUri,
      );
    } finally {
      stopwatch.stop();
      try {
        await requests.cancel();
      } finally {
        await close();
      }
    }
  }

  /// Releases the bound socket. Calling this more than once is safe.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _server.close(force: true);
  }
}

bool _validCallbackPath(String path) {
  if (path.isEmpty || !path.startsWith('/') || path.startsWith('//')) {
    return false;
  }
  if (RegExp(r'[\x00-\x20\x7f\\]').hasMatch(path)) {
    return false;
  }
  final parsed = Uri.tryParse(path);
  return parsed != null &&
      !parsed.isAbsolute &&
      !parsed.hasAuthority &&
      !parsed.hasQuery &&
      !parsed.hasFragment &&
      parsed.path == path;
}

Future<void> _respond(
  HttpRequest request, {
  required int statusCode,
  required String body,
  String? allow,
}) async {
  try {
    final response = request.response;
    response.statusCode = statusCode;
    response.headers
      ..contentType = ContentType('text', 'html', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set(HttpHeaders.pragmaHeader, 'no-cache')
      ..set(HttpHeaders.connectionHeader, 'close')
      ..set(
        'content-security-policy',
        "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
      )
      ..set('referrer-policy', 'no-referrer')
      ..set('x-content-type-options', 'nosniff');
    if (allow != null) {
      response.headers.set(HttpHeaders.allowHeader, allow);
    }
    response.write(body);
    await response.close();
  } on HttpException {
    // A browser may close its loopback connection after sending the callback.
  } on SocketException {
    // The parsed callback remains authoritative when the response is dropped.
  } on StateError {
    // The response may already be closed by the peer or server shutdown.
  }
}
