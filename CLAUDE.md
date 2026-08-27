# sapi-voice-kit — project context

## The goal

Let someone interact with Claude Code by voice: type or dictate a prompt, and instead of reading the answer on screen, hear it — the *complete* content of the response, rephrased so it's clear and natural when heard, not a mechanical truncation and not an ultra-short summary. Built for anyone who'd rather listen than read on screen.

Two things that follow from that goal, and that any change should keep true:
- The full written response on screen must stay exactly as generated — nothing added, nothing removed, nothing hidden in it. The voice mechanism is entirely separate from what's displayed.
- What gets read must be a faithful, complete spoken rendering of the answer — the way a person would read the answer aloud and put it in their own words, not a shortened stand-in for it (except in `summary` mode, which exists specifically for when a condensed version is wanted).

Native Windows `System.Speech` (SAPI) — no API keys, no Python, no installer.

## Architecture

```
sapi-voice-kit/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # this repo is its own marketplace (single-plugin setup)
├── hooks/hooks.json          # Stop hook + UserPromptSubmit hook
├── scripts/
│   ├── common.ps1            # shared voice/config/logging/speech helpers (incl. the cross-process speech mutex)
│   ├── speak.ps1              # Stop hook: reads the response aloud (natural/literal/summary)
│   ├── say.ps1                 # model-invoked: speaks text piped in via stdin (active mode + on-demand read)
│   ├── prompt-active-mode.ps1  # UserPromptSubmit hook: reminds the model in active mode
│   ├── list-voices.ps1
│   ├── set-voice.ps1
│   ├── set-mode.ps1
│   ├── set-debug.ps1
│   └── set-mute.ps1
├── skills/
│   ├── voice/SKILL.md         # /sapi-voice-kit:voice
│   ├── mode/SKILL.md          # /sapi-voice-kit:mode
│   ├── debug/SKILL.md         # /sapi-voice-kit:debug
│   ├── mute/SKILL.md          # /sapi-voice-kit:mute
│   └── read-last/SKILL.md     # model-invocable: read a specific response on demand
├── LICENSE (MIT)
└── README.md
```

## The four reading modes

The `Stop` hook receives the turn's `last_assistant_message` as JSON on stdin and decides what to speak based on `config.json`'s `mode` field:

- **natural (default):** the complete response, cleaned of markdown (headings, bullets, links, code syntax), spoken instantly. Nothing shortened.
- **literal:** the complete response exactly as written, no cleanup at all.
- **summary:** an actual condensed summary via a separate `claude -p --safe-mode --model haiku` call. Opt-in, not the default, because that call reliably costs ~20s of dead silence regardless of response length. Falls back to natural mode if the call fails for any reason.
- **active:** the model speaks for itself, mid-turn, by piping a short paraphrase to `say.ps1` via stdin — no waiting on a separate call. A `UserPromptSubmit` hook (`prompt-active-mode.ps1`) reminds the model of this every turn; in this mode the `Stop` hook does nothing (it would otherwise produce overlapping audio). Since this has the model run a command itself, Claude Code will ask for a one-time permission the first time in a session — a plugin cannot pre-grant its own permissions, and shouldn't be able to.

In natural, summary, and active modes, common programming terms (git, commit, config, hook, function, ~80 total) are read with correct English pronunciation via `PromptBuilder.AppendTextWithPronunciation` (real IPA phonemes) on the *same* selected voice, rather than switching to a second voice (tried and rejected — it works, but sounds like two people talking and roughly doubles speaking time on code-heavy responses).

Voice/language is auto-detected from the installed voice matching the system language (`Get-Culture`), with a manual override stored in `config.json` inside the plugin's persistent data directory, so it survives plugin updates.

## Muting and on-demand reading

Two controls independent of the four modes above:

- **`muted` flag** (`/sapi-voice-kit:mute on`/`off`): a machine-wide pause, separate from `mode` so toggling it doesn't lose the chosen mode. Checked first thing in `speak.ps1`, `say.ps1`, and `prompt-active-mode.ps1`, before any other logic. Since `config.json` lives in the plugin's shared data directory (not per-session), muting from one session mutes automatic reading in every session on the machine — deliberate, not a bug: it's one person at one desk with one speaker.
- **`read-last` skill**: lets the user ask, in the current turn, to have a specific response read aloud right now ("leeme eso") regardless of mode or mute state. Reuses `say.ps1`'s stdin-heredoc mechanism (same one active mode uses) with a `-Force` switch that bypasses the mute check — an explicit request should still work while muted. Unlike the other skills, this one is model-invocable (no `disable-model-invocation`), since it's meant to be triggered by natural language, not just the slash command. Writes nothing to disk: the text being read is already in the conversation's context when this runs.

## Design notes for contributors

- **Marker-in-response approach, rejected:** an earlier version had the model append a `<!--voice ... -->` block to its own response, extracted by the `Stop` hook. It worked, but showed up as literal visible text on screen — a hook only ever sees exactly what was already shown to the user, there's no hidden channel. Replaced by local text cleanup (no model cooperation needed) plus, later, the `active` mode above for when a model-authored version is actually wanted.
- **`AppendTextWithPronunciation` needs real IPA.** The pronunciation-hint parameter must be concatenated IPA Unicode characters with no spaces (Microsoft's documented example: `"duˈbwɑ"`) — space-separated ASCII approximations fail with an "invalid phoneme" error.
- **Encoding pitfalls on Windows/PowerShell 5.1, twice:** `[Console]::In.ReadToEnd()` and `[Console]::OutputEncoding` both default to the console's OEM codepage for redirected streams, not UTF-8 — corrupting accented characters on the way in (reading the hook's stdin) and on the way out (capturing `claude -p`'s output). Fixed by reading/writing raw bytes and decoding explicitly as UTF-8 in both directions. Separately, `.ps1` files need a UTF-8 BOM or PowerShell 5.1 misreads non-ASCII literals written directly in the source.
- **Command injection in a model-constructed shell command.** An early version of the `active`-mode instruction told the model to run `printf '%s' "PARAPHRASE" | powershell ...` with its own paraphrase substituted into a double-quoted string — a real risk, since a paraphrase mentioning shell syntax (`$(...)`, backticks, quotes) would have it evaluated by the shell. Fixed by using a heredoc with a single-quoted delimiter (`<<'EOF'`) instead, which passes the body through with zero shell expansion regardless of content.
- **Cross-process speech overlap, observed live.** Two parallel Claude Code sessions with this plugin active could speak at the same time — each process owns its own `SpeechSynthesizer` with no knowledge of any other process, so simultaneous speech overlapped on the shared audio device and was unintelligible. Fixed with a named Windows Mutex (`Local\SapiVoiceKitSpeak` — session-scoped, not `Global\`: the real scenario never crosses a Windows session boundary, and `Global\` would need a privilege a restricted or Remote-Desktop-session user might not have) around the actual `Speak()` call in `Invoke-SpeechSynthesis`, shared by every caller — processes now take turns instead of talking over each other. A 60s `WaitOne` timeout keeps a crashed or unusually slow holder from permanently silencing everyone else.
- **Raw URLs read as the wrong thing entirely, not just badly.** A plain `https://...` link spoken aloud came out announcing an emoticon instead of a link - `https://` starts with a colon immediately followed by a slash, and some TTS text normalization recognizes `:/` as the "confused/displeased face" emoticon before it ever gets far enough to recognize a URL. Fixed the same two ways as the file-extension problem: `ConvertTo-SpokenUrls` (common.ps1) replaces any bare `https?://\S+` with "el link" for natural/literal and as a fallback in say.ps1, and summary/active/read-last's prompts tell the model to refer to a link naturally instead of writing it out. The screen still shows the exact URL untouched either way - same principle as markdown links, which already only speak the label, never the address.
- **Full paths, same call as URLs: collapse instead of reading raw.** A path read character-by-character (drive letter, every backslash, every folder) isn't useful spoken, and risked the same kind of TTS misreading URLs did. `ConvertTo-SpokenFileNames`'s regex now consumes any leading path segments too, so `C:\...\common.ps1` or `scripts/common.ps1` collapse to `common punto ps1`, not just bare `common.ps1`. `ConvertTo-SpokenPaths` catches the rest - a bare folder mention with no recognized extension - scoped to drive-letter-absolute paths specifically (`C:\...`), an unambiguous signal in prose with essentially no false-positive risk. Researched first: no single canonical rule exists for reading paths aloud across TTS engines - the consistent pattern is each engine building its own domain-specific normalization rather than relying on default parsing, which is the approach already used throughout this file.
- **File names read oddly, fixed two different ways for two different kinds of mode.** `common.ps1` (a raw dot before a file extension) got read as an odd swallowed pause instead of sounding like a name. For the mechanical modes (natural/literal's cleanup has no model in the loop), fixed with a regex in `Get-CleanedText` that rewrites `word.extension` (for a maintained list of known extensions) into `word punto extension`. For the modes that go through the model (`summary`'s prompt, `active`'s per-turn instruction, `read-last`'s instructions), fixed instead by telling the model directly to write "punto"/"dot" instead of a literal period — since that text is never shown on screen, there's no cost to writing it however sounds best spoken.
- **No temp files, anywhere, in any mode.** Text that gets spoken always travels through memory (stdin/stdout between processes) — never through an intermediate file, not even a briefly self-deleted one. Considered and deliberately rejected in favor of not writing anything in the first place.
- **Debug logging is opt-in and bounded.** With `/sapi-voice-kit:debug` off (the default), nothing is written to the plugin's data folder beyond the settings a user explicitly changes — no logs, no copy of what was spoken. When turned on for troubleshooting, each log file is capped (trimmed to the last 200 lines once it exceeds ~50KB) so it never grows unbounded.
- **`git push`/plugin-install SSL errors on Windows behind an antivirus that does HTTPS interception:** fixed with `git config --global http.sslBackend schannel`, which makes git use the Windows certificate store (which trusts the antivirus's injected cert) instead of git's own bundled one.

## Distribution

A single repo acting as both the plugin and its own marketplace is the standard pattern for an individual Claude Code plugin. End-user install:

```
/plugin marketplace add <owner>/sapi-voice-kit
/plugin install sapi-voice-kit
```

Use the full `https://github.com/<owner>/sapi-voice-kit` URL rather than the `owner/repo` shorthand — the shorthand makes Claude Code default to an SSH clone, which fails on machines without SSH access to GitHub configured.

Not using a curl/irm-style installer script: it's not the native distribution mechanism for Claude Code plugins, and piping a remote script into a shell is a pattern worth avoiding regardless.

## License

MIT.
