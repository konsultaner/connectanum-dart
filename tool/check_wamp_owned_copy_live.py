#!/usr/bin/env python3
"""Renew real owned-copy proofs with production binaries; never timing acceptance."""
import argparse
from collections import Counter
from contextlib import ExitStack, redirect_stderr, redirect_stdout
import itertools
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import threading
import urllib.request

import probe_native_ppt_views as lifetime
import run_wamp_serializer_campaign as campaign
import wamp_serializer_compare as compare
import wamp_serializer_extensions as extensions
from merge_wamp_extension_campaigns import verify_raw_rows

ROOT = Path(__file__).resolve().parents[1]
KIND = 'production_owned_copy_correctness_never_performance_acceptance'
LOCKS = ('pubspec.lock', 'native/bench/Cargo.lock', 'native/transport/Cargo.lock')
RESOLVED_INPUTS = (*LOCKS, '.dart_tool/package_config.json')


def owned_groups():
    """The original 72 + 32 + 16 live proof cases, with unchanged inputs."""
    expanded = []
    for impl, cipher, ws, secure, file in itertools.product(
            ('dart', 'native'), ('xsalsa20poly1305', 'aes256gcm'),
            (False, True), (False, True), (False, True)):
        expanded.append(dict(transport='websocket' if ws else 'rawsocket',
            serializer='flatbuffers', peer_serializer='cbor', client_impl=impl,
            secure_transport=secure, mode='file_transfer' if file else 'rpc',
            uri='bench.rpc.echo', iterations=2, concurrency=1, payload_bytes=65536,
            file_chunk_bytes=8192, ppt_scheme='wamp', ppt_serializer='cbor',
            ppt_cipher=cipher, ppt_keyid='bench-key'))
    for impl, cipher, ws, secure in itertools.product(
            ('dart', 'native'), ('xsalsa20poly1305', 'aes256gcm'), (False, True), (False, True)):
        expanded.append(dict(transport='websocket' if ws else 'rawsocket',
            serializer='flatbuffers', peer_serializer='cbor', client_impl=impl,
            secure_transport=secure, mode='rpc', uri='bench.rpc.echo', iterations=2,
            concurrency=1, payload_bytes=65536, ppt_scheme='wamp',
            ppt_serializer='flatbuffers', ppt_cipher=cipher, ppt_keyid='bench-key'))
    for impl, peer, ws, secure in itertools.product(
            ('dart', 'native'), ('json', 'msgpack', 'cbor'), (False, True), (False, True)):
        expanded.append(dict(transport='websocket' if ws else 'rawsocket',
            serializer='flatbuffers', peer_serializer=peer, client_impl=impl,
            secure_transport=secure, mode='rpc', uri='bench.rpc.echo', iterations=2,
            concurrency=1, payload_bytes=65536, ppt_scheme='x_connectanum_bench_typed',
            ppt_serializer='flatbuffers'))
    def derived(serializer, modes):
        return [{**case, 'mode': mode,
                 'uri': 'bench.topic.copy' if mode == 'pubsub' else 'bench.rpc.echo'}
                for case in expanded if case['ppt_scheme'] == 'wamp'
                and case['ppt_serializer'] == serializer and case['mode'] == 'rpc'
                for mode in modes]
    return {'expanded': expanded,
            'cbor_pubsub_progressive': derived('cbor', ('pubsub', 'progressive_rpc')),
            'typed_pubsub': derived('flatbuffers', ('pubsub',))}


def validate_row(report, *, e2ee, transcode, native_crypto=False, zero_copy=False):
    """Use the existing independent accounting validators, without timing claims."""
    if not isinstance(report, dict) or not isinstance(report.get('samples'), list) or len(report['samples']) < 2:
        raise ValueError('missing completed correctness observations')
    copies = report.get('copy_metrics')
    if not isinstance(copies, dict):
        raise ValueError('missing owned copy observations')
    findings = compare._encoded_wamp_volume_findings(copies.get('encoded_wamp_volume'), 'live copy proof')
    counts = Counter(rows=1, encoded_volume=1)
    for kind, active in (('e2ee', e2ee), ('transcode', transcode)):
        if active:
            findings.extend(compare._owned_pipeline_findings(report, kind, label='live copy proof'))
            counts[kind] += 1
    if native_crypto:
        native = copies.get('native_crypto_copy_breakdown', {})
        component = copies.get('e2ee_copy_breakdown', {}).get('components', {}).get('native_crypto')
        if native.get('active') is not True or type(component) is not int or component <= 0:
            findings.append('missing active native crypto contribution')
        counts['native_crypto'] += 1
    if copies.get('measurement_scope') != compare.COPY_MEASUREMENT_SCOPE:
        findings.append('unsupported owned-copy measurement scope')
    if zero_copy:
        try:
            if report.get('client_impl') != 'native':
                raise ValueError('zero-copy proof requires its declared native path')
            for side in ('client', 'router'):
                compare._owned_codec(copies['native_codec_copy_breakdown'][side], side)
                compare._owned_component(copies['raw_frame_copy_breakdown'][side],
                    compare.RAW_FRAME_COPY_FIELDS, side, requests=compare.RAW_FRAME_REQUEST_FIELDS)
            compare._owned_dart(copies['dart_owned_buffer_copy_breakdown']['client'], 'client')
            compare._owned_router_dart(copies['dart_owned_buffer_copy_breakdown']['router'])
            compare._owned_transport(copies, True, report['protocol'].startswith('wamp_websocket_'))
        except (ValueError, KeyError, TypeError) as error:
            findings.append('incomplete zero-copy instrumentation: ' + str(error))
        if type(copies.get('optimized_payload_copy_bytes')) is not int or copies['optimized_payload_copy_bytes'] != 0:
            findings.append('avoidable native payload copies are not zero')
        counts['zero_avoidable_payload_copy'] += 1
    if findings:
        raise ValueError('; '.join(findings))
    return counts


def production_exports(library):
    flags = ['-D', '--defined-only'] if sys.platform.startswith('linux') else ['-g']
    exports = subprocess.check_output(['nm', *flags, str(library)], text=True)
    symbols = {line.split()[-1].lstrip('_') for line in exports.splitlines() if line.split()}
    if not any(symbol.startswith('ct_') for symbol in symbols):
        raise ValueError('production library has no observable public C API')
    if any(symbol.startswith('ct_test_') for symbol in symbols):
        raise ValueError('copy proofs require a production library without test oracles')
    return exports


def private_router(root, output):
    config = json.loads((root / 'native/bench/bench_router.json').read_text())
    ports = []
    with ExitStack() as reservations:
        for listener in config['router']['listeners']:
            sock = reservations.enter_context(socket.socket())
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
            ports.append(port)
            listener['endpoint'] = f'127.0.0.1:{port}'
            if 'http3' in listener['protocols']:
                listener['protocols'].remove('http3')
                listener['http'].pop('http3', None)
    path = output / 'router.json'
    path.write_text(json.dumps(config, indent=2) + '\n')
    return path, f'https://127.0.0.1:{ports[0]}/bench'


def run_group(root, output, library, dart, router, control, cases):
    output.mkdir()
    process = subprocess.Popen([dart, 'run', 'packages/connectanum_bench/tool/bench_main.dart',
                                '--router-config', str(router)], cwd=root,
        env={**os.environ, 'CONNECTANUM_SKIP_NATIVE_BUILD': '1',
             'CONNECTANUM_BENCH_WAMP_REUSE_WORKER': '1', 'CONNECTANUM_NATIVE_LIB': str(library)},
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, start_new_session=True)
    ready = threading.Event()
    reader_errors = []
    def read():
        try:
            with (output / 'server.log').open('w') as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    if line.strip().endswith('READY'):
                        ready.set()
        except Exception as error:
            reader_errors.append(str(error))
    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    counts = Counter()
    try:
        if not ready.wait(60):
            raise RuntimeError('copy proof server did not become ready')
        context = ssl.create_default_context(cafile=str(root / 'native/bench/bench_tls.crt'))
        with (output / 'reports.jsonl').open('w') as reports:
            for case in cases:
                request = urllib.request.Request(control + '/wamp', data=json.dumps(case).encode(),
                                                 headers={'content-type': 'application/json'})
                with urllib.request.urlopen(request, context=context, timeout=90) as response:
                    report = json.load(response)
                report.update(protocol=f'wamp_{case["transport"]}_{case["mode"]}',
                              client_impl=case['client_impl'], wamp_configuration=case)
                reports.write(json.dumps(report) + '\n')
                reports.flush()
                counts.update(validate_row(report, e2ee=case['ppt_scheme'] == 'wamp',
                    transcode=True, native_crypto=case['ppt_scheme'] == 'wamp' and case['client_impl'] == 'native'))
    finally:
        try:
            if process.poll() is None:
                process.stdin.write('stop\n')
                process.stdin.flush()
                process.wait(timeout=30)
        except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
            pass
        finally:
            try:
                process.stdin.close()
            except OSError:
                pass
            stopped = campaign.stop_process_group(process)
            reader.join(timeout=5)
            if not reader.is_alive():
                process.stdout.close()
            cleanup = {'pid': process.pid, 'exit_code': process.returncode,
                       'process_group_stopped': stopped, 'reader_stopped': not reader.is_alive(),
                       'reader_errors': reader_errors}
            (output / 'cleanup.json').write_text(json.dumps(cleanup, indent=2) + '\n')
        if process.returncode != 0 or not stopped or reader.is_alive() or reader_errors:
            raise RuntimeError('copy proof process cleanup failed: ' + json.dumps(cleanup))
    return {'name': output.name, 'counts': dict(counts), 'cleanup': cleanup,
            'raw_sha256': lifetime.digest(output / 'reports.jsonl')}


def run_short_batches(root, output, library, driver, dart, router, control):
    audits, counts = [], Counter()
    for shard in extensions.SHARDS:
        child = output / shard
        child.mkdir()
        command = [
            '--extension-diagnostics', '--diagnostic', '--extension-shard', shard,
            '--output', str(child / 'campaign'), '--driver', str(driver), '--dart', dart,
            '--native-lib', str(library), '--router-config', str(router), '--control-base', control,
            '--runner-image', 'short-production-copy-correctness-never-performance',
            '--warmups', '1', '--repetitions', '1', '--duration-ms', '50', '--samples', '2',
            '--workload-timeout-ms', '60000', '--campaign-timeout-seconds', '1200']
        # Run the existing controller directly so its timeout/finally retains
        # ownership of the driver process group; don't kill an outer controller
        # with subprocess.run(timeout=...), which could orphan the driver.
        previous_skip = os.environ.get('CONNECTANUM_SKIP_NATIVE_BUILD')
        try:
            os.environ['CONNECTANUM_SKIP_NATIVE_BUILD'] = '1'
            with (child / 'runner.log').open('w') as log, redirect_stdout(log), redirect_stderr(log):
                exit_code = campaign.main(command)
        finally:
            if previous_skip is None:
                os.environ.pop('CONNECTANUM_SKIP_NATIVE_BUILD', None)
            else:
                os.environ['CONNECTANUM_SKIP_NATIVE_BUILD'] = previous_skip
        p = child / 'campaign'
        if exit_code != 2:
            raise ValueError('incomplete short correctness campaign, or unexpected timing acceptance')
        manifest = json.loads((p / 'manifest.json').read_text())
        policy = json.loads((root / 'native/bench/artifact_gate/wamp_flatbuffers_performance.json').read_text())
        expected_rejection = f"Campaign incomplete or invalid: campaign requires at least {policy['minimum_warmup_runs']} warm-up runs"
        if (manifest['cases'] != extensions.cases_for_shard(shard)
                or manifest['metadata']['diagnostic_shard'] != shard
                or manifest['metadata']['diagnostic_inventory'] != extensions.INVENTORY
                or manifest['execution']['status'] != 'completed'
                or manifest['execution']['driver_exit_code'] != 0
                or manifest['execution']['process_group_stopped'] is not True
                or len(manifest['warmup_runs']) != 1 or len(manifest['measured_runs']) != 1
                or manifest['metadata']['inputs_unchanged'] is not True
                or manifest['metadata']['source_revision'] != subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
                or manifest['metadata']['policy_sha256'] != lifetime.digest(root / 'native/bench/artifact_gate/wamp_flatbuffers_performance.json')
                or manifest['metadata']['artifacts_sha256'] != {'driver': lifetime.digest(driver), 'native_library': lifetime.digest(library)}
                or (p / 'comparison-error.txt').read_text().strip() != expected_rejection):
            raise ValueError('incomplete short correctness campaign, or unexpected timing acceptance')
        lookup = {name: (case, codec) for case in manifest['cases'] for codec, name in case['workloads'].items()}
        observed, local, pids = Counter(), Counter(), {key: set() for key in ('client_process_metrics', 'server_process_metrics')}
        for line in (p / 'driver-results.jsonl').read_text().splitlines():
            row = json.loads(line)
            case, codec = lookup[row['workload']]
            if (extensions.configuration_findings(row, case, codec, label='short live proof')
                    or len(row['samples']) < 2 or row['data_window_elapsed_ms'] < 50):
                raise ValueError('short correctness row has wrong configuration or sample floor')
            observed[row['workload']] += 1
            for key in pids:
                pid = row[key]['pid']
                if type(pid) is not int or pid <= 0:
                    raise ValueError('missing observed worker identity')
                pids[key].add(pid)
            encrypted = bool(case['fields'].get('ppt_cipher'))
            local.update(validate_row(row, e2ee=encrypted,
                transcode=bool(row['wamp_configuration']['peer_serializer'] and row['wamp_configuration']['peer_serializer'] != codec),
                native_crypto=encrypted and case['client_impl'] == 'native',
                zero_copy=codec in case.get('zero_copy_codecs', [])))
        if verify_raw_rows(p, manifest) != len(lookup) * 2:
            raise ValueError('raw correctness stream differs from its completed pass records')
        if observed != Counter({name: 2 for name in lookup}) or any(len(v) != 1 for v in pids.values()) or pids['client_process_metrics'] == pids['server_process_metrics']:
            raise ValueError('missing/duplicate correctness rows or unstable/shared workers')
        counts.update(local)
        audits.append({'name': shard, 'counts': dict(local), 'runner_exit': exit_code,
                       'stable_pids': {key: next(iter(value)) for key, value in pids.items()},
                       'raw_sha256': lifetime.digest(p / 'driver-results.jsonl')})
    if counts != Counter(rows=300, encoded_volume=300, e2ee=96, native_crypto=72,
                         transcode=60, zero_avoidable_payload_copy=32):
        raise ValueError('short correctness copy inventory changed')
    return {'counts': dict(counts), 'batches': audits}


def run(args, root=ROOT):
    root, output = root.resolve(), args.output.resolve()
    library, driver = args.native_lib.resolve(), args.driver.resolve()
    if output.exists() or output == root or output in root.parents or not library.is_file() or not driver.is_file():
        raise ValueError('requires a new output directory and existing production binaries')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip():
        raise ValueError('copy proof requires a clean source checkout')
    with lifetime.resource_lease(args.resource_lock):
        lifetime.verify_package_roots(root)
        output.mkdir(parents=True)
        source = lifetime.snapshot(root)
        source.update({name: lifetime.digest(root / name) for name in RESOLVED_INPUTS})
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
        artifacts = {str(path): lifetime.digest(path) for path in (library, driver)}
        groups = owned_groups()
        inputs = {'kind': KIND, 'head': head, 'source_inputs': source, 'artifacts_sha256': artifacts,
                  'groups': groups, 'short_inventory': extensions.INVENTORY,
                  'dart_version': subprocess.check_output([args.dart, '--version'], text=True).strip(),
                  'scope': 'Connectanum-owned copies; dependency internals retain explicit measurement labels'}
        (output / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
        result = {'kind': KIND, 'head': head, 'status': 'failed', 'owned_groups': [],
                  'limitations': ['120 two-operation live cases and 300 short inventory rows',
                                  'short runs MUST fail the unchanged timing policy',
                                  'does not establish performance, allocation, GC or RSS acceptance']}
        try:
            (output / 'native-exports.txt').write_text(production_exports(library))
            router, control = private_router(root, output)
            for name, cases in groups.items():
                result['owned_groups'].append(run_group(root, output / name, library, args.dart, router, control, cases))
            counts = sum((Counter(item['counts']) for item in result['owned_groups']), Counter())
            if counts != Counter(rows=120, encoded_volume=120, e2ee=96, native_crypto=48, transcode=120):
                raise ValueError('live owned-copy inventory changed')
            result['owned_counts'] = dict(counts)
            result['short_inventory'] = run_short_batches(root, output, library, driver, args.dart, router, control)
            result['status'] = 'copy_correctness_complete_not_performance_acceptance'
        except Exception as error:
            result['error'] = f'{type(error).__name__}: {error}'
        finally:
            after = lifetime.snapshot(root)
            after.update({name: lifetime.digest(root / name) for name in RESOLVED_INPUTS})
            result['source_inputs_unchanged'] = after == source and head == subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
            result['binaries_unchanged'] = all(path.is_file() and lifetime.digest(path) == digest for name, digest in artifacts.items() for path in (Path(name),))
            if not result['source_inputs_unchanged'] or not result['binaries_unchanged']:
                result['status'] = 'failed'
            (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result), flush=True)
        return 0 if result['status'] == 'copy_correctness_complete_not_performance_acceptance' else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--native-lib', required=True, type=Path)
    parser.add_argument('--driver', required=True, type=Path)
    parser.add_argument('--resource-lock', required=True, type=Path)
    parser.add_argument('--dart', default='dart')
    return run(parser.parse_args(argv))


if __name__ == '__main__':
    raise SystemExit(main())
