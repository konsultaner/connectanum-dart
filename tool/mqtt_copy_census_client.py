#!/usr/bin/env python3
"""Generate a fresh-body diagnostic client; the original MQTT gate is untouched.

The retained 3020 client reuses an application buffer/fixed tail pattern. It is
a provenance witness, never the client measured by this new count diagnostic.
"""
import argparse
import json
from pathlib import Path
import subprocess

import mqtt_dart_copy_probe as probe

CLIENT_SOURCE = "packages/connectanum_router/benchmark/mqtt_qos0.dart"
CLIENT_SOURCE_SHA256 = "7ceffe037cd9227a52500a6c287c0087561d9a4da99ca08092ec5df855170c15"
FRESH_FUNCTIONS = r'''
// Count-only diagnostic: no shared body/pattern cache. Each publication gets
// a fresh owned array keyed by its capture-row nonce and unique message ID.
int mqttCensusFreshWord(int nonce, int id, int block) {
  if (block == 1) return nonce;
  if (block == 2) return id;
  var word = (nonce ^ ((id + 1) * 0x9e3779b9) ^ (block * 0x85ebca6b)) & 0xffffffff;
  word = ((word ^ (word >>> 16)) * 0x7feb352d) & 0xffffffff;
  word = ((word ^ (word >>> 15)) * 0x846ca68b) & 0xffffffff;
  return (word ^ (word >>> 16)) & 0xffffffff;
}
Uint8List mqttCensusFreshBody(int nonce, int id, int size) {
  if (nonce < 1 || nonce > 0x7fffffff || id < 0 || id > 0xffffffff || size < 12) {
    throw ArgumentError('Invalid fresh diagnostic body domain');
  }
  final body = Uint8List(size);
  ByteData.sublistView(body).setUint32(0, id);
  var word = 0;
  for (var offset = 4; offset < size; offset++) {
    if ((offset & 3) == 0) word = mqttCensusFreshWord(nonce, id, offset >> 2);
    body[offset] = (word >>> ((3 - (offset & 3)) * 8)) & 0xff;
  }
  return body;
}
bool mqttCensusBodyMatches(Uint8List body, int nonce, int id) {
  if (body.length < 12 || ByteData.sublistView(body).getUint32(0) != id) return false;
  var word = 0;
  for (var offset = 4; offset < body.length; offset++) {
    if ((offset & 3) == 0) word = mqttCensusFreshWord(nonce, id, offset >> 2);
    if (body[offset] != ((word >>> ((3 - (offset & 3)) * 8)) & 0xff)) return false;
  }
  return true;
}
'''


def instrument(encoded):
    if probe.sha(encoded) != CLIENT_SOURCE_SHA256:
        raise ValueError("Original client source changed")
    text = encoded.decode()
    start = text.index("    final payload = Uint8List(payloadSize);\n")
    end = text.index("    final sentAt = Int64List(count);\n", start)
    text = text[:start] + '''    final bodyNonce = int.parse(
      Platform.environment['MQTT_COPY_CENSUS_BODY_NONCE'] ?? '');
    if (payloadSize < 12 || bodyNonce < 1 || bodyNonce > 0x7fffffff) {
      throw ArgumentError('Fresh body nonce and >=12 bytes required');
    }
    var generatedBodies = 0;
''' + text[end:]
    start = text.index("          for (var i = 4; i < payloadSize; i++) {\n")
    end = text.index("          if (id >= count) {\n", start)
    text = text[:start] + '''          final id = ByteData.sublistView(message.payload).getUint32(0);
          if (!mqttCensusBodyMatches(message.payload, bodyNonce, id)) {
            if (!completed.isCompleted) {
              completed.completeError(StateError('corrupt fresh payload'));
            }
            return;
          }
''' + text[end:]
    text = probe.replace_once(text, "        data.setUint32(0, count + index);\n",
        "        final payload = mqttCensusFreshBody(bodyNonce, count + index, payloadSize);\n"
        "        generatedBodies++;\n")
    text = probe.replace_once(text, "      data.setUint32(0, i);\n",
        "      final payload = mqttCensusFreshBody(bodyNonce, i, payloadSize);\n"
        "      generatedBodies++;\n")
    text = probe.replace_once(text, "        'duplicates': duplicate,\n",
        "        'duplicates': duplicate,\n"
        "        'fresh_body_nonce': bodyNonce,\n"
        "        'fresh_bodies_generated': generatedBodies,\n")
    return text.encode() + FRESH_FUNCTIONS.encode()


def write_client(shadow_source):
    path = shadow_source / ".dart_tool/mqtt-fresh-client.dart"
    if path.exists():
        raise ValueError("Never overwrite fresh client source")
    path.parent.mkdir(exist_ok=True)
    encoded = instrument((shadow_source / CLIENT_SOURCE).read_bytes())
    path.write_bytes(encoded)
    return path


SELFTEST = r'''
import 'dart:convert';
import 'mqtt-fresh-client.dart' as client;
void require(bool value, String why) { if (!value) throw StateError(why); }
void main() {
  var checks = 0;
  for (final size in [12, 13, 128, 65536]) {
    final first = client.mqttCensusFreshBody(190000001, 100, size);
    final second = client.mqttCensusFreshBody(190000001, 101, size);
    final otherRow = client.mqttCensusFreshBody(190000002, 100, size);
    require(!identical(first, second), 'new array per message');
    require(client.mqttCensusBodyMatches(first, 190000001, 100), 'entire first body');
    require(client.mqttCensusBodyMatches(second, 190000001, 101), 'entire second body');
    require(client.mqttCensusBodyMatches(otherRow, 190000002, 100), 'entire other row');
    require(!client.mqttCensusBodyMatches(first, 190000002, 100), 'nonce separation');
    require(!client.mqttCensusBodyMatches(first, 190000001, 101), 'ID separation');
    for (final offset in {0, 4, 8, size ~/ 2, size - 1}) {
      first[offset] ^= 1;
      require(!client.mqttCensusBodyMatches(first, 190000001, 100), 'mutation detected');
      require(client.mqttCensusBodyMatches(second, 190000001, 101), 'independent ownership');
      first[offset] ^= 1;
    }
    checks++;
  }
  print(jsonEncode({'fresh_body_controls': checks, 'full_body': true, 'nonce_domain': 190000000}));
}
'''


def check(output, lock_root):
    source = probe.prepare(output / "original", lock_root, original=True)
    with (output / "pub.log").open("w") as stream:
        subprocess.run(["dart", "pub", "get", "--enforce-lockfile"], cwd=source,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
    client = write_client(source)
    test = source / ".dart_tool/mqtt-fresh-client-test.dart"
    test.write_text(SELFTEST)
    result = subprocess.run(["dart", "run", str(test)], cwd=source,
                            capture_output=True, text=True)
    (output / "stdout.log").write_text(result.stdout)
    (output / "stderr.log").write_text(result.stderr)
    if result.returncode:
        raise ValueError("Actual fresh body source controls failed")
    row = json.loads(result.stdout.strip().splitlines()[-1])
    if row != {"fresh_body_controls": 4, "full_body": True, "nonce_domain": 190000000}:
        raise ValueError("Actual fresh body controls missing")
    if client.read_bytes() != instrument((source / CLIENT_SOURCE).read_bytes()):
        raise ValueError("Fresh client source changed")
    probe.verify_shadow(output / "original")
    probe.verify_workspace_packages(source)
    (output / "completion.json").write_text(json.dumps({
        "complete": True, "source": probe.SOURCE, "original_client_sha256": CLIENT_SOURCE_SHA256,
        "generated_client_sha256": probe.sha(client.read_bytes()), "controls": row,
        "capture_ready": False, "scope": "Fresh-body source and ownership controls only, no capture or performance claim.",
    }, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--lock-root", default=probe.ROOT, type=Path)
    args = parser.parse_args()
    check(args.output.resolve(), args.lock_root)
