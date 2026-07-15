import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor_pkg;
import 'package:collection/collection.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;
import 'package:test/test.dart';

final _deepEquals = const DeepCollectionEquality();

final _jsonSerializer = json_serializer.Serializer();
final _msgpackSerializer = msgpack_serializer.Serializer();
final _cborSerializer = cbor_serializer.Serializer();

void main() {
  final vectorsRoot = _resolveVectorsRoot();
  final vectorCases = _loadVectorCases(vectorsRoot);

  group('pinned WAMP single-message conformance', () {
    test('vendors the upstream metadata snapshot', () {
      expect(
        File('${vectorsRoot.path}/README.md').existsSync(),
        isTrue,
        reason: 'Missing vendored upstream metadata for the pinned suite',
      );
      expect(
        File('${vectorsRoot.path}/SCHEMA.json').existsSync(),
        isTrue,
        reason: 'Missing vendored upstream schema for the pinned suite',
      );
    });

    for (final vectorCase in vectorCases) {
      for (final serializerId in const ['json', 'msgpack', 'cbor']) {
        if (!vectorCase.serializers.containsKey(serializerId)) {
          continue;
        }
        test('${vectorCase.label} [$serializerId]', () {
          final variants = _serializerVariants(
            vectorCase.serializers[serializerId],
          );
          final canonicalFrames = <Object?>[];
          AbstractMessage? parsedMessage;

          for (final variant in variants) {
            final wireBytes = _wireBytes(serializerId, variant);
            final decodedFrame = _decodeWireFrame(serializerId, wireBytes);
            canonicalFrames.add(decodedFrame);

            final message = _deserialize(serializerId, wireBytes);
            expect(
              message,
              isNotNull,
              reason:
                  'Failed to deserialize ${vectorCase.label} for $serializerId',
            );
            _expectSubset(
              vectorCase.expectedAttributes,
              _normalizeMessage(message!),
              path: 'expected_attributes',
            );
            parsedMessage ??= message;
          }

          final reserialized = _serialize(serializerId, parsedMessage!);
          final reserializedFrame = _decodeWireFrame(
            serializerId,
            reserialized,
          );

          expect(
            canonicalFrames.any(
              (frame) => _deepEquals.equals(frame, reserializedFrame),
            ),
            isTrue,
            reason:
                'Reserialized ${vectorCase.label} for $serializerId did not match any documented canonical frame',
          );

          final roundTripped = _deserialize(serializerId, reserialized);
          expect(
            roundTripped,
            isNotNull,
            reason:
                'Failed to deserialize round-tripped ${vectorCase.label} for $serializerId',
          );
          _expectSubset(
            vectorCase.expectedAttributes,
            _normalizeMessage(roundTripped!),
            path: 'round_trip',
          );
        });
      }
    }
  });
}

Directory _resolveVectorsRoot() {
  final candidates = [
    Directory('packages/connectanum_core/testdata/wamp_conformance'),
    Directory('testdata/wamp_conformance'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate;
    }
  }
  throw StateError('Could not locate vendored WAMP conformance vectors');
}

List<_VectorCase> _loadVectorCases(Directory root) {
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where((file) => file.path.contains('/singlemessage/'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  return files.expand(_loadVectorCasesFromFile).toList(growable: false);
}

Iterable<_VectorCase> _loadVectorCasesFromFile(File file) sync* {
  final vector = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final relativePath = file.path.replaceAll('\\', '/');

  final topLevelExpected = _normalizeWireValue(vector['expected_attributes']);
  final topLevelSerializers = vector['serializers'] as Map<String, dynamic>?;
  final samples = vector['samples'];

  if (samples is List) {
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index] as Map<String, dynamic>;
      final sampleExpected = _normalizeWireValue(
        sample['expected_attributes'] ?? topLevelExpected,
      );
      final sampleSerializers = sample['serializers'] ?? topLevelSerializers;
      if (sampleExpected is! Map<String, dynamic> ||
          sampleSerializers is! Map<String, dynamic>) {
        continue;
      }
      yield _VectorCase(
        label:
            '$relativePath :: ${sample['description'] ?? vector['description'] ?? 'sample_${index + 1}'}',
        expectedAttributes: sampleExpected,
        serializers: sampleSerializers,
      );
    }
    return;
  }

  if (topLevelExpected == null || topLevelSerializers == null) {
    throw StateError('Malformed vector file: ${file.path}');
  }

  yield _VectorCase(
    label: '$relativePath :: ${vector['description']}',
    expectedAttributes: topLevelExpected as Map<String, dynamic>,
    serializers: topLevelSerializers,
  );
}

List<Map<String, dynamic>> _serializerVariants(Object? serializerSpec) {
  if (serializerSpec is List) {
    return serializerSpec.cast<Map<String, dynamic>>();
  }
  if (serializerSpec is Map<String, dynamic>) {
    return [serializerSpec];
  }
  throw StateError('Unsupported serializer variant format: $serializerSpec');
}

Uint8List _wireBytes(String serializerId, Map<String, dynamic> variant) {
  final bytes = variant['bytes'];
  if (serializerId == 'json' && bytes is String) {
    return Uint8List.fromList(utf8.encode(bytes));
  }

  final bytesHex = variant['bytes_hex'];
  if (bytesHex is String) {
    return _hexToBytes(bytesHex);
  }

  final bytesBase64 = variant['bytes_base64'];
  if (bytesBase64 is String) {
    return Uint8List.fromList(base64Decode(bytesBase64));
  }

  if (bytes is String) {
    return Uint8List.fromList(utf8.encode(bytes));
  }

  throw StateError('Missing wire bytes in serializer variant: $variant');
}

Uint8List _hexToBytes(String hex) {
  final normalized = hex.trim();
  if (normalized.length.isOdd) {
    throw FormatException('Invalid hex length: $hex');
  }
  final result = Uint8List(normalized.length ~/ 2);
  for (var index = 0; index < normalized.length; index += 2) {
    result[index ~/ 2] = int.parse(
      normalized.substring(index, index + 2),
      radix: 16,
    );
  }
  return result;
}

AbstractMessage? _deserialize(String serializerId, Uint8List bytes) {
  return switch (serializerId) {
    'json' => _jsonSerializer.deserialize(bytes),
    'msgpack' => _msgpackSerializer.deserialize(bytes),
    'cbor' => _cborSerializer.deserialize(bytes),
    _ => throw StateError('Unsupported serializer: $serializerId'),
  };
}

Uint8List _serialize(String serializerId, AbstractMessage message) {
  return switch (serializerId) {
    'json' => Uint8List.fromList(
      utf8.encode(_jsonSerializer.serialize(message)),
    ),
    'msgpack' => _msgpackSerializer.serialize(message),
    'cbor' => _cborSerializer.serialize(message),
    _ => throw StateError('Unsupported serializer: $serializerId'),
  };
}

Object? _decodeWireFrame(String serializerId, Uint8List bytes) {
  final decoded = switch (serializerId) {
    'json' => jsonDecode(utf8.decode(bytes)),
    'msgpack' => msgpack_dart.deserialize(bytes),
    'cbor' => cbor_pkg.cbor.decode(bytes.toList()),
    _ => throw StateError('Unsupported serializer: $serializerId'),
  };
  return _normalizeWireValue(decoded);
}

Map<String, dynamic> _normalizeMessage(AbstractMessage message) {
  final normalized = <String, dynamic>{'message_type': message.id};

  switch (message) {
    case Hello():
      normalized['realm'] = message.realm;
      normalized['roles'] = _normalizeRoles(message.details.roles);
    case Welcome():
      normalized['session_id'] = message.sessionId;
      normalized['roles'] = _normalizeRoles(message.details.roles);
      _mergeOptional(normalized, _normalizeDetails(message.details));
    case Abort():
      normalized['details'] = _normalizeAbortDetails(message);
      normalized['reason'] = message.reason;
    case Challenge():
      normalized['method'] = message.authMethod;
      normalized['extra'] = _normalizeExtra(message.extra);
    case Authenticate():
      normalized['signature'] = message.signature ?? '';
      normalized['extra'] = _normalizeStringKeyMap(message.extra) ?? {};
    case Goodbye():
      normalized['details'] = message.message?.message == null
          ? <String, dynamic>{}
          : <String, dynamic>{'message': message.message!.message};
      normalized['reason'] = message.reason;
    case Error():
      normalized['request_type'] = message.requestTypeId;
      normalized['request_id'] = message.requestId;
      normalized['details'] = _normalizeStringKeyMap(message.details) ?? {};
      normalized['error'] = message.error;
      _mergePayload(normalized, message);
    case Publish():
      normalized['request_id'] = message.requestId;
      normalized['options'] = _normalizePublishOptions(message.options);
      normalized['topic'] = message.topic;
      _mergePayload(normalized, message);
    case Published():
      normalized['request_id'] = message.publishRequestId;
      normalized['publication_id'] = message.publicationId;
    case Subscribe():
      normalized['request_id'] = message.requestId;
      normalized['options'] = _normalizeSubscribeOptions(message.options);
      normalized['topic'] = message.topic;
    case Subscribed():
      normalized['request_id'] = message.subscribeRequestId;
      normalized['subscription_id'] = message.subscriptionId;
    case Unsubscribe():
      normalized['request_id'] = message.requestId;
      normalized['subscription_id'] = message.subscriptionId;
    case Unsubscribed():
      normalized['request_id'] = message.unsubscribeRequestId;
      if (message.details != null) {
        normalized['details'] = {
          if (message.details!.subscription != null)
            'subscription': message.details!.subscription,
          if (message.details!.reason != null)
            'reason': message.details!.reason,
        };
      }
    case Event():
      normalized['subscription'] = message.subscriptionId;
      normalized['publication'] = message.publicationId;
      normalized['details'] = _normalizeEventDetails(message.details);
      _mergePayload(normalized, message);
    case Call():
      normalized['request_id'] = message.requestId;
      normalized['options'] = _normalizeCallOptions(message.options);
      normalized['procedure'] = message.procedure;
      _mergePayload(normalized, message);
    case Cancel():
      normalized['request_id'] = message.requestId;
      normalized['options'] = _normalizeCancelOptions(message.options);
    case Result():
      normalized['request_id'] = message.callRequestId;
      normalized['details'] = _normalizeResultDetails(message.details);
      _mergePayload(normalized, message);
    case Register():
      normalized['request_id'] = message.requestId;
      normalized['options'] = _normalizeRegisterOptions(message.options);
      normalized['procedure'] = message.procedure;
    case Registered():
      normalized['request_id'] = message.registerRequestId;
      normalized['registration_id'] = message.registrationId;
    case Unregister():
      normalized['request_id'] = message.requestId;
      normalized['registration_id'] = message.registrationId;
    case Unregistered():
      normalized['request_id'] = message.unregisterRequestId;
    case Invocation():
      normalized['request_id'] = message.requestId;
      normalized['registration_id'] = message.registrationId;
      normalized['details'] = _normalizeInvocationDetails(message.details);
      _mergePayload(normalized, message);
    case Interrupt():
      normalized['request_id'] = message.requestId;
      normalized['options'] = _normalizeCancelOptions(message.options);
    case Yield():
      normalized['request_id'] = message.invocationRequestId;
      normalized['options'] = _normalizeYieldOptions(message.options);
      _mergePayload(normalized, message);
    default:
      throw StateError(
        'Unsupported message type in conformance normalizer: ${message.runtimeType}',
      );
  }

  return normalized;
}

void _mergePayload(
  Map<String, dynamic> target,
  AbstractMessageWithPayload message,
) {
  target['args'] = message.arguments;
  target['kwargs'] = _normalizeKwargs(message.argumentsKeywords);
  if (message.transparentBinaryPayload != null) {
    target['payload'] = _bytesToHex(message.transparentBinaryPayload!);
  }
}

Map<String, dynamic> _normalizeAbortDetails(Abort message) {
  final details =
      _normalizeStringKeyMap(message.details) ?? <String, dynamic>{};
  if (message.message?.message != null) {
    details['message'] = message.message!.message;
  }
  return details;
}

Map<String, dynamic> _normalizeDetails(Details details) {
  final result = <String, dynamic>{};
  if (details.realm != null && details.realm!.isNotEmpty) {
    result['realm'] = details.realm;
  }
  if (details.authid != null && details.authid!.isNotEmpty) {
    result['authid'] = details.authid;
  }
  if (details.authrole != null && details.authrole!.isNotEmpty) {
    result['authrole'] = details.authrole;
  }
  if (details.authmethod != null && details.authmethod!.isNotEmpty) {
    result['authmethod'] = details.authmethod;
  }
  if (details.authprovider != null && details.authprovider!.isNotEmpty) {
    result['authprovider'] = details.authprovider;
  }
  if (details.authmethods != null && details.authmethods!.isNotEmpty) {
    result['authmethods'] = List<String>.from(details.authmethods!);
  }
  if (details.authextra != null && details.authextra!.isNotEmpty) {
    result['authextra'] = _normalizeStringKeyMap(details.authextra);
  }
  if (details.custom.isNotEmpty) {
    result.addAll(_normalizeStringKeyMap(details.custom)!);
  }
  return result;
}

Map<String, dynamic> _normalizeExtra(Extra extra) {
  final result = <String, dynamic>{};
  _putIfNotNull(result, 'challenge', extra.challenge);
  _putIfNotNull(result, 'salt', extra.salt);
  _putIfNotNull(result, 'channel_binding', extra.channelBinding);
  _putIfNotNull(result, 'keylen', extra.keyLen);
  _putIfNotNull(result, 'iterations', extra.iterations);
  _putIfNotNull(result, 'memory', extra.memory);
  _putIfNotNull(result, 'kdf', extra.kdf);
  _putIfNotNull(result, 'nonce', extra.nonce);
  return result;
}

Map<String, dynamic>? _normalizeRoles(Roles? roles) {
  if (roles == null) {
    return null;
  }
  final result = <String, dynamic>{};
  if (roles.caller != null) {
    result['caller'] = _normalizeRole(roles.caller!.features);
  }
  if (roles.callee != null) {
    result['callee'] = _normalizeRole(roles.callee!.features);
  }
  if (roles.publisher != null) {
    result['publisher'] = _normalizeRole(roles.publisher!.features);
  }
  if (roles.subscriber != null) {
    result['subscriber'] = _normalizeRole(roles.subscriber!.features);
  }
  if (roles.broker != null) {
    result['broker'] = {
      if (roles.broker!.features != null)
        'features': _normalizeWireValue({
          'publisher_identification':
              roles.broker!.features!.publisherIdentification,
          'publication_trustlevels':
              roles.broker!.features!.publicationTrustLevels,
          'pattern_based_subscription':
              roles.broker!.features!.patternBasedSubscription,
          'subscription_meta_api': roles.broker!.features!.subscriptionMetaApi,
          'subscriber_blackwhite_listing':
              roles.broker!.features!.subscriberBlackWhiteListing,
          'session_meta_api': roles.broker!.features!.sessionMetaApi,
          'publisher_exclusion': roles.broker!.features!.publisherExclusion,
          'event_history': roles.broker!.features!.eventHistory,
          'payload_passthru_mode': roles.broker!.features!.payloadPassThruMode,
        }),
      if (roles.broker!.reflection != null)
        'reflection': roles.broker!.reflection,
    };
  }
  if (roles.dealer != null) {
    result['dealer'] = {
      if (roles.dealer!.features != null)
        'features': _normalizeWireValue({
          'caller_identification': roles.dealer!.features!.callerIdentification,
          'call_trustlevels': roles.dealer!.features!.callTrustLevels,
          'pattern_based_registration':
              roles.dealer!.features!.patternBasedRegistration,
          'registration_meta_api': roles.dealer!.features!.registrationMetaApi,
          'shared_registration': roles.dealer!.features!.sharedRegistration,
          'session_meta_api': roles.dealer!.features!.sessionMetaApi,
          'call_timeout': roles.dealer!.features!.callTimeout,
          'call_canceling': roles.dealer!.features!.callCanceling,
          'progressive_call_invocations':
              roles.dealer!.features!.progressiveCallInvocations,
          'progressive_call_results':
              roles.dealer!.features!.progressiveCallResults,
          'payload_passthru_mode': roles.dealer!.features!.payloadPassThruMode,
        }),
      if (roles.dealer!.reflection != null)
        'reflection': roles.dealer!.reflection,
    };
  }
  return result;
}

Map<String, dynamic> _normalizeRole(Object? features) {
  if (features == null) {
    return <String, dynamic>{};
  }
  if (features is CallerFeatures) {
    return {
      'features': {
        'call_canceling': features.callCanceling,
        'call_timeout': features.callTimeout,
        'caller_identification': features.callerIdentification,
        'payload_passthru_mode': features.payloadPassThruMode,
        'progressive_call_invocations': features.progressiveCallInvocations,
        'progressive_call_results': features.progressiveCallResults,
      },
    };
  }
  if (features is CalleeFeatures) {
    return {
      'features': {
        'caller_identification': features.callerIdentification,
        'call_trustlevels': features.callTrustlevels,
        'pattern_based_registration': features.patternBasedRegistration,
        'shared_registration': features.sharedRegistration,
        'call_timeout': features.callTimeout,
        'call_canceling': features.callCanceling,
        'progressive_call_invocations': features.progressiveCallInvocations,
        'progressive_call_results': features.progressiveCallResults,
        'payload_passthru_mode': features.payloadPassThruMode,
      },
    };
  }
  if (features is PublisherFeatures) {
    return {
      'features': {
        'publisher_identification': features.publisherIdentification,
        'subscriber_blackwhite_listing': features.subscriberBlackWhiteListing,
        'publisher_exclusion': features.publisherExclusion,
        'payload_passthru_mode': features.payloadPassThruMode,
      },
    };
  }
  if (features is SubscriberFeatures) {
    return {
      'features': {
        'publisher_identification': features.publisherIdentification,
        'publication_trustlevels': features.publicationTrustLevels,
        'pattern_based_subscription': features.patternBasedSubscription,
        'payload_passthru_mode': features.payloadPassThruMode,
        'subscription_revocation': features.subscriptionRevocation,
      },
    };
  }
  throw StateError('Unsupported role features type: ${features.runtimeType}');
}

Map<String, dynamic> _normalizePublishOptions(PublishOptions? options) {
  if (options == null) {
    return {};
  }
  final result = <String, dynamic>{};
  _putIfNotNull(result, 'acknowledge', options.acknowledge);
  _putIfNotNull(result, 'exclude', options.exclude);
  _putIfNotNull(result, 'exclude_authid', options.excludeAuthId);
  _putIfNotNull(result, 'exclude_authrole', options.excludeAuthRole);
  _putIfNotNull(result, 'eligible', options.eligible);
  _putIfNotNull(result, 'eligible_authid', options.eligibleAuthId);
  _putIfNotNull(result, 'eligible_authrole', options.eligibleAuthRole);
  _putIfNotNull(result, 'exclude_me', options.excludeMe);
  _putIfNotNull(result, 'disclose_me', options.discloseMe);
  _putIfNotNull(result, 'retain', options.retain);
  _mergePptOptions(result, options);
  if (options.custom.isNotEmpty) {
    result.addAll(_normalizeStringKeyMap(options.custom)!);
  }
  return result;
}

Map<String, dynamic> _normalizeSubscribeOptions(SubscribeOptions? options) {
  if (options == null) {
    return {};
  }
  final result = <String, dynamic>{};
  _putIfNotNull(result, 'match', options.match);
  _putIfNotNull(result, 'meta_topic', options.metaTopic);
  _putIfNotNull(result, 'get_retained', options.getRetained);
  if (options.custom.isNotEmpty) {
    result.addAll(_normalizeStringKeyMap(options.custom)!);
  }
  return result;
}

Map<String, dynamic> _normalizeRegisterOptions(RegisterOptions? options) {
  if (options == null) {
    return {};
  }
  final result = <String, dynamic>{};
  _putIfNotNull(result, 'disclose_caller', options.discloseCaller);
  _putIfNotNull(result, 'match', options.match);
  _putIfNotNull(result, 'invoke', options.invoke);
  if (options.custom.isNotEmpty) {
    result.addAll(_normalizeStringKeyMap(options.custom)!);
  }
  return result;
}

Map<String, dynamic> _normalizeCallOptions(CallOptions? options) {
  if (options == null) {
    return {};
  }
  final result = <String, dynamic>{};
  _putIfNotNull(result, 'receive_progress', options.receiveProgress);
  _putIfNotNull(result, 'timeout', options.timeout);
  _putIfNotNull(result, 'disclose_me', options.discloseMe);
  _mergePptOptions(result, options);
  if (options.custom.isNotEmpty) {
    result.addAll(_normalizeStringKeyMap(options.custom)!);
  }
  return result;
}

Map<String, dynamic> _normalizeCancelOptions(CancelOptions? options) {
  if (options == null) {
    return {};
  }
  final result = <String, dynamic>{};
  _putIfNotNull(result, 'mode', options.mode);
  return result;
}

Map<String, dynamic> _normalizeYieldOptions(YieldOptions? options) {
  if (options == null) {
    return {};
  }
  final result = <String, dynamic>{};
  if (options.progress) {
    result['progress'] = true;
  }
  _mergePptOptions(result, options);
  if (options.custom.isNotEmpty) {
    result.addAll(_normalizeStringKeyMap(options.custom)!);
  }
  return result;
}

Map<String, dynamic> _normalizeEventDetails(EventDetails details) {
  final result = <String, dynamic>{};
  _putIfNotNull(result, 'publisher', details.publisher);
  _putIfNotNull(result, 'trustlevel', details.trustlevel);
  _putIfNotNull(result, 'topic', details.topic);
  _mergePptOptions(result, details);
  if (details.custom.isNotEmpty) {
    result.addAll(_normalizeStringKeyMap(details.custom)!);
  }
  return result;
}

Map<String, dynamic> _normalizeResultDetails(ResultDetails details) {
  final result = <String, dynamic>{};
  if (details.progress == true) {
    result['progress'] = true;
  }
  _mergePptOptions(result, details);
  if (details.custom.isNotEmpty) {
    result.addAll(_normalizeStringKeyMap(details.custom)!);
  }
  return result;
}

Map<String, dynamic> _normalizeInvocationDetails(InvocationDetails details) {
  final result = <String, dynamic>{};
  _putIfNotNull(result, 'caller', details.caller);
  _putIfNotNull(result, 'procedure', details.procedure);
  if (details.receiveProgress == true) {
    result['receive_progress'] = true;
  }
  _mergePptOptions(result, details);
  if (details.custom.isNotEmpty) {
    result.addAll(_normalizeStringKeyMap(details.custom)!);
  }
  return result;
}

void _mergePptOptions(Map<String, dynamic> target, PPTOptions options) {
  _putIfNotNull(target, 'ppt_scheme', options.pptScheme);
  _putIfNotNull(target, 'ppt_serializer', options.pptSerializer);
  _putIfNotNull(target, 'ppt_cipher', options.pptCipher);
  _putIfNotNull(target, 'ppt_keyid', options.pptKeyId);
}

Map<String, dynamic>? _normalizeStringKeyMap(Map<dynamic, dynamic>? value) {
  if (value == null) {
    return null;
  }
  return value.map(
    (key, nestedValue) =>
        MapEntry(key.toString(), _normalizeWireValue(nestedValue)),
  );
}

Map<String, dynamic>? _normalizeKwargs(Map<String, dynamic>? kwargs) {
  if (kwargs == null || kwargs.isEmpty) {
    return null;
  }
  return _normalizeStringKeyMap(kwargs);
}

Object? _normalizeWireValue(Object? value) {
  if (value is Uint8List) {
    return value.toList(growable: false);
  }
  if (value is cbor_pkg.CborValue) {
    return _normalizeWireValue(value.toObject());
  }
  if (value is List) {
    return value.map(_normalizeWireValue).toList(growable: false);
  }
  if (value is Map) {
    return value.map(
      (key, nestedValue) =>
          MapEntry(key.toString(), _normalizeWireValue(nestedValue)),
    );
  }
  return value;
}

String _bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

void _putIfNotNull(Map<String, dynamic> map, String key, Object? value) {
  if (value != null) {
    map[key] = value;
  }
}

void _mergeOptional(Map<String, dynamic> target, Map<String, dynamic> extra) {
  for (final entry in extra.entries) {
    target[entry.key] = entry.value;
  }
}

void _expectSubset(Object? expected, Object? actual, {required String path}) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: '$path must be a map');
    final actualMap = actual as Map;
    for (final entry in expected.entries) {
      if (entry.value == null && !actualMap.containsKey(entry.key)) {
        continue;
      }
      expect(
        actualMap.containsKey(entry.key),
        isTrue,
        reason: '$path is missing key ${entry.key}',
      );
      _expectSubset(
        entry.value,
        actualMap[entry.key],
        path: '$path.${entry.key}',
      );
    }
    return;
  }

  if (expected is List) {
    expect(actual, isA<List>(), reason: '$path must be a list');
    final actualList = actual as List;
    expect(actualList.length, expected.length, reason: '$path length mismatch');
    for (var index = 0; index < expected.length; index++) {
      _expectSubset(expected[index], actualList[index], path: '$path[$index]');
    }
    return;
  }

  expect(actual, equals(expected), reason: '$path mismatch');
}

class _VectorCase {
  _VectorCase({
    required this.label,
    required this.expectedAttributes,
    required this.serializers,
  });

  final String label;
  final Map<String, dynamic> expectedAttributes;
  final Map<String, dynamic> serializers;
}
