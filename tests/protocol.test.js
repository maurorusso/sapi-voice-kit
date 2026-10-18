'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createHandler, validateArguments, PROTOCOL_VERSION } = require('../mcp-server/protocol');

const serverInfo = { name: 'test', version: '1.2.3' };

function toolWith(handler) {
  return {
    name: 'echo',
    description: 'echoes',
    inputSchema: {
      type: 'object',
      properties: {
        text: { type: 'string' },
        mode: { type: 'string', enum: ['a', 'b'] },
        rate: { type: 'integer', minimum: -10, maximum: 10 },
        flag: { type: 'boolean' },
      },
      required: ['text'],
    },
    handler,
  };
}

const handleWith = (handler) => createHandler({ serverInfo, tools: [toolWith(handler)], runner: { marker: 'runner' } });
const call = (handle, args, name = 'echo') => handle({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } });

test('initialize reports the protocol version, capabilities and server info', async () => {
  const response = await handleWith(async () => '')({ id: 7, method: 'initialize', params: {} });
  assert.equal(response.id, 7);
  assert.equal(response.result.protocolVersion, PROTOCOL_VERSION);
  assert.deepEqual(response.result.capabilities, { tools: {} });
  assert.deepEqual(response.result.serverInfo, serverInfo);
});

test('ping answers with an empty result', async () => {
  const response = await handleWith(async () => '')({ id: 2, method: 'ping' });
  assert.deepEqual(response, { jsonrpc: '2.0', id: 2, result: {} });
});

test('notifications get no response', async () => {
  assert.equal(await handleWith(async () => '')({ method: 'notifications/initialized' }), null);
});

test('an unknown method with an id is a method-not-found error; without an id it is ignored', async () => {
  const handle = handleWith(async () => '');
  assert.equal((await handle({ id: 3, method: 'nope' })).error.code, -32601);
  assert.equal(await handle({ method: 'nope' }), null);
});

test('input that is not a JSON-RPC request is rejected or ignored instead of crashing', async () => {
  const handle = handleWith(async () => '');
  for (const message of [null, 5, 'text', []]) {
    assert.equal((await handle(message)).error.code, -32600, JSON.stringify(message));
  }
  // A response (id, no method) is not something this server can answer.
  assert.equal(await handle({ jsonrpc: '2.0', id: 9, result: {} }), null);
});

test('tools/call with missing or malformed params is an invalid-params error', async () => {
  const handle = handleWith(async () => '');
  assert.equal((await handle({ id: 1, method: 'tools/call', params: null })).error.code, -32602);
  assert.equal((await handle({ id: 2, method: 'tools/call' })).error.code, -32602);
  for (const args of [null, 'text', [1]]) {
    assert.equal((await call(handle, args)).error.code, -32602, JSON.stringify(args));
  }
});

test('a bug inside the server becomes an internal error for requests and silence for notifications', async () => {
  const broken = { name: 'broken', description: 'no schema', handler: async () => '' };
  const handle = createHandler({ serverInfo, tools: [broken], runner: {} });
  const originalError = console.error;
  console.error = () => {};
  try {
    const request = await handle({ id: 5, method: 'tools/call', params: { name: 'broken' } });
    assert.equal(request.error.code, -32603);
    assert.equal(await handle({ method: 'tools/call', params: { name: 'broken' } }), null);
  } finally {
    console.error = originalError;
  }
});

test('tools/list exposes name, description and schema but never the handler', async () => {
  const response = await handleWith(async () => '')({ id: 4, method: 'tools/list' });
  assert.equal(response.result.tools.length, 1);
  assert.deepEqual(Object.keys(response.result.tools[0]).sort(), ['description', 'inputSchema', 'name']);
});

test('tools/call returns the handler text and hands the handler the runner', async () => {
  let received;
  const handle = handleWith(async (args, runner) => { received = { args, runner }; return 'hello'; });
  const response = await call(handle, { text: 'x' });
  assert.deepEqual(response.result, { content: [{ type: 'text', text: 'hello' }] });
  assert.deepEqual(received, { args: { text: 'x' }, runner: { marker: 'runner' } });
});

test('a tool that throws becomes a normal result flagged isError', async () => {
  const response = await call(handleWith(async () => { throw new Error('it broke'); }), { text: 'x' });
  assert.equal(response.error, undefined);
  assert.equal(response.result.isError, true);
  assert.equal(response.result.content[0].text, 'it broke');
});

test('an unknown tool is an invalid-params error', async () => {
  const response = await call(handleWith(async () => ''), { text: 'x' }, 'missing');
  assert.equal(response.error.code, -32602);
  assert.match(response.error.message, /Unknown tool: missing/);
});

test('invalid arguments are rejected before the handler runs', async () => {
  let ran = false;
  const handle = handleWith(async () => { ran = true; return ''; });
  for (const args of [{}, { text: 5 }, { text: 'x', mode: 'c' }, { text: 'x', rate: 11 }, { text: 'x', rate: 1.5 }, { text: 'x', flag: 'yes' }]) {
    assert.equal((await call(handle, args)).error.code, -32602, JSON.stringify(args));
  }
  assert.equal(ran, false);
});

test('validateArguments accepts valid input and unknown extra properties', () => {
  const { inputSchema } = toolWith(null);
  assert.equal(validateArguments(inputSchema, { text: 'x', mode: 'a', rate: -10, flag: true }), null);
  assert.equal(validateArguments(inputSchema, { text: 'x', extra: 1 }), null);
});
