#!/usr/bin/env python3

import argparse
import json
import tomllib
from pathlib import Path


def parse_workload_names(csv_value: str) -> list[str]:
    names = [name.strip() for name in csv_value.split(",") if name.strip()]
    if not names:
        raise ValueError("At least one workload name is required.")

    duplicates: list[str] = []
    seen: set[str] = set()
    for name in names:
        if name in seen and name not in duplicates:
            duplicates.append(name)
        seen.add(name)

    if duplicates:
        raise ValueError(
            "Duplicate workload names are not allowed: "
            + ", ".join(sorted(duplicates))
        )

    return names


def filter_scenario_document(document: dict, workload_names: list[str]) -> dict:
    workloads = document.get("workloads")
    if not isinstance(workloads, list) or not workloads:
        raise ValueError("Scenario must define at least one workload.")

    available_names = [
        workload.get("name")
        for workload in workloads
        if isinstance(workload, dict) and isinstance(workload.get("name"), str)
    ]
    missing = [name for name in workload_names if name not in available_names]
    if missing:
        raise ValueError(
            "Scenario does not define requested workload(s): "
            + ", ".join(missing)
        )

    selected_names = set(workload_names)
    filtered_workloads = [
        workload for workload in workloads if workload.get("name") in selected_names
    ]

    focus_note = "Focused workloads: {}.".format(", ".join(workload_names))
    result: dict = {}
    for key, value in document.items():
        if key == "workloads":
            continue
        if key == "description":
            description = value if isinstance(value, str) else ""
            result[key] = (
                f"{description.rstrip()} {focus_note}".strip()
                if description
                else focus_note
            )
            continue
        result[key] = value
    if "description" not in result:
        result["description"] = focus_note
    result["workloads"] = filtered_workloads
    return result


def format_toml_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "[{}]".format(", ".join(format_toml_value(item) for item in value))
    raise TypeError(f"Unsupported TOML value type: {type(value).__name__}")


def write_scenario_document(document: dict, output_path: Path) -> None:
    lines: list[str] = []

    for key, value in document.items():
        if key == "workloads":
            continue
        lines.append(f"{key} = {format_toml_value(value)}")

    workloads = document.get("workloads", [])
    for workload in workloads:
        if lines:
            lines.append("")
        lines.append("[[workloads]]")
        for key, value in workload.items():
            lines.append(f"{key} = {format_toml_value(value)}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Materialize a temporary bench scenario that keeps only the named "
            "workloads from an existing scenario."
        )
    )
    parser.add_argument("input_scenario", help="Path to the source scenario TOML file")
    parser.add_argument("output_scenario", help="Path to write the filtered scenario")
    parser.add_argument(
        "workloads",
        help="Comma-separated workload names to keep, preserving source order",
    )
    args = parser.parse_args()

    input_path = Path(args.input_scenario)
    output_path = Path(args.output_scenario)
    workload_names = parse_workload_names(args.workloads)

    document = tomllib.loads(input_path.read_text())
    filtered_document = filter_scenario_document(document, workload_names)
    write_scenario_document(filtered_document, output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
