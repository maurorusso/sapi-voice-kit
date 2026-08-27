---
description: Configure the language or voice sapi-voice-kit uses to read responses aloud. Use when the user asks to change language, pick a different voice, adjust the rate, or see which voices are installed.
disable-model-invocation: true
---

# Configure sapi-voice-kit's voice

Arguments received: "$ARGUMENTS"

Steps:

1. If there are no arguments, or the user asks to see the options ("voices", "list", "options"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/list-voices.ps1"`
   and show the list as-is.

2. If the user asks to go back to automatic ("auto", "default"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-voice.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -Auto`

3. If the argument matches the name of an installed voice (see step 1), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-voice.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -Voice "<exact name>"`

4. If the argument looks like a language code (e.g. "en-US", "es-MX", "en", "es"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-voice.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -Language "<code>"`

5. If the user asks to change the speed/rate ("faster", "slower", "speed", "rate"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-voice.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -Rate <integer from -10 to 10>`
   Negative is slower, positive is faster, 0 is the default. Pick a reasonable value from context ("a bit faster" -> 3, "much slower" -> -6) unless the user gives an exact number.

6. Confirm in one sentence what got configured (voice, language, rate, or back to automatic).
