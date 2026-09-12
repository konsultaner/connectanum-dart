const int serializerMaxPayloadNestingDepth = 64;
const int serializerMaxWampMessageFields = 7;
const int serializerMaxWampId = 0x20000000000000;

@pragma('vm:prefer-inline')
@pragma('dart2js:tryInline')
int enterSerializerContainer(int parentDepth) {
  if (parentDepth >= serializerMaxPayloadNestingDepth) {
    throw const FormatException(
      'Serialized payload exceeds the maximum nesting depth',
    );
  }
  return parentDepth + 1;
}

@pragma('vm:prefer-inline')
@pragma('dart2js:tryInline')
void validateWampMessageFieldCount(int fieldCount) {
  if (fieldCount > serializerMaxWampMessageFields) {
    throw const FormatException('WAMP message contains too many fields');
  }
}

@pragma('vm:prefer-inline')
@pragma('dart2js:tryInline')
void validateWampMessageMinimumFieldCount(int messageType, int fieldCount) {
  final int minimumFields;
  switch (messageType) {
    case 8: // ERROR
      minimumFields = 5;
    case 16: // PUBLISH
    case 32: // SUBSCRIBE
    case 36: // EVENT
    case 48: // CALL
    case 64: // REGISTER
    case 68: // INVOCATION
      minimumFields = 4;
    case 35: // UNSUBSCRIBED
    case 67: // UNREGISTERED
      minimumFields = 2;
    case 1: // HELLO
    case 2: // WELCOME
    case 3: // ABORT
    case 4: // CHALLENGE
    case 5: // AUTHENTICATE
    case 6: // GOODBYE
    case 17: // PUBLISHED
    case 33: // SUBSCRIBED
    case 34: // UNSUBSCRIBE
    case 49: // CANCEL
    case 50: // RESULT
    case 65: // REGISTERED
    case 66: // UNREGISTER
    case 69: // INTERRUPT
    case 70: // YIELD
      minimumFields = 3;
    default:
      return;
  }
  if (fieldCount < minimumFields) {
    throw const FormatException('WAMP message contains too few fields');
  }
}

@pragma('vm:prefer-inline')
@pragma('dart2js:tryInline')
void validateKnownWampMessageMinimumFieldCount(
  int fieldCount,
  int minimumFieldCount,
) {
  if (fieldCount < minimumFieldCount) {
    throw const FormatException('WAMP message contains too few fields');
  }
}

@pragma('vm:prefer-inline')
@pragma('dart2js:tryInline')
List<int>? decodeOptionalWampIdList(
  Map<String, dynamic> options,
  String optionName,
) {
  if (!options.containsKey(optionName)) {
    return null;
  }
  final value = options[optionName];
  if (value is! List) {
    _throwInvalidWampIdList(optionName);
  }
  final result = List<int>.filled(value.length, 0, growable: false);
  for (var index = 0; index < value.length; index++) {
    final entry = value[index];
    final int id;
    if (entry is int) {
      if (entry.toDouble() != entry.truncateToDouble()) {
        _throwInvalidWampIdList(optionName);
      }
      id = entry;
    } else if (entry is BigInt) {
      if (entry < BigInt.one || entry > BigInt.from(serializerMaxWampId)) {
        _throwInvalidWampIdList(optionName);
      }
      id = entry.toInt();
    } else {
      _throwInvalidWampIdList(optionName);
    }
    if (id < 1 || id > serializerMaxWampId) {
      _throwInvalidWampIdList(optionName);
    }
    result[index] = id;
  }
  return result;
}

List<String>? decodeOptionalWampStringList(
  Map<String, dynamic> options,
  String optionName,
) {
  if (!options.containsKey(optionName)) {
    return null;
  }
  final value = options[optionName];
  if (value is! List) {
    _throwInvalidWampStringList(optionName);
  }
  final result = List<String>.filled(value.length, '', growable: false);
  for (var index = 0; index < value.length; index++) {
    final entry = value[index];
    if (entry is! String) {
      _throwInvalidWampStringList(optionName);
    }
    result[index] = entry;
  }
  return result;
}

Never _throwInvalidWampIdList(String optionName) {
  throw FormatException(
    'PUBLISH.Options.$optionName must be a list of WAMP IDs',
  );
}

Never _throwInvalidWampStringList(String optionName) {
  throw FormatException(
    'PUBLISH.Options.$optionName must be a list of strings',
  );
}
