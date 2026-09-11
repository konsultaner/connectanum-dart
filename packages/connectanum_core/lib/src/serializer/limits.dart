const int serializerMaxPayloadNestingDepth = 64;
const int serializerMaxWampMessageFields = 7;

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
