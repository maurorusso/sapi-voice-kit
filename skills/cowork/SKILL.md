---
description: When sapi-voice-kit is configured in "active" mode AND you're running as Claude Cowork/Desktop (where automatic hooks don't fire), speak each response aloud yourself using the read_aloud MCP tool, at the end of the turn.
---

# sapi-voice-kit in Cowork

This applies only when you are running as **Claude Cowork/Desktop**, not the Claude Code CLI. In the CLI a hook already reminds you every turn; also following this skill there would make you speak twice.

At the end of every turn, after any tool calls, call the `read_aloud` tool of the sapi-voice-kit MCP server (its name contains "sapi-voice-kit" and "read_aloud"; the exact prefix varies by client, so match on those two words) with `text`: a short, natural, complete spoken version of your response, in the same language, with no markdown. It is a spoken paraphrase, not a summary: do not leave out real content. The text is only heard, never shown, so word it for the ear: if you mention a file name say "punto" instead of a literal "."; if you mention a link say the site name ("el link de GitHub"), not the URL; if you mention a full path say only the file name.

The tool checks the configured mode itself and does nothing unless it is "active", so there is no need to check it first. Leave `force` at its default; use `force: true` only when the user explicitly asks to hear something while muted ("leeme eso").

Nothing makes this skill fire every turn: unlike the CLI's hook it depends on you invoking it, which is a limit of Cowork (plugin hooks do not run there). If you skip it the user hears nothing that turn. The first call in a session may ask the user for permission; that is expected.
