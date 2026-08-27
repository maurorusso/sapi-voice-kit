# Shared functions for the plugin's scripts: read/save the voice config, and a small logger.

function Get-ConfigPath {
    param([Parameter(Mandatory)][string]$PluginData)
    if (-not (Test-Path $PluginData)) {
        New-Item -ItemType Directory -Path $PluginData -Force | Out-Null
    }
    return Join-Path $PluginData "config.json"
}

function Get-VoiceConfig {
    param([Parameter(Mandatory)][string]$PluginData)

    $path = Get-ConfigPath -PluginData $PluginData
    if (-not (Test-Path $path)) { return $null }
    try {
        return Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        # A corrupted/truncated config.json shouldn't take the whole plugin
        # down (both hooks would go permanently silent) - treat it the same
        # as "no config yet".
        return $null
    }
}

# Loads config.json as an editable hashtable, applies $Changes on top of it,
# removes any key named in $Remove, and saves it back. Shared by
# set-voice.ps1/set-mode.ps1 so they don't each hand-roll their own
# read-modify-write logic. Returns the resulting hashtable.
function Save-VoiceConfig {
    param(
        [Parameter(Mandatory)][string]$PluginData,
        [hashtable]$Changes = @{},
        [string[]]$Remove = @()
    )

    $path = Get-ConfigPath -PluginData $PluginData
    $current = @{}
    if (Test-Path $path) {
        try {
            (Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json).psobject.Properties |
                ForEach-Object { $current[$_.Name] = $_.Value }
        } catch {
            $current = @{}
        }
    }

    foreach ($key in $Changes.Keys) { $current[$key] = $Changes[$key] }
    foreach ($key in $Remove) { $current.Remove($key) }

    $current | ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
    return $current
}

# Picks which installed voice to use: manual override (name or language) if
# set, otherwise the installed voice matching the system language, otherwise
# null (let System.Speech use its default voice).
function Resolve-Voice {
    param(
        [Parameter(Mandatory)][System.Speech.Synthesis.SpeechSynthesizer]$Synth,
        $Config
    )

    $voices = $Synth.GetInstalledVoices() | Where-Object { $_.Enabled }

    if ($Config -and $Config.voiceName) {
        $chosen = $voices | Where-Object { $_.VoiceInfo.Name -eq $Config.voiceName } | Select-Object -First 1
        if ($chosen) { return $chosen.VoiceInfo.Name }
    }

    $language = if ($Config -and $Config.language) { $Config.language } else { (Get-Culture).Name }
    $prefix = $language.Split('-')[0]

    $byCulture = $voices | Where-Object { $_.VoiceInfo.Culture.Name -eq $language } | Select-Object -First 1
    if ($byCulture) { return $byCulture.VoiceInfo.Name }

    $byLanguage = $voices | Where-Object { $_.VoiceInfo.Culture.TwoLetterISOLanguageName -eq $prefix } | Select-Object -First 1
    if ($byLanguage) { return $byLanguage.VoiceInfo.Name }

    return $null
}

# IPA pronunciations for common programming/dev terms, so the SAME voice
# (no voice-switching - see speak.ps1 for why that was rejected) can say
# them correctly instead of applying its main language's letter-to-sound
# rules to an English word. Verified live that AppendTextWithPronunciation
# accepts concatenated IPA characters with no spaces between them (the
# documented Microsoft example is "duˈbwɑ" for "DuBois") and does NOT
# switch voice - confirmed via SpeechSynthesizer's VoiceChange event.
# Deliberately modest and high-confidence rather than exhaustive: an
# unlisted word just gets read normally, same as before this existed - a
# safe fallback, not a regression.
$script:TechPronunciations = @{
    'git'      = "$([char]0x0261)$([char]0x026a)t"
    'github'   = "$([char]0x0261)$([char]0x026a)th$([char]0x028c)b"
    'commit'   = "k$([char]0x0259)$([char]0x02c8)m$([char]0x026a)t"
    'push'     = "p$([char]0x028a)$([char]0x0283)"
    'pull'     = "p$([char]0x028a)l"
    'merge'    = "m$([char]0x025c)rd$([char]0x0292)"
    'branch'   = "br$([char]0x00e6)nt$([char]0x0283)"
    'clone'    = "klo$([char]0x028a)n"
    'hook'     = "h$([char]0x028a)k"
    'plugin'   = "$([char]0x02c8)pl$([char]0x028c)$([char]0x0261)$([char]0x026a)n"
    'bug'      = "b$([char]0x028c)$([char]0x0261)"
    'debug'    = "di$([char]0x02c8)b$([char]0x028c)$([char]0x0261)"
    'config'   = "k$([char]0x0259)n$([char]0x02c8)f$([char]0x026a)$([char]0x0261)"
    'json'     = "$([char]0x02c8)d$([char]0x0292)e$([char]0x026a)s$([char]0x0251)n"
    'null'     = "n$([char]0x028c)l"
    'string'   = "str$([char]0x026a)$([char]0x014b)"
    'function' = "$([char]0x02c8)f$([char]0x028c)$([char]0x014b)k$([char]0x0283)$([char]0x0259)n"
    'variable' = "$([char]0x02c8)v$([char]0x025b)ri$([char]0x0259)b$([char]0x0259)l"
    'array'    = "$([char]0x0259)$([char]0x02c8)re$([char]0x026a)"
    'boolean'  = "$([char]0x02c8)bul$([char]0x026a)$([char]0x0259)n"
    'object'   = "$([char]0x02c8)$([char]0x0251)bd$([char]0x0292)$([char]0x025b)kt"
    'class'    = "kl$([char]0x00e6)s"
    'method'   = "$([char]0x02c8)m$([char]0x025b)$([char]0x03b8)$([char]0x0259)d"
    'error'    = "$([char]0x02c8)$([char]0x025b)r$([char]0x0259)r"
    'warning'  = "$([char]0x02c8)w$([char]0x0254)rn$([char]0x026a)$([char]0x014b)"
    'install'  = "$([char]0x026a)n$([char]0x02c8)st$([char]0x0254)l"
    'update'   = "$([char]0x028c)p$([char]0x02c8)de$([char]0x026a)t"
    'delete'   = "d$([char]0x026a)$([char]0x02c8)lit"
    'folder'   = "$([char]0x02c8)fo$([char]0x028a)ld$([char]0x0259)r"
    'file'     = "fa$([char]0x026a)l"
    'script'   = "skr$([char]0x026a)pt"
    'code'     = "ko$([char]0x028a)d"
    'test'     = "t$([char]0x025b)st"
    'build'    = "b$([char]0x026a)ld"
    'deploy'   = "d$([char]0x026a)$([char]0x02c8)pl$([char]0x0254)$([char]0x026a)"
    'server'   = "$([char]0x02c8)s$([char]0x025c)rv$([char]0x0259)r"
    'client'   = "$([char]0x02c8)kla$([char]0x026a)$([char]0x0259)nt"
    'log'      = "l$([char]0x0254)$([char]0x0261)"
    'token'    = "$([char]0x02c8)to$([char]0x028a)k$([char]0x0259)n"
    'repo'         = "$([char]0x02c8)ripo$([char]0x028a)"
    'repository'   = "r$([char]0x026a)$([char]0x02c8)p$([char]0x0251)z$([char]0x026a)t$([char]0x0254)ri"
    'backend'      = "$([char]0x02c8)b$([char]0x00e6)k$([char]0x025b)nd"
    'frontend'     = "$([char]0x02c8)fr$([char]0x028c)nt$([char]0x025b)nd"
    'framework'    = "$([char]0x02c8)fre$([char]0x026a)mw$([char]0x025c)rk"
    'library'      = "$([char]0x02c8)la$([char]0x026a)br$([char]0x025b)ri"
    'package'      = "$([char]0x02c8)p$([char]0x00e6)k$([char]0x026a)d$([char]0x0292)"
    'module'       = "$([char]0x02c8)m$([char]0x0251)d$([char]0x0292)ul"
    'import'       = "$([char]0x02c8)$([char]0x026a)mp$([char]0x0254)rt"
    'export'       = "$([char]0x02c8)$([char]0x025b)ksp$([char]0x0254)rt"
    'return'       = "r$([char]0x026a)$([char]0x02c8)t$([char]0x025c)rn"
    'loop'         = "lup"
    'index'        = "$([char]0x02c8)$([char]0x026a)nd$([char]0x025b)ks"
    'value'        = "$([char]0x02c8)v$([char]0x00e6)lju"
    'parameter'    = "p$([char]0x0259)$([char]0x02c8)r$([char]0x00e6)m$([char]0x026a)t$([char]0x0259)r"
    'argument'     = "$([char]0x02c8)$([char]0x0251)rgj$([char]0x0259)m$([char]0x0259)nt"
    'callback'     = "$([char]0x02c8)k$([char]0x0254)lb$([char]0x00e6)k"
    'async'        = "$([char]0x02c8)e$([char]0x026a)s$([char]0x026a)$([char]0x014b)k"
    'await'        = "$([char]0x0259)$([char]0x02c8)we$([char]0x026a)t"
    'promise'      = "$([char]0x02c8)pr$([char]0x0251)m$([char]0x026a)s"
    'thread'       = "$([char]0x03b8)r$([char]0x025b)d"
    'queue'        = "kju"
    'cache'        = "k$([char]0x00e6)$([char]0x0283)"
    'stack'        = "st$([char]0x00e6)k"
    'database'     = "$([char]0x02c8)de$([char]0x026a)t$([char]0x0259)be$([char]0x026a)s"
    'query'        = "$([char]0x02c8)kw$([char]0x026a)ri"
    'schema'       = "$([char]0x02c8)skim$([char]0x0259)"
    'endpoint'     = "$([char]0x02c8)$([char]0x025b)ndp$([char]0x0254)$([char]0x026a)nt"
    'request'      = "r$([char]0x026a)$([char]0x02c8)kw$([char]0x025b)st"
    'response'     = "r$([char]0x026a)$([char]0x02c8)sp$([char]0x0251)ns"
    'header'       = "$([char]0x02c8)h$([char]0x025b)d$([char]0x0259)r"
    'session'      = "$([char]0x02c8)s$([char]0x025b)$([char]0x0283)$([char]0x0259)n"
    'cookie'       = "$([char]0x02c8)k$([char]0x028a)ki"
    'container'    = "k$([char]0x0259)n$([char]0x02c8)te$([char]0x026a)n$([char]0x0259)r"
    'docker'       = "$([char]0x02c8)d$([char]0x0251)k$([char]0x0259)r"
    'terminal'     = "$([char]0x02c8)t$([char]0x025c)rm$([char]0x026a)n$([char]0x0259)l"
    'console'      = "$([char]0x02c8)k$([char]0x0251)nso$([char]0x028a)l"
    'output'       = "$([char]0x02c8)a$([char]0x028a)tp$([char]0x028a)t"
    'input'        = "$([char]0x02c8)$([char]0x026a)np$([char]0x028a)t"
    'compile'      = "k$([char]0x0259)m$([char]0x02c8)pa$([char]0x026a)l"
    'runtime'      = "$([char]0x02c8)r$([char]0x028c)nta$([char]0x026a)m"
    'syntax'       = "$([char]0x02c8)s$([char]0x026a)nt$([char]0x00e6)ks"
    'interface'    = "$([char]0x02c8)$([char]0x026a)nt$([char]0x0259)rfe$([char]0x026a)s"
}

# Builds a PromptBuilder that reads $Text in one single voice throughout,
# but with a correct pronunciation hint for any whole-word match against
# $Dictionary (case-insensitive) - see $script:TechPronunciations above.
# Returns $null when there were no matches, so the caller can fall back to
# a plain Speak(string) call instead of the extra PromptBuilder overhead.
function Get-PronunciationPrompt {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][hashtable]$Dictionary
    )

    $pattern = '\b(' + (($Dictionary.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'
    $matches = [regex]::Matches($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($matches.Count -eq 0) { return $null }

    $prompt = New-Object System.Speech.Synthesis.PromptBuilder
    $lastEnd = 0
    foreach ($m in $matches) {
        if ($m.Index -gt $lastEnd) {
            $prompt.AppendText($Text.Substring($lastEnd, $m.Index - $lastEnd))
        }
        $pronunciation = $Dictionary[$m.Value.ToLowerInvariant()]
        $prompt.AppendTextWithPronunciation($m.Value, $pronunciation)
        $lastEnd = $m.Index + $m.Length
    }
    if ($lastEnd -lt $Text.Length) {
        $prompt.AppendText($Text.Substring($lastEnd))
    }
    return $prompt
}

# Speaks $Text using the configured voice, rate, and (optionally) the
# pronunciation dictionary. Shared by speak.ps1 (Stop hook - natural/
# literal/summary modes) and say.ps1 (active mode - model-invoked via
# stdin), so both paths pick voice/rate/pronunciation the same way.
function Invoke-SpeechSynthesis {
    param(
        [Parameter(Mandatory)][string]$Text,
        $Config,
        [bool]$UsePronunciation = $true,
        [scriptblock]$Log = { param([string]$Message) }
    )

    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    & $Log "SpeechSynthesizer created"

    $chosenVoice = Resolve-Voice -Synth $synth -Config $Config
    if ($chosenVoice) { $synth.SelectVoice($chosenVoice) }
    & $Log "chosen voice: [$chosenVoice]"

    $synth.Rate = ConvertTo-SafeRate -Value $Config.rate
    & $Log "rate: $($synth.Rate)"

    $prompt = if ($UsePronunciation) { Get-PronunciationPrompt -Text $Text -Dictionary $script:TechPronunciations } else { $null }
    if ($prompt) {
        & $Log "calling Speak() with pronunciation hints (same voice throughout)"
        $synth.Speak($prompt)
    } else {
        & $Log "calling Speak() (no known technical terms to hint)"
        $synth.Speak($Text)
    }
    & $Log "Speak() finished OK"
}

# "summary" mode only: asks Claude itself for a short spoken-style summary
# of $Text via a separate `claude -p` call. -safe-mode skips loading
# plugins/hooks for that call (so it can't recursively trigger this same
# Stop hook) while keeping normal OAuth auth (unlike -bare, which forces
# API-key auth and would break for anyone logged in via subscription, not
# an API key). -model haiku keeps it fast and cheap. Measured to reliably
# take ~20 seconds regardless of text length (session startup + round trip,
# not generation time) - that's exactly why this is an opt-in mode and not
# the default. Returns $null on any failure (not installed, no network,
# unexpected output, etc.) so the caller can fall back to natural mode's
# full-text reading instead of leaving the user in silence.
function Get-AiSummary {
    param([string]$Text)

    $prompt = "Summarize the following text in 2-4 natural spoken sentences that capture the key points, in the same language as the text. Output ONLY the summary itself - no preamble, no options, no alternate phrasings, no markdown, no quotation marks around it, nothing else.`n`n---`n`n$Text"

    try {
        # [Console]::OutputEncoding controls how PowerShell decodes bytes
        # captured from an external process's stdout - it defaults to the
        # console's OEM codepage (confirmed: ibm850, not UTF-8) rather than
        # matching what `claude` (a Node process) actually writes, so
        # accented characters in the summary came back corrupted without
        # this. Same root cause as the stdin-decoding bug in speak.ps1,
        # mirrored on the output side of a captured child process instead.
        $previousEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        try {
            $result = & claude -p $prompt --safe-mode --model haiku 2>$null
        } finally {
            [Console]::OutputEncoding = $previousEncoding
        }
        if ($LASTEXITCODE -ne 0 -or -not $result) { return $null }
        $summary = ($result -join "`n").Trim()
        if ($summary) { return $summary }
        return $null
    } catch {
        return $null
    }
}

# Clamps a rate value to the range SpeechSynthesizer.Rate accepts (-10..10),
# so a bad or stale config.json value (or a future manual edit) can never
# throw and permanently silence the plugin.
function ConvertTo-SafeRate {
    param($Value)
    if ($null -eq $Value) { return 0 }
    $rate = [int]$Value
    if ($rate -lt -10) { return -10 }
    if ($rate -gt 10) { return 10 }
    return $rate
}

# Returns a logging function bound to one file, so callers don't repeat the
# "resolve path, ensure directory exists" setup on every call. Usage:
#   $Log = Get-Logger -PluginData $PluginData -FileName "log-speak.txt"
#   & $Log "some message"
#
# Bounded: the Stop hook fires on every single turn in every session where
# the plugin is active, so an unrotated log grows forever. Before each
# write, if the file has grown past $maxBytes, it's trimmed down to the
# last $keepLines lines first. The size check itself is cheap (just reads
# the file's length), so this doesn't cost anything on the common case
# where the file is still small.
function Get-Logger {
    param(
        [string]$PluginData,
        [Parameter(Mandatory)][string]$FileName
    )
    if (-not $PluginData) {
        return { param([string]$Message) }.GetNewClosure()
    }
    if (-not (Test-Path $PluginData)) {
        New-Item -ItemType Directory -Path $PluginData -Force | Out-Null
    }
    $path = Join-Path $PluginData $FileName
    $maxBytes = 50KB
    $keepLines = 200
    return {
        param([string]$Message)
        if ((Test-Path $path) -and (Get-Item $path).Length -gt $maxBytes) {
            $tail = Get-Content -Path $path -Tail $keepLines
            Set-Content -Path $path -Value $tail -Encoding UTF8
        }
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
        Add-Content -Path $path -Value $line -Encoding UTF8
    }.GetNewClosure()
}
