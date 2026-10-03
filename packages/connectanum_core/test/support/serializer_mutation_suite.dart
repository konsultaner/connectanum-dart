import 'package:test/test.dart';

import '../message_lazy_payload_regression_test.dart' as lazy_payload;
import '../serializer/cbor/serializer_indefinite_test.dart' as cbor_indefinite;
import '../serializer/cbor/serializer_missing_messages_test.dart'
    as cbor_missing;
import '../serializer/cbor/serializer_ppt_binary_test.dart' as cbor_ppt;
import '../serializer/cbor/serializer_test.dart' as cbor_serializer;
import '../serializer/flatbuffers_binding_test.dart' as flatbuffers_binding;
import '../serializer/flatbuffers_validation_test.dart'
    as flatbuffers_validation;
import '../serializer/flatbuffers_wire_writer_test.dart' as flatbuffers_writer;
import '../serializer/flatbuffers_message_writer_test.dart'
    as flatbuffers_message_writer;
import '../serializer/flatbuffers_cbor_validation_test.dart'
    as flatbuffers_cbor_validation;
import '../serializer/flatbuffers_frame_test.dart' as flatbuffers_frame;
import '../serializer/flatbuffers_message_reader_test.dart'
    as flatbuffers_message_reader;
import '../serializer/flatbuffers_metadata_roundtrip_test.dart'
    as flatbuffers_metadata_roundtrip;
import '../serializer/json/binary_codec_test.dart' as json_binary;
import '../serializer/json/serializer_test.dart' as json_serializer;
import '../serializer/msgpack/codec_test.dart' as msgpack_codec;
import '../serializer/msgpack/ppt_rejection_test.dart' as msgpack_ppt_rejection;
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
import '../serializer/serializer_inbound_metadata_test.dart'
    as inbound_metadata;
import '../serializer/serializer_ppt_fragment_precedence_test.dart'
    as ppt_fragments;
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
  group('FlatBuffers binding', flatbuffers_binding.main);
  group('FlatBuffers validation', flatbuffers_validation.main);
  group('FlatBuffers writer', flatbuffers_writer.main);
  group('FlatBuffers message writer', flatbuffers_message_writer.main);
  group('FlatBuffers CBOR validation', flatbuffers_cbor_validation.main);
  group('FlatBuffers frame', flatbuffers_frame.main);
  group('FlatBuffers message reader', flatbuffers_message_reader.main);
  group('FlatBuffers metadata roundtrip', flatbuffers_metadata_roundtrip.main);
  group('JSON binary', json_binary.main);
  group('JSON serializer', json_serializer.main);
  group('MessagePack codec', msgpack_codec.main);
  group('MessagePack PPT rejection', msgpack_ppt_rejection.main);
  group('MessagePack ingress', msgpack_ingress.main);
  group('MessagePack missing messages', msgpack_missing.main);
  group('MessagePack serializer', msgpack_serializer.main);
  group('MessagePack wire boundaries', msgpack_wire.main);
  group('authentication extra', auth_extra.main);
  group('message shapes', shape.main);
  group('option containers', options.main);
  group('numeric options', numeric.main);
  group('outbound metadata', metadata.main);
  group('inbound metadata', inbound_metadata.main);
  group('PPT fragment precedence', ppt_fragments.main);
  group('payload containers', payload.main);
  group('PPT null values', ppt_nulls.main);
  group('resource limits', limits.main);
  group('handshake', handshake.main);
}
