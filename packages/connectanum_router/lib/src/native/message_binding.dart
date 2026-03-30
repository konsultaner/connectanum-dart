import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import 'runtime.dart';

AbstractMessage bindMessage(
  NativeMessageSerializer serializer,
  Uint8List bytes, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
}) {
  final decoded = _decodePayload(serializer, bytes);
  if (decoded is! List) {
    throw ArgumentError('Decoded WAMP message is not an array: $decoded');
  }
  if (decoded.isEmpty) {
    throw ArgumentError('WAMP message cannot be empty');
  }
  final message = _bindDecoded(decoded.cast<dynamic>());
  if (message is AbstractMessageWithPayload) {
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
  }
  return message;
}

Object? _decodePayload(NativeMessageSerializer serializer, Uint8List bytes) {
  switch (serializer) {
    case NativeMessageSerializer.json:
      return jsonDecode(utf8.decode(bytes));
    case NativeMessageSerializer.messagePack:
      return msgpack.deserialize(bytes);
    case NativeMessageSerializer.cbor:
      return _decodeCborBytes(bytes);
    case NativeMessageSerializer.ubjson:
    case NativeMessageSerializer.flatbuffers:
      throw UnsupportedError(
        'Serializer ${serializer.name} is not supported for inbound messages',
      );
  }
}

AbstractMessage _bindDecoded(List<dynamic> message) {
  final code = message[0] as int;
  if (code == MessageTypes.codeHello) {
    final realm = message[1] as String?;
    final details = _mapDetails(_asStringKeyMap(message[2]));
    return Hello(realm, details);
  }
  if (code == MessageTypes.codeAuthenticate) {
    final authenticate = Authenticate(
      signature: message.length > 1 ? message[1] as String? : null,
    );
    authenticate.extra = _asStringKeyMap(
      message.length > 2 ? message[2] : null,
    );
    return authenticate;
  }
  if (code == MessageTypes.codeAbort) {
    final reason = message.length > 2 ? message[2] as String : '';
    return Abort(reason, message: _readOptionalMessageText(message, 1));
  }
  if (code == MessageTypes.codeGoodbye) {
    final details = _asStringKeyMap(message.length > 1 ? message[1] : null);
    final reason = message.length > 2 ? message[2] as String : '';
    return Goodbye(
      details != null ? GoodbyeMessage(details['message'] as String?) : null,
      reason,
    );
  }
  if (code == MessageTypes.codePublish) {
    return _bindPublish(message);
  }
  if (code == MessageTypes.codeSubscribe) {
    return _bindSubscribe(message);
  }
  if (code == MessageTypes.codeUnsubscribe) {
    return Unsubscribe(message[1] as int, message[2] as int);
  }
  if (code == MessageTypes.codeCall) {
    return _bindCall(message);
  }
  if (code == MessageTypes.codeCancel) {
    return _bindCancel(message);
  }
  if (code == MessageTypes.codeRegister) {
    return _bindRegister(message);
  }
  if (code == MessageTypes.codeUnregister) {
    return Unregister(message[1] as int, message[2] as int);
  }
  if (code == MessageTypes.codeYield) {
    return _bindYield(message);
  }
  if (code == MessageTypes.codeError) {
    return _bindError(message);
  }
  throw UnsupportedError('WAMP message code $code is not supported');
}

Publish _bindPublish(List<dynamic> message) {
  final requestId = message[1] as int;
  final options = _mapPublishOptions(_asStringKeyMap(message[2]));
  final topic = message[3] as String;
  return Publish(requestId, topic, options: options);
}

Subscribe _bindSubscribe(List<dynamic> message) {
  final requestId = message[1] as int;
  final options = _mapSubscribeOptions(_asStringKeyMap(message[2]));
  final topic = message[3] as String;
  return Subscribe(requestId, topic, options: options);
}

Call _bindCall(List<dynamic> message) {
  final requestId = message[1] as int;
  final options = _mapCallOptions(_asStringKeyMap(message[2]));
  final procedure = message[3] as String;
  return Call(requestId, procedure, options: options);
}

Cancel _bindCancel(List<dynamic> message) {
  final requestId = message[1] as int;
  final options = _mapCancelOptions(
    _asStringKeyMap(message.length > 2 ? message[2] : null),
  );
  return Cancel(requestId, options: options);
}

Register _bindRegister(List<dynamic> message) {
  final requestId = message[1] as int;
  final options = _mapRegisterOptions(_asStringKeyMap(message[2]));
  final procedure = message[3] as String;
  return Register(requestId, procedure, options: options);
}

Yield _bindYield(List<dynamic> message) {
  final requestId = message[1] as int;
  final options = _mapYieldOptions(
    _asStringKeyMap(message.length > 2 ? message[2] : null),
  );
  return Yield(requestId, options: options);
}

Error _bindError(List<dynamic> message) {
  final requestTypeId = message[1] as int;
  final requestId = message[2] as int;
  final details = _asStringKeyMap(message[3]) ?? <String, dynamic>{};
  final error = message.length > 4 ? message[4] as String? : null;
  return Error(requestTypeId, requestId, details, error);
}

void _applyLazyPayload(
  AbstractMessageWithPayload message,
  NativeMessageSerializer serializer,
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
) {
  if (argsBytes == null && kwargsBytes == null) {
    return;
  }

  message.setLazyPayload(
    argumentsBytes: argsBytes,
    argumentsDecoder: argsBytes == null
        ? null
        : (Uint8List bytes) => _decodeArgumentList(serializer, bytes),
    argumentsKeywordsBytes: kwargsBytes,
    argumentsKeywordsDecoder: kwargsBytes == null
        ? null
        : (Uint8List bytes) => _decodeKeywordMap(serializer, bytes),
    encoding: _lazyPayloadEncodingForSerializer(serializer),
  );
}

LazyPayloadEncoding? _lazyPayloadEncodingForSerializer(
  NativeMessageSerializer serializer,
) {
  return switch (serializer) {
    NativeMessageSerializer.json => LazyPayloadEncoding.json,
    NativeMessageSerializer.messagePack => LazyPayloadEncoding.messagePack,
    NativeMessageSerializer.cbor => LazyPayloadEncoding.cbor,
    NativeMessageSerializer.ubjson => null,
    NativeMessageSerializer.flatbuffers => null,
  };
}

Details _mapDetails(Map<String, dynamic>? map) {
  final details = Details();
  if (map == null) {
    return details;
  }
  details.agent = map['agent'] as String?;
  details.realm = map['realm'] as String?;
  if (map['authmethods'] is List) {
    details.authmethods = List<String>.from(map['authmethods']);
  }
  details.authid = map['authid'] as String?;
  details.authrole = map['authrole'] as String?;
  details.authmethod = map['authmethod'] as String?;
  details.authprovider = map['authprovider'] as String?;
  details.authextra = _asStringKeyMap(map['authextra']);
  details.nonce = map['nonce'] as String?;
  details.challenge = map['challenge'] as String?;
  details.iterations = _asInt(map['iterations']);
  details.keylen = _asInt(map['keylen']);
  details.progress = map['progress'] as bool?;
  details.salt = map['salt'] as String?;
  if (map['topic'] is String) {
    details.topic = Uri.tryParse(map['topic']);
  }
  if (map['procedure'] is String) {
    details.procedure = Uri.tryParse(map['procedure']);
  }
  details.trustlevel = _asInt(map['trustlevel']);
  details.roles = _mapRoles(_asStringKeyMap(map['roles']));
  return details;
}

List<dynamic> _decodeArgumentList(
  NativeMessageSerializer serializer,
  Uint8List bytes,
) {
  final decoded = _decodeFragment(serializer, bytes);
  if (decoded == null) {
    return <dynamic>[];
  }
  if (decoded is List) {
    return List<dynamic>.from(decoded);
  }
  throw ArgumentError('Expected arguments list but got $decoded');
}

Map<String, dynamic> _decodeKeywordMap(
  NativeMessageSerializer serializer,
  Uint8List bytes,
) {
  final decoded = _decodeFragment(serializer, bytes);
  if (decoded == null) {
    return <String, dynamic>{};
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw ArgumentError('Expected keyword arguments map but got $decoded');
}

Object? _decodeFragment(NativeMessageSerializer serializer, Uint8List bytes) {
  switch (serializer) {
    case NativeMessageSerializer.json:
      return jsonDecode(utf8.decode(bytes));
    case NativeMessageSerializer.messagePack:
      return msgpack.deserialize(bytes);
    case NativeMessageSerializer.cbor:
      return _decodeCborBytes(bytes);
    case NativeMessageSerializer.ubjson:
    case NativeMessageSerializer.flatbuffers:
      throw UnsupportedError(
        'Serializer ${serializer.name} is not supported for payload decoding',
      );
  }
}

Object? _decodeCborBytes(Uint8List bytes) {
  return cbor.cborDecode(bytes.toList()).toObject();
}

Roles? _mapRoles(Map<String, dynamic>? rolesMap) {
  if (rolesMap == null) {
    return null;
  }
  final roles = Roles();
  if (rolesMap['publisher'] is Map) {
    roles.publisher = Publisher()
      ..features = _mapPublisherFeatures(
        _asStringKeyMap(rolesMap['publisher']?['features']),
      );
  }
  if (rolesMap['broker'] is Map) {
    roles.broker = Broker()
      ..features = _mapBrokerFeatures(
        _asStringKeyMap(rolesMap['broker']?['features']),
      );
  }
  if (rolesMap['subscriber'] is Map) {
    roles.subscriber = Subscriber()
      ..features = _mapSubscriberFeatures(
        _asStringKeyMap(rolesMap['subscriber']?['features']),
      );
  }
  if (rolesMap['dealer'] is Map) {
    final dealer = Dealer();
    dealer.reflection = rolesMap['dealer']['reflection'] as bool?;
    dealer.features = _mapDealerFeatures(
      _asStringKeyMap(rolesMap['dealer']?['features']),
    );
    roles.dealer = dealer;
  }
  if (rolesMap['callee'] is Map) {
    roles.callee = Callee()
      ..features = _mapCalleeFeatures(
        _asStringKeyMap(rolesMap['callee']?['features']),
      );
  }
  if (rolesMap['caller'] is Map) {
    roles.caller = Caller()
      ..features = _mapCallerFeatures(
        _asStringKeyMap(rolesMap['caller']?['features']),
      );
  }
  return roles;
}

PublisherFeatures? _mapPublisherFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = PublisherFeatures();
  features.publisherIdentification =
      map['publisher_identification'] ?? features.publisherIdentification;
  features.subscriberBlackWhiteListing =
      map['subscriber_blackwhite_listing'] ??
      features.subscriberBlackWhiteListing;
  features.publisherExclusion =
      map['publisher_exclusion'] ?? features.publisherExclusion;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

BrokerFeatures? _mapBrokerFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = BrokerFeatures();
  features.publisherIdentification =
      map['publisher_identification'] ?? features.publisherIdentification;
  features.publicationTrustLevels =
      map['publication_trust_levels'] ?? features.publicationTrustLevels;
  features.patternBasedSubscription =
      map['pattern_based_subscription'] ?? features.patternBasedSubscription;
  features.subscriptionMetaApi =
      map['subscription_meta_api'] ?? features.subscriptionMetaApi;
  features.subscriberBlackWhiteListing =
      map['subscriber_blackwhite_listing'] ??
      features.subscriberBlackWhiteListing;
  features.sessionMetaApi = map['session_meta_api'] ?? features.sessionMetaApi;
  features.publisherExclusion =
      map['publisher_exclusion'] ?? features.publisherExclusion;
  features.eventHistory = map['event_history'] ?? features.eventHistory;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

SubscriberFeatures? _mapSubscriberFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = SubscriberFeatures();
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.subscriptionRevocation =
      map['subscription_revocation'] ?? features.subscriptionRevocation;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

DealerFeatures? _mapDealerFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = DealerFeatures();
  features.callerIdentification =
      map['caller_identification'] ?? features.callerIdentification;
  features.callTrustLevels =
      map['call_trustlevels'] ?? features.callTrustLevels;
  features.patternBasedRegistration =
      map['pattern_based_registration'] ?? features.patternBasedRegistration;
  features.registrationMetaApi =
      map['registration_meta_api'] ?? features.registrationMetaApi;
  features.sharedRegistration =
      map['shared_registration'] ?? features.sharedRegistration;
  features.sessionMetaApi = map['session_meta_api'] ?? features.sessionMetaApi;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

CalleeFeatures? _mapCalleeFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = CalleeFeatures();
  features.callerIdentification =
      map['caller_identification'] ?? features.callerIdentification;
  features.callTrustlevels =
      map['call_trustlevels'] ?? features.callTrustlevels;
  features.patternBasedRegistration =
      map['pattern_based_registration'] ?? features.patternBasedRegistration;
  features.sharedRegistration =
      map['shared_registration'] ?? features.sharedRegistration;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

CallerFeatures? _mapCallerFeatures(Map<String, dynamic>? map) {
  if (map == null) return null;
  final features = CallerFeatures();
  features.callerIdentification =
      map['caller_identification'] ?? features.callerIdentification;
  features.callTimeout = map['call_timeout'] ?? features.callTimeout;
  features.callCanceling = map['call_canceling'] ?? features.callCanceling;
  features.progressiveCallResults =
      map['progressive_call_results'] ?? features.progressiveCallResults;
  features.payloadPassThruMode =
      map['payload_passthru_mode'] ?? features.payloadPassThruMode;
  return features;
}

PublishOptions? _mapPublishOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  return PublishOptions(
    acknowledge: map['acknowledge'] as bool?,
    exclude: _asIntList(map['exclude']),
    excludeAuthId: _asStringList(map['exclude_authid']),
    excludeAuthRole: _asStringList(map['exclude_authrole']),
    eligible: _asIntList(map['eligible']),
    eligibleAuthId: _asStringList(map['eligible_authid']),
    eligibleAuthRole: _asStringList(map['eligible_authrole']),
    excludeMe: map['exclude_me'] as bool?,
    discloseMe: map['disclose_me'] as bool?,
    retain: map['retain'] as bool?,
    pptScheme: map['ppt_scheme'] as String?,
    pptSerializer: map['ppt_serializer'] as String?,
    pptCipher: map['ppt_cipher'] as String?,
    pptKeyId: map['ppt_keyid'] as String?,
  );
}

SubscribeOptions? _mapSubscribeOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  return SubscribeOptions(
    match: map['match'] as String?,
    metaTopic: map['meta_topic'] as String?,
    getRetained: map['get_retained'] as bool?,
  );
}

CallOptions? _mapCallOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  return CallOptions(
    receiveProgress: map['receive_progress'] as bool?,
    timeout: _asInt(map['timeout']),
    discloseMe: map['disclose_me'] as bool?,
    pptScheme: map['ppt_scheme'] as String?,
    pptSerializer: map['ppt_serializer'] as String?,
    pptCipher: map['ppt_cipher'] as String?,
    pptKeyId: map['ppt_keyid'] as String?,
  );
}

CancelOptions? _mapCancelOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  final options = CancelOptions();
  options.mode = map['mode'] as String?;
  return options;
}

RegisterOptions? _mapRegisterOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  return RegisterOptions(
    discloseCaller: map['disclose_caller'] as bool?,
    match: map['match'] as String?,
    invoke: map['invoke'] as String?,
  );
}

YieldOptions? _mapYieldOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  return YieldOptions(
    progress: map['progress'] as bool?,
    pptScheme: map['ppt_scheme'] as String?,
    pptSerializer: map['ppt_serializer'] as String?,
    pptCipher: map['ppt_cipher'] as String?,
    pptKeyId: map['ppt_keyid'] as String?,
  );
}

String? _readOptionalMessageText(List<dynamic> message, int index) {
  final value = message.length > index ? message[index] : null;
  if (value is Map && value['message'] is String) {
    return value['message'] as String;
  }
  return value as String?;
}

Map<String, dynamic>? _asStringKeyMap(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  throw ArgumentError('Expected map but received $value');
}

int? _asInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

List<int>? _asIntList(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List) {
    return value.map((e) => _asInt(e) ?? 0).toList();
  }
  return null;
}

List<String>? _asStringList(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  return null;
}
