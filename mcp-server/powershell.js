'use strict';

const { spawn } = require('node:child_process');
const path = require('node:path');

const DEFAULT_TIMEOUT_MS = 180000;

// The Windows PowerShell that ships with the system, by its full path. A bare
// "powershell" would also be looked up in the current folder first, so a
// powershell.exe planted in a repository the server happens to start in would
// run instead.
const WINDOWS_POWERSHELL = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');

// The only variables a script gets from the server's own environment: what
// Windows PowerShell needs to start, find the user's profile and write its
// temp files, plus the plugin's own SAPI_VOICE_DATA_DIR. Each is read by its own name, written out here: never the
// environment as a whole and never a name computed at run time, so anything
// sensitive that happens to be set there is never read, let alone forwarded (no
// script needs it).
function childEnvironment(namespace) {
  const inherited = {
    ALLUSERSPROFILE: process.env.ALLUSERSPROFILE,
    APPDATA: process.env.APPDATA,
    ComSpec: process.env.ComSpec,
    HOMEDRIVE: process.env.HOMEDRIVE,
    HOMEPATH: process.env.HOMEPATH,
    LOCALAPPDATA: process.env.LOCALAPPDATA,
    NUMBER_OF_PROCESSORS: process.env.NUMBER_OF_PROCESSORS,
    OS: process.env.OS,
    PATH: process.env.PATH,
    PATHEXT: process.env.PATHEXT,
    PROCESSOR_ARCHITECTURE: process.env.PROCESSOR_ARCHITECTURE,
    ProgramData: process.env.ProgramData,
    ProgramFiles: process.env.ProgramFiles,
    PSModulePath: process.env.PSModulePath,
    SAPI_VOICE_DATA_DIR: process.env.SAPI_VOICE_DATA_DIR,
    PUBLIC: process.env.PUBLIC,
    SystemDrive: process.env.SystemDrive,
    SystemRoot: process.env.SystemRoot,
    TEMP: process.env.TEMP,
    TMP: process.env.TMP,
    USERPROFILE: process.env.USERPROFILE,
    windir: process.env.windir,
  };
  const environment = {};
  for (const [name, value] of Object.entries(inherited)) {
    if (value !== undefined) environment[name] = value;
  }
  environment.SAPI_VOICE_NAMESPACE = namespace;
  return environment;
}

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
function createPowerShellRunner({ pluginRoot, namespace, timeoutMs = DEFAULT_TIMEOUT_MS, spawnFn = spawn, executable = WINDOWS_POWERSHELL }) {
  let queue = Promise.resolve();

  // Resolves { ok, output, reason }: stdout text, and why it failed if it did.
  // A script that exits non-zero still returns its stdout, which is where the
  // scripts explain what was wrong. Its stderr is never passed on: PowerShell
  // error text carries local paths and the user name, and the model on the other
  // end may be in the cloud.
  function execute(script, args, { stdin, timeoutMs: callTimeoutMs = timeoutMs }) {
    return new Promise((resolve) => {
      const scriptPath = path.join(pluginRoot, 'scripts', script);
      const ps = spawnFn(executable, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args], {
        cwd: pluginRoot,
        env: childEnvironment(namespace),
        windowsHide: true,
        timeout: callTimeoutMs,
      });

      let stdout = '';
      ps.stdout.setEncoding('utf8');
      ps.stdout.on('data', (chunk) => { stdout += chunk; });
      ps.stderr.resume();

      // A script that exits early closes its stdin; that must not crash the server.
      ps.stdin.on('error', () => {});
      ps.stdin.end(stdin === undefined ? undefined : Buffer.from(stdin, 'utf8'));

      ps.on('error', (err) => resolve({ ok: false, output: stdout.trim(), reason: `could not start powershell: ${err.message}` }));
      ps.on('close', (code, signal) => {
        const output = stdout.trim();
        if (signal) return resolve({ ok: false, output, reason: `${script} was stopped (${signal}), probably after ${callTimeoutMs} ms` });
        if (code !== 0) return resolve({ ok: false, output, reason: `${script} exited with code ${code}` });
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

module.exports = { createPowerShellRunner, childEnvironment };
