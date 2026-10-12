# Speaking: picks the voice, takes the machine-wide speech lock, and plays the
# text with the owning engine, falling back to SAPI5 if that engine fails.

$script:SpeechLockName = 'Local\SapiVoiceKitSpeak'
$script:SpeechLockTimeoutMs = 60000

function Invoke-SpeechOnVoice {
    param(
        [Parameter(Mandatory)]$Voice,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$Rate,
        [bool]$UsePronunciation = $true,
        [scriptblock]$Log
    )
    # The system default voice records no language; assume the system's.
    $language = if ($Voice.Language) { $Voice.Language } else { (Get-Culture).Name }
    $Dictionary = if ($UsePronunciation) { Get-PronunciationDictionary -Language $language } else { @{} }

    if ($Voice.Engine -eq 'OneCore') {
        Invoke-OneCoreSpeech -Text $Text -Voice $Voice.Native -Rate $Rate -Dictionary $Dictionary -Log $Log
    } else {
        Invoke-Sapi5Speech -Text $Text -VoiceName $Voice.Name -Rate $Rate -Dictionary $Dictionary -Log $Log
    }
}

# What to try after $Failed did not work: a failed OneCore voice -> a SAPI5
# voice for the language; a failed named SAPI5 voice (e.g. uninstalled while
# waiting for the lock) -> SAPI5's default voice; a failed default voice has
# nothing left, so $null.
function Get-FallbackVoice {
    param(
        [Parameter(Mandatory)]$Failed,
        [Parameter(Mandatory)]$Config
    )
    if ($Failed.Engine -eq 'OneCore') {
        $sapi5Voices = @(Get-InstalledVoices | Where-Object { $_.Engine -eq 'Sapi5' })
        $match = Find-Voice -Voices $sapi5Voices -Language $Config.language
        if ($match) { return $match }
        return $script:DefaultSapi5Voice
    }
    if ($Failed.Name) { return $script:DefaultSapi5Voice }
    return $null
}

# Speaks $Text with the configured voice and rate. Processes take turns on the
# audio device through the speech lock; the voice is resolved after acquiring
# it, so it is never stale after a long wait. If no fallback is left, the
# engine's error is rethrown for the caller to log.
function Invoke-SpeechSynthesis {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)]$Config,
        [bool]$UsePronunciation = $true,
        [scriptblock]$Log = { param([string]$Message) }
    )

    $rate = ConvertTo-SafeRate -Value $Config.rate

    Invoke-WithNamedMutex -Name $script:SpeechLockName -TimeoutMs $script:SpeechLockTimeoutMs -Log $Log -Action {
        $voice = Resolve-SpeechTarget -Config $Config
        & $Log "voice: [$($voice.Name)] ($($voice.Engine))"
        try {
            Invoke-SpeechOnVoice -Voice $voice -Text $Text -Rate $rate -UsePronunciation $UsePronunciation -Log $Log
        } catch {
            & $Log "speech failed: $($_.Exception.Message)"
            $fallback = Get-FallbackVoice -Failed $voice -Config $Config
            if (-not $fallback) { throw }
            & $Log "retrying with [$($fallback.Name)] ($($fallback.Engine))"
            Invoke-SpeechOnVoice -Voice $fallback -Text $Text -Rate $rate -UsePronunciation $UsePronunciation -Log $Log
        }
    }
}
