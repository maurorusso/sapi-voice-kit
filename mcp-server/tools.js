'use strict';

// The MCP tools. read_aloud is the one that matters in Cowork, where plugin
// hooks do not fire and Cowork's own shell is a remote Linux sandbox with no
// PowerShell; the other tools are the plugin's slash commands made reachable
// there. Each tool runs one PowerShell script and returns what it printed.

const ON_OFF = { type: 'string', enum: ['on', 'off'] };

// Builds a tool that runs `script` with the arguments `toArgs(args)` returns.
function scriptTool({ name, description, inputSchema = { type: 'object', properties: {} }, script, toArgs = () => [], stdin }) {
  return {
    name,
    description,
    inputSchema,
    async handler(args, runner) {
      const result = await runner.run(script, toArgs(args), { stdin: stdin ? stdin(args) : undefined });
      if (!result.ok) throw new Error(result.output || result.reason);
      return result.output;
    },
  };
}

const TOOLS = [
  scriptTool({
    name: 'read_aloud',
    description: 'Speaks the given text aloud with the user\'s configured Windows voice (sapi-voice-kit). Call it at the end of a response with a short, natural, complete spoken version of it: a paraphrase, not a truncated stand-in, with no markdown, no raw file paths or URLs (say the file name only, and "the GitHub link" instead of the URL). Does nothing unless sapi-voice-kit is in "active" mode for Cowork, or force is true.',
    inputSchema: {
      type: 'object',
      properties: {
        text: { type: 'string', description: 'A short, natural spoken version of the response, in the same language as the response, no markdown.' },
        force: { type: 'boolean', description: 'Speak even if muted or not in active mode. Only for an explicit on-demand request ("leeme eso"), never for the normal per-turn call.' },
      },
      required: ['text'],
    },
    script: 'say.ps1',
    stdin: (args) => args.text,
    toArgs: (args) => (args.force === true ? ['-Force'] : ['-RequireMode', 'active']),
  }),
  scriptTool({
    name: 'set_mode',
    description: 'Sets how sapi-voice-kit reads responses in this environment (equivalent to /sapi-voice-kit:mode): natural, literal, summary or active.',
    inputSchema: {
      type: 'object',
      properties: { mode: { type: 'string', enum: ['natural', 'literal', 'summary', 'active'] } },
      required: ['mode'],
    },
    script: 'set-mode.ps1',
    toArgs: (args) => ['-Mode', args.mode],
  }),
  scriptTool({
    name: 'set_mute',
    description: 'Turns automatic reading on or off in this environment (Cowork), without changing the chosen mode (equivalent to /sapi-voice-kit:mute). The CLI and Code tab have their own mute.',
    inputSchema: { type: 'object', properties: { state: ON_OFF }, required: ['state'] },
    script: 'set-mute.ps1',
    toArgs: (args) => ['-State', args.state],
  }),
  scriptTool({
    name: 'set_voice',
    description: 'Sets the voice, language or speaking rate (equivalent to /sapi-voice-kit:voice). Give auto=true to return to automatic detection, otherwise any of voice, language (not together with voice) and rate.',
    inputSchema: {
      type: 'object',
      properties: {
        voice: { type: 'string', description: 'Exact installed voice name, e.g. "Microsoft Laura".' },
        language: { type: 'string', description: 'Language code, e.g. "es-MX".' },
        rate: { type: 'integer', minimum: -10, maximum: 10, description: 'Speaking rate from -10 (slower) to 10 (faster).' },
        auto: { type: 'boolean', description: 'Clear any manual voice/language and detect it from the system language again.' },
      },
    },
    script: 'set-voice.ps1',
    toArgs: (args) => {
      if (args.auto === true) return ['-Auto'];
      const argv = [];
      if (args.voice) argv.push('-Voice', args.voice);
      if (args.language) argv.push('-Language', args.language);
      if (args.rate !== undefined) argv.push('-Rate', String(args.rate));
      return argv;
    },
  }),
  scriptTool({
    name: 'list_voices',
    description: 'Lists every installed voice sapi-voice-kit can use and which one is in use now (equivalent to /sapi-voice-kit:voice with no arguments).',
    script: 'list-voices.ps1',
  }),
  scriptTool({
    name: 'say_test',
    description: 'Speaks a fixed test sentence that exercises every pronunciation and cleanup rule, to check audio and settings by ear (equivalent to /sapi-voice-kit:test).',
    script: 'say-test.ps1',
  }),
  scriptTool({
    name: 'set_debug',
    description: 'Turns diagnostic logging on or off (equivalent to /sapi-voice-kit:debug). Off by default; turn it on only to troubleshoot, then off again.',
    inputSchema: { type: 'object', properties: { state: ON_OFF }, required: ['state'] },
    script: 'set-debug.ps1',
    toArgs: (args) => ['-State', args.state],
  }),
];

module.exports = { TOOLS };
