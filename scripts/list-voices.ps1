# Lists the speech-synthesis voices installed on Windows (to pick one with /sapi-voice-kit:voice).

Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer

$synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object {
    [PSCustomObject]@{
        Name     = $_.VoiceInfo.Name
        Language = $_.VoiceInfo.Culture.Name
        Gender   = $_.VoiceInfo.Gender
    }
} | Format-Table -AutoSize
