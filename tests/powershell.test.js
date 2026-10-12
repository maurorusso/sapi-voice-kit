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

function withFixtures(scripts, fn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sapi-voice-kit-test-'));
  fs.mkdirSync(path.join(root, 'scripts'));
  for (const [name, lines] of Object.entries(scripts)) {
    fs.writeFileSync(path.join(root, 'scripts', name), lines.join('\r\n'), 'utf8');
  }
  return Promise.resolve(fn(root)).finally(() => fs.rmSync(root, { recursive: true, force: true }));
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

test('a failing or stopped script does not block the ones queued behind it', () => withFixtures({
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
