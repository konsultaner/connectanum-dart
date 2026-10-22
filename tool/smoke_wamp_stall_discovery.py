#!/usr/bin/env python3
"""Exercise original-process discovery with a real authenticated Linux Dart VM."""
import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
import urllib.parse

import capture_wamp_stall as diagnostic

ROOT = Path(__file__).resolve().parents[1]


def stop(process):
    if process is None:
        return
    if process.stdin is not None and not process.stdin.closed:
        try:
            process.stdin.close()
        except OSError:
            pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--dart', default='dart')
    args = parser.parse_args()
    if not Path('/proc').is_dir():
        raise ValueError('Real original-process discovery smoke requires Linux procfs')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    script = output / 'idle.dart'
    script.write_text("import 'dart:io';\nFuture<void> main() async { stdout.writeln('READY'); await stdin.drain<void>(); }\n")
    vm = observer = None
    readers = []
    lines = queue.Queue()
    def read(process, role):
        with process.stdout as stream:
            for line in stream:
                lines.put((role, line.rstrip()))
    def launch(command, role):
        process = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True)
        reader = threading.Thread(target=read, args=(process, role), daemon=True)
        reader.start()
        readers.append(reader)
        return process
    def next_line(deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Smoke VM/observer readiness deadline expired')
        return lines.get(timeout=remaining)
    try:
        vm = launch([args.dart, '--observe=0/127.0.0.1', '--no-pause-isolates-on-exit', str(script)], 'vm')
        deadline = time.monotonic() + 45
        uri = None
        while uri is None:
            role, line = next_line(deadline)
            prefix = 'The Dart VM service is listening on '
            if line.startswith(prefix):
                uri = line[len(prefix):].strip()
        observer = launch([args.dart, '--packages=' + str(ROOT / '.dart_tool/package_config.json'),
                           str(ROOT / 'packages/connectanum_bench/lib/src/dart_vm_metrics_observer_main.dart'),
                           json.dumps({'service_uri': uri, 'pid': vm.pid, 'all_isolates': False})], 'observer')
        while True:
            role, line = next_line(deadline)
            if role == 'observer' and line == 'READY':
                break
            if observer.poll() is not None:
                raise RuntimeError('Metrics observer exited before readiness')
        snapshot = diagnostic.capture_original_stacks(os.getpid(), 'real discovery smoke', threading.Event())
        worker = snapshot['roles'].get('worker', {})
        if (worker.get('pid') != vm.pid or worker.get('observer_pid') != observer.pid or worker.get('error')
                or not worker.get('isolates') or any('stack' not in entry for entry in worker['isolates'])):
            raise RuntimeError('Original-process discovery or stack capture failed: ' + json.dumps(snapshot))
        native = worker.get('linux', {})
        if native.get('error') or native.get('errors') or not native.get('threads') or not native.get('tcp'):
            raise RuntimeError('Owned Linux thread/socket observation failed: ' + json.dumps(native))
        token = urllib.parse.urlsplit(uri).path.strip('/')
        if uri in json.dumps(snapshot) or (token and token in json.dumps(snapshot)):
            raise RuntimeError('Authenticated VM endpoint was not redacted')
        (output / 'snapshot.json').write_text(json.dumps(snapshot, indent=2) + '\n')
        observer.stdin.write(json.dumps({'id': 1, 'command': 'close'}) + '\n')
        observer.stdin.flush()
        stop(observer)
        stop(vm)
        if observer.returncode != 0 or vm.returncode != 0:
            raise RuntimeError('Smoke VM/observer did not exit cleanly')
        print('Original-process VM discovery and authenticated stack capture passed; no benchmark acceptance.')
    finally:
        stop(observer)
        stop(vm)
        for reader in readers:
            reader.join(timeout=5)
        if any(reader.is_alive() for reader in readers):
            raise RuntimeError('Smoke output reader did not stop')


if __name__ == '__main__':
    main()
