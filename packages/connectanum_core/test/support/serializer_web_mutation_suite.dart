@TestOn('js')
library;

import 'package:test/test.dart';

import '../serializer/msgpack/codec_fallback_web_test.dart' as fallback;
import 'serializer_mutation_suite.dart' as serializers;

void main() {
  serializers.main();
  group('msgpack JS fallback', fallback.main);
}
