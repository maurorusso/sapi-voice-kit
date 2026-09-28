// Local stdio MCP server for Claude Cowork/Desktop, where plugin hooks
// (Stop, UserPromptSubmit) don't fire at all (confirmed against multiple
// open anthropics/claude-code issues). Exposes one tool, read_aloud, that
// pipes text to the plugin's own say.ps1 - the exact same mechanism "active"
// mode already uses in the CLI via a shell heredoc, no new speech logic
// here. There's no separate "cowork" mode value - it's the same "active"
// mode, just spoken through this MCP tool instead of a heredoc when the
// client running is Cowork/Desktop instead of the CLI (see
// skills/cowork/SKILL.md, which gates on that).
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

const PLUGIN_ROOT = process.env.PLUGIN_ROOT;
const PLUGIN_DATA = process.env.PLUGIN_DATA;

const rl = readline.createInterface({ input: process.stdin, terminal: false });

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

// Reads config.json's mode directly (no need to shell out to PowerShell
// just to check a field) - same file scripts/common.ps1's Get-VoiceConfig
// reads, default 'natural' if it doesn't exist yet, matching that
// function's own default. Never throws: a missing or corrupt config.json
// shouldn't crash this server any more than it crashes the PowerShell side
// (see Get-VoiceConfig's own try/catch for the same reasoning).
//
// This is a JS port of Get-VoiceConfig/Get-ConfigPath, not a call into
// them - there's no single shared source of truth between this and the
// PowerShell side (the BOM bug below is exactly what that already cost
// once). If config.json's path or default-mode logic ever changes in
// common.ps1, this function has to be updated to match by hand.
function readConfiguredMode() {
  if (!PLUGIN_DATA) return 'natural';
  try {
    let raw = fs.readFileSync(path.join(PLUGIN_DATA, 'config.json'), 'utf8');
    // PowerShell's Set-Content -Encoding UTF8 (used by Save-VoiceConfig in
    // common.ps1) writes a UTF-8 BOM by default - JSON.parse doesn't strip
    // it and throws on it, which silently fell through to the catch below
    // and always returned the 'natural' default regardless of the real
    // configured mode (caught live: set mode to 'active', this function
    // kept reporting 'natural' until this fix). Same family of Windows
    // encoding gotcha this project has hit before (see CLAUDE.md).
    if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
    const config = JSON.parse(raw);
    return config && config.mode ? config.mode : 'natural';
  } catch {
    return 'natural';
  }
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
    if (!PLUGIN_ROOT || !PLUGIN_DATA) {
      resolve({ ok: false, reason: 'plugin-root-or-data-missing' });
      return;
    }
    const sayScript = path.join(PLUGIN_ROOT, 'scripts', 'say.ps1');
    const args = [
      '-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', sayScript,
      '-PluginData', PLUGIN_DATA,
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
        serverInfo: { name: 'sapi-voice-kit', version: '0.7.0' }
      }
    });
  } else if (msg.method === 'notifications/initialized') {
    // no response needed
  } else if (msg.method === 'tools/list') {
    send({
      jsonrpc: '2.0',
      id: msg.id,
      result: {
        tools: [{
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
        }]
      }
    });
  } else if (msg.method === 'tools/call') {
    const toolName = msg.params && msg.params.name;
    if (toolName !== 'read_aloud') {
      send({
        jsonrpc: '2.0',
        id: msg.id,
        error: { code: -32601, message: `Unknown tool: ${toolName}` }
      });
      return;
    }
    const args = (msg.params && msg.params.arguments) || {};
    if (typeof args.text !== 'string' || !args.text.trim()) {
      send({
        jsonrpc: '2.0',
        id: msg.id,
        error: { code: -32602, message: 'Invalid params: "text" is required and must be a non-empty string.' }
      });
      return;
    }
    const force = args.force === true;
    // Enforced here, not just trusted to skills/cowork/SKILL.md's own
    // instructions: in the CLI, "active" mode is gated by a code-enforced
    // hook (prompt-active-mode.ps1's UserPromptSubmit only ever fires when
    // mode=='active'), but a skill is advisory text the model could fail to
    // follow or misjudge - this is that same gate for the Cowork path.
    // force=true still bypasses this, same as it bypasses the muted check
    // in say.ps1 - an explicit on-demand request ("leeme eso") should work
    // regardless of mode, same principle already established for read-last.
    if (!force && readConfiguredMode() !== 'active') {
      send({
        jsonrpc: '2.0',
        id: msg.id,
        result: { content: [{ type: 'text', text: 'Not spoken: sapi-voice-kit is not configured in "active" mode.' }] }
      });
      return;
    }
    const result = await speak(args.text, force);
    send({
      jsonrpc: '2.0',
      id: msg.id,
      result: {
        content: [{
          type: 'text',
          text: result.ok ? 'Spoken.' : `Not spoken: ${result.reason}`
        }]
      }
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
