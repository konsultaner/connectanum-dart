#!/usr/bin/env python3
"""Hash-pinned, production-line-only Rust coverage; preserve the raw LLVM report."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parent.parent
ROOTS = {
    "ct_core": "native/transport/ct_core/src/lib.rs",
    "ct_ffi": "native/transport/ct_ffi/src/lib.rs",
}
WORKSPACES = {
    "transport": (ROOTS, ()),
    "bench": ({"connectanum_bench_orchestrator": "native/bench/src/lib.rs"}, (
        "native/bench/src/bin/check_artifact_gate.rs",
        "native/bench/src/bin/http_stream.rs",
        "native/bench/src/bin/transform_results.rs",
    )),
}
POLICY = {"test": False, 'feature="ffi-test"': False, "otherPredicates": "unknown"}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_inventory(repo: Path, roots: dict[str, str]) -> dict[str, str]:
    inventory = {}
    for component, root in roots.items():
        directory = (repo / root).parent
        for path in sorted(directory.rglob("*.rs")):
            relative = path.relative_to(repo).as_posix()
            if relative in inventory:
                raise ValueError(f"Overlapping source roots: {relative}")
            if path.is_symlink():
                raise ValueError(f"Symlinked source: {relative}")
            inventory[relative] = component
    return inventory


def resolve_module(repo: Path, source: str, module: dict, path_override: bool) -> str:
    path = repo / source
    inline = module["inline"]
    ordinary_base = path.parent if path_override or path.name == "mod.rs" else path.with_suffix("")
    if module["path"] is not None:
        base = ordinary_base.joinpath(*inline) if inline else path.parent
        candidates = [base / module["path"]]
    else:
        base = ordinary_base.joinpath(*inline)
        candidates = [base / f'{module["name"]}.rs', base / module["name"] / "mod.rs"]
    candidates = [candidate.resolve() for candidate in candidates if candidate.is_file()]
    if len(candidates) != 1:
        raise ValueError(f"Unresolved or ambiguous module {source}: {module}")
    return candidates[0].relative_to(repo).as_posix()


def classify(repo: Path, roots: dict[str, str], scopes: dict, *, entrypoints=()) -> dict[str, str]:
    reachable: dict[str, set[tuple[bool, bool]]] = {}
    pending = [(root, False, True) for root in (*roots.values(), *entrypoints)]
    while pending:
        source, parent_test, path_override = pending.pop()
        if source not in scopes:
            raise ValueError(f"Module outside the inventoried component sources: {source}")
        scope = scopes[source]
        test_only = parent_test or scope["fileTestOnly"]
        context = (test_only, path_override)
        if context in reachable.get(source, set()):
            continue
        reachable.setdefault(source, set()).add(context)
        if scope["problems"] and not test_only:
            raise ValueError(f'Unclassified source scopes in {source}: {scope["problems"]}')
        for module in scope["modules"]:
            pending.append((resolve_module(repo, source, module, path_override),
                            test_only or module["testOnly"], module["path"] is not None))
    missing = sorted(set(scopes) - set(reachable))
    if missing:
        raise ValueError(f"Unreachable Rust sources need explicit classification: {missing}")
    return {source: "production-candidate" if any(not test for test, _ in states) else "test-only"
            for source, states in reachable.items()}


def tracked_inputs(repo: Path, inventory: dict, roots: dict) -> list[str]:
    paths = set(inventory)
    for root in roots.values():
        directory = (repo / root).parent
        while directory != repo:
            for name in ("Cargo.toml", "Cargo.lock", "build.rs"):
                path = directory / name
                if path.is_file():
                    paths.add(path.relative_to(repo).as_posix())
            directory = directory.parent
    return sorted(paths)


def checked_entrypoints(roots: dict[str, str], inventory: dict, entrypoints) -> list[str]:
    if not isinstance(entrypoints, (list, tuple)) or any(not isinstance(path, str) for path in entrypoints):
        raise ValueError("Invalid coverage entrypoints")
    if (len(set(entrypoints)) != len(entrypoints)
            or set(entrypoints) & set(roots.values())
            or not set(entrypoints) <= set(inventory)):
        raise ValueError("Duplicate or uninventoried coverage entrypoint")
    return list(entrypoints)


def snapshot(repo: Path, roots: dict[str, str], analyzer: Path, *, entrypoints=()) -> dict:
    repo = repo.resolve()
    inventory = source_inventory(repo, roots)
    if not inventory:
        raise ValueError("No Rust sources")
    entries = checked_entrypoints(roots, inventory, entrypoints)
    inputs = tracked_inputs(repo, inventory, roots)
    before = {source: digest(repo / source) for source in inputs}
    raw = json.loads(subprocess.check_output(
        [str(analyzer.resolve()), *inventory], cwd=repo, text=True,
    ))
    if set(raw) != set(inventory):
        raise ValueError("Analyzer source inventory mismatch")
    kinds = classify(repo, roots, raw, entrypoints=entries)
    for source, scope in raw.items():
        scope.update(component=inventory[source], classification=kinds[source],
                     lineCount=len((repo / source).read_text().splitlines()))
    result = {
        "schemaVersion": 1, "policy": POLICY, "roots": roots,
        "host": {"system": platform.system(), "machine": platform.machine()},
        "analyzerSha256": digest(analyzer), "inputHashes": before, "sources": raw,
        "metric": "executable production-candidate lines; no function/branch percentage",
    }
    if entries:
        result["entrypoints"] = entries
    validate_snapshot(repo, result)
    return result


def validate_snapshot(repo: Path, scope: dict) -> None:
    if scope["schemaVersion"] != 1 or scope["policy"] != POLICY:
        raise ValueError("Unsupported coverage scope policy")
    inventory = source_inventory(repo, scope["roots"])
    checked_entrypoints(scope["roots"], inventory, scope.get("entrypoints", ()))
    if set(inventory) != set(scope["sources"]):
        raise ValueError("Source inventory changed since snapshot")
    if tracked_inputs(repo, inventory, scope["roots"]) != sorted(scope["inputHashes"]):
        raise ValueError("Build input inventory changed since snapshot")
    for source, expected in scope["inputHashes"].items():
        if digest(repo / source) != expected:
            raise ValueError(f"Stale coverage source: {source}")


def read_lcov(repo: Path, raw: str, scope: dict) -> tuple[dict, list[str]]:
    records: dict[str, dict[int, int]] = {}
    outside = set()
    source = None
    for entry in raw.splitlines():
        if entry.startswith("SF:"):
            if source is not None:
                raise ValueError("Unterminated LCOV record")
            path = Path(entry[3:])
            path = (repo / path).resolve() if not path.is_absolute() else path.resolve()
            source = str(path)
            try:
                source = path.relative_to(repo).as_posix()
            except ValueError:
                pass
            if source not in scope["sources"]:
                outside.add(source)
            records.setdefault(source, {})
        elif entry.startswith("DA:"):
            if source is None:
                raise ValueError("DA outside LCOV source record")
            fields = entry[3:].split(",")
            if len(fields) not in (2, 3):
                raise ValueError("Malformed DA record")
            line, count = map(int, fields[:2])
            if line < 1 or count < 0:
                raise ValueError("Negative or zero LCOV line/count")
            if source in scope["sources"] and line > scope["sources"][source]["lineCount"]:
                raise ValueError(f"LCOV line beyond source: {source}:{line}")
            records[source][line] = max(count, records[source].get(line, 0))
        elif entry.startswith("end_of_record"):
            if entry != "end_of_record":
                raise ValueError("Malformed LCOV record boundary")
            if source is None:
                raise ValueError("LCOV end without source")
            source = None
    if source is not None or not records:
        raise ValueError("Unterminated or empty LCOV report")
    return records, sorted(outside)


def filter_lcov(repo: Path, scope: dict, raw: str) -> tuple[str, dict]:
    validate_snapshot(repo, scope)
    records, outside = read_lcov(repo, raw, scope)
    components = {name: {"found": 0, "hit": 0, "excludedTestLines": 0,
                         "unmeasuredSources": [], "files": {}} for name in scope["roots"]}
    output = []
    for source, info in sorted(scope["sources"].items()):
        component = components[info["component"]]
        lines = records.get(source, {})
        if info["classification"] == "test-only":
            excluded = set(lines)
        else:
            mixed = set(lines) & set(info["mixedLines"])
            if mixed:
                raise ValueError(f"Ambiguous production/test LCOV lines in {source}: {sorted(mixed)}")
            excluded = set(lines) & set(info["excludedLines"])
        kept = {line: count for line, count in lines.items() if line not in excluded}
        hit = sum(count > 0 for count in kept.values())
        component["excludedTestLines"] += len(excluded)
        component["found"] += len(kept)
        component["hit"] += hit
        component["files"][source] = {"found": len(kept), "hit": hit,
                                     "excludedTestLines": sorted(excluded)}
        if info["classification"] == "production-candidate" and not kept:
            component["unmeasuredSources"].append(source)
        if kept:
            output.extend([f"SF:{source}", *(f"DA:{line},{count}" for line, count in sorted(kept.items())),
                           f"LF:{len(kept)}", f"LH:{hit}", "end_of_record"])
    if not output:
        raise ValueError("No measured production lines")
    for component in components.values():
        component["percent"] = 100 * component["hit"] / component["found"] if component["found"] else None
    return "\n".join(output) + "\n", {
        "schemaVersion": 1, "metric": scope["metric"], "host": scope["host"],
        "components": components, "outsideScopeSources": outside,
        "warning": "Unmeasured sources and inactive platform branches are not evidence of 100% coverage.",
        "rawLcovSha256": hashlib.sha256(raw.encode()).hexdigest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["snapshot", "filter"])
    parser.add_argument("--workspace", choices=WORKSPACES, default="transport")
    parser.add_argument("--scope", type=Path, required=True)
    parser.add_argument("--analyzer", type=Path)
    parser.add_argument("--lcov", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    roots, entrypoints = WORKSPACES[args.workspace]
    if args.command == "snapshot":
        if not args.analyzer:
            parser.error("snapshot requires --analyzer")
        result = snapshot(REPO, roots, args.analyzer, entrypoints=entrypoints)
        with args.scope.open("x") as output:
            json.dump(result, output, indent=2)
    else:
        if not args.lcov or not args.output or not args.analyzer:
            parser.error("filter requires --lcov, --output and --analyzer")
        scope = json.loads(args.scope.read_text())
        if digest(args.analyzer) != scope["analyzerSha256"]:
            raise ValueError("Coverage analyzer changed since snapshot")
        if snapshot(REPO, roots, args.analyzer, entrypoints=entrypoints) != scope:
            raise ValueError("Coverage source scopes changed since snapshot")
        filtered, summary = filter_lcov(REPO, scope, args.lcov.read_text())
        summary["scopeSha256"] = digest(args.scope)
        with args.output.open("x") as output:
            output.write(filtered)
        with args.output.with_suffix(".summary.json").open("x") as output:
            json.dump(summary, output, indent=2)


if __name__ == "__main__":
    main()
