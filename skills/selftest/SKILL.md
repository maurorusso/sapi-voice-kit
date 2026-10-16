---
description: Run the complete sapi-voice-kit self-test. Every reading mode is spoken out loud and an output-level meter checks that sound came out when it should and stayed silent when it should. Takes about 3 minutes and speaks the whole time.
disable-model-invocation: true
---

# sapi-voice-kit self-test

This runs every mode for real, out loud, for about 3 minutes (the one-sentence quick check is `/sapi-voice-kit:test`). It is not available in Claude Cowork/Desktop, whose shell is a remote sandbox with no PowerShell and no speakers; there, use the `say_test` tool.

Before running, tell the user in one line that the test will speak for about 3 minutes and that the script itself prints, first, exactly what will be heard and a short countdown. Then run:

`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/self-test.ps1"`

Allow up to 10 minutes for the command. It uses a throwaway settings folder (the user's real settings are untouched) and a different voice from the one in use, so the user can tell the test from the plugin's own voice; `-Voice "<exact name>"` picks one.

When it finishes, show the PASS/FAIL lines and the summary as printed. A FAIL on a step that should be silent can also mean other audio was playing on the computer. Remind the user that the meter proves sound did or did not come out, and that whether it sounded right is judged by ear against the list the script printed.
