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

run_mcp_server_package_smoke() (
  local smoke_dir

  require_command dart

  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/connectanum-mcp-server-smoke.XXXXXX")"
  trap "rm -rf '$smoke_dir'" EXIT

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
    dart pub get
    dart analyze
    dart run bin/main.dart
  )
)

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
const _authState = 'agent-auth-state';
const _authRealm = 'agent.realm';
const _authId = 'consumer-agent';
const _authRole = 'agent';
const _authProvider = 'client-smoke';
const _ticketSecret = 'agent-ticket';
const _accessToken = 'agent-token';
const _refreshToken = 'agent-refresh-token';
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

    client = McpStreamableHttpClient.withAuthGrant(endpoint.uri, grant);

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

    final toolResult = await client.callTool(
      _toolName,
      id: 'call-json',
      arguments: const <String, Object?>{'text': 'ready'},
      streamable: false,
      headers: const <String, String>{
        'x-consumer-trace': 'typed-tool-json',
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

    final directTools = await client.listConnectanumToolsDirect(
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
    final directToolPage = await client.listConnectanumToolsDirect(
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

  final directTools = await client.request(
    'connectanum.tools.list',
    id: 'generic-direct-tools',
    streamable: false,
    includeSession: false,
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

  final directToolCall = await client.request(
    'connectanum.tool.call',
    id: 'generic-direct-tool-call',
    params: const <String, Object?>{
      'name': _toolName,
      'arguments': <String, Object?>{'text': 'generic direct'},
    },
    streamable: false,
    includeSession: false,
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

  final directBatch = await client.postBatch(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-tools',
        'method': 'connectanum.tools.list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-tool-call',
        'method': 'connectanum.tool.call',
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
    streamable: false,
    includeSession: false,
    headers: const <String, String>{
      'x-consumer-trace': 'generic-direct-batch',
    },
  );
  _expect(
    directBatch != null && directBatch.length == 3,
    'generic direct JSON batch did not return three responses',
  );
  _expect(
    _toolEchoText(
          _jsonRpcResult(
            directBatch![1],
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

  final directNotificationBatch = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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

  await client.notification(
    'notifications/progress',
    params: const <String, Object?>{
      'progressToken': 'generic-direct-single-notification',
      'progress': 1,
    },
    streamable: false,
    includeSession: false,
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
    'connectanum.tools.list',
    'connectanum.tool.call',
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
  final responseSessionBatch = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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
  await client.notification(
    'notifications/progress',
    params: const <String, Object?>{
      'progressToken': responseSessionNotificationTrace,
      'progress': 1,
    },
    streamable: false,
    includeSession: false,
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

  const responseSessionNotificationBatchTrace =
      'direct-response-session-notification-batch-header';
  final responseSessionNotificationBatch = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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
  _expect(
    client.sessionId == sessionId && client.lastEventId == eventId,
    'controlled MCP header direct JSON smoke changed Streamable session state',
  );

  const pollTrace = 'controlled-poll-mcp-headers';
  client.lastEventId = null;
  final events = await client.poll(
    headers: const <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
      'MCP-Session-Id': 'caller-poll-session',
      'Last-Event-ID': 'caller-poll-event',
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
  client.lastEventId = eventId;
}

Future<void> _smokeGenericJsonRpcBatchErrors(
  McpStreamableHttpClient client,
) async {
  final sessionId = client.sessionId;
  final eventId = client.lastEventId;

  const missingDirectTool = 'missing.generic.direct.batch';
  final directBatch = await client.postBatch(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-error-tools',
        'method': 'connectanum.tools.list',
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-error-missing',
        'method': 'connectanum.tool.call',
        'params': <String, Object?>{
          'name': missingDirectTool,
          'arguments': <String, Object?>{},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-error-call',
        'method': 'connectanum.tool.call',
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
    streamable: false,
    includeSession: false,
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

  final directSubscribeBatch = await client.postBatch(
    const <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-pubsub-subscribe',
        'method': 'connectanum.tool.call',
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
        'method': 'connectanum.tools.list',
      },
    ],
    streamable: false,
    includeSession: false,
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

  final directPublishPollBatch = await client.postBatch(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-pubsub-publish',
        'method': 'connectanum.tool.call',
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
        'method': 'connectanum.tool.call',
        'params': <String, Object?>{
          'name': 'connectanum.pubsub.poll',
          'arguments': <String, Object?>{
            'handle': directHandle,
          },
        },
      },
    ],
    streamable: false,
    includeSession: false,
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

  final directUnsubscribeBatch = await client.postBatch(
    <McpJsonMap>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'generic-direct-batch-pubsub-unsubscribe',
        'method': 'connectanum.tool.call',
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
        'method': 'connectanum.tools.list',
      },
    ],
    streamable: false,
    includeSession: false,
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
  final directDetailBatch = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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
  final directErrorBatch = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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
  final directToolCall = await client.callConnectanumToolDirect(
    _toolName,
    id: 'direct-tool-call',
    arguments: const <String, Object?>{'text': 'direct tool'},
    headers: const <String, String>{
      'x-consumer-trace': 'direct-tool-call',
    },
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
    headers: const <String, String>{
      'x-consumer-trace': 'direct-tools-call-alias',
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
    },
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
  const expectedDirectToolApiTraceHeaders = <String>{
    'direct-tools-list',
    'direct-tool-call',
    'direct-tools-call-alias',
    'direct-dotted-tool-call',
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

  final directResources = await client.listResources(
    id: 'direct-resources',
    directJson: true,
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
  final directResourcesPage = await client.listResources(
    id: 'direct-resources-page-2',
    cursor: directResources.nextCursor,
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-resources-page-2',
    },
  );
  _expect(
    directResourcesPage.resources.single['uri'] == _pagedResourceUri &&
        directResourcesPage.nextCursor == null,
    'direct JSON resources/list cursor page failed',
  );

  final directReadResource = await client.readResource(
    _resourceUri,
    id: 'direct-resource-read',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-resource-read',
    },
  );
  _expect(
    directReadResource.single['text'] == 'agent context is available',
    'direct JSON resources/read failed',
  );

  final directTemplates = await client.listResourceTemplates(
    id: 'direct-resource-templates',
    directJson: true,
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
  final directTemplatesPage = await client.listResourceTemplates(
    id: 'direct-resource-templates-page-2',
    cursor: directTemplates.nextCursor,
    directJson: true,
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

  final directPrompts = await client.listPrompts(
    id: 'direct-prompts',
    directJson: true,
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
  final directPromptsPage = await client.listPrompts(
    id: 'direct-prompts-page-2',
    cursor: directPrompts.nextCursor,
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'resource-prompts-direct-prompts-page-2',
    },
  );
  _expect(
    directPromptsPage.prompts.single['name'] == _pagedPromptName &&
        directPromptsPage.nextCursor == null,
    'direct JSON prompts/list cursor page failed',
  );

  final directPrompt = await client.getPrompt(
    _promptName,
    id: 'direct-prompt-get',
    arguments: const <String, String>{'taskId': 'T-direct'},
    directJson: true,
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
    acknowledge: true,
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

  final directApi = await client.listWampApi(
    id: 'direct-api-list',
    directJson: true,
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

  final directDescription = await client.describeWampApi(
    _procedureName,
    id: 'direct-api-describe',
    kind: 'procedure',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-api-describe',
    },
  );
  _expect(
    directDescription['uri'] == _procedureName,
    'direct JSON WAMP API describe helper failed',
  );

  final directSessionCount = await client.countWampSessions(
    id: 'direct-session-count',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-session-count',
    },
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
    headers: const <String, String>{'x-consumer-trace': 'direct-subscribe'},
  );
  final directPublication = await client.publishWampEvent(
    _topic,
    id: 'direct-publish',
    argumentsKeywords: const <String, Object?>{'text': 'direct'},
    acknowledge: true,
    directJson: true,
    headers: const <String, String>{'x-consumer-trace': 'direct-publish'},
  );
  _expect(
    directPublication.acknowledged,
    'direct JSON pub/sub publish helper failed',
  );

  final directEvents = await client.pollWampEvents(
    directSubscription.handle,
    id: 'direct-poll',
    directJson: true,
    headers: const <String, String>{'x-consumer-trace': 'direct-poll'},
  );
  _expect(
    jsonEncode(directEvents.events).contains('direct'),
    'direct JSON pub/sub poll helper failed',
  );

  await client.unsubscribeWampTopic(
    directSubscription.handle,
    id: 'direct-unsubscribe',
    directJson: true,
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
  final sessions = await client.listWampSessions(
    id: 'direct-session-list',
    directJson: true,
    headers: const <String, String>{'x-consumer-trace': 'direct-session-list'},
  );
  _expect(
    _jsonListContains(sessions.argumentsKeywords['session_ids'], _wampSessionId),
    'direct JSON WAMP session list helper failed',
  );

  final session = await client.getWampSession(
    _wampSessionId,
    id: 'direct-session-get',
    directJson: true,
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

  final registrations = await client.listWampRegistrations(
    id: 'direct-registration-list',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-list',
    },
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
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-lookup',
    },
  );
  _expect(
    lookupRegistration.arguments.single == _registrationId,
    'direct JSON WAMP registration lookup helper failed',
  );

  final matchingRegistration = await client.matchWampRegistration(
    _procedureName,
    id: 'direct-registration-match',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-match',
    },
  );
  _expect(
    matchingRegistration.arguments.single == _registrationId,
    'direct JSON WAMP registration match helper failed',
  );

  final registration = await client.getWampRegistration(
    _registrationId,
    id: 'direct-registration-get',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-get',
    },
  );
  _expect(
    registration.argumentsKeywords['uri'] == _procedureName,
    'direct JSON WAMP registration get helper failed',
  );

  final callees = await client.listWampRegistrationCallees(
    _registrationId,
    id: 'direct-registration-callees',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-callees',
    },
  );
  _expect(
    callees.arguments.single == _wampSessionId,
    'direct JSON WAMP registration callee list helper failed',
  );

  final calleeCount = await client.countWampRegistrationCallees(
    _registrationId,
    id: 'direct-registration-callee-count',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-registration-callee-count',
    },
  );
  _expect(
    calleeCount.arguments.single == 1,
    'direct JSON WAMP registration callee count helper failed',
  );

  final subscriptions = await client.listWampSubscriptions(
    id: 'direct-subscription-list',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-list',
    },
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
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-lookup',
    },
  );
  _expect(
    lookupSubscription.arguments.single == _subscriptionId,
    'direct JSON WAMP subscription lookup helper failed',
  );

  final matchingSubscription = await client.matchWampSubscription(
    _topic,
    id: 'direct-subscription-match',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-match',
    },
  );
  _expect(
    matchingSubscription.arguments.single == _subscriptionId,
    'direct JSON WAMP subscription match helper failed',
  );

  final subscription = await client.getWampSubscription(
    _subscriptionId,
    id: 'direct-subscription-get',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-get',
    },
  );
  _expect(
    subscription.argumentsKeywords['uri'] == _topic,
    'direct JSON WAMP subscription get helper failed',
  );

  final subscribers = await client.listWampSubscriptionSubscribers(
    _subscriptionId,
    id: 'direct-subscription-subscribers',
    directJson: true,
    headers: const <String, String>{
      'x-consumer-trace': 'direct-subscription-subscribers',
    },
  );
  _expect(
    subscribers.arguments.single == _wampSessionId,
    'direct JSON WAMP subscription subscriber list helper failed',
  );

  final subscriberCount = await client.countWampSubscriptionSubscribers(
    _subscriptionId,
    id: 'direct-subscription-subscriber-count',
    directJson: true,
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
  final streamableTraceHeadersWithoutSession = <String>{};
  final streamableTraceHeadersWithSession = <String>{};
  final authRequestBodies = <Map<String, Object?>>[];
  final authTraceHeaders = <String>[];
  final authDefaultHeaders = <String>[];
  final _subscriptions = <String, String>{};
  final _eventsByHandle = <String, List<Map<String, Object?>>>{};
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

  static Future<_AgentMcpEndpoint> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _AgentMcpEndpoint._(server);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path == '/auth') {
      await _handleAuth(request);
      return;
    }

    if (request.uri.path != '/mcp') {
      await _writeError(request, HttpStatus.notFound, 'unknown endpoint');
      return;
    }

    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer $_accessToken') {
      await _writeError(request, HttpStatus.unauthorized, 'missing bearer');
      return;
    }

    if (request.method == 'GET') {
      if (!_hasSession(request)) {
        await _writeSessionError(request);
        return;
      }
      _recordStreamableTrace('GET', request);
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
        if (!_hasSession(request)) {
          await _writeSessionError(request);
          return;
        }
        await _writeJson(request, _pingResponse(id));
      case 'tools/list':
        if (!_hasSession(request)) {
          await _writeSessionError(request);
          return;
        }
        await _writeJson(request, _toolListResponse(id, message));
      case 'tools/call':
        if (!_hasSession(request)) {
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
      request.response.statusCode = HttpStatus.accepted;
      _applyTestResponseHeaders(request);
      await request.response.close();
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
    if (_batchMethodRequiresSession(method) && !_hasSession(request)) {
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

  bool _batchMethodRequiresSession(String? method) {
    return method == 'notifications/initialized' ||
        method == 'ping' ||
        method == 'tools/list' ||
        method == 'tools/call';
  }

  void _recordDirectRequest(
    String? method,
    HttpRequest request,
    Map<String, Object?> message,
  ) {
    if (method != null && request.headers.value('MCP-Session-Id') == null) {
      final trace = request.headers.value('x-consumer-trace');
      if (trace != null) {
        directTraceHeadersWithoutSession.add(trace);
      }
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

  void _recordStreamableTrace(String method, HttpRequest request) {
    final trace = request.headers.value('x-consumer-trace');
    if (trace == null) {
      return;
    }
    if (request.headers.value('MCP-Session-Id') == null) {
      streamableTraceHeadersWithoutSession.add('$method:$trace');
    } else {
      streamableTraceHeadersWithSession.add('$method:$trace');
    }
  }

  bool _hasSession(HttpRequest request) {
    return request.headers.value('MCP-Session-Id') == _sessionId &&
        _sessionActive;
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

  void _applyTestResponseHeaders(HttpRequest request) {
    final responseSessionId = request.headers.value(
      'x-test-response-session-id',
    );
    if (responseSessionId != null) {
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
    request.response.write('id: $id\n');
    request.response.write('event: message\n');
    request.response.write('data: ${jsonEncode(message)}\n\n');
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

    await _assertSecureMcpRequiresBearer(binding);
    await _assertSecureMcpRejectsBearer(
      binding,
      _unknownAccessToken,
      acceptedMessage:
          'Bearer-protected MCP endpoint accepted an unknown access token.',
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
    await _smokeMcpOriginPolicy(binding, grant);
    await _smokeMcpCorsPreflight(binding, serviceSession, grant);
    final otherGrant = await _issueTicketHttpGrant(
      binding,
      authId: _otherTicketAuthId,
      ticket: _otherTicketSecret,
    );
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
                'include_registered_procedures': true,
                'include_pubsub_tools': true,
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
      label: 'direct JSON connectanum.tools.list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.listConnectanumToolsDirect(
          id: 'secure-unauthenticated-tools',
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON batch connectanum.tools.list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.postBatch(
          [
            {
              'jsonrpc': '2.0',
              'id': 'secure-unauthenticated-direct-batch-tools',
              'method': 'connectanum.tools.list',
              'params': {},
            },
          ],
          streamable: false,
          includeSession: false,
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON connectanum.api.list',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.request(
          'connectanum.api.list',
          id: 'secure-unauthenticated-api-list',
          params: const <String, Object?>{'kind': 'topic'},
          streamable: false,
          includeSession: false,
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON connectanum.pubsub.subscribe',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.request(
          'connectanum.pubsub.subscribe',
          id: 'secure-unauthenticated-pubsub-subscribe',
          params: const <String, Object?>{
            'topic': _topic,
            'queueLimit': 1,
          },
          streamable: false,
          includeSession: false,
        );
      },
    );
    await _expectSecureMcpUnauthorized(
      client,
      label: 'direct JSON batch WAMP meta/pubsub',
      acceptedMessage: acceptedMessage,
      operation: () async {
        await client.postBatch(
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
          streamable: false,
          includeSession: false,
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
    defaultProtocolVersion: protocolVersion,
    authGrant: authGrant,
  );
  try {
    final initializeId = '$label-supported-$protocolVersion-initialize';
    final initialize = await client.initialize(id: initializeId);
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
    if (client.protocolVersion !=
        McpStreamableHttpClient.latestProtocolVersion) {
      throw StateError(
        'MCP $label initialize with protocol $protocolVersion did not '
        'negotiate the latest server protocol version.',
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
  final client = _protocolVersionClient(
    endpoint,
    defaultProtocolVersion: _unsupportedProtocolVersion,
    authGrant: authGrant,
  );
  try {
    await client.initialize(id: '$label-unsupported-protocol-initialize');
    throw StateError('MCP $label accepted an unsupported protocol version.');
  } on McpStreamableHttpException catch (error) {
    if (error.statusCode != HttpStatus.badRequest) {
      throw StateError(
        'MCP $label unsupported protocol version returned ${error.statusCode} '
        'instead of ${HttpStatus.badRequest}.',
      );
    }
    if (client.sessionId != null || client.lastEventId != null) {
      throw StateError(
        'MCP $label unsupported protocol rejection leaked Streamable '
        'session state.',
      );
    }
  } finally {
    client.close();
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
  final directTools = await client.listConnectanumToolsDirect(
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
    await client.listConnectanumToolsDirect(id: '$label-disallowed-direct');
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
  if (catalogBatch.length != 4) {
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
  if (!jsonEncode(
    _jsonRpcResult(
      catalogBatch[2],
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
      catalogBatch[3],
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
  String? bearerToken,
}) async {
  final response = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    message,
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
  String? bearerToken,
}) async {
  final response = await _mcpRawDirectJsonRpcResponse(
    client,
    endpoint,
    messages,
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
  String? bearerToken,
}) async {
  final request = await client.postUrl(endpoint);
  request.headers.set('Accept', 'application/json');
  request.headers.set('Origin', _allowedOrigin);
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  request.headers.contentType = ContentType.json;
  final body = utf8.encode(jsonEncode(message));
  request.contentLength = body.length;
  request.add(body);
  return _mcpRawResponseFrom(await request.close());
}

Future<void> _mcpRawDirectJsonPubSubPollUntil(
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
      return;
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
  final missingMethodId = '$label-streamable-cors-missing-method';
  final missingMethod = await _mcpRawJsonPost(
    client,
    endpoint,
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': missingMethodId,
      'method': 'tools/list',
    },
    sessionId: sessionId,
    bearerToken: bearerToken,
    includeMethodHeader: false,
  );
  _assertMcpCorsErrorResponse(
    missingMethod,
    expectedStatus: HttpStatus.badRequest,
    label: '$label Streamable missing Mcp-Method',
    sessionId: sessionId,
    bodyContains: 'Mcp-Method',
  );

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
}) async {
  final client = McpStreamableHttpClient.withBearerToken(
    _mcpEndpoint(binding, secure: true),
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

Future<void> _smokeStreamableSessionReuseIsolation(
  RouterBinding binding,
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
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
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
  await _assertActiveDirectJsonRequestRejectsBearerWithoutSessionLoss(
    client,
    () async {
      await client.request(
        'connectanum.pubsub.subscribe',
        id: '$label-rejected-direct-pubsub-subscribe',
        params: {'topic': _topic, 'queueLimit': 1},
        streamable: false,
        includeSession: false,
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
      await client.postBatch(
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
        streamable: false,
        includeSession: false,
      );
    },
    sessionId: sessionId,
    lastEventId: lastEventId,
    method: 'direct JSON batch WAMP meta/pubsub',
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
        ? await client.listConnectanumToolsDirect(
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
  final method = directJson ? 'connectanum.tools.list' : 'tools/list';
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
        ? await client.request(
            method,
            id: pageLabel,
            params: params,
            streamable: false,
            includeSession: false,
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
        ? await client.request(
            method,
            id: pageLabel,
            params: params,
            streamable: false,
            includeSession: false,
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
    final pageBatch = await client.postBatch(
      [
        {
          'jsonrpc': '2.0',
          'id': pageId,
          'method': method,
          'params': {'cursor': cursor},
        },
      ],
      streamable: !directJson,
      includeSession: !directJson,
      headers: <String, String>{'x-consumer-trace': pageId},
    );
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
  _expectSortedUniqueWampApiCatalog(
    apiCatalog,
    label: 'Generic direct JSON-RPC API list',
  );

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

  final notificationBatch = await client.postBatch(
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
    streamable: false,
    includeSession: false,
    headers: const <String, String>{
      'x-consumer-trace': 'router-direct-notification-batch',
    },
  );
  if (notificationBatch != null) {
    throw StateError(
      'Generic direct JSON-RPC notification-only batch returned a response.',
    );
  }

  await client.notification(
    'notifications/progress',
    params: const <String, Object?>{
      'progressToken': 'generic-direct-single-notification',
      'progress': 1,
    },
    streamable: false,
    includeSession: false,
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
  await _smokeMcpPubSubQueueOverflow(
    client,
    serviceSession,
    label: label,
    directJson: false,
  );

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
        'id': '$label-direct-batch-tools',
        'method': 'connectanum.tools.list',
        'params': {},
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
  if (responses == null || responses.length != 6) {
    throw StateError('Direct JSON batch did not return six responses.');
  }
  if (responses[0]['id'] != '$label-direct-batch-api' ||
      !jsonEncode(responses[0]).contains(_procedure)) {
    throw StateError('Direct JSON batch API catalog response was invalid.');
  }
  await _expectBatchToolCatalogPages(
    client,
    headResponse: responses[1],
    headId: '$label-direct-batch-tools',
    label: 'Direct JSON batch connectanum.tools.list',
    idPrefix: '$label-direct-batch-tools',
    method: 'connectanum.tools.list',
    directJson: true,
  );
  if (responses[2]['id'] != '$label-direct-batch-call' ||
      !jsonEncode(responses[2]).contains(taskId)) {
    throw StateError('Direct JSON batch procedure call response was invalid.');
  }
  if (responses[3]['id'] != '$label-direct-batch-tools-alias' ||
      !jsonEncode(responses[3]).contains(aliasTaskId) ||
      !jsonEncode(responses[3]).contains(_headerWrappedNote)) {
    throw StateError(
      'Direct JSON batch plural tool alias response was invalid.',
    );
  }
  final resourceCursor = _expectPaginatedCatalogHead(
    responses[4],
    id: '$label-direct-batch-resources',
    label: 'Direct JSON batch resources/list',
    resultKey: 'resources',
    field: 'uri',
    fieldDescription: 'resource URIs',
    expectedPrimary: _resourceUri,
  );
  if (responses[5]['id'] != '$label-direct-batch-prompt' ||
      !jsonEncode(responses[5]).contains(promptTaskId)) {
    throw StateError('Direct JSON batch prompts/get response was invalid.');
  }
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

  final cursorBatch = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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

  final topicListId = '$label-direct-batch-wamp-topic-list';
  final topicDescribeId = '$label-direct-batch-wamp-topic-describe';
  final topics = await client.postBatch(
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
    streamable: false,
    includeSession: false,
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
  final resources = await client.listResources(
    id: '$label-$mode-resources',
    directJson: directJson,
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
  final resourcePage = await client.listResources(
    id: '$label-$mode-resources-page',
    cursor: resourceCursor,
    directJson: directJson,
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

  final contents = await client.readResource(
    _resourceUri,
    id: '$label-$mode-resource-read',
    directJson: directJson,
    headers: <String, String>{
      'x-consumer-trace': '$label-$mode-resource-read',
    },
  );
  if (!jsonEncode(contents).contains(
    'Consumer package router-hosted MCP context document.',
  )) {
    throw StateError('MCP resources/read did not return route context.');
  }

  final templates = await client.listResourceTemplates(
    id: '$label-$mode-resource-templates',
    directJson: directJson,
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
  final templatePage = await client.listResourceTemplates(
    id: '$label-$mode-resource-templates-page',
    cursor: templateCursor,
    directJson: directJson,
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

  final prompts = await client.listPrompts(
    id: '$label-$mode-prompts',
    directJson: directJson,
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
  final promptPage = await client.listPrompts(
    id: '$label-$mode-prompts-page',
    cursor: promptCursor,
    directJson: directJson,
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
  final prompt = await client.getPrompt(
    _promptName,
    id: '$label-$mode-prompt',
    arguments: {'taskId': taskId},
    directJson: directJson,
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
  Map<String, String> headers = const <String, String>{},
}
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final events = await client.pollWampEvents(
      subscriptionHandle,
      id: 'streamable-poll-${DateTime.now().microsecondsSinceEpoch}',
      limit: 4,
      directJson: directJson,
      headers: headers,
    );
    if (events.events.isNotEmpty) {
      return events;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for MCP pub/sub event.');
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
  final subscription = await client.subscribeWampTopic(
    _topic,
    id: '$label-$suffix-overflow-subscribe',
    queueLimit: 1,
    directJson: directJson,
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
    await client.unsubscribeWampTopic(
      subscription.handle,
      id: '$label-$suffix-overflow-unsubscribe',
      directJson: directJson,
      headers: <String, String>{
        'x-consumer-trace': '$label-$suffix-overflow-unsubscribe',
      },
    );
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

  await client.deleteSession(
    headers: <String, String>{'x-consumer-trace': '$label-streamable-delete'},
  );
  if (client.sessionId != null || client.lastEventId != null) {
    throw StateError('Streamable MCP DELETE did not clear session state.');
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
    dart pub get
    dart analyze
    if [[ -n "$hook_native_lib" ]]; then
      CONNECTANUM_NATIVE_LIB="$hook_native_lib" dart run bin/main.dart
    else
      dart run bin/main.dart
    fi
  )
)
