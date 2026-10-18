# Text normalization: turns a written response into text that sounds right
# when a TTS voice reads it. Pure string-in/string-out functions; nothing here
# touches audio, disk, or config. The screen always keeps the original text.
#
# Spoken forms are Spanish ("punto", "el link de ...") because the plugin's
# default voice is Spanish.

# The text is whatever the model wrote, and a pathological input (a huge
# unbroken token, thousands of unclosed "[", thousands of long words that each
# cost a little) can keep the regexes busy for minutes and hold up the end of
# the turn. Three limits bound that:
#  - a whole cleanup (Get-CleanedText, ConvertTo-SpokenReferences) gets one time
#    budget; when it is spent the remaining steps are skipped and the text goes
#    on as it is;
#  - no single step may run longer than $RegexTimeout (nor than what is left of
#    the budget), and a step that exceeds it is skipped too. The regex engine only
#    looks at the clock now and then, and not at all inside a long atomic scan, nor
#    inside the PowerShell code of a match evaluator, so the steps that work word
#    by word (dotfiles, file names, paths, URLs) or row by row (tables) also run
#    in chunks with the budget checked between chunks ($ChunkSize; the steps for
#    folders and file names use the smaller $IdentifierChunkSize), and the
#    abbreviation step uses no evaluator at all;
#  - a run of ASCII characters with no space longer than $MaxWordLength is dropped
#    first of all, and once URLs are converted (a long URL is still spoken) any
#    such run longer than $MaxIdentifierLength is dropped too: a base64 blob or a
#    minified line cannot be followed read aloud, and the file-name steps cost
#    time quadratic in the length of a word. 300 is above the longest Windows
#    path (260). Only ASCII counts: Chinese, Japanese and Thai are written without
#    spaces, so a normal paragraph of them is one long "word" that must be kept.
$script:RegexTimeout = [TimeSpan]::FromSeconds(2)
$script:CleanupBudget = [TimeSpan]::FromSeconds(10)
$script:CleanupDeadline = $null
$script:MaxWordLength = 2000
$script:MaxIdentifierLength = 300
$script:ChunkSize = 5000
# The steps that read folders and file names restart their search at every position of
# a word, so their cost in a chunk grows with the square of the chunk; and a regex
# timeout restarts at each match, so it does not bound a chunk that keeps matching.
# Their chunks are smaller. A word is at most $MaxIdentifierLength, far below this.
$script:IdentifierChunkSize = 1000

# Runs $Action with the cleanup budget started, unless an enclosing call already
# started it (Get-CleanedText calls ConvertTo-SpokenReferences).
function Invoke-WithCleanupBudget {
    param([Parameter(Mandatory)][scriptblock]$Action)
    $startsBudget = $null -eq $script:CleanupDeadline
    if ($startsBudget) { $script:CleanupDeadline = [DateTime]::UtcNow + $script:CleanupBudget }
    try {
        & $Action
    } finally {
        if ($startsBudget) { $script:CleanupDeadline = $null }
    }
}

function Invoke-RegexReplace {
    param(
        [string]$Text,
        [string]$Pattern,
        $Replacement,
        [System.Text.RegularExpressions.RegexOptions]$Options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $timeout = $script:RegexTimeout
    if ($script:CleanupDeadline) {
        $left = $script:CleanupDeadline - [DateTime]::UtcNow
        if ($left -le [TimeSpan]::Zero) { return $Text }
        if ($left -lt $timeout) { $timeout = $left }
    }
    try {
        return [regex]::Replace($Text, $Pattern, $Replacement, $Options, $timeout)
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        return $Text
    }
}

# Invoke-RegexReplace for a step that is slow to find its next match rather than slow
# to make one (a fence opener scans the rest of the text for its closer, and gives up
# after a long scan only to match a shorter fence; "[](" or "![a](x " repeated with no ")"
# scans to the end of the run from each start): the regex timeout restarts at every
# match, so a text with thousands of such matches would never hit it. The budget is
# checked after each match, and what is left of the text goes on unchanged.
function Invoke-BudgetedRegexReplace {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replacement
    )
    $timeout = $script:RegexTimeout
    if ($script:CleanupDeadline) {
        $left = $script:CleanupDeadline - [DateTime]::UtcNow
        if ($left -le [TimeSpan]::Zero) { return $Text }
        if ($left -lt $timeout) { $timeout = $left }
    }
    $regex = New-Object System.Text.RegularExpressions.Regex($Pattern, [System.Text.RegularExpressions.RegexOptions]::None, $timeout)
    $result = New-Object System.Text.StringBuilder
    $copied = 0
    try {
        $match = $regex.Match($Text)
        while ($match.Success) {
            [void]$result.Append($Text, $copied, $match.Index - $copied)
            [void]$result.Append($match.Result($Replacement))
            $copied = $match.Index + $match.Length
            if ($script:CleanupDeadline -and [DateTime]::UtcNow -ge $script:CleanupDeadline) { break }
            $match = $match.NextMatch()
        }
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] { }
    [void]$result.Append($Text, $copied, $Text.Length - $copied)
    return $result.ToString()
}

# Invoke-RegexReplace over a text cut into chunks, for steps whose matches never
# span a cut, so the result is the same as in one piece. Chunks end after a
# whitespace character, or after one of $CutAt when it is given (a step that
# works on whole lines passes the newline).
function Invoke-ChunkedRegexReplace {
    param(
        [string]$Text,
        [string]$Pattern,
        $Replacement,
        [char[]]$CutAt = ([char[]]" `t`n"),
        [int]$ChunkSize = $script:ChunkSize
    )
    if ($Text.Length -le $ChunkSize) { return Invoke-RegexReplace -Text $Text -Pattern $Pattern -Replacement $Replacement }

    $result = New-Object System.Text.StringBuilder
    $start = 0
    while ($start -lt $Text.Length) {
        $end = [Math]::Min($start + $ChunkSize, $Text.Length)
        if ($end -lt $Text.Length) {
            $cut = $Text.LastIndexOfAny($CutAt, $end - 1, $end - $start)
            if ($cut -gt $start) { $end = $cut + 1 }
        }
        [void]$result.Append((Invoke-RegexReplace -Text $Text.Substring($start, $end - $start) -Pattern $Pattern -Replacement $Replacement))
        $start = $end
    }
    return $result.ToString()
}

function Limit-WordLength {
    param(
        [string]$Text,
        [int]$MaxLength = $script:MaxWordLength
    )
    return Invoke-RegexReplace -Text $Text -Pattern "(?<![\x21-\x7E])[\x21-\x7E]{$($MaxLength + 1),}" -Replacement ' '
}

# Extensions read as "name punto ext". Deliberately leaves out 'c', 'h' and
# 'go': they are ordinary short words far more often than extensions.
$script:KnownFileExtensions = @(
    'ps1', 'ps1xml', 'psm1', 'psd1', 'json', 'md', 'markdown', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx',
    'py', 'html', 'htm', 'css', 'scss', 'less', 'yml', 'yaml', 'txt', 'csv', 'tsv', 'xml', 'sh', 'bash',
    'cfg', 'ini', 'conf', 'log', 'env', 'lock', 'toml', 'sql', 'rb', 'rs', 'java', 'cpp',
    'hpp', 'php', 'vue', 'svelte', 'pdf', 'zip', 'exe', 'dll', 'bat', 'cmd', 'csproj', 'sln'
)

# The folders in front of a file name or a dotfile: names of at most 255 characters, each
# followed by a separator (a name may be empty). A name has none of: whitespace, separators,
# "=", ( ) [ ] { } < > ; , | & " ' backtick, typographic punctuation (U+2010-2027) and guillemets, text
# written without spaces (CJK, Thai): those set a path off from the words around it. A whole
# "[id]" or "(group)" is a name too. A dot that starts a known extension ends the name before
# a separator and one last segment ("README.md/other.md"), before another "name.ext/" (a list:
# "Node.js/Express.js/"), and before anything but a name character or a separator.
$script:ExtensionPattern = ($script:KnownFileExtensions | ForEach-Object { [regex]::Escape($_) }) -join '|'
$script:PathFolders = '(?:(?>(?:(?<=^|[\s\\/])(?:\[+[^\s\[\]\\/]*\]+|\([^\s()\\/]*\))(?=[\\/])|[^\s.\\/=()\[\]{}<>;,|&"''`\u2010-\u2027\u00AB\u00BB\u0E00-\u0E7F\u1100-\u11FF\u3000-\u318F\u3400-\u9FFF\uAC00-\uD7AF\uFF00-\uFFEF]|(?!\.(?:' + $script:ExtensionPattern + ')(?![A-Za-z0-9_.\\/-]))(?!\.(?:' + $script:ExtensionPattern + ')[\\/](?:[^\s\\/]*(?:\s|$)|[^\s\\/]*\.(?:' + $script:ExtensionPattern + ')[\\/]))\.){0,255})[\\/])*'
# After a drive letter the path starts there: names in any script, and with "=", "&", brackets,
# braces, "'" or a parenthesised group, are folders. CJK punctuation, fullwidth forms, typographic
# punctuation, guillemets, ":" and the glue characters ( ) < > ; , | " and backtick still end one.
$script:DrivePathFolders = $script:PathFolders.Replace('(?<=^|[\s\\/])(?:\[+[^\s\[\]\\/]*\]+|\([^\s()\\/]*\))(?=[\\/])|', '\([^\s()\\/]*\)|').Replace('[^\s.\\/=()\[\]{}<>;,|&"''`', '[^\s.\\/()<>;,|"`').Replace('\u0E00-\u0E7F\u1100-\u11FF\u3000-\u318F\u3400-\u9FFF\uAC00-\uD7AF\uFF00-\uFFEF', '\u3000-\u303F\uFF00-\uFFEF:')

# Abbreviations read as words instead of being spelled out. Spanish entries
# follow the RAE list; "e.g."/"i.e." are expanded to their Spanish meaning.
# Every pattern ends in a negative lookahead so "etc" never matches the start of
# "etcetera" or the start of a path such as /etc/hosts, and "etc" is not read as an
# abbreviation when it is the name of a file ("etc.txt"). "vs" requires its dot,
# because "VS Code" is a product name. "min."/"max." are left out: ambiguous.
$script:SpokenAbbreviations = [ordered]@{
    'etc\.?(?![\w/\\])(?! punto )' = 'etcétera'
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

# Only "etc." regularly ends a sentence, so only its dot is kept when a capital
# letter follows. After the others the dot would read as a sentence break
# ("Rust versus. Go"), and a title is always followed by a name in the same sentence.
$script:AbbreviationsThatCanEndASentence = @('etc\.?(?![\w/\\])(?! punto )')

# ".env" -> "punto env", ".mcp.json" -> "punto mcp punto json", "~/.bashrc" ->
# "punto bashrc" (the leading folders are dropped, as for any file). The match
# must start at the beginning of a word (start, whitespace, "(", "*" or a
# backtick), which keeps it from ever matching an ordinary sentence-ending
# period. A name followed by a path separator is a dot folder
# (".github/workflows/x.yml"), not a dotfile: it is left for
# ConvertTo-SpokenFileNames. Runs before that function, which needs a name in
# front of the dot.
function ConvertTo-SpokenDotfiles {
    param([string]$Text)
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return 'punto ' + ($m.Groups[1].Value -replace '\.', ' punto ')
    }
    return Invoke-ChunkedRegexReplace -Text $Text -Pattern ('(?<=^|[\s(*`])' + $script:PathFolders + '\.((?>[\w-]+(?:\.[\w-]+)*))(?![\w\\/-])') -Replacement $evaluator -ChunkSize $script:IdentifierChunkSize
}

# "scripts/common.ps1" and "C:\dir\common.ps1" -> "common punto ps1": the
# leading folders are dropped, since reading every one is not useful.
function ConvertTo-SpokenFileNames {
    param([string]$Text)
    $extPattern = $script:ExtensionPattern
    # "MongoDB/Express/React/Node.js" is a list of technologies, not a path: capitalized
    # names in front of a capitalized ".js" name are kept instead of being dropped as
    # folders. A path such as "Docs/Guide/main.js" has a lowercase file name and is read
    # as a path. A list wrapped in bold keeps its opening mark: otherwise the folder prefix would
    # start at it and swallow the names.
    $capitalizedList = '(?<list>\**(?-i:(?:[A-Z][A-Za-z0-9]*/)+)(?=(?-i:[A-Z])[\w-]*\.js\b))'
    return Invoke-ChunkedRegexReplace -Text $Text -Pattern "(?:(?<![A-Za-z0-9_/\\])[A-Za-z]:[\\/]$($script:DrivePathFolders)|(?<![\w\\/-])(?!(?<=\.)(?:$extPattern)[\\/])(?:$capitalizedList|$($script:PathFolders)))([\w-]+)\.($extPattern)\b" -Replacement '${list}$1 punto $2' -ChunkSize $script:IdentifierChunkSize
}

# A drive-letter path with no recognized extension ("C:\Projects\App") -> its
# last segment. A drive letter is a single letter that does not follow another
# letter, a digit, an underscore or a separator, so "data:/app", a PATH list and "file:///C:/x"
# are left alone. A final
# separator and closing punctuation after the path ("(C:\data\)", "C:\data\.")
# are not part of the last segment.
function ConvertTo-SpokenPaths {
    param([string]$Text)
    return Invoke-ChunkedRegexReplace -Text $Text -Pattern ('(?<![A-Za-z0-9_/\\])[A-Za-z]:[\\/]' + $script:DrivePathFolders + '(?=[^\s\\/`''"),;:\u3000-\u303F\uFF00-\uFFEF]*\w)([^\s\\/`''"),;:\u3000-\u303F\uFF00-\uFFEF]+)[\\/]?') -Replacement '$1' -ChunkSize $script:IdentifierChunkSize
}

# Raw URLs are not read: "https://" starts with ":/", which some voices say as
# an emoticon. A URL becomes "el link de <site>", using the second-to-last
# label of the host (docs.github.com -> github; multi-part TLDs like .co.uk
# are not handled). A URL is made of ASCII characters and Latin letters ("ñ"), so
# text glued to it (Chinese, an em dash) stays. The port and any user:password are dropped, an IP address
# (v4 or v6) has no site name, and punctuation right after the URL ("ver
# https://x.com/a.") stays in the text so the sentence still ends.
function ConvertTo-SpokenUrls {
    param([string]$Text)
    $trailing = [char[]]'.,;:!?)]''*'
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $core = $m.Value.TrimEnd($trailing)
        $tail = $m.Value.Substring($core.Length)
        if ($tail.StartsWith(']') -and $core -match '^https?://(?:[^/\s@?#]*@)?\[[0-9a-f:.]*$') { $core += ']'; $tail = $tail.Substring(1) }
        $found = [regex]::Match($core, '^https?://(?:[^/\s@?#]*@)?(?:www\.)?(\[[0-9a-f:.]+\]|(?:[\w-]+\.)*[\w-]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $script:RegexTimeout)
        if (-not $found.Success) { return $m.Value }
        $siteHost = $found.Groups[1].Value
        if ($siteHost.StartsWith('[') -or $siteHost -match '^\d+(\.\d+){3}$') {
            $brand = 'una dirección IP'
        } else {
            $labels = $siteHost -split '\.'
            $brand = if ($labels.Count -ge 2) { $labels[$labels.Count - 2] } else { $labels[0] }
        }
        return "el link de $brand$tail"
    }
    return Invoke-ChunkedRegexReplace -Text $Text -Pattern 'https?://(?:[\x21\x23-\x3B\x3D\x3F-\x5F\x61-\x7B\x7D-\x7E]|[\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u024F\u1E00-\u1EFF])+' -Replacement $evaluator
}

# Replaces each abbreviation with its word. When the abbreviation's own dot also
# closes the sentence (followed by an uppercase letter or the end of the text),
# the period is kept so the sentence boundary survives.
function ConvertTo-SpokenAbbreviations {
    param([string]$Text)
    foreach ($abbreviation in $script:SpokenAbbreviations.GetEnumerator()) {
        $pattern = '(?<![/\\.])\b' + $abbreviation.Name
        $word = $abbreviation.Value
        if ($script:AbbreviationsThatCanEndASentence -contains $abbreviation.Name) {
            # First the occurrences whose dot ends a sentence (a capital letter or the end
            # of the text follows; the capital is matched case-sensitively), then the rest.
            $endsSentence = $pattern + '(?<=\.)(?=\s*(?:$|(?-i:[A-ZÁÉÍÓÚÑ¿¡])))'
            $Text = Invoke-RegexReplace -Text $Text -Pattern $endsSentence -Replacement "$word."
        }
        $Text = Invoke-RegexReplace -Text $Text -Pattern $pattern -Replacement $word
    }
    return $Text
}

# The steps every spoken text goes through: dotfiles first (the file-name regex
# needs a name before the dot), then file names, bare paths and abbreviations.
function ConvertTo-SpokenIdentifiers {
    param([string]$Text)
    $Text = ConvertTo-SpokenDotfiles -Text $Text
    $Text = ConvertTo-SpokenFileNames -Text $Text
    $Text = ConvertTo-SpokenPaths -Text $Text
    return ConvertTo-SpokenAbbreviations -Text $Text
}

# Links and names, in the order that keeps a URL whole: URLs go first, or the
# file-name step would turn the end of "https://x.com/README.md" into "README
# punto md". Used by Get-CleanedText and by say.ps1.
function ConvertTo-SpokenReferences {
    param([string]$Text)
    return Invoke-WithCleanupBudget { Convert-ReferencesToSpeech -Text $Text }
}

function Convert-ReferencesToSpeech {
    param([string]$Text)
    $Text = ConvertTo-SpokenUrls -Text (Limit-WordLength -Text $Text)
    return ConvertTo-SpokenIdentifiers -Text (Limit-WordLength -Text $Text -MaxLength $script:MaxIdentifierLength)
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
    return Invoke-RegexReplace -Text $Text -Pattern "(?m)[^\s.!?:;,$emDash$enDash$ellipsis\u3002\uFF01\uFF1F\uFF1A\uFF1B\uFF0C\u3001](?=[ \t]*\r?\n)" -Replacement '$&.' -Options ([System.Text.RegularExpressions.RegexOptions]::None)
}

# Natural-mode text: markdown removed so symbols are not read aloud. Only
# formatting is cleaned; the wording is never rewritten. Used by the Stop hook
# and by the /sapi-voice-kit:test sentence, so both run the same pipeline.
function Get-CleanedText {
    param([string]$Text)
    return Invoke-WithCleanupBudget { Convert-MarkdownToSpeech -Text $Text }
}

# HTML comments, but not the ones written inside inline code. An opener with no closer after it
# scans to the end of the text, and the inline-code alternative matches often, which restarts the
# regex timeout: so only the part up to the last closer is searched. Every opener in it has a
# closer, so the cost stays linear. A code span still open at that point ends at the next
# backtick of its line, so that backtick is searched too.
function Remove-HtmlComments {
    param([string]$Text)
    $lastCloser = $Text.LastIndexOf('-->', [StringComparison]::Ordinal)
    if ($lastCloser -lt 0) { return $Text }
    $end = $lastCloser + 3
    $nextBacktick = $Text.IndexOf([char]96, $end)
    $lineEnd = $Text.IndexOf([char]10, $end)
    if ($nextBacktick -ge 0 -and ($lineEnd -lt 0 -or $nextBacktick -lt $lineEnd)) { $end = $nextBacktick + 1 }
    $searched = Invoke-RegexReplace $Text.Substring(0, $end) '(`[^`\n]*`)|(?s)<!--.*?-->' '$1'
    return $searched + $Text.Substring($end)
}

function Convert-MarkdownToSpeech {
    param([string]$Text)

    $emDash = [char]0x2014
    $enDash = [char]0x2013
    $ellipsis = [char]0x2026

    $tableRow = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return ($m.Value.Trim().Trim('|') -split '(?<!\\)\|' | ForEach-Object { $_.Trim().Replace('\|', '|') }) -join ', '
    }

    $Text = Limit-WordLength -Text $Text
    # A fence is closed by a line that repeats its marker (or a longer one); a backtick fence cannot
    # have a backtick in its info string, so "```npm i``` text" is an inline span, the second alternative.
    # The opener may follow a list marker and quote markers ("1. ```", "> - ```"); the closer carries
    # markers only if the opener was quoted. A fence opened after a list marker ends with its list item.
    $Text = Invoke-BudgetedRegexReplace $Text '(?ms)^[ \t]*(?<listed>(?:[-*+]|\d{1,9}[.)])[ \t]+)?(?<quoted>(?:>[ \t]*)+)?(?<listed>(?:[-*+]|\d{1,9}[.)])[ \t]+)?(?:(?<fence>`{3,})[^`\n]*|(?<fence>~{3,})[^\n]*)\n(?(listed)(?:(?!\n[^\s>]).)*?|.*?)^[ \t]*(?(quoted)(?:>[ \t]*)*)\k<fence>[`~]*[ \t]*\r?$|(?<!(?<![^\s(\[{"\u00BF\u00A1\u00AB])`{1,2} ?)(?<!`)```(?! ?`)(?:(?=[^\S\r\n]*(?:[\w{][^\s`]*)?[^\S\r\n]*\r?\n)(?:(?!\r?\n[ \t]*(?:>[ \t]*)*(?:\r?\n|(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)?(?:`{3,}[^`\n]*[^`\s]|~~~))).)*?|[^\r\n]*?)```' ' code block omitted. '
    $Text = Remove-HtmlComments -Text $Text
    $Text = Invoke-BudgetedRegexReplace $Text '(`[^`\n]*`)|!\[([^\[\]]*)\]\([^\)]+\)' '$1$2'   # ![alt](image), with or without alt text, but not inside inline code
    # [text](link) -> text. A link with no text is removed too, but only when its target
    # has no whitespace: "[](int x) { }" is a C++ lambda, not a link.
    $Text = Invoke-BudgetedRegexReplace $Text '(`[^`\n]*`)|(?<![A-Za-z0-9\u00C0-\u024F]|\]|[A-Za-z0-9\u00C0-\u024F]_{1,2})\[([^\[\]]+)\]\([^\)]+\)|(?<![A-Za-z0-9\u00C0-\u024F]|\]|[A-Za-z0-9\u00C0-\u024F]_{1,2})\[\]\([^\s)]+\)' '$1$2'
    $Text = ConvertTo-SpokenReferences -Text $Text                      # bare URLs, file names, paths, abbreviations
    # Quote markers go first, at any indent and nested, so quoted lists, tables and headings are cleaned like any other.
    $Text = Invoke-RegexReplace $Text '(?m)^(?:\s{0,3}|[ \t]+)>\s?(?:[ \t]*>[ \t]?)*' ''
    $Text = Invoke-RegexReplace $Text '(?m)^(?=[ \t:|-]*-)(?=[^|\n]*\|)[ \t:|-]+\r?$\n?' ''   # table separator rows
    $Text = Invoke-ChunkedRegexReplace -Text $Text -Pattern '(?m)^[ \t]*\|.*$' -Replacement $tableRow -CutAt ([char[]]"`n")   # table rows: cells joined by commas
    # A quote written right after a list marker ("- > text") loses its marker here: the quote step above only sees line starts.
    $Text = Invoke-RegexReplace $Text '(?m)^[ \t]*[-*+][ \t]+(?:>(?!=)[ \t]?(?:[ \t]*>[ \t]?)*)?' ''           # bullets, at any depth
    $Text = Invoke-RegexReplace $Text '(?m)^[ \t]*\d+[.)][ \t]+(?:>(?!=)[ \t]?(?:[ \t]*>[ \t]?)*)?' ''           # numbered lists ("1." or "1)"), at any depth
    $Text = Invoke-RegexReplace $Text '(?m)^\s{0,3}#{1,6}\s*' ''          # headings
    $Text = Invoke-RegexReplace $Text '(?m)^[ \t]*[-*_]{3,}[ \t]*\r?$' ' '   # horizontal rules
    $Text = Invoke-RegexReplace $Text '(?<=\d)_(?=\d)' ''                 # 1_000_000 -> 1000000
    $Text = Invoke-RegexReplace $Text '(?<=\w)_(?=\w)' ' '                # read_aloud -> read aloud
    $Text = Invoke-RegexReplace $Text '[*_`]|(?<!\w)#' ''                  # emphasis and code marks; the # of C# stays
    $Text = Add-ImplicitLineEndPeriods -Text $Text
    # A dash match starts only at the beginning of a run of whitespace: otherwise every
    # offset inside a long run is tried again, which is quadratic. The second alternative
    # covers a dash that follows whitespace the previous dash already consumed.
    $Text = Invoke-RegexReplace $Text "(?:(?<!\s)\s*|(?<=\s))$emDash\s*" ', '
    $Text = Invoke-RegexReplace $Text "(?:(?<!\s)\s*|(?<=\s))$enDash\s*" ', '
    $Text = $Text.Replace([string]$ellipsis, '...')
    return $Text.Trim()
}
