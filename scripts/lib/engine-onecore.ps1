# OneCore engine (Windows.Media.SpeechSynthesis): the modern, more natural
# Windows 11 voices. Preferred when one exists for the target language; the
# classic SAPI5 engine (engine-sapi5.ps1) is always there as the fallback.
# Natural voices need Windows 11 22H2+ and a one-time download from
# Settings -> Narrator, so their absence is normal and never an error.

$script:OneCoreWaitTimeoutMs = 30000
$script:OneCoreTypesLoaded = $false
$script:OneCoreTypesFailed = $false
$script:OneCoreAsTask = $null

# Loads the WinRT projection that Windows PowerShell 5.1 needs to call these
# APIs. The result, success or failure, is cached for the process.
function Initialize-OneCoreTypes {
    if ($script:OneCoreTypesLoaded) { return $true }
    if ($script:OneCoreTypesFailed) { return $false }
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        $script:OneCoreAsTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]
        [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime] | Out-Null
        $script:OneCoreTypesLoaded = $true
        return $true
    } catch {
        $script:OneCoreTypesFailed = $true
        return $false
    }
}

# PowerShell has no await: this blocks on a WinRT IAsyncOperation through
# AsTask(). The wait is bounded because it runs inside the speech lock, and an
# unbounded one would freeze speech for every other process.
function Wait-OneCoreAsync {
    param($AsyncOperation, $ResultType)
    $task = $script:OneCoreAsTask.MakeGenericMethod($ResultType).Invoke($null, @($AsyncOperation))
    try {
        if (-not $task.Wait($script:OneCoreWaitTimeoutMs)) {
            throw "OneCore synthesis timed out after $($script:OneCoreWaitTimeoutMs)ms"
        }
    } catch [System.AggregateException] {
        # Task.Wait wraps the real failure; surface it.
        if ($_.Exception.InnerException) { throw $_.Exception.InnerException }
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

# SSML with each dictionary word wrapped in <phoneme>. Text and IPA are
# XML-escaped. No <prosody> wrapper: the OneCore voices ignore SSML prosody, so
# the speaking rate is set through SpeechSynthesizer.Options instead.
function ConvertTo-OneCoreSsml {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Language,
        [Parameter(Mandatory)][hashtable]$Dictionary
    )

    $body = New-Object System.Text.StringBuilder
    foreach ($segment in @(Split-PronunciationSegments -Text $Text -Dictionary $Dictionary)) {
        $escapedText = [System.Security.SecurityElement]::Escape($segment.Text)
        if ($segment.Ipa) {
            $escapedIpa = [System.Security.SecurityElement]::Escape($segment.Ipa)
            [void]$body.Append("<phoneme alphabet='ipa' ph='$escapedIpa'>$escapedText</phoneme>")
        } else {
            [void]$body.Append($escapedText)
        }
    }
    return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='$Language'>$($body.ToString())</speak>"
}

# $Voice is the WinRT VoiceInformation. $Rate (-10..10, same scale as SAPI5)
# becomes SpeakingRate, a multiplier: -10 -> 0.5x, 0 -> 1x, +10 -> 2x.
function Invoke-OneCoreSpeech {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)]$Voice,
        [Parameter(Mandatory)][int]$Rate,
        [Parameter(Mandatory)][hashtable]$Dictionary,
        [scriptblock]$Log = { param([string]$Message) }
    )

    $synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
    $synth.Voice = $Voice
    $synth.Options.SpeakingRate = [math]::Pow(2, $Rate / 10)
    $ssml = ConvertTo-OneCoreSsml -Text $Text -Language $Voice.Language -Dictionary $Dictionary
    & $Log "OneCore voice [$($Voice.DisplayName)], rate $Rate"

    $stream = Wait-OneCoreAsync -AsyncOperation $synth.SynthesizeSsmlToStreamAsync($ssml) -ResultType ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
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
}
