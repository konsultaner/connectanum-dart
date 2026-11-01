#!/usr/bin/env python3
"""Pinned Mosquitto control for the MQTT leg, with its own process metrics."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from mqtt_gateway_paho_peer import Memory
import run_mqtt_benchmark_gate as reference


def run(config, lines, emit):
    executable = config['mosquitto']
    version = reference.mosquitto_version(executable)
    if version != 'mosquitto version 2.0.18' and not config['diagnostic_only']:
        raise ValueError('Mosquitto changed; a new matched baseline is required')
    port = reference.available_port()
    with tempfile.TemporaryDirectory() as temporary:
        path = Path(temporary) / 'mosquitto.conf'
        path.write_text(reference.mosquitto_config(port, config['transport']))
        broker = subprocess.Popen([executable, '-c', str(path)], stdout=subprocess.DEVNULL, stderr=sys.stderr)
        meter = None
        try:
            reference.wait_for_listener(port, broker)
            meter = Memory(read_rss=lambda: reference.process_metrics(broker.pid)[1])
            emit(dict(kind='ready', pid=broker.pid, port=port, version=version))
            for line in lines:
                command = json.loads(line)
                if command['op'] == 'begin':
                    meter.begin()
                    emit(dict(kind='armed', phase=command['phase']))
                elif command['op'] == 'sample':
                    emit(dict(kind='sampled', memory=meter.snapshot(), queues={}))
                elif command['op'] == 'close':
                    emit(dict(kind='closed', memory=meter.snapshot()))
                    return
                else:
                    raise ValueError('Unknown reference broker command')
        finally:
            if meter is not None:
                meter.close()
            reference.stop_broker(broker)


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2 or args[0] != 'server':
        raise ValueError('Expected server role and JSON profile')
    run(json.loads(args[1]), sys.stdin, lambda message: print(json.dumps(message), flush=True))


if __name__ == '__main__':
    main()
