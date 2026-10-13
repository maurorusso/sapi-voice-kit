# Unit tests for the PowerShell library (scripts/common.ps1 and scripts/lib/).
# Dev-only: nothing here ships as a dependency of the plugin. Run with:
#   powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests/common.Tests.ps1"
#
# Pester 3.4 syntax on purpose: it is the version bundled with Windows
# PowerShell 5.1, so nothing needs installing. CI pins the same version.
#
# Audio quality cannot be asserted; /sapi-voice-kit:test covers that by ear.
# Everything below is text-in/text-out, file-in/file-out, or voice-selection
# logic run against synthetic voice lists.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
. "$repoRoot\scripts\common.ps1"

# Points the plugin's data folder at a throwaway home directory for one test.
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

Describe 'ConvertTo-SpokenDotfiles' {
    It 'reads a bare dotfile as "punto ..."' {
        ConvertTo-SpokenDotfiles -Text 'abrí .env por favor' | Should Be 'abrí punto env por favor'
    }
    It 'reads every dot of a compound dotfile inside backticks' {
        ConvertTo-SpokenDotfiles -Text 'mirá `.mcp.json`' | Should Be 'mirá `punto mcp punto json`'
    }
    It 'leaves ordinary prose alone' {
        ConvertTo-SpokenDotfiles -Text 'esto no tiene nada raro. Sigue acá.' | Should Be 'esto no tiene nada raro. Sigue acá.'
    }
}

Describe 'ConvertTo-SpokenFileNames' {
    It 'drops the folders of a relative path' {
        ConvertTo-SpokenFileNames -Text 'mirá scripts/common.ps1 ahora' | Should Be 'mirá common punto ps1 ahora'
    }
    It 'drops the folders of a Windows path' {
        ConvertTo-SpokenFileNames -Text 'abrí C:\Projects\App\docs\README.md' | Should Be 'abrí README punto md'
    }
    It 'leaves an unknown extension alone' {
        ConvertTo-SpokenFileNames -Text 'el archivo foo.xyz' | Should Be 'el archivo foo.xyz'
    }
}

Describe 'ConvertTo-SpokenPaths' {
    It 'reduces a drive path to its last segment' {
        ConvertTo-SpokenPaths -Text 'andá a C:\Projects\App' | Should Be 'andá a App'
    }
    It 'leaves prose without a drive letter alone' {
        ConvertTo-SpokenPaths -Text 'esto es una oración normal' | Should Be 'esto es una oración normal'
    }
}

Describe 'ConvertTo-SpokenUrls' {
    It 'names the site instead of reading the URL' {
        ConvertTo-SpokenUrls -Text 'mirá https://github.com/maurorusso/sapi-voice-kit' | Should Be 'mirá el link de github'
    }
    It 'ignores a www prefix' {
        ConvertTo-SpokenUrls -Text 'https://www.example.com/algo' | Should Be 'el link de example'
    }
    It 'ignores subdomains' {
        ConvertTo-SpokenUrls -Text 'https://docs.github.com/x' | Should Be 'el link de github'
    }
    It 'leaves text without a URL alone' {
        ConvertTo-SpokenUrls -Text 'no hay ningún link acá' | Should Be 'no hay ningún link acá'
    }
}

Describe 'ConvertTo-SpokenAbbreviations' {
    It 'expands a sentence-final etc. and keeps the sentence boundary' {
        ConvertTo-SpokenAbbreviations -Text 'gatos, perros, etc. Después seguimos.' | Should Be 'gatos, perros, etcétera. Después seguimos.'
    }
    It 'keeps the sentence boundary when the next sentence opens with an inverted question mark' {
        ConvertTo-SpokenAbbreviations -Text 'cosas, etc. ¿Seguimos?' | Should Be 'cosas, etcétera. ¿Seguimos?'
    }
    It 'expands etc even without its dot' {
        ConvertTo-SpokenAbbreviations -Text 'cosas, etc, que uses' | Should Be 'cosas, etcétera, que uses'
    }
    It 'does not turn the dot of Dr. into a sentence break' {
        ConvertTo-SpokenAbbreviations -Text 'hablé con el Dr. García ayer' | Should Be 'hablé con el doctor García ayer'
    }
    It 'does not invent a sentence break when the next word is lowercase' {
        ConvertTo-SpokenAbbreviations -Text 'gatos, perros, etc. seguimos con otra cosa' | Should Be 'gatos, perros, etcétera seguimos con otra cosa'
    }
    It 'leaves the product name VS Code alone' {
        ConvertTo-SpokenAbbreviations -Text 'lo abrí en VS Code' | Should Be 'lo abrí en VS Code'
    }
}

Describe 'ConvertTo-SpokenIdentifiers' {
    It 'applies dotfile, file name, path and abbreviation rules together' {
        $text = 'Abrí .env, scripts/common.ps1, C:\Projects\App y el Dr. Pérez'
        ConvertTo-SpokenIdentifiers -Text $text | Should Be 'Abrí punto env, common punto ps1, App y el doctor Pérez'
    }
}

Describe 'Add-ImplicitLineEndPeriods' {
    It 'ends an unpunctuated line with a period' {
        Add-ImplicitLineEndPeriods -Text "primera línea`nsegunda línea" | Should Be "primera línea.`nsegunda línea"
    }
    It 'leaves a line that already ends in punctuation' {
        Add-ImplicitLineEndPeriods -Text "una pregunta?`notra línea" | Should Be "una pregunta?`notra línea"
    }
    It 'does not add a period after a dash' {
        Add-ImplicitLineEndPeriods -Text "Paso uno $([char]0x2014)`nPaso dos" | Should Be "Paso uno $([char]0x2014)`nPaso dos"
    }
}

Describe 'Get-CleanedText' {
    It 'keeps only the label of a markdown link' {
        Get-CleanedText -Text 'mirá [la doc](https://example.com)' | Should Be 'mirá la doc'
    }
    It 'removes bullet markers' {
        Get-CleanedText -Text '- primer punto' | Should Be 'primer punto'
    }
    It 'replaces a code block with a short placeholder' {
        Get-CleanedText -Text 'antes ```code aca``` despues' | Should Be 'antes  code block omitted.  despues'
    }
    It 'removes heading markers' {
        Get-CleanedText -Text '## Título' | Should Be 'Título'
    }
    It 'turns an em dash into a comma' {
        Get-CleanedText -Text "texto $([char]0x2014) más texto" | Should Be 'texto, más texto'
    }
    It 'reads a bare URL as its site' {
        Get-CleanedText -Text 'mirá https://github.com/x/y ya' | Should Be 'mirá el link de github ya'
    }
}

Describe 'Pronunciation dictionaries' {
    $files = @(Get-ChildItem "$repoRoot\scripts\lib\pronunciations" -Filter *.psd1)

    It 'has one file per two-letter language code' {
        $files.Count | Should BeGreaterThan 0
        @($files | Where-Object { $_.BaseName -cnotmatch '^[a-z]{2,3}$' }).Count | Should Be 0
    }
    foreach ($file in $files) {
        $dictionary = Import-PowerShellDataFile -Path $file.FullName

        It "$($file.Name) only has single lowercase word keys" {
            @($dictionary.Keys | Where-Object { $_ -cnotmatch '^[a-z]+$' }).Count | Should Be 0
        }
        It "$($file.Name) never uses characters that would break the SSML attribute" {
            @($dictionary.Keys | Where-Object { $dictionary[$_] -match "['&<>""]" }).Count | Should Be 0
        }
        It "$($file.Name) has a pronunciation for every key" {
            @($dictionary.Keys | Where-Object { -not $dictionary[$_] }).Count | Should Be 0
        }
    }
}

Describe 'Get-PronunciationDictionary' {
    It 'gives the Spanish dictionary to every Spanish variant' {
        foreach ($language in 'es', 'es-ES', 'es-MX', 'es-AR', 'ES-es') {
            (Get-PronunciationDictionary -Language $language).ContainsKey('git') | Should Be $true
        }
    }
    It 'gives nothing to a language that has no dictionary' {
        foreach ($language in 'en-US', 'pt-BR', 'ja-JP', 'xx') {
            (Get-PronunciationDictionary -Language $language).Count | Should Be 0
        }
    }
    It 'gives nothing for an empty or unusable language' {
        foreach ($language in $null, '', '  ', '../x', 'e s', '123') {
            (Get-PronunciationDictionary -Language $language).Count | Should Be 0
        }
    }
    It 'stresses the Spanish word natural on its last syllable, not the English way' {
        (Get-PronunciationDictionary -Language 'es-ES')['natural'] | Should Match 'ˈɾal$'
    }
    It 'uses a dictionary file as soon as one is added for a language' {
        $path = "$repoRoot\scripts\lib\pronunciations\zz.psd1"
        [System.IO.File]::WriteAllText($path, "@{ 'hola' = 'ˈola' }", (New-Object System.Text.UTF8Encoding($true)))
        try { (Get-PronunciationDictionary -Language 'zz-ZZ')['hola'] | Should Be 'ˈola' }
        finally { Remove-Item $path; $script:PronunciationDictionaries.Remove('zz') }
    }
}

Describe 'Split-PronunciationSegments' {
    $dictionary = @{ git = 'IPA-GIT'; push = 'IPA-PUSH' }

    It 'gives back the original text when the segments are joined' {
        $text = 'Hice Git push, y listo.'
        $segments = @(Split-PronunciationSegments -Text $text -Dictionary $dictionary)
        ($segments | ForEach-Object { $_.Text }) -join '' | Should Be $text
    }
    It 'marks dictionary words case-insensitively' {
        $segments = @(Split-PronunciationSegments -Text 'un Git ahí' -Dictionary $dictionary)
        $hinted = @($segments | Where-Object { $_.Ipa })
        $hinted.Count | Should Be 1
        $hinted[0].Text | Should Be 'Git'
        $hinted[0].Ipa | Should Be 'IPA-GIT'
    }
    It 'does not match inside a longer word' {
        $segments = @(Split-PronunciationSegments -Text 'digital pushing' -Dictionary $dictionary)
        @($segments | Where-Object { $_.Ipa }).Count | Should Be 0
    }
    It 'returns one plain segment when nothing matches' {
        $segments = @(Split-PronunciationSegments -Text 'nada especial' -Dictionary $dictionary)
        $segments.Count | Should Be 1
        $segments[0].Ipa | Should Be $null
    }
    It 'returns no segments for empty text' {
        @(Split-PronunciationSegments -Text '' -Dictionary $dictionary).Count | Should Be 0
    }
}

Describe 'ConvertTo-OneCoreSsml' {
    It 'wraps a dictionary word in a phoneme element' {
        $ssml = ConvertTo-OneCoreSsml -Text 'usá git' -Language 'es-ES' -Dictionary (Get-PronunciationDictionary -Language 'es')
        $ssml | Should Match "<phoneme alphabet='ipa' ph='[^']+'>git</phoneme>"
    }
    It 'escapes XML characters in the text' {
        $ssml = ConvertTo-OneCoreSsml -Text 'a < b & c' -Language 'es-ES' -Dictionary @{}
        $ssml | Should Match 'a &lt; b &amp; c'
    }
    It 'adds no phoneme elements when pronunciation is off' {
        $ssml = ConvertTo-OneCoreSsml -Text 'usá git' -Language 'es-ES' -Dictionary @{}
        $ssml | Should Not Match '<phoneme'
    }
    It 'sets the language on the speak element' {
        ConvertTo-OneCoreSsml -Text 'hola' -Language 'es-MX' -Dictionary @{} | Should Match "xml:lang='es-MX'"
    }
}

Describe 'ConvertTo-SafeRate' {
    It 'passes an in-range number through' { ConvertTo-SafeRate -Value 3 | Should Be 3 }
    It 'accepts a number stored as text' { ConvertTo-SafeRate -Value '4' | Should Be 4 }
    It 'clamps to the maximum' { ConvertTo-SafeRate -Value 99 | Should Be 10 }
    It 'clamps to the minimum' { ConvertTo-SafeRate -Value -99 | Should Be -10 }
    It 'treats a missing value as normal speed' { ConvertTo-SafeRate -Value $null | Should Be 0 }
    It 'treats a non-number as normal speed instead of throwing' { ConvertTo-SafeRate -Value 'fast' | Should Be 0 }
}

Describe 'Voice selection' {
    $voices = @(
        [pscustomobject]@{ Engine = 'OneCore'; Name = 'Microsoft Pablo'; Language = 'es-ES'; Gender = 'Male'; Native = 'native-pablo' },
        [pscustomobject]@{ Engine = 'OneCore'; Name = 'Microsoft Laura'; Language = 'es-ES'; Gender = 'Female'; Native = 'native-laura' },
        [pscustomobject]@{ Engine = 'Sapi5'; Name = 'Microsoft Helena Desktop'; Language = 'es-ES'; Gender = 'Female'; Native = 'Microsoft Helena Desktop' },
        [pscustomobject]@{ Engine = 'Sapi5'; Name = 'Microsoft Zira Desktop'; Language = 'en-US'; Gender = 'Female'; Native = 'Microsoft Zira Desktop' }
    )

    It 'prefers the first voice for the language, which is the OneCore one' {
        (Find-Voice -Voices $voices -Language 'es-ES').Name | Should Be 'Microsoft Pablo'
    }
    It 'finds a voice by exact name' {
        (Find-Voice -Voices $voices -Name 'Microsoft Laura').Name | Should Be 'Microsoft Laura'
    }
    It 'finds a classic voice by its name' {
        (Find-Voice -Voices $voices -Name 'Microsoft Zira Desktop').Engine | Should Be 'Sapi5'
    }
    It 'matches on the language prefix when there is no exact match' {
        (Find-Voice -Voices $voices -Language 'es-MX').Name | Should Be 'Microsoft Pablo'
    }
    It 'falls back to the language when the named voice is not installed' {
        (Find-Voice -Voices $voices -Name 'Microsoft Gone' -Language 'en-US').Name | Should Be 'Microsoft Zira Desktop'
    }
    It 'returns nothing when no voice speaks the language' {
        Find-Voice -Voices $voices -Language 'ja-JP' | Should Be $null
    }
    It 'uses the system default voice when nothing matches' {
        $target = Resolve-SpeechTarget -Config @{ language = 'ja-JP' } -Voices $voices
        $target.Engine | Should Be 'Sapi5'
        $target.Name | Should Be $null
    }
    It 'honors the configured voice name' {
        (Resolve-SpeechTarget -Config @{ voiceName = 'Microsoft Laura' } -Voices $voices).Name | Should Be 'Microsoft Laura'
    }

    Context 'fallback after a failure' {
        Mock Get-InstalledVoices { return $voices }

        It 'goes from a failed OneCore voice to a classic voice for the language' {
            $fallback = Get-FallbackVoice -Failed $voices[0] -Config @{ language = 'es-ES' }
            $fallback.Name | Should Be 'Microsoft Helena Desktop'
        }
        It 'goes from a failed named classic voice to the default voice' {
            $fallback = Get-FallbackVoice -Failed $voices[2] -Config @{}
            $fallback.Engine | Should Be 'Sapi5'
            $fallback.Name | Should Be $null
        }
        It 'has nothing left after the default voice fails' {
            Get-FallbackVoice -Failed $script:DefaultSapi5Voice -Config @{} | Should Be $null
        }
    }
}

Describe 'Invoke-WithNamedMutex' {
    $name = 'Local\SapiVoiceKitTest' + [Guid]::NewGuid().ToString('N')

    It 'returns what the action returns' {
        Invoke-WithNamedMutex -Name $name -TimeoutMs 1000 -Action { 42 } | Should Be 42
    }
    It 'releases the mutex when the action throws' {
        { Invoke-WithNamedMutex -Name $name -TimeoutMs 1000 -Action { throw 'boom' } } | Should Throw
        Invoke-WithNamedMutex -Name $name -TimeoutMs 1000 -Action { 'second call ran' } | Should Be 'second call ran'
    }
    It 'runs anyway, and says so, when another process holds the mutex too long' {
        $holder = Start-Job -ArgumentList $name -ScriptBlock {
            param($name)
            $mutex = New-Object System.Threading.Mutex($false, $name)
            [void]$mutex.WaitOne()
            Start-Sleep -Seconds 4
            $mutex.ReleaseMutex()
        }
        Start-Sleep -Milliseconds 1500
        $messages = New-Object System.Collections.Generic.List[string]
        $log = { param([string]$Message) $messages.Add($Message) }.GetNewClosure()
        $result = Invoke-WithNamedMutex -Name $name -TimeoutMs 300 -Log $log -Action { 'ran' }
        Remove-Job $holder -Force
        $result | Should Be 'ran'
        ($messages -join ' ') | Should Match 'timed out'
    }
}

Describe 'Config store' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'returns empty settings when there is no config yet' {
        (Get-VoiceConfig).Count | Should Be 0
    }
    It 'does not create the data folder just by reading' {
        Get-VoiceConfig | Out-Null
        Test-Path (Get-SharedDataDir) | Should Be $false
    }
    It 'saves into the local namespace by default' {
        Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
        (Get-VoiceConfig).mode | Should Be 'active'
    }
    It 'keeps local and cowork independent' {
        Save-VoiceConfig -Namespace 'local' -Changes @{ voiceName = 'Microsoft Laura' } | Out-Null
        Save-VoiceConfig -Namespace 'cowork' -Changes @{ voiceName = 'Microsoft Pablo' } | Out-Null
        (Get-VoiceConfig -Namespace 'local').voiceName | Should Be 'Microsoft Laura'
        (Get-VoiceConfig -Namespace 'cowork').voiceName | Should Be 'Microsoft Pablo'
    }
    It 'removes keys without touching the others' {
        Save-VoiceConfig -Changes @{ voiceName = 'Microsoft Laura'; rate = 2 } | Out-Null
        Save-VoiceConfig -Remove @('voiceName') | Out-Null
        $config = Get-VoiceConfig
        $config.ContainsKey('voiceName') | Should Be $false
        $config.rate | Should Be 2
    }
    It 'takes the namespace from SAPI_VOICE_NAMESPACE' {
        Save-VoiceConfig -Namespace 'cowork' -Changes @{ mode = 'literal' } | Out-Null
        $env:SAPI_VOICE_NAMESPACE = 'cowork'
        try { (Get-VoiceConfig).mode | Should Be 'literal' }
        finally { Remove-Item Env:\SAPI_VOICE_NAMESPACE }
    }
    It 'rejects an unknown namespace' {
        { Get-VoiceConfig -Namespace 'nope' } | Should Throw
        { Save-VoiceConfig -Namespace 'nope' -Changes @{ a = 1 } } | Should Throw
    }
    It 'reads a corrupt config as defaults instead of failing' {
        Initialize-SharedDataDir | Out-Null
        Set-Content -Path (Get-DataFilePath 'config.json') -Value '{ not json'
        (Get-VoiceConfig).Count | Should Be 0
    }
    It 'leaves a healthy config alone when it is only locked by another program' {
        Save-VoiceConfig -Changes @{ mode = 'literal' } | Out-Null
        $path = Get-DataFilePath 'config.json'
        # Unreadable by others but still renamable: the worst case for a wrong "corrupt" verdict.
        $lock = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'Delete')
        try {
            { Save-VoiceConfig -Changes @{ mode = 'active' } } | Should Throw
        } finally {
            $lock.Dispose()
        }
        "$path.bad" | Should Not Exist
        (Get-VoiceConfig).mode | Should Be 'literal'
    }
    It 'moves a corrupt config aside and keeps saving' {
        Initialize-SharedDataDir | Out-Null
        Set-Content -Path (Get-DataFilePath 'config.json') -Value '{ not json'
        Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
        (Get-VoiceConfig).mode | Should Be 'active'
        Test-Path (Get-DataFilePath 'config.json.bad') | Should Be $true
    }
    It 'leaves no temp file behind after a write' {
        Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
        Save-VoiceConfig -Changes @{ mode = 'natural' } | Out-Null
        Test-Path (Get-DataFilePath 'config.json.tmp') | Should Be $false
    }
    It 'treats an empty config file as no config' {
        Initialize-SharedDataDir | Out-Null
        Set-Content -Path (Get-DataFilePath 'config.json') -Value ''
        (Get-VoiceConfig).Count | Should Be 0
    }
}

Describe 'Config store under concurrent processes' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    # Separate powershell.exe processes (Start-Job) all writing at once. Without
    # the lock this loses updates. The parent keeps its real USERPROFILE while
    # starting the jobs because Start-Job itself needs a valid profile; each job
    # sets the fake one for itself.
    It 'loses no write when 10 processes save at the same time' {
        $fakeHome = $script:fakeHome
        $real = $script:originalProfile
        $env:USERPROFILE = $real
        $jobs = 1..10 | ForEach-Object {
            Start-Job -ArgumentList "$repoRoot\scripts\common.ps1", $fakeHome, $_ -ScriptBlock {
                param($common, $fakeHome, $i)
                $env:USERPROFILE = $fakeHome
                . $common
                Save-VoiceConfig -Changes @{ "key$i" = $true } | Out-Null
            }
        }
        $jobs | Wait-Job -Timeout 90 | Out-Null
        $failures = @($jobs | Where-Object { $_.State -ne 'Completed' })
        $jobs | Remove-Job -Force

        $env:USERPROFILE = $fakeHome
        $config = Get-VoiceConfig
        $missing = @(1..10 | Where-Object { -not $config.ContainsKey("key$_") })
        $failures.Count | Should Be 0
        $missing.Count | Should Be 0
    }
}

Describe 'Duplicate-speech guard' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'sees no recent speech at first' {
        Test-RecentActiveSpeech | Should Be $false
    }
    It 'sees speech that was just recorded' {
        Set-RecentSpeechMarker
        Test-RecentActiveSpeech | Should Be $true
    }
    It 'forgets speech older than the window' {
        Initialize-SharedDataDir | Out-Null
        $old = (Get-Date).AddSeconds(-($script:SpeechGuardWindowSeconds + 5)).Ticks
        Set-Content -Path (Get-DataFilePath '.last-active-speech') -Value "$old"
        Test-RecentActiveSpeech | Should Be $false
    }
    It 'treats an unreadable marker as no recent speech' {
        Initialize-SharedDataDir | Out-Null
        Set-Content -Path (Get-DataFilePath '.last-active-speech') -Value 'garbage'
        Test-RecentActiveSpeech | Should Be $false
    }
    It 'stores a timestamp only, never text' {
        Set-RecentSpeechMarker
        (Get-Content -Path (Get-DataFilePath '.last-active-speech') -Raw).Trim() | Should Match '^\d+$'
    }
}

Describe 'Logger' {
    BeforeEach { Use-FakeHome }
    AfterEach { Remove-FakeHome }

    It 'writes nothing, and creates nothing, when disabled' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $false
        & $log 'hello'
        Test-Path (Get-SharedDataDir) | Should Be $false
    }
    It 'appends timestamped lines when enabled' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        & $log 'first'
        & $log 'second'
        $lines = Get-Content -Path (Get-DataFilePath 'log-test.txt')
        $lines.Count | Should Be 2
        $lines[1] | Should Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} - second$'
    }
    It 'trims the file to its last lines once it passes the size cap' {
        $script:LogMaxBytes = 200
        $script:LogKeepLines = 3
        try {
            $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
            1..30 | ForEach-Object { & $log "line number $_ padded to be long enough" }
            @(Get-Content -Path (Get-DataFilePath 'log-test.txt')).Count | Should BeLessThan 10
            (Get-Content -Path (Get-DataFilePath 'log-test.txt') -Raw) | Should Match 'line number 30'
        } finally {
            $script:LogMaxBytes = 50KB
            $script:LogKeepLines = 200
        }
    }
}

Describe 'Get-AiSummary' {
    It 'returns the text claude prints' {
        function global:claude { $null = $input; $global:LASTEXITCODE = 0; 'Un resumen corto.' }
        try { Get-AiSummary -Text 'Un texto largo.' | Should Be 'Un resumen corto.' }
        finally { Remove-Item function:\claude }
    }
    It 'returns nothing when claude fails, so the caller reads the full text' {
        function global:claude { $null = $input; $global:LASTEXITCODE = 1 }
        try { Get-AiSummary -Text 'Un texto largo.' | Should Be $null }
        finally { Remove-Item function:\claude }
    }
}

Describe 'Repository integrity' {
    It 'keeps a UTF-8 BOM on every PowerShell file (Windows PowerShell 5.1 misreads accents without one)' {
        $without = Get-ChildItem "$repoRoot\scripts", "$repoRoot\tests" -Recurse -Include *.ps1, *.psd1 | Where-Object {
            $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
            -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        }
        @($without | ForEach-Object { $_.Name }).Count | Should Be 0
    }
    It 'parses every script without errors' {
        $broken = Get-ChildItem "$repoRoot\scripts" -Recurse -Include *.ps1 | Where-Object {
            $errors = $null
            [void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -Encoding UTF8 $_.FullName), [ref]$errors)
            $errors.Count -gt 0
        }
        @($broken | ForEach-Object { $_.Name }).Count | Should Be 0
    }
}
