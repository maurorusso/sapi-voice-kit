# Tests of the speech layer: voice discovery, the order engines are tried in,
# and the parts of each engine that can be exercised without making a sound.
# Only the final "play it" calls (SpeechSynthesizer.Speak, SoundPlayer) are
# left to /sapi-voice-kit:test, by ear.
#
#   powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests/speech.Tests.ps1"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
. "$repoRoot\scripts\common.ps1"

function Use-FakeHome {
    $script:originalProfile = $env:USERPROFILE
    $script:originalNamespace = $env:SAPI_VOICE_NAMESPACE
    $script:fakeHome = Join-Path ([System.IO.Path]::GetTempPath()) ('sapi-voice-kit-test-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:fakeHome -Force | Out-Null
    $env:USERPROFILE = $script:fakeHome
    Remove-Item Env:\SAPI_VOICE_NAMESPACE -ErrorAction SilentlyContinue
}

function Remove-FakeHome {
    $env:USERPROFILE = $script:originalProfile
    if ($script:originalNamespace) { $env:SAPI_VOICE_NAMESPACE = $script:originalNamespace }
    Remove-Item -Path $script:fakeHome -Recurse -Force -ErrorAction SilentlyContinue
}

$oneCoreVoice = [pscustomobject]@{ Engine = 'OneCore'; Name = 'Voz Moderna'; Language = 'es-ES'; Gender = 'Female'; Native = 'native-onecore' }
$sapi5Voice = [pscustomobject]@{ Engine = 'Sapi5'; Name = 'Voz Clasica'; Language = 'es-ES'; Gender = 'Male'; Native = 'Voz Clasica' }

Describe 'Get-InstalledVoices' {
    It 'lists OneCore voices first, then SAPI5 ones, in one record shape' {
        Mock Get-OneCoreVoices { return @([pscustomobject]@{ DisplayName = 'Modern'; Language = 'es-MX'; Gender = 'Female' }) }
        Mock Get-Sapi5Voices { return @([pscustomobject]@{ Name = 'Classic'; Culture = [System.Globalization.CultureInfo]'es-ES'; Gender = 'Male' }) }
        $voices = @(Get-InstalledVoices)
        $voices.Count | Should Be 2
        $voices[0].Engine | Should Be 'OneCore'
        $voices[0].Name | Should Be 'Modern'
        $voices[0].Language | Should Be 'es-MX'
        $voices[1].Engine | Should Be 'Sapi5'
        $voices[1].Name | Should Be 'Classic'
        $voices[1].Language | Should Be 'es-ES'
        $voices[1].Native | Should Be 'Classic'
    }
    It 'works with only SAPI5 voices when OneCore has none' {
        Mock Get-OneCoreVoices { return @() }
        Mock Get-Sapi5Voices { return @([pscustomobject]@{ Name = 'Classic'; Culture = [System.Globalization.CultureInfo]'es-ES'; Gender = 'Male' }) }
        @(Get-InstalledVoices).Count | Should Be 1
    }
    It 'finds at least one real voice on this machine' {
        @(Get-InstalledVoices).Count | Should BeGreaterThan 0
    }
}

Describe 'Find-Voice engine preference' {
    $modernMexican = [pscustomobject]@{ Engine = 'OneCore'; Name = 'Modern MX'; Language = 'es-MX'; Gender = 'Female'; Native = 1 }
    $classicSpanish = [pscustomobject]@{ Engine = 'Sapi5'; Name = 'Classic ES'; Language = 'es-ES'; Gender = 'Male'; Native = 'Classic ES' }

    It 'takes a modern voice for a close language over a classic voice for the exact one' {
        (Find-Voice -Voices @($modernMexican, $classicSpanish) -Language 'es-ES').Name | Should Be 'Modern MX'
    }
    It 'takes the exact language within one engine' {
        $modernSpanish = [pscustomobject]@{ Engine = 'OneCore'; Name = 'Modern ES'; Language = 'es-ES'; Gender = 'Male'; Native = 2 }
        (Find-Voice -Voices @($modernMexican, $modernSpanish) -Language 'es-ES').Name | Should Be 'Modern ES'
    }
    It 'uses a voice named exactly, whatever its engine' {
        (Find-Voice -Voices @($modernMexican, $classicSpanish) -Name 'Classic ES').Engine | Should Be 'Sapi5'
    }
    It 'finds nothing for a language no voice speaks' {
        Find-Voice -Voices @($modernMexican, $classicSpanish) -Language 'ja-JP' | Should BeNullOrEmpty
    }
}

Describe 'Invoke-SpeechOnVoice' {
    It 'sends a OneCore voice to the OneCore engine with its native voice object' {
        Mock Invoke-OneCoreSpeech {}
        Mock Invoke-Sapi5Speech {}
        Invoke-SpeechOnVoice -Voice $oneCoreVoice -Text 'hola' -Rate 3
        Assert-MockCalled Invoke-OneCoreSpeech -Scope It -Exactly 1 -ParameterFilter { $Voice -eq 'native-onecore' -and $Rate -eq 3 -and $Text -eq 'hola' }
        Assert-MockCalled Invoke-Sapi5Speech -Scope It -Exactly 0
    }
    It 'sends a SAPI5 voice to the SAPI5 engine by name' {
        Mock Invoke-OneCoreSpeech {}
        Mock Invoke-Sapi5Speech {}
        Invoke-SpeechOnVoice -Voice $sapi5Voice -Text 'hola' -Rate -2
        Assert-MockCalled Invoke-Sapi5Speech -Scope It -Exactly 1 -ParameterFilter { $VoiceName -eq 'Voz Clasica' -and $Rate -eq -2 }
        Assert-MockCalled Invoke-OneCoreSpeech -Scope It -Exactly 0
    }
}

Describe 'Pronunciation dictionary follows the voice language' {
    $english = [pscustomobject]@{ Engine = 'Sapi5'; Name = 'English Voice'; Language = 'en-US'; Gender = 'Female'; Native = 'English Voice' }
    $mexican = [pscustomobject]@{ Engine = 'OneCore'; Name = 'Voz Mexicana'; Language = 'es-MX'; Gender = 'Male'; Native = 'native-mx' }

    It 'gives a Spanish voice the Spanish dictionary, whatever the variant' {
        Mock Invoke-OneCoreSpeech {}
        Invoke-SpeechOnVoice -Voice $mexican -Text 'git' -Rate 0
        Assert-MockCalled Invoke-OneCoreSpeech -Scope It -Exactly 1 -ParameterFilter { $Dictionary.ContainsKey('git') }
    }
    It 'gives an English voice no hints: the dictionary is written for Spanish' {
        Mock Invoke-Sapi5Speech {}
        Invoke-SpeechOnVoice -Voice $english -Text 'git' -Rate 0
        Assert-MockCalled Invoke-Sapi5Speech -Scope It -Exactly 1 -ParameterFilter { $Dictionary.Count -eq 0 }
    }
    It 'gives no hints when pronunciation is off, even for a Spanish voice' {
        Mock Invoke-OneCoreSpeech {}
        Invoke-SpeechOnVoice -Voice $mexican -Text 'git' -Rate 0 -UsePronunciation $false
        Assert-MockCalled Invoke-OneCoreSpeech -Scope It -Exactly 1 -ParameterFilter { $Dictionary.Count -eq 0 }
    }
    It 'uses the system language for the default voice, which records none' {
        Mock Invoke-Sapi5Speech {}
        Mock Get-Culture { return [System.Globalization.CultureInfo]'en-US' }
        Invoke-SpeechOnVoice -Voice $script:DefaultSapi5Voice -Text 'git' -Rate 0
        Assert-MockCalled Invoke-Sapi5Speech -Scope It -Exactly 1 -ParameterFilter { $Dictionary.Count -eq 0 }
    }
    It 'picks the dictionary again for the voice a failure falls back to' {
        Mock Get-InstalledVoices { return @($mexican, $english) }
        Mock Invoke-SpeechOnVoice { if ($Voice.Engine -eq 'OneCore') { throw 'modern engine failed' } }
        Invoke-SpeechSynthesis -Text 'git' -Config @{ language = 'es-MX' }
        Assert-MockCalled Invoke-SpeechOnVoice -Scope It -Exactly 2
    }
}

Describe 'Invoke-SpeechSynthesis' {
    It 'speaks with the configured voice, the clamped rate and the pronunciation dictionary' {
        Mock Get-InstalledVoices { return @($oneCoreVoice, $sapi5Voice) }
        Mock Invoke-SpeechOnVoice {}
        Invoke-SpeechSynthesis -Text 'usá git' -Config @{ voiceName = 'Voz Clasica'; rate = 99 }
        Assert-MockCalled Invoke-SpeechOnVoice -Scope It -Exactly 1 -ParameterFilter {
            $Voice.Name -eq 'Voz Clasica' -and $Rate -eq 10 -and $UsePronunciation
        }
    }
    It 'passes an empty dictionary when pronunciation is off' {
        Mock Get-InstalledVoices { return @($oneCoreVoice) }
        Mock Invoke-SpeechOnVoice {}
        Invoke-SpeechSynthesis -Text 'git' -Config @{} -UsePronunciation $false
        Assert-MockCalled Invoke-SpeechOnVoice -Scope It -Exactly 1 -ParameterFilter { -not $UsePronunciation }
    }
    It 'prefers the modern voice when the config does not name one' {
        Mock Get-InstalledVoices { return @($oneCoreVoice, $sapi5Voice) }
        Mock Invoke-SpeechOnVoice {}
        Invoke-SpeechSynthesis -Text 'hola' -Config @{ language = 'es-ES' }
        Assert-MockCalled Invoke-SpeechOnVoice -Scope It -Exactly 1 -ParameterFilter { $Voice.Engine -eq 'OneCore' }
    }
    It 'retries a failed modern voice with a classic voice for the language' {
        Mock Get-InstalledVoices { return @($oneCoreVoice, $sapi5Voice) }
        Mock Invoke-SpeechOnVoice { if ($Voice.Engine -eq 'OneCore') { throw 'modern engine failed' } }
        Invoke-SpeechSynthesis -Text 'hola' -Config @{ language = 'es-ES' }
        Assert-MockCalled Invoke-SpeechOnVoice -Scope It -Exactly 2
        Assert-MockCalled Invoke-SpeechOnVoice -Scope It -Exactly 1 -ParameterFilter { $Voice.Name -eq 'Voz Clasica' }
    }
    It 'falls back to the system default voice when no classic voice matches the language' {
        $english = [pscustomobject]@{ Engine = 'Sapi5'; Name = 'English Voice'; Language = 'en-US'; Gender = 'Male'; Native = 'English Voice' }
        Mock Get-InstalledVoices { return @($oneCoreVoice, $english) }
        Mock Invoke-SpeechOnVoice { if ($Voice.Engine -eq 'OneCore') { throw 'modern engine failed' } }
        Invoke-SpeechSynthesis -Text 'hola' -Config @{ language = 'es-ES' }
        Assert-MockCalled Invoke-SpeechOnVoice -Scope It -Exactly 1 -ParameterFilter { $Voice.Engine -eq 'Sapi5' -and -not $Voice.Name }
    }
    It 'retries a failed named classic voice with the system default voice' {
        Mock Get-InstalledVoices { return @($sapi5Voice) }
        Mock Invoke-SpeechOnVoice { if ($Voice.Name) { throw 'voice vanished' } }
        Invoke-SpeechSynthesis -Text 'hola' -Config @{ language = 'es-ES' }
        Assert-MockCalled Invoke-SpeechOnVoice -Scope It -Exactly 2
    }
    It 'rethrows when even the system default voice fails, so the caller can log it' {
        Mock Get-InstalledVoices { return @() }
        Mock Invoke-SpeechOnVoice { throw 'nothing works' }
        { Invoke-SpeechSynthesis -Text 'hola' -Config @{} } | Should Throw 'nothing works'
        Assert-MockCalled Invoke-SpeechOnVoice -Scope It -Exactly 1
    }
    It 'logs the voice it picked and each failure' {
        Mock Get-InstalledVoices { return @($oneCoreVoice, $sapi5Voice) }
        Mock Invoke-SpeechOnVoice { if ($Voice.Engine -eq 'OneCore') { throw 'modern engine failed' } }
        $script:logged = New-Object System.Collections.Generic.List[string]
        $log = { param([string]$Message) $script:logged.Add($Message) }
        Invoke-SpeechSynthesis -Text 'hola' -Config @{ language = 'es-ES' } -Log $log
        ($script:logged -join '|') | Should Match 'voice: \[Voz Moderna\]'
        ($script:logged -join '|') | Should Match 'speech failed: modern engine failed'
        ($script:logged -join '|') | Should Match 'retrying with \[Voz Clasica\]'
    }
}

Describe 'Get-Sapi5Prompt' {
    Add-Type -AssemblyName System.Speech

    It 'returns nothing when no word has a pronunciation, so the caller speaks the plain text' {
        Get-Sapi5Prompt -Text 'hola mundo' -Dictionary (Get-PronunciationDictionary -Language 'es') | Should BeNullOrEmpty
    }
    It 'builds a prompt with a phoneme for each dictionary word' {
        $prompt = Get-Sapi5Prompt -Text 'usá git hoy' -Dictionary (Get-PronunciationDictionary -Language 'es') -Culture ([System.Globalization.CultureInfo]'es-ES')
        $prompt | Should Not BeNullOrEmpty
        $xml = $prompt.ToXml()
        $xml | Should Match 'git'
        $xml | Should Match 'ph='
    }
    It 'builds a prompt even without a culture' {
        (Get-Sapi5Prompt -Text 'git' -Dictionary (Get-PronunciationDictionary -Language 'es')).ToXml() | Should Match 'ph='
    }
    It 'keeps the text around the dictionary words' {
        $xml = (Get-Sapi5Prompt -Text 'antes git despues' -Dictionary (Get-PronunciationDictionary -Language 'es')).ToXml()
        $xml | Should Match 'antes'
        $xml | Should Match 'despues'
    }
}

Describe 'SAPI5 voice discovery' {
    It 'reports real installed voices with a name and a culture' {
        $voices = @(Get-Sapi5Voices)
        $voices.Count | Should BeGreaterThan 0
        $voices[0].Name | Should Not BeNullOrEmpty
        $voices[0].Culture.Name | Should Not BeNullOrEmpty
    }
}

Describe 'OneCore engine without playback' {
    $available = @(Get-OneCoreVoices)
    $skip = $available.Count -eq 0

    It 'loads the Windows Runtime types, or reports that it cannot, without throwing' {
        { Initialize-OneCoreTypes } | Should Not Throw
        (Initialize-OneCoreTypes) | Should Be (Initialize-OneCoreTypes)
    }
    It 'returns a list (possibly empty) of voices' {
        { @(Get-OneCoreVoices) } | Should Not Throw
    }
    It 'turns SSML into an audio stream' -Skip:$skip {
        $voice = $available[0]
        $synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
        $synth.Voice = $voice
        $ssml = ConvertTo-OneCoreSsml -Text 'usá git' -Language $voice.Language -Dictionary (Get-PronunciationDictionary -Language 'es')
        $stream = Wait-OneCoreAsync -AsyncOperation $synth.SynthesizeSsmlToStreamAsync($ssml) -ResultType ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
        try { $stream.Size | Should BeGreaterThan 1000 } finally { $stream.Dispose() }
    }
    It 'gives up with a clear message when a synthesis never finishes' -Skip:$skip {
        $original = $script:OneCoreWaitTimeoutMs
        $script:OneCoreWaitTimeoutMs = 1
        try {
            $synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
            $synth.Voice = $available[0]
            $long = 'palabra ' * 4000
            $operation = $synth.SynthesizeTextToStreamAsync($long)
            { Wait-OneCoreAsync -AsyncOperation $operation -ResultType ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]) } | Should Throw 'timed out'
        } finally {
            $script:OneCoreWaitTimeoutMs = $original
        }
    }
}

Describe 'Invoke-WithNamedMutex after an abandoned lock' {
    It 'treats a mutex whose holder exited without releasing it as acquired' {
        $name = 'Local\SapiVoiceKitTest' + [Guid]::NewGuid().ToString('N')
        & powershell -NoProfile -Command "`$m = New-Object System.Threading.Mutex(`$false, '$name'); [void]`$m.WaitOne(); exit 0"
        Invoke-WithNamedMutex -Name $name -TimeoutMs 3000 -Action { 'ran' } | Should Be 'ran'
    }
}

Describe 'Script context and debug text' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'bundles the saved settings with a logger that is silent by default' {
        Save-VoiceConfig -Changes @{ mode = 'literal' } | Out-Null
        $context = New-ScriptContext -LogFile 'log-x.txt'
        $context.Config.mode | Should Be 'literal'
        $context.Debug | Should Be $false
        & $context.Log 'hello'
        Get-DataFilePath 'log-x.txt' | Should Not Exist
    }
    It 'gives a logger that writes once debug is on' {
        Save-VoiceConfig -Changes @{ debug = $true } | Out-Null
        $context = New-ScriptContext -LogFile 'log-x.txt'
        $context.Debug | Should Be $true
        & $context.Log 'hello'
        (Get-Content (Get-DataFilePath 'log-x.txt') -Encoding UTF8) | Should Match 'hello'
    }
    It 'works before any config exists' {
        $context = New-ScriptContext -LogFile 'log-x.txt'
        $context.Config.Count | Should Be 0
        $context.Debug | Should Be $false
    }
    It 'keeps the last spoken text, accents included' {
        Save-LastSpokenText -Text 'García ¿sí?'
        (Get-Content (Get-DataFilePath 'last-text.txt') -Encoding UTF8) | Should Be 'García ¿sí?'
    }
}

Describe 'Get-AiSummary with a real native command' {
    BeforeEach {
        $script:fakeBin = Join-Path ([System.IO.Path]::GetTempPath()) ('sapi-voice-kit-claude-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fakeBin -Force | Out-Null
        $script:originalPath = $env:PATH
    }
    AfterEach {
        $env:PATH = $script:originalPath
        Remove-Item -Path $script:fakeBin -Recurse -Force -ErrorAction SilentlyContinue
    }

    # A stand-in `claude` that prints the hex code of every character it
    # receives on stdin, decoded as UTF-8.
    function Install-FakeClaude {
        $echo = @'
$buffer = New-Object System.IO.MemoryStream
[Console]::OpenStandardInput().CopyTo($buffer)
$text = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
($text.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ' '
'@
        [System.IO.File]::WriteAllText("$script:fakeBin\echo-codes.ps1", $echo, [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText("$script:fakeBin\claude.cmd", "@powershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0echo-codes.ps1`"", [System.Text.Encoding]::ASCII)
        $env:PATH = "$script:fakeBin;$script:originalPath"
    }

    It 'delivers accented text to claude as UTF-8, not as question marks' {
        Install-FakeClaude
        $codes = Get-AiSummary -Text 'canción ñandú'
        $codes | Should Match '00F3'
        $codes | Should Match '00F1'
    }
    It 'returns nothing when claude prints only whitespace' {
        [System.IO.File]::WriteAllText("$script:fakeBin\claude.cmd", "@echo.", [System.Text.Encoding]::ASCII)
        $env:PATH = "$script:fakeBin;$script:originalPath"
        Get-AiSummary -Text 'algo' | Should BeNullOrEmpty
    }
    It 'returns nothing when claude is not installed' {
        $env:PATH = $script:fakeBin
        Get-AiSummary -Text 'algo' | Should BeNullOrEmpty
    }
    It 'restores the console and pipe encodings afterwards' {
        Install-FakeClaude
        $pipeBefore = $global:OutputEncoding.WebName
        $consoleBefore = [Console]::OutputEncoding.WebName
        Get-AiSummary -Text 'algo' | Out-Null
        $global:OutputEncoding.WebName | Should Be $pipeBefore
        [Console]::OutputEncoding.WebName | Should Be $consoleBefore
    }
}

Describe 'ConvertTo-SpokenUrls on hosts without a dot' {
    It 'names the host itself' {
        ConvertTo-SpokenUrls -Text 'abrí http://localhost:3000/app' | Should Be 'abrí el link de localhost:3000'
    }
}
