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

# Strips markdown so it sounds natural instead of reading symbols aloud.
# Note: this only cleans formatting, it doesn't rewrite the text.
#
# Considered and rejected: switching to a second installed voice for
# technical terms (filenames/commands, almost always English regardless of
# the response's language), so they'd be pronounced correctly instead of
# with the main voice's accent. It technically worked (confirmed live with
# SpeechSynthesizer's VoiceChange event, and PromptBuilder + StartVoice),
# but two problems killed it: switching voices roughly doubled the total
# speaking time on a code-heavy response (measured: 44s vs ~20s for the
# same text), and - the bigger issue - two different installed voices
# alternating mid-response sounds like two different people talking, not
# one voice reading a response.
#
# What's used instead: Get-PronunciationPrompt (common.ps1) keeps the ONE
# main voice for everything, but gives it a correct IPA pronunciation hint
# for known technical words (git, config, hook, etc.) via
# PromptBuilder.AppendTextWithPronunciation - no voice change, no extra
# delay worth mentioning. Confirmed via VoiceChange that the voice never
# switches with this approach. Only covers a curated word list, not
# arbitrary code identifiers - unlisted words still read with the main
# voice's normal pronunciation, same as before this existed.
# File names read oddly aloud: SAPI's text-normalization front end doesn't
# treat a "." between two word characters ("common.ps1") as reliably as a
# person would - it can swallow it into an odd pause instead of reading it as
# part of the name. The IPA dictionary in common.ps1 fixes mispronounced
# whole words, but that doesn't touch this - it's not a pronunciation
# problem, it's how the raw character is being interpreted before it ever
# gets to pronunciation. Scoped to a maintained list of known extensions
# (not every dot) specifically to avoid mangling real sentence-ending
# periods. " punto " (not "dot") because this project's spoken output is
# Spanish by default (see README) - same choice already made throughout
# this file and the rest of the plugin.
$script:KnownFileExtensions = @(
    'ps1', 'ps1xml', 'psm1', 'psd1', 'json', 'md', 'markdown', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx',
    'py', 'html', 'htm', 'css', 'scss', 'less', 'yml', 'yaml', 'txt', 'csv', 'tsv', 'xml', 'sh', 'bash',
    'cfg', 'ini', 'conf', 'log', 'env', 'lock', 'toml', 'sql', 'rb', 'go', 'rs', 'java', 'c', 'cpp', 'h',
    'hpp', 'php', 'vue', 'svelte', 'pdf', 'zip', 'exe', 'dll', 'bat', 'cmd', 'csproj', 'sln'
)

function Get-CleanedText {
    param([string]$Text)

    $emDash = [char]0x2014
    $enDash = [char]0x2013
    $ellipsis = [char]0x2026

    $extPattern = ($script:KnownFileExtensions | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $Text = [regex]::Replace($Text, "\b([\w-]+)\.($extPattern)\b", '$1 punto $2', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $Text = $Text -replace '(?s)```.*?```', ' code block omitted. '
    $Text = $Text -replace '(?s)<!--.*?-->', ''                    # stray HTML comments, if any
    $Text = $Text -replace '\[([^\]]+)\]\([^\)]+\)', '$1'          # [text](link) -> text
    $Text = $Text -replace '(?m)^\s{0,3}[-*+]\s+', ''               # list bullets
    $Text = $Text -replace '(?m)^\s{0,3}\d+\.\s+', ''                # numbered lists
    $Text = $Text -replace '(?m)^\s{0,3}#{1,6}\s*', ''               # headings
    $Text = $Text -replace '(?m)^\s{0,3}>\s?', ''                    # quotes
    $Text = $Text -replace '(?m)^\s*[-*_]{3,}\s*$', ' '              # horizontal rules
    $Text = $Text.Replace([string]$emDash, ', ').Replace([string]$enDash, ', ')
    $Text = $Text.Replace([string]$ellipsis, '...')
    $Text = $Text -replace '[*_#`]', ''
    return $Text.Trim()
}

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
#     the model speaks its own short paraphrase during the turn itself, via
#     say.ps1 (prompted every turn by prompt-active-mode.ps1). Skipping
#     here is what keeps this from producing double/overlapping audio with
#     that mechanism.

try {
    & $Log "starting. PluginData=[$PluginData]"

    if ($config -and $config.muted -eq $true) {
        & $Log "muted, exiting without reading stdin"
        exit 0
    }

    # Raw stdin bytes are read instead of [Console]::In.ReadToEnd(): that
    # method decodes using [Console]::InputEncoding, which for redirected
    # stdin picks up the console's OEM codepage (e.g. 850), not UTF-8 — and
    # Claude Code sends the hook JSON as UTF-8, so accented characters got
    # corrupted.
    $inputStream = [Console]::OpenStandardInput()
    $buffer = New-Object System.IO.MemoryStream
    $inputStream.CopyTo($buffer)
    $bytes = $buffer.ToArray()
    & $Log "stdin: $($bytes.Length) bytes"
    if ($bytes.Length -eq 0) { & $Log "empty stdin, exiting"; exit 0 }
    $json = [System.Text.Encoding]::UTF8.GetString($bytes)

    $event = $json | ConvertFrom-Json

    $rawText = $event.last_assistant_message
    if (-not $rawText) { & $Log "no last_assistant_message, exiting"; exit 0 }
    & $Log "last_assistant_message: $($rawText.Length) characters"

    $mode = if ($config -and $config.mode) { $config.mode } else { 'natural' }
    if ($mode -eq 'active') {
        & $Log "mode=[active]: the model speaks for itself via say.ps1, nothing to do here"
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
        Set-Content -Path (Join-Path $PluginData "last-text.txt") -Value $text -Encoding UTF8
    }

    Invoke-SpeechSynthesis -Text $text -Config $config -UsePronunciation ($mode -ne 'literal') -Log $Log
} catch {
    & $Log "EXCEPTION: $($_.Exception.GetType().Name): $($_.Exception.Message)"
    exit 0
}
