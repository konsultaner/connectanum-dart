import 'package:flat_buffers/flat_buffers.dart' as fb;

/// Preserve the standard SDK builder on web targets.
typedef ByteViewFlatBufferBuilder = fb.Builder;

/// Write a WAMP string with the SDK builder on web targets.
int writeWampFlatBufferString(fb.Builder builder, String value) =>
    builder.writeString(value);
