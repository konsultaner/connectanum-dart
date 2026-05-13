import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;

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
  static final Uint8List _pptArgsKeyBytes = msgpack_dart.serialize('args');
  static final Uint8List _pptKwargsKeyBytes = msgpack_dart.serialize('kwargs');
  static final Uint8List _nilBytes = msgpack_dart.serialize(null);
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
  static const Set<String> _callOptionKeys = {
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

  /// Converts a uint8 msgpack message into a WAMP message object
  @override
  AbstractMessage? deserialize(Uint8List? msgPack) {
    if (msgPack == null) {
      return null;
    }
    final fastPathMessage = _deserializeFastPathMessage(msgPack);
    if (fastPathMessage != null) {
      return fastPathMessage;
    }
    Object? message = msgpack_dart.deserialize(msgPack);
    if (message is List) {
      int messageId = message[0];
      if (messageId == MessageTypes.codeHello) {
        return Hello(
          message[1] as String?,
          _decodeDetailsMap(
            Map<dynamic, dynamic>.from(message[2] as Map<dynamic, dynamic>),
          ),
        );
      }
      if (messageId == MessageTypes.codeChallenge) {
        return Challenge(
          message[1],
          _decodeChallengeExtraMap(
            Map<dynamic, dynamic>.from(message[2] as Map<dynamic, dynamic>),
          ),
        );
      }
      if (messageId == MessageTypes.codeAuthenticate) {
        return Authenticate(signature: message[1] as String?)
          ..extra = message[2] is Map
              ? Map<String, Object?>.from(
                  _normalizeDynamicMap(
                    Map<dynamic, dynamic>.from(
                      message[2] as Map<dynamic, dynamic>,
                    ),
                  ),
                )
              : <String, Object?>{};
      }
      if (messageId == MessageTypes.codeWelcome) {
        return Welcome(
          message[1],
          _decodeWelcomeDetailsMap(
            Map<dynamic, dynamic>.from(message[2] as Map<dynamic, dynamic>),
          ),
        );
      }
      if (messageId == MessageTypes.codeRegister) {
        return Register(
          message[1],
          message[3],
          options: _decodeRegisterOptions(
            message[2] is Map
                ? _normalizeDynamicMap(
                    Map<dynamic, dynamic>.from(
                      message[2] as Map<dynamic, dynamic>,
                    ),
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
                  ? _normalizeDynamicMap(
                      Map<dynamic, dynamic>.from(
                        message[2] as Map<dynamic, dynamic>,
                      ),
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
                  ? _normalizeDynamicMap(
                      Map<dynamic, dynamic>.from(
                        message[2] as Map<dynamic, dynamic>,
                      ),
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
                  ? _normalizeDynamicMap(
                      Map<dynamic, dynamic>.from(
                        message[2] as Map<dynamic, dynamic>,
                      ),
                    )
                  : null,
            ),
          ),
          message,
          4,
        );
      }
      if (messageId == MessageTypes.codeRegistered) {
        return Registered(message[1], message[2]);
      }
      if (messageId == MessageTypes.codeUnregistered) {
        return Unregistered(message[1]);
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
            ? Map<dynamic, dynamic>.from(message[2] as Map<dynamic, dynamic>)
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
            ? Map<dynamic, dynamic>.from(message[2] as Map<dynamic, dynamic>)
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
                ? _normalizeDynamicMap(
                    Map<dynamic, dynamic>.from(
                      message[2] as Map<dynamic, dynamic>,
                    ),
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
              : _decodeUnsubscribedDetailsMap(
                  Map<dynamic, dynamic>.from(
                    message[2] as Map<dynamic, dynamic>,
                  ),
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
          message: _decodeAbortMessageMap(
            message[1] is Map
                ? Map<dynamic, dynamic>.from(
                    message[1] as Map<dynamic, dynamic>,
                  )
                : null,
          ),
        );
      }
      if (messageId == MessageTypes.codeGoodbye) {
        return Goodbye(
          _decodeGoodbyeMessageMap(
            message[1] is Map
                ? Map<dynamic, dynamic>.from(
                    message[1] as Map<dynamic, dynamic>,
                  )
                : null,
          ),
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
      final arguments = messageData[argumentsOffset];
      if (arguments is Uint8List) {
        message.transparentBinaryPayload = arguments;
      } else {
        message.arguments = arguments as List<dynamic>?;
      }
    }
    if (messageData.length >= argumentsOffset + 2) {
      message.argumentsKeywords =
          Map.castFrom<dynamic, dynamic, String, Object>(
            messageData[argumentsOffset + 1] as Map<dynamic, dynamic>,
          );
    }
    return message;
  }

  AbstractMessage? _deserializeFastPathMessage(Uint8List msgPack) {
    final ranges = _parseMsgPackTopLevelRanges(msgPack);
    if (ranges == null || ranges.isEmpty) {
      return null;
    }
    final messageId = _decodeMsgPackFragment(_sliceRange(msgPack, ranges[0]));
    if (messageId is! int) {
      return null;
    }
    if (messageId == MessageTypes.codeChallenge) {
      if (ranges.length < 3) {
        return null;
      }
      return Challenge(
        _decodeMsgPackString(_sliceRange(msgPack, ranges[1])),
        _decodeChallengeExtraMap(
          _decodeMsgPackMap(_sliceRange(msgPack, ranges[2])),
        ),
      );
    }
    if (messageId == MessageTypes.codeWelcome) {
      if (ranges.length < 3) {
        return null;
      }
      return Welcome(
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[1])),
        _decodeWelcomeDetailsMap(
          _decodeMsgPackMap(_sliceRange(msgPack, ranges[2])),
        ),
      );
    }
    if (messageId == MessageTypes.codeRegistered) {
      if (ranges.length < 3) {
        return null;
      }
      return Registered(
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[1])),
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[2])),
      );
    }
    if (messageId == MessageTypes.codeUnregistered) {
      if (ranges.length < 2) {
        return null;
      }
      return Unregistered(_decodeMsgPackInt(_sliceRange(msgPack, ranges[1])));
    }
    if (messageId == MessageTypes.codeInvocation) {
      if (ranges.length < 4) {
        return null;
      }
      final detailsMap = _decodeMsgPackMap(_sliceRange(msgPack, ranges[3]));
      final invocation = Invocation(
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[1])),
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[2])),
        InvocationDetails(
          _coerceInt(detailsMap['caller']),
          detailsMap['procedure'] as String?,
          detailsMap['receive_progress'] as bool?,
          detailsMap['ppt_scheme'] as String?,
          detailsMap['ppt_serializer'] as String?,
          detailsMap['ppt_cipher'] as String?,
          detailsMap['ppt_keyid'] as String?,
          _extractCustomDetails(detailsMap, _invocationDetailKeys),
        ),
      );
      _setLazyMsgPackPayload(invocation, msgPack, ranges, 4);
      return invocation;
    }
    if (messageId == MessageTypes.codeResult) {
      if (ranges.length < 3) {
        return null;
      }
      final detailsMap = _decodeMsgPackMap(_sliceRange(msgPack, ranges[2]));
      final result = Result(
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[1])),
        ResultDetails(
          progress: detailsMap['progress'] as bool?,
          pptScheme: detailsMap['ppt_scheme'] as String?,
          pptSerializer: detailsMap['ppt_serializer'] as String?,
          pptCipher: detailsMap['ppt_cipher'] as String?,
          pptKeyId: detailsMap['ppt_keyid'] as String?,
          custom: _extractCustomDetails(detailsMap, _resultDetailKeys),
        ),
      );
      _setLazyMsgPackPayload(result, msgPack, ranges, 3);
      return result;
    }
    if (messageId == MessageTypes.codeEvent) {
      if (ranges.length < 4) {
        return null;
      }
      final detailsMap = _decodeMsgPackMap(_sliceRange(msgPack, ranges[3]));
      final event = Event(
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[1])),
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[2])),
        EventDetails(
          publisher: _coerceInt(detailsMap['publisher']),
          trustlevel: _coerceInt(detailsMap['trustlevel']),
          topic: detailsMap['topic'] as String?,
          pptScheme: detailsMap['ppt_scheme'] as String?,
          pptSerializer: detailsMap['ppt_serializer'] as String?,
          pptCipher: detailsMap['ppt_cipher'] as String?,
          pptKeyid: detailsMap['ppt_keyid'] as String?,
          custom: _extractCustomDetails(detailsMap, _eventDetailKeys),
        ),
      );
      _setLazyMsgPackPayload(event, msgPack, ranges, 4);
      return event;
    }
    if (messageId == MessageTypes.codeError) {
      if (ranges.length < 5) {
        return null;
      }
      final error = Error(
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[1])),
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[2])),
        Map<String, Object>.from(
          _decodeMsgPackMap(_sliceRange(msgPack, ranges[3])),
        ),
        _decodeMsgPackString(_sliceRange(msgPack, ranges[4])),
      );
      _setLazyMsgPackPayload(error, msgPack, ranges, 5);
      return error;
    }
    if (messageId == MessageTypes.codePublished) {
      if (ranges.length < 3) {
        return null;
      }
      return Published(
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[1])),
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[2])),
      );
    }
    if (messageId == MessageTypes.codeSubscribed) {
      if (ranges.length < 3) {
        return null;
      }
      return Subscribed(
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[1])),
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[2])),
      );
    }
    if (messageId == MessageTypes.codeUnsubscribed) {
      if (ranges.length < 2) {
        return null;
      }
      return Unsubscribed(
        _decodeMsgPackInt(_sliceRange(msgPack, ranges[1])),
        ranges.length < 3
            ? null
            : _decodeUnsubscribedDetailsMap(
                _decodeMsgPackMap(_sliceRange(msgPack, ranges[2])),
              ),
      );
    }
    if (messageId == MessageTypes.codeAbort) {
      if (ranges.length < 3) {
        return null;
      }
      return Abort(
        _decodeMsgPackString(_sliceRange(msgPack, ranges[2])),
        message: _decodeAbortMessageMap(
          _decodeMsgPackMap(_sliceRange(msgPack, ranges[1])),
        ),
      );
    }
    if (messageId == MessageTypes.codeGoodbye) {
      if (ranges.length < 3) {
        return null;
      }
      return Goodbye(
        _decodeGoodbyeMessageMap(
          _decodeMsgPackMap(_sliceRange(msgPack, ranges[1])),
        ),
        _decodeMsgPackString(_sliceRange(msgPack, ranges[2])),
      );
    }
    return null;
  }

  Extra _decodeChallengeExtraMap(Map<dynamic, dynamic> extraMap) {
    return Extra.fromMap(_normalizeDynamicMap(extraMap));
  }

  Details _decodeWelcomeDetailsMap(Map<dynamic, dynamic> detailsMap) {
    final details = Details();
    details.setLazyFieldsLoader(() => _normalizeDynamicMap(detailsMap));
    return details;
  }

  UnsubscribedDetails _decodeUnsubscribedDetailsMap(
    Map<dynamic, dynamic> detailsMap,
  ) {
    return UnsubscribedDetails(
      _coerceInt(detailsMap['subscription']),
      detailsMap['reason'] as String?,
    );
  }

  String? _decodeAbortMessageMap(Map<dynamic, dynamic>? detailsMap) {
    if (detailsMap == null) {
      return null;
    }
    return detailsMap['message'] as String?;
  }

  GoodbyeMessage? _decodeGoodbyeMessageMap(Map<dynamic, dynamic>? detailsMap) {
    if (detailsMap == null) {
      return null;
    }
    final message = detailsMap['message'] as String?;
    return message == null ? null : GoodbyeMessage(message);
  }

  Details _decodeDetailsMap(Map<dynamic, dynamic> detailsMap) {
    final details = Details();
    details.setLazyFieldsLoader(() => _normalizeDynamicMap(detailsMap));
    return details;
  }

  Map<String, dynamic> _normalizeDynamicMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) => MapEntry(key.toString(), value));
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
      custom: custom.isEmpty ? null : custom,
    );
  }

  CallOptions? _decodeCallOptions(Map<String, dynamic>? optionsMap) {
    if (optionsMap == null || optionsMap.isEmpty) {
      return null;
    }
    final custom = _copyWithoutKeys(optionsMap, _callOptionKeys);
    return CallOptions(
      receiveProgress: optionsMap['receive_progress'] as bool?,
      timeout: _coerceInt(optionsMap['timeout']),
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

  void _setLazyMsgPackPayload(
    AbstractMessageWithPayload message,
    Uint8List msgPack,
    List<_ByteRange> ranges,
    int argumentsOffset,
  ) {
    final hasArguments = ranges.length > argumentsOffset;
    final hasArgumentsKeywords = ranges.length > argumentsOffset + 1;
    if (!hasArguments && !hasArgumentsKeywords) {
      return;
    }
    if (hasArguments && !hasArgumentsKeywords) {
      final argumentsBytes = _sliceRange(msgPack, ranges[argumentsOffset]);
      final decodedArguments = _decodeMsgPackFragment(argumentsBytes);
      if (decodedArguments is Uint8List) {
        message.transparentBinaryPayload = decodedArguments;
        return;
      }
    }
    message.setLazyPayload(
      argumentsBytes: hasArguments
          ? _sliceRange(msgPack, ranges[argumentsOffset])
          : null,
      argumentsDecoder: hasArguments ? _decodeMsgPackArguments : null,
      argumentsKeywordsBytes: hasArgumentsKeywords
          ? _sliceRange(msgPack, ranges[argumentsOffset + 1])
          : null,
      argumentsKeywordsDecoder: hasArgumentsKeywords
          ? _decodeMsgPackKeywordArguments
          : null,
      encoding: LazyPayloadEncoding.messagePack,
    );
  }

  List<dynamic> _decodeMsgPackArguments(Uint8List bytes) {
    final decoded = _decodeMsgPackFragment(bytes);
    if (decoded is List) {
      return List<dynamic>.from(decoded);
    }
    throw ArgumentError('Expected MessagePack arguments list but got $decoded');
  }

  Map<String, dynamic> _decodeMsgPackKeywordArguments(Uint8List bytes) {
    final decoded = _decodeMsgPackFragment(bytes);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw ArgumentError(
      'Expected MessagePack keyword arguments map but got $decoded',
    );
  }

  Object? _decodeMsgPackFragment(Uint8List bytes) {
    return msgpack_dart.deserialize(bytes);
  }

  Map<dynamic, dynamic> _decodeMsgPackMap(Uint8List bytes) {
    final decoded = _decodeMsgPackFragment(bytes);
    if (decoded is Map<dynamic, dynamic>) {
      return decoded;
    }
    throw ArgumentError('Expected MessagePack map but got $decoded');
  }

  int _decodeMsgPackInt(Uint8List bytes) {
    final decoded = _decodeMsgPackFragment(bytes);
    if (decoded is num) {
      return decoded.toInt();
    }
    throw ArgumentError('Expected MessagePack integer but got $decoded');
  }

  String _decodeMsgPackString(Uint8List bytes) {
    final decoded = _decodeMsgPackFragment(bytes);
    if (decoded is String) {
      return decoded;
    }
    throw ArgumentError('Expected MessagePack string but got $decoded');
  }

  /// Converts a WAMP message object into a uint8 msgpack message
  @override
  Uint8List serialize(AbstractMessage message) {
    if (message is Hello) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeHello),
        msgpack_dart.serialize(message.realm),
        _serializeDetails(message.details)!,
      ]);
    }
    if (message is Challenge) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeChallenge),
        msgpack_dart.serialize(message.authMethod),
        msgpack_dart.serialize(_challengeExtraToMap(message.extra)),
      ]);
    }
    if (message is Authenticate) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeAuthenticate),
        msgpack_dart.serialize(message.signature ?? ''),
        msgpack_dart.serialize(message.extra ?? const <String, Object?>{}),
      ]);
    }
    if (message is Welcome) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeWelcome),
        msgpack_dart.serialize(message.sessionId),
        _serializeDetails(message.details)!,
      ]);
    }
    if (message is Register) {
      return _buildMessage(4, [
        msgpack_dart.serialize(MessageTypes.codeRegister),
        msgpack_dart.serialize(message.requestId),
        _serializeRegisterOptions(message.options),
        msgpack_dart.serialize(message.procedure),
      ]);
    }
    if (message is Unregister) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeUnregister),
        msgpack_dart.serialize(message.requestId),
        msgpack_dart.serialize(message.registrationId),
      ]);
    }
    if (message is Call) {
      return _buildPayloadMessage(4, [
        msgpack_dart.serialize(MessageTypes.codeCall),
        msgpack_dart.serialize(message.requestId),
        _serializeCallOptions(message.options),
        msgpack_dart.serialize(message.procedure),
      ], _serializePayload(message));
    }
    if (message is Yield) {
      return _buildPayloadMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeYield),
        msgpack_dart.serialize(message.invocationRequestId),
        _serializeYieldOptions(message.options),
      ], _serializePayload(message));
    }
    if (message is cancel_msg.Cancel) {
      final options = <String, Object?>{};
      if (message.options?.mode != null) {
        options['mode'] = message.options!.mode;
      }
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeCancel),
        msgpack_dart.serialize(message.requestId),
        msgpack_dart.serialize(options),
      ]);
    }
    if (message is interrupt_msg.Interrupt) {
      final options = <String, Object?>{};
      if (message.options?.mode != null) {
        options['mode'] = message.options!.mode;
      }
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeInterrupt),
        msgpack_dart.serialize(message.requestId),
        msgpack_dart.serialize(options),
      ]);
    }
    if (message is Invocation) {
      return _buildPayloadMessage(4, [
        msgpack_dart.serialize(MessageTypes.codeInvocation),
        msgpack_dart.serialize(message.requestId),
        msgpack_dart.serialize(message.registrationId),
        _serializeInvocationDetails(message.details),
      ], _serializePayload(message));
    }
    if (message is Publish) {
      return _buildPayloadMessage(4, [
        msgpack_dart.serialize(MessageTypes.codePublish),
        msgpack_dart.serialize(message.requestId),
        _serializePublish(message.options),
        msgpack_dart.serialize(message.topic),
      ], _serializePayload(message));
    }
    if (message is Published) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codePublished),
        msgpack_dart.serialize(message.publishRequestId),
        msgpack_dart.serialize(message.publicationId),
      ]);
    }
    if (message is Event) {
      final detailsBytes = _serializeEventDetails(message.details);
      return _buildPayloadMessage(4, [
        msgpack_dart.serialize(MessageTypes.codeEvent),
        msgpack_dart.serialize(message.subscriptionId),
        msgpack_dart.serialize(message.publicationId),
        detailsBytes,
      ], _serializePayload(message));
    }
    if (message is Subscribe) {
      return _buildMessage(4, [
        msgpack_dart.serialize(MessageTypes.codeSubscribe),
        msgpack_dart.serialize(message.requestId),
        _serializeSubscribeOptions(message.options),
        msgpack_dart.serialize(message.topic),
      ]);
    }
    if (message is Subscribed) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeSubscribed),
        msgpack_dart.serialize(message.subscribeRequestId),
        msgpack_dart.serialize(message.subscriptionId),
      ]);
    }
    if (message is Unsubscribe) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeUnsubscribe),
        msgpack_dart.serialize(message.requestId),
        msgpack_dart.serialize(message.subscriptionId),
      ]);
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
          return _buildMessage(3, [
            msgpack_dart.serialize(MessageTypes.codeUnsubscribed),
            msgpack_dart.serialize(message.unsubscribeRequestId),
            msgpack_dart.serialize(map),
          ]);
        }
      }
      return _buildMessage(2, [
        msgpack_dart.serialize(MessageTypes.codeUnsubscribed),
        msgpack_dart.serialize(message.unsubscribeRequestId),
      ]);
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
      return _buildPayloadMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeResult),
        msgpack_dart.serialize(message.callRequestId),
        msgpack_dart.serialize(details),
      ], _serializePayload(message));
    }
    if (message is Error) {
      return _buildPayloadMessage(5, [
        msgpack_dart.serialize(MessageTypes.codeError),
        msgpack_dart.serialize(message.requestTypeId),
        msgpack_dart.serialize(message.requestId),
        msgpack_dart.serialize(message.details),
        msgpack_dart.serialize(message.error),
      ], _serializePayload(message));
    }
    if (message is Abort) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeAbort),
        msgpack_dart.serialize(
          message.message != null ? {'message': message.message!.message} : {},
        ),
        msgpack_dart.serialize(message.reason),
      ]);
    }
    if (message is Goodbye) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeGoodbye),
        msgpack_dart.serialize(
          message.message?.message != null
              ? {'message': message.message!.message}
              : {},
        ),
        msgpack_dart.serialize(message.reason),
      ]);
    }
    if (message is Registered) {
      return _buildMessage(3, [
        msgpack_dart.serialize(MessageTypes.codeRegistered),
        msgpack_dart.serialize(message.registerRequestId),
        msgpack_dart.serialize(message.registrationId),
      ]);
    }
    if (message is Unregistered) {
      return _buildMessage(2, [
        msgpack_dart.serialize(MessageTypes.codeUnregistered),
        msgpack_dart.serialize(message.unregisterRequestId),
      ]);
    }

    _logger.shout('Could not serialize the message of type: $message');
    throw UnsupportedError(
      'MsgPack serializer does not support ${message.runtimeType}',
    );
  }

  Uint8List _buildMessage(int length, List<Uint8List> parts) {
    final builder = BytesBuilder(copy: false)..add([_fixArrayHeader(length)]);
    for (final part in parts) {
      builder.add(part);
    }
    return builder.takeBytes();
  }

  Uint8List _buildPayloadMessage(
    int fixedLength,
    List<Uint8List> fixedParts,
    SerializedPayload<int, Uint8List> payload,
  ) {
    final builder = BytesBuilder(copy: false)
      ..add([_fixArrayHeader(fixedLength + payload.payloadType)]);
    for (final part in fixedParts) {
      builder.add(part);
    }
    if (payload.payload.isNotEmpty) {
      builder.add(payload.payload);
    }
    return builder.takeBytes();
  }

  int _fixArrayHeader(int length) {
    assert(length >= 0 && length <= 15);
    return 0x90 | length;
  }

  Uint8List? _serializeDetails(Details details) {
    if (details.roles != null) {
      var roles = {};
      if (details.roles!.caller != null) {
        final callerFeatures = details.roles!.caller!.features;
        if (callerFeatures != null) {
          var callerFeaturesMap = {};
          callerFeaturesMap.addEntries([
            MapEntry('call_canceling', callerFeatures.callCanceling),
            MapEntry('call_timeout', callerFeatures.callTimeout),
            MapEntry(
              'caller_identification',
              callerFeatures.callerIdentification,
            ),
            MapEntry(
              'payload_passthru_mode',
              callerFeatures.payloadPassThruMode,
            ),
            MapEntry(
              'progressive_call_results',
              callerFeatures.progressiveCallResults,
            ),
          ]);
          roles.addEntries([
            MapEntry('caller', {'features': callerFeaturesMap}),
          ]);
        } else {
          roles.addEntries([const MapEntry('caller', {})]);
        }
      }
      if (details.roles!.callee != null) {
        final calleeFeatures = details.roles!.callee!.features;
        if (calleeFeatures != null) {
          var calleeFeaturesMap = {};
          calleeFeaturesMap.addEntries([
            MapEntry(
              'caller_identification',
              calleeFeatures.callerIdentification,
            ),
            MapEntry('call_trustlevels', calleeFeatures.callTrustlevels),
            MapEntry(
              'pattern_based_registration',
              calleeFeatures.patternBasedRegistration,
            ),
            MapEntry('shared_registration', calleeFeatures.sharedRegistration),
            MapEntry('call_canceling', calleeFeatures.callCanceling),
            MapEntry('call_timeout', calleeFeatures.callTimeout),
            MapEntry(
              'caller_identification',
              calleeFeatures.callerIdentification,
            ),
            MapEntry(
              'payload_passthru_mode',
              calleeFeatures.payloadPassThruMode,
            ),
            MapEntry(
              'progressive_call_results',
              calleeFeatures.progressiveCallResults,
            ),
          ]);
          roles.addEntries([
            MapEntry('callee', {'features': calleeFeaturesMap}),
          ]);
        } else {
          roles.addEntries([const MapEntry('callee', {})]);
        }
      }
      if (details.roles!.subscriber != null) {
        final subscriberFeatures = details.roles!.subscriber!.features;
        if (subscriberFeatures != null) {
          var subscriberFeaturesMap = {};
          subscriberFeaturesMap.addEntries([
            MapEntry('call_canceling', subscriberFeatures.callCanceling),
            MapEntry('call_timeout', subscriberFeatures.callTimeout),
            MapEntry(
              'payload_passthru_mode',
              subscriberFeatures.payloadPassThruMode,
            ),
            MapEntry(
              'progressive_call_results',
              subscriberFeatures.progressiveCallResults,
            ),
            MapEntry(
              'subscription_revocation',
              subscriberFeatures.subscriptionRevocation,
            ),
          ]);
          roles.addEntries([
            MapEntry('subscriber', {'features': subscriberFeaturesMap}),
          ]);
        } else {
          roles.addEntries([const MapEntry('subscriber', {})]);
        }
      }
      if (details.roles!.publisher != null) {
        final publisherFeatures = details.roles!.publisher!.features;
        if (publisherFeatures != null) {
          var publisherFeaturesMap = {};
          publisherFeaturesMap.addEntries([
            MapEntry(
              'publisher_identification',
              publisherFeatures.publisherIdentification,
            ),
            MapEntry(
              'subscriber_blackwhite_listing',
              publisherFeatures.subscriberBlackWhiteListing,
            ),
            MapEntry(
              'publisher_exclusion',
              publisherFeatures.publisherExclusion,
            ),
            MapEntry(
              'payload_passthru_mode',
              publisherFeatures.payloadPassThruMode,
            ),
          ]);
          roles.addEntries([
            MapEntry('publisher', {'features': publisherFeaturesMap}),
          ]);
        } else {
          roles.addEntries([const MapEntry('publisher', {})]);
        }
      }
      if (details.roles!.broker != null) {
        final brokerFeatures = details.roles!.broker!.features;
        final brokerMap = <String, dynamic>{};
        if (brokerFeatures != null) {
          brokerMap['features'] = {
            'publisher_identification': brokerFeatures.publisherIdentification,
            'publication_trustlevels': brokerFeatures.publicationTrustLevels,
            'pattern_based_subscription':
                brokerFeatures.patternBasedSubscription,
            'subscription_meta_api': brokerFeatures.subscriptionMetaApi,
            'subscriber_blackwhite_listing':
                brokerFeatures.subscriberBlackWhiteListing,
            'session_meta_api': brokerFeatures.sessionMetaApi,
            'publisher_exclusion': brokerFeatures.publisherExclusion,
            'event_history': brokerFeatures.eventHistory,
            'payload_passthru_mode': brokerFeatures.payloadPassThruMode,
          };
        }
        if (details.roles!.broker!.reflection != null) {
          brokerMap['reflection'] = details.roles!.broker!.reflection;
        }
        roles.addEntries([MapEntry('broker', brokerMap)]);
      }
      if (details.roles!.dealer != null) {
        final dealerFeatures = details.roles!.dealer!.features;
        final dealerMap = <String, dynamic>{};
        if (dealerFeatures != null) {
          dealerMap['features'] = {
            'caller_identification': dealerFeatures.callerIdentification,
            'call_trustlevels': dealerFeatures.callTrustLevels,
            'pattern_based_registration':
                dealerFeatures.patternBasedRegistration,
            'registration_meta_api': dealerFeatures.registrationMetaApi,
            'shared_registration': dealerFeatures.sharedRegistration,
            'session_meta_api': dealerFeatures.sessionMetaApi,
            'call_timeout': dealerFeatures.callTimeout,
            'call_canceling': dealerFeatures.callCanceling,
            'progressive_call_results': dealerFeatures.progressiveCallResults,
            'payload_passthru_mode': dealerFeatures.payloadPassThruMode,
          };
        }
        if (details.roles!.dealer!.reflection != null) {
          dealerMap['reflection'] = details.roles!.dealer!.reflection;
        }
        roles.addEntries([MapEntry('dealer', dealerMap)]);
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

  Uint8List _serializeInvocationDetails(InvocationDetails details) {
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
    return msgpack_dart.serialize(map);
  }

  /// returns bytes to add to header and serialized payload bytes
  SerializedPayload<int, Uint8List> _serializePayload(
    AbstractMessageWithPayload message,
  ) {
    if (message.transparentBinaryPayload != null) {
      return SerializedPayload(
        1,
        msgpack_dart.serialize(message.transparentBinaryPayload),
      );
    }
    final encodedArgs =
        message.lazyPayloadEncoding == LazyPayloadEncoding.messagePack
        ? message.debugEncodedArgumentsBytes
        : null;
    final encodedKwargs =
        message.lazyPayloadEncoding == LazyPayloadEncoding.messagePack
        ? message.debugEncodedArgumentsKeywordsBytes
        : null;
    if (encodedArgs != null || encodedKwargs != null) {
      final argsBytes =
          encodedArgs ?? msgpack_dart.serialize(message.arguments ?? []);
      final kwargsBytes =
          encodedKwargs ??
          (message.argumentsKeywords == null
              ? null
              : msgpack_dart.serialize(message.argumentsKeywords));
      if (kwargsBytes != null) {
        return SerializedPayload(2, _concatBytes(argsBytes, kwargsBytes));
      }
      return SerializedPayload(1, argsBytes);
    }
    if (message.argumentsKeywords != null) {
      return SerializedPayload(
        2,
        _concatBytes(
          msgpack_dart.serialize(message.arguments ?? []),
          msgpack_dart.serialize(message.argumentsKeywords),
        ),
      );
    } else if (message.arguments != null) {
      return SerializedPayload(1, msgpack_dart.serialize(message.arguments));
    }
    return SerializedPayload(0, Uint8List(0));
  }

  Uint8List _concatBytes(Uint8List left, Uint8List right) {
    final combined = Uint8List(left.length + right.length);
    combined.setRange(0, left.length, left);
    combined.setRange(left.length, combined.length, right);
    return combined;
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
      custom![keyString] = value;
    });
    return custom ?? <String, dynamic>{};
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
    final argsBytes = argumentsBytes ?? msgpack_dart.serialize(arguments);
    final kwargsBytes =
        argumentsKeywordsBytes ?? msgpack_dart.serialize(argumentsKeywords);
    final builder = BytesBuilder(copy: false)
      ..add([0x82])
      ..add(_pptArgsKeyBytes)
      ..add(argsBytes.isEmpty ? _nilBytes : argsBytes)
      ..add(_pptKwargsKeyBytes)
      ..add(kwargsBytes.isEmpty ? _nilBytes : kwargsBytes);
    return builder.takeBytes();
  }

  Map<String, Object?> _challengeExtraToMap(Extra extra) {
    return extra.toMap();
  }
}

/// this is a little helper class for payload
/// serialization and type "safety"
class SerializedPayload<TTag, TPayload> {
  final TTag payloadType;
  final TPayload payload;

  SerializedPayload(this.payloadType, this.payload);
}

class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;
}

class _MsgPackArrayHeader {
  const _MsgPackArrayHeader(this.length, this.nextOffset);

  final int length;
  final int nextOffset;
}

Uint8List _sliceRange(Uint8List bytes, _ByteRange range) {
  return Uint8List.sublistView(bytes, range.start, range.end);
}

List<_ByteRange>? _parseMsgPackTopLevelRanges(Uint8List bytes) {
  final header = _readMsgPackArrayHeader(bytes, 0);
  if (header == null) {
    return null;
  }
  var offset = header.nextOffset;
  final ranges = <_ByteRange>[];
  for (var index = 0; index < header.length; index++) {
    final start = offset;
    final next = _skipMsgPackValue(bytes, offset);
    if (next == null) {
      return null;
    }
    ranges.add(_ByteRange(start, next));
    offset = next;
  }
  return ranges;
}

_MsgPackArrayHeader? _readMsgPackArrayHeader(Uint8List bytes, int offset) {
  if (offset >= bytes.length) {
    return null;
  }
  final lead = bytes[offset];
  if ((lead & 0xf0) == 0x90) {
    return _MsgPackArrayHeader(lead & 0x0f, offset + 1);
  }
  if (lead == 0xdc) {
    if (offset + 3 > bytes.length) {
      return null;
    }
    return _MsgPackArrayHeader(
      ByteData.sublistView(bytes, offset + 1, offset + 3).getUint16(0),
      offset + 3,
    );
  }
  if (lead == 0xdd) {
    if (offset + 5 > bytes.length) {
      return null;
    }
    return _MsgPackArrayHeader(
      ByteData.sublistView(bytes, offset + 1, offset + 5).getUint32(0),
      offset + 5,
    );
  }
  return null;
}

int? _skipMsgPackValue(Uint8List bytes, int offset) {
  if (offset >= bytes.length) {
    return null;
  }
  final lead = bytes[offset];
  if (lead <= 0x7f || lead >= 0xe0) {
    return offset + 1;
  }
  if ((lead & 0xe0) == 0xa0) {
    final length = lead & 0x1f;
    return _advanceMsgPackOffset(bytes, offset + 1, length);
  }
  if ((lead & 0xf0) == 0x90) {
    return _skipMsgPackArray(bytes, offset + 1, lead & 0x0f);
  }
  if ((lead & 0xf0) == 0x80) {
    return _skipMsgPackMap(bytes, offset + 1, lead & 0x0f);
  }
  switch (lead) {
    case 0xc0:
    case 0xc2:
    case 0xc3:
      return offset + 1;
    case 0xcc:
    case 0xd0:
      return _advanceMsgPackOffset(bytes, offset + 1, 1);
    case 0xcd:
    case 0xd1:
      return _advanceMsgPackOffset(bytes, offset + 1, 2);
    case 0xce:
    case 0xd2:
    case 0xca:
      return _advanceMsgPackOffset(bytes, offset + 1, 4);
    case 0xcf:
    case 0xd3:
    case 0xcb:
      return _advanceMsgPackOffset(bytes, offset + 1, 8);
    case 0xd9:
      return _skipMsgPackLengthPrefixed(bytes, offset + 1, 1);
    case 0xda:
      return _skipMsgPackLengthPrefixed(bytes, offset + 1, 2);
    case 0xdb:
      return _skipMsgPackLengthPrefixed(bytes, offset + 1, 4);
    case 0xc4:
      return _skipMsgPackLengthPrefixed(bytes, offset + 1, 1);
    case 0xc5:
      return _skipMsgPackLengthPrefixed(bytes, offset + 1, 2);
    case 0xc6:
      return _skipMsgPackLengthPrefixed(bytes, offset + 1, 4);
    case 0xdc:
      final length = _readMsgPackLength(bytes, offset + 1, 2);
      return length == null
          ? null
          : _skipMsgPackArray(bytes, offset + 3, length);
    case 0xdd:
      final length = _readMsgPackLength(bytes, offset + 1, 4);
      return length == null
          ? null
          : _skipMsgPackArray(bytes, offset + 5, length);
    case 0xde:
      final length = _readMsgPackLength(bytes, offset + 1, 2);
      return length == null ? null : _skipMsgPackMap(bytes, offset + 3, length);
    case 0xdf:
      final length = _readMsgPackLength(bytes, offset + 1, 4);
      return length == null ? null : _skipMsgPackMap(bytes, offset + 5, length);
    case 0xd4:
      return _advanceMsgPackOffset(bytes, offset + 2, 1);
    case 0xd5:
      return _advanceMsgPackOffset(bytes, offset + 2, 2);
    case 0xd6:
      return _advanceMsgPackOffset(bytes, offset + 2, 4);
    case 0xd7:
      return _advanceMsgPackOffset(bytes, offset + 2, 8);
    case 0xd8:
      return _advanceMsgPackOffset(bytes, offset + 2, 16);
    case 0xc7:
      return _skipMsgPackExt(bytes, offset + 1, 1);
    case 0xc8:
      return _skipMsgPackExt(bytes, offset + 1, 2);
    case 0xc9:
      return _skipMsgPackExt(bytes, offset + 1, 4);
    default:
      return null;
  }
}

int? _skipMsgPackArray(Uint8List bytes, int offset, int length) {
  var current = offset;
  for (var index = 0; index < length; index++) {
    final next = _skipMsgPackValue(bytes, current);
    if (next == null) {
      return null;
    }
    current = next;
  }
  return current;
}

int? _skipMsgPackMap(Uint8List bytes, int offset, int length) {
  var current = offset;
  for (var index = 0; index < length; index++) {
    final nextKey = _skipMsgPackValue(bytes, current);
    if (nextKey == null) {
      return null;
    }
    final nextValue = _skipMsgPackValue(bytes, nextKey);
    if (nextValue == null) {
      return null;
    }
    current = nextValue;
  }
  return current;
}

int? _skipMsgPackLengthPrefixed(Uint8List bytes, int offset, int lengthBytes) {
  final length = _readMsgPackLength(bytes, offset, lengthBytes);
  if (length == null) {
    return null;
  }
  return _advanceMsgPackOffset(bytes, offset + lengthBytes, length);
}

int? _skipMsgPackExt(Uint8List bytes, int offset, int lengthBytes) {
  final length = _readMsgPackLength(bytes, offset, lengthBytes);
  if (length == null) {
    return null;
  }
  return _advanceMsgPackOffset(bytes, offset + lengthBytes + 1, length);
}

int? _advanceMsgPackOffset(Uint8List bytes, int offset, int length) {
  final next = offset + length;
  if (next > bytes.length) {
    return null;
  }
  return next;
}

int? _readMsgPackLength(Uint8List bytes, int offset, int lengthBytes) {
  if (offset + lengthBytes > bytes.length) {
    return null;
  }
  final data = ByteData.sublistView(bytes, offset, offset + lengthBytes);
  return switch (lengthBytes) {
    1 => data.getUint8(0),
    2 => data.getUint16(0),
    4 => data.getUint32(0),
    _ => null,
  };
}

int? _coerceInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return null;
}
