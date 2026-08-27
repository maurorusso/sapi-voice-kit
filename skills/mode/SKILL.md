---
description: Switch between natural, literal, summary, or active reading in sapi-voice-kit.
disable-model-invocation: true
---

# sapi-voice-kit reading mode

Argument received: "$ARGUMENTS"

Steps:

1. If the argument says "natural" (or is empty, "default"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mode.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -Mode natural`

2. If it says "literal" (or "full", "verbatim"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mode.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -Mode literal`

3. If it says "summary" (or "resumen", "short", "corto"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mode.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -Mode summary`
   Warn the user this mode adds roughly 20 extra seconds of silence before each response is read, since it asks Claude separately for a summary.

4. If it says "active" (or "instant", "live"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mode.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -Mode active`
   Warn the user: in this mode, Claude itself speaks a short paraphrase by running a command each turn, and Claude Code will likely ask for permission to run it the first time in a session (that's expected — choosing "always allow" avoids being asked again). Mention that a copyable permission snippet to skip that first prompt is in the README.

5. Confirm to the user which mode is now active:
   - **natural**: reads the complete response, cleaned of markdown (no headings, bullets, links, code syntax) so it sounds like speech instead of a read-aloud document. Nothing is shortened or left out; the on-screen response itself is never changed.
   - **literal**: reads the complete response exactly as written, with no cleanup at all — useful mainly to check what the raw text actually says.
   - **summary**: reads a condensed summary of the response instead of the full text — takes about 20 seconds longer per response, since it makes a separate request for the summary. Falls back to natural mode automatically if that request fails.
   - **active**: Claude speaks a short, natural paraphrase of its own response as part of the same turn — fastest and most natural-sounding, no extra files, no extra AI call, but may ask for a one-time permission the first time.
