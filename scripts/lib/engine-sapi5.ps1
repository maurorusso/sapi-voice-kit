# Classic SAPI5 engine (System.Speech): present on every Windows install, so it
# is the fallback when no OneCore voice exists for the language or OneCore fails.

# VoiceInfo of every enabled SAPI5 voice.
function Get-Sapi5Voices {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    try {
        return @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
    } finally {
        $synth.Dispose()
    }
}

# A PromptBuilder that reads $Text with the dictionary's pronunciation hints, or
# $null when no word has one (the caller then speaks the plain string). The
# builder must be given the voice's own culture; the parameterless constructor
# uses the machine's culture and mis-stresses unrelated words.
function Get-Sapi5Prompt {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][hashtable]$Dictionary,
        [System.Globalization.CultureInfo]$Culture
    )

    $segments = @(Split-PronunciationSegments -Text $Text -Dictionary $Dictionary)
    if (-not ($segments | Where-Object { $_.Ipa })) { return $null }

    $prompt = if ($Culture) { New-Object System.Speech.Synthesis.PromptBuilder($Culture) } else { New-Object System.Speech.Synthesis.PromptBuilder }
    foreach ($segment in $segments) {
        if ($segment.Ipa) { $prompt.AppendTextWithPronunciation($segment.Text, $segment.Ipa) }
        else { $prompt.AppendText($segment.Text) }
    }
    return $prompt
}

# $VoiceName empty means "System.Speech's default voice". $Rate is -10..10 and
# $Dictionary the pronunciation hints (empty for none).
function Invoke-Sapi5Speech {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$VoiceName,
        [Parameter(Mandatory)][int]$Rate,
        [Parameter(Mandatory)][hashtable]$Dictionary,
        [scriptblock]$Log = { param([string]$Message) }
    )

    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    try {
        if ($VoiceName) { $synth.SelectVoice($VoiceName) }
        $synth.Rate = $Rate
        & $Log "SAPI5 voice [$($synth.Voice.Name)], rate $($synth.Rate)"

        $prompt = Get-Sapi5Prompt -Text $Text -Dictionary $Dictionary -Culture $synth.Voice.Culture
        if ($prompt) { $synth.Speak($prompt) } else { $synth.Speak($Text) }
    } finally {
        $synth.Dispose()
    }
}
