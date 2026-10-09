import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:connectanum_core/connectanum_core.dart';
import '../../message/field_assignments.dart';
import 'message_projection.dart';
import 'cbor_encoding.dart';

final _retained = Expando<_RetainedDictionary>('FlatBuffers dictionary');
const _equal = DeepCollectionEquality();

/// Internal metadata retention only. Application payloads are never cloned.
void retainWampFlatBufferDictionary(
  AbstractMessage message,
  Uint8List bytes,
  Map<String, dynamic>? dictionary,
) {
  if (dictionary == null) return;
  final projection = projectWampFlatBufferMessage(
    message,
    retainMetadata: false,
  ).dictionary!;
  _retained[message] = _RetainedDictionary(
    bytes,
    _snapshot(dictionary) as Map<String, Object?>,
    _snapshot(projection) as Map<String, Object?>,
    _modelIdentities(message),
  );
  for (final object in _retained[message]!.identities.values) {
    if (object != null) observeWampFieldAssignments(object);
  }
}

Map<String, Object?>? retainedWampFlatBufferDictionary(
  AbstractMessage message,
  Map<String, Object?>? dictionary,
) {
  final retained = _retained[message];
  if (retained == null || dictionary == null) return dictionary;
  dictionary = Map<String, Object?>.from(
    normalizeWampFlatBufferCborInput(
          dictionary,
          maximumBytes: 1048576,
          stringDictionaryKeys: true,
        )
        as Map,
  );
  final identities = _modelIdentities(message);
  if (!identical(identities[''], retained.identities[''])) return dictionary;
  final replacedPaths = <String>{};
  for (final entry in identities.entries) {
    if (!identical(entry.value, retained.identities[entry.key])) {
      replacedPaths.add(entry.key);
    }
    if (entry.value != null) {
      for (final field in assignedWampFields(entry.value!)) {
        replacedPaths.add(entry.key.isEmpty ? field : '${entry.key}.$field');
      }
    }
  }
  return _merge(
    retained.original,
    retained.baseline,
    dictionary,
    '',
    replacedPaths,
  );
}

class _RetainedDictionary {
  _RetainedDictionary(
    this.owner,
    this.original,
    this.baseline,
    this.identities,
  );
  // The original frame owner remains strongly held for the decoded model.
  final Uint8List owner;
  final Map<String, Object?> original;
  final Map<String, Object?> baseline;
  final Map<String, Object?> identities;
}

Map<String, Object?> _merge(
  Map<String, Object?> original,
  Map<String, Object?> baseline,
  Map<String, Object?> current,
  String prefix,
  Set<String> replacedPaths,
) {
  final result = Map<String, Object?>.from(original);
  for (final key in {...baseline.keys, ...current.keys}) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    final before = baseline[key];
    final after = current[key];
    if (replacedPaths.contains(path)) {
      if (current.containsKey(key)) {
        result[key] = _snapshot(after);
      } else {
        result.remove(key);
      }
    } else if (before is Map<String, Object?> &&
        after is Map &&
        original[key] is Map<String, Object?>) {
      result[key] = _merge(
        original[key] as Map<String, Object?>,
        before,
        Map<String, Object?>.from(after),
        path,
        replacedPaths,
      );
    } else if (baseline.containsKey(key) != current.containsKey(key) ||
        !_equal.equals(before, after)) {
      if (current.containsKey(key)) {
        result[key] = _snapshot(after);
      } else {
        result.remove(key);
      }
    }
  }
  return result;
}

Object? _snapshot(Object? value) {
  if (value is Uint8List) return Uint8List.fromList(value);
  if (value is List) return value.map(_snapshot).toList(growable: false);
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _snapshot(entry.value),
    };
  }
  return value;
}

Map<String, Object?> _modelIdentities(AbstractMessage message) {
  final Object? root = switch (message) {
    Hello() => message.details,
    Welcome() => message.details,
    Abort() => message.details,
    Challenge() => message.extra,
    Authenticate() => message.extra,
    Goodbye() => message.message,
    Error() => message.details,
    Publish() => message.options,
    Subscribe() => message.options,
    Unsubscribed() => message.details,
    Event() => message.details,
    Call() => message.options,
    Cancel() => message.options,
    Result() => message.details,
    Register() => message.options,
    Invocation() => message.details,
    Interrupt() => message.options,
    Yield() => message.options,
    Heartbeat() => message.details,
    _ => message,
  };
  final result = <String, Object?>{'': root};
  if (root is Details) {
    final roles = root.roles;
    result['roles'] = roles;
    final objects = <String, Object?>{
      'caller': roles?.caller,
      'callee': roles?.callee,
      'publisher': roles?.publisher,
      'subscriber': roles?.subscriber,
      'dealer': roles?.dealer,
      'broker': roles?.broker,
    };
    for (final entry in objects.entries) {
      result['roles.${entry.key}'] = entry.value;
      result['roles.${entry.key}.features'] = switch (entry.value) {
        Caller object => object.features,
        Callee object => object.features,
        Publisher object => object.features,
        Subscriber object => object.features,
        Dealer object => object.features,
        Broker object => object.features,
        _ => null,
      };
    }
  }
  return result;
}
