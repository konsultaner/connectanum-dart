enum FlatBufferFieldKind {
  scalar,
  string,
  table,
  scalarVector,
  stringVector,
  tableVector,
  union,
}

class FlatBufferFieldSpec {
  const FlatBufferFieldSpec(
    this.name,
    this.kind,
    this.width, {
    this.required = false,
    this.reference = -1,
    this.values = const [],
    this.wampInteger = false,
  });

  final String name;
  final FlatBufferFieldKind kind;
  final int width;
  final bool required;
  final int reference;
  final List<int> values;
  final bool wampInteger;
}

class FlatBufferTableSpec {
  const FlatBufferTableSpec(this.name, this.fields);

  final String name;
  final List<FlatBufferFieldSpec> fields;
}
