# Pronunciation hints for technical terms. The voice reads the whole text, but
# words listed in the dictionary for its language (pronunciations/<code>.psd1)
# get an explicit IPA pronunciation, so "git" is said the English way by a
# Spanish voice instead of being read with Spanish rules.
# Switching to a second, English voice for those words was tried and rejected:
# it sounds like two people talking and doubles the speaking time.

$script:PronunciationDictionaries = @{}

# The dictionary for a voice's language ("es-MX" -> es.psd1), or an empty one
# when that language has none: hints written for one language would be wrong in
# another. Each file is read once per process.
function Get-PronunciationDictionary {
    param([string]$Language)

    $code = "$Language".Split('-')[0].ToLowerInvariant()
    # The code comes from the voice or from config.json and becomes part of a path.
    if ($code -cnotmatch '^[a-z]{2,3}$') { return @{} }

    if (-not $script:PronunciationDictionaries.ContainsKey($code)) {
        $path = Join-Path $PSScriptRoot "pronunciations\$code.psd1"
        $script:PronunciationDictionaries[$code] = if (Test-Path $path) { Import-PowerShellDataFile -Path $path } else { @{} }
    }
    return $script:PronunciationDictionaries[$code]
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
