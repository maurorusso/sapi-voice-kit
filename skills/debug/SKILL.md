---
description: Turn sapi-voice-kit's diagnostic log files on or off. Off by default. Use when the user wants to troubleshoot why reading/voice isn't working as expected, or wants to turn logging back off afterward.
disable-model-invocation: true
---

# sapi-voice-kit debug logging

Argument received: "$ARGUMENTS"

**If you're running as Claude Cowork/Desktop (not the CLI):** call the MCP tool `set_debug` (from the sapi-voice-kit server) with `{"state": "on" | "off"}` instead of the powershell commands below - Cowork's shell has no PowerShell or access to this machine. If you're the CLI, keep using the powershell commands as written.

Steps:

1. If the argument says "on" (or "enable", "activar", "prender"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-debug.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -State on`

2. If it says "off" (or "disable", "desactivar", "apagar"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-debug.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -State off`

3. Confirm to the user: with debug **on**, sapi-voice-kit writes log files (`log-speak.txt`) and a copy of the last thing it spoke (`last-text.txt`) to its data folder, to help troubleshoot a problem. With debug **off** (the default), nothing gets written there besides the voice/language/mode settings the user explicitly chose. Suggest turning it back off once done troubleshooting. This setting is independent between the CLI/Code tab and Cowork - turning it on from one doesn't turn it on for the other.
