/// Latest stable MCP protocol revision supported by this package.
const String mcpLatestProtocolVersion = '2026-07-28';

/// Latest revision supported by the initialize/session-based MCP core.
const String mcpLatestSessionProtocolVersion = '2025-11-25';

/// Stateless per-request metadata revision supported by router-hosted HTTP.
const String mcpLatestStatelessProtocolVersion = mcpLatestProtocolVersion;

const Set<String> mcpSupportedProtocolVersions = <String>{
  '2025-03-26',
  '2025-06-18',
  mcpLatestSessionProtocolVersion,
  mcpLatestStatelessProtocolVersion,
};

String mcpNegotiateProtocolVersion(String requestedProtocolVersion) {
  return requestedProtocolVersion != mcpLatestStatelessProtocolVersion &&
          mcpSupportedProtocolVersions.contains(requestedProtocolVersion)
      ? requestedProtocolVersion
      : mcpLatestSessionProtocolVersion;
}
