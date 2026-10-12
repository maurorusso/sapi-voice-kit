---
description: Speak a fixed test sentence that exercises every pronunciation and text-cleanup rule in sapi-voice-kit, so a change to that logic can be checked by ear.
disable-model-invocation: true
---

# sapi-voice-kit test

**In Claude Cowork/Desktop** call the `say_test` tool of the sapi-voice-kit MCP server (no arguments) instead. In the CLI or the Code tab, run:

`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/say-test.ps1"`

This speaks one fixed sentence covering: a dictionary pronunciation term (`git`), a dotfile written plainly (`.env`, inside the sentence text itself) and one inside backticks (`` `.mcp.json` ``), a full file path (`scripts/common.ps1`), a bare URL and a markdown link, an abbreviation at the end of a sentence (`etc.`), two abbreviation edge cases that previously broke (`VS Code`, `Dr. García`), a question, a line break with no trailing period, a bullet list, and a few more dictionary terms (`skill`, `prompt`, `node`, `javascript`, `localhost`).

Show the user both the "texto original" and "texto limpio" the command prints (so they can see the transformation even before it finishes speaking), then let it finish speaking before saying anything else.

Use this after changing anything in `scripts/lib/text-normalization.ps1` or `scripts/lib/pronunciations/es.psd1`: audio quality can only be judged by ear.
