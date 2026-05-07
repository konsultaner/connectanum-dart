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
  _expect(
    endpoint.directMethodsWithoutSession.contains('resources/list') &&
        endpoint.directMethodsWithoutSession.contains('prompts/get'),
    'direct JSON resource/prompt helpers included Streamable session state',
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

  _expect(
    endpoint.directMethodsWithoutSession.contains('connectanum.tool.call'),
    'direct JSON WAMP helpers included Streamable session state',
  );
}

final class _AgentMcpEndpoint {
  _AgentMcpEndpoint._(this._server) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;
  final directMethodsWithoutSession = <String>{};
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
    _recordDirectRequest(method, request);

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

  void _recordDirectRequest(String? method, HttpRequest request) {
    if (method != null && request.headers.value('MCP-Session-Id') == null) {
      directMethodsWithoutSession.add(method);
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

  await _assertActiveStreamableRequestRejectsBearer(
    () async {
      await client.listTools(id: '$label-rejected-session-tools');
    },
    method: 'POST tools/list',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    () async {
      await client.poll();
    },
    method: 'GET SSE poll',
    acceptedMessage: acceptedMessage,
  );
  await _assertActiveStreamableRequestRejectsBearer(
    () async {
      await client.deleteSession();
    },
    method: 'DELETE session',
    acceptedMessage: acceptedMessage,
  );
}

Future<void> _assertActiveStreamableRequestRejectsBearer(
  Future<void> Function() request, {
  required String method,
  required String acceptedMessage,
}) async {
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

  final result = await client.callConnectanumMethodDirect(
    _procedure,
    id: '$label-direct-call',
    params: {'taskId': 'T-$label-direct', 'note': _headerWrappedNote},
  );
  final resultJson = jsonEncode(result);
  if (!resultJson.contains('T-$label-direct') ||
      !resultJson.contains(_headerWrappedNote)) {
    throw StateError('Direct JSON tool call did not return expected payload.');
  }

  await _smokeDirectJsonSingleError(client, label: label);
  await _smokeDirectJsonBatch(client, label: label);
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

  await _smokeStreamableSingleError(client, label: label);
  await _smokeStreamableBatch(client, label: label);
  await _smokeResourcesAndPrompts(client, label: label);
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

  await _smokeDirectJsonBatch(client, label: '$label-after-streamable');
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

Future<void> _smokeDirectJsonBatch(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final previousSessionId = client.sessionId;
  final previousEventId = client.lastEventId;
  final taskId = 'T-$label-direct-batch';
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
  if (responses == null || responses.length != 4) {
    throw StateError('Direct JSON batch did not return four responses.');
  }
  if (responses[0]['id'] != '$label-direct-batch-api' ||
      !jsonEncode(responses[0]).contains(_procedure)) {
    throw StateError('Direct JSON batch API catalog response was invalid.');
  }
  if (responses[1]['id'] != '$label-direct-batch-call' ||
      !jsonEncode(responses[1]).contains(taskId)) {
    throw StateError('Direct JSON batch procedure call response was invalid.');
  }
  if (responses[2]['id'] != '$label-direct-batch-resources' ||
      !jsonEncode(responses[2]).contains(_resourceUri)) {
    throw StateError('Direct JSON batch resources/list response was invalid.');
  }
  if (responses[3]['id'] != '$label-direct-batch-prompt' ||
      !jsonEncode(responses[3]).contains(promptTaskId)) {
    throw StateError('Direct JSON batch prompts/get response was invalid.');
  }
  await _smokeDirectJsonBatchErrorIsolation(client, label: label);
  if (client.sessionId != previousSessionId ||
      client.lastEventId != previousEventId) {
    throw StateError('Direct JSON batch changed Streamable session state.');
  }
}

Future<void> _smokeStreamableBatch(
  McpStreamableHttpClient client, {
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

  await _smokeStreamableBatchErrorIsolation(client, label: label);
}

Future<void> _smokeDirectJsonBatchErrorIsolation(
  McpStreamableHttpClient client, {
  required String label,
}) async {
  final taskId = 'T-$label-direct-batch-error-ok';
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
  if (responses == null || responses.length != 3) {
    throw StateError(
      'Direct JSON batch error smoke did not return three responses.',
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
  if (!jsonEncode(topicCatalog).contains(_topic)) {
    throw StateError('WAMP API topic catalog did not expose $_topic.');
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
  if (!sessionCount.argumentsKeywords.containsKey('count')) {
    throw StateError('WAMP session count did not return count metadata.');
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
