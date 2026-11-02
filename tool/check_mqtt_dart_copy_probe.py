#!/usr/bin/env python3
"""Real-source original/instrumented Dart decoder controls; never gate data."""
import argparse
import json
from pathlib import Path
import subprocess

import mqtt_dart_copy_probe as probe

CONTROL = r"""
import 'dart:convert';
import 'dart:typed_data';
import 'package:connectanum_core/mqtt.dart';
@IMPORT@

const instrumented = @INSTRUMENTED@;
var seed = 0;
final results = <Map<String, Object>>[];
void require(bool value, String reason) {
  if (!value) throw StateError(reason);
}
void reset() { @RESET@ }
Map<String, dynamic> counts() => @COUNTS@;
void expectCount(String name, int expected) {
  if (instrumented) require(counts()[name] == expected, name);
}
void expectPositive(String name) {
  if (instrumented) require((counts()[name] as int) > 0, name);
}
void zero() {
  if (instrumented) require(counts().values.every((v) => v == 0), 'zero');
}
void equalBytes(Uint8List got, Uint8List want) {
  require(got.length == want.length, 'length');
  for (var i = 0; i < want.length; i++) {
    require(got[i] == want[i], 'full body byte ' + i.toString());
  }
}
(Uint8List, Uint8List) fresh(int length) {
  seed++;
  final body = Uint8List(length);
  for (var i = 0; i < length; i++) body[i] = (seed * 29 + i * 17 + (i ~/ 256)) & 255;
  if (length >= 8) ByteData.sublistView(body).setUint64(0, seed, Endian.little);
  final wire = MqttFrame(MqttPacketType.publish, flags: 0, body: body).encode();
  return (body, wire);
}
void done(String name) {
  results.add({'name': name, 'passed': true, 'counts': counts()});
}
void terminal(MqttFrameDecoder decoder, Uint8List wire) {
  var protocol = false;
  try { decoder.add(wire); } on MqttProtocolException { protocol = true; }
  require(protocol, 'protocol error required');
  var state = false;
  try { decoder.add(Uint8List(0)); } on StateError { state = true; }
  require(state, 'terminal decoder required');
}
void main(List<String> args) {
  seed = int.parse(args.single);
  reset();
  require(MqttFrameDecoder().add(Uint8List(0)).isEmpty, 'empty');
  zero();
  done('empty_input_zero_counter');

  final (body, wire) = fresh(128);
  reset();
  final decoder = MqttFrameDecoder();
  final frames = decoder.add(wire);
  require(frames.length == 1 && decoder.bufferedBytes == 0, 'complete');
  equalBytes(frames.single.body, body);
  expectCount('body_constructor_requests', 1);
  expectCount('body_constructor_requested_bytes', body.length);
  expectCount('body_copy_bytes', body.length);
  expectCount('nonempty_body_copy_requests', 1);
  expectCount('growth_constructor_requests', 0);
  expectCount('frames_completed', 1);
  expectCount('completed_body_bytes', body.length);
  expectCount('native_poll_copy_requests', 0);
  done('single_complete_positive_counter');

  final (one, first) = fresh(128);
  final (two, second) = fresh(128);
  final combined = Uint8List(first.length + second.length)
    ..setRange(0, first.length, first)
    ..setRange(first.length, first.length + second.length, second);
  reset();
  final both = MqttFrameDecoder(maxPacketSize: first.length).add(combined);
  require(both.length == 2, 'perpacket cap, not aggregate cap');
  equalBytes(both[0].body, one);
  equalBytes(both[1].body, two);
  expectCount('body_constructor_requests', 2);
  expectCount('body_copy_bytes', one.length + two.length);
  expectCount('frames_completed', 2);
  done('coalesced_packets_keep_perpacket_limit');

  final (partialBody, partialWire) = fresh(128);
  final split = partialWire.length - partialBody.length + 64;
  final partial = MqttFrameDecoder();
  reset();
  require(partial.add(Uint8List.sublistView(partialWire, 0, split)).isEmpty, 'partial');
  require(partial.bufferedBytes > 0, 'retained partial');
  require(partial.add(Uint8List(0)).isEmpty, 'empty while pending');
  final originalByte = partialWire[split - 1];
  partialWire[split - 1] ^= 255;
  final completed = partial.add(Uint8List.sublistView(partialWire, split));
  equalBytes(completed.single.body, partialBody);
  require(completed.single.body[63] == originalByte, 'input was copied before mutation');
  expectCount('body_constructor_requests', 1);
  expectCount('growth_constructor_requests', 0);
  expectCount('nonempty_body_copy_requests', 2);
  expectCount('body_copy_bytes', partialBody.length);
  require(partial.bufferedBytes == 0, 'cleared state');
  completed.single.body[0] ^= 255; // Owned frames remain mutable.
  final (nextBody, nextWire) = fresh(31);
  equalBytes(partial.add(nextWire).single.body, nextBody);
  done('fragment_resume_and_owned_mutation');

  final (largeBody, largeWire) = fresh(16384);
  final header = largeWire.length - largeBody.length;
  final growing = MqttFrameDecoder();
  reset();
  require(growing.add(Uint8List.sublistView(largeWire, 0, header)).isEmpty, 'header only');
  expectCount('body_copy_bytes', 0);
  var offset = header;
  final received = <MqttFrame>[];
  for (final requested in [17, 3000, 4000, 5000, largeBody.length]) {
    final end = offset + requested < largeWire.length ? offset + requested : largeWire.length;
    received.addAll(growing.add(Uint8List.sublistView(largeWire, offset, end)));
    offset = end;
  }
  require(received.length == 1 && offset == largeWire.length, 'fragment complete');
  equalBytes(received.single.body, largeBody);
  expectCount('body_constructor_requests', 1);
  expectCount('body_copy_bytes', largeBody.length);
  expectCount('completed_body_bytes', largeBody.length);
  expectCount('frames_completed', 1);
  expectCount('nonempty_frames_completed', 1);
  expectCount('body_constructor_requested_bytes', 4096);
  expectCount('growth_constructor_requests', 2);
  expectCount('growth_constructor_requested_bytes', 11113 + 16384);
  expectCount('nonempty_growth_copy_requests', 2);
  expectCount('growth_copy_bytes', 3017 + 7017);
  expectCount('nonempty_body_copy_requests', 5);
  require(growing.bufferedBytes == 0, 'growth state clear');
  done('real_fragment_growth');

  final ping = MqttFrame(MqttPacketType.pingreq, flags: 0, body: Uint8List(0)).encode();
  reset();
  final pingFrames = MqttFrameDecoder().add(ping);
  require(pingFrames.length == 1 && pingFrames.single.body.isEmpty, 'zero body');
  expectCount('body_constructor_requests', 1);
  expectCount('zero_body_constructor_requests', 1);
  expectCount('body_constructor_requested_bytes', 0);
  expectCount('nonempty_body_copy_requests', 0);
  expectCount('frames_completed', 1);
  expectCount('completed_body_bytes', 0);
  done('zero_length_constructor_not_zero_operations');

  final (atLimitBody, atLimitWire) = fresh(128);
  reset();
  equalBytes(MqttFrameDecoder(maxPacketSize: atLimitWire.length)
    .add(atLimitWire).single.body, atLimitBody);
  expectCount('body_constructor_requests', 1);
  done('exact_packet_limit');

  final (_, overLimitWire) = fresh(128);
  reset();
  terminal(MqttFrameDecoder(maxPacketSize: overLimitWire.length - 1), overLimitWire);
  zero();
  done('oversize_rejected_before_constructor');

  for (final entry in <String, List<int>>{
    'nonminimal_length': [0x30, 0x80, 0x00],
    'four_continuations': [0x30, 0x80, 0x80, 0x80, 0x80],
    'invalid_type': [0x00, 0x00],
    'invalid_flags': [0x11, 0x00],
  }.entries) {
    reset();
    terminal(MqttFrameDecoder(), Uint8List.fromList(entry.value));
    zero();
    done(entry.key);
  }
  print(jsonEncode({'passed': true, 'instrumented': instrumented,
    'nonce_domain': int.parse(args.single), 'controls': results}));
}
"""


def control_source(instrumented):
    edits = {
        "@IMPORT@": ("import 'package:connectanum_core/src/mqtt/dart_copy_census.dart';"
                     if instrumented else ""),
        "@INSTRUMENTED@": str(instrumented).lower(),
        "@RESET@": "MqttDartCopyCensus.initialize();" if instrumented else "",
        "@COUNTS@": ("Map<String, dynamic>.from(MqttDartCopyCensus.snapshot()['counts'] as Map)"
                    if instrumented else "<String, dynamic>{}"),
    }
    source = CONTROL
    for marker, value in edits.items():
        if marker not in source:
            raise ValueError("Missing control template marker")
        source = source.replace(marker, value)
    return source


def run_controls(output, lock_root, nonce_base=180000000):
    if not 0 <= nonce_base < 2**53 - 2000000:
        raise ValueError("Invalid disjoint preflight nonce range")
    if output.exists():
        raise ValueError("Never overwrite retained preflight results")
    output.mkdir(parents=True)
    reports = []
    for name, instrumented, nonce in [
        ("original", False, nonce_base), ("instrumented", True, nonce_base + 1000000)
    ]:
        directory = output / name
        shadow = probe.prepare(directory, lock_root, original=not instrumented)
        for label, command in [
            ("pub-get", ["dart", "pub", "get"]),
        ]:
            with (directory / (label + ".log")).open("w") as log:
                result = subprocess.run(command, cwd=shadow, stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                raise ValueError(name + " " + label + " failed; retain evidence")
        probe.verify_shadow(directory)
        probe.verify_workspace_packages(shadow)
        harness = directory / "controls.dart"
        harness.write_text(control_source(instrumented))
        command = ["dart", "--packages=" + str(shadow / ".dart_tool/package_config.json"),
                   str(harness), str(nonce)]
        with (directory / "controls.log").open("w") as log:
            result = subprocess.run(command, cwd=shadow, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise ValueError(name + " real Dart controls failed; retain evidence")
        text = (directory / "controls.log").read_text()
        report = json.loads(text.strip().splitlines()[-1])
        if (report["passed"] is not True or report["instrumented"] != instrumented or
                report["nonce_domain"] != nonce or len(report["controls"]) != 12 or
                not all(row["passed"] is True for row in report["controls"])):
            raise ValueError("Incomplete/wrong Dart control observations")
        probe.verify_shadow(directory)
        probe.verify_workspace_packages(shadow)
        (directory / "controls.json").write_text(json.dumps(report, indent=2) + "\n")
        reports.append(report)
    if ([r["name"] for r in reports[0]["controls"]] !=
            [r["name"] for r in reports[1]["controls"]]):
        raise ValueError("Original/instrumented control inventory differs")
    summary = {
        "source": probe.SOURCE, "preflight_passed": True, "controls_per_arm": 12,
        "disjoint_nonce_domains": [r["nonce_domain"] for r in reports],
        "source_archive_sha256": probe.ARCHIVE_SHA256, "capture_ready": False,
        "scope": "Real original/shadow decoder semantics, full bodies/errors/ownership and "
                 "counter controls only. Native polling integration/guard review remain "
                 "required before count-only capture. No benchmark or acceptance claim.",
    }
    (output / "completion.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--lock-root", type=Path, default=probe.ROOT)
    parser.add_argument("--nonce-base", type=int, default=180000000)
    args = parser.parse_args()
    print(json.dumps(run_controls(args.output, args.lock_root, args.nonce_base), indent=2))


if __name__ == "__main__":
    main()
