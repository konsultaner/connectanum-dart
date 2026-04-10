import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import 'message_protocol.dart';

class NativeSessionMessage extends AbstractMessageWithPayload {
  NativeSessionMessage({
    required this.serializer,
    required this.metadata,
    Uint8List? argsBytes,
    Uint8List? kwargsBytes,
  }) {
    id = metadata.messageCode;
    _applyLazyPayload(this, serializer, argsBytes, kwargsBytes);
  }

  final NativeMessageSerializer serializer;
  final NativeMessageMetadata metadata;

  AbstractMessage materialize() {
    final boundMessage = _bindFromMetadata(
      serializer,
      metadata,
      argsBytes: debugEncodedArgumentsBytes,
      kwargsBytes: debugEncodedArgumentsKeywordsBytes,
    );
    if (boundMessage == null) {
      throw StateError(
        'Native session message ${metadata.messageCode} cannot be materialized',
      );
    }
    return boundMessage;
  }
}

AbstractMessage bindMessage(
  NativeMessageSerializer serializer,
  Uint8List bytes, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
  NativeMessageMetadata? metadata,
}) {
  final message = metadata != null
      ? _bindFromMetadata(
          serializer,
          metadata,
          argsBytes: argsBytes,
          kwargsBytes: kwargsBytes,
        )
      : null;
  final boundMessage = message ?? _bindDecodedPayload(serializer, bytes);
  if (message == null && boundMessage is AbstractMessageWithPayload) {
    _applyLazyPayload(boundMessage, serializer, argsBytes, kwargsBytes);
  }
  return boundMessage;
}

Object bindSessionMessage(
  NativeMessageSerializer serializer,
  Uint8List bytes, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
  NativeMessageMetadata? metadata,
}) {
  if (metadata != null &&
      metadata.hasFlag(NativeMessageMetadata.flagMetadataBind) &&
      _supportsSessionMetadataMessage(metadata.messageCode)) {
    return NativeSessionMessage(
      serializer: serializer,
      metadata: metadata,
      argsBytes: argsBytes,
      kwargsBytes: kwargsBytes,
    );
  }
  return bindMessage(
    serializer,
    bytes,
    argsBytes: argsBytes,
    kwargsBytes: kwargsBytes,
    metadata: metadata,
  );
}

AbstractMessage materializeSessionMessage(Object message) {
  if (message is NativeSessionMessage) {
    return message.materialize();
  }
  return message as AbstractMessage;
}

AbstractMessage _bindDecodedPayload(
  NativeMessageSerializer serializer,
  Uint8List bytes,
) {
  final decoded = _decodePayload(serializer, bytes);
  if (decoded is! List) {
    throw ArgumentError('Decoded WAMP message is not an array: $decoded');
  }
  if (decoded.isEmpty) {
    throw ArgumentError('WAMP message cannot be empty');
  }
  return _bindDecoded(decoded.cast<dynamic>());
}

AbstractMessage? _bindFromMetadata(
  NativeMessageSerializer serializer,
  NativeMessageMetadata metadata, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
}) {
  if (!metadata.hasFlag(NativeMessageMetadata.flagMetadataBind)) {
    return null;
  }
  final code = metadata.messageCode;
  final directBind = metadata.hasFlag(NativeMessageMetadata.flagDirectBind);
  if (code == MessageTypes.codePublished) {
    return Published(metadata.primaryId, metadata.secondaryId);
  }
  if (code == MessageTypes.codeSubscribed) {
    return Subscribed(metadata.primaryId, metadata.secondaryId);
  }
  if (code == MessageTypes.codeWelcome) {
    if (directBind) {
      final details = Details();
      details.realm = metadata.stringA;
      details.authid = metadata.stringB;
      details.authrole = metadata.stringC;
      details.authmethod = metadata.stringD;
      details.authprovider = metadata.stringE;
      return Welcome(metadata.primaryId, details);
    }
    return Welcome(
      metadata.primaryId,
      _mapDetails(
        _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
      ),
    );
  }
  if (code == MessageTypes.codeChallenge) {
    final extraMap = _decodeOptionalMapFragment(
      serializer,
      metadata.detailsBytes,
    );
    return Challenge(
      metadata.stringA ?? '',
      Extra(
        challenge: extraMap?['challenge'] as String?,
        salt: extraMap?['salt'] as String?,
        keyLen: _asInt(extraMap?['keylen']),
        channelBinding: extraMap?['channel_binding'] as String?,
        iterations: _asInt(extraMap?['iterations']),
        memory: _asInt(extraMap?['memory']),
        kdf: extraMap?['kdf'] as String?,
        nonce: extraMap?['nonce'] as String?,
      ),
    );
  }
  if (code == MessageTypes.codeAbort) {
    final details = directBind
        ? (metadata.stringB == null
              ? const <String, Object?>{}
              : <String, Object?>{'message': metadata.stringB})
        : _decodeOptionalMapFragment(serializer, metadata.detailsBytes) ??
              const <String, Object?>{};
    return Abort(
      metadata.stringA ?? '',
      details: details,
      message: details['message'] as String?,
      arguments: _decodeOptionalArgumentList(serializer, argsBytes),
      argumentsKeywords: _decodeOptionalKeywordMap(serializer, kwargsBytes),
    );
  }
  if (code == MessageTypes.codeEvent) {
    final message = Event(
      metadata.primaryId,
      metadata.secondaryId,
      directBind
          ? EventDetails(
              publisher:
                  metadata.hasFlag(
                    NativeMessageMetadata.flagDetailNumberAPresent,
                  )
                  ? metadata.detailNumberA
                  : null,
              trustlevel:
                  metadata.hasFlag(
                    NativeMessageMetadata.flagDetailNumberBPresent,
                  )
                  ? metadata.detailNumberB
                  : null,
              topic: metadata.stringA,
              pptScheme: metadata.stringB,
              pptSerializer: metadata.stringC,
              pptCipher: metadata.stringD,
              pptKeyid: metadata.stringE,
            )
          : _mapEventDetails(
              _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
            ),
    );
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
    return message;
  }
  if (code == MessageTypes.codeResult) {
    final message = Result(
      metadata.primaryId,
      directBind
          ? ResultDetails(
              progress:
                  metadata.hasFlag(NativeMessageMetadata.flagDetailBoolATrue)
                  ? true
                  : null,
              pptScheme: metadata.stringA,
              pptSerializer: metadata.stringB,
              pptCipher: metadata.stringC,
              pptKeyId: metadata.stringD,
            )
          : _mapResultDetails(
              _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
            ),
    );
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
    return message;
  }
  if (code == MessageTypes.codeRegistered) {
    return Registered(metadata.primaryId, metadata.secondaryId);
  }
  if (code == MessageTypes.codeInvocation) {
    final message = Invocation(
      metadata.primaryId,
      metadata.secondaryId,
      directBind
          ? InvocationDetails(
              metadata.hasFlag(NativeMessageMetadata.flagDetailNumberAPresent)
                  ? metadata.detailNumberA
                  : null,
              metadata.stringA,
              metadata.hasFlag(NativeMessageMetadata.flagDetailBoolATrue)
                  ? true
                  : null,
              metadata.stringB,
              metadata.stringC,
              metadata.stringD,
              metadata.stringE,
            )
          : _mapInvocationDetails(
              _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
            ),
    );
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
    return message;
  }
  if (code == MessageTypes.codeUnregistered) {
    return Unregistered(metadata.primaryId);
  }
  if (code == MessageTypes.codeUnsubscribed) {
    return Unsubscribed(
      metadata.primaryId,
      directBind
          ? UnsubscribedDetails(
              metadata.hasFlag(NativeMessageMetadata.flagDetailNumberAPresent)
                  ? metadata.detailNumberA
                  : null,
              metadata.stringA,
            )
          : _mapUnsubscribedDetails(
              _decodeOptionalMapFragment(serializer, metadata.detailsBytes),
            ),
    );
  }
  if (code == MessageTypes.codeGoodbye) {
    final details = directBind
        ? (metadata.stringB == null
              ? const <String, Object?>{}
              : <String, Object?>{'message': metadata.stringB})
        : _decodeOptionalMapFragment(serializer, metadata.detailsBytes) ??
              const <String, Object?>{};
    return Goodbye(
      details['message'] == null
          ? null
          : GoodbyeMessage(details['message'] as String?),
      metadata.stringA ?? '',
    );
  }
  if (code == MessageTypes.codeError) {
    final details = directBind
        ? <String, dynamic>{
            if (metadata.stringB != null) 'message': metadata.stringB,
          }
        : _decodeOptionalMapFragment(serializer, metadata.detailsBytes) ??
              <String, dynamic>{};
    final message = Error(
      metadata.primaryId,
      metadata.secondaryId,
      details,
      metadata.stringA,
    );
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
    return message;
  }
  return null;
}

bool _supportsSessionMetadataMessage(int code) {
  return code == MessageTypes.codeChallenge ||
      code == MessageTypes.codeWelcome ||
      code == MessageTypes.codeAbort ||
      code == MessageTypes.codePublished ||
      code == MessageTypes.codeSubscribed ||
      code == MessageTypes.codeEvent ||
      code == MessageTypes.codeUnsubscribed ||
      code == MessageTypes.codeResult ||
      code == MessageTypes.codeRegistered ||
      code == MessageTypes.codeInvocation ||
      code == MessageTypes.codeUnregistered ||
      code == MessageTypes.codeGoodbye ||
      code == MessageTypes.codeError;
}

Object? _decodePayload(NativeMessageSerializer serializer, Uint8List bytes) {
  switch (serializer) {
    case NativeMessageSerializer.json:
      return jsonDecode(utf8.decode(bytes));
    case NativeMessageSerializer.messagePack:
      return msgpack.deserialize(bytes);
    case NativeMessageSerializer.cbor:
      return cbor.cborDecode(bytes).toObject();
    case NativeMessageSerializer.ubjson:
    case NativeMessageSerializer.flatbuffers:
      throw UnsupportedError(
        'Serializer ${serializer.name} is not supported for inbound messages',
      );
  }
}

Map<String, dynamic>? _decodeOptionalMapFragment(
  NativeMessageSerializer serializer,
  Uint8List? bytes,
) {
  if (bytes == null) {
    return null;
  }
  final decoded = _decodeFragment(serializer, bytes);
  if (decoded == null) {
    return null;
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw ArgumentError('Expected details map but got $decoded');
}

List<dynamic>? _decodeOptionalArgumentList(
  NativeMessageSerializer serializer,
  Uint8List? bytes,
) {
  if (bytes == null) {
    return null;
  }
  return _decodeArgumentList(serializer, bytes);
}

Map<String, dynamic>? _decodeOptionalKeywordMap(
  NativeMessageSerializer serializer,
  Uint8List? bytes,
) {
  if (bytes == null) {
    return null;
  }
  return _decodeKeywordMap(serializer, bytes);
}

AbstractMessage _bindDecoded(List<dynamic> message) {
  final code = message[0] as int;
  if (code == MessageTypes.codeChallenge) {
    return _bindChallenge(message);
  }
  if (code == MessageTypes.codeWelcome) {
    return Welcome(message[1] as int, _mapDetails(_asStringKeyMap(message[2])));
  }
  if (code == MessageTypes.codeAbort) {
    final details = _asStringKeyMap(message.length > 1 ? message[1] : null);
    final reason = message.length > 2 ? message[2] as String : '';
    return Abort(
      reason,
      details: details,
      message: _readOptionalMessageText(message, 1),
    );
  }
  if (code == MessageTypes.codeGoodbye) {
    final details = _asStringKeyMap(message.length > 1 ? message[1] : null);
    final reason = message.length > 2 ? message[2] as String : '';
    return Goodbye(
      details != null ? GoodbyeMessage(details['message'] as String?) : null,
      reason,
    );
  }
  if (code == MessageTypes.codeError) {
    return _bindError(message);
  }
  if (code == MessageTypes.codePublished) {
    return Published(message[1] as int, message[2] as int);
  }
  if (code == MessageTypes.codeSubscribed) {
    return Subscribed(message[1] as int, message[2] as int);
  }
  if (code == MessageTypes.codeEvent) {
    return Event(
      message[1] as int,
      message[2] as int,
      _mapEventDetails(_asStringKeyMap(message[3])),
    );
  }
  if (code == MessageTypes.codeUnsubscribed) {
    return Unsubscribed(
      message[1] as int,
      _mapUnsubscribedDetails(
        _asStringKeyMap(message.length > 2 ? message[2] : null),
      ),
    );
  }
  if (code == MessageTypes.codeResult) {
    return Result(
      message[1] as int,
      _mapResultDetails(_asStringKeyMap(message[2])),
    );
  }
  if (code == MessageTypes.codeRegistered) {
    return Registered(message[1] as int, message[2] as int);
  }
  if (code == MessageTypes.codeInvocation) {
    return Invocation(
      message[1] as int,
      message[2] as int,
      _mapInvocationDetails(_asStringKeyMap(message[3])),
    );
  }
  if (code == MessageTypes.codeUnregistered) {
    return Unregistered(message[1] as int);
  }
  throw UnsupportedError('WAMP message code $code is not supported');
}

Challenge _bindChallenge(List<dynamic> message) {
  final extraMap = _asStringKeyMap(message.length > 2 ? message[2] : null);
  return Challenge(
    message[1] as String,
    Extra(
      challenge: extraMap?['challenge'] as String?,
      salt: extraMap?['salt'] as String?,
      keyLen: _asInt(extraMap?['keylen']),
      channelBinding: extraMap?['channel_binding'] as String?,
      iterations: _asInt(extraMap?['iterations']),
      memory: _asInt(extraMap?['memory']),
      kdf: extraMap?['kdf'] as String?,
      nonce: extraMap?['nonce'] as String?,
    ),
  );
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
        : (fragment) => _decodeArgumentList(serializer, fragment),
    argumentsKeywordsBytes: kwargsBytes,
    argumentsKeywordsDecoder: kwargsBytes == null
        ? null
        : (fragment) => _decodeKeywordMap(serializer, fragment),
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
    details.topic = Uri.tryParse(map['topic'] as String);
  }
  if (map['procedure'] is String) {
    details.procedure = Uri.tryParse(map['procedure'] as String);
  }
  details.trustlevel = _asInt(map['trustlevel']);
  details.roles = _mapRoles(_asStringKeyMap(map['roles']));
  details.custom.addAll(
    _extractCustomFields(map, const {
      'agent',
      'realm',
      'authmethods',
      'authid',
      'authrole',
      'authmethod',
      'authprovider',
      'authextra',
      'nonce',
      'challenge',
      'iterations',
      'keylen',
      'progress',
      'salt',
      'topic',
      'procedure',
      'trustlevel',
      'roles',
    }),
  );
  return details;
}

EventDetails _mapEventDetails(Map<String, dynamic>? map) {
  final safeMap = map ?? const <String, dynamic>{};
  return EventDetails(
    publisher: _asInt(safeMap['publisher']),
    trustlevel: _asInt(safeMap['trustlevel']),
    topic: safeMap['topic'] as String?,
    pptScheme: safeMap['ppt_scheme'] as String?,
    pptSerializer: safeMap['ppt_serializer'] as String?,
    pptCipher: safeMap['ppt_cipher'] as String?,
    pptKeyid: safeMap['ppt_keyid'] as String?,
    custom: _extractCustomFields(safeMap, const {
      'publisher',
      'trustlevel',
      'topic',
      'ppt_scheme',
      'ppt_serializer',
      'ppt_cipher',
      'ppt_keyid',
    }),
  );
}

ResultDetails _mapResultDetails(Map<String, dynamic>? map) {
  final safeMap = map ?? const <String, dynamic>{};
  return ResultDetails(
    progress: safeMap['progress'] as bool?,
    pptScheme: safeMap['ppt_scheme'] as String?,
    pptSerializer: safeMap['ppt_serializer'] as String?,
    pptCipher: safeMap['ppt_cipher'] as String?,
    pptKeyId: safeMap['ppt_keyid'] as String?,
    custom: _extractCustomFields(safeMap, const {
      'progress',
      'ppt_scheme',
      'ppt_serializer',
      'ppt_cipher',
      'ppt_keyid',
    }),
  );
}

InvocationDetails _mapInvocationDetails(Map<String, dynamic>? map) {
  final safeMap = map ?? const <String, dynamic>{};
  return InvocationDetails(
    _asInt(safeMap['caller']),
    safeMap['procedure'] as String?,
    safeMap['receive_progress'] as bool?,
    safeMap['ppt_scheme'] as String?,
    safeMap['ppt_serializer'] as String?,
    safeMap['ppt_cipher'] as String?,
    safeMap['ppt_keyid'] as String?,
    _extractCustomFields(safeMap, const {
      'caller',
      'procedure',
      'receive_progress',
      'ppt_scheme',
      'ppt_serializer',
      'ppt_cipher',
      'ppt_keyid',
    }),
  );
}

UnsubscribedDetails? _mapUnsubscribedDetails(Map<String, dynamic>? map) {
  if (map == null) {
    return null;
  }
  return UnsubscribedDetails(
    _asInt(map['subscription']),
    map['reason'] as String?,
  );
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
      return cbor.cborDecode(bytes).toObject();
    case NativeMessageSerializer.ubjson:
    case NativeMessageSerializer.flatbuffers:
      throw UnsupportedError(
        'Serializer ${serializer.name} is not supported for payload decoding',
      );
  }
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

Map<String, dynamic> _extractCustomFields(
  Map<String, dynamic> map,
  Set<String> knownKeys,
) {
  final custom = <String, dynamic>{};
  for (final entry in map.entries) {
    if (!knownKeys.contains(entry.key)) {
      custom[entry.key] = entry.value;
    }
  }
  return custom;
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
