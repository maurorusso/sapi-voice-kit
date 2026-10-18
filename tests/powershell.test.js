'use strict';

// Runs the real PowerShell runner against small fixture scripts in a temp
// plugin root, so process handling is tested without any audio or voices.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createPowerShellRunner } = require('../mcp-server/powershell');

const commonPs1 = path.resolve(__dirname, '..', 'scripts', 'common.ps1');
const loadCommon = `. '${commonPs1.replace(/'/g, "''")}'`;

// The retries are for Windows: the PowerShell child can still be exiting, and still hold the folder, when it is removed.
function withFixtures(scripts, fn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sapi-voice-kit-test-'));
  fs.mkdirSync(path.join(root, 'scripts'));
  for (const [name, lines] of Object.entries(scripts)) {
    fs.writeFileSync(path.join(root, 'scripts', name), lines.join('\r\n'), 'utf8');
  }
  return Promise.resolve(fn(root)).finally(() => fs.rmSync(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 }));
}

const runnerFor = (root, options = {}) => createPowerShellRunner({ pluginRoot: root, namespace: 'cowork', ...options });

test('stdout comes back as UTF-8, not OEM-codepage garbage', () => withFixtures({
  // The accents are built from char codes so the fixture file itself is ASCII.
  'accents.ps1': [
    loadCommon,
    'Write-Output ("Garc" + [char]0xED + "a " + [char]0xBF + "Confirm" + [char]0xE1 + "s " + [char]0x2014 + " " + [char]0xF1)',
  ],
}, async (root) => {
  const result = await runnerFor(root).run('accents.ps1');
  assert.equal(result.ok, true, result.reason);
  assert.equal(result.output, 'García ¿Confirmás — ñ');
}));

test('the namespace reaches the script as SAPI_VOICE_NAMESPACE, not as an argument', () => withFixtures({
  'env.ps1': ['Write-Output "$env:SAPI_VOICE_NAMESPACE|$($args.Count)"'],
}, async (root) => {
  const result = await runnerFor(root).run('env.ps1');
  assert.equal(result.output, 'cowork|0');
}));

test('stdin text is delivered to the script as UTF-8', () => withFixtures({
  'stdin.ps1': [loadCommon, '(Read-StdinUtf8).Length'],
}, async (root) => {
  const text = 'ñandú ¿sí?';
  const result = await runnerFor(root).run('stdin.ps1', [], { stdin: text });
  assert.equal(result.output, String(text.length));
}));

test('a failing script still returns what it printed, with the reason', () => withFixtures({
  'fail.ps1': ['Write-Output "something is wrong"', 'exit 3'],
}, async (root) => {
  const result = await runnerFor(root).run('fail.ps1');
  assert.equal(result.ok, false);
  assert.equal(result.output, 'something is wrong');
  assert.match(result.reason, /exited with code 3/);
}));

test('a failing script does not hand its raw error text to the caller', () => withFixtures({
  'noisy.ps1': ['[Console]::Error.WriteLine("C:\\Users\\someone\\secret.txt not found")', 'exit 2'],
}, async (root) => {
  const result = await runnerFor(root).run('noisy.ps1');
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'noisy.ps1 exited with code 2');
}));

test('PowerShell is started by its full path from the plugin folder, so a planted powershell.exe cannot take its place', async () => {
  const { EventEmitter } = require('node:events');
  const calls = [];
  const spawnFn = (command, args, options) => {
    calls.push({ command, options });
    const child = new EventEmitter();
    for (const name of ['stdout', 'stderr']) {
      child[name] = new EventEmitter();
      child[name].setEncoding = () => {};
      child[name].resume = () => {};
    }
    child.stdin = new EventEmitter();
    child.stdin.end = () => {};
    setImmediate(() => child.emit('close', 0, null));
    return child;
  };
  const result = await createPowerShellRunner({ pluginRoot: 'C:\\plugin', namespace: 'cowork', spawnFn }).run('x.ps1');
  assert.equal(result.ok, true);
  assert.ok(path.isAbsolute(calls[0].command), calls[0].command);
  assert.match(calls[0].command, /System32.WindowsPowerShell.v1\.0.powershell\.exe$/i);
  assert.equal(calls[0].options.cwd, 'C:\\plugin');
});

test('a call can ask for a longer time limit than the runner default', () => withFixtures({
  'slowish.ps1': ['Start-Sleep -Milliseconds 1500', 'Write-Output done'],
}, async (root) => {
  const runner = runnerFor(root, { timeoutMs: 400 });
  assert.equal((await runner.run('slowish.ps1')).ok, false);
  const result = await runner.run('slowish.ps1', [], { timeoutMs: 20000 });
  assert.equal(result.ok, true, result.reason);
  assert.equal(result.output, 'done');
}));

test('a script that runs too long is stopped', () => withFixtures({
  'slow.ps1': ['Start-Sleep -Seconds 20'],
}, async (root) => {
  const result = await runnerFor(root, { timeoutMs: 700 }).run('slow.ps1');
  assert.equal(result.ok, false);
  assert.match(result.reason, /was stopped/);
}));

test('scripts run one at a time, in the order they were requested', () => withFixtures({
  // Each run reports when it started and finished; if they overlapped, or ran
  // out of order, one of the checks below fails.
  'span.ps1': [
    'param($Label)',
    '$start = [DateTime]::UtcNow.Ticks',
    'Start-Sleep -Milliseconds 400',
    'Write-Output "$Label $start $([DateTime]::UtcNow.Ticks)"',
  ],
}, async (root) => {
  const runner = runnerFor(root);
  const results = await Promise.all(['first', 'second', 'third'].map((label) => runner.run('span.ps1', ['-Label', label])));
  const spans = results.map((result) => result.output.split(' '));
  assert.deepEqual(spans.map(([label]) => label), ['first', 'second', 'third']);
  for (let i = 1; i < spans.length; i++) {
    assert.ok(BigInt(spans[i][1]) >= BigInt(spans[i - 1][2]), `${spans[i][0]} started before ${spans[i - 1][0]} finished`);
  }
}));

test('a failing script does not block the ones queued behind it', () => withFixtures({
  'fail.ps1': ['exit 2'],
  'ok.ps1': ['Write-Output fine'],
}, async (root) => {
  const runner = runnerFor(root);
  const [failed, ok] = await Promise.all([runner.run('fail.ps1'), runner.run('ok.ps1')]);
  assert.equal(failed.ok, false);
  assert.equal(ok.output, 'fine');
}));

test('argument values reach the script verbatim, whatever characters they contain', () => withFixtures({
  'echo-arg.ps1': ['param([string]$Value)', 'Write-Output $Value'],
}, async (root) => {
  const runner = runnerFor(root);
  const hostile = ["it's \"quoted\"", '$(Get-Date)', '`whoami`', 'a; Remove-Item x', 'a | b', '%PATH%', 'two words', 'a\tb'];
  for (const value of hostile) {
    const result = await runner.run('echo-arg.ps1', ['-Value', value]);
    assert.equal(result.output, value);
  }
}));

test('a script gets what PowerShell needs from the environment, and no credentials', () => withFixtures({
  'env.ps1': ['Write-Output "$env:FAKE_API_TOKEN|$env:GITHUB_TOKEN|$($env:USERPROFILE.Length -gt 0)|$($env:SystemRoot.Length -gt 0)"'],
}, async (root) => {
  const saved = { FAKE_API_TOKEN: process.env.FAKE_API_TOKEN, GITHUB_TOKEN: process.env.GITHUB_TOKEN };
  process.env.FAKE_API_TOKEN = 'secret-1';
  process.env.GITHUB_TOKEN = 'secret-2';
  try {
    const result = await runnerFor(root).run('env.ps1');
    assert.equal(result.output, '||True|True');
  } finally {
    for (const [name, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[name]; else process.env[name] = value;
    }
  }
}));

test('childEnvironment forwards what PowerShell needs and the namespace, never anything else', () => {
  const { childEnvironment } = require('../mcp-server/powershell');
  const saved = process.env.MY_SECRET_TOKEN;
  process.env.MY_SECRET_TOKEN = 'x';
  try {
    const result = childEnvironment('cowork');
    assert.equal(result.SAPI_VOICE_NAMESPACE, 'cowork');
    assert.equal(result.USERPROFILE, process.env.USERPROFILE);
    assert.equal(result.SAPI_VOICE_DATA_DIR, process.env.SAPI_VOICE_DATA_DIR);
    assert.equal(Object.hasOwn(result, 'MY_SECRET_TOKEN'), false);
    for (const name of ['USERNAME', 'USERDOMAIN', 'COMPUTERNAME']) {
      assert.equal(Object.hasOwn(result, name), false, `${name} names the account or machine and no script needs it`);
    }
    assert.ok(Object.values(result).every((value) => typeof value === 'string'), 'no undefined values reach spawn');
  } finally {
    if (saved === undefined) delete process.env.MY_SECRET_TOKEN; else process.env.MY_SECRET_TOKEN = saved;
  }
});
