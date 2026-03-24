import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:logging/logging.dart';

/// This is a serializer for msgpack messages.
/// It is used to initialize an [AbstractTransport] object.
class Serializer extends AbstractSerializer {
  static final Logger _logger = Logger('Connectanum.Serializer');

  @override
  AbstractMessage? deserialize(Uint8List? message) {
    if (message is List) {
      final decodedMessage = cbor.decode(message!.toList());
      if (decodedMessage is CborList) {
        final cborMessageId = decodedMessage[0];
        if (cborMessageId is CborInt) {
          final messageId = cborMessageId.toInt();
          if (messageId == MessageTypes.codeAbort &&
              decodedMessage.length == 3) {
            return Abort(
              (decodedMessage[2] as CborString).toString(),
              message:
                  decodedMessage[1] is CborMap &&
                      (decodedMessage[1] as CborMap)[CborString('message')] !=
                          null
                  ? ((decodedMessage[1] as CborMap)[CborString('message')]
                            as CborString)
                        .toString()
                  : null,
            );
          }
          if (messageId == MessageTypes.codeChallenge &&
              decodedMessage.length == 3) {
            return Challenge(
              (decodedMessage[1] as CborString).toString(),
              Extra(
                challenge:
                    (decodedMessage[2] as CborMap)[CborString('challenge')] ==
                        null
                    ? null
                    : ((decodedMessage[2] as CborMap)[CborString('challenge')]
                              as CborString)
                          .toString(),
                salt: (decodedMessage[2] as CborMap)[CborString('salt')] == null
                    ? null
                    : ((decodedMessage[2] as CborMap)[CborString('salt')]
                              as CborString)
                          .toString(),
                keyLen:
                    (decodedMessage[2] as CborMap)[CborString('keylen')] == null
                    ? null
                    : ((decodedMessage[2] as CborMap)[CborString('keylen')]
                              as CborInt)
                          .toInt(),
                iterations:
                    (decodedMessage[2] as CborMap)[CborString('iterations')] ==
                        null
                    ? null
                    : ((decodedMessage[2] as CborMap)[CborString('iterations')]
                              as CborInt)
                          .toInt(),
                memory:
                    (decodedMessage[2] as CborMap)[CborString('memory')] == null
                    ? null
                    : ((decodedMessage[2] as CborMap)[CborString('memory')]
                              as CborInt)
                          .toInt(),
                kdf: (decodedMessage[2] as CborMap)[CborString('kdf')] == null
                    ? null
                    : ((decodedMessage[2] as CborMap)[CborString('kdf')]
                              as CborString)
                          .toString(),
                nonce:
                    (decodedMessage[2] as CborMap)[CborString('nonce')] == null
                    ? null
                    : ((decodedMessage[2] as CborMap)[CborString('nonce')]
                              as CborString)
                          .toString(),
              ),
            );
          }
          if (messageId == MessageTypes.codeWelcome &&
              decodedMessage.length == 3) {
            final details = Details();
            details.realm =
                (((decodedMessage[2] as CborMap)[CborString('realm')] ??
                            CborString(''))
                        as CborString)
                    .toString();
            details.authid =
                (((decodedMessage[2] as CborMap)[CborString('authid')] ??
                            CborString(''))
                        as CborString)
                    .toString();
            details.authprovider =
                (((decodedMessage[2] as CborMap)[CborString('authprovider')] ??
                            CborString(''))
                        as CborString)
                    .toString();
            details.authmethod =
                (((decodedMessage[2] as CborMap)[CborString('authmethod')] ??
                            CborString(''))
                        as CborString)
                    .toString();
            details.authrole =
                (((decodedMessage[2] as CborMap)[CborString('authrole')] ??
                            CborString(''))
                        as CborString)
                    .toString();
            if ((decodedMessage[2] as CborMap)[CborString('authextra')] !=
                null) {
              ((decodedMessage[2] as CborMap)[CborString('authextra')]
                      as CborMap)
                  .forEach((key, value) {
                    details.authextra ??= <String, dynamic>{};
                    if (value is CborString) {
                      details.authextra![(key as CborString).toString()] = value
                          .toString();
                    }
                    if (value is CborInt) {
                      details.authextra![(key as CborString).toString()] = value
                          .toInt();
                    }
                    if (value is CborFloat) {
                      details.authextra![(key as CborString).toString()] =
                          value.value;
                    }
                    if (value is CborBool) {
                      details.authextra![(key as CborString).toString()] =
                          value.value;
                    }
                    if (value is CborBase64) {
                      details.authextra![(key as CborString).toString()] = value
                          .toString();
                    }
                  });
            }
            if ((decodedMessage[2] as CborMap)[CborString('roles')] != null) {
              details.roles = Roles();
              if (((decodedMessage[2] as CborMap)[CborString('roles')]
                      as CborMap)[CborString('dealer')] !=
                  null) {
                details.roles!.dealer = Dealer();
                if ((((decodedMessage[2] as CborMap)[CborString('roles')]
                            as CborMap)[CborString('dealer')]
                        as CborMap)[CborString('features')] !=
                    null) {
                  details.roles!.dealer!.features = DealerFeatures();
                  details.roles!.dealer!.features!.callerIdentification =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'caller_identification',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.dealer!.features!.callTrustLevels =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'call_trustlevels',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.dealer!.features!.patternBasedRegistration =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'pattern_based_registration',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.dealer!.features!.registrationMetaApi =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'registration_meta_api',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.dealer!.features!.sharedRegistration =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'shared_registration',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.dealer!.features!.sessionMetaApi =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'session_meta_api',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.dealer!.features!.callTimeout =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString('call_timeout')] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.dealer!.features!.callCanceling =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'call_canceling',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.dealer!.features!.progressiveCallResults =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'progressive_call_results',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.dealer!.features!.payloadPassThruMode =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('dealer')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'payload_passthru_mode',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                }
              }
              if (((decodedMessage[2] as CborMap)[CborString('roles')]
                      as CborMap)[CborString('broker')] !=
                  null) {
                details.roles!.broker = Broker();
                if ((((decodedMessage[2] as CborMap)[CborString('roles')]
                            as CborMap)[CborString('broker')]
                        as CborMap)[CborString('features')] !=
                    null) {
                  details.roles!.broker!.features = BrokerFeatures();
                  details.roles!.broker!.features!.publisherIdentification =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('broker')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'publisher_identification',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.broker!.features!.publicationTrustLevels =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('broker')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'publication_trustlevels',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.broker!.features!.patternBasedSubscription =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('broker')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'pattern_based_subscription',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.broker!.features!.subscriptionMetaApi =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('broker')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'subscription_meta_api',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.broker!.features!.subscriberBlackWhiteListing =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('broker')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'subscriber_blackwhite_listing',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.broker!.features!.sessionMetaApi =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('broker')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'session_meta_api',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.broker!.features!.publisherExclusion =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('broker')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'publisher_exclusion',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.broker!.features!.eventHistory =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('broker')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'event_history',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                  details.roles!.broker!.features!.payloadPassThruMode =
                      ((((((decodedMessage[2] as CborMap)[CborString('roles')]
                                              as CborMap)[CborString('broker')]
                                          as CborMap)[CborString('features')]
                                      as CborMap)[CborString(
                                    'payload_passthru_mode',
                                  )] ??
                                  CborBool(false))
                              as CborBool)
                          .value;
                }
              }
            }
            final authMethodsValue =
                (decodedMessage[2] as CborMap)[CborString('authmethods')];
            if (authMethodsValue is CborList) {
              final authMethods = authMethodsValue.toObject();
              if (authMethods is List) {
                details.authmethods = authMethods.cast<String>();
              }
            }
            final remainingDetails = _cborMapToStringMap(
              decodedMessage[2] as CborMap,
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
              details.custom.addAll(remainingDetails);
            }
            return Welcome((decodedMessage[1] as CborInt).toInt(), details);
          }
          if (messageId == MessageTypes.codeRegistered &&
              decodedMessage.length == 3) {
            return Registered(
              (decodedMessage[1] as CborInt).toInt(),
              (decodedMessage[2] as CborInt).toInt(),
            );
          }
          if (messageId == MessageTypes.codeUnregistered &&
              decodedMessage.length == 2) {
            return Unregistered((decodedMessage[1] as CborInt).toInt());
          }
          if (messageId == MessageTypes.codeInvocation &&
              decodedMessage.length > 3) {
            final detailsMap = _cborMapToStringMap(
              decodedMessage[3] as CborMap,
            );
            final callerValue = detailsMap.remove('caller');
            final int? caller = callerValue is num ? callerValue.toInt() : null;
            final procedureValue = detailsMap.remove('procedure');
            final String? procedure = procedureValue as String?;
            final receiveProgressValue = detailsMap.remove('receive_progress');
            final bool? receiveProgress = receiveProgressValue is bool
                ? receiveProgressValue
                : null;
            final pptSchemeValue = detailsMap.remove('ppt_scheme');
            final String? pptScheme = pptSchemeValue as String?;
            final pptSerializerValue = detailsMap.remove('ppt_serializer');
            final String? pptSerializer = pptSerializerValue as String?;
            final pptCipherValue = detailsMap.remove('ppt_cipher');
            final String? pptCipher = pptCipherValue as String?;
            final pptKeyIdValue = detailsMap.remove('ppt_keyid');
            final String? pptKeyId = pptKeyIdValue as String?;
            return _addPayload(
              Invocation(
                (decodedMessage[1] as CborInt).toInt(),
                (decodedMessage[2] as CborInt).toInt(),
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
              decodedMessage,
              4,
            );
          }
          if (messageId == MessageTypes.codeResult &&
              decodedMessage.length > 2) {
            final detailsMap = _cborMapToStringMap(
              decodedMessage[2] as CborMap,
            );
            final progressValue = detailsMap.remove('progress');
            final bool? progress = progressValue is bool ? progressValue : null;
            final pptSchemeValue = detailsMap.remove('ppt_scheme');
            final String? pptScheme = pptSchemeValue as String?;
            final pptSerializerValue = detailsMap.remove('ppt_serializer');
            final String? pptSerializer = pptSerializerValue as String?;
            final pptCipherValue = detailsMap.remove('ppt_cipher');
            final String? pptCipher = pptCipherValue as String?;
            final pptKeyIdValue = detailsMap.remove('ppt_keyid');
            final String? pptKeyId = pptKeyIdValue as String?;
            return _addPayload(
              Result(
                (decodedMessage[1] as CborInt).toInt(),
                ResultDetails(
                  progress: progress,
                  pptScheme: pptScheme,
                  pptSerializer: pptSerializer,
                  pptCipher: pptCipher,
                  pptKeyId: pptKeyId,
                  custom: detailsMap,
                ),
              ),
              decodedMessage,
              3,
            );
          }
          if (messageId == MessageTypes.codePublished &&
              decodedMessage.length == 3) {
            return Published(
              (decodedMessage[1] as CborInt).toInt(),
              (decodedMessage[2] as CborInt).toInt(),
            );
          }
          if (messageId == MessageTypes.codeSubscribed &&
              decodedMessage.length == 3) {
            return Subscribed(
              (decodedMessage[1] as CborInt).toInt(),
              (decodedMessage[2] as CborInt).toInt(),
            );
          }
          if (messageId == MessageTypes.codeUnsubscribed &&
              decodedMessage.length > 1) {
            return Unsubscribed(
              (decodedMessage[1] as CborInt).toInt(),
              decodedMessage.length == 2
                  ? null
                  : UnsubscribedDetails(
                      (decodedMessage[2] as CborMap)[CborString(
                                'subscription',
                              )] ==
                              null
                          ? null
                          : ((decodedMessage[2] as CborMap)[CborString(
                                      'subscription',
                                    )]
                                    as CborInt)
                                .toInt(),
                      (decodedMessage[2] as CborMap)[CborString('reason')] ==
                              null
                          ? null
                          : ((decodedMessage[2] as CborMap)[CborString(
                                      'reason',
                                    )]
                                    as CborString)
                                .toString(),
                    ),
            );
          }
          if (messageId == MessageTypes.codeEvent &&
              decodedMessage.length > 3) {
            final detailsMap = _cborMapToStringMap(
              decodedMessage[3] as CborMap,
            );
            final publisherValue = detailsMap.remove('publisher');
            final int? publisher = publisherValue is num
                ? publisherValue.toInt()
                : null;
            final trustLevelValue = detailsMap.remove('trustlevel');
            final int? trustLevel = trustLevelValue is num
                ? trustLevelValue.toInt()
                : null;
            final topicValue = detailsMap.remove('topic');
            final String? topic = topicValue as String?;
            final pptSchemeValue = detailsMap.remove('ppt_scheme');
            final String? pptScheme = pptSchemeValue as String?;
            final pptSerializerValue = detailsMap.remove('ppt_serializer');
            final String? pptSerializer = pptSerializerValue as String?;
            final pptCipherValue = detailsMap.remove('ppt_cipher');
            final String? pptCipher = pptCipherValue as String?;
            final pptKeyIdValue = detailsMap.remove('ppt_keyid');
            final String? pptKeyId = pptKeyIdValue as String?;
            return _addPayload(
              Event(
                (decodedMessage[1] as CborInt).toInt(),
                (decodedMessage[2] as CborInt).toInt(),
                EventDetails(
                  publisher: publisher,
                  trustlevel: trustLevel,
                  topic: topic,
                  pptScheme: pptScheme,
                  pptSerializer: pptSerializer,
                  pptCipher: pptCipher,
                  pptKeyid: pptKeyId,
                  custom: detailsMap,
                ),
              ),
              decodedMessage,
              4,
            );
          }
          if (messageId == MessageTypes.codeError &&
              decodedMessage.length > 4) {
            return _addPayload(
              Error(
                (decodedMessage[1] as CborInt).toInt(),
                (decodedMessage[2] as CborInt).toInt(),
                Map<String, Object>.from(
                  (decodedMessage[3] as CborMap).toObject() as Map,
                ),
                (decodedMessage[4] as CborString).toString(),
              ),
              decodedMessage,
              5,
            );
          }
          if (messageId == MessageTypes.codeGoodbye) {
            return Goodbye(
              decodedMessage.length == 1
                  ? null
                  : GoodbyeMessage(
                      (decodedMessage[1] as CborMap)[CborString('message')] ==
                              null
                          ? null
                          : ((decodedMessage[1] as CborMap)[CborString(
                                      'message',
                                    )]
                                    as CborString)
                                .toString(),
                    ),
              (decodedMessage[2] as CborString).toString(),
            );
          }
        }
      }
      return null;
    }
    _logger.shout('Could not deserialize the message: $message');
    // TODO respond with an error
    return null;
  }

  AbstractMessageWithPayload _addPayload(
    AbstractMessageWithPayload message,
    List<dynamic> messageData,
    argumentsOffset,
  ) {
    if (messageData.length >= argumentsOffset + 1) {
      if (messageData[argumentsOffset] is CborList) {
        message.arguments =
            (messageData[argumentsOffset] as CborList).toObject()
                as List<dynamic>;
      }
    }
    if (messageData.length >= argumentsOffset + 2) {
      if (messageData[argumentsOffset + 1] is CborMap) {
        message.argumentsKeywords =
            Map.castFrom<dynamic, dynamic, String, dynamic>(
              (messageData[argumentsOffset + 1] as CborMap).toObject()
                  as Map<dynamic, dynamic>,
            );
      }
    }
    return message;
  }

  @override
  Uint8List serialize(AbstractMessage message) {
    if (message is Hello) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeHello,
            message.realm,
            _serializeDetails(message.details)!,
          ]),
        ),
      );
    }
    if (message is Challenge) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeChallenge,
            message.authMethod,
            _challengeExtraToMap(message.extra),
          ]),
        ),
      );
    }
    if (message is Authenticate) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeAuthenticate,
            message.signature ?? '',
            message.extra ?? {},
          ]),
        ),
      );
    }
    if (message is Welcome) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeWelcome,
            message.sessionId,
            _serializeDetails(message.details)!,
          ]),
        ),
      );
    }
    if (message is Register) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeRegister,
            message.requestId,
            _serializeRegisterOptions(message.options),
            message.procedure,
          ]),
        ),
      );
    }
    if (message is Unregister) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeUnregister,
            message.requestId,
            message.registrationId,
          ]),
        ),
      );
    }
    if (message is Call) {
      var structuredMessage = [
        MessageTypes.codeCall,
        message.requestId,
        _serializeCallOptions(message.options),
        message.procedure,
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Yield) {
      var structuredMessage = [
        MessageTypes.codeYield,
        message.invocationRequestId,
        _serializeYieldOptions(message.options),
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Interrupt) {
      final details = <String, Object?>{};
      if (message.options?.mode != null) {
        details['mode'] = message.options!.mode;
      }
      return Uint8List.fromList(
        cbor.encode(
          CborValue([MessageTypes.codeInterrupt, message.requestId, details]),
        ),
      );
    }
    if (message is Invocation) {
      // for serializer unit test only
      var structuredMessage = [
        MessageTypes.codeInvocation,
        message.requestId,
        message.registrationId,
        {},
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Publish) {
      var structuredMessage = [
        MessageTypes.codePublish,
        message.requestId,
        _serializePublish(message.options),
        message.topic,
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Published) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codePublished,
            message.publishRequestId,
            message.publicationId,
          ]),
        ),
      );
    }
    if (message is Event) {
      var structuredMessage = [
        MessageTypes.codeEvent,
        message.subscriptionId,
        message.publicationId,
        _serializeEventDetails(message.details),
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Subscribe) {
      var structuredMessage = [
        MessageTypes.codeSubscribe,
        message.requestId,
        _serializeSubscribeOptions(message.options),
        message.topic,
      ];
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Subscribed) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeSubscribed,
            message.subscribeRequestId,
            message.subscriptionId,
          ]),
        ),
      );
    }
    if (message is Unsubscribe) {
      var structuredMessage = [
        MessageTypes.codeUnsubscribe,
        message.requestId,
        message.subscriptionId,
      ];
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
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
            cbor.encode(
              CborValue([
                MessageTypes.codeUnsubscribed,
                message.unsubscribeRequestId,
                map,
              ]),
            ),
          );
        }
      }
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeUnsubscribed,
            message.unsubscribeRequestId,
          ]),
        ),
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
      final structuredMessage = [
        MessageTypes.codeResult,
        message.callRequestId,
        details,
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Error) {
      var structuredMessage = [
        MessageTypes.codeError,
        message.requestTypeId,
        message.requestId,
        message.details,
        message.error,
      ];
      _appendPayloadToList(structuredMessage, message);
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Abort) {
      var structuredMessage = [
        MessageTypes.codeAbort,
        message.message != null ? {'message': message.message!.message} : {},
        message.reason,
      ];
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Goodbye) {
      var structuredMessage = [
        MessageTypes.codeGoodbye,
        message.message != null
            ? {'message': message.message!.message ?? ''}
            : {},
        message.reason,
      ];
      return Uint8List.fromList(cbor.encode(CborValue(structuredMessage)));
    }
    if (message is Registered) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeRegistered,
            message.registerRequestId,
            message.registrationId,
          ]),
        ),
      );
    }
    if (message is Unregistered) {
      return Uint8List.fromList(
        cbor.encode(
          CborValue([
            MessageTypes.codeUnregistered,
            message.unregisterRequestId,
          ]),
        ),
      );
    }

    _logger.shout('Could not serialize the message of type: $message');
    throw UnsupportedError(
      'CBOR serializer does not support ${message.runtimeType}',
    );
  }

  dynamic _firstPayload(AbstractMessageWithPayload message) {
    return message.transparentBinaryPayload ??
        message.arguments ??
        (message.argumentsKeywords != null ? [] : null);
  }

  dynamic _secondPayload(AbstractMessageWithPayload message) {
    if (message.transparentBinaryPayload == null &&
        message.argumentsKeywords != null) {
      return message.argumentsKeywords;
    }
    return null;
  }

  void _appendPayloadToList(
    List structuredMessage,
    AbstractMessageWithPayload message,
  ) {
    var firstPayload = _firstPayload(message);
    if (firstPayload != null) {
      structuredMessage.add(firstPayload);
      var secondPayload = _secondPayload(message);
      if (secondPayload != null) {
        structuredMessage.add(secondPayload);
      }
    }
  }

  Map<String, dynamic> _cborMapToStringMap(CborMap? map) {
    final result = <String, dynamic>{};
    if (map == null) {
      return result;
    }
    map.forEach((key, value) {
      final resolvedKey = key.toObject().toString();
      result[resolvedKey] = value.toObject();
    });
    return result;
  }

  Map? _serializeDetails(Details details) {
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
            'call_timeout',
            details.roles!.callee!.features!.callTimeout,
          ),
          MapEntry(
            'call_canceling',
            details.roles!.callee!.features!.callCanceling,
          ),
          MapEntry(
            'progressive_call_results',
            details.roles!.callee!.features!.progressiveCallResults,
          ),
          MapEntry(
            'payload_passthru_mode',
            details.roles!.callee!.features!.payloadPassThruMode,
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
            'call_timeout',
            details.roles!.subscriber!.features!.callTimeout,
          ),
          MapEntry(
            'call_canceling',
            details.roles!.subscriber!.features!.callCanceling,
          ),
          MapEntry(
            'progressive_call_results',
            details.roles!.subscriber!.features!.progressiveCallResults,
          ),
          MapEntry(
            'payload_passthru_mode',
            details.roles!.subscriber!.features!.payloadPassThruMode,
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
      if (details.realm != null) {
        detailsParts['realm'] = details.realm;
      }
      if (details.authid != null) {
        detailsParts['authid'] = details.authid;
      }
      if (details.authmethod != null) {
        detailsParts['authmethod'] = details.authmethod;
      }
      if (details.authprovider != null) {
        detailsParts['authprovider'] = details.authprovider;
      }
      if (details.authrole != null) {
        detailsParts['authrole'] = details.authrole;
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
      return detailsParts;
    } else {
      return null;
    }
  }

  Map _serializeRegisterOptions(RegisterOptions? options) {
    var optionMap = {};
    if (options != null) {
      if (options.match != null) {
        optionMap.addEntries([MapEntry('match', options.match)]);
      }
      if (options.discloseCaller != null) {
        optionMap.addEntries([
          MapEntry('disclose_caller', options.discloseCaller),
        ]);
      }
      if (options.invoke != null) {
        optionMap.addEntries([MapEntry('invoke', options.invoke)]);
      }
      if (options.custom.isNotEmpty) {
        optionMap.addAll(options.custom);
      }
    }

    return optionMap;
  }

  Map _serializeCallOptions(CallOptions? options) {
    var optionMap = {};
    if (options != null) {
      if (options.receiveProgress != null) {
        optionMap.addEntries([
          MapEntry('receive_progress', options.receiveProgress!),
        ]);
      }
      if (options.discloseMe != null) {
        optionMap.addEntries([MapEntry('disclose_me', options.discloseMe!)]);
      }
      if (options.timeout != null) {
        optionMap.addEntries([MapEntry('timeout', options.timeout!)]);
      }
      if (options.custom.isNotEmpty) {
        optionMap.addAll(options.custom);
      }
    }
    return optionMap;
  }

  Map _serializeYieldOptions(YieldOptions? options) {
    var optionsMap = {};
    if (options != null) {
      optionsMap.addEntries([MapEntry('progress', options.progress)]);
      if (options.custom.isNotEmpty) {
        optionsMap.addAll(options.custom);
      }
    }
    return optionsMap;
  }

  Map _serializePublish(PublishOptions? options) {
    var optionMap = {};
    if (options != null) {
      if (options.retain != null) {
        optionMap.addEntries([MapEntry('retain', options.retain)]);
      }
      if (options.discloseMe != null) {
        optionMap.addEntries([MapEntry('retain', options.discloseMe)]);
      }
      if (options.acknowledge != null) {
        optionMap.addEntries([MapEntry('acknowledge', options.acknowledge)]);
      }
      if (options.excludeMe != null) {
        optionMap.addEntries([MapEntry('exclude_me', options.excludeMe)]);
      }
      if (options.exclude != null) {
        optionMap.addEntries([MapEntry('exclude', options.exclude)]);
      }
      if (options.excludeAuthId != null) {
        optionMap.addEntries([
          MapEntry('exclude_authid', options.excludeAuthId),
        ]);
      }
      if (options.excludeAuthRole != null) {
        optionMap.addEntries([
          MapEntry('exclude_authrole', options.excludeAuthRole),
        ]);
      }
      if (options.eligible != null) {
        optionMap.addEntries([MapEntry('eligible', options.eligible)]);
      }
      if (options.eligibleAuthId != null) {
        optionMap.addEntries([
          MapEntry('eligible_authid', options.eligibleAuthId),
        ]);
      }
      if (options.eligibleAuthRole != null) {
        optionMap.addEntries([
          MapEntry('eligible_authrole', options.eligibleAuthRole),
        ]);
      }
      if (options.custom.isNotEmpty) {
        optionMap.addAll(options.custom);
      }
    }
    return optionMap;
  }

  Map<String, dynamic> _serializeEventDetails(EventDetails details) {
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
    return map;
  }

  Map _serializeSubscribeOptions(SubscribeOptions? options) {
    var jsonOptions = {};
    if (options != null) {
      if (options.getRetained != null) {
        jsonOptions.addEntries([MapEntry('get_retained', options.getRetained)]);
      }
      if (options.match != null) {
        jsonOptions.addEntries([MapEntry('match', options.match)]);
      }
      if (options.metaTopic != null) {
        jsonOptions.addEntries([MapEntry('meta_topic', options.metaTopic)]);
      }
      if (options.custom.isNotEmpty) {
        jsonOptions.addAll(options.custom);
      }
      options
          .getCustomValues<dynamic>(SubscribeOptions.customSerializerCbor)
          .forEach((key, value) {
            jsonOptions.addEntries([MapEntry(key, value)]);
          });
    }

    return jsonOptions;
  }

  /// Converts a uint8 data into a PPT Payload Object
  @override
  PPTPayload? deserializePPT(Uint8List binPayload) {
    List<dynamic>? arguments;
    Map<String, dynamic>? argumentsKeywords;

    final decodedMessage = cbor.decode(binPayload);
    if (decodedMessage is CborMap) {
      if (decodedMessage[CborString('args')] != null &&
          decodedMessage[CborString('args')] is CborList) {
        arguments =
            (decodedMessage[CborString('args')] as CborList).toObject()
                as List<dynamic>;
      }

      if (decodedMessage[CborString('kwargs')] != null &&
          decodedMessage[CborString('kwargs')] is CborMap) {
        argumentsKeywords = Map.castFrom<dynamic, dynamic, String, dynamic>(
          (decodedMessage[CborString('kwargs')] as CborMap).toObject()
              as Map<dynamic, dynamic>,
        );
      }

      return PPTPayload(
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      );
    }
    return null;
  }

  /// Converts a PPT Payload Object into a uint8 array
  @override
  Uint8List serializePPT(PPTPayload pptPayload) {
    var pptMap = {
      'args': pptPayload.arguments,
      'kwargs': pptPayload.argumentsKeywords,
    };
    return Uint8List.fromList(cbor.encode(CborValue(pptMap)));
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
