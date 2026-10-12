'use strict';

// Local MCP server for Claude Cowork. Cowork does not fire plugin hooks and its
// own shell is a remote sandbox with no PowerShell, so this server is how the
// plugin speaks and is configured there. See tools.js for the tools.
//
// stdout carries only JSON-RPC; diagnostics go to stderr, where Claude
// Desktop's MCP log picks them up.

const path = require('node:path');
const readline = require('node:readline');

const { createHandler, PARSE_ERROR } = require('./protocol');
const { createPowerShellRunner } = require('./powershell');
const { TOOLS } = require('./tools');
const { version } = require('../.claude-plugin/plugin.json');

function main() {
  const runner = createPowerShellRunner({ pluginRoot: path.resolve(__dirname, '..'), namespace: 'cowork' });
  const handle = createHandler({ serverInfo: { name: 'sapi-voice-kit', version }, tools: TOOLS, runner });
  const send = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);

  // Anything that reaches here is a bug, not a request error (handle() answers
  // those). Say why before dying: otherwise the client only reports
  // "Connection closed", with no reason.
  const die = (kind) => (err) => {
    console.error(`[sapi-voice-kit] ${kind}: ${err && err.stack || err}`);
    process.exit(1);
  };
  process.on('uncaughtException', die('uncaught exception'));
  process.on('unhandledRejection', die('unhandled rejection'));

  readline.createInterface({ input: process.stdin, terminal: false }).on('line', async (line) => {
    if (!line.trim()) return;

    let message;
    try {
      message = JSON.parse(line);
    } catch {
      send({ jsonrpc: '2.0', id: null, error: { code: PARSE_ERROR, message: 'Parse error' } });
      return;
    }

    const response = await handle(message);
    if (response) send(response);
  });

  console.error(`[sapi-voice-kit] ${version} ready`);
}

main();
