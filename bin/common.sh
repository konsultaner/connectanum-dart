#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Keep automated Dart smoke runs deterministic; analytics startup can wait on
# network before the target program handles validation-only failures.
export DART_SUPPRESS_ANALYTICS="${DART_SUPPRESS_ANALYTICS:-true}"

repo_root() {
  printf '%s\n' "$ROOT_DIR"
}

cd_repo_root() {
  cd "$ROOT_DIR"
}

path_prepend_unique() {
  local path_entry="$1"

  [[ -n "$path_entry" ]] || return 0

  case ":$PATH:" in
    *":$path_entry:"*)
      ;;
    *)
      export PATH="$path_entry:$PATH"
      ;;
  esac
}

dart_binary() {
  local candidate
  local flutter_path
  local root

  if command -v dart >/dev/null 2>&1; then
    command -v dart
    return 0
  fi

  if [[ -n "${DART_SDK:-}" ]]; then
    candidate="${DART_SDK%/}/bin/dart"
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if command -v flutter >/dev/null 2>&1; then
    flutter_path="$(command -v flutter)"
    candidate="$(cd "$(dirname "$flutter_path")" && pwd)/dart"
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for root in \
    "${FLUTTER_ROOT:-}" \
    "${FLUTTER_HOME:-}" \
    "$HOME/flutter" \
    "$HOME/flutter/flutter" \
    "$HOME/development/flutter" \
    "$HOME/development/flutter/flutter" \
    "$HOME/sdk/flutter" \
    "$HOME/sdk/flutter/flutter" \
    "$HOME/fvm/default" \
    "$HOME/fvm/default/flutter_sdk"; do
    [[ -n "$root" ]] || continue
    candidate="${root%/}/bin/dart"
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_dart_env() {
  local binary
  local binary_dir

  if command -v dart >/dev/null 2>&1; then
    return 0
  fi

  if ! binary="$(dart_binary)"; then
    return 1
  fi

  binary_dir="$(cd "$(dirname "$binary")" && pwd)"
  path_prepend_unique "$binary_dir"

  if [[ -z "${FLUTTER_ROOT:-}" && -x "$binary_dir/flutter" ]]; then
    export FLUTTER_ROOT="$(cd "$binary_dir/.." && pwd)"
  fi
}

ensure_rust_env() {
  if command -v cargo >/dev/null 2>&1; then
    return 0
  fi

  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.cargo/env"
  elif [[ -d "$HOME/.cargo/bin" ]]; then
    path_prepend_unique "$HOME/.cargo/bin"
  fi

  command -v cargo >/dev/null 2>&1
}

require_command() {
  local command_name="$1"

  case "$command_name" in
    dart)
      ensure_dart_env || true
      ;;
    cargo|rustc|rustup)
      ensure_rust_env || true
      ;;
  esac

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    return 1
  fi
}

retry_command() {
  local description="$1"
  local max_attempts="$2"
  local delay_seconds="$3"
  local attempt
  local status

  shift 3

  if ! [[ "$max_attempts" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s retry attempts must be a positive integer, got %s.\n' "$description" "$max_attempts" >&2
    return 2
  fi

  if ! [[ "$delay_seconds" =~ ^[0-9]+$ ]]; then
    printf '%s retry delay must be a non-negative integer, got %s.\n' "$description" "$delay_seconds" >&2
    return 2
  fi

  for attempt in $(seq 1 "$max_attempts"); do
    if "$@"; then
      return 0
    else
      status=$?
    fi

    if (( attempt == max_attempts )); then
      return "$status"
    fi

    printf '%s failed on attempt %s/%s; retrying in %ss.\n' "$description" "$attempt" "$max_attempts" "$delay_seconds" >&2
    sleep "$delay_seconds"
  done
}

run_command_with_timeout() {
  local description="$1"
  local timeout_seconds="$2"
  shift 2

  if ! [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s timeout must be a positive integer, got %s.\n' \
      "$description" "$timeout_seconds" >&2
    return 2
  fi

  local timed_out_file
  timed_out_file="$(mktemp "${TMPDIR:-/tmp}/connectanum-timeout.XXXXXX")"
  : >"$timed_out_file"

  local command_pid
  local timeout_pid
  local status
  local had_errexit=0
  [[ $- == *e* ]] && had_errexit=1
  (
    exec "$@"
  ) &
  command_pid=$!

  (
    sleep "$timeout_seconds" &
    sleep_pid=$!

    trap 'kill "$sleep_pid" 2>/dev/null || true; exit 0' TERM INT
    wait "$sleep_pid" 2>/dev/null || exit 0

    if kill -0 "$command_pid" 2>/dev/null; then
      printf '%s exceeded %ss; terminating stalled command.\n' \
        "$description" "$timeout_seconds" >"$timed_out_file"
      kill "$command_pid" 2>/dev/null || true
      sleep 2
      kill -9 "$command_pid" 2>/dev/null || true
    fi
  ) >/dev/null 2>&1 &
  timeout_pid=$!

  set +e
  wait "$command_pid"
  status=$?
  if ((had_errexit)); then
    set -e
  else
    set +e
  fi

  kill "$timeout_pid" 2>/dev/null || true
  wait "$timeout_pid" 2>/dev/null || true

  if [[ -s "$timed_out_file" ]]; then
    cat "$timed_out_file" >&2
    rm -f "$timed_out_file"
    return 124
  fi

  rm -f "$timed_out_file"
  return "$status"
}

cargo_with_retry() {
  local max_attempts="${CONNECTANUM_CARGO_RETRY_ATTEMPTS:-3}"
  local delay_seconds="${CONNECTANUM_CARGO_RETRY_DELAY_SECONDS:-5}"

  retry_command "Cargo command" "$max_attempts" "$delay_seconds" cargo "$@"
}

native_lib_path() {
  local file_name

  if ! file_name="$(native_lib_file_name)"; then
    return 1
  fi

  printf '%s/native/transport/target/release/%s\n' "$ROOT_DIR" "$file_name"
}

native_ffi_test_lib_path() {
  local file_name

  if ! file_name="$(native_lib_file_name)"; then
    return 1
  fi

  printf '%s/native/transport/target/ffi-test/release/%s\n' "$ROOT_DIR" "$file_name"
}

native_lib_file_name() {
  case "$(uname -s)" in
    Darwin)
      printf 'libct_ffi.dylib\n'
      ;;
    Linux)
      printf 'libct_ffi.so\n'
      ;;
    CYGWIN*|MINGW*|MSYS*)
      printf 'ct_ffi.dll\n'
      ;;
    *)
      return 1
      ;;
  esac
}

native_sources_newer_than() {
  local target="$1"
  local paths=()
  local candidate

  [[ -f "$target" ]] || return 0

  for candidate in \
    "$ROOT_DIR/native/transport/Cargo.toml" \
    "$ROOT_DIR/native/transport/Cargo.lock" \
    "$ROOT_DIR/native/transport/ct_core/Cargo.toml" \
    "$ROOT_DIR/native/transport/ct_core/src" \
    "$ROOT_DIR/native/transport/ct_ffi/Cargo.toml" \
    "$ROOT_DIR/native/transport/ct_ffi/src"; do
    [[ -e "$candidate" ]] || continue
    paths+=("$candidate")
  done

  [[ "${#paths[@]}" -gt 0 ]] || return 1
  [[ -n "$(find "${paths[@]}" -newer "$target" -print -quit)" ]]
}

host_os_slug() {
  case "$(uname -s)" in
    Darwin)
      printf 'macos\n'
      ;;
    Linux)
      printf 'linux\n'
      ;;
    CYGWIN*|MINGW*|MSYS*)
      printf 'windows\n'
      ;;
    *)
      printf '%s\n' "$(uname -s | tr '[:upper:]' '[:lower:]')"
      ;;
  esac
}

host_arch_slug() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64\n'
      ;;
    arm64|aarch64)
      printf 'arm64\n'
      ;;
    *)
      printf '%s\n' "$(uname -m)"
      ;;
  esac
}

host_rust_triple() {
  local rustc_version

  require_command rustc >/dev/null
  rustc_version="$(rustc -vV)"
  awk '/^host: / { print $2 }' <<<"$rustc_version"
}

sha256_file() {
  local file_path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
    return 0
  fi

  printf 'Missing required command: sha256sum or shasum\n' >&2
  return 1
}

ensure_native_lib_env() {
  local detected_path

  if [[ -n "${CONNECTANUM_NATIVE_LIB:-}" ]]; then
    return 0
  fi

  if ! detected_path="$(native_lib_path)"; then
    return 0
  fi

  if [[ -f "$detected_path" ]]; then
    if native_sources_newer_than "$detected_path"; then
      return 0
    fi
    export CONNECTANUM_NATIVE_LIB="$detected_path"
  fi
}

native_runtime_supported() {
  case "$(uname -s)" in
    Linux|Darwin)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

chrome_binary() {
  local candidate

  if [[ -n "${CHROME_EXECUTABLE:-}" && -x "${CHROME_EXECUTABLE}" ]]; then
    printf '%s\n' "${CHROME_EXECUTABLE}"
    return 0
  fi

  for candidate in \
    google-chrome \
    chromium \
    chromium-browser \
    "$HOME/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi

    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_chrome_env() {
  local binary
  local binary_dir

  if binary="$(chrome_binary)"; then
    binary_dir="$(cd "$(dirname "$binary")" && pwd)"
    path_prepend_unique "$binary_dir"
    export CHROME_EXECUTABLE="$binary"
    return 0
  fi

  return 1
}

dart_workspace_bootstrap() {
  require_command dart
  cd_repo_root
  dart pub get
}

cargo_workspace_check() {
  require_command cargo
  cd_repo_root
  cargo_with_retry metadata --manifest-path native/transport/Cargo.toml --format-version 1 >/dev/null
}

build_native_ffi_test_release() {
  local target_dir
  local built_lib

  cargo_workspace_check
  cd_repo_root
  target_dir="$ROOT_DIR/native/transport/target/ffi-test"
  CARGO_TARGET_DIR="$target_dir" \
    cargo_with_retry build --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test --release
  if built_lib="$(native_ffi_test_lib_path)" && [[ -f "$built_lib" ]]; then
    export CONNECTANUM_NATIVE_LIB="$built_lib"
  fi
}

build_native_release() {
  local built_lib

  cargo_workspace_check
  cd_repo_root
  cargo_with_retry build --manifest-path native/transport/Cargo.toml -p ct_ffi --release
  if built_lib="$(native_lib_path)" && [[ -f "$built_lib" ]]; then
    export CONNECTANUM_NATIVE_LIB="$built_lib"
  fi
}

ensure_native_release_runtime() {
  if [[ -n "${CONNECTANUM_NATIVE_LIB:-}" ]]; then
    return 0
  fi

  if ! native_runtime_supported; then
    return 1
  fi

  ensure_native_lib_env
  if [[ -n "${CONNECTANUM_NATIVE_LIB:-}" ]]; then
    return 0
  fi

  if [[ "${CONNECTANUM_SKIP_NATIVE_BUILD:-}" == "1" || "${CONNECTANUM_SKIP_NATIVE_BUILD:-}" == "true" ]]; then
    return 1
  fi

  if ! ensure_rust_env; then
    return 1
  fi

  build_native_release
  [[ -n "${CONNECTANUM_NATIVE_LIB:-}" ]]
}

ensure_native_client_test_runtime() {
  if ! native_runtime_supported; then
    return 1
  fi

  if ! ensure_rust_env; then
    return 1
  fi

  ensure_native_lib_env
  if [[ -n "${CONNECTANUM_NATIVE_LIB:-}" ]]; then
    return 0
  fi

  build_native_ffi_test_release
}

run_public_router_hosted_mcp_client_example_dry_run() {
  local timeout_seconds="${CONNECTANUM_MCP_CLIENT_DRY_RUN_TIMEOUT_SECONDS:-60}"

  run_command_with_timeout \
    "Public router-hosted MCP client dry-run" \
    "$timeout_seconds" \
    dart run connectanum_mcp:router_hosted_client "$@"
}

run_public_router_hosted_mcp_client_dry_run_smoke() {
  local dry_run_summary

  dry_run_summary="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --protocol-version 2025-06-18 \
    --tool example.task.lookup \
    --tool-arguments '{"taskId":"T-public-example-dry-run"}' \
    --resource-uri app://example/context \
    --prompt summarize-task \
    --prompt-arguments '{"taskId":"T-public-example-dry-run"}' \
    --wamp-procedure example.task.configured.lookup \
    --wamp-topic example.events.task \
    --pubsub-topic example.events.task \
    --pubsub-event '{"taskId":"T-public-example-dry-run","status":"open"}' \
    --dry-run)"
  if [[ "$dry_run_summary" != *'"authMode":"none"'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report no-auth mode.\n'
    return 1
  fi
  if [[ "$dry_run_summary" != *'"protocolVersion":"2025-06-18"'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the requested protocol version.\n'
    return 1
  fi
  if [[ "$dry_run_summary" != *'"resourceTemplates":true'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report resource-template discovery.\n'
    return 1
  fi
  if [[ "$dry_run_summary" != *'"configuredSubscriptionMetadata":true'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report configured subscription metadata lookup.\n'
    return 1
  fi
  if [[ "$dry_run_summary" != *'"configuredRegistrationMetadata":true'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report configured registration metadata lookup.\n'
    return 1
  fi

  local pubsub_only_dry_run_summary
  pubsub_only_dry_run_summary="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --pubsub-topic example.events.task \
    --pubsub-event '{"taskId":"T-pubsub-only-example-dry-run","status":"open"}' \
    --dry-run)"
  if [[ "$pubsub_only_dry_run_summary" != *'"subscriptionMetadata":true'* ]]; then
    printf 'Public router-hosted MCP client pub/sub-only dry-run did not report subscription metadata lookup.\n'
    return 1
  fi

  local unknown_option_output
  if unknown_option_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --unknown-option \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an unknown option.\n'
    return 1
  fi
  if [[ "$unknown_option_output" != *'Unknown option: --unknown-option'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the unknown option error.\n'
    return 1
  fi

  local missing_tool_value_output
  if missing_tool_value_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --tool \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted a missing tool option value.\n'
    return 1
  fi
  if [[ "$missing_tool_value_output" != *'Missing value for --tool.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the missing tool option value error.\n'
    return 1
  fi

  local duplicate_tool_output
  if duplicate_tool_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --tool example.task.lookup \
    --tool example.task.lookup \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted duplicate tool options.\n'
    return 1
  fi
  if [[ "$duplicate_tool_output" != *'Duplicate option: --tool.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the duplicate tool option error.\n'
    return 1
  fi

  local duplicate_dry_run_output
  if duplicate_dry_run_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --dry-run \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted duplicate dry-run flags.\n'
    return 1
  fi
  if [[ "$duplicate_dry_run_output" != *'Duplicate option: --dry-run.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the duplicate dry-run flag error.\n'
    return 1
  fi

  local missing_endpoint_output
  if missing_endpoint_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted a missing endpoint.\n'
    return 1
  fi
  if [[ "$missing_endpoint_output" != *'Missing required --endpoint.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the missing endpoint error.\n'
    return 1
  fi

  local malformed_endpoint_output
  if malformed_endpoint_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint 'http://[::1' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted a malformed endpoint URL.\n'
    return 1
  fi
  if [[ "$malformed_endpoint_output" != *'--endpoint must be an absolute http or https URL.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the malformed endpoint URL error.\n'
    return 1
  fi

  local invalid_protocol_output
  if invalid_protocol_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --protocol-version 1900-01-01 \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an unsupported protocol version.\n'
    return 1
  fi
  if [[ "$invalid_protocol_output" != *'Unsupported MCP protocol version "1900-01-01".'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the unsupported protocol version error.\n'
    return 1
  fi

  local invalid_bearer_output
  if invalid_bearer_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp/secure \
    --bearer-token 'dry run bearer secret' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted a bearer token with whitespace.\n'
    return 1
  fi
  if [[ "$invalid_bearer_output" != *'Bearer token must not contain whitespace or control characters.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the invalid bearer token error.\n'
    return 1
  fi

  dry_run_summary="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp/secure \
    --protocol-version 2025-06-18 \
    --bearer-token dry-run-bearer-secret \
    --dry-run)"
  if [[ "$dry_run_summary" == *dry-run-bearer-secret* ]]; then
    printf 'Public router-hosted MCP client bearer dry-run leaked bearer token material.\n'
    return 1
  fi
  if [[ "$dry_run_summary" != *'"authMode":"bearer"'* ]]; then
    printf 'Public router-hosted MCP client bearer dry-run did not report bearer auth mode.\n'
    return 1
  fi

  dry_run_summary="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp/secure \
    --protocol-version 2025-06-18 \
    --auth-url http://127.0.0.1:8080/auth \
    --realm example.realm \
    --auth-id mcp-user \
    --ticket dry-run-ticket-secret \
    --auth-lifecycle-smoke \
    --dry-run)"
  if [[ "$dry_run_summary" == *dry-run-ticket-secret* ]]; then
    printf 'Public router-hosted MCP client ticket dry-run leaked ticket secret material.\n'
    return 1
  fi
  if [[ "$dry_run_summary" != *'"authMode":"ticket"'* ]]; then
    printf 'Public router-hosted MCP client ticket dry-run did not report ticket auth mode.\n'
    return 1
  fi
  if [[ "$dry_run_summary" != *'"authLifecycleSmoke":true'* ]]; then
    printf 'Public router-hosted MCP client ticket dry-run did not report auth lifecycle smoke mode.\n'
    return 1
  fi

  local dangling_auth_lifecycle_output
  if dangling_auth_lifecycle_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp/secure \
    --auth-lifecycle-smoke \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted auth lifecycle smoke without ticket auth.\n'
    return 1
  fi
  if [[ "$dangling_auth_lifecycle_output" != *'Use --auth-lifecycle-smoke together with --auth-url.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the dangling auth lifecycle smoke error.\n'
    return 1
  fi

  local ambiguous_auth_output
  if ambiguous_auth_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp/secure \
    --bearer-token dry-run-bearer-secret \
    --auth-url http://127.0.0.1:8080/auth \
    --realm example.realm \
    --auth-id mcp-user \
    --ticket dry-run-ticket-secret \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted mutually exclusive auth options.\n'
    return 1
  fi
  if [[ "$ambiguous_auth_output" != *'Use either --bearer-token or --auth-url, not both.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the mutually exclusive auth error.\n'
    return 1
  fi

  local incomplete_auth_output
  if incomplete_auth_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp/secure \
    --auth-url http://127.0.0.1:8080/auth \
    --realm example.realm \
    --auth-id mcp-user \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted incomplete ticket auth options.\n'
    return 1
  fi
  if [[ "$incomplete_auth_output" != *'Use --auth-url, --realm, --auth-id, and --ticket together.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the incomplete ticket auth error.\n'
    return 1
  fi

  local malformed_auth_url_output
  if malformed_auth_url_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp/secure \
    --auth-url 'http://[::1' \
    --realm example.realm \
    --auth-id mcp-user \
    --ticket dry-run-ticket-secret \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted a malformed auth URL.\n'
    return 1
  fi
  if [[ "$malformed_auth_url_output" != *'--auth-url must be an absolute http or https URL.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the malformed auth URL error.\n'
    return 1
  fi

  local invalid_auth_realm_output
  if invalid_auth_realm_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp/secure \
    --auth-url http://127.0.0.1:8080/auth \
    --realm 'bad realm' \
    --auth-id mcp-user \
    --ticket dry-run-ticket-secret \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an invalid auth realm.\n'
    return 1
  fi
  if [[ "$invalid_auth_realm_output" != *'--realm must not contain whitespace or control characters.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the invalid auth realm error.\n'
    return 1
  fi

  local invalid_auth_id_output
  if invalid_auth_id_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp/secure \
    --auth-url http://127.0.0.1:8080/auth \
    --realm example.realm \
    --auth-id 'bad auth' \
    --ticket dry-run-ticket-secret \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an invalid auth id.\n'
    return 1
  fi
  if [[ "$invalid_auth_id_output" != *'--auth-id must not contain whitespace or control characters.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the invalid auth id error.\n'
    return 1
  fi

  local dangling_tool_arguments_output
  if dangling_tool_arguments_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --tool-arguments '{"taskId":"T-public-example-dry-run"}' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted tool arguments without a tool.\n'
    return 1
  fi
  if [[ "$dangling_tool_arguments_output" != *'Use --tool-arguments together with --tool.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the dangling tool arguments error.\n'
    return 1
  fi

  local dangling_prompt_arguments_output
  if dangling_prompt_arguments_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --prompt-arguments '{"taskId":"T-public-example-dry-run"}' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted prompt arguments without a prompt.\n'
    return 1
  fi
  if [[ "$dangling_prompt_arguments_output" != *'Use --prompt-arguments together with --prompt.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the dangling prompt arguments error.\n'
    return 1
  fi

  local dangling_pubsub_event_output
  if dangling_pubsub_event_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --pubsub-event '{"taskId":"T-public-example-dry-run","status":"open"}' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted a pub/sub event without a topic.\n'
    return 1
  fi
  if [[ "$dangling_pubsub_event_output" != *'Use --pubsub-event together with --pubsub-topic.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the dangling pub/sub event error.\n'
    return 1
  fi

  local empty_tool_output
  if empty_tool_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --tool '' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an empty tool name.\n'
    return 1
  fi
  if [[ "$empty_tool_output" != *'--tool must not be empty.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the empty tool name error.\n'
    return 1
  fi

  local invalid_tool_name_output
  if invalid_tool_name_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --tool 'bad tool' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an invalid tool name.\n'
    return 1
  fi
  if [[ "$invalid_tool_name_output" != *'--tool must be 1-128 ASCII letters, digits, underscores, hyphens, or dots.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the invalid tool name error.\n'
    return 1
  fi

  local invalid_resource_uri_output
  if invalid_resource_uri_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --resource-uri readme \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an invalid resource URI.\n'
    return 1
  fi
  if [[ "$invalid_resource_uri_output" != *'--resource-uri must be an absolute URI with a scheme.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the invalid resource URI error.\n'
    return 1
  fi

  local whitespace_resource_uri_output
  if whitespace_resource_uri_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --resource-uri 'app://bad resource' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted a resource URI with whitespace.\n'
    return 1
  fi
  if [[ "$whitespace_resource_uri_output" != *'--resource-uri must not contain whitespace or control characters.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the resource URI whitespace error.\n'
    return 1
  fi

  local invalid_prompt_name_output
  if invalid_prompt_name_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --prompt 'bad prompt' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an invalid prompt name.\n'
    return 1
  fi
  if [[ "$invalid_prompt_name_output" != *'--prompt must not contain whitespace or control characters.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the invalid prompt name error.\n'
    return 1
  fi

  local invalid_wamp_topic_output
  if invalid_wamp_topic_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --wamp-topic 'bad topic' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an invalid WAMP topic.\n'
    return 1
  fi
  if [[ "$invalid_wamp_topic_output" != *'--wamp-topic must not contain whitespace or control characters.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the invalid WAMP topic error.\n'
    return 1
  fi

  local blank_pubsub_topic_output
  if blank_pubsub_topic_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --pubsub-topic '   ' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted a blank pub/sub topic.\n'
    return 1
  fi
  if [[ "$blank_pubsub_topic_output" != *'--pubsub-topic must not be empty.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the blank pub/sub topic error.\n'
    return 1
  fi

  local invalid_pubsub_topic_output
  if invalid_pubsub_topic_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --pubsub-topic 'bad topic' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted an invalid pub/sub topic.\n'
    return 1
  fi
  if [[ "$invalid_pubsub_topic_output" != *'--pubsub-topic must not contain whitespace or control characters.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the invalid pub/sub topic error.\n'
    return 1
  fi

  local malformed_tool_arguments_output
  if malformed_tool_arguments_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --tool example.task.lookup \
    --tool-arguments '{' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted malformed tool arguments JSON.\n'
    return 1
  fi
  if [[ "$malformed_tool_arguments_output" != *'--tool-arguments must be valid JSON.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the malformed tool arguments error.\n'
    return 1
  fi

  local array_pubsub_event_output
  if array_pubsub_event_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --pubsub-topic example.events.task \
    --pubsub-event '[]' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted a non-object pub/sub event.\n'
    return 1
  fi
  if [[ "$array_pubsub_event_output" != *'--pubsub-event must be a JSON object.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the non-object pub/sub event error.\n'
    return 1
  fi

  local non_string_prompt_arguments_output
  if non_string_prompt_arguments_output="$(run_public_router_hosted_mcp_client_example_dry_run \
    --endpoint http://127.0.0.1:8080/mcp \
    --prompt summarize-task \
    --prompt-arguments '{"taskId":123}' \
    --dry-run 2>&1)"; then
    printf 'Public router-hosted MCP client dry-run accepted non-string prompt arguments.\n'
    return 1
  fi
  if [[ "$non_string_prompt_arguments_output" != *'--prompt-arguments values must be strings.'* ]]; then
    printf 'Public router-hosted MCP client dry-run did not report the non-string prompt arguments error.\n'
    return 1
  fi
}

run_router_hosted_mcp_example_smoke() {
  run_public_router_hosted_mcp_client_dry_run_smoke || return

  if ! native_runtime_supported; then
    printf 'Native router-hosted MCP example smoke requires Linux or macOS; skipping on %s.\n' "$(uname -s)"
    return 0
  fi

  if ensure_rust_env; then
    ensure_native_lib_env
    if [[ -z "${CONNECTANUM_NATIVE_LIB:-}" ]]; then
      build_native_ffi_test_release
    fi
  else
    ensure_native_lib_env
    if [[ -z "${CONNECTANUM_NATIVE_LIB:-}" ]]; then
      printf 'Cargo and CONNECTANUM_NATIVE_LIB unavailable; skipping router-hosted MCP example smoke.\n'
      return 0
    fi
  fi

  run_public_router_hosted_mcp_client_live_smoke
}

assert_public_router_hosted_mcp_client_summary() {
  local summary="$1"
  local label="$2"
  local expected

  shift 2
  for expected in "$@"; do
    if [[ "$summary" != *"$expected"* ]]; then
      printf 'Public router-hosted MCP client %s summary did not include %s.\n' \
        "$label" "$expected"
      return 1
    fi
  done
}

assert_public_router_hosted_mcp_active_direct_session_summary() {
  local summary="$1"
  local label="$2"
  local summary_file
  summary_file="$(mktemp)"
  printf '%s\n' "$summary" >"$summary_file"

  SUMMARY_FILE="$summary_file" LABEL="$label" python3 <<'PY'
import json
import os

label = os.environ["LABEL"]

summary = None
with open(os.environ["SUMMARY_FILE"], encoding="utf-8") as lines:
  for line in lines:
    candidate = line.strip()
    if not candidate.startswith("{"):
        continue
    try:
        parsed = json.loads(candidate)
    except json.JSONDecodeError:
        continue
    if isinstance(parsed, dict) and isinstance(parsed.get("streamable"), dict):
        summary = parsed
        break

if summary is None:
    raise SystemExit(
        f"Public router-hosted MCP client {label} summary did not include JSON."
    )

streamable = summary.get("streamable")
if not isinstance(streamable, dict):
    raise SystemExit(
        f"Public router-hosted MCP client {label} summary did not include streamable."
    )

active_direct = streamable.get("activeDirectJson")
if not isinstance(active_direct, dict):
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} summary did not include streamable.activeDirectJson."
    )

expected = {
    "malformedSessionId": {"rejected": True, "sessionUnchanged": True},
    "directJsonStaleSessionId": {"ignored": True, "sessionUnchanged": True},
    "notificationOnlyBatch": {"accepted": True, "sessionUnchanged": True},
}

if active_direct.get("sessionUnchanged") is not True:
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} active direct JSON changed Streamable state."
    )

for key, value in expected.items():
    if active_direct.get(key) != value:
        raise SystemExit(
            "Public router-hosted MCP client "
            f"{label} active direct JSON {key} was {active_direct.get(key)!r}."
        )

batch_error = active_direct.get("batchErrorIsolation")
if not isinstance(batch_error, dict):
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} summary did not include active direct batch error isolation."
    )
if batch_error.get("sessionUnchanged") is not True:
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} active direct batch error changed Streamable state."
    )
if not isinstance(batch_error.get("errorCode"), int):
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} active direct batch error did not expose an error code."
    )
response_ids = batch_error.get("responseIds")
expected_error_ids = {
    "streamable-active-direct-batch-error-tools",
    "streamable-active-direct-batch-error-missing",
    "streamable-active-direct-batch-error-ping",
}
if not isinstance(response_ids, list) or set(response_ids) != expected_error_ids:
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} active direct batch error response ids were {response_ids!r}."
    )

pubsub = streamable.get("pubsub")
if not isinstance(pubsub, dict):
    raise SystemExit(
        f"Public router-hosted MCP client {label} summary did not include pubsub."
    )
pubsub_active_direct = pubsub.get("activeDirectJson")
if not isinstance(pubsub_active_direct, dict):
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} summary did not include pubsub.activeDirectJson."
    )
if pubsub_active_direct.get("sessionUnchanged") is not True:
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} active direct pub/sub changed Streamable state."
    )
notification_batch = pubsub_active_direct.get("notificationBatch")
if not isinstance(notification_batch, dict):
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} active direct pub/sub missed notification batch proof."
    )
if notification_batch.get("accepted") is not True:
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} active direct pub/sub notification batch was not accepted."
    )
if notification_batch.get("sessionUnchanged") is not True:
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} active direct pub/sub notification batch changed state."
    )
notification_batch_events = notification_batch.get("events")
if not isinstance(notification_batch_events, list):
    raise SystemExit(
        "Public router-hosted MCP client "
        f"{label} active direct pub/sub notification batch missed events."
    )
notification_batch_json = json.dumps(notification_batch_events, sort_keys=True)
for marker in (
    "activeDirectNotificationBatchEvent",
    "activeDirectMethodNotificationBatchEvent",
):
    if marker not in notification_batch_json:
        raise SystemExit(
            "Public router-hosted MCP client "
            f"{label} active direct pub/sub notification batch missed {marker}."
        )
PY
  local status=$?
  rm -f "$summary_file"
  return "$status"
}

assert_router_cli_consumer_package_summary() {
  local summary="$1"
  local expected

  shift
  for expected in "$@"; do
    if [[ "$summary" != *"$expected"* ]]; then
      printf 'Router CLI Dart MCP consumer package summary did not include %s.\n' \
        "$expected"
      return 1
    fi
  done
}

run_public_router_hosted_mcp_client_live_smoke() (
  local authenticated_json_summary
  local authenticated_summary
  local auth_url
  local bearer_json_summary
  local bearer_summary
  local bearer_token
  local endpoint
  local live_summary
  local pubsub_only_summary
  local secure_endpoint
  local secure_json_endpoint
  local server_log
  local server_pid
  local status
  local timeout_at

  server_log="$(mktemp "${TMPDIR:-/tmp}/connectanum-router-hosted-mcp.XXXXXX")"

  cleanup() {
    local attempt

    if [[ -n "${server_pid:-}" ]] && kill -0 "$server_pid" 2>/dev/null; then
      kill -TERM "$server_pid" 2>/dev/null || true
      for attempt in 1 2 3 4 5; do
        if ! kill -0 "$server_pid" 2>/dev/null; then
          wait "$server_pid" 2>/dev/null || true
          break
        fi
        sleep 1
      done
      if kill -0 "$server_pid" 2>/dev/null; then
        kill -KILL "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
      fi
    fi
    if [[ -n "${server_log:-}" ]]; then
      rm -f "$server_log"
    fi
  }
  trap cleanup EXIT

  dart run packages/connectanum_router/example/router_hosted_mcp.dart \
    >"$server_log" 2>&1 &
  server_pid="$!"
  timeout_at=$((SECONDS + 120))

  while ((SECONDS < timeout_at)); do
    if ! kill -0 "$server_pid" 2>/dev/null; then
      wait "$server_pid"
      status="$?"
      printf 'Router-hosted MCP example exited before serving the public endpoint.\n'
      cat "$server_log"
      return "$status"
    fi

    endpoint="$(
      sed -n 's/^Router-hosted MCP endpoint is running at //p' "$server_log" |
        tail -n 1
    )"
    secure_endpoint="$(
      sed -n 's/^Bearer-protected MCP endpoint is running at //p' "$server_log" |
        tail -n 1
    )"
    secure_json_endpoint="$(
      sed -n 's/^Bearer-protected JSON-response MCP endpoint is running at //p' "$server_log" |
        tail -n 1
    )"
    if [[ -n "$endpoint" && -n "$secure_endpoint" && -n "$secure_json_endpoint" ]]; then
      break
    fi
    sleep 1
  done

  if [[ -z "$endpoint" || -z "$secure_endpoint" || -z "$secure_json_endpoint" ]]; then
    printf 'Timed out waiting for the router-hosted MCP example endpoints.\n'
    cat "$server_log"
    return 1
  fi
  auth_url="${endpoint%/mcp}/auth"

  live_summary="$(dart run connectanum_mcp:router_hosted_client \
    --endpoint "$endpoint" \
    --protocol-version 2025-06-18 \
    --tool example.task.lookup \
    --tool-arguments '{"taskId":"T-public-example-live"}' \
    --resource-uri app://example/context \
    --prompt summarize-task \
    --prompt-arguments '{"taskId":"T-public-example-live"}' \
    --wamp-procedure example.task.configured.lookup \
    --wamp-topic example.events.task \
    --pubsub-topic example.events.task \
    --pubsub-event '{"taskId":"T-public-example-live","status":"open"}')"
  assert_public_router_hosted_mcp_client_summary "$live_summary" public \
    '"directPing"' \
    '"directWampMetadata"' \
    '"configuredRegistrationMetadata"' \
    '"configuredSubscriptionMetadata"' \
    '"streamable"' \
    '"invalidLastEventId":{"rejected":true,"sessionUnchanged":true}' \
    '"emptyLastEventId":{"accepted":true,"sessionUnchanged":true}' \
    '"malformedSessionId":{"rejected":true,"sessionUnchanged":true}' \
    '"directJsonStaleSessionId":{"ignored":true,"sessionUnchanged":true}' \
    '"notificationOnlyBatch":{"accepted":true,"sessionUnchanged":true}' \
    '"batchErrorIsolation":{"responseIds"' \
    '"batch":{"responseIds"' \
    '"wampMetadata"' \
    '"pubsub"' \
    '"activeDirectJson":{"sessionUnchanged":true,"batch":{"responseIds"' \
    '"notificationBatch":{"accepted":true,"sessionUnchanged":true' \
    '"toolNotificationEvents"'
  assert_public_router_hosted_mcp_active_direct_session_summary \
    "$live_summary" public

  printf 'Public router-hosted MCP client live smoke completed.\n'

  pubsub_only_summary="$(dart run connectanum_mcp:router_hosted_client \
    --endpoint "$endpoint" \
    --protocol-version 2025-06-18 \
    --pubsub-topic example.events.task \
    --pubsub-event '{"taskId":"T-pubsub-only-example-live","status":"open"}')"
  assert_public_router_hosted_mcp_client_summary "$pubsub_only_summary" pub/sub-only \
    '"directPing"' \
    '"streamable"' \
    '"invalidLastEventId":{"rejected":true,"sessionUnchanged":true}' \
    '"emptyLastEventId":{"accepted":true,"sessionUnchanged":true}' \
    '"malformedSessionId":{"rejected":true,"sessionUnchanged":true}' \
    '"directJsonStaleSessionId":{"ignored":true,"sessionUnchanged":true}' \
    '"notificationOnlyBatch":{"accepted":true,"sessionUnchanged":true}' \
    '"batchErrorIsolation":{"responseIds"' \
    '"pubsub"' \
    '"methodEvents"' \
    '"activeDirectJson":{"sessionUnchanged":true,"batch":{"responseIds"' \
    '"notificationBatch":{"accepted":true,"sessionUnchanged":true' \
    '"methodNotificationEvents"'
  assert_public_router_hosted_mcp_active_direct_session_summary \
    "$pubsub_only_summary" pub/sub-only

  printf 'Pub/sub-only router-hosted MCP client live smoke completed.\n'

  bearer_token="$(
    python3 - "$auth_url" <<'PY'
import json
import sys
import urllib.error
import urllib.request

auth_url = sys.argv[1]


def post(payload, allow_status=()):
    request = urllib.request.Request(
        auth_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status = response.getcode()
            body = response.read()
    except urllib.error.HTTPError as error:
        status = error.code
        body = error.read()
        if status not in allow_status:
            raise
    return status, json.loads(body.decode("utf-8"))


challenge_status, challenge = post(
    {
        "realm": "example.realm",
        "authmethod": "ticket",
        "authid": "mcp-user",
    },
    allow_status=(401,),
)
if challenge_status != 401:
    raise SystemExit(f"expected 401 auth challenge, got {challenge_status}")

state = challenge.get("state")
if not isinstance(state, str) or not state:
    raise SystemExit("auth challenge did not include a state")

grant_status, grant = post(
    {
        "state": state,
        "signature": "mcp-demo-ticket",
        "extra": {},
    },
)
if not 200 <= grant_status < 300:
    raise SystemExit(f"expected 2xx auth grant, got {grant_status}")

token = grant.get("access_token")
token_type = grant.get("token_type")
if not isinstance(token, str) or not token:
    raise SystemExit("auth grant did not include an access token")
if not isinstance(token_type, str) or token_type.lower() != "bearer":
    raise SystemExit("auth grant did not return a bearer token")

print(token)
PY
  )"

  authenticated_summary="$(dart run connectanum_mcp:router_hosted_client \
    --endpoint "$secure_endpoint" \
    --protocol-version 2025-06-18 \
    --auth-url "$auth_url" \
    --realm example.realm \
    --auth-id mcp-user \
    --ticket mcp-demo-ticket \
    --auth-lifecycle-smoke \
    --tool example.task.lookup \
    --tool-arguments '{"taskId":"T-authenticated-example-live"}' \
    --resource-uri app://example/context \
    --prompt summarize-task \
    --prompt-arguments '{"taskId":"T-authenticated-example-live"}' \
    --wamp-procedure example.task.configured.lookup \
    --wamp-topic example.events.task \
    --pubsub-topic example.events.task \
    --pubsub-event '{"taskId":"T-authenticated-example-live","status":"open"}')"
  assert_public_router_hosted_mcp_client_summary "$authenticated_summary" authenticated \
    '"directPing"' \
    '"directWampMetadata"' \
    '"configuredRegistrationMetadata"' \
    '"configuredSubscriptionMetadata"' \
    '"streamable"' \
    '"invalidLastEventId":{"rejected":true,"sessionUnchanged":true}' \
    '"emptyLastEventId":{"accepted":true,"sessionUnchanged":true}' \
    '"malformedSessionId":{"rejected":true,"sessionUnchanged":true}' \
    '"directJsonStaleSessionId":{"ignored":true,"sessionUnchanged":true}' \
    '"notificationOnlyBatch":{"accepted":true,"sessionUnchanged":true}' \
    '"batchErrorIsolation":{"responseIds"' \
    '"batch":{"responseIds"' \
    '"wampMetadata"' \
    '"pubsub"' \
    '"activeDirectJson":{"sessionUnchanged":true,"batch":{"responseIds"' \
    '"notificationBatch":{"accepted":true,"sessionUnchanged":true' \
    '"toolNotificationEvents"'
  assert_public_router_hosted_mcp_active_direct_session_summary \
    "$authenticated_summary" authenticated

  printf 'Authenticated router-hosted MCP client live smoke completed.\n'

  bearer_summary="$(dart run connectanum_mcp:router_hosted_client \
    --endpoint "$secure_endpoint" \
    --protocol-version 2025-06-18 \
    --bearer-token "$bearer_token" \
    --tool example.task.lookup \
    --tool-arguments '{"taskId":"T-bearer-example-live"}' \
    --resource-uri app://example/context \
    --prompt summarize-task \
    --prompt-arguments '{"taskId":"T-bearer-example-live"}' \
    --wamp-procedure example.task.configured.lookup \
    --wamp-topic example.events.task \
    --pubsub-topic example.events.task \
    --pubsub-event '{"taskId":"T-bearer-example-live","status":"open"}')"
  assert_public_router_hosted_mcp_client_summary "$bearer_summary" bearer-token \
    '"directPing"' \
    '"directWampMetadata"' \
    '"configuredRegistrationMetadata"' \
    '"configuredSubscriptionMetadata"' \
    '"streamable"' \
    '"invalidLastEventId":{"rejected":true,"sessionUnchanged":true}' \
    '"emptyLastEventId":{"accepted":true,"sessionUnchanged":true}' \
    '"malformedSessionId":{"rejected":true,"sessionUnchanged":true}' \
    '"directJsonStaleSessionId":{"ignored":true,"sessionUnchanged":true}' \
    '"notificationOnlyBatch":{"accepted":true,"sessionUnchanged":true}' \
    '"batchErrorIsolation":{"responseIds"' \
    '"batch":{"responseIds"' \
    '"wampMetadata"' \
    '"pubsub"' \
    '"activeDirectJson":{"sessionUnchanged":true,"batch":{"responseIds"' \
    '"notificationBatch":{"accepted":true,"sessionUnchanged":true' \
    '"toolNotificationEvents"'
  assert_public_router_hosted_mcp_active_direct_session_summary \
    "$bearer_summary" bearer-token

  printf 'Bearer-token router-hosted MCP client live smoke completed.\n'

  authenticated_json_summary="$(dart run connectanum_mcp:router_hosted_client \
    --endpoint "$secure_json_endpoint" \
    --protocol-version 2025-06-18 \
    --auth-url "$auth_url" \
    --realm example.realm \
    --auth-id mcp-user \
    --ticket mcp-demo-ticket \
    --auth-lifecycle-smoke \
    --tool example.task.lookup \
    --tool-arguments '{"taskId":"T-authenticated-json-response-example-live"}' \
    --resource-uri app://example/context \
    --prompt summarize-task \
    --prompt-arguments '{"taskId":"T-authenticated-json-response-example-live"}' \
    --wamp-procedure example.task.configured.lookup \
    --wamp-topic example.events.task \
    --pubsub-topic example.events.task \
    --pubsub-event '{"taskId":"T-authenticated-json-response-example-live","status":"open"}')"
  assert_public_router_hosted_mcp_client_summary \
    "$authenticated_json_summary" authenticated-json-response \
    '"directPing"' \
    '"directWampMetadata"' \
    '"configuredRegistrationMetadata"' \
    '"configuredSubscriptionMetadata"' \
    '"streamable"' \
    '"invalidLastEventId":{"rejected":true,"sessionUnchanged":true}' \
    '"emptyLastEventId":{"accepted":true,"sessionUnchanged":true}' \
    '"malformedSessionId":{"rejected":true,"sessionUnchanged":true}' \
    '"directJsonStaleSessionId":{"ignored":true,"sessionUnchanged":true}' \
    '"notificationOnlyBatch":{"accepted":true,"sessionUnchanged":true}' \
    '"batchErrorIsolation":{"responseIds"' \
    '"batch":{"responseIds"' \
    '"wampMetadata"' \
    '"pubsub"' \
    '"activeDirectJson":{"sessionUnchanged":true,"batch":{"responseIds"' \
    '"notificationBatch":{"accepted":true,"sessionUnchanged":true' \
    '"toolNotificationEvents"'
  assert_public_router_hosted_mcp_active_direct_session_summary \
    "$authenticated_json_summary" authenticated-json-response

  printf 'Authenticated router-hosted JSON-response MCP client live smoke completed.\n'

  bearer_json_summary="$(dart run connectanum_mcp:router_hosted_client \
    --endpoint "$secure_json_endpoint" \
    --protocol-version 2025-06-18 \
    --bearer-token "$bearer_token" \
    --tool example.task.lookup \
    --tool-arguments '{"taskId":"T-bearer-json-response-example-live"}' \
    --resource-uri app://example/context \
    --prompt summarize-task \
    --prompt-arguments '{"taskId":"T-bearer-json-response-example-live"}' \
    --wamp-procedure example.task.configured.lookup \
    --wamp-topic example.events.task \
    --pubsub-topic example.events.task \
    --pubsub-event '{"taskId":"T-bearer-json-response-example-live","status":"open"}')"
  assert_public_router_hosted_mcp_client_summary \
    "$bearer_json_summary" bearer-token-json-response \
    '"directPing"' \
    '"directWampMetadata"' \
    '"configuredRegistrationMetadata"' \
    '"configuredSubscriptionMetadata"' \
    '"streamable"' \
    '"invalidLastEventId":{"rejected":true,"sessionUnchanged":true}' \
    '"emptyLastEventId":{"accepted":true,"sessionUnchanged":true}' \
    '"malformedSessionId":{"rejected":true,"sessionUnchanged":true}' \
    '"directJsonStaleSessionId":{"ignored":true,"sessionUnchanged":true}' \
    '"notificationOnlyBatch":{"accepted":true,"sessionUnchanged":true}' \
    '"batchErrorIsolation":{"responseIds"' \
    '"batch":{"responseIds"' \
    '"wampMetadata"' \
    '"pubsub"' \
    '"activeDirectJson":{"sessionUnchanged":true,"batch":{"responseIds"' \
    '"notificationBatch":{"accepted":true,"sessionUnchanged":true' \
    '"toolNotificationEvents"'
  assert_public_router_hosted_mcp_active_direct_session_summary \
    "$bearer_json_summary" bearer-token-json-response

  printf 'Bearer-token router-hosted JSON-response MCP client live smoke completed.\n'
)

run_mcp_server_package_smoke() (
  local pub_cache
  local smoke_dir

  require_command dart

  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-mcp-server-smoke.XXXXXX")"
  pub_cache="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-mcp-server-pub-cache.XXXXXX")"
  trap "rm -rf '$smoke_dir' '$pub_cache'" EXIT

  mkdir -p "$smoke_dir/bin"
  cat >"$smoke_dir/pubspec.yaml" <<EOF
name: connectanum_mcp_server_smoke
publish_to: none
environment:
  sdk: '^3.9.2'
hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
dependencies:
  connectanum_mcp: any
dependency_overrides:
  connectanum_core:
    path: "$ROOT_DIR/packages/connectanum_core"
  connectanum_client:
    path: "$ROOT_DIR/packages/connectanum_client"
  connectanum_mcp:
    path: "$ROOT_DIR/packages/connectanum_mcp"
EOF

  cat >"$smoke_dir/bin/main.dart" <<'DART'
import 'dart:async';
import 'dart:convert';

import 'package:connectanum_mcp/connectanum_mcp.dart';

const _toolName = 'consumer.echo';
const _resourceUri = 'consumer://mcp/context';
const _resourceTemplateUri = 'consumer://mcp/task/{taskId}';
const _promptName = 'consumer.summary';

Future<void> main() async {
  await _smokeServerHandleMessage();
  await _smokeStdioTransport();
  print('MCP server-only consumer package smoke completed.');
}

Future<void> _smokeServerHandleMessage() async {
  final server = _server();
  final initialize = _jsonObjectFrom(
    await server.handleMessage({
      'jsonrpc': '2.0',
      'id': 'init',
      'method': 'initialize',
      'params': {
        'protocolVersion': mcpLatestProtocolVersion,
        'capabilities': {},
        'clientInfo': {'name': 'consumer-server-smoke', 'version': '0.1.0'},
      },
    }),
    label: 'initialize response',
  );
  final initializeResult = _jsonObjectFrom(
    initialize['result'],
    label: 'initialize result',
  );
  _expect(initialize['id'] == 'init', 'initialize id mismatch');
  _expect(
    initializeResult['protocolVersion'] == mcpLatestProtocolVersion,
    'initialize protocol mismatch',
  );
  _expect(
    jsonEncode(initializeResult['capabilities']).contains('tools'),
    'initialize did not advertise tools',
  );

  final initialized = await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
  _expect(initialized == null, 'initialized notification returned a response');
  _expect(
    server.state == McpServerState.initialized,
    'server did not enter initialized state',
  );

  final batch = _jsonListFrom(
    await server.handleMessage([
      {'jsonrpc': '2.0', 'id': 'tools', 'method': 'tools/list'},
      {
        'jsonrpc': '2.0',
        'id': 'call',
        'method': 'tools/call',
        'params': {
          'name': _toolName,
          'arguments': {'text': 'ready'},
        },
      },
      {'jsonrpc': '2.0', 'id': 'resources', 'method': 'resources/list'},
      {
        'jsonrpc': '2.0',
        'id': 'templates',
        'method': 'resources/templates/list',
      },
      {
        'jsonrpc': '2.0',
        'id': 'read',
        'method': 'resources/read',
        'params': {'uri': _resourceUri},
      },
      {
        'jsonrpc': '2.0',
        'id': 'prompt',
        'method': 'prompts/get',
        'params': {
          'name': _promptName,
          'arguments': {'text': 'ready'},
        },
      },
      {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
    ]),
    label: 'server batch response',
  );
  _expect(batch.length == 6, 'batch returned unexpected response count');
  _expect(jsonEncode(batch[0]).contains(_toolName), 'tools/list missed tool');
  _expect(jsonEncode(batch[1]).contains('ready'), 'tools/call missed echo');
  _expect(
    jsonEncode(batch[2]).contains(_resourceUri),
    'resources/list missed resource',
  );
  _expect(
    jsonEncode(batch[3]).contains(_resourceTemplateUri),
    'resources/templates/list missed template',
  );
  _expect(
    jsonEncode(batch[4]).contains('consumer package context'),
    'resources/read missed content',
  );
  _expect(
    jsonEncode(batch[5]).contains('Summarize consumer text: ready'),
    'prompts/get missed prompt content',
  );

  server.shutdown();
  _expect(server.state == McpServerState.closed, 'server did not close');
}

Future<void> _smokeStdioTransport() async {
  final output = StringBuffer();
  final transport = McpStdioTransport(
    server: _server(),
    input: Stream.value(
      utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'id': 'stdio-init',
          'method': 'initialize',
          'params': {'protocolVersion': mcpLatestProtocolVersion},
        })}\n'
        '${jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'})}\n'
        '${jsonEncode([
          {'jsonrpc': '2.0', 'id': 'stdio-tools', 'method': 'tools/list'},
          {'jsonrpc': '2.0', 'id': 'stdio-prompts', 'method': 'prompts/list'},
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        ])}\n',
      ),
    ),
    output: output,
    shutdownServerOnDone: false,
  );

  await transport.run();
  final lines = const LineSplitter().convert(output.toString());
  _expect(lines.length == 2, 'stdio transport emitted unexpected lines');
  final initialize = _jsonObjectFrom(
    jsonDecode(lines.first),
    label: 'stdio initialize response',
  );
  _expect(initialize['id'] == 'stdio-init', 'stdio initialize id mismatch');
  final batch = _jsonListFrom(
    jsonDecode(lines.last),
    label: 'stdio batch response',
  );
  _expect(batch.length == 2, 'stdio batch returned unexpected response count');
  _expect(jsonEncode(batch[0]).contains(_toolName), 'stdio tools missed tool');
  _expect(
    jsonEncode(batch[1]).contains(_promptName),
    'stdio prompts missed prompt',
  );
}

McpServer _server() => McpServer(
  serverInfo: const McpServerInfo(
    name: 'consumer-mcp-server',
    version: '0.1.0',
  ),
  tools: [
    McpTool(
      name: _toolName,
      description: 'Echoes consumer text.',
      handler: (request) {
        final text = request.arguments['text'] as String? ?? '';
        return McpToolResult.text(
          text,
          structuredContent: {'echo': text},
        );
      },
    ),
  ],
  resources: [
    McpResource(
      uri: _resourceUri,
      name: 'consumer-mcp-context',
      title: 'Consumer MCP context',
      description: 'Static context exposed by the consumer MCP server.',
      mimeType: 'application/json',
      read: (request) => [
        McpTextResourceContent(
          uri: request.uri,
          mimeType: 'application/json',
          text: '{"source":"consumer package context"}',
        ),
      ],
    ),
  ],
  resourceTemplates: [
    McpResourceTemplate(
      uriTemplate: _resourceTemplateUri,
      name: 'consumer-task',
      title: 'Consumer task',
      description: 'Template for consumer task context.',
      mimeType: 'application/json',
    ),
  ],
  prompts: [
    McpPrompt(
      name: _promptName,
      title: 'Consumer Summary',
      description: 'Builds a consumer prompt.',
      arguments: [
        McpPromptArgument(
          name: 'text',
          description: 'Text to summarize.',
          required: true,
        ),
      ],
      handler: (request) {
        final text = request.arguments['text'] ?? '';
        return McpPromptResult.text(
          'Summarize consumer text: $text',
          description: 'Consumer prompt for $text.',
        );
      },
    ),
  ],
);

Map<String, Object?> _jsonObjectFrom(Object? value, {required String label}) {
  if (value is Map<Object?, Object?>) {
    return value.map((key, value) {
      if (key is! String) {
        throw StateError('$label contained a non-string key.');
      }
      return MapEntry(key, value);
    });
  }
  throw StateError('$label was not a JSON object.');
}

List<Object?> _jsonListFrom(Object? value, {required String label}) {
  if (value is List<Object?>) {
    return value;
  }
  throw StateError('$label was not a JSON list.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
DART

  printf 'Running MCP server-only consumer package smoke from %s.\n' "$smoke_dir"
  (
    cd "$smoke_dir"
    PUB_CACHE="$pub_cache" dart pub get
    PUB_CACHE="$pub_cache" dart analyze
    PUB_CACHE="$pub_cache" dart run bin/main.dart
  )
)

run_mcp_client_package_smoke() (
  local executable_dry_run
  local executable_help
  local global_executable_dry_run
  local global_executable_help
  local global_mcp_command
  local global_smoke_workspace
  local package_name
  local package_source
  local package_target
  local pub_cache
  local smoke_dir

  require_command dart

  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-mcp-client-smoke.XXXXXX")"
  pub_cache="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-mcp-client-pub-cache.XXXXXX")"
  trap "rm -rf '$smoke_dir' '$pub_cache'" EXIT

  mkdir -p "$smoke_dir/bin"
  cat >"$smoke_dir/pubspec.yaml" <<EOF
name: connectanum_mcp_client_smoke
publish_to: none
environment:
  sdk: '^3.9.2'
hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
dependencies:
  connectanum_mcp: any
dependency_overrides:
  connectanum_core:
    path: "$ROOT_DIR/packages/connectanum_core"
  connectanum_client:
    path: "$ROOT_DIR/packages/connectanum_client"
  connectanum_mcp:
    path: "$ROOT_DIR/packages/connectanum_mcp"
EOF

  cat >"$smoke_dir/bin/main.dart" <<'DART'
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';

const _sessionId = 'agent-session';
const _protocolVersion = McpStreamableHttpClient.latestProtocolVersion;
const _authState = 'agent-auth-state';
const _authRealm = 'agent.realm';
const _authId = 'consumer-agent';
const _authRole = 'agent';
const _authProvider = 'client-smoke';
const _ticketSecret = 'agent-ticket';
const _accessToken = 'agent-token';
const _refreshToken = 'agent-refresh-token';
const _refreshedAccessToken = 'agent-token-refreshed';
const _refreshedRefreshToken = 'agent-refresh-token-refreshed';
const _toolName = 'agent.echo';
const _pagedToolName = 'agent.followup';
const _toolCursor = 'agent-tools-page-2';
const _procedureName = 'agent.lookup';
const _resourceUri = 'wamp://agent/readme';
const _pagedResourceUri = 'wamp://agent/next';
const _resourceCursor = 'agent-resources-page-2';
const _resourceTemplateUri = 'wamp://agent/task/{taskId}';
const _pagedResourceTemplateUri = 'wamp://agent/archive/{taskId}';
const _resourceTemplateCursor = 'agent-resource-templates-page-2';
const _promptName = 'agent.summary';
const _pagedPromptName = 'agent.followup_summary';
const _promptCursor = 'agent-prompts-page-2';
const _topic = 'agent.events';
const _subscriptionHandlePrefix = 'agent-subscription';
const _registrationId = 101;
const _subscriptionId = 202;
const _wampSessionId = 404;
const _sessionCount = 1;
const _publicationId = 303;
const _firstEventId = 'agent-session:get:1';

Future<void> main() async {
  final endpoint = await _AgentMcpEndpoint.bind();
  ConnectanumHttpAuthClient? authClient;
  McpStreamableHttpClient? client;

  try {
    authClient = ConnectanumHttpAuthClient(
      endpoint.authUri,
      headers: const <String, String>{
        'x-consumer-default': 'client-auth-default',
      },
    );
    await _smokeNonJsonAuthError(endpoint);

    final grant = await authClient.issueTicketToken(
      realm: _authRealm,
      authId: _authId,
      ticket: _ticketSecret,
      headers: const <String, String>{'x-consumer-trace': 'auth-issue'},
    );
    _expect(
      grant.accessToken == _accessToken,
      'auth grant access token mismatch',
    );
    _expect(
      grant.refreshToken == _refreshToken,
      'auth grant refresh token mismatch',
    );
    _expect(grant.realm == _authRealm, 'auth grant realm mismatch');
    _expect(grant.authId == _authId, 'auth grant authid mismatch');
    _expect(grant.authRole == _authRole, 'auth grant authrole mismatch');
    _expect(grant.authMethod == 'ticket', 'auth grant method mismatch');
    _expect(grant.authProvider == _authProvider, 'auth grant provider mismatch');
    _expect(
      endpoint.authRequestBodies.length == 2,
      'auth client did not complete challenge and token requests',
    );
    _expect(
      endpoint.authTraceHeaders.length == 2 &&
          endpoint.authTraceHeaders.every((trace) => trace == 'auth-issue'),
      'auth client did not forward per-call trace headers',
    );
    _expect(
      endpoint.authDefaultHeaders.length == 2 &&
          endpoint.authDefaultHeaders.every(
            (trace) => trace == 'client-auth-default',
          ),
      'auth client did not forward default auth headers',
    );

    await _smokeMalformedResponseSessionHeader(endpoint);

    client = McpStreamableHttpClient.withAuthGrant(endpoint.uri, grant);
    await _smokeAuthGrantDirectJsonBeforeLifecycle(client, endpoint);
    await _smokeAuthGrantRefreshAndRevokeLifecycle(
      authClient,
      grant,
      endpoint,
    );

    final initialize = await client.initialize(
      clientInfo: const <String, Object?>{
        'name': 'consumer-agent-smoke',
        'version': '0.1.0',
      },
      headers: const <String, String>{
        'x-consumer-trace': 'streamable-initialize',
      },
    );
    _expect(client.sessionId == _sessionId, 'initialize did not capture session');
    final initializeResult = _jsonMapFrom(
      initialize['result'],
      label: 'initialize result',
    );
    _expect(
      initializeResult['protocolVersion'] == _protocolVersion,
      'initialize returned an unexpected protocol version',
    );

    await client.notifyInitialized(
      headers: const <String, String>{
        'x-consumer-trace': 'streamable-initialized',
      },
    );

    final tools = await client.listTools(
      id: 'tools-json',
      streamable: false,
      headers: const <String, String>{
        'x-consumer-trace': 'typed-tools-json',
      },
    );
    _expect(
      tools.tools.any((tool) => tool['name'] == _toolName),
      'tools/list failed',
    );
    _expect(tools.nextCursor == _toolCursor, 'tools/list missed nextCursor');
    final toolPage = await client.listTools(
      id: 'tools-json-page-2',
      cursor: tools.nextCursor,
      streamable: false,
      headers: const <String, String>{
        'x-consumer-trace': 'typed-tools-json-page-2',
      },
    );
    _expect(
      toolPage.tools.single['name'] == _pagedToolName &&
          toolPage.nextCursor == null,
      'tools/list cursor page failed',
    );

    final toolResult = await client.callToolDirect(
      _toolName,
      id: 'direct-call',
      arguments: const <String, Object?>{'text': 'ready'},
      headers: const <String, String>{
        'x-consumer-trace': 'direct-tool-call',
      },
    );
    final structuredContent = _jsonMapFrom(
      toolResult['structuredContent'],
      label: 'structured content',
    );
    final echo = _jsonMapFrom(structuredContent['echo'], label: 'echo');
    _expect(
      echo['text'] == 'ready',
      'tools/call returned an unexpected payload',
    );

    final directTools = await client.listToolsDirect(
      id: 'direct-tools',
      headers: const <String, String>{
        'x-consumer-trace': 'direct-tools-list',
      },
    );
    _expect(
      directTools.tools.any((tool) => tool['name'] == _toolName),
      'direct JSON tools/list failed',
    );
    _expect(
      directTools.nextCursor == _toolCursor,
      'direct JSON tools/list missed nextCursor',
    );
    final directToolPage = await client.listToolsDirect(
      id: 'direct-tools-page-2',
      cursor: directTools.nextCursor,
      headers: const <String, String>{
        'x-consumer-trace': 'direct-tools-list-page-2',
      },
    );
    _expect(
      directToolPage.tools.single['name'] == _pagedToolName &&
          directToolPage.nextCursor == null,
      'direct JSON tools/list cursor page failed',
    );
    _expect(
      endpoint.sawDirectRequestWithoutSession,
      'direct JSON request included Streamable HTTP session state',
    );
    _expect(
      endpoint.directTraceHeadersWithoutSession.contains('direct-tools-list'),
      'direct JSON tools helper did not forward custom headers without '
      'Streamable session state',
    );
    _expect(
      endpoint.directTraceHeadersWithoutSession.contains(
        'direct-tools-list-page-2',
      ),
      'direct JSON tools cursor helper did not forward custom headers without '
      'Streamable session state',
    );

    await _smokeGenericJsonRpcApi(client, endpoint);
    await _smokeStreamableSseResponseSelection(client);
    await _smokeStreamablePollNonSseSessionIsolation(client);
    await _smokeMalformedPostResponseSessionIsolation(client);
    await _smokeControlledMcpRequestHeaders(client, endpoint);
    await _smokeDirectJsonHttpErrorsPreserveSession(client, endpoint);
    await _smokeGenericJsonRpcBatchErrors(client);
    await _smokeGenericJsonRpcBatchPubSub(client, endpoint);
    await _smokeGenericJsonRpcBatchResourcesAndPrompts(client, endpoint);
    await _smokeDirectToolApi(client, endpoint);
    await _smokeResourcesAndPrompts(client, endpoint);
    await _smokeWampHelpers(client, endpoint);
    await _smokeStreamableSessionLifecycle(client, endpoint);

    print('MCP client-only consumer package smoke completed.');
  } finally {
    client?.close(force: true);
    authClient?.close(force: true);
    await endpoint.close();
  }
}

Future<void> _smokeNonJsonAuthError(_AgentMcpEndpoint endpoint) async {
  final authClient = ConnectanumHttpAuthClient(
    endpoint.authTextErrorUri,
    headers: const <String, String>{
      'x-consumer-default': 'client-auth-default',
    },
  );
  try {
    await authClient.issueTicketToken(
      realm: _authRealm,
      authId: _authId,
      ticket: _ticketSecret,
      headers: const <String, String>{'x-consumer-trace': 'auth-text-error'},
    );
    throw StateError('auth client accepted a non-JSON auth error body');
  } on ConnectanumHttpAuthException catch (error) {
    _expect(
      error.statusCode == HttpStatus.serviceUnavailable,
      'non-JSON auth error returned ${error.statusCode}, expected 503',
    );
    _expect(
      error.body.contains('auth bridge unavailable'),
      'non-JSON auth error did not preserve the raw response body',
    );
    _expect(
      error.error == null,
      'non-JSON auth error exposed a decoded error payload',
    );
  } finally {
    authClient.close(force: true);
  }

  _expect(
    endpoint.authTextErrorBodies.length == 1,
    'non-JSON auth error smoke did not send exactly one challenge request',
  );
  _expect(
    endpoint.authTextErrorTraceHeaders.single == 'auth-text-error',
    'non-JSON auth error smoke did not forward per-call auth headers',
  );
}

Future<void> _smokeAuthGrantDirectJsonBeforeLifecycle(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  _expect(
    client.sessionId == null && client.lastEventId == null,
    'auth-grant direct JSON smoke started with Streamable session state',
  );

  const staleAuthHeaders = <String, String>{
    'Authorization': 'Bearer stale-agent-token',
  };

  final ping = await client.pingDirect(
    id: 'auth-grant-direct-ping',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-ping',
    },
  );
  _expect(ping.isEmpty, 'auth-grant direct JSON ping failed');

  final tools = await client.listToolsDirect(
    id: 'auth-grant-direct-tools',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-tools',
    },
  );
  _expect(
    tools.tools.any((tool) => tool['name'] == _toolName),
    'auth-grant direct JSON tools/list missed $_toolName',
  );

  final api = await client.listWampApiDirect(
    id: 'auth-grant-direct-api',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-api',
    },
  );
  _expect(
    jsonEncode(api).contains(_procedureName),
    'auth-grant direct JSON WAMP API helper failed',
  );

  final resources = await client.listResourcesDirect(
    id: 'auth-grant-direct-resources',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-resources',
    },
  );
  _expect(
    resources.resources.single['uri'] == _resourceUri,
    'auth-grant direct JSON resources/list failed',
  );

  final readResource = await client.readResourceDirect(
    _resourceUri,
    id: 'auth-grant-direct-resource-read',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-resource-read',
    },
  );
  _expect(
    readResource.single['text'] == 'agent context is available',
    'auth-grant direct JSON resources/read failed',
  );

  final templates = await client.listResourceTemplatesDirect(
    id: 'auth-grant-direct-resource-templates',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-resource-templates',
    },
  );
  _expect(
    templates.resourceTemplates.single['uriTemplate'] == _resourceTemplateUri,
    'auth-grant direct JSON resources/templates/list failed',
  );

  final prompts = await client.listPromptsDirect(
    id: 'auth-grant-direct-prompts',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-prompts',
    },
  );
  _expect(
    prompts.prompts.single['name'] == _promptName,
    'auth-grant direct JSON prompts/list failed',
  );

  final prompt = await client.getPromptDirect(
    _promptName,
    id: 'auth-grant-direct-prompt-get',
    arguments: const <String, String>{
      'taskId': 'T-auth-grant-direct-prompt',
    },
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-prompt-get',
    },
  );
  _expect(
    jsonEncode(prompt).contains('T-auth-grant-direct-prompt'),
    'auth-grant direct JSON prompts/get failed',
  );

  final sessionCount = await client.countWampSessionsDirect(
    id: 'auth-grant-direct-wamp-session-count',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-session-count',
    },
  );
  _expect(
    sessionCount.procedure == 'wamp.session.count' &&
        sessionCount.argumentsKeywords['count'] == _sessionCount,
    'auth-grant direct JSON WAMP session count failed',
  );

  final sessionList = await client.listWampSessionsDirect(
    id: 'auth-grant-direct-wamp-session-list',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-session-list',
    },
  );
  final sessionIds = sessionList.argumentsKeywords['session_ids'];
  _expect(
    sessionList.procedure == 'wamp.session.list' &&
        sessionIds is List &&
        sessionIds.contains(_wampSessionId),
    'auth-grant direct JSON WAMP session list failed',
  );

  final session = await client.getWampSessionDirect(
    _wampSessionId,
    id: 'auth-grant-direct-wamp-session-get',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-session-get',
    },
  );
  final sessionDetails = session.argumentsKeywords['details'];
  _expect(
    session.procedure == 'wamp.session.get' &&
        sessionDetails is Map &&
        sessionDetails['session'] == _wampSessionId &&
        sessionDetails['authid'] == _authId &&
        sessionDetails['authrole'] == _authRole,
    'auth-grant direct JSON WAMP session get failed',
  );

  final registrations = await client.listWampRegistrationsDirect(
    id: 'auth-grant-direct-wamp-registration-list',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-registration-list',
    },
  );
  _expect(
    _jsonListContains(registrations.argumentsKeywords['exact'], _registrationId),
    'auth-grant direct JSON WAMP registration list failed',
  );

  final lookupRegistration = await client.lookupWampRegistrationDirect(
    _procedureName,
    id: 'auth-grant-direct-wamp-registration-lookup',
    match: 'exact',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-registration-lookup',
    },
  );
  _expect(
    lookupRegistration.arguments.single == _registrationId,
    'auth-grant direct JSON WAMP registration lookup failed',
  );

  final matchingRegistration = await client.matchWampRegistrationDirect(
    _procedureName,
    id: 'auth-grant-direct-wamp-registration-match',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-registration-match',
    },
  );
  _expect(
    matchingRegistration.arguments.single == _registrationId,
    'auth-grant direct JSON WAMP registration match failed',
  );

  final registration = await client.getWampRegistrationDirect(
    _registrationId,
    id: 'auth-grant-direct-wamp-registration-get',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-registration-get',
    },
  );
  _expect(
    registration.argumentsKeywords['uri'] == _procedureName,
    'auth-grant direct JSON WAMP registration get failed',
  );

  final callees = await client.listWampRegistrationCalleesDirect(
    _registrationId,
    id: 'auth-grant-direct-wamp-registration-callees',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-registration-callees',
    },
  );
  _expect(
    callees.arguments.single == _wampSessionId,
    'auth-grant direct JSON WAMP registration callee list failed',
  );

  final calleeCount = await client.countWampRegistrationCalleesDirect(
    _registrationId,
    id: 'auth-grant-direct-wamp-registration-callee-count',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-registration-callee-count',
    },
  );
  _expect(
    calleeCount.arguments.single == 1,
    'auth-grant direct JSON WAMP registration callee count failed',
  );

  final subscriptions = await client.listWampSubscriptionsDirect(
    id: 'auth-grant-direct-wamp-subscription-list',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-subscription-list',
    },
  );
  _expect(
    _jsonListContains(subscriptions.argumentsKeywords['exact'], _subscriptionId),
    'auth-grant direct JSON WAMP subscription list failed',
  );

  final lookupSubscription = await client.lookupWampSubscriptionDirect(
    _topic,
    id: 'auth-grant-direct-wamp-subscription-lookup',
    match: 'exact',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-subscription-lookup',
    },
  );
  _expect(
    lookupSubscription.arguments.single == _subscriptionId,
    'auth-grant direct JSON WAMP subscription lookup failed',
  );

  final matchingSubscription = await client.matchWampSubscriptionDirect(
    _topic,
    id: 'auth-grant-direct-wamp-subscription-match',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-subscription-match',
    },
  );
  _expect(
    matchingSubscription.arguments.single == _subscriptionId,
    'auth-grant direct JSON WAMP subscription match failed',
  );

  final subscriptionMeta = await client.getWampSubscriptionDirect(
    _subscriptionId,
    id: 'auth-grant-direct-wamp-subscription-get',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-subscription-get',
    },
  );
  _expect(
    subscriptionMeta.argumentsKeywords['uri'] == _topic,
    'auth-grant direct JSON WAMP subscription get failed',
  );

  final subscribers = await client.listWampSubscriptionSubscribersDirect(
    _subscriptionId,
    id: 'auth-grant-direct-wamp-subscription-subscribers',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-subscription-subscribers',
    },
  );
  _expect(
    subscribers.arguments.single == _wampSessionId,
    'auth-grant direct JSON WAMP subscription subscriber list failed',
  );

  final subscriberCount = await client.countWampSubscriptionSubscribersDirect(
    _subscriptionId,
    id: 'auth-grant-direct-wamp-subscription-subscriber-count',
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-subscription-subscriber-count',
    },
  );
  _expect(
    subscriberCount.arguments.single == 1,
    'auth-grant direct JSON WAMP subscription subscriber count failed',
  );

  final subscription = await client.subscribeWampTopicDirect(
    _topic,
    id: 'auth-grant-direct-pubsub-subscribe',
    queueLimit: 2,
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-pubsub-subscribe',
    },
  );
  try {
    _expect(
      subscription.topic == _topic &&
          subscription.queueLimit == 2 &&
          subscription.handle.isNotEmpty,
      'auth-grant direct JSON pub/sub subscribe failed',
    );
    final publication = await client.publishWampEventDirect(
      _topic,
      id: 'auth-grant-direct-pubsub-publish',
      argumentsKeywords: const <String, Object?>{
        'taskId': 'T-auth-grant-direct-pubsub',
      },
      acknowledge: true,
      headers: const <String, String>{
        ...staleAuthHeaders,
        'x-consumer-trace': 'auth-grant-direct-pubsub-publish',
      },
    );
    _expect(
      publication.topic == _topic && publication.acknowledged,
      'auth-grant direct JSON pub/sub publish failed',
    );
    final events = await client.pollWampEventsDirect(
      subscription.handle,
      id: 'auth-grant-direct-pubsub-poll',
      headers: const <String, String>{
        ...staleAuthHeaders,
        'x-consumer-trace': 'auth-grant-direct-pubsub-poll',
      },
    );
    _expect(
      events.handle == subscription.handle &&
          events.topic == _topic &&
          jsonEncode(events.events).contains('T-auth-grant-direct-pubsub'),
      'auth-grant direct JSON pub/sub poll missed the published event',
    );
  } finally {
    await client.unsubscribeWampTopicDirect(
      subscription.handle,
      id: 'auth-grant-direct-pubsub-unsubscribe',
      headers: const <String, String>{
        ...staleAuthHeaders,
        'x-consumer-trace': 'auth-grant-direct-pubsub-unsubscribe',
      },
    );
  }

  await client.notifyToolDirect(
    _toolName,
    arguments: const <String, Object?>{
      'text': 'auth grant direct tool notification',
    },
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-tool-notification',
      'Mcp-Param-Text': 'wrong',
    },
  );

  await client.notifyConnectanumToolDirect(
    'connectanum.pubsub.publish',
    arguments: const <String, Object?>{
      'topic': _topic,
      'argumentsKeywords': <String, Object?>{
        'taskId': 'T-auth-grant-direct-tool-pubsub-notification',
      },
    },
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-tool-pubsub-notification',
      'Mcp-Param-Topic': 'wrong-topic',
    },
  );

  await client.notifyConnectanumMethodDirect(
    'connectanum.pubsub.publish',
    params: const <String, Object?>{
      'topic': _topic,
      'argumentsKeywords': <String, Object?>{
        'taskId': 'T-auth-grant-direct-method-pubsub-notification',
      },
    },
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-method-pubsub-notification',
      'Mcp-Param-Topic': 'wrong-topic',
    },
  );

  await client.notifyWampEventDirect(
    _topic,
    argumentsKeywords: const <String, Object?>{
      'taskId': 'T-auth-grant-direct-wamp-pubsub-notification',
    },
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-wamp-pubsub-notification',
      'Mcp-Param-Topic': 'wrong-topic',
    },
  );

  final batch = await client.postBatchDirect(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'auth-grant-direct-batch-tools',
        'method': 'tools/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'auth-grant-direct-batch-api',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'connectanum.api.list',
          'arguments': <String, Object?>{},
        },
      },
    ],
    headers: const <String, String>{
      ...staleAuthHeaders,
      'x-consumer-trace': 'auth-grant-direct-batch',
    },
  );
  _expect(
    batch != null && batch.length == 2,
    'auth-grant direct JSON batch returned an unexpected response set',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        batch![0],
        id: 'auth-grant-direct-batch-tools',
        label: 'auth-grant direct batch tools/list',
      )['tools'],
    ).contains(_toolName),
    'auth-grant direct JSON batch tools/list missed $_toolName',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        batch[1],
        id: 'auth-grant-direct-batch-api',
        label: 'auth-grant direct batch API list',
      ),
    ).contains(_procedureName),
    'auth-grant direct JSON batch API list failed',
  );

  _expect(
    client.sessionId == null && client.lastEventId == null,
    'auth-grant direct JSON smoke created Streamable session state',
  );
  const expectedTraces = <String>{
    'auth-grant-direct-ping',
    'auth-grant-direct-tools',
    'auth-grant-direct-api',
    'auth-grant-direct-resources',
    'auth-grant-direct-resource-read',
    'auth-grant-direct-resource-templates',
    'auth-grant-direct-prompts',
    'auth-grant-direct-prompt-get',
    'auth-grant-direct-wamp-session-count',
    'auth-grant-direct-wamp-session-list',
    'auth-grant-direct-wamp-session-get',
    'auth-grant-direct-wamp-registration-list',
    'auth-grant-direct-wamp-registration-lookup',
    'auth-grant-direct-wamp-registration-match',
    'auth-grant-direct-wamp-registration-get',
    'auth-grant-direct-wamp-registration-callees',
    'auth-grant-direct-wamp-registration-callee-count',
    'auth-grant-direct-wamp-subscription-list',
    'auth-grant-direct-wamp-subscription-lookup',
    'auth-grant-direct-wamp-subscription-match',
    'auth-grant-direct-wamp-subscription-get',
    'auth-grant-direct-wamp-subscription-subscribers',
    'auth-grant-direct-wamp-subscription-subscriber-count',
    'auth-grant-direct-pubsub-subscribe',
    'auth-grant-direct-pubsub-publish',
    'auth-grant-direct-pubsub-poll',
    'auth-grant-direct-pubsub-unsubscribe',
    'auth-grant-direct-tool-notification',
    'auth-grant-direct-tool-pubsub-notification',
    'auth-grant-direct-method-pubsub-notification',
    'auth-grant-direct-wamp-pubsub-notification',
    'auth-grant-direct-batch',
  };
  _expect(
    endpoint.directTraceHeadersWithoutSession.containsAll(expectedTraces),
    'auth-grant direct JSON smoke forwarded Streamable session state',
  );
  for (final trace in expectedTraces) {
    _expect(
      endpoint.directAuthorizationHeadersByTrace[trace] ==
          'Bearer $_accessToken',
      'auth-grant direct JSON $trace did not keep the grant bearer token',
    );
  }
  const expectedNotificationMethodsByTrace = <String, String>{
    'auth-grant-direct-tool-notification': 'tools/call',
    'auth-grant-direct-tool-pubsub-notification': 'connectanum.tool.call',
    'auth-grant-direct-method-pubsub-notification':
        'connectanum.pubsub.publish',
    'auth-grant-direct-wamp-pubsub-notification': 'connectanum.pubsub.publish',
  };
  for (final entry in expectedNotificationMethodsByTrace.entries) {
    final headers = endpoint.directMcpStandardHeadersByTrace[entry.key];
    _expect(
      headers?['mcp-method'] == entry.value,
      'auth-grant direct JSON ${entry.key} missed its MCP method header',
    );
  }
  final toolNotificationHeaders =
      endpoint.directMcpStandardHeadersByTrace[
        'auth-grant-direct-tool-notification'
      ];
  final toolPubSubNotificationHeaders =
      endpoint.directMcpStandardHeadersByTrace[
        'auth-grant-direct-tool-pubsub-notification'
      ];
  _expect(
    toolNotificationHeaders?['mcp-name'] == _toolName,
    'auth-grant direct JSON tool notification missed its MCP name header',
  );
  _expect(
    toolPubSubNotificationHeaders?['mcp-name'] ==
        'connectanum.pubsub.publish',
    'auth-grant direct JSON pub/sub tool notification missed its MCP name '
    'header',
  );
  const expectedDirectToolNames = <String>{
    'connectanum.api.list',
    'connectanum.pubsub.subscribe',
    'connectanum.pubsub.publish',
    'connectanum.pubsub.poll',
    'connectanum.pubsub.unsubscribe',
    'wamp.session.count',
    'wamp.session.list',
    'wamp.session.get',
    'wamp.registration.list',
    'wamp.registration.lookup',
    'wamp.registration.match',
    'wamp.registration.get',
    'wamp.registration.list_callees',
    'wamp.registration.count_callees',
    'wamp.subscription.list',
    'wamp.subscription.lookup',
    'wamp.subscription.match',
    'wamp.subscription.get',
    'wamp.subscription.list_subscribers',
    'wamp.subscription.count_subscribers',
  };
  final missingDirectToolNames = expectedDirectToolNames.difference(
    endpoint.directToolNamesWithoutSession,
  );
  _expect(
    missingDirectToolNames.isEmpty,
    'auth-grant direct JSON smoke missed lifecycle-free WAMP tools: '
    '${missingDirectToolNames.join(', ')}',
  );
}

Future<void> _smokeAuthGrantRefreshAndRevokeLifecycle(
  ConnectanumHttpAuthClient authClient,
  ConnectanumHttpAuthGrant grant,
  _AgentMcpEndpoint endpoint,
) async {
  _expect(
    grant.refreshToken == _refreshToken,
    'auth grant refresh lifecycle started with an unexpected refresh token',
  );

  final refreshed = await authClient.refreshToken(
    grant.refreshToken!,
    headers: const <String, String>{'x-consumer-trace': 'auth-refresh'},
  );
  _expect(
    refreshed.accessToken == _refreshedAccessToken,
    'auth refresh returned an unexpected access token',
  );
  _expect(
    refreshed.refreshToken == _refreshedRefreshToken,
    'auth refresh returned an unexpected refresh token',
  );
  _expect(refreshed.realm == _authRealm, 'auth refresh realm mismatch');
  _expect(refreshed.authId == _authId, 'auth refresh authid mismatch');
  _expect(refreshed.authRole == _authRole, 'auth refresh authrole mismatch');
  _expect(
    refreshed.authProvider == _authProvider,
    'auth refresh provider mismatch',
  );

  try {
    await authClient.refreshToken(
      grant.refreshToken!,
      headers: const <String, String>{
        'x-consumer-trace': 'auth-refresh-rotated',
      },
    );
    throw StateError('auth refresh accepted a rotated refresh token');
  } on ConnectanumHttpAuthException catch (error) {
    _expect(
      error.statusCode == HttpStatus.unauthorized,
      'rotated refresh token returned ${error.statusCode}, expected 401',
    );
  }

  final refreshedClient = McpStreamableHttpClient.withAuthGrant(
    endpoint.uri,
    refreshed,
  );
  try {
    final ping = await refreshedClient.pingDirect(
      id: 'auth-refresh-direct-ping',
      headers: const <String, String>{
        'Authorization': 'Bearer stale-refreshed-agent-token',
        'x-consumer-trace': 'auth-refresh-direct-ping',
      },
    );
    _expect(ping.isEmpty, 'auth refresh direct JSON ping failed');
    _expect(
      refreshedClient.sessionId == null && refreshedClient.lastEventId == null,
      'auth refresh direct JSON ping created Streamable session state',
    );
    _expect(
      endpoint.directTraceHeadersWithoutSession.contains(
        'auth-refresh-direct-ping',
      ),
      'auth refresh direct JSON ping forwarded Streamable session state',
    );
    _expect(
      endpoint.directAuthorizationHeadersByTrace['auth-refresh-direct-ping'] ==
          'Bearer $_refreshedAccessToken',
      'auth refresh direct JSON ping did not use the refreshed bearer token',
    );

    await authClient.revokeToken(
      refreshed.accessToken,
      tokenTypeHint: 'access_token',
      headers: const <String, String>{'x-consumer-trace': 'auth-revoke'},
    );

    try {
      await refreshedClient.pingDirect(
        id: 'auth-revoked-direct-ping',
        headers: const <String, String>{
          'x-consumer-trace': 'auth-revoked-direct-ping',
        },
      );
      throw StateError('auth revoke left a refreshed access token usable');
    } on McpStreamableHttpException catch (error) {
      _expect(
        error.statusCode == HttpStatus.unauthorized,
        'revoked access token returned ${error.statusCode}, expected 401',
      );
    }
    _expect(
      refreshedClient.sessionId == null && refreshedClient.lastEventId == null,
      'revoked auth direct JSON ping created Streamable session state',
    );

    await authClient.revokeToken(
      refreshed.refreshToken!,
      tokenTypeHint: 'refresh_token',
      headers: const <String, String>{
        'x-consumer-trace': 'auth-revoke-refresh',
      },
    );

    try {
      await authClient.refreshToken(
        refreshed.refreshToken!,
        headers: const <String, String>{
          'x-consumer-trace': 'auth-refresh-revoked',
        },
      );
      throw StateError('auth refresh accepted a revoked refresh token');
    } on ConnectanumHttpAuthException catch (error) {
      _expect(
        error.statusCode == HttpStatus.unauthorized,
        'revoked refresh token returned ${error.statusCode}, expected 401',
      );
    }
  } finally {
    refreshedClient.close(force: true);
  }

  _expect(
    endpoint.authRequestBodies.length == 7,
    'auth refresh/revoke smoke did not add refresh and revoke requests',
  );
  _expect(
    const <String>{
      'auth-refresh',
      'auth-refresh-rotated',
      'auth-revoke',
      'auth-revoke-refresh',
      'auth-refresh-revoked',
    }.every((trace) => endpoint.authTraceHeaders.contains(trace)),
    'auth refresh/revoke smoke did not forward per-call auth headers',
  );
  _expect(
    endpoint.authRequestBodies.any(
      (body) =>
          body['grant_type'] == 'refresh_token' &&
          body['refresh_token'] == _refreshToken,
    ),
    'auth refresh request body was not sent as expected',
  );
  _expect(
    endpoint.authRequestBodies
            .where(
              (body) =>
                  body['grant_type'] == 'refresh_token' &&
                  body['refresh_token'] == _refreshToken,
            )
            .length ==
        2,
    'rotated refresh-token request body was not sent as expected',
  );
  _expect(
    endpoint.authRequestBodies.any(
      (body) =>
          body['grant_type'] == 'revoke' &&
          body['token'] == _refreshedAccessToken &&
          body['token_type_hint'] == 'access_token',
    ),
    'auth revoke request body was not sent as expected',
  );
  _expect(
    endpoint.authRequestBodies.any(
      (body) =>
          body['grant_type'] == 'revoke' &&
          body['token'] == _refreshedRefreshToken &&
          body['token_type_hint'] == 'refresh_token',
    ),
    'auth refresh-token revoke request body was not sent as expected',
  );
  _expect(
    endpoint.authRequestBodies.any(
      (body) =>
          body['grant_type'] == 'refresh_token' &&
          body['refresh_token'] == _refreshedRefreshToken,
    ),
    'revoked refresh-token request body was not sent as expected',
  );
}

Future<void> _smokeMalformedResponseSessionHeader(
  _AgentMcpEndpoint endpoint,
) async {
  final client = McpStreamableHttpClient.withBearerToken(
    endpoint.uri,
    _accessToken,
  );
  try {
    try {
      await client.initialize(
        id: 'malformed-response-session',
        headers: const <String, String>{
          'x-test-response-session-id': 'malformed session',
        },
      );
      throw StateError(
        'MCP client accepted a malformed response MCP-Session-Id.',
      );
    } on McpStreamableProtocolException catch (error) {
      _expect(
        error.toString().contains('MCP-Session-Id'),
        'malformed response session error did not mention MCP-Session-Id',
      );
    }
    _expect(
      client.sessionId == null && client.lastEventId == null,
      'malformed response session poisoned client state',
    );

    try {
      await client.initialize(
        id: 'empty-response-session',
        headers: const <String, String>{
          'x-test-empty-response-session-id': '1',
        },
      );
      throw StateError('MCP client accepted an empty MCP-Session-Id.');
    } on McpStreamableProtocolException catch (error) {
      _expect(
        error.toString().contains('MCP-Session-Id'),
        'empty response session error did not mention MCP-Session-Id',
      );
    }
    _expect(
      client.sessionId == null && client.lastEventId == null,
      'empty response session poisoned client state',
    );

    final recovered = await client.initialize(
      id: 'recovered-after-malformed-session',
    );
    _expect(
      recovered['id'] == 'recovered-after-malformed-session' &&
          client.sessionId == _sessionId,
      'client did not recover after malformed response session',
    );
    await client.deleteSession();
    _expect(
      client.sessionId == null && client.lastEventId == null,
      'malformed response recovery cleanup did not clear session state',
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _smokeStreamableSseResponseSelection(
  McpStreamableHttpClient client,
) async {
  final sessionId = client.sessionId;
  final eventId = client.lastEventId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable SSE response selection smoke has no session.');
  }

  final response = await client.request(
    'tools/list',
    id: 'streamable-sse-response-selection',
    headers: const <String, String>{
      'x-test-sse-prefix-notification': '1',
    },
  );
  _expect(
    _jsonRpcResult(
      response,
      id: 'streamable-sse-response-selection',
      label: 'Streamable SSE response selection tools/list',
    ).containsKey('tools'),
    'Streamable SSE response selection returned the preceding notification',
  );
  _expect(
    client.lastEventId == 'agent-session:post:2',
    'Streamable SSE response selection did not capture the response event id',
  );
  final resetResponse = await client.request(
    'tools/list',
    id: 'streamable-sse-reset-event-id',
    headers: const <String, String>{
      'x-test-sse-reset-event-id': '1',
    },
  );
  _expect(
    _jsonRpcResult(
      resetResponse,
      id: 'streamable-sse-reset-event-id',
      label: 'Streamable SSE empty id reset tools/list',
    ).containsKey('tools'),
    'Streamable SSE empty id reset returned an invalid response',
  );
  _expect(
    client.lastEventId == null,
    'Streamable SSE empty id did not clear the resume cursor',
  );
  await client.poll();
  _expect(
    client.lastEventId == _firstEventId,
    'Streamable SSE empty id recovery poll did not resume without a stale cursor',
  );

  final batch = await client.postBatch(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'streamable-sse-batch-one',
        'method': 'tools/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'streamable-sse-batch-two',
        'method': 'ping',
      },
    ],
    headers: const <String, String>{
      'x-test-sse-split-batch-with-notification': '1',
    },
  );
  _expect(
    batch != null && batch.length == 2,
    'Streamable SSE batch response selection returned an invalid response set',
  );
  _expect(
    batch![0]['id'] == 'streamable-sse-batch-one' &&
        batch[1]['id'] == 'streamable-sse-batch-two',
    'Streamable SSE batch response selection did not preserve response ids',
  );
  _expect(
    client.lastEventId == 'agent-session:split-batch:3',
    'Streamable SSE batch response selection did not capture the last event id',
  );
  _expect(
    client.sessionId == sessionId,
    'Streamable SSE response selection changed the active session id',
  );
  client.lastEventId = eventId;
}

Future<void> _smokeStreamablePollNonSseSessionIsolation(
  McpStreamableHttpClient client,
) async {
  final sessionId = client.sessionId;
  final eventId = client.lastEventId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable non-SSE poll smoke has no session.');
  }

  const preservedEventId = 'agent-session:get:preserved';
  client.lastEventId = preservedEventId;
  try {
    await client.poll(
      headers: const <String, String>{
        'x-test-poll-json-response': '1',
        'x-test-response-session-id': 'agent-poll-json-session',
      },
    );
    throw StateError('MCP client accepted a non-SSE poll response.');
  } on FormatException catch (error) {
    _expect(
      error.message.contains('text/event-stream'),
      'non-SSE poll response error did not mention text/event-stream',
    );
  }

  _expect(
    client.sessionId == sessionId && client.lastEventId == preservedEventId,
    'non-SSE poll response poisoned Streamable session state',
  );

  client.lastEventId = null;
  final events = await client.poll();
  _expect(
    events.length == 1 && client.lastEventId == _firstEventId,
    'non-SSE poll recovery did not reuse the preserved session',
  );
  client.lastEventId = eventId;
}

Future<void> _smokeMalformedPostResponseSessionIsolation(
  McpStreamableHttpClient client,
) async {
  final sessionId = client.sessionId;
  final eventId = client.lastEventId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable malformed POST smoke has no session.');
  }

  const preservedJsonEventId = 'agent-session:get:preserved-json-post';
  client.lastEventId = preservedJsonEventId;
  try {
    await client.listTools(
      id: 'malformed-post-json',
      streamable: false,
      headers: const <String, String>{
        'x-test-malformed-json-response': '1',
        'x-test-response-session-id': 'agent-post-json-session',
      },
    );
    throw StateError('MCP client accepted malformed POST JSON.');
  } on FormatException {
    // Expected: malformed response bodies must not mutate session state.
  }
  _expect(
    client.sessionId == sessionId &&
        client.lastEventId == preservedJsonEventId,
    'malformed POST JSON poisoned Streamable session state',
  );

  const preservedJsonShapeEventId = 'agent-session:get:preserved-json-shape';
  client.lastEventId = preservedJsonShapeEventId;
  try {
    await client.listTools(
      id: 'malformed-post-json-shape',
      streamable: false,
      headers: const <String, String>{
        'x-test-json-array-response': '1',
        'x-test-response-session-id': 'agent-post-json-shape-session',
      },
    );
    throw StateError('MCP client accepted wrong-shape POST JSON.');
  } on FormatException {
    // Expected: valid JSON with the wrong response shape is still invalid.
  }
  _expect(
    client.sessionId == sessionId &&
        client.lastEventId == preservedJsonShapeEventId,
    'wrong-shape POST JSON poisoned Streamable session state',
  );

  const preservedSseEventId = 'agent-session:get:preserved-sse-post';
  client.lastEventId = preservedSseEventId;
  try {
    await client.listTools(
      id: 'malformed-post-sse',
      headers: const <String, String>{
        'x-test-malformed-sse-response': '1',
        'x-test-response-session-id': 'agent-post-sse-session',
      },
    );
    throw StateError('MCP client accepted malformed POST SSE data.');
  } on FormatException {
    // Expected: malformed SSE event data must not mutate session state.
  }
  _expect(
    client.sessionId == sessionId && client.lastEventId == preservedSseEventId,
    'malformed POST SSE poisoned Streamable session state',
  );

  const preservedMissingSseEventId = 'agent-session:get:preserved-missing-sse';
  client.lastEventId = preservedMissingSseEventId;
  try {
    await client.listTools(
      id: 'malformed-post-sse-missing',
      headers: const <String, String>{
        'x-test-sse-notification-only-response': '1',
        'x-test-response-session-id': 'agent-post-sse-missing-session',
      },
    );
    throw StateError('MCP client accepted POST SSE without a matching response.');
  } on FormatException {
    // Expected: POST/SSE streams must include a response for request ids.
  }
  _expect(
    client.sessionId == sessionId &&
        client.lastEventId == preservedMissingSseEventId,
    'missing POST SSE response poisoned Streamable session state',
  );

  try {
    await client.postBatch(
      const <Map<String, Object?>>[
        {'jsonrpc': '2.0', 'id': 'malformed-post-batch', 'method': 'tools/list'},
      ],
      streamable: false,
      headers: const <String, String>{
        'x-test-batch-json-object-response': '1',
        'x-test-response-session-id': 'agent-post-batch-shape-session',
      },
    );
    throw StateError('MCP client accepted wrong-shape POST batch JSON.');
  } on FormatException {
    // Expected: batch responses must remain arrays.
  }
  _expect(
    client.sessionId == sessionId &&
        client.lastEventId == preservedMissingSseEventId,
    'wrong-shape POST batch JSON poisoned Streamable session state',
  );

  const preservedNotificationJsonEventId =
      'agent-session:get:preserved-notification-json';
  client.lastEventId = preservedNotificationJsonEventId;
  try {
    await client.notification(
      'notifications/progress',
      params: const <String, Object?>{
        'progressToken': 'malformed-notification-json',
        'progress': 1,
      },
      headers: const <String, String>{
        'x-test-json-notification-response': '1',
        'x-test-response-session-id': 'agent-post-notification-json-session',
      },
    );
    throw StateError('MCP client accepted a POST notification JSON body.');
  } on FormatException {
    // Expected: notification-only POST responses must not carry a body.
  }
  _expect(
    client.sessionId == sessionId &&
        client.lastEventId == preservedNotificationJsonEventId,
    'POST notification JSON body poisoned Streamable session state',
  );

  const preservedNotificationSseEventId =
      'agent-session:get:preserved-notification-sse';
  client.lastEventId = preservedNotificationSseEventId;
  try {
    await client.notification(
      'notifications/tools/list_changed',
      headers: const <String, String>{
        'x-test-sse-notification-only-response': '1',
        'x-test-response-session-id': 'agent-post-notification-sse-session',
      },
    );
    throw StateError('MCP client accepted a POST notification SSE body.');
  } on FormatException {
    // Expected: notification-only POST/SSE responses must not carry events.
  }
  _expect(
    client.sessionId == sessionId &&
        client.lastEventId == preservedNotificationSseEventId,
    'POST notification SSE body poisoned Streamable session state',
  );

  const preservedNotificationBatchJsonEventId =
      'agent-session:get:preserved-notification-batch-json';
  client.lastEventId = preservedNotificationBatchJsonEventId;
  try {
    await client.postBatch(
      const <Map<String, Object?>>[
        {
          'jsonrpc': '2.0',
          'method': 'notifications/progress',
          'params': <String, Object?>{
            'progressToken': 'malformed-notification-batch-json',
            'progress': 1,
          },
        },
      ],
      headers: const <String, String>{
        'x-test-json-notification-response': '1',
        'x-test-response-session-id':
            'agent-post-notification-batch-json-session',
      },
    );
    throw StateError('MCP client accepted a notification-only batch JSON body.');
  } on FormatException {
    // Expected: notification-only batch responses must not carry a body.
  }
  _expect(
    client.sessionId == sessionId &&
        client.lastEventId == preservedNotificationBatchJsonEventId,
    'POST notification-only batch JSON body poisoned Streamable session state',
  );

  const preservedNotificationBatchSseEventId =
      'agent-session:get:preserved-notification-batch-sse';
  client.lastEventId = preservedNotificationBatchSseEventId;
  try {
    await client.postBatch(
      const <Map<String, Object?>>[
        {
          'jsonrpc': '2.0',
          'method': 'notifications/tools/list_changed',
        },
      ],
      headers: const <String, String>{
        'x-test-sse-notification-only-response': '1',
        'x-test-response-session-id':
            'agent-post-notification-batch-sse-session',
      },
    );
    throw StateError('MCP client accepted a notification-only batch SSE body.');
  } on FormatException {
    // Expected: notification-only batch POST/SSE responses must not carry events.
  }
  _expect(
    client.sessionId == sessionId &&
        client.lastEventId == preservedNotificationBatchSseEventId,
    'POST notification-only batch SSE body poisoned Streamable session state',
  );

  final tools = await client.listTools(
    id: 'malformed-post-recovery',
    streamable: false,
  );
  _expect(
    tools.tools.any((tool) => tool['name'] == _toolName),
    'malformed POST recovery did not reuse the preserved session',
  );
  _expect(
    client.sessionId == sessionId,
    'malformed POST recovery lost the active session',
  );
  client.lastEventId = eventId;
}

Future<void> _smokeGenericJsonRpcApi(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final sessionId = client.sessionId;
  final eventId = client.lastEventId;

  final ping = await client.request('ping', id: 'streamable-generic-ping');
  _expect(
    _jsonRpcResult(
      ping,
      id: 'streamable-generic-ping',
      label: 'streamable generic ping',
    ).isEmpty,
    'generic Streamable ping failed',
  );

  final directTools = await client.requestDirect(
    'tools/list',
    id: 'generic-direct-tools',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directTools,
        id: 'generic-direct-tools',
        label: 'generic direct tools/list',
      )['tools'],
    ).contains(_toolName),
    'generic direct JSON tools/list missed $_toolName',
  );

  final directToolCall = await client.requestDirect(
    'tools/call',
    id: 'generic-direct-tool-call',
    params: const <String, Object?>{
      'name': _toolName,
      'arguments': <String, Object?>{'text': 'generic direct'},
    },
  );
  _expect(
    _toolEchoText(
          _jsonRpcResult(
            directToolCall,
            id: 'generic-direct-tool-call',
            label: 'generic direct tool call',
          ),
          label: 'generic direct tool call',
        ) ==
        'generic direct',
    'generic direct JSON tool call failed',
  );

  final directBatch = await client.postBatchDirect(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-tools',
        'method': 'tools/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-tool-call',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': _toolName,
          'arguments': <String, Object?>{'text': 'generic batch'},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-dotted-tool',
        'method': _toolName,
        'params': <String, Object?>{'text': 'generic dotted batch'},
      },
    ],
    headers: const <String, String>{
      'x-consumer-trace': 'generic-direct-batch',
    },
  );
  _expect(
    directBatch != null && directBatch.length == 3,
    'generic direct JSON batch did not return three responses',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directBatch![0],
        id: 'generic-direct-batch-tools',
        label: 'generic direct batch tools/list',
      )['tools'],
    ).contains(_toolName),
    'generic direct JSON batch tools/list missed $_toolName',
  );
  _expect(
    _toolEchoText(
          _jsonRpcResult(
            directBatch[1],
            id: 'generic-direct-batch-tool-call',
            label: 'generic direct batch tool call',
          ),
          label: 'generic direct batch tool call',
        ) ==
        'generic batch',
    'generic direct JSON batch tool call failed',
  );
  _expect(
    _toolEchoText(
          _jsonRpcResult(
            directBatch[2],
            id: 'generic-direct-batch-dotted-tool',
            label: 'generic direct batch dotted tool',
          ),
          label: 'generic direct batch dotted tool',
        ) ==
        'generic dotted batch',
    'generic direct JSON batch dotted tool call failed',
  );

  final streamableBatch = await client.postBatch(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'streamable-batch-ping',
        'method': 'ping',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'streamable-batch-tools',
        'method': 'tools/list',
      },
    ],
  );
  _expect(
    streamableBatch != null && streamableBatch.length == 2,
    'generic Streamable batch did not return two responses',
  );
  _expect(
    _jsonRpcResult(
      streamableBatch![0],
      id: 'streamable-batch-ping',
      label: 'streamable batch ping',
    ).isEmpty,
    'generic Streamable batch ping failed',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        streamableBatch[1],
        id: 'streamable-batch-tools',
        label: 'streamable batch tools/list',
      )['tools'],
    ).contains(_toolName),
    'generic Streamable batch tools/list missed $_toolName',
  );

  final directNotificationBatch = await client.postBatchDirect(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': <String, Object?>{},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/progress',
        'params': <String, Object?>{
          'progressToken': 'generic-direct-notification-batch',
          'progress': 1,
        },
      },
    ],
    headers: const <String, String>{
      'x-consumer-trace': 'generic-direct-notification-batch',
    },
  );
  _expect(
    directNotificationBatch == null,
    'generic direct JSON notification-only batch returned a response',
  );

  final streamableNotificationBatch = await client.postBatch(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': <String, Object?>{},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/tools/list_changed',
        'params': <String, Object?>{},
      },
    ],
  );
  _expect(
    streamableNotificationBatch == null,
    'generic Streamable notification-only batch returned a response',
  );

  await client.notificationDirect(
    'notifications/progress',
    params: const <String, Object?>{
      'progressToken': 'generic-direct-single-notification',
      'progress': 1,
    },
  );
  await client.notification(
    'notifications/tools/list_changed',
    params: const <String, Object?>{},
  );

  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'generic direct JSON, notification, or batch APIs changed Streamable session state',
  );
  const expectedDirectTraceHeaders = <String>{
    'generic-direct-batch',
    'generic-direct-notification-batch',
  };
  final missingDirectTraceHeaders = expectedDirectTraceHeaders.difference(
    endpoint.directTraceHeadersWithoutSession,
  );
  _expect(
    missingDirectTraceHeaders.isEmpty,
    'generic direct JSON batches did not forward custom headers without '
    'session state for ${missingDirectTraceHeaders.join(', ')}',
  );
  const expectedDirectMethods = <String>{
    'tools/list',
    'tools/call',
    'notifications/progress',
    _toolName,
  };
  final missingDirectMethods = expectedDirectMethods.difference(
    endpoint.directMethodsWithoutSession,
  );
  _expect(
    missingDirectMethods.isEmpty,
    'generic direct JSON APIs included Streamable session state for '
    '${missingDirectMethods.join(', ')}',
  );
}

Future<void> _smokeDirectJsonHttpErrorsPreserveSession(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('direct HTTP-error smoke has no Streamable session.');
  }
  final eventId = client.lastEventId;

  const responseSessionTrace = 'direct-response-session-header';
  final responseSessionResult = await client.callConnectanumMethodDirect(
    _toolName,
    id: responseSessionTrace,
    params: const <String, Object?>{'message': 'success'},
    headers: const <String, String>{
      'x-consumer-trace': responseSessionTrace,
      'x-test-response-session-id': 'direct-session-header-ignored',
    },
  );
  _expect(
    responseSessionResult['isError'] == false,
    'direct JSON response-session smoke returned an error result.',
  );
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'direct JSON response session header changed Streamable session state',
  );
  _expect(
    endpoint.directTraceHeadersWithoutSession.contains(responseSessionTrace),
    'direct JSON response session header did not stay lifecycle-free',
  );

  const responseSessionBatchTrace = 'direct-response-session-batch-header';
  final responseSessionBatch = await client.postBatchDirect(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': responseSessionBatchTrace,
        'method': 'connectanum.tools.list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/progress',
        'params': <String, Object?>{
          'progressToken': responseSessionBatchTrace,
          'progress': 1,
        },
      },
    ],
    headers: const <String, String>{
      'x-consumer-trace': responseSessionBatchTrace,
      'x-test-response-session-id': 'direct-batch-session-header-ignored',
    },
  );
  _expect(
    responseSessionBatch != null &&
        responseSessionBatch.length == 1 &&
        responseSessionBatch.single['id'] == responseSessionBatchTrace,
    'direct JSON batch response-session smoke returned an unexpected result.',
  );
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'direct JSON batch response session header changed Streamable session '
    'state',
  );
  _expect(
    endpoint.directTraceHeadersWithoutSession.contains(
      responseSessionBatchTrace,
    ),
    'direct JSON batch response session header did not stay lifecycle-free',
  );

  const responseSessionNotificationTrace =
      'direct-response-session-notification-header';
  await client.notificationDirect(
    'notifications/progress',
    params: const <String, Object?>{
      'progressToken': responseSessionNotificationTrace,
      'progress': 1,
    },
    headers: const <String, String>{
      'x-consumer-trace': responseSessionNotificationTrace,
      'x-test-response-session-id':
          'direct-notification-session-header-ignored',
    },
  );
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'direct JSON notification response session header changed Streamable '
    'session state',
  );
  _expect(
    endpoint.directTraceHeadersWithoutSession.contains(
      responseSessionNotificationTrace,
    ),
    'direct JSON notification response session header did not stay '
    'lifecycle-free',
  );

  const responseBodyNotificationTrace = 'direct-notification-body-rejected';
  try {
    await client.notificationDirect(
      'notifications/progress',
      params: const <String, Object?>{
        'progressToken': responseBodyNotificationTrace,
        'progress': 1,
      },
      headers: const <String, String>{
        'x-consumer-trace': responseBodyNotificationTrace,
        'x-test-json-notification-response': '1',
        'x-test-response-session-id': 'direct-notification-body-ignored',
      },
    );
    throw StateError('direct JSON notification accepted a response body.');
  } on FormatException catch (error) {
    _expect(
      error.message.contains('notification response must not include a body'),
      'direct JSON notification rejected with unexpected error: $error',
    );
  }
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'direct JSON notification response body changed Streamable session state',
  );
  _expect(
    endpoint.directTraceHeadersWithoutSession.contains(
      responseBodyNotificationTrace,
    ),
    'direct JSON notification response body did not stay lifecycle-free',
  );

  const responseSessionNotificationBatchTrace =
      'direct-response-session-notification-batch-header';
  final responseSessionNotificationBatch = await client.postBatchDirect(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/progress',
        'params': <String, Object?>{
          'progressToken': responseSessionNotificationBatchTrace,
          'progress': 1,
        },
      },
    ],
    headers: const <String, String>{
      'x-consumer-trace': responseSessionNotificationBatchTrace,
      'x-test-response-session-id':
          'direct-notification-batch-session-header-ignored',
    },
  );
  _expect(
    responseSessionNotificationBatch == null,
    'direct JSON notification-only batch response-session smoke returned '
    'a response body.',
  );
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'direct JSON notification-only batch response session header changed '
    'Streamable session state',
  );
  _expect(
    endpoint.directTraceHeadersWithoutSession.contains(
      responseSessionNotificationBatchTrace,
    ),
    'direct JSON notification-only batch response session header did not stay '
    'lifecycle-free',
  );

  const responseBodyNotificationBatchTrace =
      'direct-notification-batch-body-rejected';
  try {
    await client.postBatchDirect(
      const <McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/progress',
          'params': <String, Object?>{
            'progressToken': responseBodyNotificationBatchTrace,
            'progress': 1,
          },
        },
      ],
      headers: const <String, String>{
        'x-consumer-trace': responseBodyNotificationBatchTrace,
        'x-test-json-notification-response': '1',
        'x-test-response-session-id':
            'direct-notification-batch-body-ignored',
      },
    );
    throw StateError(
      'direct JSON notification-only batch accepted a response body.',
    );
  } on FormatException catch (error) {
    _expect(
      error.message.contains(
        'notification-only batch response must not include a body',
      ),
      'direct JSON notification-only batch rejected with unexpected error: '
      '$error',
    );
  }
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'direct JSON notification-only batch response body changed Streamable '
    'session state',
  );
  _expect(
    endpoint.directTraceHeadersWithoutSession.contains(
      responseBodyNotificationBatchTrace,
    ),
    'direct JSON notification-only batch response body did not stay '
    'lifecycle-free',
  );

  for (final statusCode in const <int>[
    HttpStatus.unauthorized,
    HttpStatus.forbidden,
    HttpStatus.notFound,
  ]) {
    final trace = 'direct-http-error-$statusCode';
    try {
      await client.callConnectanumMethodDirect(
        'agent.direct.http-error',
        id: trace,
        params: <String, Object?>{'statusCode': statusCode},
        headers: <String, String>{
          'x-consumer-trace': trace,
          'x-test-force-status': '$statusCode',
          'x-test-response-session-id': 'direct-error-session-$statusCode',
        },
      );
      throw StateError('direct JSON HTTP-error smoke accepted $statusCode.');
    } on McpStreamableHttpException catch (error) {
      if (error.statusCode != statusCode) {
        throw StateError(
          'direct JSON HTTP-error smoke returned ${error.statusCode} '
          'instead of $statusCode.',
        );
      }
    }

    _expect(
      client.sessionId == sessionId && client.lastEventId == eventId,
      'direct JSON HTTP $statusCode changed Streamable session state',
    );
    _expect(
      endpoint.directTraceHeadersWithoutSession.contains(trace),
      'direct JSON HTTP $statusCode did not stay lifecycle-free',
    );
  }

  final ping = await client.ping(id: 'direct-http-error-recovery');
  _expect(ping.isEmpty, 'Streamable ping failed after direct HTTP errors');
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'direct JSON HTTP-error recovery changed Streamable session state',
  );
}

Future<void> _smokeControlledMcpRequestHeaders(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('controlled MCP header smoke has no Streamable session.');
  }
  final eventId = client.lastEventId;

  const directTrace = 'controlled-direct-mcp-headers';
  final directResult = await client.callConnectanumMethodDirect(
    _toolName,
    id: directTrace,
    params: const <String, Object?>{'message': 'controlled headers'},
    headers: const <String, String>{
      HttpHeaders.acceptHeader: 'text/plain',
      'MCP-Protocol-Version': '2099-01-01',
      'MCP-Session-Id': 'caller-direct-session',
      'Last-Event-ID': 'caller-direct-event',
      'Mcp-Method': 'caller-direct-method',
      'Mcp-Name': 'caller.direct.name',
      'x-consumer-trace': directTrace,
    },
  );
  _expect(
    directResult['isError'] == false,
    'controlled MCP header direct JSON smoke returned an error result.',
  );
  _expect(
    endpoint.directTraceHeadersWithoutSession.contains(directTrace),
    'controlled MCP header direct JSON smoke forwarded caller session state',
  );
  final directStandardHeaders =
      endpoint.directMcpStandardHeadersByTrace[directTrace] ??
      const <String, String>{};
  _expect(
    directStandardHeaders['mcp-method'] == _toolName,
    'controlled MCP header direct JSON smoke forwarded caller method header',
  );
  _expect(
    !directStandardHeaders.containsKey('mcp-name'),
    'controlled MCP header direct JSON smoke forwarded caller name header',
  );
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'controlled MCP header direct JSON smoke changed Streamable session state',
  );

  const streamableTrace = 'controlled-streamable-mcp-headers';
  final streamablePing = await client.ping(
    id: streamableTrace,
    headers: const <String, String>{
      HttpHeaders.acceptHeader: 'text/plain',
      'MCP-Protocol-Version': '2099-02-01',
      'MCP-Session-Id': 'caller-streamable-session',
      'Last-Event-ID': 'caller-streamable-event',
      'Mcp-Method': 'caller-streamable-method',
      'Mcp-Name': 'caller.streamable.name',
      'x-consumer-trace': streamableTrace,
    },
  );
  _expect(
    streamablePing.isEmpty,
    'controlled MCP header Streamable ping smoke returned an error result',
  );
  _expect(
    endpoint.streamableTraceHeadersWithSession.contains(
      'POST:$streamableTrace',
    ),
    'controlled MCP header Streamable ping did not use the owned session',
  );
  final streamableStandardHeaders =
      endpoint.streamableMcpStandardHeadersByTrace[
        'POST:$streamableTrace'
      ] ??
      const <String, String>{};
  _expect(
    streamableStandardHeaders['mcp-method'] == 'ping',
    'controlled MCP header Streamable ping forwarded caller method header',
  );
  _expect(
    !streamableStandardHeaders.containsKey('mcp-name'),
    'controlled MCP header Streamable ping forwarded caller name header',
  );
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'controlled MCP header Streamable ping changed session state',
  );

  const pollTrace = 'controlled-poll-mcp-headers';
  client.lastEventId = null;
  final events = await client.poll(
    headers: const <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
      'MCP-Session-Id': 'caller-poll-session',
      'Last-Event-ID': 'caller-poll-event',
      'Mcp-Method': 'caller-poll-method',
      'Mcp-Name': 'caller.poll.name',
      'x-consumer-trace': pollTrace,
    },
  );
  _expect(
    events.single.jsonData?['method'] == 'notifications/tools/list_changed',
    'controlled MCP header poll smoke did not return the expected event',
  );
  _expect(
    client.sessionId == sessionId && client.lastEventId == _firstEventId,
    'controlled MCP header poll smoke changed the active session id',
  );
  _expect(
    endpoint.streamableTraceHeadersWithSession.contains('GET:$pollTrace'),
    'controlled MCP header poll smoke did not use the owned Streamable session',
  );
  final pollStandardHeaders =
      endpoint.streamableMcpStandardHeadersByTrace['GET:$pollTrace'] ??
      const <String, String>{};
  _expect(
    !pollStandardHeaders.containsKey('mcp-method') &&
        !pollStandardHeaders.containsKey('mcp-name'),
    'controlled MCP header poll smoke forwarded caller standard MCP headers',
  );
  client.lastEventId = eventId;
}

Future<void> _smokeGenericJsonRpcBatchErrors(
  McpStreamableHttpClient client,
) async {
  final sessionId = client.sessionId;
  final eventId = client.lastEventId;

  const missingDirectTool = 'missing.generic.direct.batch';
  final directBatch = await client.postBatchDirect(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-error-tools',
        'method': 'tools/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-error-missing',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': missingDirectTool,
          'arguments': <String, Object?>{},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-error-call',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': _toolName,
          'arguments': <String, Object?>{'text': 'direct after error'},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': _toolName,
        'params': <String, Object?>{'text': 'direct notification'},
      },
    ],
  );
  _expect(
    directBatch != null && directBatch.length == 3,
    'generic direct JSON batch error smoke returned invalid size',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directBatch![0],
        id: 'generic-direct-batch-error-tools',
        label: 'generic direct batch error tools/list',
      )['tools'],
    ).contains(_toolName),
    'generic direct JSON batch error smoke lost tools response',
  );
  _expectJsonRpcError(
    directBatch[1],
    id: 'generic-direct-batch-error-missing',
    messageSubstring: missingDirectTool,
    label: 'generic direct batch missing tool',
  );
  _expect(
    _toolEchoText(
          _jsonRpcResult(
            directBatch[2],
            id: 'generic-direct-batch-error-call',
            label: 'generic direct batch success after error',
          ),
          label: 'generic direct batch success after error',
        ) ==
        'direct after error',
    'generic direct JSON batch error smoke lost success response',
  );

  const missingStreamableTool = 'missing.generic.streamable.batch';
  final streamableBatch = await client.postBatch(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-error-tools',
        'method': 'tools/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-error-missing',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': missingStreamableTool,
          'arguments': <String, Object?>{},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-error-ping',
        'method': 'ping',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': <String, Object?>{},
      },
    ],
  );
  _expect(
    streamableBatch != null && streamableBatch.length == 3,
    'generic Streamable batch error smoke returned invalid size',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        streamableBatch![0],
        id: 'generic-streamable-batch-error-tools',
        label: 'generic Streamable batch error tools/list',
      )['tools'],
    ).contains(_toolName),
    'generic Streamable batch error smoke lost tools response',
  );
  _expectJsonRpcError(
    streamableBatch[1],
    id: 'generic-streamable-batch-error-missing',
    messageSubstring: missingStreamableTool,
    label: 'generic Streamable batch missing tool',
  );
  _expect(
    _jsonRpcResult(
      streamableBatch[2],
      id: 'generic-streamable-batch-error-ping',
      label: 'generic Streamable batch ping after error',
    ).isEmpty,
    'generic Streamable batch error smoke lost ping response',
  );

  final recovery = await client.request(
    'ping',
    id: 'generic-batch-error-recovery-ping',
  );
  _expect(
    _jsonRpcResult(
      recovery,
      id: 'generic-batch-error-recovery-ping',
      label: 'generic batch error recovery ping',
    ).isEmpty,
    'generic batch errors left Streamable session unusable',
  );
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'generic batch errors changed Streamable session state',
  );
}

Future<void> _smokeGenericJsonRpcBatchPubSub(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final sessionId = client.sessionId;
  final eventId = client.lastEventId;

  final directSubscribeBatch = await client.postBatchDirect(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-pubsub-subscribe',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'connectanum.pubsub.subscribe',
          'arguments': <String, Object?>{
            'topic': _topic,
            'queueLimit': 2,
          },
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-pubsub-tools',
        'method': 'tools/list',
      },
    ],
  );
  _expect(
    directSubscribeBatch != null && directSubscribeBatch.length == 2,
    'generic direct JSON batch pub/sub subscribe did not return two responses',
  );
  final directSubscribe = _toolStructuredContentFromJsonRpc(
    directSubscribeBatch![0],
    id: 'generic-direct-batch-pubsub-subscribe',
    label: 'generic direct batch pub/sub subscribe',
  );
  final directHandle = directSubscribe['handle'];
  _expect(
    directHandle is String && directHandle.isNotEmpty,
    'generic direct JSON batch pub/sub subscribe returned $directHandle',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directSubscribeBatch[1],
        id: 'generic-direct-batch-pubsub-tools',
        label: 'generic direct batch pub/sub tools/list',
      )['tools'],
    ).contains('connectanum.pubsub.publish'),
    'generic direct JSON batch pub/sub tools/list missed pub/sub helpers',
  );

  final directPublishPollBatch = await client.postBatchDirect(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-pubsub-publish',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'connectanum.pubsub.publish',
          'arguments': <String, Object?>{
            'topic': _topic,
            'argumentsKeywords': <String, Object?>{'text': 'direct batch'},
            'acknowledge': true,
          },
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-pubsub-poll',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'connectanum.pubsub.poll',
          'arguments': <String, Object?>{
            'handle': directHandle,
          },
        },
      },
    ],
  );
  _expect(
    directPublishPollBatch != null && directPublishPollBatch.length == 2,
    'generic direct JSON batch pub/sub publish/poll did not return two responses',
  );
  final directPublish = _toolStructuredContentFromJsonRpc(
    directPublishPollBatch![0],
    id: 'generic-direct-batch-pubsub-publish',
    label: 'generic direct batch pub/sub publish',
  );
  _expect(
    directPublish['acknowledged'] == true,
    'generic direct JSON batch pub/sub publish was not acknowledged',
  );
  final directPoll = _toolStructuredContentFromJsonRpc(
    directPublishPollBatch[1],
    id: 'generic-direct-batch-pubsub-poll',
    label: 'generic direct batch pub/sub poll',
  );
  _expect(
    jsonEncode(directPoll['events']).contains('direct batch'),
    'generic direct JSON batch pub/sub poll missed the published event',
  );

  final directUnsubscribeBatch = await client.postBatchDirect(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-pubsub-unsubscribe',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': <String, Object?>{
            'handle': directHandle,
          },
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-pubsub-tools-after-unsubscribe',
        'method': 'tools/list',
      },
    ],
  );
  _expect(
    directUnsubscribeBatch != null && directUnsubscribeBatch.length == 2,
    'generic direct JSON batch pub/sub unsubscribe did not return two responses',
  );
  final directUnsubscribe = _toolStructuredContentFromJsonRpc(
    directUnsubscribeBatch![0],
    id: 'generic-direct-batch-pubsub-unsubscribe',
    label: 'generic direct batch pub/sub unsubscribe',
  );
  _expect(
    directUnsubscribe['unsubscribed'] == true,
    'generic direct JSON batch pub/sub unsubscribe failed',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directUnsubscribeBatch[1],
        id: 'generic-direct-batch-pubsub-tools-after-unsubscribe',
        label: 'generic direct batch pub/sub post-unsubscribe tools/list',
      )['tools'],
    ).contains('connectanum.pubsub.unsubscribe'),
    'generic direct JSON batch pub/sub post-unsubscribe tools/list failed',
  );

  final streamableSubscribeBatch = await client.postBatch(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-pubsub-subscribe',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'connectanum.pubsub.subscribe',
          'arguments': <String, Object?>{
            'topic': _topic,
            'queueLimit': 2,
          },
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-pubsub-tools',
        'method': 'tools/list',
      },
    ],
  );
  _expect(
    streamableSubscribeBatch != null && streamableSubscribeBatch.length == 2,
    'generic Streamable batch pub/sub subscribe did not return two responses',
  );
  final streamableSubscribe = _toolStructuredContentFromJsonRpc(
    streamableSubscribeBatch![0],
    id: 'generic-streamable-batch-pubsub-subscribe',
    label: 'generic Streamable batch pub/sub subscribe',
  );
  final streamableHandle = streamableSubscribe['handle'];
  _expect(
    streamableHandle is String && streamableHandle.isNotEmpty,
    'generic Streamable batch pub/sub subscribe returned $streamableHandle',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        streamableSubscribeBatch[1],
        id: 'generic-streamable-batch-pubsub-tools',
        label: 'generic Streamable batch pub/sub tools/list',
      )['tools'],
    ).contains('connectanum.pubsub.publish'),
    'generic Streamable batch pub/sub tools/list missed pub/sub helpers',
  );

  final streamablePublishPollBatch = await client.postBatch(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-pubsub-publish',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'connectanum.pubsub.publish',
          'arguments': <String, Object?>{
            'topic': _topic,
            'argumentsKeywords': <String, Object?>{'text': 'streamable batch'},
            'acknowledge': true,
          },
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-pubsub-poll',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'connectanum.pubsub.poll',
          'arguments': <String, Object?>{
            'handle': streamableHandle,
          },
        },
      },
    ],
  );
  _expect(
    streamablePublishPollBatch != null &&
        streamablePublishPollBatch.length == 2,
    'generic Streamable batch pub/sub publish/poll did not return two responses',
  );
  final streamablePublish = _toolStructuredContentFromJsonRpc(
    streamablePublishPollBatch![0],
    id: 'generic-streamable-batch-pubsub-publish',
    label: 'generic Streamable batch pub/sub publish',
  );
  _expect(
    streamablePublish['acknowledged'] == true,
    'generic Streamable batch pub/sub publish was not acknowledged',
  );
  final streamablePoll = _toolStructuredContentFromJsonRpc(
    streamablePublishPollBatch[1],
    id: 'generic-streamable-batch-pubsub-poll',
    label: 'generic Streamable batch pub/sub poll',
  );
  _expect(
    jsonEncode(streamablePoll['events']).contains('streamable batch'),
    'generic Streamable batch pub/sub poll missed the published event',
  );

  final streamableUnsubscribeBatch = await client.postBatch(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-pubsub-unsubscribe',
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': <String, Object?>{
            'handle': streamableHandle,
          },
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-pubsub-ping',
        'method': 'ping',
      },
    ],
  );
  _expect(
    streamableUnsubscribeBatch != null &&
        streamableUnsubscribeBatch.length == 2,
    'generic Streamable batch pub/sub unsubscribe did not return two responses',
  );
  final streamableUnsubscribe = _toolStructuredContentFromJsonRpc(
    streamableUnsubscribeBatch![0],
    id: 'generic-streamable-batch-pubsub-unsubscribe',
    label: 'generic Streamable batch pub/sub unsubscribe',
  );
  _expect(
    streamableUnsubscribe['unsubscribed'] == true,
    'generic Streamable batch pub/sub unsubscribe failed',
  );
  _expect(
    _jsonRpcResult(
      streamableUnsubscribeBatch[1],
      id: 'generic-streamable-batch-pubsub-ping',
      label: 'generic Streamable batch pub/sub post-unsubscribe ping',
    ).isEmpty,
    'generic Streamable batch pub/sub post-unsubscribe ping failed',
  );

  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'generic batch pub/sub changed Streamable session state',
  );
  const expectedDirectPubSubToolNames = <String>{
    'connectanum.pubsub.subscribe',
    'connectanum.pubsub.publish',
    'connectanum.pubsub.poll',
    'connectanum.pubsub.unsubscribe',
  };
  final missingDirectPubSubToolNames =
      expectedDirectPubSubToolNames.difference(
    endpoint.directToolNamesWithoutSession,
  );
  _expect(
    missingDirectPubSubToolNames.isEmpty,
    'generic direct JSON batch pub/sub included Streamable session state for '
    '${missingDirectPubSubToolNames.join(', ')}',
  );
}

Future<void> _smokeGenericJsonRpcBatchResourcesAndPrompts(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final sessionId = client.sessionId;
  final eventId = client.lastEventId;

  final directTaskId = 'T-direct-batch-resource-prompt';
  final directDetailBatch = await client.postBatchDirect(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-resource-read',
        'method': 'resources/read',
        'params': <String, Object?>{'uri': _resourceUri},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-resource-templates',
        'method': 'resources/templates/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-prompts',
        'method': 'prompts/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-prompt-get',
        'method': 'prompts/get',
        'params': <String, Object?>{
          'name': _promptName,
          'arguments': <String, Object?>{'taskId': directTaskId},
        },
      },
    ],
  );
  _expect(
    directDetailBatch != null && directDetailBatch.length == 4,
    'generic direct JSON batch resource/prompt details did not return four '
    'responses',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directDetailBatch![0],
        id: 'generic-direct-batch-resource-read',
        label: 'generic direct batch resources/read',
      )['contents'],
    ).contains('agent context is available'),
    'generic direct JSON batch resources/read missed route context',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directDetailBatch[1],
        id: 'generic-direct-batch-resource-templates',
        label: 'generic direct batch resources/templates/list',
      )['resourceTemplates'],
    ).contains(_resourceTemplateUri),
    'generic direct JSON batch resources/templates/list missed template',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directDetailBatch[2],
        id: 'generic-direct-batch-prompts',
        label: 'generic direct batch prompts/list',
      )['prompts'],
    ).contains(_promptName),
    'generic direct JSON batch prompts/list missed prompt',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directDetailBatch[3],
        id: 'generic-direct-batch-prompt-get',
        label: 'generic direct batch prompts/get',
      ),
    ).contains(directTaskId),
    'generic direct JSON batch prompts/get did not substitute task id',
  );

  final missingResourceUri = 'agent://missing/resource';
  final missingPromptName = 'missing-agent-prompt';
  final directErrorBatch = await client.postBatchDirect(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-resource-error',
        'method': 'resources/read',
        'params': <String, Object?>{'uri': missingResourceUri},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-prompt-error',
        'method': 'prompts/get',
        'params': <String, Object?>{
          'name': missingPromptName,
          'arguments': <String, Object?>{},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-resource-error-recovery',
        'method': 'resources/list',
      },
    ],
  );
  _expect(
    directErrorBatch != null && directErrorBatch.length == 3,
    'generic direct JSON batch resource/prompt errors did not return three '
    'responses',
  );
  _expectJsonRpcError(
    directErrorBatch![0],
    id: 'generic-direct-batch-resource-error',
    messageSubstring: missingResourceUri,
    label: 'generic direct batch missing resource',
  );
  _expectJsonRpcError(
    directErrorBatch[1],
    id: 'generic-direct-batch-prompt-error',
    messageSubstring: missingPromptName,
    label: 'generic direct batch missing prompt',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        directErrorBatch[2],
        id: 'generic-direct-batch-resource-error-recovery',
        label: 'generic direct batch resource error recovery',
      )['resources'],
    ).contains(_resourceUri),
    'generic direct JSON batch resource/prompt recovery failed',
  );

  final streamableTaskId = 'T-streamable-batch-resource-prompt';
  final streamableDetailBatch = await client.postBatch(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-resource-read',
        'method': 'resources/read',
        'params': <String, Object?>{'uri': _resourceUri},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-resource-templates',
        'method': 'resources/templates/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-prompts',
        'method': 'prompts/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-prompt-get',
        'method': 'prompts/get',
        'params': <String, Object?>{
          'name': _promptName,
          'arguments': <String, Object?>{'taskId': streamableTaskId},
        },
      },
    ],
  );
  _expect(
    streamableDetailBatch != null && streamableDetailBatch.length == 4,
    'generic Streamable batch resource/prompt details did not return four '
    'responses',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        streamableDetailBatch![0],
        id: 'generic-streamable-batch-resource-read',
        label: 'generic Streamable batch resources/read',
      )['contents'],
    ).contains('agent context is available'),
    'generic Streamable batch resources/read missed route context',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        streamableDetailBatch[1],
        id: 'generic-streamable-batch-resource-templates',
        label: 'generic Streamable batch resources/templates/list',
      )['resourceTemplates'],
    ).contains(_resourceTemplateUri),
    'generic Streamable batch resources/templates/list missed template',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        streamableDetailBatch[2],
        id: 'generic-streamable-batch-prompts',
        label: 'generic Streamable batch prompts/list',
      )['prompts'],
    ).contains(_promptName),
    'generic Streamable batch prompts/list missed prompt',
  );
  _expect(
    jsonEncode(
      _jsonRpcResult(
        streamableDetailBatch[3],
        id: 'generic-streamable-batch-prompt-get',
        label: 'generic Streamable batch prompts/get',
      ),
    ).contains(streamableTaskId),
    'generic Streamable batch prompts/get did not substitute task id',
  );

  final streamableErrorBatch = await client.postBatch(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-resource-error',
        'method': 'resources/read',
        'params': <String, Object?>{'uri': missingResourceUri},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-prompt-error',
        'method': 'prompts/get',
        'params': <String, Object?>{
          'name': missingPromptName,
          'arguments': <String, Object?>{},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-streamable-batch-resource-error-recovery',
        'method': 'ping',
      },
    ],
  );
  _expect(
    streamableErrorBatch != null && streamableErrorBatch.length == 3,
    'generic Streamable batch resource/prompt errors did not return three '
    'responses',
  );
  _expectJsonRpcError(
    streamableErrorBatch![0],
    id: 'generic-streamable-batch-resource-error',
    messageSubstring: missingResourceUri,
    label: 'generic Streamable batch missing resource',
  );
  _expectJsonRpcError(
    streamableErrorBatch[1],
    id: 'generic-streamable-batch-prompt-error',
    messageSubstring: missingPromptName,
    label: 'generic Streamable batch missing prompt',
  );
  _expect(
    _jsonRpcResult(
      streamableErrorBatch[2],
      id: 'generic-streamable-batch-resource-error-recovery',
      label: 'generic Streamable batch resource/prompt error recovery',
    ).isEmpty,
    'generic Streamable batch resource/prompt error recovery failed',
  );

  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'generic batch resource/prompt calls changed Streamable session state',
  );
  const expectedDirectResourcePromptMethods = <String>{
    'resources/read',
    'resources/templates/list',
    'prompts/list',
    'prompts/get',
    'resources/list',
  };
  final missingDirectResourcePromptMethods =
      expectedDirectResourcePromptMethods.difference(
    endpoint.directMethodsWithoutSession,
  );
  _expect(
    missingDirectResourcePromptMethods.isEmpty,
    'generic direct JSON batch resource/prompt calls included Streamable '
    'session state for ${missingDirectResourcePromptMethods.join(', ')}',
  );
}

Future<void> _smokeDirectToolApi(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final connectanumTools = await client.listConnectanumToolsDirect(
    id: 'direct-connectanum-tools-list',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-connectanum-tools-list',
    },
  );
  _expect(
    connectanumTools.tools.any((tool) => tool['name'] == _toolName),
    'direct JSON connectanum.tools.list helper failed',
  );

  final directToolCall = await client.callConnectanumToolDirect(
    _toolName,
    id: 'direct-connectanum-tool-call',
    arguments: const <String, Object?>{'text': 'direct tool'},
    headers: const <String, String>{
      'x-consumer-trace': 'direct-connectanum-tool-call',
    },
  );
  _expect(
    _toolEchoText(directToolCall, label: 'direct tool call') == 'direct tool',
    'direct JSON connectanum.tool.call helper failed',
  );
  await client.notifyConnectanumToolDirect(
    _toolName,
    arguments: const <String, Object?>{'text': 'direct notification'},
    headers: const <String, String>{
      'x-consumer-trace': 'direct-connectanum-tool-notify',
      'Mcp-Param-Text': 'wrong',
    },
  );

  final aliasToolCall = await client.callConnectanumMethodDirect(
    'connectanum.tools.call',
    id: 'direct-tools-call-alias',
    params: const <String, Object?>{
      'name': _toolName,
      'arguments': <String, Object?>{'text': 'direct alias'},
    },
    headers: const <String, String>{
      'x-consumer-trace': 'direct-tools-call-alias',
      'Mcp-Param-Text': 'wrong',
    },
  );
  _expect(
    _toolEchoText(aliasToolCall, label: 'direct tools.call alias') ==
        'direct alias',
    'direct JSON connectanum.tools.call alias failed',
  );

  final dottedToolCall = await client.callConnectanumMethodDirect(
    _toolName,
    id: 'direct-dotted-tool-call',
    params: const <String, Object?>{'text': 'direct dotted'},
    headers: const <String, String>{
      'x-consumer-trace': 'direct-dotted-tool-call',
      'Mcp-Param-Text': 'wrong',
    },
  );
  _expect(
    _toolEchoText(dottedToolCall, label: 'direct dotted tool') ==
        'direct dotted',
    'direct JSON dotted tool-name method failed',
  );

  await client.notifyConnectanumMethodDirect(
    'connectanum.tools.call',
    params: const <String, Object?>{
      'name': _toolName,
      'arguments': <String, Object?>{'text': 'direct alias notification'},
    },
    headers: const <String, String>{
      'x-consumer-trace': 'direct-tools-call-alias-notify',
      'Mcp-Param-Text': 'wrong',
    },
  );

  await client.notifyConnectanumMethodDirect(
    _toolName,
    params: const <String, Object?>{'text': 'direct dotted notification'},
    headers: const <String, String>{
      'x-consumer-trace': 'direct-dotted-tool-notify',
      'Mcp-Param-Text': 'wrong',
    },
  );

  const expectedDirectToolApiMethods = <String>{
    'connectanum.tools.list',
    'connectanum.tool.call',
    'connectanum.tools.call',
    _toolName,
  };
  final missingDirectToolApiMethods = expectedDirectToolApiMethods.difference(
    endpoint.directMethodsWithoutSession,
  );
  _expect(
    missingDirectToolApiMethods.isEmpty,
    'direct JSON generic tool API included Streamable session state for '
    '${missingDirectToolApiMethods.join(', ')}',
  );
  _expect(
    endpoint.directToolNamesWithoutSession.contains(_toolName),
    'direct JSON generic tool call did not capture the tool name without '
    'Streamable session state',
  );
  final directToolHeaders =
      endpoint.directMcpParameterHeadersByTrace[
        'direct-connectanum-tool-call'
      ];
  final directToolNotificationHeaders =
      endpoint.directMcpParameterHeadersByTrace[
        'direct-connectanum-tool-notify'
      ];
  final aliasToolHeaders =
      endpoint.directMcpParameterHeadersByTrace['direct-tools-call-alias'];
  final dottedToolHeaders =
      endpoint.directMcpParameterHeadersByTrace['direct-dotted-tool-call'];
  final aliasToolNotificationHeaders =
      endpoint.directMcpParameterHeadersByTrace[
        'direct-tools-call-alias-notify'
      ];
  final dottedToolNotificationHeaders =
      endpoint.directMcpParameterHeadersByTrace[
        'direct-dotted-tool-notify'
      ];
  _expect(
    directToolHeaders?['mcp-param-text'] == 'direct tool',
    'direct JSON connectanum.tool.call helper missed MCP parameter headers',
  );
  _expect(
    directToolNotificationHeaders?['mcp-param-text'] ==
        'direct notification',
    'direct JSON connectanum.tool.call notification helper missed MCP '
    'parameter headers',
  );
  _expect(
    aliasToolHeaders?['mcp-param-text'] == 'direct alias',
    'direct JSON connectanum.tools.call alias helper missed MCP parameter '
    'headers',
  );
  _expect(
    dottedToolHeaders?['mcp-param-text'] == 'direct dotted',
    'direct JSON dotted tool method helper missed MCP parameter headers',
  );
  _expect(
    aliasToolNotificationHeaders?['mcp-param-text'] ==
        'direct alias notification',
    'direct JSON connectanum.tools.call alias notification helper missed MCP '
    'parameter headers',
  );
  _expect(
    dottedToolNotificationHeaders?['mcp-param-text'] ==
        'direct dotted notification',
    'direct JSON dotted tool method notification helper missed MCP parameter '
    'headers',
  );
  const expectedDirectToolApiTraceHeaders = <String>{
    'direct-tools-list',
    'direct-connectanum-tools-list',
    'direct-connectanum-tool-call',
    'direct-connectanum-tool-notify',
    'direct-tools-call-alias',
    'direct-dotted-tool-call',
    'direct-tools-call-alias-notify',
    'direct-dotted-tool-notify',
  };
  final missingDirectToolApiTraceHeaders =
      expectedDirectToolApiTraceHeaders.difference(
    endpoint.directTraceHeadersWithoutSession,
  );
  _expect(
    missingDirectToolApiTraceHeaders.isEmpty,
    'direct JSON generic tool API did not forward custom headers without '
    'session state for ${missingDirectToolApiTraceHeaders.join(', ')}',
  );
}

Future<void> _smokeResourcesAndPrompts(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final resources = await client.listResources(
    id: 'streamable-resources',
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-streamable-resources',
    },
  );
  _expect(
    resources.resources.single['uri'] == _resourceUri,
    'streamable resources/list failed',
  );
  _expect(
    resources.nextCursor == _resourceCursor,
    'streamable resources/list missed nextCursor',
  );
  final resourcesPage = await client.listResources(
    id: 'streamable-resources-page-2',
    cursor: resources.nextCursor,
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-streamable-resources-page-2',
    },
  );
  _expect(
    resourcesPage.resources.single['uri'] == _pagedResourceUri &&
        resourcesPage.nextCursor == null,
    'streamable resources/list cursor page failed',
  );

  final readResource = await client.readResource(
    _resourceUri,
    id: 'streamable-resource-read',
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-streamable-resource-read',
    },
  );
  _expect(
    readResource.single['text'] == 'agent context is available',
    'streamable resources/read failed',
  );

  final templates = await client.listResourceTemplates(
    id: 'streamable-resource-templates',
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-streamable-templates',
    },
  );
  _expect(
    templates.resourceTemplates.single['uriTemplate'] == _resourceTemplateUri,
    'streamable resources/templates/list failed',
  );
  _expect(
    templates.nextCursor == _resourceTemplateCursor,
    'streamable resources/templates/list missed nextCursor',
  );
  final templatesPage = await client.listResourceTemplates(
    id: 'streamable-resource-templates-page-2',
    cursor: templates.nextCursor,
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-streamable-templates-page-2',
    },
  );
  _expect(
    templatesPage.resourceTemplates.single['uriTemplate'] ==
            _pagedResourceTemplateUri &&
        templatesPage.nextCursor == null,
    'streamable resources/templates/list cursor page failed',
  );

  final prompts = await client.listPrompts(
    id: 'streamable-prompts',
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-streamable-prompts',
    },
  );
  _expect(
    prompts.prompts.single['name'] == _promptName,
    'streamable prompts/list failed',
  );
  _expect(
    prompts.nextCursor == _promptCursor,
    'streamable prompts/list missed nextCursor',
  );
  final promptsPage = await client.listPrompts(
    id: 'streamable-prompts-page-2',
    cursor: prompts.nextCursor,
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-streamable-prompts-page-2',
    },
  );
  _expect(
    promptsPage.prompts.single['name'] == _pagedPromptName &&
        promptsPage.nextCursor == null,
    'streamable prompts/list cursor page failed',
  );

  final prompt = await client.getPrompt(
    _promptName,
    id: 'streamable-prompt-get',
    arguments: const <String, String>{'taskId': 'T-streamable'},
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-streamable-prompt-get',
    },
  );
  _expect(
    jsonEncode(prompt).contains('T-streamable'),
    'streamable prompts/get failed',
  );

  final directResources = await client.listResourcesDirect(
    id: 'direct-resources',
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-resources',
    },
  );
  _expect(
    directResources.resources.single['uri'] == _resourceUri,
    'direct JSON resources/list failed',
  );
  _expect(
    directResources.nextCursor == _resourceCursor,
    'direct JSON resources/list missed nextCursor',
  );
  final directResourcesPage = await client.listResourcesDirect(
    id: 'direct-resources-page-2',
    cursor: directResources.nextCursor,
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-resources-page-2',
    },
  );
  _expect(
    directResourcesPage.resources.single['uri'] == _pagedResourceUri &&
        directResourcesPage.nextCursor == null,
    'direct JSON resources/list cursor page failed',
  );

  final directReadResource = await client.readResourceDirect(
    _resourceUri,
    id: 'direct-resource-read',
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-resource-read',
    },
  );
  _expect(
    directReadResource.single['text'] == 'agent context is available',
    'direct JSON resources/read failed',
  );

  final directTemplates = await client.listResourceTemplatesDirect(
    id: 'direct-resource-templates',
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-templates',
    },
  );
  _expect(
    directTemplates.resourceTemplates.single['uriTemplate'] ==
        _resourceTemplateUri,
    'direct JSON resources/templates/list failed',
  );
  _expect(
    directTemplates.nextCursor == _resourceTemplateCursor,
    'direct JSON resources/templates/list missed nextCursor',
  );
  final directTemplatesPage = await client.listResourceTemplatesDirect(
    id: 'direct-resource-templates-page-2',
    cursor: directTemplates.nextCursor,
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-templates-page-2',
    },
  );
  _expect(
    directTemplatesPage.resourceTemplates.single['uriTemplate'] ==
            _pagedResourceTemplateUri &&
        directTemplatesPage.nextCursor == null,
    'direct JSON resources/templates/list cursor page failed',
  );

  final directPrompts = await client.listPromptsDirect(
    id: 'direct-prompts',
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-prompts',
    },
  );
  _expect(
    directPrompts.prompts.single['name'] == _promptName,
    'direct JSON prompts/list failed',
  );
  _expect(
    directPrompts.nextCursor == _promptCursor,
    'direct JSON prompts/list missed nextCursor',
  );
  final directPromptsPage = await client.listPromptsDirect(
    id: 'direct-prompts-page-2',
    cursor: directPrompts.nextCursor,
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-prompts-page-2',
    },
  );
  _expect(
    directPromptsPage.prompts.single['name'] == _pagedPromptName &&
        directPromptsPage.nextCursor == null,
    'direct JSON prompts/list cursor page failed',
  );

  final directPrompt = await client.getPromptDirect(
    _promptName,
    id: 'direct-prompt-get',
    arguments: const <String, String>{'taskId': 'T-direct'},
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-prompt-get',
    },
  );
  _expect(
    jsonEncode(directPrompt).contains('T-direct'),
    'direct JSON prompts/get failed',
  );
  const expectedDirectResourcePromptMethods = <String>{
    'resources/list',
    'resources/read',
    'resources/templates/list',
    'prompts/list',
    'prompts/get',
  };
  final missingDirectResourcePromptMethods =
      expectedDirectResourcePromptMethods.difference(
    endpoint.directMethodsWithoutSession,
  );
  _expect(
    missingDirectResourcePromptMethods.isEmpty,
    'direct JSON resource/prompt helpers included Streamable session state '
    'for ${missingDirectResourcePromptMethods.join(', ')}',
  );
  const expectedStreamableResourcePromptTraceHeaders = <String>{
    'POST:resource-prompts-streamable-resources',
    'POST:resource-prompts-streamable-resources-page-2',
    'POST:resource-prompts-streamable-resource-read',
    'POST:resource-prompts-streamable-templates',
    'POST:resource-prompts-streamable-templates-page-2',
    'POST:resource-prompts-streamable-prompts',
    'POST:resource-prompts-streamable-prompts-page-2',
    'POST:resource-prompts-streamable-prompt-get',
  };
  final missingStreamableResourcePromptTraceHeaders =
      expectedStreamableResourcePromptTraceHeaders.difference(
    endpoint.streamableTraceHeadersWithSession,
  );
  _expect(
    missingStreamableResourcePromptTraceHeaders.isEmpty,
    'Streamable resource/prompt helpers did not forward custom headers with '
    'session state for '
    '${missingStreamableResourcePromptTraceHeaders.join(', ')}',
  );
  const expectedDirectResourcePromptTraceHeaders = <String>{
    'resource-prompts-direct-resources',
    'resource-prompts-direct-resources-page-2',
    'resource-prompts-direct-resource-read',
    'resource-prompts-direct-templates',
    'resource-prompts-direct-templates-page-2',
    'resource-prompts-direct-prompts',
    'resource-prompts-direct-prompts-page-2',
    'resource-prompts-direct-prompt-get',
  };
  final missingDirectResourcePromptTraceHeaders =
      expectedDirectResourcePromptTraceHeaders.difference(
    endpoint.directTraceHeadersWithoutSession,
  );
  _expect(
    missingDirectResourcePromptTraceHeaders.isEmpty,
    'direct JSON resource/prompt helpers did not forward custom headers '
    'without session state for '
    '${missingDirectResourcePromptTraceHeaders.join(', ')}',
  );
}

void _expectSortedUniqueWampApiCatalog(
  Map<String, Object?> catalog, {
  required String label,
}) {
  final procedureUris = _wampApiCatalogUris(
    catalog['procedures'],
    label: '$label procedure catalog',
  );
  _expectSortedUniqueStrings(
    procedureUris,
    label: '$label procedure catalog',
    fieldDescription: 'procedure URI',
  );
  final topicUris = _wampApiCatalogUris(
    catalog['topics'],
    label: '$label topic catalog',
  );
  _expectSortedUniqueStrings(
    topicUris,
    label: '$label topic catalog',
    fieldDescription: 'topic URI',
  );
}

List<String> _wampApiCatalogUris(Object? value, {required String label}) {
  if (value is! Iterable) {
    throw StateError('$label was not a JSON array.');
  }
  final uris = <String>[];
  for (final item in value) {
    if (item is! Map) {
      throw StateError('$label contained a non-object item.');
    }
    final uri = item['uri'];
    if (uri is! String || uri.isEmpty) {
      throw StateError('$label contained an item without a URI.');
    }
    uris.add(uri);
  }
  return uris;
}

void _expectSortedUniqueStrings(
  List<String> values, {
  required String label,
  required String fieldDescription,
}) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw StateError('$label contained duplicate $fieldDescription $value.');
    }
  }
  final sorted = [...values]..sort();
  for (var index = 0; index < values.length; index += 1) {
    if (values[index] != sorted[index]) {
      throw StateError('$label was not sorted by $fieldDescription.');
    }
  }
}

Future<void> _smokeWampHelpers(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final api = await client.listWampApi(
    id: 'streamable-api-list',
    headers: const <String, String>{
      'x-consumer-trace': 'streamable-api-list',
    },
  );
  _expect(
    jsonEncode(api).contains(_procedureName) && jsonEncode(api).contains(_topic),
    'streamable WAMP API list helper failed',
  );
  _expectSortedUniqueWampApiCatalog(api, label: 'streamable WAMP API helper');

  final described = await client.describeWampApi(
    _procedureName,
    id: 'streamable-api-describe',
    kind: 'procedure',
    headers: const <String, String>{
      'x-consumer-trace': 'streamable-api-describe',
    },
  );
  _expect(
    described['uri'] == _procedureName,
    'streamable WAMP API describe helper failed',
  );

  final sessionCount = await client.countWampSessions(
    id: 'streamable-session-count',
    headers: const <String, String>{
      'x-consumer-trace': 'streamable-session-count',
    },
  );
  _expect(
    sessionCount.argumentsKeywords['count'] == _sessionCount,
    'streamable WAMP session meta helper failed',
  );

  final streamableSubscription = await client.subscribeWampTopic(
    _topic,
    id: 'streamable-subscribe',
    queueLimit: 5,
    options: mcpWampSubscribeOptions(
      match: 'exact',
      custom: const <String, Object?>{
        'x_consumer_subscription': 'streamable-subscribe',
      },
    ),
    headers: const <String, String>{
      'x-consumer-trace': 'streamable-subscribe',
    },
  );
  _expect(
    streamableSubscription.topic == _topic,
    'streamable pub/sub subscribe helper failed',
  );

  final streamablePublication = await client.publishWampEvent(
    _topic,
    id: 'streamable-publish',
    argumentsKeywords: const <String, Object?>{'text': 'streamable'},
    options: mcpWampPublishOptions(
      acknowledge: true,
      custom: const <String, Object?>{
        'x_consumer_trace': 'streamable-publish',
      },
    ),
    headers: const <String, String>{
      'x-consumer-trace': 'streamable-publish',
    },
  );
  _expect(
    streamablePublication.acknowledged &&
        streamablePublication.publicationId == _publicationId,
    'streamable pub/sub publish helper failed',
  );

  final streamableEvents = await client.pollWampEvents(
    streamableSubscription.handle,
    id: 'streamable-poll',
    headers: const <String, String>{'x-consumer-trace': 'streamable-poll'},
  );
  _expect(
    jsonEncode(streamableEvents.events).contains('streamable'),
    'streamable pub/sub poll helper failed',
  );

  final streamableUnsubscribe = await client.unsubscribeWampTopic(
    streamableSubscription.handle,
    id: 'streamable-unsubscribe',
    headers: const <String, String>{
      'x-consumer-trace': 'streamable-unsubscribe',
    },
  );
  _expect(
    streamableUnsubscribe.unsubscribed,
    'streamable pub/sub unsubscribe helper failed',
  );

  final directApi = await client.listWampApiDirect(
    id: 'direct-api-list',
    headers: const <String, String>{'x-consumer-trace': 'direct-api-list'},
  );
  _expect(
    jsonEncode(directApi).contains(_procedureName),
    'direct JSON WAMP API list helper failed',
  );
  _expectSortedUniqueWampApiCatalog(
    directApi,
    label: 'direct JSON WAMP API helper',
  );

  final directDescription = await client.describeWampApiDirect(
    _procedureName,
    id: 'direct-api-describe',
    kind: 'procedure',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-api-describe',
    },
  );
  _expect(
    directDescription['uri'] == _procedureName,
    'direct JSON WAMP API describe helper failed',
  );

  final directSessionCount = await client.countWampSessionsDirect(
    id: 'direct-session-count',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-session-count',
    },
  );
  _expect(
    directSessionCount.argumentsKeywords['count'] == _sessionCount,
    'direct JSON WAMP session meta helper failed',
  );

  await _smokeDirectWampMetaHelpers(client);

  final directSubscription = await client.subscribeWampTopicDirect(
    _topic,
    id: 'direct-subscribe',
    options: mcpWampSubscribeOptions(match: 'exact'),
    headers: const <String, String>{'x-consumer-trace': 'direct-subscribe'},
  );
  final directPublication = await client.publishWampEventDirect(
    _topic,
    id: 'direct-publish',
    argumentsKeywords: const <String, Object?>{'text': 'direct'},
    options: mcpWampPublishOptions(acknowledge: true),
    headers: const <String, String>{'x-consumer-trace': 'direct-publish'},
  );
  _expect(
    directPublication.acknowledged,
    'direct JSON pub/sub publish helper failed',
  );

  final directEvents = await client.pollWampEventsDirect(
    directSubscription.handle,
    id: 'direct-poll',
    headers: const <String, String>{'x-consumer-trace': 'direct-poll'},
  );
  _expect(
    jsonEncode(directEvents.events).contains('direct'),
    'direct JSON pub/sub poll helper failed',
  );

  await client.unsubscribeWampTopicDirect(
    directSubscription.handle,
    id: 'direct-unsubscribe',
    headers: const <String, String>{'x-consumer-trace': 'direct-unsubscribe'},
  );

  const expectedDirectWampToolNames = <String>{
    'connectanum.api.list',
    'connectanum.api.describe',
    'wamp.session.count',
    'wamp.session.list',
    'wamp.session.get',
    'wamp.registration.list',
    'wamp.registration.lookup',
    'wamp.registration.match',
    'wamp.registration.get',
    'wamp.registration.list_callees',
    'wamp.registration.count_callees',
    'wamp.subscription.list',
    'wamp.subscription.lookup',
    'wamp.subscription.match',
    'wamp.subscription.get',
    'wamp.subscription.list_subscribers',
    'wamp.subscription.count_subscribers',
    'connectanum.pubsub.subscribe',
    'connectanum.pubsub.publish',
    'connectanum.pubsub.poll',
    'connectanum.pubsub.unsubscribe',
  };
  final missingDirectWampToolNames = expectedDirectWampToolNames.difference(
    endpoint.directToolNamesWithoutSession,
  );
  _expect(
    missingDirectWampToolNames.isEmpty,
    'direct JSON WAMP helper tool calls included Streamable session state '
    'for ${missingDirectWampToolNames.join(', ')}',
  );
  _expect(
    endpoint.streamableTraceHeadersWithSession.containsAll(
      const <String>{
        'POST:streamable-api-list',
        'POST:streamable-api-describe',
        'POST:streamable-session-count',
        'POST:streamable-subscribe',
        'POST:streamable-publish',
        'POST:streamable-poll',
        'POST:streamable-unsubscribe',
      },
    ),
    'Streamable WAMP helpers did not forward custom headers with session state',
  );
  _expect(
    endpoint.directTraceHeadersWithoutSession.containsAll(
      const <String>{
        'direct-api-list',
        'direct-api-describe',
        'direct-session-count',
        'direct-session-list',
        'direct-session-get',
        'direct-registration-list',
        'direct-registration-lookup',
        'direct-registration-match',
        'direct-registration-get',
        'direct-registration-callees',
        'direct-registration-callee-count',
        'direct-subscription-list',
        'direct-subscription-lookup',
        'direct-subscription-match',
        'direct-subscription-get',
        'direct-subscription-subscribers',
        'direct-subscription-subscriber-count',
        'direct-subscribe',
        'direct-publish',
        'direct-poll',
        'direct-unsubscribe',
      },
    ),
    'direct JSON WAMP helpers did not forward custom headers without session '
    'state',
  );
}

Future<void> _smokeDirectWampMetaHelpers(
  McpStreamableHttpClient client,
) async {
  final sessions = await client.listWampSessionsDirect(
    id: 'direct-session-list',
    headers: const <String, String>{'x-consumer-trace': 'direct-session-list'},
  );
  _expect(
    _jsonListContains(sessions.argumentsKeywords['session_ids'], _wampSessionId),
    'direct JSON WAMP session list helper failed',
  );

  final session = await client.getWampSessionDirect(
    _wampSessionId,
    id: 'direct-session-get',
    headers: const <String, String>{'x-consumer-trace': 'direct-session-get'},
  );
  final sessionDetails = _jsonMapFrom(
    session.argumentsKeywords['details'],
    label: 'direct WAMP session details',
  );
  _expect(
    sessionDetails['session'] == _wampSessionId,
    'direct JSON WAMP session get helper failed',
  );

  final registrations = await client.listWampRegistrationsDirect(
    id: 'direct-registration-list',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-list',
    },
  );
  _expect(
    _jsonListContains(registrations.argumentsKeywords['exact'], _registrationId),
    'direct JSON WAMP registration list helper failed',
  );

  final lookupRegistration = await client.lookupWampRegistrationDirect(
    _procedureName,
    id: 'direct-registration-lookup',
    match: 'exact',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-lookup',
    },
  );
  _expect(
    lookupRegistration.arguments.single == _registrationId,
    'direct JSON WAMP registration lookup helper failed',
  );

  final matchingRegistration = await client.matchWampRegistrationDirect(
    _procedureName,
    id: 'direct-registration-match',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-match',
    },
  );
  _expect(
    matchingRegistration.arguments.single == _registrationId,
    'direct JSON WAMP registration match helper failed',
  );

  final registration = await client.getWampRegistrationDirect(
    _registrationId,
    id: 'direct-registration-get',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-get',
    },
  );
  _expect(
    registration.argumentsKeywords['uri'] == _procedureName,
    'direct JSON WAMP registration get helper failed',
  );

  final callees = await client.listWampRegistrationCalleesDirect(
    _registrationId,
    id: 'direct-registration-callees',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-callees',
    },
  );
  _expect(
    callees.arguments.single == _wampSessionId,
    'direct JSON WAMP registration callee list helper failed',
  );

  final calleeCount = await client.countWampRegistrationCalleesDirect(
    _registrationId,
    id: 'direct-registration-callee-count',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-callee-count',
    },
  );
  _expect(
    calleeCount.arguments.single == 1,
    'direct JSON WAMP registration callee count helper failed',
  );

  final subscriptions = await client.listWampSubscriptionsDirect(
    id: 'direct-subscription-list',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-list',
    },
  );
  _expect(
    _jsonListContains(subscriptions.argumentsKeywords['exact'], _subscriptionId),
    'direct JSON WAMP subscription list helper failed',
  );

  final lookupSubscription = await client.lookupWampSubscriptionDirect(
    _topic,
    id: 'direct-subscription-lookup',
    match: 'exact',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-lookup',
    },
  );
  _expect(
    lookupSubscription.arguments.single == _subscriptionId,
    'direct JSON WAMP subscription lookup helper failed',
  );

  final matchingSubscription = await client.matchWampSubscriptionDirect(
    _topic,
    id: 'direct-subscription-match',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-match',
    },
  );
  _expect(
    matchingSubscription.arguments.single == _subscriptionId,
    'direct JSON WAMP subscription match helper failed',
  );

  final subscription = await client.getWampSubscriptionDirect(
    _subscriptionId,
    id: 'direct-subscription-get',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-get',
    },
  );
  _expect(
    subscription.argumentsKeywords['uri'] == _topic,
    'direct JSON WAMP subscription get helper failed',
  );

  final subscribers = await client.listWampSubscriptionSubscribersDirect(
    _subscriptionId,
    id: 'direct-subscription-subscribers',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-subscribers',
    },
  );
  _expect(
    subscribers.arguments.single == _wampSessionId,
    'direct JSON WAMP subscription subscriber list helper failed',
  );

  final subscriberCount = await client.countWampSubscriptionSubscribersDirect(
    _subscriptionId,
    id: 'direct-subscription-subscriber-count',
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-subscriber-count',
    },
  );
  _expect(
    subscriberCount.arguments.single == 1,
    'direct JSON WAMP subscription subscriber count helper failed',
  );
}

Future<void> _smokeStreamableSessionLifecycle(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final events = await client.poll(
    headers: const <String, String>{'x-consumer-trace': 'streamable-poll'},
  );
  _expect(
    events.single.jsonData?['method'] == 'notifications/tools/list_changed',
    'GET/SSE poll did not return a tools/list_changed notification',
  );
  final eventId = client.lastEventId;
  if (eventId == null || eventId != _firstEventId) {
    throw StateError('GET/SSE poll did not capture the expected event id.');
  }

  final resumedEvents = await client.poll(
    lastEventId: eventId,
    headers: const <String, String>{'x-consumer-trace': 'streamable-resume'},
  );
  _expect(
    resumedEvents.isEmpty,
    'Last-Event-ID resume replayed a consumed notification',
  );
  _expect(
    client.lastEventId == eventId,
    'Last-Event-ID resume changed the client cursor',
  );

  await _expectInvalidLastEventIdRejectedWithoutSessionLoss(client, eventId);

  await client.deleteSession(
    headers: const <String, String>{'x-consumer-trace': 'streamable-delete'},
  );
  _expect(
    client.sessionId == null && client.lastEventId == null,
    'DELETE did not clear session state',
  );
  _expect(endpoint.sessionDeleted, 'mock endpoint did not receive DELETE');
  _expect(
    endpoint.streamableTraceHeadersWithoutSession.contains(
      'POST:streamable-initialize',
    ),
    'Streamable initialize did not forward custom trace headers',
  );
  _expect(
    endpoint.streamableTraceHeadersWithSession.containsAll(
      const <String>{
        'POST:streamable-initialized',
        'GET:streamable-poll',
        'GET:streamable-resume',
        'DELETE:streamable-delete',
      },
    ),
    'Streamable session requests did not forward custom trace headers',
  );

  client.sessionId = _sessionId;
  client.lastEventId = eventId;
  try {
    await client.listTools(id: 'stale-session-tools');
    throw StateError('Deleted Streamable MCP session remained usable.');
  } on McpStreamableHttpException catch (error) {
    _expect(
      error.statusCode == HttpStatus.notFound,
      'stale session returned ${error.statusCode}, expected 404',
    );
    _expect(
      error.body.contains('unknown session'),
      'stale session error did not explain the unknown session',
    );
  }
  _expect(
    client.sessionId == null && client.lastEventId == null,
    '404 did not clear stale Streamable session state',
  );

  final recovered = await client.initialize(
    id: 'reinitialize',
    clientInfo: const <String, Object?>{
      'name': 'consumer-agent-smoke',
      'version': '0.1.0',
    },
    headers: const <String, String>{
      'x-consumer-trace': 'streamable-reinitialize',
    },
  );
  _expect(
    recovered['id'] == 'reinitialize' && client.sessionId == _sessionId,
    'reinitialize after stale-session clearing failed',
  );
  await client.notifyInitialized(
    headers: const <String, String>{
      'x-consumer-trace': 'streamable-reinitialized',
    },
  );
  final recoveredTools = await client.listTools(
    id: 'tools-after-reinitialize',
    streamable: false,
  );
  _expect(
    recoveredTools.tools.any((tool) => tool['name'] == _toolName),
    'reinitialized session could not list tools',
  );
  await client.deleteSession();
  _expect(
    client.sessionId == null && client.lastEventId == null,
    'reinitialized DELETE did not clear session state',
  );
}

Future<void> _expectInvalidLastEventIdRejectedWithoutSessionLoss(
  McpStreamableHttpClient client,
  String eventId,
) async {
  final sessionId = client.sessionId;
  if (sessionId != _sessionId) {
    throw StateError('invalid Last-Event-ID smoke has no active session.');
  }

  try {
    await client.poll(lastEventId: '$sessionId:missing:1');
    throw StateError('Streamable MCP accepted an unknown Last-Event-ID.');
  } on McpStreamableHttpException catch (error) {
    _expect(
      error.statusCode == HttpStatus.badRequest,
      'invalid Last-Event-ID returned ${error.statusCode}, expected 400',
    );
    _expect(
      error.body.contains('Last-Event-ID'),
      'invalid Last-Event-ID error did not identify the rejected cursor',
    );
  }

  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'invalid Last-Event-ID changed active session state',
  );
  final tools = await client.listTools(
    id: 'tools-after-invalid-last-event-id',
    streamable: false,
  );
  _expect(
    tools.tools.any((tool) => tool['name'] == _toolName),
    'session failed after invalid Last-Event-ID rejection',
  );
  _expect(
    client.sessionId == sessionId,
    'invalid Last-Event-ID recovery lost the session id',
  );
}

final class _AgentMcpEndpoint {
  _AgentMcpEndpoint._(this._server) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;
  final directMethodsWithoutSession = <String>{};
  final directToolNamesWithoutSession = <String>{};
  final directTraceHeadersWithoutSession = <String>{};
  final directAuthorizationHeadersByTrace = <String, String>{};
  final directMcpStandardHeadersByTrace = <String, Map<String, String>>{};
  final directMcpParameterHeadersByTrace = <String, Map<String, String>>{};
  final streamableMcpStandardHeadersByTrace = <String, Map<String, String>>{};
  final streamableTraceHeadersWithoutSession = <String>{};
  final streamableTraceHeadersWithSession = <String>{};
  final authRequestBodies = <Map<String, Object?>>[];
  final authTextErrorBodies = <Map<String, Object?>>[];
  final authTraceHeaders = <String>[];
  final authDefaultHeaders = <String>[];
  final authTextErrorTraceHeaders = <String>[];
  final _subscriptions = <String, String>{};
  final _eventsByHandle = <String, List<Map<String, Object?>>>{};
  final _revokedAccessTokens = <String>{};
  final _revokedRefreshTokens = <String>{};
  final _rotatedRefreshTokens = <String>{};
  var sawDirectRequestWithoutSession = false;
  var sessionDeleted = false;
  var _sessionActive = false;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/mcp',
  );

  Uri get authUri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/auth',
  );

  Uri get authTextErrorUri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/auth-text-error',
  );

  static Future<_AgentMcpEndpoint> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _AgentMcpEndpoint._(server);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path == '/auth-text-error') {
      await _handleAuthTextError(request);
      return;
    }

    if (request.uri.path == '/auth') {
      await _handleAuth(request);
      return;
    }

    if (request.uri.path != '/mcp') {
      await _writeError(request, HttpStatus.notFound, 'unknown endpoint');
      return;
    }

    final bearerToken = _bearerTokenFrom(request);
    if (bearerToken == null ||
        _revokedAccessTokens.contains(bearerToken) ||
        (bearerToken != _accessToken && bearerToken != _refreshedAccessToken)) {
      await _writeError(request, HttpStatus.unauthorized, 'missing bearer');
      return;
    }

    if (request.method == 'GET') {
      if (!_hasSession(request)) {
        await _writeSessionError(request);
        return;
      }
      _recordStreamableTrace('GET', request);
      if (request.headers.value('x-test-poll-json-response') == '1') {
        await _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'poll-json',
          'result': <String, Object?>{},
        });
        return;
      }
      final lastEventId = request.headers.value('Last-Event-ID');
      if (lastEventId != null) {
        if (lastEventId == _firstEventId) {
          await _writeEmptySse(request);
          return;
        }
        await _writeError(
          request,
          HttpStatus.badRequest,
          'unknown Last-Event-ID',
        );
        return;
      }
      await _writeSse(request, <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/tools/list_changed',
      }, id: _firstEventId);
      return;
    }

    if (request.method == 'DELETE') {
      if (!_hasSession(request)) {
        await _writeError(request, HttpStatus.notFound, 'unknown session');
        return;
      }
      _recordStreamableTrace('DELETE', request);
      _sessionActive = false;
      sessionDeleted = true;
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method != 'POST') {
      await _writeError(
        request,
        HttpStatus.methodNotAllowed,
        'unsupported method',
      );
      return;
    }

    final body = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(body);
    if (decoded is List) {
      await _handleBatch(request, decoded.cast<Object?>());
      return;
    }

    final message = _jsonMapFrom(decoded, label: 'request');
    final method = message['method'] as String?;
    final id = message['id'];
    _recordDirectRequest(method, request, message);
    final accept = request.headers.value(HttpHeaders.acceptHeader) ?? '';
    if (accept.contains('text/event-stream')) {
      _recordStreamableTrace('POST', request);
    }

    final forcedStatus = request.headers.value('x-test-force-status');
    if (forcedStatus != null) {
      await _writeError(
        request,
        int.tryParse(forcedStatus) ?? HttpStatus.internalServerError,
        'forced test HTTP status',
      );
      return;
    }

    if (method != null && method.startsWith('notifications/')) {
      if (accept.contains('text/event-stream') && !_hasSession(request)) {
        await _writeSessionError(request);
        return;
      }
      if (request.headers.value('x-test-json-notification-response') == '1') {
        await _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/progress',
          'params': <String, Object?>{'progress': 1},
        });
        return;
      }
      if (accept.contains('text/event-stream') &&
          request.headers.value('x-test-sse-notification-only-response') ==
              '1') {
        await _writeSseValues(request, const <MapEntry<String, Object?>>[
          MapEntry<String, Object?>(
            'agent-session:post:notification',
            <String, Object?>{
              'jsonrpc': '2.0',
              'method': 'notifications/progress',
              'params': <String, Object?>{'progress': 1},
            },
          ),
        ]);
        return;
      }
      request.response.statusCode = HttpStatus.accepted;
      _applyTestResponseHeaders(request);
      await request.response.close();
      return;
    }

    if (!message.containsKey('id')) {
      request.response.statusCode = HttpStatus.accepted;
      _applyTestResponseHeaders(request);
      await request.response.close();
      return;
    }

    switch (method) {
      case 'initialize':
        _sessionActive = true;
        sessionDeleted = false;
        request.response.headers
          ..set('MCP-Session-Id', _sessionId)
          ..set('MCP-Protocol-Version', _protocolVersion);
        await _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, Object?>{
            'protocolVersion': _protocolVersion,
            'capabilities': <String, Object?>{
              'tools': <String, Object?>{},
            },
            'serverInfo': <String, Object?>{
              'name': 'agent-smoke',
              'version': '0.1.0',
            },
          },
        });
      case 'notifications/initialized':
        if (!_hasSession(request)) {
          await _writeSessionError(request);
          return;
        }
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
      case 'ping':
        if (_isStreamableRequest(request) && !_hasSession(request)) {
          await _writeSessionError(request);
          return;
        }
        await _writeJson(request, _pingResponse(id));
      case 'tools/list':
        if (_isStreamableRequest(request) && !_hasSession(request)) {
          await _writeSessionError(request);
          return;
        }
        if (request.headers.value('x-test-malformed-json-response') == '1') {
          await _writeMalformedJson(request);
          return;
        }
        if (request.headers.value('x-test-json-array-response') == '1') {
          await _writeJson(request, const <Object?>[]);
          return;
        }
        if (_isStreamableRequest(request) &&
            request.headers.value('x-test-malformed-sse-response') == '1') {
          await _writeMalformedSse(request);
          return;
        }
        if (_isStreamableRequest(request) &&
            request.headers.value('x-test-sse-notification-only-response') ==
                '1') {
          await _writeSseValues(request, const <MapEntry<String, Object?>>[
            MapEntry<String, Object?>(
              'agent-session:post:missing',
              <String, Object?>{
                'jsonrpc': '2.0',
                'method': 'notifications/progress',
                'params': <String, Object?>{'progress': 1},
              },
            ),
          ]);
          return;
        }
        if (_isStreamableRequest(request) &&
            request.headers.value('x-test-sse-prefix-notification') == '1') {
          await _writeSseValues(request, <MapEntry<String, Object?>>[
            const MapEntry<String, Object?>(
              'agent-session:post:1',
              <String, Object?>{
                'jsonrpc': '2.0',
                'method': 'notifications/progress',
                'params': <String, Object?>{'progress': 1},
              },
            ),
            MapEntry<String, Object?>(
              'agent-session:post:2',
              _toolListResponse(id, message),
            ),
          ]);
          return;
        }
        if (_isStreamableRequest(request) &&
            request.headers.value('x-test-sse-reset-event-id') == '1') {
          await _writeSseValues(request, <MapEntry<String, Object?>>[
            const MapEntry<String, Object?>(
              'agent-session:post-reset:1',
              <String, Object?>{
                'jsonrpc': '2.0',
                'method': 'notifications/progress',
                'params': <String, Object?>{'progress': 1},
              },
            ),
            MapEntry<String, Object?>('', _toolListResponse(id, message)),
          ]);
          return;
        }
        await _writeJson(request, _toolListResponse(id, message));
      case 'tools/call':
        if (_isStreamableRequest(request) && !_hasSession(request)) {
          await _writeSessionError(request);
          return;
        }
        await _writeJson(request, _toolCallResponse(id, message));
      case 'connectanum.tools.list':
        sawDirectRequestWithoutSession =
            request.headers.value('MCP-Session-Id') == null;
        await _writeJson(request, _toolListResponse(id, message));
      case 'connectanum.tool.call':
      case 'connectanum.tools.call':
        await _writeJson(request, _toolCallResponse(id, message));
      case 'resources/list':
        await _writeJson(request, _resourceListResponse(id, message));
      case 'resources/read':
        await _writeJson(request, _resourceReadResponse(id, message));
      case 'resources/templates/list':
        await _writeJson(request, _resourceTemplateListResponse(id, message));
      case 'prompts/list':
        await _writeJson(request, _promptListResponse(id, message));
      case 'prompts/get':
        await _writeJson(request, _promptGetResponse(id, message));
      default:
        if (method == _toolName) {
          await _writeJson(request, _directToolMethodResponse(id, message));
          return;
        }
        await _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, Object?>{
            'code': -32601,
            'message': 'unsupported method',
          },
        });
    }
  }

  Future<void> _handleAuth(HttpRequest request) async {
    if (request.method != 'POST') {
      await _writeError(
        request,
        HttpStatus.methodNotAllowed,
        'unsupported auth method',
      );
      return;
    }
    _expect(
      request.headers.value(HttpHeaders.acceptHeader) == 'application/json',
      'auth client did not request JSON responses',
    );
    _expect(
      request.headers.contentType?.mimeType == 'application/json',
      'auth client did not send JSON requests',
    );
    final trace = request.headers.value('x-consumer-trace');
    if (trace != null) {
      authTraceHeaders.add(trace);
    }
    final defaultTrace = request.headers.value('x-consumer-default');
    if (defaultTrace != null) {
      authDefaultHeaders.add(defaultTrace);
    }

    final body = await utf8.decoder.bind(request).join();
    final message = _jsonMapFrom(jsonDecode(body), label: 'auth request');
    authRequestBodies.add(message);

    switch (message['grant_type']) {
      case 'refresh_token':
        final refreshToken = message['refresh_token'];
        if (refreshToken is String) {
          if (_revokedRefreshTokens.contains(refreshToken)) {
            request.response.statusCode = HttpStatus.unauthorized;
            await _writeJson(request, const <String, Object?>{
              'error': 'invalid_grant',
              'reason': 'revoked_refresh_token',
            });
            return;
          }
          if (_rotatedRefreshTokens.contains(refreshToken)) {
            request.response.statusCode = HttpStatus.unauthorized;
            await _writeJson(request, const <String, Object?>{
              'error': 'invalid_grant',
              'reason': 'rotated_refresh_token',
            });
            return;
          }
        }
        _expect(
          refreshToken == _refreshToken,
          'auth refresh token mismatch',
        );
        _rotatedRefreshTokens.add(_refreshToken);
        await _writeJson(request, const <String, Object?>{
          'status': 'ok',
          'token_type': 'Bearer',
          'access_token': _refreshedAccessToken,
          'refresh_token': _refreshedRefreshToken,
          'realm': _authRealm,
          'authid': _authId,
          'authrole': _authRole,
          'authmethod': 'ticket',
          'authprovider': _authProvider,
          'expires_in': 60,
          'refresh_token_expires_in': 600,
          'details': <String, Object?>{'scope': 'mcp'},
        });
        return;
      case 'revoke':
        final token = message['token'];
        _expect(token is String && token.isNotEmpty, 'auth revoke missing token');
        final revokeToken = token as String;
        if (revokeToken == _accessToken ||
            revokeToken == _refreshedAccessToken) {
          _revokedAccessTokens.add(revokeToken);
        }
        if (revokeToken == _refreshToken ||
            revokeToken == _refreshedRefreshToken) {
          _revokedRefreshTokens.add(revokeToken);
        }
        await _writeJson(request, const <String, Object?>{'status': 'revoked'});
        return;
    }

    if (!message.containsKey('state')) {
      _expect(message['realm'] == _authRealm, 'auth request realm mismatch');
      _expect(message['authmethod'] == 'ticket', 'auth request method mismatch');
      _expect(message['authid'] == _authId, 'auth request authid mismatch');
      request.response.statusCode = HttpStatus.unauthorized;
      await _writeJson(request, const <String, Object?>{
        'state': _authState,
        'challenge': <String, Object?>{},
      });
      return;
    }

    _expect(message['state'] == _authState, 'auth token state mismatch');
    _expect(message['signature'] == _ticketSecret, 'auth ticket mismatch');
    await _writeJson(request, const <String, Object?>{
      'status': 'ok',
      'token_type': 'Bearer',
      'access_token': _accessToken,
      'refresh_token': _refreshToken,
      'realm': _authRealm,
      'authid': _authId,
      'authrole': _authRole,
      'authmethod': 'ticket',
      'authprovider': _authProvider,
      'expires_in': 60,
      'refresh_token_expires_in': 600,
      'details': <String, Object?>{'scope': 'mcp'},
    });
  }

  Future<void> _handleAuthTextError(HttpRequest request) async {
    if (request.method != 'POST') {
      await _writeText(
        request,
        'unsupported auth method',
        statusCode: HttpStatus.methodNotAllowed,
      );
      return;
    }
    _expect(
      request.headers.value(HttpHeaders.acceptHeader) == 'application/json',
      'auth client did not request JSON responses for non-JSON error smoke',
    );
    _expect(
      request.headers.contentType?.mimeType == 'application/json',
      'auth client did not send JSON requests for non-JSON error smoke',
    );
    final trace = request.headers.value('x-consumer-trace');
    if (trace != null) {
      authTextErrorTraceHeaders.add(trace);
    }

    final body = await utf8.decoder.bind(request).join();
    final message = _jsonMapFrom(
      jsonDecode(body),
      label: 'auth text-error request',
    );
    authTextErrorBodies.add(message);
    await _writeText(
      request,
      'auth bridge unavailable',
      statusCode: HttpStatus.serviceUnavailable,
    );
  }

  Future<void> _handleBatch(
    HttpRequest request,
    List<Object?> messages,
  ) async {
    final responses = <Map<String, Object?>>[];
    for (final item in messages) {
      final message = _jsonMapFrom(item, label: 'batch request item');
      final response = _batchResponse(request, message);
      if (response != null) {
        responses.add(response);
      }
    }
    if (responses.isEmpty) {
      if (request.headers.value('x-test-json-notification-response') == '1') {
        await _writeJson(request, const <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/progress',
          'params': <String, Object?>{'progress': 1},
        });
        return;
      }
      if (_isStreamableRequest(request) &&
          request.headers.value('x-test-sse-notification-only-response') ==
              '1') {
        await _writeSseValues(request, const <MapEntry<String, Object?>>[
          MapEntry<String, Object?>(
            'agent-session:post-batch:notification',
            <String, Object?>{
              'jsonrpc': '2.0',
              'method': 'notifications/progress',
              'params': <String, Object?>{'progress': 1},
            },
          ),
        ]);
        return;
      }
      request.response.statusCode = HttpStatus.accepted;
      _applyTestResponseHeaders(request);
      await request.response.close();
      return;
    }
    if (request.headers.value('x-test-batch-json-object-response') == '1') {
      await _writeJson(request, responses.first);
      return;
    }
    if (_isStreamableRequest(request) &&
        request.headers.value('x-test-sse-split-batch-with-notification') ==
            '1') {
      final events = <MapEntry<String, Object?>>[
        const MapEntry<String, Object?>(
          'agent-session:split-batch:1',
          <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'notifications/progress',
            'params': <String, Object?>{'progress': 1},
          },
        ),
      ];
      for (var index = 0; index < responses.length; index += 1) {
        events.add(
          MapEntry<String, Object?>(
            'agent-session:split-batch:${index + 2}',
            responses[index],
          ),
        );
      }
      await _writeSseValues(request, events);
      return;
    }
    await _writeJson(request, responses);
  }

  Map<String, Object?>? _batchResponse(
    HttpRequest request,
    Map<String, Object?> message,
  ) {
    final method = message['method'] as String?;
    final id = message['id'];
    _recordDirectRequest(method, request, message);
    if (id == null) {
      return null;
    }
    if (_batchMethodRequiresSession(method, request) && !_hasSession(request)) {
      return _jsonRpcError(id, -32001, 'missing or unknown session');
    }

    switch (method) {
      case 'notifications/initialized':
        return _jsonRpcResultResponse(id);
      case 'ping':
        return _pingResponse(id);
      case 'tools/list':
        return _toolListResponse(id, message);
      case 'tools/call':
        return _toolCallResponse(id, message);
      case 'connectanum.tools.list':
        sawDirectRequestWithoutSession =
            request.headers.value('MCP-Session-Id') == null;
        return _toolListResponse(id, message);
      case 'connectanum.tool.call':
      case 'connectanum.tools.call':
        return _toolCallResponse(id, message);
      case 'resources/list':
        return _resourceListResponse(id, message);
      case 'resources/read':
        return _resourceReadResponse(id, message);
      case 'resources/templates/list':
        return _resourceTemplateListResponse(id, message);
      case 'prompts/list':
        return _promptListResponse(id, message);
      case 'prompts/get':
        return _promptGetResponse(id, message);
      default:
        if (method == _toolName) {
          return _directToolMethodResponse(id, message);
        }
        return _jsonRpcError(id, -32601, 'unsupported method');
    }
  }

  bool _batchMethodRequiresSession(String? method, HttpRequest request) {
    return _isStreamableRequest(request) &&
        (method == 'notifications/initialized' ||
            method == 'ping' ||
            method == 'tools/list' ||
            method == 'tools/call');
  }

  void _recordDirectRequest(
    String? method,
    HttpRequest request,
    Map<String, Object?> message,
  ) {
    if (method != null && request.headers.value('MCP-Session-Id') == null) {
      sawDirectRequestWithoutSession = true;
      final trace = request.headers.value('x-consumer-trace');
      if (trace != null) {
        directTraceHeadersWithoutSession.add(trace);
        final authorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        if (authorization != null) {
          directAuthorizationHeadersByTrace[trace] = authorization;
        }
        final standardHeaders = <String, String>{};
        final parameterHeaders = <String, String>{};
        request.headers.forEach((name, values) {
          final lowerName = name.toLowerCase();
          if ((lowerName == 'mcp-method' || lowerName == 'mcp-name') &&
              values.isNotEmpty) {
            standardHeaders[lowerName] = values.first;
          }
          if (lowerName.startsWith('mcp-param-') && values.isNotEmpty) {
            parameterHeaders[lowerName] = values.first;
          }
        });
        if (standardHeaders.isNotEmpty) {
          directMcpStandardHeadersByTrace[trace] = standardHeaders;
        }
        if (parameterHeaders.isNotEmpty) {
          directMcpParameterHeadersByTrace[trace] = parameterHeaders;
        }
      }
      directMethodsWithoutSession.add(method);
      if (method == 'tools/call' ||
          method == 'connectanum.tool.call' ||
          method == 'connectanum.tools.call') {
        final params = message['params'];
        if (params is Map) {
          final name = params['name'];
          if (name is String) {
            directToolNamesWithoutSession.add(name);
          }
        }
      }
    }
  }

  void _recordStreamableTrace(String method, HttpRequest request) {
    final trace = request.headers.value('x-consumer-trace');
    if (trace == null) {
      return;
    }
    final key = '$method:$trace';
    final standardHeaders = <String, String>{};
    request.headers.forEach((name, values) {
      final lowerName = name.toLowerCase();
      if ((lowerName == 'mcp-method' || lowerName == 'mcp-name') &&
          values.isNotEmpty) {
        standardHeaders[lowerName] = values.first;
      }
    });
    if (standardHeaders.isNotEmpty) {
      streamableMcpStandardHeadersByTrace[key] = standardHeaders;
    }
    if (request.headers.value('MCP-Session-Id') == null) {
      streamableTraceHeadersWithoutSession.add(key);
    } else {
      streamableTraceHeadersWithSession.add(key);
    }
  }

  bool _hasSession(HttpRequest request) {
    return request.headers.value('MCP-Session-Id') == _sessionId &&
        _sessionActive;
  }

  String? _bearerTokenFrom(HttpRequest request) {
    final authorization = request.headers.value(HttpHeaders.authorizationHeader);
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    final token = authorization.substring('Bearer '.length).trim();
    return token.isEmpty ? null : token;
  }

  bool _isStreamableRequest(HttpRequest request) {
    return (request.headers.value(HttpHeaders.acceptHeader) ?? '').contains(
      'text/event-stream',
    );
  }

  Future<void> _writeSessionError(HttpRequest request) async {
    if (request.headers.value('MCP-Session-Id') == _sessionId) {
      await _writeError(request, HttpStatus.notFound, 'unknown session');
      return;
    }
    await _writeError(request, HttpStatus.badRequest, 'missing session');
  }

  Map<String, Object?> _pingResponse(Object? id) => _jsonRpcResultResponse(id);

  Map<String, Object?> _jsonRpcResultResponse(Object? id) {
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{},
    };
  }

  Map<String, Object?> _jsonRpcError(
    Object? id,
    int code,
    String message,
  ) {
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, Object?>{'code': code, 'message': message},
    };
  }

  String? _cursorFrom(Map<String, Object?> message) {
    final params = message['params'];
    if (params is Map) {
      final cursor = params['cursor'];
      if (cursor is String) {
        return cursor;
      }
    }
    return null;
  }

  Map<String, Object?> _toolListResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final cursor = _cursorFrom(message);
    if (cursor == _toolCursor) {
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{
          'tools': <Object?>[_toolDefinition(_pagedToolName)],
        },
      };
    }
    _expect(cursor == null, 'unexpected tools/list cursor $cursor');
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'tools': <Object?>[
          <String, Object?>{
            'name': _toolName,
            'description': 'Echoes an agent request.',
            'inputSchema': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'text': <String, Object?>{
                  'type': 'string',
                  'x-mcp-header': 'Text',
                },
              },
            },
          },
          _toolDefinition('connectanum.api.list'),
          _toolDefinition('connectanum.api.describe'),
          _toolDefinition('connectanum.pubsub.publish'),
          _toolDefinition('connectanum.pubsub.subscribe'),
          _toolDefinition('connectanum.pubsub.poll'),
          _toolDefinition('connectanum.pubsub.unsubscribe'),
          _toolDefinition('wamp.session.count'),
          _toolDefinition('wamp.session.list'),
          _toolDefinition('wamp.session.get'),
          _toolDefinition('wamp.registration.list'),
          _toolDefinition('wamp.registration.lookup'),
          _toolDefinition('wamp.registration.match'),
          _toolDefinition('wamp.registration.get'),
          _toolDefinition('wamp.registration.list_callees'),
          _toolDefinition('wamp.registration.count_callees'),
          _toolDefinition('wamp.subscription.list'),
          _toolDefinition('wamp.subscription.lookup'),
          _toolDefinition('wamp.subscription.match'),
          _toolDefinition('wamp.subscription.get'),
          _toolDefinition('wamp.subscription.list_subscribers'),
          _toolDefinition('wamp.subscription.count_subscribers'),
        ],
        'nextCursor': _toolCursor,
      },
    };
  }

  Map<String, Object?> _toolDefinition(String name) {
    return <String, Object?>{
      'name': name,
      'description': 'Connectanum helper $name.',
      'inputSchema': <String, Object?>{'type': 'object'},
    };
  }

  Map<String, Object?> _toolCallResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final params = _jsonMapFrom(message['params'], label: 'tool params');
    final name = params['name'] as String?;
    final arguments = _jsonMapFrom(params['arguments'], label: 'arguments');
    if (name != null && name.startsWith('missing.')) {
      return _jsonRpcError(id, -32004, 'Tool not found: $name');
    }
    if (name != _toolName) {
      return _structuredToolResponse(id, _wampToolStructuredContent(name, arguments));
    }
    return _agentToolResponse(id, arguments);
  }

  Map<String, Object?> _directToolMethodResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final arguments = _jsonMapFrom(
      message['params'],
      label: 'direct tool method params',
    );
    return _agentToolResponse(id, arguments);
  }

  Map<String, Object?> _agentToolResponse(
    Object? id,
    Map<String, Object?> arguments,
  ) {
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': jsonEncode(arguments)},
        ],
        'structuredContent': <String, Object?>{'echo': arguments},
        'isError': false,
      },
    };
  }

  Map<String, Object?> _structuredToolResponse(
    Object? id,
    Map<String, Object?> structuredContent,
  ) {
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'content': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': jsonEncode(structuredContent),
          },
        ],
        'structuredContent': structuredContent,
        'isError': false,
      },
    };
  }

  Map<String, Object?> _wampToolStructuredContent(
    String? name,
    Map<String, Object?> arguments,
  ) {
    switch (name) {
      case 'connectanum.api.list':
        return _apiListStructuredContent();
      case 'connectanum.api.describe':
        return _apiDescribeStructuredContent(arguments);
      case 'wamp.session.count':
        return <String, Object?>{
          'arguments': <Object?>[_sessionCount],
          'argumentsKeywords': <String, Object?>{'count': _sessionCount},
        };
      case 'wamp.session.list':
        return <String, Object?>{
          'arguments': const <Object?>[],
          'argumentsKeywords': <String, Object?>{
            'session_ids': <Object?>[_wampSessionId],
          },
        };
      case 'wamp.session.get':
        return <String, Object?>{
          'arguments': const <Object?>[],
          'argumentsKeywords': <String, Object?>{
            'details': <String, Object?>{
              'session': _firstArgument(arguments) ?? _wampSessionId,
              'authid': 'consumer-agent',
              'authrole': 'agent',
            },
          },
        };
      case 'wamp.registration.list':
        return <String, Object?>{
          'arguments': const <Object?>[],
          'argumentsKeywords': <String, Object?>{
            'exact': <Object?>[_registrationId],
          },
        };
      case 'wamp.registration.lookup':
      case 'wamp.registration.match':
        return <String, Object?>{
          'arguments': <Object?>[_registrationId],
          'argumentsKeywords': const <String, Object?>{},
        };
      case 'wamp.registration.get':
        return <String, Object?>{
          'arguments': const <Object?>[],
          'argumentsKeywords': <String, Object?>{
            'id': _firstArgument(arguments) ?? _registrationId,
            'uri': _procedureName,
            'match': 'exact',
          },
        };
      case 'wamp.registration.list_callees':
        return <String, Object?>{
          'arguments': <Object?>[_wampSessionId],
          'argumentsKeywords': const <String, Object?>{},
        };
      case 'wamp.registration.count_callees':
        return <String, Object?>{
          'arguments': const <Object?>[1],
          'argumentsKeywords': const <String, Object?>{},
        };
      case 'wamp.subscription.list':
        return <String, Object?>{
          'arguments': const <Object?>[],
          'argumentsKeywords': <String, Object?>{
            'exact': <Object?>[_subscriptionId],
          },
        };
      case 'wamp.subscription.lookup':
      case 'wamp.subscription.match':
        return <String, Object?>{
          'arguments': <Object?>[_subscriptionId],
          'argumentsKeywords': const <String, Object?>{},
        };
      case 'wamp.subscription.get':
        return <String, Object?>{
          'arguments': const <Object?>[],
          'argumentsKeywords': <String, Object?>{
            'id': _firstArgument(arguments) ?? _subscriptionId,
            'uri': _topic,
            'match': 'exact',
          },
        };
      case 'wamp.subscription.list_subscribers':
        return <String, Object?>{
          'arguments': <Object?>[_wampSessionId],
          'argumentsKeywords': const <String, Object?>{},
        };
      case 'wamp.subscription.count_subscribers':
        return <String, Object?>{
          'arguments': const <Object?>[1],
          'argumentsKeywords': const <String, Object?>{},
        };
      case 'connectanum.pubsub.subscribe':
        return _subscribeStructuredContent(arguments);
      case 'connectanum.pubsub.publish':
        return _publishStructuredContent(arguments);
      case 'connectanum.pubsub.poll':
        return _pollStructuredContent(arguments);
      case 'connectanum.pubsub.unsubscribe':
        return _unsubscribeStructuredContent(arguments);
      default:
        return <String, Object?>{
          'unknownTool': name,
          'arguments': arguments,
        };
    }
  }

  Object? _firstArgument(Map<String, Object?> arguments) {
    final values = arguments['arguments'];
    return values is List && values.isNotEmpty ? values.first : null;
  }

  Map<String, Object?> _apiListStructuredContent() {
    return <String, Object?>{
      'procedures': <Object?>[
        <String, Object?>{
          'uri': _procedureName,
          'description': 'Looks up agent task context.',
          'metadata': <String, Object?>{
            'tags': <Object?>['agent', 'safe'],
          },
        },
      ],
      'topics': <Object?>[
        <String, Object?>{
          'uri': _topic,
          'description': 'Agent task events.',
          'metadata': <String, Object?>{
            'tags': <Object?>['agent'],
          },
        },
      ],
    };
  }

  Map<String, Object?> _apiDescribeStructuredContent(
    Map<String, Object?> arguments,
  ) {
    return <String, Object?>{
      'uri': arguments['uri'],
      'kind': arguments['kind'] ?? 'procedure',
      'description': 'Agent task metadata.',
      'metadata': <String, Object?>{
        'registrationId': _registrationId,
        'subscriptionId': _subscriptionId,
      },
    };
  }

  Map<String, Object?> _subscribeStructuredContent(
    Map<String, Object?> arguments,
  ) {
    final topic = arguments['topic'] as String? ?? _topic;
    final handle = '$_subscriptionHandlePrefix-${_subscriptions.length + 1}';
    _subscriptions[handle] = topic;
    _eventsByHandle[handle] = <Map<String, Object?>>[];
    return <String, Object?>{
      'handle': handle,
      'topic': topic,
      'queueLimit': arguments['queueLimit'] ?? 100,
      'subscriptionId': _subscriptionId,
    };
  }

  Map<String, Object?> _publishStructuredContent(
    Map<String, Object?> arguments,
  ) {
    final topic = arguments['topic'] as String? ?? _topic;
    final options = arguments['options'] is Map<Object?, Object?>
        ? _jsonMapFrom(arguments['options'], label: 'publish options')
        : const <String, Object?>{};
    final event = <String, Object?>{
      'topic': topic,
      'arguments': arguments['arguments'] ?? <Object?>[],
      'argumentsKeywords': arguments['argumentsKeywords'] ?? <String, Object?>{},
      'publicationId': _publicationId,
    };
    for (final entry in _subscriptions.entries) {
      if (entry.value == topic) {
        _eventsByHandle[entry.key]?.add(event);
      }
    }
    return <String, Object?>{
      'topic': topic,
      'acknowledged':
          arguments['acknowledge'] == true || options['acknowledge'] == true,
      'publicationId': _publicationId,
    };
  }

  Map<String, Object?> _pollStructuredContent(Map<String, Object?> arguments) {
    final handle = arguments['handle'] as String? ?? '';
    final topic = _subscriptions[handle] ?? _topic;
    final events = _eventsByHandle[handle] ?? const <Map<String, Object?>>[];
    return <String, Object?>{
      'handle': handle,
      'topic': topic,
      'events': events,
      'dropped': 0,
      'remaining': 0,
    };
  }

  Map<String, Object?> _unsubscribeStructuredContent(
    Map<String, Object?> arguments,
  ) {
    final handle = arguments['handle'] as String? ?? '';
    final topic = _subscriptions.remove(handle) ?? _topic;
    _eventsByHandle.remove(handle);
    return <String, Object?>{
      'handle': handle,
      'topic': topic,
      'unsubscribed': true,
    };
  }

  Map<String, Object?> _resourceListResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final cursor = _cursorFrom(message);
    if (cursor == _resourceCursor) {
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{
          'resources': <Object?>[
            <String, Object?>{
              'uri': _pagedResourceUri,
              'name': 'Next agent context',
              'mimeType': 'text/plain',
            },
          ],
        },
      };
    }
    _expect(cursor == null, 'unexpected resources/list cursor $cursor');
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'resources': <Object?>[
          <String, Object?>{
            'uri': _resourceUri,
            'name': 'Agent context',
            'mimeType': 'text/plain',
          },
        ],
        'nextCursor': _resourceCursor,
      },
    };
  }

  Map<String, Object?> _resourceReadResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final params = _jsonMapFrom(message['params'], label: 'resource params');
    if (params['uri'] != _resourceUri) {
      return _jsonRpcError(id, -32004, 'Resource not found: ${params['uri']}');
    }
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'contents': <Object?>[
          <String, Object?>{
            'uri': params['uri'],
            'mimeType': 'text/plain',
            'text': 'agent context is available',
          },
        ],
      },
    };
  }

  Map<String, Object?> _resourceTemplateListResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final cursor = _cursorFrom(message);
    if (cursor == _resourceTemplateCursor) {
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{
          'resourceTemplates': <Object?>[
            <String, Object?>{
              'uriTemplate': _pagedResourceTemplateUri,
              'name': 'Archived agent task context',
              'mimeType': 'application/json',
            },
          ],
        },
      };
    }
    _expect(
      cursor == null,
      'unexpected resources/templates/list cursor $cursor',
    );
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'resourceTemplates': <Object?>[
          <String, Object?>{
            'uriTemplate': _resourceTemplateUri,
            'name': 'Agent task context',
            'mimeType': 'application/json',
          },
        ],
        'nextCursor': _resourceTemplateCursor,
      },
    };
  }

  Map<String, Object?> _promptListResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final cursor = _cursorFrom(message);
    if (cursor == _promptCursor) {
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{
          'prompts': <Object?>[
            <String, Object?>{
              'name': _pagedPromptName,
              'description': 'Summarizes follow-up agent context.',
              'arguments': <Object?>[
                <String, Object?>{
                  'name': 'taskId',
                  'description': 'Task id.',
                  'required': true,
                },
              ],
            },
          ],
        },
      };
    }
    _expect(cursor == null, 'unexpected prompts/list cursor $cursor');
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'prompts': <Object?>[
          <String, Object?>{
            'name': _promptName,
            'description': 'Summarizes an agent task.',
            'arguments': <Object?>[
              <String, Object?>{
                'name': 'taskId',
                'description': 'Task id.',
                'required': true,
              },
            ],
          },
        ],
        'nextCursor': _promptCursor,
      },
    };
  }

  Map<String, Object?> _promptGetResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final params = _jsonMapFrom(message['params'], label: 'prompt params');
    if (params['name'] != _promptName) {
      return _jsonRpcError(id, -32004, 'Prompt not found: ${params['name']}');
    }
    final arguments = _jsonMapFrom(params['arguments'], label: 'prompt args');
    final taskId = arguments['taskId'];
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, Object?>{
        'description': 'Agent task summary prompt.',
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': <String, Object?>{
              'type': 'text',
              'text': 'Summarize task $taskId for an agent.',
            },
          },
        ],
      },
    };
  }

  Future<void> _writeJson(
    HttpRequest request,
    Object? body,
  ) async {
    request.response.headers.contentType = ContentType.json;
    _applyTestResponseHeaders(request);
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _writeMalformedJson(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    _applyTestResponseHeaders(request);
    request.response.write('{');
    await request.response.close();
  }

  Future<void> _writeText(
    HttpRequest request,
    String body, {
    int statusCode = HttpStatus.ok,
  }) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.text;
    request.response.write(body);
    await request.response.close();
  }

  void _applyTestResponseHeaders(HttpRequest request) {
    final responseSessionId = request.headers.value(
      'x-test-response-session-id',
    );
    if (request.headers.value('x-test-empty-response-session-id') != null) {
      request.response.headers.set('MCP-Session-Id', '');
    } else if (responseSessionId != null) {
      request.response.headers.set('MCP-Session-Id', responseSessionId);
    }
  }

  Future<void> _writeSse(
    HttpRequest request,
    Map<String, Object?> message, {
    required String id,
  }) async {
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    _applyTestResponseHeaders(request);
    request.response.write('id: $id\n');
    request.response.write('event: message\n');
    request.response.write('data: ${jsonEncode(message)}\n\n');
    await request.response.close();
  }

  Future<void> _writeMalformedSse(HttpRequest request) async {
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    _applyTestResponseHeaders(request);
    request.response.write('id: agent-session:post:malformed\n');
    request.response.write('event: message\n');
    request.response.write('data: {\n\n');
    await request.response.close();
  }

  Future<void> _writeSseValues(
    HttpRequest request,
    List<MapEntry<String, Object?>> events,
  ) async {
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    _applyTestResponseHeaders(request);
    for (final event in events) {
      request.response.write('id: ${event.key}\n');
      request.response.write('event: message\n');
      request.response.write('data: ${jsonEncode(event.value)}\n\n');
    }
    await request.response.close();
  }

  Future<void> _writeEmptySse(HttpRequest request) async {
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    await request.response.close();
  }

  Future<void> _writeError(
    HttpRequest request,
    int statusCode,
    String message,
  ) async {
    request.response.statusCode = statusCode;
    await _writeJson(request, <String, Object?>{
      'error': <String, Object?>{'message': message},
    });
  }
}

Map<String, Object?> _jsonRpcResult(
  Map<String, Object?> response, {
  required Object? id,
  required String label,
}) {
  _expect(response['id'] == id, '$label returned unexpected id.');
  return _jsonMapFrom(response['result'], label: '$label result');
}

void _expectJsonRpcError(
  Map<String, Object?> response, {
  required Object? id,
  required String messageSubstring,
  required String label,
}) {
  _expect(response['id'] == id, '$label returned unexpected id.');
  _expect(
    !response.containsKey('result'),
    '$label unexpectedly contained a result.',
  );
  final error = response['error'];
  _expect(error is Map, '$label did not contain a JSON-RPC error.');
  _expect(
    jsonEncode(error).contains(messageSubstring),
    '$label error did not mention $messageSubstring.',
  );
}

Map<String, Object?> _toolStructuredContentFromJsonRpc(
  Map<String, Object?> response, {
  required Object? id,
  required String label,
}) {
  final result = _jsonRpcResult(response, id: id, label: label);
  return _jsonMapFrom(
    result['structuredContent'],
    label: '$label structured content',
  );
}

Map<String, Object?> _jsonMapFrom(Object? value, {required String label}) {
  if (value is Map<Object?, Object?>) {
    return value.map((key, value) => MapEntry(key as String, value));
  }
  throw StateError('$label was not a JSON object.');
}

String? _toolEchoText(Map<String, Object?> result, {required String label}) {
  final structuredContent = _jsonMapFrom(
    result['structuredContent'],
    label: '$label structured content',
  );
  final echo = _jsonMapFrom(structuredContent['echo'], label: '$label echo');
  final text = echo['text'];
  return text is String ? text : null;
}

bool _jsonListContains(Object? value, Object? expected) {
  return value is List && value.contains(expected);
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
DART

  printf 'Running MCP client-only consumer package smoke from %s.\n' "$smoke_dir"
  (
    cd "$smoke_dir"
    PUB_CACHE="$pub_cache" dart pub get
    executable_help="$(PUB_CACHE="$pub_cache" dart run connectanum_mcp:router_hosted_client --help)"
    if [[ "$executable_help" != *"--endpoint"* ||
      "$executable_help" != *"--protocol-version"* ||
      "$executable_help" != *"--pubsub-topic"* ]]; then
      printf 'MCP client package executable help output missed expected options.\n'
      return 1
    fi

    executable_dry_run="$(PUB_CACHE="$pub_cache" dart run connectanum_mcp:router_hosted_client \
      --endpoint http://127.0.0.1:8080/mcp \
      --protocol-version 2025-06-18 \
      --pubsub-topic agent.events \
      --pubsub-event '{"text":"ready"}' \
      --dry-run)"
    if [[ "$executable_dry_run" != *'"dryRun":true'* ||
      "$executable_dry_run" != *'"endpoint":"http://127.0.0.1:8080/mcp"'* ||
      "$executable_dry_run" != *'"pubsub":{"topic":"agent.events"'* ||
      "$executable_dry_run" != *'"subscriptionMetadata":true'* ]]; then
      printf 'MCP client package executable dry-run summary was unexpected.\n'
      printf '%s\n' "$executable_dry_run"
      return 1
    fi
    PUB_CACHE="$pub_cache" dart analyze
    PUB_CACHE="$pub_cache" dart run bin/main.dart
  )

  global_smoke_workspace="$smoke_dir/global-workspace"
  mkdir -p "$global_smoke_workspace/packages"
  cat >"$global_smoke_workspace/pubspec.yaml" <<EOF
name: connectanum_mcp_global_activation_smoke_workspace
publish_to: none
environment:
  sdk: '^3.9.2'
hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
workspace:
  - packages/connectanum_core
  - packages/connectanum_client
  - packages/connectanum_mcp
EOF
  if [[ -f "$ROOT_DIR/pubspec.lock" ]]; then
    cp "$ROOT_DIR/pubspec.lock" "$global_smoke_workspace/pubspec.lock"
  fi

  for package_name in \
    connectanum_core \
    connectanum_client \
    connectanum_mcp; do
    package_source="$ROOT_DIR/packages/$package_name"
    package_target="$global_smoke_workspace/packages/$package_name"
    mkdir -p "$package_target"
    cp "$package_source/pubspec.yaml" "$package_target/pubspec.yaml"
    cp -R "$package_source/lib" "$package_target/lib"
    if [[ -d "$package_source/bin" ]]; then
      cp -R "$package_source/bin" "$package_target/bin"
    fi
    if [[ -d "$package_source/example" ]]; then
      cp -R "$package_source/example" "$package_target/example"
    fi
    if [[ -d "$package_source/hook" ]]; then
      cp -R "$package_source/hook" "$package_target/hook"
    fi
  done
  CONNECTANUM_SKIP_NATIVE_BUILD=true \
    PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" dart pub global activate --source path "$global_smoke_workspace/packages/connectanum_mcp" >&2
  global_mcp_command="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" command -v router_hosted_client || true)"
  if [[ "$global_mcp_command" != "$pub_cache/bin/router_hosted_client" ]]; then
    printf 'Expected isolated pub-cache router_hosted_client command, got: %s\n' \
      "${global_mcp_command:-<missing>}" >&2
    return 1
  fi
  global_executable_help="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" router_hosted_client --help)"
  if [[ "$global_executable_help" != *"--endpoint"* ||
    "$global_executable_help" != *"--protocol-version"* ||
    "$global_executable_help" != *"--pubsub-topic"* ]]; then
    printf 'MCP client global executable help output missed expected options.\n'
    return 1
  fi

  global_executable_dry_run="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" router_hosted_client \
    --endpoint http://127.0.0.1:8080/mcp \
    --protocol-version 2025-06-18 \
    --pubsub-topic agent.events \
    --pubsub-event '{"text":"ready"}' \
    --dry-run)"
  if [[ "$global_executable_dry_run" != *'"dryRun":true'* ||
    "$global_executable_dry_run" != *'"endpoint":"http://127.0.0.1:8080/mcp"'* ||
    "$global_executable_dry_run" != *'"pubsub":{"topic":"agent.events"'* ||
    "$global_executable_dry_run" != *'"subscriptionMetadata":true'* ]]; then
    printf 'MCP client global executable dry-run summary was unexpected.\n'
    printf '%s\n' "$global_executable_dry_run"
    return 1
  fi
)

run_mcp_consumer_package_smoke() (
  local hook_setting
  local hook_native_lib
  local pub_cache
  local smoke_dir

  require_command dart
  hook_native_lib=""
  if native_runtime_supported && ensure_native_client_test_runtime; then
    hook_native_lib="${CONNECTANUM_NATIVE_LIB:-}"
  fi

  if [[ -n "$hook_native_lib" ]]; then
    hook_setting="CONNECTANUM_NATIVE_LIB: \"$hook_native_lib\""
  else
    hook_setting="CONNECTANUM_SKIP_NATIVE_BUILD: true"
  fi

  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-mcp-consumer-smoke.XXXXXX")"
  pub_cache="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-mcp-consumer-pub-cache.XXXXXX")"
  trap "rm -rf '$smoke_dir' '$pub_cache'" EXIT

  mkdir -p "$smoke_dir/bin"
  cat >"$smoke_dir/pubspec.yaml" <<EOF
name: connectanum_mcp_consumer_smoke
publish_to: none
environment:
  sdk: '^3.9.2'
hooks:
  user_defines:
    connectanum_client:
      $hook_setting
    connectanum_router:
      $hook_setting
dependencies:
  connectanum_mcp: any
  connectanum_router: any
dependency_overrides:
  connectanum_core:
    path: "$ROOT_DIR/packages/connectanum_core"
  connectanum_client:
    path: "$ROOT_DIR/packages/connectanum_client"
  connectanum_mcp:
    path: "$ROOT_DIR/packages/connectanum_mcp"
  connectanum_router:
    path: "$ROOT_DIR/packages/connectanum_router"
EOF

  cat >"$smoke_dir/bin/main.dart" <<'DART'
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:connectanum_router/connectanum_router.dart';

const _realm = 'consumer.mcp.realm';
const _authPath = '/auth';
const _publicMcpPath = '/mcp';
const _secureMcpPath = '/mcp/secure';
const _secureJsonPostMcpPath = '/mcp/secure-json-post';
const _jsonPostMcpPath = '/mcp/json-post';
const _nonStreamingPostMcpPath = '/mcp/non-streaming-post';
const _rateLimitedMcpPath = '/mcp/rate-limited';
const _ticketAuthId = 'consumer-user';
const _ticketSecret = 'consumer-ticket';
const _otherTicketAuthId = 'consumer-other-user';
const _otherTicketSecret = 'consumer-other-ticket';
const _wampCraAuthId = 'consumer-cra-user';
const _wampCraSecret = 'consumer-cra-secret';
const _scramAuthId = 'consumer-scram-user';
const _scramSecret = 'consumer-scram-secret';
const _topic = 'consumer.events.task';
const _batchTopic = 'consumer.events.batch';
const _procedure = 'consumer.task.lookup';
const _resourceUri = 'consumer://mcp/context';
const _pagedResourceUri = 'consumer://mcp/context/followup';
const _resourceTemplateUri = 'consumer://mcp/task/{taskId}';
const _pagedResourceTemplateUri = 'consumer://mcp/task/{taskId}/followup';
const _promptName = 'inspect-consumer-task';
const _pagedPromptName = 'inspect-consumer-task-followup';
const _headerWrappedNote = '=?base64?Zm9v?=';
const _supportedOlderProtocolVersions = ['2025-03-26', '2025-06-18'];
const _unsupportedProtocolVersion = '2099-01-01';
const _unknownAccessToken = 'consumer-unknown-access-token';
const _allowedOrigin = 'https://consumer.example';
const _disallowedOrigin = 'https://attacker.example';
const _publicMcpServerName = 'consumer-router-mcp';
const _publicMcpServerVersion = '9.8.7';
const _publicMcpServerTitle = 'Consumer router MCP';
const _publicMcpServerDescription =
    'Route metadata visible to consumer MCP clients.';
const _publicMcpInstructions =
    'Use this endpoint with consumer route-scoped credentials.';

final _consumerProcedureTaskIds = <String>[];

Future<void> main() async {
  final nativeLibraryPath = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (nativeLibraryPath == null || nativeLibraryPath.isEmpty) {
    _runApiOnlySmoke();
    print(
      'Native runtime unavailable; completed public API smoke without '
      'starting router-hosted MCP.',
    );
    return;
  }

  await _runRouterHostedMcpSmoke(nativeLibraryPath);
}

void _runApiOnlySmoke() {
  final client = McpStreamableHttpClient(Uri.parse('http://127.0.0.1:1/mcp'));
  final config = RouterConfig(
    endpoints: [
      Endpoint(
        host: '127.0.0.1',
        port: 0,
        tlsMode: TlsMode.disabled,
        maxRawSocketSizeExponent: 16,
      ),
    ],
  );
  final tool = McpTool(
    name: 'consumer.echo',
    description: 'Consumer API check',
    handler: (_) => McpToolResult.text('ok'),
  );

  if (client.endpoint.path != '/mcp' ||
      config.endpoints.single.port != 0 ||
      tool.name != 'consumer.echo') {
    throw StateError('Unexpected consumer MCP API smoke state.');
  }

  client.close();
}

Future<void> _runRouterHostedMcpSmoke(String nativeLibraryPath) async {
  late final NativeTransportRuntime runtime;
  try {
    runtime = NativeTransportRuntime(libraryPath: nativeLibraryPath);
  } on ArgumentError catch (error) {
    throw StateError('Failed to load native runtime: ${error.message}');
  }

  runtime.start();
  final router = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 0,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
        ),
      ],
    ),
    settings: _consumerRouterSettings(),
  );

  final binding = router.start(runtime);
  final serviceSession = await binding.createInternalSession(
    realmUri: _realm,
    authId: 'consumer-service',
    authRole: 'service',
  );
  final publicClient = McpStreamableHttpClient(_mcpEndpoint(binding));
  McpStreamableHttpClient? secureClient;

  try {
    await _registerConsumerApi(serviceSession);
    await _smokeMcpProtocolVersionCompatibility(binding, label: 'public');
    await _smokeDirectJson(publicClient, serviceSession, label: 'public');
    await _smokeStreamableMcp(
      publicClient,
      serviceSession,
      label: 'public',
    );
    await _smokeJsonPostMcpRoute(binding, serviceSession);
    await _smokeNonStreamingPostMcpRoute(binding, serviceSession);
    await _smokeRateLimitedMcpRoute(binding);

    await _assertSecureMcpRequiresBearer(binding);
    await _assertSecureMcpRequiresBearer(
      binding,
      endpoint: _secureJsonPostMcpEndpoint(binding),
    );
    await _assertSecureMcpRejectsBearer(
      binding,
      _unknownAccessToken,
      acceptedMessage:
          'Bearer-protected MCP endpoint accepted an unknown access token.',
    );
    await _assertSecureMcpRejectsBearer(
      binding,
      _unknownAccessToken,
      endpoint: _secureJsonPostMcpEndpoint(binding),
      acceptedMessage:
          'Bearer-protected JSON-response MCP endpoint accepted an unknown '
          'access token.',
    );
    final grant = await _issueTicketHttpGrant(binding);
    _expectHttpAuthGrant(
      grant,
      authId: _ticketAuthId,
      authMethod: 'ticket',
      authProvider: 'consumer-local',
    );
    await _smokeMcpProtocolVersionCompatibility(
      binding,
      label: 'secure',
      secure: true,
      authGrant: grant,
    );
    final otherGrant = await _issueTicketHttpGrant(
      binding,
      authId: _otherTicketAuthId,
      ticket: _otherTicketSecret,
    );
    await _smokeMcpOriginPolicy(binding, grant);
    await _smokeMcpCorsPreflight(binding, serviceSession, grant);
    await _smokeSecureJsonPostMcpRoute(
      binding,
      serviceSession,
      grant,
      otherGrant,
    );
    await _smokeLowercaseBearerMcpClients(binding, grant);
    secureClient = McpStreamableHttpClient.withAuthGrant(
      _mcpEndpoint(binding, secure: true),
      grant,
    );
    await _smokeDirectJson(secureClient, serviceSession, label: 'secure');
    await _smokeStreamableMcp(
      secureClient,
      serviceSession,
      label: 'secure',
    );
    await _smokeStreamableSessionReuseIsolation(
      binding,
      serviceSession,
      grant,
      otherGrant,
    );
    await _smokeChallengeHttpAuthMcpGrants(binding, serviceSession);
    await _smokeSecureMcpRefreshAndRevocation(
      binding,
      serviceSession,
      grant,
      label: 'secure-ticket-lifecycle',
    );
    print('Consumer package router-hosted MCP smoke completed.');
  } finally {
    secureClient?.close();
    publicClient.close();
    await serviceSession.close();
    await binding.dispose();
    runtime.shutdown();
    runtime.dispose();
  }
}

RouterSettings _consumerRouterSettings() {
  final realm = RealmSettingsBuilder(_realm)
    ..addAuthMethod('anonymous')
    ..addAuthMethod('ticket', options: const {'authenticator': 'ticket-demo'})
    ..addAuthMethod(
      'wampcra',
      options: const {'authenticator': 'cra-demo'},
    )
    ..addAuthMethod(
      'scram',
      options: const {'authenticator': 'scram-demo'},
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('anonymous')
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('consumer.task.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['call']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('consumer.events.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['publish', 'subscribe', 'unsubscribe']),
        ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('member')
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('consumer.task.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['call']),
        )
        ..addPermissionFromBuilder(
          PermissionSettingsBuilder('consumer.events.')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const ['publish', 'subscribe', 'unsubscribe']),
        ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('service')..addPermissionFromBuilder(
        PermissionSettingsBuilder('consumer.')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'register',
            'unregister',
            'call',
            'publish',
            'subscribe',
            'unsubscribe',
          ]),
      ),
    );

  final listener = ListenerSettingsBuilder(
    'consumer-mcp-http',
    '127.0.0.1:0',
  )
    ..setSessionProfile('public-wamp')
    ..addProtocol(ListenerProtocol.rawsocket)
    ..addProtocol(ListenerProtocol.http)
    ..setRawSocketOptions(const RawSocketListenerSettings(maxFrameExponent: 16))
    ..setHttpOptions(
      const HttpListenerSettings(
        sessionProfile: 'public-http',
        routes: [
          HttpRouteSettings(
            match: HttpRouteMatch(path: _authPath),
            action: HttpRouteAction(
              type: HttpRouteActionType.auth,
              sessionProfile: 'mcp-ticket',
              options: {
                'allow_insecure_transport': true,
                'token_ttl_ms': 60000,
                'refresh_token_ttl_ms': 300000,
                'rotate_refresh_tokens': true,
              },
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: _publicMcpPath),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: _realm,
              sessionProfile: 'mcp-public',
              options: {
                'name': _publicMcpServerName,
                'version': _publicMcpServerVersion,
                'title': _publicMcpServerTitle,
                'description': _publicMcpServerDescription,
                'instructions': _publicMcpInstructions,
                'includeRegisteredProcedures': true,
                'includePubsubTools': true,
                'toolListPageSize': 1,
                'resourceListPageSize': 1,
                'resourceTemplateListPageSize': 1,
                'promptListPageSize': 1,
                'allowedOrigins': [_allowedOrigin],
                'topics': [
                  {
                    'topic': _topic,
                    'title': 'Consumer task events',
                    'description': 'Events emitted by consumer task tools.',
                    'eventJsonSchema': {
                      'type': 'object',
                      'properties': {
                        'taskId': {'type': 'string'},
                      },
                    },
                    'metadata': {
                      'shortDescription':
                          'Consumer task lifecycle event stream',
                      'domain': 'consumer',
                      'entity': 'task',
                      'verbs': ['publish', 'subscribe'],
                      'tags': ['safe', 'smoke', 'event'],
                    },
                  },
                  {
                    'topic': _batchTopic,
                    'title': 'Consumer batch smoke events',
                    'description':
                        'Events used by consumer MCP batch smoke checks.',
                  },
                ],
                'resources': [
                  {
                    'uri': _resourceUri,
                    'name': 'consumer-mcp-context',
                    'title': 'Consumer MCP context',
                    'description':
                        'Static context exposed by the consumer MCP route.',
                    'mimeType': 'text/plain',
                    'text':
                        'Consumer package router-hosted MCP context document.',
                  },
                  {
                    'uri': _pagedResourceUri,
                    'name': 'consumer-mcp-followup-context',
                    'title': 'Consumer MCP follow-up context',
                    'description':
                        'Second-page static context for catalog smoke checks.',
                    'mimeType': 'text/plain',
                    'text': 'Consumer package follow-up MCP context document.',
                  },
                ],
                'resourceTemplates': [
                  {
                    'uriTemplate': _resourceTemplateUri,
                    'name': 'consumer-task-context',
                    'title': 'Consumer task context',
                    'description':
                        'Template for consumer task context resources.',
                    'mimeType': 'application/json',
                  },
                  {
                    'uriTemplate': _pagedResourceTemplateUri,
                    'name': 'consumer-task-followup-context',
                    'title': 'Consumer task follow-up context',
                    'description':
                        'Second-page template for catalog smoke checks.',
                    'mimeType': 'application/json',
                  },
                ],
                'prompts': [
                  {
                    'name': _promptName,
                    'title': 'Inspect consumer task',
                    'description': 'Builds a prompt for a consumer task id.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect consumer task {{taskId}} using MCP route context.',
                      },
                    ],
                  },
                  {
                    'name': _pagedPromptName,
                    'title': 'Inspect consumer task follow-up',
                    'description':
                        'Second-page prompt for catalog smoke checks.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect follow-up consumer task {{taskId}}.',
                      },
                    ],
                  },
                ],
              },
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: _secureMcpPath),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: _realm,
              sessionProfile: 'mcp-ticket',
              options: {
                'include_registered_procedures': true,
                'include_pubsub_tools': true,
                'allow_insecure_transport': true,
                'tool_list_page_size': 1,
                'resource_list_page_size': 1,
                'resource_template_list_page_size': 1,
                'prompt_list_page_size': 1,
                'allowed_origins': [_allowedOrigin],
                'topics': [
                  {
                    'topic': _topic,
                    'title': 'Consumer task events',
                    'description': 'Events emitted by consumer task tools.',
                    'event_json_schema': {
                      'type': 'object',
                      'properties': {
                        'taskId': {'type': 'string'},
                      },
                    },
                    'metadata': {
                      'short_description':
                          'Consumer task lifecycle event stream',
                      'domain': 'consumer',
                      'entity': 'task',
                      'verbs': ['publish', 'subscribe'],
                      'tags': ['safe', 'smoke', 'event'],
                    },
                  },
                  {
                    'topic': _batchTopic,
                    'title': 'Consumer batch smoke events',
                    'description':
                        'Events used by consumer MCP batch smoke checks.',
                  },
                ],
                'resources': [
                  {
                    'uri': _resourceUri,
                    'name': 'consumer-mcp-context',
                    'title': 'Consumer MCP context',
                    'description':
                        'Static context exposed by the consumer MCP route.',
                    'mime_type': 'text/plain',
                    'text':
                        'Consumer package router-hosted MCP context document.',
                  },
                  {
                    'uri': _pagedResourceUri,
                    'name': 'consumer-mcp-followup-context',
                    'title': 'Consumer MCP follow-up context',
                    'description':
                        'Second-page static context for catalog smoke checks.',
                    'mime_type': 'text/plain',
                    'text': 'Consumer package follow-up MCP context document.',
                  },
                ],
                'resource_templates': [
                  {
                    'uri_template': _resourceTemplateUri,
                    'name': 'consumer-task-context',
                    'title': 'Consumer task context',
                    'description':
                        'Template for consumer task context resources.',
                    'mime_type': 'application/json',
                  },
                  {
                    'uri_template': _pagedResourceTemplateUri,
                    'name': 'consumer-task-followup-context',
                    'title': 'Consumer task follow-up context',
                    'description':
                        'Second-page template for catalog smoke checks.',
                    'mime_type': 'application/json',
                  },
                ],
                'prompts': [
                  {
                    'name': _promptName,
                    'title': 'Inspect consumer task',
                    'description': 'Builds a prompt for a consumer task id.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect consumer task {{taskId}} using MCP route context.',
                      },
                    ],
                  },
                  {
                    'name': _pagedPromptName,
                    'title': 'Inspect consumer task follow-up',
                    'description':
                        'Second-page prompt for catalog smoke checks.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect follow-up consumer task {{taskId}}.',
                      },
                    ],
                  },
                ],
              },
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: _secureJsonPostMcpPath),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: _realm,
              sessionProfile: 'mcp-ticket',
              options: {
                'include_registered_procedures': true,
                'include_pubsub_tools': true,
                'allow_insecure_transport': true,
                'tool_list_page_size': 1,
                'resource_list_page_size': 1,
                'resource_template_list_page_size': 1,
                'prompt_list_page_size': 1,
                'post_response_transport': 'json',
                'allowed_origins': [_allowedOrigin],
                'topics': [
                  {
                    'topic': _topic,
                    'title': 'Consumer task events',
                    'description': 'Events emitted by consumer task tools.',
                    'event_json_schema': {
                      'type': 'object',
                      'properties': {
                        'taskId': {'type': 'string'},
                      },
                    },
                    'metadata': {
                      'short_description':
                          'Consumer task lifecycle event stream',
                      'domain': 'consumer',
                      'entity': 'task',
                      'verbs': ['publish', 'subscribe'],
                      'tags': ['safe', 'smoke', 'event'],
                    },
                  },
                  {
                    'topic': _batchTopic,
                    'title': 'Consumer batch smoke events',
                    'description':
                        'Events used by consumer MCP batch smoke checks.',
                  },
                ],
                'resources': [
                  {
                    'uri': _resourceUri,
                    'name': 'consumer-mcp-context',
                    'title': 'Consumer MCP context',
                    'description':
                        'Static context exposed by the secure JSON POST route.',
                    'mime_type': 'text/plain',
                    'text':
                        'Consumer package router-hosted MCP context document.',
                  },
                  {
                    'uri': _pagedResourceUri,
                    'name': 'consumer-mcp-followup-context',
                    'title': 'Consumer MCP follow-up context',
                    'description':
                        'Second-page static context for secure JSON POST '
                        'smoke.',
                    'mime_type': 'text/plain',
                    'text': 'Consumer package follow-up MCP context document.',
                  },
                ],
                'resource_templates': [
                  {
                    'uri_template': _resourceTemplateUri,
                    'name': 'consumer-task-context',
                    'title': 'Consumer task context',
                    'description':
                        'Template for consumer task context resources.',
                    'mime_type': 'application/json',
                  },
                  {
                    'uri_template': _pagedResourceTemplateUri,
                    'name': 'consumer-task-followup-context',
                    'title': 'Consumer task follow-up context',
                    'description':
                        'Second-page template for secure JSON POST smoke.',
                    'mime_type': 'application/json',
                  },
                ],
                'prompts': [
                  {
                    'name': _promptName,
                    'title': 'Inspect consumer task',
                    'description': 'Builds a prompt for a consumer task id.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect consumer task {{taskId}} using MCP route context.',
                      },
                    ],
                  },
                  {
                    'name': _pagedPromptName,
                    'title': 'Inspect consumer task follow-up',
                    'description':
                        'Second-page prompt for secure JSON POST smoke.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect follow-up consumer task {{taskId}}.',
                      },
                    ],
                  },
                ],
              },
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: _rateLimitedMcpPath),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: _realm,
              sessionProfile: 'mcp-public',
              rateLimit: HttpRouteRateLimitSettings(
                maxRequests: 2,
                windowMs: 60000,
              ),
              options: {
                'include_registered_procedures': true,
                'allowed_origins': [_allowedOrigin],
              },
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: _jsonPostMcpPath),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: _realm,
              sessionProfile: 'mcp-public',
              options: {
                'include_registered_procedures': true,
                'include_pubsub_tools': true,
                'tool_list_page_size': 1,
                'resource_list_page_size': 1,
                'resource_template_list_page_size': 1,
                'prompt_list_page_size': 1,
                'postResponseTransport': 'json',
                'allowed_origins': [_allowedOrigin],
                'topics': [
                  {
                    'topic': _topic,
                    'title': 'Consumer task events',
                    'description': 'Events emitted by consumer task tools.',
                    'event_json_schema': {
                      'type': 'object',
                      'properties': {
                        'taskId': {'type': 'string'},
                      },
                    },
                    'metadata': {
                      'short_description':
                          'Consumer task lifecycle event stream',
                      'domain': 'consumer',
                      'entity': 'task',
                      'verbs': ['publish', 'subscribe'],
                      'tags': ['safe', 'smoke', 'event'],
                    },
                  },
                  {
                    'topic': _batchTopic,
                    'title': 'Consumer batch smoke events',
                    'description':
                        'Events used by consumer MCP batch smoke checks.',
                  },
                ],
                'resources': [
                  {
                    'uri': _resourceUri,
                    'name': 'consumer-mcp-context',
                    'title': 'Consumer MCP context',
                    'description':
                        'Static context exposed by the JSON POST route.',
                    'mime_type': 'text/plain',
                    'text':
                        'Consumer package router-hosted MCP context document.',
                  },
                  {
                    'uri': _pagedResourceUri,
                    'name': 'consumer-mcp-followup-context',
                    'title': 'Consumer MCP follow-up context',
                    'description':
                        'Second-page static context for JSON POST smoke.',
                    'mime_type': 'text/plain',
                    'text': 'Consumer package follow-up MCP context document.',
                  },
                ],
                'resource_templates': [
                  {
                    'uri_template': _resourceTemplateUri,
                    'name': 'consumer-task-context',
                    'title': 'Consumer task context',
                    'description':
                        'Template for consumer task context resources.',
                    'mime_type': 'application/json',
                  },
                  {
                    'uri_template': _pagedResourceTemplateUri,
                    'name': 'consumer-task-followup-context',
                    'title': 'Consumer task follow-up context',
                    'description':
                        'Second-page template for JSON POST smoke.',
                    'mime_type': 'application/json',
                  },
                ],
                'prompts': [
                  {
                    'name': _promptName,
                    'title': 'Inspect consumer task',
                    'description': 'Builds a prompt for a consumer task id.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect consumer task {{taskId}} using MCP route context.',
                      },
                    ],
                  },
                  {
                    'name': _pagedPromptName,
                    'title': 'Inspect consumer task follow-up',
                    'description':
                        'Second-page prompt for JSON POST smoke.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect follow-up consumer task {{taskId}}.',
                      },
                    ],
                  },
                ],
              },
            ),
          ),
          HttpRouteSettings(
            match: HttpRouteMatch(path: _nonStreamingPostMcpPath),
            action: HttpRouteAction(
              type: HttpRouteActionType.mcp,
              realm: _realm,
              sessionProfile: 'mcp-public',
              options: {
                'include_registered_procedures': true,
                'include_pubsub_tools': true,
                'tool_list_page_size': 1,
                'resource_list_page_size': 1,
                'resource_template_list_page_size': 1,
                'prompt_list_page_size': 1,
                'streamPostResponses': false,
                'allowed_origins': [_allowedOrigin],
                'topics': [
                  {
                    'topic': _topic,
                    'title': 'Consumer task events',
                    'description': 'Events emitted by consumer task tools.',
                    'event_json_schema': {
                      'type': 'object',
                      'properties': {
                        'taskId': {'type': 'string'},
                      },
                    },
                    'metadata': {
                      'short_description':
                          'Consumer task lifecycle event stream',
                      'domain': 'consumer',
                      'entity': 'task',
                      'verbs': ['publish', 'subscribe'],
                      'tags': ['safe', 'smoke', 'event'],
                    },
                  },
                  {
                    'topic': _batchTopic,
                    'title': 'Consumer batch smoke events',
                    'description':
                        'Events used by consumer MCP batch smoke checks.',
                  },
                ],
                'resources': [
                  {
                    'uri': _resourceUri,
                    'name': 'consumer-mcp-context',
                    'title': 'Consumer MCP context',
                    'description':
                        'Static context exposed by the non-streaming route.',
                    'mime_type': 'text/plain',
                    'text':
                        'Consumer package router-hosted MCP context document.',
                  },
                  {
                    'uri': _pagedResourceUri,
                    'name': 'consumer-mcp-followup-context',
                    'title': 'Consumer MCP follow-up context',
                    'description':
                        'Second-page static context for non-streaming smoke.',
                    'mime_type': 'text/plain',
                    'text': 'Consumer package follow-up MCP context document.',
                  },
                ],
                'resource_templates': [
                  {
                    'uri_template': _resourceTemplateUri,
                    'name': 'consumer-task-context',
                    'title': 'Consumer task context',
                    'description':
                        'Template for consumer task context resources.',
                    'mime_type': 'application/json',
                  },
                  {
                    'uri_template': _pagedResourceTemplateUri,
                    'name': 'consumer-task-followup-context',
                    'title': 'Consumer task follow-up context',
                    'description':
                        'Second-page template for non-streaming smoke.',
                    'mime_type': 'application/json',
                  },
                ],
                'prompts': [
                  {
                    'name': _promptName,
                    'title': 'Inspect consumer task',
                    'description': 'Builds a prompt for a consumer task id.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect consumer task {{taskId}} using MCP route context.',
                      },
                    ],
                  },
                  {
                    'name': _pagedPromptName,
                    'title': 'Inspect consumer task follow-up',
                    'description':
                        'Second-page prompt for non-streaming smoke.',
                    'arguments': [
                      {
                        'name': 'taskId',
                        'description': 'Task id to inspect.',
                        'required': true,
                      },
                    ],
                    'messages': [
                      {
                        'role': 'user',
                        'text':
                            'Inspect follow-up consumer task {{taskId}}.',
                      },
                    ],
                  },
                ],
              },
            ),
          ),
        ],
      ),
    )
    ..setOptions(const {'max_rawsocket_size_exponent': 16});

  return (RouterSettingsBuilder()
        ..addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        )
        ..addRealmFromBuilder(realm)
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('public-wamp')
            ..addAuthMethod('anonymous'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('public-http'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('mcp-public')
            ..setRealm(_realm)
            ..addAuthMethod('anonymous'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('mcp-ticket')
            ..setRealm(_realm)
            ..setAuthMethods(const ['ticket', 'wampcra', 'scram']),
        )
        ..addAuthenticator(
          'ticket-demo',
          const AuthenticatorDefinition(
            type: 'ticket',
            options: {
              'secrets': {
                _ticketAuthId: {
                  'ticket': _ticketSecret,
                  'role': 'member',
                  'provider': 'consumer-local',
                },
                _otherTicketAuthId: {
                  'ticket': _otherTicketSecret,
                  'role': 'member',
                  'provider': 'consumer-local',
                },
              },
            },
          ),
        )
        ..addAuthenticator(
          'cra-demo',
          const AuthenticatorDefinition(
            type: 'wampcra',
            options: {
              'secrets': {
                _wampCraAuthId: {
                  'secret': _wampCraSecret,
                  'salt': 'consumer-cra-salt',
                  'iterations': 1000,
                  'keylen': 32,
                  'role': 'member',
                  'provider': 'consumer-cra',
                  'challenge': {'scope': 'consumer-mcp'},
                },
              },
            },
          ),
        )
        ..addAuthenticator(
          'scram-demo',
          const AuthenticatorDefinition(
            type: 'scram',
            options: {
              'secrets': {
                _scramAuthId: {
                  'secret': _scramSecret,
                  'salt': 'CgsMDQ4PEBESExQVFhcYGQ==',
                  'iterations': 4096,
                  'role': 'member',
                  'provider': 'consumer-scram',
                },
              },
            },
          ),
        )
        ..addListenerFromBuilder(listener))
      .build();
}

Uri _mcpEndpoint(RouterBinding binding, {bool secure = false}) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: listener.port,
    path: secure ? _secureMcpPath : _publicMcpPath,
  );
}

Uri _authEndpoint(RouterBinding binding) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: listener.port,
    path: _authPath,
  );
}

Uri _rateLimitedMcpEndpoint(RouterBinding binding) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: listener.port,
    path: _rateLimitedMcpPath,
  );
}

Uri _jsonPostMcpEndpoint(RouterBinding binding) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: listener.port,
    path: _jsonPostMcpPath,
  );
}

Uri _secureJsonPostMcpEndpoint(RouterBinding binding) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: listener.port,
    path: _secureJsonPostMcpPath,
  );
}

Uri _nonStreamingPostMcpEndpoint(RouterBinding binding) {
  final listener = binding.listeners.single;
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: listener.port,
    path: _nonStreamingPostMcpPath,
  );
}

Future<void> _registerConsumerApi(RouterSession serviceSession) async {
  final registration = await serviceSession.register(
    _procedure,
    options: RegisterOptions(
      custom: const {
        '_ai_meta_data': {
          'short_description': 'Look up consumer task state',
          'description': 'Returns a small task status document.',
          'input_json_schema': {
            'type': 'object',
            'properties': {
              'taskId': {'type': 'string', 'x-mcp-header': 'TaskId'},
              'note': {'type': 'string', 'x-mcp-header': 'Note'},
            },
            'required': ['taskId'],
          },
          'read_only_hint': true,
          'destructive_hint': false,
          'idempotent_hint': true,
          'open_world_hint': false,
        },
      },
    ),
  );

  registration.onInvoke((invocation) {
    final taskId = invocation.argumentsKeywords?['taskId'] ?? 'unknown';
    final note = invocation.argumentsKeywords?['note'];
    if (taskId is String) {
      _consumerProcedureTaskIds.add(taskId);
    }
    invocation.respondWith(
      argumentsKeywords: {
        'taskId': taskId,
        'status': 'open',
        'source': 'consumer-package-smoke',
        if (note != null) 'note': note,
      },
    );
  });
}

Future<void> _expectConsumerProcedureInvocation(
  String taskId, {
  required String label,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (_consumerProcedureTaskIds.contains(taskId)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('MCP $label did not invoke $_procedure for $taskId.');
}

void _expectNoConsumerProcedureInvocation(
  String taskId, {
  required String label,
}) {
  if (_consumerProcedureTaskIds.contains(taskId)) {
    throw StateError('MCP $label unexpectedly invoked $_procedure.');
  }
}

Future<void> _assertSecureMcpRequiresBearer(
  RouterBinding binding, {
  Uri? endpoint,
}) async {
  final client = McpStreamableHttpClient(
    endpoint ?? _mcpEndpoint(binding, secure: true),
  );
  try {
    await _assertSecureMcpUnauthorizedCoverage(client);
  } finally {
    client.close();
  }
}

Future<void> _assertSecureMcpUnauthorizedCoverage(
  McpStreamableHttpClient client, {
  String? acceptedMessage,
}) async {
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON tools/list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.listToolsDirect(
          id: 'secure-unauthenticated-tools',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON tools/call',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.callToolDirect(
          _procedure,
          id: 'secure-unauthenticated-direct-tool-call',
          arguments: const <String, Object?>{
            'taskId': 'T-secure-unauthenticated-direct-tool-call',
          },
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON ping',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.pingDirect(id: 'secure-unauthenticated-direct-ping');
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON resources/list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.listResourcesDirect(
          id: 'secure-unauthenticated-direct-resources',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON resources/read',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.readResourceDirect(
          _resourceUri,
          id: 'secure-unauthenticated-direct-resource-read',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON resources/templates/list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.listResourceTemplatesDirect(
          id: 'secure-unauthenticated-direct-resource-templates',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON prompts/list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.listPromptsDirect(
          id: 'secure-unauthenticated-direct-prompts',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON prompts/get',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.getPromptDirect(
          _promptName,
          id: 'secure-unauthenticated-direct-prompt-get',
          arguments: const <String, String>{
            'taskId': 'T-secure-unauthenticated-direct-prompt-get',
          },
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON batch tools/list and tools/call',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.postBatchDirect(
          [
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-tools',
              'method': 'tools/list',
              'params': {},
            },
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-tool-call',
              'method': 'tools/call',
              'params': {
                'name': _procedure,
                'arguments': {
                  'taskId': 'T-secure-unauthenticated-direct-batch-tool-call',
                },
              },
            },
          ],
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON batch resources/prompts',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.postBatchDirect(
          [
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-resources',
              'method': 'resources/list',
              'params': {},
            },
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-resource-read',
              'method': 'resources/read',
              'params': {'uri': _resourceUri},
            },
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-resource-templates',
              'method': 'resources/templates/list',
              'params': {},
            },
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-prompts',
              'method': 'prompts/list',
              'params': {},
            },
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-prompt-get',
              'method': 'prompts/get',
              'params': {
                'name': _promptName,
                'arguments': {
                  'taskId': 'T-secure-unauthenticated-direct-batch-prompt-get',
                },
              },
            },
          ],
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON connectanum.api.list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.requestDirect(
          'connectanum.api.list',
          id: 'secure-unauthenticated-api-list',
          params: const <String, Object?>{'kind': 'topic'},
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON connectanum.pubsub.subscribe',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.requestDirect(
          'connectanum.pubsub.subscribe',
          id: 'secure-unauthenticated-pubsub-subscribe',
          params: const <String, Object?>{
            'topic': _topic,
            'queueLimit': 1,
          },
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON batch WAMP meta/pubsub',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.postBatchDirect(
          [
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-api-list',
              'method': 'connectanum.api.list',
              'params': {'kind': 'topic'},
            },
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-pubsub-subscribe',
              'method': 'connectanum.pubsub.subscribe',
              'params': {'topic': _topic, 'queueLimit': 1},
            },
          ],
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'Streamable initialize',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.initialize(id: 'secure-unauthenticated-initialize');
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'Streamable resources/list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.listResources(
          id: 'secure-unauthenticated-streamable-resources',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'Streamable resources/read',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.readResource(
          _resourceUri,
          id: 'secure-unauthenticated-streamable-resource-read',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'Streamable resources/templates/list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.listResourceTemplates(
          id: 'secure-unauthenticated-streamable-resource-templates',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'Streamable prompts/list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.listPrompts(
          id: 'secure-unauthenticated-streamable-prompts',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'Streamable prompts/get',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.getPrompt(
          _promptName,
          id: 'secure-unauthenticated-streamable-prompt-get',
          arguments: const <String, String>{
            'taskId': 'T-secure-unauthenticated-streamable-prompt-get',
          },
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'Streamable batch tools/list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.postBatch([
          {
            'jsonrpc': '2.0',
            'id': 'secure-unauthenticated-streamable-batch-tools',
            'method': 'tools/list',
            'params': {},
          },
        ]);
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'Streamable batch resources/prompts',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.postBatch([
          {
            'jsonrpc': '2.0',
            'id': 'secure-unauthenticated-streamable-batch-resources',
            'method': 'resources/list',
            'params': {},
          },
          {
            'jsonrpc': '2.0',
            'id': 'secure-unauthenticated-streamable-batch-resource-read',
            'method': 'resources/read',
            'params': {'uri': _resourceUri},
          },
          {
            'jsonrpc': '2.0',
            'id': 'secure-unauthenticated-streamable-batch-resource-templates',
            'method': 'resources/templates/list',
            'params': {},
          },
          {
            'jsonrpc': '2.0',
            'id': 'secure-unauthenticated-streamable-batch-prompts',
            'method': 'prompts/list',
            'params': {},
          },
          {
            'jsonrpc': '2.0',
            'id': 'secure-unauthenticated-streamable-batch-prompt-get',
            'method': 'prompts/get',
            'params': {
              'name': _promptName,
              'arguments': {
                'taskId': 'T-secure-unauthenticated-streamable-batch-prompt-get',
              },
            },
          },
        ]);
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'Streamable batch WAMP meta/pubsub tools',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.postBatch([
          {
            'jsonrpc': '2.0',
            'id': 'secure-unauthenticated-streamable-batch-api-list',
            'method': 'tools/call',
            'params': {
              'name': 'connectanum.api.list',
              'arguments': {'kind': 'topic'},
            },
          },
          {
            'jsonrpc': '2.0',
            'id': 'secure-unauthenticated-streamable-batch-pubsub-subscribe',
            'method': 'tools/call',
            'params': {
              'name': 'connectanum.pubsub.subscribe',
              'arguments': {'topic': _topic, 'queueLimit': 1},
            },
          },
        ]);
      },
    );
}

Future<void> _expectSecureMcpUnauthorized(
  McpStreamableHttpClient client, {
  required String label,
  String? acceptedMessage,
  required Future<void> Function() operation,
}) async {
  try {
    await operation();
    throw StateError(
      acceptedMessage == null
          ? 'Bearer-protected MCP endpoint accepted no credentials for $label.'
          : '$acceptedMessage ($label).',
    );
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'Bearer-protected MCP endpoint returned ${error.statusCode} '
        'instead of ${HttpStatus.unauthorized} for $label.',
      );
    }
  }
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Bearer-protected MCP endpoint captured Streamable state after '
      'rejecting $label.',
    );
  }
}

McpStreamableHttpClient _protocolVersionClient(
  Uri endpoint, {
  required String defaultProtocolVersion,
  ConnectanumHttpAuthGrant? authGrant,
}) {
  final grant = authGrant;
  if (grant == null) {
    return McpStreamableHttpClient(
      endpoint,
      defaultProtocolVersion: defaultProtocolVersion,
    );
  }
  return McpStreamableHttpClient.withAuthGrant(
    endpoint,
    grant,
    defaultProtocolVersion: defaultProtocolVersion,
  );
}

Future<void> _smokeMcpProtocolVersionCompatibility(
  RouterBinding binding, {
  required String label,
  bool secure = false,
  ConnectanumHttpAuthGrant? authGrant,
}) async {
  final endpoint = _mcpEndpoint(binding, secure: secure);
  for (final version in _supportedOlderProtocolVersions) {
    await _smokeSupportedMcpProtocolVersion(
      endpoint,
      version,
      label: label,
      authGrant: authGrant,
    );
  }
  await _assertUnsupportedMcpProtocolVersionRejected(
    endpoint,
    label: label,
    authGrant: authGrant,
  );
}

Future<void> _smokeSupportedMcpProtocolVersion(
  Uri endpoint,
  String protocolVersion, {
  required String label,
  ConnectanumHttpAuthGrant? authGrant,
}) async {
  final client = _protocolVersionClient(
    endpoint,
    defaultProtocolVersion: McpStreamableHttpClient.latestProtocolVersion,
    authGrant: authGrant,
  );
  try {
    final initializeId = '$label-supported-$protocolVersion-initialize';
    final initialize = await client.initialize(
      id: initializeId,
      protocolVersion: protocolVersion,
    );
    final returnedInitializeId = initialize['id'];
    if (returnedInitializeId != initializeId) {
      throw StateError(
        'MCP $label initialize with protocol $protocolVersion returned '
        'unexpected id $returnedInitializeId.',
      );
    }
    final sessionId = client.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError(
        'MCP $label initialize with protocol $protocolVersion did not create '
        'a Streamable HTTP session.',
      );
    }
    final initializeResult = initialize['result'];
    if (initializeResult is! Map ||
        initializeResult['protocolVersion'] != protocolVersion) {
      throw StateError(
        'MCP $label initialize with protocol $protocolVersion returned '
        'unexpected negotiated protocol version.',
      );
    }
    if (client.protocolVersion != protocolVersion) {
      throw StateError(
        'MCP $label initialize with protocol $protocolVersion did not keep '
        'the requested supported protocol version.',
      );
    }

    await client.notifyInitialized();
    final ping = await client.ping(id: '$label-supported-$protocolVersion-ping');
    if (ping.isNotEmpty) {
      throw StateError(
        'MCP $label ping after protocol $protocolVersion negotiation returned '
        'unexpected content.',
      );
    }

    await client.deleteSession();
    if (client.sessionId != null || client.lastEventId != null) {
      throw StateError(
        'MCP $label protocol $protocolVersion compatibility smoke leaked '
        'Streamable session state.',
      );
    }
  } finally {
    client.close();
  }
}

Future<void> _assertUnsupportedMcpProtocolVersionRejected(
  Uri endpoint, {
  required String label,
  ConnectanumHttpAuthGrant? authGrant,
}) async {
  final httpClient = HttpClient();
  try {
    final request = await httpClient.postUrl(endpoint);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/event-stream',
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('MCP-Protocol-Version', _unsupportedProtocolVersion);
    final grant = authGrant;
    if (grant != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        '${grant.tokenType} ${grant.accessToken}',
      );
    }
    final requestBody = utf8.encode(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-unsupported-protocol-initialize',
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': _unsupportedProtocolVersion,
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{
            'name': 'connectanum_mcp_consumer_smoke',
            'version': '0.0.0',
          },
        },
      }),
    );
    request.contentLength = requestBody.length;
    request.add(requestBody);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'MCP $label accepted an unsupported protocol version '
        'with status ${response.statusCode}: $body',
      );
    }
  } finally {
    httpClient.close(force: true);
  }
}

Future<void> _smokeTypedProtocolVersionOverrides(
  McpStreamableHttpClient client, {
  required String label,
  required String routeLabel,
}) async {
  final previousProtocolVersion = client.protocolVersion;
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final olderProtocolVersion = _supportedOlderProtocolVersions.first;
  final newerProtocolVersion = _supportedOlderProtocolVersions.last;

  final tools = await client.listToolsDirect(
    id: '$label-direct-protocol-tools',
    protocolVersion: olderProtocolVersion,
  );
  if (tools.tools.isEmpty) {
    throw StateError(
      '$routeLabel direct protocol tools/list returned no tools.',
    );
  }

  final toolCall = await client.callToolDirect(
    _procedure,
    id: '$label-direct-protocol-call',
    arguments: {'taskId': 'T-$label-direct-protocol'},
    protocolVersion: newerProtocolVersion,
  );
  if (!jsonEncode(toolCall).contains('T-$label-direct-protocol')) {
    throw StateError('$routeLabel direct protocol tools/call missed payload.');
  }

  final resources = await client.listResourcesDirect(
    id: '$label-direct-protocol-resources',
    protocolVersion: olderProtocolVersion,
  );
  if (!jsonEncode(resources.resources).contains(_resourceUri)) {
    throw StateError(
      '$routeLabel direct protocol resources/list missed route context.',
    );
  }

  final readResource = await client.readResourceDirect(
    _resourceUri,
    id: '$label-direct-protocol-resource-read',
    protocolVersion: newerProtocolVersion,
  );
  if (!jsonEncode(readResource).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError(
      '$routeLabel direct protocol resources/read missed route context.',
    );
  }

  final prompt = await client.getPromptDirect(
    _promptName,
    id: '$label-direct-protocol-prompt',
    arguments: {'taskId': 'T-$label-direct-protocol-prompt'},
    protocolVersion: olderProtocolVersion,
  );
  if (!jsonEncode(prompt).contains('T-$label-direct-protocol-prompt')) {
    throw StateError('$routeLabel direct protocol prompts/get missed payload.');
  }

  final api = await client.describeWampApiDirect(
    _procedure,
    id: '$label-direct-protocol-api',
    kind: 'procedure',
    protocolVersion: olderProtocolVersion,
  );
  if (!jsonEncode(api).contains(_procedure)) {
    throw StateError(
      '$routeLabel direct protocol WAMP API describe missed tool.',
    );
  }

  final publication = await client.publishWampEventDirect(
    _topic,
    id: '$label-direct-protocol-publish',
    argumentsKeywords: {'taskId': 'T-$label-direct-protocol-publish'},
    acknowledge: true,
    protocolVersion: newerProtocolVersion,
  );
  if (!publication.acknowledged) {
    throw StateError('$routeLabel direct protocol pub/sub publish failed.');
  }

  final streamablePing = await client.ping(
    id: '$label-streamable-protocol-ping',
    protocolVersion: olderProtocolVersion,
  );
  if (streamablePing.isNotEmpty) {
    throw StateError('$routeLabel Streamable protocol ping returned data.');
  }

  if (client.protocolVersion != previousProtocolVersion ||
      client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError(
      '$routeLabel typed protocol overrides changed client state.',
    );
  }
}

Future<void> _smokeJsonPostMcpRoute(
  RouterBinding binding,
  RouterSession serviceSession,
) async {
  await _smokeJsonPostResponseMcpEndpoint(
    _jsonPostMcpEndpoint(binding),
    serviceSession,
    label: 'json-post',
    routeName: 'JSON POST',
  );
}

Future<void> _smokeSecureJsonPostMcpRoute(
  RouterBinding binding,
  RouterSession serviceSession,
  ConnectanumHttpAuthGrant grant,
  ConnectanumHttpAuthGrant otherGrant,
) async {
  await _smokeJsonPostResponseMcpEndpoint(
    _secureJsonPostMcpEndpoint(binding),
    serviceSession,
    label: 'secure-json-post',
    routeName: 'secure JSON POST',
    authGrant: grant,
    otherAuthGrant: otherGrant,
  );
}

Future<void> _smokeNonStreamingPostMcpRoute(
  RouterBinding binding,
  RouterSession serviceSession,
) async {
  await _smokeJsonPostResponseMcpEndpoint(
    _nonStreamingPostMcpEndpoint(binding),
    serviceSession,
    label: 'non-streaming-post',
    routeName: 'non-streaming POST',
  );
}

Future<void> _smokeJsonPostResponseMcpEndpoint(
  Uri endpoint,
  RouterSession serviceSession, {
  required String label,
  required String routeName,
  ConnectanumHttpAuthGrant? authGrant,
  ConnectanumHttpAuthGrant? otherAuthGrant,
}) async {
  final grant = authGrant;
  final client = grant == null
      ? McpStreamableHttpClient(endpoint)
      : McpStreamableHttpClient.withAuthGrant(endpoint, grant);
  final rawClient = HttpClient();
  final bearerToken = grant?.accessToken;
  final clientName = label.replaceAll('-', '_');
  final routeLabel = '$routeName MCP route';

  Map<String, Object?> expectJsonPostResponse(
    _McpRawHttpResponse response, {
    required Object id,
    required String label,
  }) {
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('MCP $label returned ${response.statusCode}.');
    }
    _assertMcpCorsStatefulResponse(response, label: label);
    _assertHeaderContains(
      response,
      'content-type',
      'application/json',
      label: label,
    );
    if (response.body.contains('\ndata:') ||
        response.body.contains('\nevent:') ||
        response.body.startsWith('data:') ||
        response.body.startsWith('event:')) {
      throw StateError('MCP $label returned an SSE event body.');
    }
    final payload = _jsonObjectFrom(
      jsonDecode(response.body),
      label: '$label JSON response',
    );
    if (payload['jsonrpc'] != '2.0' || payload['id'] != id) {
      throw StateError('MCP $label returned invalid JSON-RPC.');
    }
    return payload;
  }

  void expectNoPostSseCursor(String operation) {
    if (client.lastEventId != null) {
      throw StateError(
        '$routeLabel captured an SSE cursor after $operation.',
      );
    }
  }

  try {
    await _assertMcpDirectJsonCorsResponse(
      rawClient,
      endpoint,
      serviceSession,
      label: '$label-json-response',
      bearerToken: bearerToken,
    );
    await _assertMcpDirectJsonBatchCorsResponse(
      rawClient,
      endpoint,
      serviceSession,
      label: '$label-json-response',
      bearerToken: bearerToken,
    );
    await _assertMcpDirectJsonNotificationCorsResponse(
      rawClient,
      endpoint,
      label: '$label-json-response',
      bearerToken: bearerToken,
    );
    await _assertMcpDirectJsonErrorCorsResponse(
      rawClient,
      endpoint,
      label: '$label-json-response',
      bearerToken: bearerToken,
    );

    final initializeId = '$label-streamable-initialize';
    final initialize = await client.initialize(
      id: initializeId,
      clientInfo: {
        'name': 'connectanum_consumer_${clientName}_smoke',
        'version': '0.1.0',
      },
      headers: <String, String>{
        'x-consumer-trace': '$label-streamable-initialize',
      },
    );
    if (initialize['id'] != initializeId) {
      throw StateError(
        '$routeLabel initialize returned unexpected id.',
      );
    }
    final sessionId = client.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('$routeLabel did not create a session.');
    }
    expectNoPostSseCursor('initialize');

    await client.notifyInitialized(
      headers: <String, String>{
        'x-consumer-trace': '$label-streamable-initialized',
      },
    );
    if (client.sessionId != sessionId) {
      throw StateError(
        '$routeLabel initialized notification changed session id.',
      );
    }
    expectNoPostSseCursor('initialized notification');

    await _expectPagedToolCatalog(
      client,
      label: label,
      directJson: false,
    );
    if (client.sessionId != sessionId) {
      throw StateError('$routeLabel tool catalog changed session id.');
    }
    expectNoPostSseCursor('tool catalog');

    final toolCallTaskId = 'T-$label-tool-call';
    final toolCall = await client.callTool(
      _procedure,
      id: '$label-tool-call',
      arguments: <String, Object?>{
        'taskId': toolCallTaskId,
      },
      headers: <String, String>{
        'x-consumer-trace': '$label-tool-call',
      },
    );
    if (!jsonEncode(toolCall).contains(toolCallTaskId)) {
      throw StateError('$routeLabel missed tool call payload.');
    }
    if (client.sessionId != sessionId) {
      throw StateError('$routeLabel tool call changed session id.');
    }
    expectNoPostSseCursor('tool call');

    await _smokeResourcesAndPrompts(client, label: label);
    if (client.sessionId != sessionId) {
      throw StateError('$routeLabel resources/prompts changed session id.');
    }
    expectNoPostSseCursor('resources/prompts');

    await _smokeDirectJsonWhileStreamableInitialized(
      client,
      serviceSession,
      label: '$label-json-response',
    );
    if (client.sessionId != sessionId) {
      throw StateError(
        '$routeLabel active direct JSON helpers changed session id.',
      );
    }
    expectNoPostSseCursor('active direct JSON helpers');

    final rawToolsId = '$label-raw-tools';
    final rawTools = await _mcpRawJsonPost(
      rawClient,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': rawToolsId,
        'method': 'tools/list',
      },
      sessionId: sessionId,
      bearerToken: bearerToken,
    );
    final rawToolsPayload = expectJsonPostResponse(
      rawTools,
      id: rawToolsId,
      label: '$routeName route raw tools/list',
    );
    final rawToolsResult = _jsonRpcResult(
      rawToolsPayload,
      id: rawToolsId,
      label: 'MCP $routeName route raw tools/list',
    );
    if (rawToolsResult['tools'] is! List) {
      throw StateError('$routeLabel raw tools/list missed catalog.');
    }

    final rawPingId = '$label-raw-ping';
    final rawPing = await _mcpRawJsonPost(
      rawClient,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': rawPingId,
        'method': 'ping',
      },
      sessionId: sessionId,
      bearerToken: bearerToken,
    );
    final rawPingResult = _jsonRpcResult(
      expectJsonPostResponse(
        rawPing,
        id: rawPingId,
        label: '$routeName route raw ping',
      ),
      id: rawPingId,
      label: 'MCP $routeName route raw ping',
    );
    if (rawPingResult.isNotEmpty) {
      throw StateError('$routeLabel raw ping returned data.');
    }

    await _assertMcpDirectJsonErrorCorsResponse(
      rawClient,
      endpoint,
      label: '$label-active-json-response',
      sessionId: sessionId,
      bearerToken: bearerToken,
    );
    if (client.sessionId != sessionId) {
      throw StateError(
        '$routeLabel active direct JSON errors changed session id.',
      );
    }
    expectNoPostSseCursor('active direct JSON errors');

    if (otherAuthGrant != null) {
      final sessionCursor = client.lastEventId;
      await _smokeJsonPostResponseMcpSessionIsolation(
        endpoint,
        serviceSession: serviceSession,
        sessionId: sessionId,
        lastEventId: sessionCursor,
        label: label,
        otherAuthGrant: otherAuthGrant,
      );
      if (client.sessionId != sessionId ||
          client.lastEventId != sessionCursor) {
        throw StateError(
          '$routeLabel auth/session isolation changed owner session state.',
        );
      }
      expectNoPostSseCursor('auth/session isolation');
    }

    await _smokeTypedProtocolVersionOverrides(
      client,
      label: label,
      routeLabel: routeLabel,
    );

    final subscription = await client.subscribeWampTopic(
      _topic,
      id: '$label-pubsub-subscribe',
      queueLimit: 4,
    );
    try {
      final taskId = 'T-$label-service-event';
      await serviceSession.publish(
        _topic,
        argumentsKeywords: {'taskId': taskId},
        options: PublishOptions(acknowledge: true),
      );
      final events = await _pollMcpEventsUntil(client, subscription.handle);
      if (!jsonEncode(events.events).contains(taskId)) {
        throw StateError('$routeLabel pub/sub poll missed event.');
      }
    } finally {
      await client.unsubscribeWampTopic(
        subscription.handle,
        id: '$label-pubsub-unsubscribe',
      );
    }
    if (client.sessionId != sessionId) {
      throw StateError('$routeLabel pub/sub changed session id.');
    }
    expectNoPostSseCursor('pub/sub');

    final dynamicProcedure = 'consumer.task.${label.replaceAll('-', '.')}';
    final registration = await serviceSession.register(
      dynamicProcedure,
      options: RegisterOptions(
        custom: {
          '_ai_meta_data': {
            'short_description': '$routeName consumer task',
            'description':
                'Procedure registered during $routeName MCP route smoke.',
            'read_only_hint': true,
            'destructive_hint': false,
            'idempotent_hint': true,
            'open_world_hint': false,
          },
        },
      ),
    );
    registration.onInvoke((invocation) {
      invocation.respondWith(
        argumentsKeywords: {
          'source': '$label-mcp-route-smoke',
        },
      );
    });

    final poll = await _mcpRawPollUntilToolListChanged(
      rawClient,
      endpoint,
      sessionId: sessionId,
      label: label,
      bearerToken: bearerToken,
    );
    final pollEventId = _mcpFirstSseEventId(
      poll,
      label: '$label Streamable GET/SSE poll',
    );
    if (pollEventId == null || pollEventId.isEmpty) {
      throw StateError('$routeLabel GET/SSE poll missed event id.');
    }
    if (client.sessionId != sessionId) {
      throw StateError('$routeLabel GET/SSE changed session id.');
    }
    expectNoPostSseCursor('GET/SSE poll');

    await client.deleteSession();
    if (client.sessionId != null || client.lastEventId != null) {
      throw StateError('$routeLabel leaked session state.');
    }
  } finally {
    rawClient.close(force: true);
    client.close();
  }
}

Future<void> _smokeJsonPostResponseMcpSessionIsolation(
  Uri endpoint, {
  required RouterSession serviceSession,
  required String sessionId,
  String? lastEventId,
  required String label,
  required ConnectanumHttpAuthGrant otherAuthGrant,
}) async {
  final otherPrincipalClient = McpStreamableHttpClient.withBearerToken(
    endpoint,
    otherAuthGrant.accessToken,
  );
  final bearerlessClient = McpStreamableHttpClient(endpoint);
  final unknownBearerClient = McpStreamableHttpClient.withBearerToken(
    endpoint,
    _unknownAccessToken,
  );

  try {
    await _assertStreamableSessionReuseRejectedAcrossMethods(
      otherPrincipalClient,
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label-other-principal',
    );
    await _assertJsonPostIndependentPrincipalSession(
      otherPrincipalClient,
      serviceSession: serviceSession,
      ownerSessionId: sessionId,
      label: '$label-other-principal',
    );

    await _assertStreamableSessionReuseRequiresBearerAcrossMethods(
      bearerlessClient,
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label-bearerless-reused-session',
    );

    unknownBearerClient.sessionId = sessionId;
    unknownBearerClient.lastEventId = lastEventId;
    await _assertActiveStreamableSessionRejectsBearer(
      unknownBearerClient,
      label: '$label-unknown-bearer',
      acceptedMessage:
          'JSON-response Streamable MCP session accepted an unknown access '
          'token.',
    );
  } finally {
    otherPrincipalClient.close();
    bearerlessClient.close();
    unknownBearerClient.close();
  }
}

Future<void> _assertJsonPostIndependentPrincipalSession(
  McpStreamableHttpClient client, {
  required RouterSession serviceSession,
  required String ownerSessionId,
  required String label,
}) async {
  await _expectPagedToolCatalog(
    client,
    label: '$label-independent-direct',
    directJson: true,
  );
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'JSON-response MCP $label direct tools/list changed session state.',
    );
  }
  await _smokeDirectToolApi(client, label: '$label-independent');
  await _smokeGenericDirectJsonRpcPubSub(
    client,
    serviceSession,
    label: '$label-independent',
  );
  await _smokeDirectWampMetaHelpers(
    client,
    serviceSession,
    label: '$label-independent',
  );
  await _smokeResourcesAndPrompts(
    client,
    label: '$label-independent',
    directJson: true,
  );
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'JSON-response MCP $label direct resource/prompt WAMP meta/pubsub '
      'changed session state.',
    );
  }

  await client.initialize(
    id: '$label-independent-initialize',
    clientInfo: const <String, Object?>{
      'name': 'connectanum_consumer_independent_principal_smoke',
      'version': '0.1.0',
    },
  );
  await client.notifyInitialized();
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('JSON-response MCP $label did not create a session.');
  }
  if (sessionId == ownerSessionId) {
    throw StateError(
      'JSON-response MCP $label reused another principal session id.',
    );
  }
  if (client.lastEventId != null) {
    throw StateError(
      'JSON-response MCP $label captured a POST/SSE cursor.',
    );
  }

  await _expectPagedToolCatalog(
    client,
    label: '$label-independent',
    directJson: false,
  );
  if (client.sessionId != sessionId || client.lastEventId != null) {
    throw StateError(
      'JSON-response MCP $label independent tools/list changed session state.',
    );
  }

  await _smokeResourcesAndPrompts(client, label: '$label-independent');
  if (client.sessionId != sessionId || client.lastEventId != null) {
    throw StateError(
      'JSON-response MCP $label independent resources/prompts changed '
      'session state.',
    );
  }

  final subscription = await client.subscribeWampTopic(
    _topic,
    id: '$label-independent-subscribe',
    queueLimit: 4,
  );
  try {
    final taskId = 'T-$label-independent-service-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': taskId},
      options: PublishOptions(acknowledge: true),
    );
    final events = await _pollMcpEventsUntil(client, subscription.handle);
    if (!jsonEncode(events.events).contains(taskId)) {
      throw StateError(
        'JSON-response MCP $label independent pub/sub missed service event.',
      );
    }
  } finally {
    await client.unsubscribeWampTopic(
      subscription.handle,
      id: '$label-independent-unsubscribe',
    );
  }
  if (client.sessionId != sessionId || client.lastEventId != null) {
    throw StateError(
      'JSON-response MCP $label independent pub/sub changed session state.',
    );
  }

  await client.deleteSession();
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'JSON-response MCP $label independent DELETE left session state.',
    );
  }
}

Future<void> _smokeMcpOriginPolicy(
  RouterBinding binding,
  ConnectanumHttpAuthGrant grant,
) async {
  final publicAllowedClient = McpStreamableHttpClient(
    _mcpEndpoint(binding),
    headers: const <String, String>{'Origin': _allowedOrigin},
  );
  final publicDisallowedClient = McpStreamableHttpClient(
    _mcpEndpoint(binding),
    headers: const <String, String>{'Origin': _disallowedOrigin},
  );
  final secureAllowedClient = McpStreamableHttpClient.withAuthGrant(
    _mcpEndpoint(binding, secure: true),
    grant,
    headers: const <String, String>{'Origin': _allowedOrigin},
  );
  final secureDisallowedClient = McpStreamableHttpClient.withAuthGrant(
    _mcpEndpoint(binding, secure: true),
    grant,
    headers: const <String, String>{'Origin': _disallowedOrigin},
  );
  try {
    await _smokeAllowedOriginMcpClient(
      publicAllowedClient,
      label: 'public-origin',
    );
    await _assertDisallowedOriginRejected(
      publicDisallowedClient,
      label: 'public-origin',
    );
    await _smokeAllowedOriginMcpClient(
      secureAllowedClient,
      label: 'secure-origin',
    );
    await _assertDisallowedOriginRejected(
      secureDisallowedClient,
      label: 'secure-origin',
    );
  } finally {
    publicAllowedClient.close();
    publicDisallowedClient.close();
    secureAllowedClient.close();
    secureDisallowedClient.close();
  }
}

Future<void> _smokeAllowedOriginMcpClient(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final directTools = await client.listToolsDirect(
    id: '$label-direct-tools',
  );
  if (directTools.tools.isEmpty) {
    throw StateError('MCP $label direct tool catalog was empty.');
  }
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'MCP $label direct Origin check created Streamable session state.',
    );
  }

  final initializeId = '$label-initialize';
  final initialize = await client.initialize(id: initializeId);
  if (initialize['id'] != initializeId) {
    throw StateError('MCP $label initialize returned unexpected id.');
  }
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('MCP $label initialize did not create a session.');
  }
  await client.notifyInitialized();
  final streamableTools = await client.listTools(id: '$label-streamable-tools');
  if (streamableTools.tools.isEmpty) {
    throw StateError('MCP $label Streamable tool catalog was empty.');
  }
  await client.deleteSession();
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError('MCP $label Origin smoke leaked session state.');
  }
}

Future<void> _assertDisallowedOriginRejected(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  try {
    await client.listToolsDirect(id: '$label-disallowed-direct');
    throw StateError('MCP accepted a disallowed $label Origin.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.forbidden) {
      throw StateError(
        'MCP disallowed $label Origin returned ${error.statusCode} '
        'instead of ${HttpStatus.forbidden}.',
      );
    }
    if (!error.body.contains('Origin')) {
      throw StateError(
        'MCP disallowed $label Origin error did not identify Origin policy.',
      );
    }
  }
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'MCP disallowed $label Origin created Streamable session state.',
    );
  }
}

Future<void> _smokeMcpCorsPreflight(
  RouterBinding binding,
  RouterSession serviceSession,
  ConnectanumHttpAuthGrant grant,
) async {
  final client = HttpClient();
  try {
    await _assertMcpCorsPreflightMethods(
      client,
      _mcpEndpoint(binding),
      label: 'public-cors',
    );
    await _assertMcpCorsPreflightMethods(
      client,
      _mcpEndpoint(binding, secure: true),
      label: 'secure-cors',
    );
    await _assertMcpCorsPreflight(
      client,
      _mcpEndpoint(binding),
      label: 'public-disallowed-cors',
      origin: _disallowedOrigin,
      expectedStatus: HttpStatus.forbidden,
    );
    await _assertMcpCorsPreflight(
      client,
      _mcpEndpoint(binding, secure: true),
      label: 'secure-disallowed-cors',
      origin: _disallowedOrigin,
      expectedStatus: HttpStatus.forbidden,
    );
    await _assertMcpCorsMethodNegotiationErrors(
      client,
      _mcpEndpoint(binding),
      label: 'public-cors',
    );
    await _assertMcpCorsPostBodyErrors(
      client,
      _mcpEndpoint(binding),
      label: 'public-cors',
    );
    await _assertSecureMcpCorsUnauthorized(
      client,
      _mcpEndpoint(binding, secure: true),
    );
    await _assertMcpCorsMethodNegotiationErrors(
      client,
      _mcpEndpoint(binding, secure: true),
      label: 'secure-cors',
      bearerToken: grant.accessToken,
    );
    await _assertMcpCorsPostBodyErrors(
      client,
      _mcpEndpoint(binding, secure: true),
      label: 'secure-cors',
      bearerToken: grant.accessToken,
    );
    await _assertMcpDirectJsonCorsResponse(
      client,
      _mcpEndpoint(binding),
      serviceSession,
      label: 'public-cors',
    );
    await _assertMcpDirectJsonBatchCorsResponse(
      client,
      _mcpEndpoint(binding),
      serviceSession,
      label: 'public-cors',
    );
    await _assertMcpDirectJsonNotificationCorsResponse(
      client,
      _mcpEndpoint(binding),
      label: 'public-cors',
    );
    await _assertMcpDirectJsonErrorCorsResponse(
      client,
      _mcpEndpoint(binding),
      label: 'public-cors',
    );
    await _assertMcpDirectJsonCorsResponse(
      client,
      _mcpEndpoint(binding, secure: true),
      serviceSession,
      label: 'secure-cors',
      bearerToken: grant.accessToken,
    );
    await _assertMcpDirectJsonBatchCorsResponse(
      client,
      _mcpEndpoint(binding, secure: true),
      serviceSession,
      label: 'secure-cors',
      bearerToken: grant.accessToken,
    );
    await _assertMcpDirectJsonNotificationCorsResponse(
      client,
      _mcpEndpoint(binding, secure: true),
      label: 'secure-cors',
      bearerToken: grant.accessToken,
    );
    await _assertMcpDirectJsonErrorCorsResponse(
      client,
      _mcpEndpoint(binding, secure: true),
      label: 'secure-cors',
      bearerToken: grant.accessToken,
    );
    await _assertMcpStreamableCorsLifecycle(
      client,
      _mcpEndpoint(binding),
      serviceSession,
      label: 'public-cors',
    );
    await _assertMcpStreamableCorsLifecycle(
      client,
      _mcpEndpoint(binding, secure: true),
      serviceSession,
      label: 'secure-cors',
      bearerToken: grant.accessToken,
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _smokeRateLimitedMcpRoute(RouterBinding binding) async {
  final client = HttpClient();
  final endpoint = _rateLimitedMcpEndpoint(binding);
  try {
    final toolsId = 'rate-limited-direct-tools';
    final tools = await _mcpRawDirectJsonRpc(
      client,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': toolsId,
        'method': 'tools/list',
      },
      label: 'rate-limited direct JSON first tools/list',
    );
    final toolList = _jsonRpcResult(
      tools,
      id: toolsId,
      label: 'MCP rate-limited direct JSON first tools/list',
    )['tools'];
    if (toolList is! List || toolList.isEmpty) {
      throw StateError('MCP rate-limited route missed the tool catalog.');
    }

    final initialize = await _mcpRawJsonPost(
      client,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'rate-limited-streamable-initialize',
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': McpStreamableHttpClient.latestProtocolVersion,
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{
            'name': 'connectanum_consumer_rate_limit_smoke',
            'version': '0.1.0',
          },
        },
      },
    );
    if (initialize.statusCode != HttpStatus.ok) {
      throw StateError(
        'MCP rate-limited Streamable initialize returned '
        '${initialize.statusCode}.',
      );
    }
    _assertMcpCorsStatefulResponse(
      initialize,
      label: 'rate-limited Streamable initialize',
    );
    final sessionId = initialize.header('mcp-session-id');
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError(
        'MCP rate-limited Streamable initialize did not return a session id.',
      );
    }

    final directLimited = await _mcpRawDirectJsonRpcResponse(
      client,
      endpoint,
      const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'rate-limited-direct-stale-session',
        'method': 'tools/list',
      },
      sessionId: 'caller-rate-limited-direct-stale-session',
    );
    _assertMcpCorsErrorResponse(
      directLimited,
      expectedStatus: 429,
      label: 'rate-limited direct JSON stale session',
      expectNoSession: true,
      bodyContains: 'rate_limited',
    );
    _assertHeaderContains(
      directLimited,
      'x-ratelimit-limit',
      '2',
      label: 'rate-limited direct JSON stale session',
    );

    final streamableLimited = await _mcpRawJsonPost(
      client,
      endpoint,
      const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'rate-limited-streamable-session',
        'method': 'tools/list',
        'params': <String, Object?>{},
      },
      sessionId: sessionId,
    );
    _assertMcpCorsErrorResponse(
      streamableLimited,
      expectedStatus: 429,
      label: 'rate-limited Streamable session',
      sessionId: sessionId,
      bodyContains: 'rate_limited',
    );
    _assertHeaderContains(
      streamableLimited,
      'x-ratelimit-limit',
      '2',
      label: 'rate-limited Streamable session',
    );

    final deleteSession = await _mcpRawSessionRequest(
      client,
      endpoint,
      'DELETE',
      sessionId: sessionId,
    );
    if (deleteSession.statusCode != HttpStatus.accepted) {
      throw StateError(
        'MCP rate-limited Streamable DELETE returned '
        '${deleteSession.statusCode} instead of ${HttpStatus.accepted}: '
        '${deleteSession.body}',
      );
    }
    _assertMcpCorsStatefulResponse(
      deleteSession,
      label: 'rate-limited Streamable DELETE',
    );
    if (deleteSession.header('mcp-session-id') != sessionId) {
      throw StateError(
        'MCP rate-limited Streamable DELETE returned the wrong session id.',
      );
    }
    if (deleteSession.header('x-ratelimit-limit') != null) {
      throw StateError(
        'MCP rate-limited Streamable DELETE was still rate limited.',
      );
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _assertMcpCorsPreflightMethods(
  HttpClient client,
  Uri endpoint, {
  required String label,
}) async {
  for (final method in const ['POST', 'GET', 'DELETE']) {
    await _assertMcpCorsPreflight(
      client,
      endpoint,
      label: '$label $method',
      requestedMethod: method,
    );
  }
}

Future<void> _assertMcpCorsPreflight(
  HttpClient client,
  Uri endpoint, {
  required String label,
  String requestedMethod = 'POST',
  String origin = _allowedOrigin,
  int expectedStatus = HttpStatus.noContent,
}) async {
  final request = await client.openUrl('OPTIONS', endpoint);
  request.headers.set('Origin', origin);
  request.headers.set('Access-Control-Request-Method', requestedMethod);
  request.headers.set(
    'Access-Control-Request-Headers',
    'Authorization, Content-Type, MCP-Protocol-Version, MCP-Session-Id, '
    'Last-Event-ID, Mcp-Method, Mcp-Name, Mcp-Param-TaskId, '
    'Mcp-Param-Note, Mcp-Param-Message',
  );
  final response = await _mcpRawResponseFrom(await request.close());
  if (response.statusCode != expectedStatus) {
    throw StateError(
      'MCP $label preflight returned ${response.statusCode} instead of '
      '$expectedStatus.',
    );
  }
  if (expectedStatus == HttpStatus.noContent) {
    _assertCorsAllowed(response, origin, label: '$label preflight');
    _assertHeaderContains(
      response,
      'access-control-allow-methods',
      'OPTIONS',
      label: '$label preflight allow methods',
    );
    _assertHeaderContains(
      response,
      'access-control-allow-methods',
      'POST',
      label: '$label preflight allow methods',
    );
    _assertHeaderContains(
      response,
      'access-control-allow-methods',
      'GET',
      label: '$label preflight allow methods',
    );
    _assertHeaderContains(
      response,
      'access-control-allow-methods',
      'DELETE',
      label: '$label preflight allow methods',
    );
    for (final header in const [
      'authorization',
      'content-type',
      'mcp-protocol-version',
      'mcp-session-id',
      'last-event-id',
      'mcp-method',
      'mcp-name',
      'mcp-param-taskid',
      'mcp-param-note',
      'mcp-param-message',
    ]) {
      _assertHeaderContains(
        response,
        'access-control-allow-headers',
        header,
        label: '$label preflight allow headers',
      );
    }
    if (response.header('mcp-session-id') != null) {
      throw StateError('MCP $label preflight created session state.');
    }
  } else {
    if (response.header('access-control-allow-origin') != null) {
      throw StateError('MCP $label preflight exposed disallowed Origin.');
    }
    if (!response.body.contains('Origin')) {
      throw StateError('MCP $label preflight error did not identify Origin.');
    }
  }
}

Future<void> _assertMcpCorsMethodNegotiationErrors(
  HttpClient client,
  Uri endpoint, {
  required String label,
  String? bearerToken,
}) async {
  final unsupported = await _mcpRawMcpRequest(
    client,
    endpoint,
    'PUT',
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    unsupported,
    expectedStatus: HttpStatus.methodNotAllowed,
    label: '$label unsupported PUT',
    expectNoSession: true,
    bodyContains: 'GET, POST, DELETE',
  );
  for (final method in const ['GET', 'POST', 'DELETE', 'OPTIONS']) {
    _assertHeaderContains(
      unsupported,
      HttpHeaders.allowHeader,
      method,
      label: '$label unsupported PUT allow header',
    );
  }

  final getInvalidAccept = await _mcpRawMcpRequest(
    client,
    endpoint,
    'GET',
    accept: 'application/json',
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    getInvalidAccept,
    expectedStatus: HttpStatus.notAcceptable,
    label: '$label GET invalid Accept',
    expectNoSession: true,
    bodyContains: 'Accept',
  );

  final postInvalidAccept = await _mcpRawMcpRequest(
    client,
    endpoint,
    'POST',
    accept: 'text/plain',
    bearerToken: bearerToken,
    jsonBody: const <String, Object?>{
      'jsonrpc': '2.0',
      'id': 'cors-post-invalid-accept',
      'method': 'tools/list',
    },
  );
  _assertMcpCorsErrorResponse(
    postInvalidAccept,
    expectedStatus: HttpStatus.notAcceptable,
    label: '$label POST invalid Accept',
    expectNoSession: true,
    bodyContains: 'Accept',
  );
}

Future<void> _assertMcpCorsPostBodyErrors(
  HttpClient client,
  Uri endpoint, {
  required String label,
  String? bearerToken,
}) async {
  final unsupported = await _mcpRawPostBody(
    client,
    endpoint,
    body: jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': '$label-unsupported-content-type',
      'method': 'connectanum.tools.list',
    }),
    contentType: 'text/plain',
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    unsupported,
    expectedStatus: HttpStatus.unsupportedMediaType,
    label: '$label POST unsupported Content-Type',
    expectNoSession: true,
    bodyContains: 'JSON content type',
  );

  final malformed = await _mcpRawPostBody(
    client,
    endpoint,
    body: '{"jsonrpc":"2.0","id":"$label-malformed-json",',
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    malformed,
    expectedStatus: HttpStatus.badRequest,
    label: '$label POST malformed JSON',
    expectNoSession: true,
    bodyContains: 'Invalid JSON-RPC message',
  );

  final directMalformedStaleSession = await _mcpRawPostBody(
    client,
    endpoint,
    body: '{"jsonrpc":"2.0","id":"$label-direct-malformed-stale-session",',
    accept: 'application/json',
    sessionId: 'caller-direct-stale-session',
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    directMalformedStaleSession,
    expectedStatus: HttpStatus.badRequest,
    label: '$label direct JSON malformed stale session',
    expectNoSession: true,
    bodyContains: 'Invalid JSON-RPC message',
  );
}

Future<void> _assertSecureMcpCorsUnauthorized(
  HttpClient client,
  Uri endpoint,
) async {
  final direct = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    const <String, Object?>{
      'jsonrpc': '2.0',
      'id': 'secure-cors-missing-bearer-direct-tools',
      'method': 'connectanum.tools.list',
    },
  );
  _assertMcpCorsErrorResponse(
    direct,
    expectedStatus: HttpStatus.unauthorized,
    label: 'secure-cors direct JSON missing bearer',
    expectNoSession: true,
    bodyContains: 'Bearer token required',
  );
  _assertHeaderContains(
    direct,
    'www-authenticate',
    'Bearer',
    label: 'secure-cors direct JSON missing bearer',
  );

  final directStaleMissingBearer = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    const <String, Object?>{
      'jsonrpc': '2.0',
      'id': 'secure-cors-missing-bearer-direct-stale-session',
      'method': 'connectanum.tools.list',
    },
    sessionId: 'caller-secure-direct-stale-session',
  );
  _assertMcpCorsErrorResponse(
    directStaleMissingBearer,
    expectedStatus: HttpStatus.unauthorized,
    label: 'secure-cors direct JSON missing bearer stale session',
    expectNoSession: true,
    bodyContains: 'Bearer token required',
  );
  _assertHeaderContains(
    directStaleMissingBearer,
    'www-authenticate',
    'Bearer',
    label: 'secure-cors direct JSON missing bearer stale session',
  );

  final directStaleInvalidBearer = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    const <String, Object?>{
      'jsonrpc': '2.0',
      'id': 'secure-cors-invalid-bearer-direct-stale-session',
      'method': 'connectanum.tools.list',
    },
    sessionId: 'caller-secure-direct-stale-session',
    bearerToken: 'invalid-secure-direct-stale-session-token',
  );
  _assertMcpCorsErrorResponse(
    directStaleInvalidBearer,
    expectedStatus: HttpStatus.unauthorized,
    label: 'secure-cors direct JSON invalid bearer stale session',
    expectNoSession: true,
    bodyContains: 'Bearer token',
  );
  _assertHeaderContains(
    directStaleInvalidBearer,
    'www-authenticate',
    'Bearer',
    label: 'secure-cors direct JSON invalid bearer stale session',
  );

  final initialize = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 'secure-cors-missing-bearer-initialize',
      'method': 'initialize',
      'params': <String, Object?>{
        'protocolVersion': McpStreamableHttpClient.latestProtocolVersion,
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{
          'name': 'connectanum_consumer_cors_smoke',
          'version': '0.1.0',
        },
      },
    },
  );
  _assertMcpCorsErrorResponse(
    initialize,
    expectedStatus: HttpStatus.unauthorized,
    label: 'secure-cors Streamable initialize missing bearer',
    expectNoSession: true,
    bodyContains: 'Bearer token required',
  );
  _assertHeaderContains(
    initialize,
    'www-authenticate',
    'Bearer',
    label: 'secure-cors Streamable initialize missing bearer',
  );
}

Future<void> _assertMcpDirectJsonCorsResponse(
  HttpClient client,
  Uri endpoint,
  RouterSession serviceSession, {
  required String label,
  String? bearerToken,
}) async {
  final toolsId = '$label-direct-cors-tools';
  final toolsResponse = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': toolsId,
      'method': 'connectanum.tools.list',
    },
    label: '$label direct JSON tools/list',
    bearerToken: bearerToken,
  );
  if (toolsResponse['jsonrpc'] != '2.0' || toolsResponse['id'] != toolsId) {
    throw StateError(
      'MCP $label direct JSON CORS tools/list returned invalid JSON-RPC.',
    );
  }
  final result = toolsResponse['result'];
  final toolEntries = result is Map<String, Object?> ? result['tools'] : null;
  if (toolEntries is! List || toolEntries.isEmpty) {
    throw StateError('MCP $label direct JSON CORS missed tool catalog.');
  }

  final pingId = '$label-direct-cors-ping';
  final ping = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': pingId,
      'method': 'ping',
    },
    label: '$label direct JSON ping',
    bearerToken: bearerToken,
  );
  final pingResult = _jsonRpcResult(
    ping,
    id: pingId,
    label: 'MCP $label direct JSON CORS ping',
  );
  if (pingResult.isNotEmpty) {
    throw StateError('MCP $label direct JSON CORS ping returned data.');
  }

  final toolCallTaskId = 'T-$label-direct-cors-tool-call';
  final toolCallId = '$label-direct-cors-tool-call';
  final toolCall = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': toolCallId,
      'method': 'connectanum.tool.call',
      'params': {
        'name': _procedure,
        'arguments': {
          'taskId': toolCallTaskId,
          'note': _headerWrappedNote,
        },
      },
    },
    label: '$label direct JSON connectanum.tool.call',
    bearerToken: bearerToken,
  );
  final toolCallJson = jsonEncode(toolCall);
  if (toolCall['id'] != toolCallId ||
      !toolCallJson.contains(toolCallTaskId) ||
      !toolCallJson.contains(_headerWrappedNote)) {
    throw StateError(
      'MCP $label direct JSON CORS tool call missed procedure result.',
    );
  }

  final toolCallAliasTaskId = 'T-$label-direct-cors-tools-call-alias';
  final toolCallAliasId = '$label-direct-cors-tools-call-alias';
  final toolCallAlias = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': toolCallAliasId,
      'method': 'connectanum.tools.call',
      'params': {
        'name': _procedure,
        'arguments': {
          'taskId': toolCallAliasTaskId,
          'note': _headerWrappedNote,
        },
      },
    },
    label: '$label direct JSON connectanum.tools.call alias',
    bearerToken: bearerToken,
  );
  final toolCallAliasJson = jsonEncode(toolCallAlias);
  if (toolCallAlias['id'] != toolCallAliasId ||
      !toolCallAliasJson.contains(toolCallAliasTaskId) ||
      !toolCallAliasJson.contains(_headerWrappedNote)) {
    throw StateError(
      'MCP $label direct JSON CORS tools.call alias missed procedure result.',
    );
  }

  final apiListId = '$label-direct-cors-api-list';
  final apiList = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': apiListId,
      'method': 'connectanum.api.list',
    },
    label: '$label direct JSON connectanum.api.list',
    bearerToken: bearerToken,
  );
  final apiCatalog = _jsonRpcStructuredContent(
    apiList,
    id: apiListId,
    label: 'MCP $label direct JSON CORS API list',
  );
  final apiCatalogJson = jsonEncode(apiCatalog);
  if (!apiCatalogJson.contains(_procedure) ||
      !apiCatalogJson.contains(_topic)) {
    throw StateError(
      'MCP $label direct JSON CORS API list missed router metadata.',
    );
  }

  final apiDescribeId = '$label-direct-cors-api-describe';
  final apiDescribe = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': apiDescribeId,
      'method': 'connectanum.api.describe',
      'params': {'uri': _procedure, 'kind': 'procedure'},
    },
    label: '$label direct JSON connectanum.api.describe procedure',
    bearerToken: bearerToken,
  );
  final apiDescription = _jsonRpcStructuredContent(
    apiDescribe,
    id: apiDescribeId,
    label: 'MCP $label direct JSON CORS API describe',
  );
  if (!jsonEncode(apiDescription).contains(_procedure)) {
    throw StateError(
      'MCP $label direct JSON CORS API describe missed $_procedure.',
    );
  }

  final topicDescribeId = '$label-direct-cors-topic-describe';
  final topicDescribe = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': topicDescribeId,
      'method': 'connectanum.api.describe',
      'params': {'uri': _topic, 'kind': 'topic'},
    },
    label: '$label direct JSON connectanum.api.describe topic',
    bearerToken: bearerToken,
  );
  final topicDescription = _jsonRpcStructuredContent(
    topicDescribe,
    id: topicDescribeId,
    label: 'MCP $label direct JSON CORS topic describe',
  );
  final topicDescriptionJson = jsonEncode(topicDescription);
  if (!topicDescriptionJson.contains(_topic) ||
      !topicDescriptionJson.contains('eventSchema') ||
      !topicDescriptionJson.contains('allowPublish') ||
      !topicDescriptionJson.contains('allowSubscribe')) {
    throw StateError(
      'MCP $label direct JSON CORS topic describe missed $_topic metadata.',
    );
  }

  final resourcesId = '$label-direct-cors-resources';
  final resources = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': resourcesId,
      'method': 'resources/list',
    },
    label: '$label direct JSON resources/list',
    bearerToken: bearerToken,
  );
  final resourceResult = _jsonRpcResult(
    resources,
    id: resourcesId,
    label: 'MCP $label direct JSON CORS resources/list',
  );
  if (!jsonEncode(resourceResult['resources']).contains(_resourceUri)) {
    throw StateError(
      'MCP $label direct JSON CORS resources/list missed $_resourceUri.',
    );
  }

  final resourceReadId = '$label-direct-cors-resource-read';
  final resourceRead = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': resourceReadId,
      'method': 'resources/read',
      'params': {'uri': _resourceUri},
    },
    label: '$label direct JSON resources/read',
    bearerToken: bearerToken,
  );
  final resourceReadResult = _jsonRpcResult(
    resourceRead,
    id: resourceReadId,
    label: 'MCP $label direct JSON CORS resources/read',
  );
  if (!jsonEncode(resourceReadResult['contents']).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError(
      'MCP $label direct JSON CORS resources/read missed route context.',
    );
  }

  final templatesId = '$label-direct-cors-resource-templates';
  final templates = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': templatesId,
      'method': 'resources/templates/list',
    },
    label: '$label direct JSON resources/templates/list',
    bearerToken: bearerToken,
  );
  final templateResult = _jsonRpcResult(
    templates,
    id: templatesId,
    label: 'MCP $label direct JSON CORS resources/templates/list',
  );
  if (!jsonEncode(
    templateResult['resourceTemplates'],
  ).contains(_resourceTemplateUri)) {
    throw StateError(
      'MCP $label direct JSON CORS resources/templates/list missed '
      '$_resourceTemplateUri.',
    );
  }

  final promptsId = '$label-direct-cors-prompts';
  final prompts = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': promptsId,
      'method': 'prompts/list',
    },
    label: '$label direct JSON prompts/list',
    bearerToken: bearerToken,
  );
  final promptResult = _jsonRpcResult(
    prompts,
    id: promptsId,
    label: 'MCP $label direct JSON CORS prompts/list',
  );
  if (!jsonEncode(promptResult['prompts']).contains(_promptName)) {
    throw StateError(
      'MCP $label direct JSON CORS prompts/list missed $_promptName.',
    );
  }

  final promptTaskId = 'T-$label-direct-cors-prompt';
  final promptId = '$label-direct-cors-prompt';
  final prompt = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': promptId,
      'method': 'prompts/get',
      'params': {
        'name': _promptName,
        'arguments': {'taskId': promptTaskId},
      },
    },
    label: '$label direct JSON prompts/get',
    bearerToken: bearerToken,
  );
  if (prompt['id'] != promptId || !jsonEncode(prompt).contains(promptTaskId)) {
    throw StateError(
      'MCP $label direct JSON CORS prompts/get did not substitute task id.',
    );
  }

  final subscribeId = '$label-direct-cors-pubsub-subscribe';
  final subscribe = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': subscribeId,
      'method': 'connectanum.pubsub.subscribe',
      'params': {'topic': _topic, 'queueLimit': 4},
    },
    label: '$label direct JSON connectanum.pubsub.subscribe',
    bearerToken: bearerToken,
  );
  final subscription = _jsonRpcStructuredContent(
    subscribe,
    id: subscribeId,
    label: 'MCP $label direct JSON CORS pub/sub subscribe',
  );
  final handle = subscription['handle'];
  if (handle is! String ||
      handle.isEmpty ||
      subscription['topic'] != _topic ||
      subscription['queueLimit'] != 4) {
    throw StateError(
      'MCP $label direct JSON CORS pub/sub subscribe returned invalid '
      'content.',
    );
  }

  try {
    final publishId = '$label-direct-cors-pubsub-publish';
    final publish = await _mcpRawDirectJsonRpc(
      client,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': publishId,
        'method': 'connectanum.pubsub.publish',
        'params': {
          'topic': _topic,
          'argumentsKeywords': {
            'taskId': 'T-$label-direct-cors-pubsub-publish',
          },
          'acknowledge': true,
        },
      },
      label: '$label direct JSON connectanum.pubsub.publish',
      bearerToken: bearerToken,
    );
    final publication = _jsonRpcStructuredContent(
      publish,
      id: publishId,
      label: 'MCP $label direct JSON CORS pub/sub publish',
    );
    if (publication['topic'] != _topic ||
        publication['acknowledged'] != true) {
      throw StateError(
        'MCP $label direct JSON CORS pub/sub publish returned invalid '
        'content.',
      );
    }

    final serviceTaskId = 'T-$label-direct-cors-pubsub-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );
    await _mcpRawDirectJsonPubSubPollUntil(
      client,
      endpoint,
      handle,
      label: label,
      expectedTaskId: serviceTaskId,
      bearerToken: bearerToken,
    );
  } finally {
    final unsubscribeId = '$label-direct-cors-pubsub-unsubscribe';
    final unsubscribe = await _mcpRawDirectJsonRpc(
      client,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': unsubscribeId,
        'method': 'connectanum.pubsub.unsubscribe',
        'params': {'handle': handle},
      },
      label: '$label direct JSON connectanum.pubsub.unsubscribe',
      bearerToken: bearerToken,
    );
    final unsubscribeContent = _jsonRpcStructuredContent(
      unsubscribe,
      id: unsubscribeId,
      label: 'MCP $label direct JSON CORS pub/sub unsubscribe',
    );
    if (unsubscribeContent['handle'] != handle ||
        unsubscribeContent['topic'] != _topic ||
        unsubscribeContent['unsubscribed'] != true) {
      throw StateError(
        'MCP $label direct JSON CORS pub/sub unsubscribe returned invalid '
        'content.',
      );
    }
  }
}

Future<void> _assertMcpDirectJsonBatchCorsResponse(
  HttpClient client,
  Uri endpoint,
  RouterSession serviceSession, {
  required String label,
  String? bearerToken,
}) async {
  final catalogBatch = await _mcpRawDirectJsonRpcBatch(
    client,
    endpoint,
    <Map<String, Object?>>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-api-list',
        'method': 'connectanum.api.list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-tools',
        'method': 'connectanum.tools.list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-ping',
        'method': 'ping',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-resources',
        'method': 'resources/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-prompts',
        'method': 'prompts/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      },
    ],
    label: '$label direct JSON batch catalog',
    bearerToken: bearerToken,
  );
  if (catalogBatch.length != 5) {
    throw StateError(
      'MCP $label direct JSON CORS catalog batch returned '
      '${catalogBatch.length} responses.',
    );
  }
  if (!jsonEncode(
    _jsonRpcStructuredContent(
      catalogBatch[0],
      id: '$label-direct-cors-batch-api-list',
      label: 'MCP $label direct JSON CORS batch API list',
    ),
  ).contains(_procedure)) {
    throw StateError(
      'MCP $label direct JSON CORS batch API list missed $_procedure.',
    );
  }
  final batchTools = _jsonRpcResult(
    catalogBatch[1],
    id: '$label-direct-cors-batch-tools',
    label: 'MCP $label direct JSON CORS batch tools/list',
  )['tools'];
  if (batchTools is! List || batchTools.isEmpty) {
    throw StateError(
      'MCP $label direct JSON CORS batch tools/list missed direct catalog.',
    );
  }
  final batchPing = _jsonRpcResult(
    catalogBatch[2],
    id: '$label-direct-cors-batch-ping',
    label: 'MCP $label direct JSON CORS batch ping',
  );
  if (batchPing.isNotEmpty) {
    throw StateError('MCP $label direct JSON CORS batch ping returned data.');
  }
  if (!jsonEncode(
    _jsonRpcResult(
      catalogBatch[3],
      id: '$label-direct-cors-batch-resources',
      label: 'MCP $label direct JSON CORS batch resources/list',
    )['resources'],
  ).contains(_resourceUri)) {
    throw StateError(
      'MCP $label direct JSON CORS batch resources/list missed '
      '$_resourceUri.',
    );
  }
  if (!jsonEncode(
    _jsonRpcResult(
      catalogBatch[4],
      id: '$label-direct-cors-batch-prompts',
      label: 'MCP $label direct JSON CORS batch prompts/list',
    )['prompts'],
  ).contains(_promptName)) {
    throw StateError(
      'MCP $label direct JSON CORS batch prompts/list missed $_promptName.',
    );
  }

  final promptTaskId = 'T-$label-direct-cors-batch-prompt';
  final detailBatch = await _mcpRawDirectJsonRpcBatch(
    client,
    endpoint,
    <Map<String, Object?>>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-api-describe',
        'method': 'connectanum.api.describe',
        'params': {'uri': _procedure, 'kind': 'procedure'},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-topic-describe',
        'method': 'connectanum.api.describe',
        'params': {'uri': _topic, 'kind': 'topic'},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-resource-read',
        'method': 'resources/read',
        'params': {'uri': _resourceUri},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-resource-templates',
        'method': 'resources/templates/list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-prompt-get',
        'method': 'prompts/get',
        'params': {
          'name': _promptName,
          'arguments': {'taskId': promptTaskId},
        },
      },
    ],
    label: '$label direct JSON batch resource/prompt details',
    bearerToken: bearerToken,
  );
  if (detailBatch.length != 5) {
    throw StateError(
      'MCP $label direct JSON CORS detail batch returned '
      '${detailBatch.length} responses.',
    );
  }
  if (!jsonEncode(
    _jsonRpcStructuredContent(
      detailBatch[0],
      id: '$label-direct-cors-batch-api-describe',
      label: 'MCP $label direct JSON CORS batch API describe',
    ),
  ).contains(_procedure)) {
    throw StateError(
      'MCP $label direct JSON CORS batch API describe missed $_procedure.',
    );
  }
  final topicDescriptionJson = jsonEncode(
    _jsonRpcStructuredContent(
      detailBatch[1],
      id: '$label-direct-cors-batch-topic-describe',
      label: 'MCP $label direct JSON CORS batch topic describe',
    ),
  );
  if (!topicDescriptionJson.contains(_topic) ||
      !topicDescriptionJson.contains('eventSchema')) {
    throw StateError(
      'MCP $label direct JSON CORS batch topic describe missed $_topic.',
    );
  }
  if (!jsonEncode(
    _jsonRpcResult(
      detailBatch[2],
      id: '$label-direct-cors-batch-resource-read',
      label: 'MCP $label direct JSON CORS batch resources/read',
    )['contents'],
  ).contains('Consumer package router-hosted MCP context document.')) {
    throw StateError(
      'MCP $label direct JSON CORS batch resources/read missed route context.',
    );
  }
  if (!jsonEncode(
    _jsonRpcResult(
      detailBatch[3],
      id: '$label-direct-cors-batch-resource-templates',
      label: 'MCP $label direct JSON CORS batch resources/templates/list',
    )['resourceTemplates'],
  ).contains(_resourceTemplateUri)) {
    throw StateError(
      'MCP $label direct JSON CORS batch resources/templates/list missed '
      '$_resourceTemplateUri.',
    );
  }
  if (!jsonEncode(detailBatch[4]).contains(promptTaskId)) {
    throw StateError(
      'MCP $label direct JSON CORS batch prompts/get did not substitute '
      'task id.',
    );
  }

  final toolCallTaskId = 'T-$label-direct-cors-batch-tool-call';
  final toolCallAliasTaskId = 'T-$label-direct-cors-batch-tools-call-alias';
  final toolCallBatch = await _mcpRawDirectJsonRpcBatch(
    client,
    endpoint,
    <Map<String, Object?>>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-tool-call',
        'method': 'connectanum.tool.call',
        'params': {
          'name': _procedure,
          'arguments': {'taskId': toolCallTaskId},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-tools-call-alias',
        'method': 'connectanum.tools.call',
        'params': {
          'name': _procedure,
          'arguments': {'taskId': toolCallAliasTaskId},
        },
      },
    ],
    label: '$label direct JSON batch tool call aliases',
    bearerToken: bearerToken,
  );
  if (toolCallBatch.length != 2) {
    throw StateError(
      'MCP $label direct JSON CORS tool-call alias batch returned '
      '${toolCallBatch.length} responses.',
    );
  }
  if (!jsonEncode(toolCallBatch[0]).contains(toolCallTaskId)) {
    throw StateError(
      'MCP $label direct JSON CORS batch tool.call missed procedure result.',
    );
  }
  if (!jsonEncode(toolCallBatch[1]).contains(toolCallAliasTaskId)) {
    throw StateError(
      'MCP $label direct JSON CORS batch tools.call alias missed procedure '
      'result.',
    );
  }

  final subscribeBatch = await _mcpRawDirectJsonRpcBatch(
    client,
    endpoint,
    <Map<String, Object?>>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-pubsub-subscribe',
        'method': 'connectanum.pubsub.subscribe',
        'params': {'topic': _topic, 'queueLimit': 3},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-batch-pubsub-tools',
        'method': 'connectanum.tools.list',
      },
    ],
    label: '$label direct JSON batch pub/sub subscribe',
    bearerToken: bearerToken,
  );
  if (subscribeBatch.length != 2) {
    throw StateError(
      'MCP $label direct JSON CORS pub/sub subscribe batch returned '
      '${subscribeBatch.length} responses.',
    );
  }
  final subscription = _jsonRpcStructuredContent(
    subscribeBatch[0],
    id: '$label-direct-cors-batch-pubsub-subscribe',
    label: 'MCP $label direct JSON CORS batch pub/sub subscribe',
  );
  final handle = subscription['handle'];
  if (handle is! String ||
      handle.isEmpty ||
      subscription['topic'] != _topic ||
      subscription['queueLimit'] != 3) {
    throw StateError(
      'MCP $label direct JSON CORS batch pub/sub subscribe returned invalid '
      'content.',
    );
  }
  final subscribeBatchTools = _jsonRpcResult(
    subscribeBatch[1],
    id: '$label-direct-cors-batch-pubsub-tools',
    label: 'MCP $label direct JSON CORS batch pub/sub tools/list',
  )['tools'];
  if (subscribeBatchTools is! List || subscribeBatchTools.isEmpty) {
    throw StateError(
      'MCP $label direct JSON CORS batch tools/list missed direct catalog.',
    );
  }

  try {
    final serviceTaskId = 'T-$label-direct-cors-batch-service-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );
    final publishBatch = await _mcpRawDirectJsonRpcBatch(
      client,
      endpoint,
      <Map<String, Object?>>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': '$label-direct-cors-batch-pubsub-publish',
          'method': 'connectanum.pubsub.publish',
          'params': {
            'topic': _topic,
            'argumentsKeywords': {
              'taskId': 'T-$label-direct-cors-batch-publish',
            },
            'acknowledge': true,
          },
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': '$label-direct-cors-batch-pubsub-poll',
          'method': 'connectanum.pubsub.poll',
          'params': {'handle': handle, 'limit': 4},
        },
      ],
      label: '$label direct JSON batch pub/sub publish/poll',
      bearerToken: bearerToken,
    );
    if (publishBatch.length != 2) {
      throw StateError(
        'MCP $label direct JSON CORS pub/sub publish batch returned '
        '${publishBatch.length} responses.',
      );
    }
    final publication = _jsonRpcStructuredContent(
      publishBatch[0],
      id: '$label-direct-cors-batch-pubsub-publish',
      label: 'MCP $label direct JSON CORS batch pub/sub publish',
    );
    if (publication['topic'] != _topic ||
        publication['acknowledged'] != true) {
      throw StateError(
        'MCP $label direct JSON CORS batch pub/sub publish returned invalid '
        'content.',
      );
    }
    final eventBatch = _jsonRpcStructuredContent(
      publishBatch[1],
      id: '$label-direct-cors-batch-pubsub-poll',
      label: 'MCP $label direct JSON CORS batch pub/sub poll',
    );
    if (eventBatch['handle'] != handle ||
        !jsonEncode(eventBatch['events']).contains(serviceTaskId)) {
      throw StateError(
        'MCP $label direct JSON CORS batch pub/sub poll missed routed event.',
      );
    }
  } finally {
    final unsubscribeBatch = await _mcpRawDirectJsonRpcBatch(
      client,
      endpoint,
      <Map<String, Object?>>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': '$label-direct-cors-batch-pubsub-unsubscribe',
          'method': 'connectanum.pubsub.unsubscribe',
          'params': {'handle': handle},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': '$label-direct-cors-batch-pubsub-api-list',
          'method': 'connectanum.api.list',
        },
      ],
      label: '$label direct JSON batch pub/sub unsubscribe',
      bearerToken: bearerToken,
    );
    if (unsubscribeBatch.length != 2) {
      throw StateError(
        'MCP $label direct JSON CORS pub/sub unsubscribe batch returned '
        '${unsubscribeBatch.length} responses.',
      );
    }
    final unsubscribe = _jsonRpcStructuredContent(
      unsubscribeBatch[0],
      id: '$label-direct-cors-batch-pubsub-unsubscribe',
      label: 'MCP $label direct JSON CORS batch pub/sub unsubscribe',
    );
    if (unsubscribe['handle'] != handle ||
        unsubscribe['topic'] != _topic ||
        unsubscribe['unsubscribed'] != true) {
      throw StateError(
        'MCP $label direct JSON CORS batch pub/sub unsubscribe returned '
        'invalid content.',
      );
    }
    if (!jsonEncode(
      _jsonRpcStructuredContent(
        unsubscribeBatch[1],
        id: '$label-direct-cors-batch-pubsub-api-list',
        label: 'MCP $label direct JSON CORS batch pub/sub API list',
      ),
    ).contains(_topic)) {
      throw StateError(
        'MCP $label direct JSON CORS batch post-unsubscribe API list missed '
        '$_topic.',
      );
    }
  }
}

Future<void> _assertMcpDirectJsonNotificationCorsResponse(
  HttpClient client,
  Uri endpoint, {
  required String label,
  String? bearerToken,
}) async {
  final single = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    const <String, Object?>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
      'params': <String, Object?>{},
    },
    bearerToken: bearerToken,
  );
  _assertMcpDirectJsonNotificationAccepted(
    single,
    label: '$label direct JSON notification',
  );

  final batch = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    const <Map<String, Object?>>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': <String, Object?>{},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/tools/list_changed',
        'params': <String, Object?>{},
      },
    ],
    bearerToken: bearerToken,
  );
  _assertMcpDirectJsonNotificationAccepted(
    batch,
    label: '$label direct JSON notification-only batch',
  );

  final toolNotificationTaskId = 'T-$label-direct-cors-tool-notification';
  final invalidToolNotificationTaskId =
      'T-$label-direct-cors-invalid-tool-notification';
  final toolBatch = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    <Map<String, Object?>>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'connectanum.tool.call',
        'params': <String, Object?>{
          'name': _procedure,
          'arguments': <String, Object?>{
            'taskId': toolNotificationTaskId,
          },
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'connectanum.tool.call',
        'params': <String, Object?>{
          'arguments': <String, Object?>{
            'taskId': invalidToolNotificationTaskId,
            'message': '$label invalid direct JSON tool notification',
          },
        },
      },
    ],
    bearerToken: bearerToken,
  );
  _assertMcpDirectJsonNotificationAccepted(
    toolBatch,
    label: '$label direct JSON tool notification-only batch',
  );
  await _expectConsumerProcedureInvocation(
    toolNotificationTaskId,
    label: '$label direct JSON tool notification-only batch',
  );
  await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': '$label-direct-cors-tool-notification-drain',
      'method': 'ping',
    },
    label: '$label direct JSON tool notification drain',
    bearerToken: bearerToken,
  );
  _expectNoConsumerProcedureInvocation(
    invalidToolNotificationTaskId,
    label: '$label invalid direct JSON tool notification-only batch',
  );

  final pubSubSubscribeId =
      '$label-direct-cors-pubsub-notification-subscribe';
  final pubSubSubscribe = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': pubSubSubscribeId,
      'method': 'connectanum.pubsub.subscribe',
      'params': {'topic': _topic, 'queueLimit': 4},
    },
    label: '$label direct JSON pub/sub notification subscribe',
    bearerToken: bearerToken,
  );
  final pubSubSubscription = _jsonRpcStructuredContent(
    pubSubSubscribe,
    id: pubSubSubscribeId,
    label: 'MCP $label direct JSON pub/sub notification subscribe',
  );
  final pubSubHandle = pubSubSubscription['handle'];
  if (pubSubHandle is! String ||
      pubSubHandle.isEmpty ||
      pubSubSubscription['topic'] != _topic ||
      pubSubSubscription['queueLimit'] != 4) {
    throw StateError(
      'MCP $label direct JSON pub/sub notification subscribe returned '
      'invalid content.',
    );
  }

  try {
    final pubSubNotificationTaskId =
        'T-$label-direct-cors-pubsub-notification';
    final invalidPubSubNotificationTaskId =
        'T-$label-direct-cors-invalid-pubsub-notification';
    final pubSubBatch = await _mcpRawDirectJsonRpcResponse(
      client,
      endpoint,
      <Map<String, Object?>>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'connectanum.pubsub.publish',
          'params': <String, Object?>{
            'topic': _topic,
            'argumentsKeywords': <String, Object?>{
              'taskId': pubSubNotificationTaskId,
            },
            'acknowledge': true,
          },
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'connectanum.pubsub.publish',
          'params': <String, Object?>{
            'argumentsKeywords': <String, Object?>{
              'taskId': invalidPubSubNotificationTaskId,
              'message': '$label invalid direct JSON pub/sub notification',
            },
          },
        },
      ],
      bearerToken: bearerToken,
    );
    _assertMcpDirectJsonNotificationAccepted(
      pubSubBatch,
      label: '$label direct JSON pub/sub notification-only batch',
    );
    await _mcpRawDirectJsonRpc(
      client,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-pubsub-notification-drain',
        'method': 'ping',
      },
      label: '$label direct JSON pub/sub notification drain',
      bearerToken: bearerToken,
    );
    final pubSubEventBatch = await _mcpRawDirectJsonPubSubPollUntil(
      client,
      endpoint,
      pubSubHandle,
      label: label,
      expectedTaskId: pubSubNotificationTaskId,
      bearerToken: bearerToken,
    );
    final pubSubEventsJson = jsonEncode(pubSubEventBatch['events']);
    if (pubSubEventsJson.contains(invalidPubSubNotificationTaskId)) {
      throw StateError(
        'MCP $label invalid direct JSON pub/sub notification-only batch '
        'delivered an event.',
      );
    }
  } finally {
    final pubSubUnsubscribeId =
        '$label-direct-cors-pubsub-notification-unsubscribe';
    final pubSubUnsubscribe = await _mcpRawDirectJsonRpc(
      client,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': pubSubUnsubscribeId,
        'method': 'connectanum.pubsub.unsubscribe',
        'params': {'handle': pubSubHandle},
      },
      label: '$label direct JSON pub/sub notification unsubscribe',
      bearerToken: bearerToken,
    );
    final pubSubUnsubscribeContent = _jsonRpcStructuredContent(
      pubSubUnsubscribe,
      id: pubSubUnsubscribeId,
      label: 'MCP $label direct JSON pub/sub notification unsubscribe',
    );
    if (pubSubUnsubscribeContent['handle'] != pubSubHandle ||
        pubSubUnsubscribeContent['topic'] != _topic ||
        pubSubUnsubscribeContent['unsubscribed'] != true) {
      throw StateError(
        'MCP $label direct JSON pub/sub notification unsubscribe returned '
        'invalid content.',
      );
    }
  }
}

void _assertMcpDirectJsonNotificationAccepted(
  _McpRawHttpResponse response, {
  required String label,
}) {
  if (response.statusCode != HttpStatus.accepted) {
    throw StateError('MCP $label returned ${response.statusCode}.');
  }
  _assertCorsAllowed(response, _allowedOrigin, label: label);
  _assertHeaderContains(
    response,
    'access-control-expose-headers',
    'mcp-session-id',
    label: '$label exposed headers',
  );
  _assertHeaderContains(
    response,
    'access-control-expose-headers',
    'mcp-protocol-version',
    label: '$label exposed headers',
  );
  if (response.header('mcp-session-id') != null) {
    throw StateError('MCP $label created Streamable session state.');
  }
  if (response.body.trim().isNotEmpty) {
    throw StateError('MCP $label returned a JSON-RPC response body.');
  }
}

Future<void> _assertMcpDirectJsonErrorCorsResponse(
  HttpClient client,
  Uri endpoint, {
  required String label,
  String? sessionId,
  String? bearerToken,
}) async {
  final missingTool = 'missing.$label.direct-cors-error.tool';
  final missingResourceUri = 'consumer://missing/$label/direct-cors-error';
  final missingPrompt = 'missing-$label-direct-cors-error-prompt';
  final missingApiUri = 'missing.$label.direct-cors-error.api';
  final missingHandle = '$label-direct-cors-error-handle';

  final toolErrorId = '$label-direct-cors-error-tool';
  final toolError = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': toolErrorId,
      'method': 'connectanum.tool.call',
      'params': {'name': missingTool, 'arguments': <String, Object?>{}},
    },
    label: '$label direct JSON missing tool error',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _expectJsonRpcError(
    toolError,
    id: toolErrorId,
    messageSubstring: missingTool,
    label: 'MCP $label direct JSON CORS missing tool',
  );

  final resourceErrorId = '$label-direct-cors-error-resource';
  final resourceError = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': resourceErrorId,
      'method': 'resources/read',
      'params': {'uri': missingResourceUri},
    },
    label: '$label direct JSON missing resource error',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _expectJsonRpcError(
    resourceError,
    id: resourceErrorId,
    messageSubstring: missingResourceUri,
    label: 'MCP $label direct JSON CORS missing resource',
  );

  final promptErrorId = '$label-direct-cors-error-prompt';
  final promptError = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': promptErrorId,
      'method': 'prompts/get',
      'params': {
        'name': missingPrompt,
        'arguments': {'taskId': 'T-$label-direct-cors-error'},
      },
    },
    label: '$label direct JSON missing prompt error',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _expectJsonRpcError(
    promptError,
    id: promptErrorId,
    messageSubstring: missingPrompt,
    label: 'MCP $label direct JSON CORS missing prompt',
  );

  final apiErrorId = '$label-direct-cors-error-api';
  final apiError = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': apiErrorId,
      'method': 'connectanum.api.describe',
      'params': {'uri': missingApiUri, 'kind': 'procedure'},
    },
    label: '$label direct JSON missing API describe error',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _expectMcpDirectJsonToolResultError(
    apiError,
    id: apiErrorId,
    messageSubstring: missingApiUri,
    label: 'MCP $label direct JSON CORS missing API describe',
  );

  final pollErrorId = '$label-direct-cors-error-pubsub-poll';
  final pollError = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': pollErrorId,
      'method': 'connectanum.pubsub.poll',
      'params': {'handle': missingHandle, 'limit': 1},
    },
    label: '$label direct JSON missing pub/sub poll error',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _expectMcpDirectJsonToolResultError(
    pollError,
    id: pollErrorId,
    messageSubstring: missingHandle,
    label: 'MCP $label direct JSON CORS missing pub/sub poll',
  );

  final unsubscribeErrorId = '$label-direct-cors-error-pubsub-unsubscribe';
  final unsubscribeError = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': unsubscribeErrorId,
      'method': 'connectanum.pubsub.unsubscribe',
      'params': {'handle': missingHandle},
    },
    label: '$label direct JSON missing pub/sub unsubscribe error',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _expectMcpDirectJsonToolResultError(
    unsubscribeError,
    id: unsubscribeErrorId,
    messageSubstring: missingHandle,
    label: 'MCP $label direct JSON CORS missing pub/sub unsubscribe',
  );

  final recoveryId = '$label-direct-cors-error-tools-recovery';
  final recovery = await _mcpRawDirectJsonRpc(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': recoveryId,
      'method': 'connectanum.tools.list',
    },
    label: '$label direct JSON error recovery tools/list',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  final tools = _jsonRpcResult(
    recovery,
    id: recoveryId,
    label: 'MCP $label direct JSON CORS error recovery tools/list',
  )['tools'];
  if (tools is! List || tools.isEmpty) {
    throw StateError(
      'MCP $label direct JSON CORS error recovery missed tool catalog.',
    );
  }

  final batchMissingTool = '$missingTool.batch';
  final batchMissingResourceUri = '$missingResourceUri/batch';
  final batchMissingPrompt = '$missingPrompt-batch';
  final batchMissingApiUri = '$missingApiUri.batch';
  final batchMissingHandle = '$missingHandle-batch';
  final errorBatch = await _mcpRawDirectJsonRpcBatch(
    client,
    endpoint,
    <Map<String, Object?>>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-error-batch-tools',
        'method': 'connectanum.tools.list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-error-batch-missing-tool',
        'method': 'connectanum.tool.call',
        'params': {
          'name': batchMissingTool,
          'arguments': <String, Object?>{},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-error-batch-missing-resource',
        'method': 'resources/read',
        'params': {'uri': batchMissingResourceUri},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-error-batch-missing-prompt',
        'method': 'prompts/get',
        'params': {
          'name': batchMissingPrompt,
          'arguments': {'taskId': 'T-$label-direct-cors-error-batch'},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-error-batch-missing-api',
        'method': 'connectanum.api.describe',
        'params': {'uri': batchMissingApiUri, 'kind': 'procedure'},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-error-batch-missing-pubsub',
        'method': 'connectanum.pubsub.poll',
        'params': {'handle': batchMissingHandle, 'limit': 1},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': <String, Object?>{},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-direct-cors-error-batch-resources',
        'method': 'resources/list',
      },
    ],
    label: '$label direct JSON error batch',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (errorBatch.length != 7) {
    throw StateError(
      'MCP $label direct JSON CORS error batch returned '
      '${errorBatch.length} responses.',
    );
  }
  final batchTools = _jsonRpcResult(
    errorBatch[0],
    id: '$label-direct-cors-error-batch-tools',
    label: 'MCP $label direct JSON CORS error batch tools/list',
  )['tools'];
  if (batchTools is! List || batchTools.isEmpty) {
    throw StateError(
      'MCP $label direct JSON CORS error batch missed tool catalog.',
    );
  }
  _expectJsonRpcError(
    errorBatch[1],
    id: '$label-direct-cors-error-batch-missing-tool',
    messageSubstring: batchMissingTool,
    label: 'MCP $label direct JSON CORS batch missing tool',
  );
  _expectJsonRpcError(
    errorBatch[2],
    id: '$label-direct-cors-error-batch-missing-resource',
    messageSubstring: batchMissingResourceUri,
    label: 'MCP $label direct JSON CORS batch missing resource',
  );
  _expectJsonRpcError(
    errorBatch[3],
    id: '$label-direct-cors-error-batch-missing-prompt',
    messageSubstring: batchMissingPrompt,
    label: 'MCP $label direct JSON CORS batch missing prompt',
  );
  _expectMcpDirectJsonToolResultError(
    errorBatch[4],
    id: '$label-direct-cors-error-batch-missing-api',
    messageSubstring: batchMissingApiUri,
    label: 'MCP $label direct JSON CORS batch missing API describe',
  );
  _expectMcpDirectJsonToolResultError(
    errorBatch[5],
    id: '$label-direct-cors-error-batch-missing-pubsub',
    messageSubstring: batchMissingHandle,
    label: 'MCP $label direct JSON CORS batch missing pub/sub poll',
  );
  if (!jsonEncode(
    _jsonRpcResult(
      errorBatch[6],
      id: '$label-direct-cors-error-batch-resources',
      label: 'MCP $label direct JSON CORS error batch resources/list',
    )['resources'],
  ).contains(_resourceUri)) {
    throw StateError(
      'MCP $label direct JSON CORS error batch recovery missed '
      '$_resourceUri.',
    );
  }
}

void _expectMcpDirectJsonToolResultError(
  Map<String, Object?> response, {
  required Object id,
  required String messageSubstring,
  required String label,
}) {
  _expectMcpToolResultError(
    response,
    id: id,
    messageSubstring: messageSubstring,
    label: label,
  );
}

void _expectMcpToolResultError(
  Map<String, Object?> response, {
  required Object id,
  required String messageSubstring,
  required String label,
}) {
  if (response['id'] != id) {
    throw StateError('$label response id was invalid.');
  }
  if (response.containsKey('error')) {
    throw StateError('$label response unexpectedly contained JSON-RPC error.');
  }
  final result = _jsonObjectFrom(response['result'], label: '$label result');
  if (result['isError'] != true) {
    throw StateError('$label response was not an MCP tool-result error.');
  }
  if (!jsonEncode(result).contains(messageSubstring)) {
    throw StateError('$label did not mention $messageSubstring.');
  }
}

Future<Map<String, Object?>> _mcpRawDirectJsonRpc(
  HttpClient client,
  Uri endpoint,
  Map<String, Object?> message, {
  required String label,
  String? sessionId,
  String? bearerToken,
}) async {
  final response = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    message,
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('MCP $label returned ${response.statusCode}.');
  }
  _assertCorsAllowed(response, _allowedOrigin, label: label);
  _assertHeaderContains(
    response,
    'access-control-expose-headers',
    'mcp-session-id',
    label: '$label exposed headers',
  );
  _assertHeaderContains(
    response,
    'access-control-expose-headers',
    'mcp-protocol-version',
    label: '$label exposed headers',
  );
  if (response.header('mcp-session-id') != null) {
    throw StateError('MCP $label created Streamable session state.');
  }
  final payload = _jsonObjectFrom(jsonDecode(response.body), label: label);
  if (payload['jsonrpc'] != '2.0') {
    throw StateError('MCP $label returned invalid JSON-RPC.');
  }
  return payload;
}

Future<List<Map<String, Object?>>> _mcpRawDirectJsonRpcBatch(
  HttpClient client,
  Uri endpoint,
  List<Map<String, Object?>> messages, {
  required String label,
  String? sessionId,
  String? bearerToken,
}) async {
  final response = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    messages,
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('MCP $label returned ${response.statusCode}.');
  }
  _assertCorsAllowed(response, _allowedOrigin, label: label);
  _assertHeaderContains(
    response,
    'access-control-expose-headers',
    'mcp-session-id',
    label: '$label exposed headers',
  );
  _assertHeaderContains(
    response,
    'access-control-expose-headers',
    'mcp-protocol-version',
    label: '$label exposed headers',
  );
  if (response.header('mcp-session-id') != null) {
    throw StateError('MCP $label created Streamable session state.');
  }
  final payload = jsonDecode(response.body);
  if (payload is! List) {
    throw StateError('MCP $label returned non-batch JSON-RPC.');
  }
  final responses = <Map<String, Object?>>[];
  for (final item in payload) {
    final responsePayload = _jsonObjectFrom(
      item,
      label: '$label batch response',
    );
    if (responsePayload['jsonrpc'] != '2.0') {
      throw StateError('MCP $label returned invalid batch JSON-RPC.');
    }
    responses.add(responsePayload);
  }
  return responses;
}

Future<_McpRawHttpResponse> _mcpRawDirectJsonRpcResponse(
  HttpClient client,
  Uri endpoint,
  Object? message, {
  String? sessionId,
  String? bearerToken,
}) async {
  final request = await client.postUrl(endpoint);
  request.headers.set('Accept', 'application/json');
  request.headers.set('Origin', _allowedOrigin);
  if (sessionId != null) {
    request.headers.set('MCP-Session-Id', sessionId);
  }
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  request.headers.contentType = ContentType.json;
  final body = utf8.encode(jsonEncode(message));
  request.contentLength = body.length;
  request.add(body);
  return _mcpRawResponseFrom(await request.close());
}

Future<Map<String, Object?>> _mcpRawDirectJsonPubSubPollUntil(
  HttpClient client,
  Uri endpoint,
  String handle, {
  required String label,
  required String expectedTaskId,
  String? bearerToken,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final pollId =
        '$label-direct-cors-pubsub-poll-'
        '${DateTime.now().microsecondsSinceEpoch}';
    final poll = await _mcpRawDirectJsonRpc(
      client,
      endpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': pollId,
        'method': 'connectanum.pubsub.poll',
        'params': {'handle': handle, 'limit': 4},
      },
      label: '$label direct JSON connectanum.pubsub.poll',
      bearerToken: bearerToken,
    );
    final eventBatch = _jsonRpcStructuredContent(
      poll,
      id: pollId,
      label: 'MCP $label direct JSON CORS pub/sub poll',
    );
    if (eventBatch['handle'] != handle || eventBatch['topic'] != _topic) {
      throw StateError(
        'MCP $label direct JSON CORS pub/sub poll returned invalid content.',
      );
    }
    if (jsonEncode(eventBatch['events']).contains(expectedTaskId)) {
      return eventBatch;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'Timed out waiting for MCP $label direct JSON CORS pub/sub event.',
  );
}

Future<void> _assertMcpStreamableCorsLifecycle(
  HttpClient client,
  Uri endpoint,
  RouterSession serviceSession, {
  required String label,
  String? bearerToken,
}) async {
  final initializeId = '$label-streamable-cors-initialize';
  final initialize = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': initializeId,
      'method': 'initialize',
      'params': <String, Object?>{
        'protocolVersion': McpStreamableHttpClient.latestProtocolVersion,
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{
          'name': 'connectanum_consumer_cors_smoke',
          'version': '0.1.0',
        },
      },
    },
    bearerToken: bearerToken,
  );
  if (initialize.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS initialize returned '
      '${initialize.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    initialize,
    label: '$label Streamable initialize',
  );
  final sessionId = initialize.header('mcp-session-id');
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'MCP $label Streamable CORS initialize did not expose session id.',
    );
  }
  final initializePayload = _jsonObjectFrom(
    jsonDecode(initialize.body),
    label: '$label Streamable initialize response',
  );
  if (initializePayload['id'] != initializeId) {
    throw StateError(
      'MCP $label Streamable CORS initialize returned wrong id.',
    );
  }

  final initialized = await _mcpRawJsonPost(
    client,
    endpoint,
    const <String, Object?>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (initialized.statusCode != HttpStatus.accepted) {
    throw StateError(
      'MCP $label Streamable CORS initialized notification returned '
      '${initialized.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    initialized,
    label: '$label Streamable initialized notification',
  );

  final toolsId = '$label-streamable-cors-tools';
  final tools = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': toolsId,
      'method': 'tools/list',
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (tools.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS tools/list returned '
      '${tools.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    tools,
    label: '$label Streamable POST/SSE tools/list',
  );
  final toolPayload = _mcpSseJsonRpcPayload(
    tools,
    id: toolsId,
    label: '$label Streamable POST/SSE tools/list',
  );
  final toolResult = _jsonObjectFrom(
    toolPayload['result'],
    label: '$label Streamable POST/SSE tools/list result',
  );
  if (toolResult['tools'] is! List) {
    throw StateError(
      'MCP $label Streamable CORS tools/list missed tool catalog.',
    );
  }

  final pingId = '$label-streamable-cors-ping';
  final ping = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': pingId,
      'method': 'ping',
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (ping.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS ping returned ${ping.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    ping,
    label: '$label Streamable POST/SSE ping',
  );
  final pingPayload = _mcpSseJsonRpcPayload(
    ping,
    id: pingId,
    label: '$label Streamable POST/SSE ping',
  );
  final pingResult = _jsonRpcResult(
    pingPayload,
    id: pingId,
    label: 'MCP $label Streamable CORS ping',
  );
  if (pingResult.isNotEmpty) {
    throw StateError('MCP $label Streamable CORS ping returned data.');
  }

  await _assertMcpStreamableCorsPostBodyErrors(
    client,
    endpoint,
    sessionId: sessionId,
    label: label,
    bearerToken: bearerToken,
  );

  await _assertMcpStreamableCorsSessionGuardErrors(
    client,
    endpoint,
    sessionId: sessionId,
    label: label,
    bearerToken: bearerToken,
  );

  if (bearerToken != null) {
    await _assertMcpStreamableCorsAuthErrors(
      client,
      endpoint,
      sessionId: sessionId,
      label: label,
      validBearerToken: bearerToken,
    );
  }

  await _assertMcpStreamableCorsHeaderErrors(
    client,
    endpoint,
    sessionId: sessionId,
    label: label,
    bearerToken: bearerToken,
  );

  await _assertMcpStreamableCorsNamedMethods(
    client,
    endpoint,
    sessionId: sessionId,
    label: label,
    bearerToken: bearerToken,
  );

  await _assertMcpStreamableCorsWampTools(
    client,
    endpoint,
    serviceSession,
    sessionId: sessionId,
    label: label,
    bearerToken: bearerToken,
  );

  await _assertMcpStreamableCorsWampBatchTools(
    client,
    endpoint,
    serviceSession,
    sessionId: sessionId,
    label: label,
    bearerToken: bearerToken,
  );

  final dynamicProcedure = 'consumer.task.cors.${label.replaceAll('-', '.')}';
  final registration = await serviceSession.register(
    dynamicProcedure,
    options: RegisterOptions(
      custom: {
        '_ai_meta_data': {
          'short_description': 'CORS $label consumer task',
          'description':
              'Procedure registered during raw Streamable HTTP CORS smoke.',
          'read_only_hint': true,
          'destructive_hint': false,
          'idempotent_hint': true,
          'open_world_hint': false,
        },
      },
    ),
  );
  registration.onInvoke((invocation) {
    invocation.respondWith(
      argumentsKeywords: {'label': label, 'source': 'consumer-cors-smoke'},
    );
  });

  final poll = await _mcpRawPollUntilToolListChanged(
    client,
    endpoint,
    sessionId: sessionId,
    label: label,
    bearerToken: bearerToken,
  );
  final pollEventId = _mcpFirstSseEventId(
    poll,
    label: '$label Streamable GET/SSE poll',
  );
  if (pollEventId == null || pollEventId.isEmpty) {
    throw StateError(
      'MCP $label Streamable GET/SSE CORS did not expose an event id.',
    );
  }

  final resume = await _mcpRawSessionRequest(
    client,
    endpoint,
    'GET',
    sessionId: sessionId,
    bearerToken: bearerToken,
    lastEventId: pollEventId,
  );
  if (resume.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable Last-Event-ID CORS poll returned '
      '${resume.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    resume,
    label: '$label Streamable Last-Event-ID poll',
  );
  _assertMcpSseResponse(
    resume,
    label: '$label Streamable Last-Event-ID poll',
  );
  if (resume.body.contains(pollEventId) ||
      resume.body.contains('notifications/tools/list_changed')) {
    throw StateError(
      'MCP $label Streamable Last-Event-ID CORS poll replayed an old event.',
    );
  }

  final deleted = await _mcpRawSessionRequest(
    client,
    endpoint,
    'DELETE',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (deleted.statusCode != HttpStatus.accepted) {
    throw StateError(
      'MCP $label Streamable CORS DELETE returned ${deleted.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    deleted,
    label: '$label Streamable DELETE',
  );

  final stalePoll = await _mcpRawSessionRequest(
    client,
    endpoint,
    'GET',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    stalePoll,
    expectedStatus: HttpStatus.notFound,
    label: '$label Streamable stale-session poll',
    sessionId: sessionId,
    bodyContains: 'Unknown MCP HTTP session',
  );

  final staleDelete = await _mcpRawSessionRequest(
    client,
    endpoint,
    'DELETE',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    staleDelete,
    expectedStatus: HttpStatus.notFound,
    label: '$label Streamable stale-session delete',
    sessionId: sessionId,
    bodyContains: 'Unknown MCP HTTP session',
  );
}

Future<void> _assertMcpStreamableCorsPostBodyErrors(
  HttpClient client,
  Uri endpoint, {
  required String sessionId,
  required String label,
  String? bearerToken,
}) async {
  final unsupported = await _mcpRawPostBody(
    client,
    endpoint,
    body: jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': '$label-streamable-cors-unsupported-content-type',
      'method': 'tools/list',
    }),
    contentType: 'text/plain',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    unsupported,
    expectedStatus: HttpStatus.unsupportedMediaType,
    label: '$label Streamable unsupported Content-Type',
    sessionId: sessionId,
    bodyContains: 'JSON content type',
  );

  final malformed = await _mcpRawPostBody(
    client,
    endpoint,
    body: '{"jsonrpc":"2.0","id":"$label-streamable-cors-malformed-json",',
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    malformed,
    expectedStatus: HttpStatus.badRequest,
    label: '$label Streamable malformed JSON',
    sessionId: sessionId,
    bodyContains: 'Invalid JSON-RPC message',
  );

  final recoveryId = '$label-streamable-cors-post-body-recovery';
  final recovery = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': recoveryId,
      'method': 'tools/list',
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (recovery.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS POST body recovery returned '
      '${recovery.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    recovery,
    label: '$label Streamable POST body recovery',
  );
  _mcpSseJsonRpcPayload(
    recovery,
    id: recoveryId,
    label: '$label Streamable POST body recovery',
  );
}

Future<void> _assertMcpStreamableCorsSessionGuardErrors(
  HttpClient client,
  Uri endpoint, {
  required String sessionId,
  required String label,
  String? bearerToken,
}) async {
  final missingPollSession = await _mcpRawMcpRequest(
    client,
    endpoint,
    'GET',
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    missingPollSession,
    expectedStatus: HttpStatus.badRequest,
    label: '$label Streamable missing poll session',
    expectNoSession: true,
    bodyContains: 'MCP-Session-Id',
  );

  final missingDeleteSession = await _mcpRawMcpRequest(
    client,
    endpoint,
    'DELETE',
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    missingDeleteSession,
    expectedStatus: HttpStatus.badRequest,
    label: '$label Streamable missing delete session',
    expectNoSession: true,
    bodyContains: 'MCP-Session-Id',
  );

  final invalidLastEventId = await _mcpRawSessionRequest(
    client,
    endpoint,
    'GET',
    sessionId: sessionId,
    bearerToken: bearerToken,
    lastEventId: '$sessionId:missing:1',
  );
  _assertMcpCorsErrorResponse(
    invalidLastEventId,
    expectedStatus: HttpStatus.badRequest,
    label: '$label Streamable invalid Last-Event-ID',
    sessionId: sessionId,
    bodyContains: 'Last-Event-ID',
  );

  final recoveryId = '$label-streamable-cors-session-guard-recovery';
  final recovery = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': recoveryId,
      'method': 'tools/list',
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (recovery.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS session-guard recovery returned '
      '${recovery.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    recovery,
    label: '$label Streamable session-guard recovery',
  );
  _mcpSseJsonRpcPayload(
    recovery,
    id: recoveryId,
    label: '$label Streamable session-guard recovery',
  );
}

Future<void> _assertMcpStreamableCorsAuthErrors(
  HttpClient client,
  Uri endpoint, {
  required String sessionId,
  required String label,
  required String validBearerToken,
}) async {
  final missingPost = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': '$label-streamable-cors-missing-bearer-post',
      'method': 'tools/list',
    },
    sessionId: sessionId,
  );
  _assertMcpCorsErrorResponse(
    missingPost,
    expectedStatus: HttpStatus.unauthorized,
    label: '$label Streamable POST missing bearer',
    sessionId: sessionId,
    bodyContains: 'Bearer token required',
  );
  _assertHeaderContains(
    missingPost,
    'www-authenticate',
    'Bearer',
    label: '$label Streamable POST missing bearer',
  );

  final invalidToken = 'invalid-$label-cors-token';
  final invalidPost = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': '$label-streamable-cors-invalid-bearer-post',
      'method': 'tools/list',
    },
    sessionId: sessionId,
    bearerToken: invalidToken,
  );
  _assertMcpCorsErrorResponse(
    invalidPost,
    expectedStatus: HttpStatus.unauthorized,
    label: '$label Streamable POST invalid bearer',
    sessionId: sessionId,
    bodyContains: 'Bearer token',
  );
  _assertHeaderContains(
    invalidPost,
    'www-authenticate',
    'Bearer',
    label: '$label Streamable POST invalid bearer',
  );

  final missingPoll = await _mcpRawSessionRequest(
    client,
    endpoint,
    'GET',
    sessionId: sessionId,
  );
  _assertMcpCorsErrorResponse(
    missingPoll,
    expectedStatus: HttpStatus.unauthorized,
    label: '$label Streamable poll missing bearer',
    sessionId: sessionId,
    bodyContains: 'Bearer token required',
  );
  _assertHeaderContains(
    missingPoll,
    'www-authenticate',
    'Bearer',
    label: '$label Streamable poll missing bearer',
  );

  final invalidDelete = await _mcpRawSessionRequest(
    client,
    endpoint,
    'DELETE',
    sessionId: sessionId,
    bearerToken: invalidToken,
  );
  _assertMcpCorsErrorResponse(
    invalidDelete,
    expectedStatus: HttpStatus.unauthorized,
    label: '$label Streamable delete invalid bearer',
    sessionId: sessionId,
    bodyContains: 'Bearer token',
  );
  _assertHeaderContains(
    invalidDelete,
    'www-authenticate',
    'Bearer',
    label: '$label Streamable delete invalid bearer',
  );

  final recoveryId = '$label-streamable-cors-auth-recovery';
  final recovery = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': recoveryId,
      'method': 'tools/list',
    },
    sessionId: sessionId,
    bearerToken: validBearerToken,
  );
  if (recovery.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS auth-error recovery returned '
      '${recovery.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    recovery,
    label: '$label Streamable auth-error recovery',
  );
  _mcpSseJsonRpcPayload(
    recovery,
    id: recoveryId,
    label: '$label Streamable auth-error recovery',
  );
}

Future<void> _assertMcpStreamableCorsHeaderErrors(
  HttpClient client,
  Uri endpoint, {
  required String sessionId,
  required String label,
  String? bearerToken,
}) async {
  final headerlessToolsId = '$label-streamable-cors-headerless-tools';
  final headerlessTools = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': headerlessToolsId,
      'method': 'tools/list',
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
    includeMethodHeader: false,
  );
  if (headerlessTools.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable headerless tools/list returned '
      '${headerlessTools.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    headerlessTools,
    label: '$label Streamable headerless tools/list',
  );
  _mcpSseJsonRpcPayload(
    headerlessTools,
    id: headerlessToolsId,
    label: '$label Streamable headerless tools/list',
  );

  final headerlessToolTaskId =
      'T-$label-streamable-cors-headerless-tool-call';
  final headerlessToolCallId = '$label-streamable-cors-headerless-tool-call';
  final headerlessToolCall = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': headerlessToolCallId,
      'method': 'tools/call',
      'params': {
        'name': _procedure,
        'arguments': {
          'taskId': headerlessToolTaskId,
          'note': _headerWrappedNote,
        },
      },
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
    includeMethodHeader: false,
    includeNameHeader: false,
  );
  if (headerlessToolCall.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable headerless tools/call returned '
      '${headerlessToolCall.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    headerlessToolCall,
    label: '$label Streamable headerless tools/call',
  );
  final headerlessToolPayload = _mcpSseJsonRpcPayload(
    headerlessToolCall,
    id: headerlessToolCallId,
    label: '$label Streamable headerless tools/call',
  );
  final headerlessToolJson = jsonEncode(headerlessToolPayload['result']);
  if (!headerlessToolJson.contains(headerlessToolTaskId) ||
      !headerlessToolJson.contains(_headerWrappedNote)) {
    throw StateError(
      'MCP $label Streamable headerless tools/call missed procedure result.',
    );
  }

  final headerlessResourceId =
      '$label-streamable-cors-headerless-resource-read';
  final headerlessResource = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': headerlessResourceId,
      'method': 'resources/read',
      'params': {'uri': _resourceUri},
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
    includeMethodHeader: false,
    includeNameHeader: false,
  );
  if (headerlessResource.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable headerless resources/read returned '
      '${headerlessResource.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    headerlessResource,
    label: '$label Streamable headerless resources/read',
  );
  final headerlessResourcePayload = _mcpSseJsonRpcPayload(
    headerlessResource,
    id: headerlessResourceId,
    label: '$label Streamable headerless resources/read',
  );
  if (!jsonEncode(headerlessResourcePayload['result']).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError(
      'MCP $label Streamable headerless resources/read missed route context.',
    );
  }

  final headerlessPromptTaskId =
      'T-$label-streamable-cors-headerless-prompt';
  final headerlessPromptId = '$label-streamable-cors-headerless-prompt';
  final headerlessPrompt = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': headerlessPromptId,
      'method': 'prompts/get',
      'params': {
        'name': _promptName,
        'arguments': {'taskId': headerlessPromptTaskId},
      },
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
    includeMethodHeader: false,
    includeNameHeader: false,
  );
  if (headerlessPrompt.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable headerless prompts/get returned '
      '${headerlessPrompt.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    headerlessPrompt,
    label: '$label Streamable headerless prompts/get',
  );
  final headerlessPromptPayload = _mcpSseJsonRpcPayload(
    headerlessPrompt,
    id: headerlessPromptId,
    label: '$label Streamable headerless prompts/get',
  );
  if (!jsonEncode(headerlessPromptPayload['result']).contains(
    headerlessPromptTaskId,
  )) {
    throw StateError(
      'MCP $label Streamable headerless prompts/get did not substitute task id.',
    );
  }

  final nameMismatchTaskId = 'T-$label-streamable-cors-name-mismatch';
  final nameMismatch = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': '$label-streamable-cors-name-mismatch',
      'method': 'tools/call',
      'params': {
        'name': _procedure,
        'arguments': {
          'taskId': nameMismatchTaskId,
          'note': _headerWrappedNote,
        },
      },
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
    nameHeader: 'consumer.task.other',
    parameterHeaders: {
      'TaskId': nameMismatchTaskId,
      'Note': _mcpBase64Header(_headerWrappedNote),
    },
  );
  _assertMcpCorsErrorResponse(
    nameMismatch,
    expectedStatus: HttpStatus.badRequest,
    label: '$label Streamable mismatched Mcp-Name',
    sessionId: sessionId,
    bodyContains: 'Mcp-Name',
  );

  final missingParamTaskId = 'T-$label-streamable-cors-missing-param';
  final missingParam = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': '$label-streamable-cors-missing-param',
      'method': 'tools/call',
      'params': {
        'name': _procedure,
        'arguments': {
          'taskId': missingParamTaskId,
          'note': _headerWrappedNote,
        },
      },
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  _assertMcpCorsErrorResponse(
    missingParam,
    expectedStatus: HttpStatus.badRequest,
    label: '$label Streamable missing Mcp-Param-TaskId',
    sessionId: sessionId,
    bodyContains: 'Mcp-Param-TaskId',
  );

  final invalidNoteTaskId = 'T-$label-streamable-cors-invalid-note';
  final invalidNote = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': '$label-streamable-cors-invalid-note',
      'method': 'tools/call',
      'params': {
        'name': _procedure,
        'arguments': {
          'taskId': invalidNoteTaskId,
          'note': _headerWrappedNote,
        },
      },
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
    parameterHeaders: {
      'TaskId': invalidNoteTaskId,
      'Note': '=?base64?not-base64?=',
    },
  );
  _assertMcpCorsErrorResponse(
    invalidNote,
    expectedStatus: HttpStatus.badRequest,
    label: '$label Streamable invalid Mcp-Param-Note',
    sessionId: sessionId,
    bodyContains: 'Mcp-Param-Note',
  );

  final recoveryId = '$label-streamable-cors-header-error-recovery';
  final recovery = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': recoveryId,
      'method': 'tools/list',
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (recovery.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS header-error recovery returned '
      '${recovery.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    recovery,
    label: '$label Streamable header-error recovery',
  );
  _mcpSseJsonRpcPayload(
    recovery,
    id: recoveryId,
    label: '$label Streamable header-error recovery',
  );
}

Future<void> _assertMcpStreamableCorsNamedMethods(
  HttpClient client,
  Uri endpoint, {
  required String sessionId,
  required String label,
  String? bearerToken,
}) async {
  final toolTaskId = 'T-$label-streamable-cors-tool-call';
  final toolCallId = '$label-streamable-cors-tool-call';
  final toolCall = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': toolCallId,
      'method': 'tools/call',
      'params': {
        'name': _procedure,
        'arguments': {
          'taskId': toolTaskId,
          'note': _headerWrappedNote,
        },
      },
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
    parameterHeaders: {
      'TaskId': toolTaskId,
      'Note': _mcpBase64Header(_headerWrappedNote),
    },
  );
  if (toolCall.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS tools/call returned '
      '${toolCall.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    toolCall,
    label: '$label Streamable POST/SSE tools/call',
  );
  final toolPayload = _mcpSseJsonRpcPayload(
    toolCall,
    id: toolCallId,
    label: '$label Streamable POST/SSE tools/call',
  );
  final toolJson = jsonEncode(toolPayload['result']);
  if (!toolJson.contains(toolTaskId) || !toolJson.contains(_headerWrappedNote)) {
    throw StateError(
      'MCP $label Streamable CORS tools/call missed procedure result.',
    );
  }

  final resourceId = '$label-streamable-cors-resource-read';
  final resource = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': resourceId,
      'method': 'resources/read',
      'params': {'uri': _resourceUri},
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (resource.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS resources/read returned '
      '${resource.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    resource,
    label: '$label Streamable POST/SSE resources/read',
  );
  final resourcePayload = _mcpSseJsonRpcPayload(
    resource,
    id: resourceId,
    label: '$label Streamable POST/SSE resources/read',
  );
  if (!jsonEncode(resourcePayload['result']).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError(
      'MCP $label Streamable CORS resources/read missed route context.',
    );
  }

  final promptTaskId = 'T-$label-streamable-cors-prompt';
  final promptId = '$label-streamable-cors-prompt';
  final prompt = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': promptId,
      'method': 'prompts/get',
      'params': {
        'name': _promptName,
        'arguments': {'taskId': promptTaskId},
      },
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (prompt.statusCode != HttpStatus.ok) {
    throw StateError(
      'MCP $label Streamable CORS prompts/get returned '
      '${prompt.statusCode}.',
    );
  }
  _assertMcpCorsStatefulResponse(
    prompt,
    label: '$label Streamable POST/SSE prompts/get',
  );
  final promptPayload = _mcpSseJsonRpcPayload(
    prompt,
    id: promptId,
    label: '$label Streamable POST/SSE prompts/get',
  );
  if (!jsonEncode(promptPayload['result']).contains(promptTaskId)) {
    throw StateError(
      'MCP $label Streamable CORS prompts/get did not substitute task id.',
    );
  }
}

Future<void> _assertMcpStreamableCorsWampTools(
  HttpClient client,
  Uri endpoint,
  RouterSession serviceSession, {
  required String sessionId,
  required String label,
  String? bearerToken,
}) async {
  final apiListId = '$label-streamable-cors-wamp-api-list';
  final apiList = await _mcpRawStreamableToolCall(
    client,
    endpoint,
    sessionId: sessionId,
    id: apiListId,
    name: 'connectanum.api.list',
    arguments: const <String, Object?>{},
    label: '$label Streamable WAMP API list',
    bearerToken: bearerToken,
  );
  final apiCatalog = _jsonRpcStructuredContent(
    apiList,
    id: apiListId,
    label: 'MCP $label Streamable CORS WAMP API list',
  );
  final apiCatalogJson = jsonEncode(apiCatalog);
  if (!apiCatalogJson.contains(_procedure) ||
      !apiCatalogJson.contains(_topic)) {
    throw StateError(
      'MCP $label Streamable CORS WAMP API list missed router metadata.',
    );
  }

  final apiDescribeId = '$label-streamable-cors-wamp-api-describe';
  final apiDescribe = await _mcpRawStreamableToolCall(
    client,
    endpoint,
    sessionId: sessionId,
    id: apiDescribeId,
    name: 'connectanum.api.describe',
    arguments: {'uri': _procedure, 'kind': 'procedure'},
    label: '$label Streamable WAMP API describe',
    bearerToken: bearerToken,
  );
  final apiDescription = _jsonRpcStructuredContent(
    apiDescribe,
    id: apiDescribeId,
    label: 'MCP $label Streamable CORS WAMP API describe',
  );
  if (!jsonEncode(apiDescription).contains(_procedure)) {
    throw StateError(
      'MCP $label Streamable CORS WAMP API describe missed $_procedure.',
    );
  }

  final topicDescribeId = '$label-streamable-cors-wamp-topic-describe';
  final topicDescribe = await _mcpRawStreamableToolCall(
    client,
    endpoint,
    sessionId: sessionId,
    id: topicDescribeId,
    name: 'connectanum.api.describe',
    arguments: {'uri': _topic, 'kind': 'topic'},
    label: '$label Streamable WAMP topic describe',
    bearerToken: bearerToken,
  );
  final topicDescription = _jsonRpcStructuredContent(
    topicDescribe,
    id: topicDescribeId,
    label: 'MCP $label Streamable CORS WAMP topic describe',
  );
  final topicDescriptionJson = jsonEncode(topicDescription);
  if (!topicDescriptionJson.contains(_topic) ||
      !topicDescriptionJson.contains('eventSchema') ||
      !topicDescriptionJson.contains('allowPublish') ||
      !topicDescriptionJson.contains('allowSubscribe')) {
    throw StateError(
      'MCP $label Streamable CORS WAMP topic describe missed $_topic.',
    );
  }

  final missingApiUri = 'missing.$label.streamable-cors-wamp-api';
  final missingApiId = '$label-streamable-cors-wamp-api-missing';
  final missingApi = await _mcpRawStreamableToolCall(
    client,
    endpoint,
    sessionId: sessionId,
    id: missingApiId,
    name: 'connectanum.api.describe',
    arguments: {'uri': missingApiUri, 'kind': 'procedure'},
    label: '$label Streamable WAMP missing API describe',
    bearerToken: bearerToken,
  );
  _expectMcpToolResultError(
    missingApi,
    id: missingApiId,
    messageSubstring: missingApiUri,
    label: 'MCP $label Streamable CORS missing WAMP API describe',
  );

  final subscribeId = '$label-streamable-cors-wamp-pubsub-subscribe';
  final subscribe = await _mcpRawStreamableToolCall(
    client,
    endpoint,
    sessionId: sessionId,
    id: subscribeId,
    name: 'connectanum.pubsub.subscribe',
    arguments: {'topic': _topic, 'queueLimit': 4},
    label: '$label Streamable WAMP pub/sub subscribe',
    bearerToken: bearerToken,
  );
  final subscription = _jsonRpcStructuredContent(
    subscribe,
    id: subscribeId,
    label: 'MCP $label Streamable CORS WAMP pub/sub subscribe',
  );
  final handle = subscription['handle'];
  if (handle is! String ||
      handle.isEmpty ||
      subscription['topic'] != _topic ||
      subscription['queueLimit'] != 4) {
    throw StateError(
      'MCP $label Streamable CORS WAMP pub/sub subscribe returned invalid '
      'content.',
    );
  }

  try {
    final publishId = '$label-streamable-cors-wamp-pubsub-publish';
    final publish = await _mcpRawStreamableToolCall(
      client,
      endpoint,
      sessionId: sessionId,
      id: publishId,
      name: 'connectanum.pubsub.publish',
      arguments: {
        'topic': _topic,
        'argumentsKeywords': {
          'taskId': 'T-$label-streamable-cors-wamp-pubsub-publish',
        },
        'acknowledge': true,
      },
      label: '$label Streamable WAMP pub/sub publish',
      bearerToken: bearerToken,
    );
    final publication = _jsonRpcStructuredContent(
      publish,
      id: publishId,
      label: 'MCP $label Streamable CORS WAMP pub/sub publish',
    );
    if (publication['topic'] != _topic ||
        publication['acknowledged'] != true) {
      throw StateError(
        'MCP $label Streamable CORS WAMP pub/sub publish returned invalid '
        'content.',
      );
    }

    final serviceTaskId = 'T-$label-streamable-cors-wamp-pubsub-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );
    await _mcpRawStreamablePubSubPollUntil(
      client,
      endpoint,
      sessionId: sessionId,
      handle: handle,
      label: label,
      expectedTaskId: serviceTaskId,
      bearerToken: bearerToken,
    );
  } finally {
    final unsubscribeId = '$label-streamable-cors-wamp-pubsub-unsubscribe';
    final unsubscribe = await _mcpRawStreamableToolCall(
      client,
      endpoint,
      sessionId: sessionId,
      id: unsubscribeId,
      name: 'connectanum.pubsub.unsubscribe',
      arguments: {'handle': handle},
      label: '$label Streamable WAMP pub/sub unsubscribe',
      bearerToken: bearerToken,
    );
    final unsubscribeContent = _jsonRpcStructuredContent(
      unsubscribe,
      id: unsubscribeId,
      label: 'MCP $label Streamable CORS WAMP pub/sub unsubscribe',
    );
    if (unsubscribeContent['handle'] != handle ||
        unsubscribeContent['topic'] != _topic ||
        unsubscribeContent['unsubscribed'] != true) {
      throw StateError(
        'MCP $label Streamable CORS WAMP pub/sub unsubscribe returned '
        'invalid content.',
      );
    }
  }

  final missingHandle = '$label-streamable-cors-wamp-pubsub-missing-handle';
  final missingPollId = '$label-streamable-cors-wamp-pubsub-missing-poll';
  final missingPoll = await _mcpRawStreamableToolCall(
    client,
    endpoint,
    sessionId: sessionId,
    id: missingPollId,
    name: 'connectanum.pubsub.poll',
    arguments: {'handle': missingHandle, 'limit': 1},
    label: '$label Streamable WAMP missing pub/sub poll',
    bearerToken: bearerToken,
  );
  _expectMcpToolResultError(
    missingPoll,
    id: missingPollId,
    messageSubstring: missingHandle,
    label: 'MCP $label Streamable CORS missing WAMP pub/sub poll',
  );
}

Future<void> _assertMcpStreamableCorsWampBatchTools(
  HttpClient client,
  Uri endpoint,
  RouterSession serviceSession, {
  required String sessionId,
  required String label,
  String? bearerToken,
}) async {
  final apiListId = '$label-streamable-cors-wamp-batch-api-list';
  final apiDescribeId = '$label-streamable-cors-wamp-batch-api-describe';
  final topicDescribeId = '$label-streamable-cors-wamp-batch-topic-describe';
  final missingApiUri = 'missing.$label.streamable-cors-wamp-batch-api';
  final missingApiId = '$label-streamable-cors-wamp-batch-api-missing';
  final apiBatch = await _mcpRawStreamableJsonRpcBatch(
    client,
    endpoint,
    <Map<String, Object?>>[
      _mcpToolCallMessage(
        id: apiListId,
        name: 'connectanum.api.list',
        arguments: const <String, Object?>{},
      ),
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': '$label-streamable-cors-wamp-batch-ping',
        'method': 'ping',
      },
      _mcpToolCallMessage(
        id: apiDescribeId,
        name: 'connectanum.api.describe',
        arguments: {'uri': _procedure, 'kind': 'procedure'},
      ),
      _mcpToolCallMessage(
        id: topicDescribeId,
        name: 'connectanum.api.describe',
        arguments: {'uri': _topic, 'kind': 'topic'},
      ),
      _mcpToolCallMessage(
        id: missingApiId,
        name: 'connectanum.api.describe',
        arguments: {'uri': missingApiUri, 'kind': 'procedure'},
      ),
    ],
    sessionId: sessionId,
    label: '$label Streamable WAMP API batch',
    bearerToken: bearerToken,
  );
  if (apiBatch.length != 5) {
    throw StateError(
      'MCP $label Streamable CORS WAMP API batch returned '
      '${apiBatch.length} responses.',
    );
  }
  final apiCatalogJson = jsonEncode(
    _jsonRpcStructuredContent(
      apiBatch[0],
      id: apiListId,
      label: 'MCP $label Streamable CORS WAMP batch API list',
    ),
  );
  if (!apiCatalogJson.contains(_procedure) ||
      !apiCatalogJson.contains(_topic)) {
    throw StateError(
      'MCP $label Streamable CORS WAMP batch API list missed router '
      'metadata.',
    );
  }
  final batchPing = _jsonRpcResult(
    apiBatch[1],
    id: '$label-streamable-cors-wamp-batch-ping',
    label: 'MCP $label Streamable CORS WAMP batch ping',
  );
  if (batchPing.isNotEmpty) {
    throw StateError(
      'MCP $label Streamable CORS WAMP batch ping returned data.',
    );
  }
  if (!jsonEncode(
    _jsonRpcStructuredContent(
      apiBatch[2],
      id: apiDescribeId,
      label: 'MCP $label Streamable CORS WAMP batch API describe',
    ),
  ).contains(_procedure)) {
    throw StateError(
      'MCP $label Streamable CORS WAMP batch API describe missed '
      '$_procedure.',
    );
  }
  final topicDescriptionJson = jsonEncode(
    _jsonRpcStructuredContent(
      apiBatch[3],
      id: topicDescribeId,
      label: 'MCP $label Streamable CORS WAMP batch topic describe',
    ),
  );
  if (!topicDescriptionJson.contains(_topic) ||
      !topicDescriptionJson.contains('eventSchema') ||
      !topicDescriptionJson.contains('allowPublish') ||
      !topicDescriptionJson.contains('allowSubscribe')) {
    throw StateError(
      'MCP $label Streamable CORS WAMP batch topic describe missed $_topic.',
    );
  }
  _expectMcpToolResultError(
    apiBatch[4],
    id: missingApiId,
    messageSubstring: missingApiUri,
    label: 'MCP $label Streamable CORS WAMP batch missing API describe',
  );

  final subscribeId = '$label-streamable-cors-wamp-batch-pubsub-subscribe';
  final subscribeCatalogId =
      '$label-streamable-cors-wamp-batch-pubsub-api-list';
  final subscribeBatch = await _mcpRawStreamableJsonRpcBatch(
    client,
    endpoint,
    <Map<String, Object?>>[
      _mcpToolCallMessage(
        id: subscribeId,
        name: 'connectanum.pubsub.subscribe',
        arguments: {'topic': _topic, 'queueLimit': 4},
      ),
      _mcpToolCallMessage(
        id: subscribeCatalogId,
        name: 'connectanum.api.list',
        arguments: const <String, Object?>{},
      ),
    ],
    sessionId: sessionId,
    label: '$label Streamable WAMP pub/sub subscribe batch',
    bearerToken: bearerToken,
  );
  if (subscribeBatch.length != 2) {
    throw StateError(
      'MCP $label Streamable CORS WAMP pub/sub subscribe batch returned '
      '${subscribeBatch.length} responses.',
    );
  }
  final subscription = _jsonRpcStructuredContent(
    subscribeBatch[0],
    id: subscribeId,
    label: 'MCP $label Streamable CORS WAMP batch pub/sub subscribe',
  );
  final handle = subscription['handle'];
  if (handle is! String ||
      handle.isEmpty ||
      subscription['topic'] != _topic ||
      subscription['queueLimit'] != 4) {
    throw StateError(
      'MCP $label Streamable CORS WAMP batch pub/sub subscribe returned '
      'invalid content.',
    );
  }
  if (!jsonEncode(
    _jsonRpcStructuredContent(
      subscribeBatch[1],
      id: subscribeCatalogId,
      label: 'MCP $label Streamable CORS WAMP batch pub/sub API list',
    ),
  ).contains(_topic)) {
    throw StateError(
      'MCP $label Streamable CORS WAMP batch pub/sub API list missed $_topic.',
    );
  }

  try {
    final serviceTaskId = 'T-$label-streamable-cors-wamp-batch-service-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );
    final publishId = '$label-streamable-cors-wamp-batch-pubsub-publish';
    final pollId = '$label-streamable-cors-wamp-batch-pubsub-poll';
    final publishBatch = await _mcpRawStreamableJsonRpcBatch(
      client,
      endpoint,
      <Map<String, Object?>>[
        _mcpToolCallMessage(
          id: publishId,
          name: 'connectanum.pubsub.publish',
          arguments: {
            'topic': _topic,
            'argumentsKeywords': {
              'taskId': 'T-$label-streamable-cors-wamp-batch-publish',
            },
            'acknowledge': true,
          },
        ),
        _mcpToolCallMessage(
          id: pollId,
          name: 'connectanum.pubsub.poll',
          arguments: {'handle': handle, 'limit': 4},
        ),
      ],
      sessionId: sessionId,
      label: '$label Streamable WAMP pub/sub publish/poll batch',
      bearerToken: bearerToken,
    );
    if (publishBatch.length != 2) {
      throw StateError(
        'MCP $label Streamable CORS WAMP pub/sub publish batch returned '
        '${publishBatch.length} responses.',
      );
    }
    final publication = _jsonRpcStructuredContent(
      publishBatch[0],
      id: publishId,
      label: 'MCP $label Streamable CORS WAMP batch pub/sub publish',
    );
    if (publication['topic'] != _topic ||
        publication['acknowledged'] != true) {
      throw StateError(
        'MCP $label Streamable CORS WAMP batch pub/sub publish returned '
        'invalid content.',
      );
    }
    final eventBatch = _jsonRpcStructuredContent(
      publishBatch[1],
      id: pollId,
      label: 'MCP $label Streamable CORS WAMP batch pub/sub poll',
    );
    if (eventBatch['handle'] != handle ||
        eventBatch['topic'] != _topic ||
        !jsonEncode(eventBatch['events']).contains(serviceTaskId)) {
      throw StateError(
        'MCP $label Streamable CORS WAMP batch pub/sub poll missed routed '
        'event.',
      );
    }
  } finally {
    final unsubscribeId =
        '$label-streamable-cors-wamp-batch-pubsub-unsubscribe';
    final recoveryId =
        '$label-streamable-cors-wamp-batch-pubsub-unsubscribe-api-list';
    final unsubscribeBatch = await _mcpRawStreamableJsonRpcBatch(
      client,
      endpoint,
      <Map<String, Object?>>[
        _mcpToolCallMessage(
          id: unsubscribeId,
          name: 'connectanum.pubsub.unsubscribe',
          arguments: {'handle': handle},
        ),
        _mcpToolCallMessage(
          id: recoveryId,
          name: 'connectanum.api.list',
          arguments: const <String, Object?>{},
        ),
      ],
      sessionId: sessionId,
      label: '$label Streamable WAMP pub/sub unsubscribe batch',
      bearerToken: bearerToken,
    );
    if (unsubscribeBatch.length != 2) {
      throw StateError(
        'MCP $label Streamable CORS WAMP pub/sub unsubscribe batch returned '
        '${unsubscribeBatch.length} responses.',
      );
    }
    final unsubscribe = _jsonRpcStructuredContent(
      unsubscribeBatch[0],
      id: unsubscribeId,
      label: 'MCP $label Streamable CORS WAMP batch pub/sub unsubscribe',
    );
    if (unsubscribe['handle'] != handle ||
        unsubscribe['topic'] != _topic ||
        unsubscribe['unsubscribed'] != true) {
      throw StateError(
        'MCP $label Streamable CORS WAMP batch pub/sub unsubscribe returned '
        'invalid content.',
      );
    }
    if (!jsonEncode(
      _jsonRpcStructuredContent(
        unsubscribeBatch[1],
        id: recoveryId,
        label: 'MCP $label Streamable CORS WAMP batch pub/sub recovery',
      ),
    ).contains(_topic)) {
      throw StateError(
        'MCP $label Streamable CORS WAMP batch recovery missed $_topic.',
      );
    }
  }

  final missingHandle =
      '$label-streamable-cors-wamp-batch-pubsub-missing-handle';
  final missingPollId = '$label-streamable-cors-wamp-batch-pubsub-missing';
  final missingRecoveryId =
      '$label-streamable-cors-wamp-batch-pubsub-missing-api-list';
  final missingPollBatch = await _mcpRawStreamableJsonRpcBatch(
    client,
    endpoint,
    <Map<String, Object?>>[
      _mcpToolCallMessage(
        id: missingPollId,
        name: 'connectanum.pubsub.poll',
        arguments: {'handle': missingHandle, 'limit': 1},
      ),
      _mcpToolCallMessage(
        id: missingRecoveryId,
        name: 'connectanum.api.list',
        arguments: const <String, Object?>{},
      ),
    ],
    sessionId: sessionId,
    label: '$label Streamable WAMP missing pub/sub batch',
    bearerToken: bearerToken,
  );
  if (missingPollBatch.length != 2) {
    throw StateError(
      'MCP $label Streamable CORS WAMP missing pub/sub batch returned '
      '${missingPollBatch.length} responses.',
    );
  }
  _expectMcpToolResultError(
    missingPollBatch[0],
    id: missingPollId,
    messageSubstring: missingHandle,
    label: 'MCP $label Streamable CORS WAMP batch missing pub/sub poll',
  );
  if (!jsonEncode(
    _jsonRpcStructuredContent(
      missingPollBatch[1],
      id: missingRecoveryId,
      label: 'MCP $label Streamable CORS WAMP batch missing recovery',
    ),
  ).contains(_topic)) {
    throw StateError(
      'MCP $label Streamable CORS WAMP batch missing recovery missed $_topic.',
    );
  }
}

Map<String, Object?> _mcpToolCallMessage({
  required String id,
  required String name,
  required Map<String, Object?> arguments,
}) {
  return <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'method': 'tools/call',
    'params': {'name': name, 'arguments': arguments},
  };
}

Future<Map<String, Object?>> _mcpRawStreamableToolCall(
  HttpClient client,
  Uri endpoint, {
  required String sessionId,
  required String id,
  required String name,
  required Map<String, Object?> arguments,
  required String label,
  String? bearerToken,
}) async {
  final response = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': arguments},
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('MCP $label returned ${response.statusCode}.');
  }
  _assertMcpCorsStatefulResponse(response, label: label);
  return _mcpSseJsonRpcPayload(response, id: id, label: label);
}

Future<List<Map<String, Object?>>> _mcpRawStreamableJsonRpcBatch(
  HttpClient client,
  Uri endpoint,
  List<Map<String, Object?>> messages, {
  required String sessionId,
  required String label,
  String? bearerToken,
}) async {
  final response = await _mcpRawPostBody(
    client,
    endpoint,
    body: jsonEncode(messages),
    sessionId: sessionId,
    bearerToken: bearerToken,
  );
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('MCP $label returned ${response.statusCode}.');
  }
  _assertMcpCorsStatefulResponse(response, label: label);
  return _mcpSseJsonRpcBatchPayload(response, label: label);
}

Future<void> _mcpRawStreamablePubSubPollUntil(
  HttpClient client,
  Uri endpoint, {
  required String sessionId,
  required String handle,
  required String label,
  required String expectedTaskId,
  String? bearerToken,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final pollId =
        '$label-streamable-cors-wamp-pubsub-poll-'
        '${DateTime.now().microsecondsSinceEpoch}';
    final poll = await _mcpRawStreamableToolCall(
      client,
      endpoint,
      sessionId: sessionId,
      id: pollId,
      name: 'connectanum.pubsub.poll',
      arguments: {'handle': handle, 'limit': 4},
      label: '$label Streamable WAMP pub/sub poll',
      bearerToken: bearerToken,
    );
    final eventBatch = _jsonRpcStructuredContent(
      poll,
      id: pollId,
      label: 'MCP $label Streamable CORS WAMP pub/sub poll',
    );
    if (eventBatch['handle'] != handle || eventBatch['topic'] != _topic) {
      throw StateError(
        'MCP $label Streamable CORS WAMP pub/sub poll returned invalid '
        'content.',
      );
    }
    if (jsonEncode(eventBatch['events']).contains(expectedTaskId)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'Timed out waiting for MCP $label Streamable CORS WAMP pub/sub event.',
  );
}

Future<_McpRawHttpResponse> _mcpRawJsonPost(
  HttpClient client,
  Uri endpoint,
  Map<String, Object?> message, {
  String? sessionId,
  String? bearerToken,
  Map<String, String> parameterHeaders = const <String, String>{},
  bool includeMethodHeader = true,
  bool includeNameHeader = true,
  String? methodHeader,
  String? nameHeader,
}) async {
  final request = await client.postUrl(endpoint);
  request.headers.set('Origin', _allowedOrigin);
  request.headers.set(
    HttpHeaders.acceptHeader,
    'application/json, text/event-stream',
  );
  request.headers.set(
    'MCP-Protocol-Version',
    McpStreamableHttpClient.latestProtocolVersion,
  );
  final method = message['method'];
  if (method is String) {
    if (includeMethodHeader) {
      request.headers.set('Mcp-Method', methodHeader ?? method);
    }
    final params = message['params'];
    if (params is Map<Object?, Object?>) {
      final name = switch (method) {
        'tools/call' || 'prompts/get' => params['name'],
        'resources/read' => params['uri'],
        _ => null,
      };
      if (includeNameHeader && name is String && name.isNotEmpty) {
        request.headers.set('Mcp-Name', nameHeader ?? name);
      }
    }
  }
  if (sessionId != null) {
    request.headers.set('MCP-Session-Id', sessionId);
  }
  for (final entry in parameterHeaders.entries) {
    request.headers.set('Mcp-Param-${entry.key}', entry.value);
  }
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  request.headers.contentType = ContentType.json;
  final body = utf8.encode(jsonEncode(message));
  request.contentLength = body.length;
  request.add(body);
  return _mcpRawResponseFrom(await request.close());
}

Future<_McpRawHttpResponse> _mcpRawPostBody(
  HttpClient client,
  Uri endpoint, {
  required String body,
  String accept = 'application/json, text/event-stream',
  String contentType = 'application/json',
  String? sessionId,
  String? bearerToken,
}) async {
  final request = await client.postUrl(endpoint);
  request.headers.set('Origin', _allowedOrigin);
  request.headers.set(HttpHeaders.acceptHeader, accept);
  request.headers.set(
    'MCP-Protocol-Version',
    McpStreamableHttpClient.latestProtocolVersion,
  );
  request.headers.set(HttpHeaders.contentTypeHeader, contentType);
  if (sessionId != null) {
    request.headers.set('MCP-Session-Id', sessionId);
  }
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  final encodedBody = utf8.encode(body);
  request.contentLength = encodedBody.length;
  request.add(encodedBody);
  return _mcpRawResponseFrom(await request.close());
}

Future<_McpRawHttpResponse> _mcpRawMcpRequest(
  HttpClient client,
  Uri endpoint,
  String method, {
  String accept = 'application/json, text/event-stream',
  String? bearerToken,
  Map<String, Object?>? jsonBody,
}) async {
  final request = await client.openUrl(method, endpoint);
  request.headers.set('Origin', _allowedOrigin);
  request.headers.set(HttpHeaders.acceptHeader, accept);
  request.headers.set(
    'MCP-Protocol-Version',
    McpStreamableHttpClient.latestProtocolVersion,
  );
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  if (jsonBody != null) {
    request.headers.contentType = ContentType.json;
    final body = utf8.encode(jsonEncode(jsonBody));
    request.contentLength = body.length;
    request.add(body);
  }
  return _mcpRawResponseFrom(await request.close());
}

Future<_McpRawHttpResponse> _mcpRawSessionRequest(
  HttpClient client,
  Uri endpoint,
  String method, {
  required String sessionId,
  String? bearerToken,
  String? lastEventId,
}) async {
  final request = await client.openUrl(method, endpoint);
  request.headers.set('Origin', _allowedOrigin);
  request.headers.set(
    HttpHeaders.acceptHeader,
    method == 'GET' ? 'text/event-stream' : 'application/json, text/event-stream',
  );
  request.headers.set(
    'MCP-Protocol-Version',
    McpStreamableHttpClient.latestProtocolVersion,
  );
  request.headers.set('MCP-Session-Id', sessionId);
  if (lastEventId != null) {
    request.headers.set('Last-Event-ID', lastEventId);
  }
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  return _mcpRawResponseFrom(await request.close());
}

Future<_McpRawHttpResponse> _mcpRawPollUntilToolListChanged(
  HttpClient client,
  Uri endpoint, {
  required String sessionId,
  required String label,
  String? bearerToken,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final response = await _mcpRawSessionRequest(
      client,
      endpoint,
      'GET',
      sessionId: sessionId,
      bearerToken: bearerToken,
    );
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'MCP $label Streamable GET/SSE CORS poll returned '
        '${response.statusCode}.',
      );
    }
    _assertMcpCorsStatefulResponse(
      response,
      label: '$label Streamable GET/SSE poll',
    );
    _assertMcpSseResponse(response, label: '$label Streamable GET/SSE poll');
    if (response.body.contains('notifications/tools/list_changed')) {
      return response;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for MCP $label Streamable CORS poll.');
}

void _assertMcpCorsErrorResponse(
  _McpRawHttpResponse response, {
  required int expectedStatus,
  required String label,
  String? sessionId,
  bool expectNoSession = false,
  String? bodyContains,
}) {
  if (response.statusCode != expectedStatus) {
    throw StateError(
      'MCP $label returned ${response.statusCode} instead of '
      '$expectedStatus: ${response.body}',
    );
  }
  _assertMcpCorsStatefulResponse(response, label: label);
  final responseSessionId = response.header('mcp-session-id');
  if (sessionId != null && responseSessionId != sessionId) {
    throw StateError('MCP $label returned the wrong session id.');
  }
  if (expectNoSession && responseSessionId != null) {
    throw StateError('MCP $label created Streamable session state.');
  }
  _assertHeaderContains(
    response,
    'content-type',
    'application/json',
    label: label,
  );
  if (bodyContains != null &&
      !response.body.toLowerCase().contains(bodyContains.toLowerCase())) {
    throw StateError('MCP $label response did not mention $bodyContains.');
  }
}

void _assertMcpCorsStatefulResponse(
  _McpRawHttpResponse response, {
  required String label,
}) {
  _assertCorsAllowed(response, _allowedOrigin, label: label);
  _assertHeaderContains(
    response,
    'access-control-expose-headers',
    'mcp-session-id',
    label: '$label exposed headers',
  );
  _assertHeaderContains(
    response,
    'access-control-expose-headers',
    'mcp-protocol-version',
    label: '$label exposed headers',
  );
  if (response.header('mcp-protocol-version') == null) {
    throw StateError('$label did not return MCP-Protocol-Version.');
  }
}

void _assertMcpSseResponse(
  _McpRawHttpResponse response, {
  required String label,
}) {
  _assertHeaderContains(
    response,
    'content-type',
    'text/event-stream',
    label: label,
  );
}

Map<String, Object?> _mcpSseJsonRpcPayload(
  _McpRawHttpResponse response, {
  required Object? id,
  required String label,
}) {
  _assertMcpSseResponse(response, label: label);
  final data = response.body
      .split('\n')
      .where((line) => line.startsWith('data:'))
      .map((line) => line.substring('data:'.length).trimLeft())
      .join('\n');
  if (data.isEmpty) {
    throw StateError('$label SSE response did not contain JSON-RPC data.');
  }
  final payload = _jsonObjectFrom(jsonDecode(data), label: '$label SSE data');
  if (payload['id'] != id) {
    throw StateError('$label SSE response returned wrong id.');
  }
  return payload;
}

List<Map<String, Object?>> _mcpSseJsonRpcBatchPayload(
  _McpRawHttpResponse response, {
  required String label,
}) {
  _assertMcpSseResponse(response, label: label);
  final data = response.body
      .split('\n')
      .where((line) => line.startsWith('data:'))
      .map((line) => line.substring('data:'.length).trimLeft())
      .join('\n');
  if (data.isEmpty) {
    throw StateError('$label SSE response did not contain JSON-RPC data.');
  }
  final payload = jsonDecode(data);
  if (payload is! List) {
    throw StateError('$label SSE response did not contain a JSON-RPC batch.');
  }
  final responses = <Map<String, Object?>>[];
  for (final item in payload) {
    final responsePayload = _jsonObjectFrom(
      item,
      label: '$label SSE batch response',
    );
    if (responsePayload['jsonrpc'] != '2.0') {
      throw StateError('$label SSE batch response was not JSON-RPC.');
    }
    responses.add(responsePayload);
  }
  return responses;
}

String? _mcpFirstSseEventId(
  _McpRawHttpResponse response, {
  required String label,
}) {
  _assertMcpSseResponse(response, label: label);
  for (final line in response.body.split('\n')) {
    if (line.startsWith('id:')) {
      return line.substring('id:'.length).trim();
    }
  }
  return null;
}

void _assertCorsAllowed(
  _McpRawHttpResponse response,
  String origin, {
  required String label,
}) {
  if (response.header('access-control-allow-origin') != origin) {
    throw StateError(
      '$label did not echo the allowed Origin. Headers: ${response.headers}',
    );
  }
  _assertHeaderContains(response, 'vary', 'origin', label: '$label vary');
}

void _assertHeaderContains(
  _McpRawHttpResponse response,
  String headerName,
  String expected, {
  required String label,
}) {
  final value = response.header(headerName)?.toLowerCase();
  if (value == null || !value.contains(expected.toLowerCase())) {
    throw StateError('$label missing $expected in $headerName.');
  }
}

Future<_McpRawHttpResponse> _mcpRawResponseFrom(
  HttpClientResponse response,
) async {
  final headers = <String, List<String>>{};
  response.headers.forEach((name, values) {
    headers[name.toLowerCase()] = List<String>.unmodifiable(values);
  });
  final body = await utf8.decodeStream(response);
  return _McpRawHttpResponse(response.statusCode, headers, body);
}

final class _McpRawHttpResponse {
  const _McpRawHttpResponse(this.statusCode, this.headers, this.body);

  final int statusCode;
  final Map<String, List<String>> headers;
  final String body;

  String? header(String name) => headers[name.toLowerCase()]?.join(', ');
}

Future<void> _assertSecureMcpRejectsBearer(
  RouterBinding binding,
  String bearerToken, {
  required String acceptedMessage,
  Uri? endpoint,
}) async {
  final client = McpStreamableHttpClient.withBearerToken(
    endpoint ?? _mcpEndpoint(binding, secure: true),
    bearerToken,
  );
  try {
    await _assertSecureMcpUnauthorizedCoverage(
      client,
      acceptedMessage: acceptedMessage,
    );
  } finally {
    client.close();
  }
}

Future<ConnectanumHttpAuthGrant> _issueTicketHttpGrant(
  RouterBinding binding, {
  String authId = _ticketAuthId,
  String ticket = _ticketSecret,
}) async {
  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  try {
    return await authClient.issueTicketToken(
      realm: _realm,
      authId: authId,
      ticket: ticket,
      headers: const <String, String>{
        'x-consumer-trace': 'ticket-auth-grant',
      },
    );
  } finally {
    authClient.close(force: true);
  }
}

Future<ConnectanumHttpAuthGrant> _issueWampCraHttpGrant(
  RouterBinding binding,
) async {
  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  try {
    return await authClient.issueWampCraToken(
      realm: _realm,
      authId: _wampCraAuthId,
      secret: _wampCraSecret,
      headers: const <String, String>{
        'x-consumer-trace': 'wampcra-auth-grant',
      },
    );
  } finally {
    authClient.close(force: true);
  }
}

Future<ConnectanumHttpAuthGrant> _issueScramHttpGrant(
  RouterBinding binding,
) async {
  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  try {
    return await authClient.issueScramToken(
      realm: _realm,
      authId: _scramAuthId,
      secret: _scramSecret,
      headers: const <String, String>{
        'x-consumer-trace': 'scram-auth-grant',
      },
    );
  } finally {
    authClient.close(force: true);
  }
}

Future<void> _smokeChallengeHttpAuthMcpGrants(
  RouterBinding binding,
  RouterSession serviceSession,
) async {
  await _expectRejectedChallengeHttpAuthGrant(
    binding,
    authMethod: 'wampcra',
  );
  final wampCraGrant = await _issueWampCraHttpGrant(binding);
  _expectHttpAuthGrant(
    wampCraGrant,
    authId: _wampCraAuthId,
    authMethod: 'wampcra',
    authProvider: 'consumer-cra',
  );
  await _smokeSecureMcpGrant(
    binding,
    wampCraGrant,
    label: 'secure-wampcra',
  );
  await _smokeSecureMcpRefreshAndRevocation(
    binding,
    serviceSession,
    wampCraGrant,
    label: 'secure-wampcra-lifecycle',
  );

  await _expectRejectedChallengeHttpAuthGrant(
    binding,
    authMethod: 'scram',
  );
  final scramGrant = await _issueScramHttpGrant(binding);
  _expectHttpAuthGrant(
    scramGrant,
    authId: _scramAuthId,
    authMethod: 'scram',
    authProvider: 'consumer-scram',
  );
  await _smokeSecureMcpGrant(
    binding,
    scramGrant,
    label: 'secure-scram',
  );
  await _smokeSecureMcpRefreshAndRevocation(
    binding,
    serviceSession,
    scramGrant,
    label: 'secure-scram-lifecycle',
  );
}

Future<void> _expectRejectedChallengeHttpAuthGrant(
  RouterBinding binding, {
  required String authMethod,
}) async {
  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  try {
    if (authMethod == 'wampcra') {
      await authClient.issueWampCraToken(
        realm: _realm,
        authId: _wampCraAuthId,
        secret: 'wrong-$_wampCraSecret',
        headers: const <String, String>{
          'x-consumer-trace': 'wampcra-auth-rejection',
        },
      );
    } else if (authMethod == 'scram') {
      await authClient.issueScramToken(
        realm: _realm,
        authId: _scramAuthId,
        secret: 'wrong-$_scramSecret',
        headers: const <String, String>{
          'x-consumer-trace': 'scram-auth-rejection',
        },
      );
    } else {
      throw ArgumentError.value(authMethod, 'authMethod');
    }
  } on ConnectanumHttpAuthException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'HTTP auth bridge rejected $authMethod with ${error.statusCode} '
        'instead of ${HttpStatus.unauthorized}.',
      );
    }
    final errorText = jsonEncode(error.error ?? error.body);
    if (errorText.contains('access_token') ||
        errorText.contains('refresh_token')) {
      throw StateError(
        'HTTP auth bridge rejection for $authMethod leaked token material.',
      );
    }
    return;
  } finally {
    authClient.close(force: true);
  }
  throw StateError('HTTP auth bridge accepted invalid $authMethod credentials.');
}

void _expectHttpAuthGrant(
  ConnectanumHttpAuthGrant grant, {
  required String authId,
  required String authMethod,
  required String authProvider,
}) {
  if (grant.realm != _realm ||
      grant.authId != authId ||
      grant.authRole != 'member' ||
      grant.authMethod != authMethod ||
      grant.authProvider != authProvider) {
    throw StateError(
      'HTTP auth bridge grant for $authMethod returned unexpected '
      'principal metadata.',
    );
  }
  if (grant.accessToken.isEmpty ||
      grant.tokenType.toLowerCase() != 'bearer' ||
      grant.refreshToken == null ||
      grant.refreshToken!.isEmpty) {
    throw StateError('HTTP auth bridge grant for $authMethod is incomplete.');
  }
}

Future<void> _smokeSecureMcpGrant(
  RouterBinding binding,
  ConnectanumHttpAuthGrant grant, {
  required String label,
}) async {
  final directClient = McpStreamableHttpClient.withAuthGrant(
    _mcpEndpoint(binding, secure: true),
    grant,
  );
  McpStreamableHttpClient? streamableClient;
  try {
    await _expectPagedToolCatalog(
      directClient,
      label: '$label-direct-grant',
      directJson: true,
    );
    final directResult = await directClient.callConnectanumToolDirect(
      _procedure,
      id: '$label-direct-call',
      arguments: {
        'taskId': 'T-$label-direct',
        'note': _headerWrappedNote,
      },
    );
    _expectDirectToolPayload(
      directResult,
      taskId: 'T-$label-direct',
      label: '$label direct grant',
    );
    if (directClient.sessionId != null || directClient.lastEventId != null) {
      throw StateError('Secure direct MCP grant $label captured session state.');
    }

    streamableClient = await _openSecureStreamableSession(
      binding,
      grant,
      label: label,
    );
    await _expectPagedToolCatalog(
      streamableClient,
      label: '$label-streamable-grant',
      directJson: false,
    );
    final streamableResult = await streamableClient.callTool(
      _procedure,
      id: '$label-streamable-call',
      arguments: {
        'taskId': 'T-$label-streamable',
        'note': _headerWrappedNote,
      },
    );
    final streamableResultJson = jsonEncode(streamableResult);
    if (!streamableResultJson.contains('T-$label-streamable') ||
        !streamableResultJson.contains(_headerWrappedNote)) {
      throw StateError(
        'Secure Streamable MCP grant $label returned unexpected payload.',
      );
    }
    await streamableClient.deleteSession();
  } finally {
    directClient.close();
    streamableClient?.close();
  }
}

Future<void> _smokeLowercaseBearerMcpClients(
  RouterBinding binding,
  ConnectanumHttpAuthGrant grant,
) async {
  final headers = <String, String>{
    HttpHeaders.authorizationHeader: 'bearer ${grant.accessToken}',
  };
  final directClient = McpStreamableHttpClient(
    _mcpEndpoint(binding, secure: true),
    headers: headers,
  );
  final jsonPostClient = McpStreamableHttpClient(
    _secureJsonPostMcpEndpoint(binding),
    headers: headers,
  );
  final streamableClient = McpStreamableHttpClient(
    _mcpEndpoint(binding, secure: true),
    headers: headers,
  );

  try {
    await _expectPagedToolCatalog(
      directClient,
      label: 'secure-lowercase-bearer',
      directJson: true,
    );
    final directResult = await directClient.callConnectanumToolDirect(
      _procedure,
      id: 'secure-lowercase-bearer-direct-call',
      arguments: const <String, Object?>{
        'taskId': 'T-secure-lowercase-bearer-direct',
        'note': _headerWrappedNote,
      },
      headers: const <String, String>{
        'x-consumer-trace': 'secure-lowercase-bearer-direct-call',
      },
    );
    _expectDirectToolPayload(
      directResult,
      taskId: 'T-secure-lowercase-bearer-direct',
      label: 'secure lowercase bearer direct JSON',
    );
    if (directClient.sessionId != null || directClient.lastEventId != null) {
      throw StateError(
        'Secure lowercase bearer direct JSON captured Streamable state.',
      );
    }

    await _expectPagedToolCatalog(
      jsonPostClient,
      label: 'secure-json-post-lowercase-bearer',
      directJson: true,
    );
    if (jsonPostClient.sessionId != null ||
        jsonPostClient.lastEventId != null) {
      throw StateError(
        'Secure lowercase bearer JSON-response direct access captured '
        'Streamable state.',
      );
    }

    await streamableClient.initialize(
      id: 'secure-lowercase-bearer-streamable-initialize',
      clientInfo: const <String, Object?>{
        'name': 'connectanum_consumer_lowercase_bearer_smoke',
        'version': '0.1.0',
      },
      headers: const <String, String>{
        'x-consumer-trace': 'secure-lowercase-bearer-streamable-initialize',
      },
    );
    await streamableClient.notifyInitialized(
      headers: const <String, String>{
        'x-consumer-trace': 'secure-lowercase-bearer-streamable-initialized',
      },
    );
    final sessionId = streamableClient.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError(
        'Secure lowercase bearer Streamable MCP session did not initialize.',
      );
    }
    await _expectPagedToolCatalog(
      streamableClient,
      label: 'secure-lowercase-bearer',
      directJson: false,
    );
    final streamableResult = await streamableClient.callTool(
      _procedure,
      id: 'secure-lowercase-bearer-streamable-call',
      arguments: const <String, Object?>{
        'taskId': 'T-secure-lowercase-bearer-streamable',
        'note': _headerWrappedNote,
      },
      headers: const <String, String>{
        'x-consumer-trace': 'secure-lowercase-bearer-streamable-call',
      },
    );
    final streamableJson = jsonEncode(streamableResult);
    if (!streamableJson.contains('T-secure-lowercase-bearer-streamable') ||
        !streamableJson.contains(_headerWrappedNote)) {
      throw StateError(
        'Secure lowercase bearer Streamable MCP returned unexpected payload.',
      );
    }
    await streamableClient.deleteSession();
  } finally {
    directClient.close();
    jsonPostClient.close();
    streamableClient.close();
  }
}

Future<void> _smokeStreamableSessionReuseIsolation(
  RouterBinding binding,
  RouterSession serviceSession,
  ConnectanumHttpAuthGrant primaryGrant,
  ConnectanumHttpAuthGrant otherGrant,
) async {
  final primaryClient = await _openSecureStreamableSession(
    binding,
    primaryGrant,
    label: 'secure-reuse-primary',
  );
  final otherPrincipalClient = McpStreamableHttpClient.withBearerToken(
    _mcpEndpoint(binding, secure: true),
    otherGrant.accessToken,
  );
  final publicRouteClient = McpStreamableHttpClient(_mcpEndpoint(binding));
  final bearerlessSecureClient = McpStreamableHttpClient(
    _mcpEndpoint(binding, secure: true),
  );
  final unknownBearerClient = McpStreamableHttpClient.withBearerToken(
    _mcpEndpoint(binding, secure: true),
    _unknownAccessToken,
  );

  try {
    await _expectPagedToolCatalog(
      primaryClient,
      label: 'secure-reuse-primary',
      directJson: false,
    );

    final sessionId = primaryClient.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Primary secure Streamable MCP session has no id.');
    }
    final lastEventId = primaryClient.lastEventId;

    await _assertStreamableSessionReuseRejectedAcrossMethods(
      otherPrincipalClient,
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: 'other bearer principal',
    );
    await _assertStreamableIndependentPrincipalSession(
      otherPrincipalClient,
      serviceSession: serviceSession,
      ownerSessionId: sessionId,
      label: 'other bearer principal',
    );

    await _assertStreamableSessionReuseRejectedAcrossMethods(
      publicRouteClient,
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: 'public route',
    );

    await _assertStreamableSessionReuseRequiresBearerAcrossMethods(
      bearerlessSecureClient,
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: 'secure bearerless reused session',
    );

    unknownBearerClient.sessionId = sessionId;
    unknownBearerClient.lastEventId = lastEventId;
    await _assertActiveStreamableSessionRejectsBearer(
      unknownBearerClient,
      label: 'secure-reuse-unknown-bearer',
      acceptedMessage:
          'Streamable MCP session accepted an unknown access token.',
    );

    await _expectPagedToolCatalog(
      primaryClient,
      label: 'secure-reuse-primary-after-rejected-reuse',
      directJson: false,
    );
    if (primaryClient.sessionId != sessionId) {
      throw StateError(
        'Rejected Streamable MCP session reuse changed the primary session id.',
      );
    }

    await primaryClient.deleteSession();
  } finally {
    primaryClient.close();
    otherPrincipalClient.close();
    publicRouteClient.close();
    bearerlessSecureClient.close();
    unknownBearerClient.close();
  }
}

Future<void> _assertStreamableIndependentPrincipalSession(
  McpStreamableHttpClient client, {
  required RouterSession serviceSession,
  required String ownerSessionId,
  required String label,
}) async {
  await _expectPagedToolCatalog(
    client,
    label: '$label-independent-direct',
    directJson: true,
  );
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Secure Streamable MCP $label direct tools/list changed session state.',
    );
  }
  await _smokeDirectToolApi(client, label: '$label-independent');
  await _smokeGenericDirectJsonRpcPubSub(
    client,
    serviceSession,
    label: '$label-independent',
  );
  await _smokeDirectWampMetaHelpers(
    client,
    serviceSession,
    label: '$label-independent',
  );
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Secure Streamable MCP $label direct WAMP meta/pubsub changed session state.',
    );
  }

  await client.initialize(
    id: '$label-independent-initialize',
    clientInfo: const <String, Object?>{
      'name': 'connectanum_consumer_independent_streamable_principal_smoke',
      'version': '0.1.0',
    },
  );
  await client.notifyInitialized();
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Secure Streamable MCP $label did not create a session.');
  }
  if (sessionId == ownerSessionId) {
    throw StateError(
      'Secure Streamable MCP $label reused another principal session id.',
    );
  }

  await _expectPagedToolCatalog(
    client,
    label: '$label-independent',
    directJson: false,
  );
  if (client.sessionId != sessionId) {
    throw StateError(
      'Secure Streamable MCP $label independent tools/list changed session id.',
    );
  }
  final lastEventId = client.lastEventId;
  if (lastEventId == null || !lastEventId.startsWith('$sessionId:')) {
    throw StateError(
      'Secure Streamable MCP $label independent tools/list did not capture '
      'a session-scoped POST/SSE cursor.',
    );
  }

  final subscription = await client.subscribeWampTopic(
    _topic,
    id: '$label-independent-streamable-subscribe',
    queueLimit: 4,
  );
  try {
    final taskId = 'T-$label-independent-streamable-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': taskId},
      options: PublishOptions(acknowledge: true),
    );
    final events = await _pollMcpEventsUntil(client, subscription.handle);
    if (!jsonEncode(events.events).contains(taskId)) {
      throw StateError(
        'Secure Streamable MCP $label independent pub/sub missed service '
        'event.',
      );
    }
  } finally {
    await client.unsubscribeWampTopic(
      subscription.handle,
      id: '$label-independent-streamable-unsubscribe',
    );
  }
  final pubSubEventId = client.lastEventId;
  if (client.sessionId != sessionId ||
      pubSubEventId == null ||
      !pubSubEventId.startsWith('$sessionId:') ||
      pubSubEventId == lastEventId) {
    throw StateError(
      'Secure Streamable MCP $label independent pub/sub did not stay on the '
      'new session cursor.',
    );
  }

  await client.deleteSession();
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Secure Streamable MCP $label independent DELETE left session state.',
    );
  }
}

Future<void> _assertStreamableSessionReuseRequiresBearerAcrossMethods(
  McpStreamableHttpClient client, {
  required String sessionId,
  String? lastEventId,
  required String label,
}) async {
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': '$label-session-batch-tools',
          'method': 'tools/list',
          'params': {},
        },
        {
          'jsonrpc': '2.0',
          'id': '$label-session-batch-resources',
          'method': 'resources/list',
          'params': {},
        },
      ]);
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label batch tools/resources',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': '$label-session-batch-api-list',
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.api.list',
            'arguments': {'kind': 'topic'},
          },
        },
        {
          'jsonrpc': '2.0',
          'id': '$label-session-batch-pubsub-subscribe',
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.subscribe',
            'arguments': {'topic': _topic, 'queueLimit': 1},
          },
        },
      ]);
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label batch WAMP meta/pubsub',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.notifyInitialized();
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label notification',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.listTools(id: '$label-tools');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label tools/list',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.callTool(
        _procedure,
        id: '$label-tool-call',
        arguments: {'taskId': 'T-$label-tool-call'},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label tools/call',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.listResources(id: '$label-resources');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label resources/list',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.readResource(_resourceUri, id: '$label-resource-read');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label resources/read',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.listResourceTemplates(id: '$label-resource-templates');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label resources/templates/list',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.listPrompts(id: '$label-prompts');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label prompts/list',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.getPrompt(
        _promptName,
        id: '$label-prompt-get',
        arguments: {'taskId': 'T-$label-prompt-get'},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label prompts/get',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.poll();
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label poll',
  );
  await _expectSecureMcpUnauthorizedWithSession(
    client,
    () async {
      await client.deleteSession();
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label delete',
  );
}

Future<void> _expectSecureMcpUnauthorizedWithSession(
  McpStreamableHttpClient client,
  Future<void> Function() operation, {
  required String sessionId,
  String? lastEventId,
  required String label,
}) async {
  client.sessionId = sessionId;
  client.lastEventId = lastEventId;
  await _expectSecureMcpUnauthorized(
    client,
    label: label,
    operation: operation,
  );
}

Future<void> _assertStreamableSessionReuseRejectedAcrossMethods(
  McpStreamableHttpClient client, {
  required String sessionId,
  String? lastEventId,
  required String label,
}) async {
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': '$label-session-batch-tools',
          'method': 'tools/list',
          'params': {},
        },
        {
          'jsonrpc': '2.0',
          'id': '$label-session-batch-resources',
          'method': 'resources/list',
          'params': {},
        },
      ]);
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label batch tools/resources',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': '$label-session-batch-api-list',
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.api.list',
            'arguments': {'kind': 'topic'},
          },
        },
        {
          'jsonrpc': '2.0',
          'id': '$label-session-batch-pubsub-subscribe',
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.subscribe',
            'arguments': {'topic': _topic, 'queueLimit': 1},
          },
        },
      ]);
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label batch WAMP meta/pubsub',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.notifyInitialized();
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label notification',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.listTools(id: '$label-tools');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label tools/list',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.callTool(
        _procedure,
        id: '$label-tool-call',
        arguments: {'taskId': 'T-$label-tool-call'},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label tools/call',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.listResources(id: '$label-resources');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label resources/list',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.readResource(_resourceUri, id: '$label-resource-read');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label resources/read',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.listResourceTemplates(id: '$label-resource-templates');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label resources/templates/list',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.listPrompts(id: '$label-prompts');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label prompts/list',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.getPrompt(
        _promptName,
        id: '$label-prompt-get',
        arguments: {'taskId': 'T-$label-prompt-get'},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label prompts/get',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.poll();
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label poll',
  );
  await _assertStreamableSessionReuseRejectedWithSession(
    client,
    () async {
      await client.deleteSession();
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    label: '$label delete',
  );
}

Future<void> _assertStreamableSessionReuseRejectedWithSession(
  McpStreamableHttpClient client,
  Future<void> Function() request, {
  required String sessionId,
  String? lastEventId,
  required String label,
}) async {
  client.sessionId = sessionId;
  client.lastEventId = lastEventId;
  await _assertStreamableSessionReuseRejected(
    client,
    request,
    label: label,
  );
}

Future<void> _assertStreamableSessionReuseRejected(
  McpStreamableHttpClient client,
  Future<void> Function() request, {
  required String label,
}) async {
  try {
    await request();
    throw StateError('Streamable MCP accepted stale session reuse via $label.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.notFound) {
      throw StateError(
        'Streamable MCP stale session reuse via $label returned '
        '${error.statusCode} instead of ${HttpStatus.notFound}.',
      );
    }
  }

  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Streamable MCP stale session reuse via $label did not clear '
      'client session state.',
    );
  }
}

Future<void> _assertHttpRefreshRejected(
  RouterBinding binding,
  String refreshToken, {
  required String acceptedMessage,
}) async {
  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  try {
    await authClient.refreshToken(
      refreshToken,
      headers: const <String, String>{
        'x-consumer-trace': 'refresh-rejection',
      },
    );
    throw StateError(acceptedMessage);
  } on ConnectanumHttpAuthException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'HTTP auth bridge returned ${error.statusCode} instead of '
        '${HttpStatus.unauthorized} for a rejected refresh token.',
      );
    }
  } finally {
    authClient.close(force: true);
  }
}

Future<void> _smokeSecureMcpRefreshAndRevocation(
  RouterBinding binding,
  RouterSession serviceSession,
  ConnectanumHttpAuthGrant grant, {
  required String label,
}) async {
  final refreshToken = grant.refreshToken;
  if (refreshToken == null || refreshToken.isEmpty) {
    throw StateError('HTTP auth bridge did not issue a refresh token.');
  }

  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  McpStreamableHttpClient? rotatedSessionClient;
  McpStreamableHttpClient? refreshedClient;
  McpStreamableHttpClient? revokedSessionClient;
  try {
    rotatedSessionClient = await _openSecureStreamableSession(
      binding,
      grant,
      label: '$label-rotated',
    );

    final refreshed = await authClient.refreshToken(
      refreshToken,
      headers: <String, String>{
        'x-consumer-trace': '$label-refresh',
      },
    );
    _expectRefreshedHttpAuthGrant(refreshed, grant, label: label);
    if (refreshed.accessToken == grant.accessToken) {
      throw StateError(
        'HTTP auth bridge refresh for $label reused the access token.',
      );
    }
    final rotatedRefreshToken = refreshed.refreshToken;
    if (rotatedRefreshToken == null || rotatedRefreshToken.isEmpty) {
      throw StateError(
        'HTTP auth bridge refresh for $label did not rotate refresh token.',
      );
    }
    if (rotatedRefreshToken == refreshToken) {
      throw StateError(
        'HTTP auth bridge refresh for $label reused the refresh token.',
      );
    }

    await _assertActiveStreamableSessionRejectsBearer(
      rotatedSessionClient,
      label: '$label-rotated',
      acceptedMessage:
          'Streamable MCP session accepted a rotated $label access token.',
    );
    rotatedSessionClient.close();
    rotatedSessionClient = null;
    await _assertSecureMcpRejectsBearer(
      binding,
      grant.accessToken,
      acceptedMessage:
          'Bearer-protected MCP endpoint accepted a rotated $label access token.',
    );
    await _assertHttpRefreshRejected(
      binding,
      refreshToken,
      acceptedMessage:
          'HTTP auth bridge accepted a rotated $label refresh token.',
    );

    refreshedClient = McpStreamableHttpClient.withAuthGrant(
      _mcpEndpoint(binding, secure: true),
      refreshed,
    );
    await _smokeDirectJson(
      refreshedClient,
      serviceSession,
      label: '$label-refreshed',
    );
    await _smokeStreamableMcp(
      refreshedClient,
      serviceSession,
      label: '$label-refreshed',
    );

    revokedSessionClient = await _openSecureStreamableSession(
      binding,
      refreshed,
      label: '$label-revoked',
    );
    await authClient.revokeToken(
      rotatedRefreshToken,
      tokenTypeHint: 'refresh_token',
      headers: <String, String>{
        'x-consumer-trace': '$label-revoke',
      },
    );
    await _assertActiveStreamableSessionRejectsBearer(
      revokedSessionClient,
      label: '$label-revoked',
      acceptedMessage:
          'Streamable MCP session accepted a revoked $label access token.',
    );
    revokedSessionClient.close();
    revokedSessionClient = null;
    await _assertSecureMcpRejectsBearer(
      binding,
      refreshed.accessToken,
      acceptedMessage:
          'Bearer-protected MCP endpoint accepted a revoked $label access token.',
    );
    await _assertHttpRefreshRejected(
      binding,
      rotatedRefreshToken,
      acceptedMessage:
          'HTTP auth bridge accepted a revoked $label refresh token.',
    );
  } finally {
    rotatedSessionClient?.close();
    refreshedClient?.close();
    revokedSessionClient?.close();
    authClient.close(force: true);
  }
}

void _expectRefreshedHttpAuthGrant(
  ConnectanumHttpAuthGrant refreshed,
  ConnectanumHttpAuthGrant original, {
  required String label,
}) {
  if (refreshed.realm != original.realm ||
      refreshed.authId != original.authId ||
      refreshed.authRole != original.authRole ||
      refreshed.authMethod != original.authMethod ||
      refreshed.authProvider != original.authProvider) {
    throw StateError(
      'HTTP auth bridge refresh for $label returned unexpected principal '
      'metadata.',
    );
  }
  if (refreshed.accessToken.isEmpty ||
      refreshed.tokenType.toLowerCase() != 'bearer' ||
      refreshed.refreshToken == null ||
      refreshed.refreshToken!.isEmpty) {
    throw StateError('HTTP auth bridge refresh for $label is incomplete.');
  }
}

Future<McpStreamableHttpClient> _openSecureStreamableSession(
  RouterBinding binding,
  ConnectanumHttpAuthGrant grant, {
  required String label,
}) async {
  final client = McpStreamableHttpClient.withAuthGrant(
    _mcpEndpoint(binding, secure: true),
    grant,
  );
  try {
    await client.initialize(id: '$label-active-session-initialize');
    await client.notifyInitialized();
    final sessionId = client.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Secure Streamable MCP session did not initialize.');
    }
    return client;
  } catch (_) {
    client.close();
    rethrow;
  }
}

Future<void> _assertActiveStreamableSessionRejectsBearer(
  McpStreamableHttpClient client, {
  required String label,
  required String acceptedMessage,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Secure Streamable MCP rejection smoke has no session.');
  }
  final lastEventId = client.lastEventId;

  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.pingDirect(
        id: '$label-rejected-direct-ping',
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON ping',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.notificationDirect(
        'notifications/initialized',
        params: const <String, Object?>{},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON notifications/initialized',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.listToolsDirect(
        id: '$label-rejected-direct-tools',
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON tools/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.callToolDirect(
        _procedure,
        id: '$label-rejected-direct-tool-call',
        arguments: {'taskId': 'T-$label-rejected-direct-tool-call'},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON tools/call',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.postBatchDirect(
        [
          {
            'jsonrpc': '2.0',
            'id': '$label-rejected-direct-batch-tools',
            'method': 'tools/list',
            'params': {},
          },
          {
            'jsonrpc': '2.0',
            'id': '$label-rejected-direct-batch-tool-call',
            'method': 'tools/call',
            'params': {
              'name': _procedure,
              'arguments': {'taskId': 'T-$label-rejected-direct-batch-tool-call'},
            },
          },
        ],
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON batch tools/list and tools/call',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.postBatchDirect(
        [
          {
            'jsonrpc': '2.0',
            'id': '$label-rejected-direct-batch-api',
            'method': 'connectanum.api.list',
            'params': {'kind': 'procedure'},
          },
          {
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
            'params': {},
          },
        ],
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON batch connectanum.api.list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.requestDirect(
        'connectanum.api.list',
        id: '$label-rejected-direct-api',
        params: {'kind': 'procedure'},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON connectanum.api.list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.requestDirect(
        'connectanum.pubsub.subscribe',
        id: '$label-rejected-direct-pubsub-subscribe',
        params: {'topic': _topic, 'queueLimit': 1},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON connectanum.pubsub.subscribe',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.postBatchDirect(
        [
          {
            'jsonrpc': '2.0',
            'id': '$label-rejected-direct-batch-api-list',
            'method': 'connectanum.api.list',
            'params': {'kind': 'topic'},
          },
          {
            'jsonrpc': '2.0',
            'id': '$label-rejected-direct-batch-pubsub-subscribe',
            'method': 'connectanum.pubsub.subscribe',
            'params': {'topic': _topic, 'queueLimit': 1},
          },
        ],
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON batch WAMP meta/pubsub',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.listResourcesDirect(
        id: '$label-rejected-direct-resources',
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON resources/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.readResourceDirect(
        _resourceUri,
        id: '$label-rejected-direct-resource-read',
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON resources/read',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.listResourceTemplatesDirect(
        id: '$label-rejected-direct-resource-templates',
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON resources/templates/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.listPromptsDirect(
        id: '$label-rejected-direct-prompts',
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON prompts/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.getPromptDirect(
        _promptName,
        id: '$label-rejected-direct-prompt-get',
        arguments: {'taskId': 'T-$label-rejected-direct-prompt-get'},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON prompts/get',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': '$label-rejected-session-batch-tools',
          'method': 'tools/list',
          'params': {},
        },
        {
          'jsonrpc': '2.0',
          'id': '$label-rejected-session-batch-resources',
          'method': 'resources/list',
          'params': {},
        },
        {
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
          'params': {},
        },
      ]);
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST batch tools/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': '$label-rejected-session-batch-api-list',
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.api.list',
            'arguments': {'kind': 'topic'},
          },
        },
        {
          'jsonrpc': '2.0',
          'id': '$label-rejected-session-batch-pubsub-subscribe',
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.subscribe',
            'arguments': {'topic': _topic, 'queueLimit': 1},
          },
        },
      ]);
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST batch WAMP meta/pubsub tools',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.notifyInitialized();
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST notifications/initialized',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.listTools(id: '$label-rejected-session-tools');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST tools/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.callTool(
        _procedure,
        id: '$label-rejected-session-tool-call',
        arguments: {'taskId': 'T-$label-rejected-session-tool-call'},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST tools/call',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.listResources(id: '$label-rejected-session-resources');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST resources/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.readResource(
        _resourceUri,
        id: '$label-rejected-session-resource-read',
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST resources/read',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.listResourceTemplates(
        id: '$label-rejected-session-resource-templates',
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST resources/templates/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.listPrompts(id: '$label-rejected-session-prompts');
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST prompts/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.getPrompt(
        _promptName,
        id: '$label-rejected-session-prompt-get',
        arguments: {'taskId': 'T-$label-rejected-session-prompt-get'},
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'POST prompts/get',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.poll();
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'GET SSE poll',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.deleteSession();
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'DELETE session',
    acceptedMessage: acceptedMessage,
  );
}

Future<void> _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
  McpStreamableHttpClient client,
  Future<void> Function() request, {
  required String sessionId,
  String? lastEventId,
  required String method,
  required String acceptedMessage,
}) async {
  client.sessionId = sessionId;
  client.lastEventId = lastEventId;
  try {
    await request();
    throw StateError('$acceptedMessage $method succeeded.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'Active direct JSON MCP $method returned ${error.statusCode} '
        'instead of ${HttpStatus.unauthorized} for a rejected token.',
      );
    }
  }
  if (client.sessionId != sessionId || client.lastEventId != lastEventId) {
    throw StateError(
      'Active direct JSON MCP $method changed Streamable session state.',
    );
  }
}

Future<void> _assertActiveStreamableRequestRejectsBearer(
  McpStreamableHttpClient client,
  Future<void> Function() request, {
  required String sessionId,
  String? lastEventId,
  required String method,
  required String acceptedMessage,
}) async {
  client.sessionId = sessionId;
  client.lastEventId = lastEventId;
  try {
    await request();
    throw StateError('$acceptedMessage $method succeeded.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'Active Streamable MCP $method returned ${error.statusCode} '
        'instead of ${HttpStatus.unauthorized} for a rejected token.',
      );
    }
  }
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Active Streamable MCP $method did not clear rejected session state.',
    );
  }
}

Future<void> _smokeDirectJson(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  await _expectPagedToolCatalog(
    client,
    label: label,
    directJson: true,
  );

  await _smokeDirectToolApi(client, label: label);
  await _smokeDirectWampApiHelpers(client, label: label);
  await _smokeGenericDirectJsonRpcAccess(
    client,
    serviceSession,
    label: label,
  );
  await _smokeDirectWampMetaHelpers(
    client,
    serviceSession,
    label: label,
  );
  await _smokeGenericDirectJsonRpcPubSub(
    client,
    serviceSession,
    label: label,
  );
  await _smokeDirectJsonSingleError(client, label: label);
  await _smokeDirectJsonBatch(client, serviceSession, label: label);
  await _smokeGenericDirectJsonRpcResourcesAndPrompts(client, label: label);
  await _smokeGenericDirectJsonRpcResourcePromptErrors(
    client,
    label: label,
  );
  await _smokeResourcesAndPrompts(client, label: label, directJson: true);
  await _smokeWampMetaDiscovery(
    client,
    serviceSession,
    label: label,
    directJson: true,
  );

  final subscription = await client.subscribeWampTopicDirect(
    _topic,
    id: '$label-direct-subscribe',
    queueLimit: 4,
    options: mcpWampSubscribeOptions(
      match: 'exact',
      custom: <String, Object?>{
        'x_consumer_subscription': '$label-direct-subscribe',
      },
    ),
  );
  try {
    final subscribers = await _smokeWampSubscriptionMeta(
      client,
      serviceSession,
      label: label,
      directJson: true,
    );
    final subscriber = subscribers.first;

    final publication = await client.publishWampEventDirect(
      _topic,
      id: '$label-direct-publish',
      argumentsKeywords: {'taskId': 'T-$label-direct-publish'},
      options: mcpWampPublishOptions(
        acknowledge: true,
        excludeMe: false,
        custom: <String, Object?>{
          'x_consumer_trace': '$label-direct-publish',
        },
      ),
    );
    if (!publication.acknowledged) {
      throw StateError('Direct JSON MCP pub/sub publish was not acknowledged.');
    }
    final selfEvents = await _pollMcpEventsUntil(
      client,
      subscription.handle,
      directJson: true,
    );
    if (!jsonEncode(selfEvents.events).contains('T-$label-direct-publish')) {
      throw StateError(
        'Direct JSON MCP pub/sub publish with exclude_me=false was not '
        'delivered to its own subscription.',
      );
    }

    final excludedPublication = await client.publishWampEventDirect(
      _topic,
      id: '$label-direct-publish-exclude-me',
      argumentsKeywords: {'taskId': 'T-$label-direct-publish-exclude-me'},
      options: mcpWampPublishOptions(
        acknowledge: true,
        excludeMe: true,
        custom: <String, Object?>{
          'x_consumer_trace': '$label-direct-publish-exclude-me',
        },
      ),
    );
    if (!excludedPublication.acknowledged) {
      throw StateError(
        'Direct JSON MCP pub/sub exclude_me publish was not acknowledged.',
      );
    }
    final excludedEvents = await client.pollWampEventsDirect(
      subscription.handle,
      id: '$label-direct-poll-exclude-me',
      limit: 4,
    );
    if (jsonEncode(excludedEvents.events).contains(
      'T-$label-direct-publish-exclude-me',
    )) {
      throw StateError(
        'Direct JSON MCP pub/sub publish with exclude_me=true reached its own '
        'subscription.',
      );
    }

    await _smokeWampPublishSessionFilters(
      client,
      subscription.handle,
      subscriber,
      label: label,
      directJson: true,
    );

    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': 'T-$label-direct-event'},
      options: PublishOptions(acknowledge: true),
    );
    final events = await _pollMcpEventsUntil(
      client,
      subscription.handle,
      directJson: true,
    );
    if (!jsonEncode(events.events).contains('T-$label-direct-event')) {
      throw StateError('Direct JSON MCP pub/sub poll missed service event.');
    }
  } finally {
    await client.unsubscribeWampTopicDirect(
      subscription.handle,
      id: '$label-direct-unsubscribe',
    );
  }
  await _smokeMcpPubSubQueueOverflow(
    client,
    serviceSession,
    label: label,
    directJson: true,
  );

  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError('Direct JSON MCP helpers captured Streamable state.');
  }
}

Future<List<String>> _expectPagedToolCatalog(
  McpStreamableHttpClient client, {
  required String label,
  required bool directJson,
}) async {
  final mode = directJson ? 'direct' : 'streamable';
  final names = <String>[];
  String? cursor;
  var pageCount = 0;

  do {
    pageCount += 1;
    if (pageCount > 128) {
      throw StateError('$mode MCP tool catalog pagination did not terminate.');
    }
    final pageLabel = '$label-$mode-tools-page-$pageCount';
    final page = directJson
        ? await client.listToolsDirect(
            id: pageLabel,
            cursor: cursor,
            headers: <String, String>{
              'x-consumer-trace': pageLabel,
            },
          )
        : await client.listTools(
            id: pageLabel,
            cursor: cursor,
            headers: <String, String>{
              'x-consumer-trace': pageLabel,
            },
          );
    final pageNames = _toolNamesFromCatalog(
      page.tools,
      label: '$mode MCP tool catalog page $pageCount',
    );
    if (pageNames.isEmpty) {
      throw StateError('$mode MCP tool catalog returned an empty page.');
    }
    names.addAll(pageNames);
    cursor = page.nextCursor;
    if (cursor != null && cursor.isEmpty) {
      throw StateError('$mode MCP tool catalog returned an empty cursor.');
    }
  } while (cursor != null);

  if (pageCount < 2) {
    throw StateError('$mode MCP tool catalog did not expose a cursor.');
  }
  _expectSortedUniqueNames(
    names,
    label: '$mode MCP tool catalog',
  );
  if (!names.contains(_procedure)) {
    throw StateError('$mode MCP tool catalog did not expose $_procedure.');
  }
  if (!names.contains('connectanum.api.list') ||
      !names.contains('connectanum.pubsub.subscribe')) {
    throw StateError(
      '$mode MCP tool catalog did not expose Connectanum meta/pubsub tools.',
    );
  }
  return names;
}

Future<List<String>> _expectGenericToolCatalog(
  McpStreamableHttpClient client, {
  required String label,
  required bool directJson,
  void Function(String operation)? expectStreamableProgress,
}) async {
  final mode = directJson ? 'generic direct' : 'generic streamable';
  const method = 'tools/list';
  final names = <String>[];
  String? cursor;
  var pageCount = 0;

  do {
    pageCount += 1;
    if (pageCount > 128) {
      throw StateError('$mode MCP tool catalog pagination did not terminate.');
    }
    final pageLabel = '$label-tools-page-$pageCount';
    final params = <String, Object?>{
      if (cursor != null) 'cursor': cursor,
    };
    final response = directJson
        ? await client.requestDirect(
            method,
            id: pageLabel,
            params: params,
          )
        : await client.request(method, id: pageLabel, params: params);
    final result = _jsonRpcResult(
      response,
      id: pageLabel,
      label: '$mode MCP tool catalog page $pageCount',
    );
    final pageNames = _toolNamesFromCatalog(
      result['tools'],
      label: '$mode MCP tool catalog page $pageCount',
    );
    if (pageNames.isEmpty) {
      throw StateError('$mode MCP tool catalog returned an empty page.');
    }
    names.addAll(pageNames);
    cursor = result['nextCursor'] as String?;
    if (cursor != null && cursor.isEmpty) {
      throw StateError('$mode MCP tool catalog returned an empty cursor.');
    }
    expectStreamableProgress?.call('tools/list page $pageCount');
  } while (cursor != null);

  if (pageCount < 2) {
    throw StateError('$mode MCP tool catalog did not expose a cursor.');
  }
  _expectSortedUniqueNames(names, label: '$mode MCP tool catalog');
  if (!names.contains(_procedure)) {
    throw StateError('$mode MCP tool catalog did not expose $_procedure.');
  }
  if (!names.contains('connectanum.api.list') ||
      !names.contains('connectanum.pubsub.subscribe')) {
    throw StateError(
      '$mode MCP tool catalog did not expose Connectanum meta/pubsub tools.',
    );
  }
  return names;
}

Future<List<String>> _expectGenericCatalogPages(
  McpStreamableHttpClient client, {
  required String label,
  required String method,
  required String resultKey,
  required String field,
  required String fieldDescription,
  required String expectedPrimary,
  required String expectedPaged,
  required bool directJson,
  void Function(String operation)? expectStreamableProgress,
}) async {
  final mode = directJson ? 'generic direct' : 'generic streamable';
  final values = <String>[];
  String? cursor;
  var pageCount = 0;

  do {
    pageCount += 1;
    if (pageCount > 128) {
      throw StateError('$mode $method pagination did not terminate.');
    }
    final pageLabel = '$label-page-$pageCount';
    final params = <String, Object?>{
      if (cursor != null) 'cursor': cursor,
    };
    final response = directJson
        ? await client.requestDirect(
            method,
            id: pageLabel,
            params: params,
          )
        : await client.request(method, id: pageLabel, params: params);
    final result = _jsonRpcResult(
      response,
      id: pageLabel,
      label: '$mode $method page $pageCount',
    );
    final pageValues = _catalogStringFieldValues(
      result[resultKey],
      field: field,
      label: '$mode $method page $pageCount',
    );
    if (pageValues.isEmpty) {
      throw StateError('$mode $method returned an empty page.');
    }
    values.addAll(pageValues);
    final nextCursor = result['nextCursor'];
    if (nextCursor != null && (nextCursor is! String || nextCursor.isEmpty)) {
      throw StateError('$mode $method returned an invalid cursor.');
    }
    cursor = nextCursor as String?;
    expectStreamableProgress?.call('$method page $pageCount');
  } while (cursor != null);

  if (pageCount < 2) {
    throw StateError('$mode $method did not expose a cursor.');
  }
  _expectSortedUniqueCatalogValues(
    values,
    label: '$mode $method',
    fieldDescription: fieldDescription,
  );
  if (!values.contains(expectedPrimary) || !values.contains(expectedPaged)) {
    throw StateError(
      '$mode $method missed expected catalog entries.',
    );
  }
  return values;
}

String? _expectToolListPage(
  Map<String, Object?> response, {
  required Object id,
  required String label,
  required List<String> names,
  bool requireCursor = false,
}) {
  final result = _jsonRpcResult(response, id: id, label: label);
  final pageNames = _toolNamesFromCatalog(
    result['tools'],
    label: '$label catalog page',
  );
  if (pageNames.isEmpty) {
    throw StateError('$label returned an empty tool page.');
  }
  _expectSortedUniqueNames(pageNames, label: '$label catalog page');
  names.addAll(pageNames);
  final cursor = result['nextCursor'];
  if (cursor != null && (cursor is! String || cursor.isEmpty)) {
    throw StateError('$label returned an invalid cursor.');
  }
  if (requireCursor && cursor == null) {
    throw StateError('$label did not return a cursor.');
  }
  return cursor as String?;
}

Future<List<String>> _expectBatchToolCatalogPages(
  McpStreamableHttpClient client, {
  required Map<String, Object?> headResponse,
  required Object headId,
  required String label,
  required String idPrefix,
  required String method,
  required bool directJson,
  void Function(String operation)? expectStreamableProgress,
}) async {
  final names = <String>[];
  var cursor = _expectToolListPage(
    headResponse,
    id: headId,
    label: '$label page 1',
    names: names,
    requireCursor: true,
  );
  var pageCount = 1;

  while (cursor != null) {
    pageCount += 1;
    if (pageCount > 128) {
      throw StateError('$label pagination did not terminate.');
    }
    final pageId = '$idPrefix-page-$pageCount';
    final pageRequest = <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': pageId,
        'method': method,
        'params': {'cursor': cursor},
      },
    ];
    final pageHeaders = <String, String>{'x-consumer-trace': pageId};
    final pageBatch = directJson
        ? await client.postBatchDirect(pageRequest, headers: pageHeaders)
        : await client.postBatch(pageRequest, headers: pageHeaders);
    if (pageBatch == null || pageBatch.length != 1) {
      throw StateError(
        '$label cursor page $pageCount did not return one response.',
      );
    }
    cursor = _expectToolListPage(
      pageBatch[0],
      id: pageId,
      label: '$label page $pageCount',
      names: names,
    );
    expectStreamableProgress?.call('$method page $pageCount');
  }

  if (pageCount < 2) {
    throw StateError('$label did not expose a cursor.');
  }
  _expectSortedUniqueNames(names, label: label);
  if (!names.contains(_procedure)) {
    throw StateError('$label did not expose $_procedure.');
  }
  if (!names.contains('connectanum.api.list') ||
      !names.contains('connectanum.pubsub.subscribe')) {
    throw StateError(
      '$label did not expose Connectanum meta/pubsub tools.',
    );
  }
  return names;
}

String _expectPaginatedCatalogHead(
  Map<String, Object?> response, {
  required Object id,
  required String label,
  required String resultKey,
  required String field,
  required String fieldDescription,
  required String expectedPrimary,
}) {
  final result = _jsonRpcResult(response, id: id, label: label);
  final values = _catalogStringFieldValues(
    result[resultKey],
    field: field,
    label: '$label catalog page',
  );
  if (values.isEmpty) {
    throw StateError('$label returned an empty catalog page.');
  }
  _expectSortedUniqueCatalogValues(
    values,
    label: '$label catalog page',
    fieldDescription: fieldDescription,
  );
  if (!values.contains(expectedPrimary)) {
    throw StateError('$label did not expose $expectedPrimary.');
  }
  final cursor = result['nextCursor'];
  if (cursor is! String || cursor.isEmpty) {
    throw StateError('$label did not return a non-empty cursor.');
  }
  return cursor;
}

void _expectCatalogCursorPage(
  Map<String, Object?> response, {
  required Object id,
  required String label,
  required String resultKey,
  required String field,
  required String fieldDescription,
  required String expectedPaged,
}) {
  final result = _jsonRpcResult(response, id: id, label: label);
  final values = _catalogStringFieldValues(
    result[resultKey],
    field: field,
    label: '$label catalog cursor page',
  );
  if (values.isEmpty) {
    throw StateError('$label returned an empty cursor page.');
  }
  _expectSortedUniqueCatalogValues(
    values,
    label: '$label catalog cursor page',
    fieldDescription: fieldDescription,
  );
  if (!values.contains(expectedPaged)) {
    throw StateError('$label did not expose $expectedPaged.');
  }
  if (result['nextCursor'] != null) {
    throw StateError('$label returned an unexpected extra cursor.');
  }
}

Future<void> _smokeDirectToolApi(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final helperTaskId = 'T-$label-direct-tool-helper';
  final helperResult = await client.callConnectanumToolDirect(
    _procedure,
    id: '$label-direct-tool-helper',
    arguments: {'taskId': helperTaskId, 'note': _headerWrappedNote},
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-tool-helper',
    },
  );
  _expectDirectToolPayload(
    helperResult,
    taskId: helperTaskId,
    label: 'Direct JSON tool helper',
  );

  final headerOverrideTaskId = 'T-$label-direct-tool-header-override';
  final headerOverrideResult = await client.callConnectanumToolDirect(
    _procedure,
    id: '$label-direct-tool-header-override',
    arguments: {'taskId': headerOverrideTaskId, 'note': _headerWrappedNote},
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-tool-header-override',
      'Mcp-Method': 'consumer.tool.wrong',
      'Mcp-Name': 'consumer.task.wrong',
      'Mcp-Param-TaskId': 'wrong-task',
      'Mcp-Param-Note': 'wrong-note',
    },
  );
  _expectDirectToolPayload(
    headerOverrideResult,
    taskId: headerOverrideTaskId,
    label: 'Direct JSON tool helper header override',
  );

  final aliasTaskId = 'T-$label-direct-tools-call-alias';
  final aliasResult = await client.callConnectanumMethodDirect(
    'connectanum.tools.call',
    id: '$label-direct-tools-call-alias',
    params: {
      'name': _procedure,
      'arguments': {'taskId': aliasTaskId, 'note': _headerWrappedNote},
    },
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-tools-call-alias',
      'Mcp-Param-TaskId': 'wrong-task',
      'Mcp-Param-Note': 'wrong-note',
    },
  );
  _expectDirectToolPayload(
    aliasResult,
    taskId: aliasTaskId,
    label: 'Direct JSON plural tool alias',
  );

  final dottedTaskId = 'T-$label-direct-dotted-method';
  final dottedResult = await client.callConnectanumMethodDirect(
    _procedure,
    id: '$label-direct-dotted-method',
    params: {'taskId': dottedTaskId, 'note': _headerWrappedNote},
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-dotted-method',
      'Mcp-Param-TaskId': 'wrong-task',
      'Mcp-Param-Note': 'wrong-note',
    },
  );
  _expectDirectToolPayload(
    dottedResult,
    taskId: dottedTaskId,
    label: 'Direct JSON dotted tool method',
  );

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON tool API changed Streamable session state.');
  }
}

Future<void> _smokeDirectWampApiHelpers(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final procedureCatalog = await client.listWampApiDirect(
    id: '$label-direct-helper-api-procedures',
    kind: 'procedure',
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-helper-api-procedures',
    },
  );
  final procedureUris = _catalogStringFieldValues(
    procedureCatalog['procedures'],
    field: 'uri',
    label: 'Direct WAMP API helper procedure catalog',
  );
  _expectSortedUniqueCatalogValues(
    procedureUris,
    label: 'Direct WAMP API helper procedure catalog',
    fieldDescription: 'procedure URI',
  );
  if (!procedureUris.contains(_procedure)) {
    throw StateError(
      'Direct WAMP API helper procedure catalog missed $_procedure.',
    );
  }

  final procedureDescription = await client.describeWampApiDirect(
    _procedure,
    id: '$label-direct-helper-api-procedure-describe',
    kind: 'procedure',
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-helper-api-procedure-describe',
    },
  );
  if (procedureDescription['uri'] != _procedure) {
    throw StateError(
      'Direct WAMP API helper procedure describe missed $_procedure.',
    );
  }

  final topicCatalog = await client.listWampApiDirect(
    id: '$label-direct-helper-api-topics',
    kind: 'topic',
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-helper-api-topics',
    },
  );
  final topicUris = _catalogStringFieldValues(
    topicCatalog['topics'],
    field: 'uri',
    label: 'Direct WAMP API helper topic catalog',
  );
  _expectSortedUniqueCatalogValues(
    topicUris,
    label: 'Direct WAMP API helper topic catalog',
    fieldDescription: 'topic URI',
  );
  final topicCatalogJson = jsonEncode(topicCatalog);
  if (!topicUris.contains(_topic) ||
      !topicCatalogJson.contains('Consumer task lifecycle event stream')) {
    throw StateError('Direct WAMP API helper topic catalog missed $_topic.');
  }

  final topicDescription = await client.describeWampApiDirect(
    _topic,
    id: '$label-direct-helper-api-topic-describe',
    kind: 'topic',
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-helper-api-topic-describe',
    },
  );
  final topicDescriptionJson = jsonEncode(topicDescription);
  if (topicDescription['uri'] != _topic ||
      !topicDescriptionJson.contains('eventSchema') ||
      !topicDescriptionJson.contains('allowPublish') ||
      !topicDescriptionJson.contains('allowSubscribe')) {
    throw StateError('Direct WAMP API helper topic describe missed $_topic.');
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct WAMP API helpers changed Streamable session state.');
  }
}

void _expectDirectToolPayload(
  Object? result, {
  required String taskId,
  required String label,
}) {
  final resultJson = jsonEncode(result);
  if (!resultJson.contains(taskId) ||
      !resultJson.contains(_headerWrappedNote)) {
    throw StateError('$label did not return expected payload.');
  }
}

List<String> _toolNamesFromCatalog(Object? value, {required String label}) {
  return _catalogStringFieldValues(value, field: 'name', label: label);
}

List<String> _catalogStringFieldValues(
  Object? value, {
  required String field,
  required String label,
}) {
  if (value is! Iterable) {
    throw StateError('$label was not a JSON array.');
  }
  final values = <String>[];
  for (final item in value) {
    if (item is! Map) {
      throw StateError('$label contained a non-object item.');
    }
    final fieldValue = item[field];
    if (fieldValue is! String || fieldValue.isEmpty) {
      throw StateError('$label contained an item without $field.');
    }
    values.add(fieldValue);
  }
  return values;
}

void _expectSortedUniqueNames(
  List<String> names, {
  required String label,
}) {
  _expectSortedUniqueCatalogValues(
    names,
    label: label,
    fieldDescription: 'tool name',
  );
}

void _expectSortedUniqueCatalogValues(
  List<String> values, {
  required String label,
  required String fieldDescription,
}) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw StateError('$label contained duplicate $fieldDescription $value.');
    }
  }
  final sorted = [...values]..sort();
  for (var index = 0; index < values.length; index += 1) {
    if (values[index] != sorted[index]) {
      throw StateError('$label was not sorted by $fieldDescription.');
    }
  }
}

void _expectSortedUniqueWampApiCatalog(
  Map<String, Object?> catalog, {
  required String label,
  bool includeTopics = true,
}) {
  final procedureUris = _catalogStringFieldValues(
    catalog['procedures'],
    field: 'uri',
    label: '$label procedure catalog',
  );
  _expectSortedUniqueCatalogValues(
    procedureUris,
    label: '$label procedure catalog',
    fieldDescription: 'procedure URI',
  );
  if (!includeTopics) {
    return;
  }
  final topicUris = _catalogStringFieldValues(
    catalog['topics'],
    field: 'uri',
    label: '$label topic catalog',
  );
  _expectSortedUniqueCatalogValues(
    topicUris,
    label: '$label topic catalog',
    fieldDescription: 'topic URI',
  );
}

Map<String, Object?> _jsonObjectFrom(Object? value, {required String label}) {
  if (value is Map<Object?, Object?>) {
    return value.map((key, value) {
      if (key is! String) {
        throw StateError('$label contained a non-string key.');
      }
      return MapEntry(key, value);
    });
  }
  throw StateError('$label was not a JSON object.');
}

void _expectPublicMcpInitializeMetadata(Map<String, Object?> initialize) {
  void expectField(
    Map<String, Object?> object,
    String field,
    Object? expected,
    String label,
  ) {
    final actual = object[field];
    if (actual != expected) {
      throw StateError(
        '$label returned unexpected $field: $actual.',
      );
    }
  }

  final result = _jsonObjectFrom(
    initialize['result'],
    label: 'public Streamable initialize result',
  );
  final serverInfo = _jsonObjectFrom(
    result['serverInfo'],
    label: 'public Streamable initialize serverInfo',
  );
  expectField(serverInfo, 'name', _publicMcpServerName, 'public MCP');
  expectField(serverInfo, 'version', _publicMcpServerVersion, 'public MCP');
  expectField(serverInfo, 'title', _publicMcpServerTitle, 'public MCP');
  expectField(
    serverInfo,
    'description',
    _publicMcpServerDescription,
    'public MCP',
  );
  expectField(
    result,
    'instructions',
    _publicMcpInstructions,
    'public MCP initialize',
  );
}

String _mcpBase64Header(String value) =>
    '=?base64?${base64Encode(utf8.encode(value))}?=';

Map<String, Object?> _jsonRpcStructuredContent(
  Map<String, Object?> response, {
  required Object id,
  required String label,
}) {
  if (response['id'] != id) {
    throw StateError('$label response id was invalid.');
  }
  final result = _jsonObjectFrom(response['result'], label: '$label result');
  if (result['isError'] == true) {
    throw StateError('$label returned an MCP tool error: ${jsonEncode(result)}');
  }
  return _jsonObjectFrom(
    result['structuredContent'],
    label: '$label structuredContent',
  );
}

Map<String, Object?> _jsonRpcResult(
  Map<String, Object?> response, {
  required Object id,
  required String label,
}) {
  if (response['id'] != id) {
    throw StateError('$label response id was invalid.');
  }
  return _jsonObjectFrom(response['result'], label: '$label result');
}

Future<void> _smokeGenericDirectJsonRpcAccess(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  await _expectGenericToolCatalog(
    client,
    label: '$label-generic-direct',
    directJson: true,
  );

  final taskId = 'T-$label-generic-direct-tool-call';
  final toolCallId = '$label-generic-direct-tool-call';
  final toolCall = await client.postDirect(
    {
      'jsonrpc': '2.0',
      'id': toolCallId,
      'method': 'connectanum.tool.call',
      'params': {
        'name': _procedure,
        'arguments': {'taskId': taskId, 'note': _headerWrappedNote},
      },
    },
  );
  final toolCallJson = jsonEncode(toolCall);
  if (toolCall == null ||
      toolCall['id'] != toolCallId ||
      !toolCallJson.contains(taskId) ||
      !toolCallJson.contains(_headerWrappedNote)) {
    throw StateError('Generic direct JSON-RPC tool call failed.');
  }

  final apiListId = '$label-generic-direct-api-list';
  final apiList = await client.requestDirect(
    'connectanum.api.list',
    id: apiListId,
  );
  final apiCatalog = _jsonRpcStructuredContent(
    apiList,
    id: apiListId,
    label: 'Generic direct JSON-RPC API list',
  );
  final apiCatalogJson = jsonEncode(apiCatalog);
  if (!apiCatalogJson.contains(_procedure) ||
      !apiCatalogJson.contains(_topic)) {
    throw StateError('Generic direct JSON-RPC API list missed catalog items.');
  }
  _expectSortedUniqueWampApiCatalog(
    apiCatalog,
    label: 'Generic direct JSON-RPC API list',
  );

  final describeId = '$label-generic-direct-api-describe';
  final describe = await client.requestDirect(
    'connectanum.api.describe',
    id: describeId,
    params: {'uri': _procedure, 'kind': 'procedure'},
  );
  if (describe['id'] != describeId ||
      !jsonEncode(describe['result']).contains(_procedure)) {
    throw StateError('Generic direct JSON-RPC API describe missed $_procedure.');
  }

  await _smokeGenericDirectJsonRpcWampRegistrationSessionMeta(
    client,
    serviceSession,
    label: label,
  );

  final notificationBatch = await client.postBatchDirect(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': <String, Object?>{},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/progress',
        'params': <String, Object?>{
          'progressToken': 'generic-direct-notification-batch',
          'progress': 1,
        },
      },
    ],
    headers: const <String, String>{
      'x-consumer-trace': 'router-direct-notification-batch',
    },
  );
  if (notificationBatch != null) {
    throw StateError(
      'Generic direct JSON-RPC notification-only batch returned a response.',
    );
  }

  await client.notificationDirect(
    'notifications/progress',
    params: const <String, Object?>{
      'progressToken': 'generic-direct-single-notification',
      'progress': 1,
    },
  );

  final standardToolNotificationTaskId =
      'T-$label-generic-direct-standard-tool-notification';
  await client.notifyToolDirect(
    _procedure,
    arguments: {
      'taskId': standardToolNotificationTaskId,
      'note': _headerWrappedNote,
    },
    headers: {
      'x-consumer-trace':
          '$label-generic-direct-standard-tool-notification',
      'Mcp-Param-TaskId': 'wrong-task',
      'Mcp-Param-Note': 'wrong-note',
    },
  );
  await _expectConsumerProcedureInvocation(
    standardToolNotificationTaskId,
    label: '$label generic direct standard tool notification',
  );

  final helperToolNotificationTaskId =
      'T-$label-generic-direct-helper-tool-notification';
  await client.notifyConnectanumToolDirect(
    _procedure,
    arguments: {
      'taskId': helperToolNotificationTaskId,
      'note': _headerWrappedNote,
    },
    headers: {
      'x-consumer-trace': '$label-generic-direct-helper-tool-notification',
      'Mcp-Param-TaskId': 'wrong-task',
      'Mcp-Param-Note': 'wrong-note',
    },
  );
  await _expectConsumerProcedureInvocation(
    helperToolNotificationTaskId,
    label: '$label generic direct helper tool notification',
  );

  final helperMethodNotificationTaskId =
      'T-$label-generic-direct-helper-method-notification';
  await client.notifyConnectanumMethodDirect(
    _procedure,
    params: {
      'taskId': helperMethodNotificationTaskId,
      'note': _headerWrappedNote,
    },
    headers: {
      'x-consumer-trace': '$label-generic-direct-helper-method-notification',
      'Mcp-Param-TaskId': 'wrong-task',
      'Mcp-Param-Note': 'wrong-note',
    },
  );
  await _expectConsumerProcedureInvocation(
    helperMethodNotificationTaskId,
    label: '$label generic direct helper method notification',
  );

  final helperAliasNotificationTaskId =
      'T-$label-generic-direct-helper-alias-notification';
  await client.notifyConnectanumMethodDirect(
    'connectanum.tools.call',
    params: {
      'name': _procedure,
      'arguments': {
        'taskId': helperAliasNotificationTaskId,
        'note': _headerWrappedNote,
      },
    },
    headers: {
      'x-consumer-trace': '$label-generic-direct-helper-alias-notification',
      'Mcp-Param-TaskId': 'wrong-task',
      'Mcp-Param-Note': 'wrong-note',
    },
  );
  await _expectConsumerProcedureInvocation(
    helperAliasNotificationTaskId,
    label: '$label generic direct helper alias notification',
  );

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Generic direct JSON-RPC access changed session state.');
  }
}

Future<void> _smokeGenericDirectJsonRpcWampRegistrationSessionMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionCountId = '$label-generic-direct-session-count';
  final sessionCount = await client.requestDirect(
    'wamp.session.count',
    id: sessionCountId,
  );
  final sessionCountContent = _jsonRpcStructuredContent(
    sessionCount,
    id: sessionCountId,
    label: 'Generic direct JSON-RPC WAMP session count',
  );
  final sessionCountKeywords = _jsonObjectFrom(
    sessionCountContent['argumentsKeywords'],
    label: 'Generic direct JSON-RPC WAMP session count kwargs',
  );
  final visibleSessionCount = sessionCountKeywords['count'];
  if (visibleSessionCount is! int) {
    throw StateError(
      'Generic direct JSON-RPC WAMP session count missed count metadata.',
    );
  }

  final sessionListId = '$label-generic-direct-session-list';
  final sessionList = await client.requestDirect(
    'wamp.session.list',
    id: sessionListId,
  );
  final sessionListContent = _jsonRpcStructuredContent(
    sessionList,
    id: sessionListId,
    label: 'Generic direct JSON-RPC WAMP session list',
  );
  final sessionListKeywords = _jsonObjectFrom(
    sessionListContent['argumentsKeywords'],
    label: 'Generic direct JSON-RPC WAMP session list kwargs',
  );
  final sessionIds = _integerMetaIdsFromValue(
    sessionListKeywords['session_ids'],
    'generic direct session list',
  );
  if (sessionIds.contains(serviceSession.sessionId)) {
    throw StateError(
      'Generic direct JSON-RPC WAMP session list leaked service session.',
    );
  }
  if (sessionIds.length != visibleSessionCount) {
    throw StateError(
      'Generic direct JSON-RPC WAMP session count did not match list.',
    );
  }
  if (sessionIds.isEmpty) {
    throw StateError(
      'Generic direct JSON-RPC WAMP session list missed visible sessions.',
    );
  }

  final visibleSessionId = sessionIds.first;
  final sessionGetId = '$label-generic-direct-session-get';
  final sessionGet = await client.requestDirect(
    'wamp.session.get',
    id: sessionGetId,
    params: {'id': visibleSessionId},
  );
  final sessionGetContent = _jsonRpcStructuredContent(
    sessionGet,
    id: sessionGetId,
    label: 'Generic direct JSON-RPC WAMP session get',
  );
  final sessionGetKeywords = _jsonObjectFrom(
    sessionGetContent['argumentsKeywords'],
    label: 'Generic direct JSON-RPC WAMP session get kwargs',
  );
  final sessionDetails = _jsonObjectFrom(
    sessionGetKeywords['details'],
    label: 'Generic direct JSON-RPC WAMP session details',
  );
  if (sessionDetails['id'] != visibleSessionId) {
    throw StateError(
      'Generic direct JSON-RPC WAMP session get missed visible session.',
    );
  }

  final registrationLookupId = '$label-generic-direct-registration-lookup';
  final registrationLookup = await client.requestDirect(
    'wamp.registration.lookup',
    id: registrationLookupId,
    params: {'uri': _procedure},
  );
  final registrationLookupContent = _jsonRpcStructuredContent(
    registrationLookup,
    id: registrationLookupId,
    label: 'Generic direct JSON-RPC WAMP registration lookup',
  );
  final registrationLookupArguments = registrationLookupContent['arguments'];
  if (registrationLookupArguments is! List) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration lookup missed arguments.',
    );
  }
  final registrationId = _singleMetaId(
    registrationLookupArguments.cast<Object?>(),
    'generic direct registration lookup',
  );
  if (registrationId <= 0) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration lookup returned '
      'invalid id $registrationId.',
    );
  }

  final registrationMatchId = '$label-generic-direct-registration-match';
  final registrationMatch = await client.requestDirect(
    'wamp.registration.match',
    id: registrationMatchId,
    params: {'uri': _procedure},
  );
  final registrationMatchContent = _jsonRpcStructuredContent(
    registrationMatch,
    id: registrationMatchId,
    label: 'Generic direct JSON-RPC WAMP registration match',
  );
  final registrationMatchArguments = registrationMatchContent['arguments'];
  if (registrationMatchArguments is! List) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration match missed arguments.',
    );
  }
  final matchingRegistrationId = _singleMetaId(
    registrationMatchArguments.cast<Object?>(),
    'generic direct registration match',
  );
  if (matchingRegistrationId != registrationId) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration match did not agree '
      'with lookup.',
    );
  }

  final registrationListId = '$label-generic-direct-registration-list';
  final registrationList = await client.requestDirect(
    'wamp.registration.list',
    id: registrationListId,
  );
  final registrationListContent = _jsonRpcStructuredContent(
    registrationList,
    id: registrationListId,
    label: 'Generic direct JSON-RPC WAMP registration list',
  );
  final registrationListKeywords = _jsonObjectFrom(
    registrationListContent['argumentsKeywords'],
    label: 'Generic direct JSON-RPC WAMP registration list kwargs',
  );
  final exactRegistrationIds = _integerMetaIdsFromValue(
    registrationListKeywords['exact'],
    'generic direct registration list exact',
  );
  if (!exactRegistrationIds.contains(registrationId)) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration list missed $_procedure.',
    );
  }

  final registrationGetId = '$label-generic-direct-registration-get';
  final registrationGet = await client.requestDirect(
    'wamp.registration.get',
    id: registrationGetId,
    params: {'id': registrationId},
  );
  final registrationGetContent = _jsonRpcStructuredContent(
    registrationGet,
    id: registrationGetId,
    label: 'Generic direct JSON-RPC WAMP registration get',
  );
  final registrationGetKeywords = _jsonObjectFrom(
    registrationGetContent['argumentsKeywords'],
    label: 'Generic direct JSON-RPC WAMP registration get kwargs',
  );
  if (registrationGetKeywords['uri'] != _procedure) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration get missed $_procedure.',
    );
  }

  final registrationCalleesId = '$label-generic-direct-registration-callees';
  final registrationCallees = await client.requestDirect(
    'wamp.registration.list_callees',
    id: registrationCalleesId,
    params: {'id': registrationId},
  );
  final registrationCalleesContent = _jsonRpcStructuredContent(
    registrationCallees,
    id: registrationCalleesId,
    label: 'Generic direct JSON-RPC WAMP registration callees',
  );
  final registrationCalleeArguments = registrationCalleesContent['arguments'];
  if (registrationCalleeArguments is! List) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration callees missed arguments.',
    );
  }
  final calleeIds = _integerMetaIds(
    registrationCalleeArguments.cast<Object?>(),
    'generic direct registration callees',
  );
  if (calleeIds.contains(serviceSession.sessionId) || calleeIds.isNotEmpty) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration callees leaked '
      'internal sessions.',
    );
  }

  final registrationCalleeCountId =
      '$label-generic-direct-registration-callee-count';
  final registrationCalleeCount = await client.requestDirect(
    'wamp.registration.count_callees',
    id: registrationCalleeCountId,
    params: {'id': registrationId},
  );
  final registrationCalleeCountContent = _jsonRpcStructuredContent(
    registrationCalleeCount,
    id: registrationCalleeCountId,
    label: 'Generic direct JSON-RPC WAMP registration callee count',
  );
  final registrationCalleeCountArguments =
      registrationCalleeCountContent['arguments'];
  if (registrationCalleeCountArguments is! List) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration callee count missed '
      'arguments.',
    );
  }
  final calleeCount = _singleMetaId(
    registrationCalleeCountArguments.cast<Object?>(),
    'generic direct registration callee count',
  );
  if (calleeCount != 0) {
    throw StateError(
      'Generic direct JSON-RPC WAMP registration callee count leaked '
      'internal sessions.',
    );
  }
}

Future<void> _smokeDirectWampMetaHelpers(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final sessionCountId = '$label-direct-helper-wamp-session-count';
  final sessionListId = '$label-direct-helper-wamp-session-list';
  final registrationLookupId = '$label-direct-helper-wamp-registration-lookup';
  final registrationMatchId = '$label-direct-helper-wamp-registration-match';
  final registrationListId = '$label-direct-helper-wamp-registration-list';
  final sessionCount = await client.countWampSessionsDirect(
    id: sessionCountId,
    headers: <String, String>{'x-consumer-trace': sessionCountId},
  );
  final sessionList = await client.listWampSessionsDirect(
    id: sessionListId,
    headers: <String, String>{'x-consumer-trace': sessionListId},
  );
  final registrationLookup = await client.lookupWampRegistrationDirect(
    _procedure,
    id: registrationLookupId,
    headers: <String, String>{'x-consumer-trace': registrationLookupId},
  );
  final registrationMatch = await client.matchWampRegistrationDirect(
    _procedure,
    id: registrationMatchId,
    headers: <String, String>{'x-consumer-trace': registrationMatchId},
  );
  final registrationList = await client.listWampRegistrationsDirect(
    id: registrationListId,
    headers: <String, String>{'x-consumer-trace': registrationListId},
  );
  final ids = _expectWampRegistrationSessionBatchDiscovery(
    [
      _wampMetaHelperBatchResponse(sessionCount, id: sessionCountId),
      _wampMetaHelperBatchResponse(sessionList, id: sessionListId),
      _wampMetaHelperBatchResponse(
        registrationLookup,
        id: registrationLookupId,
      ),
      _wampMetaHelperBatchResponse(registrationMatch, id: registrationMatchId),
      _wampMetaHelperBatchResponse(registrationList, id: registrationListId),
    ],
    sessionCountId: sessionCountId,
    sessionListId: sessionListId,
    registrationLookupId: registrationLookupId,
    registrationMatchId: registrationMatchId,
    registrationListId: registrationListId,
    serviceSession: serviceSession,
    modeLabel: 'Direct WAMP meta helpers',
  );

  final visibleSessionId = ids[0];
  final registrationId = ids[1];
  final sessionGetId = '$label-direct-helper-wamp-session-get';
  final registrationGetId = '$label-direct-helper-wamp-registration-get';
  final registrationCalleesId =
      '$label-direct-helper-wamp-registration-callees';
  final registrationCalleeCountId =
      '$label-direct-helper-wamp-registration-callee-count';
  final sessionGet = await client.getWampSessionDirect(
    visibleSessionId,
    id: sessionGetId,
    headers: <String, String>{'x-consumer-trace': sessionGetId},
  );
  final registrationGet = await client.getWampRegistrationDirect(
    registrationId,
    id: registrationGetId,
    headers: <String, String>{'x-consumer-trace': registrationGetId},
  );
  final registrationCallees = await client.listWampRegistrationCalleesDirect(
    registrationId,
    id: registrationCalleesId,
    headers: <String, String>{'x-consumer-trace': registrationCalleesId},
  );
  final registrationCalleeCount = await client
      .countWampRegistrationCalleesDirect(
        registrationId,
        id: registrationCalleeCountId,
        headers: <String, String>{
          'x-consumer-trace': registrationCalleeCountId,
        },
      );
  _expectWampRegistrationSessionBatchDetails(
    [
      _wampMetaHelperBatchResponse(sessionGet, id: sessionGetId),
      _wampMetaHelperBatchResponse(registrationGet, id: registrationGetId),
      _wampMetaHelperBatchResponse(
        registrationCallees,
        id: registrationCalleesId,
      ),
      _wampMetaHelperBatchResponse(
        registrationCalleeCount,
        id: registrationCalleeCountId,
      ),
    ],
    sessionGetId: sessionGetId,
    registrationGetId: registrationGetId,
    registrationCalleesId: registrationCalleesId,
    registrationCalleeCountId: registrationCalleeCountId,
    visibleSessionId: visibleSessionId,
    serviceSession: serviceSession,
    modeLabel: 'Direct WAMP meta helpers',
  );

  final subscription = await client.subscribeWampTopicDirect(
    _topic,
    id: '$label-direct-helper-wamp-subscribe',
    queueLimit: 2,
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-helper-wamp-subscribe',
    },
  );
  try {
    final subscriptionId = subscription.subscriptionId;
    if (subscriptionId == null || subscriptionId <= 0) {
      throw StateError('Direct WAMP meta helpers missed subscription id.');
    }

    final subscriptionLookupId =
        '$label-direct-helper-wamp-subscription-lookup';
    final subscriptionMatchId = '$label-direct-helper-wamp-subscription-match';
    final subscriptionListId = '$label-direct-helper-wamp-subscription-list';
    final subscriptionLookup = await client.lookupWampSubscriptionDirect(
      _topic,
      id: subscriptionLookupId,
      headers: <String, String>{'x-consumer-trace': subscriptionLookupId},
    );
    final subscriptionMatch = await client.matchWampSubscriptionDirect(
      _topic,
      id: subscriptionMatchId,
      headers: <String, String>{'x-consumer-trace': subscriptionMatchId},
    );
    final subscriptionList = await client.listWampSubscriptionsDirect(
      id: subscriptionListId,
      headers: <String, String>{'x-consumer-trace': subscriptionListId},
    );
    final discoveredSubscriptionId = _expectWampSubscriptionBatchDiscovery(
      [
        _wampMetaHelperBatchResponse(
          subscriptionLookup,
          id: subscriptionLookupId,
        ),
        _wampMetaHelperBatchResponse(
          subscriptionMatch,
          id: subscriptionMatchId,
        ),
        _wampMetaHelperBatchResponse(subscriptionList, id: subscriptionListId),
      ],
      subscriptionLookupId: subscriptionLookupId,
      subscriptionMatchId: subscriptionMatchId,
      subscriptionListId: subscriptionListId,
      modeLabel: 'Direct WAMP subscription meta helpers',
    );
    if (discoveredSubscriptionId != subscriptionId) {
      throw StateError(
        'Direct WAMP subscription meta helpers disagreed with subscribe id.',
      );
    }

    final subscriptionGetId = '$label-direct-helper-wamp-subscription-get';
    final subscribersId = '$label-direct-helper-wamp-subscription-subscribers';
    final subscriberCountId =
        '$label-direct-helper-wamp-subscription-subscriber-count';
    final subscriptionGet = await client.getWampSubscriptionDirect(
      subscriptionId,
      id: subscriptionGetId,
      headers: <String, String>{'x-consumer-trace': subscriptionGetId},
    );
    final subscribers = await client.listWampSubscriptionSubscribersDirect(
      subscriptionId,
      id: subscribersId,
      headers: <String, String>{'x-consumer-trace': subscribersId},
    );
    final subscriberCount = await client.countWampSubscriptionSubscribersDirect(
      subscriptionId,
      id: subscriberCountId,
      headers: <String, String>{'x-consumer-trace': subscriberCountId},
    );
    _expectWampSubscriptionBatchDetails(
      [
        _wampMetaHelperBatchResponse(subscriptionGet, id: subscriptionGetId),
        _wampMetaHelperBatchResponse(subscribers, id: subscribersId),
        _wampMetaHelperBatchResponse(subscriberCount, id: subscriberCountId),
      ],
      subscriptionGetId: subscriptionGetId,
      subscribersId: subscribersId,
      subscriberCountId: subscriberCountId,
      serviceSession: serviceSession,
      modeLabel: 'Direct WAMP subscription meta helpers',
    );
  } finally {
    await client.unsubscribeWampTopicDirect(
      subscription.handle,
      id: '$label-direct-helper-wamp-unsubscribe',
      headers: <String, String>{
        'x-consumer-trace': '$label-direct-helper-wamp-unsubscribe',
      },
    );
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct WAMP meta helpers changed Streamable state.');
  }
}

Future<void> _smokeGenericDirectJsonRpcResourcesAndPrompts(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  await _expectGenericCatalogPages(
    client,
    label: '$label-generic-direct-resources',
    method: 'resources/list',
    resultKey: 'resources',
    field: 'uri',
    fieldDescription: 'resource URI',
    expectedPrimary: _resourceUri,
    expectedPaged: _pagedResourceUri,
    directJson: true,
  );

  final readId = '$label-generic-direct-resource-read';
  final read = await client.requestDirect(
    'resources/read',
    id: readId,
    params: {'uri': _resourceUri},
  );
  final readResult = _jsonRpcResult(
    read,
    id: readId,
    label: 'Generic direct JSON-RPC resources/read',
  );
  if (!jsonEncode(readResult['contents']).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError(
      'Generic direct JSON-RPC resources/read missed route context.',
    );
  }

  await _expectGenericCatalogPages(
    client,
    label: '$label-generic-direct-resource-templates',
    method: 'resources/templates/list',
    resultKey: 'resourceTemplates',
    field: 'uriTemplate',
    fieldDescription: 'resource template URI',
    expectedPrimary: _resourceTemplateUri,
    expectedPaged: _pagedResourceTemplateUri,
    directJson: true,
  );

  await _expectGenericCatalogPages(
    client,
    label: '$label-generic-direct-prompts',
    method: 'prompts/list',
    resultKey: 'prompts',
    field: 'name',
    fieldDescription: 'prompt name',
    expectedPrimary: _promptName,
    expectedPaged: _pagedPromptName,
    directJson: true,
  );

  final taskId = 'T-$label-generic-direct-prompt';
  final promptId = '$label-generic-direct-prompt-get';
  final prompt = _jsonObjectFrom(
    await client.postDirect(
      {
        'jsonrpc': '2.0',
        'id': promptId,
        'method': 'prompts/get',
        'params': {
          'name': _promptName,
          'arguments': {'taskId': taskId},
        },
      },
    ),
    label: 'Generic direct JSON-RPC prompts/get response',
  );
  final promptResult = _jsonRpcResult(
    prompt,
    id: promptId,
    label: 'Generic direct JSON-RPC prompts/get',
  );
  if (!jsonEncode(promptResult).contains(taskId)) {
    throw StateError(
      'Generic direct JSON-RPC prompts/get did not substitute $taskId.',
    );
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError(
      'Generic direct JSON-RPC resources/prompts changed Streamable state.',
    );
  }
}

Future<void> _smokeGenericDirectJsonRpcResourcePromptErrors(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final missingResourceUri = 'connectanum://consumer/missing/$label';
  final resourceErrorId = '$label-generic-direct-resource-error';
  final resourceError = await client.requestDirect(
    'resources/read',
    id: resourceErrorId,
    params: {'uri': missingResourceUri},
  );
  _expectJsonRpcError(
    resourceError,
    id: resourceErrorId,
    messageSubstring: missingResourceUri,
    label: 'Generic direct JSON-RPC missing resource',
  );

  final missingPromptName = 'missing-$label-prompt';
  final promptErrorId = '$label-generic-direct-prompt-error';
  final promptError = _jsonObjectFrom(
    await client.postDirect(
      {
        'jsonrpc': '2.0',
        'id': promptErrorId,
        'method': 'prompts/get',
        'params': {'name': missingPromptName, 'arguments': {}},
      },
    ),
    label: 'Generic direct JSON-RPC missing prompt response',
  );
  _expectJsonRpcError(
    promptError,
    id: promptErrorId,
    messageSubstring: missingPromptName,
    label: 'Generic direct JSON-RPC missing prompt',
  );

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError(
      'Generic direct JSON-RPC resource/prompt errors changed '
      'Streamable state.',
    );
  }

  final resources = await client.requestDirect(
    'resources/list',
    id: '$label-generic-direct-resource-error-recovery',
  );
  if (!jsonEncode(resources).contains(_resourceUri)) {
    throw StateError(
      'Generic direct JSON-RPC resource error recovery missed $_resourceUri.',
    );
  }

  final prompts = await client.requestDirect(
    'prompts/list',
    id: '$label-generic-direct-prompt-error-recovery',
  );
  if (!jsonEncode(prompts).contains(_promptName)) {
    throw StateError(
      'Generic direct JSON-RPC prompt error recovery missed $_promptName.',
    );
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError(
      'Generic direct JSON-RPC resource/prompt error recovery changed '
      'Streamable state.',
    );
  }
}

Future<void> _smokeGenericDirectJsonRpcPubSub(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final subscribeId = '$label-generic-direct-pubsub-subscribe';
  final subscribe = await client.requestDirect(
    'connectanum.pubsub.subscribe',
    id: subscribeId,
    params: {'topic': _topic, 'queueLimit': 4},
  );
  final subscription = _jsonRpcStructuredContent(
    subscribe,
    id: subscribeId,
    label: 'Generic direct JSON-RPC pub/sub subscribe',
  );
  final handle = subscription['handle'];
  if (handle is! String ||
      handle.isEmpty ||
      subscription['topic'] != _topic ||
      subscription['queueLimit'] != 4) {
    throw StateError(
      'Generic direct JSON-RPC pub/sub subscribe returned invalid content.',
    );
  }

  try {
    await _smokeGenericDirectJsonRpcWampSubscriptionMeta(
      client,
      serviceSession,
      label: label,
    );
    await _smokeDirectJsonBatchWampSubscriptionMeta(
      client,
      serviceSession,
      label: label,
    );
    await _smokeDirectJsonBatchPubSub(
      client,
      serviceSession,
      handle,
      label: label,
    );

    final publishId = '$label-generic-direct-pubsub-publish';
    final publishResponse = _jsonObjectFrom(
      await client.postDirect(
        {
          'jsonrpc': '2.0',
          'id': publishId,
          'method': 'connectanum.pubsub.publish',
          'params': {
            'topic': _topic,
            'argumentsKeywords': {
              'taskId': 'T-$label-generic-direct-pubsub-publish',
            },
            'acknowledge': true,
          },
        },
      ),
      label: 'Generic direct JSON-RPC pub/sub publish response',
    );
    final publication = _jsonRpcStructuredContent(
      publishResponse,
      id: publishId,
      label: 'Generic direct JSON-RPC pub/sub publish',
    );
    if (publication['topic'] != _topic ||
        publication['acknowledged'] != true) {
      throw StateError(
        'Generic direct JSON-RPC pub/sub publish returned invalid content.',
      );
    }

    final helperNotificationTaskId =
        'T-$label-generic-direct-pubsub-helper-notification';
    await client.notifyWampEventDirect(
      _topic,
      argumentsKeywords: {'taskId': helperNotificationTaskId},
      headers: {
        'x-consumer-trace':
            '$label-generic-direct-pubsub-helper-notification',
        'Mcp-Param-Topic': 'wrong-topic',
      },
    );
    await _pollGenericDirectJsonRpcPubSubUntil(
      client,
      handle,
      label: label,
      expectedTaskId: helperNotificationTaskId,
    );

    final serviceTaskId = 'T-$label-generic-direct-pubsub-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );
    await _pollGenericDirectJsonRpcPubSubUntil(
      client,
      handle,
      label: label,
      expectedTaskId: serviceTaskId,
    );
  } finally {
    final unsubscribeId = '$label-generic-direct-pubsub-unsubscribe';
    final unsubscribe = await client.requestDirect(
      'connectanum.pubsub.unsubscribe',
      id: unsubscribeId,
      params: {'handle': handle},
    );
    final unsubscribeContent = _jsonRpcStructuredContent(
      unsubscribe,
      id: unsubscribeId,
      label: 'Generic direct JSON-RPC pub/sub unsubscribe',
    );
    if (unsubscribeContent['handle'] != handle ||
        unsubscribeContent['topic'] != _topic ||
        unsubscribeContent['unsubscribed'] != true) {
      throw StateError(
        'Generic direct JSON-RPC pub/sub unsubscribe returned invalid content.',
      );
    }
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError(
      'Generic direct JSON-RPC pub/sub changed Streamable state.',
    );
  }
}

Future<void> _smokeGenericDirectJsonRpcWampSubscriptionMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final subscriptionLookupId = '$label-generic-direct-subscription-lookup';
  final subscriptionLookup = await client.requestDirect(
    'wamp.subscription.lookup',
    id: subscriptionLookupId,
    params: {'topic': _topic},
  );
  final subscriptionLookupContent = _jsonRpcStructuredContent(
    subscriptionLookup,
    id: subscriptionLookupId,
    label: 'Generic direct JSON-RPC WAMP subscription lookup',
  );
  final subscriptionLookupArguments = subscriptionLookupContent['arguments'];
  if (subscriptionLookupArguments is! List) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription lookup missed arguments.',
    );
  }
  final subscriptionId = _singleMetaId(
    subscriptionLookupArguments.cast<Object?>(),
    'generic direct subscription lookup',
  );
  if (subscriptionId <= 0) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription lookup returned invalid id '
      '$subscriptionId.',
    );
  }

  final subscriptionMatchId = '$label-generic-direct-subscription-match';
  final subscriptionMatch = await client.requestDirect(
    'wamp.subscription.match',
    id: subscriptionMatchId,
    params: {'topic': _topic},
  );
  final subscriptionMatchContent = _jsonRpcStructuredContent(
    subscriptionMatch,
    id: subscriptionMatchId,
    label: 'Generic direct JSON-RPC WAMP subscription match',
  );
  final subscriptionMatchArguments = subscriptionMatchContent['arguments'];
  if (subscriptionMatchArguments is! List) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription match missed arguments.',
    );
  }
  final matchedSubscriptionIds = _integerMetaIds(
    subscriptionMatchArguments.cast<Object?>(),
    'generic direct subscription match',
  );
  if (!matchedSubscriptionIds.contains(subscriptionId)) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription match missed $_topic.',
    );
  }

  final subscriptionListId = '$label-generic-direct-subscription-list';
  final subscriptionList = await client.requestDirect(
    'wamp.subscription.list',
    id: subscriptionListId,
  );
  final subscriptionListContent = _jsonRpcStructuredContent(
    subscriptionList,
    id: subscriptionListId,
    label: 'Generic direct JSON-RPC WAMP subscription list',
  );
  final subscriptionListKeywords = _jsonObjectFrom(
    subscriptionListContent['argumentsKeywords'],
    label: 'Generic direct JSON-RPC WAMP subscription list kwargs',
  );
  final exactSubscriptionIds = _integerMetaIdsFromValue(
    subscriptionListKeywords['exact'],
    'generic direct subscription list exact',
  );
  if (!exactSubscriptionIds.contains(subscriptionId)) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription list missed $_topic.',
    );
  }

  final subscriptionGetId = '$label-generic-direct-subscription-get';
  final subscriptionGet = await client.requestDirect(
    'wamp.subscription.get',
    id: subscriptionGetId,
    params: {'id': subscriptionId},
  );
  final subscriptionGetContent = _jsonRpcStructuredContent(
    subscriptionGet,
    id: subscriptionGetId,
    label: 'Generic direct JSON-RPC WAMP subscription get',
  );
  final subscriptionGetKeywords = _jsonObjectFrom(
    subscriptionGetContent['argumentsKeywords'],
    label: 'Generic direct JSON-RPC WAMP subscription get kwargs',
  );
  if (!jsonEncode(subscriptionGetKeywords).contains(_topic)) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription get missed $_topic.',
    );
  }

  final subscribersId = '$label-generic-direct-subscription-subscribers';
  final subscribers = await client.requestDirect(
    'wamp.subscription.list_subscribers',
    id: subscribersId,
    params: {'id': subscriptionId},
  );
  final subscribersContent = _jsonRpcStructuredContent(
    subscribers,
    id: subscribersId,
    label: 'Generic direct JSON-RPC WAMP subscription subscribers',
  );
  final subscriberArguments = subscribersContent['arguments'];
  if (subscriberArguments is! List) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription subscribers missed '
      'arguments.',
    );
  }
  final subscriberIds = _integerMetaIds(
    subscriberArguments.cast<Object?>(),
    'generic direct subscription subscribers',
  );
  if (subscriberIds.isEmpty) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription subscribers was empty.',
    );
  }
  if (subscriberIds.contains(serviceSession.sessionId)) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription subscribers leaked service '
      'session.',
    );
  }

  final subscriberCountId =
      '$label-generic-direct-subscription-subscriber-count';
  final subscriberCount = await client.requestDirect(
    'wamp.subscription.count_subscribers',
    id: subscriberCountId,
    params: {'id': subscriptionId},
  );
  final subscriberCountContent = _jsonRpcStructuredContent(
    subscriberCount,
    id: subscriberCountId,
    label: 'Generic direct JSON-RPC WAMP subscription subscriber count',
  );
  final subscriberCountArguments = subscriberCountContent['arguments'];
  if (subscriberCountArguments is! List) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription subscriber count missed '
      'arguments.',
    );
  }
  final subscriberTotal = _singleMetaId(
    subscriberCountArguments.cast<Object?>(),
    'generic direct subscription subscriber count',
  );
  if (subscriberTotal != subscriberIds.length) {
    throw StateError(
      'Generic direct JSON-RPC WAMP subscription subscriber count did not '
      'match visible sessions.',
    );
  }
}

Future<void> _smokeDirectJsonBatchWampSubscriptionMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final subscriptionLookupId =
      '$label-direct-batch-wamp-subscription-lookup';
  final subscriptionMatchId = '$label-direct-batch-wamp-subscription-match';
  final subscriptionListId = '$label-direct-batch-wamp-subscription-list';
  final discovery = await client.postBatchDirect(
    [
      {
        'jsonrpc': '2.0',
        'id': subscriptionLookupId,
        'method': 'wamp.subscription.lookup',
        'params': {'topic': _topic},
      },
      {
        'jsonrpc': '2.0',
        'id': subscriptionMatchId,
        'method': 'wamp.subscription.match',
        'params': {'topic': _topic},
      },
      {
        'jsonrpc': '2.0',
        'id': subscriptionListId,
        'method': 'wamp.subscription.list',
        'params': {},
      },
    ],
  );
  if (discovery == null) {
    throw StateError(
      'Direct JSON batch WAMP subscription meta discovery returned null.',
    );
  }
  final subscriptionId = _expectWampSubscriptionBatchDiscovery(
    discovery,
    subscriptionLookupId: subscriptionLookupId,
    subscriptionMatchId: subscriptionMatchId,
    subscriptionListId: subscriptionListId,
    modeLabel: 'Direct JSON batch WAMP subscription meta',
  );

  final subscriptionGetId = '$label-direct-batch-wamp-subscription-get';
  final subscribersId = '$label-direct-batch-wamp-subscription-subscribers';
  final subscriberCountId =
      '$label-direct-batch-wamp-subscription-subscriber-count';
  final details = await client.postBatchDirect(
    [
      {
        'jsonrpc': '2.0',
        'id': subscriptionGetId,
        'method': 'wamp.subscription.get',
        'params': {'id': subscriptionId},
      },
      {
        'jsonrpc': '2.0',
        'id': subscribersId,
        'method': 'wamp.subscription.list_subscribers',
        'params': {'id': subscriptionId},
      },
      {
        'jsonrpc': '2.0',
        'id': subscriberCountId,
        'method': 'wamp.subscription.count_subscribers',
        'params': {'id': subscriptionId},
      },
    ],
  );
  if (details == null) {
    throw StateError(
      'Direct JSON batch WAMP subscription meta details returned null.',
    );
  }
  _expectWampSubscriptionBatchDetails(
    details,
    subscriptionGetId: subscriptionGetId,
    subscribersId: subscribersId,
    subscriberCountId: subscriberCountId,
    serviceSession: serviceSession,
    modeLabel: 'Direct JSON batch WAMP subscription meta',
  );

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError(
      'Direct JSON batch WAMP subscription meta changed Streamable state.',
    );
  }
}

Future<void> _smokeDirectJsonBatchPubSub(
  McpStreamableHttpClient client,
  RouterSession serviceSession,
  String handle, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  String? tempHandle;

  try {
    final subscribeId = '$label-direct-batch-pubsub-subscribe';
    final apiListId = '$label-direct-batch-pubsub-api-list';
    final subscribeBatch = await client.postBatchDirect(
      [
        {
          'jsonrpc': '2.0',
          'id': subscribeId,
          'method': 'connectanum.pubsub.subscribe',
          'params': {'topic': _batchTopic, 'queueLimit': 2},
        },
        {
          'jsonrpc': '2.0',
          'id': apiListId,
          'method': 'connectanum.api.list',
          'params': {'kind': 'procedure'},
        },
      ],
    );
    if (subscribeBatch == null || subscribeBatch.length != 2) {
      throw StateError(
        'Direct JSON batch pub/sub subscribe did not return two responses.',
      );
    }
    final subscription = _jsonRpcStructuredContent(
      subscribeBatch[0],
      id: subscribeId,
      label: 'Direct JSON batch pub/sub subscribe',
    );
    final tempHandleValue = subscription['handle'];
    if (tempHandleValue is! String ||
        tempHandleValue.isEmpty ||
        subscription['topic'] != _batchTopic ||
        subscription['queueLimit'] != 2) {
      throw StateError(
        'Direct JSON batch pub/sub subscribe returned invalid content.',
      );
    }
    tempHandle = tempHandleValue;
    if (subscribeBatch[1]['id'] != apiListId ||
        !jsonEncode(subscribeBatch[1]).contains(_procedure)) {
      throw StateError('Direct JSON batch pub/sub API list was invalid.');
    }

    final publishId = '$label-direct-batch-pubsub-publish';
    final apiDescribeId = '$label-direct-batch-pubsub-api-describe';
    final publishBatch = await client.postBatchDirect(
      [
        {
          'jsonrpc': '2.0',
          'id': publishId,
          'method': 'connectanum.pubsub.publish',
          'params': {
            'topic': _topic,
            'argumentsKeywords': {
              'taskId': 'T-$label-direct-batch-pubsub-publish',
            },
            'acknowledge': true,
          },
        },
        {
          'jsonrpc': '2.0',
          'id': apiDescribeId,
          'method': 'connectanum.api.describe',
          'params': {'uri': _procedure, 'kind': 'procedure'},
        },
      ],
    );
    if (publishBatch == null || publishBatch.length != 2) {
      throw StateError(
        'Direct JSON batch pub/sub publish did not return two responses.',
      );
    }
    final publication = _jsonRpcStructuredContent(
      publishBatch[0],
      id: publishId,
      label: 'Direct JSON batch pub/sub publish',
    );
    if (publication['topic'] != _topic ||
        publication['acknowledged'] != true) {
      throw StateError(
        'Direct JSON batch pub/sub publish returned invalid content.',
      );
    }
    if (publishBatch[1]['id'] != apiDescribeId ||
        !jsonEncode(publishBatch[1]).contains(_procedure)) {
      throw StateError('Direct JSON batch pub/sub API describe was invalid.');
    }

    final serviceTaskId = 'T-$label-direct-batch-pubsub-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );
    await _pollDirectJsonBatchPubSubUntil(
      client,
      handle,
      label: label,
      expectedTaskId: serviceTaskId,
    );
  } finally {
    if (tempHandle != null) {
      final unsubscribeId = '$label-direct-batch-pubsub-unsubscribe';
      final apiListId = '$label-direct-batch-pubsub-unsubscribe-api-list';
      final unsubscribeBatch = await client.postBatchDirect(
        [
          {
            'jsonrpc': '2.0',
            'id': unsubscribeId,
            'method': 'connectanum.pubsub.unsubscribe',
            'params': {'handle': tempHandle},
          },
          {
            'jsonrpc': '2.0',
            'id': apiListId,
            'method': 'connectanum.api.list',
            'params': {'kind': 'procedure'},
          },
        ],
      );
      if (unsubscribeBatch == null || unsubscribeBatch.length != 2) {
        throw StateError(
          'Direct JSON batch pub/sub unsubscribe did not return two '
          'responses.',
        );
      }
      final unsubscribe = _jsonRpcStructuredContent(
        unsubscribeBatch[0],
        id: unsubscribeId,
        label: 'Direct JSON batch pub/sub unsubscribe',
      );
      if (unsubscribe['handle'] != tempHandle ||
          unsubscribe['topic'] != _batchTopic ||
          unsubscribe['unsubscribed'] != true) {
        throw StateError(
          'Direct JSON batch pub/sub unsubscribe returned invalid content.',
        );
      }
      if (unsubscribeBatch[1]['id'] != apiListId ||
          !jsonEncode(unsubscribeBatch[1]).contains(_procedure)) {
        throw StateError(
          'Direct JSON batch pub/sub unsubscribe API list was invalid.',
        );
      }
    }
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON batch pub/sub changed Streamable state.');
  }
}

Future<void> _smokeGenericStreamableJsonRpcAccess(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Generic Streamable JSON-RPC smoke has no session id.');
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError(
        'Generic Streamable JSON-RPC $operation changed session id.',
      );
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Generic Streamable JSON-RPC $operation did not advance SSE state.',
      );
    }
    previousEventId = eventId;
  }

  final notificationBatch = await client.postBatch(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': <String, Object?>{},
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/tools/list_changed',
        'params': <String, Object?>{},
      },
    ],
  );
  if (notificationBatch != null) {
    throw StateError(
      'Generic Streamable JSON-RPC notification-only batch returned a response.',
    );
  }
  if (client.sessionId != sessionId || client.lastEventId != previousEventId) {
    throw StateError(
      'Generic Streamable JSON-RPC notification-only batch changed session state.',
    );
  }
  await client.notification(
    'notifications/tools/list_changed',
    params: const <String, Object?>{},
  );
  if (client.sessionId != sessionId || client.lastEventId != previousEventId) {
    throw StateError(
      'Generic Streamable JSON-RPC notification changed session state.',
    );
  }

  await _expectGenericToolCatalog(
    client,
    label: '$label-generic-streamable',
    directJson: false,
    expectStreamableProgress: expectStreamableProgress,
  );

  final taskId = 'T-$label-generic-streamable-tool-call';
  final toolCallId = '$label-generic-streamable-tool-call';
  final toolCall = _jsonObjectFrom(
    await client.post(
      {
        'jsonrpc': '2.0',
        'id': toolCallId,
        'method': 'tools/call',
        'params': {
          'name': _procedure,
          'arguments': {'taskId': taskId, 'note': _headerWrappedNote},
        },
      },
      headers: {
        'Mcp-Method': 'consumer.streamable.wrong',
        'Mcp-Name': 'consumer.streamable.wrong',
        'Mcp-Param-TaskId': taskId,
        'Mcp-Param-Note': _mcpBase64Header(_headerWrappedNote),
      },
    ),
    label: 'Generic Streamable JSON-RPC tools/call response',
  );
  final toolContent = _jsonRpcStructuredContent(
    toolCall,
    id: toolCallId,
    label: 'Generic Streamable JSON-RPC tools/call',
  );
  final toolContentJson = jsonEncode(toolContent);
  if (!toolContentJson.contains(taskId) ||
      !toolContentJson.contains(_headerWrappedNote)) {
    throw StateError('Generic Streamable JSON-RPC tools/call failed.');
  }
  expectStreamableProgress('tools/call');

  final directMethodTaskId = 'T-$label-generic-streamable-direct-method';
  final directMethodId = '$label-generic-streamable-direct-method';
  final directMethod = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': directMethodId,
      'method': _procedure,
      'params': {
        'taskId': directMethodTaskId,
        'note': _headerWrappedNote,
      },
    }),
    label: 'Generic Streamable JSON-RPC direct method response',
  );
  final directMethodContent = _jsonRpcStructuredContent(
    directMethod,
    id: directMethodId,
    label: 'Generic Streamable JSON-RPC direct method',
  );
  final directMethodJson = jsonEncode(directMethodContent);
  if (!directMethodJson.contains(directMethodTaskId) ||
      !directMethodJson.contains(_headerWrappedNote)) {
    throw StateError('Generic Streamable JSON-RPC direct method failed.');
  }
  expectStreamableProgress('direct method');

  final aliasTaskId = 'T-$label-generic-streamable-tools-alias';
  final aliasId = '$label-generic-streamable-tools-alias';
  final alias = _jsonObjectFrom(
    await client.post(
      {
        'jsonrpc': '2.0',
        'id': aliasId,
        'method': 'connectanum.tools.call',
        'params': {
          'name': _procedure,
          'arguments': {
            'taskId': aliasTaskId,
            'note': _headerWrappedNote,
          },
        },
      },
      headers: {
        'Mcp-Param-TaskId': aliasTaskId,
        'Mcp-Param-Note': _mcpBase64Header(_headerWrappedNote),
      },
    ),
    label: 'Generic Streamable JSON-RPC connectanum.tools.call response',
  );
  final aliasContent = _jsonRpcStructuredContent(
    alias,
    id: aliasId,
    label: 'Generic Streamable JSON-RPC connectanum.tools.call',
  );
  final aliasJson = jsonEncode(aliasContent);
  if (!aliasJson.contains(aliasTaskId) ||
      !aliasJson.contains(_headerWrappedNote)) {
    throw StateError(
      'Generic Streamable JSON-RPC connectanum.tools.call failed.',
    );
  }
  expectStreamableProgress('connectanum.tools.call');

  final directApiListId = '$label-generic-streamable-direct-api-list';
  final directApiList = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': directApiListId,
      'method': 'connectanum.api.list',
      'params': {'kind': 'procedure'},
    }),
    label: 'Generic Streamable JSON-RPC direct API list response',
  );
  final directApiContent = _jsonRpcStructuredContent(
    directApiList,
    id: directApiListId,
    label: 'Generic Streamable JSON-RPC direct API list',
  );
  if (!jsonEncode(directApiContent).contains(_procedure)) {
    throw StateError(
      'Generic Streamable JSON-RPC direct API list missed $_procedure.',
    );
  }
  _expectSortedUniqueWampApiCatalog(
    directApiContent,
    label: 'Generic Streamable JSON-RPC direct API list',
    includeTopics: false,
  );
  expectStreamableProgress('direct WAMP API list');

  final directApiDescribeId = '$label-generic-streamable-direct-api-describe';
  final directApiDescribe = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': directApiDescribeId,
      'method': 'connectanum.api.describe',
      'params': {'uri': _procedure, 'kind': 'procedure'},
    }),
    label: 'Generic Streamable JSON-RPC direct API describe response',
  );
  final directApiDescription = _jsonRpcStructuredContent(
    directApiDescribe,
    id: directApiDescribeId,
    label: 'Generic Streamable JSON-RPC direct API describe',
  );
  if (!jsonEncode(directApiDescription).contains(_procedure)) {
    throw StateError(
      'Generic Streamable JSON-RPC direct API describe missed $_procedure.',
    );
  }
  expectStreamableProgress('direct WAMP API describe');

  final apiListId = '$label-generic-streamable-api-list';
  final apiList = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': apiListId,
      'method': 'tools/call',
      'params': {
        'name': 'connectanum.api.list',
        'arguments': {'kind': 'procedure'},
      },
    }),
    label: 'Generic Streamable JSON-RPC API list response',
  );
  final apiContent = _jsonRpcStructuredContent(
    apiList,
    id: apiListId,
    label: 'Generic Streamable JSON-RPC API list',
  );
  if (!jsonEncode(apiContent).contains(_procedure)) {
    throw StateError(
      'Generic Streamable JSON-RPC API list missed $_procedure.',
    );
  }
  _expectSortedUniqueWampApiCatalog(
    apiContent,
    label: 'Generic Streamable JSON-RPC API list',
    includeTopics: false,
  );
  expectStreamableProgress('WAMP API list');

  final apiDescribeId = '$label-generic-streamable-api-describe';
  final apiDescribe = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': apiDescribeId,
      'method': 'tools/call',
      'params': {
        'name': 'connectanum.api.describe',
        'arguments': {'uri': _procedure, 'kind': 'procedure'},
      },
    }),
    label: 'Generic Streamable JSON-RPC API describe response',
  );
  final apiDescription = _jsonRpcStructuredContent(
    apiDescribe,
    id: apiDescribeId,
    label: 'Generic Streamable JSON-RPC API describe',
  );
  if (!jsonEncode(apiDescription).contains(_procedure)) {
    throw StateError(
      'Generic Streamable JSON-RPC API describe missed $_procedure.',
    );
  }
  expectStreamableProgress('WAMP API describe');

  final sessionCountId = '$label-generic-streamable-session-count';
  final sessionCount = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': sessionCountId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.session.count',
        'arguments': {},
      },
    }),
    label: 'Generic Streamable JSON-RPC WAMP session count response',
  );
  final sessionCountContent = _jsonRpcStructuredContent(
    sessionCount,
    id: sessionCountId,
    label: 'Generic Streamable JSON-RPC WAMP session count',
  );
  final sessionCountKeywords = _jsonObjectFrom(
    sessionCountContent['argumentsKeywords'],
    label: 'Generic Streamable JSON-RPC WAMP session count kwargs',
  );
  final visibleSessionCount = sessionCountKeywords['count'];
  if (visibleSessionCount is! int) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP session count missed count metadata.',
    );
  }
  expectStreamableProgress('WAMP session count');

  final sessionListId = '$label-generic-streamable-session-list';
  final sessionList = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': sessionListId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.session.list',
        'arguments': {},
      },
    }),
    label: 'Generic Streamable JSON-RPC WAMP session list response',
  );
  final sessionListContent = _jsonRpcStructuredContent(
    sessionList,
    id: sessionListId,
    label: 'Generic Streamable JSON-RPC WAMP session list',
  );
  final sessionListKeywords = _jsonObjectFrom(
    sessionListContent['argumentsKeywords'],
    label: 'Generic Streamable JSON-RPC WAMP session list kwargs',
  );
  final sessionIds = _integerMetaIdsFromValue(
    sessionListKeywords['session_ids'],
    'generic streamable session list',
  );
  if (sessionIds.contains(serviceSession.sessionId)) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP session list leaked service session.',
    );
  }
  if (sessionIds.length != visibleSessionCount) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP session count did not match list.',
    );
  }
  if (sessionIds.isEmpty) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP session list missed visible sessions.',
    );
  }
  expectStreamableProgress('WAMP session list');

  final visibleSessionId = sessionIds.first;
  final sessionGetId = '$label-generic-streamable-session-get';
  final sessionGet = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': sessionGetId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.session.get',
        'arguments': {
          'arguments': [visibleSessionId],
        },
      },
    }),
    label: 'Generic Streamable JSON-RPC WAMP session get response',
  );
  final sessionGetContent = _jsonRpcStructuredContent(
    sessionGet,
    id: sessionGetId,
    label: 'Generic Streamable JSON-RPC WAMP session get',
  );
  final sessionGetKeywords = _jsonObjectFrom(
    sessionGetContent['argumentsKeywords'],
    label: 'Generic Streamable JSON-RPC WAMP session get kwargs',
  );
  final sessionDetails = _jsonObjectFrom(
    sessionGetKeywords['details'],
    label: 'Generic Streamable JSON-RPC WAMP session details',
  );
  if (sessionDetails['id'] != visibleSessionId) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP session get missed visible session.',
    );
  }
  expectStreamableProgress('WAMP session get');

  final registrationLookupId = '$label-generic-streamable-registration-lookup';
  final registrationLookup = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': registrationLookupId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.lookup',
        'arguments': {
          'arguments': [_procedure],
        },
      },
    }),
    label: 'Generic Streamable JSON-RPC WAMP registration lookup response',
  );
  final registrationLookupContent = _jsonRpcStructuredContent(
    registrationLookup,
    id: registrationLookupId,
    label: 'Generic Streamable JSON-RPC WAMP registration lookup',
  );
  final registrationLookupArguments = registrationLookupContent['arguments'];
  if (registrationLookupArguments is! List) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration lookup missed arguments.',
    );
  }
  final registrationId = _singleMetaId(
    registrationLookupArguments.cast<Object?>(),
    'generic streamable registration lookup',
  );
  if (registrationId <= 0) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration lookup returned '
      'invalid id $registrationId.',
    );
  }
  expectStreamableProgress('WAMP registration lookup');

  final registrationMatchId = '$label-generic-streamable-registration-match';
  final registrationMatch = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': registrationMatchId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.match',
        'arguments': {
          'arguments': [_procedure],
        },
      },
    }),
    label: 'Generic Streamable JSON-RPC WAMP registration match response',
  );
  final registrationMatchContent = _jsonRpcStructuredContent(
    registrationMatch,
    id: registrationMatchId,
    label: 'Generic Streamable JSON-RPC WAMP registration match',
  );
  final registrationMatchArguments = registrationMatchContent['arguments'];
  if (registrationMatchArguments is! List) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration match missed arguments.',
    );
  }
  final matchingRegistrationId = _singleMetaId(
    registrationMatchArguments.cast<Object?>(),
    'generic streamable registration match',
  );
  if (matchingRegistrationId != registrationId) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration match did not agree '
      'with lookup.',
    );
  }
  expectStreamableProgress('WAMP registration match');

  final registrationListId = '$label-generic-streamable-registration-list';
  final registrationList = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': registrationListId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.list',
        'arguments': {},
      },
    }),
    label: 'Generic Streamable JSON-RPC WAMP registration list response',
  );
  final registrationListContent = _jsonRpcStructuredContent(
    registrationList,
    id: registrationListId,
    label: 'Generic Streamable JSON-RPC WAMP registration list',
  );
  final registrationListKeywords = _jsonObjectFrom(
    registrationListContent['argumentsKeywords'],
    label: 'Generic Streamable JSON-RPC WAMP registration list kwargs',
  );
  final exactRegistrationIds = _integerMetaIdsFromValue(
    registrationListKeywords['exact'],
    'generic streamable registration list exact',
  );
  if (!exactRegistrationIds.contains(registrationId)) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration list missed $_procedure.',
    );
  }
  expectStreamableProgress('WAMP registration list');

  final registrationGetId = '$label-generic-streamable-registration-get';
  final registrationGet = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': registrationGetId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.get',
        'arguments': {
          'arguments': [registrationId],
        },
      },
    }),
    label: 'Generic Streamable JSON-RPC WAMP registration get response',
  );
  final registrationGetContent = _jsonRpcStructuredContent(
    registrationGet,
    id: registrationGetId,
    label: 'Generic Streamable JSON-RPC WAMP registration get',
  );
  final registrationGetKeywords = _jsonObjectFrom(
    registrationGetContent['argumentsKeywords'],
    label: 'Generic Streamable JSON-RPC WAMP registration get kwargs',
  );
  if (registrationGetKeywords['uri'] != _procedure) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration get missed $_procedure.',
    );
  }
  expectStreamableProgress('WAMP registration get');

  final registrationCalleesId =
      '$label-generic-streamable-registration-callees';
  final registrationCallees = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': registrationCalleesId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.list_callees',
        'arguments': {
          'arguments': [registrationId],
        },
      },
    }),
    label: 'Generic Streamable JSON-RPC WAMP registration callees response',
  );
  final registrationCalleesContent = _jsonRpcStructuredContent(
    registrationCallees,
    id: registrationCalleesId,
    label: 'Generic Streamable JSON-RPC WAMP registration callees',
  );
  final registrationCalleeArguments = registrationCalleesContent['arguments'];
  if (registrationCalleeArguments is! List) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration callees missed '
      'arguments.',
    );
  }
  final calleeIds = _integerMetaIds(
    registrationCalleeArguments.cast<Object?>(),
    'generic streamable registration callees',
  );
  if (calleeIds.contains(serviceSession.sessionId) || calleeIds.isNotEmpty) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration callees leaked '
      'internal sessions.',
    );
  }
  expectStreamableProgress('WAMP registration callees');

  final registrationCalleeCountId =
      '$label-generic-streamable-registration-callee-count';
  final registrationCalleeCount = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': registrationCalleeCountId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.count_callees',
        'arguments': {
          'arguments': [registrationId],
        },
      },
    }),
    label:
        'Generic Streamable JSON-RPC WAMP registration callee count response',
  );
  final registrationCalleeCountContent = _jsonRpcStructuredContent(
    registrationCalleeCount,
    id: registrationCalleeCountId,
    label: 'Generic Streamable JSON-RPC WAMP registration callee count',
  );
  final registrationCalleeCountArguments =
      registrationCalleeCountContent['arguments'];
  if (registrationCalleeCountArguments is! List) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration callee count missed '
      'arguments.',
    );
  }
  final calleeCount = _singleMetaId(
    registrationCalleeCountArguments.cast<Object?>(),
    'generic streamable registration callee count',
  );
  if (calleeCount != 0) {
    throw StateError(
      'Generic Streamable JSON-RPC WAMP registration callee count leaked '
      'internal sessions.',
    );
  }
  expectStreamableProgress('WAMP registration callee count');

  await _expectGenericCatalogPages(
    client,
    label: '$label-generic-streamable-resources',
    method: 'resources/list',
    resultKey: 'resources',
    field: 'uri',
    fieldDescription: 'resource URI',
    expectedPrimary: _resourceUri,
    expectedPaged: _pagedResourceUri,
    directJson: false,
    expectStreamableProgress: expectStreamableProgress,
  );

  final readId = '$label-generic-streamable-resource-read';
  final read = await client.request(
    'resources/read',
    id: readId,
    params: {'uri': _resourceUri},
  );
  final readResult = _jsonRpcResult(
    read,
    id: readId,
    label: 'Generic Streamable JSON-RPC resources/read',
  );
  if (!jsonEncode(readResult['contents']).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError(
      'Generic Streamable JSON-RPC resources/read missed route context.',
    );
  }
  expectStreamableProgress('resources/read');

  await _expectGenericCatalogPages(
    client,
    label: '$label-generic-streamable-resource-templates',
    method: 'resources/templates/list',
    resultKey: 'resourceTemplates',
    field: 'uriTemplate',
    fieldDescription: 'resource template URI',
    expectedPrimary: _resourceTemplateUri,
    expectedPaged: _pagedResourceTemplateUri,
    directJson: false,
    expectStreamableProgress: expectStreamableProgress,
  );

  await _expectGenericCatalogPages(
    client,
    label: '$label-generic-streamable-prompts',
    method: 'prompts/list',
    resultKey: 'prompts',
    field: 'name',
    fieldDescription: 'prompt name',
    expectedPrimary: _promptName,
    expectedPaged: _pagedPromptName,
    directJson: false,
    expectStreamableProgress: expectStreamableProgress,
  );

  final promptTaskId = 'T-$label-generic-streamable-prompt';
  final promptId = '$label-generic-streamable-prompt-get';
  final prompt = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': promptId,
      'method': 'prompts/get',
      'params': {
        'name': _promptName,
        'arguments': {'taskId': promptTaskId},
      },
    }),
    label: 'Generic Streamable JSON-RPC prompts/get response',
  );
  final promptResult = _jsonRpcResult(
    prompt,
    id: promptId,
    label: 'Generic Streamable JSON-RPC prompts/get',
  );
  if (!jsonEncode(promptResult).contains(promptTaskId)) {
    throw StateError(
      'Generic Streamable JSON-RPC prompts/get did not substitute '
      '$promptTaskId.',
    );
  }
  expectStreamableProgress('prompts/get');

  final directSubscribeId =
      '$label-generic-streamable-direct-pubsub-subscribe';
  final directSubscribe = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': directSubscribeId,
      'method': 'connectanum.pubsub.subscribe',
      'params': {'topic': _topic, 'queueLimit': 4},
    }),
    label: 'Generic Streamable JSON-RPC direct pub/sub subscribe response',
  );
  final directSubscription = _jsonRpcStructuredContent(
    directSubscribe,
    id: directSubscribeId,
    label: 'Generic Streamable JSON-RPC direct pub/sub subscribe',
  );
  final directHandle = directSubscription['handle'];
  if (directHandle is! String ||
      directHandle.isEmpty ||
      directSubscription['topic'] != _topic ||
      directSubscription['queueLimit'] != 4) {
    throw StateError(
      'Generic Streamable JSON-RPC direct pub/sub subscribe returned invalid '
      'content.',
    );
  }
  expectStreamableProgress('direct pub/sub subscribe');

  try {
    final directPublishId =
        '$label-generic-streamable-direct-pubsub-publish';
    final directPublish = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': directPublishId,
        'method': 'connectanum.pubsub.publish',
        'params': {
          'topic': _topic,
          'argumentsKeywords': {
            'taskId': 'T-$label-generic-streamable-direct-pubsub-publish',
          },
          'acknowledge': true,
        },
      }),
      label: 'Generic Streamable JSON-RPC direct pub/sub publish response',
    );
    final directPublication = _jsonRpcStructuredContent(
      directPublish,
      id: directPublishId,
      label: 'Generic Streamable JSON-RPC direct pub/sub publish',
    );
    if (directPublication['topic'] != _topic ||
        directPublication['acknowledged'] != true) {
      throw StateError(
        'Generic Streamable JSON-RPC direct pub/sub publish returned invalid '
        'content.',
      );
    }
    expectStreamableProgress('direct pub/sub publish');

    final directServiceTaskId =
        'T-$label-generic-streamable-direct-pubsub-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': directServiceTaskId},
      options: PublishOptions(acknowledge: true),
    );

    final directDeadline = DateTime.now().add(const Duration(seconds: 5));
    var sawDirectServiceEvent = false;
    while (DateTime.now().isBefore(directDeadline)) {
      final directPollId =
          '$label-generic-streamable-direct-pubsub-poll-'
          '${DateTime.now().microsecondsSinceEpoch}';
      final directPoll = _jsonObjectFrom(
        await client.post({
          'jsonrpc': '2.0',
          'id': directPollId,
          'method': 'connectanum.pubsub.poll',
          'params': {'handle': directHandle, 'limit': 4},
        }),
        label: 'Generic Streamable JSON-RPC direct pub/sub poll response',
      );
      final directEventBatch = _jsonRpcStructuredContent(
        directPoll,
        id: directPollId,
        label: 'Generic Streamable JSON-RPC direct pub/sub poll',
      );
      if (directEventBatch['handle'] != directHandle ||
          directEventBatch['topic'] != _topic) {
        throw StateError(
          'Generic Streamable JSON-RPC direct pub/sub poll returned invalid '
          'content.',
        );
      }
      expectStreamableProgress('direct pub/sub poll');
      if (jsonEncode(directEventBatch['events']).contains(
        directServiceTaskId,
      )) {
        sawDirectServiceEvent = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (!sawDirectServiceEvent) {
      throw StateError(
        'Generic Streamable JSON-RPC direct pub/sub poll missed service '
        'event.',
      );
    }
  } finally {
    final directUnsubscribeId =
        '$label-generic-streamable-direct-pubsub-unsubscribe';
    final directUnsubscribe = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': directUnsubscribeId,
        'method': 'connectanum.pubsub.unsubscribe',
        'params': {'handle': directHandle},
      }),
      label:
          'Generic Streamable JSON-RPC direct pub/sub unsubscribe response',
    );
    final directUnsubscribeContent = _jsonRpcStructuredContent(
      directUnsubscribe,
      id: directUnsubscribeId,
      label: 'Generic Streamable JSON-RPC direct pub/sub unsubscribe',
    );
    if (directUnsubscribeContent['handle'] != directHandle ||
        directUnsubscribeContent['topic'] != _topic ||
        directUnsubscribeContent['unsubscribed'] != true) {
      throw StateError(
        'Generic Streamable JSON-RPC direct pub/sub unsubscribe returned '
        'invalid content.',
      );
    }
    expectStreamableProgress('direct pub/sub unsubscribe');
  }

  await _smokeStreamableBatchDirectWampApiPubSub(
    client,
    serviceSession,
    label: label,
  );
  previousEventId = client.lastEventId;

  final subscribeId = '$label-generic-streamable-pubsub-subscribe';
  final subscribe = _jsonObjectFrom(
    await client.post({
      'jsonrpc': '2.0',
      'id': subscribeId,
      'method': 'tools/call',
      'params': {
        'name': 'connectanum.pubsub.subscribe',
        'arguments': {'topic': _topic, 'queueLimit': 4},
      },
    }),
    label: 'Generic Streamable JSON-RPC pub/sub subscribe response',
  );
  final subscription = _jsonRpcStructuredContent(
    subscribe,
    id: subscribeId,
    label: 'Generic Streamable JSON-RPC pub/sub subscribe',
  );
  final handle = subscription['handle'];
  if (handle is! String ||
      handle.isEmpty ||
      subscription['topic'] != _topic ||
      subscription['queueLimit'] != 4) {
    throw StateError(
      'Generic Streamable JSON-RPC pub/sub subscribe returned invalid content.',
    );
  }
  expectStreamableProgress('pub/sub subscribe');

  try {
    final subscriptionLookupId =
        '$label-generic-streamable-subscription-lookup';
    final subscriptionLookup = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': subscriptionLookupId,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.subscription.lookup',
          'arguments': {
            'arguments': [_topic],
          },
        },
      }),
      label:
          'Generic Streamable JSON-RPC WAMP subscription lookup response',
    );
    final subscriptionLookupContent = _jsonRpcStructuredContent(
      subscriptionLookup,
      id: subscriptionLookupId,
      label: 'Generic Streamable JSON-RPC WAMP subscription lookup',
    );
    final subscriptionLookupArguments =
        subscriptionLookupContent['arguments'];
    if (subscriptionLookupArguments is! List) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription lookup missed '
        'arguments.',
      );
    }
    final subscriptionId = _singleMetaId(
      subscriptionLookupArguments.cast<Object?>(),
      'generic streamable subscription lookup',
    );
    if (subscriptionId <= 0) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription lookup returned '
        'invalid id $subscriptionId.',
      );
    }
    expectStreamableProgress('WAMP subscription lookup');

    final subscriptionMatchId =
        '$label-generic-streamable-subscription-match';
    final subscriptionMatch = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': subscriptionMatchId,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.subscription.match',
          'arguments': {
            'arguments': [_topic],
          },
        },
      }),
      label: 'Generic Streamable JSON-RPC WAMP subscription match response',
    );
    final subscriptionMatchContent = _jsonRpcStructuredContent(
      subscriptionMatch,
      id: subscriptionMatchId,
      label: 'Generic Streamable JSON-RPC WAMP subscription match',
    );
    final subscriptionMatchArguments =
        subscriptionMatchContent['arguments'];
    if (subscriptionMatchArguments is! List) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription match missed '
        'arguments.',
      );
    }
    final matchedSubscriptionIds = _integerMetaIds(
      subscriptionMatchArguments.cast<Object?>(),
      'generic streamable subscription match',
    );
    if (!matchedSubscriptionIds.contains(subscriptionId)) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription match missed $_topic.',
      );
    }
    expectStreamableProgress('WAMP subscription match');

    final subscriptionListId =
        '$label-generic-streamable-subscription-list';
    final subscriptionList = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': subscriptionListId,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.subscription.list',
          'arguments': {},
        },
      }),
      label: 'Generic Streamable JSON-RPC WAMP subscription list response',
    );
    final subscriptionListContent = _jsonRpcStructuredContent(
      subscriptionList,
      id: subscriptionListId,
      label: 'Generic Streamable JSON-RPC WAMP subscription list',
    );
    final subscriptionListKeywords = _jsonObjectFrom(
      subscriptionListContent['argumentsKeywords'],
      label: 'Generic Streamable JSON-RPC WAMP subscription list kwargs',
    );
    final exactSubscriptionIds = _integerMetaIdsFromValue(
      subscriptionListKeywords['exact'],
      'generic streamable subscription list exact',
    );
    if (!exactSubscriptionIds.contains(subscriptionId)) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription list missed $_topic.',
      );
    }
    expectStreamableProgress('WAMP subscription list');

    final subscriptionGetId = '$label-generic-streamable-subscription-get';
    final subscriptionGet = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': subscriptionGetId,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.subscription.get',
          'arguments': {
            'arguments': [subscriptionId],
          },
        },
      }),
      label: 'Generic Streamable JSON-RPC WAMP subscription get response',
    );
    final subscriptionGetContent = _jsonRpcStructuredContent(
      subscriptionGet,
      id: subscriptionGetId,
      label: 'Generic Streamable JSON-RPC WAMP subscription get',
    );
    final subscriptionGetKeywords = _jsonObjectFrom(
      subscriptionGetContent['argumentsKeywords'],
      label: 'Generic Streamable JSON-RPC WAMP subscription get kwargs',
    );
    if (!jsonEncode(subscriptionGetKeywords).contains(_topic)) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription get missed $_topic.',
      );
    }
    expectStreamableProgress('WAMP subscription get');

    final subscribersId = '$label-generic-streamable-subscription-subscribers';
    final subscribers = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': subscribersId,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.subscription.list_subscribers',
          'arguments': {
            'arguments': [subscriptionId],
          },
        },
      }),
      label:
          'Generic Streamable JSON-RPC WAMP subscription subscribers response',
    );
    final subscribersContent = _jsonRpcStructuredContent(
      subscribers,
      id: subscribersId,
      label: 'Generic Streamable JSON-RPC WAMP subscription subscribers',
    );
    final subscriberArguments = subscribersContent['arguments'];
    if (subscriberArguments is! List) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription subscribers missed '
        'arguments.',
      );
    }
    final subscriberIds = _integerMetaIds(
      subscriberArguments.cast<Object?>(),
      'generic streamable subscription subscribers',
    );
    if (subscriberIds.isEmpty) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription subscribers was empty.',
      );
    }
    if (subscriberIds.contains(serviceSession.sessionId)) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription subscribers leaked '
        'service session.',
      );
    }
    expectStreamableProgress('WAMP subscription subscribers');

    final subscriberCountId =
        '$label-generic-streamable-subscription-subscriber-count';
    final subscriberCount = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': subscriberCountId,
        'method': 'tools/call',
        'params': {
          'name': 'wamp.subscription.count_subscribers',
          'arguments': {
            'arguments': [subscriptionId],
          },
        },
      }),
      label:
          'Generic Streamable JSON-RPC WAMP subscription subscriber count '
          'response',
    );
    final subscriberCountContent = _jsonRpcStructuredContent(
      subscriberCount,
      id: subscriberCountId,
      label: 'Generic Streamable JSON-RPC WAMP subscription subscriber count',
    );
    final subscriberCountArguments = subscriberCountContent['arguments'];
    if (subscriberCountArguments is! List) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription subscriber count '
        'missed arguments.',
      );
    }
    final subscriberTotal = _singleMetaId(
      subscriberCountArguments.cast<Object?>(),
      'generic streamable subscription subscriber count',
    );
    if (subscriberTotal != subscriberIds.length) {
      throw StateError(
        'Generic Streamable JSON-RPC WAMP subscription subscriber count did '
        'not match visible sessions.',
      );
    }
    expectStreamableProgress('WAMP subscription subscriber count');

    await _smokeStreamableBatchWampSubscriptionMeta(
      client,
      serviceSession,
      label: label,
    );
    await _smokeStreamableBatchPubSub(
      client,
      serviceSession,
      handle,
      label: label,
    );
    previousEventId = client.lastEventId;

    final publishId = '$label-generic-streamable-pubsub-publish';
    final publish = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': publishId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.publish',
          'arguments': {
            'topic': _topic,
            'argumentsKeywords': {
              'taskId': 'T-$label-generic-streamable-pubsub-publish',
            },
            'acknowledge': true,
          },
        },
      }),
      label: 'Generic Streamable JSON-RPC pub/sub publish response',
    );
    final publication = _jsonRpcStructuredContent(
      publish,
      id: publishId,
      label: 'Generic Streamable JSON-RPC pub/sub publish',
    );
    if (publication['topic'] != _topic ||
        publication['acknowledged'] != true) {
      throw StateError(
        'Generic Streamable JSON-RPC pub/sub publish returned invalid content.',
      );
    }
    expectStreamableProgress('pub/sub publish');

    final serviceTaskId = 'T-$label-generic-streamable-pubsub-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var sawServiceEvent = false;
    while (DateTime.now().isBefore(deadline)) {
      final pollId =
          '$label-generic-streamable-pubsub-poll-'
          '${DateTime.now().microsecondsSinceEpoch}';
      final poll = _jsonObjectFrom(
        await client.post({
          'jsonrpc': '2.0',
          'id': pollId,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.poll',
            'arguments': {'handle': handle, 'limit': 4},
          },
        }),
        label: 'Generic Streamable JSON-RPC pub/sub poll response',
      );
      final eventBatch = _jsonRpcStructuredContent(
        poll,
        id: pollId,
        label: 'Generic Streamable JSON-RPC pub/sub poll',
      );
      if (eventBatch['handle'] != handle || eventBatch['topic'] != _topic) {
        throw StateError(
          'Generic Streamable JSON-RPC pub/sub poll returned invalid content.',
        );
      }
      expectStreamableProgress('pub/sub poll');
      if (jsonEncode(eventBatch['events']).contains(serviceTaskId)) {
        sawServiceEvent = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (!sawServiceEvent) {
      throw StateError(
        'Generic Streamable JSON-RPC pub/sub poll missed service event.',
      );
    }
  } finally {
    final unsubscribeId = '$label-generic-streamable-pubsub-unsubscribe';
    final unsubscribe = _jsonObjectFrom(
      await client.post({
        'jsonrpc': '2.0',
        'id': unsubscribeId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.unsubscribe',
          'arguments': {'handle': handle},
        },
      }),
      label: 'Generic Streamable JSON-RPC pub/sub unsubscribe response',
    );
    final unsubscribeContent = _jsonRpcStructuredContent(
      unsubscribe,
      id: unsubscribeId,
      label: 'Generic Streamable JSON-RPC pub/sub unsubscribe',
    );
    if (unsubscribeContent['handle'] != handle ||
        unsubscribeContent['topic'] != _topic ||
        unsubscribeContent['unsubscribed'] != true) {
      throw StateError(
        'Generic Streamable JSON-RPC pub/sub unsubscribe returned invalid '
        'content.',
      );
    }
    expectStreamableProgress('pub/sub unsubscribe');
  }
}

Future<void> _smokeStreamableBatchDirectWampApiPubSub(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP direct batch WAMP API/pubsub has no session id.',
    );
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError(
        'Streamable MCP direct batch WAMP API/pubsub $operation changed '
        'session id.',
      );
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Streamable MCP direct batch WAMP API/pubsub $operation did not '
        'update SSE state.',
      );
    }
    previousEventId = eventId;
  }

  String? tempHandle;
  try {
    final subscribeId =
        '$label-streamable-direct-batch-pubsub-subscribe';
    final apiListId = '$label-streamable-direct-batch-api-list';
    final subscribeBatch = await client.postBatch([
      {
        'jsonrpc': '2.0',
        'id': subscribeId,
        'method': 'connectanum.pubsub.subscribe',
        'params': {'topic': _batchTopic, 'queueLimit': 4},
      },
      {
        'jsonrpc': '2.0',
        'id': apiListId,
        'method': 'connectanum.api.list',
        'params': {'kind': 'procedure'},
      },
    ]);
    if (subscribeBatch == null || subscribeBatch.length != 2) {
      throw StateError(
        'Streamable MCP direct batch pub/sub subscribe did not return two '
        'responses.',
      );
    }
    final subscription = _jsonRpcStructuredContent(
      subscribeBatch[0],
      id: subscribeId,
      label: 'Streamable MCP direct batch pub/sub subscribe',
    );
    final tempHandleValue = subscription['handle'];
    if (tempHandleValue is! String ||
        tempHandleValue.isEmpty ||
        subscription['topic'] != _batchTopic ||
        subscription['queueLimit'] != 4) {
      throw StateError(
        'Streamable MCP direct batch pub/sub subscribe returned invalid '
        'content.',
      );
    }
    tempHandle = tempHandleValue;
    if (subscribeBatch[1]['id'] != apiListId ||
        !jsonEncode(subscribeBatch[1]).contains(_procedure)) {
      throw StateError(
        'Streamable MCP direct batch WAMP API list was invalid.',
      );
    }
    expectStreamableProgress('subscribe batch');

    final publishId = '$label-streamable-direct-batch-pubsub-publish';
    final topicDescribeId =
        '$label-streamable-direct-batch-topic-describe';
    final publishBatch = await client.postBatch([
      {
        'jsonrpc': '2.0',
        'id': publishId,
        'method': 'connectanum.pubsub.publish',
        'params': {
          'topic': _batchTopic,
          'argumentsKeywords': {
            'taskId': 'T-$label-streamable-direct-batch-pubsub-publish',
          },
          'acknowledge': true,
        },
      },
      {
        'jsonrpc': '2.0',
        'id': topicDescribeId,
        'method': 'connectanum.api.describe',
        'params': {'uri': _batchTopic, 'kind': 'topic'},
      },
    ]);
    if (publishBatch == null || publishBatch.length != 2) {
      throw StateError(
        'Streamable MCP direct batch pub/sub publish did not return two '
        'responses.',
      );
    }
    final publication = _jsonRpcStructuredContent(
      publishBatch[0],
      id: publishId,
      label: 'Streamable MCP direct batch pub/sub publish',
    );
    if (publication['topic'] != _batchTopic ||
        publication['acknowledged'] != true) {
      throw StateError(
        'Streamable MCP direct batch pub/sub publish returned invalid content.',
      );
    }
    if (publishBatch[1]['id'] != topicDescribeId ||
        !jsonEncode(publishBatch[1]).contains(_batchTopic)) {
      throw StateError(
        'Streamable MCP direct batch WAMP topic describe was invalid.',
      );
    }
    expectStreamableProgress('publish batch');

    final serviceTaskId = 'T-$label-streamable-direct-batch-pubsub-event';
    await serviceSession.publish(
      _batchTopic,
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var sawServiceEvent = false;
    while (DateTime.now().isBefore(deadline)) {
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final pollId = '$label-streamable-direct-batch-pubsub-poll-$timestamp';
      final topicListId =
          '$label-streamable-direct-batch-topic-list-$timestamp';
      final pollBatch = await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': pollId,
          'method': 'connectanum.pubsub.poll',
          'params': {'handle': tempHandle, 'limit': 4},
        },
        {
          'jsonrpc': '2.0',
          'id': topicListId,
          'method': 'connectanum.api.list',
          'params': {'kind': 'topic'},
        },
      ]);
      if (pollBatch == null || pollBatch.length != 2) {
        throw StateError(
          'Streamable MCP direct batch pub/sub poll did not return two '
          'responses.',
        );
      }
      final eventBatch = _jsonRpcStructuredContent(
        pollBatch[0],
        id: pollId,
        label: 'Streamable MCP direct batch pub/sub poll',
      );
      if (eventBatch['handle'] != tempHandle ||
          eventBatch['topic'] != _batchTopic) {
        throw StateError(
          'Streamable MCP direct batch pub/sub poll returned invalid content.',
        );
      }
      if (pollBatch[1]['id'] != topicListId ||
          !jsonEncode(pollBatch[1]).contains(_batchTopic)) {
        throw StateError(
          'Streamable MCP direct batch WAMP topic list was invalid.',
        );
      }
      expectStreamableProgress('poll batch');
      if (jsonEncode(eventBatch['events']).contains(serviceTaskId)) {
        sawServiceEvent = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (!sawServiceEvent) {
      throw StateError(
        'Streamable MCP direct batch pub/sub poll missed service event.',
      );
    }
  } finally {
    if (tempHandle != null) {
      final unsubscribeId =
          '$label-streamable-direct-batch-pubsub-unsubscribe';
      final apiListId =
          '$label-streamable-direct-batch-unsubscribe-api-list';
      final unsubscribeBatch = await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': unsubscribeId,
          'method': 'connectanum.pubsub.unsubscribe',
          'params': {'handle': tempHandle},
        },
        {
          'jsonrpc': '2.0',
          'id': apiListId,
          'method': 'connectanum.api.list',
          'params': {'kind': 'procedure'},
        },
      ]);
      if (unsubscribeBatch == null || unsubscribeBatch.length != 2) {
        throw StateError(
          'Streamable MCP direct batch pub/sub unsubscribe did not return two '
          'responses.',
        );
      }
      final unsubscribe = _jsonRpcStructuredContent(
        unsubscribeBatch[0],
        id: unsubscribeId,
        label: 'Streamable MCP direct batch pub/sub unsubscribe',
      );
      if (unsubscribe['handle'] != tempHandle ||
          unsubscribe['topic'] != _batchTopic ||
          unsubscribe['unsubscribed'] != true) {
        throw StateError(
          'Streamable MCP direct batch pub/sub unsubscribe returned invalid '
          'content.',
        );
      }
      if (unsubscribeBatch[1]['id'] != apiListId ||
          !jsonEncode(unsubscribeBatch[1]).contains(_procedure)) {
        throw StateError(
          'Streamable MCP direct batch unsubscribe API list was invalid.',
        );
      }
      expectStreamableProgress('unsubscribe batch');
    }
  }
}

Future<void> _pollGenericDirectJsonRpcPubSubUntil(
  McpStreamableHttpClient client,
  String handle, {
  required String label,
  required String expectedTaskId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final pollId =
        '$label-generic-direct-pubsub-poll-'
        '${DateTime.now().microsecondsSinceEpoch}';
    final poll = await client.requestDirect(
      'connectanum.pubsub.poll',
      id: pollId,
      params: {'handle': handle, 'limit': 4},
    );
    final eventBatch = _jsonRpcStructuredContent(
      poll,
      id: pollId,
      label: 'Generic direct JSON-RPC pub/sub poll',
    );
    if (eventBatch['handle'] != handle || eventBatch['topic'] != _topic) {
      throw StateError(
        'Generic direct JSON-RPC pub/sub poll returned invalid content.',
      );
    }
    if (jsonEncode(eventBatch['events']).contains(expectedTaskId)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'Timed out waiting for generic direct JSON-RPC pub/sub event.',
  );
}

Future<void> _pollDirectJsonBatchPubSubUntil(
  McpStreamableHttpClient client,
  String handle, {
  required String label,
  required String expectedTaskId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final pollId = '$label-direct-batch-pubsub-poll-$timestamp';
    final apiListId = '$label-direct-batch-pubsub-poll-api-$timestamp';
    final pollBatch = await client.postBatchDirect(
      [
        {
          'jsonrpc': '2.0',
          'id': pollId,
          'method': 'connectanum.pubsub.poll',
          'params': {'handle': handle, 'limit': 4},
        },
        {
          'jsonrpc': '2.0',
          'id': apiListId,
          'method': 'connectanum.api.list',
          'params': {'kind': 'procedure'},
        },
      ],
    );
    if (pollBatch == null || pollBatch.length != 2) {
      throw StateError(
        'Direct JSON batch pub/sub poll did not return two responses.',
      );
    }
    final eventBatch = _jsonRpcStructuredContent(
      pollBatch[0],
      id: pollId,
      label: 'Direct JSON batch pub/sub poll',
    );
    if (eventBatch['handle'] != handle || eventBatch['topic'] != _topic) {
      throw StateError(
        'Direct JSON batch pub/sub poll returned invalid content.',
      );
    }
    if (pollBatch[1]['id'] != apiListId ||
        !jsonEncode(pollBatch[1]).contains(_procedure)) {
      throw StateError('Direct JSON batch pub/sub poll API list was invalid.');
    }
    if (jsonEncode(eventBatch['events']).contains(expectedTaskId)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for direct JSON batch pub/sub event.');
}

Future<void> _smokeStreamableMcp(
  McpStreamableHttpClient client,
  RouterSession serviceSession,
  {required String label}
) async {
  await _assertRejectedStreamableInitializeDoesNotCaptureSession(
    client,
    label: label,
  );
  await _assertClientSuppliedStreamableInitializeSessionRejected(
    client,
    label: label,
  );
  await _assertMalformedStreamableSessionRejected(client, label: label);

  final initializeResult = await client.initialize(
    clientInfo: const {
      'name': 'connectanum_consumer_package_smoke',
      'version': '0.1.0',
    },
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-initialize',
    },
  );
  final initializeJson = jsonEncode(initializeResult);
  if (!initializeJson.contains('resources') ||
      !initializeJson.contains('prompts')) {
    throw StateError(
      'Streamable MCP initialize did not advertise resources and prompts.',
    );
  }
  if (label == 'public') {
    _expectPublicMcpInitializeMetadata(initializeResult);
  }
  await client.notifyInitialized(
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-initialized',
    },
  );

  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP initialize did not capture a session id.');
  }
  final eventIdBeforeDirectCatalog = client.lastEventId;
  await _expectPagedToolCatalog(
    client,
    label: '$label-after-streamable',
    directJson: true,
  );
  if (client.sessionId != sessionId ||
      client.lastEventId != eventIdBeforeDirectCatalog) {
    throw StateError(
      'Direct JSON tool catalog changed Streamable MCP session state.',
    );
  }

  await _smokeDirectJsonSingleError(
    client,
    label: '$label-direct-after-streamable',
  );
  await _smokeDirectJsonWhileStreamableInitialized(
    client,
    serviceSession,
    label: label,
  );

  final result = await client.callTool(
    _procedure,
    id: '$label-streamable-direct-catalog-call',
    arguments: {
      'taskId': 'T-$label-streamable-direct-catalog',
      'note': _headerWrappedNote,
    },
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-direct-catalog-call',
    },
  );
  final resultJson = jsonEncode(result);
  if (!resultJson.contains('T-$label-streamable-direct-catalog') ||
      !resultJson.contains(_headerWrappedNote)) {
    throw StateError('Streamable MCP tool call returned unexpected payload.');
  }

  await _expectPagedToolCatalog(
    client,
    label: label,
    directJson: false,
  );

  await _smokeGenericStreamableJsonRpcAccess(
    client,
    serviceSession,
    label: label,
  );
  await _smokeStreamableSingleError(client, label: label);
  await _smokeStreamableBatch(client, serviceSession, label: label);
  await _smokeResourcesAndPrompts(client, label: label);
  await _smokeStreamableResourcePromptErrors(client, label: label);
  await _smokeWampMetaDiscovery(client, serviceSession, label: label);

  final subscription = await client.subscribeWampTopic(
    _topic,
    id: '$label-streamable-subscribe',
    queueLimit: 4,
    options: mcpWampSubscribeOptions(
      match: 'exact',
      custom: <String, Object?>{
        'x_consumer_subscription': '$label-streamable-subscribe',
      },
    ),
  );
  try {
    final subscribers = await _smokeWampSubscriptionMeta(
      client,
      serviceSession,
      label: label,
    );
    final subscriber = subscribers.first;

    final selfPublication = await client.publishWampEvent(
      _topic,
      id: '$label-streamable-publish',
      argumentsKeywords: {'taskId': 'T-$label-streamable-publish'},
      options: mcpWampPublishOptions(
        acknowledge: true,
        excludeMe: false,
        custom: <String, Object?>{
          'x_consumer_trace': '$label-streamable-publish',
        },
      ),
    );
    if (!selfPublication.acknowledged) {
      throw StateError('Streamable MCP pub/sub publish was not acknowledged.');
    }
    final selfEvents = await _pollMcpEventsUntil(client, subscription.handle);
    if (!jsonEncode(selfEvents.events).contains(
      'T-$label-streamable-publish',
    )) {
      throw StateError(
        'Streamable MCP pub/sub publish with exclude_me=false was not '
        'delivered to its own subscription.',
      );
    }

    final excludedPublication = await client.publishWampEvent(
      _topic,
      id: '$label-streamable-publish-exclude-me',
      argumentsKeywords: {'taskId': 'T-$label-streamable-publish-exclude-me'},
      options: mcpWampPublishOptions(
        acknowledge: true,
        excludeMe: true,
        custom: <String, Object?>{
          'x_consumer_trace': '$label-streamable-publish-exclude-me',
        },
      ),
    );
    if (!excludedPublication.acknowledged) {
      throw StateError(
        'Streamable MCP pub/sub exclude_me publish was not acknowledged.',
      );
    }
    final excludedEvents = await client.pollWampEvents(
      subscription.handle,
      id: '$label-streamable-poll-exclude-me',
      limit: 4,
    );
    if (jsonEncode(excludedEvents.events).contains(
      'T-$label-streamable-publish-exclude-me',
    )) {
      throw StateError(
        'Streamable MCP pub/sub publish with exclude_me=true reached its own '
        'subscription.',
      );
    }

    await _smokeWampPublishSessionFilters(
      client,
      subscription.handle,
      subscriber,
      label: label,
    );

    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': 'T-$label-streamable-event'},
      options: PublishOptions(acknowledge: true),
    );
    final events = await _pollMcpEventsUntil(client, subscription.handle);
    if (!jsonEncode(events.events).contains('T-$label-streamable-event')) {
      throw StateError('Streamable MCP pub/sub poll missed service event.');
    }
  } finally {
    await client.unsubscribeWampTopic(
      subscription.handle,
      id: '$label-streamable-unsubscribe',
    );
  }
  await _smokeMcpPubSubQueueOverflow(
    client,
    serviceSession,
    label: label,
    directJson: false,
  );
  await _smokeStreamableNotificationToolCall(client, label: label);
  await _smokeStreamableNotificationPubSub(client, label: label);

  await _smokeStreamableSessionLifecycle(
    client,
    serviceSession,
    label: label,
  );
}

Future<void> _assertRejectedStreamableInitializeDoesNotCaptureSession(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final rejected = await client.post(
    const <String, Object?>{
      'jsonrpc': '2.0',
      'id': 'rejected-initialize',
      'method': 'initialize',
      'params': <String, Object?>{
        'protocolVersion': 123,
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{
          'name': 'connectanum_consumer_package_smoke',
          'version': '0.1.0',
        },
      },
    },
    includeSession: false,
    headers: <String, String>{
      'x-consumer-trace': '$label-rejected-streamable-initialize',
    },
  );
  if (rejected == null ||
      rejected['id'] != 'rejected-initialize' ||
      rejected['error'] is! Map<String, Object?>) {
    throw StateError(
      'Rejected Streamable MCP initialize did not return a JSON-RPC error.',
    );
  }
  if (!jsonEncode(rejected['error']).contains('protocolVersion')) {
    throw StateError(
      'Rejected Streamable MCP initialize did not explain protocolVersion.',
    );
  }
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError(
      'Rejected Streamable MCP initialize captured session state.',
    );
  }
}

Future<void> _assertClientSuppliedStreamableInitializeSessionRejected(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final httpClient = HttpClient();
  try {
    final request = await httpClient.postUrl(client.endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/event-stream',
    );
    request.headers.set(
      'MCP-Protocol-Version',
      McpStreamableHttpClient.latestProtocolVersion,
    );
    request.headers.set('Mcp-Method', 'initialize');
    request.headers.set('MCP-Session-Id', 'consumer-chosen-session');
    request.headers.set('origin', _allowedOrigin);
    request.headers.set(
      'x-consumer-trace',
      '$label-client-session-initialize',
    );
    for (final entry in client.headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final body = utf8.encode(
      jsonEncode(const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'client-session-initialize',
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': McpStreamableHttpClient.latestProtocolVersion,
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{
            'name': 'connectanum_consumer_package_smoke',
            'version': '0.1.0',
          },
        },
      }),
    );
    request.contentLength = body.length;
    request.add(body);
    final response = await _mcpRawResponseFrom(await request.close());
    if (response.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Client-supplied Streamable MCP initialize session returned '
        '${response.statusCode}, expected 400.',
      );
    }
    if (response.header('mcp-session-id') != null) {
      throw StateError(
        'Client-supplied Streamable MCP initialize session was echoed.',
      );
    }
    if (!response.body.contains('MCP-Session-Id')) {
      throw StateError(
        'Client-supplied Streamable MCP initialize session was rejected '
        'without explaining MCP-Session-Id.',
      );
    }
    if (client.sessionId != null || client.lastEventId != null) {
      throw StateError(
        'Client-supplied Streamable MCP initialize changed client state.',
      );
    }
  } finally {
    httpClient.close(force: true);
  }
}

Future<void> _assertMalformedStreamableSessionRejected(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  const malformedSessionId = 'malformed session';
  final httpClient = HttpClient();
  try {
    Future<HttpClientRequest> openRequest(
      String method, {
      required String accept,
      String? mcpMethod,
    }) async {
      final request = await httpClient.openUrl(method, client.endpoint);
      request.headers.set('origin', _allowedOrigin);
      request.headers.set(HttpHeaders.acceptHeader, accept);
      request.headers.set(
        'MCP-Protocol-Version',
        McpStreamableHttpClient.latestProtocolVersion,
      );
      request.headers.set('MCP-Session-Id', malformedSessionId);
      request.headers.set(
        'x-consumer-trace',
        '$label-malformed-session-${method.toLowerCase()}',
      );
      if (mcpMethod != null) {
        request.headers.set('Mcp-Method', mcpMethod);
      }
      for (final entry in client.headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      return request;
    }

    Future<void> expectRejected(
      Future<HttpClientResponse> responseFuture,
      String operation,
    ) async {
      final response = await _mcpRawResponseFrom(await responseFuture);
      if (response.statusCode != HttpStatus.badRequest) {
        throw StateError(
          'Malformed Streamable MCP session $operation returned '
          '${response.statusCode}, expected 400.',
        );
      }
      if (response.header('mcp-session-id') != null) {
        throw StateError(
          'Malformed Streamable MCP session $operation echoed MCP-Session-Id.',
        );
      }
      if (!response.body.contains('MCP-Session-Id')) {
        throw StateError(
          'Malformed Streamable MCP session $operation was rejected without '
          'explaining MCP-Session-Id.',
        );
      }
      if (client.sessionId != null || client.lastEventId != null) {
        throw StateError(
          'Malformed Streamable MCP session $operation changed client state.',
        );
      }
    }

    final post = await openRequest(
      'POST',
      accept: 'application/json, text/event-stream',
      mcpMethod: 'tools/list',
    );
    post.headers.contentType = ContentType.json;
    final postBody = utf8.encode(
      jsonEncode(const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'malformed-session-tools',
        'method': 'tools/list',
        'params': <String, Object?>{},
      }),
    );
    post.contentLength = postBody.length;
    post.add(postBody);
    await expectRejected(post.close(), 'POST');

    final poll = await openRequest('GET', accept: 'text/event-stream');
    await expectRejected(poll.close(), 'GET');

    final delete = await openRequest(
      'DELETE',
      accept: 'application/json, text/event-stream',
    );
    await expectRejected(delete.close(), 'DELETE');
  } finally {
    httpClient.close(force: true);
  }
}

Future<void> _smokeDirectJsonWhileStreamableInitialized(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP direct JSON smoke has no session id.');
  }
  final eventId = client.lastEventId;

  final ping = await client.pingDirect(
    id: '$label-direct-after-streamable-ping',
    headers: <String, String>{
      'x-consumer-trace': '$label-direct-after-streamable-ping',
    },
  );
  if (ping.isNotEmpty) {
    throw StateError(
      'Direct JSON MCP ping after Streamable initialization returned data.',
    );
  }

  await _smokeDirectToolApi(
    client,
    label: '$label-direct-after-streamable',
  );
  await _smokeDirectWampApiHelpers(
    client,
    label: '$label-direct-after-streamable',
  );
  await _smokeGenericDirectJsonRpcAccess(
    client,
    serviceSession,
    label: '$label-after-streamable',
  );
  await _smokeGenericDirectJsonRpcPubSub(
    client,
    serviceSession,
    label: '$label-after-streamable',
  );
  await _smokeDirectJsonBatch(
    client,
    serviceSession,
    label: '$label-after-streamable',
  );
  await _smokeGenericDirectJsonRpcResourcesAndPrompts(
    client,
    label: '$label-direct-after-streamable',
  );
  await _smokeGenericDirectJsonRpcResourcePromptErrors(
    client,
    label: '$label-direct-after-streamable',
  );
  await _smokeResourcesAndPrompts(
    client,
    label: '$label-direct-after-streamable',
    directJson: true,
  );
  await _smokeDirectWampMetaHelpers(
    client,
    serviceSession,
    label: '$label-direct-after-streamable',
  );

  await _smokeWampMetaDiscovery(
    client,
    serviceSession,
    label: '$label-direct-after-streamable',
    directJson: true,
  );

  final subscription = await client.subscribeWampTopicDirect(
    _topic,
    id: '$label-direct-after-streamable-subscribe',
    queueLimit: 4,
  );
  try {
    final subscribers = await _smokeWampSubscriptionMeta(
      client,
      serviceSession,
      label: '$label-direct-after-streamable',
      directJson: true,
    );
    final subscriber = subscribers.first;

    await _smokeWampPublishSessionFilters(
      client,
      subscription.handle,
      subscriber,
      label: '$label-direct-after-streamable',
      directJson: true,
    );

    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': 'T-$label-direct-after-streamable-event'},
      options: PublishOptions(acknowledge: true),
    );
    final events = await _pollMcpEventsUntil(
      client,
      subscription.handle,
      directJson: true,
    );
    if (!jsonEncode(events.events).contains(
      'T-$label-direct-after-streamable-event',
    )) {
      throw StateError(
        'Direct JSON MCP pub/sub poll missed service event after '
        'Streamable initialization.',
      );
    }
  } finally {
    await client.unsubscribeWampTopicDirect(
      subscription.handle,
      id: '$label-direct-after-streamable-unsubscribe',
    );
  }

  if (client.sessionId != sessionId || client.lastEventId != eventId) {
    throw StateError(
      'Direct JSON helpers changed Streamable MCP session state.',
    );
  }
}

Future<void> _smokeDirectJsonSingleError(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final missingTool = 'missing.$label.direct.single';
  final errorId = '$label-direct-error-missing';
  try {
    await client.callToolDirect(
      missingTool,
      id: errorId,
      arguments: {},
    );
    throw StateError('Direct JSON single error smoke accepted a missing tool.');
  } on McpJsonRpcException catch (error) {
    _expectMcpJsonRpcException(
      error,
      id: errorId,
      method: 'tools/call',
      messageSubstring: missingTool,
      label: 'Direct JSON single missing tool',
    );
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON single error changed Streamable state.');
  }

  await _expectPagedToolCatalog(
    client,
    label: '$label-direct-error-recovery',
    directJson: true,
  );
  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON error recovery changed Streamable state.');
  }
}

Future<void> _smokeStreamableSingleError(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP single error smoke has no initialized session id.',
    );
  }

  final previousEventId = client.lastEventId;
  final missingTool = 'missing.$label.streamable.single';
  final errorId = '$label-streamable-error-missing';
  try {
    await client.callTool(missingTool, id: errorId, arguments: {});
    throw StateError('Streamable MCP single error smoke accepted missing tool.');
  } on McpJsonRpcException catch (error) {
    _expectMcpJsonRpcException(
      error,
      id: errorId,
      method: 'tools/call',
      messageSubstring: missingTool,
      label: 'Streamable MCP single missing tool',
    );
  }

  if (client.sessionId != sessionId) {
    throw StateError('Streamable MCP single error changed session id.');
  }
  final eventIdAfterError = client.lastEventId;
  if (eventIdAfterError == null ||
      !eventIdAfterError.startsWith('$sessionId:') ||
      eventIdAfterError == previousEventId) {
    throw StateError(
      'Streamable MCP single error did not update SSE event state.',
    );
  }

  await _expectPagedToolCatalog(
    client,
    label: '$label-streamable-error-recovery',
    directJson: false,
  );
  if (client.sessionId != sessionId) {
    throw StateError(
      'Streamable MCP single error recovery changed session id.',
    );
  }
  final eventIdAfterRecovery = client.lastEventId;
  if (eventIdAfterRecovery == null ||
      !eventIdAfterRecovery.startsWith('$sessionId:') ||
      eventIdAfterRecovery == eventIdAfterError) {
    throw StateError(
      'Streamable MCP single error recovery did not update SSE state.',
    );
  }
}

Future<void> _smokeStreamableResourcePromptErrors(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP resource/prompt error smoke has no session id.',
    );
  }

  var previousEventId = client.lastEventId;
  final missingResourceUri = 'connectanum://consumer/$label/missing-resource';
  final resourceErrorId = '$label-streamable-resource-error';
  try {
    await client.readResource(missingResourceUri, id: resourceErrorId);
    throw StateError(
      'Streamable MCP resource error smoke accepted missing resource.',
    );
  } on McpJsonRpcException catch (error) {
    _expectMcpJsonRpcException(
      error,
      id: resourceErrorId,
      method: 'resources/read',
      messageSubstring: missingResourceUri,
      label: 'Streamable MCP missing resource',
    );
  }

  if (client.sessionId != sessionId) {
    throw StateError('Streamable MCP resource error changed session id.');
  }
  final eventIdAfterResourceError = client.lastEventId;
  if (eventIdAfterResourceError == null ||
      !eventIdAfterResourceError.startsWith('$sessionId:') ||
      eventIdAfterResourceError == previousEventId) {
    throw StateError(
      'Streamable MCP resource error did not update SSE event state.',
    );
  }
  previousEventId = eventIdAfterResourceError;

  final missingPromptName = 'missing-$label-streamable-prompt';
  final promptErrorId = '$label-streamable-prompt-error';
  try {
    await client.getPrompt(
      missingPromptName,
      id: promptErrorId,
      arguments: {},
    );
    throw StateError(
      'Streamable MCP prompt error smoke accepted missing prompt.',
    );
  } on McpJsonRpcException catch (error) {
    _expectMcpJsonRpcException(
      error,
      id: promptErrorId,
      method: 'prompts/get',
      messageSubstring: missingPromptName,
      label: 'Streamable MCP missing prompt',
    );
  }

  if (client.sessionId != sessionId) {
    throw StateError('Streamable MCP prompt error changed session id.');
  }
  final eventIdAfterPromptError = client.lastEventId;
  if (eventIdAfterPromptError == null ||
      !eventIdAfterPromptError.startsWith('$sessionId:') ||
      eventIdAfterPromptError == previousEventId) {
    throw StateError(
      'Streamable MCP prompt error did not update SSE event state.',
    );
  }
  previousEventId = eventIdAfterPromptError;

  final resources = await client.listResources(
    id: '$label-streamable-resource-error-recovery',
  );
  final resourceUris = {
    for (final resource in resources.resources) resource['uri'],
  };
  if (!resourceUris.contains(_resourceUri)) {
    throw StateError(
      'Streamable MCP resource error recovery missed $_resourceUri.',
    );
  }
  if (client.sessionId != sessionId) {
    throw StateError(
      'Streamable MCP resource error recovery changed session id.',
    );
  }
  final eventIdAfterResourceRecovery = client.lastEventId;
  if (eventIdAfterResourceRecovery == null ||
      !eventIdAfterResourceRecovery.startsWith('$sessionId:') ||
      eventIdAfterResourceRecovery == previousEventId) {
    throw StateError(
      'Streamable MCP resource error recovery did not update SSE state.',
    );
  }
  previousEventId = eventIdAfterResourceRecovery;

  final prompts = await client.listPrompts(
    id: '$label-streamable-prompt-error-recovery',
  );
  final promptNames = {for (final prompt in prompts.prompts) prompt['name']};
  if (!promptNames.contains(_promptName)) {
    throw StateError(
      'Streamable MCP prompt error recovery missed $_promptName.',
    );
  }
  if (client.sessionId != sessionId) {
    throw StateError(
      'Streamable MCP prompt error recovery changed session id.',
    );
  }
  final eventIdAfterPromptRecovery = client.lastEventId;
  if (eventIdAfterPromptRecovery == null ||
      !eventIdAfterPromptRecovery.startsWith('$sessionId:') ||
      eventIdAfterPromptRecovery == previousEventId) {
    throw StateError(
      'Streamable MCP prompt error recovery did not update SSE state.',
    );
  }
}

Future<void> _smokeDirectJsonBatch(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final taskId = 'T-$label-direct-batch';
  final directProcedureTaskId = 'T-$label-direct-batch-procedure';
  final aliasTaskId = 'T-$label-direct-batch-tools-alias';
  final promptTaskId = 'T-$label-direct-batch-prompt';
  final notificationTaskId = 'T-$label-direct-batch-notification';
  final responses = await client.postBatchDirect(
    [
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-api',
        'method': 'connectanum.api.list',
        'params': {'kind': 'procedure'},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-tools',
        'method': 'tools/list',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-call',
        'method': 'tools/call',
        'params': {
          'name': _procedure,
          'arguments': {'taskId': taskId},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-procedure',
        'method': _procedure,
        'params': {'taskId': directProcedureTaskId},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-tools-alias',
        'method': 'connectanum.tools.call',
        'params': {
          'name': _procedure,
          'arguments': {'taskId': aliasTaskId, 'note': _headerWrappedNote},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-resources',
        'method': 'resources/list',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-prompt',
        'method': 'prompts/get',
        'params': {
          'name': _promptName,
          'arguments': {'taskId': promptTaskId},
        },
      },
      {
        'jsonrpc': '2.0',
        'method': 'connectanum.tool.call',
        'params': {
          'name': _procedure,
          'arguments': {'taskId': notificationTaskId},
        },
      },
    ],
  );
  if (responses == null || responses.length != 7) {
    throw StateError('Direct JSON batch did not return seven responses.');
  }
  if (responses[0]['id'] != '$label-direct-batch-api' ||
      !jsonEncode(responses[0]).contains(_procedure)) {
    throw StateError('Direct JSON batch API catalog response was invalid.');
  }
  await _expectBatchToolCatalogPages(
    client,
    headResponse: responses[1],
    headId: '$label-direct-batch-tools',
    label: 'Direct JSON batch tools/list',
    idPrefix: '$label-direct-batch-tools',
    method: 'tools/list',
    directJson: true,
  );
  if (responses[2]['id'] != '$label-direct-batch-call' ||
      !jsonEncode(responses[2]).contains(taskId)) {
    throw StateError('Direct JSON batch tools/call response was invalid.');
  }
  if (responses[3]['id'] != '$label-direct-batch-procedure' ||
      !jsonEncode(responses[3]).contains(directProcedureTaskId)) {
    throw StateError('Direct JSON batch procedure alias response was invalid.');
  }
  if (responses[4]['id'] != '$label-direct-batch-tools-alias' ||
      !jsonEncode(responses[4]).contains(aliasTaskId) ||
      !jsonEncode(responses[4]).contains(_headerWrappedNote)) {
    throw StateError(
      'Direct JSON batch plural tool alias response was invalid.',
    );
  }
  final resourceCursor = _expectPaginatedCatalogHead(
    responses[5],
    id: '$label-direct-batch-resources',
    label: 'Direct JSON batch resources/list',
    resultKey: 'resources',
    field: 'uri',
    fieldDescription: 'resource URIs',
    expectedPrimary: _resourceUri,
  );
  if (responses[6]['id'] != '$label-direct-batch-prompt' ||
      !jsonEncode(responses[6]).contains(promptTaskId)) {
    throw StateError('Direct JSON batch prompts/get response was invalid.');
  }
  await _expectConsumerProcedureInvocation(
    notificationTaskId,
    label: 'Direct JSON mixed batch notification',
  );
  await _smokeDirectJsonBatchResourcePromptDetails(
    client,
    label: label,
    resourceCursor: resourceCursor,
  );
  await _smokeDirectJsonBatchErrorIsolation(client, label: label);
  await _smokeDirectJsonBatchWampMeta(
    client,
    serviceSession,
    label: label,
  );
  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON batch changed Streamable session state.');
  }
}

Future<void> _smokeDirectJsonBatchResourcePromptDetails(
  McpStreamableHttpClient client, {
  required String label,
  required String resourceCursor,
}) async {
  final detailBatch = await client.postBatchDirect(
    [
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-resource-read',
        'method': 'resources/read',
        'params': {'uri': _resourceUri},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-resource-templates',
        'method': 'resources/templates/list',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-prompts',
        'method': 'prompts/list',
        'params': {},
      },
    ],
  );
  if (detailBatch == null || detailBatch.length != 3) {
    throw StateError(
      'Direct JSON batch resource/prompt details did not return three '
      'responses.',
    );
  }

  final resource = _jsonRpcResult(
    detailBatch[0],
    id: '$label-direct-batch-resource-read',
    label: 'Direct JSON batch resources/read',
  );
  if (!jsonEncode(resource['contents']).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError(
      'Direct JSON batch resources/read missed route context.',
    );
  }

  final templateCursor = _expectPaginatedCatalogHead(
    detailBatch[1],
    id: '$label-direct-batch-resource-templates',
    label: 'Direct JSON batch resources/templates/list',
    resultKey: 'resourceTemplates',
    field: 'uriTemplate',
    fieldDescription: 'resource template URIs',
    expectedPrimary: _resourceTemplateUri,
  );
  final promptCursor = _expectPaginatedCatalogHead(
    detailBatch[2],
    id: '$label-direct-batch-prompts',
    label: 'Direct JSON batch prompts/list',
    resultKey: 'prompts',
    field: 'name',
    fieldDescription: 'prompt names',
    expectedPrimary: _promptName,
  );

  final cursorBatch = await client.postBatchDirect(
    [
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-resources-cursor',
        'method': 'resources/list',
        'params': {'cursor': resourceCursor},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-resource-templates-cursor',
        'method': 'resources/templates/list',
        'params': {'cursor': templateCursor},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-prompts-cursor',
        'method': 'prompts/list',
        'params': {'cursor': promptCursor},
      },
    ],
  );
  if (cursorBatch == null || cursorBatch.length != 3) {
    throw StateError(
      'Direct JSON batch resource/prompt cursor pages did not return three '
      'responses.',
    );
  }
  _expectCatalogCursorPage(
    cursorBatch[0],
    id: '$label-direct-batch-resources-cursor',
    label: 'Direct JSON batch resources/list cursor',
    resultKey: 'resources',
    field: 'uri',
    fieldDescription: 'resource URIs',
    expectedPaged: _pagedResourceUri,
  );
  _expectCatalogCursorPage(
    cursorBatch[1],
    id: '$label-direct-batch-resource-templates-cursor',
    label: 'Direct JSON batch resources/templates/list cursor',
    resultKey: 'resourceTemplates',
    field: 'uriTemplate',
    fieldDescription: 'resource template URIs',
    expectedPaged: _pagedResourceTemplateUri,
  );
  _expectCatalogCursorPage(
    cursorBatch[2],
    id: '$label-direct-batch-prompts-cursor',
    label: 'Direct JSON batch prompts/list cursor',
    resultKey: 'prompts',
    field: 'name',
    fieldDescription: 'prompt names',
    expectedPaged: _pagedPromptName,
  );
}

Future<void> _smokeDirectJsonBatchWampMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionCountId = '$label-direct-batch-wamp-session-count';
  final sessionListId = '$label-direct-batch-wamp-session-list';
  final registrationLookupId = '$label-direct-batch-wamp-registration-lookup';
  final registrationMatchId = '$label-direct-batch-wamp-registration-match';
  final registrationListId = '$label-direct-batch-wamp-registration-list';
  final discovery = await client.postBatchDirect(
    [
      {
        'jsonrpc': '2.0',
        'id': sessionCountId,
        'method': 'wamp.session.count',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': sessionListId,
        'method': 'wamp.session.list',
        'params': {},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationLookupId,
        'method': 'wamp.registration.lookup',
        'params': {'uri': _procedure},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationMatchId,
        'method': 'wamp.registration.match',
        'params': {'uri': _procedure},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationListId,
        'method': 'wamp.registration.list',
        'params': {},
      },
    ],
  );
  if (discovery == null) {
    throw StateError('Direct JSON batch WAMP meta discovery returned null.');
  }
  final ids = _expectWampRegistrationSessionBatchDiscovery(
    discovery,
    sessionCountId: sessionCountId,
    sessionListId: sessionListId,
    registrationLookupId: registrationLookupId,
    registrationMatchId: registrationMatchId,
    registrationListId: registrationListId,
    serviceSession: serviceSession,
    modeLabel: 'Direct JSON batch WAMP meta',
  );

  final visibleSessionId = ids[0];
  final registrationId = ids[1];
  final sessionGetId = '$label-direct-batch-wamp-session-get';
  final registrationGetId = '$label-direct-batch-wamp-registration-get';
  final registrationCalleesId =
      '$label-direct-batch-wamp-registration-callees';
  final registrationCalleeCountId =
      '$label-direct-batch-wamp-registration-callee-count';
  final details = await client.postBatchDirect(
    [
      {
        'jsonrpc': '2.0',
        'id': sessionGetId,
        'method': 'wamp.session.get',
        'params': {'id': visibleSessionId},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationGetId,
        'method': 'wamp.registration.get',
        'params': {'id': registrationId},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationCalleesId,
        'method': 'wamp.registration.list_callees',
        'params': {'id': registrationId},
      },
      {
        'jsonrpc': '2.0',
        'id': registrationCalleeCountId,
        'method': 'wamp.registration.count_callees',
        'params': {'id': registrationId},
      },
    ],
  );
  if (details == null) {
    throw StateError('Direct JSON batch WAMP meta details returned null.');
  }
  _expectWampRegistrationSessionBatchDetails(
    details,
    sessionGetId: sessionGetId,
    registrationGetId: registrationGetId,
    registrationCalleesId: registrationCalleesId,
    registrationCalleeCountId: registrationCalleeCountId,
    visibleSessionId: visibleSessionId,
    serviceSession: serviceSession,
    modeLabel: 'Direct JSON batch WAMP meta',
  );

  final topicListId = '$label-direct-batch-wamp-topic-list';
  final topicDescribeId = '$label-direct-batch-wamp-topic-describe';
  final topics = await client.postBatchDirect(
    [
      {
        'jsonrpc': '2.0',
        'id': topicListId,
        'method': 'connectanum.api.list',
        'params': {'kind': 'topic'},
      },
      {
        'jsonrpc': '2.0',
        'id': topicDescribeId,
        'method': 'connectanum.api.describe',
        'params': {'uri': _topic, 'kind': 'topic'},
      },
    ],
  );
  if (topics == null) {
    throw StateError('Direct JSON batch WAMP topic meta returned null.');
  }
  _expectWampTopicBatchMetadata(
    topics,
    topicListId: topicListId,
    topicDescribeId: topicDescribeId,
    topicUri: _topic,
    topicDescription: 'Consumer task lifecycle event stream',
    modeLabel: 'Direct JSON batch WAMP topic meta',
  );
}

Future<void> _smokeStreamableBatch(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP batch has no initialized session id.');
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError('Streamable MCP batch $operation changed session id.');
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Streamable MCP batch $operation did not update SSE event state.',
      );
    }
    previousEventId = eventId;
  }

  final taskId = 'T-$label-streamable-batch';
  final promptTaskId = 'T-$label-streamable-batch-prompt';
  final responses = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-tools',
      'method': 'tools/list',
      'params': {},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-call',
      'method': 'tools/call',
      'params': {
        'name': _procedure,
        'arguments': {'taskId': taskId},
      },
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-resources',
      'method': 'resources/list',
      'params': {},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-prompt',
      'method': 'prompts/get',
      'params': {
        'name': _promptName,
        'arguments': {'taskId': promptTaskId},
      },
    },
    {'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}},
  ]);
  if (responses == null || responses.length != 4) {
    throw StateError('Streamable MCP batch did not return four responses.');
  }
  expectStreamableProgress('initial batch');
  await _expectBatchToolCatalogPages(
    client,
    headResponse: responses[0],
    headId: '$label-streamable-batch-tools',
    label: 'Streamable MCP batch tools/list',
    idPrefix: '$label-streamable-batch-tools',
    method: 'tools/list',
    directJson: false,
    expectStreamableProgress: expectStreamableProgress,
  );
  if (responses[1]['id'] != '$label-streamable-batch-call' ||
      !jsonEncode(responses[1]).contains(taskId)) {
    throw StateError('Streamable MCP batch tools/call response was invalid.');
  }
  final resourceCursor = _expectPaginatedCatalogHead(
    responses[2],
    id: '$label-streamable-batch-resources',
    label: 'Streamable MCP batch resources/list',
    resultKey: 'resources',
    field: 'uri',
    fieldDescription: 'resource URIs',
    expectedPrimary: _resourceUri,
  );
  if (responses[3]['id'] != '$label-streamable-batch-prompt' ||
      !jsonEncode(responses[3]).contains(promptTaskId)) {
    throw StateError('Streamable MCP batch prompts/get response was invalid.');
  }

  await _smokeStreamableBatchResourcePromptDetails(
    client,
    label: label,
    resourceCursor: resourceCursor,
  );
  await _smokeStreamableBatchWampMeta(
    client,
    serviceSession,
    label: label,
  );
  await _smokeStreamableBatchErrorIsolation(client, label: label);
}

Future<void> _smokeStreamableBatchResourcePromptDetails(
  McpStreamableHttpClient client, {
  required String label,
  required String resourceCursor,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP batch resource/prompt details has no session id.',
    );
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError(
        'Streamable MCP batch resource/prompt $operation changed session id.',
      );
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Streamable MCP batch resource/prompt $operation did not update SSE '
        'state.',
      );
    }
    previousEventId = eventId;
  }

  final detailBatch = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-resource-read',
      'method': 'resources/read',
      'params': {'uri': _resourceUri},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-resource-templates',
      'method': 'resources/templates/list',
      'params': {},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-prompts',
      'method': 'prompts/list',
      'params': {},
    },
  ]);
  if (detailBatch == null || detailBatch.length != 3) {
    throw StateError(
      'Streamable MCP batch resource/prompt details did not return three '
      'responses.',
    );
  }

  final resource = _jsonRpcResult(
    detailBatch[0],
    id: '$label-streamable-batch-resource-read',
    label: 'Streamable MCP batch resources/read',
  );
  if (!jsonEncode(resource['contents']).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError(
      'Streamable MCP batch resources/read missed route context.',
    );
  }

  final templateCursor = _expectPaginatedCatalogHead(
    detailBatch[1],
    id: '$label-streamable-batch-resource-templates',
    label: 'Streamable MCP batch resources/templates/list',
    resultKey: 'resourceTemplates',
    field: 'uriTemplate',
    fieldDescription: 'resource template URIs',
    expectedPrimary: _resourceTemplateUri,
  );
  final promptCursor = _expectPaginatedCatalogHead(
    detailBatch[2],
    id: '$label-streamable-batch-prompts',
    label: 'Streamable MCP batch prompts/list',
    resultKey: 'prompts',
    field: 'name',
    fieldDescription: 'prompt names',
    expectedPrimary: _promptName,
  );
  expectStreamableProgress('details batch');

  final cursorBatch = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-resources-cursor',
      'method': 'resources/list',
      'params': {'cursor': resourceCursor},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-resource-templates-cursor',
      'method': 'resources/templates/list',
      'params': {'cursor': templateCursor},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-prompts-cursor',
      'method': 'prompts/list',
      'params': {'cursor': promptCursor},
    },
  ]);
  if (cursorBatch == null || cursorBatch.length != 3) {
    throw StateError(
      'Streamable MCP batch resource/prompt cursor pages did not return three '
      'responses.',
    );
  }
  _expectCatalogCursorPage(
    cursorBatch[0],
    id: '$label-streamable-batch-resources-cursor',
    label: 'Streamable MCP batch resources/list cursor',
    resultKey: 'resources',
    field: 'uri',
    fieldDescription: 'resource URIs',
    expectedPaged: _pagedResourceUri,
  );
  _expectCatalogCursorPage(
    cursorBatch[1],
    id: '$label-streamable-batch-resource-templates-cursor',
    label: 'Streamable MCP batch resources/templates/list cursor',
    resultKey: 'resourceTemplates',
    field: 'uriTemplate',
    fieldDescription: 'resource template URIs',
    expectedPaged: _pagedResourceTemplateUri,
  );
  _expectCatalogCursorPage(
    cursorBatch[2],
    id: '$label-streamable-batch-prompts-cursor',
    label: 'Streamable MCP batch prompts/list cursor',
    resultKey: 'prompts',
    field: 'name',
    fieldDescription: 'prompt names',
    expectedPaged: _pagedPromptName,
  );
  expectStreamableProgress('cursor batch');
}

Future<void> _smokeStreamableBatchWampMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP batch WAMP meta has no session id.');
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError(
        'Streamable MCP batch WAMP meta $operation changed session id.',
      );
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Streamable MCP batch WAMP meta $operation did not update SSE state.',
      );
    }
    previousEventId = eventId;
  }

  final sessionCountId = '$label-streamable-batch-wamp-session-count';
  final sessionListId = '$label-streamable-batch-wamp-session-list';
  final registrationLookupId =
      '$label-streamable-batch-wamp-registration-lookup';
  final registrationMatchId =
      '$label-streamable-batch-wamp-registration-match';
  final registrationListId = '$label-streamable-batch-wamp-registration-list';
  final discovery = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': sessionCountId,
      'method': 'tools/call',
      'params': {'name': 'wamp.session.count', 'arguments': {}},
    },
    {
      'jsonrpc': '2.0',
      'id': sessionListId,
      'method': 'tools/call',
      'params': {'name': 'wamp.session.list', 'arguments': {}},
    },
    {
      'jsonrpc': '2.0',
      'id': registrationLookupId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.lookup',
        'arguments': {
          'arguments': [_procedure],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationMatchId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.match',
        'arguments': {
          'arguments': [_procedure],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationListId,
      'method': 'tools/call',
      'params': {'name': 'wamp.registration.list', 'arguments': {}},
    },
  ]);
  if (discovery == null) {
    throw StateError('Streamable MCP batch WAMP meta discovery returned null.');
  }
  final ids = _expectWampRegistrationSessionBatchDiscovery(
    discovery,
    sessionCountId: sessionCountId,
    sessionListId: sessionListId,
    registrationLookupId: registrationLookupId,
    registrationMatchId: registrationMatchId,
    registrationListId: registrationListId,
    serviceSession: serviceSession,
    modeLabel: 'Streamable MCP batch WAMP meta',
  );
  expectStreamableProgress('discovery batch');

  final visibleSessionId = ids[0];
  final registrationId = ids[1];
  final sessionGetId = '$label-streamable-batch-wamp-session-get';
  final registrationGetId = '$label-streamable-batch-wamp-registration-get';
  final registrationCalleesId =
      '$label-streamable-batch-wamp-registration-callees';
  final registrationCalleeCountId =
      '$label-streamable-batch-wamp-registration-callee-count';
  final details = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': sessionGetId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.session.get',
        'arguments': {
          'arguments': [visibleSessionId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationGetId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.get',
        'arguments': {
          'arguments': [registrationId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationCalleesId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.list_callees',
        'arguments': {
          'arguments': [registrationId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': registrationCalleeCountId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.registration.count_callees',
        'arguments': {
          'arguments': [registrationId],
        },
      },
    },
  ]);
  if (details == null) {
    throw StateError('Streamable MCP batch WAMP meta details returned null.');
  }
  _expectWampRegistrationSessionBatchDetails(
    details,
    sessionGetId: sessionGetId,
    registrationGetId: registrationGetId,
    registrationCalleesId: registrationCalleesId,
    registrationCalleeCountId: registrationCalleeCountId,
    visibleSessionId: visibleSessionId,
    serviceSession: serviceSession,
    modeLabel: 'Streamable MCP batch WAMP meta',
  );
  expectStreamableProgress('details batch');

  final topicListId = '$label-streamable-batch-wamp-topic-list';
  final topicDescribeId = '$label-streamable-batch-wamp-topic-describe';
  final topics = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': topicListId,
      'method': 'tools/call',
      'params': {
        'name': 'connectanum.api.list',
        'arguments': {'kind': 'topic'},
      },
    },
    {
      'jsonrpc': '2.0',
      'id': topicDescribeId,
      'method': 'tools/call',
      'params': {
        'name': 'connectanum.api.describe',
        'arguments': {'uri': _topic, 'kind': 'topic'},
      },
    },
  ]);
  if (topics == null) {
    throw StateError('Streamable MCP batch WAMP topic meta returned null.');
  }
  _expectWampTopicBatchMetadata(
    topics,
    topicListId: topicListId,
    topicDescribeId: topicDescribeId,
    topicUri: _topic,
    topicDescription: 'Consumer task lifecycle event stream',
    modeLabel: 'Streamable MCP batch WAMP topic meta',
  );
  expectStreamableProgress('topic metadata batch');
}

Future<void> _smokeStreamableBatchWampSubscriptionMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP batch WAMP subscription meta has no session id.',
    );
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError(
        'Streamable MCP batch WAMP subscription meta $operation changed '
        'session id.',
      );
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Streamable MCP batch WAMP subscription meta $operation did not '
        'update SSE state.',
      );
    }
    previousEventId = eventId;
  }

  final subscriptionLookupId =
      '$label-streamable-batch-wamp-subscription-lookup';
  final subscriptionMatchId =
      '$label-streamable-batch-wamp-subscription-match';
  final subscriptionListId =
      '$label-streamable-batch-wamp-subscription-list';
  final discovery = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': subscriptionLookupId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.lookup',
        'arguments': {
          'arguments': [_topic],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': subscriptionMatchId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.match',
        'arguments': {
          'arguments': [_topic],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': subscriptionListId,
      'method': 'tools/call',
      'params': {'name': 'wamp.subscription.list', 'arguments': {}},
    },
  ]);
  if (discovery == null) {
    throw StateError(
      'Streamable MCP batch WAMP subscription meta discovery returned null.',
    );
  }
  final subscriptionId = _expectWampSubscriptionBatchDiscovery(
    discovery,
    subscriptionLookupId: subscriptionLookupId,
    subscriptionMatchId: subscriptionMatchId,
    subscriptionListId: subscriptionListId,
    modeLabel: 'Streamable MCP batch WAMP subscription meta',
  );
  expectStreamableProgress('discovery batch');

  final subscriptionGetId =
      '$label-streamable-batch-wamp-subscription-get';
  final subscribersId =
      '$label-streamable-batch-wamp-subscription-subscribers';
  final subscriberCountId =
      '$label-streamable-batch-wamp-subscription-subscriber-count';
  final details = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': subscriptionGetId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.get',
        'arguments': {
          'arguments': [subscriptionId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': subscribersId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.list_subscribers',
        'arguments': {
          'arguments': [subscriptionId],
        },
      },
    },
    {
      'jsonrpc': '2.0',
      'id': subscriberCountId,
      'method': 'tools/call',
      'params': {
        'name': 'wamp.subscription.count_subscribers',
        'arguments': {
          'arguments': [subscriptionId],
        },
      },
    },
  ]);
  if (details == null) {
    throw StateError(
      'Streamable MCP batch WAMP subscription meta details returned null.',
    );
  }
  _expectWampSubscriptionBatchDetails(
    details,
    subscriptionGetId: subscriptionGetId,
    subscribersId: subscribersId,
    subscriberCountId: subscriberCountId,
    serviceSession: serviceSession,
    modeLabel: 'Streamable MCP batch WAMP subscription meta',
  );
  expectStreamableProgress('details batch');
}

Future<void> _smokeStreamableBatchPubSub(
  McpStreamableHttpClient client,
  RouterSession serviceSession,
  String handle, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP batch pub/sub has no session id.');
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError(
        'Streamable MCP batch pub/sub $operation changed session id.',
      );
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Streamable MCP batch pub/sub $operation did not update SSE state.',
      );
    }
    previousEventId = eventId;
  }

  String? tempHandle;
  try {
    final subscribeId = '$label-streamable-batch-pubsub-subscribe';
    final apiListId = '$label-streamable-batch-pubsub-api-list';
    final subscribeBatch = await client.postBatch([
      {
        'jsonrpc': '2.0',
        'id': subscribeId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.subscribe',
          'arguments': {'topic': _batchTopic, 'queueLimit': 2},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': apiListId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.api.list',
          'arguments': {'kind': 'procedure'},
        },
      },
    ]);
    if (subscribeBatch == null || subscribeBatch.length != 2) {
      throw StateError(
        'Streamable MCP batch pub/sub subscribe did not return two '
        'responses.',
      );
    }
    final subscription = _jsonRpcStructuredContent(
      subscribeBatch[0],
      id: subscribeId,
      label: 'Streamable MCP batch pub/sub subscribe',
    );
    final tempHandleValue = subscription['handle'];
    if (tempHandleValue is! String ||
        tempHandleValue.isEmpty ||
        subscription['topic'] != _batchTopic ||
        subscription['queueLimit'] != 2) {
      throw StateError(
        'Streamable MCP batch pub/sub subscribe returned invalid content.',
      );
    }
    tempHandle = tempHandleValue;
    if (subscribeBatch[1]['id'] != apiListId ||
        !jsonEncode(subscribeBatch[1]).contains(_procedure)) {
      throw StateError('Streamable MCP batch pub/sub API list was invalid.');
    }
    expectStreamableProgress('subscribe batch');

    final publishId = '$label-streamable-batch-pubsub-publish';
    final apiDescribeId = '$label-streamable-batch-pubsub-api-describe';
    final publishBatch = await client.postBatch([
      {
        'jsonrpc': '2.0',
        'id': publishId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.pubsub.publish',
          'arguments': {
            'topic': _topic,
            'argumentsKeywords': {
              'taskId': 'T-$label-streamable-batch-pubsub-publish',
            },
            'acknowledge': true,
          },
        },
      },
      {
        'jsonrpc': '2.0',
        'id': apiDescribeId,
        'method': 'tools/call',
        'params': {
          'name': 'connectanum.api.describe',
          'arguments': {
            'uri': _procedure,
            'kind': 'procedure',
          },
        },
      },
    ]);
    if (publishBatch == null || publishBatch.length != 2) {
      throw StateError(
        'Streamable MCP batch pub/sub publish did not return two responses.',
      );
    }
    final publication = _jsonRpcStructuredContent(
      publishBatch[0],
      id: publishId,
      label: 'Streamable MCP batch pub/sub publish',
    );
    if (publication['topic'] != _topic ||
        publication['acknowledged'] != true) {
      throw StateError(
        'Streamable MCP batch pub/sub publish returned invalid content.',
      );
    }
    if (publishBatch[1]['id'] != apiDescribeId ||
        !jsonEncode(publishBatch[1]).contains(_procedure)) {
      throw StateError(
        'Streamable MCP batch pub/sub API describe was invalid.',
      );
    }
    expectStreamableProgress('publish batch');

    final serviceTaskId = 'T-$label-streamable-batch-pubsub-event';
    await serviceSession.publish(
      _topic,
      argumentsKeywords: {'taskId': serviceTaskId},
      options: PublishOptions(acknowledge: true),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var sawServiceEvent = false;
    while (DateTime.now().isBefore(deadline)) {
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final pollId = '$label-streamable-batch-pubsub-poll-$timestamp';
      final apiListId = '$label-streamable-batch-pubsub-poll-api-$timestamp';
      final pollBatch = await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': pollId,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.poll',
            'arguments': {'handle': handle, 'limit': 4},
          },
        },
        {
          'jsonrpc': '2.0',
          'id': apiListId,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.api.list',
            'arguments': {'kind': 'procedure'},
          },
        },
      ]);
      if (pollBatch == null || pollBatch.length != 2) {
        throw StateError(
          'Streamable MCP batch pub/sub poll did not return two responses.',
        );
      }
      final eventBatch = _jsonRpcStructuredContent(
        pollBatch[0],
        id: pollId,
        label: 'Streamable MCP batch pub/sub poll',
      );
      if (eventBatch['handle'] != handle || eventBatch['topic'] != _topic) {
        throw StateError(
          'Streamable MCP batch pub/sub poll returned invalid content.',
        );
      }
      if (pollBatch[1]['id'] != apiListId ||
          !jsonEncode(pollBatch[1]).contains(_procedure)) {
        throw StateError(
          'Streamable MCP batch pub/sub poll API list was invalid.',
        );
      }
      expectStreamableProgress('poll batch');
      if (jsonEncode(eventBatch['events']).contains(serviceTaskId)) {
        sawServiceEvent = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (!sawServiceEvent) {
      throw StateError(
        'Streamable MCP batch pub/sub poll missed service event.',
      );
    }
  } finally {
    if (tempHandle != null) {
      final unsubscribeId = '$label-streamable-batch-pubsub-unsubscribe';
      final apiListId =
          '$label-streamable-batch-pubsub-unsubscribe-api-list';
      final unsubscribeBatch = await client.postBatch([
        {
          'jsonrpc': '2.0',
          'id': unsubscribeId,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.pubsub.unsubscribe',
            'arguments': {'handle': tempHandle},
          },
        },
        {
          'jsonrpc': '2.0',
          'id': apiListId,
          'method': 'tools/call',
          'params': {
            'name': 'connectanum.api.list',
            'arguments': {'kind': 'procedure'},
          },
        },
      ]);
      if (unsubscribeBatch == null || unsubscribeBatch.length != 2) {
        throw StateError(
          'Streamable MCP batch pub/sub unsubscribe did not return two '
          'responses.',
        );
      }
      final unsubscribe = _jsonRpcStructuredContent(
        unsubscribeBatch[0],
        id: unsubscribeId,
        label: 'Streamable MCP batch pub/sub unsubscribe',
      );
      if (unsubscribe['handle'] != tempHandle ||
          unsubscribe['topic'] != _batchTopic ||
          unsubscribe['unsubscribed'] != true) {
        throw StateError(
          'Streamable MCP batch pub/sub unsubscribe returned invalid content.',
        );
      }
      if (unsubscribeBatch[1]['id'] != apiListId ||
          !jsonEncode(unsubscribeBatch[1]).contains(_procedure)) {
        throw StateError(
          'Streamable MCP batch pub/sub unsubscribe API list was invalid.',
        );
      }
      expectStreamableProgress('unsubscribe batch');
    }
  }
}

Map<String, Object?> _wampMetaHelperBatchResponse(
  McpStreamableWampMetaCallResult result, {
  required Object id,
}) {
  return {
    'jsonrpc': '2.0',
    'id': id,
    'result': {'isError': false, 'structuredContent': result.structuredContent},
  };
}

int _expectWampSubscriptionBatchDiscovery(
  List<Map<String, Object?>> responses, {
  required String subscriptionLookupId,
  required String subscriptionMatchId,
  required String subscriptionListId,
  required String modeLabel,
}) {
  if (responses.length != 3) {
    throw StateError('$modeLabel discovery returned ${responses.length}.');
  }

  final subscriptionLookupContent = _jsonRpcStructuredContent(
    responses[0],
    id: subscriptionLookupId,
    label: '$modeLabel subscription lookup',
  );
  final subscriptionLookupArguments =
      subscriptionLookupContent['arguments'];
  if (subscriptionLookupArguments is! List) {
    throw StateError('$modeLabel subscription lookup missed arguments.');
  }
  final subscriptionId = _singleMetaId(
    subscriptionLookupArguments.cast<Object?>(),
    '$modeLabel subscription lookup',
  );
  if (subscriptionId <= 0) {
    throw StateError(
      '$modeLabel subscription lookup returned invalid id $subscriptionId.',
    );
  }

  final subscriptionMatchContent = _jsonRpcStructuredContent(
    responses[1],
    id: subscriptionMatchId,
    label: '$modeLabel subscription match',
  );
  final subscriptionMatchArguments =
      subscriptionMatchContent['arguments'];
  if (subscriptionMatchArguments is! List) {
    throw StateError('$modeLabel subscription match missed arguments.');
  }
  final matchedSubscriptionIds = _integerMetaIds(
    subscriptionMatchArguments.cast<Object?>(),
    '$modeLabel subscription match',
  );
  if (!matchedSubscriptionIds.contains(subscriptionId)) {
    throw StateError('$modeLabel subscription match missed $_topic.');
  }

  final subscriptionListContent = _jsonRpcStructuredContent(
    responses[2],
    id: subscriptionListId,
    label: '$modeLabel subscription list',
  );
  final subscriptionListKeywords = _jsonObjectFrom(
    subscriptionListContent['argumentsKeywords'],
    label: '$modeLabel subscription list kwargs',
  );
  final exactSubscriptionIds = _integerMetaIdsFromValue(
    subscriptionListKeywords['exact'],
    '$modeLabel subscription list exact',
  );
  if (!exactSubscriptionIds.contains(subscriptionId)) {
    throw StateError('$modeLabel subscription list missed $_topic.');
  }

  return subscriptionId;
}

void _expectWampSubscriptionBatchDetails(
  List<Map<String, Object?>> responses, {
  required String subscriptionGetId,
  required String subscribersId,
  required String subscriberCountId,
  required RouterSession serviceSession,
  required String modeLabel,
}) {
  if (responses.length != 3) {
    throw StateError('$modeLabel details returned ${responses.length}.');
  }

  final subscriptionGetContent = _jsonRpcStructuredContent(
    responses[0],
    id: subscriptionGetId,
    label: '$modeLabel subscription get',
  );
  final subscriptionGetKeywords = _jsonObjectFrom(
    subscriptionGetContent['argumentsKeywords'],
    label: '$modeLabel subscription get kwargs',
  );
  if (!jsonEncode(subscriptionGetKeywords).contains(_topic)) {
    throw StateError('$modeLabel subscription get missed $_topic.');
  }

  final subscribersContent = _jsonRpcStructuredContent(
    responses[1],
    id: subscribersId,
    label: '$modeLabel subscription subscribers',
  );
  final subscriberArguments = subscribersContent['arguments'];
  if (subscriberArguments is! List) {
    throw StateError('$modeLabel subscription subscribers missed arguments.');
  }
  final subscriberIds = _integerMetaIds(
    subscriberArguments.cast<Object?>(),
    '$modeLabel subscription subscribers',
  );
  if (subscriberIds.isEmpty) {
    throw StateError('$modeLabel subscription subscribers was empty.');
  }
  if (subscriberIds.contains(serviceSession.sessionId)) {
    throw StateError('$modeLabel subscription subscribers leaked sessions.');
  }

  final subscriberCountContent = _jsonRpcStructuredContent(
    responses[2],
    id: subscriberCountId,
    label: '$modeLabel subscription subscriber count',
  );
  final subscriberCountArguments = subscriberCountContent['arguments'];
  if (subscriberCountArguments is! List) {
    throw StateError(
      '$modeLabel subscription subscriber count missed arguments.',
    );
  }
  final subscriberTotal = _singleMetaId(
    subscriberCountArguments.cast<Object?>(),
    '$modeLabel subscription subscriber count',
  );
  if (subscriberTotal != subscriberIds.length) {
    throw StateError(
      '$modeLabel subscription subscriber count did not match visible '
      'sessions.',
    );
  }
}

List<int> _expectWampRegistrationSessionBatchDiscovery(
  List<Map<String, Object?>> responses, {
  required String sessionCountId,
  required String sessionListId,
  required String registrationLookupId,
  required String registrationMatchId,
  required String registrationListId,
  required RouterSession serviceSession,
  required String modeLabel,
}) {
  if (responses.length != 5) {
    throw StateError('$modeLabel discovery returned ${responses.length}.');
  }

  final sessionCountContent = _jsonRpcStructuredContent(
    responses[0],
    id: sessionCountId,
    label: '$modeLabel session count',
  );
  final sessionCountKeywords = _jsonObjectFrom(
    sessionCountContent['argumentsKeywords'],
    label: '$modeLabel session count kwargs',
  );
  final visibleSessionCount = sessionCountKeywords['count'];
  if (visibleSessionCount is! int) {
    throw StateError('$modeLabel session count missed count metadata.');
  }

  final sessionListContent = _jsonRpcStructuredContent(
    responses[1],
    id: sessionListId,
    label: '$modeLabel session list',
  );
  final sessionListKeywords = _jsonObjectFrom(
    sessionListContent['argumentsKeywords'],
    label: '$modeLabel session list kwargs',
  );
  final sessionIds = _integerMetaIdsFromValue(
    sessionListKeywords['session_ids'],
    '$modeLabel session list',
  );
  if (sessionIds.contains(serviceSession.sessionId)) {
    throw StateError('$modeLabel session list leaked service session.');
  }
  if (sessionIds.length != visibleSessionCount) {
    throw StateError('$modeLabel session count did not match list.');
  }
  if (sessionIds.isEmpty) {
    throw StateError('$modeLabel session list missed visible sessions.');
  }

  final registrationLookupContent = _jsonRpcStructuredContent(
    responses[2],
    id: registrationLookupId,
    label: '$modeLabel registration lookup',
  );
  final registrationLookupArguments =
      registrationLookupContent['arguments'];
  if (registrationLookupArguments is! List) {
    throw StateError('$modeLabel registration lookup missed arguments.');
  }
  final registrationId = _singleMetaId(
    registrationLookupArguments.cast<Object?>(),
    '$modeLabel registration lookup',
  );
  if (registrationId <= 0) {
    throw StateError(
      '$modeLabel registration lookup returned invalid id $registrationId.',
    );
  }

  final registrationMatchContent = _jsonRpcStructuredContent(
    responses[3],
    id: registrationMatchId,
    label: '$modeLabel registration match',
  );
  final registrationMatchArguments = registrationMatchContent['arguments'];
  if (registrationMatchArguments is! List) {
    throw StateError('$modeLabel registration match missed arguments.');
  }
  final matchingRegistrationId = _singleMetaId(
    registrationMatchArguments.cast<Object?>(),
    '$modeLabel registration match',
  );
  if (matchingRegistrationId != registrationId) {
    throw StateError('$modeLabel registration match disagreed with lookup.');
  }

  final registrationListContent = _jsonRpcStructuredContent(
    responses[4],
    id: registrationListId,
    label: '$modeLabel registration list',
  );
  final registrationListKeywords = _jsonObjectFrom(
    registrationListContent['argumentsKeywords'],
    label: '$modeLabel registration list kwargs',
  );
  final exactRegistrationIds = _integerMetaIdsFromValue(
    registrationListKeywords['exact'],
    '$modeLabel registration list exact',
  );
  if (!exactRegistrationIds.contains(registrationId)) {
    throw StateError('$modeLabel registration list missed $_procedure.');
  }

  return [sessionIds.first, registrationId];
}

void _expectWampRegistrationSessionBatchDetails(
  List<Map<String, Object?>> responses, {
  required String sessionGetId,
  required String registrationGetId,
  required String registrationCalleesId,
  required String registrationCalleeCountId,
  required int visibleSessionId,
  required RouterSession serviceSession,
  required String modeLabel,
}) {
  if (responses.length != 4) {
    throw StateError('$modeLabel details returned ${responses.length}.');
  }

  final sessionGetContent = _jsonRpcStructuredContent(
    responses[0],
    id: sessionGetId,
    label: '$modeLabel session get',
  );
  final sessionGetKeywords = _jsonObjectFrom(
    sessionGetContent['argumentsKeywords'],
    label: '$modeLabel session get kwargs',
  );
  final sessionDetails = _jsonObjectFrom(
    sessionGetKeywords['details'],
    label: '$modeLabel session details',
  );
  if (sessionDetails['id'] != visibleSessionId) {
    throw StateError('$modeLabel session get missed visible session.');
  }

  final registrationGetContent = _jsonRpcStructuredContent(
    responses[1],
    id: registrationGetId,
    label: '$modeLabel registration get',
  );
  final registrationGetKeywords = _jsonObjectFrom(
    registrationGetContent['argumentsKeywords'],
    label: '$modeLabel registration get kwargs',
  );
  if (registrationGetKeywords['uri'] != _procedure) {
    throw StateError('$modeLabel registration get missed $_procedure.');
  }

  final registrationCalleesContent = _jsonRpcStructuredContent(
    responses[2],
    id: registrationCalleesId,
    label: '$modeLabel registration callees',
  );
  final registrationCalleeArguments =
      registrationCalleesContent['arguments'];
  if (registrationCalleeArguments is! List) {
    throw StateError('$modeLabel registration callees missed arguments.');
  }
  final calleeIds = _integerMetaIds(
    registrationCalleeArguments.cast<Object?>(),
    '$modeLabel registration callees',
  );
  if (calleeIds.contains(serviceSession.sessionId) || calleeIds.isNotEmpty) {
    throw StateError('$modeLabel registration callees leaked sessions.');
  }

  final registrationCalleeCountContent = _jsonRpcStructuredContent(
    responses[3],
    id: registrationCalleeCountId,
    label: '$modeLabel registration callee count',
  );
  final registrationCalleeCountArguments =
      registrationCalleeCountContent['arguments'];
  if (registrationCalleeCountArguments is! List) {
    throw StateError(
      '$modeLabel registration callee count missed arguments.',
    );
  }
  final calleeCount = _singleMetaId(
    registrationCalleeCountArguments.cast<Object?>(),
    '$modeLabel registration callee count',
  );
  if (calleeCount != 0) {
    throw StateError('$modeLabel registration callee count leaked sessions.');
  }
}

void _expectWampTopicBatchMetadata(
  List<Map<String, Object?>> responses, {
  required String topicListId,
  required String topicDescribeId,
  required String topicUri,
  required String topicDescription,
  required String modeLabel,
}) {
  if (responses.length != 2) {
    throw StateError('$modeLabel returned ${responses.length}.');
  }

  final topicListContent = _jsonRpcStructuredContent(
    responses[0],
    id: topicListId,
    label: '$modeLabel topic list',
  );
  final topicListJson = jsonEncode(topicListContent);
  if (!topicListJson.contains(topicUri) ||
      !topicListJson.contains(topicDescription)) {
    throw StateError('$modeLabel topic list missed $topicUri metadata.');
  }

  final topicDescribeContent = _jsonRpcStructuredContent(
    responses[1],
    id: topicDescribeId,
    label: '$modeLabel topic describe',
  );
  final topicDescribeJson = jsonEncode(topicDescribeContent);
  if (!topicDescribeJson.contains(topicUri) ||
      !topicDescribeJson.contains('eventSchema') ||
      !topicDescribeJson.contains('allowPublish') ||
      !topicDescribeJson.contains('allowSubscribe')) {
    throw StateError('$modeLabel topic describe missed $topicUri metadata.');
  }
}

Future<void> _smokeDirectJsonBatchErrorIsolation(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final taskId = 'T-$label-direct-batch-error-ok';
  final aliasTaskId = 'T-$label-direct-batch-error-alias-ok';
  final missingTool = 'missing.$label.direct.batch';
  final responses = await client.postBatchDirect(
    [
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-error-api',
        'method': 'connectanum.api.list',
        'params': {'kind': 'procedure'},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-error-missing',
        'method': 'connectanum.tool.call',
        'params': {
          'name': missingTool,
          'arguments': {},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-error-call',
        'method': 'connectanum.tool.call',
        'params': {
          'name': _procedure,
          'arguments': {'taskId': taskId},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-error-tools-alias',
        'method': 'connectanum.tools.call',
        'params': {
          'name': _procedure,
          'arguments': {'taskId': aliasTaskId, 'note': _headerWrappedNote},
        },
      },
      {
        'jsonrpc': '2.0',
        'method': 'connectanum.tool.call',
        'params': {
          'name': _procedure,
          'arguments': {
            'taskId': 'T-$label-direct-batch-error-notification',
          },
        },
      },
    ],
  );
  if (responses == null || responses.length != 4) {
    throw StateError(
      'Direct JSON batch error smoke did not return four responses.',
    );
  }
  if (responses[0]['id'] != '$label-direct-batch-error-api' ||
      !jsonEncode(responses[0]).contains(_procedure)) {
    throw StateError('Direct JSON batch error smoke lost API response.');
  }
  _expectJsonRpcError(
    responses[1],
    id: '$label-direct-batch-error-missing',
    messageSubstring: missingTool,
    label: 'Direct JSON batch missing tool',
  );
  if (responses[2]['id'] != '$label-direct-batch-error-call' ||
      !jsonEncode(responses[2]).contains(taskId)) {
    throw StateError('Direct JSON batch error smoke lost success response.');
  }
  if (responses[3]['id'] != '$label-direct-batch-error-tools-alias' ||
      !jsonEncode(responses[3]).contains(aliasTaskId) ||
      !jsonEncode(responses[3]).contains(_headerWrappedNote)) {
    throw StateError(
      'Direct JSON batch error smoke lost plural alias success response.',
    );
  }
}

Future<void> _smokeStreamableBatchErrorIsolation(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP batch error smoke has no initialized session id.',
    );
  }

  var previousEventId = client.lastEventId;
  void expectStreamableProgress(String operation) {
    if (client.sessionId != sessionId) {
      throw StateError(
        'Streamable MCP batch error smoke $operation changed session id.',
      );
    }
    final eventId = client.lastEventId;
    if (eventId == null ||
        !eventId.startsWith('$sessionId:') ||
        eventId == previousEventId) {
      throw StateError(
        'Streamable MCP batch error smoke $operation did not update SSE state.',
      );
    }
    previousEventId = eventId;
  }

  final missingTool = 'missing.$label.streamable.batch';
  final promptTaskId = 'T-$label-streamable-batch-error-prompt';
  final responses = await client.postBatch([
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-error-tools',
      'method': 'tools/list',
      'params': {},
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-error-missing',
      'method': 'tools/call',
      'params': {
        'name': missingTool,
        'arguments': {},
      },
    },
    {
      'jsonrpc': '2.0',
      'id': '$label-streamable-batch-error-prompt',
      'method': 'prompts/get',
      'params': {
        'name': _promptName,
        'arguments': {'taskId': promptTaskId},
      },
    },
    {'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}},
  ]);
  if (responses == null || responses.length != 3) {
    throw StateError(
      'Streamable MCP batch error smoke did not return three responses.',
    );
  }
  expectStreamableProgress('initial batch');
  await _expectBatchToolCatalogPages(
    client,
    headResponse: responses[0],
    headId: '$label-streamable-batch-error-tools',
    label: 'Streamable MCP batch error tools/list',
    idPrefix: '$label-streamable-batch-error-tools',
    method: 'tools/list',
    directJson: false,
    expectStreamableProgress: expectStreamableProgress,
  );
  _expectJsonRpcError(
    responses[1],
    id: '$label-streamable-batch-error-missing',
    messageSubstring: missingTool,
    label: 'Streamable MCP batch missing tool',
  );
  if (responses[2]['id'] != '$label-streamable-batch-error-prompt' ||
      !jsonEncode(responses[2]).contains(promptTaskId)) {
    throw StateError('Streamable MCP batch error smoke lost prompt response.');
  }
}

void _expectJsonRpcError(
  Map<String, Object?> response, {
  required Object id,
  required String messageSubstring,
  required String label,
}) {
  if (response['id'] != id) {
    throw StateError('$label response id was invalid.');
  }
  if (response.containsKey('result')) {
    throw StateError('$label response unexpectedly contained a result.');
  }
  final error = response['error'];
  if (error is! Map) {
    throw StateError('$label response did not contain a JSON-RPC error.');
  }
  if (!jsonEncode(error).contains(messageSubstring)) {
    throw StateError('$label error did not mention $messageSubstring.');
  }
}

void _expectMcpJsonRpcException(
  McpJsonRpcException error, {
  required Object id,
  required String method,
  required String messageSubstring,
  required String label,
}) {
  if (error.id != id) {
    throw StateError('$label exception id was invalid.');
  }
  if (error.method != method) {
    throw StateError('$label exception method was invalid.');
  }
  if (!jsonEncode(error.error).contains(messageSubstring)) {
    throw StateError('$label exception did not mention $messageSubstring.');
  }
}

Future<void> _smokeResourcesAndPrompts(
  McpStreamableHttpClient client, {
  required String label,
  bool directJson = false,
}) async {
  final mode = directJson ? 'direct' : 'streamable';
  final resources = directJson
      ? await client.listResourcesDirect(
          id: '$label-$mode-resources',
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resources',
          },
        )
      : await client.listResources(
          id: '$label-$mode-resources',
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resources',
          },
        );
  final resourceUris = {
    for (final resource in resources.resources) resource['uri'],
  };
  if (!resourceUris.contains(_resourceUri)) {
    throw StateError('MCP resources/list did not expose $_resourceUri.');
  }
  final resourceCursor = resources.nextCursor;
  if (resourceCursor == null || resourceCursor.isEmpty) {
    throw StateError('MCP resources/list did not expose a catalog cursor.');
  }
  final resourcePage = directJson
      ? await client.listResourcesDirect(
          id: '$label-$mode-resources-page',
          cursor: resourceCursor,
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resources-page',
          },
        )
      : await client.listResources(
          id: '$label-$mode-resources-page',
          cursor: resourceCursor,
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resources-page',
          },
        );
  final pagedResourceUris = {
    for (final resource in resourcePage.resources) resource['uri'],
  };
  if (!pagedResourceUris.contains(_pagedResourceUri) ||
      resourcePage.nextCursor != null) {
    throw StateError('MCP resources/list cursor page was invalid.');
  }

  final contents = directJson
      ? await client.readResourceDirect(
          _resourceUri,
          id: '$label-$mode-resource-read',
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resource-read',
          },
        )
      : await client.readResource(
          _resourceUri,
          id: '$label-$mode-resource-read',
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resource-read',
          },
        );
  if (!jsonEncode(contents).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError('MCP resources/read did not return route context.');
  }

  final templates = directJson
      ? await client.listResourceTemplatesDirect(
          id: '$label-$mode-resource-templates',
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resource-templates',
          },
        )
      : await client.listResourceTemplates(
          id: '$label-$mode-resource-templates',
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resource-templates',
          },
        );
  final templateUris = {
    for (final template in templates.resourceTemplates)
      template['uriTemplate'] ?? template['uri_template'],
  };
  if (!templateUris.contains(_resourceTemplateUri)) {
    throw StateError(
      'MCP resources/templates/list did not expose $_resourceTemplateUri.',
    );
  }
  final templateCursor = templates.nextCursor;
  if (templateCursor == null || templateCursor.isEmpty) {
    throw StateError(
      'MCP resources/templates/list did not expose a catalog cursor.',
    );
  }
  final templatePage = directJson
      ? await client.listResourceTemplatesDirect(
          id: '$label-$mode-resource-templates-page',
          cursor: templateCursor,
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resource-templates-page',
          },
        )
      : await client.listResourceTemplates(
          id: '$label-$mode-resource-templates-page',
          cursor: templateCursor,
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-resource-templates-page',
          },
        );
  final pagedTemplateUris = {
    for (final template in templatePage.resourceTemplates)
      template['uriTemplate'] ?? template['uri_template'],
  };
  if (!pagedTemplateUris.contains(_pagedResourceTemplateUri) ||
      templatePage.nextCursor != null) {
    throw StateError(
      'MCP resources/templates/list cursor page was invalid.',
    );
  }

  final prompts = directJson
      ? await client.listPromptsDirect(
          id: '$label-$mode-prompts',
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-prompts',
          },
        )
      : await client.listPrompts(
          id: '$label-$mode-prompts',
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-prompts',
          },
        );
  final promptNames = {for (final prompt in prompts.prompts) prompt['name']};
  if (!promptNames.contains(_promptName)) {
    throw StateError('MCP prompts/list did not expose $_promptName.');
  }
  final promptCursor = prompts.nextCursor;
  if (promptCursor == null || promptCursor.isEmpty) {
    throw StateError('MCP prompts/list did not expose a catalog cursor.');
  }
  final promptPage = directJson
      ? await client.listPromptsDirect(
          id: '$label-$mode-prompts-page',
          cursor: promptCursor,
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-prompts-page',
          },
        )
      : await client.listPrompts(
          id: '$label-$mode-prompts-page',
          cursor: promptCursor,
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-prompts-page',
          },
        );
  final pagedPromptNames = {
    for (final prompt in promptPage.prompts) prompt['name'],
  };
  if (!pagedPromptNames.contains(_pagedPromptName) ||
      promptPage.nextCursor != null) {
    throw StateError('MCP prompts/list cursor page was invalid.');
  }

  final taskId = 'T-$label-$mode-prompt';
  final prompt = directJson
      ? await client.getPromptDirect(
          _promptName,
          id: '$label-$mode-prompt',
          arguments: {'taskId': taskId},
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-prompt',
          },
        )
      : await client.getPrompt(
          _promptName,
          id: '$label-$mode-prompt',
          arguments: {'taskId': taskId},
          headers: <String, String>{
            'x-consumer-trace': '$label-$mode-prompt',
          },
        );
  if (!jsonEncode(prompt).contains(taskId)) {
    throw StateError('MCP prompts/get did not substitute $taskId.');
  }

}

Future<void> _smokeWampMetaDiscovery(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
  bool directJson = false,
}) async {
  final mode = directJson ? 'direct' : 'streamable';
  final procedureCatalog = await client.listWampApi(
    id: '$label-$mode-api-procedures',
    kind: 'procedure',
    directJson: directJson,
  );
  if (!jsonEncode(procedureCatalog).contains(_procedure)) {
    throw StateError('WAMP API procedure catalog did not expose $_procedure.');
  }

  final procedureDescription = await client.describeWampApi(
    _procedure,
    id: '$label-$mode-api-procedure-describe',
    kind: 'procedure',
    directJson: directJson,
  );
  if (!jsonEncode(procedureDescription).contains(_procedure)) {
    throw StateError('WAMP API procedure describe missed $_procedure.');
  }

  final topicCatalog = await client.listWampApi(
    id: '$label-$mode-api-topics',
    kind: 'topic',
    directJson: directJson,
  );
  final topicCatalogJson = jsonEncode(topicCatalog);
  if (!topicCatalogJson.contains(_topic) ||
      !topicCatalogJson.contains('Consumer task lifecycle event stream')) {
    throw StateError('WAMP API topic catalog did not expose $_topic.');
  }

  final topicDescription = await client.describeWampApi(
    _topic,
    id: '$label-$mode-api-topic-describe',
    kind: 'topic',
    directJson: directJson,
  );
  final topicDescriptionJson = jsonEncode(topicDescription);
  if (!topicDescriptionJson.contains(_topic) ||
      !topicDescriptionJson.contains('eventSchema') ||
      !topicDescriptionJson.contains('allowPublish') ||
      !topicDescriptionJson.contains('allowSubscribe')) {
    throw StateError('WAMP API topic describe missed $_topic metadata.');
  }

  final registrationMatch = await client.matchWampRegistration(
    _procedure,
    id: '$label-$mode-registration-match',
    directJson: directJson,
  );
  final registrationId = _singleMetaId(
    registrationMatch.arguments,
    '$mode registration match',
  );
  final registrationLookup = await client.lookupWampRegistration(
    _procedure,
    id: '$label-$mode-registration-lookup',
    directJson: directJson,
  );
  final lookupRegistrationIds = _integerMetaIds(
    registrationLookup.arguments,
    '$mode registration lookup',
  );
  if (!lookupRegistrationIds.contains(registrationId)) {
    throw StateError('WAMP registration lookup missed $_procedure.');
  }
  final registrationList = await client.listWampRegistrations(
    id: '$label-$mode-registration-list',
    directJson: directJson,
  );
  final exactRegistrationIds = _integerMetaIdsFromValue(
    registrationList.argumentsKeywords['exact'],
    '$mode registration list exact',
  );
  if (!exactRegistrationIds.contains(registrationId)) {
    throw StateError('WAMP registration list missed $_procedure.');
  }
  final registrationDetails = await client.getWampRegistration(
    registrationId,
    id: '$label-$mode-registration-get',
    directJson: directJson,
  );
  if (!jsonEncode(registrationDetails.argumentsKeywords).contains(_procedure)) {
    throw StateError('WAMP registration details missed $_procedure.');
  }

  final registrationCallees = await client.listWampRegistrationCallees(
    registrationId,
    id: '$label-$mode-registration-callees',
    directJson: directJson,
  );
  final calleeIds = _integerMetaIds(
    registrationCallees.arguments,
    '$mode registration callees',
  );
  if (calleeIds.contains(serviceSession.sessionId)) {
    throw StateError('WAMP registration callee list leaked service session.');
  }
  if (calleeIds.isNotEmpty) {
    throw StateError(
      'WAMP registration callee list exposed unexpected sessions '
      '${jsonEncode(calleeIds)}.',
    );
  }

  final registrationCalleeCount = await client.countWampRegistrationCallees(
    registrationId,
    id: '$label-$mode-registration-callee-count',
    directJson: directJson,
  );
  final calleeCount = _singleMetaId(
    registrationCalleeCount.arguments,
    '$mode registration callee count',
  );
  if (calleeCount != 0) {
    throw StateError('WAMP registration callee count leaked service session.');
  }

  final sessionCount = await client.countWampSessions(
    id: '$label-$mode-session-count',
    directJson: directJson,
  );
  final visibleSessionCount = sessionCount.argumentsKeywords['count'];
  if (visibleSessionCount is! int) {
    throw StateError('WAMP session count did not return count metadata.');
  }
  final sessions = await client.listWampSessions(
    id: '$label-$mode-session-list',
    directJson: directJson,
  );
  final sessionIds = _integerMetaIdsFromValue(
    sessions.argumentsKeywords['session_ids'],
    '$mode session list',
  );
  if (sessionIds.contains(serviceSession.sessionId)) {
    throw StateError('WAMP session list leaked service session.');
  }
  if (sessionIds.length != visibleSessionCount) {
    throw StateError('WAMP session count did not match visible session list.');
  }
  if (sessionIds.isEmpty) {
    throw StateError('WAMP session list did not expose any visible sessions.');
  }
  final visibleSessionId = sessionIds.first;
  final sessionDetails = await client.getWampSession(
    visibleSessionId,
    id: '$label-$mode-session-get',
    directJson: directJson,
  );
  final details = sessionDetails.argumentsKeywords['details'];
  if (details is! Map || details['id'] != visibleSessionId) {
    throw StateError('WAMP session get did not return visible session details.');
  }
}

final class _McpSubscriberMeta {
  const _McpSubscriberMeta({
    required this.sessionId,
    required this.authId,
    required this.authRole,
  });

  final int sessionId;
  final String authId;
  final String authRole;
}

Future<List<_McpSubscriberMeta>> _smokeWampSubscriptionMeta(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
  bool directJson = false,
}) async {
  final mode = directJson ? 'direct' : 'streamable';
  final subscriptionLookup = await client.lookupWampSubscription(
    _topic,
    id: '$label-$mode-subscription-lookup',
    directJson: directJson,
  );
  final subscriptionId = _singleMetaId(
    subscriptionLookup.arguments,
    '$mode subscription lookup',
  );
  final subscriptionMatch = await client.matchWampSubscription(
    _topic,
    id: '$label-$mode-subscription-match',
    directJson: directJson,
  );
  final matchedSubscriptionIds = _integerMetaIds(
    subscriptionMatch.arguments,
    '$mode subscription match',
  );
  if (!matchedSubscriptionIds.contains(subscriptionId)) {
    throw StateError('WAMP subscription match missed $_topic.');
  }
  final subscriptionList = await client.listWampSubscriptions(
    id: '$label-$mode-subscription-list',
    directJson: directJson,
  );
  final exactSubscriptionIds = _integerMetaIdsFromValue(
    subscriptionList.argumentsKeywords['exact'],
    '$mode subscription list exact',
  );
  if (!exactSubscriptionIds.contains(subscriptionId)) {
    throw StateError('WAMP subscription list missed $_topic.');
  }
  final subscriptionDetails = await client.getWampSubscription(
    subscriptionId,
    id: '$label-$mode-subscription-get',
    directJson: directJson,
  );
  if (!jsonEncode(subscriptionDetails.argumentsKeywords).contains(_topic)) {
    throw StateError('WAMP subscription details missed $_topic.');
  }

  final subscribers = await client.listWampSubscriptionSubscribers(
    subscriptionId,
    id: '$label-$mode-subscription-subscribers',
    directJson: directJson,
  );
  final subscriberIds = _integerMetaIds(
    subscribers.arguments,
    '$mode subscription subscribers',
  );
  if (subscriberIds.isEmpty) {
    throw StateError('WAMP subscription subscriber list was empty.');
  }
  if (subscriberIds.contains(serviceSession.sessionId)) {
    throw StateError('WAMP subscription subscriber list leaked service session.');
  }

  final subscriberCount = await client.countWampSubscriptionSubscribers(
    subscriptionId,
    id: '$label-$mode-subscription-subscriber-count',
    directJson: directJson,
  );
  final subscriberTotal = _singleMetaId(
    subscriberCount.arguments,
    '$mode subscription subscriber count',
  );
  if (subscriberTotal != subscriberIds.length) {
    throw StateError(
      'WAMP subscription subscriber count did not match visible sessions.',
    );
  }

  final subscriberMetas = <_McpSubscriberMeta>[];
  for (final subscriberId in subscriberIds) {
    final subscriberDetailsResult = await client.getWampSession(
      subscriberId,
      id: '$label-$mode-subscription-subscriber-$subscriberId-get',
      directJson: directJson,
    );
    final subscriberDetails =
        subscriberDetailsResult.argumentsKeywords['details'];
    final authId = subscriberDetails is Map
        ? subscriberDetails['authid']
        : null;
    final authRole = subscriberDetails is Map
        ? subscriberDetails['authrole']
        : null;
    if (subscriberDetails is! Map ||
        subscriberDetails['id'] != subscriberId ||
        authId is! String ||
        authId.isEmpty ||
        authRole is! String ||
        authRole.isEmpty) {
      throw StateError(
        'WAMP subscription subscriber details did not expose auth metadata.',
      );
    }
    subscriberMetas.add(
      _McpSubscriberMeta(
        sessionId: subscriberId,
        authId: authId,
        authRole: authRole,
      ),
    );
  }
  return subscriberMetas;
}

int _singleMetaId(List<Object?> arguments, String label) {
  if (arguments.length != 1 || arguments.single is! int) {
    throw StateError('WAMP meta $label returned ${jsonEncode(arguments)}.');
  }
  return arguments.single as int;
}

List<int> _integerMetaIds(List<Object?> arguments, String label) {
  final ids = <int>[];
  for (final value in arguments) {
    if (value is! int) {
      throw StateError('WAMP meta $label returned ${jsonEncode(arguments)}.');
    }
    ids.add(value);
  }
  return ids;
}

List<int> _integerMetaIdsFromValue(Object? value, String label) {
  if (value is! List) {
    throw StateError('WAMP meta $label returned ${jsonEncode(value)}.');
  }
  return _integerMetaIds(value.cast<Object?>(), label);
}

Future<McpStreamableWampEventBatch> _pollMcpEventsUntil(
  McpStreamableHttpClient client,
  String subscriptionHandle, {
  bool directJson = false,
  Map<String, String> headers = const <String, String>{},
}
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final eventId = 'streamable-poll-${DateTime.now().microsecondsSinceEpoch}';
    final events = directJson
        ? await client.pollWampEventsDirect(
            subscriptionHandle,
            id: eventId,
            limit: 4,
            headers: headers,
          )
        : await client.pollWampEvents(
            subscriptionHandle,
            id: eventId,
            limit: 4,
            headers: headers,
          );
    if (events.events.isNotEmpty) {
      return events;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for MCP pub/sub event.');
}

Future<void> _smokeWampPublishSessionFilters(
  McpStreamableHttpClient client,
  String subscriptionHandle,
  _McpSubscriberMeta subscriber, {
  required String label,
  bool directJson = false,
}) async {
  final mode = directJson ? 'direct' : 'streamable';

  Future<McpStreamableWampPublicationResult> publishFiltered(
    String suffix,
    String taskId,
    McpJsonMap options,
  ) {
    final publishId = '$label-$mode-publish-$suffix';
    return directJson
        ? client.publishWampEventDirect(
            _topic,
            id: publishId,
            argumentsKeywords: {'taskId': taskId},
            options: options,
          )
        : client.publishWampEvent(
            _topic,
            id: publishId,
            argumentsKeywords: {'taskId': taskId},
            options: options,
          );
  }

  McpJsonMap publishOptions(
    String suffix, {
    List<int>? eligible,
    List<int>? exclude,
    List<String>? eligibleAuthId,
    List<String>? excludeAuthId,
    List<String>? eligibleAuthRole,
    List<String>? excludeAuthRole,
  }) =>
      mcpWampPublishOptions(
        acknowledge: true,
        excludeMe: false,
        eligible: eligible,
        exclude: exclude,
        eligibleAuthId: eligibleAuthId,
        excludeAuthId: excludeAuthId,
        eligibleAuthRole: eligibleAuthRole,
        excludeAuthRole: excludeAuthRole,
        custom: <String, Object?>{
          'x_consumer_trace': '$label-$mode-publish-$suffix',
        },
      );

  Future<void> expectDelivery(
    String suffix,
    String taskId,
    McpJsonMap options,
    String failure,
  ) async {
    final publication = await publishFiltered(suffix, taskId, options);
    if (!publication.acknowledged) {
      throw StateError('MCP pub/sub $suffix publish was not acknowledged.');
    }
    final events = await _pollMcpEventsUntil(
      client,
      subscriptionHandle,
      directJson: directJson,
    );
    if (!jsonEncode(events.events).contains(taskId)) {
      throw StateError(failure);
    }
  }

  Future<void> expectSuppression(
    String suffix,
    String taskId,
    McpJsonMap options,
    String failure,
  ) async {
    final publication = await publishFiltered(suffix, taskId, options);
    if (!publication.acknowledged) {
      throw StateError('MCP pub/sub $suffix publish was not acknowledged.');
    }

    final flushSuffix = '$suffix-flush';
    final flushTaskId = 'T-$label-$mode-publish-flush-$suffix';
    final flushPublication = await publishFiltered(
      flushSuffix,
      flushTaskId,
      publishOptions(flushSuffix),
    );
    if (!flushPublication.acknowledged) {
      throw StateError(
        'MCP pub/sub $flushSuffix publish was not acknowledged.',
      );
    }

    final events = await _pollMcpEventsUntil(
      client,
      subscriptionHandle,
      directJson: directJson,
    );
    final encodedEvents = jsonEncode(events.events);
    if (!encodedEvents.contains(flushTaskId)) {
      throw StateError(
        'MCP pub/sub $flushSuffix publish was not delivered to that '
        'subscription.',
      );
    }
    if (encodedEvents.contains(taskId)) {
      throw StateError(failure);
    }
  }

  final eligibleSessionTaskId = 'T-$label-$mode-publish-eligible-session';
  await expectDelivery(
    'eligible-session',
    eligibleSessionTaskId,
    publishOptions(
      'eligible-session',
      eligible: <int>[subscriber.sessionId],
    ),
    'MCP pub/sub publish with an eligible subscriber did not reach that '
    'subscription.',
  );

  final eligibleAuthIdTaskId = 'T-$label-$mode-publish-eligible-authid';
  await expectDelivery(
    'eligible-authid',
    eligibleAuthIdTaskId,
    publishOptions(
      'eligible-authid',
      eligibleAuthId: <String>[subscriber.authId],
    ),
    'MCP pub/sub publish with an eligible authid did not reach that '
    'subscription.',
  );

  final eligibleAuthRoleTaskId = 'T-$label-$mode-publish-eligible-authrole';
  await expectDelivery(
    'eligible-authrole',
    eligibleAuthRoleTaskId,
    publishOptions(
      'eligible-authrole',
      eligibleAuthRole: <String>[subscriber.authRole],
    ),
    'MCP pub/sub publish with an eligible authrole did not reach that '
    'subscription.',
  );

  final excludedSessionTaskId = 'T-$label-$mode-publish-exclude-session';
  await expectSuppression(
    'exclude-session',
    excludedSessionTaskId,
    publishOptions(
      'exclude-session',
      exclude: <int>[subscriber.sessionId],
    ),
    'MCP pub/sub publish with an excluded subscriber reached that '
    'subscription.',
  );

  final excludedAuthIdTaskId = 'T-$label-$mode-publish-exclude-authid';
  await expectSuppression(
    'exclude-authid',
    excludedAuthIdTaskId,
    publishOptions(
      'exclude-authid',
      excludeAuthId: <String>[subscriber.authId],
    ),
    'MCP pub/sub publish with an excluded authid reached that subscription.',
  );

  final excludedAuthRoleTaskId = 'T-$label-$mode-publish-exclude-authrole';
  await expectSuppression(
    'exclude-authrole',
    excludedAuthRoleTaskId,
    publishOptions(
      'exclude-authrole',
      excludeAuthRole: <String>[subscriber.authRole],
    ),
    'MCP pub/sub publish with an excluded authrole reached that subscription.',
  );
}

Future<void> _smokeStreamableNotificationPubSub(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP pub/sub notification smoke has no session id.',
    );
  }

  final subscription = await client.subscribeWampTopic(
    _topic,
    id: '$label-streamable-notification-pubsub-subscribe',
    queueLimit: 4,
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-notification-pubsub-subscribe',
    },
  );
  try {
    final eventIdBeforeHelperNotification = client.lastEventId;
    final helperTaskId = 'T-$label-streamable-helper-notification-pubsub';
    await client.notifyWampEvent(
      _topic,
      argumentsKeywords: {'taskId': helperTaskId},
      headers: <String, String>{
        'Mcp-Method': 'consumer.pubsub.wrong',
        'Mcp-Name': 'consumer.pubsub.wrong',
        'Mcp-Param-Topic': 'wrong-topic',
        'x-consumer-trace': '$label-streamable-notification-pubsub-helper',
      },
    );
    if (client.sessionId != sessionId ||
        client.lastEventId != eventIdBeforeHelperNotification) {
      throw StateError(
        'Streamable MCP pub/sub notification helper changed session state.',
      );
    }

    final helperEvents = await _pollMcpEventsUntil(
      client,
      subscription.handle,
      headers: <String, String>{
        'x-consumer-trace': '$label-streamable-notification-pubsub-helper-poll',
      },
    );
    if (!jsonEncode(helperEvents.events).contains(helperTaskId)) {
      throw StateError(
        'Streamable MCP pub/sub notification helper did not deliver event.',
      );
    }

    final methodTaskId = 'T-$label-streamable-method-pubsub';
    final methodPublish = await client.callConnectanumMethod(
      'connectanum.pubsub.publish',
      id: '$label-streamable-method-pubsub-publish',
      params: {
        'topic': _topic,
        'argumentsKeywords': {'taskId': methodTaskId},
        'acknowledge': true,
      },
      headers: <String, String>{
        'Mcp-Param-Topic': 'wrong-topic',
        'x-consumer-trace': '$label-streamable-method-pubsub-publish',
      },
    );
    final methodPublishContent = _jsonObjectFrom(
      methodPublish['structuredContent'],
      label: '$label Streamable method pub/sub publish result',
    );
    if (methodPublishContent['topic'] != _topic ||
        methodPublishContent['acknowledged'] != true) {
      throw StateError(
        'Streamable MCP Connectanum method publish returned '
        '${jsonEncode(methodPublishContent)}.',
      );
    }

    final methodEvents = await _pollMcpEventsUntil(
      client,
      subscription.handle,
      headers: <String, String>{
        'x-consumer-trace': '$label-streamable-method-pubsub-poll',
      },
    );
    if (!jsonEncode(methodEvents.events).contains(methodTaskId)) {
      throw StateError(
        'Streamable MCP Connectanum method publish did not deliver event.',
      );
    }

    final eventIdBeforeMethodNotification = client.lastEventId;
    final methodNotificationTaskId =
        'T-$label-streamable-method-notification-pubsub';
    await client.notifyConnectanumMethod(
      'connectanum.pubsub.publish',
      params: {
        'topic': _topic,
        'argumentsKeywords': {'taskId': methodNotificationTaskId},
        'acknowledge': true,
      },
      headers: <String, String>{
        'Mcp-Param-Topic': 'wrong-topic',
        'x-consumer-trace':
            '$label-streamable-method-notification-pubsub',
      },
    );
    if (client.sessionId != sessionId ||
        client.lastEventId != eventIdBeforeMethodNotification) {
      throw StateError(
        'Streamable MCP Connectanum method notification changed session state.',
      );
    }

    final methodNotificationEvents = await _pollMcpEventsUntil(
      client,
      subscription.handle,
      headers: <String, String>{
        'x-consumer-trace':
            '$label-streamable-method-notification-pubsub-poll',
      },
    );
    if (!jsonEncode(methodNotificationEvents.events)
        .contains(methodNotificationTaskId)) {
      throw StateError(
        'Streamable MCP Connectanum method notification did not deliver event.',
      );
    }

    final eventIdBeforeNotificationBatch = client.lastEventId;
    final taskId = 'T-$label-streamable-notification-pubsub';
    final invalidTaskId = 'T-$label-streamable-invalid-notification-pubsub';
    final notificationBatch = await client.postBatch(
      [
        {
          'jsonrpc': '2.0',
          'method': 'connectanum.pubsub.publish',
          'params': {
            'topic': _topic,
            'argumentsKeywords': {'taskId': taskId},
            'acknowledge': true,
          },
        },
        {
          'jsonrpc': '2.0',
          'method': 'connectanum.pubsub.publish',
          'params': {
            'argumentsKeywords': {
              'taskId': invalidTaskId,
              'message': '$label invalid Streamable pub/sub notification',
            },
          },
        },
      ],
      headers: <String, String>{
        'x-consumer-trace': '$label-streamable-notification-pubsub-batch',
      },
    );
    if (notificationBatch != null) {
      throw StateError(
        'Streamable MCP pub/sub notification-only batch returned a response.',
      );
    }
    if (client.sessionId != sessionId ||
        client.lastEventId != eventIdBeforeNotificationBatch) {
      throw StateError(
        'Streamable MCP pub/sub notification-only batch changed session state.',
      );
    }

    final events = await _pollMcpEventsUntil(
      client,
      subscription.handle,
      headers: <String, String>{
        'x-consumer-trace': '$label-streamable-notification-pubsub-poll',
      },
    );
    final eventsJson = jsonEncode(events.events);
    if (!eventsJson.contains(taskId)) {
      throw StateError(
        'Streamable MCP pub/sub notification-only batch did not deliver event.',
      );
    }
    if (eventsJson.contains(invalidTaskId)) {
      throw StateError(
        'Streamable MCP invalid pub/sub notification delivered an event.',
      );
    }
  } finally {
    await client.unsubscribeWampTopic(
      subscription.handle,
      id: '$label-streamable-notification-pubsub-unsubscribe',
      headers: <String, String>{
        'x-consumer-trace': '$label-streamable-notification-pubsub-unsubscribe',
      },
    );
  }
}

Future<void> _smokeStreamableNotificationToolCall(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP tool notification smoke has no session id.',
    );
  }

  final eventIdBeforeNotificationBatch = client.lastEventId;
  final taskId = 'T-$label-streamable-notification-tool';
  final invalidTaskId = 'T-$label-streamable-invalid-notification-tool';
  final notificationBatch = await client.postBatch(
    [
      {
        'jsonrpc': '2.0',
        'method': 'connectanum.tool.call',
        'params': {
          'name': _procedure,
          'arguments': {'taskId': taskId},
        },
      },
      {
        'jsonrpc': '2.0',
        'method': 'connectanum.tool.call',
        'params': {
          'arguments': {
            'taskId': invalidTaskId,
            'message': '$label invalid Streamable tool notification',
          },
        },
      },
    ],
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-notification-tool-batch',
    },
  );
  if (notificationBatch != null) {
    throw StateError(
      'Streamable MCP tool notification-only batch returned a response.',
    );
  }
  if (client.sessionId != sessionId ||
      client.lastEventId != eventIdBeforeNotificationBatch) {
    throw StateError(
      'Streamable MCP tool notification-only batch changed session state.',
    );
  }

  final eventIdBeforeHelperNotification = client.lastEventId;
  final helperTaskId = 'T-$label-streamable-helper-notification-tool';
  await client.notifyTool(
    _procedure,
    arguments: {'taskId': helperTaskId},
    headers: <String, String>{
      'Mcp-Method': 'consumer.tool.notification.wrong',
      'Mcp-Name': 'consumer.tool.notification.wrong',
      'Mcp-Param-TaskId': 'wrong-task',
      'x-consumer-trace': '$label-streamable-notification-tool-helper',
    },
  );
  if (client.sessionId != sessionId ||
      client.lastEventId != eventIdBeforeHelperNotification) {
    throw StateError(
      'Streamable MCP standard tool notification helper changed session state.',
    );
  }
  await _expectConsumerProcedureInvocation(
    helperTaskId,
    label: '$label Streamable standard tool notification helper',
  );

  final eventIdBeforeDottedNotification = client.lastEventId;
  final dottedTaskId = 'T-$label-streamable-dotted-notification-tool';
  await client.notifyConnectanumMethod(
    _procedure,
    params: {'taskId': dottedTaskId},
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-notification-tool-dotted',
    },
  );
  if (client.sessionId != sessionId ||
      client.lastEventId != eventIdBeforeDottedNotification) {
    throw StateError(
      'Streamable MCP dotted tool notification changed session state.',
    );
  }
  await _expectConsumerProcedureInvocation(
    dottedTaskId,
    label: '$label Streamable dotted tool notification',
  );

  final eventIdBeforeAliasNotification = client.lastEventId;
  final aliasTaskId = 'T-$label-streamable-alias-notification-tool';
  await client.notifyConnectanumMethod(
    'connectanum.tools.call',
    params: {
      'name': _procedure,
      'arguments': {'taskId': aliasTaskId},
    },
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-notification-tool-alias',
    },
  );
  if (client.sessionId != sessionId ||
      client.lastEventId != eventIdBeforeAliasNotification) {
    throw StateError(
      'Streamable MCP plural tool alias notification changed session state.',
    );
  }
  await _expectConsumerProcedureInvocation(
    aliasTaskId,
    label: '$label Streamable plural tool alias notification',
  );

  await _expectConsumerProcedureInvocation(
    taskId,
    label: '$label Streamable tool notification-only batch',
  );
  await client.ping(
    id: '$label-streamable-notification-tool-drain',
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-notification-tool-drain',
    },
  );
  if (client.sessionId != sessionId) {
    throw StateError(
      'Streamable MCP tool notification drain changed session id.',
    );
  }
  _expectNoConsumerProcedureInvocation(
    invalidTaskId,
    label: '$label invalid Streamable tool notification-only batch',
  );
}

Future<void> _smokeMcpPubSubQueueOverflow(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
  required bool directJson,
}
) async {
  final mode = directJson ? 'Direct JSON' : 'Streamable MCP';
  final suffix = directJson ? 'direct' : 'streamable';
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final subscription = directJson
      ? await client.subscribeWampTopicDirect(
          _topic,
          id: '$label-$suffix-overflow-subscribe',
          queueLimit: 1,
          headers: <String, String>{
            'x-consumer-trace': '$label-$suffix-overflow-subscribe',
          },
        )
      : await client.subscribeWampTopic(
          _topic,
          id: '$label-$suffix-overflow-subscribe',
          queueLimit: 1,
          headers: <String, String>{
            'x-consumer-trace': '$label-$suffix-overflow-subscribe',
          },
        );
  try {
    final taskIds = [
      'T-$label-$suffix-overflow-first',
      'T-$label-$suffix-overflow-second',
      'T-$label-$suffix-overflow-third',
    ];
    for (final taskId in taskIds) {
      await serviceSession.publish(
        _topic,
        argumentsKeywords: {'taskId': taskId},
        options: PublishOptions(acknowledge: true),
      );
    }

    final overflowEvents = await _pollMcpEventsUntil(
      client,
      subscription.handle,
      directJson: directJson,
      headers: <String, String>{
        'x-consumer-trace': '$label-$suffix-overflow-poll',
      },
    );
    final encodedEvents = jsonEncode(overflowEvents.events);
    if (overflowEvents.handle != subscription.handle ||
        overflowEvents.topic != _topic ||
        overflowEvents.events.length != 1 ||
        overflowEvents.dropped < 2 ||
        overflowEvents.remaining != 0 ||
        !encodedEvents.contains(taskIds.last) ||
        encodedEvents.contains(taskIds.first) ||
        encodedEvents.contains(taskIds[1])) {
      throw StateError(
        '$mode pub/sub queue overflow did not retain only the newest event.',
      );
    }
  } finally {
    if (directJson) {
      await client.unsubscribeWampTopicDirect(
        subscription.handle,
        id: '$label-$suffix-overflow-unsubscribe',
        headers: <String, String>{
          'x-consumer-trace': '$label-$suffix-overflow-unsubscribe',
        },
      );
    } else {
      await client.unsubscribeWampTopic(
        subscription.handle,
        id: '$label-$suffix-overflow-unsubscribe',
        headers: <String, String>{
          'x-consumer-trace': '$label-$suffix-overflow-unsubscribe',
        },
      );
    }
  }

  if (directJson) {
    if (client.sessionId != previousSessionId ||
        client.lastEventId != previousEventId) {
      throw StateError(
        'Direct JSON pub/sub queue overflow changed Streamable state.',
      );
    }
  } else if (client.sessionId != previousSessionId ||
      client.lastEventId == previousEventId) {
    throw StateError(
      'Streamable MCP pub/sub queue overflow did not preserve session state '
      'and advance SSE state.',
    );
  }
}

Future<void> _smokeStreamableSessionLifecycle(
  McpStreamableHttpClient client,
  RouterSession serviceSession, {
  required String label,
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP session did not capture a session id.');
  }

  final dynamicProcedure = 'consumer.task.dynamic.$label';
  final registration = await serviceSession.register(
    dynamicProcedure,
    options: RegisterOptions(
      custom: {
        '_ai_meta_data': {
          'short_description': 'Dynamic $label consumer task',
          'description':
              'Procedure registered after MCP initialization to verify '
              'Streamable HTTP GET/SSE polling.',
          'read_only_hint': true,
          'destructive_hint': false,
          'idempotent_hint': true,
          'open_world_hint': false,
        },
      },
    ),
  );
  registration.onInvoke((invocation) {
    invocation.respondWith(
      argumentsKeywords: {'label': label, 'source': 'consumer-package-smoke'},
    );
  });

  final events = await _pollStreamableSessionEventsUntil(
    client,
    label: label,
    headers: <String, String>{'x-consumer-trace': '$label-streamable-poll'},
  );
  final hasToolListChanged = events.any(
    (event) => event.jsonData?['method'] == 'notifications/tools/list_changed',
  );
  if (!hasToolListChanged) {
    throw StateError(
      'Streamable MCP GET/SSE poll did not receive tools/list_changed.',
    );
  }
  final eventId = client.lastEventId;
  if (eventId == null || eventId.isEmpty) {
    throw StateError('Streamable MCP GET/SSE poll did not capture event id.');
  }

  final resumedEvents = await client.poll(
    lastEventId: eventId,
    headers: <String, String>{'x-consumer-trace': '$label-streamable-resume'},
  );
  if (resumedEvents.any(
    (event) =>
        event.id == eventId ||
        event.jsonData?['method'] == 'notifications/tools/list_changed',
  )) {
    throw StateError('Streamable MCP Last-Event-ID replayed an old event.');
  }

  final eventIdAfterResume = client.lastEventId;
  if (eventIdAfterResume == null || eventIdAfterResume.isEmpty) {
    throw StateError('Streamable MCP resume did not preserve an SSE cursor.');
  }
  await _assertInvalidLastEventIdRejectedWithoutSessionLoss(
    client,
    label: label,
    sessionId: sessionId,
    eventId: eventIdAfterResume,
  );

  final cleanupSubscription = await client.subscribeWampTopic(
    _topic,
    id: '$label-delete-cleanup-subscribe',
    queueLimit: 5,
    headers: <String, String>{
      'x-consumer-trace': '$label-delete-cleanup-subscribe',
    },
  );
  final cleanupSubscriptionId = cleanupSubscription.subscriptionId;
  if (cleanupSubscriptionId == null) {
    throw StateError(
      'Streamable MCP DELETE cleanup subscription did not return an id.',
    );
  }
  final cleanupSubscriberCount = await client.countWampSubscriptionSubscribers(
    cleanupSubscriptionId,
    id: '$label-delete-cleanup-count',
    headers: <String, String>{
      'x-consumer-trace': '$label-delete-cleanup-count',
    },
  );
  if (cleanupSubscriberCount.arguments.single != 1) {
    throw StateError(
      'Streamable MCP DELETE cleanup expected one subscriber before delete.',
    );
  }

  await client.deleteSession(
    headers: <String, String>{'x-consumer-trace': '$label-streamable-delete'},
  );
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError('Streamable MCP DELETE did not clear session state.');
  }
  final cleanupSubscriberCountAfterDelete = await client
      .countWampSubscriptionSubscribersDirect(
        cleanupSubscriptionId,
        id: '$label-delete-cleanup-count-after-delete',
        headers: <String, String>{
          'x-consumer-trace': '$label-delete-cleanup-count-after-delete',
        },
      );
  if (cleanupSubscriberCountAfterDelete.arguments.single != 0) {
    throw StateError(
      'Streamable MCP DELETE left a WAMP subscriber behind.',
    );
  }

  await _assertStreamableSessionReuseRejectedAcrossMethods(
    client,
    sessionId: sessionId,
    lastEventId: eventId,
    label: '$label deleted session',
  );

  final recovered = await client.initialize(
    id: '$label-reinitialize',
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-reinitialize',
    },
  );
  if (recovered['id'] != '$label-reinitialize' || client.sessionId == null) {
    throw StateError('Streamable MCP reinitialize after 404 failed.');
  }
  await client.notifyInitialized(
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-reinitialized',
    },
  );
  await client.deleteSession(
    headers: <String, String>{
      'x-consumer-trace': '$label-streamable-recovered-delete',
    },
  );
}

Future<void> _assertInvalidLastEventIdRejectedWithoutSessionLoss(
  McpStreamableHttpClient client, {
  required String label,
  required String sessionId,
  required String eventId,
}) async {
  try {
    await client.poll(lastEventId: '$sessionId:missing:1');
    throw StateError('Streamable MCP accepted an unknown Last-Event-ID.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'Streamable MCP invalid Last-Event-ID returned '
        '${error.statusCode} instead of ${HttpStatus.badRequest}.',
      );
    }
    if (!error.body.contains('Last-Event-ID')) {
      throw StateError(
        'Streamable MCP invalid Last-Event-ID error did not explain '
        'the resume cursor problem.',
      );
    }
  }

  if (client.sessionId != sessionId || client.lastEventId != eventId) {
    throw StateError(
      'Streamable MCP invalid Last-Event-ID changed active session state.',
    );
  }

  await _expectPagedToolCatalog(
    client,
    label: '$label-after-invalid-last-event-id',
    directJson: false,
  );
  if (client.sessionId != sessionId) {
    throw StateError(
      'Streamable MCP invalid Last-Event-ID recovery lost session id.',
    );
  }
}

Future<List<McpSseEvent>> _pollStreamableSessionEventsUntil(
  McpStreamableHttpClient client, {
  required String label,
  Map<String, String> headers = const <String, String>{},
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final events = await client.poll(headers: headers);
    if (events.any(
      (event) =>
          event.jsonData?['method'] == 'notifications/tools/list_changed',
    )) {
      return events;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for $label Streamable MCP SSE event.');
}
DART

  printf 'Running MCP consumer package smoke from %s.\n' "$smoke_dir"
  (
    cd "$smoke_dir"
    PUB_CACHE="$pub_cache" dart pub get
    PUB_CACHE="$pub_cache" dart analyze
    if [[ -n "$hook_native_lib" ]]; then
      CONNECTANUM_NATIVE_LIB="$hook_native_lib" PUB_CACHE="$pub_cache" dart run bin/main.dart
    else
      PUB_CACHE="$pub_cache" dart run bin/main.dart
    fi
  )
)

run_bench_cli_consumer_package_smoke() (
  local bench_service_help_output
  local global_bench_command
  local global_bench_service_command
  local global_router_command
  local global_smoke_workspace
  local global_worker_command
  local help_output
  local http_port
  local native_lib
  local package_name
  local package_source
  local package_target
  local ports
  local pub_cache
  local rawsocket_port
  local bench_service_log
  local bench_service_pid
  local router_bench_output
  local router_bench_port
  local router_help_output
  local smoke_dir
  local websocket_port
  local worker_help_output

  require_command dart

  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-bench-cli-smoke.XXXXXX")"
  pub_cache="$smoke_dir/pub-cache"
  bench_service_log="$smoke_dir/bench-service.log"
  bench_service_pid=""

  _cleanup_bench_cli_smoke() {
    local status="${1:-0}"

    if [[ -n "${bench_service_pid:-}" ]]; then
      if kill -0 "$bench_service_pid" >/dev/null 2>&1; then
        if [[ -n "${http_port:-}" ]]; then
          curl -fsS -X POST \
            "http://127.0.0.1:$http_port/bench/stop" \
            >/dev/null 2>&1 || true
        fi
        for _ in {1..50}; do
          if ! kill -0 "$bench_service_pid" >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done
      fi
      if kill -0 "$bench_service_pid" >/dev/null 2>&1; then
        kill "$bench_service_pid" >/dev/null 2>&1 || true
        for _ in {1..50}; do
          if ! kill -0 "$bench_service_pid" >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done
      fi
      if kill -0 "$bench_service_pid" >/dev/null 2>&1; then
        kill -KILL "$bench_service_pid" >/dev/null 2>&1 || true
      fi
      wait "$bench_service_pid" >/dev/null 2>&1 || true
      bench_service_pid=""
    fi

    return "$status"
  }

  trap '_cleanup_bench_cli_smoke 0 >/dev/null 2>&1 || true; rm -rf "$smoke_dir"' EXIT

  mkdir -p "$smoke_dir/bench-runner"
  cat >"$smoke_dir/bench-runner/pubspec.yaml" <<EOF
name: connectanum_bench_cli_runner_smoke
publish_to: none
environment:
  sdk: '^3.9.2'
hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
    connectanum_router:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
dependencies:
  connectanum_bench: any
dependency_overrides:
  connectanum_auth_server:
    path: "$ROOT_DIR/packages/connectanum_auth_server"
  connectanum_core:
    path: "$ROOT_DIR/packages/connectanum_core"
  connectanum_client:
    path: "$ROOT_DIR/packages/connectanum_client"
  connectanum_mcp:
    path: "$ROOT_DIR/packages/connectanum_mcp"
  connectanum_router:
    path: "$ROOT_DIR/packages/connectanum_router"
  connectanum_bench:
    path: "$ROOT_DIR/packages/connectanum_bench"
EOF

  printf 'Running bench CLI consumer package smoke from %s.\n' "$smoke_dir"
  (
    cd "$smoke_dir/bench-runner"
    PUB_CACHE="$pub_cache" dart pub get >&2
    help_output="$(PUB_CACHE="$pub_cache" dart run connectanum_bench:router_bench --help)"
    grep -F -- '-h, --help' <<<"$help_output" >/dev/null
    grep -F -- 'Print this usage information.' <<<"$help_output" >/dev/null
    grep -F -- '--config (mandatory)' <<<"$help_output" >/dev/null
    grep -F -- '--native-lib (mandatory)' <<<"$help_output" >/dev/null
    bench_service_help_output="$(
      PUB_CACHE="$pub_cache" dart run connectanum_bench:bench_router_service --help
    )"
    grep -F -- '--router-config' <<<"$bench_service_help_output" >/dev/null
    grep -F -- '--native-lib' <<<"$bench_service_help_output" >/dev/null
    grep -F -- '--control-realm' <<<"$bench_service_help_output" >/dev/null
    worker_help_output="$(
      PUB_CACHE="$pub_cache" dart run connectanum_bench:wamp_client_worker --help
    )"
    grep -F -- '--realm' <<<"$worker_help_output" >/dev/null
    grep -F -- '--targets-json' <<<"$worker_help_output" >/dev/null
    grep -F -- '--native-lib' <<<"$worker_help_output" >/dev/null
  )

  global_smoke_workspace="$smoke_dir/global-workspace"
  mkdir -p "$global_smoke_workspace/packages"
  cat >"$global_smoke_workspace/pubspec.yaml" <<EOF
name: connectanum_bench_global_activation_smoke_workspace
publish_to: none
environment:
  sdk: '^3.9.2'
hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
    connectanum_router:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
workspace:
  - packages/connectanum_auth_server
  - packages/connectanum_core
  - packages/connectanum_client
  - packages/connectanum_mcp
  - packages/connectanum_router
  - packages/connectanum_bench
EOF
  if [[ -f "$ROOT_DIR/pubspec.lock" ]]; then
    cp "$ROOT_DIR/pubspec.lock" "$global_smoke_workspace/pubspec.lock"
  fi

  for package_name in \
    connectanum_auth_server \
    connectanum_core \
    connectanum_client \
    connectanum_mcp \
    connectanum_router \
    connectanum_bench; do
    package_source="$ROOT_DIR/packages/$package_name"
    package_target="$global_smoke_workspace/packages/$package_name"
    mkdir -p "$package_target"
    cp "$package_source/pubspec.yaml" "$package_target/pubspec.yaml"
    cp -R "$package_source/lib" "$package_target/lib"
    if [[ -d "$package_source/bin" ]]; then
      cp -R "$package_source/bin" "$package_target/bin"
    fi
    if [[ -d "$package_source/hook" ]]; then
      cp -R "$package_source/hook" "$package_target/hook"
    fi
    if [[ "$package_name" == "connectanum_bench" && -d "$package_source/tool" ]]; then
      cp -R "$package_source/tool" "$package_target/tool"
    fi
  done

  CONNECTANUM_SKIP_NATIVE_BUILD=true \
    PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" dart pub global activate --source path "$global_smoke_workspace/packages/connectanum_bench" >&2
  CONNECTANUM_SKIP_NATIVE_BUILD=true \
    PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" dart pub global activate --source path "$global_smoke_workspace/packages/connectanum_router" >&2
  global_bench_command="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" command -v router_bench || true)"
  if [[ "$global_bench_command" != "$pub_cache/bin/router_bench" ]]; then
    printf 'Expected isolated pub-cache router_bench command, got: %s\n' \
      "${global_bench_command:-<missing>}" >&2
    return 1
  fi
  global_router_command="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" command -v connectanum_router || true)"
  if [[ "$global_router_command" != "$pub_cache/bin/connectanum_router" ]]; then
    printf 'Expected isolated pub-cache connectanum_router command, got: %s\n' \
      "${global_router_command:-<missing>}" >&2
    return 1
  fi
  global_bench_service_command="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" command -v bench_router_service || true)"
  if [[ "$global_bench_service_command" != "$pub_cache/bin/bench_router_service" ]]; then
    printf 'Expected isolated pub-cache bench_router_service command, got: %s\n' \
      "${global_bench_service_command:-<missing>}" >&2
    return 1
  fi
  global_worker_command="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" command -v wamp_client_worker || true)"
  if [[ "$global_worker_command" != "$pub_cache/bin/wamp_client_worker" ]]; then
    printf 'Expected isolated pub-cache wamp_client_worker command, got: %s\n' \
      "${global_worker_command:-<missing>}" >&2
    return 1
  fi

  help_output="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" router_bench --help)"
  grep -F -- '--config (mandatory)' <<<"$help_output" >/dev/null
  grep -F -- '--native-lib (mandatory)' <<<"$help_output" >/dev/null
  router_help_output="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" connectanum_router --help)"
  grep -F -- 'Usage: connectanum_router --config <path>' <<<"$router_help_output" >/dev/null
  bench_service_help_output="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" bench_router_service --help)"
  grep -F -- '--router-config' <<<"$bench_service_help_output" >/dev/null
  grep -F -- '--native-lib' <<<"$bench_service_help_output" >/dev/null
  worker_help_output="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" wamp_client_worker --help)"
  grep -F -- '--realm' <<<"$worker_help_output" >/dev/null
  grep -F -- '--targets-json' <<<"$worker_help_output" >/dev/null

  native_lib=""
  if native_runtime_supported && ensure_native_client_test_runtime; then
    native_lib="${CONNECTANUM_NATIVE_LIB:-}"
  fi
  if [[ -z "$native_lib" ]]; then
    printf 'Native runtime unavailable; completed bench CLI help smoke only.\n'
    return 0
  fi
  require_command curl
  require_command python3

  ports="$(
    python3 - <<'PY'
import socket

ports = []
for _ in range(4):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        ports.append(sock.getsockname()[1])
print(*ports)
PY
  )"
  read -r http_port rawsocket_port websocket_port router_bench_port <<<"$ports"
  if [[ ! "$http_port" =~ ^[0-9]+$ ||
        ! "$rawsocket_port" =~ ^[0-9]+$ ||
        ! "$websocket_port" =~ ^[0-9]+$ ||
        ! "$router_bench_port" =~ ^[0-9]+$ ]]; then
    printf 'Failed to reserve bench CLI smoke ports: %s\n' "$ports" >&2
    return 1
  fi

  cat >"$smoke_dir/router-bench.yaml" <<YAML
router:
  realms:
    - name: bench.control
      auth:
        authmethods: [anonymous]
      roles:
        - name: anonymous
          permissions:
            - uri: bench.
              match: prefix
              allow: [register, unregister, subscribe, unsubscribe, publish, call]
        - name: bench
          permissions:
            - uri: bench.
              match: prefix
              allow: [register, unregister, subscribe, unsubscribe, publish, call]

  listeners:
    - endpoint: 127.0.0.1:$router_bench_port
      authmethods: [anonymous]
      protocols: [rawsocket]
      tls:
        mode: disabled
      rawsocket:
        max_rawsocket_size_exponent: 16

  worker_pool:
    min_workers: 1

  authenticators:
    anonymous:
      type: anonymous
YAML

  cat >"$smoke_dir/router-bench-scenario.yaml" <<YAML
benchmarks:
  - name: installed_router_bench_rawsocket_rpc
    type: wamp_rawsocket_rpc
    duration: 1ms
    extra:
      serializer: json
      path: bench.rpc.echo
      iterations: 1
      request_bytes: 16
YAML

  router_bench_output="$(
    cd "$global_smoke_workspace"
    CONNECTANUM_SKIP_NATIVE_BUILD=true \
      PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" router_bench \
      --scenario "$smoke_dir/router-bench-scenario.yaml" \
      --config "$smoke_dir/router-bench.yaml" \
      --native-lib "$native_lib"
  )"
  grep -F -- 'WAMP samples: 1' <<<"$router_bench_output" >/dev/null
  grep -F -- 'WAMP request bytes: 16' <<<"$router_bench_output" >/dev/null

  cat >"$smoke_dir/bench-router.yaml" <<YAML
router:
  session_profiles:
    - name: public-http
      auth:
        methods: []

  realms:
    - name: bench.control
      auth:
        authmethods: [anonymous]
      roles:
        - name: anonymous
          permissions: []
        - name: bench
          permissions: []
    - name: bench.secure
      auth:
        authmethods: [ticket]
        ticket:
          authenticator: ticket-basic
      roles:
        - name: internal
          permissions:
            - uri: bench.
              match: prefix
              allow: [register, unregister, subscribe, unsubscribe, publish, call]
        - name: member
          permissions:
            - uri: bench.
              match: prefix
              allow: [register, unregister, subscribe, unsubscribe, publish, call]

  listeners:
    - endpoint: 127.0.0.1:$http_port
      protocols: [http]
      tls:
        mode: disabled
      http:
        session_profile: public-http
        routes:
          - match:
              path: /bench/healthz
              methods: [GET]
            action:
              type: rpc
              realm: bench.control
              procedure: bench.http.healthz
          - match:
              path: /bench/wamp
              methods: [POST]
            action:
              type: rpc
              realm: bench.control
              procedure: bench.http.wamp
          - match:
              path: /bench/stop
              methods: [POST]
            action:
              type: rpc
              realm: bench.control
              procedure: bench.http.stop
    - endpoint: 127.0.0.1:$rawsocket_port
      authmethods: [anonymous, ticket]
      protocols: [rawsocket]
      tls:
        mode: disabled
      rawsocket:
        max_rawsocket_size_exponent: 16
    - endpoint: 127.0.0.1:$websocket_port
      authmethods: [anonymous, ticket]
      protocols: [websocket]
      tls:
        mode: disabled
      websocket:
        path: /wamp
        subprotocols: [wamp.2.json, wamp.2.msgpack, wamp.2.cbor]

  worker_pool:
    min_workers: 1

  authenticators:
    anonymous:
      type: anonymous
    ticket-basic:
      type: ticket
      options:
        secrets:
          bench-user:
            ticket: bench-ticket
            role: member
            provider: bench-ticket-store
YAML

  (
    cd "$global_smoke_workspace"
    exec env CONNECTANUM_SKIP_NATIVE_BUILD=true \
      PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" bench_router_service \
      --router-config "$smoke_dir/bench-router.yaml" \
      --native-lib "$native_lib"
  ) >"$bench_service_log" 2>&1 &
  bench_service_pid=$!

  for _ in {1..600}; do
    if grep -F 'READY' "$bench_service_log" >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$bench_service_pid" >/dev/null 2>&1; then
      printf 'Bench router service exited before READY.\n' >&2
      cat "$bench_service_log" >&2
      _cleanup_bench_cli_smoke 1
    fi
    sleep 0.1
  done
  if ! grep -F 'READY' "$bench_service_log" >/dev/null 2>&1; then
    printf 'Bench router service did not report READY.\n' >&2
    cat "$bench_service_log" >&2
    _cleanup_bench_cli_smoke 1
  fi

  BENCH_HTTP_PORT="$http_port" python3 - <<'PY'
import json
import os
import urllib.error
import urllib.request

base_url = f"http://127.0.0.1:{os.environ['BENCH_HTTP_PORT']}"


def post_json(path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(
        f"{base_url}{path}",
        data=data,
        method="POST" if payload is not None else "GET",
        headers={"content-type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        body = error.read().decode(errors="replace")
        raise SystemExit(
            f"Installed bench service request {path} failed: "
            f"{error.code} {body}"
        )


def assert_wamp_scenario(label, scenario):
    status, body = post_json("/bench/wamp", scenario)
    if status != 200:
        raise SystemExit(
            f"Installed bench service WAMP {label} returned HTTP {status}: {body}"
        )
    decoded = json.loads(body)
    samples = decoded.get("samples")
    if not isinstance(samples, list) or len(samples) != scenario["iterations"]:
        raise SystemExit(
            f"Installed bench service WAMP {label} returned unexpected samples: "
            f"{body}"
        )
    sample = samples[0]
    if sample.get("request_bytes") != scenario["payload_bytes"]:
        raise SystemExit(
            f"Installed bench service WAMP {label} sample missed request bytes: "
            f"{body}"
        )


assert_wamp_scenario(
    "native rawsocket rpc",
    {
        "transport": "rawsocket",
        "client_impl": "native",
        "serializer": "json",
        "mode": "rpc",
        "uri": "bench.rpc.echo",
        "iterations": 1,
        "concurrency": 1,
        "payload_bytes": 16,
    },
)
assert_wamp_scenario(
    "dart websocket pubsub",
    {
        "transport": "websocket",
        "client_impl": "dart",
        "serializer": "cbor",
        "mode": "pubsub",
        "uri": "bench.topic",
        "iterations": 1,
        "concurrency": 1,
        "payload_bytes": 16,
    },
)
PY
  _cleanup_bench_cli_smoke 0
)

run_router_cli_consumer_package_smoke() (
  local health_body
  local health_head_status
  local health_alias_body
  local health_alias_head_status
  local mcp_port
  local metrics_body
  local metrics_head_status
  local metrics_line
  local metrics_port
  local native_lib
  local package_name
  local package_source
  local package_target
  local asset_body
  local asset_body_file
  local asset_head_headers_file
  local asset_headers_file
  local asset_range_body
  local asset_range_body_file
  local asset_range_headers_file
  local asset_traversal_body_file
  local fastcgi_body
  local fastcgi_body_file
  local fastcgi_headers_file
  local fastcgi_port
  local fastcgi_server_log
  local fastcgi_server_pid
  local reverse_proxy_body
  local reverse_proxy_body_file
  local reverse_proxy_headers_file
  local reverse_proxy_port
  local reverse_proxy_server_log
  local reverse_proxy_server_pid
  local traversal_status
  local dart_consumer_summary
  local smoke_dir
  local pub_cache
  local global_smoke_workspace
  local global_router_command
  local router_command
  local router_log
  local router_pid

  require_command dart

  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-router-cli-smoke.XXXXXX")"
  pub_cache="$smoke_dir/pub-cache"
  router_log="$smoke_dir/router.log"
  router_pid=""
  fastcgi_server_pid=""
  reverse_proxy_server_pid=""
  # The executable smoke should prove that consumer harnesses can discover the
  # source-checkout alias without requiring pub global activation first.
  _router_cli_smoke_process_ids() {
    ROUTER_SMOKE_CONFIG="$smoke_dir/router.yaml" ps -ww -axo pid=,comm=,command= \
      | awk '
          BEGIN {
            needle = ENVIRON["ROUTER_SMOKE_CONFIG"]
          }
          $2 !~ /(^|\/)(awk|bash|zsh|sh)$/ &&
          index($0, needle) &&
          index($0, "connectanum_router") &&
          index($0, "--config") {
            print $1
          }
        '
  }

  _wait_for_router_cli_smoke_processes() {
    local pids

    for _ in {1..50}; do
      pids="$(_router_cli_smoke_process_ids)"
      if [[ -z "$pids" ]]; then
        return 0
      fi
      sleep 0.1
    done

    pids="$(_router_cli_smoke_process_ids)"
    if [[ -n "$pids" ]]; then
      kill -KILL $pids >/dev/null 2>&1 || true
    fi

    for _ in {1..50}; do
      pids="$(_router_cli_smoke_process_ids)"
      if [[ -z "$pids" ]]; then
        return 0
      fi
      sleep 0.1
    done
  }

  _wait_for_router_cli_smoke_pid_exit() {
    local pid="$1"
    local shutdown_timeout_seconds="${CONNECTANUM_ROUTER_CLI_SMOKE_SHUTDOWN_TIMEOUT_SECONDS:-5}"
    local attempts
    local attempt

    if ! [[ "$shutdown_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
      shutdown_timeout_seconds=5
    fi
    attempts=$((shutdown_timeout_seconds * 10))

    for ((attempt = 0; attempt < attempts; attempt++)); do
      if ! kill -0 "$pid" >/dev/null 2>&1; then
        wait "$pid" >/dev/null 2>&1 || true
        return 0
      fi
      sleep 0.1
    done

    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
    wait "$pid" >/dev/null 2>&1 || true
  }

  _wait_for_router_cli_smoke_lock_release() {
    local lock_path

    if ! command -v lsof >/dev/null 2>&1; then
      return 0
    fi

    lock_path="${TMPDIR:-/tmp}/connectanum_native_runtime.lock"
    for _ in {1..50}; do
      if ! lsof "$lock_path" >/dev/null 2>&1; then
        return 0
      fi
      sleep 0.1
    done
  }

  _cleanup_router_cli_smoke() {
    local router_pids
    local status

    status="${1:-$?}"
    trap - EXIT HUP INT TERM
    if [[ -n "${fastcgi_server_pid:-}" ]]; then
      if kill -0 "$fastcgi_server_pid" >/dev/null 2>&1; then
        kill "$fastcgi_server_pid" >/dev/null 2>&1 || true
      fi
      wait "$fastcgi_server_pid" >/dev/null 2>&1 || true
    fi
    if [[ -n "${reverse_proxy_server_pid:-}" ]]; then
      if kill -0 "$reverse_proxy_server_pid" >/dev/null 2>&1; then
        kill "$reverse_proxy_server_pid" >/dev/null 2>&1 || true
      fi
      wait "$reverse_proxy_server_pid" >/dev/null 2>&1 || true
    fi
    if [[ -n "${router_pid:-}" ]]; then
      if kill -0 "$router_pid" >/dev/null 2>&1; then
        kill "$router_pid" >/dev/null 2>&1 || true
      fi
      router_pids="$(_router_cli_smoke_process_ids)"
      if [[ -n "$router_pids" ]]; then
        kill $router_pids >/dev/null 2>&1 || true
      fi
      _wait_for_router_cli_smoke_pid_exit "$router_pid"
      _wait_for_router_cli_smoke_processes
      _wait_for_router_cli_smoke_lock_release
    fi
    if [[ -n "${smoke_dir:-}" ]]; then
      rm -rf "$smoke_dir"
    fi
    exit "$status"
  }
  trap _cleanup_router_cli_smoke EXIT
  trap '_cleanup_router_cli_smoke 129' HUP
  trap '_cleanup_router_cli_smoke 130' INT
  trap '_cleanup_router_cli_smoke 143' TERM

  printf 'Running router CLI consumer package smoke from %s.\n' "$smoke_dir"
  router_command="$(PATH="$ROOT_DIR/bin:$PATH" command -v connectanum_router || true)"
  if [[ "$router_command" != "$ROOT_DIR/bin/connectanum_router" ]]; then
    printf 'Expected source-checkout connectanum_router alias, got: %s\n' "${router_command:-<missing>}" >&2
    return 1
  fi
  (
    cd "$smoke_dir"
    PATH="$ROOT_DIR/bin:$PATH" connectanum_router --help \
      | grep -F 'Usage: connectanum_router --config <path>'
  )

  mkdir -p "$smoke_dir/router-runner"
  cat >"$smoke_dir/router-runner/pubspec.yaml" <<EOF
name: connectanum_router_cli_runner_smoke
publish_to: none
environment:
  sdk: '^3.9.2'
hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
    connectanum_router:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
dependencies:
  connectanum_router: any
dependency_overrides:
  connectanum_core:
    path: "$ROOT_DIR/packages/connectanum_core"
  connectanum_client:
    path: "$ROOT_DIR/packages/connectanum_client"
  connectanum_mcp:
    path: "$ROOT_DIR/packages/connectanum_mcp"
  connectanum_router:
    path: "$ROOT_DIR/packages/connectanum_router"
EOF

  (
    cd "$smoke_dir/router-runner"
    PUB_CACHE="$pub_cache" dart pub get >&2
    PUB_CACHE="$pub_cache" dart run connectanum_router --help \
      | grep -F 'Usage: connectanum_router --config <path>'
  )

  global_smoke_workspace="$smoke_dir/global-workspace"
  mkdir -p "$global_smoke_workspace/packages"
  cat >"$global_smoke_workspace/pubspec.yaml" <<EOF
name: connectanum_router_global_activation_smoke_workspace
publish_to: none
environment:
  sdk: '^3.9.2'
hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
    connectanum_router:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
workspace:
  - packages/connectanum_core
  - packages/connectanum_mcp
  - packages/connectanum_client
  - packages/connectanum_router
  - packages/connectanum_auth_server
EOF
  if [[ -f "$ROOT_DIR/pubspec.lock" ]]; then
    cp "$ROOT_DIR/pubspec.lock" "$global_smoke_workspace/pubspec.lock"
  fi

  for package_name in \
    connectanum_core \
    connectanum_mcp \
    connectanum_client \
    connectanum_router \
    connectanum_auth_server; do
    package_source="$ROOT_DIR/packages/$package_name"
    package_target="$global_smoke_workspace/packages/$package_name"
    mkdir -p "$package_target"
    cp "$package_source/pubspec.yaml" "$package_target/pubspec.yaml"
    cp -R "$package_source/lib" "$package_target/lib"
    if [[ -d "$package_source/bin" ]]; then
      cp -R "$package_source/bin" "$package_target/bin"
    fi
    if [[ -d "$package_source/hook" ]]; then
      cp -R "$package_source/hook" "$package_target/hook"
    fi
  done
  CONNECTANUM_SKIP_NATIVE_BUILD=true \
    PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" dart pub global activate --source path "$global_smoke_workspace/packages/connectanum_router" >&2
  global_router_command="$(PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" command -v connectanum_router || true)"
  if [[ "$global_router_command" != "$pub_cache/bin/connectanum_router" ]]; then
    printf 'Expected isolated pub-cache connectanum_router command, got: %s\n' \
      "${global_router_command:-<missing>}" >&2
    return 1
  fi
  PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" connectanum_router --help \
    | grep -F 'Usage: connectanum_router --config <path>'

  native_lib=""
  if native_runtime_supported && ensure_native_client_test_runtime; then
    native_lib="${CONNECTANUM_NATIVE_LIB:-}"
  fi
  if [[ -z "$native_lib" ]]; then
    printf 'Native runtime unavailable; completed router CLI help smoke only.\n'
    return 0
  fi
  require_command curl
  require_command python3

  mcp_port="$(
    python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
  )"
  fastcgi_port="$(
    python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
  )"
  reverse_proxy_port="$(
    python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
  )"

  mkdir -p "$smoke_dir/static"
  printf 'router file route smoke\n' >"$smoke_dir/static/hello.txt"
  fastcgi_server_log="$smoke_dir/fastcgi.log"
  cat >"$smoke_dir/fastcgi_upstream.py" <<'PY'
import os
import socket
import struct

FCGI_VERSION = 1
FCGI_BEGIN_REQUEST = 1
FCGI_END_REQUEST = 3
FCGI_PARAMS = 4
FCGI_STDIN = 5
FCGI_STDOUT = 6
REQUEST_ID = 1


def read_exact(stream, length):
    data = bytearray()
    while len(data) < length:
        chunk = stream.recv(length - len(data))
        if not chunk:
            raise EOFError("unexpected FastCGI EOF")
        data.extend(chunk)
    return bytes(data)


def read_length(data, offset):
    first = data[offset]
    if first & 0x80:
        return (
            ((first & 0x7F) << 24)
            | (data[offset + 1] << 16)
            | (data[offset + 2] << 8)
            | data[offset + 3],
            offset + 4,
        )
    return first, offset + 1


def decode_params(data):
    params = {}
    offset = 0
    while offset < len(data):
        name_length, offset = read_length(data, offset)
        value_length, offset = read_length(data, offset)
        name = data[offset : offset + name_length].decode("utf-8")
        offset += name_length
        value = data[offset : offset + value_length].decode("utf-8")
        offset += value_length
        params[name] = value
    return params


def record(record_type, content):
    padding_length = (8 - (len(content) % 8)) % 8
    header = struct.pack(
        "!BBHHBB",
        FCGI_VERSION,
        record_type,
        REQUEST_ID,
        len(content),
        padding_length,
        0,
    )
    return header + content + (b"\x00" * padding_length)


def serve(connection):
    params_bytes = bytearray()
    stdin_bytes = bytearray()
    while True:
        header = read_exact(connection, 8)
        version, record_type, request_id, content_length, padding_length, _ = (
            struct.unpack("!BBHHBB", header)
        )
        if version != FCGI_VERSION or request_id != REQUEST_ID:
            raise ValueError("unexpected FastCGI record header")
        content = read_exact(connection, content_length)
        if padding_length:
            read_exact(connection, padding_length)
        if record_type == FCGI_BEGIN_REQUEST:
            continue
        if record_type == FCGI_PARAMS:
            if content:
                params_bytes.extend(content)
            continue
        if record_type == FCGI_STDIN:
            if content:
                stdin_bytes.extend(content)
                continue
            break

    params = decode_params(bytes(params_bytes))
    body = (
        "fastcgi:"
        f"{stdin_bytes.decode('utf-8')}:"
        f"{params.get('REQUEST_METHOD', '')}:"
        f"{params.get('SCRIPT_FILENAME', '')}:"
        f"{params.get('QUERY_STRING', '')}"
    ).encode("utf-8")
    stdout = (
        b"Status: 207 Multi-Status\r\n"
        b"Content-Type: text/plain\r\n"
        b"X-FastCGI: ok\r\n"
        b"\r\n"
        + body
    )
    connection.sendall(record(FCGI_STDOUT, stdout))
    connection.sendall(record(FCGI_STDOUT, b""))
    connection.sendall(record(FCGI_END_REQUEST, struct.pack("!IB3x", 0, 0)))


with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", int(os.environ["FASTCGI_PORT"])))
    server.listen(1)
    with open(os.environ["FASTCGI_READY"], "w", encoding="utf-8") as ready:
        ready.write("ready\n")
    connection, _ = server.accept()
    with connection:
        serve(connection)
PY
  FASTCGI_PORT="$fastcgi_port" \
    FASTCGI_READY="$smoke_dir/fastcgi.ready" \
    python3 "$smoke_dir/fastcgi_upstream.py" \
      >"$fastcgi_server_log" 2>&1 &
  fastcgi_server_pid=$!
  for _ in {1..50}; do
    if [[ -f "$smoke_dir/fastcgi.ready" ]]; then
      break
    fi
    if ! kill -0 "$fastcgi_server_pid" >/dev/null 2>&1; then
      printf 'Router CLI FastCGI smoke upstream exited before readiness.\n' >&2
      cat "$fastcgi_server_log" >&2
      _cleanup_router_cli_smoke 1
    fi
    sleep 0.1
  done
  if [[ ! -f "$smoke_dir/fastcgi.ready" ]]; then
    printf 'Router CLI FastCGI smoke upstream did not become ready.\n' >&2
    cat "$fastcgi_server_log" >&2
    _cleanup_router_cli_smoke 1
  fi

  reverse_proxy_server_log="$smoke_dir/reverse-proxy.log"
  cat >"$smoke_dir/reverse_proxy_upstream.py" <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def log_message(self, format, *args):
        return

    def _read_request_body(self):
        transfer_encoding = self.headers.get("transfer-encoding", "").lower()
        if "chunked" in transfer_encoding:
            chunks = []
            while True:
                line = self.rfile.readline()
                if line == b"":
                    raise EOFError("unexpected chunked request EOF")
                line = line.strip()
                if not line:
                    continue
                size = int(line.split(b";", 1)[0], 16)
                if size == 0:
                    while True:
                        trailer = self.rfile.readline()
                        if trailer in (b"\r\n", b"\n", b""):
                            break
                    break
                chunks.append(self.rfile.read(size))
                self.rfile.read(2)
            return b"".join(chunks).decode("utf-8")
        length = int(self.headers.get("content-length", "0") or "0")
        return self.rfile.read(length).decode("utf-8")

    def _handle(self):
        body = self._read_request_body()
        response = (
            f"reverse_proxy:{body}:{self.command}:{self.path}:"
            f"{self.headers.get('x-forwarded-proto', '')}:"
            f"{self.headers.get('x-forwarded-host', '')}"
        ).encode("utf-8")
        self.send_response(208)
        self.send_header("Content-Type", "text/plain")
        self.send_header("X-Reverse-Proxy", "ok")
        self.send_header("Connection", "close")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)


server = ThreadingHTTPServer(
    ("127.0.0.1", int(os.environ["REVERSE_PROXY_PORT"])),
    Handler,
)
with open(os.environ["REVERSE_PROXY_READY"], "w", encoding="utf-8") as ready:
    ready.write("ready\n")
try:
    server.serve_forever()
finally:
    server.server_close()
PY
  REVERSE_PROXY_PORT="$reverse_proxy_port" \
    REVERSE_PROXY_READY="$smoke_dir/reverse-proxy.ready" \
    python3 "$smoke_dir/reverse_proxy_upstream.py" \
      >"$reverse_proxy_server_log" 2>&1 &
  reverse_proxy_server_pid=$!
  for _ in {1..50}; do
    if [[ -f "$smoke_dir/reverse-proxy.ready" ]]; then
      break
    fi
    if ! kill -0 "$reverse_proxy_server_pid" >/dev/null 2>&1; then
      printf 'Router CLI reverse proxy smoke upstream exited before readiness.\n' >&2
      cat "$reverse_proxy_server_log" >&2
      _cleanup_router_cli_smoke 1
    fi
    sleep 0.1
  done
  if [[ ! -f "$smoke_dir/reverse-proxy.ready" ]]; then
    printf 'Router CLI reverse proxy smoke upstream did not become ready.\n' >&2
    cat "$reverse_proxy_server_log" >&2
    _cleanup_router_cli_smoke 1
  fi

  cat >"$smoke_dir/router.yaml" <<YAML
router:
  session_profiles:
    - name: public-wamp
      auth:
        methods: [anonymous]
    - name: public-http
      auth:
        methods: []
    - name: mcp-ticket
      realm: cli.smoke
      auth:
        methods: [ticket]

  realms:
    - name: cli.smoke
      auth:
        authmethods: [anonymous, ticket]
        ticket:
          authenticator: ticket-basic
      roles:
        - name: anonymous
          permissions:
            - uri: ""
              match: prefix
              allow: [subscribe, publish, call, register, unregister]
        - name: member
          permissions:
            - uri: ""
              match: prefix
              allow: [subscribe, publish, call, register, unregister]

    - name: connectanum.metrics
      auth:
        authmethods: [anonymous]
      roles:
        - name: anonymous
          permissions:
            - uri: ""
              match: prefix
              allow: [call]
        - name: metrics
          permissions:
            - uri: ""
              match: prefix
              allow: [register, unregister, call, subscribe, publish]

  listeners:
    - endpoint: 127.0.0.1:0
      session_profile: public-wamp
      protocols: [rawsocket]
      tls:
        mode: disabled
      rawsocket:
        max_rawsocket_size_exponent: 16
    - endpoint: 127.0.0.1:$mcp_port
      session_profile: public-wamp
      protocols: [http]
      tls:
        mode: disabled
      http:
        session_profile: public-http
        routes:
          - match:
              prefix: /assets
              methods: [GET]
            action:
              type: file
              directory: "$smoke_dir/static"
              cache_control: max-age=60
          - match:
              path: /proxy/healthz
              methods: [GET, HEAD]
            action:
              type: session_proxy
              delegate: metrics
              procedure: connectanum.metrics.healthz
          - match:
              prefix: /php
              methods: [GET, POST]
            action:
              type: fastcgi
              delegate: "127.0.0.1:$fastcgi_port"
              options:
                document_root: /srv/app/public
                strip_prefix: true
                timeout_ms: 5000
          - match:
              prefix: /upstream
              methods: [GET, POST]
            action:
              type: reverse_proxy
              delegate: "http://127.0.0.1:$reverse_proxy_port/backend"
              options:
                strip_prefix: true
                timeout_ms: 5000
                max_response_bytes: 1048576
          - match:
              path: /auth
              methods: [POST]
            action:
              type: auth
              session_profile: mcp-ticket
              token_ttl_ms: 60000
              refresh_token_ttl_ms: 300000
              allow_insecure_transport: true
          - match:
              path: /mcp
            action:
              type: mcp
              realm: cli.smoke
              session_profile: public-wamp
              options:
                name: cli-router-mcp
                instructions: Router CLI MCP smoke endpoint.
                include_standard_meta_api: true
                include_pubsub_tools: true
                resources:
                  - uri: cli://mcp/context
                    name: cli-context
                    mime_type: text/plain
                    text: Router CLI MCP context.
                resource_templates:
                  - uri_template: cli://mcp/task/{taskId}
                    name: cli-task
                    description: Router CLI task resource template.
                prompts:
                  - name: summarize-cli-context
                    arguments:
                      - name: topic
                        required: true
                    messages:
                      - role: user
                        text: Summarize {{topic}} from the router CLI MCP smoke.
                procedures:
                  - procedure: cli.smoke.lookup
                    tool_name: cli.smoke.lookup
                    title: CLI Lookup
                    description: Procedure metadata exposed by the router CLI MCP smoke.
                    allow_call: false
                topics:
                  - topic: cli.smoke.events
                    title: CLI Smoke Events
                    description: Events exposed by the router CLI MCP smoke.
          - match:
              path: /mcp/secure
            action:
              type: mcp
              realm: cli.smoke
              session_profile: mcp-ticket
              options:
                name: cli-router-mcp-secure
                instructions: Router CLI bearer-protected MCP smoke endpoint.
                include_standard_meta_api: true
                include_pubsub_tools: true
                allow_insecure_transport: true
                resources:
                  - uri: cli://mcp/secure/context
                    name: cli-secure-context
                    mime_type: text/plain
                    text: Router CLI secure MCP context.
                resource_templates:
                  - uri_template: cli://mcp/secure/task/{taskId}
                    name: cli-secure-task
                    description: Router CLI secure task resource template.
                prompts:
                  - name: summarize-secure-cli-context
                    arguments:
                      - name: topic
                        required: true
                    messages:
                      - role: user
                        text: Summarize secure {{topic}} from the router CLI MCP smoke.
                procedures:
                  - procedure: cli.smoke.secure.lookup
                    tool_name: cli.smoke.secure.lookup
                    title: CLI Secure Lookup
                    description: Protected procedure metadata exposed by the router CLI MCP smoke.
                    allow_call: false
                topics:
                  - topic: cli.smoke.secure.events
                    title: CLI Secure Smoke Events
                    description: Protected events exposed by the router CLI MCP smoke.
                  - topic: cli.smoke.secure.metadata
                    title: CLI Secure Metadata Events
                    description: Protected configured-only events exposed by the router CLI MCP smoke.
                    allow_publish: false
                    allow_subscribe: true
          - match:
              path: /mcp/secure-json-post
            action:
              type: mcp
              realm: cli.smoke
              session_profile: mcp-ticket
              options:
                name: cli-router-mcp-secure-json-post
                instructions: Router CLI bearer-protected JSON-response MCP smoke endpoint.
                include_standard_meta_api: true
                include_pubsub_tools: true
                allow_insecure_transport: true
                post_response_transport: json
                resource_list_page_size: 1
                resource_template_list_page_size: 1
                prompt_list_page_size: 1
                resources:
                  - uri: cli://mcp/secure/context
                    name: cli-secure-context
                    mime_type: text/plain
                    text: Router CLI secure MCP context.
                  - uri: cli://mcp/secure/context-extra
                    name: cli-secure-context-extra
                    mime_type: text/plain
                    text: Router CLI secure MCP extra context.
                resource_templates:
                  - uri_template: cli://mcp/secure/task/{taskId}
                    name: cli-secure-task
                    description: Router CLI secure task resource template.
                  - uri_template: cli://mcp/secure/task/{taskId}/extra
                    name: cli-secure-task-extra
                    description: Router CLI secure extra task resource template.
                prompts:
                  - name: summarize-secure-cli-context
                    arguments:
                      - name: topic
                        required: true
                    messages:
                      - role: user
                        text: Summarize secure {{topic}} from the router CLI MCP smoke.
                  - name: summarize-secure-cli-context-extra
                    arguments:
                      - name: topic
                        required: true
                    messages:
                      - role: user
                        text: Summarize extra secure {{topic}} from the router CLI MCP smoke.
                procedures:
                  - procedure: cli.smoke.secure.lookup
                    tool_name: cli.smoke.secure.lookup
                    title: CLI Secure Lookup
                    description: Protected procedure metadata exposed by the router CLI MCP smoke.
                    allow_call: false
                topics:
                  - topic: cli.smoke.secure.events
                    title: CLI Secure Smoke Events
                    description: Protected events exposed by the router CLI MCP smoke.
                  - topic: cli.smoke.secure.metadata
                    title: CLI Secure Metadata Events
                    description: Protected configured-only events exposed by the router CLI MCP smoke.
                    allow_publish: false
                    allow_subscribe: true

  internal_realms:
    - name: connectanum.metrics
      auth_id: metrics-daemon
      auth_role: metrics
      services: [metrics]

  metrics:
    open_metrics:
      enabled: true
      listen: 127.0.0.1:0
      path: /metrics
      realm: connectanum.metrics

  authenticators:
    anonymous:
      type: anonymous
    ticket-basic:
      type: ticket
      options:
        secrets:
          cli-user:
            ticket: cli-ticket
            role: member
            provider: cli-ticket-db
YAML

  (
    cd "$smoke_dir"
    exec env PATH="$pub_cache/bin:$PATH" PUB_CACHE="$pub_cache" connectanum_router \
      --config "$smoke_dir/router.yaml" \
      --native-lib "$native_lib"
  ) >"$router_log" 2>&1 &
  router_pid=$!

  for _ in {1..300}; do
    if grep -F 'OpenMetrics exporter listening on ' "$router_log" >/dev/null 2>&1 && \
       grep -F 'Router running. Press Ctrl+C to stop.' "$router_log" >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$router_pid" >/dev/null 2>&1; then
      printf 'Router CLI exited before the health endpoint was ready.\n' >&2
      cat "$router_log" >&2
      _cleanup_router_cli_smoke 1
    fi
    sleep 0.1
  done

  if ! grep -F 'Router running. Press Ctrl+C to stop.' "$router_log" >/dev/null 2>&1; then
    printf 'Router CLI did not report a running state.\n' >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi

  metrics_line="$(grep -F 'OpenMetrics exporter listening on ' "$router_log" | head -n 1)"
  metrics_port="$(sed -E 's/.*listening on 127\.0\.0\.1:([0-9]+)\/metrics.*/\1/' <<<"$metrics_line")"
  if [[ ! "$metrics_port" =~ ^[0-9]+$ ]]; then
    printf 'Could not parse router CLI OpenMetrics port from: %s\n' "$metrics_line" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi

  health_body="$(curl -fsS "http://127.0.0.1:$metrics_port/healthz")"
  if [[ "$health_body" != "ok" ]]; then
    printf 'Router CLI healthz returned unexpected body: %s\n' "$health_body" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi
  health_head_status="$(curl -fsS -I -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$metrics_port/healthz")"
  if [[ "$health_head_status" != "200" ]]; then
    printf 'Router CLI healthz HEAD returned unexpected status: %s\n' \
      "$health_head_status" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi

  health_alias_body="$(curl -fsS "http://127.0.0.1:$metrics_port/health")"
  if [[ "$health_alias_body" != "ok" ]]; then
    printf 'Router CLI health alias returned unexpected body: %s\n' \
      "$health_alias_body" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi
  health_alias_head_status="$(curl -fsS -I -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$metrics_port/health")"
  if [[ "$health_alias_head_status" != "200" ]]; then
    printf 'Router CLI health alias HEAD returned unexpected status: %s\n' \
      "$health_alias_head_status" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi

  metrics_body="$(curl -fsS "http://127.0.0.1:$metrics_port/metrics")"
  grep -F 'connectanum_router_drain_in_progress' <<<"$metrics_body" >/dev/null
  metrics_head_status="$(curl -fsS -I -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$metrics_port/metrics")"
  if [[ "$metrics_head_status" != "200" ]]; then
    printf 'Router CLI metrics HEAD returned unexpected status: %s\n' \
      "$metrics_head_status" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi

  asset_headers_file="$smoke_dir/asset.headers"
  asset_body_file="$smoke_dir/asset.body"
  asset_head_headers_file="$smoke_dir/asset-head.headers"
  asset_range_headers_file="$smoke_dir/asset-range.headers"
  asset_range_body_file="$smoke_dir/asset-range.body"
  asset_traversal_body_file="$smoke_dir/asset-traversal.body"
  fastcgi_headers_file="$smoke_dir/fastcgi.headers"
  fastcgi_body_file="$smoke_dir/fastcgi.body"
  reverse_proxy_headers_file="$smoke_dir/reverse-proxy.headers"
  reverse_proxy_body_file="$smoke_dir/reverse-proxy.body"

  curl -fsS -D "$asset_headers_file" -o "$asset_body_file" \
    "http://127.0.0.1:$mcp_port/assets/hello.txt"
  asset_body="$(<"$asset_body_file")"
  if [[ "$asset_body" != "router file route smoke" ]]; then
    printf 'Router CLI configured file route returned unexpected body: %s\n' \
      "$asset_body" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi
  grep -Eiq '^content-type: text/plain(; charset=utf-8)?\r?$' \
    "$asset_headers_file"
  grep -Eiq '^cache-control: max-age=60\r?$' "$asset_headers_file"
  grep -Eiq '^accept-ranges: bytes\r?$' "$asset_headers_file"

  curl -fsS -I -D "$asset_head_headers_file" -o /dev/null \
    "http://127.0.0.1:$mcp_port/assets/hello.txt"
  grep -Eq '^HTTP/[0-9.]+ 200' "$asset_head_headers_file"
  grep -Eiq '^content-length: 24\r?$' "$asset_head_headers_file"

  curl -fsS -D "$asset_range_headers_file" -H 'Range: bytes=0-5' \
    -o "$asset_range_body_file" \
    "http://127.0.0.1:$mcp_port/assets/hello.txt"
  asset_range_body="$(<"$asset_range_body_file")"
  if [[ "$asset_range_body" != "router" ]]; then
    printf 'Router CLI configured file range returned unexpected body: %s\n' \
      "$asset_range_body" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi
  grep -Eq '^HTTP/[0-9.]+ 206' "$asset_range_headers_file"
  grep -Eiq '^content-range: bytes 0-5/24\r?$' "$asset_range_headers_file"

  traversal_status="$(
    curl -sS -o "$asset_traversal_body_file" -w '%{http_code}' \
      "http://127.0.0.1:$mcp_port/assets/%2e%2e/router.yaml"
  )"
  if [[ "$traversal_status" != "404" ]]; then
    printf 'Router CLI configured file traversal returned HTTP %s.\n' \
      "$traversal_status" >&2
    cat "$asset_traversal_body_file" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi
  grep -F 'file_not_found' "$asset_traversal_body_file" >/dev/null

  curl -fsS -D "$fastcgi_headers_file" -o "$fastcgi_body_file" \
    --data-binary 'ping' \
    "http://127.0.0.1:$mcp_port/php/index.php?active=true"
  fastcgi_body="$(<"$fastcgi_body_file")"
  if [[ "$fastcgi_body" != "fastcgi:ping:POST:/srv/app/public/index.php:active=true" ]]; then
    printf 'Router CLI configured FastCGI route returned unexpected body: %s\n' \
      "$fastcgi_body" >&2
    cat "$fastcgi_server_log" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi
  grep -Eq '^HTTP/[0-9.]+ 207' "$fastcgi_headers_file"
  grep -Eiq '^x-fastcgi: ok\r?$' "$fastcgi_headers_file"

  curl -fsS -D "$reverse_proxy_headers_file" \
    -H 'X-Consumer-Smoke: yes' \
    -o "$reverse_proxy_body_file" \
    --data-binary 'ping' \
    "http://127.0.0.1:$mcp_port/upstream/echo?active=true"
  reverse_proxy_body="$(<"$reverse_proxy_body_file")"
  if [[ "$reverse_proxy_body" != "reverse_proxy:ping:POST:/backend/echo?active=true:http:127.0.0.1:$mcp_port" ]]; then
    printf 'Router CLI configured reverse_proxy route returned unexpected body: %s\n' \
      "$reverse_proxy_body" >&2
    cat "$reverse_proxy_server_log" >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi
  grep -Eq '^HTTP/[0-9.]+ 208' "$reverse_proxy_headers_file"
  grep -Eiq '^x-reverse-proxy: ok\r?$' "$reverse_proxy_headers_file"

  MCP_PORT="$mcp_port" python3 - <<'PY'
import json
import os
import time
import urllib.error
import urllib.request

base_url = f"http://127.0.0.1:{os.environ['MCP_PORT']}"
endpoint = f"{base_url}/mcp"
secure_endpoint = f"{base_url}/mcp/secure"
secure_json_endpoint = f"{base_url}/mcp/secure-json-post"
auth_endpoint = f"{base_url}/auth"
protocol_version = "2025-11-25"
auth_id = "cli-user"
ticket = "cli-ticket"


def request(
    method,
    payload=None,
    *,
    endpoint=endpoint,
    headers=None,
    accept="application/json",
    allow_error=False,
):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(endpoint, data=data, method=method)
    req.add_header("Accept", accept)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    for name, value in (headers or {}).items():
        req.add_header(name, value)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return (
                response.status,
                {key.lower(): value for key, value in response.headers.items()},
                response.read().decode("utf-8"),
            )
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        if allow_error:
            return (
                error.code,
                {key.lower(): value for key, value in error.headers.items()},
                body,
            )
        raise AssertionError(
            f"{method} {endpoint} returned {error.code}: {body}"
        ) from error


def json_payload(body):
    text = body.strip()
    if not text:
        return None
    if text.startswith("event:") or text.startswith("data:"):
        for block in text.split("\n\n"):
            data_lines = [
                line[len("data:") :].lstrip()
                for line in block.splitlines()
                if line.startswith("data:")
            ]
            if data_lines:
                return json.loads("\n".join(data_lines))
        raise AssertionError(f"SSE response did not contain data: {body}")
    return json.loads(text)


def post_json(payload, *, endpoint=endpoint, headers=None, accept="application/json"):
    status, response_headers, body = request(
        "POST", payload, endpoint=endpoint, headers=headers, accept=accept
    )
    if status < 200 or status >= 300:
        raise AssertionError(f"Unexpected MCP HTTP status {status}: {body}")
    parsed = json_payload(body)
    if isinstance(parsed, dict) and "error" in parsed:
        raise AssertionError(f"MCP JSON-RPC error: {parsed['error']}")
    return status, response_headers, parsed


def post_auth(payload, *, allow_error=False):
    status, response_headers, body = request(
        "POST",
        payload,
        endpoint=auth_endpoint,
        accept="application/json",
        allow_error=allow_error,
    )
    parsed = json_payload(body)
    if not allow_error and (status < 200 or status >= 300):
        raise AssertionError(f"Unexpected auth HTTP status {status}: {body}")
    return status, response_headers, parsed


def expect_secure_rejection(payload, *, endpoint=secure_endpoint, headers=None, label):
    status, _, body = request(
        "POST",
        payload,
        endpoint=endpoint,
        headers=headers,
        accept="application/json",
        allow_error=True,
    )
    if status not in (401, 403):
        raise AssertionError(
            f"Installed CLI protected MCP route accepted {label}: {status} {body}"
        )


def structured_content(message, *, label):
    result = message.get("result") if isinstance(message, dict) else None
    if not isinstance(result, dict):
        raise AssertionError(f"{label} missed JSON-RPC result: {message}")
    if result.get("isError") is True:
        raise AssertionError(f"{label} returned MCP tool error: {result}")
    content = result.get("structuredContent")
    if not isinstance(content, dict):
        raise AssertionError(f"{label} missed structuredContent: {result}")
    return content


def poll_direct_pubsub_events(
    handle,
    *,
    endpoint,
    headers=None,
    id_prefix,
    label,
    marker,
):
    for attempt in range(30):
        _, _, poll_result = post_json(
            {
                "jsonrpc": "2.0",
                "id": f"{id_prefix}-poll-{attempt}",
                "method": "connectanum.pubsub.poll",
                "params": {"handle": handle, "limit": 10},
            },
            endpoint=endpoint,
            headers=headers,
        )
        content = structured_content(
            poll_result,
            label=f"{label} poll",
        )
        events = content.get("events")
        if isinstance(events, list) and marker in json.dumps(events):
            return events
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {label} events")


_, _, tools = post_json({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
tool_names = {tool.get("name") for tool in tools["result"]["tools"]}
for expected in {
    "connectanum.api.list",
    "connectanum.pubsub.subscribe",
    "connectanum.pubsub.publish",
}:
    if expected not in tool_names:
        raise AssertionError(f"Installed CLI MCP route missed tool {expected}")

_, _, resources = post_json(
    {"jsonrpc": "2.0", "id": 2, "method": "resources/list"}
)
resource_uris = {
    resource.get("uri") for resource in resources["result"]["resources"]
}
if "cli://mcp/context" not in resource_uris:
    raise AssertionError("Installed CLI MCP route missed configured resource")

_, _, resource = post_json(
    {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "resources/read",
        "params": {"uri": "cli://mcp/context"},
    }
)
if "Router CLI MCP context." not in json.dumps(resource["result"]["contents"]):
    raise AssertionError("Installed CLI MCP resources/read missed context")

_, _, resource_templates = post_json(
    {"jsonrpc": "2.0", "id": 4, "method": "resources/templates/list"}
)
resource_template_uris = {
    template.get("uriTemplate")
    for template in resource_templates["result"]["resourceTemplates"]
}
if "cli://mcp/task/{taskId}" not in resource_template_uris:
    raise AssertionError("Installed CLI MCP route missed configured resource template")

_, _, prompts = post_json({"jsonrpc": "2.0", "id": 5, "method": "prompts/list"})
prompt_names = {prompt.get("name") for prompt in prompts["result"]["prompts"]}
if "summarize-cli-context" not in prompt_names:
    raise AssertionError("Installed CLI MCP route missed configured prompt")

_, _, prompt = post_json(
    {
        "jsonrpc": "2.0",
        "id": 6,
        "method": "prompts/get",
        "params": {
            "name": "summarize-cli-context",
            "arguments": {"topic": "consumer readiness"},
        },
    }
)
if "consumer readiness" not in json.dumps(prompt["result"]["messages"]):
    raise AssertionError("Installed CLI MCP prompts/get missed substitution")

_, _, procedures = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-procedures",
        "method": "connectanum.api.list",
        "params": {"kind": "procedure"},
    }
)
if "cli.smoke.lookup" not in json.dumps(procedures["result"]):
    raise AssertionError(
        "Installed CLI MCP direct procedure catalog missed public procedure"
    )
_, _, procedure_description = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-procedure-describe",
        "method": "connectanum.api.describe",
        "params": {"kind": "procedure", "uri": "cli.smoke.lookup"},
    }
)
if "CLI Lookup" not in json.dumps(procedure_description["result"]):
    raise AssertionError(
        "Installed CLI MCP direct procedure describe missed public metadata"
    )

_, _, topics = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-topics",
        "method": "connectanum.api.list",
        "params": {"kind": "topic"},
    }
)
if "cli.smoke.events" not in json.dumps(topics["result"]):
    raise AssertionError("Installed CLI MCP direct topic catalog missed public topic")
_, _, topic_description = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-topic-describe",
        "method": "connectanum.api.describe",
        "params": {"kind": "topic", "uri": "cli.smoke.events"},
    }
)
if "CLI Smoke Events" not in json.dumps(topic_description["result"]):
    raise AssertionError(
        "Installed CLI MCP direct topic describe missed public metadata"
    )
_, _, direct_subscribe = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-direct-pubsub-subscribe",
        "method": "connectanum.pubsub.subscribe",
        "params": {"topic": "cli.smoke.events", "queueLimit": 5},
    }
)
direct_subscription = structured_content(
    direct_subscribe,
    label="Installed CLI MCP direct pubsub subscribe",
)
direct_handle = direct_subscription.get("handle")
if (
    not isinstance(direct_handle, str)
    or not direct_handle
    or direct_subscription.get("topic") != "cli.smoke.events"
):
    raise AssertionError(
        "Installed CLI MCP direct pubsub subscribe was invalid: "
        f"{direct_subscription}"
    )
_, _, direct_publish = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-direct-pubsub-publish",
        "method": "connectanum.pubsub.publish",
        "params": {
            "topic": "cli.smoke.events",
            "argumentsKeywords": {"via": "public-direct-publish"},
            "acknowledge": True,
        },
    }
)
direct_publication = structured_content(
    direct_publish,
    label="Installed CLI MCP direct pubsub publish",
)
if (
    direct_publication.get("topic") != "cli.smoke.events"
    or direct_publication.get("acknowledged") is not True
):
    raise AssertionError(
        "Installed CLI MCP direct pubsub publish was invalid: "
        f"{direct_publication}"
    )
direct_events = poll_direct_pubsub_events(
    direct_handle,
    endpoint=endpoint,
    id_prefix="public-direct-pubsub",
    label="Installed CLI MCP direct pubsub",
    marker="public-direct-publish",
)
if "public-direct-publish" not in json.dumps(direct_events):
    raise AssertionError("Installed CLI MCP direct pubsub poll missed public event")

streamable_headers = {
    "MCP-Protocol-Version": protocol_version,
}
_, initialize_headers, initialize = post_json(
    {
        "jsonrpc": "2.0",
        "id": "initialize",
        "method": "initialize",
        "params": {
            "protocolVersion": protocol_version,
            "capabilities": {},
            "clientInfo": {
                "name": "router-cli-consumer-smoke",
                "version": "0.0.0",
            },
        },
    },
    headers=streamable_headers,
    accept="application/json, text/event-stream",
)
session_id = initialize_headers.get("mcp-session-id")
if not session_id:
    raise AssertionError("Installed CLI MCP Streamable initialize missed session id")
if initialize["result"]["protocolVersion"] != protocol_version:
    raise AssertionError("Installed CLI MCP Streamable initialize changed protocol")

session_headers = {
    **streamable_headers,
    "MCP-Session-Id": session_id,
}
notification_status, _, notification_body = request(
    "POST",
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    headers=session_headers,
    accept="application/json, text/event-stream",
)
if notification_status < 200 or notification_status >= 300:
    raise AssertionError(
        f"Installed CLI MCP initialized notification returned {notification_status}"
    )
if notification_body.strip():
    notification_payload = json_payload(notification_body)
    if isinstance(notification_payload, dict) and "error" in notification_payload:
        raise AssertionError(
            "Installed CLI MCP initialized notification returned "
            f"{notification_payload['error']}"
        )
_, list_headers, streamable_tools = post_json(
    {"jsonrpc": "2.0", "id": "tools", "method": "tools/list"},
    headers=session_headers,
    accept="application/json",
)
response_session_id = list_headers.get("mcp-session-id")
if response_session_id is not None and response_session_id != session_id:
    raise AssertionError("Installed CLI MCP Streamable tools/list changed session id")
streamable_tool_names = {
    tool.get("name") for tool in streamable_tools["result"]["tools"]
}
if "connectanum.api.list" not in streamable_tool_names:
    raise AssertionError("Installed CLI MCP Streamable tools/list missed meta tool")
if "connectanum.api.describe" not in streamable_tool_names:
    raise AssertionError(
        "Installed CLI MCP Streamable tools/list missed describe tool"
    )
if "connectanum.pubsub.publish" not in streamable_tool_names:
    raise AssertionError("Installed CLI MCP Streamable tools/list missed pubsub tool")
_, _, streamable_topic_description = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-streamable-topic-describe",
        "method": "tools/call",
        "params": {
            "name": "connectanum.api.describe",
            "arguments": {"kind": "topic", "uri": "cli.smoke.events"},
        },
    },
    headers=session_headers,
    accept="application/json",
)
streamable_topic_content = structured_content(
    streamable_topic_description,
    label="Installed CLI MCP Streamable topic describe",
)
if "CLI Smoke Events" not in json.dumps(streamable_topic_content):
    raise AssertionError(
        "Installed CLI MCP Streamable topic describe missed public metadata"
    )
_, _, streamable_procedure_description = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-streamable-procedure-describe",
        "method": "tools/call",
        "params": {
            "name": "connectanum.api.describe",
            "arguments": {"kind": "procedure", "uri": "cli.smoke.lookup"},
        },
    },
    headers=session_headers,
    accept="application/json",
)
streamable_procedure_content = structured_content(
    streamable_procedure_description,
    label="Installed CLI MCP Streamable procedure describe",
)
if "CLI Lookup" not in json.dumps(streamable_procedure_content):
    raise AssertionError(
        "Installed CLI MCP Streamable procedure describe missed public metadata"
    )
_, _, streamable_publish = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-streamable-pubsub-publish",
        "method": "tools/call",
        "params": {
            "name": "connectanum.pubsub.publish",
            "arguments": {
                "topic": "cli.smoke.events",
                "argumentsKeywords": {"via": "public-streamable-publish"},
                "acknowledge": True,
            },
        },
    },
    headers=session_headers,
    accept="application/json",
)
streamable_publication = structured_content(
    streamable_publish,
    label="Installed CLI MCP Streamable pubsub publish",
)
if (
    streamable_publication.get("topic") != "cli.smoke.events"
    or streamable_publication.get("acknowledged") is not True
):
    raise AssertionError(
        "Installed CLI MCP Streamable pubsub publish was invalid: "
        f"{streamable_publication}"
    )
streamable_events = poll_direct_pubsub_events(
    direct_handle,
    endpoint=endpoint,
    id_prefix="public-streamable-pubsub",
    label="Installed CLI MCP Streamable pubsub",
    marker="public-streamable-publish",
)
if "public-streamable-publish" not in json.dumps(streamable_events):
    raise AssertionError(
        "Installed CLI MCP direct pubsub poll missed public Streamable event"
    )
_, _, direct_unsubscribe = post_json(
    {
        "jsonrpc": "2.0",
        "id": "public-direct-pubsub-unsubscribe",
        "method": "connectanum.pubsub.unsubscribe",
        "params": {"handle": direct_handle},
    }
)
direct_unsubscribe_content = structured_content(
    direct_unsubscribe,
    label="Installed CLI MCP direct pubsub unsubscribe",
)
if direct_unsubscribe_content.get("unsubscribed") is not True:
    raise AssertionError(
        "Installed CLI MCP direct pubsub unsubscribe was invalid: "
        f"{direct_unsubscribe_content}"
    )

delete_status, delete_headers, _ = request(
    "DELETE", headers=session_headers, accept="application/json, text/event-stream"
)
if delete_status < 200 or delete_status >= 300:
    raise AssertionError(f"Installed CLI MCP DELETE returned {delete_status}")
if delete_headers.get("mcp-session-id") != session_id:
    raise AssertionError("Installed CLI MCP DELETE missed session id")

expect_secure_rejection(
    {"jsonrpc": "2.0", "id": "secure-missing", "method": "tools/list"},
    label="missing bearer credentials",
)
expect_secure_rejection(
    {"jsonrpc": "2.0", "id": "secure-json-missing", "method": "tools/list"},
    endpoint=secure_json_endpoint,
    label="missing bearer credentials on JSON-response route",
)
expect_secure_rejection(
    {"jsonrpc": "2.0", "id": "secure-unknown", "method": "tools/list"},
    headers={"Authorization": "Bearer not-a-valid-token"},
    label="unknown bearer credentials",
)
expect_secure_rejection(
    {"jsonrpc": "2.0", "id": "secure-json-unknown", "method": "tools/list"},
    endpoint=secure_json_endpoint,
    headers={"Authorization": "Bearer not-a-valid-token"},
    label="unknown bearer credentials on JSON-response route",
)

auth_status, _, challenge = post_auth(
    {
        "realm": "cli.smoke",
        "authmethod": "ticket",
        "authid": auth_id,
    },
    allow_error=True,
)
if auth_status != 401:
    raise AssertionError(f"Installed CLI auth start returned {auth_status}")
state = challenge.get("state") if isinstance(challenge, dict) else None
if not state:
    raise AssertionError("Installed CLI auth challenge missed state")
_, _, grant = post_auth(
    {
        "state": state,
        "signature": ticket,
        "extra": {},
    }
)
access_token = grant.get("access_token") if isinstance(grant, dict) else None
token_type = grant.get("token_type") if isinstance(grant, dict) else None
if not access_token or str(token_type).lower() != "bearer":
    raise AssertionError(f"Installed CLI auth grant was invalid: {grant}")
if grant.get("authid") != auth_id or grant.get("authrole") != "member":
    raise AssertionError(f"Installed CLI auth grant identity mismatch: {grant}")

bearer_headers = {"Authorization": f"Bearer {access_token}"}
_, _, secure_tools = post_json(
    {"jsonrpc": "2.0", "id": "secure-tools", "method": "tools/list"},
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
secure_tool_names = {tool.get("name") for tool in secure_tools["result"]["tools"]}
if "connectanum.api.list" not in secure_tool_names:
    raise AssertionError("Installed CLI protected MCP tools/list missed meta tool")
_, _, secure_resources = post_json(
    {"jsonrpc": "2.0", "id": "secure-resources", "method": "resources/list"},
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
secure_resource_uris = {
    resource.get("uri") for resource in secure_resources["result"]["resources"]
}
if "cli://mcp/secure/context" not in secure_resource_uris:
    raise AssertionError("Installed CLI protected MCP missed secure resource")
_, _, secure_resource = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-resource-read",
        "method": "resources/read",
        "params": {"uri": "cli://mcp/secure/context"},
    },
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
if "Router CLI secure MCP context." not in json.dumps(
    secure_resource["result"]["contents"]
):
    raise AssertionError(
        "Installed CLI protected MCP resources/read missed secure context"
    )
_, _, secure_templates = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-resource-templates",
        "method": "resources/templates/list",
    },
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
secure_template_uris = {
    template.get("uriTemplate")
    for template in secure_templates["result"]["resourceTemplates"]
}
if "cli://mcp/secure/task/{taskId}" not in secure_template_uris:
    raise AssertionError(
        "Installed CLI protected MCP missed secure resource template"
    )
_, _, secure_prompts = post_json(
    {"jsonrpc": "2.0", "id": "secure-prompts", "method": "prompts/list"},
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
secure_prompt_names = {
    prompt.get("name") for prompt in secure_prompts["result"]["prompts"]
}
if "summarize-secure-cli-context" not in secure_prompt_names:
    raise AssertionError("Installed CLI protected MCP missed secure prompt")
_, _, secure_prompt = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-prompt-get",
        "method": "prompts/get",
        "params": {
            "name": "summarize-secure-cli-context",
            "arguments": {"topic": "protected consumer readiness"},
        },
    },
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
if "protected consumer readiness" not in json.dumps(
    secure_prompt["result"]["messages"]
):
    raise AssertionError(
        "Installed CLI protected MCP prompts/get missed secure substitution"
    )
_, _, secure_procedures = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-procedures",
        "method": "connectanum.api.list",
        "params": {"kind": "procedure"},
    },
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
if "cli.smoke.secure.lookup" not in json.dumps(secure_procedures["result"]):
    raise AssertionError(
        "Installed CLI protected MCP missed secure procedure"
    )
_, _, secure_procedure_description = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-procedure-describe",
        "method": "connectanum.api.describe",
        "params": {
            "kind": "procedure",
            "uri": "cli.smoke.secure.lookup",
        },
    },
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
if "CLI Secure Lookup" not in json.dumps(
    secure_procedure_description["result"]
):
    raise AssertionError(
        "Installed CLI protected MCP direct procedure describe "
        "missed secure metadata"
    )
_, _, secure_topics = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-topics",
        "method": "connectanum.api.list",
        "params": {"kind": "topic"},
    },
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
if "cli.smoke.secure.events" not in json.dumps(secure_topics["result"]):
    raise AssertionError("Installed CLI protected MCP missed secure topic")
_, _, secure_topic_description = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-topic-describe",
        "method": "connectanum.api.describe",
        "params": {"kind": "topic", "uri": "cli.smoke.secure.events"},
    },
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
if "CLI Secure Smoke Events" not in json.dumps(
    secure_topic_description["result"]
):
    raise AssertionError(
        "Installed CLI protected MCP direct topic describe missed secure metadata"
    )
_, _, secure_direct_subscribe = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-direct-pubsub-subscribe",
        "method": "connectanum.pubsub.subscribe",
        "params": {"topic": "cli.smoke.secure.events", "queueLimit": 5},
    },
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
secure_direct_subscription = structured_content(
    secure_direct_subscribe,
    label="Installed CLI protected MCP direct pubsub subscribe",
)
secure_direct_handle = secure_direct_subscription.get("handle")
if (
    not isinstance(secure_direct_handle, str)
    or not secure_direct_handle
    or secure_direct_subscription.get("topic") != "cli.smoke.secure.events"
):
    raise AssertionError(
        "Installed CLI protected MCP direct pubsub subscribe was invalid: "
        f"{secure_direct_subscription}"
    )

secure_streamable_headers = {
    **streamable_headers,
    **bearer_headers,
}
_, secure_initialize_headers, secure_initialize = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-initialize",
        "method": "initialize",
        "params": {
            "protocolVersion": protocol_version,
            "capabilities": {},
            "clientInfo": {
                "name": "router-cli-consumer-smoke-secure",
                "version": "0.0.0",
            },
        },
    },
    endpoint=secure_endpoint,
    headers=secure_streamable_headers,
    accept="application/json, text/event-stream",
)
secure_session_id = secure_initialize_headers.get("mcp-session-id")
if not secure_session_id:
    raise AssertionError("Installed CLI protected MCP initialize missed session id")
if secure_initialize["result"]["protocolVersion"] != protocol_version:
    raise AssertionError("Installed CLI protected MCP initialize changed protocol")

secure_session_headers = {
    **secure_streamable_headers,
    "MCP-Session-Id": secure_session_id,
}
secure_notification_status, _, secure_notification_body = request(
    "POST",
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    endpoint=secure_endpoint,
    headers=secure_session_headers,
    accept="application/json, text/event-stream",
)
if secure_notification_status < 200 or secure_notification_status >= 300:
    raise AssertionError(
        "Installed CLI protected MCP initialized notification returned "
        f"{secure_notification_status}"
    )
if secure_notification_body.strip():
    secure_notification_payload = json_payload(secure_notification_body)
    if (
        isinstance(secure_notification_payload, dict)
        and "error" in secure_notification_payload
    ):
        raise AssertionError(
            "Installed CLI protected MCP initialized notification returned "
            f"{secure_notification_payload['error']}"
        )
_, secure_list_headers, secure_streamable_tools = post_json(
    {"jsonrpc": "2.0", "id": "secure-streamable-tools", "method": "tools/list"},
    endpoint=secure_endpoint,
    headers=secure_session_headers,
    accept="application/json",
)
secure_response_session_id = secure_list_headers.get("mcp-session-id")
if (
    secure_response_session_id is not None
    and secure_response_session_id != secure_session_id
):
    raise AssertionError(
        "Installed CLI protected MCP tools/list changed session id"
    )
secure_streamable_tool_names = {
    tool.get("name") for tool in secure_streamable_tools["result"]["tools"]
}
if "connectanum.api.describe" not in secure_streamable_tool_names:
    raise AssertionError(
        "Installed CLI protected MCP Streamable tools/list missed describe tool"
    )
if "connectanum.pubsub.publish" not in secure_streamable_tool_names:
    raise AssertionError(
        "Installed CLI protected MCP Streamable tools/list missed pubsub tool"
    )
_, _, secure_streamable_topic_description = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-streamable-topic-describe",
        "method": "tools/call",
        "params": {
            "name": "connectanum.api.describe",
            "arguments": {
                "kind": "topic",
                "uri": "cli.smoke.secure.events",
            },
        },
    },
    endpoint=secure_endpoint,
    headers=secure_session_headers,
    accept="application/json",
)
secure_streamable_topic_content = structured_content(
    secure_streamable_topic_description,
    label="Installed CLI protected MCP Streamable topic describe",
)
if "CLI Secure Smoke Events" not in json.dumps(secure_streamable_topic_content):
    raise AssertionError(
        "Installed CLI protected MCP Streamable topic describe "
        "missed secure metadata"
    )
_, _, secure_streamable_procedure_description = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-streamable-procedure-describe",
        "method": "tools/call",
        "params": {
            "name": "connectanum.api.describe",
            "arguments": {
                "kind": "procedure",
                "uri": "cli.smoke.secure.lookup",
            },
        },
    },
    endpoint=secure_endpoint,
    headers=secure_session_headers,
    accept="application/json",
)
secure_streamable_procedure_content = structured_content(
    secure_streamable_procedure_description,
    label="Installed CLI protected MCP Streamable procedure describe",
)
if "CLI Secure Lookup" not in json.dumps(secure_streamable_procedure_content):
    raise AssertionError(
        "Installed CLI protected MCP Streamable procedure describe "
        "missed secure metadata"
    )
_, _, secure_streamable_publish = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-streamable-pubsub-publish",
        "method": "tools/call",
        "params": {
            "name": "connectanum.pubsub.publish",
            "arguments": {
                "topic": "cli.smoke.secure.events",
                "argumentsKeywords": {"via": "secure-streamable-publish"},
                "acknowledge": True,
            },
        },
    },
    endpoint=secure_endpoint,
    headers=secure_session_headers,
    accept="application/json",
)
secure_publish_content = structured_content(
    secure_streamable_publish,
    label="Installed CLI protected MCP Streamable pubsub publish",
)
if (
    secure_publish_content.get("topic") != "cli.smoke.secure.events"
    or secure_publish_content.get("acknowledged") is not True
):
    raise AssertionError(
        "Installed CLI protected MCP Streamable pubsub publish was invalid: "
        f"{secure_publish_content}"
    )
secure_direct_events = poll_direct_pubsub_events(
    secure_direct_handle,
    endpoint=secure_endpoint,
    headers=bearer_headers,
    id_prefix="secure-direct-pubsub",
    label="Installed CLI protected MCP direct pubsub",
    marker="secure-streamable-publish",
)
if "secure-streamable-publish" not in json.dumps(secure_direct_events):
    raise AssertionError(
        "Installed CLI protected MCP direct pubsub poll missed streamable event"
    )
_, _, secure_direct_unsubscribe = post_json(
    {
        "jsonrpc": "2.0",
        "id": "secure-direct-pubsub-unsubscribe",
        "method": "connectanum.pubsub.unsubscribe",
        "params": {"handle": secure_direct_handle},
    },
    endpoint=secure_endpoint,
    headers=bearer_headers,
)
secure_unsubscribe_content = structured_content(
    secure_direct_unsubscribe,
    label="Installed CLI protected MCP direct pubsub unsubscribe",
)
if secure_unsubscribe_content.get("unsubscribed") is not True:
    raise AssertionError(
        "Installed CLI protected MCP direct pubsub unsubscribe was invalid: "
        f"{secure_unsubscribe_content}"
    )
secure_delete_status, secure_delete_headers, _ = request(
    "DELETE",
    endpoint=secure_endpoint,
    headers=secure_session_headers,
    accept="application/json, text/event-stream",
)
if secure_delete_status < 200 or secure_delete_status >= 300:
    raise AssertionError(
        f"Installed CLI protected MCP DELETE returned {secure_delete_status}"
    )
if secure_delete_headers.get("mcp-session-id") != secure_session_id:
    raise AssertionError("Installed CLI protected MCP DELETE missed session id")
PY
  mkdir -p "$smoke_dir/dart-consumer/bin"
  cat >"$smoke_dir/dart-consumer/pubspec.yaml" <<EOF
name: connectanum_router_cli_mcp_client_smoke
publish_to: none
environment:
  sdk: '^3.9.2'
hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_SKIP_NATIVE_BUILD: true
dependencies:
  connectanum_mcp: any
dependency_overrides:
  connectanum_core:
    path: "$ROOT_DIR/packages/connectanum_core"
  connectanum_client:
    path: "$ROOT_DIR/packages/connectanum_client"
  connectanum_mcp:
    path: "$ROOT_DIR/packages/connectanum_mcp"
EOF

  cat >"$smoke_dir/dart-consumer/bin/main.dart" <<'DART'
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';

const _protocolVersion = McpStreamableHttpClient.latestProtocolVersion;
const _publicTopic = 'cli.smoke.events';
const _secureTopic = 'cli.smoke.secure.events';
const _configuredOnlySecureTopic = 'cli.smoke.secure.metadata';
const _secureProcedure = 'cli.smoke.secure.lookup';

Future<void> main() async {
  final port = Platform.environment['MCP_PORT'] ?? '';
  _expect(port.isNotEmpty, 'MCP_PORT must be set.');

  final baseUri = Uri.parse('http://127.0.0.1:$port');
  final publicEndpoint = baseUri.resolve('/mcp');
  final secureEndpoint = baseUri.resolve('/mcp/secure');
  final secureJsonEndpoint = baseUri.resolve('/mcp/secure-json-post');
  final authEndpoint = baseUri.resolve('/auth');
  final proxyEndpoint = baseUri.resolve('/proxy/healthz');
  final publicClient = McpStreamableHttpClient(publicEndpoint);
  final authClient = ConnectanumHttpAuthClient(authEndpoint);
  McpStreamableHttpClient? secureClient;
  McpStreamableHttpClient? secureJsonClient;

  try {
    await _expectSessionProxyRoute(endpoint: proxyEndpoint);

    final publicTools = await publicClient.listToolsDirect(
      id: 'dart-consumer-public-tools',
    );
    _expect(
      _stringFields(publicTools.tools, 'name').contains('connectanum.api.list'),
      'Dart consumer missed public direct JSON meta tool.',
    );

    final publicResources = await publicClient.listResourcesDirect(
      id: 'dart-consumer-public-resources',
    );
    _expect(
      _stringFields(
        publicResources.resources,
        'uri',
      ).contains('cli://mcp/context'),
      'Dart consumer missed public direct JSON resource.',
    );

    final publicResourceContents = await publicClient.readResourceDirect(
      'cli://mcp/context',
      id: 'dart-consumer-public-resource-read',
    );
    _expect(
      jsonEncode(publicResourceContents).contains('Router CLI MCP context.'),
      'Dart consumer public direct JSON resource read missed content.',
    );

    final publicResourceTemplates =
        await publicClient.listResourceTemplatesDirect(
      id: 'dart-consumer-public-resource-templates',
    );
    _expect(
      _stringFields(
        publicResourceTemplates.resourceTemplates,
        'uriTemplate',
      ).contains('cli://mcp/task/{taskId}'),
      'Dart consumer missed public direct JSON resource template.',
    );

    final publicPrompts = await publicClient.listPromptsDirect(
      id: 'dart-consumer-public-prompts',
    );
    _expect(
      _stringFields(
        publicPrompts.prompts,
        'name',
      ).contains('summarize-cli-context'),
      'Dart consumer missed public direct JSON prompt.',
    );

    final publicPrompt = await publicClient.getPromptDirect(
      'summarize-cli-context',
      id: 'dart-consumer-public-prompt-get',
      arguments: const <String, String>{
        'topic': 'Dart consumer readiness',
      },
    );
    _expect(
      jsonEncode(publicPrompt).contains('Dart consumer readiness'),
      'Dart consumer public direct JSON prompt get missed substitution.',
    );

    final publicDirectBatch = await publicClient.postBatchDirect(
      <McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-public-direct-batch-resource-read',
          'method': 'resources/read',
          'params': <String, Object?>{'uri': 'cli://mcp/context'},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-public-direct-batch-prompt-get',
          'method': 'prompts/get',
          'params': <String, Object?>{
            'name': 'summarize-cli-context',
            'arguments': <String, Object?>{
              'topic': 'Dart direct batch consumer readiness',
            },
          },
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-public-direct-batch-bad-method',
          'method': 'tools/unknown',
          'params': <String, Object?>{},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-public-direct-batch-resource-templates',
          'method': 'resources/templates/list',
          'params': <String, Object?>{},
        },
      ],
    );
    _expect(
      publicDirectBatch?.length == 4,
      'Dart consumer public direct JSON batch response count changed.',
    );
    final publicDirectBatchResource = _batchResult(
      publicDirectBatch,
      'dart-consumer-public-direct-batch-resource-read',
      'Dart consumer public direct JSON batch resource read',
    );
    _expect(
      jsonEncode(
        publicDirectBatchResource,
      ).contains('Router CLI MCP context.'),
      'Dart consumer public direct JSON batch resource missed content.',
    );
    final publicDirectBatchPrompt = _batchResult(
      publicDirectBatch,
      'dart-consumer-public-direct-batch-prompt-get',
      'Dart consumer public direct JSON batch prompt get',
    );
    _expect(
      jsonEncode(
        publicDirectBatchPrompt,
      ).contains('Dart direct batch consumer readiness'),
      'Dart consumer public direct JSON batch prompt missed substitution.',
    );
    final publicDirectBatchError = _batchError(
      publicDirectBatch,
      'dart-consumer-public-direct-batch-bad-method',
      'Dart consumer public direct JSON batch bad method',
    );
    _expect(
      publicDirectBatchError['code'] == McpErrorCodes.methodNotFound,
      'Dart consumer public direct JSON batch missed method error isolation.',
    );
    final publicDirectBatchTemplates = _batchResult(
      publicDirectBatch,
      'dart-consumer-public-direct-batch-resource-templates',
      'Dart consumer public direct JSON batch resource templates',
    );
    _expect(
      jsonEncode(
        publicDirectBatchTemplates,
      ).contains('cli://mcp/task/{taskId}'),
      'Dart consumer public direct JSON batch templates missed template.',
    );
    _expect(
      publicClient.sessionId == null && publicClient.lastEventId == null,
      'Dart consumer public direct JSON batch changed Streamable state.',
    );

    final publicInitialize = await publicClient.initialize(
      id: 'dart-consumer-public-initialize',
      protocolVersion: _protocolVersion,
      clientInfo: const <String, Object?>{
        'name': 'router-cli-dart-consumer-smoke',
        'version': '0.0.0',
      },
    );
    _expect(
      _resultFrom(publicInitialize, 'public initialize')['protocolVersion'] ==
          _protocolVersion,
      'Dart consumer public Streamable initialize changed protocol.',
    );
    await publicClient.notifyInitialized();

    final publicStreamableContents = await publicClient.readResource(
      'cli://mcp/context',
      id: 'dart-consumer-public-streamable-resource-read',
    );
    _expect(
      jsonEncode(publicStreamableContents).contains('Router CLI MCP context.'),
      'Dart consumer public Streamable resource read missed content.',
    );

    final publicStreamablePrompt = await publicClient.getPrompt(
      'summarize-cli-context',
      id: 'dart-consumer-public-streamable-prompt-get',
      arguments: const <String, String>{
        'topic': 'Dart Streamable consumer readiness',
      },
    );
    _expect(
      jsonEncode(publicStreamablePrompt).contains(
        'Dart Streamable consumer readiness',
      ),
      'Dart consumer public Streamable prompt get missed substitution.',
    );

    final publicBatchSessionId = publicClient.sessionId;
    final publicBatchLastEventId = publicClient.lastEventId;
    final publicStreamableBatch = await publicClient.postBatch(
      <McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-public-streamable-batch-resource-read',
          'method': 'resources/read',
          'params': <String, Object?>{'uri': 'cli://mcp/context'},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-public-streamable-batch-prompt-get',
          'method': 'prompts/get',
          'params': <String, Object?>{
            'name': 'summarize-cli-context',
            'arguments': <String, Object?>{
              'topic': 'Dart Streamable batch consumer readiness',
            },
          },
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-public-streamable-batch-bad-method',
          'method': 'tools/unknown',
          'params': <String, Object?>{},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
          'params': <String, Object?>{},
        },
      ],
    );
    _expect(
      publicStreamableBatch?.length == 3,
      'Dart consumer public Streamable batch response count changed.',
    );
    final publicStreamableBatchResource = _batchResult(
      publicStreamableBatch,
      'dart-consumer-public-streamable-batch-resource-read',
      'Dart consumer public Streamable batch resource read',
    );
    _expect(
      jsonEncode(
        publicStreamableBatchResource,
      ).contains('Router CLI MCP context.'),
      'Dart consumer public Streamable batch resource missed content.',
    );
    final publicStreamableBatchPrompt = _batchResult(
      publicStreamableBatch,
      'dart-consumer-public-streamable-batch-prompt-get',
      'Dart consumer public Streamable batch prompt get',
    );
    _expect(
      jsonEncode(
        publicStreamableBatchPrompt,
      ).contains('Dart Streamable batch consumer readiness'),
      'Dart consumer public Streamable batch prompt missed substitution.',
    );
    final publicStreamableBatchError = _batchError(
      publicStreamableBatch,
      'dart-consumer-public-streamable-batch-bad-method',
      'Dart consumer public Streamable batch bad method',
    );
    _expect(
      publicStreamableBatchError['code'] == McpErrorCodes.methodNotFound,
      'Dart consumer public Streamable batch missed method error isolation.',
    );
    _expect(
      publicClient.sessionId == publicBatchSessionId,
      'Dart consumer public Streamable batch changed session id.',
    );
    final publicBatchNextEventId = publicClient.lastEventId;
    _expect(
      publicBatchSessionId != null &&
          publicBatchNextEventId != null &&
          publicBatchNextEventId != publicBatchLastEventId &&
          publicBatchNextEventId.startsWith('$publicBatchSessionId:'),
      'Dart consumer public Streamable batch did not advance SSE state.',
    );
    await _expectInvalidLastEventIdRejectedWithoutSessionLoss(
      publicClient,
      sessionId: publicBatchSessionId as String,
      eventId: publicBatchNextEventId as String,
      label: 'Dart consumer public Streamable invalid Last-Event-ID',
    );
    await _expectEmptyLastEventIdStartsFreshPoll(
      publicClient,
      sessionId: publicBatchSessionId,
      eventId: publicClient.lastEventId,
      label: 'Dart consumer public Streamable empty Last-Event-ID',
    );

    final publicStreamableTools = await publicClient.listTools(
      id: 'dart-consumer-public-streamable-tools',
    );
    _expect(
      _stringFields(
        publicStreamableTools.tools,
        'name',
      ).contains('connectanum.api.list'),
      'Dart consumer missed public Streamable meta tool.',
    );
    final publicActiveDirectSessionId = publicClient.sessionId;
    final publicActiveDirectLastEventId = publicClient.lastEventId;
    final publicActiveDirectSubscription =
        await publicClient.subscribeWampTopicDirect(
      _publicTopic,
      id: 'dart-consumer-public-active-direct-subscribe',
      queueLimit: 5,
    );
    _expect(
      publicActiveDirectSubscription.topic == _publicTopic &&
          publicActiveDirectSubscription.handle.isNotEmpty,
      'Dart consumer public active direct JSON subscription was invalid.',
    );
    await _expectNotificationPubSub(
      publicClient,
      publicActiveDirectSubscription.handle,
      topic: _publicTopic,
      marker: 'dart-consumer-public-active-direct-notification',
      idPrefix: 'dart-consumer-public-active-direct-notification-poll',
      label: 'Dart consumer public active direct JSON pub/sub',
      directJson: true,
    );
    final publicActiveDirectUnsubscribe =
        await publicClient.unsubscribeWampTopicDirect(
      publicActiveDirectSubscription.handle,
      id: 'dart-consumer-public-active-direct-unsubscribe',
    );
    _expect(
      publicActiveDirectUnsubscribe.unsubscribed,
      'Dart consumer public active direct JSON unsubscribe was invalid.',
    );
    _expect(
      publicClient.sessionId == publicActiveDirectSessionId &&
          publicClient.lastEventId == publicActiveDirectLastEventId,
      'Dart consumer public active direct JSON pub/sub changed Streamable state.',
    );
    await _expectRawDirectJsonStaleSessionIgnored(
      publicEndpoint,
      publicClient,
      id: 'dart-consumer-public-direct-json-stale-session',
      label: 'Dart consumer public direct JSON stale MCP-Session-Id',
    );
    await publicClient.deleteSession();
    _expect(
      publicClient.sessionId == null && publicClient.lastEventId == null,
      'Dart consumer public Streamable delete leaked state.',
    );

    final grant = await authClient.issueTicketToken(
      realm: 'cli.smoke',
      authId: 'cli-user',
      ticket: 'cli-ticket',
    );
    _expect(grant.accessToken.isNotEmpty, 'Dart consumer auth grant was empty.');
    _expect(grant.tokenType == 'Bearer', 'Dart consumer auth grant was not Bearer.');
    _expect(grant.realm == 'cli.smoke', 'Dart consumer auth grant realm changed.');
    _expect(grant.authId == 'cli-user', 'Dart consumer auth grant authid changed.');
    _expect(
      grant.authRole == 'member',
      'Dart consumer auth grant authrole changed.',
    );
    _expect(
      grant.authMethod == 'ticket',
      'Dart consumer auth grant authmethod changed.',
    );
    _expect(
      grant.authProvider == 'cli-ticket-db',
      'Dart consumer auth grant authprovider changed.',
    );
    final originalRefreshToken = grant.refreshToken;
    if (originalRefreshToken == null || originalRefreshToken.isEmpty) {
      throw StateError('Dart consumer auth grant missed a refresh token.');
    }

    final unauthenticatedSecureJsonClient =
        McpStreamableHttpClient(secureJsonEndpoint);
    try {
      await _expectMcpHttpRejected(
        () => unauthenticatedSecureJsonClient.listToolsDirect(
          id: 'dart-consumer-secure-json-missing-tools',
        ),
        HttpStatus.unauthorized,
        'Dart consumer protected JSON-response route without bearer',
      );
      _expect(
        unauthenticatedSecureJsonClient.sessionId == null &&
            unauthenticatedSecureJsonClient.lastEventId == null,
        'Dart consumer protected JSON-response rejection captured state.',
      );
    } finally {
      unauthenticatedSecureJsonClient.close(force: true);
    }

    secureJsonClient = McpStreamableHttpClient.withAuthGrant(
      secureJsonEndpoint,
      grant,
    );
    final secureJsonTools = await secureJsonClient.listToolsDirect(
      id: 'dart-consumer-secure-json-tools',
    );
    _expect(
      _stringFields(
        secureJsonTools.tools,
        'name',
      ).contains('connectanum.pubsub.publish'),
      'Dart consumer missed protected JSON-response direct tools.',
    );

    final secureJsonResourceContents =
        await secureJsonClient.readResourceDirect(
      'cli://mcp/secure/context',
      id: 'dart-consumer-secure-json-resource-read',
    );
    _expect(
      jsonEncode(
        secureJsonResourceContents,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected JSON-response resource read missed content.',
    );

    final secureJsonDirectBatch = await secureJsonClient.postBatchDirect(
      <McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-json-direct-batch-resource-read',
          'method': 'resources/read',
          'params': <String, Object?>{'uri': 'cli://mcp/secure/context'},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-json-direct-batch-bad-method',
          'method': 'tools/unknown',
          'params': <String, Object?>{},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-json-direct-batch-api-list',
          'method': 'connectanum.api.list',
          'params': <String, Object?>{'kind': 'topic'},
        },
      ],
    );
    _expect(
      secureJsonDirectBatch?.length == 3,
      'Dart consumer protected JSON-response direct batch count changed.',
    );
    final secureJsonDirectBatchResource = _batchResult(
      secureJsonDirectBatch,
      'dart-consumer-secure-json-direct-batch-resource-read',
      'Dart consumer protected JSON-response direct batch resource read',
    );
    _expect(
      jsonEncode(
        secureJsonDirectBatchResource,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected JSON-response direct batch missed content.',
    );
    final secureJsonDirectBatchError = _batchError(
      secureJsonDirectBatch,
      'dart-consumer-secure-json-direct-batch-bad-method',
      'Dart consumer protected JSON-response direct batch bad method',
    );
    _expect(
      secureJsonDirectBatchError['code'] == McpErrorCodes.methodNotFound,
      'Dart consumer protected JSON-response direct batch missed error isolation.',
    );
    final secureJsonDirectBatchApi = _batchResult(
      secureJsonDirectBatch,
      'dart-consumer-secure-json-direct-batch-api-list',
      'Dart consumer protected JSON-response direct batch API list',
    );
    _expect(
      jsonEncode(secureJsonDirectBatchApi).contains(_secureTopic),
      'Dart consumer protected JSON-response direct batch missed topic API.',
    );

    final secureJsonDirectSubscription =
        await secureJsonClient.subscribeWampTopicDirect(
      _secureTopic,
      id: 'dart-consumer-secure-json-direct-subscribe',
      queueLimit: 5,
    );
    _expect(
      secureJsonDirectSubscription.topic == _secureTopic &&
          secureJsonDirectSubscription.handle.isNotEmpty,
      'Dart consumer protected JSON-response direct subscription was invalid.',
    );
    final secureJsonDirectPublication =
        await secureJsonClient.publishWampEventDirect(
      _secureTopic,
      id: 'dart-consumer-secure-json-direct-publish',
      argumentsKeywords: const <String, Object?>{
        'via': 'dart-consumer-secure-json-direct',
      },
      acknowledge: true,
    );
    _expect(
      secureJsonDirectPublication.topic == _secureTopic &&
          secureJsonDirectPublication.acknowledged,
      'Dart consumer protected JSON-response direct publish was invalid.',
    );
    final secureJsonDirectEvents = await _pollUntilEvent(
      secureJsonClient,
      secureJsonDirectSubscription.handle,
      marker: 'dart-consumer-secure-json-direct',
      idPrefix: 'dart-consumer-secure-json-direct-poll',
    );
    _expect(
      jsonEncode(
        secureJsonDirectEvents.events,
      ).contains('dart-consumer-secure-json-direct'),
      'Dart consumer protected JSON-response direct poll missed event.',
    );
    final secureJsonDirectUnsubscribe =
        await secureJsonClient.unsubscribeWampTopicDirect(
      secureJsonDirectSubscription.handle,
      id: 'dart-consumer-secure-json-direct-unsubscribe',
    );
    _expect(
      secureJsonDirectUnsubscribe.unsubscribed,
      'Dart consumer protected JSON-response direct unsubscribe was invalid.',
    );
    _expect(
      secureJsonClient.sessionId == null && secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response direct access captured state.',
    );

    final secureJsonInitialize = await secureJsonClient.initialize(
      id: 'dart-consumer-secure-json-initialize',
      protocolVersion: _protocolVersion,
      clientInfo: const <String, Object?>{
        'name': 'router-cli-dart-consumer-smoke-secure-json',
        'version': '0.0.0',
      },
    );
    _expect(
      _resultFrom(
        secureJsonInitialize,
        'secure JSON-response initialize',
      )['protocolVersion'] == _protocolVersion,
      'Dart consumer protected JSON-response initialize changed protocol.',
    );
    final secureJsonSessionId = secureJsonClient.sessionId;
    _expect(
      secureJsonSessionId != null && secureJsonSessionId.isNotEmpty,
      'Dart consumer protected JSON-response route missed session id.',
    );
    _expect(
      secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response initialize captured SSE cursor.',
    );
    await secureJsonClient.notifyInitialized();
    _expect(
      secureJsonClient.sessionId == secureJsonSessionId &&
          secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response initialized state changed.',
    );

    final activeMissingBearerSecureJsonClient =
        McpStreamableHttpClient(secureJsonEndpoint);
    try {
      await _expectMcpHttpRejected(
        () => activeMissingBearerSecureJsonClient.listToolsDirect(
          id: 'dart-consumer-secure-json-active-missing-bearer-tools',
        ),
        HttpStatus.unauthorized,
        'Dart consumer protected JSON-response route without bearer during active session',
      );
      _expect(
        activeMissingBearerSecureJsonClient.sessionId == null &&
            activeMissingBearerSecureJsonClient.lastEventId == null,
        'Dart consumer JSON-response missing-bearer protected route captured state.',
      );
    } finally {
      activeMissingBearerSecureJsonClient.close(force: true);
    }

    final activeUnknownBearerSecureJsonClient =
        McpStreamableHttpClient.withBearerToken(
      secureJsonEndpoint,
      'not-a-valid-json-response-token',
    );
    try {
      await _expectMcpHttpRejected(
        () => activeUnknownBearerSecureJsonClient.initialize(
          id: 'dart-consumer-secure-json-active-unknown-bearer-initialize',
          protocolVersion: _protocolVersion,
          clientInfo: const <String, Object?>{
            'name':
                'router-cli-dart-consumer-smoke-secure-json-unknown-bearer',
            'version': '0.0.0',
          },
        ),
        HttpStatus.unauthorized,
        'Dart consumer protected JSON-response route with unknown bearer during active session',
      );
      _expect(
        activeUnknownBearerSecureJsonClient.sessionId == null &&
            activeUnknownBearerSecureJsonClient.lastEventId == null,
        'Dart consumer JSON-response unknown-bearer protected route captured state.',
      );
    } finally {
      activeUnknownBearerSecureJsonClient.close(force: true);
    }
    _expect(
      secureJsonClient.sessionId == secureJsonSessionId &&
          secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response auth rejection changed valid session state.',
    );

    final secureJsonActiveProcedureCatalog =
        await secureJsonClient.listWampApiDirect(
      id: 'dart-consumer-secure-json-active-direct-procedure-catalog',
      kind: 'procedure',
    );
    _expect(
      jsonEncode(secureJsonActiveProcedureCatalog).contains(_secureProcedure),
      'Dart consumer protected JSON-response active direct JSON procedure catalog missed metadata.',
    );

    final secureJsonActiveProcedureDescription =
        await secureJsonClient.describeWampApiDirect(
      _secureProcedure,
      id: 'dart-consumer-secure-json-active-direct-procedure-describe',
      kind: 'procedure',
    );
    _expect(
      jsonEncode(
        secureJsonActiveProcedureDescription,
      ).contains('CLI Secure Lookup'),
      'Dart consumer protected JSON-response active direct JSON procedure describe missed metadata.',
    );

    final secureJsonActiveTopicDescription =
        await secureJsonClient.describeWampApiDirect(
      _secureTopic,
      id: 'dart-consumer-secure-json-active-direct-topic-describe',
      kind: 'topic',
    );
    _expect(
      jsonEncode(
        secureJsonActiveTopicDescription,
      ).contains('CLI Secure Smoke Events'),
      'Dart consumer protected JSON-response active direct JSON topic describe missed metadata.',
    );
    await _expectConfiguredWampRegistrationMeta(
      secureJsonClient,
      idPrefix: 'dart-consumer-secure-json-active-direct',
      label:
          'Dart consumer protected JSON-response active direct configured WAMP registration meta',
      procedure: _secureProcedure,
      directJson: true,
      expectSseCursor: false,
    );
    await _expectWampSessionMeta(
      secureJsonClient,
      idPrefix: 'dart-consumer-secure-json-active-direct',
      label:
          'Dart consumer protected JSON-response active direct WAMP session meta',
      expectedAuthId: 'cli-user',
      expectedAuthRole: 'member',
      directJson: true,
      expectSseCursor: false,
    );
    await _expectConfiguredWampSubscriptionMeta(
      secureJsonClient,
      idPrefix: 'dart-consumer-secure-json-active-direct',
      label:
          'Dart consumer protected JSON-response active direct configured WAMP subscription meta',
      topic: _configuredOnlySecureTopic,
      directJson: true,
      expectSseCursor: false,
    );

    final secureJsonActiveResources =
        await secureJsonClient.listResourcesDirect(
      id: 'dart-consumer-secure-json-active-direct-resources',
    );
    _expect(
      _stringFields(
        secureJsonActiveResources.resources,
        'uri',
      ).contains('cli://mcp/secure/context'),
      'Dart consumer protected JSON-response active direct JSON resources missed context.',
    );
    _expect(
      secureJsonActiveResources.nextCursor != null,
      'Dart consumer protected JSON-response active direct JSON resources missed cursor.',
    );
    final secureJsonActiveResourcesPage =
        await secureJsonClient.listResourcesDirect(
      id: 'dart-consumer-secure-json-active-direct-resources-page',
      cursor: secureJsonActiveResources.nextCursor,
    );
    _expect(
      _stringFields(
            secureJsonActiveResourcesPage.resources,
            'uri',
          ).contains('cli://mcp/secure/context-extra') &&
          secureJsonActiveResourcesPage.nextCursor == null,
      'Dart consumer protected JSON-response active direct JSON resources cursor page missed extra context.',
    );
    final secureJsonActiveResourceContents =
        await secureJsonClient.readResourceDirect(
      'cli://mcp/secure/context',
      id: 'dart-consumer-secure-json-active-direct-resource-read',
    );
    _expect(
      jsonEncode(
        secureJsonActiveResourceContents,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected JSON-response active direct JSON resource read missed content.',
    );

    final secureJsonActiveTemplates =
        await secureJsonClient.listResourceTemplatesDirect(
      id: 'dart-consumer-secure-json-active-direct-templates',
    );
    _expect(
      _stringFields(
        secureJsonActiveTemplates.resourceTemplates,
        'uriTemplate',
      ).contains('cli://mcp/secure/task/{taskId}'),
      'Dart consumer protected JSON-response active direct JSON templates missed secure task.',
    );
    _expect(
      secureJsonActiveTemplates.nextCursor != null,
      'Dart consumer protected JSON-response active direct JSON templates missed cursor.',
    );
    final secureJsonActiveTemplatesPage =
        await secureJsonClient.listResourceTemplatesDirect(
      id: 'dart-consumer-secure-json-active-direct-templates-page',
      cursor: secureJsonActiveTemplates.nextCursor,
    );
    _expect(
      _stringFields(
            secureJsonActiveTemplatesPage.resourceTemplates,
            'uriTemplate',
          ).contains('cli://mcp/secure/task/{taskId}/extra') &&
          secureJsonActiveTemplatesPage.nextCursor == null,
      'Dart consumer protected JSON-response active direct JSON templates cursor page missed secure extra task.',
    );

    final secureJsonActivePrompts = await secureJsonClient.listPromptsDirect(
      id: 'dart-consumer-secure-json-active-direct-prompts',
    );
    _expect(
      _stringFields(
        secureJsonActivePrompts.prompts,
        'name',
      ).contains('summarize-secure-cli-context'),
      'Dart consumer protected JSON-response active direct JSON prompts missed secure prompt.',
    );
    _expect(
      secureJsonActivePrompts.nextCursor != null,
      'Dart consumer protected JSON-response active direct JSON prompts missed cursor.',
    );
    final secureJsonActivePromptsPage =
        await secureJsonClient.listPromptsDirect(
      id: 'dart-consumer-secure-json-active-direct-prompts-page',
      cursor: secureJsonActivePrompts.nextCursor,
    );
    _expect(
      _stringFields(
            secureJsonActivePromptsPage.prompts,
            'name',
          ).contains('summarize-secure-cli-context-extra') &&
          secureJsonActivePromptsPage.nextCursor == null,
      'Dart consumer protected JSON-response active direct JSON prompts cursor page missed secure extra prompt.',
    );
    final secureJsonActivePrompt = await secureJsonClient.getPromptDirect(
      'summarize-secure-cli-context',
      id: 'dart-consumer-secure-json-active-direct-prompt-get',
      arguments: const <String, String>{
        'topic': 'active JSON-response direct prompt readiness',
      },
    );
    _expect(
      jsonEncode(
        secureJsonActivePrompt,
      ).contains('active JSON-response direct prompt readiness'),
      'Dart consumer protected JSON-response active direct JSON prompt missed substitution.',
    );
    final secureJsonActiveDirectBatch = await secureJsonClient.postBatchDirect(
      <McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-json-active-direct-batch-resource-read',
          'method': 'resources/read',
          'params': <String, Object?>{'uri': 'cli://mcp/secure/context'},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-json-active-direct-batch-bad-method',
          'method': 'tools/unknown',
          'params': <String, Object?>{},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-json-active-direct-batch-api-list',
          'method': 'connectanum.api.list',
          'params': <String, Object?>{'kind': 'topic'},
        },
      ],
    );
    _expect(
      secureJsonActiveDirectBatch?.length == 3,
      'Dart consumer protected JSON-response active direct batch count changed.',
    );
    final secureJsonActiveDirectBatchResource = _batchResult(
      secureJsonActiveDirectBatch,
      'dart-consumer-secure-json-active-direct-batch-resource-read',
      'Dart consumer protected JSON-response active direct batch resource read',
    );
    _expect(
      jsonEncode(
        secureJsonActiveDirectBatchResource,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected JSON-response active direct batch missed content.',
    );
    final secureJsonActiveDirectBatchError = _batchError(
      secureJsonActiveDirectBatch,
      'dart-consumer-secure-json-active-direct-batch-bad-method',
      'Dart consumer protected JSON-response active direct batch bad method',
    );
    _expect(
      secureJsonActiveDirectBatchError['code'] ==
          McpErrorCodes.methodNotFound,
      'Dart consumer protected JSON-response active direct batch missed error isolation.',
    );
    final secureJsonActiveDirectBatchApi = _batchResult(
      secureJsonActiveDirectBatch,
      'dart-consumer-secure-json-active-direct-batch-api-list',
      'Dart consumer protected JSON-response active direct batch API list',
    );
    _expect(
      jsonEncode(secureJsonActiveDirectBatchApi).contains(_secureTopic),
      'Dart consumer protected JSON-response active direct batch missed topic API.',
    );
    _expect(
      secureJsonClient.sessionId == secureJsonSessionId &&
          secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response active direct JSON helpers or batch changed Streamable state.',
    );
    await _expectRawDirectJsonStaleSessionIgnored(
      secureJsonEndpoint,
      secureJsonClient,
      id: 'dart-consumer-secure-json-active-direct-json-stale-session',
      label:
          'Dart consumer protected JSON-response direct JSON stale MCP-Session-Id',
      bearerToken: grant.accessToken,
    );
    final secureJsonActiveDirectNotificationSubscription =
        await secureJsonClient.subscribeWampTopicDirect(
      _secureTopic,
      id: 'dart-consumer-secure-json-active-direct-notification-subscribe',
      queueLimit: 5,
    );
    _expect(
      secureJsonActiveDirectNotificationSubscription.topic == _secureTopic &&
          secureJsonActiveDirectNotificationSubscription.handle.isNotEmpty,
      'Dart consumer protected JSON-response active direct notification subscription was invalid.',
    );
    await _expectNotificationPubSub(
      secureJsonClient,
      secureJsonActiveDirectNotificationSubscription.handle,
      topic: _secureTopic,
      marker: 'dart-consumer-secure-json-active-direct-notification',
      idPrefix: 'dart-consumer-secure-json-active-direct-notification-poll',
      label:
          'Dart consumer protected JSON-response active direct JSON pub/sub',
      directJson: true,
    );
    final secureJsonActiveDirectNotificationUnsubscribe =
        await secureJsonClient.unsubscribeWampTopicDirect(
      secureJsonActiveDirectNotificationSubscription.handle,
      id: 'dart-consumer-secure-json-active-direct-notification-unsubscribe',
    );
    _expect(
      secureJsonActiveDirectNotificationUnsubscribe.unsubscribed,
      'Dart consumer protected JSON-response active direct notification unsubscribe was invalid.',
    );
    _expect(
      secureJsonClient.sessionId == secureJsonSessionId &&
          secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response active direct notification pub/sub changed Streamable state.',
    );

    final secureJsonStreamableProcedureCatalog =
        await secureJsonClient.listWampApi(
      id: 'dart-consumer-secure-json-streamable-procedure-catalog',
      kind: 'procedure',
    );
    _expect(
      jsonEncode(secureJsonStreamableProcedureCatalog).contains(
        _secureProcedure,
      ),
      'Dart consumer protected JSON-response Streamable procedure catalog missed metadata.',
    );

    final secureJsonStreamableProcedureDescription =
        await secureJsonClient.describeWampApi(
      _secureProcedure,
      id: 'dart-consumer-secure-json-streamable-procedure-describe',
      kind: 'procedure',
    );
    _expect(
      jsonEncode(
        secureJsonStreamableProcedureDescription,
      ).contains('CLI Secure Lookup'),
      'Dart consumer protected JSON-response Streamable procedure describe missed metadata.',
    );

    final secureJsonStreamableTopicDescription =
        await secureJsonClient.describeWampApi(
      _secureTopic,
      id: 'dart-consumer-secure-json-streamable-topic-describe',
      kind: 'topic',
    );
    _expect(
      jsonEncode(
        secureJsonStreamableTopicDescription,
      ).contains('CLI Secure Smoke Events'),
      'Dart consumer protected JSON-response Streamable topic describe missed metadata.',
    );
    await _expectConfiguredWampRegistrationMeta(
      secureJsonClient,
      idPrefix: 'dart-consumer-secure-json-streamable',
      label:
          'Dart consumer protected JSON-response Streamable configured WAMP registration meta',
      procedure: _secureProcedure,
      directJson: false,
      expectSseCursor: false,
    );
    await _expectWampSessionMeta(
      secureJsonClient,
      idPrefix: 'dart-consumer-secure-json-streamable',
      label: 'Dart consumer protected JSON-response Streamable WAMP session meta',
      expectedAuthId: 'cli-user',
      expectedAuthRole: 'member',
      directJson: false,
      expectSseCursor: false,
    );
    await _expectConfiguredWampSubscriptionMeta(
      secureJsonClient,
      idPrefix: 'dart-consumer-secure-json-streamable',
      label:
          'Dart consumer protected JSON-response Streamable configured WAMP subscription meta',
      topic: _configuredOnlySecureTopic,
      directJson: false,
      expectSseCursor: false,
    );
    final secureJsonStreamableResources = await secureJsonClient.listResources(
      id: 'dart-consumer-secure-json-streamable-resources',
    );
    _expect(
      _stringFields(
        secureJsonStreamableResources.resources,
        'uri',
      ).contains('cli://mcp/secure/context'),
      'Dart consumer protected JSON-response Streamable resources missed context.',
    );
    _expect(
      secureJsonStreamableResources.nextCursor != null,
      'Dart consumer protected JSON-response Streamable resources missed cursor.',
    );
    final secureJsonStreamableResourcesPage =
        await secureJsonClient.listResources(
      id: 'dart-consumer-secure-json-streamable-resources-page',
      cursor: secureJsonStreamableResources.nextCursor,
    );
    _expect(
      _stringFields(
            secureJsonStreamableResourcesPage.resources,
            'uri',
          ).contains('cli://mcp/secure/context-extra') &&
          secureJsonStreamableResourcesPage.nextCursor == null,
      'Dart consumer protected JSON-response Streamable resources cursor page missed extra context.',
    );
    final secureJsonStreamableResourceContents =
        await secureJsonClient.readResource(
      'cli://mcp/secure/context',
      id: 'dart-consumer-secure-json-streamable-resource-read',
    );
    _expect(
      jsonEncode(
        secureJsonStreamableResourceContents,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected JSON-response Streamable resource read missed content.',
    );
    final secureJsonStreamableTemplates =
        await secureJsonClient.listResourceTemplates(
      id: 'dart-consumer-secure-json-streamable-templates',
    );
    _expect(
      _stringFields(
        secureJsonStreamableTemplates.resourceTemplates,
        'uriTemplate',
      ).contains('cli://mcp/secure/task/{taskId}'),
      'Dart consumer protected JSON-response Streamable templates missed secure task.',
    );
    _expect(
      secureJsonStreamableTemplates.nextCursor != null,
      'Dart consumer protected JSON-response Streamable templates missed cursor.',
    );
    final secureJsonStreamableTemplatesPage =
        await secureJsonClient.listResourceTemplates(
      id: 'dart-consumer-secure-json-streamable-templates-page',
      cursor: secureJsonStreamableTemplates.nextCursor,
    );
    _expect(
      _stringFields(
            secureJsonStreamableTemplatesPage.resourceTemplates,
            'uriTemplate',
          ).contains('cli://mcp/secure/task/{taskId}/extra') &&
          secureJsonStreamableTemplatesPage.nextCursor == null,
      'Dart consumer protected JSON-response Streamable templates cursor page missed secure extra task.',
    );
    final secureJsonStreamablePrompts = await secureJsonClient.listPrompts(
      id: 'dart-consumer-secure-json-streamable-prompts',
    );
    _expect(
      _stringFields(
        secureJsonStreamablePrompts.prompts,
        'name',
      ).contains('summarize-secure-cli-context'),
      'Dart consumer protected JSON-response Streamable prompts missed secure prompt.',
    );
    _expect(
      secureJsonStreamablePrompts.nextCursor != null,
      'Dart consumer protected JSON-response Streamable prompts missed cursor.',
    );
    final secureJsonStreamablePromptsPage =
        await secureJsonClient.listPrompts(
      id: 'dart-consumer-secure-json-streamable-prompts-page',
      cursor: secureJsonStreamablePrompts.nextCursor,
    );
    _expect(
      _stringFields(
            secureJsonStreamablePromptsPage.prompts,
            'name',
          ).contains('summarize-secure-cli-context-extra') &&
          secureJsonStreamablePromptsPage.nextCursor == null,
      'Dart consumer protected JSON-response Streamable prompts cursor page missed secure extra prompt.',
    );
    final secureJsonStreamablePrompt = await secureJsonClient.getPrompt(
      'summarize-secure-cli-context',
      id: 'dart-consumer-secure-json-streamable-prompt-get',
      arguments: const <String, String>{
        'topic': 'active JSON-response Streamable prompt readiness',
      },
    );
    _expect(
      jsonEncode(
        secureJsonStreamablePrompt,
      ).contains('active JSON-response Streamable prompt readiness'),
      'Dart consumer protected JSON-response Streamable prompt missed substitution.',
    );
    _expect(
      secureJsonClient.sessionId == secureJsonSessionId &&
          secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response Streamable WAMP and resource/prompt helpers changed session state.',
    );

    final secureJsonStreamableSubscription =
        await secureJsonClient.subscribeWampTopic(
      _secureTopic,
      id: 'dart-consumer-secure-json-streamable-subscribe',
      queueLimit: 5,
    );
    _expect(
      secureJsonStreamableSubscription.topic == _secureTopic &&
          secureJsonStreamableSubscription.handle.isNotEmpty,
      'Dart consumer protected JSON-response Streamable subscription was invalid.',
    );
    await _expectWampSubscriptionMeta(
      secureJsonClient,
      idPrefix: 'dart-consumer-secure-json-active-direct',
      label:
          'Dart consumer protected JSON-response active direct WAMP subscription meta',
      topic: _secureTopic,
      subscription: secureJsonStreamableSubscription,
      expectedAuthId: 'cli-user',
      expectedAuthRole: 'member',
      directJson: true,
      expectSseCursor: false,
    );
    await _expectWampSubscriptionMeta(
      secureJsonClient,
      idPrefix: 'dart-consumer-secure-json-streamable',
      label: 'Dart consumer protected JSON-response Streamable WAMP subscription meta',
      topic: _secureTopic,
      subscription: secureJsonStreamableSubscription,
      expectedAuthId: 'cli-user',
      expectedAuthRole: 'member',
      directJson: false,
      expectSseCursor: false,
    );
    final secureJsonStreamablePublication =
        await secureJsonClient.publishWampEvent(
      _secureTopic,
      id: 'dart-consumer-secure-json-streamable-publish',
      argumentsKeywords: const <String, Object?>{
        'via': 'dart-consumer-secure-json-streamable',
      },
      acknowledge: true,
    );
    _expect(
      secureJsonStreamablePublication.topic == _secureTopic &&
          secureJsonStreamablePublication.acknowledged,
      'Dart consumer protected JSON-response Streamable publish was invalid.',
    );
    final secureJsonStreamableEvents = await _pollUntilEvent(
      secureJsonClient,
      secureJsonStreamableSubscription.handle,
      marker: 'dart-consumer-secure-json-streamable',
      idPrefix: 'dart-consumer-secure-json-streamable-poll',
      directJson: false,
    );
    _expect(
      jsonEncode(
        secureJsonStreamableEvents.events,
      ).contains('dart-consumer-secure-json-streamable'),
      'Dart consumer protected JSON-response Streamable poll missed event.',
    );
    final secureJsonStreamableUnsubscribe =
        await secureJsonClient.unsubscribeWampTopic(
      secureJsonStreamableSubscription.handle,
      id: 'dart-consumer-secure-json-streamable-unsubscribe',
    );
    _expect(
      secureJsonStreamableUnsubscribe.unsubscribed,
      'Dart consumer protected JSON-response Streamable unsubscribe was invalid.',
    );
    _expect(
      secureJsonClient.sessionId == secureJsonSessionId &&
          secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response pubsub captured SSE state.',
    );

    final secureJsonStreamableBatch = await secureJsonClient.postBatch(
      <McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-json-streamable-batch-resource-read',
          'method': 'resources/read',
          'params': <String, Object?>{'uri': 'cli://mcp/secure/context'},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-json-streamable-batch-bad-method',
          'method': 'tools/unknown',
          'params': <String, Object?>{},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-json-streamable-batch-tools',
          'method': 'tools/list',
          'params': <String, Object?>{},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
          'params': <String, Object?>{},
        },
      ],
    );
    _expect(
      secureJsonStreamableBatch?.length == 3,
      'Dart consumer protected JSON-response Streamable batch count changed.',
    );
    final secureJsonStreamableBatchResource = _batchResult(
      secureJsonStreamableBatch,
      'dart-consumer-secure-json-streamable-batch-resource-read',
      'Dart consumer protected JSON-response Streamable batch resource read',
    );
    _expect(
      jsonEncode(
        secureJsonStreamableBatchResource,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected JSON-response Streamable batch missed content.',
    );
    final secureJsonStreamableBatchError = _batchError(
      secureJsonStreamableBatch,
      'dart-consumer-secure-json-streamable-batch-bad-method',
      'Dart consumer protected JSON-response Streamable batch bad method',
    );
    _expect(
      secureJsonStreamableBatchError['code'] == McpErrorCodes.methodNotFound,
      'Dart consumer protected JSON-response Streamable batch missed error isolation.',
    );
    final secureJsonStreamableBatchTools = _batchResult(
      secureJsonStreamableBatch,
      'dart-consumer-secure-json-streamable-batch-tools',
      'Dart consumer protected JSON-response Streamable batch tools',
    );
    _expect(
      jsonEncode(secureJsonStreamableBatchTools).contains(
        'connectanum.pubsub.publish',
      ),
      'Dart consumer protected JSON-response Streamable batch missed tools.',
    );
    _expect(
      secureJsonClient.sessionId == secureJsonSessionId &&
          secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response batch captured SSE state.',
    );
    await _expectInvalidLastEventIdRejectedWithoutSessionLoss(
      secureJsonClient,
      sessionId: secureJsonSessionId as String,
      eventId: null,
      label:
          'Dart consumer protected JSON-response Streamable invalid Last-Event-ID',
    );
    await _expectEmptyLastEventIdStartsFreshPoll(
      secureJsonClient,
      sessionId: secureJsonSessionId,
      eventId: secureJsonClient.lastEventId,
      label:
          'Dart consumer protected JSON-response Streamable empty Last-Event-ID',
    );
    await secureJsonClient.deleteSession();
    _expect(
      secureJsonClient.sessionId == null && secureJsonClient.lastEventId == null,
      'Dart consumer protected JSON-response delete leaked state.',
    );

    final tokenOnlyJsonClient = McpStreamableHttpClient.withBearerToken(
      secureJsonEndpoint,
      grant.accessToken,
    );
    try {
      final tokenOnlyDirectTools = await tokenOnlyJsonClient.listToolsDirect(
        id: 'dart-consumer-secure-json-token-only-direct-tools',
      );
      _expect(
        _stringFields(
          tokenOnlyDirectTools.tools,
          'name',
        ).contains('connectanum.pubsub.publish'),
        'Dart consumer token-only JSON-response direct tools missed pub/sub.',
      );
      final tokenOnlyDirectApiTool = await tokenOnlyJsonClient.callToolDirect(
        'connectanum.api.list',
        id: 'dart-consumer-secure-json-token-only-direct-api-tool-call',
        arguments: const <String, Object?>{'kind': 'topic'},
      );
      _expect(
        jsonEncode(tokenOnlyDirectApiTool).contains(_secureTopic),
        'Dart consumer token-only JSON-response direct tool call missed topic API.',
      );
      final tokenOnlyDirectProcedureCatalog =
          await tokenOnlyJsonClient.listWampApiDirect(
        id: 'dart-consumer-secure-json-token-only-direct-procedure-catalog',
        kind: 'procedure',
      );
      _expect(
        jsonEncode(tokenOnlyDirectProcedureCatalog).contains(
          _secureProcedure,
        ),
        'Dart consumer token-only JSON-response direct procedure catalog missed metadata.',
      );
      final tokenOnlyDirectProcedureDescription = await tokenOnlyJsonClient
          .describeWampApiDirect(
            _secureProcedure,
            id:
                'dart-consumer-secure-json-token-only-direct-procedure-describe',
            kind: 'procedure',
          );
      _expect(
        jsonEncode(tokenOnlyDirectProcedureDescription).contains(
          'CLI Secure Lookup',
        ),
        'Dart consumer token-only JSON-response direct procedure describe missed metadata.',
      );
      final tokenOnlyDirectTopicDescription = await tokenOnlyJsonClient
          .describeWampApiDirect(
            _secureTopic,
            id: 'dart-consumer-secure-json-token-only-direct-topic-describe',
            kind: 'topic',
          );
      _expect(
        jsonEncode(tokenOnlyDirectTopicDescription).contains(
          'CLI Secure Smoke Events',
        ),
        'Dart consumer token-only JSON-response direct topic describe missed metadata.',
      );
      final tokenOnlyDirectResources = await tokenOnlyJsonClient
          .listResourcesDirect(
            id: 'dart-consumer-secure-json-token-only-direct-resources',
          );
      _expect(
        _stringFields(
          tokenOnlyDirectResources.resources,
          'uri',
        ).contains('cli://mcp/secure/context'),
        'Dart consumer token-only JSON-response direct resources missed context.',
      );
      final tokenOnlyDirectContents = await tokenOnlyJsonClient
          .readResourceDirect(
            'cli://mcp/secure/context',
            id: 'dart-consumer-secure-json-token-only-direct-resource-read',
          );
      _expect(
        jsonEncode(tokenOnlyDirectContents).contains(
          'Router CLI secure MCP context.',
        ),
        'Dart consumer token-only JSON-response direct resource read missed content.',
      );
      final tokenOnlyDirectTemplates = await tokenOnlyJsonClient
          .listResourceTemplatesDirect(
            id: 'dart-consumer-secure-json-token-only-direct-templates',
          );
      _expect(
        _stringFields(
          tokenOnlyDirectTemplates.resourceTemplates,
          'uriTemplate',
        ).contains('cli://mcp/secure/task/{taskId}'),
        'Dart consumer token-only JSON-response direct templates missed secure task.',
      );
      final tokenOnlyDirectPrompts = await tokenOnlyJsonClient
          .listPromptsDirect(
            id: 'dart-consumer-secure-json-token-only-direct-prompts',
          );
      _expect(
        _stringFields(
          tokenOnlyDirectPrompts.prompts,
          'name',
        ).contains('summarize-secure-cli-context'),
        'Dart consumer token-only JSON-response direct prompts missed secure prompt.',
      );
      final tokenOnlyDirectPrompt = await tokenOnlyJsonClient.getPromptDirect(
        'summarize-secure-cli-context',
        id: 'dart-consumer-secure-json-token-only-direct-prompt-get',
        arguments: const <String, String>{
          'topic': 'Dart token-only direct JSON-response readiness',
        },
      );
      _expect(
        jsonEncode(tokenOnlyDirectPrompt).contains(
          'Dart token-only direct JSON-response readiness',
        ),
        'Dart consumer token-only JSON-response direct prompt missed substitution.',
      );
      final tokenOnlyDirectBatch = await tokenOnlyJsonClient.postBatchDirect(
        <McpJsonMap>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'dart-consumer-secure-json-token-only-direct-batch-resource',
            'method': 'resources/read',
            'params': <String, Object?>{'uri': 'cli://mcp/secure/context'},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'dart-consumer-secure-json-token-only-direct-batch-bad-method',
            'method': 'tools/unknown',
            'params': <String, Object?>{},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'dart-consumer-secure-json-token-only-direct-batch-api',
            'method': 'tools/call',
            'params': <String, Object?>{
              'name': 'connectanum.api.list',
              'arguments': <String, Object?>{'kind': 'topic'},
            },
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
            'params': <String, Object?>{},
          },
        ],
      );
      _expect(
        tokenOnlyDirectBatch?.length == 3,
        'Dart consumer token-only JSON-response direct batch count changed.',
      );
      final tokenOnlyDirectBatchResource = _batchResult(
        tokenOnlyDirectBatch,
        'dart-consumer-secure-json-token-only-direct-batch-resource',
        'Dart consumer token-only JSON-response direct batch resource read',
      );
      _expect(
        jsonEncode(tokenOnlyDirectBatchResource).contains(
          'Router CLI secure MCP context.',
        ),
        'Dart consumer token-only JSON-response direct batch missed content.',
      );
      final tokenOnlyDirectBatchError = _batchError(
        tokenOnlyDirectBatch,
        'dart-consumer-secure-json-token-only-direct-batch-bad-method',
        'Dart consumer token-only JSON-response direct batch bad method',
      );
      _expect(
        tokenOnlyDirectBatchError['code'] == McpErrorCodes.methodNotFound,
        'Dart consumer token-only JSON-response direct batch missed error isolation.',
      );
      final tokenOnlyDirectBatchApi = _batchResult(
        tokenOnlyDirectBatch,
        'dart-consumer-secure-json-token-only-direct-batch-api',
        'Dart consumer token-only JSON-response direct batch API call',
      );
      _expect(
        jsonEncode(tokenOnlyDirectBatchApi).contains(_secureTopic),
        'Dart consumer token-only JSON-response direct batch missed topic API.',
      );
      _expect(
        tokenOnlyJsonClient.sessionId == null &&
            tokenOnlyJsonClient.lastEventId == null,
        'Dart consumer token-only JSON-response direct batch captured state.',
      );
      await _expectConfiguredWampRegistrationMeta(
        tokenOnlyJsonClient,
        idPrefix: 'dart-consumer-secure-json-token-only-direct',
        label:
            'Dart consumer token-only JSON-response direct configured WAMP registration meta',
        procedure: _secureProcedure,
        directJson: true,
        expectSseCursor: false,
      );
      await _expectWampSessionMeta(
        tokenOnlyJsonClient,
        idPrefix: 'dart-consumer-secure-json-token-only-direct',
        label: 'Dart consumer token-only JSON-response direct WAMP session meta',
        expectedAuthId: 'cli-user',
        expectedAuthRole: 'member',
        directJson: true,
        expectSseCursor: false,
      );
      await _expectConfiguredWampSubscriptionMeta(
        tokenOnlyJsonClient,
        idPrefix: 'dart-consumer-secure-json-token-only-direct',
        label:
            'Dart consumer token-only JSON-response direct configured WAMP subscription meta',
        topic: _configuredOnlySecureTopic,
        directJson: true,
        expectSseCursor: false,
      );
      final tokenOnlyDirectSubscription =
          await tokenOnlyJsonClient.subscribeWampTopicDirect(
        _secureTopic,
        id: 'dart-consumer-secure-json-token-only-direct-subscribe',
        queueLimit: 5,
      );
      _expect(
        tokenOnlyDirectSubscription.topic == _secureTopic &&
            tokenOnlyDirectSubscription.handle.isNotEmpty,
        'Dart consumer token-only JSON-response direct subscription was invalid.',
      );
      await _expectWampSubscriptionMeta(
        tokenOnlyJsonClient,
        idPrefix: 'dart-consumer-secure-json-token-only-direct',
        label:
            'Dart consumer token-only JSON-response direct WAMP subscription meta',
        topic: _secureTopic,
        subscription: tokenOnlyDirectSubscription,
        expectedAuthId: 'cli-user',
        expectedAuthRole: 'member',
        directJson: true,
        expectSseCursor: false,
      );
      final tokenOnlyDirectPublication =
          await tokenOnlyJsonClient.publishWampEventDirect(
        _secureTopic,
        id: 'dart-consumer-secure-json-token-only-direct-publish',
        argumentsKeywords: const <String, Object?>{
          'via': 'dart-consumer-token-only-json-direct',
        },
        acknowledge: true,
      );
      _expect(
        tokenOnlyDirectPublication.topic == _secureTopic &&
            tokenOnlyDirectPublication.acknowledged,
        'Dart consumer token-only JSON-response direct publish was invalid.',
      );
      final tokenOnlyDirectEvents = await _pollUntilEvent(
        tokenOnlyJsonClient,
        tokenOnlyDirectSubscription.handle,
        marker: 'dart-consumer-token-only-json-direct',
        idPrefix: 'dart-consumer-secure-json-token-only-direct-poll',
      );
      _expect(
        jsonEncode(
          tokenOnlyDirectEvents.events,
        ).contains('dart-consumer-token-only-json-direct'),
        'Dart consumer token-only JSON-response direct poll missed event.',
      );
      await _expectNotificationPubSub(
        tokenOnlyJsonClient,
        tokenOnlyDirectSubscription.handle,
        topic: _secureTopic,
        marker: 'dart-consumer-token-only-json-direct-notification',
        idPrefix:
            'dart-consumer-secure-json-token-only-direct-notification-poll',
        label: 'Dart consumer token-only JSON-response direct pub/sub',
        directJson: true,
      );
      final tokenOnlyDirectUnsubscribe =
          await tokenOnlyJsonClient.unsubscribeWampTopicDirect(
        tokenOnlyDirectSubscription.handle,
        id: 'dart-consumer-secure-json-token-only-direct-unsubscribe',
      );
      _expect(
        tokenOnlyDirectUnsubscribe.unsubscribed,
        'Dart consumer token-only JSON-response direct unsubscribe was invalid.',
      );
      _expect(
        tokenOnlyJsonClient.sessionId == null &&
            tokenOnlyJsonClient.lastEventId == null,
        'Dart consumer token-only JSON-response direct access captured state.',
      );

      final tokenOnlyInitialize = await tokenOnlyJsonClient.initialize(
        id: 'dart-consumer-secure-json-token-only-initialize',
        protocolVersion: _protocolVersion,
        clientInfo: const <String, Object?>{
          'name': 'router-cli-dart-consumer-smoke-token-only',
          'version': '0.0.0',
        },
      );
      _expect(
        _resultFrom(
          tokenOnlyInitialize,
          'token-only secure JSON-response initialize',
        )['protocolVersion'] == _protocolVersion,
        'Dart consumer token-only JSON-response initialize changed protocol.',
      );
      final tokenOnlySessionId = tokenOnlyJsonClient.sessionId;
      _expect(
        tokenOnlySessionId != null && tokenOnlyJsonClient.lastEventId == null,
        'Dart consumer token-only JSON-response initialize missed state.',
      );
      await tokenOnlyJsonClient.notifyInitialized();
      await _expectRawDirectJsonStaleSessionIgnored(
        secureJsonEndpoint,
        tokenOnlyJsonClient,
        id: 'dart-consumer-secure-json-token-only-direct-json-stale-session',
        label:
            'Dart consumer token-only JSON-response direct JSON stale MCP-Session-Id',
        bearerToken: grant.accessToken,
      );
      await _expectConfiguredWampRegistrationMeta(
        tokenOnlyJsonClient,
        idPrefix: 'dart-consumer-secure-json-token-only-streamable',
        label:
            'Dart consumer token-only JSON-response Streamable configured WAMP registration meta',
        procedure: _secureProcedure,
        directJson: false,
        expectSseCursor: false,
      );
      await _expectWampSessionMeta(
        tokenOnlyJsonClient,
        idPrefix: 'dart-consumer-secure-json-token-only-streamable',
        label:
            'Dart consumer token-only JSON-response Streamable WAMP session meta',
        expectedAuthId: 'cli-user',
        expectedAuthRole: 'member',
        directJson: false,
        expectSseCursor: false,
      );
      final tokenOnlyStreamableTools = await tokenOnlyJsonClient.listTools(
        id: 'dart-consumer-secure-json-token-only-streamable-tools',
      );
      _expect(
        _stringFields(
          tokenOnlyStreamableTools.tools,
          'name',
        ).contains('connectanum.pubsub.publish'),
        'Dart consumer token-only JSON-response Streamable tools missed pub/sub.',
      );
      final tokenOnlyStreamableApiTool = await tokenOnlyJsonClient.callTool(
        'connectanum.api.list',
        id: 'dart-consumer-secure-json-token-only-streamable-api-tool-call',
        arguments: const <String, Object?>{'kind': 'topic'},
      );
      _expect(
        jsonEncode(tokenOnlyStreamableApiTool).contains(_secureTopic),
        'Dart consumer token-only JSON-response Streamable tool call missed topic API.',
      );
      final tokenOnlyStreamableProcedureCatalog =
          await tokenOnlyJsonClient.listWampApi(
        id: 'dart-consumer-secure-json-token-only-streamable-procedure-catalog',
        kind: 'procedure',
      );
      _expect(
        jsonEncode(tokenOnlyStreamableProcedureCatalog).contains(
          _secureProcedure,
        ),
        'Dart consumer token-only JSON-response Streamable procedure catalog missed metadata.',
      );
      final tokenOnlyStreamableProcedureDescription =
          await tokenOnlyJsonClient.describeWampApi(
        _secureProcedure,
        id:
            'dart-consumer-secure-json-token-only-streamable-procedure-describe',
        kind: 'procedure',
      );
      _expect(
        jsonEncode(tokenOnlyStreamableProcedureDescription).contains(
          'CLI Secure Lookup',
        ),
        'Dart consumer token-only JSON-response Streamable procedure describe missed metadata.',
      );
      final tokenOnlyStreamableTopicDescription = await tokenOnlyJsonClient
          .describeWampApi(
            _secureTopic,
            id: 'dart-consumer-secure-json-token-only-streamable-topic-describe',
            kind: 'topic',
          );
      _expect(
        jsonEncode(tokenOnlyStreamableTopicDescription).contains(
          'CLI Secure Smoke Events',
        ),
        'Dart consumer token-only JSON-response Streamable topic describe missed metadata.',
      );
      final tokenOnlyStreamableResources = await tokenOnlyJsonClient
          .listResources(
            id: 'dart-consumer-secure-json-token-only-streamable-resources',
          );
      _expect(
        _stringFields(
          tokenOnlyStreamableResources.resources,
          'uri',
        ).contains('cli://mcp/secure/context'),
        'Dart consumer token-only JSON-response Streamable resources missed context.',
      );
      final tokenOnlyStreamableContents = await tokenOnlyJsonClient
          .readResource(
            'cli://mcp/secure/context',
            id: 'dart-consumer-secure-json-token-only-streamable-resource-read',
          );
      _expect(
        jsonEncode(tokenOnlyStreamableContents).contains(
          'Router CLI secure MCP context.',
        ),
        'Dart consumer token-only JSON-response Streamable resource read missed content.',
      );
      final tokenOnlyStreamableTemplates = await tokenOnlyJsonClient
          .listResourceTemplates(
            id: 'dart-consumer-secure-json-token-only-streamable-templates',
          );
      _expect(
        _stringFields(
          tokenOnlyStreamableTemplates.resourceTemplates,
          'uriTemplate',
        ).contains('cli://mcp/secure/task/{taskId}'),
        'Dart consumer token-only JSON-response Streamable templates missed secure task.',
      );
      final tokenOnlyStreamablePrompts = await tokenOnlyJsonClient.listPrompts(
        id: 'dart-consumer-secure-json-token-only-streamable-prompts',
      );
      _expect(
        _stringFields(
          tokenOnlyStreamablePrompts.prompts,
          'name',
        ).contains('summarize-secure-cli-context'),
        'Dart consumer token-only JSON-response Streamable prompts missed secure prompt.',
      );
      final tokenOnlyStreamablePrompt = await tokenOnlyJsonClient.getPrompt(
        'summarize-secure-cli-context',
        id: 'dart-consumer-secure-json-token-only-streamable-prompt-get',
        arguments: const <String, String>{
          'topic': 'Dart token-only Streamable JSON-response readiness',
        },
      );
      _expect(
        jsonEncode(tokenOnlyStreamablePrompt).contains(
          'Dart token-only Streamable JSON-response readiness',
        ),
        'Dart consumer token-only JSON-response Streamable prompt missed substitution.',
      );
      final tokenOnlyStreamableBatch = await tokenOnlyJsonClient.postBatch(
        <McpJsonMap>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id':
                'dart-consumer-secure-json-token-only-streamable-batch-resource',
            'method': 'resources/read',
            'params': <String, Object?>{'uri': 'cli://mcp/secure/context'},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id':
                'dart-consumer-secure-json-token-only-streamable-batch-bad-method',
            'method': 'tools/unknown',
            'params': <String, Object?>{},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'dart-consumer-secure-json-token-only-streamable-batch-tools',
            'method': 'tools/list',
            'params': <String, Object?>{},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
            'params': <String, Object?>{},
          },
        ],
      );
      _expect(
        tokenOnlyStreamableBatch?.length == 3,
        'Dart consumer token-only JSON-response Streamable batch count changed.',
      );
      final tokenOnlyStreamableBatchResource = _batchResult(
        tokenOnlyStreamableBatch,
        'dart-consumer-secure-json-token-only-streamable-batch-resource',
        'Dart consumer token-only JSON-response Streamable batch resource read',
      );
      _expect(
        jsonEncode(tokenOnlyStreamableBatchResource).contains(
          'Router CLI secure MCP context.',
        ),
        'Dart consumer token-only JSON-response Streamable batch missed content.',
      );
      final tokenOnlyStreamableBatchError = _batchError(
        tokenOnlyStreamableBatch,
        'dart-consumer-secure-json-token-only-streamable-batch-bad-method',
        'Dart consumer token-only JSON-response Streamable batch bad method',
      );
      _expect(
        tokenOnlyStreamableBatchError['code'] == McpErrorCodes.methodNotFound,
        'Dart consumer token-only JSON-response Streamable batch missed error isolation.',
      );
      final tokenOnlyStreamableBatchTools = _batchResult(
        tokenOnlyStreamableBatch,
        'dart-consumer-secure-json-token-only-streamable-batch-tools',
        'Dart consumer token-only JSON-response Streamable batch tools',
      );
      _expect(
        jsonEncode(tokenOnlyStreamableBatchTools).contains(
          'connectanum.pubsub.publish',
        ),
        'Dart consumer token-only JSON-response Streamable batch missed tools.',
      );
      _expect(
        tokenOnlyJsonClient.sessionId == tokenOnlySessionId &&
            tokenOnlyJsonClient.lastEventId == null,
        'Dart consumer token-only JSON-response Streamable batch captured SSE state.',
      );
      await _expectConfiguredWampSubscriptionMeta(
        tokenOnlyJsonClient,
        idPrefix: 'dart-consumer-secure-json-token-only-streamable',
        label:
            'Dart consumer token-only JSON-response Streamable configured WAMP subscription meta',
        topic: _configuredOnlySecureTopic,
        directJson: false,
        expectSseCursor: false,
      );
      final tokenOnlyStreamableSubscription =
          await tokenOnlyJsonClient.subscribeWampTopic(
        _secureTopic,
        id: 'dart-consumer-secure-json-token-only-streamable-subscribe',
        queueLimit: 5,
      );
      _expect(
        tokenOnlyStreamableSubscription.topic == _secureTopic &&
            tokenOnlyStreamableSubscription.handle.isNotEmpty,
        'Dart consumer token-only JSON-response Streamable subscription was invalid.',
      );
      await _expectWampSubscriptionMeta(
        tokenOnlyJsonClient,
        idPrefix: 'dart-consumer-secure-json-token-only-streamable',
        label:
            'Dart consumer token-only JSON-response Streamable WAMP subscription meta',
        topic: _secureTopic,
        subscription: tokenOnlyStreamableSubscription,
        expectedAuthId: 'cli-user',
        expectedAuthRole: 'member',
        directJson: false,
        expectSseCursor: false,
      );
      final tokenOnlyStreamablePublication =
          await tokenOnlyJsonClient.publishWampEvent(
        _secureTopic,
        id: 'dart-consumer-secure-json-token-only-streamable-publish',
        argumentsKeywords: const <String, Object?>{
          'via': 'dart-consumer-token-only-json-streamable',
        },
        acknowledge: true,
      );
      _expect(
        tokenOnlyStreamablePublication.topic == _secureTopic &&
            tokenOnlyStreamablePublication.acknowledged,
        'Dart consumer token-only JSON-response Streamable publish was invalid.',
      );
      final tokenOnlyStreamableEvents = await _pollUntilEvent(
        tokenOnlyJsonClient,
        tokenOnlyStreamableSubscription.handle,
        marker: 'dart-consumer-token-only-json-streamable',
        idPrefix: 'dart-consumer-secure-json-token-only-streamable-poll',
        directJson: false,
      );
      _expect(
        jsonEncode(
          tokenOnlyStreamableEvents.events,
        ).contains('dart-consumer-token-only-json-streamable'),
        'Dart consumer token-only JSON-response Streamable poll missed event.',
      );
      await _expectNotificationPubSub(
        tokenOnlyJsonClient,
        tokenOnlyStreamableSubscription.handle,
        topic: _secureTopic,
        marker: 'dart-consumer-token-only-json-streamable-notification',
        idPrefix:
            'dart-consumer-secure-json-token-only-streamable-notification-poll',
        label: 'Dart consumer token-only JSON-response Streamable pub/sub',
        directJson: false,
      );
      final tokenOnlyStreamableUnsubscribe =
          await tokenOnlyJsonClient.unsubscribeWampTopic(
        tokenOnlyStreamableSubscription.handle,
        id: 'dart-consumer-secure-json-token-only-streamable-unsubscribe',
      );
      _expect(
        tokenOnlyStreamableUnsubscribe.unsubscribed,
        'Dart consumer token-only JSON-response Streamable unsubscribe was invalid.',
      );
      _expect(
        tokenOnlyJsonClient.sessionId == tokenOnlySessionId &&
            tokenOnlyJsonClient.lastEventId == null,
        'Dart consumer token-only JSON-response Streamable captured SSE state.',
      );
      await _expectInvalidLastEventIdRejectedWithoutSessionLoss(
        tokenOnlyJsonClient,
        sessionId: tokenOnlySessionId as String,
        eventId: null,
        label:
            'Dart consumer token-only JSON-response Streamable invalid Last-Event-ID',
      );
      await _expectEmptyLastEventIdStartsFreshPoll(
        tokenOnlyJsonClient,
        sessionId: tokenOnlySessionId,
        eventId: tokenOnlyJsonClient.lastEventId,
        label:
            'Dart consumer token-only JSON-response Streamable empty Last-Event-ID',
      );
      await tokenOnlyJsonClient.deleteSession();
      _expect(
        tokenOnlyJsonClient.sessionId == null &&
            tokenOnlyJsonClient.lastEventId == null,
        'Dart consumer token-only JSON-response delete leaked state.',
      );
    } finally {
      tokenOnlyJsonClient.close(force: true);
    }

    final tokenOnlySecureClient = McpStreamableHttpClient.withBearerToken(
      secureEndpoint,
      grant.accessToken,
    );
    try {
      final tokenOnlySecureDirectTools = await tokenOnlySecureClient
          .listToolsDirect(id: 'dart-consumer-secure-token-only-direct-tools');
      _expect(
        _stringFields(
          tokenOnlySecureDirectTools.tools,
          'name',
        ).contains('connectanum.pubsub.publish'),
        'Dart consumer token-only secure direct tools missed pub/sub.',
      );
      final tokenOnlySecureDirectApiTool = await tokenOnlySecureClient
          .callToolDirect(
            'connectanum.api.list',
            id: 'dart-consumer-secure-token-only-direct-api-tool-call',
            arguments: const <String, Object?>{'kind': 'topic'},
          );
      _expect(
        jsonEncode(tokenOnlySecureDirectApiTool).contains(_secureTopic),
        'Dart consumer token-only secure direct tool call missed topic API.',
      );
      final tokenOnlySecureDirectResources = await tokenOnlySecureClient
          .listResourcesDirect(
            id: 'dart-consumer-secure-token-only-direct-resources',
          );
      _expect(
        _stringFields(
          tokenOnlySecureDirectResources.resources,
          'uri',
        ).contains('cli://mcp/secure/context'),
        'Dart consumer token-only secure direct resources missed context.',
      );
      final tokenOnlySecureDirectContents = await tokenOnlySecureClient
          .readResourceDirect(
            'cli://mcp/secure/context',
            id: 'dart-consumer-secure-token-only-direct-resource-read',
          );
      _expect(
        jsonEncode(
          tokenOnlySecureDirectContents,
        ).contains('Router CLI secure MCP context.'),
        'Dart consumer token-only secure direct resource read missed content.',
      );
      final tokenOnlySecureDirectTemplates = await tokenOnlySecureClient
          .listResourceTemplatesDirect(
            id: 'dart-consumer-secure-token-only-direct-templates',
          );
      _expect(
        _stringFields(
          tokenOnlySecureDirectTemplates.resourceTemplates,
          'uriTemplate',
        ).contains('cli://mcp/secure/task/{taskId}'),
        'Dart consumer token-only secure direct templates missed secure task.',
      );
      final tokenOnlySecureDirectPrompts = await tokenOnlySecureClient
          .listPromptsDirect(
            id: 'dart-consumer-secure-token-only-direct-prompts',
          );
      _expect(
        _stringFields(
          tokenOnlySecureDirectPrompts.prompts,
          'name',
        ).contains('summarize-secure-cli-context'),
        'Dart consumer token-only secure direct prompts missed secure prompt.',
      );
      final tokenOnlySecureDirectPrompt = await tokenOnlySecureClient
          .getPromptDirect(
            'summarize-secure-cli-context',
            id: 'dart-consumer-secure-token-only-direct-prompt-get',
            arguments: const <String, String>{
              'topic': 'Dart token-only secure direct readiness',
            },
          );
      _expect(
        jsonEncode(tokenOnlySecureDirectPrompt).contains(
          'Dart token-only secure direct readiness',
        ),
        'Dart consumer token-only secure direct prompt missed substitution.',
      );
      final tokenOnlySecureDirectBatch =
          await tokenOnlySecureClient.postBatchDirect(
        <McpJsonMap>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'dart-consumer-secure-token-only-direct-batch-resource',
            'method': 'resources/read',
            'params': <String, Object?>{'uri': 'cli://mcp/secure/context'},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'dart-consumer-secure-token-only-direct-batch-bad-method',
            'method': 'tools/unknown',
            'params': <String, Object?>{},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'dart-consumer-secure-token-only-direct-batch-api',
            'method': 'tools/call',
            'params': <String, Object?>{
              'name': 'connectanum.api.list',
              'arguments': <String, Object?>{'kind': 'topic'},
            },
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
            'params': <String, Object?>{},
          },
        ],
      );
      _expect(
        tokenOnlySecureDirectBatch?.length == 3,
        'Dart consumer token-only secure direct batch count changed.',
      );
      final tokenOnlySecureDirectBatchResource = _batchResult(
        tokenOnlySecureDirectBatch,
        'dart-consumer-secure-token-only-direct-batch-resource',
        'Dart consumer token-only secure direct batch resource read',
      );
      _expect(
        jsonEncode(tokenOnlySecureDirectBatchResource).contains(
          'Router CLI secure MCP context.',
        ),
        'Dart consumer token-only secure direct batch missed content.',
      );
      final tokenOnlySecureDirectBatchError = _batchError(
        tokenOnlySecureDirectBatch,
        'dart-consumer-secure-token-only-direct-batch-bad-method',
        'Dart consumer token-only secure direct batch bad method',
      );
      _expect(
        tokenOnlySecureDirectBatchError['code'] == McpErrorCodes.methodNotFound,
        'Dart consumer token-only secure direct batch missed error isolation.',
      );
      final tokenOnlySecureDirectBatchApi = _batchResult(
        tokenOnlySecureDirectBatch,
        'dart-consumer-secure-token-only-direct-batch-api',
        'Dart consumer token-only secure direct batch API call',
      );
      _expect(
        jsonEncode(tokenOnlySecureDirectBatchApi).contains(_secureTopic),
        'Dart consumer token-only secure direct batch missed topic API.',
      );
      _expect(
        tokenOnlySecureClient.sessionId == null &&
            tokenOnlySecureClient.lastEventId == null,
        'Dart consumer token-only secure direct batch captured state.',
      );
      final tokenOnlySecureDirectTopics = await tokenOnlySecureClient
          .listWampApiDirect(
            id: 'dart-consumer-secure-token-only-direct-topics',
            kind: 'topic',
          );
      _expect(
        jsonEncode(tokenOnlySecureDirectTopics).contains(_secureTopic),
        'Dart consumer token-only secure direct WAMP catalog missed topic.',
      );
      final tokenOnlySecureDirectTopicDescription =
          await tokenOnlySecureClient.describeWampApiDirect(
        _secureTopic,
        id: 'dart-consumer-secure-token-only-direct-topic-describe',
        kind: 'topic',
      );
      _expect(
        jsonEncode(tokenOnlySecureDirectTopicDescription).contains(
          'CLI Secure Smoke Events',
        ),
        'Dart consumer token-only secure direct topic describe missed metadata.',
      );
      await _expectConfiguredWampRegistrationMeta(
        tokenOnlySecureClient,
        idPrefix: 'dart-consumer-secure-token-only-direct',
        label:
            'Dart consumer token-only secure direct configured WAMP registration meta',
        procedure: _secureProcedure,
        directJson: true,
        expectSseCursor: false,
      );
      await _expectWampSessionMeta(
        tokenOnlySecureClient,
        idPrefix: 'dart-consumer-secure-token-only-direct',
        label: 'Dart consumer token-only secure direct WAMP session meta',
        expectedAuthId: 'cli-user',
        expectedAuthRole: 'member',
        directJson: true,
        expectSseCursor: false,
      );
      await _expectConfiguredWampSubscriptionMeta(
        tokenOnlySecureClient,
        idPrefix: 'dart-consumer-secure-token-only-direct',
        label:
            'Dart consumer token-only secure direct configured WAMP subscription meta',
        topic: _configuredOnlySecureTopic,
        directJson: true,
        expectSseCursor: false,
      );
      final tokenOnlySecureDirectSubscription = await tokenOnlySecureClient
          .subscribeWampTopicDirect(
            _secureTopic,
            id: 'dart-consumer-secure-token-only-direct-subscribe',
            queueLimit: 5,
          );
      _expect(
        tokenOnlySecureDirectSubscription.topic == _secureTopic &&
            tokenOnlySecureDirectSubscription.handle.isNotEmpty,
        'Dart consumer token-only secure direct subscription was invalid.',
      );
      await _expectWampSubscriptionMeta(
        tokenOnlySecureClient,
        idPrefix: 'dart-consumer-secure-token-only-direct',
        label: 'Dart consumer token-only secure direct WAMP subscription meta',
        topic: _secureTopic,
        subscription: tokenOnlySecureDirectSubscription,
        expectedAuthId: 'cli-user',
        expectedAuthRole: 'member',
        directJson: true,
        expectSseCursor: false,
      );
      final tokenOnlySecureDirectPublication = await tokenOnlySecureClient
          .publishWampEventDirect(
            _secureTopic,
            id: 'dart-consumer-secure-token-only-direct-publish',
            argumentsKeywords: const <String, Object?>{
              'via': 'dart-consumer-token-only-direct',
            },
            acknowledge: true,
          );
      _expect(
        tokenOnlySecureDirectPublication.topic == _secureTopic &&
            tokenOnlySecureDirectPublication.acknowledged,
        'Dart consumer token-only secure direct publish was invalid.',
      );
      final tokenOnlySecureDirectEvents = await _pollUntilEvent(
        tokenOnlySecureClient,
        tokenOnlySecureDirectSubscription.handle,
        marker: 'dart-consumer-token-only-direct',
        idPrefix: 'dart-consumer-secure-token-only-direct-poll',
      );
      _expect(
        jsonEncode(
          tokenOnlySecureDirectEvents.events,
        ).contains('dart-consumer-token-only-direct'),
        'Dart consumer token-only secure direct poll missed event.',
      );
      await _expectNotificationPubSub(
        tokenOnlySecureClient,
        tokenOnlySecureDirectSubscription.handle,
        topic: _secureTopic,
        marker: 'dart-consumer-token-only-direct-notification',
        idPrefix: 'dart-consumer-secure-token-only-direct-notification-poll',
        label: 'Dart consumer token-only secure direct pub/sub',
        directJson: true,
      );
      final tokenOnlySecureDirectUnsubscribe = await tokenOnlySecureClient
          .unsubscribeWampTopicDirect(
            tokenOnlySecureDirectSubscription.handle,
            id: 'dart-consumer-secure-token-only-direct-unsubscribe',
          );
      _expect(
        tokenOnlySecureDirectUnsubscribe.unsubscribed,
        'Dart consumer token-only secure direct unsubscribe was invalid.',
      );
      _expect(
        tokenOnlySecureClient.sessionId == null &&
            tokenOnlySecureClient.lastEventId == null,
        'Dart consumer token-only secure direct pubsub captured state.',
      );

      final tokenOnlySecureInitialize = await tokenOnlySecureClient.initialize(
        id: 'dart-consumer-secure-token-only-initialize',
        protocolVersion: _protocolVersion,
        clientInfo: const <String, Object?>{
          'name': 'router-cli-dart-consumer-smoke-secure-token-only',
          'version': '0.0.0',
        },
      );
      _expect(
        _resultFrom(
          tokenOnlySecureInitialize,
          'token-only secure initialize',
        )['protocolVersion'] == _protocolVersion,
        'Dart consumer token-only secure initialize changed protocol.',
      );
      final tokenOnlySecureSessionId = tokenOnlySecureClient.sessionId;
      _expect(
        tokenOnlySecureSessionId != null,
        'Dart consumer token-only secure initialize missed session state.',
      );
      await tokenOnlySecureClient.notifyInitialized();
      await _expectWampSessionMeta(
        tokenOnlySecureClient,
        idPrefix: 'dart-consumer-secure-token-only-streamable',
        label: 'Dart consumer token-only secure Streamable WAMP session meta',
        expectedAuthId: 'cli-user',
        expectedAuthRole: 'member',
        directJson: false,
        expectSseCursor: true,
      );
      final tokenOnlySecureStreamableTools = await tokenOnlySecureClient
          .listTools(id: 'dart-consumer-secure-token-only-streamable-tools');
      _expect(
        _stringFields(
          tokenOnlySecureStreamableTools.tools,
          'name',
        ).contains('connectanum.pubsub.publish'),
        'Dart consumer token-only secure Streamable tools missed pub/sub.',
      );
      final tokenOnlySecureStreamableApiTool = await tokenOnlySecureClient
          .callTool(
            'connectanum.api.list',
            id: 'dart-consumer-secure-token-only-streamable-api-tool-call',
            arguments: const <String, Object?>{'kind': 'topic'},
          );
      _expect(
        jsonEncode(tokenOnlySecureStreamableApiTool).contains(_secureTopic),
        'Dart consumer token-only secure Streamable tool call missed topic API.',
      );
      final tokenOnlySecureStreamableResources = await tokenOnlySecureClient
          .listResources(
            id: 'dart-consumer-secure-token-only-streamable-resources',
          );
      _expect(
        _stringFields(
          tokenOnlySecureStreamableResources.resources,
          'uri',
        ).contains('cli://mcp/secure/context'),
        'Dart consumer token-only secure Streamable resources missed context.',
      );
      final tokenOnlySecureStreamableContents = await tokenOnlySecureClient
          .readResource(
            'cli://mcp/secure/context',
            id: 'dart-consumer-secure-token-only-streamable-resource-read',
          );
      _expect(
        jsonEncode(
          tokenOnlySecureStreamableContents,
        ).contains('Router CLI secure MCP context.'),
        'Dart consumer token-only secure Streamable resource read missed content.',
      );
      final tokenOnlySecureStreamableTemplates = await tokenOnlySecureClient
          .listResourceTemplates(
            id: 'dart-consumer-secure-token-only-streamable-templates',
          );
      _expect(
        _stringFields(
          tokenOnlySecureStreamableTemplates.resourceTemplates,
          'uriTemplate',
        ).contains('cli://mcp/secure/task/{taskId}'),
        'Dart consumer token-only secure Streamable templates missed secure task.',
      );
      final tokenOnlySecureStreamablePrompts = await tokenOnlySecureClient
          .listPrompts(
            id: 'dart-consumer-secure-token-only-streamable-prompts',
          );
      _expect(
        _stringFields(
          tokenOnlySecureStreamablePrompts.prompts,
          'name',
        ).contains('summarize-secure-cli-context'),
        'Dart consumer token-only secure Streamable prompts missed secure prompt.',
      );
      final tokenOnlySecureStreamablePrompt = await tokenOnlySecureClient
          .getPrompt(
            'summarize-secure-cli-context',
            id: 'dart-consumer-secure-token-only-streamable-prompt-get',
            arguments: const <String, String>{
              'topic': 'Dart token-only secure Streamable readiness',
            },
          );
      _expect(
        jsonEncode(tokenOnlySecureStreamablePrompt).contains(
          'Dart token-only secure Streamable readiness',
        ),
        'Dart consumer token-only secure Streamable prompt missed substitution.',
      );
      final tokenOnlySecureBatchSessionId = tokenOnlySecureClient.sessionId;
      final tokenOnlySecureBatchLastEventId = tokenOnlySecureClient.lastEventId;
      final tokenOnlySecureStreamableBatch =
          await tokenOnlySecureClient.postBatch(
        <McpJsonMap>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'dart-consumer-secure-token-only-streamable-batch-resource',
            'method': 'resources/read',
            'params': <String, Object?>{'uri': 'cli://mcp/secure/context'},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id':
                'dart-consumer-secure-token-only-streamable-batch-bad-method',
            'method': 'tools/unknown',
            'params': <String, Object?>{},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'dart-consumer-secure-token-only-streamable-batch-tools',
            'method': 'tools/list',
            'params': <String, Object?>{},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
            'params': <String, Object?>{},
          },
        ],
      );
      _expect(
        tokenOnlySecureStreamableBatch?.length == 3,
        'Dart consumer token-only secure Streamable batch count changed.',
      );
      final tokenOnlySecureStreamableBatchResource = _batchResult(
        tokenOnlySecureStreamableBatch,
        'dart-consumer-secure-token-only-streamable-batch-resource',
        'Dart consumer token-only secure Streamable batch resource read',
      );
      _expect(
        jsonEncode(tokenOnlySecureStreamableBatchResource).contains(
          'Router CLI secure MCP context.',
        ),
        'Dart consumer token-only secure Streamable batch missed content.',
      );
      final tokenOnlySecureStreamableBatchError = _batchError(
        tokenOnlySecureStreamableBatch,
        'dart-consumer-secure-token-only-streamable-batch-bad-method',
        'Dart consumer token-only secure Streamable batch bad method',
      );
      _expect(
        tokenOnlySecureStreamableBatchError['code'] ==
            McpErrorCodes.methodNotFound,
        'Dart consumer token-only secure Streamable batch missed error isolation.',
      );
      final tokenOnlySecureStreamableBatchTools = _batchResult(
        tokenOnlySecureStreamableBatch,
        'dart-consumer-secure-token-only-streamable-batch-tools',
        'Dart consumer token-only secure Streamable batch tools',
      );
      _expect(
        jsonEncode(tokenOnlySecureStreamableBatchTools).contains(
          'connectanum.pubsub.publish',
        ),
        'Dart consumer token-only secure Streamable batch missed tools.',
      );
      final tokenOnlySecureBatchNextEventId =
          tokenOnlySecureClient.lastEventId;
      _expect(
        tokenOnlySecureClient.sessionId == tokenOnlySecureBatchSessionId,
        'Dart consumer token-only secure Streamable batch changed session id.',
      );
      _expect(
        tokenOnlySecureBatchSessionId != null &&
            tokenOnlySecureBatchNextEventId != null &&
            tokenOnlySecureBatchNextEventId !=
                tokenOnlySecureBatchLastEventId &&
            tokenOnlySecureBatchNextEventId.startsWith(
              '$tokenOnlySecureBatchSessionId:',
            ),
        'Dart consumer token-only secure Streamable batch missed SSE state.',
      );
      await _expectInvalidLastEventIdRejectedWithoutSessionLoss(
        tokenOnlySecureClient,
        sessionId: tokenOnlySecureBatchSessionId as String,
        eventId: tokenOnlySecureBatchNextEventId as String,
        label:
            'Dart consumer token-only secure Streamable invalid Last-Event-ID',
      );
      await _expectEmptyLastEventIdStartsFreshPoll(
        tokenOnlySecureClient,
        sessionId: tokenOnlySecureBatchSessionId,
        eventId: tokenOnlySecureClient.lastEventId,
        label: 'Dart consumer token-only secure Streamable empty Last-Event-ID',
      );
      final tokenOnlySecureStreamableTopics = await tokenOnlySecureClient
          .listWampApi(
            id: 'dart-consumer-secure-token-only-streamable-topics',
            kind: 'topic',
          );
      _expect(
        jsonEncode(tokenOnlySecureStreamableTopics).contains(_secureTopic),
        'Dart consumer token-only secure Streamable WAMP catalog missed topic.',
      );
      final tokenOnlySecureStreamableTopicDescription =
          await tokenOnlySecureClient.describeWampApi(
        _secureTopic,
        id: 'dart-consumer-secure-token-only-streamable-topic-describe',
        kind: 'topic',
      );
      _expect(
        jsonEncode(tokenOnlySecureStreamableTopicDescription).contains(
          'CLI Secure Smoke Events',
        ),
        'Dart consumer token-only secure Streamable topic describe missed metadata.',
      );
      await _expectConfiguredWampRegistrationMeta(
        tokenOnlySecureClient,
        idPrefix: 'dart-consumer-secure-token-only-streamable',
        label:
            'Dart consumer token-only secure Streamable configured WAMP registration meta',
        procedure: _secureProcedure,
        directJson: false,
        expectSseCursor: true,
      );
      await _expectConfiguredWampSubscriptionMeta(
        tokenOnlySecureClient,
        idPrefix: 'dart-consumer-secure-token-only-streamable',
        label:
            'Dart consumer token-only secure Streamable configured WAMP subscription meta',
        topic: _configuredOnlySecureTopic,
        directJson: false,
        expectSseCursor: true,
      );
      final tokenOnlySecureCatalogLastEventId =
          tokenOnlySecureClient.lastEventId;
      final tokenOnlySecureStreamableSubscription = await tokenOnlySecureClient
          .subscribeWampTopic(
            _secureTopic,
            id: 'dart-consumer-secure-token-only-streamable-subscribe',
            queueLimit: 5,
          );
      _expect(
        tokenOnlySecureStreamableSubscription.topic == _secureTopic &&
            tokenOnlySecureStreamableSubscription.handle.isNotEmpty,
        'Dart consumer token-only secure Streamable subscription was invalid.',
      );
      await _expectWampSubscriptionMeta(
        tokenOnlySecureClient,
        idPrefix: 'dart-consumer-secure-token-only-streamable',
        label:
            'Dart consumer token-only secure Streamable WAMP subscription meta',
        topic: _secureTopic,
        subscription: tokenOnlySecureStreamableSubscription,
        expectedAuthId: 'cli-user',
        expectedAuthRole: 'member',
        directJson: false,
        expectSseCursor: true,
      );
      final tokenOnlySecureStreamablePublication = await tokenOnlySecureClient
          .publishWampEvent(
            _secureTopic,
            id: 'dart-consumer-secure-token-only-streamable-publish',
            argumentsKeywords: const <String, Object?>{
              'via': 'dart-consumer-token-only-streamable',
            },
            acknowledge: true,
          );
      _expect(
        tokenOnlySecureStreamablePublication.topic == _secureTopic &&
            tokenOnlySecureStreamablePublication.acknowledged,
        'Dart consumer token-only secure Streamable publish was invalid.',
      );
      final tokenOnlySecureStreamableEvents = await _pollUntilEvent(
        tokenOnlySecureClient,
        tokenOnlySecureStreamableSubscription.handle,
        marker: 'dart-consumer-token-only-streamable',
        idPrefix: 'dart-consumer-secure-token-only-streamable-poll',
        directJson: false,
      );
      _expect(
        jsonEncode(
          tokenOnlySecureStreamableEvents.events,
        ).contains('dart-consumer-token-only-streamable'),
        'Dart consumer token-only secure Streamable poll missed event.',
      );
      await _expectNotificationPubSub(
        tokenOnlySecureClient,
        tokenOnlySecureStreamableSubscription.handle,
        topic: _secureTopic,
        marker: 'dart-consumer-token-only-streamable-notification',
        idPrefix:
            'dart-consumer-secure-token-only-streamable-notification-poll',
        label: 'Dart consumer token-only secure Streamable pub/sub',
        directJson: false,
      );
      final tokenOnlySecureStreamableUnsubscribe = await tokenOnlySecureClient
          .unsubscribeWampTopic(
            tokenOnlySecureStreamableSubscription.handle,
            id: 'dart-consumer-secure-token-only-streamable-unsubscribe',
          );
      _expect(
        tokenOnlySecureStreamableUnsubscribe.unsubscribed,
        'Dart consumer token-only secure Streamable unsubscribe was invalid.',
      );
      final tokenOnlySecureLastEventId = tokenOnlySecureClient.lastEventId;
      _expect(
        tokenOnlySecureLastEventId != null &&
            tokenOnlySecureLastEventId != tokenOnlySecureCatalogLastEventId &&
            tokenOnlySecureLastEventId.startsWith(
              '$tokenOnlySecureSessionId:',
            ),
        'Dart consumer token-only secure Streamable pubsub missed SSE state.',
      );
      await tokenOnlySecureClient.deleteSession();
      _expect(
        tokenOnlySecureClient.sessionId == null &&
            tokenOnlySecureClient.lastEventId == null,
        'Dart consumer token-only secure delete leaked state.',
      );
    } finally {
      tokenOnlySecureClient.close(force: true);
    }

    secureClient = McpStreamableHttpClient.withAuthGrant(
      secureEndpoint,
      grant,
    );
    final secureTools = await secureClient.listToolsDirect(
      id: 'dart-consumer-secure-tools',
    );
    _expect(
      _stringFields(
        secureTools.tools,
        'name',
      ).contains('connectanum.pubsub.publish'),
      'Dart consumer missed protected direct JSON pubsub tool.',
    );

    final secureResources = await secureClient.listResourcesDirect(
      id: 'dart-consumer-secure-resources',
    );
    _expect(
      _stringFields(
        secureResources.resources,
        'uri',
      ).contains('cli://mcp/secure/context'),
      'Dart consumer missed protected direct JSON resource.',
    );

    final secureResourceContents = await secureClient.readResourceDirect(
      'cli://mcp/secure/context',
      id: 'dart-consumer-secure-resource-read',
    );
    _expect(
      jsonEncode(
        secureResourceContents,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected direct JSON resource read missed content.',
    );

    final secureDirectBatch = await secureClient.postBatchDirect(
      <McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-direct-batch-resource-read',
          'method': 'resources/read',
          'params': <String, Object?>{'uri': 'cli://mcp/secure/context'},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-direct-batch-bad-method',
          'method': 'tools/unknown',
          'params': <String, Object?>{},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-direct-batch-tools',
          'method': 'tools/list',
          'params': <String, Object?>{},
        },
      ],
    );
    _expect(
      secureDirectBatch?.length == 3,
      'Dart consumer protected direct JSON batch response count changed.',
    );
    final secureDirectBatchResource = _batchResult(
      secureDirectBatch,
      'dart-consumer-secure-direct-batch-resource-read',
      'Dart consumer protected direct JSON batch resource read',
    );
    _expect(
      jsonEncode(
        secureDirectBatchResource,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected direct JSON batch resource missed content.',
    );
    final secureDirectBatchError = _batchError(
      secureDirectBatch,
      'dart-consumer-secure-direct-batch-bad-method',
      'Dart consumer protected direct JSON batch bad method',
    );
    _expect(
      secureDirectBatchError['code'] == McpErrorCodes.methodNotFound,
      'Dart consumer protected direct JSON batch missed method error isolation.',
    );
    final secureDirectBatchTools = _batchResult(
      secureDirectBatch,
      'dart-consumer-secure-direct-batch-tools',
      'Dart consumer protected direct JSON batch tools list',
    );
    _expect(
      jsonEncode(
        secureDirectBatchTools,
      ).contains('connectanum.pubsub.publish'),
      'Dart consumer protected direct JSON batch missed pubsub tool.',
    );
    _expect(
      secureClient.sessionId == null && secureClient.lastEventId == null,
      'Dart consumer protected direct JSON batch changed Streamable state.',
    );

    final secureProcedureCatalog = await secureClient.listWampApiDirect(
      id: 'dart-consumer-secure-procedure-catalog',
      kind: 'procedure',
    );
    _expect(
      jsonEncode(secureProcedureCatalog).contains(_secureProcedure),
      'Dart consumer missed protected direct JSON procedure catalog.',
    );
    final secureProcedureDescription =
        await secureClient.describeWampApiDirect(
      _secureProcedure,
      id: 'dart-consumer-secure-procedure-describe',
      kind: 'procedure',
    );
    _expect(
      jsonEncode(secureProcedureDescription).contains('CLI Secure Lookup'),
      'Dart consumer missed protected direct JSON procedure metadata.',
    );

    final secureCatalog = await secureClient.listWampApiDirect(
      id: 'dart-consumer-secure-topics',
      kind: 'topic',
    );
    _expect(
      jsonEncode(secureCatalog).contains(_secureTopic),
      'Dart consumer missed protected direct JSON topic catalog.',
    );
    final secureTopicDescription = await secureClient.describeWampApiDirect(
      _secureTopic,
      id: 'dart-consumer-secure-topic-describe',
      kind: 'topic',
    );
    _expect(
      jsonEncode(secureTopicDescription).contains('CLI Secure Smoke Events'),
      'Dart consumer missed protected direct JSON topic metadata.',
    );

    final subscription = await secureClient.subscribeWampTopicDirect(
      _secureTopic,
      id: 'dart-consumer-secure-subscribe',
      queueLimit: 5,
    );
    _expect(
      subscription.topic == _secureTopic && subscription.handle.isNotEmpty,
      'Dart consumer protected direct JSON subscription was invalid.',
    );

    final secureInitialize = await secureClient.initialize(
      id: 'dart-consumer-secure-initialize',
      protocolVersion: _protocolVersion,
      clientInfo: const <String, Object?>{
        'name': 'router-cli-dart-consumer-smoke-secure',
        'version': '0.0.0',
      },
    );
    _expect(
      _resultFrom(secureInitialize, 'secure initialize')['protocolVersion'] ==
          _protocolVersion,
      'Dart consumer protected Streamable initialize changed protocol.',
    );
    await secureClient.notifyInitialized();
    final secureSessionId = secureClient.sessionId;
    final secureLastEventId = secureClient.lastEventId;
    _expect(
      secureSessionId != null && secureSessionId.isNotEmpty,
      'Dart consumer protected Streamable initialize missed session state.',
    );

    final unauthenticatedSecureClient = McpStreamableHttpClient(secureEndpoint);
    try {
      await _expectMcpHttpRejected(
        () => unauthenticatedSecureClient.listToolsDirect(
          id: 'dart-consumer-secure-active-missing-bearer-tools',
        ),
        HttpStatus.unauthorized,
        'Dart consumer protected route without bearer during active session',
      );
      _expect(
        unauthenticatedSecureClient.sessionId == null &&
            unauthenticatedSecureClient.lastEventId == null,
        'Dart consumer missing-bearer protected route captured state.',
      );
    } finally {
      unauthenticatedSecureClient.close(force: true);
    }

    final unknownBearerSecureClient = McpStreamableHttpClient.withBearerToken(
      secureEndpoint,
      'not-a-valid-token',
    );
    try {
      await _expectMcpHttpRejected(
        () => unknownBearerSecureClient.initialize(
          id: 'dart-consumer-secure-active-unknown-bearer-initialize',
          protocolVersion: _protocolVersion,
          clientInfo: const <String, Object?>{
            'name': 'router-cli-dart-consumer-smoke-unknown-bearer',
            'version': '0.0.0',
          },
        ),
        HttpStatus.unauthorized,
        'Dart consumer protected route with unknown bearer during active session',
      );
      _expect(
        unknownBearerSecureClient.sessionId == null &&
            unknownBearerSecureClient.lastEventId == null,
        'Dart consumer unknown-bearer protected route captured state.',
      );
    } finally {
      unknownBearerSecureClient.close(force: true);
    }
    _expect(
      secureClient.sessionId == secureSessionId &&
          secureClient.lastEventId == secureLastEventId,
      'Dart consumer protected Streamable auth rejection changed valid session state.',
    );

    final secureActiveDirectTopicDescription =
        await secureClient.describeWampApiDirect(
      _secureTopic,
      id: 'dart-consumer-secure-active-direct-topic-describe',
      kind: 'topic',
    );
    _expect(
      jsonEncode(
        secureActiveDirectTopicDescription,
      ).contains('CLI Secure Smoke Events'),
      'Dart consumer protected active direct JSON topic describe missed metadata.',
    );
    _expect(
      secureClient.sessionId == secureSessionId &&
          secureClient.lastEventId == secureLastEventId,
      'Dart consumer protected active direct JSON topic describe changed Streamable state.',
    );

    final secureActiveDirectTemplates =
        await secureClient.listResourceTemplatesDirect(
      id: 'dart-consumer-secure-active-direct-templates',
    );
    _expect(
      _stringFields(
        secureActiveDirectTemplates.resourceTemplates,
        'uriTemplate',
      ).contains('cli://mcp/secure/task/{taskId}'),
      'Dart consumer protected active direct JSON templates missed secure task.',
    );

    final secureActiveDirectPrompts = await secureClient.listPromptsDirect(
      id: 'dart-consumer-secure-active-direct-prompts',
    );
    _expect(
      _stringFields(
        secureActiveDirectPrompts.prompts,
        'name',
      ).contains('summarize-secure-cli-context'),
      'Dart consumer protected active direct JSON prompts missed secure prompt.',
    );
    final secureActiveDirectPrompt = await secureClient.getPromptDirect(
      'summarize-secure-cli-context',
      id: 'dart-consumer-secure-active-direct-prompt-get',
      arguments: const <String, String>{
        'topic': 'active direct prompt readiness',
      },
    );
    _expect(
      jsonEncode(
        secureActiveDirectPrompt,
      ).contains('active direct prompt readiness'),
      'Dart consumer protected active direct JSON prompt missed substitution.',
    );
    _expect(
      secureClient.sessionId == secureSessionId &&
          secureClient.lastEventId == secureLastEventId,
      'Dart consumer protected active direct JSON resource/prompt helpers changed Streamable state.',
    );
    await _expectNotificationPubSub(
      secureClient,
      subscription.handle,
      topic: _secureTopic,
      marker: 'dart-consumer-secure-active-direct-notification',
      idPrefix: 'dart-consumer-secure-active-direct-notification-poll',
      label: 'Dart consumer protected active direct JSON pub/sub',
      directJson: true,
    );

    final secureStreamableContents = await secureClient.readResource(
      'cli://mcp/secure/context',
      id: 'dart-consumer-secure-streamable-resource-read',
    );
    _expect(
      jsonEncode(
        secureStreamableContents,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected Streamable resource read missed content.',
    );
    final secureStreamableResources = await secureClient.listResources(
      id: 'dart-consumer-secure-streamable-resources',
    );
    _expect(
      _stringFields(
        secureStreamableResources.resources,
        'uri',
      ).contains('cli://mcp/secure/context'),
      'Dart consumer protected Streamable resources missed context.',
    );
    final secureStreamableTemplates =
        await secureClient.listResourceTemplates(
      id: 'dart-consumer-secure-streamable-templates',
    );
    _expect(
      _stringFields(
        secureStreamableTemplates.resourceTemplates,
        'uriTemplate',
      ).contains('cli://mcp/secure/task/{taskId}'),
      'Dart consumer protected Streamable templates missed secure task.',
    );
    final secureStreamablePrompts = await secureClient.listPrompts(
      id: 'dart-consumer-secure-streamable-prompts',
    );
    _expect(
      _stringFields(
        secureStreamablePrompts.prompts,
        'name',
      ).contains('summarize-secure-cli-context'),
      'Dart consumer protected Streamable prompts missed secure prompt.',
    );
    final secureStreamablePrompt = await secureClient.getPrompt(
      'summarize-secure-cli-context',
      id: 'dart-consumer-secure-streamable-prompt-get',
      arguments: const <String, String>{
        'topic': 'protected Streamable prompt readiness',
      },
    );
    _expect(
      jsonEncode(
        secureStreamablePrompt,
      ).contains('protected Streamable prompt readiness'),
      'Dart consumer protected Streamable prompt missed substitution.',
    );
    _expect(
      secureClient.sessionId == secureSessionId &&
          secureClient.lastEventId != null &&
          secureClient.lastEventId!.startsWith('$secureSessionId:'),
      'Dart consumer protected Streamable resource/prompt helpers lost SSE state.',
    );

    final secureBatchSessionId = secureClient.sessionId;
    final secureBatchLastEventId = secureClient.lastEventId;
    final secureStreamableBatch = await secureClient.postBatch(
      <McpJsonMap>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-streamable-batch-resource-read',
          'method': 'resources/read',
          'params': <String, Object?>{'uri': 'cli://mcp/secure/context'},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-streamable-batch-bad-method',
          'method': 'tools/unknown',
          'params': <String, Object?>{},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'dart-consumer-secure-streamable-batch-tools',
          'method': 'tools/list',
          'params': <String, Object?>{},
        },
        <String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
          'params': <String, Object?>{},
        },
      ],
    );
    _expect(
      secureStreamableBatch?.length == 3,
      'Dart consumer protected Streamable batch response count changed.',
    );
    final secureStreamableBatchResource = _batchResult(
      secureStreamableBatch,
      'dart-consumer-secure-streamable-batch-resource-read',
      'Dart consumer protected Streamable batch resource read',
    );
    _expect(
      jsonEncode(
        secureStreamableBatchResource,
      ).contains('Router CLI secure MCP context.'),
      'Dart consumer protected Streamable batch resource missed content.',
    );
    final secureStreamableBatchError = _batchError(
      secureStreamableBatch,
      'dart-consumer-secure-streamable-batch-bad-method',
      'Dart consumer protected Streamable batch bad method',
    );
    _expect(
      secureStreamableBatchError['code'] == McpErrorCodes.methodNotFound,
      'Dart consumer protected Streamable batch missed method error isolation.',
    );
    final secureStreamableBatchTools = _batchResult(
      secureStreamableBatch,
      'dart-consumer-secure-streamable-batch-tools',
      'Dart consumer protected Streamable batch tools list',
    );
    _expect(
      jsonEncode(
        secureStreamableBatchTools,
      ).contains('connectanum.pubsub.publish'),
      'Dart consumer protected Streamable batch missed pubsub tool.',
    );
    _expect(
      secureClient.sessionId == secureBatchSessionId,
      'Dart consumer protected Streamable batch changed session id.',
    );
    final secureBatchNextEventId = secureClient.lastEventId;
    _expect(
      secureBatchSessionId != null &&
          secureBatchNextEventId != null &&
          secureBatchNextEventId != secureBatchLastEventId &&
          secureBatchNextEventId.startsWith('$secureBatchSessionId:'),
      'Dart consumer protected Streamable batch did not advance SSE state.',
    );
    await _expectInvalidLastEventIdRejectedWithoutSessionLoss(
      secureClient,
      sessionId: secureBatchSessionId as String,
      eventId: secureBatchNextEventId as String,
      label: 'Dart consumer protected Streamable invalid Last-Event-ID',
    );
    await _expectEmptyLastEventIdStartsFreshPoll(
      secureClient,
      sessionId: secureBatchSessionId,
      eventId: secureClient.lastEventId,
      label: 'Dart consumer protected Streamable empty Last-Event-ID',
    );

    final secureStreamableTools = await secureClient.listTools(
      id: 'dart-consumer-secure-streamable-tools',
    );
    _expect(
      _stringFields(
        secureStreamableTools.tools,
        'name',
      ).contains('connectanum.pubsub.publish'),
      'Dart consumer missed protected Streamable pubsub tool.',
    );
    await _expectRawDirectJsonStaleSessionIgnored(
      secureEndpoint,
      secureClient,
      id: 'dart-consumer-secure-direct-json-stale-session',
      label: 'Dart consumer protected direct JSON stale MCP-Session-Id',
      bearerToken: grant.accessToken,
    );

    final secureStreamableMetaLastEventId = secureClient.lastEventId;
    final secureStreamableProcedureCatalog = await secureClient.listWampApi(
      id: 'dart-consumer-secure-streamable-procedure-catalog',
      kind: 'procedure',
    );
    _expect(
      jsonEncode(secureStreamableProcedureCatalog).contains(_secureProcedure),
      'Dart consumer missed protected Streamable procedure catalog.',
    );
    final secureStreamableProcedureDescription =
        await secureClient.describeWampApi(
      _secureProcedure,
      id: 'dart-consumer-secure-streamable-procedure-describe',
      kind: 'procedure',
    );
    _expect(
      jsonEncode(
        secureStreamableProcedureDescription,
      ).contains('CLI Secure Lookup'),
      'Dart consumer missed protected Streamable procedure metadata.',
    );
    final secureStreamableTopicDescription = await secureClient.describeWampApi(
      _secureTopic,
      id: 'dart-consumer-secure-streamable-topic-describe',
      kind: 'topic',
    );
    _expect(
      jsonEncode(
        secureStreamableTopicDescription,
      ).contains('CLI Secure Smoke Events'),
      'Dart consumer missed protected Streamable topic metadata.',
    );
    final secureStreamableMetaNextEventId = secureClient.lastEventId;
    _expect(
      secureClient.sessionId == secureBatchSessionId &&
          secureStreamableMetaNextEventId != null &&
          secureStreamableMetaNextEventId.startsWith('$secureBatchSessionId:') &&
          secureStreamableMetaNextEventId != secureStreamableMetaLastEventId,
      'Dart consumer protected Streamable WAMP metadata lost SSE state.',
    );

    final publication = await secureClient.publishWampEvent(
      _secureTopic,
      id: 'dart-consumer-secure-streamable-publish',
      argumentsKeywords: const <String, Object?>{
        'via': 'dart-consumer-streamable',
      },
      acknowledge: true,
    );
    _expect(
      publication.topic == _secureTopic && publication.acknowledged,
      'Dart consumer protected Streamable pubsub publish was invalid.',
    );

    final events = await _pollUntilEvent(
      secureClient,
      subscription.handle,
    );
    _expect(
      jsonEncode(events.events).contains('dart-consumer-streamable'),
      'Dart consumer protected direct JSON poll missed Streamable event.',
    );

    final unsubscribe = await secureClient.unsubscribeWampTopicDirect(
      subscription.handle,
      id: 'dart-consumer-secure-unsubscribe',
    );
    _expect(
      unsubscribe.unsubscribed,
      'Dart consumer protected direct JSON unsubscribe was invalid.',
    );
    final deletedSecureSessionId = secureClient.sessionId;
    final deletedSecureLastEventId = secureClient.lastEventId;
    _expect(
      deletedSecureSessionId != null && deletedSecureLastEventId != null,
      'Dart consumer protected Streamable delete missed active session state.',
    );
    final staleSecureSessionId = deletedSecureSessionId!;
    final staleSecureLastEventId = deletedSecureLastEventId!;
    await secureClient.deleteSession();
    _expect(
      secureClient.sessionId == null && secureClient.lastEventId == null,
      'Dart consumer protected Streamable delete leaked state.',
    );
    await _assertDeletedStreamableSessionRejectedAcrossMethods(
      secureEndpoint,
      grant,
      sessionId: staleSecureSessionId,
      lastEventId: staleSecureLastEventId,
      idPrefix: 'dart-consumer-secure-deleted-session',
      label: 'Dart consumer protected deleted Streamable session',
    );

    final refreshedGrant = await authClient.refreshToken(originalRefreshToken);
    _expect(
      refreshedGrant.accessToken.isNotEmpty,
      'Dart consumer refresh returned an empty access token.',
    );
    _expect(
      refreshedGrant.accessToken != grant.accessToken,
      'Dart consumer refresh reused the original access token.',
    );
    _expect(
      refreshedGrant.tokenType == 'Bearer',
      'Dart consumer refresh did not return a Bearer grant.',
    );
    _expect(
      refreshedGrant.realm == grant.realm &&
          refreshedGrant.authId == grant.authId &&
          refreshedGrant.authRole == grant.authRole &&
          refreshedGrant.authMethod == grant.authMethod &&
          refreshedGrant.authProvider == grant.authProvider,
      'Dart consumer refresh changed the authenticated principal.',
    );
    final refreshedRefreshToken = refreshedGrant.refreshToken;
    if (refreshedRefreshToken == null || refreshedRefreshToken.isEmpty) {
      throw StateError('Dart consumer refresh missed a refresh token.');
    }

    final refreshedClient = McpStreamableHttpClient.withAuthGrant(
      secureEndpoint,
      refreshedGrant,
    );
    final refreshedJsonClient = McpStreamableHttpClient.withAuthGrant(
      secureJsonEndpoint,
      refreshedGrant,
    );
    try {
      final refreshedJsonTools = await refreshedJsonClient.listToolsDirect(
        id: 'dart-consumer-refreshed-json-response-tools',
      );
      _expect(
        _stringFields(
          refreshedJsonTools.tools,
          'name',
        ).contains('connectanum.pubsub.publish'),
        'Dart consumer refreshed grant missed JSON-response direct JSON tools.',
      );

      final refreshedJsonInitialize = await refreshedJsonClient.initialize(
        id: 'dart-consumer-refreshed-json-response-initialize',
        protocolVersion: _protocolVersion,
        clientInfo: const <String, Object?>{
          'name': 'router-cli-dart-consumer-smoke-refreshed-json-response',
          'version': '0.0.0',
        },
      );
      _expect(
        _resultFrom(
          refreshedJsonInitialize,
          'refreshed JSON-response initialize',
        )['protocolVersion'] == _protocolVersion,
        'Dart consumer refreshed JSON-response initialize changed protocol.',
      );
      await refreshedJsonClient.notifyInitialized();
      final refreshedJsonStreamableTools = await refreshedJsonClient.listTools(
        id: 'dart-consumer-refreshed-json-response-streamable-tools',
      );
      _expect(
        _stringFields(
          refreshedJsonStreamableTools.tools,
          'name',
        ).contains('connectanum.pubsub.publish'),
        'Dart consumer refreshed grant missed JSON-response Streamable tools.',
      );
      await refreshedJsonClient.deleteSession();
      _expect(
        refreshedJsonClient.sessionId == null &&
            refreshedJsonClient.lastEventId == null,
        'Dart consumer refreshed JSON-response delete leaked state.',
      );

      final refreshedTools = await refreshedClient.listToolsDirect(
        id: 'dart-consumer-refreshed-secure-tools',
      );
      _expect(
        _stringFields(
          refreshedTools.tools,
          'name',
        ).contains('connectanum.pubsub.publish'),
        'Dart consumer refreshed grant missed protected direct JSON tools.',
      );

      final refreshedInitialize = await refreshedClient.initialize(
        id: 'dart-consumer-refreshed-secure-initialize',
        protocolVersion: _protocolVersion,
        clientInfo: const <String, Object?>{
          'name': 'router-cli-dart-consumer-smoke-refreshed',
          'version': '0.0.0',
        },
      );
      _expect(
        _resultFrom(
          refreshedInitialize,
          'refreshed secure initialize',
        )['protocolVersion'] == _protocolVersion,
        'Dart consumer refreshed Streamable initialize changed protocol.',
      );
      await refreshedClient.notifyInitialized();
      final refreshedStreamableTools = await refreshedClient.listTools(
        id: 'dart-consumer-refreshed-streamable-tools',
      );
      _expect(
        _stringFields(
          refreshedStreamableTools.tools,
          'name',
        ).contains('connectanum.pubsub.publish'),
        'Dart consumer refreshed grant missed protected Streamable tools.',
      );
      await refreshedClient.deleteSession();
      _expect(
        refreshedClient.sessionId == null && refreshedClient.lastEventId == null,
        'Dart consumer refreshed Streamable delete leaked state.',
      );

      await authClient.revokeToken(
        refreshedGrant.accessToken,
        tokenTypeHint: 'access_token',
      );
      await _expectMcpHttpRejected(
        () => refreshedJsonClient.listToolsDirect(
          id: 'dart-consumer-revoked-json-response-tools',
        ),
        HttpStatus.unauthorized,
        'Dart consumer revoked access token JSON-response direct JSON request',
      );
      await _expectMcpHttpRejected(
        () => refreshedClient.listToolsDirect(
          id: 'dart-consumer-revoked-access-tools',
        ),
        HttpStatus.unauthorized,
        'Dart consumer revoked access token direct JSON request',
      );

      await authClient.revokeToken(
        refreshedRefreshToken,
        tokenTypeHint: 'refresh_token',
      );
      await _expectAuthRejected(
        () => authClient.refreshToken(refreshedRefreshToken),
        HttpStatus.unauthorized,
        'Dart consumer revoked refresh token request',
      );
    } finally {
      refreshedJsonClient.close(force: true);
      refreshedClient.close(force: true);
    }

    print(jsonEncode(<String, Object?>{
      'routerCliConsumerSummary': <String, Object?>{
        'public': <String, Object?>{
          'directJson': true,
          'streamable': true,
          'streamableInvalidLastEventId': true,
          'streamableEmptyLastEventId': true,
          'directJsonStaleSessionId': true,
          'streamableSessionDelete': true,
          'resourcesPrompts': true,
          'wampMeta': true,
          'pubsub': true,
          'pubsubNotifications': true,
          'sessionProxy': true,
          'batch': true,
        },
        'secure': <String, Object?>{
          'ticketGrant': true,
          'directJson': true,
          'streamable': true,
          'streamableInvalidLastEventId': true,
          'streamableEmptyLastEventId': true,
          'directJsonStaleSessionId': true,
          'streamableSessionDelete': true,
          'deletedSessionRejected': true,
          'deletedSessionMatrix': true,
          'resourcesPrompts': true,
          'pubsub': true,
          'pubsubNotifications': true,
          'wampMeta': true,
          'batch': true,
          'authRejectionIsolation': true,
          'refreshAndRevoke': true,
        },
        'jsonResponse': <String, Object?>{
          'active': <String, Object?>{
            'directJson': true,
            'directJsonStaleSessionId': true,
            'streamable': true,
            'streamableInvalidLastEventId': true,
            'streamableEmptyLastEventId': true,
            'streamableSessionDelete': true,
            'resourcesPrompts': true,
            'wampMeta': true,
            'registrationMeta': true,
            'configuredRegistrationMeta': true,
            'sessionMeta': true,
            'subscriptionMeta': true,
            'configuredSubscriptionMeta': true,
            'pubsub': true,
            'pubsubNotifications': true,
            'batch': true,
            'authRejectionIsolation': true,
            'refreshAndRevoke': true,
          },
          'tokenOnly': <String, Object?>{
            'directJson': true,
            'directJsonStaleSessionId': true,
            'streamable': true,
            'streamableInvalidLastEventId': true,
            'streamableEmptyLastEventId': true,
            'streamableSessionDelete': true,
            'resourcesPrompts': true,
            'wampMeta': true,
            'registrationMeta': true,
            'configuredRegistrationMeta': true,
            'sessionMeta': true,
            'subscriptionMeta': true,
            'configuredSubscriptionMeta': true,
            'pubsub': true,
            'pubsubNotifications': true,
            'batch': true,
          },
        },
        'tokenOnly': <String, Object?>{
          'directJson': true,
          'streamable': true,
          'streamableInvalidLastEventId': true,
          'streamableEmptyLastEventId': true,
          'streamableSessionDelete': true,
          'resourcesPrompts': true,
          'wampMeta': true,
          'registrationMeta': true,
          'configuredRegistrationMeta': true,
          'sessionMeta': true,
          'subscriptionMeta': true,
          'configuredSubscriptionMeta': true,
          'pubsub': true,
          'pubsubNotifications': true,
          'batch': true,
        },
      },
    }));
  } finally {
    secureJsonClient?.close(force: true);
    secureClient?.close(force: true);
    authClient.close(force: true);
    publicClient.close(force: true);
  }
}

Future<void> _expectSessionProxyRoute({
  required Uri endpoint,
}) async {
  final httpClient = HttpClient();
  try {
    final uri = endpoint.replace(queryParameters: const <String, String>{
      'source': 'dart-consumer',
    });
    final getRequest = await httpClient.getUrl(uri);
    getRequest.headers.set(HttpHeaders.acceptHeader, 'text/plain');
    getRequest.headers.set('x-consumer-trace', 'dart-session-proxy');
    final getResponse = await getRequest.close().timeout(
      const Duration(seconds: 5),
    );
    final getBody = await utf8.decoder
        .bind(getResponse)
        .join()
        .timeout(const Duration(seconds: 5));
    _expect(
      getResponse.statusCode == HttpStatus.ok,
      'Dart consumer session_proxy GET returned '
      '${getResponse.statusCode}: $getBody',
    );
    _expect(
      getBody == 'ok',
      'Dart consumer session_proxy GET returned unexpected body $getBody.',
    );
    final contentType =
        getResponse.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    _expect(
      contentType.startsWith('text/plain'),
      'Dart consumer session_proxy GET missed text/plain content type.',
    );

    final headRequest = await httpClient.headUrl(uri);
    headRequest.headers.set(HttpHeaders.acceptHeader, 'text/plain');
    headRequest.headers.set('x-consumer-trace', 'dart-session-proxy-head');
    final headResponse = await headRequest.close().timeout(
      const Duration(seconds: 5),
    );
    final headBody = await utf8.decoder
        .bind(headResponse)
        .join()
        .timeout(const Duration(seconds: 5));
    _expect(
      headResponse.statusCode == HttpStatus.ok,
      'Dart consumer session_proxy HEAD returned '
      '${headResponse.statusCode}: $headBody',
    );
    _expect(
      headBody.isEmpty,
      'Dart consumer session_proxy HEAD returned a response body.',
    );
  } finally {
    httpClient.close(force: true);
  }
}

Future<int> _expectWampSessionMeta(
  McpStreamableHttpClient client, {
  required String idPrefix,
  required String label,
  required String expectedAuthId,
  required String expectedAuthRole,
  required bool directJson,
  required bool expectSseCursor,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final sessionCount = await client.countWampSessions(
    id: '$idPrefix-wamp-session-count',
    directJson: directJson,
  );
  _expect(
    sessionCount.procedure == 'wamp.session.count',
    '$label returned ${sessionCount.procedure} for session count.',
  );
  final count = _metaCount(sessionCount, '$label session count');
  _expect(count >= 1, '$label returned an empty session count.');

  final sessions = await client.listWampSessions(
    id: '$idPrefix-wamp-session-list',
    directJson: directJson,
  );
  _expect(
    sessions.procedure == 'wamp.session.list',
    '$label returned ${sessions.procedure} for session list.',
  );
  final sessionIds = _integerMetaIds(
    sessions.argumentsKeywords['session_ids'],
    '$label session list',
  );
  _expect(sessionIds.isNotEmpty, '$label returned an empty session list.');
  final visibleSessionId = sessionIds.first;

  final session = await client.getWampSession(
    visibleSessionId,
    id: '$idPrefix-wamp-session-get',
    directJson: directJson,
  );
  _expect(
    session.procedure == 'wamp.session.get',
    '$label returned ${session.procedure} for session get.',
  );
  final details = _jsonObjectFrom(
    session.argumentsKeywords['details'],
    '$label session details',
  );
  _expect(
    details['authid'] == expectedAuthId &&
        details['authrole'] == expectedAuthRole,
    '$label returned unexpected auth details: ${jsonEncode(details)}.',
  );
  final detailSessionId = details['session'] ?? details['id'];
  if (detailSessionId != null) {
    _expect(
      detailSessionId == visibleSessionId,
      '$label returned mismatched session details: ${jsonEncode(details)}.',
    );
  }

  _expectWampMetaState(
    client,
    previousSessionId: previousSessionId,
    previousEventId: previousEventId,
    label: label,
    directJson: directJson,
    expectSseCursor: expectSseCursor,
  );
  return visibleSessionId;
}

Future<int> _expectConfiguredWampRegistrationMeta(
  McpStreamableHttpClient client, {
  required String idPrefix,
  required String label,
  required String procedure,
  required bool directJson,
  required bool expectSseCursor,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final lookup = await client.lookupWampRegistration(
    procedure,
    id: '$idPrefix-wamp-registration-lookup',
    directJson: directJson,
  );
  _expect(
    lookup.procedure == 'wamp.registration.lookup',
    '$label returned ${lookup.procedure} for registration lookup.',
  );
  final lookupIds = _integerMetaIds(
    lookup.arguments,
    '$label registration lookup',
  );
  _expect(lookupIds.isNotEmpty, '$label returned an empty lookup result.');
  final registrationId = lookupIds.first;

  final match = await client.matchWampRegistration(
    procedure,
    id: '$idPrefix-wamp-registration-match',
    directJson: directJson,
  );
  _expect(
    match.procedure == 'wamp.registration.match',
    '$label returned ${match.procedure} for registration match.',
  );
  final matchedRegistrationId = _singleMetaId(
    match.arguments,
    '$label registration match',
  );
  _expect(
    matchedRegistrationId == registrationId,
    '$label registration match did not agree with lookup.',
  );

  final registrations = await client.listWampRegistrations(
    id: '$idPrefix-wamp-registration-list',
    directJson: directJson,
  );
  _expect(
    registrations.procedure == 'wamp.registration.list',
    '$label returned ${registrations.procedure} for registration list.',
  );
  final exactRegistrationIds = _integerMetaIds(
    registrations.argumentsKeywords['exact'],
    '$label registration list exact',
  );
  _expect(
    exactRegistrationIds.contains(registrationId),
    '$label registration list missed $procedure.',
  );

  final details = await client.getWampRegistration(
    registrationId,
    id: '$idPrefix-wamp-registration-get',
    directJson: directJson,
  );
  _expect(
    details.procedure == 'wamp.registration.get',
    '$label returned ${details.procedure} for registration get.',
  );
  _expect(
    jsonEncode(details.argumentsKeywords).contains(procedure),
    '$label registration details missed $procedure.',
  );

  final callees = await client.listWampRegistrationCallees(
    registrationId,
    id: '$idPrefix-wamp-registration-callees',
    directJson: directJson,
  );
  _expect(
    callees.procedure == 'wamp.registration.list_callees',
    '$label returned ${callees.procedure} for registration callees.',
  );
  final calleeIds = _integerMetaIds(
    callees.arguments,
    '$label registration callees',
  );
  _expect(
    calleeIds.isEmpty,
    '$label leaked registration callees: ${jsonEncode(calleeIds)}.',
  );

  final calleeCount = await client.countWampRegistrationCallees(
    registrationId,
    id: '$idPrefix-wamp-registration-callee-count',
    directJson: directJson,
  );
  _expect(
    calleeCount.procedure == 'wamp.registration.count_callees',
    '$label returned ${calleeCount.procedure} for registration callee count.',
  );
  _expect(
    _metaCount(calleeCount, '$label registration callee count') == 0,
    '$label registration callee count leaked internal sessions.',
  );

  _expectWampMetaState(
    client,
    previousSessionId: previousSessionId,
    previousEventId: previousEventId,
    label: label,
    directJson: directJson,
    expectSseCursor: expectSseCursor,
  );
  return registrationId;
}

Future<void> _expectWampSubscriptionMeta(
  McpStreamableHttpClient client, {
  required String idPrefix,
  required String label,
  required String topic,
  required McpStreamableWampSubscriptionResult subscription,
  required String expectedAuthId,
  required String expectedAuthRole,
  required bool directJson,
  required bool expectSseCursor,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final rawSubscriptionId = subscription.subscriptionId;
  _expect(
    rawSubscriptionId != null && rawSubscriptionId > 0,
    '$label missed a subscription id.',
  );
  final subscriptionId = rawSubscriptionId!;
  final lookup = await client.lookupWampSubscription(
    topic,
    id: '$idPrefix-wamp-subscription-lookup',
    directJson: directJson,
  );
  _expect(
    _integerMetaIds(lookup.arguments, '$label subscription lookup')
        .contains(subscriptionId),
    '$label subscription lookup missed $topic.',
  );

  final match = await client.matchWampSubscription(
    topic,
    id: '$idPrefix-wamp-subscription-match',
    directJson: directJson,
  );
  _expect(
    _integerMetaIds(match.arguments, '$label subscription match')
        .contains(subscriptionId),
    '$label subscription match missed $topic.',
  );

  final subscriptions = await client.listWampSubscriptions(
    id: '$idPrefix-wamp-subscription-list',
    directJson: directJson,
  );
  _expect(
    _integerMetaIds(
      subscriptions.argumentsKeywords['exact'],
      '$label subscription list exact',
    ).contains(subscriptionId),
    '$label subscription list missed $topic.',
  );

  final details = await client.getWampSubscription(
    subscriptionId,
    id: '$idPrefix-wamp-subscription-get',
    directJson: directJson,
  );
  _expect(
    jsonEncode(details.argumentsKeywords).contains(topic),
    '$label subscription details missed $topic.',
  );

  final subscribers = await client.listWampSubscriptionSubscribers(
    subscriptionId,
    id: '$idPrefix-wamp-subscription-subscribers',
    directJson: directJson,
  );
  final subscriberIds = _integerMetaIds(
    subscribers.arguments,
    '$label subscription subscribers',
  );
  _expect(
    subscriberIds.isNotEmpty,
    '$label returned an empty subscription subscriber list.',
  );

  final subscriberCount = await client.countWampSubscriptionSubscribers(
    subscriptionId,
    id: '$idPrefix-wamp-subscription-subscriber-count',
    directJson: directJson,
  );
  _expect(
    _metaCount(subscriberCount, '$label subscription subscriber count') ==
        subscriberIds.length,
    '$label subscription subscriber count did not match visible sessions.',
  );

  for (final subscriberId in subscriberIds) {
    final subscriber = await client.getWampSession(
      subscriberId,
      id: '$idPrefix-wamp-subscription-subscriber-$subscriberId-get',
      directJson: directJson,
    );
    final subscriberDetails = _jsonObjectFrom(
      subscriber.argumentsKeywords['details'],
      '$label subscriber session details',
    );
    _expect(
      subscriberDetails['authid'] == expectedAuthId &&
          subscriberDetails['authrole'] == expectedAuthRole,
      '$label subscriber returned unexpected auth details: '
      '${jsonEncode(subscriberDetails)}.',
    );
  }

  _expectWampMetaState(
    client,
    previousSessionId: previousSessionId,
    previousEventId: previousEventId,
    label: label,
    directJson: directJson,
    expectSseCursor: expectSseCursor,
  );
}

Future<int> _expectConfiguredWampSubscriptionMeta(
  McpStreamableHttpClient client, {
  required String idPrefix,
  required String label,
  required String topic,
  required bool directJson,
  required bool expectSseCursor,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final lookup = await client.lookupWampSubscription(
    topic,
    id: '$idPrefix-wamp-configured-subscription-lookup',
    directJson: directJson,
  );
  _expect(
    lookup.procedure == 'wamp.subscription.lookup',
    '$label returned ${lookup.procedure} for subscription lookup.',
  );
  final lookupIds = _integerMetaIds(
    lookup.arguments,
    '$label subscription lookup',
  );
  _expect(lookupIds.isNotEmpty, '$label returned an empty lookup result.');
  final subscriptionId = lookupIds.first;

  final match = await client.matchWampSubscription(
    topic,
    id: '$idPrefix-wamp-configured-subscription-match',
    directJson: directJson,
  );
  _expect(
    match.procedure == 'wamp.subscription.match',
    '$label returned ${match.procedure} for subscription match.',
  );
  _expect(
    _integerMetaIds(match.arguments, '$label subscription match').contains(
      subscriptionId,
    ),
    '$label subscription match did not include lookup id.',
  );

  final subscriptions = await client.listWampSubscriptions(
    id: '$idPrefix-wamp-configured-subscription-list',
    directJson: directJson,
  );
  _expect(
    subscriptions.procedure == 'wamp.subscription.list',
    '$label returned ${subscriptions.procedure} for subscription list.',
  );
  final exactSubscriptionIds = _integerMetaIds(
    subscriptions.argumentsKeywords['exact'],
    '$label subscription list exact',
  );
  _expect(
    exactSubscriptionIds.contains(subscriptionId),
    '$label subscription list missed $topic.',
  );

  final details = await client.getWampSubscription(
    subscriptionId,
    id: '$idPrefix-wamp-configured-subscription-get',
    directJson: directJson,
  );
  _expect(
    details.procedure == 'wamp.subscription.get',
    '$label returned ${details.procedure} for subscription get.',
  );
  _expect(
    jsonEncode(details.argumentsKeywords).contains(topic),
    '$label subscription details missed $topic.',
  );

  final subscribers = await client.listWampSubscriptionSubscribers(
    subscriptionId,
    id: '$idPrefix-wamp-configured-subscription-subscribers',
    directJson: directJson,
  );
  _expect(
    subscribers.procedure == 'wamp.subscription.list_subscribers',
    '$label returned ${subscribers.procedure} for subscription subscribers.',
  );
  final subscriberIds = _integerMetaIds(
    subscribers.arguments,
    '$label subscription subscribers',
  );
  _expect(
    subscriberIds.isEmpty,
    '$label leaked configured subscription subscribers: '
    '${jsonEncode(subscriberIds)}.',
  );

  final subscriberCount = await client.countWampSubscriptionSubscribers(
    subscriptionId,
    id: '$idPrefix-wamp-configured-subscription-subscriber-count',
    directJson: directJson,
  );
  _expect(
    subscriberCount.procedure == 'wamp.subscription.count_subscribers',
    '$label returned ${subscriberCount.procedure} for subscriber count.',
  );
  _expect(
    _metaCount(subscriberCount, '$label subscription subscriber count') == 0,
    '$label configured subscription subscriber count was not zero.',
  );

  _expectWampMetaState(
    client,
    previousSessionId: previousSessionId,
    previousEventId: previousEventId,
    label: label,
    directJson: directJson,
    expectSseCursor: expectSseCursor,
  );
  return subscriptionId;
}

Future<McpStreamableWampEventBatch> _pollUntilEvent(
  McpStreamableHttpClient client,
  String handle, {
  String marker = 'dart-consumer-streamable',
  String idPrefix = 'dart-consumer-secure-poll',
  bool directJson = true,
}) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    final events = directJson
        ? await client.pollWampEventsDirect(
            handle,
            id: '$idPrefix-$attempt',
            limit: 10,
          )
        : await client.pollWampEvents(
            handle,
            id: '$idPrefix-$attempt',
            limit: 10,
          );
    if (jsonEncode(events.events).contains(marker)) {
      return events;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'Timed out waiting for Dart consumer protected Streamable pubsub event.',
  );
}

Future<void> _expectNotificationPubSub(
  McpStreamableHttpClient client,
  String handle, {
  required String topic,
  required String marker,
  required String idPrefix,
  required String label,
  required bool directJson,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final event = <String, Object?>{'via': marker};
  if (directJson) {
    await client.notifyWampEventDirect(topic, argumentsKeywords: event);
  } else {
    await client.notifyWampEvent(topic, argumentsKeywords: event);
  }
  final events = await _pollUntilEvent(
    client,
    handle,
    marker: marker,
    idPrefix: idPrefix,
    directJson: directJson,
  );
  _expect(
    jsonEncode(events.events).contains(marker),
    '$label notification-only pub/sub did not deliver an event.',
  );
  if (directJson) {
    _expect(
      client.sessionId == previousSessionId &&
          client.lastEventId == previousEventId,
      '$label direct JSON notification-only pub/sub changed Streamable state.',
    );
  }
}

Future<void> _expectMcpHttpRejected(
  Future<Object?> Function() operation,
  int statusCode,
  String label,
) async {
  try {
    await operation();
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode == statusCode) {
      return;
    }
    throw StateError(
      '$label returned ${error.statusCode}, expected $statusCode.',
    );
  }
  throw StateError('$label was accepted.');
}

Future<void> _expectRawDirectJsonStaleSessionIgnored(
  Uri endpoint,
  McpStreamableHttpClient streamableClient, {
  required String id,
  required String label,
  String? bearerToken,
}) async {
  final previousSessionId = streamableClient.sessionId;
  final previousEventId = streamableClient.lastEventId;
  _expect(
    previousSessionId != null && previousSessionId.isNotEmpty,
    '$label requires an active Streamable session.',
  );

  final payload = utf8.encode(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/list',
      'params': <String, Object?>{},
    }),
  );
  final httpClient = HttpClient();
  try {
    final request = await httpClient.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('MCP-Protocol-Version', _protocolVersion);
    request.headers.set('MCP-Session-Id', '$id-stale');
    request.headers.set('x-consumer-trace', id);
    if (bearerToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $bearerToken',
      );
    }
    request.contentLength = payload.length;
    request.add(payload);

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    _expect(
      response.statusCode == HttpStatus.ok,
      '$label returned ${response.statusCode}: $body',
    );
    _expect(
      response.headers.value('MCP-Session-Id') == null,
      '$label echoed a Streamable session id.',
    );
    final responsePayload = _jsonObjectFrom(jsonDecode(body), label);
    _expect(
      responsePayload['id'] == id && responsePayload['result'] is Map,
      '$label missed a direct JSON result: $body',
    );
    _expect(
      streamableClient.sessionId == previousSessionId &&
          streamableClient.lastEventId == previousEventId,
      '$label changed typed Streamable client state.',
    );
  } finally {
    httpClient.close(force: true);
  }
}

Future<void> _expectInvalidLastEventIdRejectedWithoutSessionLoss(
  McpStreamableHttpClient client, {
  required String sessionId,
  required String? eventId,
  required String label,
}) async {
  try {
    await client.poll(lastEventId: '$sessionId:missing:1');
    throw StateError('$label was accepted.');
  } on McpStreamableHttpException catch (error) {
    _expect(
      error.statusCode == HttpStatus.badRequest,
      '$label returned ${error.statusCode}, expected ${HttpStatus.badRequest}.',
    );
    _expect(
      error.body.contains('Last-Event-ID'),
      '$label rejection did not name Last-Event-ID.',
    );
  }
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    '$label changed active Streamable state.',
  );
}

Future<void> _expectEmptyLastEventIdStartsFreshPoll(
  McpStreamableHttpClient client, {
  required String sessionId,
  required String? eventId,
  required String label,
}) async {
  final events = await client.poll(lastEventId: '');
  _expect(events.isNotEmpty, '$label did not return SSE events.');
  final nextEventId = client.lastEventId;
  _expect(
    client.sessionId == sessionId &&
        nextEventId != null &&
        nextEventId.isNotEmpty,
    '$label lost active Streamable state.',
  );
  _expect(
    eventId == null || nextEventId != eventId,
    '$label reused the previous SSE cursor.',
  );
}

Future<void> _assertDeletedStreamableSessionRejectedAcrossMethods(
  Uri endpoint,
  ConnectanumHttpAuthGrant grant, {
  required String sessionId,
  String? lastEventId,
  required String idPrefix,
  required String label,
}) async {
  final client = McpStreamableHttpClient.withAuthGrant(endpoint, grant);
  try {
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.postBatch(<McpJsonMap>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': '$idPrefix-batch-tools',
            'method': 'tools/list',
            'params': <String, Object?>{},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': '$idPrefix-batch-resources',
            'method': 'resources/list',
            'params': <String, Object?>{},
          },
        ]);
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label batch tools/resources',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.postBatch(<McpJsonMap>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': '$idPrefix-batch-api-list',
            'method': 'tools/call',
            'params': <String, Object?>{
              'name': 'connectanum.api.list',
              'arguments': <String, Object?>{'kind': 'topic'},
            },
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': '$idPrefix-batch-pubsub-subscribe',
            'method': 'tools/call',
            'params': <String, Object?>{
              'name': 'connectanum.pubsub.subscribe',
              'arguments': <String, Object?>{
                'topic': _secureTopic,
                'queueLimit': 1,
              },
            },
          },
        ]);
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label batch WAMP meta/pubsub',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.notifyInitialized();
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label notification',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.listTools(id: '$idPrefix-tools');
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label tools/list',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.callTool(
          _secureProcedure,
          id: '$idPrefix-tool-call',
          arguments: <String, Object?>{'taskId': 'T-$idPrefix-tool-call'},
        );
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label tools/call',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.listResources(id: '$idPrefix-resources');
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label resources/list',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.readResource(
          'cli://mcp/secure/context',
          id: '$idPrefix-resource-read',
        );
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label resources/read',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.listResourceTemplates(
          id: '$idPrefix-resource-templates',
        );
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label resources/templates/list',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.listPrompts(id: '$idPrefix-prompts');
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label prompts/list',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.getPrompt(
          'summarize-secure-cli-context',
          id: '$idPrefix-prompt-get',
          arguments: <String, String>{
            'topic': 'deleted session replay readiness',
          },
        );
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label prompts/get',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.poll();
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label poll',
    );
    await _assertDeletedStreamableSessionRejectedWithState(
      client,
      () async {
        await client.deleteSession();
      },
      sessionId: sessionId,
      lastEventId: lastEventId,
      label: '$label delete',
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _assertDeletedStreamableSessionRejectedWithState(
  McpStreamableHttpClient client,
  Future<void> Function() operation, {
  required String sessionId,
  String? lastEventId,
  required String label,
}) async {
  client.sessionId = sessionId;
  client.lastEventId = lastEventId;
  await _expectMcpHttpRejected(
    () async {
      await operation();
      return null;
    },
    HttpStatus.notFound,
    label,
  );
  _expect(
    client.sessionId == null && client.lastEventId == null,
    '$label kept stale Streamable state.',
  );
}

Future<void> _expectAuthRejected(
  Future<Object?> Function() operation,
  int statusCode,
  String label,
) async {
  try {
    await operation();
  } on ConnectanumHttpAuthException catch (error) {
    if (error.statusCode == statusCode) {
      return;
    }
    throw StateError(
      '$label returned ${error.statusCode}, expected $statusCode.',
    );
  }
  throw StateError('$label was accepted.');
}

void _expectWampMetaState(
  McpStreamableHttpClient client, {
  required String? previousSessionId,
  required String? previousEventId,
  required String label,
  required bool directJson,
  required bool expectSseCursor,
}) {
  if (directJson) {
    _expect(
      client.sessionId == previousSessionId &&
          client.lastEventId == previousEventId,
      '$label changed Streamable state during direct JSON helper calls.',
    );
    return;
  }

  _expect(
    previousSessionId != null && client.sessionId == previousSessionId,
    '$label changed Streamable session id.',
  );
  if (expectSseCursor) {
    _expect(
      client.lastEventId != null &&
          client.lastEventId != previousEventId &&
          client.lastEventId!.startsWith('$previousSessionId:'),
      '$label did not advance the Streamable SSE cursor.',
    );
  } else {
    _expect(
      client.lastEventId == previousEventId,
      '$label unexpectedly captured a Streamable SSE cursor.',
    );
  }
}

int _metaCount(McpStreamableWampMetaCallResult result, String label) {
  final keywordCount = result.argumentsKeywords['count'];
  if (keywordCount != null) {
    return _integerFrom(keywordCount, label);
  }
  if (result.arguments.length == 1) {
    return _integerFrom(result.arguments.single, label);
  }
  throw StateError('$label returned ${jsonEncode(result.structuredContent)}.');
}

int _singleMetaId(Object? value, String label) {
  final ids = _integerMetaIds(value, label);
  _expect(ids.length == 1, '$label returned ${jsonEncode(value)}.');
  return ids.single;
}

int _integerFrom(Object? value, String label) {
  if (value is int) {
    return value;
  }
  if (value is num && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw StateError('$label returned non-integer value ${jsonEncode(value)}.');
}

List<int> _integerMetaIds(Object? value, String label) {
  if (value is! Iterable) {
    throw StateError('$label returned ${jsonEncode(value)}.');
  }
  final ids = <int>[];
  for (final item in value) {
    ids.add(_integerFrom(item, label));
  }
  return ids;
}

McpJsonMap _jsonObjectFrom(Object? value, String label) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw StateError('$label returned ${jsonEncode(value)}.');
}

Set<String> _stringFields(Iterable<McpJsonMap> values, String field) {
  final result = <String>{};
  for (final value in values) {
    final fieldValue = value[field];
    if (fieldValue is String) {
      result.add(fieldValue);
    }
  }
  return result;
}

McpJsonMap _resultFrom(McpJsonMap response, String label) {
  final result = response['result'];
  if (result is Map<String, Object?>) {
    return result;
  }
  if (result is Map) {
    return Map<String, Object?>.from(result);
  }
  throw StateError('$label missed a JSON-RPC result object.');
}

McpJsonMap _batchResponse(
  List<McpJsonMap>? responses,
  String id,
  String label,
) {
  if (responses == null) {
    throw StateError('$label missed batch response $id.');
  }
  for (final response in responses) {
    if (response['id'] == id) {
      return response;
    }
  }
  throw StateError('$label missed batch response $id.');
}

McpJsonMap _batchResult(
  List<McpJsonMap>? responses,
  String id,
  String label,
) {
  return _resultFrom(_batchResponse(responses, id, label), label);
}

McpJsonMap _batchError(
  List<McpJsonMap>? responses,
  String id,
  String label,
) {
  final error = _batchResponse(responses, id, label)['error'];
  if (error is Map<String, Object?>) {
    return error;
  }
  if (error is Map) {
    return Map<String, Object?>.from(error);
  }
  throw StateError('$label missed a JSON-RPC error object.');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
DART

  printf 'Running router CLI Dart MCP consumer package smoke from %s.\n' "$smoke_dir/dart-consumer"
  if ! dart_consumer_summary="$(
    set -e
    cd "$smoke_dir/dart-consumer"
    PUB_CACHE="$pub_cache" dart pub get >&2
    PUB_CACHE="$pub_cache" dart analyze >&2
    CONNECTANUM_NATIVE_LIB="$native_lib" MCP_PORT="$mcp_port" PUB_CACHE="$pub_cache" \
      dart run bin/main.dart
  )"; then
    printf 'Router CLI Dart consumer smoke failed. Router log follows.\n' >&2
    cat "$router_log" >&2
    _cleanup_router_cli_smoke 1
  fi
  printf '%s\n' "$dart_consumer_summary"
  assert_router_cli_consumer_package_summary "$dart_consumer_summary" \
    '"routerCliConsumerSummary"' \
    '"public":{"directJson":true,"streamable":true,"streamableInvalidLastEventId":true,"streamableEmptyLastEventId":true,"directJsonStaleSessionId":true,"streamableSessionDelete":true,"resourcesPrompts":true,"wampMeta":true,"pubsub":true,"pubsubNotifications":true,"sessionProxy":true,"batch":true}' \
    '"secure":{"ticketGrant":true,"directJson":true,"streamable":true,"streamableInvalidLastEventId":true,"streamableEmptyLastEventId":true,"directJsonStaleSessionId":true,"streamableSessionDelete":true,"deletedSessionRejected":true,"deletedSessionMatrix":true,"resourcesPrompts":true,"pubsub":true,"pubsubNotifications":true,"wampMeta":true,"batch":true,"authRejectionIsolation":true,"refreshAndRevoke":true}' \
    '"jsonResponse":{"active":{"directJson":true,"directJsonStaleSessionId":true,"streamable":true,"streamableInvalidLastEventId":true,"streamableEmptyLastEventId":true,"streamableSessionDelete":true,"resourcesPrompts":true,"wampMeta":true,"registrationMeta":true,"configuredRegistrationMeta":true,"sessionMeta":true,"subscriptionMeta":true,"configuredSubscriptionMeta":true,"pubsub":true,"pubsubNotifications":true,"batch":true,"authRejectionIsolation":true,"refreshAndRevoke":true},"tokenOnly":{"directJson":true,"directJsonStaleSessionId":true,"streamable":true,"streamableInvalidLastEventId":true,"streamableEmptyLastEventId":true,"streamableSessionDelete":true,"resourcesPrompts":true,"wampMeta":true,"registrationMeta":true,"configuredRegistrationMeta":true,"sessionMeta":true,"subscriptionMeta":true,"configuredSubscriptionMeta":true,"pubsub":true,"pubsubNotifications":true,"batch":true}}' \
    '"tokenOnly":{"directJson":true,"streamable":true,"streamableInvalidLastEventId":true,"streamableEmptyLastEventId":true,"streamableSessionDelete":true,"resourcesPrompts":true,"wampMeta":true,"registrationMeta":true,"configuredRegistrationMeta":true,"sessionMeta":true,"subscriptionMeta":true,"configuredSubscriptionMeta":true,"pubsub":true,"pubsubNotifications":true,"batch":true}'

  printf 'Router CLI consumer package smoke served GET/HEAD /healthz, /health, /metrics, a configured /assets file route with GET/HEAD/range/traversal coverage, a configured /proxy/healthz session_proxy route backed by the router internal metrics health service, a configured /php FastCGI route backed by a neutral upstream, a configured /upstream reverse_proxy route backed by a neutral upstream, /auth, /mcp, /mcp/secure, /mcp/secure-json-post, public raw JSON resources/resource templates/prompts/WAMP procedure and topic catalog/describe/pub-sub/notification pub-sub plus Streamable procedure and topic describe/pub-sub/invalid Last-Event-ID/empty Last-Event-ID/session delete/direct JSON stale session-id isolation, token-only protected clients, token-only protected JSON-response tool calls/resources/resource templates/prompts/WAMP procedure catalog/describe/registration/configured registration/session/subscription/configured subscription meta/pubsub/notification pubsub/batches/direct JSON stale session-id isolation plus Streamable procedure catalog/describe/topic describe/invalid Last-Event-ID/empty Last-Event-ID/session delete, token-only protected tool calls/resources/resource templates/prompts/WAMP registration/configured registration/session/subscription/configured subscription meta/notification pubsub/batches plus Streamable invalid Last-Event-ID/empty Last-Event-ID/session delete, token-only protected pub/sub, active protected JSON-response auth rejection/refresh-revoke/direct JSON stale session-id isolation, direct JSON procedure catalog/describe/topic/registration/configured registration/session/subscription/configured subscription/resource list pagination/read/resource template pagination/prompt pagination/pub-sub/notification pub-sub/batch isolation, and Streamable resource list pagination/read/resource template pagination/prompt pagination plus procedure/topic/registration/configured registration/session/subscription/configured subscription metadata/pub-sub/batch/invalid Last-Event-ID/empty Last-Event-ID/session delete, active protected auth rejection isolation, active protected direct JSON WAMP meta, resource/prompt, and notification pub-sub isolation, protected raw JSON resources/resource templates/prompts/WAMP procedure and topic describe/pub-sub/notification pub-sub/batches plus Streamable resources/resource templates/prompts/procedure and topic describe/pub-sub/batches/invalid Last-Event-ID/empty Last-Event-ID/session delete/direct JSON stale session-id isolation, protected pub/sub, and a public Dart MCP client from the package executable command.\n'
  printf 'Router CLI consumer package smoke rejected stale protected Streamable session replay across the method matrix.\n'
  _cleanup_router_cli_smoke 0
)
