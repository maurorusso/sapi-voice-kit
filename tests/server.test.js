// Unit tests for mcp-server/server.js - dev-only tooling, never shipped
// with the plugin. Run with:
//   node --test tests/server.test.js
//
// Uses node:test, built into Node since v18 - no install needed, matching
// this project's own zero-runtime-dependency stance for its own tooling.
//
// Only the pure, synthesis-free pieces are covered here (path
// construction, config parsing, the static tool schema) - requiring
// server.js as a module (guarded by `require.main === module` in the file
// itself) never attaches a stdin listener or spawns anything, so these
// tests never touch real audio or a real PowerShell process.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

test('sharedDataDir() builds the same fixed path scripts/common.ps1 uses', () => {
  const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sapi-voice-kit-test-'));
  const originalUserProfile = process.env.USERPROFILE;
  process.env.USERPROFILE = fakeHome;
  try {
    delete require.cache[require.resolve('../mcp-server/server.js')];
    const { sharedDataDir } = require('../mcp-server/server.js');
    const expected = path.join(fakeHome, '.claude', 'plugins', 'data', 'sapi-voice-kit-shared');
    assert.equal(sharedDataDir(), expected);
  } finally {
    process.env.USERPROFILE = originalUserProfile;
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});

test('readConfiguredMode() reads config.cowork.mode, not config.local.mode', async () => {
  const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sapi-voice-kit-test-'));
  const originalUserProfile = process.env.USERPROFILE;
  process.env.USERPROFILE = fakeHome;
  try {
    delete require.cache[require.resolve('../mcp-server/server.js')];
    const server = require('../mcp-server/server.js');
    const dir = server.sharedDataDir();
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, 'config.json'),
      JSON.stringify({ local: { mode: 'active' }, cowork: { mode: 'natural' } }),
      'utf8'
    );
    assert.equal(await server.readConfiguredMode(), 'natural');
  } finally {
    process.env.USERPROFILE = originalUserProfile;
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});

test('readConfiguredMode() strips a UTF-8 BOM instead of defaulting to natural', async () => {
  // Regression test for the exact bug this function's own comment
  // describes: PowerShell's Set-Content -Encoding UTF8 writes a BOM, and
  // JSON.parse throws on it unless it's stripped first.
  const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sapi-voice-kit-test-'));
  const originalUserProfile = process.env.USERPROFILE;
  process.env.USERPROFILE = fakeHome;
  try {
    delete require.cache[require.resolve('../mcp-server/server.js')];
    const server = require('../mcp-server/server.js');
    const dir = server.sharedDataDir();
    fs.mkdirSync(dir, { recursive: true });
    const bom = Buffer.from([0xEF, 0xBB, 0xBF]);
    const json = Buffer.from(JSON.stringify({ cowork: { mode: 'active' } }), 'utf8');
    fs.writeFileSync(path.join(dir, 'config.json'), Buffer.concat([bom, json]));
    assert.equal(await server.readConfiguredMode(), 'active');
  } finally {
    process.env.USERPROFILE = originalUserProfile;
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});

test('readConfiguredMode() defaults to natural when config.json is absent', async () => {
  const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sapi-voice-kit-test-'));
  const originalUserProfile = process.env.USERPROFILE;
  process.env.USERPROFILE = fakeHome;
  try {
    delete require.cache[require.resolve('../mcp-server/server.js')];
    const server = require('../mcp-server/server.js');
    assert.equal(await server.readConfiguredMode(), 'natural');
  } finally {
    process.env.USERPROFILE = originalUserProfile;
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});

test('readConfiguredMode() defaults to natural when only "local" is set (cowork untouched)', async () => {
  const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sapi-voice-kit-test-'));
  const originalUserProfile = process.env.USERPROFILE;
  process.env.USERPROFILE = fakeHome;
  try {
    delete require.cache[require.resolve('../mcp-server/server.js')];
    const server = require('../mcp-server/server.js');
    const dir = server.sharedDataDir();
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'config.json'), JSON.stringify({ local: { mode: 'active' } }), 'utf8');
    assert.equal(await server.readConfiguredMode(), 'natural');
  } finally {
    process.env.USERPROFILE = originalUserProfile;
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});

test('readConfiguredMode() retries and recovers from a transient torn/corrupt read', async () => {
  // Exercises the actual point of the retry loop, not just its edge cases:
  // the first read hits a truncated file (simulating this landing mid a
  // PowerShell writer's non-atomic Set-Content), and a fix lands inside
  // the retry's short delay window - the function must recover instead of
  // giving up on the first failure.
  const fakeHome = fs.mkdtempSync(path.join(os.tmpdir(), 'sapi-voice-kit-test-'));
  const originalUserProfile = process.env.USERPROFILE;
  process.env.USERPROFILE = fakeHome;
  try {
    delete require.cache[require.resolve('../mcp-server/server.js')];
    const server = require('../mcp-server/server.js');
    const dir = server.sharedDataDir();
    fs.mkdirSync(dir, { recursive: true });
    const configPath = path.join(dir, 'config.json');
    fs.writeFileSync(configPath, '{"cowork": {"mode": "acti', 'utf8');
    setTimeout(() => {
      fs.writeFileSync(configPath, JSON.stringify({ cowork: { mode: 'active' } }), 'utf8');
    }, 10);
    assert.equal(await server.readConfiguredMode(), 'active');
  } finally {
    process.env.USERPROFILE = originalUserProfile;
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});

test('TOOLS: every entry has a name, description, and inputSchema, and read_aloud is present', () => {
  delete require.cache[require.resolve('../mcp-server/server.js')];
  const { TOOLS } = require('../mcp-server/server.js');
  assert.ok(Array.isArray(TOOLS) && TOOLS.length > 0);
  for (const tool of TOOLS) {
    assert.equal(typeof tool.name, 'string');
    assert.ok(tool.name.length > 0);
    assert.equal(typeof tool.description, 'string');
    assert.ok(tool.description.length > 0);
    assert.equal(typeof tool.inputSchema, 'object');
    assert.equal(tool.inputSchema.type, 'object');
  }
  assert.ok(TOOLS.some((t) => t.name === 'read_aloud'));
});

test('TOOLS: no duplicate tool names', () => {
  delete require.cache[require.resolve('../mcp-server/server.js')];
  const { TOOLS } = require('../mcp-server/server.js');
  const names = TOOLS.map((t) => t.name);
  assert.equal(new Set(names).size, names.length);
});
