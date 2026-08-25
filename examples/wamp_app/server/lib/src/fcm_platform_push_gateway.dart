import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:googleapis_auth/auth_io.dart' as google_auth;
import 'package:http/http.dart' as http;

import 'platform_push_service.dart';
import 'server_config.dart';

final class FcmPlatformPushGateway implements PlatformPushGateway {
  FcmPlatformPushGateway({
    required String projectId,
    required http.Client client,
    Uri? endpoint,
    this.maxResponseBytes = 64 * 1024,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _client = client,
       _endpoint = endpoint ?? _endpointForProject(projectId) {
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
  }

  static const _messagingScope =
      'https://www.googleapis.com/auth/firebase.messaging';
  static const _maxCredentialBytes = 128 * 1024;
  static const _invalidTokenCodes = {
    'INVALID_ARGUMENT',
    'SENDER_ID_MISMATCH',
    'UNREGISTERED',
  };
  static final _projectIdPattern = RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$');

  final http.Client _client;
  final Uri _endpoint;
  final int maxResponseBytes;
  final Duration requestTimeout;
  bool _closed = false;

  @override
  Set<String> get providers => const {'fcm'};

  static Future<FcmPlatformPushGateway> fromConfig(
    FcmPlatformPushConfig config, {
    Duration initializationTimeout = const Duration(seconds: 15),
  }) async {
    if (initializationTimeout <= Duration.zero) {
      throw ArgumentError.value(initializationTimeout, 'initializationTimeout');
    }
    final baseClient = http.Client();
    http.Client? authenticatedClient;
    try {
      final credentials = await _loadCredentials(config.serviceAccountPath);
      final projectId = config.projectId ?? credentials.projectId;
      if (projectId == null) {
        throw const FormatException('FCM project ID is missing.');
      }
      authenticatedClient = await google_auth
          .clientViaServiceAccount(credentials, const [
            _messagingScope,
          ], baseClient: baseClient)
          .timeout(initializationTimeout);
      return FcmPlatformPushGateway(
        projectId: projectId,
        client: authenticatedClient,
      );
    } catch (_) {
      (authenticatedClient ?? baseClient).close();
      throw StateError('FCM platform push initialization failed.');
    }
  }

  @override
  Future<PlatformPushDeliveryResult> deliver({
    required String provider,
    required String token,
    required int cursor,
  }) async {
    if (_closed || provider != 'fcm' || cursor <= 0) {
      return PlatformPushDeliveryResult.retryableFailure;
    }
    try {
      final request = http.Request('POST', _endpoint)
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'message': {
            'token': token,
            'data': {'cursor': '$cursor'},
            'android': {'priority': 'HIGH'},
            'apns': {
              'headers': {'apns-push-type': 'background', 'apns-priority': '5'},
              'payload': {
                'aps': {'content-available': 1},
              },
            },
            'webpush': {
              'headers': {'Urgency': 'high'},
            },
          },
        });
      final response = await _client.send(request).timeout(requestTimeout);
      final body = await _readBounded(response.stream);
      if (body == null) return PlatformPushDeliveryResult.retryableFailure;
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map<String, dynamic>) {
        return PlatformPushDeliveryResult.retryableFailure;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final name = decoded['name'];
        return name is String && name.trim().isNotEmpty
            ? PlatformPushDeliveryResult.accepted
            : PlatformPushDeliveryResult.retryableFailure;
      }
      final errorCode = _fcmErrorCode(decoded);
      return _invalidTokenCodes.contains(errorCode)
          ? PlatformPushDeliveryResult.invalidToken
          : PlatformPushDeliveryResult.retryableFailure;
    } catch (_) {
      return PlatformPushDeliveryResult.retryableFailure;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  Future<Uint8List?> _readBounded(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in stream) {
      length += chunk.length;
      if (length > maxResponseBytes) return null;
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static Future<google_auth.ServiceAccountCredentials> _loadCredentials(
    String path,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in File(path).openRead()) {
      length += chunk.length;
      if (length > _maxCredentialBytes) {
        throw const FormatException('FCM credential file is too large.');
      }
      bytes.add(chunk);
    }
    final document = bytes.takeBytes();
    if (document.isEmpty) {
      throw const FormatException('FCM credential file is empty.');
    }
    try {
      return google_auth.ServiceAccountCredentials.fromJson(
        utf8.decode(document),
      );
    } finally {
      document.fillRange(0, document.length, 0);
    }
  }

  static Uri _endpointForProject(String projectId) {
    if (!_projectIdPattern.hasMatch(projectId)) {
      throw ArgumentError.value(projectId, 'projectId');
    }
    return Uri.https(
      'fcm.googleapis.com',
      '/v1/projects/$projectId/messages:send',
    );
  }

  static String? _fcmErrorCode(Map<String, dynamic> response) {
    final error = response['error'];
    if (error is! Map) return null;
    final details = error['details'];
    if (details is! List) return null;
    for (final detail in details) {
      if (detail is Map &&
          detail['@type'] ==
              'type.googleapis.com/google.firebase.fcm.v1.FcmError') {
        final errorCode = detail['errorCode'];
        if (errorCode is String) return errorCode;
      }
    }
    return null;
  }
}
