'use strict';

// Starts the real server process and talks to it over stdio, the way an MCP
// client does.

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const { spawn } = require('node:child_process');

const serverPath = path.resolve(__dirname, '..', 'mcp-server', 'server.js');

// Sends each line, closes stdin, and returns the lines the server wrote to stdout.
function converse(lines, env = process.env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [serverPath], { stdio: ['pipe', 'pipe', 'pipe'], env });
    let stdout = '';
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.on('error', reject);
    child.on('close', () => resolve(stdout.split('\n').filter(Boolean)));
    child.stdin.end(`${lines.join('\n')}\n`);
  });
}

test('stdout carries only JSON-RPC: replies to requests, errors for bad input, nothing for notifications', async () => {
  const replies = (await converse([
    JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }),
    JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }),
    'this is not json',
    'null',
    JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }),
  ])).map((line) => JSON.parse(line));

  // Replies may interleave, because requests are handled concurrently.
  const byId = (id) => replies.find((reply) => reply.id === id);
  const byCode = (code) => replies.find((reply) => reply.error && reply.error.code === code);

  assert.equal(replies.length, 4);
  assert.equal(byId(1).result.serverInfo.name, 'sapi-voice-kit');
  assert.equal(byId(2).result.tools.length, 7);
  assert.equal(byCode(-32700).id, null);
  assert.ok(byCode(-32600));
});

test('tool calls sent together take effect in the order sent', async () => {
  // A throwaway home keeps the real settings untouched. The last call is
  // silent only if the mute saved just before it was already in place.
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'sapi-voice-kit-server-'));
  try {
    const call = (id, name, args) => JSON.stringify({ jsonrpc: '2.0', id, method: 'tools/call', params: { name, arguments: args } });
    const replies = (await converse([
      call(1, 'set_mode', { mode: 'active' }),
      call(2, 'set_mute', { state: 'on' }),
      call(3, 'read_aloud', { text: 'prueba' }),
    ], { ...process.env, USERPROFILE: home })).map((line) => JSON.parse(line));

    const byId = (id) => replies.find((reply) => reply.id === id).result.content[0].text;
    assert.match(byId(3), /^Not spoken: .*muted/);
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
});
