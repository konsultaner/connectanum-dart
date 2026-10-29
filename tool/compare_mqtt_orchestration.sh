#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 3 && -f "$1" && -x "$2/bin/python" && -x "$2/bin/coverage" ]] || exit 2
library="$1"
venv="$2"
output="$3"
failed=0
for leg in bare-1 traced-1 bare-2 traced-2; do
  command=("$venv/bin/python" -m run_mqtt_benchmark_gate)
  if [[ "$leg" == traced-* ]]; then
    command=("$venv/bin/coverage" run --append --source=run_mqtt_benchmark_gate -m run_mqtt_benchmark_gate)
  fi
  for profile in ws_sustained ws_v311_sustained 64k_sustained; do
    destination="$output/$leg/$profile"
    mkdir -p "$destination"
    result=0
    env -u TOKIO_WORKER_THREADS -u CONNECTANUM_NATIVE_RUNTIME_THREADS \
      CONNECTANUM_NATIVE_LIB="$library" "${command[@]}" --native-router \
      --budget "tool/mqtt_native_${profile}_benchmark_budget.json" \
      --output "$destination" > "$destination/gate.log" 2>&1 || result=$?
    printf '%s\n' "$result" > "$destination/exit-code.txt"
    echo "$leg $profile: exit $result"
    if [[ "$result" -ne 0 ]]; then failed=1; fi
  done
done
exit "$failed"
