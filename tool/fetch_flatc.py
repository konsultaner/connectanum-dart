#!/usr/bin/env python3
"""Fetch the checksum-pinned flatc release into an explicitly supplied directory."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import platform
import subprocess
from urllib.parse import quote
from urllib.request import urlopen
import zipfile

from generate_wamp_flatbuffers import ROOT, SCHEMA


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((ROOT / SCHEMA / "manifest.json").read_text())
    system = platform.system().lower()
    machine = platform.machine().lower()
    machine = {"aarch64": "arm64", "x64": "amd64"}.get(machine, machine)
    key = system + "-" + machine
    asset = manifest["compiler_assets"].get(key)
    if not asset:
        parser.error(f"No pinned compiler binary for {key}; build flatc {manifest['flatc']} from source")
    url = ("https://github.com/google/flatbuffers/releases/download/v" +
           manifest["flatc"] + "/" + quote(asset["name"]))
    with urlopen(url, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != asset["sha256"]:
        parser.error("Compiler archive checksum mismatch")
    executable = "flatc.exe" if system == "windows" else "flatc"
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        matches = [name for name in archive.namelist() if Path(name).name == executable]
        if len(matches) != 1:
            parser.error("Compiler archive has no unique flatc executable")
        binary = archive.read(matches[0])
    args.output.mkdir(parents=True, exist_ok=True)
    target = args.output / executable
    target.write_bytes(binary)
    target.chmod(0o755)
    version = subprocess.check_output([str(target.resolve()), "--version"], text=True).strip()
    if version != "flatc version " + manifest["flatc"]:
        parser.error("Downloaded compiler version mismatch")
    print(target.resolve())


if __name__ == "__main__":
    main()
