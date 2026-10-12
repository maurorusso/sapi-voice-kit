# Stop hook: reads Claude Code's last response aloud. Claude Code sends the
# hook event as JSON on stdin (the text is in last_assistant_message). What is
# spoken depends on the configured mode:
#
#   natural (default)  the whole response with markdown removed
#   literal            the whole response exactly as written
#   summary            a short summary from a separate `claude -p` call (~20 s,
#                      so opt-in); the full natural text if that call fails
#   active             nothing here: the model speaks for itself mid-turn
#                      (say.ps1), and speaking here too would double the audio
#
# Hooks do not fire in Cowork, so this script only ever runs for the CLI and the
# Code tab.

. "$PSScriptRoot\common.ps1"

$context = New-ScriptContext -LogFile 'log-speak.txt'
$Log = $context.Log

try {
    # Read stdin completely even when about to exit, so the writer never blocks.
    $json = Read-StdinUtf8

    if ($context.Config.muted -eq $true) { & $Log 'muted'; exit 0 }
    $mode = if ($context.Config.mode) { $context.Config.mode } else { 'natural' }
    if ($mode -eq 'active') { & $Log 'active mode: the model speaks for itself'; exit 0 }

    $response = ($json | ConvertFrom-Json).last_assistant_message
    if (-not $response) { & $Log 'no response text in the hook event'; exit 0 }

    switch ($mode) {
        'literal' { $text = $response.Trim() }
        'summary' {
            $cleaned = Get-CleanedText -Text $response
            $text = if ($cleaned) { Get-AiSummary -Text $cleaned }
            if (-not $text) { & $Log 'no summary, reading the full text'; $text = $cleaned }
        }
        default { $text = Get-CleanedText -Text $response }
    }
    if (-not $text) { & $Log 'nothing to speak after cleanup'; exit 0 }

    if ($context.Debug) { Save-LastSpokenText -Text $text }
    Invoke-SpeechSynthesis -Text $text -Config $context.Config -UsePronunciation ($mode -ne 'literal') -Log $Log
} catch {
    & $Log "EXCEPTION: $($_.Exception.Message)"
    exit 0
}
