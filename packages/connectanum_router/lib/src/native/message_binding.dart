import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import 'runtime.dart';

const String _jsonBinaryPrefix = '\\u0000';

AbstractMessage bindMessage(
  NativeMessageSerializer serializer,
  Uint8List bytes, {
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
  int? metadataMessageCode,
  int? metadataPrimaryId,
  int? metadataSecondaryId,
  int? metadataDetailNumberA,
  int? metadataFlags,
  Uint8List? metadataDetailsBytes,
  String? metadataStringA,
  String? metadataStringB,
  String? metadataStringC,
  String? metadataStringD,
  String? metadataStringE,
}) {
  if (metadataMessageCode != null &&
      metadataFlags != null &&
      (metadataFlags & _metadataBindFlag) != 0) {
    final metadataBound = bindMessageFromMetadata(
      serializer,
      messageCode: metadataMessageCode,
      primaryId: metadataPrimaryId ?? 0,
      secondaryId: metadataSecondaryId ?? 0,
      detailNumberA: metadataDetailNumberA ?? 0,
      flags: metadataFlags,
      detailsBytes: metadataDetailsBytes,
      stringA: metadataStringA,
      stringB: metadataStringB,
      stringC: metadataStringC,
      stringD: metadataStringD,
      stringE: metadataStringE,
      argsBytes: argsBytes,
      kwargsBytes: kwargsBytes,
    );
    if (metadataBound != null) {
      return metadataBound;
    }
  }
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

const int _metadataBindFlag = 1 << 4;
const int _directBindFlag = 1 << 0;
const int _detailNumberAPresentFlag = 1 << 1;
const int _detailBoolATrueFlag = 1 << 3;
const int _detailBoolBTrueFlag = 1 << 5;
const int _detailBoolCTrueFlag = 1 << 6;
const int _detailBoolDTrueFlag = 1 << 7;

AbstractMessage? bindMessageFromMetadata(
  NativeMessageSerializer serializer, {
  required int messageCode,
  required int primaryId,
  required int secondaryId,
  required int detailNumberA,
  required int flags,
  Uint8List? detailsBytes,
  String? stringA,
  String? stringB,
  String? stringC,
  String? stringD,
  String? stringE,
  Uint8List? argsBytes,
  Uint8List? kwargsBytes,
}) {
  if ((flags & _metadataBindFlag) == 0) {
    return null;
  }

  final directBind = (flags & _directBindFlag) != 0;
  AbstractMessage? message;
  if (messageCode == MessageTypes.codeHello) {
    message = stringA == null
        ? null
        : Hello(
            stringA,
            _detailsFromMetadata(
              serializer,
              detailsBytes,
              authId: directBind ? stringB : null,
              authRole: directBind ? stringC : null,
              authMethod: directBind ? stringD : null,
              authProvider: directBind ? stringE : null,
            ),
          );
  } else if (messageCode == MessageTypes.codeAuthenticate) {
    final authenticate = Authenticate(signature: stringA);
    if (detailsBytes != null) {
      authenticate.extra = lazyStringKeyMap<Object?>(
        loader: () => Map<String, Object?>.from(
          _decodeOptionalMapFragment(serializer, detailsBytes) ??
              const <String, dynamic>{},
        ),
      );
    }
    message = authenticate;
  } else if (messageCode == MessageTypes.codeAbort) {
    final detailsMap = directBind
        ? _lazyObjectDetailMap(
            serializer,
            detailsBytes,
            initialValues: <String, Object?>{'message': ?stringB},
            knownKeys: const {'message'},
          )
        : _decodeOptionalMapFragment(serializer, detailsBytes) == null
        ? null
        : Map<String, Object?>.from(
            _decodeOptionalMapFragment(serializer, detailsBytes)!,
          );
    message = Abort(
      stringA ?? '',
      details: detailsMap,
      message: detailsMap?['message'] as String?,
    );
  } else if (messageCode == MessageTypes.codeHeartbeat) {
    final heartbeat =
        _decodeOptionalMapFragment(serializer, detailsBytes) ??
        const <String, dynamic>{};
    message = Heartbeat(
      details: Map<String, Object?>.from(
        _asStringKeyMap(heartbeat['details']) ?? const <String, Object?>{},
      ),
      ping: _asInt(heartbeat['ping']),
      incoming: _asInt(heartbeat['incoming']),
      outgoing: _asInt(heartbeat['outgoing']),
    );
  } else if (messageCode == MessageTypes.codeGoodbye) {
    final detailsMap = directBind
        ? (stringB == null ? null : <String, dynamic>{'message': stringB})
        : _decodeOptionalMapFragment(serializer, detailsBytes);
    message = Goodbye(
      detailsMap != null && detailsMap['message'] is String
          ? GoodbyeMessage(detailsMap['message'] as String)
          : null,
      stringA ?? '',
    );
  } else if (messageCode == MessageTypes.codePublish) {
    final options = directBind
        ? (_mapPublishOptionsFromMetadata(
                flags,
                stringB,
                stringC,
                stringD,
                stringE,
              ) ??
              (detailsBytes == null ? null : PublishOptions()))
        : _mapPublishOptions(
            _decodeOptionalMapFragment(serializer, detailsBytes),
          );
    if (directBind && options != null) {
      _attachLazyCustomFieldsFromDetails(
        options,
        serializer,
        detailsBytes,
        const {
          'acknowledge',
          'exclude',
          'exclude_authid',
          'exclude_authrole',
          'eligible',
          'eligible_authid',
          'eligible_authrole',
          'exclude_me',
          'disclose_me',
          'retain',
          'ppt_scheme',
          'ppt_serializer',
          'ppt_cipher',
          'ppt_keyid',
        },
      );
    }
    message = stringA == null
        ? null
        : Publish(primaryId, stringA, options: options);
  } else if (messageCode == MessageTypes.codeSubscribe) {
    final options = directBind
        ? (_mapSubscribeOptionsFromMetadata(flags, stringB, stringC) ??
              (detailsBytes == null ? null : SubscribeOptions()))
        : _mapSubscribeOptions(
            _decodeOptionalMapFragment(serializer, detailsBytes),
          );
    if (directBind && options != null) {
      _attachLazyCustomFieldsFromDetails(
        options,
        serializer,
        detailsBytes,
        const {'match', 'meta_topic', 'get_retained'},
      );
    }
    message = stringA == null
        ? null
        : Subscribe(primaryId, stringA, options: options);
  } else if (messageCode == MessageTypes.codeUnsubscribe) {
    message = Unsubscribe(primaryId, secondaryId);
  } else if (messageCode == MessageTypes.codeCall) {
    final options = directBind
        ? _mapCallOptionsFromMetadata(
                flags,
                detailNumberA,
                stringB,
                stringC,
                stringD,
                stringE,
              ) ??
              (detailsBytes == null ? null : CallOptions())
        : _mapCallOptions(_decodeOptionalMapFragment(serializer, detailsBytes));
    if (directBind && options != null) {
      _attachLazyCustomFieldsFromDetails(
        options,
        serializer,
        detailsBytes,
        const {
          'receive_progress',
          'timeout',
          'disclose_me',
          'ppt_scheme',
          'ppt_serializer',
          'ppt_cipher',
          'ppt_keyid',
        },
      );
    }
    message = stringA == null
        ? null
        : Call(primaryId, stringA, options: options);
  } else if (messageCode == MessageTypes.codeCancel) {
    message = Cancel(
      primaryId,
      options: directBind
          ? _mapCancelOptionsFromMetadata(stringA)
          : _mapCancelOptions(
              _decodeOptionalMapFragment(serializer, detailsBytes),
            ),
    );
  } else if (messageCode == MessageTypes.codeInterrupt) {
    final options = directBind
        ? _mapCancelOptionsFromMetadata(stringA)
        : _mapCancelOptions(
            _decodeOptionalMapFragment(serializer, detailsBytes),
          );
    message = Interrupt(
      primaryId,
      options: _interruptOptionsFromMode(options?.mode),
    );
  } else if (messageCode == MessageTypes.codeRegister) {
    final options = directBind
        ? (_mapRegisterOptionsFromMetadata(flags, stringB, stringC) ??
              (detailsBytes == null ? null : RegisterOptions()))
        : _mapRegisterOptions(
            _decodeOptionalMapFragment(serializer, detailsBytes),
          );
    if (directBind && options != null) {
      _attachLazyCustomFieldsFromDetails(
        options,
        serializer,
        detailsBytes,
        const {'disclose_caller', 'match', 'invoke'},
      );
    }
    message = stringA == null
        ? null
        : Register(primaryId, stringA, options: options);
  } else if (messageCode == MessageTypes.codeUnregister) {
    message = Unregister(primaryId, secondaryId);
  } else if (messageCode == MessageTypes.codeYield) {
    final options = directBind
        ? (_mapYieldOptionsFromMetadata(
                flags,
                stringA,
                stringB,
                stringC,
                stringD,
              ) ??
              (detailsBytes == null ? null : YieldOptions()))
        : _mapYieldOptions(
            _decodeOptionalMapFragment(serializer, detailsBytes),
          );
    if (directBind && options != null) {
      _attachLazyCustomFieldsFromDetails(
        options,
        serializer,
        detailsBytes,
        const {
          'progress',
          'ppt_scheme',
          'ppt_serializer',
          'ppt_cipher',
          'ppt_keyid',
        },
      );
    }
    message = Yield(primaryId, options: options);
  } else if (messageCode == MessageTypes.codeError) {
    final detailsMap = directBind
        ? _lazyDynamicDetailMap(
            serializer,
            detailsBytes,
            initialValues: <String, dynamic>{'message': ?stringB},
            knownKeys: const {'message'},
          )
        : _decodeOptionalMapFragment(serializer, detailsBytes) ??
              <String, dynamic>{};
    message = Error(primaryId, secondaryId, detailsMap, stringA);
  } else if (messageCode == MessageTypes.codeUnsubscribed) {
    message = Unsubscribed(
      primaryId,
      directBind
          ? _mapUnsubscribedDetailsFromMetadata(flags, detailNumberA, stringA)
          : _mapUnsubscribedDetails(
              _decodeOptionalMapFragment(serializer, detailsBytes),
            ),
    );
  } else {
    final unknown = _decodeOptionalMapFragment(serializer, detailsBytes);
    if (unknown != null && unknown['fields'] is List) {
      message = UnknownMessage(
        messageCode,
        fields: _asDynamicList(unknown['fields']),
        requestId: _asInt(unknown['request_id']),
      );
    }
  }

  if (message is AbstractMessageWithPayload) {
    _applyLazyPayload(message, serializer, argsBytes, kwargsBytes);
  }
  return message;
}

Object? _decodePayload(NativeMessageSerializer serializer, Uint8List bytes) {
  switch (serializer) {
    case NativeMessageSerializer.json:
      return _normalizeJsonBinaryPayload(jsonDecode(utf8.decode(bytes)));
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
  if (code == MessageTypes.codeHeartbeat) {
    return Heartbeat(
      details: Map<String, Object?>.from(
        _asStringKeyMap(message.length > 1 ? message[1] : null) ??
            const <String, Object?>{},
      ),
      ping: _asInt(message.length > 2 ? message[2] : null),
      incoming: _asInt(message.length > 3 ? message[3] : null),
      outgoing: _asInt(message.length > 4 ? message[4] : null),
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
  if (code == MessageTypes.codeInterrupt) {
    return _bindInterrupt(message);
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
  return UnknownMessage(
    code,
    fields: message.length > 1 ? message.sublist(1) : const <dynamic>[],
  );
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

Interrupt _bindInterrupt(List<dynamic> message) {
  final requestId = message[1] as int;
  final options = _mapCancelOptions(
    _asStringKeyMap(message.length > 2 ? message[2] : null),
  );
  return Interrupt(
    requestId,
    options: _interruptOptionsFromMode(options?.mode),
  );
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

Details _detailsFromMetadata(
  NativeMessageSerializer serializer,
  Uint8List? detailsBytes, {
  String? authId,
  String? authRole,
  String? authMethod,
  String? authProvider,
}) {
  final details = Details();
  details.authid = authId;
  details.authrole = authRole;
  details.authmethod = authMethod;
  details.authprovider = authProvider;
  if (detailsBytes != null) {
    details.setLazyFieldsLoader(
      () => Map<String, dynamic>.from(
        _decodeOptionalMapFragment(serializer, detailsBytes) ??
            const <String, dynamic>{},
      ),
    );
  }
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
      return _normalizeJsonBinaryPayload(jsonDecode(utf8.decode(bytes)));
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

Map<String, dynamic>? _decodeOptionalMapFragment(
  NativeMessageSerializer serializer,
  Uint8List? bytes,
) {
  if (bytes == null || bytes.isEmpty) {
    return null;
  }
  final decoded = _decodeFragment(serializer, bytes);
  if (decoded == null) {
    return null;
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw ArgumentError('Expected metadata map but got $decoded');
}

Object? _decodeCborBytes(Uint8List bytes) {
  return cbor.cborDecode(bytes.toList()).toObject();
}

Object? _normalizeJsonBinaryPayload(Object? value) {
  if (value is String && value.startsWith(_jsonBinaryPrefix)) {
    return Uint8List.fromList(
      base64.decode(value.substring(_jsonBinaryPrefix.length)),
    );
  }
  if (value is List) {
    return value
        .map<Object?>((entry) => _normalizeJsonBinaryPayload(entry))
        .toList(growable: false);
  }
  if (value is Map) {
    return value.map<Object?, Object?>(
      (key, entry) => MapEntry(key, _normalizeJsonBinaryPayload(entry)),
    );
  }
  return value;
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
  final options = PublishOptions(
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
  options.custom.addAll(
    _extractCustomFields(map, const {
      'acknowledge',
      'exclude',
      'exclude_authid',
      'exclude_authrole',
      'eligible',
      'eligible_authid',
      'eligible_authrole',
      'exclude_me',
      'disclose_me',
      'retain',
      'ppt_scheme',
      'ppt_serializer',
      'ppt_cipher',
      'ppt_keyid',
    }),
  );
  return options;
}

PublishOptions? _mapPublishOptionsFromMetadata(
  int flags,
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
) {
  final acknowledge = (flags & _detailBoolATrueFlag) != 0 ? true : null;
  final excludeMe = (flags & _detailBoolBTrueFlag) != 0 ? true : null;
  final discloseMe = (flags & _detailBoolCTrueFlag) != 0 ? true : null;
  final retain = (flags & _detailBoolDTrueFlag) != 0 ? true : null;
  if (acknowledge == null &&
      excludeMe == null &&
      discloseMe == null &&
      retain == null &&
      pptScheme == null &&
      pptSerializer == null &&
      pptCipher == null &&
      pptKeyId == null) {
    return null;
  }
  return PublishOptions(
    acknowledge: acknowledge,
    excludeMe: excludeMe,
    discloseMe: discloseMe,
    retain: retain,
    pptScheme: pptScheme,
    pptSerializer: pptSerializer,
    pptCipher: pptCipher,
    pptKeyId: pptKeyId,
  );
}

SubscribeOptions? _mapSubscribeOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  final options = SubscribeOptions(
    match: map['match'] as String?,
    metaTopic: map['meta_topic'] as String?,
    getRetained: map['get_retained'] as bool?,
  );
  options.custom.addAll(
    _extractCustomFields(map, const {'match', 'meta_topic', 'get_retained'}),
  );
  return options;
}

SubscribeOptions? _mapSubscribeOptionsFromMetadata(
  int flags,
  String? match,
  String? metaTopic,
) {
  final getRetained = (flags & _detailBoolATrueFlag) != 0 ? true : null;
  if (match == null && metaTopic == null && getRetained == null) {
    return null;
  }
  return SubscribeOptions(
    match: match,
    metaTopic: metaTopic,
    getRetained: getRetained,
  );
}

CallOptions? _mapCallOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  final options = CallOptions(
    receiveProgress: map['receive_progress'] as bool?,
    timeout: _asInt(map['timeout']),
    discloseMe: map['disclose_me'] as bool?,
    pptScheme: map['ppt_scheme'] as String?,
    pptSerializer: map['ppt_serializer'] as String?,
    pptCipher: map['ppt_cipher'] as String?,
    pptKeyId: map['ppt_keyid'] as String?,
  );
  options.custom.addAll(
    _extractCustomFields(map, const {
      'receive_progress',
      'timeout',
      'disclose_me',
      'ppt_scheme',
      'ppt_serializer',
      'ppt_cipher',
      'ppt_keyid',
    }),
  );
  return options;
}

CallOptions? _mapCallOptionsFromMetadata(
  int flags,
  int timeout,
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
) {
  final receiveProgress = (flags & _detailBoolATrueFlag) != 0 ? true : null;
  final discloseMe = (flags & _detailBoolBTrueFlag) != 0 ? true : null;
  final resolvedTimeout = (flags & _detailNumberAPresentFlag) != 0
      ? timeout
      : null;
  if (receiveProgress == null &&
      resolvedTimeout == null &&
      discloseMe == null &&
      pptScheme == null &&
      pptSerializer == null &&
      pptCipher == null &&
      pptKeyId == null) {
    return null;
  }
  return CallOptions(
    receiveProgress: receiveProgress,
    timeout: resolvedTimeout,
    discloseMe: discloseMe,
    pptScheme: pptScheme,
    pptSerializer: pptSerializer,
    pptCipher: pptCipher,
    pptKeyId: pptKeyId,
  );
}

CancelOptions? _mapCancelOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  final options = CancelOptions();
  options.mode = map['mode'] as String?;
  return options;
}

CancelOptions? _mapCancelOptionsFromMetadata(String? mode) {
  if (mode == null) {
    return null;
  }
  final options = CancelOptions();
  options.mode = mode;
  return options;
}

InterruptOptions? _interruptOptionsFromMode(String? mode) {
  if (mode == null) {
    return null;
  }
  final options = InterruptOptions();
  options.mode = mode;
  return options;
}

RegisterOptions? _mapRegisterOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  final options = RegisterOptions(
    discloseCaller: map['disclose_caller'] as bool?,
    match: map['match'] as String?,
    invoke: map['invoke'] as String?,
  );
  options.custom.addAll(
    _extractCustomFields(map, const {'disclose_caller', 'match', 'invoke'}),
  );
  return options;
}

RegisterOptions? _mapRegisterOptionsFromMetadata(
  int flags,
  String? match,
  String? invoke,
) {
  final discloseCaller = (flags & _detailBoolATrueFlag) != 0 ? true : null;
  if (discloseCaller == null && match == null && invoke == null) {
    return null;
  }
  return RegisterOptions(
    discloseCaller: discloseCaller,
    match: match,
    invoke: invoke,
  );
}

YieldOptions? _mapYieldOptions(Map<String, dynamic>? map) {
  if (map == null) return null;
  final options = YieldOptions(
    progress: map['progress'] as bool?,
    pptScheme: map['ppt_scheme'] as String?,
    pptSerializer: map['ppt_serializer'] as String?,
    pptCipher: map['ppt_cipher'] as String?,
    pptKeyId: map['ppt_keyid'] as String?,
  );
  options.custom.addAll(
    _extractCustomFields(map, const {
      'progress',
      'ppt_scheme',
      'ppt_serializer',
      'ppt_cipher',
      'ppt_keyid',
    }),
  );
  return options;
}

YieldOptions? _mapYieldOptionsFromMetadata(
  int flags,
  String? pptScheme,
  String? pptSerializer,
  String? pptCipher,
  String? pptKeyId,
) {
  final progress = (flags & _detailBoolATrueFlag) != 0 ? true : null;
  if (progress == null &&
      pptScheme == null &&
      pptSerializer == null &&
      pptCipher == null &&
      pptKeyId == null) {
    return null;
  }
  return YieldOptions(
    progress: progress,
    pptScheme: pptScheme,
    pptSerializer: pptSerializer,
    pptCipher: pptCipher,
    pptKeyId: pptKeyId,
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

UnsubscribedDetails? _mapUnsubscribedDetailsFromMetadata(
  int flags,
  int subscription,
  String? reason,
) {
  final resolvedSubscription = (flags & _detailNumberAPresentFlag) != 0
      ? subscription
      : null;
  if (resolvedSubscription == null && reason == null) {
    return null;
  }
  return UnsubscribedDetails(resolvedSubscription, reason);
}

void _attachLazyCustomFieldsFromDetails(
  CustomFieldContainer target,
  NativeMessageSerializer serializer,
  Uint8List? detailsBytes,
  Set<String> knownKeys,
) {
  if (detailsBytes == null) {
    return;
  }
  target.setLazyCustomFieldsLoader(
    () => _extractCustomFields(
      _decodeOptionalMapFragment(serializer, detailsBytes) ??
          const <String, dynamic>{},
      knownKeys,
    ),
  );
}

Map<String, dynamic> _lazyDynamicDetailMap(
  NativeMessageSerializer serializer,
  Uint8List? detailsBytes, {
  Map<String, dynamic>? initialValues,
  Set<String> knownKeys = const <String>{},
}) {
  return lazyStringKeyMap<dynamic>(
    initialValues: initialValues,
    loader: detailsBytes == null
        ? null
        : () => _extractCustomFields(
            _decodeOptionalMapFragment(serializer, detailsBytes) ??
                const <String, dynamic>{},
            knownKeys,
          ),
  );
}

Map<String, Object?> _lazyObjectDetailMap(
  NativeMessageSerializer serializer,
  Uint8List? detailsBytes, {
  Map<String, Object?>? initialValues,
  Set<String> knownKeys = const <String>{},
}) {
  return lazyStringKeyMap<Object?>(
    initialValues: initialValues,
    loader: detailsBytes == null
        ? null
        : () => Map<String, Object?>.from(
            _extractCustomFields(
              _decodeOptionalMapFragment(serializer, detailsBytes) ??
                  const <String, dynamic>{},
              knownKeys,
            ),
          ),
  );
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

List<dynamic> _asDynamicList(Object? value) {
  if (value == null) {
    return const <dynamic>[];
  }
  if (value is List) {
    return List<dynamic>.from(value);
  }
  throw ArgumentError('Expected list but received $value');
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
