# UserPromptSubmit hook: only in "active" mode, reminds the model on every
# turn to speak its response itself by piping a short natural paraphrase to
# say.ps1, instead of the automatic Stop-hook reading (which is skipped
# entirely in this mode - see speak.ps1, so the two never produce double
# audio). Repeats every turn, not just once, for the same reason
# request-summary.ps1 used to (the old, now-removed, <!--voice--> design):
# doesn't depend on the model "remembering" in a long conversation. In any
# other mode, this does nothing.

param([string]$PluginData, [string]$PluginRoot)

. "$PSScriptRoot\common.ps1"

try {
    $config = if ($PluginData) { Get-VoiceConfig -PluginData $PluginData } else { $null }
    if ($config -and $config.muted -eq $true) { exit 0 }
    $mode = if ($config -and $config.mode) { $config.mode } else { 'natural' }
    if ($mode -ne 'active') { exit 0 }

    $sayScript = if ($PluginRoot) { Join-Path $PluginRoot "scripts\say.ps1" } else { "say.ps1" }

    # IMPORTANT: the example command below uses a single-quoted heredoc
    # delimiter (<<'EOF') on purpose, not printf with a double-quoted
    # string. A previous version used `printf '%s' "PARAPHRASE" | ...`,
    # which is a real command-injection risk: if the model's paraphrase
    # naturally contains shell metacharacters (very plausible in a coding
    # assistant's own output - $(...), backticks, quotes), those get
    # evaluated by the shell instead of passed through as literal text.
    # Confirmed live: `printf '%s' "text with $(echo INJECTED)"` executes
    # the embedded command. A single-quoted heredoc delimiter disables all
    # shell expansion inside it, so the body is always passed through
    # exactly as written, whatever it contains - confirmed with the same
    # dangerous input (dollar-parens, quotes, backticks) coming through
    # byte-for-byte unmodified. Found and verified by a peer session
    # reviewing this file before it shipped.
    $instructions = @"
Active voice mode is on: nothing gets read aloud automatically this turn - the usual automatic reader is off. At the very end of your turn, after any tool calls, run this exact command yourself (as a normal command), replacing PARAPHRASE with a short, natural, complete-enough spoken version of your response, in the same language as your response, no markdown. This text is only ever spoken aloud, never shown on screen. $($script:SpokenTextGuidance)

powershell -NoProfile -ExecutionPolicy Bypass -File "$sayScript" -PluginData "$PluginData" <<'EOF'
PARAPHRASE
EOF

Use that exact form - a heredoc with a single-quoted 'EOF' delimiter - so your text is passed through literally with no shell expansion, even if it contains `$`, backticks, or quotes. Do not use printf or a double-quoted string for this; those can execute characters your paraphrase happens to contain.

If you skip this, the user hears nothing this turn. Claude Code may ask for permission to run this the first time in a session - that's expected, not an error.
"@

    # Same UTF8-direct-to-stdout approach as Get-AiSummary's caller and the
    # old request-summary.ps1: avoids [Console]::OutputEncoding defaulting
    # to the OEM codepage and corrupting the instruction's accented text.
    $output = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName = 'UserPromptSubmit'
            additionalContext = $instructions
        }
    }
    $json = $output | ConvertTo-Json -Depth 5

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
} catch {
    exit 0
}
