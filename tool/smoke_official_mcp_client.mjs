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

async function runClient(endpoint, label, options, transportOptions) {
  const transport = new StreamableHTTPClientTransport(
    endpoint,
    transportOptions,
  );
  const client = new Client(
    { name: `connectanum-${label}-consumer-smoke`, version: '1.0.0' },
    options,
  );
  let summary;
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

    summary = {
      era: client.getProtocolEra(),
      sessionId: transport.sessionId ?? null,
      sessionTerminated: false,
      toolCount: tools.tools.length,
      promptCount: prompts.prompts.length,
      resourceCount: resources.resources.length,
      resourceTemplateCount: templates.resourceTemplates.length,
      resourceContentCount: read.contents.length,
      toolCallSucceeded: true,
    };
    if (transport.sessionId !== undefined) {
      await transport.terminateSession();
      requireCondition(
        transport.sessionId === undefined,
        `${label} transport retained its terminated session`,
      );
      summary.sessionTerminated = true;
    }
    return summary;
  } finally {
    await client.close();
  }
}

async function issueTicketGrant(endpoint, realm, authId, ticket) {
  const challengeResponse = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ realm, authmethod: 'ticket', authid: authId }),
  });
  requireCondition(
    challengeResponse.status === 401,
    'router ticket authentication did not return a challenge',
  );
  const challenge = await challengeResponse.json();
  requireCondition(
    typeof challenge.state === 'string' && challenge.state.length > 0,
    'router ticket authentication challenge omitted state',
  );

  const grantResponse = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ state: challenge.state, signature: ticket }),
  });
  requireCondition(
    grantResponse.ok,
    'router ticket authentication did not issue a grant',
  );
  const grant = await grantResponse.json();
  requireCondition(
    typeof grant.access_token === 'string' && grant.access_token.length > 0,
    'router ticket grant omitted its access token',
  );
  requireCondition(
    String(grant.token_type).toLowerCase() === 'bearer',
    'router ticket grant omitted its bearer token type',
  );
  return grant.access_token;
}

async function runProtectedClient(endpoint, label, options, accessToken) {
  const authState = {
    currentToken: 'router-image-rejected-official-client-token',
    tokenCalls: 0,
    unauthorizedCalls: 0,
  };
  const authProvider = {
    token: async () => {
      authState.tokenCalls += 1;
      return authState.currentToken;
    },
    onUnauthorized: async ({ response }) => {
      requireCondition(
        response.status === 401,
        `${label} auth provider received a non-401 response`,
      );
      authState.unauthorizedCalls += 1;
      requireCondition(
        authState.unauthorizedCalls === 1,
        `${label} auth provider was refreshed more than once`,
      );
      authState.currentToken = accessToken;
    },
  };

  const result = await runClient(endpoint, label, options, { authProvider });
  requireCondition(
    authState.unauthorizedCalls === 1,
    `${label} did not exercise the rejected bearer retry`,
  );
  requireCondition(
    authState.tokenCalls > 1,
    `${label} did not request bearer credentials per operation`,
  );
  return {
    ...result,
    authRetrySucceeded: true,
    unauthorizedCalls: authState.unauthorizedCalls,
    tokenCalls: authState.tokenCalls,
  };
}

const [
  publicEndpointArgument,
  protectedEndpointArgument,
  authEndpointArgument,
] = process.argv.slice(2);
const authRealm = process.env.OFFICIAL_MCP_AUTH_REALM;
const authId = process.env.OFFICIAL_MCP_AUTH_ID;
const authTicket = process.env.OFFICIAL_MCP_AUTH_TICKET;
if (
  !publicEndpointArgument ||
  !protectedEndpointArgument ||
  !authEndpointArgument ||
  !authRealm ||
  !authId ||
  !authTicket
) {
  throw new Error(
    'Usage: smoke_official_mcp_client.mjs PUBLIC_ENDPOINT ' +
      'PROTECTED_ENDPOINT AUTH_ENDPOINT with OFFICIAL_MCP_AUTH_REALM, ' +
      'OFFICIAL_MCP_AUTH_ID, and OFFICIAL_MCP_AUTH_TICKET set',
  );
}
const publicEndpoint = new URL(publicEndpointArgument);
const protectedEndpoint = new URL(protectedEndpointArgument);
const authEndpoint = new URL(authEndpointArgument);

const publicLegacy = await runClient(publicEndpoint, 'public-legacy');
const publicModern = await runClient(publicEndpoint, 'public-modern', {
  versionNegotiation: { mode: 'auto' },
});
const accessToken = await issueTicketGrant(
  authEndpoint,
  authRealm,
  authId,
  authTicket,
);
const protectedLegacy = await runProtectedClient(
  protectedEndpoint,
  'protected-legacy',
  undefined,
  accessToken,
);
const protectedModern = await runProtectedClient(
  protectedEndpoint,
  'protected-modern',
  { versionNegotiation: { mode: 'auto' } },
  accessToken,
);

requireCondition(
  publicLegacy.era === 'legacy' && protectedLegacy.era === 'legacy',
  'legacy negotiation was not selected',
);
requireCondition(
  typeof publicLegacy.sessionId === 'string' &&
    publicLegacy.sessionId.length > 0 &&
    typeof protectedLegacy.sessionId === 'string' &&
    protectedLegacy.sessionId.length > 0,
  'legacy negotiation did not establish a Streamable HTTP session',
);
requireCondition(
  publicLegacy.sessionTerminated && protectedLegacy.sessionTerminated,
  'legacy Streamable HTTP session was not terminated',
);
requireCondition(
  publicModern.era === 'modern' && protectedModern.era === 'modern',
  'modern negotiation was not selected',
);
requireCondition(
  publicModern.sessionId === null && protectedModern.sessionId === null,
  'modern negotiation unexpectedly established a compatibility session',
);

console.log(
  JSON.stringify({
    officialMcpClientSummary: {
      sdk: `@modelcontextprotocol/client@${
        process.env.OFFICIAL_MCP_CLIENT_VERSION ?? 'unknown'
      }`,
      public: { legacy: publicLegacy, modern: publicModern },
      protected: { legacy: protectedLegacy, modern: protectedModern },
    },
  }),
);
