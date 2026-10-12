'use strict';

const { spawn } = require('node:child_process');
const path = require('node:path');

const DEFAULT_TIMEOUT_MS = 180000;

// Runs the plugin's PowerShell scripts for the MCP tools.
//
// Arguments always go through spawn's argument array and never through a
// shell, so tool arguments cannot be interpreted as commands. `namespace` is
// handed to the scripts as SAPI_VOICE_NAMESPACE, which selects the config
// section (see scripts/lib/config.ps1); it is not a per-call argument.
//
// Scripts run one at a time, in the order they were requested. A client may
// send several tool calls at once (set_mode followed by read_aloud, say), and
// running them in parallel would let the second read a setting before the
// first has saved it.
function createPowerShellRunner({ pluginRoot, namespace, timeoutMs = DEFAULT_TIMEOUT_MS, spawnFn = spawn }) {
  let queue = Promise.resolve();

  // Resolves { ok, output, reason }: stdout text, and why it failed if it did.
  // A script that exits non-zero still returns its stdout, which is where the
  // scripts explain what was wrong.
  function execute(script, args, { stdin }) {
    return new Promise((resolve) => {
      const scriptPath = path.join(pluginRoot, 'scripts', script);
      const ps = spawnFn('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args], {
        env: { ...process.env, SAPI_VOICE_NAMESPACE: namespace },
        windowsHide: true,
        timeout: timeoutMs,
      });

      let stdout = '';
      let stderr = '';
      ps.stdout.setEncoding('utf8');
      ps.stderr.setEncoding('utf8');
      ps.stdout.on('data', (chunk) => { stdout += chunk; });
      ps.stderr.on('data', (chunk) => { stderr += chunk; });

      // A script that exits early closes its stdin; that must not crash the server.
      ps.stdin.on('error', () => {});
      ps.stdin.end(stdin === undefined ? undefined : Buffer.from(stdin, 'utf8'));

      ps.on('error', (err) => resolve({ ok: false, output: stdout.trim(), reason: `could not start powershell: ${err.message}` }));
      ps.on('close', (code, signal) => {
        const output = stdout.trim();
        if (signal) return resolve({ ok: false, output, reason: `${script} was stopped (${signal}), probably after ${timeoutMs} ms` });
        if (code !== 0) return resolve({ ok: false, output, reason: stderr.trim() || `${script} exited with code ${code}` });
        return resolve({ ok: true, output, reason: null });
      });
    });
  }

  function run(script, args = [], options = {}) {
    const result = queue.then(() => execute(script, args, options));
    queue = result.then(() => {}, () => {});
    return result;
  }

  return { run };
}

module.exports = { createPowerShellRunner };
