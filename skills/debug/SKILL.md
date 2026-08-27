---
description: Turn sapi-voice-kit's diagnostic log files on or off. Off by default. Use when the user wants to troubleshoot why reading/voice isn't working as expected, or wants to turn logging back off afterward.
disable-model-invocation: true
---

# sapi-voice-kit debug logging

Argument received: "$ARGUMENTS"

Steps:

1. If the argument says "on" (or "enable", "activar", "prender"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-debug.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -State on`

2. If it says "off" (or "disable", "desactivar", "apagar"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-debug.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -State off`

3. Confirm to the user: with debug **on**, sapi-voice-kit writes log files (`log-speak.txt`) and a copy of the last thing it spoke (`last-text.txt`) to its data folder, to help troubleshoot a problem. With debug **off** (the default), nothing gets written there besides the voice/language/mode settings the user explicitly chose. Suggest turning it back off once done troubleshooting.
