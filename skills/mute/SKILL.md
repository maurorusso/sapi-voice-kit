---
description: Silence sapi-voice-kit's automatic reading entirely, machine-wide, without losing the chosen mode - or turn it back on. Use when the user wants everything to stop talking right now (e.g. two sessions overlapping, or a noisy moment), or to reactivate it afterward.
disable-model-invocation: true
---

# sapi-voice-kit mute

Argument received: "$ARGUMENTS"

Steps:

1. If the argument says "on" (or "mute", "silenciar", "callate", "silencio"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mute.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -State on`

2. If it says "off" (or "unmute", "activar", "reactivar"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mute.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -State off`

3. Confirm to the user:
   - Muted **on**: nothing gets read automatically anymore - not the Stop hook, not active mode's per-turn reminder - in ANY Claude Code session on this machine, since the setting lives in the plugin's shared config, not per-session. The mode they had chosen (natural/literal/summary/active) is remembered and comes back exactly as it was once unmuted.
   - Muted **off**: automatic reading resumes in the previously chosen mode.
   - Either way, mention that asking for a specific response to be read out loud on demand (the "read this" skill) still works even while muted - mute only stops the automatic, every-turn reading.
