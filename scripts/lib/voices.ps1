# Which voice speaks. Both engines' voices are described by one record,
#   { Engine; Name; Language; Gender; Native }
# where Native is what the engine needs to select the voice, so choosing a voice
# does not depend on which engine owns it.

# What System.Speech does when no voice is named. Used as the last resort.
$script:DefaultSapi5Voice = [pscustomobject]@{ Engine = 'Sapi5'; Name = $null; Language = $null; Gender = $null; Native = $null }

# Every installed voice, OneCore first: list order is the preference order, so a
# modern voice wins automatic selection when one exists for the language.
function Get-InstalledVoices {
    $voices = New-Object System.Collections.Generic.List[object]
    foreach ($voice in (Get-OneCoreVoices)) {
        $voices.Add([pscustomobject]@{ Engine = 'OneCore'; Name = $voice.DisplayName; Language = $voice.Language; Gender = "$($voice.Gender)"; Native = $voice })
    }
    foreach ($voice in (Get-Sapi5Voices)) {
        $voices.Add([pscustomobject]@{ Engine = 'Sapi5'; Name = $voice.Name; Language = $voice.Culture.Name; Gender = "$($voice.Gender)"; Native = $voice.Name })
    }
    return $voices.ToArray()
}

# The voice with exactly this name, else the best one for the language (the
# system language when none is given), else $null. Engines are tried in list
# order, and within an engine an exact match ("es-ES") beats any "es-*", so a
# modern voice for a close language wins over a classic one for the exact one.
function Find-Voice {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Voices,
        [string]$Name,
        [string]$Language
    )

    if ($Name) {
        $named = $Voices | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($named) { return $named }
    }
    if (-not $Language) { $Language = (Get-Culture).Name }
    $prefix = $Language.Split('-')[0]
    foreach ($engine in @($Voices | ForEach-Object { $_.Engine } | Select-Object -Unique)) {
        $ofEngine = @($Voices | Where-Object { $_.Engine -eq $engine })
        $exact = $ofEngine | Where-Object { $_.Language -eq $Language } | Select-Object -First 1
        if ($exact) { return $exact }
        $close = $ofEngine | Where-Object { $_.Language.Split('-')[0] -eq $prefix } | Select-Object -First 1
        if ($close) { return $close }
    }
    return $null
}

# The configured voice (config voiceName/language), else the best match for the
# system language, else SAPI5's default voice. A named voice that is no longer
# installed falls back to automatic selection.
function Resolve-SpeechTarget {
    param(
        [Parameter(Mandatory)]$Config,
        [object[]]$Voices = @(Get-InstalledVoices)
    )
    $voice = Find-Voice -Voices $Voices -Name $Config.voiceName -Language $Config.language
    if ($voice) { return $voice }
    return $script:DefaultSapi5Voice
}
