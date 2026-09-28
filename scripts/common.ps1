# Shared functions for the plugin's scripts: read/save the voice config, and a small logger.

# Shared instruction for any prompt that asks the model to write text meant
# only to be heard, never shown on screen (Get-AiSummary's prompt below, and
# active mode's per-turn instruction in prompt-active-mode.ps1). Kept in ONE
# place because it used to be duplicated near-verbatim in those two files
# plus skills/read-last/SKILL.md, and every wording tweak needed all three
# edited in sync (caught in review - it happened more than once in this
# project's history). SKILL.md still has its own copy: a skill's
# instructions are static markdown read directly by the model, there's no
# way to interpolate a PowerShell variable into it - so that one file still
# needs a manual sync if this wording changes, but the two PowerShell-side
# copies no longer can drift from each other.
$script:SpokenTextGuidance = 'If you mention a file name, say the word for a period (e.g. "punto" in Spanish, "dot" in English) instead of writing a literal "." character, since a raw dot right before a file extension reads oddly aloud (for example write "common punto pe ese uno", not "common.ps1"). If you would mention a URL or link, do not write it out - refer to it by its site name instead (e.g. "el link de GitHub") so two different links in the same response are still told apart, and let the reader look at the screen for the actual address, since a raw URL read aloud (the "https://" part especially) sounds wrong. Same idea for a full file path (e.g. "C:\Users\...\common.ps1" or "scripts/common.ps1") - just say the file name, not every folder in between.'

function Get-ConfigPath {
    param([Parameter(Mandatory)][string]$PluginData)
    if (-not (Test-Path $PluginData)) {
        New-Item -ItemType Directory -Path $PluginData -Force | Out-Null
    }
    return Join-Path $PluginData "config.json"
}

# Guards against speaking twice within a few seconds - can happen in
# "active" mode if, in the same CLI turn, the model both follows
# prompt-active-mode.ps1's heredoc instruction AND separately invokes
# skills/cowork/SKILL.md's read_aloud MCP tool call too (found in review:
# nothing code-level stops both from firing, since Cowork's MCP server is
# reachable from any session including the CLI - only the skill's own
# "you're the CLI, do nothing" instruction discourages it, and that's
# advisory, not enforced). say.ps1 is the one script both paths already
# funnel through, so this lives there rather than duplicated in both
# prompt-active-mode.ps1 and mcp-server/server.js. Stores only a bare
# timestamp, never the text - same privacy stance as everywhere else in this
# plugin (see README's Privacidad section): nothing readable ends up on disk
# just to support this check.
# Originally compared a hash of the text too (only treat it as a duplicate
# if the exact same text was spoken), matching the exact double-speak
# scenario it was designed around: the CLI heredoc and Cowork's read_aloud
# MCP tool call funnel through this same script, but the model writes an
# independent paraphrase for each one - review confirmed those two
# paraphrases of the same response are very unlikely to be byte-identical,
# so the hash check defeated the guard's own purpose (it would almost never
# actually match in the one situation it exists for). Time-only now: any
# active-mode speech within the window counts, regardless of content - a
# real second turn's worth of new content taking under a few seconds
# (thinking, tool calls, generation) essentially never happens in practice,
# so this doesn't trade away real turns to close the gap.
function Test-RecentActiveSpeech {
    param(
        [Parameter(Mandatory)][string]$PluginData,
        [int]$WindowSeconds = 8
    )
    $path = Join-Path $PluginData ".last-active-speech"
    if (-not (Test-Path $path)) { return $false }
    try {
        $lastTicks = [long](Get-Content -Path $path -Raw -Encoding UTF8).Trim()
        $elapsedTicks = (Get-Date).Ticks - $lastTicks
        return ($elapsedTicks -le [TimeSpan]::FromSeconds($WindowSeconds).Ticks)
    } catch {
        # A corrupted/missing marker should never block real speech - treat
        # it the same as "no recent duplicate".
        return $false
    }
}

# Only ever called for a non-forced speech (see say.ps1) - an explicit
# on-demand read ("leeme eso") deliberately does NOT update this marker, so
# it can never cause the *next* turn's real automatic speech to be wrongly
# swallowed as a "recent duplicate" of an intentional repeat.
function Set-RecentSpeechMarker {
    param([Parameter(Mandatory)][string]$PluginData)
    try {
        if (-not (Test-Path $PluginData)) {
            New-Item -ItemType Directory -Path $PluginData -Force | Out-Null
        }
        $path = Join-Path $PluginData ".last-active-speech"
        "$((Get-Date).Ticks)" | Set-Content -Path $path -Encoding UTF8
    } catch {
        # Best-effort only - never let a failure to write this marker block
        # the speech that already happened.
    }
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
    'git'      = "$([char]0x02c8)$([char]0x0261)$([char]0x026a)t"
    'github'   = "$([char]0x02c8)$([char]0x0261)$([char]0x026a)th$([char]0x028c)b"
    'commit'   = "k$([char]0x0259)$([char]0x02c8)m$([char]0x026a)t"
    'push'     = "$([char]0x02c8)p$([char]0x028a)$([char]0x0283)"
    'pull'     = "$([char]0x02c8)p$([char]0x028a)l"
    'merge'    = "$([char]0x02c8)m$([char]0x025c)rd$([char]0x0292)"
    'branch'   = "$([char]0x02c8)br$([char]0x00e6)nt$([char]0x0283)"
    'clone'    = "$([char]0x02c8)klo$([char]0x028a)n"
    'hook'     = "$([char]0x02c8)h$([char]0x028a)k"
    'plugin'   = "$([char]0x02c8)pl$([char]0x028c)$([char]0x0261)$([char]0x026a)n"
    'bug'      = "$([char]0x02c8)b$([char]0x028c)$([char]0x0261)"
    'debug'    = "di$([char]0x02c8)b$([char]0x028c)$([char]0x0261)"
    'config'   = "k$([char]0x0259)n$([char]0x02c8)f$([char]0x026a)$([char]0x0261)"
    'json'     = "$([char]0x02c8)d$([char]0x0292)e$([char]0x026a)s$([char]0x0251)n"
    'null'     = "$([char]0x02c8)n$([char]0x028c)l"
    'string'   = "$([char]0x02c8)str$([char]0x026a)$([char]0x014b)"
    'function' = "$([char]0x02c8)f$([char]0x028c)$([char]0x014b)k$([char]0x0283)$([char]0x0259)n"
    'variable' = "$([char]0x02c8)v$([char]0x025b)ri$([char]0x0259)b$([char]0x0259)l"
    'array'    = "$([char]0x0259)$([char]0x02c8)re$([char]0x026a)"
    'boolean'  = "$([char]0x02c8)bul$([char]0x026a)$([char]0x0259)n"
    'object'   = "$([char]0x02c8)$([char]0x0251)bd$([char]0x0292)$([char]0x025b)kt"
    'class'    = "$([char]0x02c8)kl$([char]0x00e6)s"
    'method'   = "$([char]0x02c8)m$([char]0x025b)$([char]0x03b8)$([char]0x0259)d"
    'error'    = "$([char]0x02c8)$([char]0x025b)r$([char]0x0259)r"
    'warning'  = "$([char]0x02c8)w$([char]0x0254)rn$([char]0x026a)$([char]0x014b)"
    'install'  = "$([char]0x026a)n$([char]0x02c8)st$([char]0x0254)l"
    'update'   = "$([char]0x028c)p$([char]0x02c8)de$([char]0x026a)t"
    'delete'   = "d$([char]0x026a)$([char]0x02c8)lit"
    'folder'   = "$([char]0x02c8)fo$([char]0x028a)ld$([char]0x0259)r"
    'file'     = "$([char]0x02c8)fa$([char]0x026a)l"
    'script'   = "$([char]0x02c8)skr$([char]0x026a)pt"
    'code'     = "$([char]0x02c8)ko$([char]0x028a)d"
    'test'     = "$([char]0x02c8)t$([char]0x025b)st"
    'build'    = "$([char]0x02c8)b$([char]0x026a)ld"
    'deploy'   = "d$([char]0x026a)$([char]0x02c8)pl$([char]0x0254)$([char]0x026a)"
    'server'   = "$([char]0x02c8)s$([char]0x025c)rv$([char]0x0259)r"
    'client'   = "$([char]0x02c8)kla$([char]0x026a)$([char]0x0259)nt"
    'log'      = "$([char]0x02c8)l$([char]0x0254)$([char]0x0261)"
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
    'loop'         = "$([char]0x02c8)lup"
    'index'        = "$([char]0x02c8)$([char]0x026a)nd$([char]0x025b)ks"
    'value'        = "$([char]0x02c8)v$([char]0x00e6)lju"
    'parameter'    = "p$([char]0x0259)$([char]0x02c8)r$([char]0x00e6)m$([char]0x026a)t$([char]0x0259)r"
    'argument'     = "$([char]0x02c8)$([char]0x0251)rgj$([char]0x0259)m$([char]0x0259)nt"
    'callback'     = "$([char]0x02c8)k$([char]0x0254)lb$([char]0x00e6)k"
    'async'        = "$([char]0x02c8)e$([char]0x026a)s$([char]0x026a)$([char]0x014b)k"
    'await'        = "$([char]0x0259)$([char]0x02c8)we$([char]0x026a)t"
    'promise'      = "$([char]0x02c8)pr$([char]0x0251)m$([char]0x026a)s"
    'thread'       = "$([char]0x02c8)$([char]0x03b8)r$([char]0x025b)d"
    'queue'        = "$([char]0x02c8)kju"
    'cache'        = "$([char]0x02c8)k$([char]0x00e6)$([char]0x0283)"
    'stack'        = "$([char]0x02c8)st$([char]0x00e6)k"
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
    # Proper nouns / product names and a few more loanwords - added after
    # feedback that words like these (highlighted as code/file references in
    # Claude Code's own UI) were coming out mispronounced. Confirmed live,
    # one by one, same as every entry above - see CLAUDE.md's design notes
    # for the two patterns that came out of that listening pass: every
    # monosyllable needs an explicit stress mark even though there's only
    # one syllable to stress (app, skill, claude, node, prompt...), and a
    # few loanwords sound better "castellanizado" - a plain Spanish vowel
    # instead of the closer-to-native English one. `prompt`, `model`, and
    # `localhost` are deliberately castellanized this way (confirmed by ear,
    # not a transcription mistake) - don't "fix" them back to English IPA
    # without listening first; `node`, right next to them and using the
    # same English diphthong "wrong" for `local`, was confirmed to already
    # sound fine and was deliberately left alone.
    'readme'       = "$([char]0x02c8)ridmi"
    'npm'          = "$([char]0x025b)npi$([char]0x02c8)$([char]0x025b)m"
    'node'         = "$([char]0x02c8)no$([char]0x028a)d"
    'javascript'   = "$([char]0x02c8)d$([char]0x0292)$([char]0x00e6)v$([char]0x0259)skr$([char]0x026a)pt"
    'typescript'   = "$([char]0x02c8)ta$([char]0x026a)pskr$([char]0x026a)pt"
    'python'       = "$([char]0x02c8)pa$([char]0x026a)$([char]0x03b8)$([char]0x0251)n"
    'markdown'     = "$([char]0x02c8)m$([char]0x0251)rkda$([char]0x028a)n"
    'regex'        = "$([char]0x02c8)rid$([char]0x0292)$([char]0x025b)ks"
    'mcp'          = "$([char]0x025b)msi$([char]0x02c8)pi"
    'sapi'         = "$([char]0x02c8)se$([char]0x026a)pi"
    'app'          = "$([char]0x02c8)$([char]0x00e6)p"
    'skill'        = "$([char]0x02c8)sk$([char]0x026a)l"
    'prompt'       = "$([char]0x02c8)prompt"
    'agent'        = "$([char]0x02c8)e$([char]0x026a)d$([char]0x0292)$([char]0x0259)nt"
    'model'        = "$([char]0x02c8)model"
    'workflow'     = "$([char]0x02c8)w$([char]0x025d)rkflo$([char]0x028a)"
    'localhost'    = "$([char]0x02c8)lok$([char]0x0259)lhost"
    'claude'       = "$([char]0x02c8)kl$([char]0x0254)d"
    # "vs" (as in "VS Code", or standalone) - Spanish letter names ("be
    # ese"), not English ones ("vee ess") - requested directly: this voice
    # was reading the "V" the English way by default. Deliberately not
    # "uve" (the more formal Spanish name for V) - asked for specifically
    # as "como B", the casual/common pronunciation.
    'vs'           = "be$([char]0x02c8)ese"
    # "che" - took five attempts to land, worth documenting the path since
    # the wrong-looking ones are the ones a future contributor is likely to
    # try first: plain /tʃe/ (weak, swallowed vowel), the affricate ligature
    # ʧ (same), a single lengthened vowel ʧeː (same), and an open ɛ (tʃɛ,
    # same) all sounded the same - a barely-audible "e" - both on SAPI5 and
    # on the OneCore voice this is now the default engine. What actually
    # worked, confirmed live: writing the vowel TWICE (tʃee) instead of
    # using the IPA length mark for it - this voice's phoneme parser
    # apparently gives a repeated vowel character real duration in a way it
    # doesn't for a length-marked single one.
    'che'          = "$([char]0x02c8)t$([char]0x0283)ee"
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

# Dotfiles (.env, .gitignore, .mcp.json) - a leading "." is the Unix
# convention for a hidden/config file, not a real file-extension marker the
# way the "." in "common.ps1" is. Handled separately from
# ConvertTo-SpokenFileNames below because that regex requires a non-empty
# name *before* the dot it matches - a bare leading dot like ".env" has
# nothing before it to match, so it fell straight through untouched
# (confirmed live: read character-by-character by SAPI's default handling),
# and ".mcp.json" partially matched but left the leading dot itself stray
# and unspoken (confirmed live: "...json" kept a bare "." glued to "mcp").
# Reads every dot in the match as "punto", so ".env" -> "punto env" and
# ".mcp.json" -> "punto mcp punto json" - matches how a person actually says
# these out loud. Must run BEFORE ConvertTo-SpokenFileNames, so that
# function never gets a chance to partially match the same text first.
#
# The lookbehind (start of text, or right after whitespace/"("/a path
# separator/a backtick) is what keeps this from ever matching an ordinary
# sentence-ending period: "...code. Now let's..." always has a space between
# the period and the next sentence, and this pattern only matches a dot
# glued directly to a following word character with no space - real prose
# never looks like that, only a dotfile name does. The backtick is
# specifically for the common real case of Claude writing a file name as
# inline code (`` `.mcp.json` `` ) - without it in the lookbehind, that's
# exactly the same "nothing before the dot to match" gap this function
# exists to close, just one character further in (confirmed live: missing
# the backtick left the leading dot stray inside the backticks too).
function ConvertTo-SpokenDotfiles {
    param([string]$Text)
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return 'punto ' + ($m.Groups[1].Value -replace '\.', ' punto ')
    }
    return [regex]::Replace($Text, '(?<=^|[\s(\\/`])\.([\w-]+(?:\.[\w-]+)*)\b', $evaluator)
}

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

# Spoken-word replacements for common abbreviations, so "etc." reads as the
# real word "etcétera" instead of getting spelled out letter by letter
# (confirmed live: this voice's default handling of "etc." says "e t c")
# or clipped oddly. Spanish entries sourced against the RAE's own official
# abbreviation list (rae.es/buen-uso-espanol/lista-de-abreviaturas). English
# e.g./i.e. deliberately expand to their SPANISH meaning ("por ejemplo"/"es
# decir"), not their English reading - this voice is Spanish by default, and
# speaking the English words themselves ("for example") through Spanish
# letter-to-sound rules sounded worse than just saying it in Spanish
# (confirmed live). [ordered] because a couple of entries share a prefix
# ("dr." / "dra.") and must be tried in an order where the more specific one
# can't accidentally get shadowed.
#
# Every pattern ends in (?!\w): without it, 'etc\.?' (dot optional) matched
# just the first three letters of "etcétera" itself, since \b alone doesn't
# stop it - "c" and "é" are both word characters to .NET regex, so there's
# no \b between them either (confirmed live: "etc." followed by "etcétera"
# in the SAME text - the model's own fully-spelled word - came out doubled,
# "etcéteraétera"). (?!\w) blocks that: it only matches when what follows
# isn't a word character at all.
#
# "vs" requires its dot (no longer optional) for the same live-confirmed
# reason: "VS Code" (capitalized, no period - a real product name that
# comes up constantly in this project's own domain) was being expanded to
# "versus Code". A written "vs." abbreviation always carries the dot in
# practice; "VS" as a bare product-name fragment never does.
#
# Deliberately modest and high-confidence rather than exhaustive - same
# philosophy as $script:TechPronunciations below: an unlisted abbreviation
# just reads as before (whatever SAPI's default handling does with it), a
# safe fallback, not a regression. Excludes ambiguous ones on purpose -
# "min."/"max." can mean "minute(s)" or "minimum/maximum" depending on
# context, and guessing wrong would be worse than leaving it unconverted.
$script:SpokenAbbreviations = [ordered]@{
    'etc\.?(?!\w)'        = 'etcétera'
    'p\.\s?ej\.(?!\w)'    = 'por ejemplo'
    'e\.\s?g\.(?!\w)'     = 'por ejemplo'
    'i\.\s?e\.(?!\w)'     = 'es decir'
    'aprox\.(?!\w)'       = 'aproximadamente'
    'approx\.(?!\w)'      = 'aproximadamente'
    'vs\.(?!\w)'          = 'versus'
    'n[uú]m\.(?!\w)'      = 'número'
    'p[aá]g\.(?!\w)'      = 'página'
    'dra\.(?!\w)'         = 'doctora'
    'dr\.(?!\w)'          = 'doctor'
    'sra\.(?!\w)'         = 'señora'
    'sr\.(?!\w)'          = 'señor'
    'uds\.(?!\w)'         = 'ustedes'
    'ud\.(?!\w)'          = 'usted'
    'depto\.(?!\w)'       = 'departamento'
    'tel\.(?!\w)'         = 'teléfono'
}

# Replaces each abbreviation with its spoken word, and - only when the
# abbreviation's own dot also looks like it closed the sentence (followed by
# whitespace-then-uppercase, or by the end of the text) - keeps a period
# after it. "etc." doing double duty as both the abbreviation's dot and the
# sentence's own final period is by far the most common case of this
# (confirmed live: "gatos, etc. Después seguimos." lost its only sentence
# boundary when "etc." became "etcétera" with no period, running both
# sentences together). Mid-sentence uses ("p. ej. usando Node") don't look
# like this and correctly get no extra period.
#
# Title abbreviations (Dr., Dra., Sr., Sra.) are excluded from that
# heuristic entirely: they're always immediately followed by a capitalized
# name in the SAME sentence, by definition, so "followed by whitespace then
# an uppercase letter" - the exact signal used for every other entry - is
# guaranteed true for these and means the opposite of what it means
# elsewhere. Confirmed live: without this exclusion, "Dr. García" became
# "doctor. García", inserting a false sentence break into someone's name.
$script:AbbreviationsNeverPreservePeriod = @('dra\.(?!\w)', 'dr\.(?!\w)', 'sra\.(?!\w)', 'sr\.(?!\w)')

function ConvertTo-SpokenAbbreviations {
    param([string]$Text)
    foreach ($pattern in $script:SpokenAbbreviations.Keys) {
        $word = $script:SpokenAbbreviations[$pattern]
        $preservePeriod = $script:AbbreviationsNeverPreservePeriod -notcontains $pattern
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            if ($preservePeriod -and $m.Value.EndsWith('.')) {
                $tail = $Text.Substring($m.Index + $m.Length)
                if ($tail -match '^\s*($|[A-ZÁÉÍÓÚÑ])') { return "$word." }
            }
            return $word
        }
        $Text = [regex]::Replace($Text, "\b$pattern", $evaluator, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    return $Text
}

# Markdown/plain text often wraps a sentence or paragraph onto a new line
# without a trailing period - especially the last line before a blank line -
# and TTS reads straight through that as one run-on sentence with no pause,
# since nothing marks the boundary. Requested directly: any line break
# should be treated as if the line had ended with a period, unless it
# genuinely already ends in real punctuation (a period, question/exclamation
# mark, colon, semicolon, or comma - a comma-ending line is a deliberate
# mid-sentence wrap, not a paragraph break, and forcing a period there would
# cut the sentence wrong). Uses a lookahead for the newline instead of
# consuming it, so it never has to re-emit a CRLF-vs-LF newline itself.
#
# A closing ")"/quote is NOT excluded (unlike the punctuation above) - a
# line ending in one still needs the same boundary marker as any other word
# would (confirmed live: "Instalalo (ver README)\nDespués seguimos" got no
# period at all before this, since ")" was wrongly treated as already
# "real" terminal punctuation - it isn't, it's just closing a parenthetical).
#
# An em/en dash IS excluded, but for the opposite reason: not because it's
# already terminal, but to avoid a real bug this function introduced when it
# wasn't excluded - a period appended right after a dash survived into the
# em-dash-to-comma replacement a few lines below in Get-CleanedText, turning
# "Paso uno —" into "Paso uno , ." (confirmed live). A dash already implies
# continuation, same as a colon (already excluded above), so leaving it out
# here is correct on its own terms too, not just a workaround.
function Add-ImplicitLineEndPeriods {
    param([string]$Text)
    $emDash = [char]0x2014
    $enDash = [char]0x2013
    $ellipsis = [char]0x2026
    return [regex]::Replace($Text, "(?m)[^\s.!?:;,$emDash$enDash$ellipsis](?=[ \t]*\r?\n)", '$&.')
}

# Strips markdown so it sounds natural instead of reading symbols aloud.
# Note: this only cleans formatting, it doesn't rewrite the text. Used by
# speak.ps1 (Stop hook - natural mode) and scripts/say-test.ps1
# (/sapi-voice-kit:test) - both need the exact production cleanup pipeline,
# not a second copy of it.
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
# What's used instead: Get-PronunciationPrompt (below) keeps the ONE main
# voice for everything, but gives it a correct IPA pronunciation hint for
# known technical words (git, config, hook, etc.) via
# PromptBuilder.AppendTextWithPronunciation - no voice change, no extra
# delay worth mentioning. Confirmed via VoiceChange that the voice never
# switches with this approach. Only covers a curated word list, not
# arbitrary code identifiers - unlisted words still read with the main
# voice's normal pronunciation, same as before this existed.
function Get-CleanedText {
    param([string]$Text)

    $emDash = [char]0x2014
    $enDash = [char]0x2013
    $ellipsis = [char]0x2026

    # ConvertTo-SpokenDotfiles must run first: ".env"/".mcp.json" have
    # nothing before their leading dot for ConvertTo-SpokenFileNames's regex
    # to match, so that one would leave them stray or partially converted if
    # it saw them first (confirmed live - see its own comment).
    # ConvertTo-SpokenFileNames then handles "C:\...\common.ps1" or
    # "scripts/common.ps1" -> "common punto ps1" (drops the path, fixes the
    # dot). ConvertTo-SpokenPaths catches what that one can't: a bare folder
    # mention with no recognized extension at the end.
    $Text = ConvertTo-SpokenDotfiles -Text $Text
    $Text = ConvertTo-SpokenFileNames -Text $Text
    $Text = ConvertTo-SpokenPaths -Text $Text
    $Text = ConvertTo-SpokenAbbreviations -Text $Text

    $Text = $Text -replace '(?s)```.*?```', ' code block omitted. '
    $Text = $Text -replace '(?s)<!--.*?-->', ''                    # stray HTML comments, if any
    $Text = $Text -replace '\[([^\]]+)\]\([^\)]+\)', '$1'          # [text](link) -> text
    $Text = ConvertTo-SpokenUrls -Text $Text                        # any URL left bare (not in markdown link syntax)
    $Text = $Text -replace '(?m)^\s{0,3}[-*+]\s+', ''               # list bullets
    $Text = $Text -replace '(?m)^\s{0,3}\d+\.\s+', ''                # numbered lists
    $Text = $Text -replace '(?m)^\s{0,3}#{1,6}\s*', ''               # headings
    $Text = $Text -replace '(?m)^\s{0,3}>\s?', ''                    # quotes
    $Text = $Text -replace '(?m)^\s*[-*_]{3,}\s*$', ' '              # horizontal rules
    $Text = Add-ImplicitLineEndPeriods -Text $Text                   # a line break with no punctuation reads as a run-on otherwise
    # Consumes any whitespace around the dash too, not just the dash itself
    # - a plain .Replace(dash, ', ') left the surrounding spaces in place,
    # so "texto — más" (space-dash-space) became "texto ,  más" (space,
    # comma, two spaces) instead of a clean "texto, más" (confirmed live -
    # didn't affect how it sounded, but was needlessly messy in the text
    # actually being spoken).
    $Text = $Text -replace "\s*$emDash\s*", ', '
    $Text = $Text -replace "\s*$enDash\s*", ', '
    $Text = $Text.Replace([string]$ellipsis, '...')
    $Text = $Text -replace '[*_#`]', ''
    return $Text.Trim()
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
    #
    # Caveat this introduced (flagged in review): $Dictionary keys must be
    # single words. The old alternation regex could in principle match a
    # multi-word key ("pull request") as a phrase; tokenizing by '\w+'
    # splits on the space first, so a multi-word key would silently never
    # match. Not a bug today - every entry in $script:TechPronunciations is
    # one word - but a real constraint for whoever adds the next one.
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

# --- OneCore (Windows.Media.SpeechSynthesis) support ---
#
# A modern OneCore voice sounded clearly more natural than the legacy SAPI5
# Desktop voices this plugin always used before - confirmed live, side by
# side, same sentence, same listener. Preferred by default whenever one is
# installed for the target language; SAPI5 remains the fallback (always
# present on any Windows install - OneCore's own natural voices need
# Windows 11 22H2+ and a one-time download from Settings -> Narrator, never
# assume one exists). See CLAUDE.md's design notes for the two real
# problems found before this was trusted: SSML `<prosody rate="N%">` had no
# audible effect on this voice at all (fixed below by using
# `SpeechSynthesizer.Options.SpeakingRate` instead - a distinct native
# property, confirmed live to actually change speed, unlike the SSML
# attribute), and question intonation - already a known limitation on
# SAPI5 too, confirmed to be exactly as flat on OneCore, not something this
# integration could fix either way (see that design note).

$script:OneCoreTypeLoaded = $false
$script:OneCoreLoadFailed = $false
$script:OneCoreAsTaskGeneric = $null

# Lazily loads the WinRT projection needed to call Windows.Media.SpeechSynthesis
# from Windows PowerShell 5.1 (not natively .NET-Framework-visible without
# this). Wrapped in try/catch and cached in a script-level flag: this must
# never be able to break anything for a user on an older Windows version or
# missing component - a failure here just means Resolve-SpeechTarget below
# falls back to SAPI5, exactly as if no OneCore voice were installed.
function Initialize-OneCoreTypes {
    if ($script:OneCoreTypeLoaded) { return $true }
    # A failed load is cached too, not just a successful one - without this,
    # a machine with no OneCore support (Windows 10, or Windows 11 with no
    # modern voice downloaded) re-ran Add-Type plus a reflection method
    # lookup on every single Invoke-SpeechSynthesis call, forever, for the
    # life of the process - a real per-call cost this project doesn't
    # otherwise have, caught in review before shipping.
    if ($script:OneCoreLoadFailed) { return $false }
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        $script:OneCoreAsTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]
        [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime] | Out-Null
        $script:OneCoreTypeLoaded = $true
        return $true
    } catch {
        $script:OneCoreLoadFailed = $true
        return $false
    }
}

# Blocks synchronously on a WinRT IAsyncOperation<T> - PowerShell has no
# native `await`, this is the standard reflection-based bridge (AsTask then
# .Wait()) for calling WinRT async APIs from Windows PowerShell 5.1.
function Wait-OneCoreAsync {
    param($AsyncOp, $ResultType, [int]$TimeoutMs = 30000)
    $task = $script:OneCoreAsTaskGeneric.MakeGenericMethod($ResultType).Invoke($null, @($AsyncOp))
    try {
        # Bounded, unlike an earlier version of this function that waited
        # forever (Wait(-1)) - found in review: this call runs INSIDE the
        # cross-process speech mutex (see Invoke-SpeechSynthesis), so an
        # unbounded wait here meant a single hung WinRT call could freeze
        # speech for every other session on the machine indefinitely, not
        # just this one. 30s comfortably covers any real synthesis while
        # staying well under the mutex's own 60s timeout budget.
        if (-not $task.Wait($TimeoutMs)) {
            throw "OneCore synthesis timed out after ${TimeoutMs}ms without completing"
        }
    } catch [System.AggregateException] {
        # Task.Wait() wraps a faulted task's real error in an
        # AggregateException with a generic "One or more errors occurred"
        # message - unwrapping it here means the debug log (built
        # specifically for troubleshooting this) records the actual WinRT
        # failure instead of that useless generic text (found in review).
        $inner = $_.Exception.InnerException
        if ($inner) { throw $inner }
        throw
    }
    return $task.Result
}

function Get-OneCoreVoices {
    if (-not (Initialize-OneCoreTypes)) { return @() }
    try {
        return @([Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices)
    } catch {
        return @()
    }
}

# Decides which synthesis engine and voice to use, without speaking
# anything yet. An explicit /sapi-voice-kit:voice override is checked
# against BOTH engines by name before falling back to auto-detection -
# OneCore's DisplayName strings ("Microsoft Pablo") and SAPI5's Name
# strings ("Microsoft Pablo Desktop") never collide, so a voiceName saved
# before OneCore support existed still resolves to the same SAPI5 voice it
# always did.
function Resolve-SpeechTarget {
    param($Config)

    # Fetched once and reused by both the voiceName-override check below and
    # the auto-detect fallback further down - a stale/uninstalled voiceName
    # (e.g. saved before OneCore support existed, or the voice got removed)
    # used to re-enumerate this twice in the same call (found in review).
    $oneCoreVoices = Get-OneCoreVoices

    if ($Config -and $Config.voiceName) {
        $oneCoreMatch = $oneCoreVoices | Where-Object { $_.DisplayName -eq $Config.voiceName } | Select-Object -First 1
        if ($oneCoreMatch) { return @{ Engine = 'OneCore'; Voice = $oneCoreMatch } }

        Add-Type -AssemblyName System.Speech
        $sapiSynth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $sapiMatch = $sapiSynth.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Name -eq $Config.voiceName } | Select-Object -First 1
        if ($sapiMatch) { return @{ Engine = 'Sapi5'; VoiceName = $sapiMatch.VoiceInfo.Name } }
        # Named voice isn't installed under either engine anymore - fall
        # through to auto-detection below rather than erroring out.
    }

    $language = if ($Config -and $Config.language) { $Config.language } else { (Get-Culture).Name }
    $prefix = $language.Split('-')[0]

    $oneCoreMatch = $oneCoreVoices | Where-Object { $_.Language -eq $language } | Select-Object -First 1
    if (-not $oneCoreMatch) {
        $oneCoreMatch = $oneCoreVoices | Where-Object { $_.Language.Split('-')[0] -eq $prefix } | Select-Object -First 1
    }
    if ($oneCoreMatch) { return @{ Engine = 'OneCore'; Voice = $oneCoreMatch } }

    Add-Type -AssemblyName System.Speech
    $sapiSynth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    return @{ Engine = 'Sapi5'; VoiceName = (Resolve-Voice -Synth $sapiSynth -Config $Config) }
}

# Builds the SSML OneCore needs: XML-escapes $Text, and (unless
# $UsePronunciation is false, same as the SAPI5 path) wraps any dictionary
# word in <phoneme alphabet='ipa'> using the exact same IPA strings SAPI5's
# PromptBuilder already uses - confirmed live that OneCore honors the same
# alphabet correctly. Tokenizes once and does an O(1) lookup per token, same
# approach as Get-PronunciationPrompt above and for the same reason (a
# 100-entry sequential regex pass per call is real, avoidable work) - see
# that function's own comment for the measured cost this avoids. No
# <prosody> wrapper here - rate is set via Options.SpeakingRate instead (see
# Invoke-OneCoreSpeech), since SSML's own rate attribute had no audible
# effect on this voice at all (confirmed live) while the native property
# does.
function ConvertTo-OneCoreSsml {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Language,
        [bool]$UsePronunciation = $true
    )
    $body = New-Object System.Text.StringBuilder
    if ($UsePronunciation) {
        $tokenMatches = [regex]::Matches($Text, '\w+')
        $lastEnd = 0
        foreach ($m in $tokenMatches) {
            if ($m.Index -gt $lastEnd) {
                [void]$body.Append([System.Security.SecurityElement]::Escape($Text.Substring($lastEnd, $m.Index - $lastEnd)))
            }
            $key = $m.Value.ToLowerInvariant()
            if ($script:TechPronunciations.ContainsKey($key)) {
                # The IPA value is escaped too, not just the visible word -
                # every current dictionary entry happens to avoid ' and &,
                # but nothing enforced that, so an unescaped attribute value
                # was one careless future entry away from breaking every
                # SSML call that used it (found in review).
                [void]$body.Append("<phoneme alphabet='ipa' ph='$([System.Security.SecurityElement]::Escape($script:TechPronunciations[$key]))'>")
                [void]$body.Append([System.Security.SecurityElement]::Escape($m.Value))
                [void]$body.Append('</phoneme>')
            } else {
                [void]$body.Append([System.Security.SecurityElement]::Escape($m.Value))
            }
            $lastEnd = $m.Index + $m.Length
        }
        if ($lastEnd -lt $Text.Length) {
            [void]$body.Append([System.Security.SecurityElement]::Escape($Text.Substring($lastEnd)))
        }
    } else {
        [void]$body.Append([System.Security.SecurityElement]::Escape($Text))
    }
    $open = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='$Language'>"
    return "$open$($body.ToString())</speak>"
}

# Speaks via OneCore. $Rate uses SAPI5's -10..10 scale (so config.json's
# `rate` field means the same thing regardless of which engine ends up
# speaking) - converted to Options.SpeakingRate's multiplier (1.0 =
# normal) with the same roughly-doubles-per-10-units curve SAPI5's own
# Rate property documents, e.g. -10 -> 0.5x, 0 -> 1.0x, +10 -> 2.0x.
function Invoke-OneCoreSpeech {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)]$Voice,
        $Config,
        [bool]$UsePronunciation = $true,
        [scriptblock]$Log = { param([string]$Message) }
    )
    $synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
    $synth.Voice = $Voice
    $rate = ConvertTo-SafeRate -Value $Config.rate
    $synth.Options.SpeakingRate = [math]::Pow(2, $rate / 10)
    $ssml = ConvertTo-OneCoreSsml -Text $Text -Language $Voice.Language -UsePronunciation $UsePronunciation
    & $Log "calling SynthesizeSsmlToStreamAsync (OneCore [$($Voice.DisplayName)], rate=$rate, SpeakingRate=$($synth.Options.SpeakingRate))"
    $stream = Wait-OneCoreAsync -AsyncOp $synth.SynthesizeSsmlToStreamAsync($ssml) -ResultType ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
    # try/finally now wraps stream/player creation too, not just PlaySync() -
    # found in review: if AsStreamForRead or the SoundPlayer constructor
    # itself ever threw (e.g. an unexpected stream format), $stream and
    # $netStream leaked with no cleanup at all. $stream (the WinRT object
    # itself, not just its .NET stream wrapper) is now disposed too - it
    # wasn't before.
    $netStream = $null
    $player = $null
    try {
        $netStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
        $player = New-Object System.Media.SoundPlayer($netStream)
        $player.PlaySync()
    } finally {
        if ($player) { $player.Dispose() }
        if ($netStream) { $netStream.Dispose() }
        $stream.Dispose()
    }
    & $Log "OneCore playback finished OK"
}

# Speaks $Text with a specific already-resolved SAPI5 voice name. Unchanged
# behavior from before OneCore support existed - only extracted out of
# Invoke-SpeechSynthesis so that function could become a thin dispatcher
# (see Resolve-SpeechTarget above) instead of assuming SAPI5 unconditionally.
function Invoke-Sapi5Speech {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$VoiceName,
        $Config,
        [bool]$UsePronunciation = $true,
        [scriptblock]$Log = { param([string]$Message) }
    )
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    & $Log "SpeechSynthesizer created"

    if ($VoiceName) { $synth.SelectVoice($VoiceName) }
    & $Log "chosen voice: [$VoiceName]"

    $synth.Rate = ConvertTo-SafeRate -Value $Config.rate
    & $Log "rate: $($synth.Rate)"

    $prompt = if ($UsePronunciation) { Get-PronunciationPrompt -Text $Text -Dictionary $script:TechPronunciations -Culture $synth.Voice.Culture } else { $null }
    if ($prompt) {
        & $Log "calling Speak() with pronunciation hints (same voice throughout)"
        $synth.Speak($prompt)
    } else {
        & $Log "calling Speak() (no known technical terms to hint)"
        $synth.Speak($Text)
    }
    & $Log "Speak() finished OK"
}

# Speaks $Text using the configured voice, rate, and (optionally) the
# pronunciation dictionary. Shared by speak.ps1 (Stop hook - natural/
# literal/summary modes) and say.ps1 (active mode - model-invoked via
# stdin), so both paths pick voice/rate/pronunciation the same way. Picks
# the engine via Resolve-SpeechTarget, then falls back to SAPI5 for this
# one utterance if OneCore throws for any reason (never let an engine-level
# failure leave the user in total silence when a working fallback exists -
# same principle already applied to summary mode falling back to natural
# text, and read-last/active falling back gracefully on missing plugin data).
function Invoke-SpeechSynthesis {
    param(
        [Parameter(Mandatory)][string]$Text,
        $Config,
        [bool]$UsePronunciation = $true,
        [scriptblock]$Log = { param([string]$Message) }
    )

    $target = Resolve-SpeechTarget -Config $Config
    & $Log "engine: [$($target.Engine)]"

    # Cross-process mutex: each plugin process (this session's Stop hook,
    # another parallel session's Stop hook, active mode's say.ps1, ...) gets
    # its own synthesizer with no knowledge of any other process. Two
    # sessions speaking at once produced genuinely overlapping, unintelligible
    # audio on the shared output device (observed live: two parallel Claude
    # Code sessions with this plugin active). A named Mutex serializes actual
    # speech across every process on the machine that uses this function,
    # regardless of which engine each one picked - whoever gets here first
    # speaks, the rest wait their turn instead of talking over each other.
    # WaitOne has a timeout so a process that died while holding the mutex
    # (or one that's just taking unusually long) can't permanently silence
    # everyone else - after 60s, speak anyway rather than staying silent
    # forever. AbandonedMutexException is caught and treated as "got it"
    # (that's .NET's normal way of reporting a previous holder exited
    # without releasing - the mutex is still valid). Local\ (session-scoped),
    # not Global\: the actual problem this solves - two Claude Code sessions
    # on the same desktop, same Windows login - never crosses a session
    # boundary, and Global\ requires a privilege (SeCreateGlobalPrivilege) a
    # restricted or Remote-Desktop-session user may not have. Local\ needs
    # no special privilege and is sufficient for the real scenario, so
    # there's no reason to ask for the broader one.
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

        if ($target.Engine -eq 'OneCore') {
            try {
                Invoke-OneCoreSpeech -Text $Text -Voice $target.Voice -Config $Config -UsePronunciation $UsePronunciation -Log $Log
            } catch {
                & $Log "OneCore speech failed ($($_.Exception.Message)) - falling back to SAPI5 for this utterance"
                Add-Type -AssemblyName System.Speech
                $fallbackVoice = Resolve-Voice -Synth (New-Object System.Speech.Synthesis.SpeechSynthesizer) -Config $Config
                Invoke-Sapi5Speech -Text $Text -VoiceName $fallbackVoice -Config $Config -UsePronunciation $UsePronunciation -Log $Log
            }
        } else {
            try {
                Invoke-Sapi5Speech -Text $Text -VoiceName $target.VoiceName -Config $Config -UsePronunciation $UsePronunciation -Log $Log
            } catch {
                # The resolved voice name can go stale between Resolve-
                # SpeechTarget (before the mutex) and here (after it - up to
                # 60s later if another process was speaking) if it gets
                # uninstalled or config changes in that window (found in
                # review). Retry once with no voice override - SelectVoice()
                # is simply skipped in that case (see Invoke-Sapi5Speech),
                # so this uses whatever default voice is still installed
                # rather than leaving the user in total silence.
                & $Log "SAPI5 speech with voice [$($target.VoiceName)] failed ($($_.Exception.Message)) - retrying with the default voice"
                Invoke-Sapi5Speech -Text $Text -VoiceName $null -Config $Config -UsePronunciation $UsePronunciation -Log $Log
            }
        }
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

    $prompt = "Summarize the following text in 2-4 natural spoken sentences that capture the key points, in the same language as the text. This summary will ONLY ever be spoken aloud by a text-to-speech engine, never shown on screen - write it accordingly. $($script:SpokenTextGuidance) Avoid markdown, raw symbols, and abbreviations that wouldn't make sense read aloud. Output ONLY the summary itself - no preamble, no options, no alternate phrasings, no quotation marks around it, nothing else.`n`n---`n`n$Text"

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
