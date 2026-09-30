---
description: Silence sapi-voice-kit's automatic reading entirely, machine-wide, without losing the chosen mode - or turn it back on. Use when the user wants everything to stop talking right now (e.g. two sessions overlapping, or a noisy moment), or to reactivate it afterward.
disable-model-invocation: true
---

# sapi-voice-kit mute

Argument received: "$ARGUMENTS"

**If you're running as Claude Cowork/Desktop (not the CLI):** call the MCP tool `set_mute` (from the sapi-voice-kit server) with `{"state": "on" | "off"}` instead of the powershell commands below - Cowork's shell has no PowerShell or access to this machine. If you're the CLI, keep using the powershell commands as written.

Steps:

1. If the argument says "on" (or "mute", "silenciar", "callate", "silencio"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mute.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -State on`

2. If it says "off" (or "unmute", "activar", "reactivar"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mute.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -State off`

3. Confirm to the user:
   - Muted **on**: nothing gets read automatically anymore - not the Stop hook, not active mode's per-turn reminder - in every CLI/Desktop "Code" tab session on this machine (that setting is shared across those, since they're indistinguishable to this plugin), but **not** in Cowork - muting from the CLI doesn't mute Cowork, and muting from Cowork doesn't mute the CLI, since each has its own independent setting. The mode they had chosen (natural/literal/summary/active) is remembered and comes back exactly as it was once unmuted.
   - Muted **off**: automatic reading resumes in the previously chosen mode.
   - Either way, mention that asking for a specific response to be read out loud on demand (the "read this" skill) still works even while muted - mute only stops the automatic, every-turn reading.
