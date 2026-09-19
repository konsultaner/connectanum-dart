import 'package:test/test.dart';

import '../message_lazy_payload_regression_test.dart' as lazy_payload;
import '../serializer/cbor/serializer_indefinite_test.dart' as cbor_indefinite;
import '../serializer/cbor/serializer_missing_messages_test.dart'
    as cbor_missing;
import '../serializer/cbor/serializer_ppt_binary_test.dart' as cbor_ppt;
import '../serializer/cbor/serializer_test.dart' as cbor_serializer;
import '../serializer/json/binary_codec_test.dart' as json_binary;
import '../serializer/json/serializer_test.dart' as json_serializer;
import '../serializer/msgpack/codec_test.dart' as msgpack_codec;
import '../serializer/msgpack/serializer_ingress_test.dart' as msgpack_ingress;
import '../serializer/msgpack/serializer_missing_messages_test.dart'
    as msgpack_missing;
import '../serializer/msgpack/serializer_test.dart' as msgpack_serializer;
import '../serializer/msgpack/serializer_wire_boundaries_test.dart'
    as msgpack_wire;
import '../serializer/serializer_authenticate_extra_security_test.dart'
    as auth_extra;
import '../serializer/serializer_message_shape_security_test.dart' as shape;
import '../serializer/serializer_option_container_security_test.dart'
    as options;
import '../serializer/serializer_optional_numeric_security_test.dart'
    as numeric;
import '../serializer/serializer_outbound_metadata_test.dart' as metadata;
import '../serializer/serializer_payload_container_matrix_test.dart' as payload;
import '../serializer/serializer_ppt_null_values_test.dart' as ppt_nulls;
import '../serializer/serializer_security_limits_test.dart' as limits;
import '../serializer_challenge_welcome_test.dart' as handshake;

void main() {
  group('lazy payload', lazy_payload.main);
  group('CBOR indefinite', cbor_indefinite.main);
  group('CBOR missing messages', cbor_missing.main);
  group('CBOR PPT binary', cbor_ppt.main);
  group('CBOR serializer', cbor_serializer.main);
  group('JSON binary', json_binary.main);
  group('JSON serializer', json_serializer.main);
  group('MessagePack codec', msgpack_codec.main);
  group('MessagePack ingress', msgpack_ingress.main);
  group('MessagePack missing messages', msgpack_missing.main);
  group('MessagePack serializer', msgpack_serializer.main);
  group('MessagePack wire boundaries', msgpack_wire.main);
  group('authentication extra', auth_extra.main);
  group('message shapes', shape.main);
  group('option containers', options.main);
  group('numeric options', numeric.main);
  group('outbound metadata', metadata.main);
  group('payload containers', payload.main);
  group('PPT null values', ppt_nulls.main);
  group('resource limits', limits.main);
  group('handshake', handshake.main);
}
