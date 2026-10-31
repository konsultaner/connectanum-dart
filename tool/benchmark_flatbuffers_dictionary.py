#!/usr/bin/env python3
"""Compare two fixed dictionary readers; component evidence, never parity."""
import argparse
import collections
import fcntl
import json
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import urllib.parse

import capture_wamp_stall as capture
import diagnose_wamp_rss as guards
import run_wamp_serializer_campaign as campaign
from dart_heap_allocation_evidence import allocation_evidence

ROOT = Path(__file__).resolve().parents[1]
CORE = 'packages/connectanum_core/lib/'
TARGETS = tuple(CORE + 'src/serializer/flatbuffers/' + name
                for name in ('frame.dart', 'message_projection.dart', 'wire_reader.dart',
                             'validation.dart'))
CBOR_SCANNER = CORE + 'src/serializer/flatbuffers/cbor_validation.dart'
SUITES = ('binding', 'validation', 'wire_writer', 'frame', 'message_reader',
          'metadata_roundtrip', 'fragments', 'copy_retention', 'metadata_access',
          'deferred_metadata', 'metadata_encoding', 'reader_cache', 'cbor_validation')


def prepare(root, output, baseline):
    if not re.fullmatch('[0-9a-f]{40}', baseline):
        raise ValueError('Component baseline must be an explicit full commit SHA')
    changed = subprocess.check_output(['git', 'diff', '--name-only', baseline, 'HEAD', '--', CORE], cwd=root, text=True).splitlines()
    allowed = (set(TARGETS[:2]), {TARGETS[0], TARGETS[2]}, set(TARGETS[:3]),
               {TARGETS[0], TARGETS[1], TARGETS[3]}, {TARGETS[3]}, set(TARGETS),
               {CBOR_SCANNER})
    if set(changed) not in allowed:
        raise ValueError('Component must isolate dictionary agreement/projection, sparse decoding or validation')
    config_path = root / '.dart_tool/package_config.json'
    original = json.loads(config_path.read_text())
    test = next(package for package in original['packages'] if package['name'] == 'test')
    test_root = urllib.parse.urljoin(config_path.as_uri(), test['rootUri'])
    runner = Path(urllib.parse.unquote(urllib.parse.urlparse(test_root).path)) / 'bin/test.dart'
    if not runner.is_file():
        raise ValueError('Resolved test runner is missing')
    template = ROOT / 'tool/flatbuffers_dictionary_component'
    for name in ('worker', 'controller', 'payload'):
        (output / (name + '.dart')).write_bytes((template / (name + '.dart.template')).read_bytes())
    for variant in ('baseline', 'candidate'):
        folder = output / variant
        library = folder / 'core/lib'
        shutil.copytree(root / CORE, library)
        if variant == 'baseline':
            for name in (*TARGETS, CBOR_SCANNER):
                (library / name.removeprefix(CORE)).write_bytes(
                    subprocess.check_output(['git', 'show', baseline + ':' + name], cwd=root))
        projection = library / 'src/serializer/flatbuffers/message_projection.dart'
        source = projection.read_text()
        if 'dictionaryPlanProbeVariant' in source:
            raise ValueError('Private variant marker already present')
        projection.write_text(source + f"\nconst dictionaryPlanProbeVariant = '{variant}';\n")
        config = json.loads(json.dumps(original))
        for package in config['packages']:
            package['rootUri'] = ((folder / 'core').as_uri() + '/' if package['name'] == 'connectanum_core'
                                  else urllib.parse.urljoin(config_path.as_uri(), package['rootUri']))
        (folder / 'package_config.json').write_text(json.dumps(config, indent=2) + '\n')
    imports = ["import 'dart:io';", "import 'dart:typed_data';", "import 'package:test/test.dart';",
               "import 'package:connectanum_core/connectanum_core.dart' as wamp;",
               "import 'package:connectanum_core/flatbuffers_serializer.dart' as fb;",
               f'import {json.dumps((output / "payload.dart").as_uri())} as componentFixture;',
               "import 'package:connectanum_core/src/serializer/flatbuffers/message_projection.dart' as probe;"]
    groups = []
    for index, name in enumerate(SUITES):
        path = root / 'packages/connectanum_core/test/serializer' / f'flatbuffers_{name}_test.dart'
        imports.append(f'import {json.dumps(path.as_uri())} as suite{index};')
        groups.append(f"group('{name}', suite{index}.main);")
    wrapper = '\n'.join(imports) + '''
void main() {
  test('actual private core variant is selected', () =>
    expect(probe.dictionaryPlanProbeVariant, Platform.environment['DICTIONARY_EXPECTED_VARIANT']));
  for (final shape in ['call', 'result']) {
    for (final opaque in [false, true]) {
      for (final length in [0, 1, 10240]) {
        test('component byte view $shape opaque=$opaque length=$length', () {
          final body = Uint8List.fromList(List.generate(length, (i) => (i * 31) & 255));
          final wamp.AbstractMessage message = shape == 'call'
              ? wamp.Call(7, 'com.example.echo',
                  options: opaque ? wamp.CallOptions(pptScheme: 'x_dictionary_probe', pptSerializer: 'flatbuffers') : null,
                  arguments: [body])
              : wamp.Result(7,
                  opaque ? wamp.ResultDetails(pptScheme: 'x_dictionary_probe', pptSerializer: 'flatbuffers') : wamp.ResultDetails(),
                  arguments: [body]);
          final codec = fb.Serializer();
          final frame = codec.serialize(message);
          final decoded = codec.deserialize(frame) as wamp.AbstractMessageWithPayload;
          final bytes = componentFixture.dictionaryComponentPayloadBytes(decoded);
          expect(bytes, body);
          if (opaque) {
            final offset = bytes.offsetInBytes - frame.offsetInBytes;
            expect(offset, greaterThanOrEqualTo(0));
            expect(offset + bytes.length, lessThanOrEqualTo(frame.length));
            if (length > 0) {
              frame[offset] = 255;
              expect(bytes[0], 255);
            }
          } else {
            expect(bytes, same(decoded.arguments!.single));
          }
        });
      }
    }
  }
  test('component rejects absent, nonbinary and multiple application vectors', () {
    for (final arguments in <List<dynamic>?>[null, [], [1], [Uint8List(1), Uint8List(1)]]) {
      expect(() => componentFixture.dictionaryComponentPayloadBytes(wamp.Result(1, wamp.ResultDetails(), arguments: arguments)), throwsStateError);
    }
  });
''' + '\n'.join(groups) + '\n}\n'
    (output / 'private-tests.dart').write_text(wrapper)
    return runner


def summarize(rows):
    groups = collections.defaultdict(list)
    wires = collections.defaultdict(set)
    for row in rows:
        info, work = row['info'], row['workload']
        if (info['shape'] not in ('result', 'call') or type(row['cycle']) is not int or not 0 <= row['cycle'] < 4
                or type(row['order_index']) is not int or not 0 <= row['order_index'] < 4
                or type(row['round']) is not int or not -1 <= row['round'] < 4
                or type(info['pid']) is not int or info['pid'] <= 0
                or type(work['elapsed_us']) is not int or type(work['checksum']) is not int
                or type(work['control']) is not bool):
            raise ValueError('Invalid component identity or round')
        key = (info['shape'], row['cycle'], row['order_index'])
        if (info['variant'] != ('baseline', 'candidate', 'candidate', 'baseline')[row['order_index']]
                or work['variant'] != info['variant'] or work['shape'] != info['shape']
                or info['payload_alias_verified'] is not True or work['count'] != 100000
                or work['checksum'] != 37 * work['count'] or work['elapsed_us'] <= 0
                or type(row['allocated_bytes']) is not int or row['allocated_bytes'] < 0
                or not re.fullmatch('[0-9a-f]{64}', info['wire_sha256'])):
            raise ValueError('Invalid component worker, bytes, or measurement')
        wires[info['shape']].add(info['wire_sha256'])
        if row['round'] >= 0:
            _, _, findings = allocation_evidence(
                {'pid': info['pid'], 'allocated_bytes_delta': row['allocated_bytes'],
                 'gc_count_delta': row['gc_count'], 'allocation_measurement': row['allocation_measurement']},
                observed_pids={info['pid']}, label='dictionary component')
            if findings:
                raise ValueError('; '.join(findings))
        groups[key].append(row)
    expected = {(shape, cycle, index) for shape in ('result', 'call') for cycle in range(4) for index in range(4)}
    if set(groups) != expected or any(len(group) != 5 or {row['round'] for row in group} != {-1, 0, 1, 2, 3} for group in groups.values()):
        raise ValueError('Missing or replayed component rounds/workers')
    if set(wires) != {'result', 'call'} or any(len(value) != 1 for value in wires.values()):
        raise ValueError('Baseline and candidate wire bytes differ')
    workers = {}
    for key, group in groups.items():
        if len({row['info']['pid'] for row in group}) != 1:
            raise ValueError('Worker process changed within component rounds')
        control = next(row for row in group if row['round'] == -1)
        if not control['workload']['control'] or any(row['workload']['control'] for row in group if row['round'] >= 0):
            raise ValueError('Invalid component control labels')
        measured = [row for row in group if row['round'] >= 0]
        workers[key] = {'us_per_decode': statistics.median(row['workload']['elapsed_us'] / 100000 for row in measured),
                        'managed_bytes_per_decode': statistics.median(row['allocated_bytes'] / 100000 for row in measured),
                        'control_allocated_bytes': control['allocated_bytes']}
    result = {}
    for shape in ('result', 'call'):
        pairs = []
        for cycle in range(4):
            for baseline_index, candidate_index in ((0, 1), (3, 2)):
                baseline, candidate = workers[(shape, cycle, baseline_index)], workers[(shape, cycle, candidate_index)]
                pairs.append({'cycle': cycle, 'baseline': baseline, 'candidate': candidate,
                              'elapsed_ratio': candidate['us_per_decode'] / baseline['us_per_decode']})
        result[shape] = {'worker_pairs': pairs, 'median_elapsed_ratio': statistics.median(pair['elapsed_ratio'] for pair in pairs),
                         'wire_sha256': next(iter(wires[shape]))}
    return result


def run(args):
    if platform.system() != 'Linux':
        raise ValueError('Run this component in an isolated Linux benchmark job')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip():
        raise ValueError('Component source must be committed and clean')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    sources = guards.source_inputs(ROOT)
    resolved = {name: campaign.sha256(ROOT / name) for name in guards.RESOLVED}
    for name in resolved:
        path = output / 'resolved-inputs' / name.replace('/', '__').lstrip('.')
        path.parent.mkdir(exist_ok=True)
        shutil.copyfile(ROOT / name, path)
    result = {'schema_version': 1, 'kind': 'dictionary_field_component_never_acceptance', 'primary_acceptance_eligible': False,
              'head': head, 'baseline': args.baseline_ref, 'source_inputs': sources, 'resolved_inputs': resolved,
              'scope': 'Actual RESULT/CALL model decoding with 10-KiB CBOR byte-vector args; balanced fresh workers, not transport/profile parity',
              'test_suites': list(SUITES), 'status': 'failed', 'tests': []}
    artifacts = {}
    process = None
    try:
        with campaign.LOCK.open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            runner = prepare(ROOT, output, args.baseline_ref)
            environment = {**os.environ, 'CONNECTANUM_NATIVE_LIB': str(args.native_lib.resolve(strict=True)),
                           'CONNECTANUM_SKIP_NATIVE_BUILD': '1'}
            paths = [path for path in output.rglob('*') if path.is_file() and path.suffix in ('.dart', '.json')]
            paths.append(args.native_lib.resolve())
            artifacts = {str(path): {'path': str(path), 'sha256': campaign.sha256(path)} for path in paths}
            for variant in ('baseline', 'candidate'):
                config = output / variant / 'package_config.json'
                with (output / variant / 'tests.log').open('w') as log:
                    check = subprocess.run([args.dart, '--packages=' + str(config), str(runner), str(output / 'private-tests.dart'),
                                            '--reporter', 'expanded', '--concurrency=1'], cwd=ROOT, env={**environment, 'DICTIONARY_EXPECTED_VARIANT': variant},
                                           stdout=log, stderr=subprocess.STDOUT, timeout=240)
                result['tests'].append({'variant': variant, 'exit_code': check.returncode})
                if check.returncode:
                    raise ValueError('Private functional regression suite failed')
                if guards.changed_inputs(ROOT, sources, resolved, artifacts, head):
                    raise ValueError('Private tests changed component source inputs')
                with (output / variant / 'compile.log').open('w') as log:
                    subprocess.run([args.dart, 'compile', 'kernel', '--packages=' + str(config), str(output / 'worker.dart'),
                                    '--output', str(output / variant / 'worker.dill')], cwd=ROOT, stdout=log,
                                   stderr=subprocess.STDOUT, check=True, timeout=120)
            with (output / 'controller-compile.log').open('w') as log:
                subprocess.run([args.dart, 'compile', 'kernel', str(output / 'controller.dart'), '--output', str(output / 'controller.dill')],
                               cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
            paths = [path for path in output.rglob('*') if path.is_file() and path.suffix in ('.dart', '.json', '.dill')]
            paths.append(args.native_lib.resolve())
            for path in paths:
                if str(path) not in artifacts:
                    artifacts[str(path)] = {'path': str(path), 'sha256': campaign.sha256(path)}
            result['private_artifacts'] = artifacts
            if guards.changed_inputs(ROOT, sources, resolved, artifacts, head):
                raise ValueError('Component inputs changed before measurement')
            with (output / 'observations.jsonl').open('w') as log, (output / 'controller.stderr.log').open('w') as errors:
                process = subprocess.Popen([args.dart, str(output / 'controller.dill'), str(output)], cwd=ROOT, env=environment,
                                           stdout=log, stderr=errors, start_new_session=True)
                result['controller_exit_code'] = process.wait(timeout=900)
            result['process_group_stopped'] = campaign.stop_process_group(process)
            process = None
            raw = (output / 'observations.jsonl').read_text()
            # Worker service URIs are removed by the controller. Sanitize failure
            # diagnostics too, before retaining any output as a public artifact.
            (output / 'observations.jsonl').write_text(capture.redact_debug_text(raw))
            if result['controller_exit_code'] or not result['process_group_stopped']:
                raise ValueError('Component controller or cleanup failed')
            rows = [json.loads(line) for line in raw.splitlines() if line.strip()]
            result['summary'] = summarize(rows)
            result['rows'] = len(rows)
            result['raw_sha256'] = campaign.sha256(output / 'observations.jsonl')
            result['status'] = 'diagnostic_complete_never_acceptance'
    except Exception as error:
        result['error'] = capture.redact_debug_text(str(error))
    finally:
        if process is not None:
            try:
                result['process_group_stopped'] = campaign.stop_process_group(process)
            except Exception as error:
                result['process_group_stopped'] = False
                result['cleanup_error'] = capture.redact_debug_text(str(error))
        raw = output / 'observations.jsonl'
        if raw.exists():
            raw.write_text(capture.redact_debug_text(raw.read_text(errors='replace')))
        for path in output.rglob('*.log'):
            path.write_text(capture.redact_debug_text(path.read_text(errors='replace')))
        result['changed'] = guards.changed_inputs(ROOT, sources, resolved, artifacts, head)
        if result['changed']:
            result['status'] = 'failed'
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result.get(key) for key in ('kind', 'status', 'rows', 'error', 'changed', 'summary')}))
    return int(result['status'] == 'failed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline-ref', required=True)
    parser.add_argument('--native-lib', type=Path, required=True)
    parser.add_argument('--dart', default='dart')
    raise SystemExit(run(parser.parse_args()))
