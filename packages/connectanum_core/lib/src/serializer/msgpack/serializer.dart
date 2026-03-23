import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;

import 'package:connectanum_core/src/message/abstract_message.dart';
import 'package:connectanum_core/src/message/abort.dart';
import 'package:connectanum_core/src/message/abstract_message_with_payload.dart';
import 'package:connectanum_core/src/message/authenticate.dart';
import 'package:connectanum_core/src/message/call.dart';
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
import 'package:connectanum_core/src/message/registered.dart';
import 'package:connectanum_core/src/message/result.dart';
import 'package:connectanum_core/src/message/subscribe.dart';
import 'package:connectanum_core/src/message/subscribed.dart';
import 'package:connectanum_core/src/message/unregister.dart';
import 'package:connectanum_core/src/message/unregistered.dart';
import 'package:connectanum_core/src/message/unsubscribe.dart';
import 'package:connectanum_core/src/message/details.dart';
import 'package:connectanum_core/src/message/unsubscribed.dart';
import 'package:connectanum_core/src/message/welcome.dart';
import 'package:connectanum_core/src/message/yield.dart';

import '../../message/ppt_payload.dart';
import '../abstract_serializer.dart';

/// This is a seralizer for msgpack messages.
/// It is used to initialize an [AbstractTransport] object.
class Serializer extends AbstractSerializer {
  static final Logger _logger = Logger('Connectanum.Serializer');

  /// Converts a uint8 msgpack message into a WAMP message object
  @override
  AbstractMessage? deserialize(Uint8List? msgPack) {
    Object? message = msgpack_dart.deserialize(msgPack!);
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
          (message[2]['authextra'] as Map).forEach((key, value) {
            details.authextra ??= <String, dynamic>{};
            details.authextra![key] = value;
          });
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
        final welcome = Welcome(message[1], details);
        final remainingDetails = Map<String, dynamic>.from(
          message[2] as Map<dynamic, dynamic>,
        );
        remainingDetails.remove('roles');
        remainingDetails.remove('realm');
        remainingDetails.remove('authid');
        remainingDetails.remove('authprovider');
        remainingDetails.remove('authmethod');
        remainingDetails.remove('authrole');
        remainingDetails.remove('authextra');
        remainingDetails.remove('authmethods');
        if (remainingDetails.isNotEmpty) {
          details.custom.addAll(remainingDetails);
        }
        return welcome;
      }
      if (messageId == MessageTypes.codeRegistered) {
        return Registered(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeUnregistered) {
        return Unregistered(message[1]);
      }
      if (messageId == MessageTypes.codeInvocation) {
        final detailsMap = Map<String, dynamic>.from(
          message[3] as Map<dynamic, dynamic>,
        );
        final caller = detailsMap.remove('caller');
        final procedure = detailsMap.remove('procedure');
        final receiveProgress = detailsMap.remove('receive_progress');
        final pptScheme = detailsMap.remove('ppt_scheme');
        final pptSerializer = detailsMap.remove('ppt_serializer');
        final pptCipher = detailsMap.remove('ppt_cipher');
        final pptKeyId = detailsMap.remove('ppt_keyid');
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
              detailsMap,
            ),
          ),
          message,
          4,
        );
      }
      if (messageId == MessageTypes.codeResult) {
        final detailsMap = Map<String, dynamic>.from(
          message[2] as Map<dynamic, dynamic>,
        );
        final progress = detailsMap.remove('progress');
        final pptScheme = detailsMap.remove('ppt_scheme');
        final pptSerializer = detailsMap.remove('ppt_serializer');
        final pptCipher = detailsMap.remove('ppt_cipher');
        final pptKeyId = detailsMap.remove('ppt_keyid');
        return _addPayload(
          Result(
            message[1],
            ResultDetails(
              progress: progress,
              pptScheme: pptScheme,
              pptSerializer: pptSerializer,
              pptCipher: pptCipher,
              pptKeyId: pptKeyId,
              custom: detailsMap,
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
        final detailsMap = Map<String, dynamic>.from(
          message[3] as Map<dynamic, dynamic>,
        );
        final publisher = detailsMap.remove('publisher');
        final trustlevel = detailsMap.remove('trustlevel');
        final topic = detailsMap.remove('topic');
        final pptScheme = detailsMap.remove('ppt_scheme');
        final pptSerializer = detailsMap.remove('ppt_serializer');
        final pptCipher = detailsMap.remove('ppt_cipher');
        final pptKeyId = detailsMap.remove('ppt_keyid');
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
              custom: detailsMap,
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
            Map<String, Object>.from(message[3]),
            message[4],
          ),
          message,
          5,
        );
      }
      if (messageId == MessageTypes.codeAbort) {
        return Abort(
          message[2],
          message: message[1] == null ? null : message[1]['message'],
        );
      }
      if (messageId == MessageTypes.codeGoodbye) {
        return Goodbye(
          message[1] == null ? null : GoodbyeMessage(message[1]['message']),
          message[2],
        );
      }
    }
    _logger.shout('Could not deserialize the message: $msgPack');
    // TODO respond with an error
    return null;
  }

  AbstractMessageWithPayload _addPayload(
    AbstractMessageWithPayload message,
    List<dynamic> messageData,
    argumentsOffset,
  ) {
    if (messageData.length >= argumentsOffset + 1) {
      message.arguments = messageData[argumentsOffset] as List<dynamic>?;
    }
    if (messageData.length >= argumentsOffset + 2) {
      message.argumentsKeywords =
          Map.castFrom<dynamic, dynamic, String, Object>(
            messageData[argumentsOffset + 1] as Map<dynamic, dynamic>,
          );
    }
    return message;
  }

  /// Converts a WAMP message object into a uint8 msgpack message
  @override
  Uint8List serialize(AbstractMessage message) {
    if (message is Hello) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeHello) +
            msgpack_dart.serialize(message.realm) +
            _serializeDetails(message.details)!,
      );
    }
    if (message is Challenge) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeChallenge) +
            msgpack_dart.serialize(message.authMethod) +
            msgpack_dart.serialize(_challengeExtraToMap(message.extra)),
      );
    }
    if (message is Authenticate) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeAuthenticate) +
            msgpack_dart.serialize(message.signature ?? '') +
            msgpack_dart.serialize(message.extra ?? '{}'),
      );
    }
    if (message is Welcome) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeWelcome) +
            msgpack_dart.serialize(message.sessionId) +
            _serializeDetails(message.details)!,
      );
    }
    if (message is Register) {
      return Uint8List.fromList(
        [148] +
            msgpack_dart.serialize(MessageTypes.codeRegister) +
            msgpack_dart.serialize(message.requestId) +
            _serializeRegisterOptions(message.options) +
            msgpack_dart.serialize(message.procedure),
      );
    }
    if (message is Unregister) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeUnregister) +
            msgpack_dart.serialize(message.requestId) +
            msgpack_dart.serialize(message.registrationId),
      );
    }
    if (message is Call) {
      var res =
          [148] +
          msgpack_dart.serialize(MessageTypes.codeCall) +
          msgpack_dart.serialize(message.requestId) +
          _serializeCallOptions(message.options) +
          msgpack_dart.serialize(message.procedure);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Yield) {
      var res =
          [147] +
          msgpack_dart.serialize(MessageTypes.codeYield) +
          msgpack_dart.serialize(message.invocationRequestId) +
          _serializeYieldOptions(message.options);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is interrupt_msg.Interrupt) {
      final options = <String, Object?>{};
      if (message.options?.mode != null) {
        options['mode'] = message.options!.mode;
      }
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeInterrupt) +
            msgpack_dart.serialize(message.requestId) +
            msgpack_dart.serialize(options),
      );
    }
    if (message is Invocation) {
      // for serializer unit test only
      var res =
          [148] +
          msgpack_dart.serialize(MessageTypes.codeInvocation) +
          msgpack_dart.serialize(message.requestId) +
          msgpack_dart.serialize(message.registrationId) +
          msgpack_dart.serialize({});
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Publish) {
      var res =
          [148] +
          msgpack_dart.serialize(MessageTypes.codePublish) +
          msgpack_dart.serialize(message.requestId) +
          _serializePublish(message.options) +
          msgpack_dart.serialize(message.topic);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Published) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codePublished) +
            msgpack_dart.serialize(message.publishRequestId) +
            msgpack_dart.serialize(message.publicationId),
      );
    }
    if (message is Event) {
      final detailsBytes = _serializeEventDetails(message.details);
      var res =
          [148] +
          msgpack_dart.serialize(MessageTypes.codeEvent) +
          msgpack_dart.serialize(message.subscriptionId) +
          msgpack_dart.serialize(message.publicationId) +
          detailsBytes.toList();
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Subscribe) {
      return Uint8List.fromList(
        [148] +
            msgpack_dart.serialize(MessageTypes.codeSubscribe) +
            msgpack_dart.serialize(message.requestId) +
            _serializeSubscribeOptions(message.options) +
            msgpack_dart.serialize(message.topic),
      );
    }
    if (message is Subscribed) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeSubscribed) +
            msgpack_dart.serialize(message.subscribeRequestId) +
            msgpack_dart.serialize(message.subscriptionId),
      );
    }
    if (message is Unsubscribe) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeUnsubscribe) +
            msgpack_dart.serialize(message.requestId) +
            msgpack_dart.serialize(message.subscriptionId),
      );
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
          return Uint8List.fromList(
            [147] +
                msgpack_dart.serialize(MessageTypes.codeUnsubscribed) +
                msgpack_dart.serialize(message.unsubscribeRequestId) +
                msgpack_dart.serialize(map),
          );
        }
      }
      return Uint8List.fromList(
        [146] +
            msgpack_dart.serialize(MessageTypes.codeUnsubscribed) +
            msgpack_dart.serialize(message.unsubscribeRequestId),
      );
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
      var res =
          [147] +
          msgpack_dart.serialize(MessageTypes.codeResult) +
          msgpack_dart.serialize(message.callRequestId) +
          msgpack_dart.serialize(details);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Error) {
      var res =
          [149] +
          msgpack_dart.serialize(MessageTypes.codeError) +
          msgpack_dart.serialize(message.requestTypeId) +
          msgpack_dart.serialize(message.requestId) +
          msgpack_dart.serialize(message.details) +
          msgpack_dart.serialize(message.error);
      var payload = _serializePayload(message);
      res[0] += payload.payloadType;
      res += payload.payload;
      return Uint8List.fromList(res);
    }
    if (message is Abort) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeAbort) +
            msgpack_dart.serialize(
              message.message != null
                  ? {'message': message.message!.message}
                  : {},
            ) +
            msgpack_dart.serialize(message.reason),
      );
    }
    if (message is Goodbye) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeGoodbye) +
            msgpack_dart.serialize(
              message.message != null
                  ? {'message': message.message!.message ?? ""}
                  : {},
            ) +
            msgpack_dart.serialize(message.reason),
      );
    }
    if (message is Registered) {
      return Uint8List.fromList(
        [147] +
            msgpack_dart.serialize(MessageTypes.codeRegistered) +
            msgpack_dart.serialize(message.registerRequestId) +
            msgpack_dart.serialize(message.registrationId),
      );
    }
    if (message is Unregistered) {
      return Uint8List.fromList(
        [146] +
            msgpack_dart.serialize(MessageTypes.codeUnregistered) +
            msgpack_dart.serialize(message.unregisterRequestId),
      );
    }

    _logger.shout('Could not serialize the message of type: $message');
    throw UnsupportedError(
      'MsgPack serializer does not support ${message.runtimeType}',
    );
  }

  Uint8List? _serializeDetails(Details details) {
    if (details.roles != null) {
      var roles = {};
      if (details.roles!.caller != null &&
          details.roles!.caller!.features != null) {
        var callerFeatures = {};
        callerFeatures.addEntries([
          MapEntry(
            'call_canceling',
            details.roles!.caller!.features!.callCanceling,
          ),
          MapEntry(
            'call_timeout',
            details.roles!.caller!.features!.callTimeout,
          ),
          MapEntry(
            'caller_identification',
            details.roles!.caller!.features!.callerIdentification,
          ),
          MapEntry(
            'payload_passthru_mode',
            details.roles!.caller!.features!.payloadPassThruMode,
          ),
          MapEntry(
            'progressive_call_results',
            details.roles!.caller!.features!.progressiveCallResults,
          ),
        ]);
        roles.addEntries([
          MapEntry('caller', {'features': callerFeatures}),
        ]);
      }
      if (details.roles!.callee != null &&
          details.roles!.callee!.features != null) {
        var calleeFeatures = {};
        calleeFeatures.addEntries([
          MapEntry(
            'caller_identification',
            details.roles!.callee!.features!.callerIdentification,
          ),
          MapEntry(
            'call_trustlevels',
            details.roles!.callee!.features!.callTrustlevels,
          ),
          MapEntry(
            'pattern_based_registration',
            details.roles!.callee!.features!.patternBasedRegistration,
          ),
          MapEntry(
            'shared_registration',
            details.roles!.callee!.features!.sharedRegistration,
          ),
          MapEntry(
            'call_canceling',
            details.roles!.callee!.features!.callCanceling,
          ),
          MapEntry(
            'call_timeout',
            details.roles!.callee!.features!.callTimeout,
          ),
          MapEntry(
            'caller_identification',
            details.roles!.callee!.features!.callerIdentification,
          ),
          MapEntry(
            'payload_passthru_mode',
            details.roles!.callee!.features!.payloadPassThruMode,
          ),
          MapEntry(
            'progressive_call_results',
            details.roles!.callee!.features!.progressiveCallResults,
          ),
        ]);
        roles.addEntries([
          MapEntry('callee', {'features': calleeFeatures}),
        ]);
      }
      if (details.roles!.subscriber != null &&
          details.roles!.subscriber!.features != null) {
        var subscriberFeatures = {};
        subscriberFeatures.addEntries([
          MapEntry(
            'call_canceling',
            details.roles!.subscriber!.features!.callCanceling,
          ),
          MapEntry(
            'call_timeout',
            details.roles!.subscriber!.features!.callTimeout,
          ),
          MapEntry(
            'payload_passthru_mode',
            details.roles!.subscriber!.features!.payloadPassThruMode,
          ),
          MapEntry(
            'progressive_call_results',
            details.roles!.subscriber!.features!.progressiveCallResults,
          ),
          MapEntry(
            'subscription_revocation',
            details.roles!.subscriber!.features!.subscriptionRevocation,
          ),
        ]);
        roles.addEntries([
          MapEntry('subscriber', {'features': subscriberFeatures}),
        ]);
      }
      if (details.roles!.publisher != null &&
          details.roles!.publisher!.features != null) {
        var publisherFeatures = {};
        publisherFeatures.addEntries([
          MapEntry(
            'publisher_identification',
            details.roles!.publisher!.features!.publisherIdentification,
          ),
          MapEntry(
            'subscriber_blackwhite_listing',
            details.roles!.publisher!.features!.subscriberBlackWhiteListing,
          ),
          MapEntry(
            'publisher_exclusion',
            details.roles!.publisher!.features!.publisherExclusion,
          ),
          MapEntry(
            'payload_passthru_mode',
            details.roles!.publisher!.features!.payloadPassThruMode,
          ),
        ]);
        roles.addEntries([
          MapEntry('publisher', {'features': publisherFeatures}),
        ]);
      }
      var detailsParts = <String, dynamic>{};
      detailsParts['roles'] = roles;
      if (details.authid != null) {
        detailsParts['authid'] = details.authid;
      }
      if (details.authmethods != null && details.authmethods!.isNotEmpty) {
        detailsParts['authmethods'] = details.authmethods;
      }
      if (details.authextra != null) {
        detailsParts['authextra'] = details.authextra;
      }
      if (details.custom.isNotEmpty) {
        details.custom.forEach((key, value) {
          detailsParts.putIfAbsent(key, () => value);
        });
      }
      return msgpack_dart.serialize(detailsParts);
    } else {
      return null;
    }
  }

  Uint8List _serializeSubscribeOptions(SubscribeOptions? options) {
    final subscriptionOptions = <String, dynamic>{};
    if (options != null) {
      if (options.getRetained != null) {
        subscriptionOptions['get_retained'] = options.getRetained;
      }
      if (options.match != null) {
        subscriptionOptions['match'] = options.match;
      }
      if (options.metaTopic != null) {
        subscriptionOptions['meta_topic'] = options.metaTopic;
      }
      if (options.custom.isNotEmpty) {
        subscriptionOptions.addAll(options.custom);
      }
      options
          .getCustomValues<dynamic>(SubscribeOptions.customSerializerMsgpack)
          .forEach((key, value) {
            subscriptionOptions.putIfAbsent(key, () => value);
          });
    }

    return msgpack_dart.serialize(subscriptionOptions);
  }

  Uint8List _serializeRegisterOptions(RegisterOptions? options) {
    final registerOptions = <String, dynamic>{};
    if (options != null) {
      if (options.match != null) {
        registerOptions['match'] = options.match;
      }
      if (options.discloseCaller != null) {
        registerOptions['disclose_caller'] = options.discloseCaller;
      }
      if (options.invoke != null) {
        registerOptions['invoke'] = options.invoke;
      }
      if (options.custom.isNotEmpty) {
        registerOptions.addAll(options.custom);
      }
    }

    return msgpack_dart.serialize(registerOptions);
  }

  Uint8List _serializeCallOptions(CallOptions? options) {
    final callOptions = <String, dynamic>{};
    if (options != null) {
      if (options.receiveProgress != null) {
        callOptions['receive_progress'] = options.receiveProgress;
      }
      if (options.discloseMe != null) {
        callOptions['disclose_me'] = options.discloseMe;
      }
      if (options.timeout != null) {
        callOptions['timeout'] = options.timeout;
      }
      if (options.pptScheme != null) {
        callOptions['ppt_scheme'] = options.pptScheme;
      }
      if (options.pptSerializer != null) {
        callOptions['ppt_serializer'] = options.pptSerializer;
      }
      if (options.pptCipher != null) {
        callOptions['ppt_cipher'] = options.pptCipher;
      }
      if (options.pptKeyId != null) {
        callOptions['ppt_keyid'] = options.pptKeyId;
      }
      if (options.custom.isNotEmpty) {
        callOptions.addAll(options.custom);
      }
    }

    return msgpack_dart.serialize(callOptions);
  }

  Uint8List _serializeYieldOptions(YieldOptions? options) {
    final yieldOptions = <String, dynamic>{};
    if (options != null) {
      yieldOptions['progress'] = options.progress;
      if (options.pptScheme != null) {
        yieldOptions['ppt_scheme'] = options.pptScheme;
      }
      if (options.pptSerializer != null) {
        yieldOptions['ppt_serializer'] = options.pptSerializer;
      }
      if (options.pptCipher != null) {
        yieldOptions['ppt_cipher'] = options.pptCipher;
      }
      if (options.pptKeyId != null) {
        yieldOptions['ppt_keyid'] = options.pptKeyId;
      }
      if (options.custom.isNotEmpty) {
        yieldOptions.addAll(options.custom);
      }
    }
    return msgpack_dart.serialize(yieldOptions);
  }

  Uint8List _serializePublish(PublishOptions? options) {
    final publishDetails = <String, dynamic>{};
    if (options != null) {
      publishDetails.addAll({
        if (options.retain != null) 'retain': options.retain,
        if (options.discloseMe != null) 'disclose_me': options.discloseMe,
        if (options.acknowledge != null) 'acknowledge': options.acknowledge,
        if (options.excludeMe != null) 'exclude_me': options.excludeMe,
        if (options.exclude != null) 'exclude': options.exclude,
        if (options.excludeAuthId != null)
          'exclude_authid': options.excludeAuthId,
        if (options.excludeAuthRole != null)
          'exclude_auth_role': options.excludeAuthRole,
        if (options.eligible != null) 'eligible': options.eligible,
        if (options.eligibleAuthRole != null)
          'eligible_authrole': options.eligibleAuthRole,
        if (options.eligibleAuthId != null)
          'eligible_authid': options.eligibleAuthId,
        if (options.pptScheme != null) 'ppt_scheme': options.pptScheme,
        if (options.pptSerializer != null)
          'ppt_serializer': options.pptSerializer,
        if (options.pptCipher != null) 'ppt_cipher': options.pptCipher,
        if (options.pptKeyId != null) 'ppt_keyid': options.pptKeyId,
      });
      if (options.custom.isNotEmpty) {
        publishDetails.addAll(options.custom);
      }
    }
    return msgpack_dart.serialize(publishDetails);
  }

  Uint8List _serializeEventDetails(EventDetails details) {
    final map = <String, dynamic>{};
    if (details.publisher != null) {
      map['publisher'] = details.publisher;
    }
    if (details.topic != null) {
      map['topic'] = details.topic;
    }
    if (details.trustlevel != null) {
      map['trustlevel'] = details.trustlevel;
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
    return msgpack_dart.serialize(map);
  }

  /// returns bytes to add to header and serialized payload bytes
  SerializedPayload<int, Uint8List> _serializePayload(
    AbstractMessageWithPayload message,
  ) {
    if (message.argumentsKeywords != null) {
      return SerializedPayload(
        2,
        Uint8List.fromList(
          msgpack_dart.serialize(message.arguments ?? []) +
              msgpack_dart.serialize(message.argumentsKeywords),
        ),
      );
    } else if (message.arguments != null) {
      return SerializedPayload(1, msgpack_dart.serialize(message.arguments));
    }
    return SerializedPayload(0, Uint8List(0));
  }

  /// Converts a uint8 data into a PPT Payload Object
  @override
  PPTPayload? deserializePPT(Uint8List binPayload) {
    List<dynamic>? arguments;
    Map<String, dynamic>? argumentsKeywords;

    Object? decodedObject = msgpack_dart.deserialize(binPayload);

    if (decodedObject is Map) {
      if (decodedObject['args'] != null && decodedObject['args'] is List) {
        arguments = decodedObject['args'] as List<dynamic>?;
      }

      if (decodedObject['kwargs'] != null && decodedObject['kwargs'] is Map) {
        argumentsKeywords = Map.castFrom<dynamic, dynamic, String, Object>(
          decodedObject['kwargs'] as Map<dynamic, dynamic>,
        );
      }

      return PPTPayload(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      );
    }

    _logger.shout('Could not deserialize the message: $binPayload');
    // TODO respond with an error
    return null;
  }

  /// Converts a PPT Payload Object into a uint8 array
  @override
  Uint8List serializePPT(PPTPayload pptPayload) {
    var pptMap = {
      'args': pptPayload.arguments,
      'kwargs': pptPayload.argumentsKeywords,
    };
    return msgpack_dart.serialize(pptMap);
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

/// this is a little helper class for payload
/// serialization and type "safety"
class SerializedPayload<TTag, TPayload> {
  final TTag payloadType;
  final TPayload payload;

  SerializedPayload(this.payloadType, this.payload);
}
