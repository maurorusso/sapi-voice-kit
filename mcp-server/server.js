// Local stdio MCP server for Claude Cowork/Desktop, where plugin hooks
// (Stop, UserPromptSubmit) don't fire at all (confirmed against multiple
// open anthropics/claude-code issues). Exposes read_aloud plus the same
// settings commands the CLI has as slash commands (set_mode, set_mute,
// set_voice, list_voices, say_test, set_debug) - Cowork's own shell tool
// runs in a remote Linux sandbox with no PowerShell and no access to this
// machine, so those commands' SKILL.md files can't just shell out there the
// way they do in the CLI. Each tool here runs the same .ps1 script the
// matching slash command already runs, via spawn (no shell), and returns
// its output as the tool result text.
//
// Hand-rolled JSON-RPC 2.0 over stdio instead of the official MCP SDK
// (@modelcontextprotocol/sdk): this project's whole point is zero external
// dependencies (see README - no API keys, no Python, no installers), and
// pulling in an npm package would mean either an npm install step at
// install time (breaks that promise) or vendoring compiled output into the
// repo. This protocol surface is small enough (initialize, tools/list,
// tools/call) that hand-rolling it is the smaller trade-off. Validated live
// (2026-09-27) with a throwaway test server using this exact scaffold,
// confirmed reachable from both a Code session and a real Cowork session,
// with real audio output in both.
//
// Runs on Node because Node already ships with Claude Code/Desktop - no
// extra runtime to install, unlike Python (confirmed not installed on this
// machine during testing).

const { spawn } = require('child_process');
const readline = require('readline');
const path = require('path');
const fs = require('fs');
const os = require('os');

const PLUGIN_ROOT = process.env.PLUGIN_ROOT;
const PLUGIN_DATA = process.env.PLUGIN_DATA;

// Logged once at startup, to stderr (stdout is reserved for JSON-RPC
// responses - writing anything else there would corrupt the protocol
// stream). A "Couldn't start... Connection closed" error in Claude
// Desktop's own MCP panel gives no detail about *why* - this at least puts
// whether these two env vars were even populated at launch into Claude
// Desktop's own MCP log (%APPDATA%\Claude\logs\mcp*.log on Windows), which
// was previously invisible.
console.error(`[sapi-voice-kit] starting. PLUGIN_ROOT=${PLUGIN_ROOT || '(missing)'} PLUGIN_DATA=${PLUGIN_DATA || '(missing)'}`);

// An uncaught exception anywhere below would otherwise crash this process
// silently from Claude Desktop's point of view - it would just see the
// stdio pipe close and report "Connection closed", with no indication this
// was the cause. Logging it to stderr first turns a silent, unexplained
// disconnect into something diagnosable in Claude Desktop's own MCP log.
process.on('uncaughtException', (err) => {
  console.error('[sapi-voice-kit] uncaught exception: ' + (err && err.stack || err));
});
process.on('unhandledRejection', (err) => {
  console.error('[sapi-voice-kit] unhandled rejection: ' + (err && err.stack || err));
});

// Passed as -PluginData to every script this server spawns. Never actually
// empty even if the PLUGIN_DATA env var itself is missing: several scripts
// (say.ps1 in particular) treat an empty -PluginData as "skip config
// entirely" - no mode/mute check, no shared-dir resolution at all - which
// would silently break active-mode's mute check and duplicate-speech guard.
// The exact value only matters as a one-time migration-source hint inside
// Resolve-SharedDataDir (common.ps1) - every script ends up reading/writing
// the same fixed shared directory regardless of what's passed here, so a
// placeholder is fine when the real PLUGIN_DATA is missing.
const PLUGIN_DATA_ARG = PLUGIN_DATA || PLUGIN_ROOT || 'sapi-voice-kit';

// Same fixed, shared data directory scripts/common.ps1's
// Resolve-SharedDataDir computes - one config.json per Windows user
// account, independent of whichever install-specific ${CLAUDE_PLUGIN_DATA}
// this particular install happens to be running from. Before this, Code
// and Cowork each read/wrote their own separate config.json (from their
// own separate plugin cache folders), so /sapi-voice-kit:mode active set
// from Code was invisible to Cowork's read_aloud, which kept reporting
// "not configured in active mode" - confirmed live. This JS port has to be
// kept in sync by hand with Resolve-SharedDataDir - there's no single
// shared source of truth between the PowerShell and Node sides of this
// plugin (see the BOM bug below, which cost exactly that once already).
function sharedDataDir() {
  const home = process.env.USERPROFILE || os.homedir();
  return path.join(home, '.claude', 'plugins', 'data', 'sapi-voice-kit-shared');
}

// Only listens on real stdin when this file is actually run as the server
// (require.main === module) - tests/server.test.js requires this file to
// reach its pure functions/data (sharedDataDir, readConfiguredMode, TOOLS)
// without also attaching a readline listener to the test runner's own
// stdin, which would never close and hang the test process.
const rl = require.main === module
  ? readline.createInterface({ input: process.stdin, terminal: false })
  : null;

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

// Reads config.json's "cowork" namespace mode directly (no need to shell
// out to PowerShell just to check a field) - same file and same namespace
// split scripts/common.ps1's Get-VoiceConfig reads (config.json is
// {"local": {...}, "cowork": {...}} - "local" covers the CLI and Desktop's
// Code tab, indistinguishable to this plugin; "cowork" is everything that
// reaches this plugin through this MCP server, since Cowork's own shell has
// no PowerShell and can only get here via MCP). Default 'natural' if
// absent, matching Get-VoiceConfig's own default. Never throws: a missing
// or corrupt config.json shouldn't crash this server any more than it
// crashes the PowerShell side (see Get-VoiceConfig's own try/catch for the
// same reasoning).
//
// Async, with a short retry-on-parse-failure: this read has no equivalent
// of common.ps1's Local\SapiVoiceKitConfig mutex protecting it (found in
// review - Get-VoiceConfig gained that lock, this JS-side read didn't).
// There's no built-in cross-process lock primitive on the Node side
// without a native addon, so real mutual exclusion with the PowerShell
// writers isn't practical here - instead, a torn read (this landing mid
// Write-ConfigRoot's non-atomic Set-Content) is treated as transient and
// retried a couple of times with a brief delay before falling back to
// 'natural', rather than failing on the first attempt. Config writes
// finish in low single-digit milliseconds, so even one retry almost
// always lands on the settled file. A missing file (ENOENT) is a normal
// "not configured yet" case, not a race, so that one returns immediately
// without retrying.
async function readConfiguredMode() {
  const configPath = path.join(sharedDataDir(), 'config.json');
  const maxAttempts = 3;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      let raw = fs.readFileSync(configPath, 'utf8');
      // PowerShell's Set-Content -Encoding UTF8 (used by Save-VoiceConfig in
      // common.ps1) writes a UTF-8 BOM by default - JSON.parse doesn't strip
      // it and throws on it, which silently fell through to the catch below
      // and always returned the 'natural' default regardless of the real
      // configured mode (caught live: set mode to 'active', this function
      // kept reporting 'natural' until this fix). Same family of Windows
      // encoding gotcha this project has hit before (see CLAUDE.md).
      if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
      const config = JSON.parse(raw);
      const cowork = config && config.cowork;
      return cowork && cowork.mode ? cowork.mode : 'natural';
    } catch (err) {
      if (err.code === 'ENOENT' || attempt === maxAttempts - 1) {
        return 'natural';
      }
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  return 'natural';
}

// Runs one of this plugin's .ps1 scripts (no shell - spawn() with an
// argument array never passes anything through shell parsing) and resolves
// with its exit status and captured stdout, so a tool result can show the
// user exactly what the equivalent slash command would have printed in the
// CLI. Shared by every settings tool below; read_aloud uses speak()
// instead, since that one needs the speakChain queue and -Force plumbing.
function runScript(scriptName, extraArgs) {
  return new Promise((resolve) => {
    if (!PLUGIN_ROOT) {
      resolve({ ok: false, reason: 'plugin-root-missing', output: '' });
      return;
    }
    const scriptPath = path.join(PLUGIN_ROOT, 'scripts', scriptName);
    const args = [
      '-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', scriptPath,
      '-PluginData', PLUGIN_DATA_ARG,
      ...extraArgs,
    ];
    const ps = spawn('powershell', args);
    let stdout = '';
    let stderr = '';
    ps.stdout.on('data', (chunk) => { stdout += chunk.toString('utf8'); });
    ps.stderr.on('data', (chunk) => { stderr += chunk.toString('utf8'); });
    ps.on('error', (err) => {
      resolve({ ok: false, reason: 'powershell-not-available: ' + String(err), output: stdout.trim() });
    });
    ps.on('close', (code) => {
      resolve({
        ok: code === 0,
        reason: code === 0 ? null : `exit-code-${code}${stderr.trim() ? ': ' + stderr.trim() : ''}`,
        output: stdout.trim(),
      });
    });
  });
}

// Pipes $text to say.ps1 via stdin, exactly like the model already does in
// active mode via the single-quoted heredoc (scripts/prompt-active-mode.ps1)
// - spawn() with an argument array never invokes a shell to parse the
// command, so the text never passes through shell parsing at all. No
// heredoc needed here for the same safety property spawn() already gives
// for free.
// Only one speak() runs at a time: without this, two rapid tools/call
// requests (a retry, a double tool-call) would each spawn their own
// powershell/say.ps1 process. The cross-process mutex in common.ps1 already
// stops them from talking over each other, but that just makes the second
// process block for up to 60s waiting its turn - wasted duplicate synthesis
// work instead of a cheap in-process queue.
let speakChain = Promise.resolve();

function speak(text, force) {
  const run = () => new Promise((resolve) => {
    if (!PLUGIN_ROOT) {
      resolve({ ok: false, reason: 'plugin-root-missing' });
      return;
    }
    const sayScript = path.join(PLUGIN_ROOT, 'scripts', 'say.ps1');
    const args = [
      '-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', sayScript,
      '-PluginData', PLUGIN_DATA_ARG,
      '-Namespace', 'cowork',
    ];
    if (force) args.push('-Force');

    // spawn() with an argument array never throws synchronously for a
    // missing executable (e.g. ENOENT) - that only ever surfaces later via
    // the 'error' event below, so there's no need for a try/catch here too.
    const ps = spawn('powershell', args);

    ps.on('error', (err) => {
      // e.g. ENOENT - powershell not found (non-Windows), matches the
      // "windows-only" caveat this plugin already documents elsewhere.
      resolve({ ok: false, reason: 'powershell-not-available: ' + String(err) });
    });
    // ps.stdin is its own Writable stream with its own 'error' event,
    // separate from ps's - without this handler, a write hitting EPIPE
    // (powershell exits abnormally fast, e.g. a bad PLUGIN_ROOT resolving
    // to a missing say.ps1) is an unhandled stream error, which crashes
    // this whole long-lived server process instead of just failing this
    // one call. Caught live in review before shipping.
    ps.stdin.on('error', (err) => {
      resolve({ ok: false, reason: 'stdin-write-failed: ' + String(err) });
    });
    ps.stdin.write(text, 'utf8');
    ps.stdin.end();
    ps.on('close', (code) => {
      resolve(code === 0 ? { ok: true } : { ok: false, reason: `exit-code-${code}` });
    });
  });

  const result = speakChain.then(run);
  // Never let one failed call poison the chain for every call after it.
  speakChain = result.then(() => {}, () => {});
  return result;
}

const TOOLS = [
  {
    name: 'read_aloud',
    description: 'Speaks the given text aloud using the user\'s configured Windows voice (sapi-voice-kit). Call this after writing a response, with a short, natural, complete-enough spoken version of it - a paraphrase, not a truncated or shortened stand-in for the response - not the raw markdown, no raw file paths/URLs (say the file name only, say "the GitHub link" instead of the URL). Only meant to be used when the user has sapi-voice-kit configured in "active" mode; check that first.',
    inputSchema: {
      type: 'object',
      properties: {
        text: {
          type: 'string',
          description: 'A short, natural spoken version of the response, in the same language as the response, no markdown.'
        },
        force: {
          type: 'boolean',
          description: 'Bypass the mute setting (/sapi-voice-kit:mute). Only set true for an explicit on-demand request ("leeme eso"), not for the normal per-turn call.'
        }
      },
      required: ['text']
    }
  },
  {
    name: 'set_mode',
    description: 'Sets sapi-voice-kit\'s reading mode (equivalent to /sapi-voice-kit:mode in the CLI). Use when the user asks to switch how responses are read aloud.',
    inputSchema: {
      type: 'object',
      properties: {
        mode: { type: 'string', enum: ['natural', 'literal', 'summary', 'active'] }
      },
      required: ['mode']
    }
  },
  {
    name: 'set_mute',
    description: 'Turns automatic reading on or off machine-wide, without changing the chosen mode (equivalent to /sapi-voice-kit:mute).',
    inputSchema: {
      type: 'object',
      properties: { state: { type: 'string', enum: ['on', 'off'] } },
      required: ['state']
    }
  },
  {
    name: 'set_voice',
    description: 'Sets the voice, language, or speaking rate sapi-voice-kit uses (equivalent to /sapi-voice-kit:voice). Pass auto=true to go back to automatic voice detection.',
    inputSchema: {
      type: 'object',
      properties: {
        voice: { type: 'string', description: 'Exact installed voice name, e.g. "Microsoft Laura".' },
        language: { type: 'string', description: 'Language code, e.g. "es-MX".' },
        rate: { type: 'integer', description: 'Speaking rate from -10 (slower) to 10 (faster).' },
        auto: { type: 'boolean', description: 'Clear any manual voice/language override and detect automatically again.' }
      }
    }
  },
  {
    name: 'list_voices',
    description: 'Lists every installed speech-synthesis voice sapi-voice-kit can use, and which one is active now (equivalent to /sapi-voice-kit:voice with no arguments).',
    inputSchema: { type: 'object', properties: {} }
  },
  {
    name: 'say_test',
    description: 'Speaks one fixed test sentence that exercises every pronunciation/cleanup rule sapi-voice-kit has, so audio and settings can be verified by ear (equivalent to /sapi-voice-kit:test).',
    inputSchema: { type: 'object', properties: {} }
  },
  {
    name: 'set_debug',
    description: 'Turns sapi-voice-kit\'s diagnostic logging on or off (equivalent to /sapi-voice-kit:debug). Off by default; turn on only to troubleshoot a specific problem, then off again.',
    inputSchema: {
      type: 'object',
      properties: { state: { type: 'string', enum: ['on', 'off'] } },
      required: ['state']
    }
  },
];

function toolResult(id, text) {
  send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text }] } });
}

if (require.main === module) {
rl.on('line', async (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return; }

  if (msg.method === 'initialize') {
    send({
      jsonrpc: '2.0',
      id: msg.id,
      result: {
        protocolVersion: '2025-06-18',
        capabilities: { tools: {} },
        serverInfo: { name: 'sapi-voice-kit', version: '0.8.0' }
      }
    });
  } else if (msg.method === 'notifications/initialized') {
    // no response needed
  } else if (msg.method === 'tools/list') {
    send({ jsonrpc: '2.0', id: msg.id, result: { tools: TOOLS } });
  } else if (msg.method === 'tools/call') {
    const toolName = msg.params && msg.params.name;
    const args = (msg.params && msg.params.arguments) || {};

    if (toolName === 'read_aloud') {
      if (typeof args.text !== 'string' || !args.text.trim()) {
        send({
          jsonrpc: '2.0', id: msg.id,
          error: { code: -32602, message: 'Invalid params: "text" is required and must be a non-empty string.' }
        });
        return;
      }
      const force = args.force === true;
      // Enforced here, not just trusted to skills/cowork/SKILL.md's own
      // instructions: in the CLI, "active" mode is gated by a code-enforced
      // hook (prompt-active-mode.ps1's UserPromptSubmit only ever fires when
      // mode=='active'), but a skill is advisory text the model could fail
      // to follow or misjudge - this is that same gate for the Cowork path.
      // force=true still bypasses this, same as it bypasses the muted check
      // in say.ps1 - an explicit on-demand request ("leeme eso") should work
      // regardless of mode, same principle already established for
      // read-last.
      if (!force && (await readConfiguredMode()) !== 'active') {
        toolResult(msg.id, 'Not spoken: sapi-voice-kit is not configured in "active" mode.');
        return;
      }
      const result = await speak(args.text, force);
      toolResult(msg.id, result.ok ? 'Spoken.' : `Not spoken: ${result.reason}`);
      return;
    }

    // Every settings tool below writes/reads the "cowork" namespace, never
    // "local" - that's the whole point of the split (see the comment on
    // readConfiguredMode above): Cowork gets its own independent
    // mode/voice/mute/debug, separate from whatever the CLI/Code tab has.

    if (toolName === 'set_mode') {
      const result = await runScript('set-mode.ps1', ['-Mode', String(args.mode), '-Namespace', 'cowork']);
      toolResult(msg.id, result.ok ? result.output : `Error: ${result.reason}`);
      return;
    }

    if (toolName === 'set_mute') {
      const result = await runScript('set-mute.ps1', ['-State', String(args.state), '-Namespace', 'cowork']);
      toolResult(msg.id, result.ok ? result.output : `Error: ${result.reason}`);
      return;
    }

    if (toolName === 'set_voice') {
      const extraArgs = [];
      if (args.auto === true) {
        extraArgs.push('-Auto');
      } else {
        if (args.voice) extraArgs.push('-Voice', String(args.voice));
        if (args.language) extraArgs.push('-Language', String(args.language));
        if (typeof args.rate === 'number') extraArgs.push('-Rate', String(args.rate));
      }
      extraArgs.push('-Namespace', 'cowork');
      const result = await runScript('set-voice.ps1', extraArgs);
      toolResult(msg.id, result.ok ? result.output : `Error: ${result.reason}`);
      return;
    }

    if (toolName === 'list_voices') {
      const result = await runScript('list-voices.ps1', ['-Namespace', 'cowork']);
      toolResult(msg.id, result.ok ? result.output : `Error: ${result.reason}`);
      return;
    }

    if (toolName === 'say_test') {
      const result = await runScript('say-test.ps1', ['-Namespace', 'cowork']);
      toolResult(msg.id, result.ok ? result.output : `Error: ${result.reason}`);
      return;
    }

    if (toolName === 'set_debug') {
      const result = await runScript('set-debug.ps1', ['-State', String(args.state), '-Namespace', 'cowork']);
      toolResult(msg.id, result.ok ? result.output : `Error: ${result.reason}`);
      return;
    }

    send({
      jsonrpc: '2.0',
      id: msg.id,
      error: { code: -32601, message: `Unknown tool: ${toolName}` }
    });
  } else if (msg.id !== undefined) {
    // A request (has an id, expects a reply) for a method this server
    // doesn't implement - respond instead of dropping it silently, so a
    // client waiting on a reply doesn't hang. Methods without an id are
    // notifications (like notifications/initialized above) and correctly
    // get no response either way.
    send({
      jsonrpc: '2.0',
      id: msg.id,
      error: { code: -32601, message: `Method not found: ${msg.method}` }
    });
  }
});
}

// Exported for tests/server.test.js only - never required by anything at
// runtime (Claude Desktop/Cowork always runs this file directly as the
// server, never via require()). Kept to exactly the pure, synthesis-free
// pieces: path construction, config parsing, and the static tool schema -
// nothing here spawns a process or touches real audio.
module.exports = { sharedDataDir, readConfiguredMode, TOOLS };
