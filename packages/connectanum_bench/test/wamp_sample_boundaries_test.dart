import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_bench/src/wamp_sample_json.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:connectanum_router/src/router/http/http_context.dart';
import 'package:test/test.dart';

void main() {
  group('versioned worker sample records', () {
    const named = <String, Object?>{
      'worker': 3,
      'iteration': 7,
      'latency_ms': 1.25,
      'request_bytes': 4294967296,
      'response_bytes': 4294967297,
      'payload_preparation_us': 11,
      'native_builder_input_copied_bytes': 13,
      'native_builder_growth_copied_bytes': 17,
      'native_ppt_frame_submissions': 19,
      'native_ppt_payload_bytes': 23,
      'native_ppt_payload_reused_bytes': 29,
      'started_at_us': 9007199254740993,
      'completed_at_us': 9007199254742243,
    };
    const positional = <Object?>[
      3,
      7,
      1.25,
      4294967296,
      4294967297,
      11,
      13,
      17,
      19,
      23,
      29,
      9007199254740993,
      9007199254742243,
    ];

    test('golden order preserves every public field and wide integer', () {
      final sample = WampSample.fromJson(named);
      expect(WampSample.workerRecordEncoding, 'positional_v1');
      expect(sample.toWorkerRecord(), positional);
      expect(
        jsonEncode(wampSampleWorkerRecordForJsonEncoding(sample)),
        jsonEncode(positional),
      );
      final decoded = WampSample.fromWorkerRecord(
        (jsonDecode(jsonEncode(positional)) as List).cast<Object?>(),
      );
      expect(decoded.toJson(), named);
      expect(jsonEncode(decoded), jsonEncode(named));
      expect(
        jsonEncode(wampSamplesForJsonEncoding([decoded])),
        jsonEncode([named]),
      );
    });

    test(
      'all nullable combinations preserve omitted fields and explicit zero',
      () {
        final optional = named.keys.skip(5).toList();
        for (var mask = 0; mask < 256; mask++) {
          final fields = Map<String, Object?>.from(named);
          for (var i = 0; i < optional.length; i++) {
            if (mask & (1 << i) == 0) {
              fields.remove(optional[i]);
            } else {
              fields[optional[i]] = 0;
            }
          }
          final sample = WampSample.fromJson(fields);
          expect(
            WampSample.fromWorkerRecord(sample.toWorkerRecord()).toJson(),
            fields,
            reason: 'mask=$mask',
          );
          expect(
            jsonEncode(wampSampleWorkerRecordForJsonEncoding(sample)),
            jsonEncode(sample.toWorkerRecord()),
            reason: 'mask=$mask',
          );
          expect(
            jsonEncode(wampSamplesForJsonEncoding([sample])),
            jsonEncode([fields]),
            reason: 'mask=$mask',
          );
        }
      },
    );

    test('worker UTF-8 preserves named, positional and error JSON bytes', () {
      final sample = WampSample.fromJson(named);
      for (final compact in [false, true]) {
        final response = <String, Object?>{
          if (compact) 'sample_encoding': WampSample.workerRecordEncoding,
          'samples': [sample],
          'extra': {'text': 'Unicode: 🪄 é \n \r \u0000 \ud800'},
          'empty': [],
          'absent': null,
        };
        final expected = utf8.encode(
          jsonEncode(
            response,
            toEncodable: compact
                ? (object) => (object as WampSample).toWorkerRecord()
                : null,
          ),
        );
        expect(
          wampWorkerResponseJsonBytes(response, compactSamples: compact),
          expected,
        );
      }
      final error = {'error': 'bad request 🪄 \n \r \u0000'};
      expect(
        wampWorkerResponseJsonBytes(error),
        utf8.encode(jsonEncode(error)),
      );
      expect(
        wampWorkerResponseJsonBytes({'samples': []}, compactSamples: true),
        utf8.encode('{"samples":[]}'),
      );
    });

    test('worker UTF-8 preserves encoder failure and later recovery', () {
      for (final compact in [false, true]) {
        for (final invalid in [
          double.nan,
          double.infinity,
          double.negativeInfinity,
          Object(),
        ]) {
          expect(
            () => wampWorkerResponseJsonBytes({
              'invalid': invalid,
            }, compactSamples: compact),
            throwsA(isA<JsonUnsupportedObjectError>()),
          );
        }
        final cycle = <Object?>[];
        cycle.add(cycle);
        expect(
          () => wampWorkerResponseJsonBytes({
            'cycle': cycle,
          }, compactSamples: compact),
          throwsA(isA<JsonCyclicError>()),
        );
        expect(
          wampWorkerResponseJsonBytes({'ok': true}, compactSamples: compact),
          utf8.encode('{"ok":true}'),
        );
      }
    });

    test('chunked reports retain every named/positional sample and byte', () {
      final samples = List.generate(
        2048,
        (index) => WampSample.fromJson({...named, 'iteration': index}),
      );
      for (final compact in [false, true]) {
        final response = <String, Object?>{
          if (compact) 'sample_encoding': WampSample.workerRecordEncoding,
          'samples': compact ? samples : wampSamplesForJsonEncoding(samples),
          // Cross several chunk boundaries inside multibyte/escaped strings.
          'extra': List.filled(65537, 'é 🪄 \n \r \u0000 \ud800').join(),
          'absent': null,
          'empty': [],
        };
        final expected = wampWorkerResponseJsonBytes(
          response,
          compactSamples: compact,
        );
        final chunks = wampResponseJsonChunks(
          response,
          compactSamples: compact,
        );
        expect(chunks.length, greaterThan(2));
        expect(chunks.every((chunk) => chunk.length <= 65536), isTrue);
        expect(chunks.expand((chunk) => chunk), expected);
        final decoded =
            jsonDecode(utf8.decode(chunks.expand((c) => c).toList()))
                as Map<String, Object?>;
        final rows = decoded['samples'] as List;
        expect(rows.length, samples.length);
        for (var index = 0; index < samples.length; index++) {
          final restored = compact
              ? WampSample.fromWorkerRecord(
                  (rows[index] as List).cast<Object?>(),
                )
              : WampSample.fromJson(rows[index] as Map<String, Object?>);
          expect(restored.toJson(), samples[index].toJson());
        }
      }
    });

    test('chunked encoding fails before publishing any partial report', () {
      for (final compact in [false, true]) {
        for (final invalid in [double.nan, double.infinity, Object()]) {
          List<List<int>>? published;
          expect(
            () => published = wampResponseJsonChunks({
              'valid_prefix': List.filled(131073, 'x').join(),
              'invalid': invalid,
            }, compactSamples: compact),
            throwsA(isA<JsonUnsupportedObjectError>()),
          );
          expect(published, isNull);
        }
        final cycle = <Object?>[];
        cycle.add(cycle);
        expect(
          () =>
              wampResponseJsonChunks({'cycle': cycle}, compactSamples: compact),
          throwsA(isA<JsonCyclicError>()),
        );
        for (final response in <Map<String, Object?>>[
          {'samples': []},
          {'error': 'bad request 🪄 \n \r \u0000'},
        ]) {
          expect(
            wampResponseJsonChunks(
              response,
              compactSamples: compact,
            ).expand((chunk) => chunk),
            wampWorkerResponseJsonBytes(response, compactSamples: compact),
          );
        }
      }
    });

    test(
      'streamed reports preserve complete bytes and immutable snapshots',
      () {
        for (final compact in [false, true]) {
          final samples = List.generate(
            2048,
            (index) => WampSample.fromJson({...named, 'iteration': index}),
          );
          final metadata = <String, Object?>{
            'extra': {'text': 'Unicode: 🪄 é \n \r \u0000 \ud800'},
            'absent': null,
            'empty': [],
          };
          final expected = wampWorkerResponseJsonBytes({
            if (compact) 'sample_encoding': WampSample.workerRecordEncoding,
            'samples': compact ? samples : wampSamplesForJsonEncoding(samples),
            ...metadata,
          }, compactSamples: compact);
          final report = prepareWampSampleReportJson(
            samples: samples,
            fields: metadata,
            compactSamples: compact,
          );
          final iterator = report.chunks.iterator;
          expect(iterator.moveNext(), isTrue);
          final output = BytesBuilder(copy: false)..add(iterator.current);
          samples.clear();
          (metadata['extra'] as Map)['text'] = 'changed';
          metadata.clear();
          var chunks = 1;
          while (iterator.moveNext()) {
            expect(iterator.current.length, lessThanOrEqualTo(65536));
            output.add(iterator.current);
            chunks++;
          }
          expect(chunks, greaterThan(3));
          expect(output.takeBytes(), expected);
          // Iteration neither consumes nor exposes mutable metadata storage.
          expect(report.chunks.expand((c) => c), expected);
        }
      },
    );

    test(
      'streamed preparation rejects late invalid rows/metadata atomically',
      () {
        final valid = WampSample.fromJson(named);
        for (final compact in [false, true]) {
          for (final invalid in [
            double.nan,
            double.infinity,
            -double.infinity,
          ]) {
            WampSampleReportJson? published;
            expect(
              () => published = prepareWampSampleReportJson(
                samples: [
                  ...List.filled(2048, valid),
                  WampSample.fromJson({...named, 'latency_ms': invalid}),
                ],
                fields: const {},
                compactSamples: compact,
              ),
              throwsA(isA<JsonUnsupportedObjectError>()),
            );
            expect(published, isNull);
          }
          for (final invalid in [Object(), double.nan, double.infinity]) {
            expect(
              () => prepareWampSampleReportJson(
                samples: [valid],
                fields: {'invalid': invalid},
                compactSamples: compact,
              ),
              throwsA(isA<JsonUnsupportedObjectError>()),
            );
          }
          final cycle = <Object?>[];
          cycle.add(cycle);
          expect(
            () => prepareWampSampleReportJson(
              samples: [valid],
              fields: {'cycle': cycle},
              compactSamples: compact,
            ),
            throwsA(isA<JsonCyclicError>()),
          );
          for (final key in ['samples', 'sample_encoding']) {
            expect(
              () => prepareWampSampleReportJson(
                samples: [valid],
                fields: {key: []},
                compactSamples: compact,
              ),
              throwsArgumentError,
            );
          }
        }
      },
    );

    test(
      'streamed reports retain empty rows, zeros and numeric JSON spellings',
      () {
        for (final compact in [false, true]) {
          for (final latency in [-1.0, 0.0, -0.0, 1e-100, 1e100]) {
            for (final samples in <List<WampSample>>[
              [],
              [
                WampSample.fromJson({...named, 'latency_ms': latency}),
              ],
            ]) {
              final report = prepareWampSampleReportJson(
                samples: samples,
                fields: const {},
                compactSamples: compact,
              );
              expect(
                report.chunks.expand((chunk) => chunk),
                wampWorkerResponseJsonBytes({
                  if (compact)
                    'sample_encoding': WampSample.workerRecordEncoding,
                  'samples': compact
                      ? samples
                      : wampSamplesForJsonEncoding(samples),
                }, compactSamples: compact),
              );
            }
          }
        }
      },
    );

    test('streamed batch boundaries preserve every exact numeric row', () {
      for (final compact in [false, true]) {
        for (final count in [0, 1, 63, 64, 65, 127, 128, 129, 257]) {
          final samples = List.generate(
            count,
            (index) => WampSample.fromJson({
              ...named,
              'iteration': index,
              'latency_ms': index.isEven
                  ? -double.maxFinite
                  : double.minPositive,
              for (final key in named.keys)
                if (key != 'latency_ms' && key != 'iteration')
                  key: 0x7fffffffffffffff,
            }),
          );
          final report = prepareWampSampleReportJson(
            samples: samples,
            fields: const {'extra': r'🌟\path"'},
            compactSamples: compact,
          );
          final chunks = report.chunks.toList();
          expect(chunks.every((c) => c.length <= 65536), isTrue);
          expect(
            chunks.expand((c) => c),
            wampWorkerResponseJsonBytes({
              if (compact) 'sample_encoding': WampSample.workerRecordEncoding,
              'samples': compact
                  ? samples
                  : wampSamplesForJsonEncoding(samples),
              'extra': r'🌟\path"',
            }, compactSamples: compact),
          );
        }
      }
    });

    test('record input and output cannot mutate a parsed sample', () {
      final row = List<Object?>.from(positional);
      final sample = WampSample.fromWorkerRecord(row);
      row[0] = 99;
      sample.toWorkerRecord()[1] = 99;
      expect(sample.toJson(), named);
    });

    test('observation scalars remain independent across context changes', () {
      final samples = <WampSample>[];
      final expected = <List<Object?>>[];
      for (var index = 0; index < 160; index++) {
        final row = <Object?>[
          index,
          index,
          1.25,
          index * 7,
          index * 11,
          index * 13,
          index.isEven ? null : 0,
          index * 17,
          index * 19,
          index * 23,
          index * 29,
          9007199254740993 + index,
          9007199254742243 + index,
        ];
        expected.add(List.of(row));
        samples.add(WampSample.fromWorkerRecord(row));
      }
      // Revisit an earlier scalar tuple with distinct per-observation values.
      final repeated = List<Object?>.of(expected[130])
        ..[1] = 999
        ..[2] = 2.5
        ..[5] = 1000
        ..[11] = 9007199254745001
        ..[12] = 9007199254746001;
      samples.add(WampSample.fromWorkerRecord(repeated));
      expected.add(repeated);
      for (var index = 0; index < samples.length; index++) {
        final sample = samples[index];
        expect(sample.toWorkerRecord(), expected[index]);
        sample.toJson()['worker'] = -1;
        sample.toWorkerRecord()[6] = -1;
        expect(sample.toWorkerRecord(), expected[index]);
      }
      final absent = WampSample.fromWorkerRecord(
        List<Object?>.of(positional)..[8] = null,
      );
      final zero = WampSample.fromWorkerRecord(
        List<Object?>.of(positional)..[8] = 0,
      );
      expect(
        absent.toJson().containsKey('native_ppt_frame_submissions'),
        isFalse,
      );
      expect(zero.toJson()['native_ppt_frame_submissions'], 0);
    });

    test('numeric JSON spellings match named-field parsing', () {
      final row = positional.map((value) {
        return value is int && value <= 9007199254740991
            ? value.toDouble()
            : value;
      }).toList();
      expect(WampSample.fromWorkerRecord(row).toJson(), named);
    });

    test('rejects truncated and extended records', () {
      for (var length = 0; length <= 15; length++) {
        if (length == 13) continue;
        expect(
          () => WampSample.fromWorkerRecord(List<Object?>.filled(length, 0)),
          throwsFormatException,
          reason: 'length=$length',
        );
      }
    });

    test('record numbers follow named-field validation', () {
      for (var index = 0; index < positional.length; index++) {
        for (final invalid in <Object?>[
          '1',
          true,
          [],
          {},
          if (index < 5) null,
        ]) {
          final row = List<Object?>.from(positional)..[index] = invalid;
          expect(
            () => WampSample.fromWorkerRecord(row),
            throwsFormatException,
            reason: 'index=$index value=$invalid',
          );
        }
      }
      for (final index in [8, 9, 10]) {
        for (final invalid in [
          -1,
          1.5,
          double.nan,
          double.infinity,
          9007199254740992.0,
        ]) {
          final row = List<Object?>.from(positional)..[index] = invalid;
          expect(
            () => WampSample.fromWorkerRecord(row),
            throwsFormatException,
            reason: 'copy index=$index value=$invalid',
          );
        }
      }
    });

    test('many records preserve every observation and public JSON byte', () {
      final originals = List.generate(
        2048,
        (index) => WampSample.fromJson({
          ...named,
          'iteration': index,
          'native_ppt_frame_submissions': index,
          'started_at_us': 1000000 + index * 2000,
          'completed_at_us': 1001250 + index * 2000,
        }),
      );
      final wire = jsonEncode(
        originals,
        toEncodable: (value) => (value as WampSample).toWorkerRecord(),
      );
      final restored = (jsonDecode(wire) as List)
          .cast<List<Object?>>()
          .map(WampSample.fromWorkerRecord)
          .toList(growable: false);
      expect(restored, hasLength(originals.length));
      expect(jsonEncode(restored), jsonEncode(originals));
      expect(
        WampSampleWindow.fromSamples(restored)!.toJson(),
        WampSampleWindow.fromSamples(originals)!.toJson(),
      );
    });

    test(
      'JSON projection is read only while public snapshots remain mutable',
      () {
        final sample = WampSample.fromJson(named);
        final projection = wampSamplesForJsonEncoding([sample]);
        final list = (projection as dynamic).toJson() as List<Object>;
        final map = list.single as Map<String, Object?>;
        expect(map, named);
        expect(map.keys, orderedEquals(named.keys));
        expect(map.length, named.length);
        expect(map.isEmpty, isFalse);
        expect(map['unknown'], isNull);
        final Object nonStringKey = 7;
        expect(map[nonStringKey], isNull);
        expect(() => map['worker'] = 99, throwsUnsupportedError);
        expect(map.clear, throwsUnsupportedError);
        expect(() => map.remove('worker'), throwsUnsupportedError);
        expect(() => list[0] = Object(), throwsUnsupportedError);
        expect(() => list.length = 0, throwsUnsupportedError);
        sample.toJson()['worker'] = 99;
        expect(map['worker'], named['worker']);
        expect(jsonEncode(projection), jsonEncode([named]));
        expect(jsonEncode(wampSamplesForJsonEncoding([])), '[]');
      },
    );

    test(
      'worker JSON view preserves row length, nulls and read-only ownership',
      () {
        final sample = WampSample.fromJson(named);
        final view = wampSampleWorkerRecordForJsonEncoding(sample);
        expect(view, positional);
        expect(view.length, 13);
        expect(() => view[-1], throwsRangeError);
        expect(() => view[13], throwsRangeError);
        expect(() => view[0] = 99, throwsUnsupportedError);
        expect(() => view.length = 0, throwsUnsupportedError);
        sample.toWorkerRecord()[0] = 99;
        expect(view[0], named['worker']);
      },
    );

    test('both JSON projections reject nonfinite model numbers', () {
      for (final number in [double.nan, double.infinity, -double.infinity]) {
        final sample = WampSample(
          worker: 0,
          iteration: 0,
          latencyMs: number,
          requestBytes: 0,
          responseBytes: 0,
        );
        for (final projection in [
          wampSamplesForJsonEncoding([sample]),
          wampSampleWorkerRecordForJsonEncoding(sample),
        ]) {
          expect(
            () => jsonEncode(projection),
            throwsA(isA<JsonUnsupportedObjectError>()),
          );
          expect(
            () => JsonUtf8Encoder().convert(projection),
            throwsA(isA<JsonUnsupportedObjectError>()),
          );
        }
      }
    });

    test('JSON projection preserves null omission and numeric spelling', () {
      final fields = <String, Object?>{
        ...named,
        for (final key in named.keys.skip(5)) key: null,
      };
      final sample = WampSample.fromJson(fields);
      expect(
        jsonEncode(wampSamplesForJsonEncoding([sample])),
        jsonEncode([sample.toJson()]),
      );
      for (final latency in [-1.0, 0.0, -0.0, 1e-100, 1e100]) {
        final sample = WampSample.fromJson({...named, 'latency_ms': latency});
        expect(
          jsonEncode(wampSamplesForJsonEncoding([sample])),
          jsonEncode([sample.toJson()]),
        );
      }
    });

    test(
      'HTTP response models cross an isolate and retain named JSON bytes',
      () async {
        final samples = List.generate(
          2048,
          (index) => WampSample.fromJson({
            ...named,
            'iteration': index,
          }),
        );
        for (final model in <Object>[
          samples,
          wampSamplesForJsonEncoding(samples),
        ]) {
          final payload = HttpResponseUtil.json(
            requestId: 71,
            status: 200,
            body: {'samples': model},
          );
          final bytes = await _encodeHttpResponseInIsolate(
            payload.toKeywordArguments(),
          );
          expect(
            utf8.decode(bytes),
            jsonEncode({
              'samples': samples.map((sample) => sample.toJson()).toList(),
            }),
          );
        }
      },
    );
  });

  group('sample JSON boundary', () {
    test('numeric JSON spellings preserve all values and timing units', () {
      final sample = WampSample.fromJson(
        jsonDecode('''{
          "worker": 3.0,
          "iteration": 7.0,
          "latency_ms": 5,
          "request_bytes": 4294967296.0,
          "response_bytes": 4294967297.0,
          "started_at_us": 1000000.0,
          "completed_at_us": 1005000.0
        }''')
            as Map<String, Object?>,
      );
      expect(sample.worker, 3);
      expect(sample.iteration, 7);
      expect(sample.latencyMs, 5.0);
      expect(sample.requestBytes, 4294967296);
      expect(sample.responseBytes, 4294967297);
      expect(sample.startedAtUs, 1000000);
      expect(sample.completedAtUs, 1005000);
      expect(sample.toJson(), {
        'worker': 3,
        'iteration': 7,
        'latency_ms': 5.0,
        'request_bytes': 4294967296,
        'response_bytes': 4294967297,
        'started_at_us': 1000000,
        'completed_at_us': 1005000,
      });
    });

    for (final field in [
      'worker',
      'iteration',
      'latency_ms',
      'request_bytes',
      'response_bytes',
    ]) {
      for (final value in <Object?>[null, '1', true, [], {}]) {
        test('rejects $field=$value without coercing non-numbers', () {
          expect(
            () => WampSample.fromJson({..._json(), field: value}),
            throwsFormatException,
          );
        });
      }
      test('requires $field', () {
        final json = _json()..remove(field);
        expect(() => WampSample.fromJson(json), throwsFormatException);
      });
    }

    for (final field in ['started_at_us', 'completed_at_us']) {
      for (final value in <Object>['1', false, [], {}]) {
        test('rejects malformed optional $field=$value', () {
          expect(
            () => WampSample.fromJson({..._json(), field: value}),
            throwsFormatException,
          );
        });
      }
      test('preserves one-sided $field without inventing the other bound', () {
        final json = {..._json(), field: 1234};
        expect(WampSample.fromJson(json).toJson(), json);
      });
    }

    test('explicit null bounds are omitted and maps do not alias samples', () {
      final json = {
        ..._json(),
        'started_at_us': null,
        'completed_at_us': null,
      };
      final sample = WampSample.fromJson(json);
      json['worker'] = 99;
      final encoded = sample.toJson();
      expect(encoded, _json());
      encoded['request_bytes'] = 99;
      expect(sample.worker, 2);
      expect(sample.requestBytes, 23);
      expect(sample.toJson(), _json());
    });
  });

  group('sample timing boundaries', () {
    for (final latency in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('non-finite latency $latency cannot invent a measured span', () {
        final sample = WampSample(
          worker: 2,
          iteration: 4,
          latencyMs: latency,
          requestBytes: 23,
          responseBytes: 41,
        );
        expect(sample.startedAtUs, isNull);
        expect(sample.completedAtUs, isNull);
        expect(sample.toJson(), isNot(contains('started_at_us')));
        expect(sample.toJson(), isNot(contains('completed_at_us')));
        expect(WampSampleWindow.fromSamples([sample]), isNull);
      });
    }

    test('zero latency still has a valid, zero-length measured window', () {
      final sample = WampSample(
        worker: 0,
        iteration: 0,
        latencyMs: 0,
        requestBytes: 0,
        responseBytes: 0,
      );
      expect(sample.startedAtUs, isNotNull);
      expect(sample.startedAtUs, sample.completedAtUs);
      final window = WampSampleWindow.fromSamples([sample]);
      expect(window, isNotNull);
      expect(window!.elapsedMs, 0.0);
    });

    test('empty samples have no measured window', () {
      expect(WampSampleWindow.fromSamples([]), isNull);
    });

    test('unordered and nested samples use the outer wall-clock span', () {
      final samples = [
        _sample(4000, 7000),
        _sample(2000, 8000),
        _sample(3000, 5000),
        _sample(1000, 6000),
      ];
      for (final ordered in [samples, samples.reversed]) {
        final window = WampSampleWindow.fromSamples(ordered);
        expect(window, isNotNull);
        expect(window!.toJson(), {
          'started_at_us': 1000,
          'completed_at_us': 8000,
        });
        expect(window.elapsedMs, 7.0);
      }
    });

    test('incomplete samples cannot extend a valid measured window', () {
      final window = WampSampleWindow.fromSamples([
        _sample(0, null),
        _sample(null, 1000000),
        _sample(1000, 2500),
        _sample(9999, 9),
      ]);
      expect(window, isNotNull);
      expect(window!.startedAtUs, 1000);
      expect(window.completedAtUs, 2500);
      expect(window.elapsedMs, 1.5);
    });

    test('all incomplete samples provide no measured window', () {
      expect(
        WampSampleWindow.fromSamples([_sample(0, null), _sample(null, 9)]),
        isNull,
      );
    });
  });
}

Future<Uint8List> _encodeHttpResponseInIsolate(Map<String, Object?> kwargs) =>
    Isolate.run(
      () =>
          HttpResponsePayload.fromKeywordArguments(kwargs)!.encodeBodyBytes()!,
    );

Map<String, Object?> _json() => {
  'worker': 2,
  'iteration': 4,
  'latency_ms': 1.5,
  'request_bytes': 23,
  'response_bytes': 41,
};

WampSample _sample(int? start, int? end) => WampSample.fromJson({
  ..._json(),
  'started_at_us': start,
  'completed_at_us': end,
});
