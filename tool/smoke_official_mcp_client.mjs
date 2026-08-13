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

function requireStructuredToolResult(result, label, toolName) {
  requireCondition(
    result.isError !== true,
    `${label} ${toolName} returned an error`,
  );
  requireCondition(
    result.structuredContent !== null &&
      typeof result.structuredContent === 'object' &&
      !Array.isArray(result.structuredContent),
    `${label} ${toolName} omitted structured content`,
  );
  return result.structuredContent;
}

async function runPubSubLifecycle(client, label) {
  const topic = 'image.smoke.events';
  const eventSource = `official-client-${label}`;
  let handle;
  try {
    const subscribe = requireStructuredToolResult(
      await client.callTool({
        name: 'connectanum.pubsub.subscribe',
        arguments: { topic, queueLimit: 4 },
      }),
      label,
      'connectanum.pubsub.subscribe',
    );
    requireCondition(
      typeof subscribe.handle === 'string' && subscribe.handle.length > 0,
      `${label} subscribe omitted its explicit handle`,
    );
    requireCondition(
      subscribe.topic === topic,
      `${label} subscribe returned the wrong topic`,
    );
    handle = subscribe.handle;

    const publish = requireStructuredToolResult(
      await client.callTool({
        name: 'connectanum.pubsub.publish',
        arguments: {
          topic,
          argumentsKeywords: { source: eventSource },
          acknowledge: true,
          options: { exclude_me: false },
        },
      }),
      label,
      'connectanum.pubsub.publish',
    );
    requireCondition(
      publish.topic === topic && publish.acknowledged === true,
      `${label} publish was not acknowledged on the requested topic`,
    );

    let receivedEvent;
    for (
      let attempt = 0;
      attempt < 40 && receivedEvent === undefined;
      attempt += 1
    ) {
      const poll = requireStructuredToolResult(
        await client.callTool({
          name: 'connectanum.pubsub.poll',
          arguments: { handle, limit: 4 },
        }),
        label,
        'connectanum.pubsub.poll',
      );
      requireCondition(
        poll.handle === handle && poll.topic === topic,
        `${label} poll did not preserve its explicit handle and topic`,
      );
      requireCondition(
        Array.isArray(poll.events) && poll.dropped === 0,
        `${label} poll returned invalid or dropped event evidence`,
      );
      receivedEvent = poll.events.find(
        (event) => event.argumentsKeywords?.source === eventSource,
      );
      if (receivedEvent === undefined) {
        await new Promise((resolve) => setTimeout(resolve, 25));
      }
    }
    requireCondition(
      receivedEvent !== undefined,
      `${label} did not receive its self-delivered publication`,
    );

    const unsubscribe = requireStructuredToolResult(
      await client.callTool({
        name: 'connectanum.pubsub.unsubscribe',
        arguments: { handle },
      }),
      label,
      'connectanum.pubsub.unsubscribe',
    );
    requireCondition(
      unsubscribe.handle === handle && unsubscribe.unsubscribed === true,
      `${label} unsubscribe did not release its explicit handle`,
    );
    handle = undefined;
    return {
      pubSubHandleReturned: true,
      pubSubPublishAcknowledged: true,
      pubSubEventReceived: true,
      pubSubUnsubscribed: true,
    };
  } finally {
    if (handle !== undefined) {
      const cleanup = await client.callTool({
        name: 'connectanum.pubsub.unsubscribe',
        arguments: { handle },
      });
      requireCondition(
        cleanup.isError !== true,
        `${label} failed to clean up its pub/sub handle`,
      );
    }
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
    const instructions = client.getInstructions();
    const tools = await client.listTools();
    const prompts = await client.listPrompts();
    const resources = await client.listResources();
    const templates = await client.listResourceTemplates();
    const read = await client.readResource({
      uri: 'connectanum://router-image/context',
    });
    const promptSubject = `official client ${label}`;
    const prompt = await client.getPrompt({
      name: 'inspect-router-image',
      arguments: { subject: promptSubject },
    });
    const call = await client.callTool({
      name: 'wamp.session.count',
      arguments: {},
    });

    const pubSubToolNames = [
      'connectanum.pubsub.subscribe',
      'connectanum.pubsub.publish',
      'connectanum.pubsub.poll',
      'connectanum.pubsub.unsubscribe',
    ];

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
    requireCondition(
      typeof instructions === 'string' &&
        instructions.includes('router image MCP'),
      `${label} client did not receive the router instructions`,
    );
    requireCondition(read.contents.length > 0, `${label} resource read was empty`);
    requireCondition(
      prompt.messages.some(
        (message) =>
          message.role === 'user' &&
          message.content?.type === 'text' &&
          message.content.text.includes(promptSubject),
      ),
      `${label} prompt did not render its subject argument`,
    );
    requireCondition(call.isError !== true, `${label} tool call returned an error`);
    requireCondition(
      pubSubToolNames.every((name) =>
        tools.tools.some((tool) => tool.name === name),
      ),
      `${label} client did not discover the complete pub/sub tool lifecycle`,
    );
    const pubSub = await runPubSubLifecycle(client, label);

    summary = {
      era: client.getProtocolEra(),
      sessionId: transport.sessionId ?? null,
      sessionTerminated: false,
      toolCount: tools.tools.length,
      promptCount: prompts.prompts.length,
      resourceCount: resources.resources.length,
      resourceTemplateCount: templates.resourceTemplates.length,
      resourceContentCount: read.contents.length,
      instructionsReceived: true,
      promptRendered: true,
      toolCallSucceeded: true,
      ...pubSub,
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
