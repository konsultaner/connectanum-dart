@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:connectanum_bench/src/bench_payload/codec.dart';
import 'package:connectanum_bench/src/bench_payload/generated/workload_payload_connectanum.bench_generated.dart'
    as schema;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:test/test.dart';

void main() {
  test(
    'single-table fixture has identical bytes with either vtable policy',
    () {
      for (final size in [0, 1, 7, 65536, 1048576]) {
        for (final identity in [(0, 0), (1, 1), (0xffffffff, 0xffffffff)]) {
          Uint8List encode(bool deduplicateTables) {
            final builder = flatbuffers.WampFlatBufferBuilder(
              initialSize: size + 128,
              deduplicateTables: deduplicateTables,
            );
            builder.finish(
              schema.WorkloadPayloadObjectBuilder(
                worker: identity.$1,
                iteration: identity.$2,
                body: BenchPayloadCodec.body(
                  worker: identity.$1,
                  iteration: identity.$2,
                  length: size,
                ),
              ).finish(builder),
              BenchPayloadCodec.fileIdentifier,
            );
            return builder.buffer;
          }

          final expected = encode(true);
          expect(encode(false), orderedEquals(expected));
          expect(
            BenchPayloadCodec.encodeDart(
              worker: identity.$1,
              iteration: identity.$2,
              bodyBytes: size,
            ),
            orderedEquals(expected),
          );
          BenchPayloadCodec.verify(
            bytes: expected,
            worker: identity.$1,
            iteration: identity.$2,
            bodyBytes: size,
          );
        }
      }
    },
  );
}
