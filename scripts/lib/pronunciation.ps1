# Pronunciation hints. The voice reads the whole text, but words listed in the
# dictionary for its language (pronunciations/<code>.psd1) get an explicit IPA
# pronunciation, so "git" is said the English way by a Spanish voice instead of
# being read with Spanish rules. Words the voice stresses wrongly even so are
# respelled (respellings/<code>.psd1).
# Switching to a second, English voice for those words was tried and rejected:
# it sounds like two people talking and doubles the speaking time.

$script:LanguageTables = @{}

# The table in <Folder>/<code>.psd1 for a voice's language ("es-MX" -> es.psd1),
# or an empty one when that language has none: data written for one language
# would be wrong in another. Each file is read once per process.
function Import-LanguageTable {
    param(
        [Parameter(Mandatory)][string]$Folder,
        [string]$Language
    )

    $code = "$Language".Split('-')[0].ToLowerInvariant()
    # The code comes from the voice or from config.json and becomes part of a path.
    if ($code -cnotmatch '^[a-z]{2,3}$') { return @{} }

    $key = "$Folder/$code"
    if (-not $script:LanguageTables.ContainsKey($key)) {
        $path = Join-Path $PSScriptRoot "$Folder\$code.psd1"
        $script:LanguageTables[$key] = if (Test-Path $path) { Import-PowerShellDataFile -Path $path } else { @{} }
    }
    return $script:LanguageTables[$key]
}

# word -> IPA, for the words a voice of this language says wrongly.
function Get-PronunciationDictionary {
    param([string]$Language)
    return Import-LanguageTable -Folder 'pronunciations' -Language $Language
}

# word -> respelling, for the words whose stress the voice gets wrong even with IPA.
function Get-Respellings {
    param([string]$Language)
    return Import-LanguageTable -Folder 'respellings' -Language $Language
}

# $Text with each whole word that has a respelling replaced by it, keeping the
# capitalization ("Natural" -> "Naturál", "NATURAL" -> "NATURÁL").
function ConvertTo-RespelledText {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][hashtable]$Respellings
    )

    if ($Respellings.Count -eq 0) { return $Text }
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $respelling = $Respellings[$m.Value.ToLowerInvariant()]
        if (-not $respelling) { return $m.Value }
        if ($m.Value.Length -gt 1 -and $m.Value -ceq $m.Value.ToUpperInvariant()) { return $respelling.ToUpperInvariant() }
        if ($m.Value[0] -ceq [char]::ToUpperInvariant($m.Value[0])) { return $respelling.Substring(0, 1).ToUpperInvariant() + $respelling.Substring(1) }
        return $respelling
    }
    return [regex]::Replace($Text, '\w+', $evaluator)
}

# Splits $Text into consecutive segments of { Text; Ipa }. Ipa is the dictionary
# pronunciation for a word that has one (case-insensitive whole-word match) and
# $null for everything else. Concatenating every Text gives back the input.
# Dictionary keys must be single words, because matching is word by word.
function Split-PronunciationSegments {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][hashtable]$Dictionary
    )

    $segments = New-Object System.Collections.Generic.List[object]
    $position = 0
    foreach ($word in [regex]::Matches($Text, '\w+')) {
        $key = $word.Value.ToLowerInvariant()
        if (-not $Dictionary.ContainsKey($key)) { continue }
        if ($word.Index -gt $position) {
            $segments.Add([pscustomobject]@{ Text = $Text.Substring($position, $word.Index - $position); Ipa = $null })
        }
        $segments.Add([pscustomobject]@{ Text = $word.Value; Ipa = $Dictionary[$key] })
        $position = $word.Index + $word.Length
    }
    if ($position -lt $Text.Length) {
        $segments.Add([pscustomobject]@{ Text = $Text.Substring($position); Ipa = $null })
    }
    return $segments.ToArray()
}
