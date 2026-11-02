#!/usr/bin/env python3
"""Retain original diagnostic input ZIPs and exact API metadata once per runner."""
import argparse
import json
from pathlib import Path
import subprocess
import zipfile

import run_mqtt_dart_copy_census as census


REPO = "konsultaner/connectanum-dart"


def api(path):
    return json.loads(subprocess.check_output(["gh", "api", "repos/" + REPO + "/" + path]))


def fetch(root):
    if root.exists():
        raise ValueError("Never overwrite/download an existing retained input directory")
    root.mkdir(parents=True)
    run = api("actions/runs/" + str(census.SOURCE_RUN))
    jobs = json.loads(subprocess.check_output([
        "gh", "run", "view", str(census.SOURCE_RUN), "--repo", REPO,
        "--json", "headSha,status,conclusion,jobs"]))
    (root / "source-run.json").write_text(json.dumps(run, indent=2) + "\n")
    (root / "source-jobs.json").write_text(json.dumps(jobs, indent=2) + "\n")
    artifacts = []
    for ident, (name, wanted) in census.ARTIFACTS.items():
        metadata = api("actions/artifacts/" + str(ident))
        expected_run = census.SOURCE_RUN if ident == 13119578041 else 41395078952
        if (metadata["name"] != name or metadata["digest"] != "sha256:" + wanted or
                metadata["expired"] or metadata["workflow_run"]["id"] != expected_run or
                metadata["workflow_run"]["head_sha"] != census.probe.SOURCE):
            raise ValueError("Wrong exact original artifact/run/source")
        artifacts.append(metadata)
        archive = root / (str(ident) + ".zip")
        with archive.open("xb") as stream:
            subprocess.run(["gh", "api", "repos/" + REPO + "/actions/artifacts/" + str(ident) + "/zip"],
                           stdout=stream, check=True)
        if archive.stat().st_size != metadata["size_in_bytes"] or census.support.digest(archive) != wanted:
            raise ValueError("Original artifact ZIP digest/size mismatch")
        target = root / ("mqtt-native-profile" if ident == 13119578041 else "copy")
        target.mkdir()
        with zipfile.ZipFile(archive) as packed:
            if packed.testzip() is not None:
                raise ValueError("Corrupt original artifact ZIP")
            for member in packed.infolist():
                if (not (target / member.filename).resolve().is_relative_to(target.resolve()) or
                        (member.external_attr >> 16) & 0o170000 == 0o120000):
                    raise ValueError("Artifact ZIP escape/link rejected")
            packed.extractall(target)
    (root / "source-artifacts.json").write_text(json.dumps(artifacts, indent=2) + "\n")
    census.verify_inputs(root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    fetch(parser.parse_args().output.resolve())
