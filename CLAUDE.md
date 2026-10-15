# sapi-voice-kit — project context

## Goal

Let someone use Claude Code by voice: instead of reading the answer on screen, hear it — the *complete* content of the response, rephrased so it is clear and natural when heard. Not a mechanical truncation and not an ultra-short summary. Built for people who find reading on screen hard, or who prefer to listen.

Native Windows speech only: no API keys, no Python, no installer.

## Invariants — keep these true in any change

- The response on screen is never changed. The voice path is entirely separate from what is displayed.
- What is spoken is a faithful, complete rendering of the answer, not a shortened stand-in (except in `summary` mode, whose purpose is a condensed version).
- Nothing readable is written to disk by default: no logs, no copy of what was spoken. Only `config.json` and a bare timestamp (`.last-active-speech`). Spoken text travels through memory (stdin/stdout), never through a temp file.
- Every `.ps1` and `.psd1` under `scripts/` is saved as UTF-8 **with BOM**: Windows PowerShell 5.1 misreads accents without one. `tests/common.Tests.ps1` enforces it.
- Tool and slash-command arguments reach PowerShell only as discrete `spawn` arguments or a single-quoted heredoc, never through string concatenation into a shell command.
- The plugin has no runtime dependencies. Pester 3.4 (bundled with Windows PowerShell 5.1) and `node:test` are dev-only.

## Layout

```
.claude-plugin/        plugin.json, marketplace.json (this repo is its own marketplace)
hooks/hooks.json       Stop hook (speak.ps1) and UserPromptSubmit hook (prompt-active-mode.ps1)
.mcp.json              registers the MCP server for Claude Code sessions
mcp-server/            Cowork's way in: server.js (wiring), protocol.js, tools.js, powershell.js
scripts/               entry points: speak, say, say-test, prompt-active-mode, list-voices, set-*
scripts/common.ps1     loads scripts/lib/
scripts/lib/           one concern per file; see ARCHITECTURE.md for the table
skills/                slash commands (voice, mode, mute, debug, test, selftest), read-last, cowork
tests/                 Pester (PowerShell library and entry scripts) and node:test (MCP server, repo integrity)
```

## Reading modes

The Stop hook receives `last_assistant_message` and acts on `mode` from `config.json`:

- **natural** (default): the whole response, markdown removed (`Get-CleanedText`).
- **literal**: the whole response exactly as written.
- **summary**: a short summary from a separate `claude -p --no-session-persistence` call (the flag keeps Claude Code from saving a transcript of the response on the user's disk). About 20 s of silence, so opt-in; falls back to natural if the call fails.
- **active**: the model speaks a short paraphrase itself, mid-turn, by piping it to `say.ps1`; the Stop hook stays silent so audio never doubles. In the CLI a UserPromptSubmit hook reminds the model each turn (Claude Code asks for permission once per session). In Cowork, which fires no plugin hooks, `skills/cowork` reminds it to call the `read_aloud` MCP tool.

`muted` pauses automatic reading without losing the mode. `read-last` ("leeme eso") reads one response on demand through `say.ps1 -Force`, which ignores mute.

## Config

One fixed folder per Windows user, shared by every install: `%USERPROFILE%\.claude\plugins\data\sapi-voice-kit-shared\`. `config.json` holds two independent sections:

- `local`: everything started by Claude Code's hooks. The CLI and Desktop's Code tab fire identical hooks, so the plugin cannot tell them apart and they share it.
- `cowork`: everything arriving through the MCP server, the only way Cowork reaches the plugin.

The section is chosen by `SAPI_VOICE_NAMESPACE` (the MCP server sets `cowork` when it spawns a script; default `local`). Reads and writes go through a named mutex (`Local\SapiVoiceKitConfig`); writes are temp-file-and-rename. Speech uses its own mutex (`Local\SapiVoiceKitSpeak`) so parallel sessions take turns instead of talking over each other. The duplicate-speech guard is deliberately **not** per-namespace: it exists to deduplicate across them.

The old per-install config is not migrated (removed in 0.9.0); settings reset once on upgrade.

## Voices

`Get-InstalledVoices` merges OneCore (modern Windows 11 voices, listed first so they win automatic selection) and SAPI5 (classic, on every Windows). A configured voice name or language is matched against that one list. If a voice fails, `Invoke-SpeechSynthesis` falls back: OneCore → SAPI5 voice for the language → SAPI5 default.

Technical terms (git, commit, hook, ...) get IPA pronunciations on the *same* voice, from the dictionary of the language that voice speaks: `scripts/lib/pronunciations/<code>.psd1` (today only `es.psd1`, used for every Spanish voice, es-ES, es-MX, ...). A voice in a language with no file gets no hints, because IPA written for Spanish is wrong for another language. To support another language, add its file; nothing else changes. Words the voices stress wrongly even with IPA are respelled instead (`scripts/lib/respellings/<code>.psd1`, e.g. `natural` -> `naturál`: the written accent is honored where the IPA stress mark is not; the screen text is untouched). Both are skipped in literal mode. The rules for adding entries are at the top of each file. Check changes with `/sapi-voice-kit:test` by ear.

## Cowork

Plugin hooks do not fire in Cowork, and its own shell tool is a remote Linux sandbox with no PowerShell, so the MCP server is how the plugin speaks and is configured there. It exposes `read_aloud`, `set_mode`, `set_mute`, `set_voice`, `list_voices`, `say_test`, `set_debug`; each runs one script and returns its output. `read_aloud` passes `-RequireMode active` to `say.ps1`, so the mode check lives in one place.

Whether Cowork registers the plugin's MCP server by itself is inconsistent: Anthropic documents that a user-installed plugin does not bring MCP servers, yet it has sometimes appeared. The README gives the one-time manual entry as a fallback; adding it when the server already registered duplicates it. Packaging the server as a `.mcpb` Desktop Extension does not help: anthropics/claude-code#26259 shows Cowork's VM only forwards `type: "sdk"` servers and drops stdio ones.

## Working on this repo

- Tests: `powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests"` and `node --test tests/`. CI (`.github/workflows/test.yml`) runs both on every PR and push to `main`, on Windows, with Pester pinned to 3.4.0.
- Audio quality cannot be asserted: run `/sapi-voice-kit:test` after touching `text-normalization.ps1` or a dictionary. Before approving a PR that touches speech, run `/sapi-voice-kit:selftest` (about 3 minutes, out loud): it checks with the output-level meter that every mode makes sound or stays silent as it should; whether it sounds right is still judged by ear.
- Every change goes through a branch and a PR; the owner merges.
- Release: bump `version` in `plugin.json` and both places in `marketplace.json` (`tests/repo.test.js` checks they agree; the MCP server reads the plugin's version from `plugin.json`).

## Decisions (what was tried and why it is the way it is)

- **A second voice for technical terms**: rejected. It works, but sounds like two people talking and doubles speaking time. IPA hints on one voice instead.
- **The model appending a hidden `<!--voice-->` block to its answer**: rejected. A hook only sees what is already on screen; there is no hidden channel.
- **A temp file for spoken text**: rejected, even a self-deleting one. Text goes through memory.
- **Calling Cowork's shell tool to run `say.ps1`**: does not work (remote Linux sandbox). Hence the local MCP server.
- **A fifth `cowork` mode value**: rejected. Cowork and the CLI are one behavior ("the model speaks") over two transports.
- **The official MCP SDK**: rejected, to keep the plugin free of npm dependencies. The protocol surface needed is small.
- **One flat config shared by all environments**: tried; it removed the ability to use a different voice in Cowork. Hence the two sections.
- **Migrating the old per-install configs**: removed. It needed a lock, a cleanup of legacy files, and a one-time-code path that would live forever, for one-time benefit.
- **Cleaning abbreviations/paths/URLs by regex for natural and literal, instruction to the model for summary/active/read-last**: the model path cannot be forced, so `say.ps1` also normalizes what it receives.
- **SSML `<prosody>` for rate or question intonation**: the OneCore voices ignore it. Rate uses `SpeechSynthesizer.Options.SpeakingRate`.

## Known limitations

- Spanish questions get weak rising intonation on every Microsoft Spanish voice, SAPI5 or OneCore, and no SSML changes that. A neural cloud voice would fix it at the cost of API keys and internet, which this project exists to avoid.
- The voices have no /ʃ/ ("sh") sound: "push" is spoken as "pus". The dictionary entry is still better than none.
- Cowork's plugin screen can show a stale version, and a restart does not refresh it.
- In active mode in Cowork, speaking depends on the model invoking the skill every turn.
- If the MCP server is registered both by the plugin and by a manual entry in `claude_desktop_config.json`, Claude Code sessions see two `read_aloud` tools; the duplicate-speech guard absorbs the double call.
