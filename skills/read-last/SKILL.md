---
description: Read a specific response out loud right now, on the user's explicit request, regardless of the current reading mode or mute state - e.g. "leeme eso", "no entendí, léelo", "read that last part to me". Different from the automatic per-turn reading - this is triggered once, when asked, not a standing background task.
---

# sapi-voice-kit read on demand

The user is asking, in this turn, to have something read out loud - usually your own previous response (or the specific part of it they're pointing at), because natural mode's automatic reading either wasn't on, got muted, or they just want to hear a particular part again.

Steps:

1. Identify the text to read: normally your immediately preceding response in this conversation, or the specific portion the user calls out (e.g. "leeme el último párrafo").
2. Write a short, natural, complete-enough spoken version of that text, in the same language it was written in - no markdown, no raw symbols. This text is only ever spoken aloud, never shown on screen: if you mention a file name, say the word for a period ("punto" in Spanish, "dot" in English) instead of a literal "." character, since a raw dot right before a file extension reads oddly aloud. If you'd mention a URL/link, don't write it out - refer to it by its site name instead (e.g. "el link de GitHub") so two different links in the same response are still told apart, and let the user look at the screen for the actual address, since a raw URL read aloud (the "https://" part especially) sounds wrong. Same idea for a full file path - just say the file name, not every folder in between.
3. Run this exact command yourself, replacing PARAPHRASE with that text:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/say.ps1" -PluginData "${CLAUDE_PLUGIN_DATA}" -Force <<'EOF'
   PARAPHRASE
   EOF
   ```

   Use that exact form - a heredoc with a single-quoted `'EOF'` delimiter - so the text is passed through literally with no shell expansion, even if it contains `$`, backticks, or quotes. Do not use `printf` or a double-quoted string for this.

4. The `-Force` flag makes this work even if the user has muted automatic reading (`/sapi-voice-kit:mute on`) - mute silences the automatic reader, not an explicit request like this one. Claude Code may ask for permission to run this the first time in a session - that's expected, not an error.
5. Don't repeat the text on screen just because you're about to speak it - the on-screen response and what gets read aloud are independent, same as every other mode.
