# Stop hook: reads Claude Code's last response aloud.
# Receives the hook event as JSON on stdin (includes last_assistant_message).

param([string]$PluginData)

. "$PSScriptRoot\common.ps1"

# Debug logging is off by default: with it off, this plugin writes nothing
# to its data folder besides the voice/language/mode settings the user
# explicitly chose (config.json) - no log files, no copy of what was
# spoken sitting around in plain text. Turn it on with
# /sapi-voice-kit:debug on when actually troubleshooting something.
$config = if ($PluginData) { Get-VoiceConfig -PluginData $PluginData } else { $null }
$debugOn = $config -and $config.debug -eq $true
$Log = Get-Logger -PluginData $(if ($debugOn) { $PluginData } else { $null }) -FileName "log-speak.txt"

# Get-CleanedText lives in common.ps1 now (it's shared with
# scripts/say-test.ps1, the /sapi-voice-kit:test command - both need the
# exact production cleanup pipeline, not a reimplementation of it).
#
# A model-written hidden <!--voice--> summary each turn was tried and
# rejected before this: a Stop hook only ever sees exactly what's already on
# screen (last_assistant_message) - there's no hidden channel, so the marker
# showed up as literal visible text in the terminal.
#
# Four modes:
#   - natural (default): local-only, doesn't shorten anything - the
#     complete response, cleaned of markdown so it sounds like speech.
#     Instant, no extra cost.
#   - literal: skips cleanup too, for the rare case someone wants to hear
#     the response byte-for-byte, symbols and all.
#   - summary: an actual condensed summary via a separate `claude -p` call
#     (Get-AiSummary in common.ps1) - opt-in, not the default, specifically
#     because that call reliably costs ~20 seconds of dead silence
#     regardless of text length (measured: session startup + round trip,
#     not generation time). Falls back to natural mode's full text if the
#     call fails for any reason, so choosing this mode is never worse than
#     natural, just sometimes slower.
#   - active: this hook does nothing at all (see the early exit below) -
#     the model speaks its own short paraphrase during the turn itself.
#     In the CLI, that's say.ps1 via a shell heredoc (prompted every turn
#     by prompt-active-mode.ps1's hook); in Claude Cowork/Desktop, which
#     doesn't fire plugin hooks at all, it's the read_aloud MCP tool
#     instead (mcp-server/server.js), reminded by skills/cowork/SKILL.md.
#     Same mode, same model-speaks-itself idea, two transports depending
#     on which client is actually running. Skipping here is what keeps
#     this hook from producing double/overlapping audio with either one.

try {
    & $Log "starting. PluginData=[$PluginData]"

    # Raw stdin bytes are read instead of [Console]::In.ReadToEnd(): that
    # method decodes using [Console]::InputEncoding, which for redirected
    # stdin picks up the console's OEM codepage (e.g. 850), not UTF-8 — and
    # Claude Code sends the hook JSON as UTF-8, so accented characters got
    # corrupted.
    #
    # Read fully before checking $muted (below) so stdin is always drained,
    # even when muted - whatever invoked this script may be doing a blocking
    # write of the full payload and not expect the child to exit before
    # reading any of it.
    $inputStream = [Console]::OpenStandardInput()
    $buffer = New-Object System.IO.MemoryStream
    $inputStream.CopyTo($buffer)
    $bytes = $buffer.ToArray()
    & $Log "stdin: $($bytes.Length) bytes"

    if ($config -and $config.muted -eq $true) {
        & $Log "muted, exiting"
        exit 0
    }
    if ($bytes.Length -eq 0) { & $Log "empty stdin, exiting"; exit 0 }
    $json = [System.Text.Encoding]::UTF8.GetString($bytes)

    $event = $json | ConvertFrom-Json

    $rawText = $event.last_assistant_message
    if (-not $rawText) { & $Log "no last_assistant_message, exiting"; exit 0 }
    & $Log "last_assistant_message: $($rawText.Length) characters"

    $mode = if ($config -and $config.mode) { $config.mode } else { 'natural' }
    if ($mode -eq 'active') {
        # The model speaks for itself, via say.ps1 (CLI) or the read_aloud
        # MCP tool (Cowork) - see the header comment above. This hook itself
        # never runs in Cowork at all (hooks don't fire there), so this
        # branch only actually matters in the CLI, keeping this hook from
        # speaking on top of what prompt-active-mode.ps1's reminder triggers.
        & $Log "mode=[active]: the model speaks for itself, nothing to do here"
        exit 0
    }

    if ($mode -eq 'literal') {
        $text = $rawText.Trim()
    } else {
        $cleaned = Get-CleanedText -Text $rawText
        if ($mode -eq 'summary') {
            & $Log "mode=[summary], asking claude -p for a summary..."
            $summary = Get-AiSummary -Text $cleaned
            if ($summary) {
                $text = $summary
                & $Log "got AI summary ($($text.Length) characters)"
            } else {
                & $Log "AI summary failed or unavailable, falling back to natural (full text)"
                $text = $cleaned
            }
        } else {
            $text = $cleaned
        }
    }
    if (-not $text) { & $Log "nothing to speak after processing"; exit 0 }
    & $Log "mode=[$mode], speaking $($text.Length) characters"

    if ($debugOn) {
        $dataDir = Resolve-SharedDataDir -PluginData $PluginData
        Set-Content -Path (Join-Path $dataDir "last-text.txt") -Value $text -Encoding UTF8
    }

    Invoke-SpeechSynthesis -Text $text -Config $config -UsePronunciation ($mode -ne 'literal') -Log $Log
} catch {
    & $Log "EXCEPTION: $($_.Exception.GetType().Name): $($_.Exception.Message)"
    exit 0
}
