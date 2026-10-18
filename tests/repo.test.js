'use strict';

// Checks that tie the repository's files together.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
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

test('every parameter an MCP tool passes to a script is declared by that script', () => {
  let checked = 0;
  for (const block of read('mcp-server/tools.js').split(/^  scriptTool\(\{/m).slice(1)) {
    const script = /script: '([\w-]+\.ps1)'/.exec(block)[1];
    const declared = declaredParameters(script);
    for (const [, name] of block.matchAll(/'-([A-Za-z]+)'/g)) {
      assert.ok(declared.includes(name.toLowerCase()), `tools.js: ${script} has no -${name}`);
      checked++;
    }
  }
  assert.ok(checked > 0, 'found no parameters to check; the pattern is stale');
});

test('the skills that carry a copy of the spoken-text guidance keep its three rules', () => {
  // The hook builds its reminder from $script:SpokenTextGuidance; a skill is static
  // markdown, so its copy is checked here for the rules that matter.
  const rules = [/punto/, /site name/, /full (file )?path/];
  for (const file of ['scripts/lib/spoken-text-prompt.ps1', 'skills/read-last/SKILL.md', 'skills/cowork/SKILL.md']) {
    for (const rule of rules) assert.match(read(file), rule, `${file} lost the rule ${rule}`);
  }
});

test('every /sapi-voice-kit: command the documentation names has a skill', () => {
  const skills = new Set(fs.readdirSync(path.join(root, 'skills')));
  let checked = 0;
  for (const file of ['README.md', 'ARCHITECTURE.md', 'CONTRIBUTING.md', '.claude/CLAUDE.md', '.github/ISSUE_TEMPLATE/bug_report.md']) {
    for (const [, name] of read(file).matchAll(/\/sapi-voice-kit:([a-z-]+)/g)) {
      assert.ok(skills.has(name), `${file} names /sapi-voice-kit:${name}, which has no folder in skills/`);
      checked++;
    }
  }
  assert.ok(checked > 0, 'found no commands to check; the pattern is stale');
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

  const builtIn = new Set(['Get-Culture', 'Get-FileHash', 'Import-PowerShellDataFile', 'Invoke-Pester']);
  const documents = ['README.md', 'ARCHITECTURE.md', '.claude/CLAUDE.md', 'CONTRIBUTING.md', 'SECURITY.md'];
  for (const file of documents) {
    for (const [name] of read(file).matchAll(/(?:Get|Set|Invoke|ConvertTo|Add|Test|Save|Read|Write|Resolve|Find|New|Split|Initialize|Assert|Wait)-[A-Z][A-Za-z0-9]+/g)) {
      assert.ok(defined.has(name) || builtIn.has(name), `${file} mentions ${name}, which no script defines`);
    }
  }
});

test('the repository holds only text files and valid PNG images: no stray caches or other binaries', () => {
  // Only files git tracks count: an ignored scratch file on a developer's disk is not part of the repository.
  // The plugin directory accepts text, and complete PNG, JPEG, GIF and WebP images; the only image here is the icon.
  const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const pngEnd = Buffer.from('IEND');
  const isCompletePng = (bytes) => bytes.subarray(0, 8).equals(pngSignature) && bytes.subarray(bytes.length - 8, bytes.length - 4).equals(pngEnd);

  const tracked = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' }).split(String.fromCharCode(0)).filter(Boolean);
  const binaries = tracked.filter((file) => {
    if (!fs.existsSync(path.join(root, file))) return false;
    const bytes = fs.readFileSync(path.join(root, file));
    if (!bytes.includes(0)) return false;
    return !(file.endsWith('.png') && isCompletePng(bytes) && bytes.length < 2 * 1024 * 1024);
  });
  assert.deepEqual(binaries, []);
});

test('every skill description is valid YAML: an unquoted value cannot contain ": " or " #"', () => {
  const skills = fs.readdirSync(path.join(root, 'skills')).map((dir) => `skills/${dir}/SKILL.md`);
  for (const file of skills) {
    const frontMatter = /^---\r?\n([\s\S]*?)\r?\n---/.exec(read(file));
    assert.ok(frontMatter, `${file} has no front matter`);
    const line = frontMatter[1].split(/\r?\n/).find((l) => l.startsWith('description:'));
    assert.ok(line, `${file} has no description`);
    const value = line.slice('description:'.length).trim();
    if (/^["'>|]/.test(value)) continue;
    assert.doesNotMatch(value, /: | #/, `${file}: an unquoted description with ": " or " #" does not parse as YAML`);
  }
});
