# Text the model writes only to be heard (summary mode, active mode's
# per-turn instruction, read-last). It never appears on screen, so it can be
# worded purely for the ear.

# Shared by Get-AiSummary below and prompt-active-mode.ps1. skills/read-last
# and skills/cowork keep a copy in prose (a skill is static markdown and cannot
# interpolate this); tests/common.Tests.ps1 fails if the copies drift.
$script:SpokenTextGuidance = 'If you mention a file name, say the word for a period (e.g. "punto" in Spanish, "dot" in English) instead of writing a literal "." character, since a raw dot right before a file extension reads oddly aloud (for example write "common punto pe ese uno", not "common.ps1"). If you would mention a URL or link, do not write it out - refer to it by its site name instead (e.g. "el link de GitHub") so two different links in the same response are still told apart, and let the reader look at the screen for the actual address, since a raw URL read aloud (the "https://" part especially) sounds wrong. Same idea for a full file path (e.g. "C:\Users\...\common.ps1" or "scripts/common.ps1") - just say the file name, not every folder in between.'

# "summary" mode: asks Claude for a short spoken-style summary of $Text with a
# separate `claude -p` call (about 20 s, which is why the mode is opt-in).
# --safe-mode keeps that call from loading this plugin's own hooks,
# --no-session-persistence keeps it from saving a transcript of the response in
# the user's Claude folder, and the prompt goes through stdin because a long
# response would exceed the Windows command-line limit as an argument. Returns $null on any failure so the caller
# can read the full text instead.
function Get-AiSummary {
    param([Parameter(Mandatory)][string]$Text)

    $prompt = "Summarize the following text in 2-4 natural spoken sentences that capture the key points, in the same language as the text. This summary will ONLY ever be spoken aloud by a text-to-speech engine, never shown on screen - write it accordingly. $($script:SpokenTextGuidance) Avoid markdown, raw symbols, and abbreviations that wouldn't make sense read aloud. Output ONLY the summary itself - no preamble, no options, no alternate phrasings, no quotation marks around it, nothing else.`n`n---`n`n$Text"

    # Both encodings are set to UTF-8 for the call: $OutputEncoding is how the
    # prompt is sent to claude, [Console]::OutputEncoding how its answer is read.
    # $OutputEncoding must be set in the global scope: a plain assignment inside
    # a function creates a local variable the pipe to a native command ignores.
    $previousPipeEncoding = $global:OutputEncoding
    $previousConsoleEncoding = [Console]::OutputEncoding
    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $global:OutputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
        $result = $prompt | & claude -p --safe-mode --no-session-persistence --model haiku 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $result) { return $null }
        $summary = ($result -join "`n").Trim()
        if ($summary) { return $summary }
        return $null
    } catch {
        return $null
    } finally {
        $global:OutputEncoding = $previousPipeEncoding
        [Console]::OutputEncoding = $previousConsoleEncoding
    }
}
