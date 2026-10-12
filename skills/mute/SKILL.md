---
description: Silence sapi-voice-kit's automatic reading entirely, per environment (CLI/Code tab and Cowork each have their own), without losing the chosen mode - or turn it back on. Use when the user wants everything to stop talking right now (e.g. two sessions overlapping, or a noisy moment), or to reactivate it afterward.
disable-model-invocation: true
---

# sapi-voice-kit mute

Argument received: "$ARGUMENTS"

**In Claude Cowork/Desktop** call the `set_mute` tool of the sapi-voice-kit MCP server with `{"state": "on" | "off"}` instead of the commands below. If you're the CLI or the Code tab, use the powershell commands as written.

Steps:

1. If the argument says "on" (or "mute", "silenciar", "callate", "silencio"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mute.ps1" -State on`

2. If it says "off" (or "unmute", "activar", "reactivar"), run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/set-mute.ps1" -State off`

3. Confirm to the user:
   - Muted **on**: nothing gets read automatically anymore - not the Stop hook, not active mode's per-turn reminder - in the CLI and the Code tab (they share one setting, since the plugin cannot tell them apart) but **not** in Cowork, and the other way round: each environment has its own. The mode they had chosen (natural/literal/summary/active) is remembered and comes back exactly as it was once unmuted.
   - Muted **off**: automatic reading resumes in the previously chosen mode.
   - Either way, mention that asking for a specific response to be read out loud on demand (the "read this" skill) still works even while muted - mute only stops the automatic, every-turn reading.
