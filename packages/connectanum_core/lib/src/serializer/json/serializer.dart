import 'dart:typed_data';
import 'dart:isolate';

import 'package:logging/logging.dart';

import 'package:connectanum_core/src/message/abstract_message.dart';
import 'package:connectanum_core/src/message/abort.dart';
import 'package:connectanum_core/src/message/abstract_message_with_payload.dart';
import 'package:connectanum_core/src/message/authenticate.dart';
import 'package:connectanum_core/src/message/call.dart';
import 'package:connectanum_core/src/message/cancel.dart' as cancel_msg;
import 'package:connectanum_core/src/message/challenge.dart';
import 'package:connectanum_core/src/message/error.dart';
import 'package:connectanum_core/src/message/event.dart';
import 'package:connectanum_core/src/message/goodbye.dart';
import 'package:connectanum_core/src/message/hello.dart';
import 'package:connectanum_core/src/message/interrupt.dart' as interrupt_msg;
import 'package:connectanum_core/src/message/message_types.dart';
import 'package:connectanum_core/src/message/publish.dart';
import 'package:connectanum_core/src/message/published.dart';
import 'package:connectanum_core/src/message/register.dart';
import 'package:connectanum_core/src/message/invocation.dart';
import 'package:connectanum_core/src/message/registered.dart' as registered_msg;
import 'package:connectanum_core/src/message/result.dart';
import 'package:connectanum_core/src/message/subscribe.dart';
import 'package:connectanum_core/src/message/subscribed.dart';
import 'package:connectanum_core/src/message/unregister.dart';
import 'package:connectanum_core/src/message/unregistered.dart'
    as unregistered_msg;
import 'package:connectanum_core/src/message/unsubscribe.dart';
import 'package:connectanum_core/src/message/details.dart';
import 'package:connectanum_core/src/message/unsubscribed.dart';
import 'package:connectanum_core/src/message/welcome.dart';
import 'package:connectanum_core/src/message/yield.dart';

import 'dart:convert';

import '../../message/ppt_payload.dart';
import '../abstract_serializer.dart';

/// This is a serializer for JSON messages. It is used to initialize an [AbstractTransport]
/// object.
class Serializer extends AbstractSerializer {
  static final String _binaryPrefix = '\u0000';
  static const String _escapedBinaryPrefix = r'\u0000';
  static final Logger _logger = Logger('Connectanum.Serializer');
  static const Utf8Decoder _utf8Decoder = Utf8Decoder();
  static const Set<String> _invocationDetailKeys = {
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
  static const Set<String> _resultDetailKeys = {
    'progress',
    'ppt_scheme',
    'ppt_serializer',
    'ppt_cipher',
    'ppt_keyid',
  };
  static const Set<String> _eventDetailKeys = {
    'publisher',
    'trustlevel',
    'topic',
    'ppt_scheme',
    'ppt_serializer',
    'ppt_cipher',
    'ppt_keyid',
  };
  static const Set<String> _callOptionKeys = {
    'progress',
    'receive_progress',
    'timeout',
    'disclose_me',
    'ppt_scheme',
    'ppt_serializer',
    'ppt_cipher',
    'ppt_keyid',
  };
  static const Set<String> _publishOptionKeys = {
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
  static const Set<String> _registerOptionKeys = {
    'disclose_caller',
    'match',
    'invoke',
    'forward_timeout',
  };
  static const Set<String> _subscribeOptionKeys = {
    'match',
    'meta_topic',
    'get_retained',
  };
  static const Set<String> _yieldOptionKeys = {
    'progress',
    'ppt_scheme',
    'ppt_serializer',
    'ppt_cipher',
    'ppt_keyid',
  };

  /// Converts a uint8 JSON message into a WAMP message object
  @override
  AbstractMessage? deserialize(Uint8List? jsonMessage) {
    return deserializeFromString(Utf8Decoder().convert(jsonMessage!));
  }

  /// Converts a string JSON message into a WAMP message object
  AbstractMessage? deserializeFromString(String jsonMessage) {
    Object? message = json.decode(jsonMessage);
    if (message is List) {
      int messageId = message[0];
      if (messageId == MessageTypes.codeHello) {
        return Hello(
          message[1] as String?,
          _decodeDetailsMap(
            _normalizeJsonStringKeyMap(message[2] as Map<dynamic, dynamic>),
          ),
        );
      }
      if (messageId == MessageTypes.codeChallenge) {
        final extraMap = message[2] is Map
            ? _normalizeJsonStringKeyMap(message[2] as Map<dynamic, dynamic>)
            : const <String, dynamic>{};
        return Challenge(message[1], Extra.fromMap(extraMap));
      }
      if (messageId == MessageTypes.codeAuthenticate) {
        return Authenticate(signature: message[1] as String?)
          ..extra = message[2] is Map
              ? Map<String, Object?>.from(
                  _normalizeJsonStringKeyMap(
                    message[2] as Map<dynamic, dynamic>,
                  ),
                )
              : <String, Object?>{};
      }
      if (messageId == MessageTypes.codeWelcome) {
        return Welcome(
          message[1],
          _decodeDetailsMap(
            _normalizeJsonStringKeyMap(message[2] as Map<dynamic, dynamic>),
          ),
        );
      }
      if (messageId == MessageTypes.codeRegister) {
        return Register(
          message[1],
          message[3],
          options: _decodeRegisterOptions(
            message[2] is Map
                ? _normalizeJsonStringKeyMap(
                    message[2] as Map<dynamic, dynamic>,
                  )
                : null,
          ),
        );
      }
      if (messageId == MessageTypes.codeUnregister) {
        return Unregister(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeCall) {
        return _addPayload(
          Call(
            message[1],
            message[3],
            options: _decodeCallOptions(
              message[2] is Map
                  ? _normalizeJsonStringKeyMap(
                      message[2] as Map<dynamic, dynamic>,
                    )
                  : null,
            ),
          ),
          message,
          4,
        );
      }
      if (messageId == MessageTypes.codeYield) {
        return _addPayload(
          Yield(
            message[1],
            options: _decodeYieldOptions(
              message[2] is Map
                  ? _normalizeJsonStringKeyMap(
                      message[2] as Map<dynamic, dynamic>,
                    )
                  : null,
            ),
          ),
          message,
          3,
        );
      }
      if (messageId == MessageTypes.codePublish) {
        return _addPayload(
          Publish(
            message[1],
            message[3],
            options: _decodePublishOptions(
              message[2] is Map
                  ? _normalizeJsonStringKeyMap(
                      message[2] as Map<dynamic, dynamic>,
                    )
                  : null,
            ),
          ),
          message,
          4,
        );
      }
      if (messageId == MessageTypes.codeRegistered) {
        return registered_msg.Registered(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeUnregistered) {
        return unregistered_msg.Unregistered(message[1]);
      }
      if (messageId == MessageTypes.codeInvocation) {
        final detailsMap = message[3] as Map<dynamic, dynamic>;
        final caller = detailsMap['caller'];
        final procedure = detailsMap['procedure'];
        final progress = detailsMap['progress'];
        final receiveProgress = detailsMap['receive_progress'];
        final pptScheme = detailsMap['ppt_scheme'];
        final pptSerializer = detailsMap['ppt_serializer'];
        final pptCipher = detailsMap['ppt_cipher'];
        final pptKeyId = detailsMap['ppt_keyid'];
        return _addPayload(
          Invocation(
            message[1],
            message[2],
            InvocationDetails(
                caller,
                procedure,
                receiveProgress,
                pptScheme,
                pptSerializer,
                pptCipher,
                pptKeyId,
                _extractCustomDetails(detailsMap, _invocationDetailKeys),
              )
              ..progress = progress
              ..timeout = detailsMap['timeout'] as int?,
          ),
          message,
          4,
        );
      }
      if (messageId == MessageTypes.codeInterrupt) {
        final optionsMap = message.length > 2 && message[2] is Map
            ? message[2] as Map<dynamic, dynamic>
            : null;
        return interrupt_msg.Interrupt(
          message[1],
          options: optionsMap == null
              ? null
              : (() {
                  final options = interrupt_msg.InterruptOptions();
                  options.mode = optionsMap['mode'] as String?;
                  return options;
                })(),
        );
      }
      if (messageId == MessageTypes.codeCancel) {
        final optionsMap = message.length > 2 && message[2] is Map
            ? message[2] as Map<dynamic, dynamic>
            : null;
        return cancel_msg.Cancel(
          message[1],
          options: optionsMap == null
              ? null
              : (() {
                  final options = cancel_msg.CancelOptions();
                  options.mode = optionsMap['mode'] as String?;
                  return options;
                })(),
        );
      }
      if (messageId == MessageTypes.codeResult) {
        final detailsMap = message[2] as Map<dynamic, dynamic>;
        final progress = detailsMap['progress'];
        final pptScheme = detailsMap['ppt_scheme'];
        final pptSerializer = detailsMap['ppt_serializer'];
        final pptCipher = detailsMap['ppt_cipher'];
        final pptKeyId = detailsMap['ppt_keyid'];
        return _addPayload(
          Result(
            message[1],
            ResultDetails(
              progress: progress,
              pptScheme: pptScheme,
              pptSerializer: pptSerializer,
              pptCipher: pptCipher,
              pptKeyId: pptKeyId,
              custom: _extractCustomDetails(detailsMap, _resultDetailKeys),
            ),
          ),
          message,
          3,
        );
      }
      if (messageId == MessageTypes.codePublished) {
        return Published(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeSubscribe) {
        return Subscribe(
          message[1],
          message[3],
          options: _decodeSubscribeOptions(
            message[2] is Map
                ? _normalizeJsonStringKeyMap(
                    message[2] as Map<dynamic, dynamic>,
                  )
                : null,
          ),
        );
      }
      if (messageId == MessageTypes.codeSubscribed) {
        return Subscribed(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeUnsubscribe) {
        return Unsubscribe(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeUnsubscribed) {
        return Unsubscribed(
          message[1],
          message.length == 2
              ? null
              : UnsubscribedDetails(
                  message[2]['subscription'],
                  message[2]['reason'],
                ),
        );
      }
      if (messageId == MessageTypes.codeEvent) {
        final detailsMap = message[3] as Map<dynamic, dynamic>;
        final publisher = detailsMap['publisher'];
        final trustlevel = detailsMap['trustlevel'];
        final topic = detailsMap['topic'];
        final pptScheme = detailsMap['ppt_scheme'];
        final pptSerializer = detailsMap['ppt_serializer'];
        final pptCipher = detailsMap['ppt_cipher'];
        final pptKeyId = detailsMap['ppt_keyid'];
        return _addPayload(
          Event(
            message[1],
            message[2],
            EventDetails(
              publisher: publisher,
              trustlevel: trustlevel,
              topic: topic,
              pptScheme: pptScheme,
              pptSerializer: pptSerializer,
              pptCipher: pptCipher,
              pptKeyid: pptKeyId,
              custom: _extractCustomDetails(detailsMap, _eventDetailKeys),
            ),
          ),
          message,
          4,
        );
      }
      if (messageId == MessageTypes.codeError) {
        return _addPayload(
          Error(
            message[1],
            message[2],
            _normalizeJsonStringKeyMap(message[3] as Map<dynamic, dynamic>),
            message[4],
          ),
          message,
          5,
        );
      }
      if (messageId == MessageTypes.codeAbort) {
        final details = message.length > 1 && message[1] != null
            ? _normalizeJsonStringKeyMap(message[1] as Map<dynamic, dynamic>)
            : <String, Object?>{};
        final reason = message.length > 2 ? message[2] as String : '';
        List<dynamic>? arguments;
        Map<String, Object?>? argumentsKeywords;
        if (message.length > 3 && message[3] != null) {
          arguments = List<dynamic>.from(message[3] as List);
        }
        if (message.length > 4 && message[4] != null) {
          argumentsKeywords = Map<String, Object?>.from(
            message[4] as Map<String, dynamic>,
          );
        }
        final messageText = details['message'] as String?;
        return Abort(
          reason,
          details: details,
          message: messageText,
          arguments: arguments,
          argumentsKeywords: argumentsKeywords,
        );
      }
      if (messageId == MessageTypes.codeGoodbye) {
        return Goodbye(
          _decodeGoodbyeMessage(
            message.length > 1 && message[1] is Map
                ? message[1] as Map<dynamic, dynamic>
                : null,
          ),
          message[2],
        );
      }
    }
    _logger.shout('Could not deserialize the message: $jsonMessage');
    // TODO respond with an error
    return null;
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
      timeout: optionsMap['timeout'] as int?,
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
    final custom = _copyWithoutKeys(optionsMap, _publishOptionKeys);
    return PublishOptions(
      acknowledge: optionsMap['acknowledge'] as bool?,
      exclude: _asIntList(optionsMap['exclude']),
      excludeAuthId: _asStringList(optionsMap['exclude_authid']),
      excludeAuthRole: _asStringList(optionsMap['exclude_authrole']),
      eligible: _asIntList(optionsMap['eligible']),
      eligibleAuthId: _asStringList(optionsMap['eligible_authid']),
      eligibleAuthRole: _asStringList(optionsMap['eligible_authrole']),
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

  Map<String, dynamic> _copyWithoutKeys(
    Map<String, dynamic> map,
    Set<String> keys,
  ) {
    final custom = Map<String, dynamic>.from(map);
    custom.removeWhere((key, _) => keys.contains(key));
    return custom;
  }

  List<int>? _asIntList(Object? value) {
    if (value is! List) {
      return null;
    }
    return value.whereType<num>().map((entry) => entry.toInt()).toList();
  }

  List<String>? _asStringList(Object? value) {
    if (value is! List) {
      return null;
    }
    return value.map((entry) => entry.toString()).toList();
  }

  AbstractMessageWithPayload _addPayload(
    AbstractMessageWithPayload message,
    List<dynamic> messageData,
    argumentsOffset,
  ) {
    if (messageData.length == argumentsOffset + 1 &&
        messageData[argumentsOffset] is String) {
      if (_isBinaryJsonString(messageData[argumentsOffset] as String)) {
        message.transparentBinaryPayload = _convertStringToUint8List(
          messageData[argumentsOffset] as String,
        );
      }
    } else {
      if (messageData.length >= argumentsOffset + 1) {
        message.arguments = messageData[argumentsOffset] as List<dynamic>?;
      }
      if (messageData.length >= argumentsOffset + 2) {
        final rawKwargs = messageData[argumentsOffset + 1];
        if (rawKwargs is Map) {
          // Defensive copy to avoid downstream mutation surprises.
          message.argumentsKeywords = Map<String, Object?>.from(
            rawKwargs as Map<Object?, Object?>,
          );
        } else {
          // Some routers may send kwargs as an unexpected type (e.g. a list).
          // Skip them to keep deserialization resilient.
          _logger.warning(
            'Unexpected kwargs type (${rawKwargs.runtimeType}), dropping payload',
          );
          message.argumentsKeywords = null;
        }
      }
      _convertMessagePayloadBinaryJsonStringToUint8List(message);
    }
    return message;
  }

  void _convertMessagePayloadBinaryJsonStringToUint8List(
    AbstractMessageWithPayload message,
  ) {
    final arguments = message.wireArguments;
    final argumentsKeywords = message.wireArgumentsKeywords;
    if (arguments != null && arguments.isNotEmpty) {
      _convertListEntriesBinaryJsonStringToUint8List(arguments);
    }

    if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
      _convertMapEntriesBinaryJsonStringToUint8List(argumentsKeywords);
    }
  }

  void _convertMapEntriesBinaryJsonStringToUint8List(Map payload) {
    for (var element in payload.entries) {
      if (element.value is Map) {
        _convertMapEntriesBinaryJsonStringToUint8List(element.value);
      }
      if (element.value is List) {
        _convertListEntriesBinaryJsonStringToUint8List(element.value);
      }
      if (element.value is String &&
          _isBinaryJsonString(element.value as String)) {
        payload[element.key] = _convertStringToUint8List(
          element.value as String,
        );
      }
    }
  }

  void _convertListEntriesBinaryJsonStringToUint8List(List payload) {
    for (var i = 0; i < payload.length; i++) {
      if (payload[i] is Map) {
        _convertMapEntriesBinaryJsonStringToUint8List(payload[i]);
      }
      if (payload[i] is List) {
        _convertListEntriesBinaryJsonStringToUint8List(payload[i]);
      }
      if (payload[i] is String && _isBinaryJsonString(payload[i] as String)) {
        payload[i] = _convertStringToUint8List(payload[i] as String);
      }
    }
  }

  Map<String, dynamic> _extractCustomDetails(
    Map<dynamic, dynamic> source,
    Set<String> knownKeys,
  ) {
    Map<String, dynamic>? custom;
    source.forEach((key, value) {
      final keyString = key is String ? key : key.toString();
      if (knownKeys.contains(keyString)) {
        return;
      }
      custom ??= <String, dynamic>{};
      custom![keyString] = _normalizeJsonPayloadFragment(value);
    });
    return custom ?? <String, dynamic>{};
  }

  Map<String, dynamic> _normalizeJsonStringKeyMap(
    Map<dynamic, dynamic> source,
  ) {
    return source.map<String, dynamic>(
      (key, value) => MapEntry(
        key is String ? key : key.toString(),
        _normalizeJsonPayloadFragment(value),
      ),
    );
  }

  Object? _normalizeJsonPayloadFragment(Object? value) {
    if (value is String && _isBinaryJsonString(value)) {
      return _convertStringToUint8List(value);
    }
    if (value is List) {
      return value
          .map<Object?>((entry) => _normalizeJsonPayloadFragment(entry))
          .toList(growable: false);
    }
    if (value is Map) {
      return value.map<Object?, Object?>(
        (key, entry) => MapEntry(key, _normalizeJsonPayloadFragment(entry)),
      );
    }
    return value;
  }

  String _encodeJsonObject(Object? value) {
    return json.encode(_jsonEncodablePayloadFragment(value));
  }

  Uint8List _convertStringToUint8List(String binaryJsonString) {
    if (binaryJsonString.startsWith(_binaryPrefix)) {
      return base64.decode(binaryJsonString.substring(_binaryPrefix.length));
    }
    if (binaryJsonString.startsWith(_escapedBinaryPrefix)) {
      return base64.decode(
        binaryJsonString.substring(_escapedBinaryPrefix.length),
      );
    }
    throw ArgumentError('Expected binary JSON string prefix');
  }

  bool _isBinaryJsonString(String value) {
    return value.startsWith(_binaryPrefix) ||
        value.startsWith(_escapedBinaryPrefix);
  }

  GoodbyeMessage? _decodeGoodbyeMessage(Map<dynamic, dynamic>? detailsMap) {
    if (detailsMap == null) {
      return null;
    }
    final message = detailsMap['message'] as String?;
    return message == null ? null : GoodbyeMessage(message);
  }

  /// Converts a WAMP message object into a uint8 json message
  @override
  String serialize(AbstractMessage message) {
    return serializeToString(message);
  }

  /// Converts a WAMP message object into a string json message
  String serializeToString(AbstractMessage message) {
    if (message is Hello) {
      return '[${MessageTypes.codeHello},${message.realm == null ? 'null' : '"${message.realm!}"'},${_serializeDetails(message.details)}]';
    }
    if (message is Challenge) {
      return '[${MessageTypes.codeChallenge},"${message.authMethod}",${_encodeJsonObject(_challengeExtraToMap(message.extra))}]';
    }
    if (message is Authenticate) {
      return '[${MessageTypes.codeAuthenticate},"${message.signature ?? ""}",${message.extra == null ? '{}' : _encodeJsonObject(message.extra)}]';
    }
    if (message is Welcome) {
      return '[${MessageTypes.codeWelcome},${message.sessionId},${_serializeDetails(message.details)}]';
    }
    if (message is Register) {
      return '[${MessageTypes.codeRegister},${message.requestId},${_serializeRegisterOptions(message.options)},"${message.procedure}"]';
    }
    if (message is Unregister) {
      return '[${MessageTypes.codeUnregister},${message.requestId},${message.registrationId}]';
    }
    if (message is Call) {
      return '[${MessageTypes.codeCall},${message.requestId},${_serializeCallOptions(message.options)},"${message.procedure}"${_serializePayload(message)}]';
    }
    if (message is Yield) {
      return '[${MessageTypes.codeYield},${message.invocationRequestId},${_serializeYieldOptions(message.options)}${_serializePayload(message)}]';
    }
    if (message is cancel_msg.Cancel) {
      final options = message.options;
      final details = <String, Object?>{};
      if (options?.mode != null) {
        details['mode'] = options!.mode;
      }
      final detailsJson = details.isEmpty ? '{}' : json.encode(details);
      return '[${MessageTypes.codeCancel},${message.requestId},$detailsJson]';
    }
    if (message is interrupt_msg.Interrupt) {
      final options = message.options;
      final details = <String, Object?>{};
      if (options?.mode != null) {
        details['mode'] = options!.mode;
      }
      final detailsJson = details.isEmpty ? '{}' : json.encode(details);
      return '[${MessageTypes.codeInterrupt},${message.requestId},$detailsJson]';
    }
    if (message is Invocation) {
      return '[${MessageTypes.codeInvocation},${message.requestId},${message.registrationId},${_serializeInvocationDetails(message.details)}${_serializePayload(message)}]';
    }
    if (message is Publish) {
      return '[${MessageTypes.codePublish},${message.requestId},${_serializePublish(message.options)},"${message.topic}"${_serializePayload(message)}]';
    }
    if (message is Published) {
      return '[${MessageTypes.codePublished},${message.publishRequestId},${message.publicationId}]';
    }
    if (message is Event) {
      final payload = _serializePayload(message);
      final detailsJson = _serializeEventDetails(
        message.details,
        allowOmit: false,
      );
      return '[${MessageTypes.codeEvent},${message.subscriptionId},${message.publicationId},$detailsJson$payload]';
    }
    if (message is Subscribe) {
      return '[${MessageTypes.codeSubscribe},${message.requestId},${_serializeSubscribeOptions(message.options)},"${message.topic}"]';
    }
    if (message is Subscribed) {
      return '[${MessageTypes.codeSubscribed},${message.subscribeRequestId},${message.subscriptionId}]';
    }
    if (message is Unsubscribe) {
      return '[${MessageTypes.codeUnsubscribe},${message.requestId},${message.subscriptionId}]';
    }
    if (message is Unsubscribed) {
      final details = message.details;
      if (details != null) {
        final map = <String, Object?>{};
        if (details.subscription != null) {
          map['subscription'] = details.subscription;
        }
        if (details.reason != null) {
          map['reason'] = details.reason;
        }
        if (map.isNotEmpty) {
          return '[${MessageTypes.codeUnsubscribed},${message.unsubscribeRequestId},${_encodeJsonObject(map)}]';
        }
      }
      return '[${MessageTypes.codeUnsubscribed},${message.unsubscribeRequestId}]';
    }
    if (message is Result) {
      final details = <String, Object?>{};
      final resultDetails = message.details;
      if (resultDetails.progress != null) {
        details['progress'] = resultDetails.progress;
      }
      if (resultDetails.pptScheme != null) {
        details['ppt_scheme'] = resultDetails.pptScheme;
      }
      if (resultDetails.pptSerializer != null) {
        details['ppt_serializer'] = resultDetails.pptSerializer;
      }
      if (resultDetails.pptCipher != null) {
        details['ppt_cipher'] = resultDetails.pptCipher;
      }
      if (resultDetails.pptKeyId != null) {
        details['ppt_keyid'] = resultDetails.pptKeyId;
      }
      if (resultDetails.custom.isNotEmpty) {
        details.addAll(resultDetails.custom);
      }
      final encodedDetails = _encodeJsonObject(details);
      return '[${MessageTypes.codeResult},${message.callRequestId},$encodedDetails${_serializePayload(message)}]';
    }
    if (message is Error) {
      return '[${MessageTypes.codeError},${message.requestTypeId},${message.requestId},${_encodeJsonObject(message.details)},"${message.error}"${_serializePayload(message)}]';
    }
    if (message is Abort) {
      final data = <dynamic>[
        MessageTypes.codeAbort,
        message.details,
        message.reason,
      ];
      if (message.arguments != null) {
        data.add(message.arguments);
        if (message.argumentsKeywords != null) {
          data.add(message.argumentsKeywords);
        }
      } else if (message.argumentsKeywords != null) {
        data.add(const []);
        data.add(message.argumentsKeywords);
      }
      return _encodeJsonObject(data);
    }
    if (message is Goodbye) {
      return '[${MessageTypes.codeGoodbye},${message.message?.message != null ? '{"message":"${message.message!.message}"}' : "{}"},"${message.reason}"]';
    }
    if (message is registered_msg.Registered) {
      return '[${MessageTypes.codeRegistered},${message.registerRequestId},${message.registrationId}]';
    }
    if (message is unregistered_msg.Unregistered) {
      return '[${MessageTypes.codeUnregistered},${message.unregisterRequestId}]';
    }

    _logger.shout('Could not serialize the message of type: $message');
    throw UnsupportedError(
      'JSON serializer does not support ${message.runtimeType}',
    );
  }

  String _serializeDetails(Details details) {
    if (details.roles != null) {
      var rolesJson = [];
      if (details.roles?.caller != null) {
        final callerFeatures = details.roles!.caller!.features;
        if (callerFeatures != null) {
          var callerFeaturesJson = [];
          callerFeaturesJson.add(
            '"call_canceling":${callerFeatures.callCanceling ? "true" : "false"}',
          );
          callerFeaturesJson.add(
            '"call_timeout":${callerFeatures.callTimeout ? "true" : "false"}',
          );
          callerFeaturesJson.add(
            '"caller_identification":${callerFeatures.callerIdentification ? "true" : "false"}',
          );
          callerFeaturesJson.add(
            '"payload_passthru_mode":${callerFeatures.payloadPassThruMode ? "true" : "false"}',
          );
          callerFeaturesJson.add(
            '"progressive_call_invocations":${callerFeatures.progressiveCallInvocations ? "true" : "false"}',
          );
          callerFeaturesJson.add(
            '"progressive_call_results":${callerFeatures.progressiveCallResults ? "true" : "false"}',
          );
          rolesJson.add(
            '"caller":{"features":{${callerFeaturesJson.join(",")}}}',
          );
        } else {
          rolesJson.add('"caller":{}');
        }
      }
      if (details.roles?.callee != null) {
        final calleeFeatures = details.roles!.callee!.features;
        if (calleeFeatures != null) {
          var calleeFeaturesJson = [];
          calleeFeaturesJson.add(
            '"caller_identification":${calleeFeatures.callerIdentification ? "true" : "false"}',
          );
          calleeFeaturesJson.add(
            '"call_trustlevels":${calleeFeatures.callTrustlevels ? "true" : "false"}',
          );
          calleeFeaturesJson.add(
            '"pattern_based_registration":${calleeFeatures.patternBasedRegistration ? "true" : "false"}',
          );
          calleeFeaturesJson.add(
            '"shared_registration":${calleeFeatures.sharedRegistration ? "true" : "false"}',
          );
          calleeFeaturesJson.add(
            '"call_timeout":${calleeFeatures.callTimeout ? "true" : "false"}',
          );
          calleeFeaturesJson.add(
            '"call_canceling":${calleeFeatures.callCanceling ? "true" : "false"}',
          );
          calleeFeaturesJson.add(
            '"progressive_call_invocations":${calleeFeatures.progressiveCallInvocations ? "true" : "false"}',
          );
          calleeFeaturesJson.add(
            '"progressive_call_results":${calleeFeatures.progressiveCallResults ? "true" : "false"}',
          );
          calleeFeaturesJson.add(
            '"payload_passthru_mode":${calleeFeatures.payloadPassThruMode ? "true" : "false"}',
          );
          rolesJson.add(
            '"callee":{"features":{${calleeFeaturesJson.join(",")}}}',
          );
        } else {
          rolesJson.add('"callee":{}');
        }
      }
      if (details.roles?.subscriber != null) {
        final subscriberFeatures = details.roles!.subscriber!.features;
        if (subscriberFeatures != null) {
          var subscriberFeaturesJson = [];
          subscriberFeaturesJson.add(
            '"publisher_identification":${subscriberFeatures.publisherIdentification ? "true" : "false"}',
          );
          subscriberFeaturesJson.add(
            '"publication_trustlevels":${subscriberFeatures.publicationTrustLevels ? "true" : "false"}',
          );
          subscriberFeaturesJson.add(
            '"pattern_based_subscription":${subscriberFeatures.patternBasedSubscription ? "true" : "false"}',
          );
          subscriberFeaturesJson.add(
            '"payload_passthru_mode":${subscriberFeatures.payloadPassThruMode ? "true" : "false"}',
          );
          subscriberFeaturesJson.add(
            '"subscription_revocation":${subscriberFeatures.subscriptionRevocation ? "true" : "false"}',
          );
          rolesJson.add(
            '"subscriber":{"features":{${subscriberFeaturesJson.join(",")}}}',
          );
        } else {
          rolesJson.add('"subscriber":{}');
        }
      }
      if (details.roles?.publisher != null) {
        final publisherFeatures = details.roles!.publisher!.features;
        if (publisherFeatures != null) {
          var publisherFeaturesJson = [];
          publisherFeaturesJson.add(
            '"publisher_identification":${publisherFeatures.publisherIdentification ? "true" : "false"}',
          );
          publisherFeaturesJson.add(
            '"subscriber_blackwhite_listing":${publisherFeatures.subscriberBlackWhiteListing ? "true" : "false"}',
          );
          publisherFeaturesJson.add(
            '"publisher_exclusion":${publisherFeatures.publisherExclusion ? "true" : "false"}',
          );
          publisherFeaturesJson.add(
            '"payload_passthru_mode":${publisherFeatures.payloadPassThruMode ? "true" : "false"}',
          );
          rolesJson.add(
            '"publisher":{"features":{${publisherFeaturesJson.join(",")}}}',
          );
        } else {
          rolesJson.add('"publisher":{}');
        }
      }
      if (details.roles?.broker != null) {
        final brokerFeatures = details.roles!.broker!.features;
        final brokerParts = <String>[];
        if (brokerFeatures != null) {
          final brokerFeaturesJson = <String>[
            '"publisher_identification":${brokerFeatures.publisherIdentification ? "true" : "false"}',
            '"publication_trustlevels":${brokerFeatures.publicationTrustLevels ? "true" : "false"}',
            '"pattern_based_subscription":${brokerFeatures.patternBasedSubscription ? "true" : "false"}',
            '"subscription_meta_api":${brokerFeatures.subscriptionMetaApi ? "true" : "false"}',
            '"subscriber_blackwhite_listing":${brokerFeatures.subscriberBlackWhiteListing ? "true" : "false"}',
            '"session_meta_api":${brokerFeatures.sessionMetaApi ? "true" : "false"}',
            '"publisher_exclusion":${brokerFeatures.publisherExclusion ? "true" : "false"}',
            '"event_history":${brokerFeatures.eventHistory ? "true" : "false"}',
            '"payload_passthru_mode":${brokerFeatures.payloadPassThruMode ? "true" : "false"}',
          ];
          brokerParts.add('"features":{${brokerFeaturesJson.join(",")}}');
        }
        if (details.roles!.broker!.reflection != null) {
          brokerParts.add(
            '"reflection":${details.roles!.broker!.reflection! ? "true" : "false"}',
          );
        }
        rolesJson.add(
          brokerParts.isEmpty
              ? '"broker":{}'
              : '"broker":{${brokerParts.join(",")}}',
        );
      }
      if (details.roles?.dealer != null) {
        final dealerFeatures = details.roles!.dealer!.features;
        final dealerParts = <String>[];
        if (dealerFeatures != null) {
          final dealerFeaturesJson = <String>[
            '"caller_identification":${dealerFeatures.callerIdentification ? "true" : "false"}',
            '"call_trustlevels":${dealerFeatures.callTrustLevels ? "true" : "false"}',
            '"pattern_based_registration":${dealerFeatures.patternBasedRegistration ? "true" : "false"}',
            '"registration_meta_api":${dealerFeatures.registrationMetaApi ? "true" : "false"}',
            '"shared_registration":${dealerFeatures.sharedRegistration ? "true" : "false"}',
            '"session_meta_api":${dealerFeatures.sessionMetaApi ? "true" : "false"}',
            '"call_timeout":${dealerFeatures.callTimeout ? "true" : "false"}',
            '"call_canceling":${dealerFeatures.callCanceling ? "true" : "false"}',
            '"progressive_call_invocations":${dealerFeatures.progressiveCallInvocations ? "true" : "false"}',
            '"progressive_call_results":${dealerFeatures.progressiveCallResults ? "true" : "false"}',
            '"payload_passthru_mode":${dealerFeatures.payloadPassThruMode ? "true" : "false"}',
          ];
          dealerParts.add('"features":{${dealerFeaturesJson.join(",")}}');
        }
        if (details.roles!.dealer!.reflection != null) {
          dealerParts.add(
            '"reflection":${details.roles!.dealer!.reflection! ? "true" : "false"}',
          );
        }
        rolesJson.add(
          dealerParts.isEmpty
              ? '"dealer":{}'
              : '"dealer":{${dealerParts.join(",")}}',
        );
      }
      var detailsParts = ['"roles":{${rolesJson.join(",")}}'];
      if (details.authid != null) {
        detailsParts.add('"authid":"${details.authid}"');
      }
      if (details.realm != null) {
        detailsParts.add('"realm":"${details.realm}"');
      }
      if (details.authrole != null && details.authrole!.isNotEmpty) {
        detailsParts.add('"authrole":"${details.authrole}"');
      }
      if (details.authmethod != null && details.authmethod!.isNotEmpty) {
        detailsParts.add('"authmethod":"${details.authmethod}"');
      }
      if (details.authprovider != null && details.authprovider!.isNotEmpty) {
        detailsParts.add('"authprovider":"${details.authprovider}"');
      }
      if (details.authmethods != null && details.authmethods!.isNotEmpty) {
        detailsParts.add(
          '"authmethods":["${details.authmethods!.join('","')}"]',
        );
      }
      if (details.authextra != null) {
        detailsParts.add('"authextra":${_encodeJsonObject(details.authextra)}');
      }
      if (details.custom.isNotEmpty) {
        details.custom.forEach((key, value) {
          detailsParts.add('"$key":${_encodeJsonObject(value)}');
        });
      }
      return '{${detailsParts.join(",")}}';
    } else {
      return '{}';
    }
  }

  String _serializeSubscribeOptions(SubscribeOptions? options) {
    if (options == null) {
      return '{}';
    }
    final map = <String, dynamic>{};
    if (options.getRetained != null) {
      map['get_retained'] = options.getRetained;
    }
    if (options.match != null) {
      map['match'] = options.match;
    }
    if (options.metaTopic != null) {
      map['meta_topic'] = options.metaTopic;
    }
    if (options.custom.isNotEmpty) {
      map.addAll(options.custom);
    }
    final legacyCustomEntries =
        options
            .getCustomValues<String>(SubscribeOptions.customSerializerJson)
            .entries
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in legacyCustomEntries) {
      map.putIfAbsent(entry.key, () => _decodeCustomJsonValue(entry.value));
    }
    return _encodeJsonObject(map);
  }

  String _serializeRegisterOptions(RegisterOptions? options) {
    if (options == null) {
      return '{}';
    }
    final map = <String, dynamic>{};
    if (options.match != null) {
      map['match'] = options.match;
    }
    if (options.discloseCaller != null) {
      map['disclose_caller'] = options.discloseCaller;
    }
    if (options.invoke != null) {
      map['invoke'] = options.invoke;
    }
    if (options.forwardTimeout != null) {
      map['forward_timeout'] = options.forwardTimeout;
    }
    if (options.custom.isNotEmpty) {
      map.addAll(options.custom);
    }
    return _encodeJsonObject(map);
  }

  String _serializeCallOptions(CallOptions? options) {
    if (options == null) {
      return '{}';
    }
    final map = <String, dynamic>{};
    if (options.progress != null) {
      map['progress'] = options.progress;
    }
    if (options.receiveProgress != null) {
      map['receive_progress'] = options.receiveProgress;
    }
    if (options.discloseMe != null) {
      map['disclose_me'] = options.discloseMe;
    }
    if (options.timeout != null) {
      map['timeout'] = options.timeout;
    }
    if (options.custom.isNotEmpty) {
      map.addAll(options.custom);
    }
    if (options.pptScheme != null) {
      map['ppt_scheme'] = options.pptScheme;
    }
    if (options.pptSerializer != null) {
      map['ppt_serializer'] = options.pptSerializer;
    }
    if (options.pptCipher != null) {
      map['ppt_cipher'] = options.pptCipher;
    }
    if (options.pptKeyId != null) {
      map['ppt_keyid'] = options.pptKeyId;
    }
    return _encodeJsonObject(map);
  }

  String _serializeYieldOptions(YieldOptions? options) {
    if (options == null) {
      return '{}';
    }
    final map = <String, dynamic>{'progress': options.progress};
    if (options.custom.isNotEmpty) {
      map.addAll(options.custom);
    }
    if (options.pptScheme != null) {
      map['ppt_scheme'] = options.pptScheme;
    }
    if (options.pptSerializer != null) {
      map['ppt_serializer'] = options.pptSerializer;
    }
    if (options.pptCipher != null) {
      map['ppt_cipher'] = options.pptCipher;
    }
    if (options.pptKeyId != null) {
      map['ppt_keyid'] = options.pptKeyId;
    }
    return _encodeJsonObject(map);
  }

  String _serializePublish(PublishOptions? options) {
    if (options == null) {
      return '{}';
    }
    final map = <String, dynamic>{};
    if (options.retain != null) {
      map['retain'] = options.retain;
    }
    if (options.discloseMe != null) {
      map['disclose_me'] = options.discloseMe;
    }
    if (options.acknowledge != null) {
      map['acknowledge'] = options.acknowledge;
    }
    if (options.excludeMe != null) {
      map['exclude_me'] = options.excludeMe;
    }
    if (options.exclude != null) {
      map['exclude'] = options.exclude;
    }
    if (options.excludeAuthId != null) {
      map['exclude_authid'] = options.excludeAuthId;
    }
    if (options.excludeAuthRole != null) {
      map['exclude_authrole'] = options.excludeAuthRole;
    }
    if (options.eligible != null) {
      map['eligible'] = options.eligible;
    }
    if (options.eligibleAuthId != null) {
      map['eligible_authid'] = options.eligibleAuthId;
    }
    if (options.eligibleAuthRole != null) {
      map['eligible_authrole'] = options.eligibleAuthRole;
    }
    if (options.custom.isNotEmpty) {
      map.addAll(options.custom);
    }
    if (options.pptScheme != null) {
      map['ppt_scheme'] = options.pptScheme;
    }
    if (options.pptSerializer != null) {
      map['ppt_serializer'] = options.pptSerializer;
    }
    if (options.pptCipher != null) {
      map['ppt_cipher'] = options.pptCipher;
    }
    if (options.pptKeyId != null) {
      map['ppt_keyid'] = options.pptKeyId;
    }
    return _encodeJsonObject(map);
  }

  String _serializePayload(AbstractMessageWithPayload message) {
    final encodedArgs = message.lazyPayloadEncoding == LazyPayloadEncoding.json
        ? message.debugEncodedArgumentsBytes
        : null;
    final encodedKwargs =
        message.lazyPayloadEncoding == LazyPayloadEncoding.json
        ? message.debugEncodedArgumentsKeywordsBytes
        : null;
    if (encodedArgs != null || encodedKwargs != null) {
      final arguments = encodedArgs == null ? message.wireArguments : null;
      final argumentsKeywords = encodedKwargs == null
          ? message.wireArgumentsKeywords
          : null;
      final argsJson = encodedArgs == null
          ? _encodeJsonObject(arguments ?? const [])
          : _utf8Decoder.convert(encodedArgs);
      if (encodedKwargs != null) {
        return ',$argsJson,${_utf8Decoder.convert(encodedKwargs)}';
      }
      if (argumentsKeywords != null) {
        return ',$argsJson,${_encodeJsonObject(argumentsKeywords)}';
      }
      return ',$argsJson';
    }

    final arguments = message.wireArguments;
    final argumentsKeywords = message.wireArgumentsKeywords;
    _convertMessagePayloadUint8ListToBinaryJsonString(
      arguments,
      argumentsKeywords,
    );
    if (message.transparentBinaryPayload != null) {
      return ',${_encodeJsonObject(_convertUint8ListToString(message.transparentBinaryPayload!))}';
    } else {
      if (argumentsKeywords != null) {
        return ',${_encodeJsonObject(arguments ?? [])},${_encodeJsonObject(argumentsKeywords)}';
      } else if (arguments != null) {
        return ',${_encodeJsonObject(arguments)}';
      }
    }
    return '';
  }

  void _convertMessagePayloadUint8ListToBinaryJsonString(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  ) {
    if (arguments != null && arguments.isNotEmpty) {
      _convertListEntriesUint8ListToBinaryJsonString(arguments);
    }

    if (argumentsKeywords != null && argumentsKeywords.isNotEmpty) {
      _convertMapEntriesUint8ListToBinaryJsonString(argumentsKeywords);
    }
  }

  void _convertMapEntriesUint8ListToBinaryJsonString(Map payload) {
    for (var element in payload.entries) {
      if (element.value is Map) {
        _convertMapEntriesUint8ListToBinaryJsonString(element.value);
      }
      if (element.value is List) {
        _convertListEntriesUint8ListToBinaryJsonString(element.value);
      }
      if (element.value is Uint8List) {
        payload[element.key] = _convertUint8ListToString(element.value);
      } else if (element.value is TransferableTypedData) {
        final binary = (element.value as TransferableTypedData)
            .materialize()
            .asUint8List();
        payload[element.key] = _convertUint8ListToString(binary);
      }
    }
  }

  dynamic _decodeCustomJsonValue(String value) {
    try {
      return _normalizeJsonPayloadFragment(json.decode(value));
    } catch (_) {
      return value;
    }
  }

  void _convertListEntriesUint8ListToBinaryJsonString(List payload) {
    for (var i = 0; i < payload.length; i++) {
      if (payload[i] is Map) {
        _convertMapEntriesUint8ListToBinaryJsonString(payload[i]);
      }
      if (payload[i] is List) {
        _convertListEntriesUint8ListToBinaryJsonString(payload[i]);
      }
      if (payload[i] is Uint8List) {
        payload[i] = _convertUint8ListToString(payload[i]);
      } else if (payload[i] is TransferableTypedData) {
        final binary = (payload[i] as TransferableTypedData)
            .materialize()
            .asUint8List();
        payload[i] = _convertUint8ListToString(binary);
      }
    }
  }

  String _convertUint8ListToString(Uint8List binary) {
    return '$_binaryPrefix${base64.encode(binary)}';
  }

  Object? _jsonEncodablePayloadFragment(Object? value) {
    if (value is Uint8List) {
      return _convertUint8ListToString(value);
    }
    if (value is TransferableTypedData) {
      return _convertUint8ListToString(value.materialize().asUint8List());
    }
    if (value is List) {
      return value
          .map<Object?>((entry) => _jsonEncodablePayloadFragment(entry))
          .toList(growable: false);
    }
    if (value is Map) {
      return value.map<Object?, Object?>(
        (key, entry) => MapEntry(key, _jsonEncodablePayloadFragment(entry)),
      );
    }
    return value;
  }

  String _serializeEventDetails(
    EventDetails details, {
    required bool allowOmit,
  }) {
    final map = <String, Object?>{};
    if (details.publisher != null) {
      map['publisher'] = details.publisher;
    }
    if (details.trustlevel != null) {
      map['trustlevel'] = details.trustlevel;
    }
    if (details.topic != null) {
      map['topic'] = details.topic;
    }
    if (details.pptScheme != null) {
      map['ppt_scheme'] = details.pptScheme;
    }
    if (details.pptSerializer != null) {
      map['ppt_serializer'] = details.pptSerializer;
    }
    if (details.pptCipher != null) {
      map['ppt_cipher'] = details.pptCipher;
    }
    if (details.pptKeyId != null) {
      map['ppt_keyid'] = details.pptKeyId;
    }
    if (details.custom.isNotEmpty) {
      map.addAll(details.custom);
    }
    if (map.isEmpty && allowOmit) {
      return '';
    }
    return map.isEmpty ? '{}' : _encodeJsonObject(map);
  }

  String _serializeInvocationDetails(InvocationDetails details) {
    final map = <String, Object?>{};
    if (details.caller != null) {
      map['caller'] = details.caller;
    }
    if (details.procedure != null) {
      map['procedure'] = details.procedure;
    }
    if (details.progress != null) {
      map['progress'] = details.progress;
    }
    if (details.receiveProgress != null) {
      map['receive_progress'] = details.receiveProgress;
    }
    if (details.timeout != null) {
      map['timeout'] = details.timeout;
    }
    if (details.pptScheme != null) {
      map['ppt_scheme'] = details.pptScheme;
    }
    if (details.pptSerializer != null) {
      map['ppt_serializer'] = details.pptSerializer;
    }
    if (details.pptCipher != null) {
      map['ppt_cipher'] = details.pptCipher;
    }
    if (details.pptKeyId != null) {
      map['ppt_keyid'] = details.pptKeyId;
    }
    if (details.custom.isNotEmpty) {
      map.addAll(details.custom);
    }
    return map.isEmpty ? '{}' : _encodeJsonObject(map);
  }

  /// Converts a uint8 JSON message into a PPT Payload Object
  @override
  PPTPayload? deserializePPT(Uint8List binPayload) {
    var messageStr = Utf8Decoder().convert(binPayload);
    Object? decodedObject = json.decode(messageStr);

    if (decodedObject is Map) {
      final arguments = _normalizeJsonPayloadFragment(decodedObject['args']);
      final argumentsKeywords = _normalizeJsonPayloadFragment(
        decodedObject['kwargs'],
      );
      return PPTPayload(
        arguments: arguments is List ? arguments.cast<dynamic>() : null,
        argumentsKeywords: argumentsKeywords is Map
            ? argumentsKeywords.cast<String, dynamic>()
            : null,
      );
    }

    _logger.shout('Could not deserialize the message: $messageStr');
    // TODO respond with an error
    return null;
  }

  /// Converts a PPT Payload Object into a uint8 array
  @override
  Uint8List serializePPT(PPTPayload pptPayload) {
    return serializePPTFragments(
      arguments: pptPayload.arguments,
      argumentsKeywords: pptPayload.argumentsKeywords,
    );
  }

  @override
  Uint8List serializePPTFragments({
    Uint8List? argumentsBytes,
    Uint8List? argumentsKeywordsBytes,
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    final argsJson = argumentsBytes == null
        ? _encodeJsonObject(arguments)
        : _utf8Decoder.convert(argumentsBytes);
    final kwargsJson = argumentsKeywordsBytes == null
        ? _encodeJsonObject(argumentsKeywords)
        : _utf8Decoder.convert(argumentsKeywordsBytes);
    final builder = StringBuffer()
      ..write('{"args": ')
      ..write(argsJson)
      ..write(', "kwargs": ')
      ..write(kwargsJson)
      ..write('}');
    return Utf8Encoder().convert(builder.toString());
  }

  Map<String, Object?> _challengeExtraToMap(Extra extra) {
    return extra.toMap();
  }
}
