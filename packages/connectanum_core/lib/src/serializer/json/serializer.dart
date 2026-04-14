import 'dart:typed_data';

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
  static final String _binaryPrefix = '\\u0000';
  static final Logger _logger = Logger('Connectanum.Serializer');
  static const Utf8Decoder _utf8Decoder = Utf8Decoder();
  static const Set<String> _invocationDetailKeys = {
    'caller',
    'procedure',
    'receive_progress',
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
      if (messageId == MessageTypes.codeChallenge) {
        return Challenge(
          message[1],
          Extra(
            challenge: message[2]['challenge'],
            salt: message[2]['salt'],
            keyLen: message[2]['keylen'],
            iterations: message[2]['iterations'],
            memory: message[2]['memory'],
            kdf: message[2]['kdf'],
            nonce: message[2]['nonce'],
          ),
        );
      }
      if (messageId == MessageTypes.codeWelcome) {
        final details = Details();
        details.realm = message[2]['realm'] ?? '';
        details.authid = message[2]['authid'] ?? '';
        details.authprovider = message[2]['authprovider'] ?? '';
        details.authmethod = message[2]['authmethod'] ?? '';
        details.authrole = message[2]['authrole'] ?? '';
        if (message[2]['authextra'] != null) {
          details.authextra = _normalizeJsonStringKeyMap(
            message[2]['authextra'] as Map<dynamic, dynamic>,
          );
        }
        if (message[2]['roles'] != null) {
          details.roles = Roles();
          if (message[2]['roles']['dealer'] != null) {
            details.roles!.dealer = Dealer();
            if (message[2]['roles']['dealer']['features'] != null) {
              details.roles!.dealer!.features = DealerFeatures();
              details.roles!.dealer!.features!.callerIdentification =
                  message[2]['roles']['dealer']['features']['caller_identification'] ??
                  false;
              details.roles!.dealer!.features!.callTrustLevels =
                  message[2]['roles']['dealer']['features']['call_trustlevels'] ??
                  false;
              details.roles!.dealer!.features!.patternBasedRegistration =
                  message[2]['roles']['dealer']['features']['pattern_based_registration'] ??
                  false;
              details.roles!.dealer!.features!.registrationMetaApi =
                  message[2]['roles']['dealer']['features']['registration_meta_api'] ??
                  false;
              details.roles!.dealer!.features!.sharedRegistration =
                  message[2]['roles']['dealer']['features']['shared_registration'] ??
                  false;
              details.roles!.dealer!.features!.sessionMetaApi =
                  message[2]['roles']['dealer']['features']['session_meta_api'] ??
                  false;
              details.roles!.dealer!.features!.callTimeout =
                  message[2]['roles']['dealer']['features']['call_timeout'] ??
                  false;
              details.roles!.dealer!.features!.callCanceling =
                  message[2]['roles']['dealer']['features']['call_canceling'] ??
                  false;
              details.roles!.dealer!.features!.progressiveCallResults =
                  // ignore: prefer_single_quotes
                  message[2]['roles']['dealer']['features']['progressive_call_results'] ??
                  false;
              details.roles!.dealer!.features!.payloadPassThruMode =
                  message[2]['roles']['dealer']['features']['payload_passthru_mode'] ??
                  false;
            }
          }
          if (message[2]['roles']['broker'] != null) {
            details.roles!.broker = Broker();
            if (message[2]['roles']['broker']['features'] != null) {
              details.roles!.broker!.features = BrokerFeatures();
              details.roles!.broker!.features!.publisherIdentification =
                  message[2]['roles']['broker']['features']['publisher_identification'] ??
                  false;
              details.roles!.broker!.features!.publicationTrustLevels =
                  message[2]['roles']['broker']['features']['publication_trustlevels'] ??
                  false;
              details.roles!.broker!.features!.patternBasedSubscription =
                  message[2]['roles']['broker']['features']['pattern_based_subscription'] ??
                  false;
              details.roles!.broker!.features!.subscriptionMetaApi =
                  message[2]['roles']['broker']['features']['subscription_meta_api'] ??
                  false;
              details.roles!.broker!.features!.subscriberBlackWhiteListing =
                  message[2]['roles']['broker']['features']['subscriber_blackwhite_listing'] ??
                  false;
              details.roles!.broker!.features!.sessionMetaApi =
                  message[2]['roles']['broker']['features']['session_meta_api'] ??
                  false;
              details.roles!.broker!.features!.publisherExclusion =
                  message[2]['roles']['broker']['features']['publisher_exclusion'] ??
                  false;
              details.roles!.broker!.features!.eventHistory =
                  message[2]['roles']['broker']['features']['event_history'] ??
                  false;
              details.roles!.broker!.features!.payloadPassThruMode =
                  message[2]['roles']['broker']['features']['payload_passthru_mode'] ??
                  false;
            }
          }
        }
        final remainingDetails = Map<String, dynamic>.from(
          message[2] as Map<dynamic, dynamic>,
        );
        remainingDetails
          ..remove('roles')
          ..remove('realm')
          ..remove('authid')
          ..remove('authprovider')
          ..remove('authmethod')
          ..remove('authrole')
          ..remove('authextra');
        if (details.authmethods != null) {
          remainingDetails.remove('authmethods');
        }
        if (remainingDetails.isNotEmpty) {
          details.custom.addAll(_normalizeJsonStringKeyMap(remainingDetails));
        }
        return Welcome(message[1], details);
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
            ),
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
      if (messageId == MessageTypes.codeSubscribed) {
        return Subscribed(message[1], message[2]);
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
          message[1] == null ? null : GoodbyeMessage(message[1]['message']),
          message[2],
        );
      }
    }
    _logger.shout('Could not deserialize the message: $jsonMessage');
    // TODO respond with an error
    return null;
  }

  AbstractMessageWithPayload _addPayload(
    AbstractMessageWithPayload message,
    List<dynamic> messageData,
    argumentsOffset,
  ) {
    if (messageData.length == argumentsOffset + 1 &&
        messageData[argumentsOffset] is String) {
      if ((messageData[argumentsOffset] as String).startsWith(_binaryPrefix)) {
        message.transparentBinaryPayload = _convertStringToUint8List(
          (messageData[argumentsOffset] as String).substring(
            _binaryPrefix.length - 1,
          ),
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
    if (message.arguments != null && message.arguments!.isNotEmpty) {
      _convertListEntriesBinaryJsonStringToUint8List(message.arguments!);
    }

    if (message.argumentsKeywords != null &&
        message.argumentsKeywords!.isNotEmpty) {
      _convertMapEntriesBinaryJsonStringToUint8List(message.argumentsKeywords!);
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
      if (element.value is String && element.value.startsWith(_binaryPrefix)) {
        payload[element.key] = _convertStringToUint8List(
          (element.value as String).substring(_binaryPrefix.length - 1),
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
      if (payload[i] is String && payload[i].startsWith(_binaryPrefix)) {
        payload[i] = _convertStringToUint8List(
          (payload[i] as String).substring(_binaryPrefix.length - 1),
        );
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
    if (value is String && value.startsWith(_binaryPrefix)) {
      return _convertStringToUint8List(
        value.substring(_binaryPrefix.length - 1),
      );
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
    return base64.decode(binaryJsonString.substring(1));
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
      return '[${MessageTypes.codeGoodbye},${message.message != null ? '{"message":"${message.message!.message ?? ""}"}' : "{}"},"${message.reason}"]';
    }
    if (message is registered_msg.Registered) {
      return '[${MessageTypes.codeRegistered},${message.registerRequestId},${message.registrationId}]';
    }
    if (message is unregistered_msg.Unregistered) {
      return '[${MessageTypes.codeUnregistered},${message.unregisterRequestId}]';
    }

    _logger.shout('Could not serialize the message of type: $message');
    throw Exception(''); // TODO think of something helpful here...
  }

  String _serializeDetails(Details details) {
    if (details.roles != null) {
      var rolesJson = [];
      if (details.roles?.caller?.features != null) {
        var callerFeatures = [];
        callerFeatures.add(
          '"call_canceling":${details.roles!.caller!.features!.callCanceling ? "true" : "false"}',
        );
        callerFeatures.add(
          '"call_timeout":${details.roles!.caller!.features!.callTimeout ? "true" : "false"}',
        );
        callerFeatures.add(
          '"caller_identification":${details.roles!.caller!.features!.callerIdentification ? "true" : "false"}',
        );
        callerFeatures.add(
          '"payload_passthru_mode":${details.roles!.caller!.features!.payloadPassThruMode ? "true" : "false"}',
        );
        callerFeatures.add(
          '"progressive_call_results":${details.roles!.caller!.features!.progressiveCallResults ? "true" : "false"}',
        );
        rolesJson.add('"caller":{"features":{${callerFeatures.join(",")}}}');
      }
      if (details.roles?.callee?.features != null) {
        var calleeFeatures = [];
        calleeFeatures.add(
          '"caller_identification":${details.roles!.callee!.features!.callerIdentification ? "true" : "false"}',
        );
        calleeFeatures.add(
          '"call_trustlevels":${details.roles!.callee!.features!.callTrustlevels ? "true" : "false"}',
        );
        calleeFeatures.add(
          '"pattern_based_registration":${details.roles!.callee!.features!.patternBasedRegistration ? "true" : "false"}',
        );
        calleeFeatures.add(
          '"shared_registration":${details.roles!.callee!.features!.sharedRegistration ? "true" : "false"}',
        );
        calleeFeatures.add(
          '"call_timeout":${details.roles!.callee!.features!.callTimeout ? "true" : "false"}',
        );
        calleeFeatures.add(
          '"call_canceling":${details.roles!.callee!.features!.callCanceling ? "true" : "false"}',
        );
        calleeFeatures.add(
          '"progressive_call_results":${details.roles!.callee!.features!.progressiveCallResults ? "true" : "false"}',
        );
        calleeFeatures.add(
          '"payload_passthru_mode":${details.roles!.callee!.features!.payloadPassThruMode ? "true" : "false"}',
        );
        rolesJson.add('"callee":{"features":{${calleeFeatures.join(",")}}}');
      }
      if (details.roles?.subscriber?.features != null) {
        var subscriberFeatures = [];
        subscriberFeatures.add(
          '"call_timeout":${details.roles!.subscriber!.features!.callTimeout ? "true" : "false"}',
        );
        subscriberFeatures.add(
          '"call_canceling":${details.roles!.subscriber!.features!.callCanceling ? "true" : "false"}',
        );
        subscriberFeatures.add(
          '"progressive_call_results":${details.roles!.subscriber!.features!.progressiveCallResults ? "true" : "false"}',
        );
        subscriberFeatures.add(
          '"payload_passthru_mode":${details.roles!.subscriber!.features!.payloadPassThruMode ? "true" : "false"}',
        );
        subscriberFeatures.add(
          '"subscription_revocation":${details.roles!.subscriber!.features!.subscriptionRevocation ? "true" : "false"}',
        );
        rolesJson.add(
          '"subscriber":{"features":{${subscriberFeatures.join(",")}}}',
        );
      }
      if (details.roles?.publisher?.features != null) {
        var publisherFeatures = [];
        publisherFeatures.add(
          '"publisher_identification":${details.roles!.publisher!.features!.publisherIdentification ? "true" : "false"}',
        );
        publisherFeatures.add(
          '"subscriber_blackwhite_listing":${details.roles!.publisher!.features!.subscriberBlackWhiteListing ? "true" : "false"}',
        );
        publisherFeatures.add(
          '"publisher_exclusion":${details.roles!.publisher!.features!.publisherExclusion ? "true" : "false"}',
        );
        publisherFeatures.add(
          '"payload_passthru_mode":${details.roles!.publisher!.features!.payloadPassThruMode ? "true" : "false"}',
        );
        rolesJson.add(
          '"publisher":{"features":{${publisherFeatures.join(",")}}}',
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
      final argsJson = encodedArgs == null
          ? _encodeJsonObject(message.arguments ?? const [])
          : _utf8Decoder.convert(encodedArgs);
      if (encodedKwargs != null) {
        return ',$argsJson,${_utf8Decoder.convert(encodedKwargs)}';
      }
      if (message.argumentsKeywords != null) {
        return ',$argsJson,${_encodeJsonObject(message.argumentsKeywords)}';
      }
      return ',$argsJson';
    }
    _convertMessagePayloadUint8ListToBinaryJsonString(message);
    if (message.transparentBinaryPayload != null) {
      return ',${_encodeJsonObject(_convertUint8ListToString(message.transparentBinaryPayload!))}';
    } else {
      if (message.argumentsKeywords != null) {
        return ',${_encodeJsonObject(message.arguments ?? [])},${_encodeJsonObject(message.argumentsKeywords)}';
      } else if (message.arguments != null) {
        return ',${_encodeJsonObject(message.arguments)}';
      }
    }
    return '';
  }

  void _convertMessagePayloadUint8ListToBinaryJsonString(
    AbstractMessageWithPayload message,
  ) {
    if (message.arguments != null && message.arguments!.isNotEmpty) {
      _convertListEntriesUint8ListToBinaryJsonString(message.arguments!);
    }

    if (message.argumentsKeywords != null &&
        message.argumentsKeywords!.isNotEmpty) {
      _convertMapEntriesUint8ListToBinaryJsonString(message.argumentsKeywords!);
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
      }
    }
  }

  String _convertUint8ListToString(Uint8List binary) {
    return '\\u0000${base64.encode(binary)}';
  }

  Object? _jsonEncodablePayloadFragment(Object? value) {
    if (value is Uint8List) {
      return _convertUint8ListToString(value);
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
    if (details.receiveProgress != null) {
      map['receive_progress'] = details.receiveProgress;
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
    final map = <String, Object?>{};
    if (extra.challenge != null) {
      map['challenge'] = extra.challenge;
    }
    if (extra.salt != null) {
      map['salt'] = extra.salt;
    }
    if (extra.keyLen != null) {
      map['keylen'] = extra.keyLen;
    }
    if (extra.iterations != null) {
      map['iterations'] = extra.iterations;
    }
    if (extra.memory != null) {
      map['memory'] = extra.memory;
    }
    if (extra.kdf != null) {
      map['kdf'] = extra.kdf;
    }
    if (extra.channelBinding != null) {
      map['channel_binding'] = extra.channelBinding;
    }
    if (extra.nonce != null) {
      map['nonce'] = extra.nonce;
    }
    return map;
  }
}
