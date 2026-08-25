import 'dart:convert';
import 'dart:typed_data';

import 'account_registration.dart';

enum CallMediaKind { voice, video }

enum CallState { ringing, active, declined, cancelled, ended, missed }

enum CallSignalKind { offer, answer, iceCandidate, decline, hangup }

abstract final class WampAppCallLimits {
  static const maximumDevicesPerCall = 16;
  static const maximumSignalPlaintextBytes = 256 * 1024;
  static const sealedBoxOverheadBytes = 48;
  static const maximumSignalCiphertextBytes =
      maximumSignalPlaintextBytes + sealedBoxOverheadBytes;
  static const maximumSignalsPerCall = 4096;
}

/// A device-targeted WebRTC signal whose payload is opaque to the router.
final class EncryptedCallSignal {
  EncryptedCallSignal({
    required this.callId,
    required this.signalId,
    required this.kind,
    required String senderUsername,
    required this.senderDeviceId,
    required String recipientUsername,
    required this.recipientDeviceId,
    required Uint8List sealedPayload,
    required this.signature,
    required DateTime createdAt,
  }) : senderUsername = AccountRegistration.normalizeUsername(senderUsername),
       recipientUsername = AccountRegistration.normalizeUsername(
         recipientUsername,
       ),
       _sealedPayload = Uint8List.fromList(sealedPayload),
       createdAt = createdAt.toUtc() {
    validate();
  }

  static const version = 'wampapp-call-signal-v1';
  static const algorithm = 'x25519-xsalsa20poly1305-sealedbox+ed25519';

  final String callId;
  final String signalId;
  final CallSignalKind kind;
  final String senderUsername;
  final String senderDeviceId;
  final String recipientUsername;
  final String recipientDeviceId;
  final Uint8List _sealedPayload;
  final String signature;
  final DateTime createdAt;

  Uint8List get sealedPayload => Uint8List.fromList(_sealedPayload);

  void validate() {
    _validateOpaqueId(callId, 'call_id');
    _validateOpaqueId(signalId, 'signal_id');
    _validateUsername(senderUsername, 'sender_username');
    _validateUsername(recipientUsername, 'recipient_username');
    if (senderUsername == recipientUsername) {
      throw const FormatException('Call signal participants must differ.');
    }
    _validateBase64Url(senderDeviceId, 'sender_device_id', expectedBytes: 32);
    _validateBase64Url(
      recipientDeviceId,
      'recipient_device_id',
      expectedBytes: 32,
    );
    if (_sealedPayload.length <= WampAppCallLimits.sealedBoxOverheadBytes ||
        _sealedPayload.length >
            WampAppCallLimits.maximumSignalCiphertextBytes) {
      throw const FormatException('Encrypted call signal size is invalid.');
    }
    _validateBase64Url(signature, 'signature', expectedBytes: 64);
    if (!createdAt.isUtc) {
      throw const FormatException('Call signal time must be UTC.');
    }
  }

  List<int> signaturePayload() {
    validate();
    return signaturePayloadFor(
      callId: callId,
      signalId: signalId,
      kind: kind,
      senderUsername: senderUsername,
      senderDeviceId: senderDeviceId,
      recipientUsername: recipientUsername,
      recipientDeviceId: recipientDeviceId,
      sealedPayload: _sealedPayload,
      createdAt: createdAt,
    );
  }

  static List<int> signaturePayloadFor({
    required String callId,
    required String signalId,
    required CallSignalKind kind,
    required String senderUsername,
    required String senderDeviceId,
    required String recipientUsername,
    required String recipientDeviceId,
    required Uint8List sealedPayload,
    required DateTime createdAt,
  }) => utf8.encode(
    <String>[
      version,
      algorithm,
      callId,
      signalId,
      kind.name,
      AccountRegistration.normalizeUsername(senderUsername),
      senderDeviceId,
      AccountRegistration.normalizeUsername(recipientUsername),
      recipientDeviceId,
      base64Url.encode(sealedPayload).replaceAll('=', ''),
      createdAt.toUtc().toIso8601String(),
    ].join('\n'),
  );

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'version': version,
      'algorithm': algorithm,
      'call_id': callId,
      'signal_id': signalId,
      'kind': kind.name,
      'sender_username': senderUsername,
      'sender_device_id': senderDeviceId,
      'recipient_username': recipientUsername,
      'recipient_device_id': recipientDeviceId,
      'sealed_payload': Uint8List.fromList(_sealedPayload),
      'signature': signature,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => {
    ...toWampKeywords(),
    'sealed_payload': base64Url.encode(_sealedPayload),
  };

  factory EncryptedCallSignal.fromWampKeywords(Map<String, dynamic>? value) =>
      _fromMap(value, binaryPayload: true);

  factory EncryptedCallSignal.fromJson(Map<String, dynamic>? value) =>
      _fromMap(value, binaryPayload: false);

  static EncryptedCallSignal _fromMap(
    Map<String, dynamic>? value, {
    required bool binaryPayload,
  }) {
    if (value == null ||
        value['version'] != version ||
        value['algorithm'] != algorithm) {
      throw const FormatException('Unsupported encrypted call signal.');
    }
    final kind = _enumValue(CallSignalKind.values, value['kind'], 'kind');
    final rawPayload = value['sealed_payload'];
    final payload = binaryPayload
        ? _readBinary(rawPayload, 'sealed_payload')
        : _decodeBase64Url(rawPayload, 'sealed_payload');
    return EncryptedCallSignal(
      callId: _readString(value['call_id'], 'call_id'),
      signalId: _readString(value['signal_id'], 'signal_id'),
      kind: kind,
      senderUsername: _readString(value['sender_username'], 'sender_username'),
      senderDeviceId: _readString(
        value['sender_device_id'],
        'sender_device_id',
      ),
      recipientUsername: _readString(
        value['recipient_username'],
        'recipient_username',
      ),
      recipientDeviceId: _readString(
        value['recipient_device_id'],
        'recipient_device_id',
      ),
      sealedPayload: payload,
      signature: _readString(value['signature'], 'signature'),
      createdAt: _readUtcDate(value['created_at'], 'created_at'),
    );
  }
}

final class CallStartRequest {
  CallStartRequest({
    required this.media,
    required String calleeUsername,
    required Iterable<EncryptedCallSignal> offers,
  }) : calleeUsername = AccountRegistration.normalizeUsername(calleeUsername),
       offers = List<EncryptedCallSignal>.unmodifiable(offers) {
    validate();
  }

  final CallMediaKind media;
  final String calleeUsername;
  final List<EncryptedCallSignal> offers;

  String get callId => offers.first.callId;
  String get callerUsername => offers.first.senderUsername;
  String get callerDeviceId => offers.first.senderDeviceId;

  void validate() {
    _validateUsername(calleeUsername, 'callee_username');
    if (offers.isEmpty ||
        offers.length > WampAppCallLimits.maximumDevicesPerCall) {
      throw const FormatException('Call offer count is invalid.');
    }
    final first = offers.first;
    final recipientDevices = <String>{};
    for (final offer in offers) {
      offer.validate();
      if (offer.kind != CallSignalKind.offer ||
          offer.callId != first.callId ||
          offer.senderUsername != first.senderUsername ||
          offer.senderDeviceId != first.senderDeviceId ||
          offer.recipientUsername != calleeUsername ||
          !recipientDevices.add(offer.recipientDeviceId)) {
        throw const FormatException('Call offers are inconsistent.');
      }
    }
  }

  Map<String, dynamic> toWampKeywords() => {
    'media': media.name,
    'callee_username': calleeUsername,
    'offers': offers.map((offer) => offer.toWampKeywords()).toList(),
  };

  factory CallStartRequest.fromWampKeywords(Map<String, dynamic>? value) {
    final rawOffers = value?['offers'];
    if (rawOffers is! List) {
      throw const FormatException('Call offers must be a list.');
    }
    return CallStartRequest(
      media: _enumValue(CallMediaKind.values, value?['media'], 'media'),
      calleeUsername: _readString(value?['callee_username'], 'callee_username'),
      offers: rawOffers.map(
        (offer) =>
            EncryptedCallSignal.fromWampKeywords(_readMap(offer, 'offer')),
      ),
    );
  }
}

final class CallRecord {
  CallRecord({
    required this.callId,
    required String callerUsername,
    required this.callerDeviceId,
    required String calleeUsername,
    required this.media,
    required this.state,
    required DateTime createdAt,
    this.acceptedDeviceId,
    DateTime? answeredAt,
    DateTime? endedAt,
  }) : callerUsername = AccountRegistration.normalizeUsername(callerUsername),
       calleeUsername = AccountRegistration.normalizeUsername(calleeUsername),
       createdAt = createdAt.toUtc(),
       answeredAt = answeredAt?.toUtc(),
       endedAt = endedAt?.toUtc() {
    validate();
  }

  final String callId;
  final String callerUsername;
  final String callerDeviceId;
  final String calleeUsername;
  final CallMediaKind media;
  final CallState state;
  final String? acceptedDeviceId;
  final DateTime createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  bool get isTerminal => switch (state) {
    CallState.declined ||
    CallState.cancelled ||
    CallState.ended ||
    CallState.missed => true,
    _ => false,
  };

  void validate() {
    _validateOpaqueId(callId, 'call_id');
    _validateUsername(callerUsername, 'caller_username');
    _validateUsername(calleeUsername, 'callee_username');
    if (callerUsername == calleeUsername) {
      throw const FormatException('Call participants must differ.');
    }
    _validateBase64Url(callerDeviceId, 'caller_device_id', expectedBytes: 32);
    final acceptedDevice = acceptedDeviceId;
    if (acceptedDevice != null) {
      _validateBase64Url(
        acceptedDevice,
        'accepted_device_id',
        expectedBytes: 32,
      );
    }
    if ((state == CallState.active ||
            state == CallState.ended ||
            answeredAt != null) &&
        (acceptedDeviceId == null || answeredAt == null)) {
      throw const FormatException('Answered call metadata is incomplete.');
    }
    if (state == CallState.ringing &&
        (acceptedDeviceId != null || answeredAt != null || endedAt != null)) {
      throw const FormatException('Ringing call metadata is invalid.');
    }
    if (isTerminal && endedAt == null) {
      throw const FormatException('Terminal call end time is required.');
    }
    if (!isTerminal && endedAt != null) {
      throw const FormatException('Active call cannot have an end time.');
    }
    if (answeredAt case final answered? when answered.isBefore(createdAt)) {
      throw const FormatException('Call answer predates creation.');
    }
    if (endedAt case final ended?
        when ended.isBefore(answeredAt ?? createdAt)) {
      throw const FormatException('Call end predates its current state.');
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'call_id': callId,
      'caller_username': callerUsername,
      'caller_device_id': callerDeviceId,
      'callee_username': calleeUsername,
      'media': media.name,
      'state': state.name,
      if (acceptedDeviceId != null) 'accepted_device_id': acceptedDeviceId,
      'created_at': createdAt.toIso8601String(),
      if (answeredAt != null) 'answered_at': answeredAt!.toIso8601String(),
      if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toWampKeywords();

  factory CallRecord.fromWampKeywords(Map<String, dynamic>? value) =>
      _fromMap(value);

  factory CallRecord.fromJson(Map<String, dynamic>? value) => _fromMap(value);

  static CallRecord _fromMap(Map<String, dynamic>? value) => CallRecord(
    callId: _readString(value?['call_id'], 'call_id'),
    callerUsername: _readString(value?['caller_username'], 'caller_username'),
    callerDeviceId: _readString(value?['caller_device_id'], 'caller_device_id'),
    calleeUsername: _readString(value?['callee_username'], 'callee_username'),
    media: _enumValue(CallMediaKind.values, value?['media'], 'media'),
    state: _enumValue(CallState.values, value?['state'], 'state'),
    acceptedDeviceId: value?['accepted_device_id'] == null
        ? null
        : _readString(value?['accepted_device_id'], 'accepted_device_id'),
    createdAt: _readUtcDate(value?['created_at'], 'created_at'),
    answeredAt: value?['answered_at'] == null
        ? null
        : _readUtcDate(value?['answered_at'], 'answered_at'),
    endedAt: value?['ended_at'] == null
        ? null
        : _readUtcDate(value?['ended_at'], 'ended_at'),
  );
}

final class CallUpdate {
  CallUpdate({
    required this.cursor,
    required this.call,
    Iterable<EncryptedCallSignal> signals = const [],
  }) : signals = List<EncryptedCallSignal>.unmodifiable(signals) {
    validate();
  }

  final int cursor;
  final CallRecord call;
  final List<EncryptedCallSignal> signals;

  void validate() {
    if (cursor < 1 ||
        signals.length > WampAppCallLimits.maximumDevicesPerCall) {
      throw const FormatException('Call update is invalid.');
    }
    call.validate();
    for (final signal in signals) {
      signal.validate();
      if (signal.callId != call.callId) {
        throw const FormatException('Call update contains another call.');
      }
    }
  }

  Map<String, dynamic> toWampKeywords() => {
    'cursor': cursor,
    'call': call.toWampKeywords(),
    'signals': signals.map((signal) => signal.toWampKeywords()).toList(),
  };

  Map<String, dynamic> toJson() => {
    'cursor': cursor,
    'call': call.toJson(),
    'signals': signals.map((signal) => signal.toJson()).toList(),
  };

  factory CallUpdate.fromWampKeywords(Map<String, dynamic>? value) =>
      _fromMap(value, fromJson: false);

  factory CallUpdate.fromJson(Map<String, dynamic>? value) =>
      _fromMap(value, fromJson: true);

  static CallUpdate _fromMap(
    Map<String, dynamic>? value, {
    required bool fromJson,
  }) {
    final rawSignals = value?['signals'];
    if (rawSignals is! List) {
      throw const FormatException('Call update signals must be a list.');
    }
    return CallUpdate(
      cursor: _readInt(value?['cursor'], 'cursor'),
      call: fromJson
          ? CallRecord.fromJson(_readMap(value?['call'], 'call'))
          : CallRecord.fromWampKeywords(_readMap(value?['call'], 'call')),
      signals: rawSignals.map((signal) {
        final mapped = _readMap(signal, 'signal');
        return fromJson
            ? EncryptedCallSignal.fromJson(mapped)
            : EncryptedCallSignal.fromWampKeywords(mapped);
      }),
    );
  }
}

final class CallBatch {
  CallBatch({required this.nextCursor, required Iterable<CallUpdate> updates})
    : updates = List<CallUpdate>.unmodifiable(updates) {
    if (nextCursor < 0) {
      throw const FormatException('Call cursor must not be negative.');
    }
  }

  final int nextCursor;
  final List<CallUpdate> updates;

  Map<String, dynamic> toWampKeywords() => {
    'next_cursor': nextCursor,
    'updates': updates.map((update) => update.toWampKeywords()).toList(),
  };

  factory CallBatch.fromWampKeywords(Map<String, dynamic>? value) {
    final rawUpdates = value?['updates'];
    if (rawUpdates is! List) {
      throw const FormatException('Call batch updates must be a list.');
    }
    return CallBatch(
      nextCursor: _readInt(value?['next_cursor'], 'next_cursor'),
      updates: rawUpdates.map(
        (update) => CallUpdate.fromWampKeywords(_readMap(update, 'update')),
      ),
    );
  }
}

final class CallWakeup {
  const CallWakeup({required this.cursor});

  final int cursor;

  Map<String, dynamic> toWampKeywords() => {'cursor': cursor};

  factory CallWakeup.fromWampKeywords(Map<String, dynamic>? value) {
    final cursor = _readInt(value?['cursor'], 'cursor');
    if (cursor < 1) throw const FormatException('Call wakeup is invalid.');
    return CallWakeup(cursor: cursor);
  }
}

final class CallIceServer {
  CallIceServer({
    required Iterable<String> urls,
    this.username,
    this.credential,
  }) : urls = List<String>.unmodifiable(urls) {
    if (this.urls.isEmpty ||
        this.urls.length > 8 ||
        this.urls.any(
          (url) =>
              url.length > 2048 ||
              !(url.startsWith('stun:') ||
                  url.startsWith('turn:') ||
                  url.startsWith('turns:')),
        ) ||
        ((username == null) != (credential == null)) ||
        (username?.isEmpty ?? false) ||
        (credential?.isEmpty ?? false)) {
      throw const FormatException('ICE server configuration is invalid.');
    }
  }

  final List<String> urls;
  final String? username;
  final String? credential;

  Map<String, dynamic> toWampKeywords() => {
    'urls': urls,
    if (username != null) 'username': username,
    if (credential != null) 'credential': credential,
  };

  factory CallIceServer.fromWampKeywords(Map<String, dynamic> value) {
    final urls = value['urls'];
    if (urls is! List || urls.any((url) => url is! String)) {
      throw const FormatException('ICE server URLs must be strings.');
    }
    return CallIceServer(
      urls: urls.cast<String>(),
      username: value['username'] == null
          ? null
          : _readString(value['username'], 'username'),
      credential: value['credential'] == null
          ? null
          : _readString(value['credential'], 'credential'),
    );
  }
}

final class CallConfiguration {
  CallConfiguration({
    required Iterable<CallIceServer> iceServers,
    required DateTime expiresAt,
  }) : iceServers = List<CallIceServer>.unmodifiable(iceServers),
       expiresAt = expiresAt.toUtc() {
    if (this.iceServers.length > 16) {
      throw const FormatException('Too many ICE servers were configured.');
    }
  }

  final List<CallIceServer> iceServers;
  final DateTime expiresAt;

  Map<String, dynamic> toWampKeywords() => {
    'ice_servers': iceServers.map((server) => server.toWampKeywords()).toList(),
    'expires_at': expiresAt.toIso8601String(),
  };

  factory CallConfiguration.fromWampKeywords(Map<String, dynamic>? value) {
    final rawServers = value?['ice_servers'];
    if (rawServers is! List) {
      throw const FormatException('ICE servers must be a list.');
    }
    return CallConfiguration(
      iceServers: rawServers.map(
        (server) =>
            CallIceServer.fromWampKeywords(_readMap(server, 'ice_server')),
      ),
      expiresAt: _readUtcDate(value?['expires_at'], 'expires_at'),
    );
  }
}

T _enumValue<T extends Enum>(List<T> values, Object? value, String field) {
  if (value is! String) throw FormatException('$field must be a string.');
  final found = values
      .where((candidate) => candidate.name == value)
      .firstOrNull;
  if (found == null) throw FormatException('$field is invalid.');
  return found;
}

void _validateUsername(String value, String field) {
  if (!RegExp(r'^[a-z0-9][a-z0-9_.-]{2,63}$').hasMatch(value)) {
    throw FormatException('$field is invalid.');
  }
}

void _validateOpaqueId(String value, String field) {
  if (value.length < 22 ||
      value.length > 86 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw FormatException('$field is invalid.');
  }
  final decoded = _decodeBase64Url(value, field);
  if (decoded.length < 16 || decoded.length > 64) {
    throw FormatException('$field is invalid.');
  }
}

void _validateBase64Url(
  String value,
  String field, {
  required int expectedBytes,
}) {
  if (_decodeBase64Url(value, field).length != expectedBytes) {
    throw FormatException('$field is invalid.');
  }
}

Uint8List _decodeBase64Url(Object? value, String field) {
  if (value is! String ||
      value.isEmpty ||
      !RegExp(r'^[A-Za-z0-9_-]+={0,2}$').hasMatch(value)) {
    throw FormatException('$field must be base64url.');
  }
  try {
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } catch (_) {
    throw FormatException('$field must be base64url.');
  }
}

Uint8List _readBinary(Object? value, String field) {
  if (value is Uint8List) return Uint8List.fromList(value);
  if (value is List<int>) return Uint8List.fromList(value);
  throw FormatException('$field must be binary.');
}

String _readString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

int _readInt(Object? value, String field) {
  if (value is! int) throw FormatException('$field must be an integer.');
  return value;
}

Map<String, dynamic> _readMap(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be a map.');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

DateTime _readUtcDate(Object? value, String field) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field must be a UTC timestamp.');
  }
  return parsed;
}
