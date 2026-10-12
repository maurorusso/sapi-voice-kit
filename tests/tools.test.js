'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { TOOLS } = require('../mcp-server/tools');
const { validateArguments } = require('../mcp-server/protocol');

// A runner that records what the tools ask it to run.
function fakeRunner(result = { ok: true, output: '', reason: null }) {
  const calls = [];
  const record = (kind) => async (script, args, options) => {
    calls.push({ kind, script, args, stdin: options && options.stdin });
    return result;
  };
  return { calls, run: record('run') };
}

const tool = (name) => TOOLS.find((candidate) => candidate.name === name);

test('every tool has a unique name, a description, an object schema and a handler', () => {
  const names = TOOLS.map((candidate) => candidate.name);
  assert.equal(new Set(names).size, names.length);
  for (const candidate of TOOLS) {
    assert.ok(candidate.description.length > 20, candidate.name);
    assert.equal(candidate.inputSchema.type, 'object', candidate.name);
    assert.equal(typeof candidate.handler, 'function', candidate.name);
  }
  assert.deepEqual([...names].sort(), ['list_voices', 'read_aloud', 'say_test', 'set_debug', 'set_mode', 'set_mute', 'set_voice']);
});

test('read_aloud pipes the text to say.ps1 and requires active mode', async () => {
  const runner = fakeRunner();
  await tool('read_aloud').handler({ text: 'Hola García' }, runner);
  assert.deepEqual(runner.calls, [{ kind: 'run', script: 'say.ps1', args: ['-RequireMode', 'active'], stdin: 'Hola García' }]);
});

test('read_aloud with force skips the mode requirement instead', async () => {
  const runner = fakeRunner();
  await tool('read_aloud').handler({ text: 'x', force: true }, runner);
  assert.deepEqual(runner.calls[0].args, ['-Force']);
});

test('read_aloud returns what the script says when it declined to speak', async () => {
  const runner = fakeRunner({ ok: true, output: "Not spoken: sapi-voice-kit is not in 'active' mode.", reason: null });
  assert.match(await tool('read_aloud').handler({ text: 'x' }, runner), /Not spoken/);
});

test('settings tools run their script with the matching arguments', async () => {
  const runner = fakeRunner({ ok: true, output: 'done', reason: null });
  await tool('set_mode').handler({ mode: 'active' }, runner);
  await tool('set_mute').handler({ state: 'on' }, runner);
  await tool('set_debug').handler({ state: 'off' }, runner);
  await tool('list_voices').handler({}, runner);
  assert.deepEqual(runner.calls.map(({ kind, script, args }) => [kind, script, args]), [
    ['run', 'set-mode.ps1', ['-Mode', 'active']],
    ['run', 'set-mute.ps1', ['-State', 'on']],
    ['run', 'set-debug.ps1', ['-State', 'off']],
    ['run', 'list-voices.ps1', []],
  ]);
});

test('set_voice builds arguments for each way of calling it', async () => {
  const argsFor = async (input) => {
    const runner = fakeRunner();
    await tool('set_voice').handler(input, runner);
    return runner.calls[0].args;
  };
  assert.deepEqual(await argsFor({ auto: true, voice: 'ignored' }), ['-Auto']);
  assert.deepEqual(await argsFor({ voice: 'Microsoft Laura' }), ['-Voice', 'Microsoft Laura']);
  assert.deepEqual(await argsFor({ language: 'es-MX' }), ['-Language', 'es-MX']);
  assert.deepEqual(await argsFor({ rate: 0 }), ['-Rate', '0']);
  assert.deepEqual(await argsFor({ voice: 'V', rate: -3 }), ['-Voice', 'V', '-Rate', '-3']);
});

test('an argument that looks like a flag stays a single argument value', async () => {
  const runner = fakeRunner();
  await tool('set_voice').handler({ voice: '-Auto' }, runner);
  assert.deepEqual(runner.calls[0].args, ['-Voice', '-Auto']);
});

test('a script that fails surfaces its own message as the tool error', async () => {
  const runner = fakeRunner({ ok: false, output: 'Nothing to change: give -Voice.', reason: 'exit code 1' });
  await assert.rejects(tool('set_voice').handler({}, runner), /Nothing to change/);
});

test('a script that fails without output surfaces the reason', async () => {
  const runner = fakeRunner({ ok: false, output: '', reason: 'could not start powershell' });
  await assert.rejects(tool('set_mode').handler({ mode: 'active' }, runner), /could not start powershell/);
});

test('the set_voice schema bounds the rate to what the script accepts', () => {
  const { inputSchema } = tool('set_voice');
  assert.ok(validateArguments(inputSchema, { rate: 11 }));
  assert.ok(validateArguments(inputSchema, { rate: -11 }));
  assert.equal(validateArguments(inputSchema, { rate: 10 }), null);
});
