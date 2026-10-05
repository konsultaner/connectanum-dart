import 'dart:typed_data';

/// Internal payload anchor pairing a native owner with its exact exported view.
typedef NativeFlatBufferPptOwnerAnchor = ({
  Object buffer,
  Uint8List bytes,
});
