#!/usr/bin/env node

import {
  Client,
  StreamableHTTPClientTransport,
} from '@modelcontextprotocol/client';

function requireCondition(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function runClient(endpoint, label, options) {
  const transport = new StreamableHTTPClientTransport(endpoint);
  const client = new Client(
    { name: `connectanum-${label}-consumer-smoke`, version: '1.0.0' },
    options,
  );
  try {
    await client.connect(transport);
    const tools = await client.listTools();
    const prompts = await client.listPrompts();
    const resources = await client.listResources();
    const templates = await client.listResourceTemplates();
    const read = await client.readResource({
      uri: 'connectanum://router-image/context',
    });
    const call = await client.callTool({
      name: 'wamp.session.count',
      arguments: {},
    });

    requireCondition(
      tools.tools.some((tool) => tool.name === 'wamp.session.count'),
      `${label} client did not discover wamp.session.count`,
    );
    requireCondition(
      prompts.prompts.some((prompt) => prompt.name === 'inspect-router-image'),
      `${label} client did not discover the packaged prompt`,
    );
    requireCondition(
      resources.resources.some(
        (resource) => resource.uri === 'connectanum://router-image/context',
      ),
      `${label} client did not discover the packaged resource`,
    );
    requireCondition(
      templates.resourceTemplates.some(
        (template) =>
          template.uriTemplate === 'connectanum://router-image/item/{itemId}',
      ),
      `${label} client did not discover the packaged resource template`,
    );
    requireCondition(read.contents.length > 0, `${label} resource read was empty`);
    requireCondition(call.isError !== true, `${label} tool call returned an error`);

    return {
      era: client.getProtocolEra(),
      sessionId: transport.sessionId ?? null,
      toolCount: tools.tools.length,
      promptCount: prompts.prompts.length,
      resourceCount: resources.resources.length,
      resourceTemplateCount: templates.resourceTemplates.length,
      resourceContentCount: read.contents.length,
      toolCallSucceeded: true,
    };
  } finally {
    await client.close();
  }
}

const endpointArgument = process.argv[2];
if (!endpointArgument) {
  throw new Error('Usage: smoke_official_mcp_client.mjs ENDPOINT');
}
const endpoint = new URL(endpointArgument);

const legacy = await runClient(endpoint, 'legacy');
const modern = await runClient(endpoint, 'modern', {
  versionNegotiation: { mode: 'auto' },
});

requireCondition(legacy.era === 'legacy', 'legacy negotiation was not selected');
requireCondition(
  typeof legacy.sessionId === 'string' && legacy.sessionId.length > 0,
  'legacy negotiation did not establish a Streamable HTTP session',
);
requireCondition(modern.era === 'modern', 'modern negotiation was not selected');
requireCondition(
  modern.sessionId === null,
  'modern negotiation unexpectedly established a compatibility session',
);

console.log(
  JSON.stringify({
    officialMcpClientSummary: {
      sdk: `@modelcontextprotocol/client@${
        process.env.OFFICIAL_MCP_CLIENT_VERSION ?? 'unknown'
      }`,
      legacy,
      modern,
    },
  }),
);
