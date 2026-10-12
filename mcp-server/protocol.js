'use strict';

// The slice of MCP (JSON-RPC 2.0 over stdio) this server needs: initialize,
// ping, tools/list and tools/call. Hand-written instead of using the official
// SDK so the plugin stays free of npm dependencies.

const PROTOCOL_VERSION = '2025-06-18';

const PARSE_ERROR = -32700;
const INVALID_REQUEST = -32600;
const METHOD_NOT_FOUND = -32601;
const INVALID_PARAMS = -32602;
const INTERNAL_ERROR = -32603;

const TYPE_CHECKS = {
  string: (value) => typeof value === 'string',
  boolean: (value) => typeof value === 'boolean',
  integer: (value) => Number.isInteger(value),
};

// Checks `args` against the small subset of JSON Schema the tools use (type,
// enum, minimum, maximum, required). Returns an error message, or null.
function validateArguments(schema, args) {
  for (const key of schema.required || []) {
    if (args[key] === undefined) return `"${key}" is required`;
  }
  for (const [key, rule] of Object.entries(schema.properties || {})) {
    const value = args[key];
    if (value === undefined) continue;
    if (rule.type && !TYPE_CHECKS[rule.type](value)) return `"${key}" must be a ${rule.type}`;
    if (rule.enum && !rule.enum.includes(value)) return `"${key}" must be one of: ${rule.enum.join(', ')}`;
    if (rule.minimum !== undefined && value < rule.minimum) return `"${key}" must be at least ${rule.minimum}`;
    if (rule.maximum !== undefined && value > rule.maximum) return `"${key}" must be at most ${rule.maximum}`;
  }
  return null;
}

// Returns an async function that takes one parsed JSON-RPC message and returns
// the response to send, or null when none is due (notifications).
function createHandler({ serverInfo, tools, runner }) {
  const toolsByName = new Map(tools.map((tool) => [tool.name, tool]));
  const listing = tools.map(({ name, description, inputSchema }) => ({ name, description, inputSchema }));

  const result = (id, value) => ({ jsonrpc: '2.0', id, result: value });
  const failure = (id, code, message) => ({ jsonrpc: '2.0', id, error: { code, message } });

  async function callTool(id, params) {
    const tool = toolsByName.get(params.name);
    if (!tool) return failure(id, INVALID_PARAMS, `Unknown tool: ${params.name}`);

    const args = params.arguments === undefined ? {} : params.arguments;
    if (args === null || typeof args !== 'object' || Array.isArray(args)) {
      return failure(id, INVALID_PARAMS, `Invalid arguments for ${tool.name}: expected an object`);
    }
    const problem = validateArguments(tool.inputSchema, args);
    if (problem) return failure(id, INVALID_PARAMS, `Invalid arguments for ${tool.name}: ${problem}`);

    // A tool that fails is a normal result flagged isError, so the model sees
    // the reason; protocol errors are reserved for malformed requests.
    try {
      const text = await tool.handler(args, runner);
      return result(id, { content: [{ type: 'text', text }] });
    } catch (err) {
      return result(id, { content: [{ type: 'text', text: err.message }], isError: true });
    }
  }

  async function dispatch(id, method, params) {
    switch (method) {
      case 'initialize':
        return result(id, { protocolVersion: PROTOCOL_VERSION, capabilities: { tools: {} }, serverInfo });
      case 'ping':
        return result(id, {});
      case 'tools/list':
        return result(id, { tools: listing });
      case 'tools/call':
        return callTool(id, params);
      default:
        return id !== undefined ? failure(id, METHOD_NOT_FOUND, `Method not found: ${method}`) : null;
    }
  }

  return async function handle(message) {
    if (message === null || typeof message !== 'object' || Array.isArray(message)) {
      return failure(null, INVALID_REQUEST, 'Invalid request: expected a JSON object');
    }
    const { id, method } = message;
    // A message without a method is a response to a request this server never
    // sent (it sends none); there is nothing to answer.
    if (typeof method !== 'string') return null;

    const params = message.params !== null && typeof message.params === 'object' ? message.params : {};
    try {
      return await dispatch(id, method, params);
    } catch (err) {
      console.error(`[sapi-voice-kit] failed to handle ${method}: ${err.stack || err}`);
      return id !== undefined ? failure(id, INTERNAL_ERROR, 'Internal error') : null;
    }
  };
}

module.exports = { createHandler, validateArguments, PROTOCOL_VERSION, PARSE_ERROR };
