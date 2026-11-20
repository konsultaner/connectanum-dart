@TestOn('js')
library;

import 'package:connectanum_core/src/serializer/msgpack/codec.dart' as codec;
import 'package:test/test.dart';

import 'codec_fallback_test_support.dart';
import 'codec_test_support.dart' as support;

void main() {
  registerFallbackTests(
    const support.CheckedCodec(codec.serialize, codec.deserialize),
    delegatedRootErrors: true,
  );
}
