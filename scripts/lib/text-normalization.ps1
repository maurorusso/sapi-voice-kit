# Text normalization: turns a written response into text that sounds right
# when a TTS voice reads it. Pure string-in/string-out functions; nothing here
# touches audio, disk, or config. The screen always keeps the original text.
#
# Spoken forms are Spanish ("punto", "el link de ...") because the plugin's
# default voice is Spanish.

# Extensions read as "name punto ext". Deliberately leaves out 'c', 'h' and
# 'go': they are ordinary short words far more often than extensions.
$script:KnownFileExtensions = @(
    'ps1', 'ps1xml', 'psm1', 'psd1', 'json', 'md', 'markdown', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx',
    'py', 'html', 'htm', 'css', 'scss', 'less', 'yml', 'yaml', 'txt', 'csv', 'tsv', 'xml', 'sh', 'bash',
    'cfg', 'ini', 'conf', 'log', 'env', 'lock', 'toml', 'sql', 'rb', 'rs', 'java', 'cpp',
    'hpp', 'php', 'vue', 'svelte', 'pdf', 'zip', 'exe', 'dll', 'bat', 'cmd', 'csproj', 'sln'
)

# Abbreviations read as words instead of being spelled out. Spanish entries
# follow the RAE list; "e.g."/"i.e." are expanded to their Spanish meaning.
# Ordered so "dra." is tried before "dr.". Every pattern ends in (?!\w) so
# "etc" never matches the start of "etcetera". "vs" requires its dot, because
# "VS Code" is a product name. "min."/"max." are left out: ambiguous.
$script:SpokenAbbreviations = [ordered]@{
    'etc\.?(?!\w)'        = 'etcétera'
    'p\.\s?ej\.(?!\w)'    = 'por ejemplo'
    'e\.\s?g\.(?!\w)'     = 'por ejemplo'
    'i\.\s?e\.(?!\w)'     = 'es decir'
    'aprox\.(?!\w)'       = 'aproximadamente'
    'approx\.(?!\w)'      = 'aproximadamente'
    'vs\.(?!\w)'          = 'versus'
    'n[uú]m\.(?!\w)'      = 'número'
    'p[aá]g\.(?!\w)'      = 'página'
    'dra\.(?!\w)'         = 'doctora'
    'dr\.(?!\w)'          = 'doctor'
    'sra\.(?!\w)'         = 'señora'
    'sr\.(?!\w)'          = 'señor'
    'uds\.(?!\w)'         = 'ustedes'
    'ud\.(?!\w)'          = 'usted'
    'depto\.(?!\w)'       = 'departamento'
    'tel\.(?!\w)'         = 'teléfono'
}

# Titles are always followed by a name in the same sentence, so their dot never
# ends a sentence and must not be kept.
$script:AbbreviationsNeverPreservePeriod = @('dra\.(?!\w)', 'dr\.(?!\w)', 'sra\.(?!\w)', 'sr\.(?!\w)')

# ".env" -> "punto env", ".mcp.json" -> "punto mcp punto json". The lookbehind
# (start, whitespace, "(", a path separator or a backtick) keeps it from ever
# matching an ordinary sentence-ending period. Runs before
# ConvertTo-SpokenFileNames, which needs a name in front of the dot.
function ConvertTo-SpokenDotfiles {
    param([string]$Text)
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return 'punto ' + ($m.Groups[1].Value -replace '\.', ' punto ')
    }
    return [regex]::Replace($Text, '(?<=^|[\s(\\/`])\.([\w-]+(?:\.[\w-]+)*)\b', $evaluator)
}

# "scripts/common.ps1" and "C:\dir\common.ps1" -> "common punto ps1": the
# leading folders are dropped, since reading every one is not useful.
function ConvertTo-SpokenFileNames {
    param([string]$Text)
    $extPattern = ($script:KnownFileExtensions | ForEach-Object { [regex]::Escape($_) }) -join '|'
    return [regex]::Replace($Text, "(?:[^\s\\/]+[\\/])*([\w-]+)\.($extPattern)\b", '$1 punto $2', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

# A drive-letter path with no recognized extension ("C:\Projects\App") -> its
# last segment. "C:\" never appears in ordinary prose, so this is safe.
function ConvertTo-SpokenPaths {
    param([string]$Text)
    return [regex]::Replace($Text, '[A-Za-z]:[\\/](?:[^\s\\/]+[\\/])*([^\s\\/]+)', '$1')
}

# Raw URLs are not read: "https://" starts with ":/", which some voices say as
# an emoticon. A URL becomes "el link de <site>", using the second-to-last
# label of the host (docs.github.com -> github; multi-part TLDs like .co.uk
# are not handled).
function ConvertTo-SpokenUrls {
    param([string]$Text)
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $parts = $m.Groups[1].Value -split '\.'
        $brand = if ($parts.Count -ge 2) { $parts[$parts.Count - 2] } else { $parts[0] }
        return "el link de $brand"
    }
    return [regex]::Replace($Text, 'https?://(?:www\.)?([^/\s]+)\S*', $evaluator)
}

# Replaces each abbreviation with its word. When the abbreviation's own dot also
# closes the sentence (followed by an uppercase letter or the end of the text),
# the period is kept so the sentence boundary survives.
function ConvertTo-SpokenAbbreviations {
    param([string]$Text)
    foreach ($pattern in $script:SpokenAbbreviations.Keys) {
        $word = $script:SpokenAbbreviations[$pattern]
        $preservePeriod = $script:AbbreviationsNeverPreservePeriod -notcontains $pattern
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            if ($preservePeriod -and $m.Value.EndsWith('.')) {
                $tail = $Text.Substring($m.Index + $m.Length)
                if ($tail -cmatch '^\s*($|[A-ZÁÉÍÓÚÑ¿¡])') { return "$word." }
            }
            return $word
        }
        $Text = [regex]::Replace($Text, "\b$pattern", $evaluator, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    return $Text
}

# The steps every spoken text goes through: dotfiles first (the file-name regex
# needs a name before the dot), then file names, bare paths and abbreviations.
# URLs are handled separately because their position relative to markdown links
# matters (see Get-CleanedText).
function ConvertTo-SpokenIdentifiers {
    param([string]$Text)
    $Text = ConvertTo-SpokenDotfiles -Text $Text
    $Text = ConvertTo-SpokenFileNames -Text $Text
    $Text = ConvertTo-SpokenPaths -Text $Text
    return ConvertTo-SpokenAbbreviations -Text $Text
}

# A line break with no punctuation reads as one run-on sentence, so such a line
# gets a period. Lines already ending in . ! ? : ; , or an ellipsis are left
# alone, and so are dashes: a dash implies continuation, and a period after one
# would survive the dash-to-comma step in Get-CleanedText as ", .".
function Add-ImplicitLineEndPeriods {
    param([string]$Text)
    $emDash = [char]0x2014
    $enDash = [char]0x2013
    $ellipsis = [char]0x2026
    return [regex]::Replace($Text, "(?m)[^\s.!?:;,$emDash$enDash$ellipsis](?=[ \t]*\r?\n)", '$&.')
}

# Natural-mode text: markdown removed so symbols are not read aloud. Only
# formatting is cleaned; the wording is never rewritten. Used by the Stop hook
# and by the /sapi-voice-kit:test sentence, so both run the same pipeline.
function Get-CleanedText {
    param([string]$Text)

    $emDash = [char]0x2014
    $enDash = [char]0x2013
    $ellipsis = [char]0x2026

    $Text = ConvertTo-SpokenIdentifiers -Text $Text

    $Text = $Text -replace '(?s)```.*?```', ' code block omitted. '
    $Text = $Text -replace '(?s)<!--.*?-->', ''
    $Text = $Text -replace '\[([^\]]+)\]\([^\)]+\)', '$1'          # [text](link) -> text
    $Text = ConvertTo-SpokenUrls -Text $Text                        # bare URLs, after markdown links
    $Text = $Text -replace '(?m)^\s{0,3}[-*+]\s+', ''               # bullets
    $Text = $Text -replace '(?m)^\s{0,3}\d+\.\s+', ''               # numbered lists
    $Text = $Text -replace '(?m)^\s{0,3}#{1,6}\s*', ''              # headings
    $Text = $Text -replace '(?m)^\s{0,3}>\s?', ''                   # quotes
    $Text = $Text -replace '(?m)^\s*[-*_]{3,}\s*$', ' '             # horizontal rules
    $Text = Add-ImplicitLineEndPeriods -Text $Text
    $Text = $Text -replace "\s*$emDash\s*", ', '
    $Text = $Text -replace "\s*$enDash\s*", ', '
    $Text = $Text.Replace([string]$ellipsis, '...')
    $Text = $Text -replace '[*_#`]', ''
    return $Text.Trim()
}
