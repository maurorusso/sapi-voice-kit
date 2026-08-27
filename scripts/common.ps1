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
# File names read oddly aloud: SAPI's text-normalization front end doesn't
# treat a "." between two word characters ("common.ps1") as reliably as a
# person would - it can swallow it into an odd pause instead of reading it as
# part of the name. Scoped to a maintained list of known extensions (not
# every dot) specifically to avoid mangling real sentence-ending periods.
# " punto " (not "dot") because this project's spoken output is Spanish by
# default (see README) - same choice already made throughout the plugin.
#
# Shared (not just speak.ps1's problem): natural/literal go through
# Get-CleanedText, a mechanical step with no model involved, so a regex is a
# complete fix there. summary/active/read-last instead ask the *model* to
# write "punto" itself (that text is never shown on screen, so there's no
# cost to phrasing it however sounds best spoken) - but a written instruction
# is not a guarantee the model follows it every time. Calling this same
# function in say.ps1 right before speaking closes that gap: a no-op if the
# model already wrote "punto" (no literal dot left to match), a real fix if
# it didn't.
#
# Deliberately excludes 'c', 'h', and 'go': those are also ordinary short
# words/letters ("la opción c", "vamos", a single initial) that are far more
# likely to show up right after a period than as this project's file
# extension, and a false match only costs an odd extra "punto" - not worth
# the trade for these three specifically. Every other entry here is
# extension-shaped enough (or Spanish/English word-unlike enough - 'rb',
# 'sh', 'cpp', 'hpp'...) that a stray match is unlikely enough to be worth it.
$script:KnownFileExtensions = @(
    'ps1', 'ps1xml', 'psm1', 'psd1', 'json', 'md', 'markdown', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx',
    'py', 'html', 'htm', 'css', 'scss', 'less', 'yml', 'yaml', 'txt', 'csv', 'tsv', 'xml', 'sh', 'bash',
    'cfg', 'ini', 'conf', 'log', 'env', 'lock', 'toml', 'sql', 'rb', 'rs', 'java', 'cpp',
    'hpp', 'php', 'vue', 'svelte', 'pdf', 'zip', 'exe', 'dll', 'bat', 'cmd', 'csproj', 'sln'
)

function ConvertTo-SpokenFileNames {
    param([string]$Text)
    $extPattern = ($script:KnownFileExtensions | ForEach-Object { [regex]::Escape($_) }) -join '|'
    # (?:[^\s\\/]+[\\/])* consumes any leading path segments - folders, a
    # Windows drive letter ("C:"), either \ or / as separator - right up to
    # the file name, so a full path ("C:\Desarrollos\...\common.ps1" or
    # "scripts/common.ps1") collapses to just "common punto ps1" instead of
    # also reading every folder in between. Same reasoning as URLs below:
    # research (couldn't find one canonical rule for this - TTS engines each
    # build their own domain-specific normalization for paths/dates/URLs
    # rather than relying on default behavior) confirms there's no single
    # "correct" way, so this follows the same "say what matters, not the
    # full technical string" call already made for URLs and markdown links.
    return [regex]::Replace($Text, "(?:[^\s\\/]+[\\/])*([\w-]+)\.($extPattern)\b", '$1 punto $2', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

# Catches what ConvertTo-SpokenFileNames can't: a path with no recognized
# extension at the end - a bare folder mention ("C:\Desarrollos\IA"), or a
# file with an extension not in the list above. Scoped specifically to a
# Windows drive-letter-absolute path ("C:\...") since that prefix alone is
# an unambiguous, essentially false-positive-free signal (nothing in normal
# prose looks like "C:\") - collapses it to just its last segment, the same
# way a full file path collapses to just the file name above.
function ConvertTo-SpokenPaths {
    param([string]$Text)
    return [regex]::Replace($Text, '[A-Za-z]:[\\/](?:[^\s\\/]+[\\/])*([^\s\\/]+)', '$1')
}

# URLs read badly aloud, and not just because they're long and full of
# punctuation: "https://..." starts with a colon immediately followed by a
# slash, a sequence some TTS engines' text normalization recognizes as the
# ":/" emoticon (a "confused"/displeased face) before ever getting to
# recognizing it's a URL - observed live (a spoken response reading a plain
# https:// link came out announcing an emoticon instead of the link).
# Simplest fix, and consistent with how markdown links already work here
# (the [text](url) regex below speaks the label, never the URL): don't speak
# raw URLs at all. The screen still shows the exact link untouched - this
# only changes what gets read aloud, same principle as every other cleanup
# step in this file.
function ConvertTo-SpokenUrls {
    param([string]$Text)
    # "el link" alone doesn't distinguish two different links in the same
    # response (raised by a reviewer, not urgent then - worth doing since
    # it's cheap). Says the domain's brand name instead: from the host,
    # drop "www.", split on ".", and take the second-to-last label
    # (github.com -> github; docs.github.com -> github, ignoring the
    # subdomain). Doesn't handle multi-part TLDs like .co.uk correctly
    # (would say "co" instead of the real name) - not worth the extra
    # complexity for links this project's own responses realistically
    # contain (mostly GitHub).
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $hostName = $m.Groups[1].Value
        $parts = $hostName -split '\.'
        $brand = if ($parts.Count -ge 2) { $parts[$parts.Count - 2] } else { $parts[0] }
        return "el link de $brand"
    }
    return [regex]::Replace($Text, 'https?://(?:www\.)?([^/\s]+)\S*', $evaluator)
}

function Get-PronunciationPrompt {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][hashtable]$Dictionary,
        [System.Globalization.CultureInfo]$Culture
    )

    # Tokenizes $Text once with a fixed-cost pattern ('\w+' - independent of
    # $Dictionary's size), then does an O(1) hashtable lookup per token -
    # instead of building one big alternation regex out of every dictionary
    # key and matching THAT against the text (what this used to do). Same
    # matching semantics (word-boundary, case-insensitive exact match), same
    # output - just decouples matching cost from dictionary size. Measured
    # why this matters, and why it isn't urgent: at this dictionary's real
    # size (82 entries) the old approach took ~1.6ms/call; a synthetic 20x
    # larger dictionary (1640 entries) took ~15ms/call - a real, measurable
    # scaling relationship, but still negligible next to the several seconds
    # Speak() itself takes. This dictionary is curated tech vocabulary, not
    # a general-language dictionary (see the CLAUDE.md note on why importing
    # one of those was rejected) - it will never reasonably reach a size
    # where that mattered. This change removes the ceiling anyway, for free,
    # with identical behavior - cheap insurance, not a fix for an active
    # problem.
    $tokenMatches = [regex]::Matches($Text, '\w+')
    if ($tokenMatches.Count -eq 0) { return $null }

    $prompt = $null
    $lastEnd = 0
    foreach ($m in $tokenMatches) {
        $key = $m.Value.ToLowerInvariant()
        if (-not $Dictionary.ContainsKey($key)) { continue }
        # PromptBuilder() with no arguments defaults to the *machine's*
        # current language-culture setting (Microsoft's own documented
        # behavior), not necessarily the culture of the voice actually
        # selected - and even when the two look like the same value, using
        # the parameterless constructor produced audibly wrong stress on
        # unrelated Spanish words elsewhere in the same prompt (confirmed
        # live: "corregi" stressed on the wrong syllable). Passing the
        # voice's own Culture explicitly fixed it - confirmed live, same
        # text, same voice, only this constructor call changed.
        if (-not $prompt) {
            $prompt = if ($Culture) { New-Object System.Speech.Synthesis.PromptBuilder($Culture) } else { New-Object System.Speech.Synthesis.PromptBuilder }
        }
        if ($m.Index -gt $lastEnd) {
            $prompt.AppendText($Text.Substring($lastEnd, $m.Index - $lastEnd))
        }
        $prompt.AppendTextWithPronunciation($m.Value, $Dictionary[$key])
        $lastEnd = $m.Index + $m.Length
    }
    if (-not $prompt) { return $null }
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

    $prompt = if ($UsePronunciation) { Get-PronunciationPrompt -Text $Text -Dictionary $script:TechPronunciations -Culture $synth.Voice.Culture } else { $null }

    # Cross-process mutex: each plugin process (this session's Stop hook,
    # another parallel session's Stop hook, active mode's say.ps1, ...) gets
    # its own SpeechSynthesizer with no knowledge of any other process. Two
    # sessions speaking at once produced genuinely overlapping, unintelligible
    # audio on the shared output device (observed live: two parallel Claude
    # Code sessions with this plugin active). A named Mutex serializes actual
    # speech across every process on the machine that uses this function -
    # whoever gets here first speaks, the rest wait their turn instead of
    # talking over each other. WaitOne has a timeout so a process that died
    # while holding the mutex (or one that's just taking unusually long)
    # can't permanently silence everyone else - after 60s, speak anyway
    # rather than staying silent forever. AbandonedMutexException is caught
    # and treated as "got it" (that's .NET's normal way of reporting a
    # previous holder exited without releasing - the mutex is still valid).
    # Local\ (session-scoped), not Global\: the actual problem this solves -
    # two Claude Code sessions on the same desktop, same Windows login -
    # never crosses a session boundary, and Global\ requires a privilege
    # (SeCreateGlobalPrivilege) a restricted or Remote-Desktop-session user
    # may not have. Local\ needs no special privilege and is sufficient for
    # the real scenario, so there's no reason to ask for the broader one.
    $mutex = New-Object System.Threading.Mutex($false, 'Local\SapiVoiceKitSpeak')
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne(60000)
        } catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
            & $Log "previous holder of the speech mutex exited without releasing it - continuing anyway"
        }
        if (-not $acquired) {
            & $Log "timed out waiting 60s for another process to finish speaking - speaking anyway instead of staying silent"
        } else {
            & $Log "acquired cross-process speech mutex"
        }

        if ($prompt) {
            & $Log "calling Speak() with pronunciation hints (same voice throughout)"
            $synth.Speak($prompt)
        } else {
            & $Log "calling Speak() (no known technical terms to hint)"
            $synth.Speak($Text)
        }
        & $Log "Speak() finished OK"
    } finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
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

    $prompt = "Summarize the following text in 2-4 natural spoken sentences that capture the key points, in the same language as the text. This summary will ONLY ever be spoken aloud by a text-to-speech engine, never shown on screen - write it accordingly: if you mention a file name, say the word for a period (e.g. 'punto' in Spanish, 'dot' in English) instead of writing a literal '.' character, since a literal period right before a file extension reads oddly aloud (for example write 'common punto pe ese uno', not 'common.ps1'). If you'd mention a URL/link, don't write it out - refer to it by its site name instead (e.g. 'el link de GitHub', 'the GitHub link') so two different links in the same response are still told apart, and let the reader look at the screen for the actual address, since a raw URL read character-by-character (and the 'https://' part specifically) sounds wrong spoken aloud. Same idea for a full file path (e.g. 'C:\Users\...\common.ps1' or 'scripts/common.ps1') - just say the file name ('common punto pe ese uno'), not every folder in between. Avoid markdown, raw symbols, and abbreviations that wouldn't make sense read aloud. Output ONLY the summary itself - no preamble, no options, no alternate phrasings, no quotation marks around it, nothing else.`n`n---`n`n$Text"

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
