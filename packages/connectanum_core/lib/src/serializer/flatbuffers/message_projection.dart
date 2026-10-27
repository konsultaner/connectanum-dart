import 'package:connectanum_core/connectanum_core.dart';

import 'generated/validation_schema.dart';
import 'generated/wamp_wamp.proto_generated.dart' as wire;
import 'validation_types.dart';
import 'wamp_dictionary.dart';
import 'dictionary_retention.dart';

// The wire schema is fixed. Avoid scanning it and allocating predicates for
// every projection, including metadata-only native message binding.
final _messageTags = {
  for (final tag in wire.AnyMessageTypeId.values) tag.name: tag.value,
};
final _dictionaryFields = {
  for (final table in wampValidationTables)
    table.name: _selectDictionaryFields(table),
};

// Both projection and agreement must inspect the same fixed schema fields.
// Keep the plans immutable so sharing them cannot weaken later validation.
List<FlatBufferFieldSpec> flatBufferDictionaryFields(String name) =>
    _dictionaryFields[name] ?? (throw StateError('No element'));

List<FlatBufferFieldSpec> _selectDictionaryFields(FlatBufferTableSpec table) {
  final routingFields = switch (table.name) {
    'Hello' => const {'realm'},
    'Authenticate' => const {'signature'},
    'Abort' || 'Goodbye' => const {'reason'},
    'Error' => const {'request_type', 'error'},
    'Publish' || 'Subscribe' => const {'topic'},
    'Event' => const {'subscription', 'publication'},
    'Call' || 'Register' => const {'procedure'},
    'Invocation' => const {'registration'},
    _ => const <String>{},
  };
  return List<FlatBufferFieldSpec>.unmodifiable(
    table.fields.where(
      (field) =>
          !routingFields.contains(field.name) &&
          !(const {
            'session',
            'request',
            'args',
            'kwargs',
            'payload',
            'method',
            'method_name',
          }).contains(field.name),
    ),
  );
}

/// The message envelope and its complete logical WAMP dictionary. Application
/// byte vectors are supplied separately by the serializer or native builder.
class FlatBufferMessageProjection {
  const FlatBufferMessageProjection(this.fields, this.dictionary);

  final Map<String, Object?> fields;
  final Map<String, Object?>? dictionary;
}

FlatBufferMessageProjection projectWampFlatBufferMessage(
  AbstractMessage message, {
  bool retainMetadata = true,
}) {
  String name;
  final body = <String, Object?>{};
  Map<String, Object?>? dictionary;
  Map<String, Object?> map(Map? value) =>
      value == null ? {} : Map<String, Object?>.from(value);
  switch (message) {
    case Hello():
      name = 'Hello';
      body['realm'] = message.realm;
      dictionary = map(WampDictionaryCodec.serializeDetails(message.details));
    case Welcome():
      name = 'Welcome';
      body['session'] = message.sessionId;
      dictionary = map(WampDictionaryCodec.serializeDetails(message.details));
    case Abort():
      if (message.arguments != null || message.argumentsKeywords != null) {
        throw UnsupportedError('FlatBuffers ABORT has no application payload');
      }
      name = 'Abort';
      body['reason'] = message.reason;
      dictionary = map(message.details);
    case Challenge():
      name = 'Challenge';
      final method = flatBufferAuthMethods[message.authMethod];
      if (message.authMethod.isEmpty) {
        throw ArgumentError('Authentication method must be nonempty');
      }
      body['method'] = method ?? 0;
      if (method == null) body['method_name'] = message.authMethod;
      dictionary = map(message.extra.toMap());
    case Authenticate():
      name = 'Authenticate';
      body['signature'] = message.signature ?? '';
      dictionary = map(message.extra);
    case Goodbye():
      name = 'Goodbye';
      body['reason'] = message.reason;
      dictionary = {
        if (message.message?.message != null)
          'message': message.message!.message,
      };
    case Error():
      if (!(const {
        16,
        32,
        34,
        48,
        64,
        66,
        68,
      }).contains(message.requestTypeId)) {
        throw ArgumentError('Unsupported ERROR request type');
      }
      name = 'Error';
      body['request_type'] = message.requestTypeId;
      body['request'] = message.requestId;
      body['error'] = message.error;
      dictionary = map(message.details);
    case Publish():
      name = 'Publish';
      body['request'] = message.requestId;
      body['topic'] = message.topic;
      dictionary = WampDictionaryCodec.serializePublish(message.options);
    case Published():
      name = 'Published';
      body['request'] = message.publishRequestId;
      body['publication'] = message.publicationId;
    case Subscribe():
      name = 'Subscribe';
      body['request'] = message.requestId;
      body['topic'] = message.topic;
      dictionary = map(
        WampDictionaryCodec.serializeSubscribeOptions(message.options),
      );
    case Subscribed():
      name = 'Subscribed';
      body['request'] = message.subscribeRequestId;
      body['subscription'] = message.subscriptionId;
    case Unsubscribe():
      name = 'Unsubscribe';
      body['request'] = message.requestId;
      body['subscription'] = message.subscriptionId;
    case Unsubscribed():
      name = 'Unsubscribed';
      body['request'] = message.unsubscribeRequestId;
      dictionary = {
        if (message.details?.subscription != null)
          'subscription': message.details!.subscription,
        if (message.details?.reason != null) 'reason': message.details!.reason,
      };
    case Event():
      name = 'Event';
      body['subscription'] = message.subscriptionId;
      body['publication'] = message.publicationId;
      dictionary = WampDictionaryCodec.serializeEventDetails(message.details);
    case Call():
      name = 'Call';
      body['request'] = message.requestId;
      body['procedure'] = message.procedure;
      dictionary = WampDictionaryCodec.serializeCallOptions(message.options);
    case Cancel():
      name = 'Cancel';
      body['request'] = message.requestId;
      dictionary = {
        if (message.options?.mode != null) 'mode': message.options!.mode,
      };
    case Result():
      name = 'Result';
      body['request'] = message.callRequestId;
      final details = message.details;
      dictionary = {
        if (details.progress != null) 'progress': details.progress,
        if (details.pptScheme != null) 'ppt_scheme': details.pptScheme,
        if (details.pptSerializer != null)
          'ppt_serializer': details.pptSerializer,
        if (details.pptCipher != null) 'ppt_cipher': details.pptCipher,
        if (details.pptKeyId != null) 'ppt_keyid': details.pptKeyId,
        ...details.custom,
      };
    case Register():
      name = 'Register';
      body['request'] = message.requestId;
      body['procedure'] = message.procedure;
      dictionary = map(
        WampDictionaryCodec.serializeRegisterOptions(message.options),
      );
    case Registered():
      name = 'Registered';
      body['request'] = message.registerRequestId;
      body['registration'] = message.registrationId;
    case Unregister():
      name = 'Unregister';
      body['request'] = message.requestId;
      body['registration'] = message.registrationId;
    case Unregistered():
      name = 'Unregistered';
      body['request'] = message.unregisterRequestId;
      dictionary = {};
    case Invocation():
      name = 'Invocation';
      body['request'] = message.requestId;
      body['registration'] = message.registrationId;
      dictionary = WampDictionaryCodec.serializeInvocationDetails(
        message.details,
      );
    case Interrupt():
      name = 'Interrupt';
      body['request'] = message.requestId;
      dictionary = {
        if (message.options?.mode != null) 'mode': message.options!.mode,
      };
    case Yield():
      name = 'Yield';
      body['request'] = message.invocationRequestId;
      dictionary = WampDictionaryCodec.serializeYieldOptions(message.options);
    case Heartbeat():
      name = 'Heartbeat';
      body['ping'] = message.ping;
      body['incoming'] = message.incoming;
      body['outgoing'] = message.outgoing;
      body['presence'] =
          (message.ping == null ? 0 : 1) |
          (message.incoming == null ? 0 : 2) |
          (message.outgoing == null ? 0 : 4);
      dictionary = map(message.details);
    default:
      throw UnsupportedError(
        'FlatBuffers does not support ${message.runtimeType}',
      );
  }
  if (retainMetadata) {
    dictionary = retainedWampFlatBufferDictionary(message, dictionary);
  }
  if (dictionary != null && name != 'Heartbeat') {
    body.addAll(projectFlatBufferDictionary(name, dictionary));
  }
  return FlatBufferMessageProjection({
    'msg_type': _messageTags[name]!,
    'msg': body,
  }, dictionary);
}

const flatBufferAuthMethods = {
  'anonymous': 0,
  'ticket': 1,
  'wampcra': 2,
  'wamp-scram': 3,
  'cryptosign': 4,
};

const _enums = <String, Map<String, int>>{
  'method': flatBufferAuthMethods,
  'authmethod': flatBufferAuthMethods,
  'match': {'exact': 0, 'prefix': 1, 'wildcard': 2},
  'invoke': {'single': 0, 'first': 1, 'last': 2, 'roundrobin': 3, 'random': 4},
  'mode': {'skip': 0, 'kill': 1, 'killnowait': 2},
  'ppt_scheme': {'cryptobox': 1, 'mqtt': 2, 'xbr': 3, 'opaque': 4},
  'ppt_serializer': {
    'transport': 0,
    'json': 1,
    'msgpack': 2,
    'cbor': 3,
    'ubjson': 4,
    'opaque': 5,
    'flatbuffers': 6,
    'flexbuffers': 7,
  },
  'ppt_cipher': {'xsalsa20poly1305': 1, 'aes256gcm': 2},
};

/// Project representable dictionary fields into the pinned upstream table.
/// Unrepresentable names and values remain in the complete metadata dictionary.
Map<String, Object?> projectFlatBufferDictionary(
  String name,
  Map<String, Object?> dictionary,
) {
  final fields = <String, Object?>{};
  for (final field in flatBufferDictionaryFields(name)) {
    final value =
        field.name == 'extra' && (name == 'Challenge' || name == 'Authenticate')
        ? dictionary
        : dictionary[field.name];
    if (value == null) {
      if (field.required && field.kind == FlatBufferFieldKind.string) {
        fields[field.name] = '';
      } else if (field.required && field.kind == FlatBufferFieldKind.table) {
        fields[field.name] = <String, Object?>{};
      }
      continue;
    }
    switch (field.kind) {
      case FlatBufferFieldKind.string:
        if (value is! String) _invalid(field.name);
        fields[field.name] = value;
      case FlatBufferFieldKind.scalar:
        if (_enums.containsKey(field.name)) {
          if (value is! String) _invalid(field.name);
          final projected = _enums[field.name]![value];
          if (projected != null) fields[field.name] = projected;
        } else if (field.width == 1 && field.values.length == 2) {
          if (value is! bool) _invalid(field.name);
          fields[field.name] = value;
        } else {
          if (value is! int || value < 0 || value > 9007199254740992) {
            _invalid(field.name);
          }
          final maximum = switch (field.width) {
            1 => 255,
            2 => 65535,
            4 => 4294967295,
            _ => 9007199254740992,
          };
          if (value <= maximum) fields[field.name] = value;
        }
      case FlatBufferFieldKind.scalarVector:
        if (value is! List) _invalid(field.name);
        if (field.name == 'authmethods') {
          if (value.any((item) => item is! String || item.isEmpty)) {
            _invalid(field.name);
          }
          fields[field.name] = [
            for (final item in value)
              if (flatBufferAuthMethods.containsKey(item))
                flatBufferAuthMethods[item],
          ];
        } else {
          if (value.any(
            (item) => item is! int || item < 0 || item > 9007199254740992,
          )) {
            _invalid(field.name);
          }
          fields[field.name] = value;
        }
      case FlatBufferFieldKind.stringVector:
        if (value is! List || value.any((item) => item is! String)) {
          _invalid(field.name);
        }
        fields[field.name] = value;
      case FlatBufferFieldKind.table:
        if (value is! Map || value.keys.any((key) => key is! String)) {
          _invalid(field.name);
        }
        final nested = Map<String, Object?>.from(value);
        final nestedTable = wampValidationTables[field.reference];
        if (nestedTable.name == 'Map') {
          for (final entry in nested.entries) {
            if (entry.value is String &&
                RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(entry.key)) {
              fields[field.name] = {'key': entry.key, 'value': entry.value};
              break;
            }
          }
        } else {
          fields[field.name] = _roles(nestedTable, nested);
        }
      case FlatBufferFieldKind.tableVector:
        if (value is! List) _invalid(field.name);
        fields[field.name] = [for (final item in value) _principal(item)];
      case FlatBufferFieldKind.union:
        _invalid(field.name);
    }
  }
  return fields;
}

Map<String, Object?> _roles(
  FlatBufferTableSpec table,
  Map<String, Object?> roles,
) {
  final projected = <String, Object?>{};
  for (final role in table.fields) {
    final value = roles[role.name];
    if (value == null) continue;
    if (value is! Map) _invalid(role.name);
    final features = value['features'];
    if (features != null && features is! Map) _invalid(role.name);
    final output = <String, Object?>{};
    if (features is Map) {
      for (final feature in wampValidationTables[role.reference].fields) {
        final key = feature.name == 'payload_transparency'
            ? 'payload_passthru_mode'
            : feature.name;
        final enabled = features[key];
        if (enabled == null) continue;
        if (enabled is! bool) _invalid(key);
        output[feature.name] = enabled;
      }
    }
    projected[role.name] = output;
  }
  return projected;
}

Map<String, Object?> _principal(Object? value) {
  if (value is! Map) _invalid('forward_for');
  final session = value['session'];
  if (session != null &&
      (session is! int || session < 0 || session > 9007199254740992)) {
    _invalid('forward_for.session');
  }
  for (final name in ['authid', 'authrole']) {
    if (value[name] != null && value[name] is! String) {
      _invalid('forward_for.$name');
    }
  }
  return {
    'session': ?session,
    if (value['authid'] != null) 'authid': value['authid'],
    if (value['authrole'] != null) 'authrole': value['authrole'],
  };
}

Never _invalid(String field) =>
    throw ArgumentError('Invalid WAMP dictionary field $field');
