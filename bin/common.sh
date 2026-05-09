#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
  cargo metadata --manifest-path native/transport/Cargo.toml --format-version 1 >/dev/null
}

build_native_ffi_test_release() {
  local target_dir
  local built_lib

  cargo_workspace_check
  cd_repo_root
  target_dir="$ROOT_DIR/native/transport/target/ffi-test"
  CARGO_TARGET_DIR="$target_dir" \
    cargo build --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test --release
  if built_lib="$(native_ffi_test_lib_path)" && [[ -f "$built_lib" ]]; then
    export CONNECTANUM_NATIVE_LIB="$built_lib"
  fi
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

run_router_hosted_mcp_example_smoke() {
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

  dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit
}

run_mcp_client_package_smoke() (
  local smoke_dir

  require_command dart

  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-mcp-client-smoke.XXXXXX")"
  trap "rm -rf '$smoke_dir'" EXIT

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
const _toolName = 'agent.echo';
const _procedureName = 'agent.lookup';
const _resourceUri = 'wamp://agent/readme';
const _resourceTemplateUri = 'wamp://agent/task/{taskId}';
const _promptName = 'agent.summary';
const _topic = 'agent.events';
const _subscriptionHandlePrefix = 'agent-subscription';
const _registrationId = 101;
const _subscriptionId = 202;
const _wampSessionId = 404;
const _sessionCount = 1;
const _publicationId = 303;

Future<void> main() async {
  final endpoint = await _AgentMcpEndpoint.bind();
  final client = McpStreamableHttpClient.withBearerToken(
    endpoint.uri,
    'agent-token',
  );

  try {
    final initialize = await client.initialize(
      clientInfo: const <String, Object?>{
        'name': 'consumer-agent-smoke',
        'version': '0.1.0',
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

    await client.notifyInitialized();

    final tools = await client.listTools(
      id: 'tools-json',
      streamable: false,
    );
    _expect(
      tools.tools.any((tool) => tool['name'] == _toolName),
      'tools/list failed',
    );

    final toolResult = await client.callTool(
      _toolName,
      id: 'call-json',
      arguments: const <String, Object?>{'text': 'ready'},
      streamable: false,
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

    final directTools = await client.listConnectanumToolsDirect(
      id: 'direct-tools',
    );
    _expect(
      directTools.tools.any((tool) => tool['name'] == _toolName),
      'direct JSON tools/list failed',
    );
    _expect(
      endpoint.sawDirectRequestWithoutSession,
      'direct JSON request included Streamable HTTP session state',
    );

    await _smokeDirectToolApi(client, endpoint);
    await _smokeResourcesAndPrompts(client, endpoint);
    await _smokeWampHelpers(client, endpoint);

    final events = await client.poll();
    _expect(
      events.single.jsonData?['method'] == 'notifications/tools/list_changed',
      'GET/SSE poll did not return a tools/list_changed notification',
    );

    await client.deleteSession();
    _expect(client.sessionId == null, 'DELETE did not clear session state');
    _expect(endpoint.sessionDeleted, 'mock endpoint did not receive DELETE');

    print('MCP client-only consumer package smoke completed.');
  } finally {
    client.close(force: true);
    await endpoint.close();
  }
}

Future<void> _smokeDirectToolApi(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final directToolCall = await client.callConnectanumToolDirect(
    _toolName,
    id: 'direct-tool-call',
    arguments: const <String, Object?>{'text': 'direct tool'},
  );
  _expect(
    _toolEchoText(directToolCall, label: 'direct tool call') == 'direct tool',
    'direct JSON connectanum.tool.call helper failed',
  );

  final aliasToolCall = await client.callConnectanumMethodDirect(
    'connectanum.tools.call',
    id: 'direct-tools-call-alias',
    params: const <String, Object?>{
      'name': _toolName,
      'arguments': <String, Object?>{'text': 'direct alias'},
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
  );
  _expect(
    _toolEchoText(dottedToolCall, label: 'direct dotted tool') ==
        'direct dotted',
    'direct JSON dotted tool-name method failed',
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
}

Future<void> _smokeResourcesAndPrompts(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final resources = await client.listResources(id: 'streamable-resources');
  _expect(
    resources.resources.single['uri'] == _resourceUri,
    'streamable resources/list failed',
  );

  final readResource = await client.readResource(
    _resourceUri,
    id: 'streamable-resource-read',
  );
  _expect(
    readResource.single['text'] == 'agent context is available',
    'streamable resources/read failed',
  );

  final templates = await client.listResourceTemplates(
    id: 'streamable-resource-templates',
  );
  _expect(
    templates.resourceTemplates.single['uriTemplate'] == _resourceTemplateUri,
    'streamable resources/templates/list failed',
  );

  final prompts = await client.listPrompts(id: 'streamable-prompts');
  _expect(
    prompts.prompts.single['name'] == _promptName,
    'streamable prompts/list failed',
  );

  final prompt = await client.getPrompt(
    _promptName,
    id: 'streamable-prompt-get',
    arguments: const <String, String>{'taskId': 'T-streamable'},
  );
  _expect(
    jsonEncode(prompt).contains('T-streamable'),
    'streamable prompts/get failed',
  );

  final directResources = await client.listResources(
    id: 'direct-resources',
    directJson: true,
  );
  _expect(
    directResources.resources.single['uri'] == _resourceUri,
    'direct JSON resources/list failed',
  );

  final directReadResource = await client.readResource(
    _resourceUri,
    id: 'direct-resource-read',
    directJson: true,
  );
  _expect(
    directReadResource.single['text'] == 'agent context is available',
    'direct JSON resources/read failed',
  );

  final directTemplates = await client.listResourceTemplates(
    id: 'direct-resource-templates',
    directJson: true,
  );
  _expect(
    directTemplates.resourceTemplates.single['uriTemplate'] ==
        _resourceTemplateUri,
    'direct JSON resources/templates/list failed',
  );

  final directPrompts = await client.listPrompts(
    id: 'direct-prompts',
    directJson: true,
  );
  _expect(
    directPrompts.prompts.single['name'] == _promptName,
    'direct JSON prompts/list failed',
  );

  final directPrompt = await client.getPrompt(
    _promptName,
    id: 'direct-prompt-get',
    arguments: const <String, String>{'taskId': 'T-direct'},
    directJson: true,
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
}

Future<void> _smokeWampHelpers(
  McpStreamableHttpClient client,
  _AgentMcpEndpoint endpoint,
) async {
  final api = await client.listWampApi(id: 'streamable-api-list');
  _expect(
    jsonEncode(api).contains(_procedureName) && jsonEncode(api).contains(_topic),
    'streamable WAMP API list helper failed',
  );

  final described = await client.describeWampApi(
    _procedureName,
    id: 'streamable-api-describe',
    kind: 'procedure',
  );
  _expect(
    described['uri'] == _procedureName,
    'streamable WAMP API describe helper failed',
  );

  final sessionCount = await client.countWampSessions(
    id: 'streamable-session-count',
  );
  _expect(
    sessionCount.argumentsKeywords['count'] == _sessionCount,
    'streamable WAMP session meta helper failed',
  );

  final streamableSubscription = await client.subscribeWampTopic(
    _topic,
    id: 'streamable-subscribe',
    queueLimit: 5,
  );
  _expect(
    streamableSubscription.topic == _topic,
    'streamable pub/sub subscribe helper failed',
  );

  final streamablePublication = await client.publishWampEvent(
    _topic,
    id: 'streamable-publish',
    argumentsKeywords: const <String, Object?>{'text': 'streamable'},
    acknowledge: true,
  );
  _expect(
    streamablePublication.acknowledged &&
        streamablePublication.publicationId == _publicationId,
    'streamable pub/sub publish helper failed',
  );

  final streamableEvents = await client.pollWampEvents(
    streamableSubscription.handle,
    id: 'streamable-poll',
  );
  _expect(
    jsonEncode(streamableEvents.events).contains('streamable'),
    'streamable pub/sub poll helper failed',
  );

  final streamableUnsubscribe = await client.unsubscribeWampTopic(
    streamableSubscription.handle,
    id: 'streamable-unsubscribe',
  );
  _expect(
    streamableUnsubscribe.unsubscribed,
    'streamable pub/sub unsubscribe helper failed',
  );

  final directApi = await client.listWampApi(
    id: 'direct-api-list',
    directJson: true,
  );
  _expect(
    jsonEncode(directApi).contains(_procedureName),
    'direct JSON WAMP API list helper failed',
  );

  final directDescription = await client.describeWampApi(
    _procedureName,
    id: 'direct-api-describe',
    kind: 'procedure',
    directJson: true,
  );
  _expect(
    directDescription['uri'] == _procedureName,
    'direct JSON WAMP API describe helper failed',
  );

  final directSessionCount = await client.countWampSessions(
    id: 'direct-session-count',
    directJson: true,
  );
  _expect(
    directSessionCount.argumentsKeywords['count'] == _sessionCount,
    'direct JSON WAMP session meta helper failed',
  );

  await _smokeDirectWampMetaHelpers(client);

  final directSubscription = await client.subscribeWampTopic(
    _topic,
    id: 'direct-subscribe',
    directJson: true,
  );
  final directPublication = await client.publishWampEvent(
    _topic,
    id: 'direct-publish',
    argumentsKeywords: const <String, Object?>{'text': 'direct'},
    acknowledge: true,
    directJson: true,
  );
  _expect(
    directPublication.acknowledged,
    'direct JSON pub/sub publish helper failed',
  );

  final directEvents = await client.pollWampEvents(
    directSubscription.handle,
    id: 'direct-poll',
    directJson: true,
  );
  _expect(
    jsonEncode(directEvents.events).contains('direct'),
    'direct JSON pub/sub poll helper failed',
  );

  await client.unsubscribeWampTopic(
    directSubscription.handle,
    id: 'direct-unsubscribe',
    directJson: true,
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
}

Future<void> _smokeDirectWampMetaHelpers(
  McpStreamableHttpClient client,
) async {
  final sessions = await client.listWampSessions(
    id: 'direct-session-list',
    directJson: true,
  );
  _expect(
    _jsonListContains(sessions.argumentsKeywords['session_ids'], _wampSessionId),
    'direct JSON WAMP session list helper failed',
  );

  final session = await client.getWampSession(
    _wampSessionId,
    id: 'direct-session-get',
    directJson: true,
  );
  final sessionDetails = _jsonMapFrom(
    session.argumentsKeywords['details'],
    label: 'direct WAMP session details',
  );
  _expect(
    sessionDetails['session'] == _wampSessionId,
    'direct JSON WAMP session get helper failed',
  );

  final registrations = await client.listWampRegistrations(
    id: 'direct-registration-list',
    directJson: true,
  );
  _expect(
    _jsonListContains(registrations.argumentsKeywords['exact'], _registrationId),
    'direct JSON WAMP registration list helper failed',
  );

  final lookupRegistration = await client.lookupWampRegistration(
    _procedureName,
    id: 'direct-registration-lookup',
    match: 'exact',
    directJson: true,
  );
  _expect(
    lookupRegistration.arguments.single == _registrationId,
    'direct JSON WAMP registration lookup helper failed',
  );

  final matchingRegistration = await client.matchWampRegistration(
    _procedureName,
    id: 'direct-registration-match',
    directJson: true,
  );
  _expect(
    matchingRegistration.arguments.single == _registrationId,
    'direct JSON WAMP registration match helper failed',
  );

  final registration = await client.getWampRegistration(
    _registrationId,
    id: 'direct-registration-get',
    directJson: true,
  );
  _expect(
    registration.argumentsKeywords['uri'] == _procedureName,
    'direct JSON WAMP registration get helper failed',
  );

  final callees = await client.listWampRegistrationCallees(
    _registrationId,
    id: 'direct-registration-callees',
    directJson: true,
  );
  _expect(
    callees.arguments.single == _wampSessionId,
    'direct JSON WAMP registration callee list helper failed',
  );

  final calleeCount = await client.countWampRegistrationCallees(
    _registrationId,
    id: 'direct-registration-callee-count',
    directJson: true,
  );
  _expect(
    calleeCount.arguments.single == 1,
    'direct JSON WAMP registration callee count helper failed',
  );

  final subscriptions = await client.listWampSubscriptions(
    id: 'direct-subscription-list',
    directJson: true,
  );
  _expect(
    _jsonListContains(subscriptions.argumentsKeywords['exact'], _subscriptionId),
    'direct JSON WAMP subscription list helper failed',
  );

  final lookupSubscription = await client.lookupWampSubscription(
    _topic,
    id: 'direct-subscription-lookup',
    match: 'exact',
    directJson: true,
  );
  _expect(
    lookupSubscription.arguments.single == _subscriptionId,
    'direct JSON WAMP subscription lookup helper failed',
  );

  final matchingSubscription = await client.matchWampSubscription(
    _topic,
    id: 'direct-subscription-match',
    directJson: true,
  );
  _expect(
    matchingSubscription.arguments.single == _subscriptionId,
    'direct JSON WAMP subscription match helper failed',
  );

  final subscription = await client.getWampSubscription(
    _subscriptionId,
    id: 'direct-subscription-get',
    directJson: true,
  );
  _expect(
    subscription.argumentsKeywords['uri'] == _topic,
    'direct JSON WAMP subscription get helper failed',
  );

  final subscribers = await client.listWampSubscriptionSubscribers(
    _subscriptionId,
    id: 'direct-subscription-subscribers',
    directJson: true,
  );
  _expect(
    subscribers.arguments.single == _wampSessionId,
    'direct JSON WAMP subscription subscriber list helper failed',
  );

  final subscriberCount = await client.countWampSubscriptionSubscribers(
    _subscriptionId,
    id: 'direct-subscription-subscriber-count',
    directJson: true,
  );
  _expect(
    subscriberCount.arguments.single == 1,
    'direct JSON WAMP subscription subscriber count helper failed',
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
  final _subscriptions = <String, String>{};
  final _eventsByHandle = <String, List<Map<String, Object?>>>{};
  var sawDirectRequestWithoutSession = false;
  var sessionDeleted = false;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/mcp',
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
    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer agent-token') {
      await _writeError(request, HttpStatus.unauthorized, 'missing bearer');
      return;
    }

    if (request.method == 'GET') {
      if (!_hasSession(request)) {
        await _writeError(request, HttpStatus.badRequest, 'missing session');
        return;
      }
      await _writeSse(request, <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/tools/list_changed',
      });
      return;
    }

    if (request.method == 'DELETE') {
      if (!_hasSession(request)) {
        await _writeError(request, HttpStatus.notFound, 'unknown session');
        return;
      }
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
    final message = _jsonMapFrom(jsonDecode(body), label: 'request');
    final method = message['method'] as String?;
    final id = message['id'];
    _recordDirectRequest(method, request, message);

    switch (method) {
      case 'initialize':
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
          await _writeError(request, HttpStatus.badRequest, 'missing session');
          return;
        }
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
      case 'tools/list':
        if (!_hasSession(request)) {
          await _writeError(request, HttpStatus.badRequest, 'missing session');
          return;
        }
        await _writeJson(request, _toolListResponse(id));
      case 'tools/call':
        if (!_hasSession(request)) {
          await _writeError(request, HttpStatus.badRequest, 'missing session');
          return;
        }
        await _writeJson(request, _toolCallResponse(id, message));
      case 'connectanum.tools.list':
        sawDirectRequestWithoutSession =
            request.headers.value('MCP-Session-Id') == null;
        await _writeJson(request, _toolListResponse(id));
      case 'connectanum.tool.call':
      case 'connectanum.tools.call':
        await _writeJson(request, _toolCallResponse(id, message));
      case 'resources/list':
        await _writeJson(request, _resourceListResponse(id));
      case 'resources/read':
        await _writeJson(request, _resourceReadResponse(id, message));
      case 'resources/templates/list':
        await _writeJson(request, _resourceTemplateListResponse(id));
      case 'prompts/list':
        await _writeJson(request, _promptListResponse(id));
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

  void _recordDirectRequest(
    String? method,
    HttpRequest request,
    Map<String, Object?> message,
  ) {
    if (method != null && request.headers.value('MCP-Session-Id') == null) {
      directMethodsWithoutSession.add(method);
      if (method == 'connectanum.tool.call' ||
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

  bool _hasSession(HttpRequest request) {
    return request.headers.value('MCP-Session-Id') == _sessionId;
  }

  Map<String, Object?> _toolListResponse(Object? id) {
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
                'text': <String, Object?>{'type': 'string'},
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
      'acknowledged': arguments['acknowledge'] == true,
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

  Map<String, Object?> _resourceListResponse(Object? id) {
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
      },
    };
  }

  Map<String, Object?> _resourceReadResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final params = _jsonMapFrom(message['params'], label: 'resource params');
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

  Map<String, Object?> _resourceTemplateListResponse(Object? id) {
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
      },
    };
  }

  Map<String, Object?> _promptListResponse(Object? id) {
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
      },
    };
  }

  Map<String, Object?> _promptGetResponse(
    Object? id,
    Map<String, Object?> message,
  ) {
    final params = _jsonMapFrom(message['params'], label: 'prompt params');
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
    Map<String, Object?> body,
  ) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _writeSse(
    HttpRequest request,
    Map<String, Object?> message,
  ) async {
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.write('id: agent-event-1\n');
    request.response.write('event: message\n');
    request.response.write('data: ${jsonEncode(message)}\n\n');
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
    dart pub get
    dart analyze
    dart run bin/main.dart
  )
)

run_mcp_consumer_package_smoke() (
  local hook_setting
  local hook_native_lib
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
  trap "rm -rf '$smoke_dir'" EXIT

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
const _ticketAuthId = 'consumer-user';
const _ticketSecret = 'consumer-ticket';
const _topic = 'consumer.events.task';
const _batchTopic = 'consumer.events.batch';
const _procedure = 'consumer.task.lookup';
const _resourceUri = 'consumer://mcp/context';
const _resourceTemplateUri = 'consumer://mcp/task/{taskId}';
const _promptName = 'inspect-consumer-task';
const _headerWrappedNote = '=?base64?Zm9v?=';
const _supportedOlderProtocolVersions = ['2025-03-26', '2025-06-18'];
const _unsupportedProtocolVersion = '2099-01-01';

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
    await _smokeMcpProtocolVersionCompatibility(binding);
    await _smokeDirectJson(publicClient, serviceSession, label: 'public');
    await _smokeStreamableMcp(
      publicClient,
      serviceSession,
      label: 'public',
    );

    await _assertSecureMcpRequiresBearer(binding);
    final grant = await _issueTicketHttpGrant(binding);
    secureClient = McpStreamableHttpClient.withBearerToken(
      _mcpEndpoint(binding, secure: true),
      grant.accessToken,
    );
    await _smokeDirectJson(secureClient, serviceSession, label: 'secure');
    await _smokeStreamableMcp(
      secureClient,
      serviceSession,
      label: 'secure',
    );
    await _smokeSecureMcpRefreshAndRevocation(
      binding,
      serviceSession,
      grant,
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
                'include_registered_procedures': true,
                'include_pubsub_tools': true,
                'resource_list_page_size': 10,
                'resource_template_list_page_size': 10,
                'prompt_list_page_size': 10,
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
                'resource_list_page_size': 10,
                'resource_template_list_page_size': 10,
                'prompt_list_page_size': 10,
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
            ..setAuthMethods(const ['ticket']),
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

Future<void> _assertSecureMcpRequiresBearer(RouterBinding binding) async {
  final client = McpStreamableHttpClient(_mcpEndpoint(binding, secure: true));
  try {
    await client.listConnectanumToolsDirect(id: 'secure-unauthenticated-tools');
    throw StateError('Bearer-protected MCP endpoint accepted no credentials.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'Bearer-protected MCP endpoint returned ${error.statusCode} '
        'instead of ${HttpStatus.unauthorized}.',
      );
    }
  } finally {
    client.close();
  }
}

Future<void> _smokeMcpProtocolVersionCompatibility(
  RouterBinding binding,
) async {
  for (final version in _supportedOlderProtocolVersions) {
    await _smokeSupportedMcpProtocolVersion(binding, version);
  }
  await _assertUnsupportedMcpProtocolVersionRejected(binding);
}

Future<void> _smokeSupportedMcpProtocolVersion(
  RouterBinding binding,
  String protocolVersion,
) async {
  final client = McpStreamableHttpClient(
    _mcpEndpoint(binding),
    defaultProtocolVersion: protocolVersion,
  );
  try {
    final initializeId = 'supported-$protocolVersion-initialize';
    final initialize = await client.initialize(id: initializeId);
    final returnedInitializeId = initialize['id'];
    if (returnedInitializeId != initializeId) {
      throw StateError(
        'MCP initialize with protocol $protocolVersion returned '
        'unexpected id $returnedInitializeId.',
      );
    }
    final sessionId = client.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError(
        'MCP initialize with protocol $protocolVersion did not create '
        'a Streamable HTTP session.',
      );
    }
    if (client.protocolVersion !=
        McpStreamableHttpClient.latestProtocolVersion) {
      throw StateError(
        'MCP initialize with protocol $protocolVersion did not negotiate '
        'the latest server protocol version.',
      );
    }

    await client.notifyInitialized();
    final ping = await client.ping(id: 'supported-$protocolVersion-ping');
    if (ping.isNotEmpty) {
      throw StateError(
        'MCP ping after protocol $protocolVersion negotiation returned '
        'unexpected content.',
      );
    }

    await client.deleteSession();
    if (client.sessionId != null || client.lastEventId != null) {
      throw StateError(
        'MCP protocol $protocolVersion compatibility smoke leaked '
        'Streamable session state.',
      );
    }
  } finally {
    client.close();
  }
}

Future<void> _assertUnsupportedMcpProtocolVersionRejected(
  RouterBinding binding,
) async {
  final client = McpStreamableHttpClient(
    _mcpEndpoint(binding),
    defaultProtocolVersion: _unsupportedProtocolVersion,
  );
  try {
    await client.initialize(id: 'unsupported-protocol-initialize');
    throw StateError('MCP accepted an unsupported protocol version.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'MCP unsupported protocol version returned ${error.statusCode} '
        'instead of ${HttpStatus.badRequest}.',
      );
    }
    if (client.sessionId != null || client.lastEventId != null) {
      throw StateError(
        'MCP unsupported protocol rejection leaked Streamable session state.',
      );
    }
  } finally {
    client.close();
  }
}

Future<void> _assertSecureMcpRejectsBearer(
  RouterBinding binding,
  String bearerToken, {
  required String acceptedMessage,
}) async {
  final client = McpStreamableHttpClient.withBearerToken(
    _mcpEndpoint(binding, secure: true),
    bearerToken,
  );
  try {
    await client.listConnectanumToolsDirect(id: 'secure-rejected-bearer-tools');
    throw StateError(acceptedMessage);
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.unauthorized) {
      throw StateError(
        'Bearer-protected MCP endpoint returned ${error.statusCode} '
        'instead of ${HttpStatus.unauthorized} for a rejected token.',
      );
    }
  } finally {
    client.close();
  }
}

Future<ConnectanumHttpAuthGrant> _issueTicketHttpGrant(
  RouterBinding binding,
) async {
  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  try {
    return await authClient.issueTicketToken(
      realm: _realm,
      authId: _ticketAuthId,
      ticket: _ticketSecret,
    );
  } finally {
    authClient.close(force: true);
  }
}

Future<void> _assertTicketRefreshRejected(
  RouterBinding binding,
  String refreshToken, {
  required String acceptedMessage,
}) async {
  final authClient = ConnectanumHttpAuthClient(_authEndpoint(binding));
  try {
    await authClient.refreshToken(refreshToken);
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
  ConnectanumHttpAuthGrant grant,
) async {
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
      grant.accessToken,
      label: 'secure-rotated',
    );

    final refreshed = await authClient.refreshToken(refreshToken);
    if (refreshed.accessToken == grant.accessToken) {
      throw StateError('HTTP auth bridge refresh reused the access token.');
    }
    final rotatedRefreshToken = refreshed.refreshToken;
    if (rotatedRefreshToken == null || rotatedRefreshToken.isEmpty) {
      throw StateError('HTTP auth bridge refresh did not rotate refresh token.');
    }
    if (rotatedRefreshToken == refreshToken) {
      throw StateError('HTTP auth bridge refresh reused the refresh token.');
    }

    await _assertActiveStreamableSessionRejectsBearer(
      rotatedSessionClient,
      label: 'secure-rotated',
      acceptedMessage:
          'Streamable MCP session accepted a rotated access token.',
    );
    rotatedSessionClient.close();
    rotatedSessionClient = null;
    await _assertSecureMcpRejectsBearer(
      binding,
      grant.accessToken,
      acceptedMessage:
          'Bearer-protected MCP endpoint accepted a rotated access token.',
    );
    await _assertTicketRefreshRejected(
      binding,
      refreshToken,
      acceptedMessage: 'HTTP auth bridge accepted a rotated refresh token.',
    );

    refreshedClient = McpStreamableHttpClient.withBearerToken(
      _mcpEndpoint(binding, secure: true),
      refreshed.accessToken,
    );
    await _smokeDirectJson(
      refreshedClient,
      serviceSession,
      label: 'secure-refreshed',
    );
    await _smokeStreamableMcp(
      refreshedClient,
      serviceSession,
      label: 'secure-refreshed',
    );

    revokedSessionClient = await _openSecureStreamableSession(
      binding,
      refreshed.accessToken,
      label: 'secure-revoked',
    );
    await authClient.revokeToken(
      rotatedRefreshToken,
      tokenTypeHint: 'refresh_token',
    );
    await _assertActiveStreamableSessionRejectsBearer(
      revokedSessionClient,
      label: 'secure-revoked',
      acceptedMessage:
          'Streamable MCP session accepted a revoked access token.',
    );
    revokedSessionClient.close();
    revokedSessionClient = null;
    await _assertSecureMcpRejectsBearer(
      binding,
      refreshed.accessToken,
      acceptedMessage:
          'Bearer-protected MCP endpoint accepted a revoked access token.',
    );
    await _assertTicketRefreshRejected(
      binding,
      rotatedRefreshToken,
      acceptedMessage: 'HTTP auth bridge accepted a revoked refresh token.',
    );
  } finally {
    rotatedSessionClient?.close();
    refreshedClient?.close();
    revokedSessionClient?.close();
    authClient.close(force: true);
  }
}

Future<McpStreamableHttpClient> _openSecureStreamableSession(
  RouterBinding binding,
  String bearerToken, {
  required String label,
}) async {
  final client = McpStreamableHttpClient.withBearerToken(
    _mcpEndpoint(binding, secure: true),
    bearerToken,
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

  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.postBatch(
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
        streamable: false,
        includeSession: false,
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON batch connectanum.api.list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    client,
    () async {
      await client.request(
        'connectanum.api.list',
        id: '$label-rejected-direct-api',
        params: {'kind': 'procedure'},
        streamable: false,
        includeSession: false,
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON connectanum.api.list',
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
  final tools = await client.listConnectanumToolsDirect(
    id: '$label-direct-tools',
  );
  final names = {for (final tool in tools.tools) tool['name'] as String};
  if (!names.contains(_procedure)) {
    throw StateError('Direct JSON tool catalog did not expose $_procedure.');
  }

  await _smokeDirectToolApi(client, label: label);
  await _smokeGenericDirectJsonRpcAccess(
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

  final subscription = await client.subscribeWampTopic(
    _topic,
    id: '$label-direct-subscribe',
    queueLimit: 4,
    directJson: true,
  );
  try {
    await _smokeWampSubscriptionMeta(
      client,
      serviceSession,
      label: label,
      directJson: true,
    );

    final publication = await client.publishWampEvent(
      _topic,
      id: '$label-direct-publish',
      argumentsKeywords: {'taskId': 'T-$label-direct-publish'},
      acknowledge: true,
      directJson: true,
    );
    if (!publication.acknowledged) {
      throw StateError('Direct JSON MCP pub/sub publish was not acknowledged.');
    }

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
    await client.unsubscribeWampTopic(
      subscription.handle,
      id: '$label-direct-unsubscribe',
      directJson: true,
    );
  }

  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError('Direct JSON MCP helpers captured Streamable state.');
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
  );
  _expectDirectToolPayload(
    helperResult,
    taskId: helperTaskId,
    label: 'Direct JSON tool helper',
  );

  final aliasTaskId = 'T-$label-direct-tools-call-alias';
  final aliasResult = await client.callConnectanumMethodDirect(
    'connectanum.tools.call',
    id: '$label-direct-tools-call-alias',
    params: {
      'name': _procedure,
      'arguments': {'taskId': aliasTaskId, 'note': _headerWrappedNote},
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
  final toolsId = '$label-generic-direct-tools';
  final tools = await client.request(
    'connectanum.tools.list',
    id: toolsId,
    streamable: false,
    includeSession: false,
  );
  final toolsJson = jsonEncode(tools['result']);
  if (tools['id'] != toolsId ||
      !toolsJson.contains(_procedure) ||
      !toolsJson.contains('wamp.session.count')) {
    throw StateError(
      'Generic direct JSON-RPC tools/list missed router tools.',
    );
  }

  final taskId = 'T-$label-generic-direct-tool-call';
  final toolCallId = '$label-generic-direct-tool-call';
  final toolCall = await client.post(
    {
      'jsonrpc': '2.0',
      'id': toolCallId,
      'method': 'connectanum.tool.call',
      'params': {
        'name': _procedure,
        'arguments': {'taskId': taskId, 'note': _headerWrappedNote},
      },
    },
    streamable: false,
    includeSession: false,
  );
  final toolCallJson = jsonEncode(toolCall);
  if (toolCall == null ||
      toolCall['id'] != toolCallId ||
      !toolCallJson.contains(taskId) ||
      !toolCallJson.contains(_headerWrappedNote)) {
    throw StateError('Generic direct JSON-RPC tool call failed.');
  }

  final apiListId = '$label-generic-direct-api-list';
  final apiList = await client.request(
    'connectanum.api.list',
    id: apiListId,
    streamable: false,
    includeSession: false,
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

  final describeId = '$label-generic-direct-api-describe';
  final describe = await client.request(
    'connectanum.api.describe',
    id: describeId,
    params: {'uri': _procedure, 'kind': 'procedure'},
    streamable: false,
    includeSession: false,
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
  final sessionCount = await client.request(
    'wamp.session.count',
    id: sessionCountId,
    streamable: false,
    includeSession: false,
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
  final sessionList = await client.request(
    'wamp.session.list',
    id: sessionListId,
    streamable: false,
    includeSession: false,
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
  final sessionGet = await client.request(
    'wamp.session.get',
    id: sessionGetId,
    params: {'id': visibleSessionId},
    streamable: false,
    includeSession: false,
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
  final registrationLookup = await client.request(
    'wamp.registration.lookup',
    id: registrationLookupId,
    params: {'uri': _procedure},
    streamable: false,
    includeSession: false,
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
  final registrationMatch = await client.request(
    'wamp.registration.match',
    id: registrationMatchId,
    params: {'uri': _procedure},
    streamable: false,
    includeSession: false,
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
  final registrationList = await client.request(
    'wamp.registration.list',
    id: registrationListId,
    streamable: false,
    includeSession: false,
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
  final registrationGet = await client.request(
    'wamp.registration.get',
    id: registrationGetId,
    params: {'id': registrationId},
    streamable: false,
    includeSession: false,
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
  final registrationCallees = await client.request(
    'wamp.registration.list_callees',
    id: registrationCalleesId,
    params: {'id': registrationId},
    streamable: false,
    includeSession: false,
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
  final registrationCalleeCount = await client.request(
    'wamp.registration.count_callees',
    id: registrationCalleeCountId,
    params: {'id': registrationId},
    streamable: false,
    includeSession: false,
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

Future<void> _smokeGenericDirectJsonRpcResourcesAndPrompts(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;

  final resourcesId = '$label-generic-direct-resources';
  final resources = await client.request(
    'resources/list',
    id: resourcesId,
    streamable: false,
    includeSession: false,
  );
  final resourcesResult = _jsonRpcResult(
    resources,
    id: resourcesId,
    label: 'Generic direct JSON-RPC resources/list',
  );
  if (!jsonEncode(resourcesResult['resources']).contains(_resourceUri)) {
    throw StateError(
      'Generic direct JSON-RPC resources/list missed $_resourceUri.',
    );
  }

  final readId = '$label-generic-direct-resource-read';
  final read = await client.request(
    'resources/read',
    id: readId,
    params: {'uri': _resourceUri},
    streamable: false,
    includeSession: false,
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

  final templatesId = '$label-generic-direct-resource-templates';
  final templates = await client.request(
    'resources/templates/list',
    id: templatesId,
    streamable: false,
    includeSession: false,
  );
  final templatesResult = _jsonRpcResult(
    templates,
    id: templatesId,
    label: 'Generic direct JSON-RPC resources/templates/list',
  );
  if (!jsonEncode(
    templatesResult['resourceTemplates'],
  ).contains(_resourceTemplateUri)) {
    throw StateError(
      'Generic direct JSON-RPC resources/templates/list missed '
      '$_resourceTemplateUri.',
    );
  }

  final promptsId = '$label-generic-direct-prompts';
  final prompts = await client.request(
    'prompts/list',
    id: promptsId,
    streamable: false,
    includeSession: false,
  );
  final promptsResult = _jsonRpcResult(
    prompts,
    id: promptsId,
    label: 'Generic direct JSON-RPC prompts/list',
  );
  if (!jsonEncode(promptsResult['prompts']).contains(_promptName)) {
    throw StateError(
      'Generic direct JSON-RPC prompts/list missed $_promptName.',
    );
  }

  final taskId = 'T-$label-generic-direct-prompt';
  final promptId = '$label-generic-direct-prompt-get';
  final prompt = _jsonObjectFrom(
    await client.post(
      {
        'jsonrpc': '2.0',
        'id': promptId,
        'method': 'prompts/get',
        'params': {
          'name': _promptName,
          'arguments': {'taskId': taskId},
        },
      },
      streamable: false,
      includeSession: false,
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
  final resourceError = await client.request(
    'resources/read',
    id: resourceErrorId,
    params: {'uri': missingResourceUri},
    streamable: false,
    includeSession: false,
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
    await client.post(
      {
        'jsonrpc': '2.0',
        'id': promptErrorId,
        'method': 'prompts/get',
        'params': {'name': missingPromptName, 'arguments': {}},
      },
      streamable: false,
      includeSession: false,
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

  final resources = await client.request(
    'resources/list',
    id: '$label-generic-direct-resource-error-recovery',
    streamable: false,
    includeSession: false,
  );
  if (!jsonEncode(resources).contains(_resourceUri)) {
    throw StateError(
      'Generic direct JSON-RPC resource error recovery missed $_resourceUri.',
    );
  }

  final prompts = await client.request(
    'prompts/list',
    id: '$label-generic-direct-prompt-error-recovery',
    streamable: false,
    includeSession: false,
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
  final subscribe = await client.request(
    'connectanum.pubsub.subscribe',
    id: subscribeId,
    params: {'topic': _topic, 'queueLimit': 4},
    streamable: false,
    includeSession: false,
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
      await client.post(
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
        streamable: false,
        includeSession: false,
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
    final unsubscribe = await client.request(
      'connectanum.pubsub.unsubscribe',
      id: unsubscribeId,
      params: {'handle': handle},
      streamable: false,
      includeSession: false,
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
  final subscriptionLookup = await client.request(
    'wamp.subscription.lookup',
    id: subscriptionLookupId,
    params: {'topic': _topic},
    streamable: false,
    includeSession: false,
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
  final subscriptionMatch = await client.request(
    'wamp.subscription.match',
    id: subscriptionMatchId,
    params: {'topic': _topic},
    streamable: false,
    includeSession: false,
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
  final subscriptionList = await client.request(
    'wamp.subscription.list',
    id: subscriptionListId,
    streamable: false,
    includeSession: false,
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
  final subscriptionGet = await client.request(
    'wamp.subscription.get',
    id: subscriptionGetId,
    params: {'id': subscriptionId},
    streamable: false,
    includeSession: false,
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
  final subscribers = await client.request(
    'wamp.subscription.list_subscribers',
    id: subscribersId,
    params: {'id': subscriptionId},
    streamable: false,
    includeSession: false,
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
  final subscriberCount = await client.request(
    'wamp.subscription.count_subscribers',
    id: subscriberCountId,
    params: {'id': subscriptionId},
    streamable: false,
    includeSession: false,
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
  final discovery = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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
  final details = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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
    final subscribeBatch = await client.postBatch(
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
      streamable: false,
      includeSession: false,
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
    final publishBatch = await client.postBatch(
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
      streamable: false,
      includeSession: false,
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
      final unsubscribeBatch = await client.postBatch(
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
        streamable: false,
        includeSession: false,
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

  final toolsId = '$label-generic-streamable-tools';
  final tools = await client.request('tools/list', id: toolsId);
  final toolsResult = _jsonRpcResult(
    tools,
    id: toolsId,
    label: 'Generic Streamable JSON-RPC tools/list',
  );
  final toolsJson = jsonEncode(toolsResult['tools']);
  if (!toolsJson.contains(_procedure) ||
      !toolsJson.contains('connectanum.pubsub.subscribe')) {
    throw StateError(
      'Generic Streamable JSON-RPC tools/list missed router tools.',
    );
  }
  expectStreamableProgress('tools/list');

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

  final resourcesId = '$label-generic-streamable-resources';
  final resources = await client.request('resources/list', id: resourcesId);
  final resourcesResult = _jsonRpcResult(
    resources,
    id: resourcesId,
    label: 'Generic Streamable JSON-RPC resources/list',
  );
  if (!jsonEncode(resourcesResult['resources']).contains(_resourceUri)) {
    throw StateError(
      'Generic Streamable JSON-RPC resources/list missed $_resourceUri.',
    );
  }
  expectStreamableProgress('resources/list');

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

  final templatesId = '$label-generic-streamable-resource-templates';
  final templates = await client.request(
    'resources/templates/list',
    id: templatesId,
  );
  final templatesResult = _jsonRpcResult(
    templates,
    id: templatesId,
    label: 'Generic Streamable JSON-RPC resources/templates/list',
  );
  if (!jsonEncode(
    templatesResult['resourceTemplates'],
  ).contains(_resourceTemplateUri)) {
    throw StateError(
      'Generic Streamable JSON-RPC resources/templates/list missed '
      '$_resourceTemplateUri.',
    );
  }
  expectStreamableProgress('resources/templates/list');

  final promptsId = '$label-generic-streamable-prompts';
  final prompts = await client.request('prompts/list', id: promptsId);
  final promptsResult = _jsonRpcResult(
    prompts,
    id: promptsId,
    label: 'Generic Streamable JSON-RPC prompts/list',
  );
  if (!jsonEncode(promptsResult['prompts']).contains(_promptName)) {
    throw StateError(
      'Generic Streamable JSON-RPC prompts/list missed $_promptName.',
    );
  }
  expectStreamableProgress('prompts/list');

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
    final poll = await client.request(
      'connectanum.pubsub.poll',
      id: pollId,
      params: {'handle': handle, 'limit': 4},
      streamable: false,
      includeSession: false,
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
    final pollBatch = await client.postBatch(
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
      streamable: false,
      includeSession: false,
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
  final initializeResult = await client.initialize(
    clientInfo: const {
      'name': 'connectanum_consumer_package_smoke',
      'version': '0.1.0',
    },
  );
  final initializeJson = jsonEncode(initializeResult);
  if (!initializeJson.contains('resources') ||
      !initializeJson.contains('prompts')) {
    throw StateError(
      'Streamable MCP initialize did not advertise resources and prompts.',
    );
  }
  await client.notifyInitialized();

  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError('Streamable MCP initialize did not capture a session id.');
  }
  final eventIdBeforeDirectCatalog = client.lastEventId;
  final directCatalog = await client.listConnectanumToolsDirect(
    id: '$label-direct-catalog-for-streamable',
  );
  final directCatalogNames = {
    for (final tool in directCatalog.tools) tool['name'] as String,
  };
  if (!directCatalogNames.contains(_procedure)) {
    throw StateError('Direct JSON tool catalog did not expose $_procedure.');
  }
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
  );
  final resultJson = jsonEncode(result);
  if (!resultJson.contains('T-$label-streamable-direct-catalog') ||
      !resultJson.contains(_headerWrappedNote)) {
    throw StateError('Streamable MCP tool call returned unexpected payload.');
  }

  final tools = await client.listTools(id: '$label-streamable-tools');
  final names = {for (final tool in tools.tools) tool['name'] as String};
  if (!names.contains(_procedure)) {
    throw StateError('Streamable MCP tool catalog did not expose $_procedure.');
  }

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
  );
  try {
    await _smokeWampSubscriptionMeta(client, serviceSession, label: label);

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

  await _smokeStreamableSessionLifecycle(
    client,
    serviceSession,
    label: label,
  );
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

  await _smokeDirectToolApi(
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

  await _smokeWampMetaDiscovery(
    client,
    serviceSession,
    label: '$label-direct-after-streamable',
    directJson: true,
  );

  final subscription = await client.subscribeWampTopic(
    _topic,
    id: '$label-direct-after-streamable-subscribe',
    queueLimit: 4,
    directJson: true,
  );
  try {
    await _smokeWampSubscriptionMeta(
      client,
      serviceSession,
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
    await client.unsubscribeWampTopic(
      subscription.handle,
      id: '$label-direct-after-streamable-unsubscribe',
      directJson: true,
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
    await client.callConnectanumToolDirect(
      missingTool,
      id: errorId,
      arguments: {},
    );
    throw StateError('Direct JSON single error smoke accepted a missing tool.');
  } on McpJsonRpcException catch (error) {
    _expectMcpJsonRpcException(
      error,
      id: errorId,
      method: 'connectanum.tool.call',
      messageSubstring: missingTool,
      label: 'Direct JSON single missing tool',
    );
  }

  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON single error changed Streamable state.');
  }

  final tools = await client.listConnectanumToolsDirect(
    id: '$label-direct-error-recovery-tools',
  );
  final names = {for (final tool in tools.tools) tool['name'] as String};
  if (!names.contains(_procedure)) {
    throw StateError('Direct JSON recovery tool catalog missed $_procedure.');
  }
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

  final tools = await client.listTools(id: '$label-streamable-error-recovery');
  final names = {for (final tool in tools.tools) tool['name'] as String};
  if (!names.contains(_procedure)) {
    throw StateError(
      'Streamable MCP single error recovery missed $_procedure.',
    );
  }
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
  final aliasTaskId = 'T-$label-direct-batch-tools-alias';
  final promptTaskId = 'T-$label-direct-batch-prompt';
  final responses = await client.postBatch(
    [
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-api',
        'method': 'connectanum.api.list',
        'params': {'kind': 'procedure'},
      },
      {
        'jsonrpc': '2.0',
        'id': '$label-direct-batch-call',
        'method': _procedure,
        'params': {'taskId': taskId},
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
          'arguments': {'taskId': 'T-$label-direct-batch-notification'},
        },
      },
    ],
    streamable: false,
    includeSession: false,
  );
  if (responses == null || responses.length != 5) {
    throw StateError('Direct JSON batch did not return five responses.');
  }
  if (responses[0]['id'] != '$label-direct-batch-api' ||
      !jsonEncode(responses[0]).contains(_procedure)) {
    throw StateError('Direct JSON batch API catalog response was invalid.');
  }
  if (responses[1]['id'] != '$label-direct-batch-call' ||
      !jsonEncode(responses[1]).contains(taskId)) {
    throw StateError('Direct JSON batch procedure call response was invalid.');
  }
  if (responses[2]['id'] != '$label-direct-batch-tools-alias' ||
      !jsonEncode(responses[2]).contains(aliasTaskId) ||
      !jsonEncode(responses[2]).contains(_headerWrappedNote)) {
    throw StateError(
      'Direct JSON batch plural tool alias response was invalid.',
    );
  }
  if (responses[3]['id'] != '$label-direct-batch-resources' ||
      !jsonEncode(responses[3]).contains(_resourceUri)) {
    throw StateError('Direct JSON batch resources/list response was invalid.');
  }
  if (responses[4]['id'] != '$label-direct-batch-prompt' ||
      !jsonEncode(responses[4]).contains(promptTaskId)) {
    throw StateError('Direct JSON batch prompts/get response was invalid.');
  }
  await _smokeDirectJsonBatchResourcePromptDetails(client, label: label);
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
}) async {
  final detailBatch = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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

  final templates = _jsonRpcResult(
    detailBatch[1],
    id: '$label-direct-batch-resource-templates',
    label: 'Direct JSON batch resources/templates/list',
  );
  if (!jsonEncode(
    templates['resourceTemplates'],
  ).contains(_resourceTemplateUri)) {
    throw StateError(
      'Direct JSON batch resources/templates/list missed '
      '$_resourceTemplateUri.',
    );
  }

  final prompts = _jsonRpcResult(
    detailBatch[2],
    id: '$label-direct-batch-prompts',
    label: 'Direct JSON batch prompts/list',
  );
  if (!jsonEncode(prompts['prompts']).contains(_promptName)) {
    throw StateError('Direct JSON batch prompts/list missed $_promptName.');
  }
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
  final discovery = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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
  final details = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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

  final previousEventId = client.lastEventId;
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
  if (responses[0]['id'] != '$label-streamable-batch-tools' ||
      !jsonEncode(responses[0]).contains(_procedure)) {
    throw StateError('Streamable MCP batch tools/list response was invalid.');
  }
  if (responses[1]['id'] != '$label-streamable-batch-call' ||
      !jsonEncode(responses[1]).contains(taskId)) {
    throw StateError('Streamable MCP batch tools/call response was invalid.');
  }
  if (responses[2]['id'] != '$label-streamable-batch-resources' ||
      !jsonEncode(responses[2]).contains(_resourceUri)) {
    throw StateError('Streamable MCP batch resources/list response invalid.');
  }
  if (responses[3]['id'] != '$label-streamable-batch-prompt' ||
      !jsonEncode(responses[3]).contains(promptTaskId)) {
    throw StateError('Streamable MCP batch prompts/get response was invalid.');
  }
  final eventId = client.lastEventId;
  if (eventId == null ||
      !eventId.startsWith('$sessionId:') ||
      eventId == previousEventId) {
    throw StateError('Streamable MCP batch did not update SSE event state.');
  }

  await _smokeStreamableBatchResourcePromptDetails(client, label: label);
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
}) async {
  final sessionId = client.sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    throw StateError(
      'Streamable MCP batch resource/prompt details has no session id.',
    );
  }

  final previousEventId = client.lastEventId;
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

  final templates = _jsonRpcResult(
    detailBatch[1],
    id: '$label-streamable-batch-resource-templates',
    label: 'Streamable MCP batch resources/templates/list',
  );
  if (!jsonEncode(
    templates['resourceTemplates'],
  ).contains(_resourceTemplateUri)) {
    throw StateError(
      'Streamable MCP batch resources/templates/list missed '
      '$_resourceTemplateUri.',
    );
  }

  final prompts = _jsonRpcResult(
    detailBatch[2],
    id: '$label-streamable-batch-prompts',
    label: 'Streamable MCP batch prompts/list',
  );
  if (!jsonEncode(prompts['prompts']).contains(_promptName)) {
    throw StateError('Streamable MCP batch prompts/list missed $_promptName.');
  }

  if (client.sessionId != sessionId) {
    throw StateError(
      'Streamable MCP batch resource/prompt details changed session id.',
    );
  }
  final eventId = client.lastEventId;
  if (eventId == null ||
      !eventId.startsWith('$sessionId:') ||
      eventId == previousEventId) {
    throw StateError(
      'Streamable MCP batch resource/prompt details did not update SSE state.',
    );
  }
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

Future<void> _smokeDirectJsonBatchErrorIsolation(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final taskId = 'T-$label-direct-batch-error-ok';
  final aliasTaskId = 'T-$label-direct-batch-error-alias-ok';
  final missingTool = 'missing.$label.direct.batch';
  final responses = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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

  final previousEventId = client.lastEventId;
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
  if (responses[0]['id'] != '$label-streamable-batch-error-tools' ||
      !jsonEncode(responses[0]).contains(_procedure)) {
    throw StateError('Streamable MCP batch error smoke lost tools response.');
  }
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
  if (client.sessionId != sessionId) {
    throw StateError('Streamable MCP batch error smoke changed session id.');
  }
  final eventId = client.lastEventId;
  if (eventId == null ||
      !eventId.startsWith('$sessionId:') ||
      eventId == previousEventId) {
    throw StateError(
      'Streamable MCP batch error smoke did not update SSE event state.',
    );
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
  final resources = await client.listResources(
    id: '$label-$mode-resources',
    directJson: directJson,
  );
  final resourceUris = {
    for (final resource in resources.resources) resource['uri'],
  };
  if (!resourceUris.contains(_resourceUri)) {
    throw StateError('MCP resources/list did not expose $_resourceUri.');
  }

  final contents = await client.readResource(
    _resourceUri,
    id: '$label-$mode-resource-read',
    directJson: directJson,
  );
  if (!jsonEncode(contents).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError('MCP resources/read did not return route context.');
  }

  final templates = await client.listResourceTemplates(
    id: '$label-$mode-resource-templates',
    directJson: directJson,
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

  final prompts = await client.listPrompts(
    id: '$label-$mode-prompts',
    directJson: directJson,
  );
  final promptNames = {for (final prompt in prompts.prompts) prompt['name']};
  if (!promptNames.contains(_promptName)) {
    throw StateError('MCP prompts/list did not expose $_promptName.');
  }

  final taskId = 'T-$label-$mode-prompt';
  final prompt = await client.getPrompt(
    _promptName,
    id: '$label-$mode-prompt',
    arguments: {'taskId': taskId},
    directJson: directJson,
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

Future<void> _smokeWampSubscriptionMeta(
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
}
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final events = await client.pollWampEvents(
      subscriptionHandle,
      id: 'streamable-poll-${DateTime.now().microsecondsSinceEpoch}',
      limit: 4,
      directJson: directJson,
    );
    if (events.events.isNotEmpty) {
      return events;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for MCP pub/sub event.');
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

  final events = await _pollStreamableSessionEventsUntil(client, label: label);
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

  final resumedEvents = await client.poll(lastEventId: eventId);
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

  await client.deleteSession();
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError('Streamable MCP DELETE did not clear session state.');
  }

  client.sessionId = sessionId;
  client.lastEventId = eventId;
  try {
    await client.listTools(id: '$label-stale-session-tools');
    throw StateError('Deleted Streamable MCP session remained usable.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.notFound) {
      rethrow;
    }
  }
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError('Streamable MCP 404 did not clear stale session state.');
  }

  final recovered = await client.initialize(id: '$label-reinitialize');
  if (recovered['id'] != '$label-reinitialize' || client.sessionId == null) {
    throw StateError('Streamable MCP reinitialize after 404 failed.');
  }
  await client.notifyInitialized();
  await client.deleteSession();
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

  final tools = await client.listTools(
    id: '$label-after-invalid-last-event-id-tools',
  );
  final names = {for (final tool in tools.tools) tool['name'] as String};
  if (!names.contains(_procedure)) {
    throw StateError(
      'Streamable MCP session failed after invalid Last-Event-ID rejection.',
    );
  }
  if (client.sessionId != sessionId) {
    throw StateError(
      'Streamable MCP invalid Last-Event-ID recovery lost session id.',
    );
  }
}

Future<List<McpSseEvent>> _pollStreamableSessionEventsUntil(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final events = await client.poll();
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
    dart pub get
    dart analyze
    if [[ -n "$hook_native_lib" ]]; then
      CONNECTANUM_NATIVE_LIB="$hook_native_lib" dart run bin/main.dart
    else
      dart run bin/main.dart
    fi
  )
)
