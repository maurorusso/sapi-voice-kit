# End-to-end tests of the entry-point scripts (the ones hooks, skills and the MCP
# server run), each in its own PowerShell process like in real use.
#
# They run against a copy of scripts/ whose lib/speech.ps1 is replaced by a
# recorder, so what would have been spoken is written to a file instead of
# played. The audio engines are the one part that needs ears: see
# /sapi-voice-kit:test. The home directory is a throwaway one, so the tests
# never touch the real config.
#
#   powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests/scripts.Tests.ps1"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
. "$repoRoot\scripts\common.ps1"

# Instead of speaking, appends { text, pronunciation, rate } as one JSON line to
# $env:SAPI_TEST_SPOKEN; throws when $env:SAPI_TEST_FAIL is 1.
$recorderSource = @'
function Invoke-SpeechSynthesis {
    param([string]$Text, $Config, [bool]$UsePronunciation = $true, [scriptblock]$Log)
    if ($env:SAPI_TEST_FAIL -eq '1') { throw 'engine exploded' }
    $line = @{ text = $Text; pronunciation = $UsePronunciation; rate = $Config.rate } | ConvertTo-Json -Compress
    [System.IO.File]::AppendAllText($env:SAPI_TEST_SPOKEN, "$line`n", (New-Object System.Text.UTF8Encoding($false)))
}
'@

$script:work = Join-Path ([System.IO.Path]::GetTempPath()) ('sapi-voice-kit-scripts-' + [Guid]::NewGuid().ToString('N'))
$script:sandbox = Join-Path $script:work 'plugin'
$script:fakeBin = Join-Path $script:work 'bin'
$script:spokenFile = Join-Path $script:work 'spoken.jsonl'

New-Item -ItemType Directory -Path $script:fakeBin -Force | Out-Null
Copy-Item -Path "$repoRoot\scripts" -Destination $script:sandbox -Recurse
[System.IO.File]::WriteAllText("$script:sandbox\lib\speech.ps1", $recorderSource, (New-Object System.Text.UTF8Encoding($true)))

# Replaces the real `claude` for summary mode: prints a fixed line, or fails.
function Set-FakeClaude {
    param([switch]$Fail)
    $body = if ($Fail) { "@exit /b 1" } else { "@echo SUMMARY OF THE RESPONSE" }
    [System.IO.File]::WriteAllText("$script:fakeBin\claude.cmd", $body, [System.Text.Encoding]::ASCII)
}

function Use-FakeHome {
    $script:savedEnv = @{}
    foreach ($name in 'USERPROFILE', 'SAPI_VOICE_NAMESPACE', 'SAPI_TEST_SPOKEN', 'SAPI_TEST_FAIL', 'PATH') {
        $script:savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    $script:fakeHome = Join-Path $script:work ('home-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:fakeHome -Force | Out-Null
    $env:USERPROFILE = $script:fakeHome
    $env:SAPI_TEST_SPOKEN = $script:spokenFile
    $env:PATH = "$script:fakeBin;$($script:savedEnv['PATH'])"
    Remove-Item Env:\SAPI_VOICE_NAMESPACE, Env:\SAPI_TEST_FAIL -ErrorAction SilentlyContinue
    Remove-Item $script:spokenFile -ErrorAction SilentlyContinue
    Remove-Item "$script:fakeBin\claude.cmd" -ErrorAction SilentlyContinue
}

function Remove-FakeHome {
    foreach ($name in $script:savedEnv.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:savedEnv[$name])
    }
    Remove-Item -Path $script:fakeHome -Recurse -Force -ErrorAction SilentlyContinue
}

# Runs scripts/<Name> in a new process; returns its output (stdout then stderr,
# trimmed) and exit code. Stdin, when given, is sent as UTF-8 bytes.
#
# A real process with redirected streams, not `& powershell 2>&1`: under
# $ErrorActionPreference = 'Stop' (what GitHub Actions' PowerShell shell sets) a
# line on the child's stderr becomes a terminating error in the caller and
# kills the child half-way.
function Invoke-Entry {
    param([string]$Name, [string[]]$Arguments = @(), [string]$Stdin)

    $quoted = @($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' })
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell'
    $info.Arguments = (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script:sandbox\$Name`"") + $quoted) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)

    $process = [System.Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if ($PSBoundParameters.ContainsKey('Stdin')) {
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Stdin)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    }
    # Closing the underlying stream, not the writer around it: on a machine whose
    # console is UTF-8 the writer would put a byte-order mark in front of the input.
    $process.StandardInput.BaseStream.Close()
    $process.WaitForExit()
    return [pscustomobject]@{ Output = ($stdout.Result + $stderr.Result).Trim(); ExitCode = $process.ExitCode }
}

function Get-Spoken {
    if (-not (Test-Path $script:spokenFile)) { return @() }
    return @(Get-Content $script:spokenFile -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Get-SavedConfig { return Get-VoiceConfig -Namespace 'local' }

function New-HookEvent {
    param([string]$Message)
    return (@{ last_assistant_message = $Message } | ConvertTo-Json -Compress)
}

Describe 'say.ps1' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'speaks the text piped in, with pronunciation hints on' {
        $result = Invoke-Entry 'say.ps1' -Stdin 'Hola mundo'
        $result.Output | Should Be 'Spoken.'
        $spoken = @(Get-Spoken)
        $spoken.Count | Should Be 1
        $spoken[0].text | Should Be 'Hola mundo'
        $spoken[0].pronunciation | Should Be $true
    }
    It 'passes accented text through intact' {
        Invoke-Entry 'say.ps1' -Stdin '¿Confirmás, García? ñandú' | Out-Null
        (Get-Spoken)[0].text | Should Be '¿Confirmás, García? ñandú'
    }
    It 'passes the configured rate to the engine' {
        Save-VoiceConfig -Changes @{ rate = 4 } | Out-Null
        Invoke-Entry 'say.ps1' -Stdin 'hola' | Out-Null
        (Get-Spoken)[0].rate | Should Be 4
    }
    It 'says file names and links the way they are heard' {
        Invoke-Entry 'say.ps1' -Stdin 'Mirá scripts/common.ps1 y https://github.com/x/y ahora' | Out-Null
        $text = (Get-Spoken)[0].text
        $text | Should Match 'common punto ps1'
        $text | Should Match 'el link'
        $text | Should Not Match 'https'
    }
    It 'stays silent and says why when muted' {
        Save-VoiceConfig -Changes @{ muted = $true } | Out-Null
        $result = Invoke-Entry 'say.ps1' -Stdin 'hola'
        $result.Output | Should Match 'Not spoken: .*muted'
        Get-Spoken | Should BeNullOrEmpty
    }
    It 'speaks while muted when forced' {
        Save-VoiceConfig -Changes @{ muted = $true } | Out-Null
        Invoke-Entry 'say.ps1' -Arguments '-Force' -Stdin 'hola' | Out-Null
        @(Get-Spoken).Count | Should Be 1
    }
    It 'does nothing unless the configured mode is the required one' {
        Save-VoiceConfig -Changes @{ mode = 'natural' } | Out-Null
        $result = Invoke-Entry 'say.ps1' -Arguments '-RequireMode', 'active' -Stdin 'hola'
        $result.Output | Should Match "not in 'active' mode"
        Get-Spoken | Should BeNullOrEmpty
    }
    It 'speaks when the configured mode is the required one' {
        Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
        Invoke-Entry 'say.ps1' -Arguments '-RequireMode', 'active' -Stdin 'hola' | Out-Null
        @(Get-Spoken).Count | Should Be 1
    }
    It 'ignores the required mode when forced' {
        Invoke-Entry 'say.ps1' -Arguments '-Force', '-RequireMode', 'active' -Stdin 'hola' | Out-Null
        @(Get-Spoken).Count | Should Be 1
    }
    It 'says so when the text is empty' {
        $result = Invoke-Entry 'say.ps1' -Stdin '   '
        $result.Output | Should Match 'empty'
        Get-Spoken | Should BeNullOrEmpty
    }
    It 'ignores a byte-order mark in front of the input' {
        $bom = [string][char]0xFEFF
        (Invoke-Entry 'say.ps1' -Stdin ($bom + '   ')).Output | Should Match 'empty'
        Invoke-Entry 'say.ps1' -Stdin ($bom + 'hola') | Out-Null
        (Get-Spoken)[0].text | Should Be 'hola'
    }
    It 'skips a second utterance right after the first (CLI hook plus Cowork tool in one turn)' {
        Invoke-Entry 'say.ps1' -Stdin 'primera' | Out-Null
        $second = Invoke-Entry 'say.ps1' -Stdin 'segunda'
        $second.Output | Should Match 'already spoken'
        @(Get-Spoken).Count | Should Be 1
    }
    It 'repeats on request even right after speaking, and does not arm the guard' {
        Invoke-Entry 'say.ps1' -Arguments '-Force' -Stdin 'uno' | Out-Null
        Invoke-Entry 'say.ps1' -Arguments '-Force' -Stdin 'otra vez' | Out-Null
        Invoke-Entry 'say.ps1' -Stdin 'sin forzar' | Out-Null
        @(Get-Spoken).Count | Should Be 3
    }
    It 'reports an engine failure instead of crashing' {
        $env:SAPI_TEST_FAIL = '1'
        $result = Invoke-Entry 'say.ps1' -Stdin 'hola'
        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'Not spoken: an error'
    }
    It 'writes no log and no copy of the text by default' {
        Invoke-Entry 'say.ps1' -Stdin 'texto privado' | Out-Null
        Get-ChildItem (Get-SharedDataDir) -Name | Should Be '.last-active-speech'
    }
    It 'keeps a copy of the last spoken text when debug is on' {
        Save-VoiceConfig -Changes @{ debug = $true } | Out-Null
        Invoke-Entry 'say.ps1' -Stdin 'texto de prueba' | Out-Null
        (Get-Content (Get-DataFilePath 'last-text.txt') -Encoding UTF8) | Should Be 'texto de prueba'
    }
    It 'logs why it stayed silent when debug is on' {
        Save-VoiceConfig -Changes @{ debug = $true; muted = $true } | Out-Null
        Invoke-Entry 'say.ps1' -Stdin 'hola' | Out-Null
        (Get-Content (Get-DataFilePath 'log-say.txt') -Encoding UTF8) | Should Match 'muted'
    }
    It 'rejects a required mode that does not exist' {
        (Invoke-Entry 'say.ps1' -Arguments '-RequireMode', 'loud' -Stdin 'hola').ExitCode | Should Not Be 0
    }
}

Describe 'speak.ps1 (Stop hook)' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'reads the response with markdown removed in natural mode (the default)' {
        Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent "# Título`n`nUsá **negrita** y [un link](https://x.com).") | Out-Null
        $spoken = @(Get-Spoken)
        $spoken.Count | Should Be 1
        $spoken[0].text | Should Match 'negrita'
        $spoken[0].text | Should Not Match '\*\*'
        $spoken[0].text | Should Not Match '#'
        $spoken[0].pronunciation | Should Be $true
    }
    It 'reads a hook event that starts with a byte-order mark' {
        Invoke-Entry 'speak.ps1' -Stdin (([string][char]0xFEFF) + (New-HookEvent 'hola')) | Out-Null
        (Get-Spoken)[0].text | Should Match 'hola'
    }
    It 'reads the response untouched, without pronunciation hints, in literal mode' {
        Save-VoiceConfig -Changes @{ mode = 'literal' } | Out-Null
        Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent "  **tal cual**  ") | Out-Null
        $spoken = @(Get-Spoken)
        $spoken[0].text | Should Be '**tal cual**'
        $spoken[0].pronunciation | Should Be $false
    }
    It 'reads the summary claude returns in summary mode' {
        Save-VoiceConfig -Changes @{ mode = 'summary' } | Out-Null
        Set-FakeClaude
        Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent 'Una respuesta larga.') | Out-Null
        (Get-Spoken)[0].text | Should Be 'SUMMARY OF THE RESPONSE'
    }
    It 'falls back to the whole cleaned text when the summary call fails' {
        Save-VoiceConfig -Changes @{ mode = 'summary' } | Out-Null
        Set-FakeClaude -Fail
        Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent 'Una respuesta larga.') | Out-Null
        (Get-Spoken)[0].text | Should Match 'Una respuesta larga'
    }
    It 'stays silent in active mode: the model speaks for itself' {
        Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
        Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent 'hola') | Out-Null
        Get-Spoken | Should BeNullOrEmpty
    }
    It 'stays silent when muted' {
        Save-VoiceConfig -Changes @{ muted = $true } | Out-Null
        Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent 'hola') | Out-Null
        Get-Spoken | Should BeNullOrEmpty
    }
    It 'stays silent when the event has no response text' {
        Invoke-Entry 'speak.ps1' -Stdin '{"other":"field"}' | Out-Null
        Get-Spoken | Should BeNullOrEmpty
    }
    It 'stays silent when cleanup leaves nothing to say' {
        Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent '---') | Out-Null
        Get-Spoken | Should BeNullOrEmpty
    }
    It 'survives input that is not JSON and exits cleanly' {
        $result = Invoke-Entry 'speak.ps1' -Stdin 'this is not json'
        $result.ExitCode | Should Be 0
        Get-Spoken | Should BeNullOrEmpty
    }
    It 'survives an engine failure and exits cleanly' {
        $env:SAPI_TEST_FAIL = '1'
        (Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent 'hola')).ExitCode | Should Be 0
    }
    It 'keeps accents intact' {
        Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent '¿Confirmás, García?') | Out-Null
        (Get-Spoken)[0].text | Should Match 'Confirmás, García'
    }
    It 'reads the cowork section only when asked to' {
        Save-VoiceConfig -Namespace 'cowork' -Changes @{ muted = $true } | Out-Null
        Invoke-Entry 'speak.ps1' -Stdin (New-HookEvent 'hola') | Out-Null
        @(Get-Spoken).Count | Should Be 1
    }
}

Describe 'set-mode.ps1, set-mute.ps1 and set-debug.ps1' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'saves the reading mode' {
        (Invoke-Entry 'set-mode.ps1' -Arguments '-Mode', 'literal').Output | Should Be 'Reading mode: literal'
        (Get-SavedConfig).mode | Should Be 'literal'
    }
    It 'rejects a mode that does not exist and saves nothing' {
        (Invoke-Entry 'set-mode.ps1' -Arguments '-Mode', 'loud').ExitCode | Should Not Be 0
        (Get-SavedConfig).mode | Should BeNullOrEmpty
    }
    It 'mutes and unmutes without touching the mode' {
        Invoke-Entry 'set-mode.ps1' -Arguments '-Mode', 'active' | Out-Null
        Invoke-Entry 'set-mute.ps1' -Arguments '-State', 'on' | Out-Null
        (Get-SavedConfig).muted | Should Be $true
        (Get-SavedConfig).mode | Should Be 'active'
        Invoke-Entry 'set-mute.ps1' -Arguments '-State', 'off' | Out-Null
        (Get-SavedConfig).muted | Should Be $false
    }
    It 'turns debug logging on and off' {
        Invoke-Entry 'set-debug.ps1' -Arguments '-State', 'on' | Out-Null
        (Get-SavedConfig).debug | Should Be $true
        Invoke-Entry 'set-debug.ps1' -Arguments '-State', 'off' | Out-Null
        (Get-SavedConfig).debug | Should Be $false
    }
    It 'rejects a state other than on or off' {
        (Invoke-Entry 'set-mute.ps1' -Arguments '-State', 'maybe').ExitCode | Should Not Be 0
        (Invoke-Entry 'set-debug.ps1' -Arguments '-State', 'maybe').ExitCode | Should Not Be 0
    }
    It 'writes to the section named by SAPI_VOICE_NAMESPACE and leaves the other alone' {
        $env:SAPI_VOICE_NAMESPACE = 'cowork'
        Invoke-Entry 'set-mode.ps1' -Arguments '-Mode', 'summary' | Out-Null
        Remove-Item Env:\SAPI_VOICE_NAMESPACE
        (Get-VoiceConfig -Namespace 'cowork').mode | Should Be 'summary'
        (Get-VoiceConfig -Namespace 'local').mode | Should BeNullOrEmpty
    }
    It 'fails on an unknown namespace instead of writing somewhere else' {
        $env:SAPI_VOICE_NAMESPACE = 'elsewhere'
        (Invoke-Entry 'set-mode.ps1' -Arguments '-Mode', 'literal').ExitCode | Should Not Be 0
        Get-DataFilePath 'config.json' | Should Not Exist
    }
}

Describe 'set-voice.ps1' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'saves a voice by name' {
        Invoke-Entry 'set-voice.ps1' -Arguments '-Voice', 'Microsoft Laura' | Out-Null
        (Get-SavedConfig).voiceName | Should Be 'Microsoft Laura'
    }
    It 'saves a language' {
        Invoke-Entry 'set-voice.ps1' -Arguments '-Language', 'es-MX' | Out-Null
        (Get-SavedConfig).language | Should Be 'es-MX'
    }
    It 'saves a rate, including zero and negative ones' {
        Invoke-Entry 'set-voice.ps1' -Arguments '-Rate', '3' | Out-Null
        (Get-SavedConfig).rate | Should Be 3
        Invoke-Entry 'set-voice.ps1' -Arguments '-Rate', '0' | Out-Null
        (Get-SavedConfig).rate | Should Be 0
        Invoke-Entry 'set-voice.ps1' -Arguments '-Rate', '-4' | Out-Null
        (Get-SavedConfig).rate | Should Be -4
    }
    It 'rejects a rate outside -10..10' {
        (Invoke-Entry 'set-voice.ps1' -Arguments '-Rate', '11').ExitCode | Should Not Be 0
        (Get-SavedConfig).rate | Should BeNullOrEmpty
    }
    It 'choosing a voice clears the language and vice versa' {
        Invoke-Entry 'set-voice.ps1' -Arguments '-Language', 'es-MX' | Out-Null
        Invoke-Entry 'set-voice.ps1' -Arguments '-Voice', 'Microsoft Laura' | Out-Null
        $config = Get-SavedConfig
        $config.voiceName | Should Be 'Microsoft Laura'
        $config.ContainsKey('language') | Should Be $false
        Invoke-Entry 'set-voice.ps1' -Arguments '-Language', 'en-US' | Out-Null
        $config = Get-SavedConfig
        $config.language | Should Be 'en-US'
        $config.ContainsKey('voiceName') | Should Be $false
    }
    It 'changing the rate keeps the chosen voice' {
        Invoke-Entry 'set-voice.ps1' -Arguments '-Voice', 'Microsoft Laura' | Out-Null
        Invoke-Entry 'set-voice.ps1' -Arguments '-Rate', '2' | Out-Null
        (Get-SavedConfig).voiceName | Should Be 'Microsoft Laura'
    }
    It '-Auto clears the voice and the language but keeps the rate' {
        Invoke-Entry 'set-voice.ps1' -Arguments '-Voice', 'Microsoft Laura' | Out-Null
        Invoke-Entry 'set-voice.ps1' -Arguments '-Rate', '2' | Out-Null
        Invoke-Entry 'set-voice.ps1' -Arguments '-Auto' | Out-Null
        $config = Get-SavedConfig
        $config.ContainsKey('voiceName') | Should Be $false
        $config.rate | Should Be 2
    }
    It 'refuses a voice and a language together' {
        $result = Invoke-Entry 'set-voice.ps1' -Arguments '-Voice', 'Microsoft Laura', '-Language', 'es-MX'
        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'not both'
    }
    It 'asks for something to change when called with nothing' {
        $result = Invoke-Entry 'set-voice.ps1'
        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'Nothing to change'
    }
}

Describe 'list-voices.ps1' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'lists the voices and says which one is in use for the local section' {
        $result = Invoke-Entry 'list-voices.ps1'
        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'Se está usando ahora \(local\)'
    }
    It 'says which one is in use for the cowork section' {
        $env:SAPI_VOICE_NAMESPACE = 'cowork'
        (Invoke-Entry 'list-voices.ps1').Output | Should Match 'Se está usando ahora \(cowork\)'
    }
    It 'falls back to automatic selection when the configured voice is not installed' {
        Save-VoiceConfig -Changes @{ voiceName = 'Microsoft Nobody' } | Out-Null
        $result = Invoke-Entry 'list-voices.ps1'
        $result.ExitCode | Should Be 0
        $result.Output | Should Not Match 'Nobody'
    }
}

Describe 'prompt-active-mode.ps1 (UserPromptSubmit hook)' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'adds the speak-it-yourself reminder in active mode' {
        Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
        $json = (Invoke-Entry 'prompt-active-mode.ps1').Output | ConvertFrom-Json
        $json.hookSpecificOutput.hookEventName | Should Be 'UserPromptSubmit'
        $context = $json.hookSpecificOutput.additionalContext
        $context | Should Match 'say\.ps1'
        $context | Should Match "<<'EOF'"
        $context | Should Match 'punto'
    }
    It 'points at the say.ps1 next to it' {
        Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
        $json = (Invoke-Entry 'prompt-active-mode.ps1').Output | ConvertFrom-Json
        $json.hookSpecificOutput.additionalContext | Should Match ([regex]::Escape("$script:sandbox\say.ps1"))
    }
    It 'adds nothing in the other modes' {
        foreach ($mode in 'natural', 'literal', 'summary') {
            Save-VoiceConfig -Changes @{ mode = $mode } | Out-Null
            (Invoke-Entry 'prompt-active-mode.ps1').Output | Should BeNullOrEmpty
        }
    }
    It 'adds nothing when muted' {
        Save-VoiceConfig -Changes @{ mode = 'active'; muted = $true } | Out-Null
        (Invoke-Entry 'prompt-active-mode.ps1').Output | Should BeNullOrEmpty
    }
    It 'adds nothing before anything is configured' {
        (Invoke-Entry 'prompt-active-mode.ps1').Output | Should BeNullOrEmpty
    }
}

Describe 'say-test.ps1' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'shows the original and the cleaned text and speaks the cleaned one' {
        $result = Invoke-Entry 'say-test.ps1'
        $result.Output | Should Match 'Texto original'
        $result.Output | Should Match 'Texto limpio'
        $result.Output | Should Match 'Listo'
        $spoken = (Get-Spoken)[0].text
        $spoken | Should Match 'punto mcp punto json'
        $spoken | Should Match 'etcétera'
        $spoken | Should Not Match 'https'
    }
    It 'reports the error when speaking fails' {
        $env:SAPI_TEST_FAIL = '1'
        (Invoke-Entry 'say-test.ps1').Output | Should Match 'Error al hablar: engine exploded'
    }
}

Describe 'Cleanup of the test sandbox' {
    It 'removes the temporary plugin copy' {
        Remove-Item -Path $script:work -Recurse -Force -ErrorAction SilentlyContinue
        Test-Path $script:work | Should Be $false
    }
}
