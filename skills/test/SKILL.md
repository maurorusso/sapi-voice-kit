---
description: Speak a fixed test sentence that exercises every pronunciation and text-cleanup rule in sapi-voice-kit, so a change to that logic can be checked by ear.
disable-model-invocation: true
---

# sapi-voice-kit test

Run:

`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/say-test.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}"`

This speaks one fixed sentence covering: a dictionary pronunciation term (`git`), a dotfile written plainly (`.env`, inside the sentence text itself) and one inside backticks (`` `.mcp.json` ``), a full file path (`scripts/common.ps1`), a bare URL and a markdown link, an abbreviation at the end of a sentence (`etc.`), two abbreviation edge cases that previously broke (`VS Code`, `Dr. García`), a question, a line break with no trailing period, a bullet list, and a few more dictionary terms (`skill`, `prompt`, `node`, `javascript`, `localhost`).

Show the user both the "texto original" and "texto limpio" the command prints (so they can see the transformation even before it finishes speaking), then let it finish speaking before saying anything else.

Use this after touching anything in `scripts/common.ps1`'s text-cleanup functions (`ConvertTo-Spoken*`, `Add-ImplicitLineEndPeriods`, `Get-CleanedText`) or `$script:TechPronunciations` - it catches regressions by ear instead of needing a new throwaway test script written from scratch each time.
