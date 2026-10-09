#!/usr/bin/env python3
"""Check pinned upstream Python readers against Dart/Rust and compiler fixtures."""

import argparse
import importlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from generate_wamp_flatbuffers import ROOT, SCHEMA, verify_inputs

ENUMS = {"method": "AuthMethod", "request_type": "MessageType",
         "match": "Match", "invoke": "InvocationPolicy", "mode": "CancelMode",
         "ppt_scheme": "PPTScheme", "ppt_serializer": "PPTSerializer"}
CALL_ARGS = bytes([0x82, 1, 0x65, 104, 101, 108, 108, 111])


def check_fields(table, expected):
    for key, wanted in expected.items():
        name = "".join(part.title() for part in key.split("_"))
        getter = getattr(table, name)
        if isinstance(wanted, list):
            actual = [getter(i) for i in range(getattr(table, name + "Length")())]
        else:
            actual = getter()
            if isinstance(wanted, dict):
                assert actual is not None, key
                check_fields(actual, wanted)
                continue
            if key in ENUMS:
                enum_name = ENUMS[key]
                enum = getattr(importlib.import_module("wamp.proto." + enum_name), enum_name)
                wanted = getattr(enum, wanted)
            elif isinstance(actual, bytes):
                actual = actual.decode("utf-8")
        if actual != wanted:
            raise AssertionError(f"{key}: {actual!r} != {wanted!r}")


def read_message(data, type_name, union_tag, expected):
    module = importlib.import_module("wamp.proto.Message")
    root = module.Message.GetRootAs(data, 0)
    if root.MsgType() != union_tag:
        raise AssertionError(f"Union discriminator {root.MsgType()} != {union_tag}")
    table = root.Msg()
    klass = getattr(importlib.import_module("wamp.proto." + type_name), type_name)
    message = klass()
    message.Init(table.Bytes, table.Pos)
    check_fields(message, expected)


def write_python_call(path):
    import flatbuffers
    call = importlib.import_module("wamp.proto.Call")
    message = importlib.import_module("wamp.proto.Message")
    builder = flatbuffers.Builder(128)
    procedure = builder.CreateString("com.example.proc")
    args = builder.CreateByteVector(CALL_ARGS)
    call.CallStart(builder)
    call.CallAddRequest(builder, 77)
    call.CallAddProcedure(builder, procedure)
    call.CallAddArgs(builder, args)
    value = call.CallEnd(builder)
    message.MessageStart(builder)
    message.MessageAddMsgType(builder, 16)
    message.MessageAddMsg(builder, value)
    root = message.MessageEnd(builder)
    builder.Finish(root)
    path.write_bytes(builder.Output())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flatc", default=os.environ.get("FLATC", "flatc"))
    args = parser.parse_args()
    manifest = verify_inputs(ROOT)
    import flatbuffers
    if flatbuffers.__version__ != manifest["python_runtime"]["version"]:
        parser.error("Install flatbuffers==" + manifest["python_runtime"]["version"])
    actual = subprocess.check_output([args.flatc, "--version"], text=True).strip()
    if actual != "flatc version " + manifest["flatc"]:
        parser.error("Pinned flatc version required")
    with tempfile.TemporaryDirectory(prefix="connectanum-flatbuffers-interop-") as directory:
        directory = Path(directory)
        generated = directory / "python"
        # --python-typing also generates the imports for referenced tables.
        subprocess.run([args.flatc, "--python", "--python-typing", "--gen-all", "-o", str(generated),
                        str(ROOT / SCHEMA / "upstream/wamp.fbs")], check=True)
        sys.path.insert(0, str(generated))
        cases = json.loads((ROOT / SCHEMA / "fixtures.json").read_text())
        upstream_cases = [case for case in cases if case["union_tag"] != 26]
        for case in upstream_cases:
            data = (ROOT / SCHEMA / "fixtures" / (case["name"] + ".bin")).read_bytes()
            # The unmodified reader intentionally ignores the appended control
            # string; all upstream fields must still agree.
            fields = dict(case["wire"]["msg"])
            fields.pop("method_name", None)
            read_message(data, case["wire"]["msg_type"], case["union_tag"], fields)
        emitted = directory / "emitted"
        emitted.mkdir()
        write_python_call(emitted / "python_call.bin")
        subprocess.run(["dart", "run", "tool/emit_flatbuffers_fixture.dart", str(emitted)],
                       cwd=ROOT / "packages/connectanum_core", check=True)
        environment = dict(os.environ, CONNECTANUM_FLATBUFFERS_EMIT_DIR=str(emitted))
        subprocess.run(["cargo", "test", "-p", "ct_core", "flatbuffers_conformance_tests"],
                       cwd=ROOT / "native/transport", env=environment, check=True)
        for name in ["dart_call_metadata", "rust_call_metadata"]:
            read_message((emitted / (name + ".bin")).read_bytes(), "Call", 16,
                         {"request": 77, "procedure": "com.example.proc", "args": list(CALL_ARGS)})
        read_message((emitted / "dart_call_metadata.bin").read_bytes(), "Call", 16,
                     {"caller": 9007199254740992})
        read_message((emitted / "dart_publish_ids.bin").read_bytes(), "Publish", 8,
                     {"request": 42, "topic": "com.example.topic",
                      "exclude": [1, 4294967296, 9007199254740991, 9007199254740992]})
        read_message((emitted / "dart_publish_empty_ids.bin").read_bytes(), "Publish", 8,
                     {"request": 42, "topic": "com.example.topic", "exclude": []})
        # Reload modules from the derived schema only after upstream checks,
        # so no extended getter can accidentally mask an upstream incompatibility.
        extended = directory / "extended_python"
        subprocess.run([args.flatc, "--python", "--python-typing", "--gen-all", "-o", str(extended),
                        str(ROOT / SCHEMA / "wamp.fbs")], check=True)
        for module in list(sys.modules):
            if module == "wamp" or module.startswith("wamp."):
                del sys.modules[module]
        sys.path.insert(0, str(extended))
        for case in cases:
            data = (ROOT / SCHEMA / "fixtures" / (case["name"] + ".bin")).read_bytes()
            read_message(data, case["wire"]["msg_type"], case["union_tag"], case["wire"]["msg"])
            root = importlib.import_module("wamp.proto.Message").Message.GetRootAs(data, 0)
            expected = case["wire"].get("metadata")
            actual = [root.Metadata(i) for i in range(root.MetadataLength())]
            assert actual == (expected or []), case["name"]
        for language in ["dart", "rust"]:
            for mask in [0, 1, 7]:
                read_message((emitted / f"{language}_heartbeat_{mask}.bin").read_bytes(), "Heartbeat", 26,
                             {"ping": 0, "incoming": 0, "outgoing": 0, "presence": mask})
            read_message((emitted / f"{language}_challenge_custom.bin").read_bytes(), "Challenge", 4,
                         {"method": "NULL", "method_name": "com.example.custom"})
        # Exercise the actual native model codec and the public Dart serializer,
        # including retained custom metadata and encoded argument spans.
        codec_environment = dict(environment, CONNECTANUM_FLATBUFFERS_CODEC_DIR=str(emitted))
        codec_test = ["cargo", "test", "-p", "ct_core", "all_public_messages_round_trip_without_a_whole_message_cbor_shim"]
        subprocess.run(codec_test, cwd=ROOT / "native/transport", env=codec_environment, check=True)
        subprocess.run(["dart", "run", "tool/roundtrip_flatbuffers_codec.dart", str(emitted)],
                       cwd=ROOT / "packages/connectanum_core", check=True)
        subprocess.run(codec_test, cwd=ROOT / "native/transport", env=codec_environment, check=True)
        codec_cases = json.loads((ROOT / SCHEMA / "codec_cases.json").read_text())
        canonical = {case["name"]: case for case in cases}
        for case in codec_cases:
            pinned = canonical[case["name"]]
            for language in ["rust", "dart", "dart_segments"]:
                read_message((emitted / f"{language}_codec_{case['name']}.bin").read_bytes(),
                             pinned["wire"]["msg_type"], pinned["union_tag"], {})
        print(f"Unmodified upstream readers accepted {len(upstream_cases)} fixtures; "
              f"extended readers accepted {len(cases)} fixtures and Dart/Rust extension output; "
              f"Python/Dart/Rust bidirectional Call conformance and contiguous/segmented Dart output for all {len(codec_cases)} public codec messages passed.")


if __name__ == "__main__":
    main()
