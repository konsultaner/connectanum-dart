import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:logging/logging.dart';

/// This is a serializer for msgpack messages.
/// It is used to initialize an [AbstractTransport] object.
class Serializer extends AbstractSerializer {
  static final Logger _logger = Logger('Connectanum.Serializer');
  static final Uint8List _emptyListBytes = Uint8List.fromList(
    cbor.encode(CborValue(const [])),
  );
  static final Uint8List _pptArgsKeyBytes = Uint8List.fromList(
    cbor.encode(CborValue('args')),
  );
  static final Uint8List _pptKwargsKeyBytes = Uint8List.fromList(
    cbor.encode(CborValue('kwargs')),
  );
  static final Uint8List _nullBytes = Uint8List.fromList(
    cbor.encode(CborValue(null)),
  );
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

  @override
  AbstractMessage? deserialize(Uint8List? message) {
    if (message == null) {
      return null;
    }
    final fastPathMessage = _deserializeFastPathMessage(message);
    if (fastPathMessage != null) {
      return fastPathMessage;
    }
    final decodedMessage = cbor.decode(message.toList());
    if (decodedMessage is CborList) {
      final cborMessageId = decodedMessage[0];
      if (cborMessageId is CborInt) {
        final messageId = cborMessageId.toInt();
        if (messageId == MessageTypes.codeAbort && decodedMessage.length == 3) {
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
              nonce: (decodedMessage[2] as CborMap)[CborString('nonce')] == null
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
          if ((decodedMessage[2] as CborMap)[CborString('authextra')] != null) {
            ((decodedMessage[2] as CborMap)[CborString('authextra')] as CborMap)
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
                                    as CborMap)[CborString('call_canceling')] ??
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
                                    as CborMap)[CborString('event_history')] ??
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
        if (messageId == MessageTypes.codeInterrupt &&
            decodedMessage.length >= 2) {
          final options =
              decodedMessage.length > 2 && decodedMessage[2] is CborMap
              ? (() {
                  final options = InterruptOptions();
                  options.mode =
                      ((decodedMessage[2] as CborMap)[CborString('mode')]
                              as CborString?)
                          ?.toString();
                  return options;
                })()
              : null;
          return Interrupt(
            (decodedMessage[1] as CborInt).toInt(),
            options: options,
          );
        }
        if (messageId == MessageTypes.codeCancel &&
            decodedMessage.length >= 2) {
          final options =
              decodedMessage.length > 2 && decodedMessage[2] is CborMap
              ? (() {
                  final options = CancelOptions();
                  options.mode =
                      ((decodedMessage[2] as CborMap)[CborString('mode')]
                              as CborString?)
                          ?.toString();
                  return options;
                })()
              : null;
          return Cancel(
            (decodedMessage[1] as CborInt).toInt(),
            options: options,
          );
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
          final detailsMap = _cborMapToStringMap(decodedMessage[3] as CborMap);
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
        if (messageId == MessageTypes.codeResult && decodedMessage.length > 2) {
          final detailsMap = _cborMapToStringMap(decodedMessage[2] as CborMap);
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
                    (decodedMessage[2] as CborMap)[CborString('reason')] == null
                        ? null
                        : ((decodedMessage[2] as CborMap)[CborString('reason')]
                                  as CborString)
                              .toString(),
                  ),
          );
        }
        if (messageId == MessageTypes.codeEvent && decodedMessage.length > 3) {
          final detailsMap = _cborMapToStringMap(decodedMessage[3] as CborMap);
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
        if (messageId == MessageTypes.codeError && decodedMessage.length > 4) {
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
                        : ((decodedMessage[1] as CborMap)[CborString('message')]
                                  as CborString)
                              .toString(),
                  ),
            (decodedMessage[2] as CborString).toString(),
          );
        }
      }
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
        message.arguments = _cborListToDart(
          messageData[argumentsOffset] as CborList,
        );
      }
    }
    if (messageData.length >= argumentsOffset + 2) {
      if (messageData[argumentsOffset + 1] is CborMap) {
        message.argumentsKeywords = _cborMapToStringMap(
          messageData[argumentsOffset + 1] as CborMap,
        );
      }
    }
    return message;
  }

  AbstractMessage? _deserializeFastPathMessage(Uint8List message) {
    final ranges = _parseCborTopLevelRanges(message);
    if (ranges == null || ranges.isEmpty) {
      return null;
    }
    final messageId = _decodeCborIntFragment(_sliceRange(message, ranges[0]));
    if (messageId == MessageTypes.codeAbort) {
      if (ranges.length < 3) {
        return null;
      }
      return Abort(
        _decodeCborStringFragment(_sliceRange(message, ranges[2])),
        message: _decodeAbortDetailMap(
          _decodeCborDetailMap(_sliceRange(message, ranges[1])),
        ),
      );
    }
    if (messageId == MessageTypes.codeChallenge) {
      if (ranges.length < 3) {
        return null;
      }
      return Challenge(
        _decodeCborStringFragment(_sliceRange(message, ranges[1])),
        _decodeChallengeExtraDetailMap(
          _decodeCborDetailMap(_sliceRange(message, ranges[2])),
        ),
      );
    }
    if (messageId == MessageTypes.codeWelcome) {
      if (ranges.length < 3) {
        return null;
      }
      return Welcome(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
        _decodeWelcomeDetailMap(
          _decodeCborDetailMap(_sliceRange(message, ranges[2])),
        ),
      );
    }
    if (messageId == MessageTypes.codeRegistered) {
      if (ranges.length < 3) {
        return null;
      }
      return Registered(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
        _decodeCborIntFragment(_sliceRange(message, ranges[2])),
      );
    }
    if (messageId == MessageTypes.codeUnregistered) {
      if (ranges.length < 2) {
        return null;
      }
      return Unregistered(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
      );
    }
    if (messageId == MessageTypes.codeInvocation) {
      if (ranges.length < 4) {
        return null;
      }
      final detailsMap = _decodeCborDetailMap(_sliceRange(message, ranges[3]));
      final invocation = Invocation(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
        _decodeCborIntFragment(_sliceRange(message, ranges[2])),
        InvocationDetails(
          _coerceNumToInt(detailsMap['caller']),
          detailsMap['procedure'] as String?,
          detailsMap['receive_progress'] as bool?,
          detailsMap['ppt_scheme'] as String?,
          detailsMap['ppt_serializer'] as String?,
          detailsMap['ppt_cipher'] as String?,
          detailsMap['ppt_keyid'] as String?,
          _extractCustomCborDetails(detailsMap, _invocationDetailKeys),
        ),
      );
      _setLazyCborPayload(invocation, message, ranges, 4);
      return invocation;
    }
    if (messageId == MessageTypes.codeResult) {
      if (ranges.length < 3) {
        return null;
      }
      final detailsMap = _decodeCborDetailMap(_sliceRange(message, ranges[2]));
      final result = Result(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
        ResultDetails(
          progress: detailsMap['progress'] as bool?,
          pptScheme: detailsMap['ppt_scheme'] as String?,
          pptSerializer: detailsMap['ppt_serializer'] as String?,
          pptCipher: detailsMap['ppt_cipher'] as String?,
          pptKeyId: detailsMap['ppt_keyid'] as String?,
          custom: _extractCustomCborDetails(detailsMap, _resultDetailKeys),
        ),
      );
      _setLazyCborPayload(result, message, ranges, 3);
      return result;
    }
    if (messageId == MessageTypes.codeEvent) {
      if (ranges.length < 4) {
        return null;
      }
      final detailsMap = _decodeCborDetailMap(_sliceRange(message, ranges[3]));
      final event = Event(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
        _decodeCborIntFragment(_sliceRange(message, ranges[2])),
        EventDetails(
          publisher: _coerceNumToInt(detailsMap['publisher']),
          trustlevel: _coerceNumToInt(detailsMap['trustlevel']),
          topic: detailsMap['topic'] as String?,
          pptScheme: detailsMap['ppt_scheme'] as String?,
          pptSerializer: detailsMap['ppt_serializer'] as String?,
          pptCipher: detailsMap['ppt_cipher'] as String?,
          pptKeyid: detailsMap['ppt_keyid'] as String?,
          custom: _extractCustomCborDetails(detailsMap, _eventDetailKeys),
        ),
      );
      _setLazyCborPayload(event, message, ranges, 4);
      return event;
    }
    if (messageId == MessageTypes.codeError) {
      if (ranges.length < 5) {
        return null;
      }
      final error = Error(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
        _decodeCborIntFragment(_sliceRange(message, ranges[2])),
        Map<String, Object>.from(
          _decodeCborDetailMap(_sliceRange(message, ranges[3])),
        ),
        _decodeCborStringFragment(_sliceRange(message, ranges[4])),
      );
      _setLazyCborPayload(error, message, ranges, 5);
      return error;
    }
    if (messageId == MessageTypes.codePublished) {
      if (ranges.length < 3) {
        return null;
      }
      return Published(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
        _decodeCborIntFragment(_sliceRange(message, ranges[2])),
      );
    }
    if (messageId == MessageTypes.codeSubscribed) {
      if (ranges.length < 3) {
        return null;
      }
      return Subscribed(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
        _decodeCborIntFragment(_sliceRange(message, ranges[2])),
      );
    }
    if (messageId == MessageTypes.codeUnsubscribed) {
      if (ranges.length < 2) {
        return null;
      }
      return Unsubscribed(
        _decodeCborIntFragment(_sliceRange(message, ranges[1])),
        ranges.length < 3
            ? null
            : _decodeUnsubscribedDetailMap(
                _decodeCborDetailMap(_sliceRange(message, ranges[2])),
              ),
      );
    }
    if (messageId == MessageTypes.codeGoodbye) {
      if (ranges.length < 3) {
        return null;
      }
      return Goodbye(
        _decodeGoodbyeDetailMap(
          _decodeCborDetailMap(_sliceRange(message, ranges[1])),
        ),
        _decodeCborStringFragment(_sliceRange(message, ranges[2])),
      );
    }
    return null;
  }

  String? _decodeAbortDetailMap(Map<String, dynamic> detailsMap) {
    return detailsMap['message'] as String?;
  }

  Extra _decodeChallengeExtraDetailMap(Map<String, dynamic> detailsMap) {
    return Extra(
      challenge: detailsMap['challenge'] as String?,
      salt: detailsMap['salt'] as String?,
      channelBinding: detailsMap['channel_binding'] as String?,
      keyLen: _coerceNumToInt(detailsMap['keylen']),
      iterations: _coerceNumToInt(detailsMap['iterations']),
      memory: _coerceNumToInt(detailsMap['memory']),
      kdf: detailsMap['kdf'] as String?,
      nonce: detailsMap['nonce'] as String?,
    );
  }

  Details _decodeWelcomeDetailMap(Map<String, dynamic> detailsMap) {
    final details = Details();
    details.realm = detailsMap['realm'] as String? ?? '';
    details.authid = detailsMap['authid'] as String? ?? '';
    details.authprovider = detailsMap['authprovider'] as String? ?? '';
    details.authmethod = detailsMap['authmethod'] as String? ?? '';
    details.authrole = detailsMap['authrole'] as String? ?? '';
    final authMethods = detailsMap['authmethods'];
    if (authMethods is List) {
      details.authmethods = authMethods.cast<String>();
    }
    final authExtra = _asStringDynamicMap(detailsMap['authextra']);
    if (authExtra != null) {
      details.authextra = authExtra;
    }
    final rolesMap = _asStringDynamicMap(detailsMap['roles']);
    if (rolesMap != null) {
      final roles = Roles();
      final dealerMap = _asStringDynamicMap(rolesMap['dealer']);
      if (dealerMap != null) {
        roles.dealer = Dealer();
        final featuresMap = _asStringDynamicMap(dealerMap['features']);
        if (featuresMap != null) {
          roles.dealer!.features = DealerFeatures();
          roles.dealer!.features!.callerIdentification =
              featuresMap['caller_identification'] as bool? ?? false;
          roles.dealer!.features!.callTrustLevels =
              featuresMap['call_trustlevels'] as bool? ?? false;
          roles.dealer!.features!.patternBasedRegistration =
              featuresMap['pattern_based_registration'] as bool? ?? false;
          roles.dealer!.features!.registrationMetaApi =
              featuresMap['registration_meta_api'] as bool? ?? false;
          roles.dealer!.features!.sharedRegistration =
              featuresMap['shared_registration'] as bool? ?? false;
          roles.dealer!.features!.sessionMetaApi =
              featuresMap['session_meta_api'] as bool? ?? false;
          roles.dealer!.features!.callTimeout =
              featuresMap['call_timeout'] as bool? ?? false;
          roles.dealer!.features!.callCanceling =
              featuresMap['call_canceling'] as bool? ?? false;
          roles.dealer!.features!.progressiveCallResults =
              featuresMap['progressive_call_results'] as bool? ?? false;
          roles.dealer!.features!.payloadPassThruMode =
              featuresMap['payload_passthru_mode'] as bool? ?? false;
        }
      }
      final brokerMap = _asStringDynamicMap(rolesMap['broker']);
      if (brokerMap != null) {
        roles.broker = Broker();
        final featuresMap = _asStringDynamicMap(brokerMap['features']);
        if (featuresMap != null) {
          roles.broker!.features = BrokerFeatures();
          roles.broker!.features!.publisherIdentification =
              featuresMap['publisher_identification'] as bool? ?? false;
          roles.broker!.features!.publicationTrustLevels =
              featuresMap['publication_trustlevels'] as bool? ?? false;
          roles.broker!.features!.patternBasedSubscription =
              featuresMap['pattern_based_subscription'] as bool? ?? false;
          roles.broker!.features!.subscriptionMetaApi =
              featuresMap['subscription_meta_api'] as bool? ?? false;
          roles.broker!.features!.subscriberBlackWhiteListing =
              featuresMap['subscriber_blackwhite_listing'] as bool? ?? false;
          roles.broker!.features!.sessionMetaApi =
              featuresMap['session_meta_api'] as bool? ?? false;
          roles.broker!.features!.publisherExclusion =
              featuresMap['publisher_exclusion'] as bool? ?? false;
          roles.broker!.features!.eventHistory =
              featuresMap['event_history'] as bool? ?? false;
          roles.broker!.features!.payloadPassThruMode =
              featuresMap['payload_passthru_mode'] as bool? ?? false;
        }
      }
      if (roles.dealer != null || roles.broker != null) {
        details.roles = roles;
      }
    }
    final remainingDetails = Map<String, dynamic>.from(detailsMap);
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
    return details;
  }

  UnsubscribedDetails _decodeUnsubscribedDetailMap(
    Map<String, dynamic> detailsMap,
  ) {
    return UnsubscribedDetails(
      _coerceNumToInt(detailsMap['subscription']),
      detailsMap['reason'] as String?,
    );
  }

  GoodbyeMessage? _decodeGoodbyeDetailMap(Map<String, dynamic> detailsMap) {
    final message = detailsMap['message'] as String?;
    return message == null ? null : GoodbyeMessage(message);
  }

  Map<String, dynamic>? _asStringDynamicMap(Object? value) {
    if (value is Map) {
      return value.map(
        (key, nestedValue) => MapEntry(key.toString(), nestedValue),
      );
    }
    return null;
  }

  void _setLazyCborPayload(
    AbstractMessageWithPayload message,
    Uint8List bytes,
    List<_ByteRange> ranges,
    int argumentsOffset,
  ) {
    final hasArguments = ranges.length > argumentsOffset;
    final hasArgumentsKeywords = ranges.length > argumentsOffset + 1;
    if (!hasArguments && !hasArgumentsKeywords) {
      return;
    }
    message.setLazyPayload(
      argumentsBytes: hasArguments
          ? _sliceRange(bytes, ranges[argumentsOffset])
          : null,
      argumentsDecoder: hasArguments ? _decodeCborArgumentListFragment : null,
      argumentsKeywordsBytes: hasArgumentsKeywords
          ? _sliceRange(bytes, ranges[argumentsOffset + 1])
          : null,
      argumentsKeywordsDecoder: hasArgumentsKeywords
          ? _decodeCborKeywordMapFragment
          : null,
      encoding: LazyPayloadEncoding.cbor,
    );
  }

  int _decodeCborIntFragment(Uint8List bytes) {
    final decoded = _decodePayloadFragment(bytes);
    if (decoded is num) {
      return decoded.toInt();
    }
    throw ArgumentError('Expected CBOR integer but got $decoded');
  }

  String _decodeCborStringFragment(Uint8List bytes) {
    final decoded = _decodePayloadFragment(bytes);
    if (decoded is String) {
      return decoded;
    }
    throw ArgumentError('Expected CBOR string but got $decoded');
  }

  Map<String, dynamic> _decodeCborDetailMap(Uint8List bytes) {
    final decoded = _decodePayloadFragment(bytes);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw ArgumentError('Expected CBOR map but got $decoded');
  }

  List<dynamic> _decodeCborArgumentListFragment(Uint8List bytes) {
    final decoded = _decodePayloadFragment(bytes);
    if (decoded is List) {
      return List<dynamic>.from(decoded);
    }
    throw ArgumentError('Expected CBOR arguments list but got $decoded');
  }

  Map<String, dynamic> _decodeCborKeywordMapFragment(Uint8List bytes) {
    final decoded = _decodePayloadFragment(bytes);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw ArgumentError('Expected CBOR keyword arguments map but got $decoded');
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
      return _serializeCborPayloadMessage(4, [
            MessageTypes.codeCall,
            message.requestId,
            _serializeCallOptions(message.options),
            message.procedure,
          ], message) ??
          (() {
            var structuredMessage = [
              MessageTypes.codeCall,
              message.requestId,
              _serializeCallOptions(message.options),
              message.procedure,
            ];
            _appendPayloadToList(structuredMessage, message);
            return Uint8List.fromList(
              cbor.encode(CborValue(structuredMessage)),
            );
          })();
    }
    if (message is Yield) {
      return _serializeCborPayloadMessage(3, [
            MessageTypes.codeYield,
            message.invocationRequestId,
            _serializeYieldOptions(message.options),
          ], message) ??
          (() {
            var structuredMessage = [
              MessageTypes.codeYield,
              message.invocationRequestId,
              _serializeYieldOptions(message.options),
            ];
            _appendPayloadToList(structuredMessage, message);
            return Uint8List.fromList(
              cbor.encode(CborValue(structuredMessage)),
            );
          })();
    }
    if (message is Cancel) {
      final details = <String, Object?>{};
      if (message.options?.mode != null) {
        details['mode'] = message.options!.mode;
      }
      return Uint8List.fromList(
        cbor.encode(
          CborValue([MessageTypes.codeCancel, message.requestId, details]),
        ),
      );
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
      return _serializeCborPayloadMessage(4, [
            MessageTypes.codeInvocation,
            message.requestId,
            message.registrationId,
            _serializeInvocationDetails(message.details),
          ], message) ??
          (() {
            var structuredMessage = [
              MessageTypes.codeInvocation,
              message.requestId,
              message.registrationId,
              _serializeInvocationDetails(message.details),
            ];
            _appendPayloadToList(structuredMessage, message);
            return Uint8List.fromList(
              cbor.encode(CborValue(structuredMessage)),
            );
          })();
    }
    if (message is Publish) {
      return _serializeCborPayloadMessage(4, [
            MessageTypes.codePublish,
            message.requestId,
            _serializePublish(message.options),
            message.topic,
          ], message) ??
          (() {
            var structuredMessage = [
              MessageTypes.codePublish,
              message.requestId,
              _serializePublish(message.options),
              message.topic,
            ];
            _appendPayloadToList(structuredMessage, message);
            return Uint8List.fromList(
              cbor.encode(CborValue(structuredMessage)),
            );
          })();
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
      return _serializeCborPayloadMessage(4, [
            MessageTypes.codeEvent,
            message.subscriptionId,
            message.publicationId,
            _serializeEventDetails(message.details),
          ], message) ??
          (() {
            var structuredMessage = [
              MessageTypes.codeEvent,
              message.subscriptionId,
              message.publicationId,
              _serializeEventDetails(message.details),
            ];
            _appendPayloadToList(structuredMessage, message);
            return Uint8List.fromList(
              cbor.encode(CborValue(structuredMessage)),
            );
          })();
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
      return _serializeCborPayloadMessage(3, [
            MessageTypes.codeResult,
            message.callRequestId,
            details,
          ], message) ??
          (() {
            final structuredMessage = [
              MessageTypes.codeResult,
              message.callRequestId,
              details,
            ];
            _appendPayloadToList(structuredMessage, message);
            return Uint8List.fromList(
              cbor.encode(CborValue(structuredMessage)),
            );
          })();
    }
    if (message is Error) {
      return _serializeCborPayloadMessage(5, [
            MessageTypes.codeError,
            message.requestTypeId,
            message.requestId,
            message.details,
            message.error,
          ], message) ??
          (() {
            var structuredMessage = [
              MessageTypes.codeError,
              message.requestTypeId,
              message.requestId,
              message.details,
              message.error,
            ];
            _appendPayloadToList(structuredMessage, message);
            return Uint8List.fromList(
              cbor.encode(CborValue(structuredMessage)),
            );
          })();
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

  Uint8List? _serializeCborPayloadMessage(
    int fixedLength,
    List<Object?> fixedValues,
    AbstractMessageWithPayload message,
  ) {
    final payloadFragments = _lazyCborPayloadFragments(message);
    if (payloadFragments == null) {
      return null;
    }
    final builder = BytesBuilder(copy: false)
      ..add([_fixArrayHeader(fixedLength + payloadFragments.length)]);
    for (final value in fixedValues) {
      builder.add(_encodeCborValue(value));
    }
    for (final fragment in payloadFragments) {
      builder.add(fragment);
    }
    return builder.takeBytes();
  }

  List<Uint8List>? _lazyCborPayloadFragments(
    AbstractMessageWithPayload message,
  ) {
    if (message.lazyPayloadEncoding != LazyPayloadEncoding.cbor) {
      return null;
    }
    final encodedArgs = message.debugEncodedArgumentsBytes;
    final encodedKwargs = message.debugEncodedArgumentsKeywordsBytes;
    if (encodedArgs == null && encodedKwargs == null) {
      return null;
    }

    final fragments = <Uint8List>[];
    if (encodedArgs != null) {
      fragments.add(encodedArgs);
    } else if (encodedKwargs != null) {
      fragments.add(
        message.arguments == null
            ? _emptyListBytes
            : _encodeCborValue(message.arguments),
      );
    }

    if (encodedKwargs != null) {
      fragments.add(encodedKwargs);
    } else if (message.argumentsKeywords != null) {
      fragments.add(_encodeCborValue(message.argumentsKeywords));
    }

    return fragments;
  }

  Uint8List _encodeCborValue(Object? value) {
    return Uint8List.fromList(cbor.encode(CborValue(value)));
  }

  int _fixArrayHeader(int length) {
    assert(length >= 0 && length <= 23);
    return 0x80 | length;
  }

  dynamic _firstPayload(AbstractMessageWithPayload message) {
    if (message.lazyPayloadEncoding == LazyPayloadEncoding.cbor) {
      final encodedArgs = message.debugEncodedArgumentsBytes;
      final encodedKwargs = message.debugEncodedArgumentsKeywordsBytes;
      if (encodedArgs != null) {
        return _decodePayloadFragment(encodedArgs);
      }
      if (encodedKwargs != null) {
        if (message.arguments != null) {
          return message.arguments;
        }
        return _decodePayloadFragment(_emptyListBytes);
      }
    }
    return message.transparentBinaryPayload ??
        message.arguments ??
        (message.argumentsKeywords != null ? [] : null);
  }

  dynamic _secondPayload(AbstractMessageWithPayload message) {
    if (message.lazyPayloadEncoding == LazyPayloadEncoding.cbor) {
      final encodedKwargs = message.debugEncodedArgumentsKeywordsBytes;
      if (encodedKwargs != null) {
        return _decodePayloadFragment(encodedKwargs);
      }
    }
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

  Object? _decodePayloadFragment(Uint8List bytes) {
    final decoded = cbor.decode(bytes);
    return _cborValueToDart(decoded);
  }

  Map<String, dynamic> _cborMapToStringMap(CborMap? map) {
    final result = <String, dynamic>{};
    if (map == null) {
      return result;
    }
    map.forEach((key, value) {
      final resolvedKey = _cborValueToDart(key).toString();
      result[resolvedKey] = _cborValueToDart(value);
    });
    return result;
  }

  List<dynamic> _cborListToDart(CborList list) {
    return list.map(_cborValueToDart).toList(growable: false);
  }

  Object? _cborValueToDart(Object? value) {
    if (value is CborBytes) {
      return Uint8List.fromList(value.bytes);
    }
    if (value is CborList) {
      return _cborListToDart(value);
    }
    if (value is CborMap) {
      final result = <Object?, Object?>{};
      value.forEach((key, nestedValue) {
        result[_cborValueToDart(key)] = _cborValueToDart(nestedValue);
      });
      return result;
    }
    if (value is CborValue) {
      return value.toObject();
    }
    return value;
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
      if (options.pptScheme != null) {
        optionMap.addEntries([MapEntry('ppt_scheme', options.pptScheme!)]);
      }
      if (options.pptSerializer != null) {
        optionMap.addEntries([
          MapEntry('ppt_serializer', options.pptSerializer!),
        ]);
      }
      if (options.pptCipher != null) {
        optionMap.addEntries([MapEntry('ppt_cipher', options.pptCipher!)]);
      }
      if (options.pptKeyId != null) {
        optionMap.addEntries([MapEntry('ppt_keyid', options.pptKeyId!)]);
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
      if (options.pptScheme != null) {
        optionsMap.addEntries([MapEntry('ppt_scheme', options.pptScheme!)]);
      }
      if (options.pptSerializer != null) {
        optionsMap.addEntries([
          MapEntry('ppt_serializer', options.pptSerializer!),
        ]);
      }
      if (options.pptCipher != null) {
        optionsMap.addEntries([MapEntry('ppt_cipher', options.pptCipher!)]);
      }
      if (options.pptKeyId != null) {
        optionsMap.addEntries([MapEntry('ppt_keyid', options.pptKeyId!)]);
      }
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
        optionMap.addEntries([MapEntry('disclose_me', options.discloseMe)]);
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
      if (options.pptScheme != null) {
        optionMap.addEntries([MapEntry('ppt_scheme', options.pptScheme)]);
      }
      if (options.pptSerializer != null) {
        optionMap.addEntries([
          MapEntry('ppt_serializer', options.pptSerializer),
        ]);
      }
      if (options.pptCipher != null) {
        optionMap.addEntries([MapEntry('ppt_cipher', options.pptCipher)]);
      }
      if (options.pptKeyId != null) {
        optionMap.addEntries([MapEntry('ppt_keyid', options.pptKeyId)]);
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

  Map<String, dynamic> _serializeInvocationDetails(InvocationDetails details) {
    final map = <String, dynamic>{};
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

  Map<String, dynamic> _extractCustomCborDetails(
    Map<String, dynamic> source,
    Set<String> knownKeys,
  ) {
    Map<String, dynamic>? custom;
    source.forEach((key, value) {
      if (knownKeys.contains(key)) {
        return;
      }
      custom ??= <String, dynamic>{};
      custom![key] = value;
    });
    return custom ?? <String, dynamic>{};
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
        arguments = _cborListToDart(
          decodedMessage[CborString('args')] as CborList,
        );
      }

      if (decodedMessage[CborString('kwargs')] != null &&
          decodedMessage[CborString('kwargs')] is CborMap) {
        argumentsKeywords = Map.castFrom<Object?, Object?, String, dynamic>(
          _cborValueToDart(decodedMessage[CborString('kwargs')])!
              as Map<Object?, Object?>,
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
    final argsBytes = argumentsBytes ?? _encodeCborValue(arguments);
    final kwargsBytes =
        argumentsKeywordsBytes ?? _encodeCborValue(argumentsKeywords);
    final builder = BytesBuilder(copy: false)
      ..add([0xa2])
      ..add(_pptArgsKeyBytes)
      ..add(argsBytes.isEmpty ? _nullBytes : argsBytes)
      ..add(_pptKwargsKeyBytes)
      ..add(kwargsBytes.isEmpty ? _nullBytes : kwargsBytes);
    return builder.takeBytes();
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

class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;
}

class _CborArrayHeader {
  const _CborArrayHeader(this.length, this.nextOffset);

  final int length;
  final int nextOffset;
}

Uint8List _sliceRange(Uint8List bytes, _ByteRange range) {
  return Uint8List.sublistView(bytes, range.start, range.end);
}

List<_ByteRange>? _parseCborTopLevelRanges(Uint8List bytes) {
  final header = _readCborArrayHeader(bytes, 0);
  if (header == null) {
    return null;
  }
  var offset = header.nextOffset;
  final ranges = <_ByteRange>[];
  for (var index = 0; index < header.length; index++) {
    final start = offset;
    final next = _skipCborValue(bytes, offset);
    if (next == null) {
      return null;
    }
    ranges.add(_ByteRange(start, next));
    offset = next;
  }
  return ranges;
}

_CborArrayHeader? _readCborArrayHeader(Uint8List bytes, int offset) {
  if (offset >= bytes.length) {
    return null;
  }
  final lead = bytes[offset];
  final majorType = lead >> 5;
  if (majorType != 4) {
    return null;
  }
  final lengthInfo = _readCborLength(bytes, offset + 1, lead & 0x1f);
  if (lengthInfo == null || lengthInfo.length == null) {
    return null;
  }
  return _CborArrayHeader(lengthInfo.length!, lengthInfo.nextOffset);
}

class _CborLengthInfo {
  const _CborLengthInfo(this.length, this.nextOffset);

  final int? length;
  final int nextOffset;
}

_CborLengthInfo? _readCborLength(
  Uint8List bytes,
  int offset,
  int additionalInfo,
) {
  if (additionalInfo < 24) {
    return _CborLengthInfo(additionalInfo, offset);
  }
  switch (additionalInfo) {
    case 24:
      if (offset + 1 > bytes.length) {
        return null;
      }
      return _CborLengthInfo(bytes[offset], offset + 1);
    case 25:
      if (offset + 2 > bytes.length) {
        return null;
      }
      return _CborLengthInfo(
        ByteData.sublistView(bytes, offset, offset + 2).getUint16(0),
        offset + 2,
      );
    case 26:
      if (offset + 4 > bytes.length) {
        return null;
      }
      return _CborLengthInfo(
        ByteData.sublistView(bytes, offset, offset + 4).getUint32(0),
        offset + 4,
      );
    case 27:
      if (offset + 8 > bytes.length) {
        return null;
      }
      final data = ByteData.sublistView(bytes, offset, offset + 8);
      final high = data.getUint32(0);
      final low = data.getUint32(4);
      final value = (BigInt.from(high) << 32) | BigInt.from(low);
      if (value > BigInt.from(0x7fffffff)) {
        return null;
      }
      return _CborLengthInfo(value.toInt(), offset + 8);
    case 31:
      return _CborLengthInfo(null, offset);
    default:
      return null;
  }
}

int? _skipCborValue(Uint8List bytes, int offset) {
  if (offset >= bytes.length) {
    return null;
  }
  final lead = bytes[offset];
  final majorType = lead >> 5;
  final additionalInfo = lead & 0x1f;
  final lengthInfo = _readCborLength(bytes, offset + 1, additionalInfo);
  if (lengthInfo == null) {
    return null;
  }
  switch (majorType) {
    case 0:
    case 1:
      return lengthInfo.nextOffset;
    case 2:
    case 3:
      if (lengthInfo.length == null) {
        return _skipIndefiniteCborStringsOrBytes(bytes, lengthInfo.nextOffset);
      }
      final next = lengthInfo.nextOffset + lengthInfo.length!;
      return next <= bytes.length ? next : null;
    case 4:
      return lengthInfo.length == null
          ? _skipIndefiniteCborArray(bytes, lengthInfo.nextOffset)
          : _skipDefiniteCborArray(
              bytes,
              lengthInfo.nextOffset,
              lengthInfo.length!,
            );
    case 5:
      return lengthInfo.length == null
          ? _skipIndefiniteCborMap(bytes, lengthInfo.nextOffset)
          : _skipDefiniteCborMap(
              bytes,
              lengthInfo.nextOffset,
              lengthInfo.length!,
            );
    case 6:
      return _skipCborValue(bytes, lengthInfo.nextOffset);
    case 7:
      return lengthInfo.nextOffset;
    default:
      return null;
  }
}

int? _skipDefiniteCborArray(Uint8List bytes, int offset, int length) {
  var current = offset;
  for (var index = 0; index < length; index++) {
    final next = _skipCborValue(bytes, current);
    if (next == null) {
      return null;
    }
    current = next;
  }
  return current;
}

int? _skipDefiniteCborMap(Uint8List bytes, int offset, int length) {
  var current = offset;
  for (var index = 0; index < length; index++) {
    final nextKey = _skipCborValue(bytes, current);
    if (nextKey == null) {
      return null;
    }
    final nextValue = _skipCborValue(bytes, nextKey);
    if (nextValue == null) {
      return null;
    }
    current = nextValue;
  }
  return current;
}

int? _skipIndefiniteCborStringsOrBytes(Uint8List bytes, int offset) {
  var current = offset;
  while (true) {
    if (current >= bytes.length) {
      return null;
    }
    if (bytes[current] == 0xff) {
      return current + 1;
    }
    final next = _skipCborValue(bytes, current);
    if (next == null) {
      return null;
    }
    current = next;
  }
}

int? _skipIndefiniteCborArray(Uint8List bytes, int offset) {
  var current = offset;
  while (true) {
    if (current >= bytes.length) {
      return null;
    }
    if (bytes[current] == 0xff) {
      return current + 1;
    }
    final next = _skipCborValue(bytes, current);
    if (next == null) {
      return null;
    }
    current = next;
  }
}

int? _skipIndefiniteCborMap(Uint8List bytes, int offset) {
  var current = offset;
  while (true) {
    if (current >= bytes.length) {
      return null;
    }
    if (bytes[current] == 0xff) {
      return current + 1;
    }
    final nextKey = _skipCborValue(bytes, current);
    if (nextKey == null) {
      return null;
    }
    final nextValue = _skipCborValue(bytes, nextKey);
    if (nextValue == null) {
      return null;
    }
    current = nextValue;
  }
}

int? _coerceNumToInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return null;
}
