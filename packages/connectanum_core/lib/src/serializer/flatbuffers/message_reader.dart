import 'dart:typed_data';
import 'dictionary_retention.dart';
import 'cbor_validation.dart';

import 'package:cbor/cbor.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/limits.dart';
import 'frame.dart';

/// Reconstruct models from a validated extended frame. This internal stage
/// deliberately rejects unacknowledged legacy dictionary placeholders.
AbstractMessage readWampFlatBufferMessage(Uint8List bytes) {
  try {
    return _readMessage(bytes);
  } on TypeError {
    throw const FormatException('Invalid FlatBuffers model dictionary type');
  } on ArgumentError {
    throw const FormatException('Invalid FlatBuffers model dictionary value');
  } on AssertionError {
    throw const FormatException('Invalid FlatBuffers model field');
  }
}

AbstractMessage _readMessage(Uint8List bytes) {
  final frame = readWampFlatBufferFrame(bytes);
  if (frame.name == 'EventReceived') {
    throw UnsupportedError('No public WAMP model for EventReceived');
  }
  final fields = frame.fields;
  final map = frame.dictionary;
  if (map == null &&
      !{
        'Published',
        'Subscribed',
        'Unsubscribe',
        'Registered',
        'Unregister',
      }.contains(frame.name)) {
    throw const FormatException('Extended FlatBuffers metadata is required');
  }
  final dictionary = Map<String, dynamic>.from(map ?? const {});
  int integer(String key) => fields[key] as int;
  String text(String key) => fields[key] as String;
  final AbstractMessage message;
  try {
    message = switch (frame.name) {
      'Hello' => Hello(text('realm'), _decodeDetailsMap(dictionary)),
      'Welcome' => Welcome(integer('session'), _decodeDetailsMap(dictionary)),
      'Abort' => Abort(text('reason'), details: dictionary),
      'Challenge' => Challenge(
        frame.challengeMethod,
        Extra.fromMap(dictionary),
      ),
      'Authenticate' => Authenticate(
        signature: text('signature'),
      )..extra = dictionary,
      'Goodbye' => Goodbye(
        GoodbyeMessage(dictionary['message'] as String?),
        text('reason'),
      ),
      'Error' => Error(
        integer('request_type'),
        integer('request'),
        dictionary,
        text('error'),
      ),
      'Publish' => Publish(
        integer('request'),
        text('topic'),
        options: _decodePublishOptions(dictionary),
      ),
      'Published' => Published(integer('request'), integer('publication')),
      'Subscribe' => Subscribe(
        integer('request'),
        text('topic'),
        options: _decodeSubscribeOptions(dictionary),
      ),
      'Subscribed' => Subscribed(integer('request'), integer('subscription')),
      'Unsubscribe' => Unsubscribe(integer('request'), integer('subscription')),
      'Unsubscribed' => Unsubscribed(
        integer('request'),
        dictionary.isEmpty
            ? null
            : UnsubscribedDetails(
                decodeOptionalWampId(
                  dictionary,
                  'subscription',
                  'UNSUBSCRIBED.Details.subscription',
                ),
                dictionary['reason'] as String?,
              ),
      ),
      'Event' => Event(
        integer('subscription'),
        integer('publication'),
        _eventDetails(dictionary),
      ),
      'Call' => Call(
        integer('request'),
        text('procedure'),
        options: _decodeCallOptions(dictionary),
      ),
      'Cancel' => Cancel(
        integer('request'),
        options: CancelOptions()..mode = dictionary['mode'] as String?,
      ),
      'Result' => Result(integer('request'), _resultDetails(dictionary)),
      'Register' => Register(
        integer('request'),
        text('procedure'),
        options: _decodeRegisterOptions(dictionary),
      ),
      'Registered' => Registered(integer('request'), integer('registration')),
      'Unregister' => Unregister(integer('request'), integer('registration')),
      'Unregistered' => Unregistered(integer('request')),
      'Invocation' => Invocation(
        integer('request'),
        integer('registration'),
        _invocationDetails(dictionary),
      ),
      'Interrupt' => Interrupt(
        integer('request'),
        options: InterruptOptions()..mode = dictionary['mode'] as String?,
      ),
      'Yield' => Yield(
        integer('request'),
        options: _decodeYieldOptions(dictionary),
      ),
      'Heartbeat' => Heartbeat(
        details: dictionary,
        ping: (integer('presence') & 1) == 0 ? null : integer('ping'),
        incoming: (integer('presence') & 2) == 0 ? null : integer('incoming'),
        outgoing: (integer('presence') & 4) == 0 ? null : integer('outgoing'),
      ),
      _ => throw UnsupportedError('No public WAMP model for ${frame.name}'),
    };
  } on TypeError {
    throw const FormatException('Invalid FlatBuffers model dictionary type');
  } on ArgumentError {
    throw const FormatException('Invalid FlatBuffers model dictionary value');
  }
  if (message is AbstractMessageWithPayload) {
    message.restoreLazyPayload(
      LazyMessagePayload.encoded(
        transparentBinaryPayload: fields['payload'] as Uint8List?,
        encoding: LazyPayloadEncoding.cbor,
        argumentsBytes: fields['args'] as Uint8List?,
        argumentsKeywordsBytes: fields['kwargs'] as Uint8List?,
        argumentsDecoder: (value) => _decodeApplication(value) as List,
        argumentsKeywordsDecoder: (value) => Map<String, dynamic>.from(
          _decodeApplication(value) as Map,
        ),
        anchor: frame.bytes,
      ),
    );
  }
  retainWampFlatBufferDictionary(message, frame.bytes, frame.dictionary);
  return message;
}

EventDetails _eventDetails(Map<String, dynamic> map) => EventDetails(
  publisher: decodeOptionalWampId(map, 'publisher', 'EVENT.Details.publisher'),
  trustlevel: decodeOptionalWampNonNegativeInteger(
    map,
    'trustlevel',
    'EVENT.Details.trustlevel',
  ),
  topic: map['topic'] as String?,
  pptScheme: map['ppt_scheme'] as String?,
  pptSerializer: map['ppt_serializer'] as String?,
  pptCipher: map['ppt_cipher'] as String?,
  pptKeyid: map['ppt_keyid'] as String?,
  custom: _copyWithoutKeys(map, _eventDetailKeys),
);

InvocationDetails _invocationDetails(Map<String, dynamic> map) {
  decodeOptionalWampNonNegativeInteger(
    map,
    'trustlevel',
    'INVOCATION.Details.trustlevel',
  );
  return InvocationDetails(
      decodeOptionalWampId(map, 'caller', 'INVOCATION.Details.caller'),
      map['procedure'] as String?,
      map['receive_progress'] as bool?,
      map['ppt_scheme'] as String?,
      map['ppt_serializer'] as String?,
      map['ppt_cipher'] as String?,
      map['ppt_keyid'] as String?,
      _copyWithoutKeys(map, _invocationDetailKeys),
    )
    ..progress = map['progress'] as bool?
    ..timeout = decodeOptionalWampNonNegativeInteger(
      map,
      'timeout',
      'INVOCATION.Details.timeout',
    );
}

ResultDetails _resultDetails(Map<String, dynamic> map) => ResultDetails(
  progress: map['progress'] as bool?,
  pptScheme: map['ppt_scheme'] as String?,
  pptSerializer: map['ppt_serializer'] as String?,
  pptCipher: map['ppt_cipher'] as String?,
  pptKeyId: map['ppt_keyid'] as String?,
  custom: _copyWithoutKeys(map, _resultDetailKeys),
);

/// Decode a native application span with the same limits and value semantics
/// as the public FlatBuffers reader. Decoding happens only on application access.
Object? decodeWampFlatBufferApplication(Uint8List bytes) {
  validateFlatBufferCbor(bytes);
  return _decodeApplication(bytes);
}

Object? _decodeApplication(Uint8List bytes) {
  try {
    return _applicationValue(cbor.decode(bytes));
  } on Exception {
    throw const FormatException('Invalid FlatBuffers application value');
  } on ArgumentError {
    throw const FormatException('Invalid FlatBuffers application value');
  } on TypeError {
    throw const FormatException('Invalid FlatBuffers application value');
  }
}

Object? _applicationValue(Object? value) {
  if (value is CborBytes) {
    final bytes = value.bytes;
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }
  if (value is CborValue && value is! CborList && value is! CborMap) {
    return _applicationValue(value.toObject());
  }
  if (value is Uint8List) return value;
  if (value is BigInt && value.abs() <= BigInt.from(9007199254740992)) {
    return value.toInt();
  }
  if (value is List) {
    return value.map(_applicationValue).toList(growable: false);
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        _applicationValue(entry.key): _applicationValue(entry.value),
    };
  }
  return value;
}

Details _decodeDetailsMap(Map<String, dynamic> detailsMap) {
  final details = Details();
  details.setLazyFieldsLoader(() => Map<String, dynamic>.from(detailsMap));
  return details;
}

RegisterOptions? _decodeRegisterOptions(Map<String, dynamic>? optionsMap) {
  if (optionsMap == null || optionsMap.isEmpty) {
    return null;
  }
  final custom = _copyWithoutKeys(optionsMap, _registerOptionKeys);
  return RegisterOptions(
    discloseCaller: optionsMap['disclose_caller'] as bool?,
    match: optionsMap['match'] as String?,
    invoke: optionsMap['invoke'] as String?,
    forwardTimeout: optionsMap['forward_timeout'] as bool?,
    custom: custom.isEmpty ? null : custom,
  );
}

CallOptions? _decodeCallOptions(Map<String, dynamic>? optionsMap) {
  if (optionsMap == null || optionsMap.isEmpty) {
    return null;
  }
  final custom = _copyWithoutKeys(optionsMap, _callOptionKeys);
  return CallOptions(
    progress: optionsMap['progress'] as bool?,
    receiveProgress: optionsMap['receive_progress'] as bool?,
    timeout: decodeOptionalWampNonNegativeInteger(
      optionsMap,
      'timeout',
      'CALL.Options.timeout',
    ),
    discloseMe: optionsMap['disclose_me'] as bool?,
    pptScheme: optionsMap['ppt_scheme'] as String?,
    pptSerializer: optionsMap['ppt_serializer'] as String?,
    pptCipher: optionsMap['ppt_cipher'] as String?,
    pptKeyId: optionsMap['ppt_keyid'] as String?,
    custom: custom.isEmpty ? null : custom,
  );
}

YieldOptions? _decodeYieldOptions(Map<String, dynamic>? optionsMap) {
  if (optionsMap == null || optionsMap.isEmpty) {
    return null;
  }
  final custom = _copyWithoutKeys(optionsMap, _yieldOptionKeys);
  return YieldOptions(
    progress: optionsMap['progress'] as bool?,
    pptScheme: optionsMap['ppt_scheme'] as String?,
    pptSerializer: optionsMap['ppt_serializer'] as String?,
    pptCipher: optionsMap['ppt_cipher'] as String?,
    pptKeyId: optionsMap['ppt_keyid'] as String?,
    custom: custom.isEmpty ? null : custom,
  );
}

PublishOptions? _decodePublishOptions(Map<String, dynamic>? optionsMap) {
  if (optionsMap == null || optionsMap.isEmpty) {
    return null;
  }
  return _decodeNonEmptyPublishOptions(optionsMap);
}

SubscribeOptions? _decodeSubscribeOptions(Map<String, dynamic>? optionsMap) {
  if (optionsMap == null || optionsMap.isEmpty) {
    return null;
  }
  final custom = _copyWithoutKeys(optionsMap, _subscribeOptionKeys);
  return SubscribeOptions(
    match: optionsMap['match'] as String?,
    metaTopic: optionsMap['meta_topic'] as String?,
    getRetained: optionsMap['get_retained'] as bool?,
    custom: custom.isEmpty ? null : custom,
  );
}

PublishOptions _decodeNonEmptyPublishOptions(Map<String, dynamic> optionsMap) {
  final custom = _copyWithoutKeys(optionsMap, _publishOptionKeys);
  return PublishOptions(
    acknowledge: optionsMap['acknowledge'] as bool?,
    exclude: decodeOptionalWampIdList(optionsMap, 'exclude'),
    excludeAuthId: decodeOptionalWampStringList(optionsMap, 'exclude_authid'),
    excludeAuthRole: decodeOptionalWampStringList(
      optionsMap,
      'exclude_authrole',
    ),
    eligible: decodeOptionalWampIdList(optionsMap, 'eligible'),
    eligibleAuthId: decodeOptionalWampStringList(optionsMap, 'eligible_authid'),
    eligibleAuthRole: decodeOptionalWampStringList(
      optionsMap,
      'eligible_authrole',
    ),
    excludeMe: optionsMap['exclude_me'] as bool?,
    discloseMe: optionsMap['disclose_me'] as bool?,
    retain: optionsMap['retain'] as bool?,
    pptScheme: optionsMap['ppt_scheme'] as String?,
    pptSerializer: optionsMap['ppt_serializer'] as String?,
    pptCipher: optionsMap['ppt_cipher'] as String?,
    pptKeyId: optionsMap['ppt_keyid'] as String?,
    custom: custom.isEmpty ? null : custom,
  );
}

Map<String, dynamic> _copyWithoutKeys(
  Map<String, dynamic> map,
  Set<String> keys,
) {
  final custom = Map<String, dynamic>.from(map);
  custom.removeWhere((key, _) => keys.contains(key));
  return custom;
}

const Set<String> _registerOptionKeys = {
  'disclose_caller',
  'match',
  'invoke',
  'forward_timeout',
};

const Set<String> _callOptionKeys = {
  'progress',
  'receive_progress',
  'timeout',
  'disclose_me',
  'ppt_scheme',
  'ppt_serializer',
  'ppt_cipher',
  'ppt_keyid',
};

const Set<String> _yieldOptionKeys = {
  'progress',
  'ppt_scheme',
  'ppt_serializer',
  'ppt_cipher',
  'ppt_keyid',
};

const Set<String> _publishOptionKeys = {
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
};

const Set<String> _subscribeOptionKeys = {
  'match',
  'meta_topic',
  'get_retained',
};

const Set<String> _eventDetailKeys = {
  'publisher',
  'trustlevel',
  'topic',
  'ppt_scheme',
  'ppt_serializer',
  'ppt_cipher',
  'ppt_keyid',
};

const Set<String> _invocationDetailKeys = {
  'caller',
  'procedure',
  'progress',
  'receive_progress',
  'timeout',
  'ppt_scheme',
  'ppt_serializer',
  'ppt_cipher',
  'ppt_keyid',
};

const Set<String> _resultDetailKeys = {
  'progress',
  'ppt_scheme',
  'ppt_serializer',
  'ppt_cipher',
  'ppt_keyid',
};
