# UserPromptSubmit hook. Only in "active" mode: every turn it reminds the model
# to speak its answer itself, by piping a short paraphrase to say.ps1. In any
# other mode, or when muted, it adds nothing.
#
# Hooks do not fire in Cowork; there the same reminder comes from
# skills/cowork/SKILL.md and the model calls the read_aloud MCP tool instead.

. "$PSScriptRoot\common.ps1"

try {
    $config = Get-VoiceConfig
    if ($config.muted -eq $true) { exit 0 }
    if ($config.mode -ne 'active') { exit 0 }

    $sayScript = Join-Path $PSScriptRoot 'say.ps1'

    # The command uses a heredoc with a single-quoted delimiter (<<'EOF'): the
    # shell passes the body through untouched. Building it with printf and a
    # double-quoted string would execute any $(...) or backticks in the
    # paraphrase.
    $instructions = @"
Active voice mode is on: nothing gets read aloud automatically this turn - the usual automatic reader is off. At the very end of your turn, after any tool calls, run this exact command yourself (as a normal command), replacing PARAPHRASE with a short, natural, complete-enough spoken version of your response, in the same language as your response, no markdown. This text is only ever spoken aloud, never shown on screen. $($script:SpokenTextGuidance)

powershell -NoProfile -ExecutionPolicy Bypass -File "$sayScript" <<'EOF'
PARAPHRASE
EOF

Use that exact form - a heredoc with a single-quoted 'EOF' delimiter - so your text is passed through literally with no shell expansion, even if it contains `$, backticks, or quotes. Do not use printf or a double-quoted string for this; those can execute characters your paraphrase happens to contain.

If you skip this, the user hears nothing this turn. Claude Code may ask for permission to run this the first time in a session - that's expected, not an error.
"@

    $output = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName     = 'UserPromptSubmit'
            additionalContext = $instructions
        }
    }

    # Written as UTF-8 bytes: the console codepage would corrupt the accents.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($output | ConvertTo-Json -Depth 5))
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
} catch {
    # A broken reminder must not block the user's prompt; the cost is that this
    # turn is not spoken.
    exit 0
}
