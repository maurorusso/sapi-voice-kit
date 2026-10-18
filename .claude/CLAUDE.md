# sapi-voice-kit — project context

## Goal

Let someone use Claude Code by voice: instead of reading the answer on screen, hear it — the *complete* content of the response, rephrased so it is clear and natural when heard. Not a mechanical truncation and not an ultra-short summary. Built for people who find reading on screen hard, or who prefer to listen.

Native Windows speech only: no API keys, no Python, no installer.

## Invariants — keep these true in any change

- The response on screen is never changed. The voice path is entirely separate from what is displayed.
- What is spoken is a faithful, complete rendering of the answer, not a shortened stand-in (code blocks become a short placeholder and runs of hundreds of ASCII characters with no space, such as a base64 blob, are dropped; `summary` mode, whose purpose is a condensed version, is the one exception).
- Nothing readable is written to disk by default: no logs, no copy of what was spoken. Only `config.json` and a bare timestamp (`.last-active-speech`). Spoken text travels through memory (stdin/stdout), never through a temp file.
- Every `.ps1` and `.psd1` under `scripts/` is saved as UTF-8 **with BOM**: Windows PowerShell 5.1 misreads accents without one. `tests/common.Tests.ps1` enforces it.
- The plugin's own code passes tool arguments to PowerShell only as discrete `spawn` arguments, and text only through stdin or a single-quoted heredoc, never by string concatenation into a shell command. The two voice commands a skill has the model run take a value only after it checks it is an installed voice name or a language code.
- The plugin has no runtime dependencies. Pester 3.4 (bundled with Windows PowerShell 5.1) and `node:test` are dev-only.

## Layout

```
.claude-plugin/        plugin.json, marketplace.json (this repo is its own marketplace)
hooks/hooks.json       Stop hook (speak.ps1) and UserPromptSubmit hook (prompt-active-mode.ps1)
.mcp.json              registers the MCP server for Claude Code sessions
mcp-server/            Cowork's way in: server.js (wiring), protocol.js, tools.js, powershell.js
scripts/               entry points: speak, say, say-test, self-test, prompt-active-mode, list-voices, set-*
scripts/common.ps1     loads scripts/lib/
scripts/lib/           one concern per file; see ARCHITECTURE.md for the table
skills/                slash commands (voice, mode, mute, debug, test, selftest), read-last, cowork
tests/                 Pester (PowerShell library and entry scripts) and node:test (MCP server, repo integrity)
```

## Reading modes

The Stop hook receives `last_assistant_message` and acts on `mode` from `config.json`:

- **natural** (default): the whole response with markdown removed and code blocks replaced by a placeholder (`Get-CleanedText`).
- **literal**: the whole response exactly as written.
- **summary**: a short summary from a separate `claude -p --safe-mode --tools "" --no-session-persistence --model haiku` call (no tools, and no transcript of the response saved on the user's disk). About 20 s of silence, so opt-in; falls back to natural if the call fails.
- **active**: the model speaks a short paraphrase itself, mid-turn, by piping it to `say.ps1`; the Stop hook stays silent so audio never doubles. In the CLI a UserPromptSubmit hook reminds the model each turn (Claude Code asks for permission once per session); the command is a Bash heredoc, so it needs the Bash tool. In Cowork, which fires no plugin hooks, `skills/cowork` reminds it to call the `read_aloud` MCP tool.

`muted` pauses automatic reading without losing the mode. `read-last` ("leeme eso") reads one response on demand through `say.ps1 -Force`, which ignores mute.

## Config

One fixed folder per Windows user, shared by every install: `%USERPROFILE%\.claude\plugins\data\sapi-voice-kit-shared\`. `config.json` holds two independent sections:

- `local`: everything started by Claude Code's hooks. The CLI and Desktop's Code tab fire identical hooks, so the plugin cannot tell them apart and they share it.
- `cowork`: everything arriving through the MCP server, the only way Cowork reaches the plugin.

`SAPI_VOICE_DATA_DIR`, when set, replaces that folder: the tests and `/sapi-voice-kit:selftest` use it to work in a throwaway directory without touching the real settings, and the MCP server forwards it to its scripts. The section is chosen by `SAPI_VOICE_NAMESPACE` (the MCP server sets `cowork` when it spawns a script; default `local`). Reads and writes go through a named mutex (`Local\SapiVoiceKitConfig`); writes are temp-file-and-rename. Speech uses its own mutex (`Local\SapiVoiceKitSpeak`) so parallel sessions take turns instead of talking over each other; the debug log has a third (`Local\SapiVoiceKitLog`) that is best effort. The duplicate-speech guard is deliberately **not** per-namespace: it exists to deduplicate across them.

## Voices

`Get-InstalledVoices` merges OneCore (modern Windows 11 voices, listed first so they win automatic selection) and SAPI5 (classic, on every Windows). A configured voice name or language is matched against that one list. If a voice fails, `Invoke-SpeechSynthesis` falls back: OneCore → SAPI5 voice for the language → SAPI5 default.

Technical terms (git, commit, hook, ...) get IPA pronunciations on the *same* voice, from the dictionary of the language that voice speaks: `scripts/lib/pronunciations/<code>.psd1` (today only `es.psd1`, used for every Spanish voice, es-ES, es-MX, ...). A voice in a language with no file gets no hints, because IPA written for Spanish is wrong for another language. To support another language, add its file; nothing else changes. Words the voices stress wrongly even with IPA are respelled instead (`scripts/lib/respellings/<code>.psd1`, e.g. `natural` -> `naturál`: the written accent is honored where the IPA stress mark is not; the screen text is untouched). Both are skipped in literal mode. The rules for adding entries are at the top of each file. Check changes with `/sapi-voice-kit:test` by ear.

## Cowork

Plugin hooks do not fire in Cowork, and its own shell tool is a remote Linux sandbox with no PowerShell, so the MCP server is how the plugin speaks and is configured there. It exposes `read_aloud`, `set_mode`, `set_mute`, `set_voice`, `list_voices`, `say_test`, `set_debug`; each runs one script and returns its output. `read_aloud` passes `-RequireMode active` to `say.ps1`, so the mode check lives in one place.

Whether Cowork registers the plugin's MCP server by itself is inconsistent: Anthropic documents that a user-installed plugin does not bring MCP servers, yet it has sometimes appeared. The README gives the one-time manual entry as a fallback; adding it when the server already registered duplicates it. Packaging the server as a `.mcpb` Desktop Extension does not help: anthropics/claude-code#26259 shows Cowork's VM only forwards `type: "sdk"` servers and drops stdio ones.

## Working on this repo

- Tests: `powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests"` and `node --test`. CI (`.github/workflows/test.yml`) runs both on every PR and push to `main`, on Windows, with Pester pinned to 3.4.0.
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
- **Two config sections (`local`, `cowork`), not one flat file**: the voice has to be able to differ in Cowork.
- **Cleaning abbreviations/paths/URLs by regex for natural mode and in `say.ps1`, instruction to the model for summary/active/read-last**: the model path cannot be forced, so `say.ps1` also normalizes what it receives, and summary mode runs the model's summary through `Get-CleanedText` before speaking it.
- **SSML `<prosody>` for rate or question intonation**: the OneCore voices ignore it. Rate uses `SpeechSynthesizer.Options.SpeakingRate`.

## Known limitations

- Spanish questions get weak rising intonation on every Microsoft Spanish voice, SAPI5 or OneCore, and no SSML changes that. A neural cloud voice would fix it at the cost of API keys and internet, which this project exists to avoid.
- The voices have no /ʃ/ ("sh") sound: "push" is spoken as "pus". The dictionary entry is still better than none.
- Cowork's plugin screen can show a stale version, and a restart does not refresh it.
- In active mode in Cowork, speaking depends on the model invoking the skill every turn.
- `.mcp.json` starts `node` by name, and the hooks and skills start `powershell` by name, so a `powershell.exe` planted in the folder a hook runs from would be found first on `cmd.exe`; only the MCP server uses the full System32 path.
- A file name with several dots (`common.Tests.ps1`, `app.module.ts`) is read as its last two parts and keeps the folders in front of it: the file-name pattern's name part cannot contain dots, and allowing them made the pattern far too slow on long dotted words. Paths with spaces (`C:\Program Files\App\run.exe`) are not parsed, so a word before the first space is left in; a file name glued to Chinese, Japanese or Thai text with no punctuation between them is left as written (`\b` finds no boundary there); and `chart.js/package.json` reads as a list, because it has the same shape as `README.md/other.md`. Capitalized folders in front of a capitalized `.js` file name (`Models/User.js`) are kept, because that shape matches a technology list (`MongoDB/Express/Node.js`).
- Text written without spaces (Chinese, Japanese, Korean, Thai) glued to a Windows drive path with no punctuation between them is read as part of the path: after `C:\` a folder name may be in any script, because user names are. Two URLs joined by a comma with no space (`https://a.com,https://b.com`) are read as one link. A drive-path folder name with a comma, a semicolon, a backtick, an unbalanced parenthesis or a typographic dash, quote or guillemet (valid on Windows, `C:\Users\Smith,John`) ends the folder at that character, because those characters are what tell two joined paths apart.
- A comment or a link inside a span written with two backticks (` ``<!-- x -->`` `) is treated as outside code: the pair of backticks that opens the span reads as an empty span.
- Markdown that is ambiguous or malformed can still read some code aloud or lose a line: a mention of three backticks at the end of a line pairs with the next bare closing line (the sentence "Do this: ```" followed by code and a closing fence reads as one fence, which is what that shape usually means); a fence that is never closed is read as text; the unindented body of a fence opened after a list marker ends with its list item; a thematic break written `- - -`, an empty checkbox `[ ]` and a line that starts with a year and a period (`2024. text`, read as a list item) are spoken as written or lose that start. A quote marker is removed at any indent, so a line that starts with `>=` loses its `>`, as Markdown reads it.
- A natural-mode answer longer than about 15,000 characters is cut off when the Stop hook's 900 s timeout runs out (a Spanish voice speaks about 17 characters per second).
- The modern (OneCore) voices synthesize the whole text before playing anything, so a long answer starts after a delay (about 5 s for 10,000 characters), and past roughly 65,000 characters the 30 s wait runs out and the text is read again with a classic voice.
- A long `read_aloud` holds the MCP server's queue until it finishes speaking, so `set_mute` waits behind it.
- In active mode the spoken paraphrase is part of the Claude session transcript, which the plugin does not control.
- If the MCP server is registered both by the plugin and by a manual entry in `claude_desktop_config.json`, Claude Code sessions see two `read_aloud` tools; the duplicate-speech guard absorbs the double call.
