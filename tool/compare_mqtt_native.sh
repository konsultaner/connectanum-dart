#!/usr/bin/env bash
# Compare native libraries with the same Dart harness and unchanged budgets.
set -euo pipefail
if [[ $# -ne 3 || ! -f "$1" || ! -f "$2" ]]; then
  echo 'Usage: compare_mqtt_native.sh BASELINE_LIB CANDIDATE_LIB OUTPUT' >&2
  exit 2
fi
baseline_lib="$1"
candidate_lib="$2"
output="$3"
candidate_workers="${MQTT_COMPARE_WORKER_THREADS:-}"
if [[ -n "$candidate_workers" && ! "$candidate_workers" =~ ^[1-9][0-9]*$ ]]; then
  echo 'MQTT_COMPARE_WORKER_THREADS must be a positive integer' >&2
  exit 2
fi
failed=0
for leg in baseline-1 candidate-1 baseline-2 candidate-2; do
  library="$baseline_lib"
  workers="${CONNECTANUM_NATIVE_RUNTIME_THREADS:-}"
  if [[ "$leg" == candidate-* ]]; then
    library="$candidate_lib"
    if [[ -n "$candidate_workers" ]]; then workers="$candidate_workers"; fi
  fi
  mkdir -p "$output/$leg"
  echo "${workers:-auto}" > "$output/$leg/runtime-workers.txt"
  for profile in ws_sustained ws_v311_sustained 64k_sustained; do
    destination="$output/$leg/$profile"
    mkdir -p "$destination"
    result=0
    CONNECTANUM_NATIVE_LIB="$library" CONNECTANUM_NATIVE_RUNTIME_THREADS="$workers" \
      python3 tool/run_mqtt_benchmark_gate.py \
      --native-router --budget "tool/mqtt_native_${profile}_benchmark_budget.json" \
      --output "$destination" > "$destination/gate.log" 2>&1 || result=$?
    echo "$result" > "$destination/exit-code.txt"
    echo "$leg $profile: exit $result"
    if [[ "$leg" == candidate-* && "$result" -ne 0 ]]; then failed=1; fi
  done
done
exit "$failed"
