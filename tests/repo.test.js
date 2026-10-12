'use strict';

// Checks that tie the repository's files together.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');
const readJson = (relativePath) => JSON.parse(read(relativePath).replace(/^\uFEFF/, ''));

test('every manifest and config file is valid JSON', () => {
  for (const file of ['.claude-plugin/plugin.json', '.claude-plugin/marketplace.json', 'hooks/hooks.json', '.mcp.json']) {
    assert.doesNotThrow(() => readJson(file), file);
  }
});

test('the plugin and marketplace manifests agree on the version', () => {
  const plugin = readJson('.claude-plugin/plugin.json');
  const marketplace = readJson('.claude-plugin/marketplace.json');
  assert.match(plugin.version, /^\d+\.\d+\.\d+$/);
  assert.equal(marketplace.version, plugin.version);
  for (const entry of marketplace.plugins) assert.equal(entry.version, plugin.version, entry.name);
});

test('every script a hook runs exists', () => {
  const { hooks } = readJson('hooks/hooks.json');
  const commands = Object.values(hooks).flat().flatMap((group) => group.hooks.map((hook) => hook.command));
  assert.ok(commands.length >= 2);
  for (const command of commands) {
    const script = /scripts\\([\w-]+\.ps1)/.exec(command);
    assert.ok(script, `no script in: ${command}`);
    assert.ok(fs.existsSync(path.join(root, 'scripts', script[1])), script[1]);
  }
});

test('the MCP server entry in .mcp.json exists and needs no environment settings', () => {
  const server = readJson('.mcp.json').mcpServers['sapi-voice-kit'];
  assert.equal(server.command, 'node');
  const entry = server.args[0].replace('${CLAUDE_PLUGIN_ROOT}', root);
  assert.ok(fs.existsSync(entry), entry);
  assert.equal(server.env, undefined);
});

// The parameter names a script declares: everything between `param(` and its matching `)`.
function declaredParameters(script) {
  const source = read(`scripts/${script}`);
  const start = source.indexOf('param(');
  if (start === -1) return [];
  let depth = 0;
  let end = start + 'param'.length;
  do {
    if (source[end] === '(') depth++;
    if (source[end] === ')') depth--;
    end++;
  } while (depth > 0 && end < source.length);
  return [...source.slice(start, end).matchAll(/\$(\w+)/g)].map((match) => match[1].toLowerCase());
}

test('every parameter a hook or skill passes to a script is declared by that script', () => {
  const skills = fs.readdirSync(path.join(root, 'skills')).map((dir) => `skills/${dir}/SKILL.md`);
  let checked = 0;
  for (const file of ['hooks/hooks.json', ...skills]) {
    for (const [, script, rest] of read(file).matchAll(/scripts[\\/]+([\w-]+\.ps1)([^\r\n`]*)/g)) {
      const declared = declaredParameters(script);
      for (const [, name] of rest.matchAll(/\s-([A-Za-z]+)/g)) {
        assert.ok(declared.includes(name.toLowerCase()), `${file}: ${script} has no -${name}`);
        checked++;
      }
    }
  }
  assert.ok(checked > 0, 'found no parameters to check; the pattern is stale');
});

test('no hook or skill passes the removed -PluginData or -Namespace parameters', () => {
  const skills = fs.readdirSync(path.join(root, 'skills')).map((dir) => `skills/${dir}/SKILL.md`);
  for (const file of ['hooks/hooks.json', ...skills]) {
    assert.doesNotMatch(read(file), /-PluginData|-Namespace/, file);
  }
});

test('every PowerShell function the documentation names exists in scripts/', () => {
  const defined = new Set();
  const scripts = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) {
      const relative = `${dir}/${entry.name}`;
      if (entry.isDirectory()) walk(relative);
      else if (entry.name.endsWith('.ps1')) scripts.push(relative);
    }
  };
  walk('scripts');
  for (const file of scripts) {
    for (const [, name] of read(file).matchAll(/^function ([\w-]+)/gm)) defined.add(name);
  }

  const builtIn = new Set(['Get-Culture', 'Import-PowerShellDataFile', 'Invoke-Pester']);
  const documents = ['README.md', 'ARCHITECTURE.md', 'CLAUDE.md', 'CONTRIBUTING.md', 'SECURITY.md'];
  for (const file of documents) {
    for (const [name] of read(file).matchAll(/(?:Get|Set|Invoke|ConvertTo|Add|Test|Save|Read|Write|Resolve|Find|New|Split|Initialize|Assert|Wait)-[A-Z][A-Za-z0-9]+/g)) {
      assert.ok(defined.has(name) || builtIn.has(name), `${file} mentions ${name}, which no script defines`);
    }
  }
});
