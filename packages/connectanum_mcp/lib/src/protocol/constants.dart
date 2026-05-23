const String mcpLatestProtocolVersion = '2025-11-25';

const Set<String> mcpSupportedProtocolVersions = <String>{
  '2025-03-26',
  '2025-06-18',
  mcpLatestProtocolVersion,
};

String mcpNegotiateProtocolVersion(String requestedProtocolVersion) {
  return mcpSupportedProtocolVersions.contains(requestedProtocolVersion)
      ? requestedProtocolVersion
      : mcpLatestProtocolVersion;
}
