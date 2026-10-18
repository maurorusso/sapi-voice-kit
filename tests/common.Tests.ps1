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
# The logger limits as the library defines them, so tests that lower them can restore the real values.
$script:DefaultLogMaxBytes = $script:LogMaxBytes
$script:DefaultLogKeepLines = $script:LogKeepLines

# Points the plugin's data folder at a throwaway directory for one test.
function Use-FakeDataDir {
    $script:originalDataDir = $env:SAPI_VOICE_DATA_DIR
    $script:originalNamespace = $env:SAPI_VOICE_NAMESPACE
    $script:fakeDataDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sapi-voice-kit-test-' + [Guid]::NewGuid().ToString('N'))
    $env:SAPI_VOICE_DATA_DIR = $script:fakeDataDir
    Remove-Item Env:\SAPI_VOICE_NAMESPACE -ErrorAction SilentlyContinue
}

function Remove-FakeDataDir {
    if ($script:originalDataDir) { $env:SAPI_VOICE_DATA_DIR = $script:originalDataDir } else { Remove-Item Env:\SAPI_VOICE_DATA_DIR -ErrorAction SilentlyContinue }
    if ($script:originalNamespace) { $env:SAPI_VOICE_NAMESPACE = $script:originalNamespace }
    Remove-Item -Path $script:fakeDataDir -Recurse -Force -ErrorAction SilentlyContinue
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
    It 'does not take a word ending in a letter followed by :/ for a drive' {
        ConvertTo-SpokenPaths -Text 'docker run -v data:/app/data nginx' | Should Be 'docker run -v data:/app/data nginx'
        ConvertTo-SpokenPaths -Text 'export PATH=/usr/local/bin:/usr/bin:/bin' | Should Be 'export PATH=/usr/local/bin:/usr/bin:/bin'
        ConvertTo-SpokenPaths -Text 'scp host:/var/log/x.log .' | Should Be 'scp host:/var/log/x.log .'
    }
    It 'does not take a letter that follows a separator for a drive' {
        ConvertTo-SpokenPaths -Text 'PATH=/a:/b' | Should Be 'PATH=/a:/b'
        ConvertTo-SpokenPaths -Text 'file:///C:/Users/x/doc.txt' | Should Be 'file:///C:/Users/x/doc.txt'
    }
    It 'keeps the folder name when a folder path ends in a separator and then a period or a question mark' {
        ConvertTo-SpokenPaths -Text 'Ver C:\Users\x\datos\.' | Should Be 'Ver datos.'
        ConvertTo-SpokenPaths -Text '¿Es C:\Users\x\datos\?' | Should Be '¿Es datos?'
    }
    It 'keeps the closing punctuation after a folder path that ends in a separator' {
        ConvertTo-SpokenPaths -Text 'Guardado en `C:\Users\x\datos\` listo.' | Should Be 'Guardado en `datos` listo.'
        ConvertTo-SpokenPaths -Text 'Carpeta (C:\Users\x\datos\) lista.' | Should Be 'Carpeta (datos) lista.'
        ConvertTo-SpokenPaths -Text 'Carpeta C:\Users\x\datos\, luego' | Should Be 'Carpeta datos, luego'
        ConvertTo-SpokenPaths -Text 'dijo "C:\Users\x\datos\" ok' | Should Be 'dijo "datos" ok'
    }
    It 'reduces a drive path to its last segment' {
        ConvertTo-SpokenPaths -Text 'andá a C:\Projects\App' | Should Be 'andá a App'
    }
    It 'leaves prose without a drive letter alone' {
        ConvertTo-SpokenPaths -Text 'esto es una oración normal' | Should Be 'esto es una oración normal'
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
    It 'adds no period after full-width sentence punctuation' {
        foreach ($code in 0x3002, 0xFF01, 0xFF1F, 0xFF1A, 0xFF1B, 0xFF0C, 0x3001) {
            $text = 'ab' + [char]$code + "`ncd"
            Add-ImplicitLineEndPeriods -Text $text | Should Be $text
        }
    }
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
    It 'reads a URL that ends in a file name as its site, not as a file' {
        Get-CleanedText -Text 'mirá https://github.com/o/r/blob/main/README.md ya' | Should Be 'mirá el link de github ya'
    }
    It 'keeps the punctuation that follows a URL' {
        Get-CleanedText -Text 'Ver https://example.com/docs. Luego sigue.' | Should Be 'Ver el link de example. Luego sigue.'
    }
    It 'leaves the port out of the site name' {
        Get-CleanedText -Text 'abrí http://localhost:3000/app' | Should Be 'abrí el link de localhost'
    }
    It 'does not read an IP address as a site name' {
        Get-CleanedText -Text 'abrí http://127.0.0.1:8080/x' | Should Be 'abrí el link de una dirección IP'
    }
    It 'reads an underscore inside a name as a space' {
        Get-CleanedText -Text 'la herramienta read_aloud' | Should Be 'la herramienta read aloud'
    }
    It 'keeps the # of a language name' {
        Get-CleanedText -Text 'escrito en C# y F#' | Should Be 'escrito en C# y F#'
    }
    It 'does not expand etc inside a path' {
        Get-CleanedText -Text 'editá /etc/hosts y etc/passwd' | Should Be 'editá /etc/hosts y etc/passwd'
    }
    It 'does not leave a sentence break after an abbreviation that is not the end of one' {
        Get-CleanedText -Text 'Rust vs. Go es rápido' | Should Be 'Rust versus Go es rápido'
        Get-CleanedText -Text 'lenguajes, e.g. Python o Go.' | Should Be 'lenguajes, por ejemplo Python o Go.'
    }
    It 'keeps the period of etc. when a new sentence follows' {
        Get-CleanedText -Text 'Usá git, npm, etc. Luego seguí.' | Should Be 'Usá git, npm, etcétera. Luego seguí.'
    }
    It 'strips list markers at any depth' {
        Get-CleanedText -Text "- a`n  - b`n    - c" | Should Be "a.`nb.`nc"
        Get-CleanedText -Text '      1. n' | Should Be 'n'
    }
    It 'reads a markdown table as rows of comma-separated cells, without the separator row' {
        Get-CleanedText -Text "| Modo | Qué hace |`n|---|---|`n| natural | lee todo |" | Should Be "Modo, Qué hace.`nnatural, lee todo"
    }
    It 'drops the folders in front of a dotfile too' {
        Get-CleanedText -Text 'Editá ~/.bashrc y ./.env y src/.env.' | Should Be 'Editá punto bashrc y punto env y punto env.'
    }
    It 'does not read a file called etc as the abbreviation' {
        Get-CleanedText -Text 'abrí etc.txt' | Should Be 'abrí etc punto txt'
    }
    It 'keeps a pipe that is escaped inside a table cell' {
        Get-CleanedText -Text '| a | b\|c |' | Should Be 'a, b|c'
    }
    It 'does not add a sentence period after a bold label on its own line' {
        Get-CleanedText -Text "**Pasos:**`nuno" | Should Be "Pasos:`nuno"
    }
    It 'names a URL that has no path by its site, and keeps the period after it' {
        Get-CleanedText -Text 'Entrá a https://claude.ai. Luego sigue.' | Should Be 'Entrá a el link de claude. Luego sigue.'
    }
    It 'keeps the closing parenthesis after a URL' {
        Get-CleanedText -Text 'el sitio (https://claude.ai)' | Should Be 'el sitio (el link de claude)'
    }
    It 'does not read an IPv6 address as a site name' {
        Get-CleanedText -Text 'abrí http://[::1]:8080/x' | Should Be 'abrí el link de una dirección IP'
    }
    It 'leaves a user and password out of the site name' {
        Get-CleanedText -Text 'https://user:pass@example.com/a' | Should Be 'el link de example'
    }
    It 'recognizes a URL written in capitals' {
        Get-CleanedText -Text 'HTTP://EXAMPLE.COM/a' | Should Be 'el link de EXAMPLE'
    }
    It 'reads a file inside a dot folder as a file, not as a dotfile' {
        ConvertTo-SpokenReferences -Text '.github/workflows/test.yml y ~/.claude/settings.json' | Should Be 'test punto yml y settings punto json'
    }
    It 'reads a glob of an extension as the extension' {
        Get-CleanedText -Text 'archivos *.js' | Should Be 'archivos punto js'
    }
    It 'reads digit groups separated by underscores as one number' {
        Get-CleanedText -Text 'son 1_000_000 pesos' | Should Be 'son 1000000 pesos'
    }
    It 'finishes quickly on text built to keep a regex busy' {
        $inputs = @(('x' * 20000), ('<!-- ' * 10000), ('[a ' * 10000))
        foreach ($text in $inputs) {
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-CleanedText -Text $text | Out-Null
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should BeLessThan 12
        }
    }
}

Describe 'Limit-WordLength' {
    It 'drops a run of non-space characters too long to be read, and nothing else' {
        Limit-WordLength -Text (('a' * 3000) + ' fin y hola') | Should Match '^\s+fin y hola$'
    }
    It 'leaves ordinary text alone' {
        Limit-WordLength -Text 'hola mundo, con https://example.com/una/ruta/larga' | Should Be 'hola mundo, con https://example.com/una/ruta/larga'
    }
    It 'keeps a long paragraph written without spaces, as Chinese or Japanese is' {
        $paragraph = [string][char]0x3042 * 480
        Limit-WordLength -Text $paragraph -MaxLength 300 | Should Be $paragraph
        (Get-CleanedText -Text $paragraph).Length | Should Be 480
        (ConvertTo-SpokenReferences -Text $paragraph).Length | Should Be 480
    }
    It 'drops a long ASCII run that follows a non-ASCII character, and keeps that character' {
        $ideograms = [string][char]0x65E5 * 5
        $quote = [string][char]0x201C
        Limit-WordLength -Text ($ideograms + ('x' * 400)) -MaxLength 300 | Should Be ($ideograms + ' ')
        Limit-WordLength -Text ($quote + ('x' * 400)) -MaxLength 300 | Should Be ($quote + ' ')
    }
    It 'takes the limit as a parameter' {
        Limit-WordLength -Text ('b' * 400) -MaxLength 300 | Should Be ' '
        Limit-WordLength -Text ('b' * 300) -MaxLength 300 | Should Be ('b' * 300)
    }
}

Describe 'Invoke-ChunkedRegexReplace' {
    It 'gives the same result as one pass when the text is cut into chunks' {
        $saved = @($script:ChunkSize, $script:IdentifierChunkSize)
        $script:ChunkSize = 50
        $script:IdentifierChunkSize = 50
        try {
            $text = (1..40 | ForEach-Object { "abrí scripts/common$_.ps1 y ~/.env C:\Users\x\datos\app$_" }) -join "`n"
            $chunked = ConvertTo-SpokenReferences -Text $text
            $script:ChunkSize = 1000000
            $script:IdentifierChunkSize = 1000000
            $whole = ConvertTo-SpokenReferences -Text $text
            $chunked | Should Be $whole
            $whole | Should Match 'common1 punto ps1 y punto env app1'
        } finally { $script:ChunkSize = $saved[0]; $script:IdentifierChunkSize = $saved[1] }
    }
}

Describe 'Code in the text' {
    It 'keeps the arguments of a call written inside inline code' {
        Get-CleanedText -Text 'usa `handlers[0](event)` ya' | Should Be 'usa handlers[0](event) ya'
        Get-CleanedText -Text 'usa `callbacks[i](data)` ya' | Should Be 'usa callbacks[i](data) ya'
    }
    It 'still reads the text of a link and of two links in a row' {
        Get-CleanedText -Text 'ok [la guia](https://example.com/x) ok' | Should Be 'ok la guia ok'
        Get-CleanedText -Text 'ok [a](x)[b](y) ok' | Should Be 'ok ab ok'
    }
    It 'does not take an identifier or a closing bracket in front of the parentheses for a link' {
        Get-CleanedText -Text '[a][b](c)' | Should Be '[a][b](c)'
        Get-CleanedText -Text 'x[](int y)' | Should Be 'x[](int y)'
        Get-CleanedText -Text '[a][](c)' | Should Be '[a][](c)'
        Get-CleanedText -Text 'arr[](x)' | Should Be 'arr[](x)'
        Get-CleanedText -Text 'foo_[](x)' | Should Be 'foo[](x)'
        Get-CleanedText -Text 'foo__[a](b)' | Should Be 'foo [a](b)'
        Get-CleanedText -Text 'handlers_[0](event)' | Should Be 'handlers[0](event)'
    }
    It 'takes an accented Latin letter, a digit or an underscore before the bracket for an identifier' {
        $e = [string][char]0xE9
        Get-CleanedText -Text ('el caf' + $e + '[0](event)') | Should Be ('el caf' + $e + '[0](event)')
        Get-CleanedText -Text ('Jos' + $e + '[ver nota](https://x.com)') | Should Be ('Jos' + $e + '[ver nota](el link de x)')
        Get-CleanedText -Text ('a' + [char]0xF1 + 'o_[0](x)') | Should Be ('a' + [char]0xF1 + 'o[0](x)')
        Get-CleanedText -Text ('caf' + $e + '_[](x)') | Should Be ('caf' + $e + '[](x)')
        Get-CleanedText -Text 'array1[0](event)' | Should Be 'array1[0](event)'
        Get-CleanedText -Text 'a1_[0](x)' | Should Be 'a1[0](x)'
        Get-CleanedText -Text 'a1_[](x)' | Should Be 'a1[](x)'
    }
    It 'keeps only the label of a link that has a title after the address' {
        Get-CleanedText -Text '[la doc](https://x.com "Docs")' | Should Be 'la doc'
    }
    It 'reads a link written right after Chinese, Japanese, Korean or Thai text' {
        $see = [string][char]0x8BE6 + [char]0x89C1
        $doc = [string][char]0x6587 + [char]0x6863
        Get-CleanedText -Text ($see + '[' + $doc + '](https://example.com/a)' + [char]0x3002) | Should Be ($see + $doc + [char]0x3002)
    }
    It 'reads a link written inside underscore emphasis' {
        Get-CleanedText -Text 'ver _[docs](https://example.com/a)_ fin' | Should Be 'ver docs fin'
        Get-CleanedText -Text '_[docs](x)_ al inicio' | Should Be 'docs al inicio'
        Get-CleanedText -Text 'ver __[docs](x)__ fin' | Should Match '^ver\s+docs\s+fin$'
    }
    It 'keeps an HTML comment marker that is written inside inline code' {
        Get-CleanedText -Text 'the `<!--voice-->` block' | Should Be 'the <!--voice--> block'
        Get-CleanedText -Text '`<!--` and `-->` both' | Should Be '<!-- and --> both'
    }
    It 'keeps the markers of two comments written inside inline code' {
        Get-CleanedText -Text 'a `<!-- x -->` y' | Should Match '^a <!-- x --> y$'
        Get-CleanedText -Text '`<!-- a -->` and `<!-- b -->`' | Should Be '<!-- a --> and <!-- b -->'
        Get-CleanedText -Text 'a <!-- c --> `<!-- x -->` y' | Should Match '^a\s+<!-- x --> y$'
    }
    It 'does not slow down when many code spans are followed by an opener that is never closed' {
        # A "<!--" with no "-->" scans to the end of the text, and each code span is a match that
        # restarts the regex timeout, so the cost grows with the text unless the step has a budget.
        # The leading "-->" matters: the step only searches up to the last closer, and without one it returns early.
        $text = "x -->`n" + ('`x` <!-- ' * 6000)
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Get-CleanedText -Text $text | Out-Null
        $watch.Stop()
        $watch.Elapsed.TotalSeconds | Should BeLessThan 6
    }
    It 'removes a comment that spans lines, leaves what is between two comments and removes an empty one' {
        Get-CleanedText -Text "a`n<!--`nnota`n-->`nb" | Should Match '^a\.\s+b$'
        Get-CleanedText -Text '<!-- uno --> medio <!-- dos --> fin' | Should Match '^medio\s+fin$'
        Get-CleanedText -Text 'x <!---->y' | Should Be 'x y'
    }
    It 'keeps a comment marker written in inline code when lines follow it' {
        Get-CleanedText -Text "Primera linea`nUsa ``<!--voice-->`` para eso.`nFin" | Should Be "Primera linea.`nUsa <!--voice--> para eso.`nFin"
    }
    It 'does not let a lone backtick hide a comment on a later line either' {
        $tick = [string][char]96
        $result = Get-CleanedText -Text ('Un ' + $tick + " suelto`n<!-- oculto -->`nfin " + $tick + " y`n<!-- otro -->`nfin")
        $result | Should Not Match 'oculto|otro'
    }
    It 'does not let a lone backtick hide a link on the next line' {
        $tick = [string][char]96
        $result = Get-CleanedText -Text ('Un ' + $tick + " suelto`n[doc](http://x.com)`nfin " + $tick + ' y')
        $result | Should Match 'doc'
        $result | Should Not Match '\]\('
    }
    It 'keeps a C++ lambda written in plain text' {
        Get-CleanedText -Text 'La lambda es [](int x) { return x; } en C++' | Should Be 'La lambda es [](int x) { return x; } en C++'
    }
    It 'does not let a lone backtick hide a comment on the next line' {
        $tick = [string][char]96
        Get-CleanedText -Text ('Un ' + $tick + " suelto`n<!-- oculto -->`nfin " + $tick + ' y') | Should Not Match 'oculto'
    }
    It 'still removes a real HTML comment, even one that has code in it' {
        Get-CleanedText -Text 'antes <!-- oculto --> despues' | Should Match '^antes\s+despues$'
        Get-CleanedText -Text 'a `x` <!-- c `y` --> b' | Should Match '^a x\s+b$'
    }
    It 'keeps the words between two spans that show three backticks' {
        $two = [string][char]96 * 2
        $three = [string][char]96 * 3
        $span = $two + ' ' + $three + ' ' + $two
        $result = Get-CleanedText -Text ('Usá ' + $span + ' para abrir un bloque y ' + $span + ' para cerrar. Fin.')
        $result | Should Match 'para abrir un bloque y'
        $result | Should Match 'para cerrar'
    }
    It 'does not let a lone backtick hide an image on the next line' {
        $tick = [string][char]96
        $result = Get-CleanedText -Text ('Un ' + $tick + " suelto`n![img](a.png)`nfin " + $tick + ' y')
        $result | Should Match 'img'
        $result | Should Not Match '!'
    }
    It 'drops an image that has no alt text, without leaving the exclamation mark' {
        Get-CleanedText -Text 'Mira ![](a.png) listo' | Should Be 'Mira  listo'
    }
    It 'reads an image written with a title as its alt text only' {
        Get-CleanedText -Text 'Mira ![logo](a.png "Logo") listo' | Should Be 'Mira logo listo'
    }
    It 'keeps an image written inside inline code as written' {
        Get-CleanedText -Text 'una imagen `![alt](url)` y ![real](a.png) fin' | Should Be 'una imagen ![alt](url) y real fin'
        Get-CleanedText -Text 'Image syntax is `![alt text](path/to/img.png)`, which shows the picture.' | Should Match 'path/to/img.png'
    }
    It 'finds a backtick that is followed by a combining mark' {
        $tick = [string][char]96
        $text = 'text ' + $tick + '<!--x-->' + $tick + [char]0x301
        Get-CleanedText -Text $text | Should Match '<!--x-->'
    }
    It 'keeps a regex or a token written inside inline code as written' {
        Get-CleanedText -Text 'Use the regex `^[a-z](\d+)$` to match' | Should Be 'Use the regex ^[a-z](\d+)$ to match'
        Get-CleanedText -Text 'the line `[WARN](2026-10-25)` appears' | Should Be 'the line [WARN](2026-10-25) appears'
        Get-CleanedText -Text 'ver [docs](http://d.com) y `[b](c)` ya' | Should Be 'ver docs y [b](c) ya'
    }
    It 'omits a block fenced with tildes' {
        $result = Get-CleanedText -Text "antes`n~~~`nsecreto`n~~~`ndespues"
        $result | Should Not Match 'secreto'
        $result | Should Match 'code block omitted'
        $result | Should Match 'despues'
    }
    It 'omits a block fenced with four backticks that contains a shorter fence' {
        $tick = [string][char]96
        $four = $tick * 4
        $three = $tick * 3
        $text = "antes`n" + $four + "markdown`n" + $three + "js`nsecreto`n" + $three + "`n" + $four + "`ndespues"
        $result = Get-CleanedText -Text $text
        $result | Should Not Match 'secreto'
        $result | Should Not Match 'markdown'
        $result | Should Match 'despues'
    }
}

Describe 'Fenced code blocks' {
    function ConvertFrom-Ticks { param([string]$Text) return $Text.Replace('Q', [string][char]96) }

    It 'omits a fence that is indented, closed with trailing spaces or closed with a longer marker' {
        foreach ($text in "  QQQ`n  secreto`n  QQQ`nfin", "QQQ`nsecreto`nQQQ   `nfin", "QQQ`nsecreto`nQQQQQ`nfin", "~~~~md`nsecreto`n~~~~~`nfin") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'secreto'
            $result | Should Match 'fin'
        }
    }
    It 'keeps what follows a shorter fence inside a longer one' {
        foreach ($text in "QQQQmd`nQQQjs`nsecreto`nQQQ`nmas secreto`nQQQQ`ndespues", "~~~~md`nsecreto`n~~~`nmas secreto`n~~~~`ndespues") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'secreto'
            $result | Should Match 'despues'
        }
    }
    It 'keeps the prose between two fences that each start a line' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "a`nQQQ`nS1`nQQQ`nPROSE`nQQQ`nS2`nQQQ`nz")
        $result | Should Match 'PROSE'
        $result | Should Not Match 'S1'
        $result | Should Not Match 'S2'
    }
    It 'does not end a fence at backticks in the middle of a body line or at a line with an info string' {
        foreach ($text in "QQQ`nfoo QQQ SECRET2`nQQQ`nfin", "QQQ`nfoo`nQQQjs`nSECRET`nQQQ`nfin") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'SECRET'
            $result | Should Match 'fin'
        }
    }
    It 'keeps a technology list wrapped in marks' {
        foreach ($mark in '()', '[]', '<>', '""') {
            $open = [string]$mark[0]
            $close = [string]$mark[1]
            Get-CleanedText -Text ($open + 'MongoDB/Express/Node.js' + $close) | Should Be ($open + 'MongoDB/Express/Node punto js' + $close)
        }
        Get-CleanedText -Text '**MongoDB/Express/Node.js**' | Should Be 'MongoDB/Express/Node punto js'
    }
    It 'omits an indented tilde fence and one closed with trailing spaces' {
        foreach ($text in "  ~~~`n  secreto`n  ~~~`nfin", "~~~`nsecreto`n~~~   `nfin") {
            $result = Get-CleanedText -Text $text
            $result | Should Not Match 'secreto'
            $result | Should Not Match '~'
            $result | Should Match 'fin'
        }
    }
    It 'does not end a fence at a body line that ends with a fence marker' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "x`nQQQ`nline QQQ`nSECRET`nQQQ`nfin")
        $result | Should Not Match 'SECRET'
        $result | Should Match 'fin'
    }
    It 'keeps the words between mentions of triple backticks with a language, written inside double backticks' {
        $two = [string][char]96 * 2
        $three = [string][char]96 * 3
        Get-CleanedText -Text ('escribi ' + $two + ' ' + $three + 'js ' + $two + ' y para cerrarlo ' + $two + ' ' + $three + ' ' + $two + ' listo. Fin.') | Should Match 'y para cerrarlo'
        Get-CleanedText -Text ('Para cerrar escribi ' + $two + ' js' + $three + ' ' + $two + ' y para abrir ' + $two + ' js' + $three + ' ' + $two + ' listo.') | Should Match 'y para abrir'
    }
    It 'keeps the words between double-backtick mentions of triple backticks, whatever opens the span' {
        $two = [string][char]96 * 2
        $three = [string][char]96 * 3
        foreach ($open in '(', '[', '{', '"', [string][char]0xBF, [string][char]0xA1, [string][char]0xAB) {
            $text = 'Abri ' + $open + $two + ' ' + $three + 'js ' + $two + ' y para cerrar ' + $open + $two + ' ' + $three + ' ' + $two + ' listo.'
            Get-CleanedText -Text $text | Should Match 'y para cerrar'
        }
    }
    It 'omits a fence that follows text on the same line, whatever follows its three backticks' {
        foreach ($text in "Do this: QQQ`nSECRET`nQQQ`nend", "1. QQQ`nSECRET`nQQQ`nend", "Do this: QQQ bash`nSECRET`nQQQ`nend", "Do this: QQQ{r}`nSECRET`nQQQ`nend", "Do this: QQQbash`r`nSECRET`r`nQQQ`r`nend") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'SECRET'
            $result | Should Match 'end'
        }
    }
    It 'ends an inline fence at its own closing backticks, so what follows is cleaned as usual' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks 'Corre QQQnpm iQQQ y mira [la doc](https://x.com/a) con QzQ ya.')
        $result | Should Be 'Corre  code block omitted.  y mira la doc con z ya.'
    }
    It 'omits an inline fence that follows a code span' {
        foreach ($text in 'Usa QnpmQ QQQnpm i fooQQQ para instalar.', "Corre QmakeQ QQQbash`nSECRETO1`nQQQ`ny listo.", 'Opcion QaQ o QbQ QQQcodigo secretoQQQ listo') {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'npm i foo|SECRETO1|codigo secreto'
            $result | Should Match 'code block omitted'
        }
    }
    It 'omits two inline fences in a row' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks 'x QQQaQQQ QQQbQQQ y')
        $result | Should Not Match 'a.*b'
        ([regex]::Matches($result, 'code block omitted')).Count | Should Be 2
    }
    It 'keeps the words between mentions of triple backticks wrapped in single backticks, with a language' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks 'Para abrir escribi Q QQQjs Q y para cerrar Q QQQ Q listo.')
        $result | Should Match 'y para cerrar'
    }
    It 'omits a fence whose block holds tildes or is indented' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "Use QQQ x`n~~~`nQQQ`nsecret`nQQQ`n~~~`nfin")
        $result | Should Not Match 'secret'
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "1. Envolve el codigo con QQQ asi:`n   QQQjs`n   SECRETO`n   QQQ`nfin")
        $result | Should Not Match 'SECRETO'
    }
    It 'omits a real fence that follows a one-line mention of triple backticks, and keeps the prose' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "Wrap code in triple backticks (QQQ) like this:`nQQQ`nconst a = 1;`nQQQ`ndone.")
        $result | Should Not Match 'const a'
        $result | Should Match 'Wrap code'
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "Cerra con QQQ al final:`nQQQ`nls -la`nQQQ`nlisto.")
        $result | Should Not Match 'ls -la'
        $result | Should Match 'al final'
    }
    It 'keeps the words between two mentions of triple backticks in a table, a list and two lines' {
        Get-CleanedText -Text (ConvertFrom-Ticks "| QQQ | abre bloque |`n| QQQ | cierra bloque |") | Should Match 'abre bloque'
        Get-CleanedText -Text (ConvertFrom-Ticks "1. Escribi QQQbash en una linea`n2. Pone tu comando`n3. Cerra con QQQ") | Should Match 'Pone tu comando'
        Get-CleanedText -Text (ConvertFrom-Ticks "Escribi QQQjs en la primera linea`ny QQQ en la ultima.") | Should Match 'en la primera'
    }
    It 'does not pair a triple backtick mentioned in prose with one in a later paragraph' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "Use QQQ to open a fence.`n`nThis paragraph is real prose that must be heard.`n`nUse QQQ to close it.")
        $result | Should Match 'real prose that must be heard'
    }
    It 'stops a quoted triple backtick at the empty quote line, so the quoted prose after it is heard and a later quoted fence is omitted' {
        foreach ($newline in "`n", "`r`n") {
            $text = ConvertFrom-Ticks ("> Para abrir un bloque usa QQQ" + $newline + ">" + $newline + "> prosa X" + $newline + ">" + $newline + "> QQQbash" + $newline + "> secretCmd" + $newline + "> QQQ" + $newline + "> prosa Y")
            $result = Get-CleanedText -Text $text
            $result | Should Match 'prosa X'
            $result | Should Match 'prosa Y'
            $result | Should Not Match 'secretCmd'
        }
    }
    It 'stops a quoted triple backtick at a quote line that is empty or only spaces, at any depth' {
        foreach ($text in "> Para abrir usa QQQ`n> `n> prosa X`n> `n> QQQbash`n> secretCmd`n> QQQ`n> prosa Y", "> > Para abrir usa QQQ`n> > `n> > prosa X`n> >`n> > QQQbash`n> > secretCmd`n> > QQQ`n> > prosa Y") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Match 'prosa X'
            $result | Should Match 'prosa Y'
            $result | Should Not Match 'secretCmd'
        }
    }
    It 'removes the marker of a quote indented under a list item' {
        Get-CleanedText -Text "1. Paso uno`n   > nota importante`n2. Paso dos" | Should Not Match '>'
    }
    It 'does not let an image swallow the parenthesis that comes after it' {
        Get-CleanedText -Text 'Vea ![alt](img/x.png) (captura de pantalla) fin.' | Should Match 'captura de pantalla'
    }
    It 'omits a fence opened right after a list marker, whatever is inside it' {
        foreach ($text in "1. QQQbash`n   secretG`n`n   secretH`n   QQQ`n2. after1", "- ~~~`n  secretG`n  ~~~`n- after1", "> - QQQjs title=`"a b`"`n>   secretG`n>`n>   secretH`n>   QQQ`n> - after1", "- > QQQ`n  > secretG`n  >`n  > secretH`n  > QQQ`n- after1", "1) QQQ`r`n   secretG`r`n`r`n   secretH`r`n   QQQ`r`n2) after1") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'secret'
            $result | Should Match 'after1'
        }
    }
    It 'removes the marker of a quote nested deeper than three spaces or inside a quoted list item' {
        Get-CleanedText -Text "- a PROSEa`n  - b PROSEb`n    > q PROSEq`n  - PROSEc" | Should Not Match '>'
        Get-CleanedText -Text "> - a PROSEa`n>   > q PROSEq`n> - PROSEb" | Should Not Match '>'
        Get-CleanedText -Text "> - a PROSEa`r`n>   > q PROSEq`r`n> - PROSEb" | Should Not Match '>'
    }
    It 'keeps a mention of triple backticks literal when the next line opens a longer fence or a fence after a list marker' {
        $first = Get-CleanedText -Text (ConvertFrom-Ticks "PROSEa mention QQQ`nQQQQbash`nCODEa`nQQQQ`nPROSEc")
        $first | Should Not Match 'CODEa'
        $first | Should Match 'PROSEc'
        $second = Get-CleanedText -Text (ConvertFrom-Ticks "- Abri con QQQ`n- PROSEb`n- QQQbash`n  CODEa`n  QQQ`n- PROSEc")
        $second | Should Not Match 'CODEa'
        $second | Should Match 'PROSEb'
        $second | Should Match 'PROSEc'
    }
    It 'does not let a line that starts with a double-backtick span end a fence opened by a mention' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "Do this: QQQ`nQQxQQ = 1`nSECRET`nQQQ`nend")
        $result | Should Not Match 'SECRET'
        $result | Should Match 'end'
    }
    It 'removes a quote marker or a parenthesis list marker that follows a list marker' {
        $result = Get-CleanedText -Text "- > quote MARKA`n1. > quote MARKB`n> - > nested MARKC`n1) paren MARKD"
        $result | Should Not Match '>'
        $result | Should Not Match '1\)'
        $result | Should Match 'MARKA'
        $result | Should Match 'MARKD'
    }
    It 'omits a fence opened after any list marker, with a blank line inside the code' {
        foreach ($text in "* QQQbash`n  secretG`n`n  secretH`n  QQQ`n* after1", "+ QQQbash`n  secretG`n`n  secretH`n  QQQ`n+ after1", "10. QQQbash`n    secretG`n`n    secretH`n    QQQ`n11. after1") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'secret'
            $result | Should Match 'after1'
        }
    }
    It 'omits a fence indented four spaces or a tab under a list item, with a blank line inside the code' {
        foreach ($indent in '    ', "`t") {
            $text = ConvertFrom-Ticks ("1. paso`n`n" + $indent + "QQQbash`n" + $indent + "secretG`n`n" + $indent + "secretH`n" + $indent + "QQQ`n`n2. paso dos")
            $result = Get-CleanedText -Text $text
            $result | Should Not Match 'secret'
            $result | Should Match 'paso dos'
        }
    }
    It 'does not let a list item that mentions triple backticks swallow its sibling items' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "Sintaxis:`n- QQQ abre un bloque PROSE1`n- Otro punto PROSE2`n`nEjemplo:`n`nQQQbash`ncmd secretZ`nQQQ`n`nFin PROSE3")
        $result | Should Match 'PROSE1'
        $result | Should Match 'PROSE2'
        $result | Should Match 'PROSE3'
        $result | Should Not Match 'secretZ'
    }
    It 'does not let a quoted fence inside a sample close the unquoted fence that contains it' {
        foreach ($newline in "`n", "`r`n") {
            $text = ConvertFrom-Ticks ("Asi se escribe una cita con codigo:" + $newline + $newline + "QQQmarkdown" + $newline + "> QQQjs" + $newline + "> const secreto = 1;" + $newline + "> QQQ" + $newline + "QQQ" + $newline + $newline + "Despues, ejecuta:" + $newline + $newline + "QQQbash" + $newline + "npm test" + $newline + "QQQ" + $newline + $newline + "Listo PROSAFIN.")
            $result = Get-CleanedText -Text $text
            $result | Should Not Match 'secreto'
            $result | Should Not Match 'npm test'
            $result | Should Match 'Despues, ejecuta'
            $result | Should Match 'PROSAFIN'
        }
        $tilde = Get-CleanedText -Text "~~~md`n> ~~~`n> CODEQ`n> ~~~`n~~~`n`nFin PROSAFIN."
        $tilde | Should Not Match 'CODEQ'
        $tilde | Should Match 'PROSAFIN'
    }
    It 'cleans a list, a table and a heading written inside a blockquote like any other' {
        Get-CleanedText -Text "> - a`n> - b" | Should Be "a.`nb"
        Get-CleanedText -Text "> 1. uno`n> 2. dos" | Should Be "uno.`ndos"
        Get-CleanedText -Text "> | x | y |`n> |---|---|`n> | 1 | 2 |" | Should Be "x, y.`n1, 2"
        Get-CleanedText -Text "> ## Titulo`n> texto" | Should Be "Titulo.`ntexto"
    }
    It 'keeps a comparison that follows a list marker' {
        Get-CleanedText -Text '- >= 2 elementos' | Should Match '>= 2 elementos'
    }
    It 'omits a fence written inside a nested blockquote without leaving its markers' {
        foreach ($text in "> > QQQjs`n> > secretG`n> > QQQ`n> > after1", "> > QQQts title=`"x`"`n> > secretG`n> > QQQ`n> > after1", "> > ~~~bash`n> > secretG`n> > ~~~`n> > after1") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'secretG'
            $result | Should Not Match '>'
            $result | Should Match 'after1'
        }
    }
    It 'removes the markers of a nested blockquote and keeps its text' {
        Get-CleanedText -Text "> > uno`n> > dos" | Should Be "uno.`ndos"
        Get-CleanedText -Text ">> x" | Should Be 'x'
        Get-CleanedText -Text "> a`n> > c`n>>> d" | Should Be "a.`nc.`nd"
    }
    It 'leaves a greater-than sign in the middle of a line alone' {
        Get-CleanedText -Text 'Si 5 > 3 entonces sigue' | Should Be 'Si 5 > 3 entonces sigue'
    }
    It 'omits a fence written inside a blockquote, whatever its info string or marker' {
        foreach ($text in "> ~~~bash`n> secretA`n> ~~~`n> after1", "> QQQts title=`"x`"`n> secretC`n> QQQ`n> after1", "> QQQyaml {1,3}`n> secretD`n> QQQ`nafter1", "> - item1`n>   QQQjs copy`n>   secretE`n>   QQQ`n> after1", "> QQQQjs`n> secretF`n> QQQQ`n> after1") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'secret'
            $result | Should Match 'after1'
        }
    }
    It 'stops an inline triple backtick at a blank line, so the paragraph after it is still heard' {
        foreach ($newline in "`n", "`r`n") {
            $text = ConvertFrom-Ticks ("Para cerrar un bloque escribi QQQ" + $newline + $newline + "Esta es una explicacion importante que se debe escuchar." + $newline + $newline + "Y para abrir uno escribi QQQ" + $newline + "Fin.")
            Get-CleanedText -Text $text | Should Match 'explicacion importante que se debe escuchar'
        }
    }
    It 'omits a real fence that follows a sentence that mentions triple backticks' {
        foreach ($text in "A fenced block starts with QQQ:`n`nQQQtext`nhello world`nQQQ`ndone.", "Wrap code in triple backticks (QQQ) like this:`nQQQjs`nconst a = 1;`nQQQ`ndone.") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'hello world|const a'
            $result | Should Match 'done'
        }
    }
    It 'keeps the words between two mentions of triple backticks written as code' {
        Get-CleanedText -Text (ConvertFrom-Ticks 'Abri con Q QQQ Q y cerra con Q QQQ Q listo.') | Should Match 'y cerra con'
        Get-CleanedText -Text (ConvertFrom-Ticks 'Use QQQQ QQQ QQQQ and QQQQ QQQ QQQQ now') | Should Match 'and'
    }
    It 'does not take an inline span at the start of a line for a fence' {
        $result = Get-CleanedText -Text (ConvertFrom-Ticks "Intro.`nQQQnpm iQQQ y despues`nPROSE ONE.`n`nQQQ`nSECRET`nQQQ`nend")
        $result | Should Match 'PROSE ONE'
        $result | Should Not Match 'SECRET'
    }
    It 'omits a fence opened after a list marker or after text on the same line' {
        foreach ($text in "1. QQQbash`n   S1`n   QQQ`n2. Prose P1`nQQQ`nS2`nQQQ`nend", "Do this: QQQbash`nS1`nQQQ`nProse P1`nQQQpy`nS2`nQQQ`nend") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Match 'Prose P1'
            $result | Should Not Match 'S1'
            $result | Should Not Match 'S2'
        }
    }
    It 'stops looking for fences when the budget is spent, however many openers there are' {
        # Every "````a" line scans the rest of the text for a four-backtick closer, finds none,
        # and only then matches as a three-backtick fence: each match is quick, so the regex
        # timeout never fires, and without a budget check between matches the step runs far past the budget.
        $saved = $script:CleanupBudget
        $script:CleanupBudget = [TimeSpan]::FromSeconds(1)
        try {
            $text = ConvertFrom-Ticks ("QQQQa`nQQQ`n" * 6000)
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-CleanedText -Text $text | Out-Null
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should BeLessThan 6
        } finally { $script:CleanupBudget = $saved }
    }
    It 'stops the link step when the budget is spent, however many links interrupt a long run of brackets' {
        # Every "[](" in a run of them with no space scans to the end of the run; the short
        # link between the runs is a match that restarts the regex timeout. Without the budget
        # check between matches this 100 KB text runs far past the budget.
        $saved = $script:CleanupBudget
        $script:CleanupBudget = [TimeSpan]::FromSeconds(3)
        try {
            $unit = '[](' + [char]0x0436
            $run = ($unit * 1250) + ' [](a) '
            $text = $run * 20
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-CleanedText -Text $text | Out-Null
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should BeLessThan 8
        } finally { $script:CleanupBudget = $saved }
    }
    It 'stops the image step when the budget is spent, however many code spans interrupt the failing starts' {
        # Each "![a](x " start with no ")" scans to the end of the text; every "`a`" between them is
        # a match that restarts the regex timeout. Without the budget check between matches this
        # 100 KB text runs far past the budget.
        $saved = $script:CleanupBudget
        $script:CleanupBudget = [TimeSpan]::FromSeconds(3)
        try {
            $tick = [string][char]96
            $segment = ('![a](x ' * 10) + $tick + 'a' + $tick + ' '
            $text = $segment * 1350
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-CleanedText -Text $text | Out-Null
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should BeLessThan 9
        } finally { $script:CleanupBudget = $saved }
    }
    It 'passes the rest of the text through unchanged when the budget runs out between matches' {
        # The deadline falls while the loop is still matching (300000 matches take seconds), or has
        # already passed when the function starts on a slow machine; either way nothing is lost.
        $script:CleanupDeadline = [DateTime]::UtcNow.AddMilliseconds(300)
        try {
            $result = Invoke-BudgetedRegexReplace -Text (('a' * 300000) + 'END') -Pattern 'a' -Replacement 'X'
        } finally { $script:CleanupDeadline = $null }
        $result | Should Match 'END$'
        $result | Should Match 'aaaa'
        $result.Length | Should Be 300003
    }
    It 'returns the text unchanged when one scan runs past the regex timeout' {
        $saved = $script:RegexTimeout
        $script:RegexTimeout = [TimeSpan]::FromMilliseconds(50)
        try {
            $text = ('a' * 40) + 'b'
            Invoke-BudgetedRegexReplace -Text $text -Pattern '(a+)+$' -Replacement 'X' | Should Be $text
        } finally { $script:RegexTimeout = $saved }
    }
    It 'expands group references in the replacement' {
        Invoke-BudgetedRegexReplace -Text 'abc' -Pattern '(b)' -Replacement '[$1]' | Should Be 'a[b]c'
    }
    It 'returns the text unchanged when the budget is already spent' {
        $script:CleanupDeadline = [DateTime]::UtcNow.AddSeconds(-1)
        try { Invoke-BudgetedRegexReplace -Text 'aaa' -Pattern 'a' -Replacement 'X' | Should Be 'aaa' }
        finally { $script:CleanupDeadline = $null }
    }
    It 'keeps the text when a single scan of openers times out' {
        $text = '~~~~a' + "`n"
        $result = Get-CleanedText -Text ($text * 8000)
        $result.Length | Should BeGreaterThan 1000
    }
    It 'closes a fence on a line that ends with CRLF' {
        foreach ($text in "a`r`n~~~`r`nSECRET`r`n~~~`r`nb", "a`r`nQQQQmd`r`nQQQjs`r`nSECRET`r`nQQQ`r`nMORE`r`nQQQQ`r`nb") {
            $result = Get-CleanedText -Text (ConvertFrom-Ticks $text)
            $result | Should Not Match 'SECRET'
            $result | Should Not Match 'MORE'
            $result | Should Match 'b$'
        }
    }
}

Describe 'Large texts and the cleanup budget' {
    It 'stops a cleanup of a huge text of abbreviations and URLs within its budget' {
        $saved = $script:CleanupBudget
        $script:CleanupBudget = [TimeSpan]::FromSeconds(1)
        try {
            foreach ($text in (('etc. ' * 120000), ('http://a.b ' * 100000))) {
                $watch = [System.Diagnostics.Stopwatch]::StartNew()
                Get-CleanedText -Text $text | Out-Null
                $watch.Stop()
                $watch.Elapsed.TotalSeconds | Should BeLessThan 5
            }
        } finally { $script:CleanupBudget = $saved }
    }
    It 'cleans text built to make the dash, rule and link steps quadratic in little time' {
        # With the default budget, on purpose: a smaller one is spent before these steps
        # run and the test would pass whatever the patterns are. A quadratic step takes
        # tens of seconds on these inputs; the current patterns take a few seconds each.
        $dash = [string][char]0x2014
        $inputs = @(
            ((' ' * 3000 + 'x' + $dash + 'x') * 100),
            ((("`n" * 3000) + "x`n---`nx") * 100),
            ((('[ ' * 3000) + '] [b](c) ') * 50)
        )
        foreach ($text in $inputs) {
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-CleanedText -Text $text | Out-Null
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should BeLessThan 15
        }
    }
    It 'converts every dash of a series separated by spaces or a line break' {
        $dash = [string][char]0x2014
        $en = [string][char]0x2013
        foreach ($text in ('a ' + $dash + ' ' + $dash + ' b'), ('a ' + $en + ' ' + $en + ' b'), ("x $dash`n$dash y")) {
            $result = Get-CleanedText -Text $text
            $result.Contains($dash) | Should Be $false
            $result.Contains($en) | Should Be $false
        }
    }
    It 'still turns dashes, rules and links into plain text' {
        $dash = [string][char]0x2014
        Get-CleanedText -Text ('uno ' + $dash + ' dos' + $dash + 'tres') | Should Be 'uno, dos, tres'
        Get-CleanedText -Text "antes`n`n---`n`ndespués" | Should Match '^antes\.\s+después$'
        Get-CleanedText -Text 'mirá [esta página](https://example.com) y [otra](x)' | Should Be 'mirá esta página y otra'
    }
    It 'runs the abbreviation step without per-match PowerShell code, so it is cheap on its own' {
        $saved = $script:CleanupBudget
        $script:CleanupBudget = [TimeSpan]::FromSeconds(1)
        try {
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-WithCleanupBudget { ConvertTo-SpokenAbbreviations -Text ('etc. ' * 120000) } | Out-Null
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should BeLessThan 3
        } finally { $script:CleanupBudget = $saved }
    }
    It 'reads many URLs the same way in chunks as in one piece' {
        $saved = $script:ChunkSize
        try {
            $text = (1..40 | ForEach-Object { "mirá https://docs.example$_.com/x/y, luego http://localhost:$_/app." }) -join ' '
            $script:ChunkSize = 1000000
            $whole = ConvertTo-SpokenUrls -Text $text
            $script:ChunkSize = 70
            ConvertTo-SpokenUrls -Text $text | Should Be $whole
            $whole | Should Match '^mirá el link de example1, luego el link de localhost\.'
        } finally { $script:ChunkSize = $saved }
    }
}

Describe 'Table rows and the cleanup budget' {
    It 'gives the same result when the table is cut into chunks at line ends' {
        $saved = $script:ChunkSize
        try {
            $text = (1..30 | ForEach-Object { "| celda $_ | otra |" }) -join "`n"
            $script:ChunkSize = 1000000
            $whole = Get-CleanedText -Text $text
            $script:ChunkSize = 60
            Get-CleanedText -Text $text | Should Be $whole
            $whole | Should Match '^celda 1, otra\.'
        } finally { $script:ChunkSize = $saved }
    }
    It 'stops a cleanup of a huge table within its budget' {
        $text = "|`n" * 100000
        $saved = $script:CleanupBudget
        $script:CleanupBudget = [TimeSpan]::FromSeconds(1)
        try {
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-CleanedText -Text $text | Out-Null
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should BeLessThan 6
        } finally { $script:CleanupBudget = $saved }
    }
}

Describe 'Cleanup budget' {
    It 'skips a step once the budget is spent' {
        $script:CleanupDeadline = [DateTime]::UtcNow.AddSeconds(-1)
        try { Invoke-RegexReplace -Text 'abc' -Pattern 'b' -Replacement 'X' | Should Be 'abc' }
        finally { $script:CleanupDeadline = $null }
    }
    It 'does not leave a budget running after a cleanup' {
        Get-CleanedText -Text 'hola' | Out-Null
        $script:CleanupDeadline | Should Be $null
    }
    It 'stops a cleanup of text full of slow words within its budget' {
        $word = ('a/b.' * 74) + 'a/'
        $text = ($word + ' f.md ') * 2000
        $saved = $script:CleanupBudget
        $script:CleanupBudget = [TimeSpan]::FromSeconds(1)
        try {
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Get-CleanedText -Text $text | Out-Null
            $watch.Stop()
            $watch.Elapsed.TotalSeconds | Should BeLessThan 8
        } finally { $script:CleanupBudget = $saved }
    }
}

Describe 'Text written without spaces next to links, files and paths' {
    It 'reads a URL that contains Latin accented letters as a whole' {
        ConvertTo-SpokenUrls -Text 'https://es.wikipedia.org/wiki/España' | Should Be 'el link de wikipedia'
        ConvertTo-SpokenUrls -Text 'https://mañana.com/ya' | Should Be 'el link de mañana'
        ConvertTo-SpokenUrls -Text 'https://ejemplo.com/ñandú ya' | Should Be 'el link de ejemplo ya'
    }
    It 'removes a horizontal rule in text with CRLF line endings' {
        Get-CleanedText -Text "antes`r`n`r`n---`r`n`r`ndespués" | Should Not Match '-'
    }
    It 'reads a path through a folder whose name looks like a file' {
        ConvertTo-SpokenReferences -Text 'node_modules/three.js/examples/jsm/loaders/GLTFLoader.js' | Should Be 'GLTFLoader punto js'
        ConvertTo-SpokenReferences -Text 'Next.js/app/page.tsx' | Should Be 'page punto tsx'
        ConvertTo-SpokenReferences -Text 'vue.js/docs/guide.md' | Should Be 'guide punto md'
        ConvertTo-SpokenReferences -Text '.env/bin/activate.sh' | Should Be 'activate punto sh'
        ConvertTo-SpokenReferences -Text '~/.env/lib/site.py' | Should Be 'site punto py'
    }
    It 'does not fuse or lose the names of a list written with slashes' {
        ConvertTo-SpokenReferences -Text 'Stack: React.js/Node.js/Express.js' | Should Be 'Stack: React punto js/Node.js/Express.js'
        ConvertTo-SpokenReferences -Text 'Vue.js/Nuxt.js/Pinia' | Should Be 'Vue punto js/Nuxt.js/Pinia'
        ConvertTo-SpokenReferences -Text 'Node.js/Express.js/Mongo.js' | Should Be 'Node punto js/Express.js/Mongo.js'
    }
    It 'keeps the capitalized names of a technology list that ends in a .js name' {
        ConvertTo-SpokenReferences -Text 'Usa TypeScript/Node.js en el backend.' | Should Be 'Usa TypeScript/Node punto js en el backend.'
        ConvertTo-SpokenReferences -Text 'Stack: MongoDB/Express/React/Node.js' | Should Be 'Stack: MongoDB/Express/React/Node punto js'
        ConvertTo-SpokenReferences -Text 'Frontend con HTML/CSS/React.js' | Should Be 'Frontend con HTML/CSS/React punto js'
        ConvertTo-SpokenReferences -Text 'abrí src/app/main.js' | Should Be 'abrí main punto js'
        ConvertTo-SpokenReferences -Text 'abrí Docs/Guide/main.js' | Should Be 'abrí main punto js'
        ConvertTo-SpokenReferences -Text 'Src/Utils/helpers.js y Src/Utils/helpers.ts' | Should Be 'helpers punto js y helpers punto ts'
    }
    It 'keeps a technology list wrapped in parentheses, bold, backticks or quotes' {
        ConvertTo-SpokenReferences -Text 'El stack MERN (MongoDB/Express/React/Node.js) es popular.' | Should Be 'El stack MERN (MongoDB/Express/React/Node punto js) es popular.'
        ConvertTo-SpokenReferences -Text '**MongoDB/Express/React/Node.js**' | Should Be '**MongoDB/Express/React/Node punto js**'
        ConvertTo-SpokenReferences -Text 'Usá `React/Next.js` ya' | Should Be 'Usá `React/Next punto js` ya'
        ConvertTo-SpokenReferences -Text '"MongoDB/Express/React/Node.js"' | Should Be '"MongoDB/Express/React/Node punto js"'
        Get-CleanedText -Text 'Usa (TypeScript/Node.js).' | Should Be 'Usa (TypeScript/Node punto js).'
    }
    It 'drops a markdown link that has no text' {
        Get-CleanedText -Text 'Ver [](https://x.com) ahora' | Should Not Match '[\[\]()]'
    }
    It 'keeps the head of a C++ lambda, which looks like a link with no text' {
        Get-CleanedText -Text 'Usa la lambda `[](int x) { return x; }` en C++.' | Should Match '\[\]\(int x\) \{ return x; \}'
    }
    It 'keeps only the label of a markdown image, and drops one that has none' {
        Get-CleanedText -Text 'Vea ![alt](img/x.png)' | Should Be 'Vea alt'
        $result = Get-CleanedText -Text 'Mirá ![](x.png) y ![captura](img/foo.png) listo'
        $result | Should Not Match '[!\[\]()]'
        $result | Should Match 'captura'
    }
    It 'finds the file names in a chunk of separator-free text broken only by non-ASCII characters in little time' {
        # No whitespace and no separator for about 4700 characters, in ASCII runs of 295 that
        # the word caps let through.
        $block = ('.a.sh' * 59) + [string][char]0xA1
        $text = ($block * 16) + ' ver README.md ok'
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = ConvertTo-SpokenFileNames -Text $text
        $watch.Stop()
        $result | Should Match 'ver README punto md ok$'
        $watch.Elapsed.TotalSeconds | Should BeLessThan 3
    }
    It 'keeps the first of two file names separated by a slash' {
        ConvertTo-SpokenFileNames -Text 'lee README.md/otro.md' | Should Be 'lee README punto md/otro.md'
        ConvertTo-SpokenFileNames -Text 'Edita package.json/tsconfig.json' | Should Match '^Edita package punto json'
    }
    It 'keeps the text glued to a URL' {
        $tail = [string][char]0x7136 * 3
        $comma = [string][char]0xFF0C
        ConvertTo-SpokenUrls -Text ('https://example.cn/docs' + $comma + $tail) | Should Be ('el link de example' + $comma + $tail)
        $dash = [string][char]0x2014
        ConvertTo-SpokenUrls -Text ('https://x.com/a' + $dash + 'y luego') | Should Be ('el link de x' + $dash + 'y luego')
    }
    It 'keeps the text glued around a file name written between backticks' {
        $head = [string][char]0x4FEE * 3
        $tail = [string][char]0x4E2A * 2
        ConvertTo-SpokenReferences -Text ($head + '`src/main.py`' + $tail) | Should Be ($head + '`main punto py`' + $tail)
    }
    It 'reads a Windows path whose folders are written in Chinese, Japanese, Korean or Thai' {
        $user = [string][char]0x5F20 + [char]0x4E09
        $thai = [string][char]0x0E2A + [char]0x0E21 + [char]0x0E0A + [char]0x0E32 + [char]0x0E22
        ConvertTo-SpokenFileNames -Text ('C:\Users\' + $user + '\Documents\report.pdf') | Should Be 'report punto pdf'
        ConvertTo-SpokenFileNames -Text ('C:\Users\' + $thai + '\Desktop\a.txt') | Should Be 'a punto txt'
        ConvertTo-SpokenPaths -Text ('C:\Users\' + $user + '\AppData\Local\Temp') | Should Be 'Temp'
    }
    It 'does not let one path swallow the text up to the next one in unspaced Chinese or Japanese text' {
        $and = [string][char]0x548C
        $fullComma = [string][char]0xFF0C
        $user = [string][char]0x5F20 + [char]0x4E09
        $tick = [string][char]96
        ConvertTo-SpokenReferences -Text ($tick + 'C:\Users\' + $user + '\a.py' + $tick + $and + $tick + 'C:\Users\' + $user + '\b.py' + $tick) | Should Be ($tick + 'a punto py' + $tick + $and + $tick + 'b punto py' + $tick)
        ConvertTo-SpokenReferences -Text 'C:\Users\bob\a.js,C:\Users\bob\b.js' | Should Be 'a punto js,b punto js'
        # Names glued to the text are not converted, but nothing between the two paths is dropped.
        $glued = ConvertTo-SpokenReferences -Text ('C:\Users\bob\a.js' + $and + 'C:\Users\bob\b.js')
        $glued | Should Be ('a.js' + $and + 'b punto js')
        $head = [string][char]0x6BD4 + [char]0x8F83
        $tail = [string][char]0x6587
        $both = ConvertTo-SpokenReferences -Text ($head + 'C:\Users\bob\a.js' + $and + 'C:\Users\bob\b.js' + $tail)
        $both | Should Be ($head + 'a.js' + $and + 'C:\Users\bob\b.js' + $tail)
        ConvertTo-SpokenReferences -Text ('C:\Users\bob\Docs' + $and + 'C:\Users\bob\Other') | Should Be ('Docs' + $and + 'C:\Users\bob\Other')
        ConvertTo-SpokenReferences -Text ('C:\Users\' + $user + '\a.json' + $fullComma + 'D:\out\b.log') | Should Be ('a punto json' + $fullComma + 'b punto log')
    }
    It 'treats the Chinese enumeration comma and full stop as the end of a file name' {
        $enumeration = [string][char]0x3001
        $stop = [string][char]0x3002
        ConvertTo-SpokenReferences -Text ('src/a.py' + $enumeration + 'src/b.py' + $stop) | Should Be ('a punto py' + $enumeration + 'b punto py' + $stop)
    }
    It 'ends a file name at punctuation that follows its extension' {
        ConvertTo-SpokenReferences -Text 'src/a.js,src/b.js' | Should Be 'a punto js,b punto js'
        ConvertTo-SpokenReferences -Text 'src/a.js;src/b.js' | Should Be 'a punto js;b punto js'
        ConvertTo-SpokenReferences -Text 'src/a.js!src/b.js' | Should Be 'a punto js!b punto js'
        ConvertTo-SpokenReferences -Text 'src/a.js)src/b.js' | Should Be 'a punto js)b punto js'
    }
    It 'keeps the text between two paths whichever script it is written in' {
        # Thai, Korean (jamo and syllables), Japanese (hiragana, katakana), fullwidth and Chinese text.
        foreach ($code in 0x0E2A, 0x1100, 0x3042, 0x30A2, 0xAC00, 0xFF21, 0x4FEE) {
            $text = 'x src/a' + [char]$code + 'src/b.py y'
            ConvertTo-SpokenReferences -Text $text | Should Be $text
        }
    }
    It 'keeps the word in front of a path that is set off with dashes, quotes or an ellipsis' {
        $em = [string][char]0x2014
        $en = [string][char]0x2013
        $open = [string][char]0x201C
        $close = [string][char]0x201D
        Get-CleanedText -Text ('the main file' + $em + 'src/main.py' + $em + 'handles it') | Should Be 'the main file, main punto py, handles it'
        Get-CleanedText -Text ('the main file' + $en + 'src/main.py' + $en + 'handles it') | Should Be 'the main file, main punto py, handles it'
        ConvertTo-SpokenReferences -Text ('the main file' + $open + 'src/main.py' + $close + ' ok') | Should Be ('the main file' + $open + 'main punto py' + $close + ' ok')
        ConvertTo-SpokenReferences -Text ('the main file' + [char]0x2026 + 'C:\Users\bob\app.json') | Should Be ('the main file' + [char]0x2026 + 'app punto json')
        Get-CleanedText -Text ('stack' + $em + 'MongoDB/Express/Node.js' + $em + 'ok') | Should Be 'stack, MongoDB/Express/Node punto js, ok'
    }
    It 'keeps the word in front of a path set off with any typographic quote, hyphen or guillemet' {
        foreach ($code in (0x2010..0x2027) + 0x00AB + 0x00BB) {
            ConvertTo-SpokenReferences -Text ('abre' + [char]$code + 'src/main.py') | Should Be ('abre' + [char]$code + 'main punto py')
        }
        ConvertTo-SpokenReferences -Text ('x' + [char]0xAB + 'src/main.py' + [char]0xBB) | Should Be ('x' + [char]0xAB + 'main punto py' + [char]0xBB)
    }
    It 'keeps the name of a flag or a variable that is joined to a path with "="' {
        Get-CleanedText -Text 'run --config=cfg/app.json y --file=src/main.py' | Should Be 'run --config=app punto json y --file=main punto py'
        Get-CleanedText -Text 'export CONFIG=/etc/app/conf.json' | Should Be 'export CONFIG=conf punto json'
        Get-CleanedText -Text 'x=src/main.py;y=src/b.py' | Should Be 'x=main punto py;y=b punto py'
        Get-CleanedText -Text 'NAME=C:\Users\Me\a.txt' | Should Be 'NAME=a punto txt'
    }
    It 'keeps the call or the command written right before a path' {
        Get-CleanedText -Text "Use require('./config/app.json') to load it." | Should Be "Use require('app punto json') to load it."
        Get-CleanedText -Text 'Call readFile(src/a.js) now' | Should Be 'Call readFile(a punto js) now'
        Get-CleanedText -Text 'open(path/to/file.txt)' | Should Be 'open(file punto txt)'
        Get-CleanedText -Text 'cd app;./run.sh' | Should Be 'cd app;run punto sh'
        Get-CleanedText -Text 'cd app&&./run.sh' | Should Be 'cd app&&run punto sh'
        Get-CleanedText -Text 'foo,bar/baz.js' | Should Be 'foo,baz punto js'
        Get-CleanedText -Text 'cat <in/data.json' | Should Be 'cat <data punto json'
        Get-CleanedText -Text 'PATH=C:\bin;C:\tools\x.exe' | Should Be 'PATH=bin;x punto exe'
        Get-CleanedText -Text 'C:\bin,C:\tools\x.exe' | Should Be 'bin,x punto exe'
    }
    It 'ends the last folder of a drive path at a space or at the punctuation that closes it' {
        ConvertTo-SpokenPaths -Text 'Copiá C:\Projects\App y luego C:\Other\Thing por favor' | Should Be 'Copiá App y luego Thing por favor'
        ConvertTo-SpokenPaths -Text 'Ver C:\temp/out y/o C:\tmp' | Should Be 'Ver out y/o tmp'
        ConvertTo-SpokenPaths -Text 'C:\a\b,C:\c\d' | Should Be 'b,d'
        ConvertTo-SpokenPaths -Text 'PATH=C:\bin;C:\tools' | Should Be 'PATH=bin;tools'
        ConvertTo-SpokenPaths -Text '(C:\a\b)(C:\c\d)' | Should Be '(b)(d)'
        $tick = [string][char]96
        ConvertTo-SpokenPaths -Text ($tick + 'C:\a\b' + $tick + $tick + 'C:\c\d' + $tick) | Should Be ($tick + 'b' + $tick + $tick + 'd' + $tick)
    }
    It 'reads a dotfile written inside parentheses' {
        Get-CleanedText -Text 'abri (.env) y (.mcp.json)' | Should Be 'abri (punto env) y (punto mcp punto json)'
    }
    It 'ends a drive folder at a pipe' {
        Get-CleanedText -Text 'C:\Users\Smith|John\a.txt' | Should Be 'Smith|a punto txt'
    }
    It 'reads long folder names' {
        Get-CleanedText -Text 'Abri src/components-library-shared/button.tsx ya' | Should Be 'Abri button punto tsx ya'
        Get-CleanedText -Text 'C:\Users\maria-fernanda-gonzalez\documentos-compartidos\informe.pdf' | Should Be 'informe punto pdf'
    }
    It 'ends a drive folder at a typographic dash' {
        Get-CleanedText -Text ('C:\Users\bob\a' + [char]0x2014 + 'b\c.txt') | Should Be 'a, c punto txt'
    }
    It 'keeps the variable name in front of a dotfile joined with an equals sign' {
        ConvertTo-SpokenReferences -Text 'export FILE=src/.env' | Should Be 'export FILE=src/.env'
        ConvertTo-SpokenReferences -Text 'DOTENV=./.env' | Should Be 'DOTENV=./.env'
    }
    It 'keeps what is written right before a path, whichever glue character joins them' {
        Get-CleanedText -Text 'run $(pwd)/src/main.py now' | Should Be 'run $(pwd)main punto py now'
        Get-CleanedText -Text 'cd ${HOME}/src/main.py' | Should Be 'cd ${HOME}main punto py'
        Get-CleanedText -Text 'items[0]/src/data.json' | Should Be 'items[0]data punto json'
        Get-CleanedText -Text 'echo hi>out/log.txt' | Should Be 'echo hi>log punto txt'
        Get-CleanedText -Text 'cat x|src/b.js' | Should Be 'cat x|b punto js'
        Get-CleanedText -Text 'see [docs/readme.md]' | Should Be 'see [readme punto md]'
        Get-CleanedText -Text 'say "src/a.js" now' | Should Be 'say "a punto js" now'
    }
    It 'reads the file of a route whose folders are written as [id] or (group)' {
        Get-CleanedText -Text 'Editá app/[id]/page.tsx y app/(auth)/login/page.tsx.' | Should Be 'Editá page punto tsx y page punto tsx.'
        Get-CleanedText -Text 'src/routes/[[optional]]/page.svelte' | Should Be 'page punto svelte'
        Get-CleanedText -Text 'app/[...slug]/route.ts' | Should Be 'route punto ts'
        Get-CleanedText -Text '(src/main.py)' | Should Be '(main punto py)'
        Get-CleanedText -Text '[id]/page.tsx es la ruta' | Should Be 'page punto tsx es la ruta'
        Get-CleanedText -Text 'open (auth)/login/page.tsx' | Should Be 'open page punto tsx'
        Get-CleanedText -Text 'see [1]docs/readme.md now' | Should Be 'see [1]readme punto md now'
        Get-CleanedText -Text '[src/main.py]' | Should Be '[main punto py]'
    }
    It 'still reads a drive path whose folder name has parentheses, an ampersand or an equals sign' {
        Get-CleanedText -Text 'C:\App(x86)\a.exe' | Should Be 'a punto exe'
        Get-CleanedText -Text 'C:\Users\me\App(1.0)\bin\a.exe' | Should Be 'a punto exe'
        Get-CleanedText -Text 'C:\R&D\a.txt' | Should Be 'a punto txt'
        Get-CleanedText -Text 'C:\Users\O''Brien\a.txt' | Should Be 'a punto txt'
        Get-CleanedText -Text 'C:\Docs\[old]\a.txt' | Should Be 'a punto txt'
        Get-CleanedText -Text 'C:\Docs\{3F2A-91}\a.txt' | Should Be 'a punto txt'
    }
    It 'does not read on from a drive path into the path after a separator that joins them' {
        Get-CleanedText -Text '["C:\a\b","src/x.js"]' | Should Be '["b","x punto js"]'
        Get-CleanedText -Text '(C:\Projects\App),(src/x.js)' | Should Be '(App),(x punto js)'
        Get-CleanedText -Text 'copy C:\Projects\App,src/x.js now' | Should Be 'copy App,x punto js now'
        Get-CleanedText -Text 'dirs: C:\data\in;out/log.txt' | Should Be 'dirs: in;log punto txt'
        Get-CleanedText -Text 'C:\a\b)(src/x.js)' | Should Be 'b)(x punto js)'
    }
    It 'still reads a drive path whose folder name has an equals sign' {
        Get-CleanedText -Text 'C:\a=b\c.txt' | Should Be 'c punto txt'
    }
    It 'keeps Hangul compatibility jamo and Bopomofo glued in front of a path' {
        $text = [string][char]0x314B + [char]0x314B + 'src/main.py'
        ConvertTo-SpokenReferences -Text $text | Should Be $text
    }
    It 'reads a name that looks like a list of two files as one file name and keeps the first' {
        ConvertTo-SpokenReferences -Text 'lee README.md/otro.md y mas' | Should Be 'lee README punto md/otro.md y mas'
    }
    It 'keeps a folder whose name starts like a known extension' {
        foreach ($folder in 'my.js.d', 'my.js-lib', 'my.js_v2', 'my.js2') {
            ConvertTo-SpokenReferences -Text "x/$folder/y.py" | Should Be 'y punto py'
        }
    }
    It 'ends the last folder of a drive path at Chinese punctuation even when the name starts with a symbol' {
        ConvertTo-SpokenPaths -Text ('C:\a\-' + [char]0x3001 + 'b') | Should Be ('a-' + [char]0x3001 + 'b')
    }
    It 'swallows nothing before any CJK punctuation or fullwidth form that follows a drive path' {
        foreach ($code in (0x3000..0x303F) + (0xFF00..0xFFEF)) {
            $text = 'C:\Users\bob\Docs' + [char]$code + 'src/main.py'
            ConvertTo-SpokenReferences -Text $text | Should Match ('Docs' + [regex]::Escape([string][char]$code))
        }
    }
    It 'does not take a drive letter that follows a digit, a letter or an underscore' {
        foreach ($text in 'x1C:\data\app y', '9C:\data\app', 'a_C:\data\app') {
            ConvertTo-SpokenPaths -Text $text | Should Be $text
        }
    }
    It 'does not take a drive letter that follows a backslash' {
        ConvertTo-SpokenPaths -Text '\\?\C:\Users\x\proyecto' | Should Be '\\?\C:\Users\x\proyecto'
    }
    It 'drops the trailing slash of a drive path written with forward slashes' {
        ConvertTo-SpokenPaths -Text 'C:/Users/x/datos/' | Should Be 'datos'
    }
    It 'ends a drive path at Chinese punctuation instead of reading on into the next path' {
        $enumeration = [string][char]0x3001
        $fullComma = [string][char]0xFF0C
        ConvertTo-SpokenReferences -Text ('C:\Users\bob\Docs' + $enumeration + 'src/main.py') | Should Be ('Docs' + $enumeration + 'main punto py')
        ConvertTo-SpokenReferences -Text ('C:\Users\bob\Docs' + $enumeration + 'C:\Users\bob\Other') | Should Be ('Docs' + $enumeration + 'Other')
        ConvertTo-SpokenReferences -Text ('C:\Users\bob\Docs' + $fullComma + '/etc/hosts') | Should Be ('Docs' + $fullComma + '/etc/hosts')
    }
    It 'does not leave a drive letter behind when the path is glued to Chinese text' {
        $head = [string][char]0x4FEE * 3
        ConvertTo-SpokenReferences -Text ($head + 'C:\x\main.py') | Should Be ($head + 'main punto py')
    }
    It 'reads absolute POSIX and UNC paths as their file name' {
        ConvertTo-SpokenReferences -Text 'abrí /home/user/app/main.py ya' | Should Be 'abrí main punto py ya'
        ConvertTo-SpokenReferences -Text '/home/me/.config/app/settings.json' | Should Be 'settings punto json'
        ConvertTo-SpokenReferences -Text 'mirá /home/me/.bashrc' | Should Be 'mirá punto bashrc'
        ConvertTo-SpokenReferences -Text '\\server\share\file.txt' | Should Be 'file punto txt'
    }
    It 'adds no period after the full stop of Chinese or Japanese text' {
        $line = ([string][char]0x4F7F * 3) + [char]0x3002
        Get-CleanedText -Text ($line + "`n" + $line + "`n" + 'fin') | Should Be ($line + "`n" + $line + "`nfin")
    }
}

Describe 'ConvertTo-SpokenReferences with very long words' {
    It 'still speaks a long URL, whose site is what matters' {
        ConvertTo-SpokenReferences -Text ('mirá https://example.com/' + ('a' * 500) + ' ya') | Should Be 'mirá el link de example ya'
    }
    It 'drops a long unbroken run that is not a URL before the file-name steps see it' {
        $text = ('a/' * 200) + ' fin'
        ConvertTo-SpokenReferences -Text $text | Should Match '^\s*fin$'
    }
    It 'reads a Windows path of ordinary length' {
        ConvertTo-SpokenReferences -Text 'abrí C:\Users\x\proyectos\app\src\index.js ya' | Should Be 'abrí index punto js ya'
    }
}

Describe 'ConvertTo-SpokenReferences' {
    It 'handles the URL before the file-name rule can cut into it' {
        ConvertTo-SpokenReferences -Text 'https://docs.python.org/3/library/os.html y scripts/common.ps1' | Should Be 'el link de python y common punto ps1'
    }
}

Describe 'Respellings' {
    $files = @(Get-ChildItem "$repoRoot\scripts\lib\respellings" -Filter *.psd1)

    It 'has one file per two- or three-letter language code' {
        $files.Count | Should BeGreaterThan 0
        @($files | Where-Object { $_.BaseName -cnotmatch '^[a-z]{2,3}$' }).Count | Should Be 0
    }
    foreach ($file in $files) {
        $table = Import-PowerShellDataFile -Path $file.FullName

        It "$($file.Name) maps single lowercase words to single words" {
            @($table.GetEnumerator() | Where-Object { $_.Name -cnotmatch '^[a-z]+$' }).Count | Should Be 0
            @($table.Values | Where-Object { $_ -notmatch '^[\p{L}]+$' }).Count | Should Be 0
        }
    }

    It 'respells natural so the Spanish voices stress its last syllable' {
        (Get-Respellings -Language 'es-ES')['natural'] | Should Be 'naturál'
    }
    It 'gives every Spanish variant the Spanish table and other languages none' {
        (Get-Respellings -Language 'es-MX').Contains('natural') | Should Be $true
        (Get-Respellings -Language 'en-US').Count | Should Be 0
        (Get-Respellings -Language '../x').Count | Should Be 0
    }
}

Describe 'ConvertTo-RespelledText' {
    $table = @{ natural = 'naturál' }

    It 'respells a whole word' {
        ConvertTo-RespelledText -Text 'esto es natural.' -Respellings $table | Should Be 'esto es naturál.'
    }
    It 'keeps the capitalization' {
        ConvertTo-RespelledText -Text 'Natural y NATURAL' -Respellings $table | Should Be 'Naturál y NATURÁL'
    }
    It 'leaves words that merely contain it alone' {
        ConvertTo-RespelledText -Text 'naturaleza y sobrenatural' -Respellings $table | Should Be 'naturaleza y sobrenatural'
    }
    It 'leaves the text alone when there are no respellings or it is empty' {
        ConvertTo-RespelledText -Text 'natural' -Respellings @{} | Should Be 'natural'
        ConvertTo-RespelledText -Text '' -Respellings $table | Should Be ''
    }
}

Describe 'Pronunciation dictionaries' {
    $files = @(Get-ChildItem "$repoRoot\scripts\lib\pronunciations" -Filter *.psd1)

    It 'has one file per two- or three-letter language code' {
        $files.Count | Should BeGreaterThan 0
        @($files | Where-Object { $_.BaseName -cnotmatch '^[a-z]{2,3}$' }).Count | Should Be 0
    }
    foreach ($file in $files) {
        $dictionary = Import-PowerShellDataFile -Path $file.FullName

        It "$($file.Name) only has single lowercase word entries" {
            @($dictionary.GetEnumerator() | Where-Object { $_.Name -cnotmatch '^[a-z]+$' }).Count | Should Be 0
        }
        It "$($file.Name) never uses characters that would break the SSML attribute" {
            @($dictionary.GetEnumerator() | Where-Object { $_.Value -match "['&<>""]" }).Count | Should Be 0
        }
        It "$($file.Name) has a pronunciation for every entry" {
            @($dictionary.GetEnumerator() | Where-Object { -not $_.Value }).Count | Should Be 0
        }
    }
}

Describe 'Get-PronunciationDictionary' {
    It 'gives the Spanish dictionary to every Spanish variant' {
        foreach ($language in 'es', 'es-ES', 'es-MX', 'es-AR', 'ES-es') {
            (Get-PronunciationDictionary -Language $language).Contains('git') | Should Be $true
        }
    }
    It 'gives nothing to a language that has no dictionary' {
        foreach ($language in 'en-US', 'pt-BR', 'ja-JP', 'xx') {
            (Get-PronunciationDictionary -Language $language).Count | Should Be 0
        }
    }
    It 'leaves ordinary Spanish words to the voice, not to an English pronunciation' {
        $dictionary = Get-PronunciationDictionary -Language 'es'
        foreach ($word in 'error', 'terminal') { $dictionary.Contains($word) | Should Be $false }
    }
    It 'gives nothing for an empty or unusable language' {
        foreach ($language in $null, '', '  ', '../x', 'e s', '123') {
            (Get-PronunciationDictionary -Language $language).Count | Should Be 0
        }
    }
    It 'reads a dictionary from a folder whose name has square brackets' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('sapi-voice-kit-dict [1] ' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$root\pronunciations" -Force | Out-Null
        [System.IO.File]::WriteAllText("$root\pronunciations\zy.psd1", "@{ 'hola' = 'ola' }", (New-Object System.Text.UTF8Encoding($true)))
        $realRoot = $script:LanguageTablesRoot
        $script:LanguageTablesRoot = $root
        try { (Get-PronunciationDictionary -Language 'zy-ZY')['hola'] | Should Be 'ola' }
        finally {
            $script:LanguageTablesRoot = $realRoot
            $script:LanguageTables.Remove('pronunciations/zy')
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
    It 'uses a dictionary file as soon as one is added for a language' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('sapi-voice-kit-dict-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$root\pronunciations" -Force | Out-Null
        [System.IO.File]::WriteAllText("$root\pronunciations\zz.psd1", "@{ 'hola' = 'ˈola' }", (New-Object System.Text.UTF8Encoding($true)))
        $realRoot = $script:LanguageTablesRoot
        $script:LanguageTablesRoot = $root
        try { (Get-PronunciationDictionary -Language 'zz-ZZ')['hola'] | Should Be 'ˈola' }
        finally {
            $script:LanguageTablesRoot = $realRoot
            $script:LanguageTables.Remove('pronunciations/zz')
            Remove-Item $root -Recurse -Force
        }
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
    It 'drops control characters, which are not valid XML' {
        $ssml = ConvertTo-OneCoreSsml -Text "hola$([char]27)$([char]1) mundo" -Language 'es-ES' -Dictionary @{}
        $ssml | Should Match '>hola mundo<'
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
        It 'keeps the language of the failed voice instead of the configured one' {
            $english = [pscustomobject]@{ Engine = 'OneCore'; Name = 'Microsoft Guy'; Language = 'en-US'; Gender = 'Male'; Native = 'native-guy' }
            $fallback = Get-FallbackVoice -Failed $english -Config @{ language = 'es-ES' }
            $fallback.Name | Should Be 'Microsoft Zira Desktop'
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
        # A Windows mutex is re-entrant for the thread that owns it, so a second call
        # from the same thread would pass even without the release: it is checked
        # from another thread.
        $probe = New-Object System.Threading.Mutex($false, $name)
        $shell = [powershell]::Create()
        try {
            { Invoke-WithNamedMutex -Name $name -TimeoutMs 1000 -Action { throw 'boom' } } | Should Throw
            $shell.Runspace = [runspacefactory]::CreateRunspace()
            $shell.Runspace.ThreadOptions = 'UseNewThread'
            $shell.Runspace.Open()
            $null = $shell.AddScript({ param($m) $got = $m.WaitOne(500); if ($got) { $m.ReleaseMutex() }; $got }).AddArgument($probe)
            @($shell.Invoke())[0] | Should Be $true
        } finally {
            $shell.Dispose()
            $probe.Dispose()
        }
    }
    It 'runs anyway, and says so, when another process holds the mutex too long' {
        $holder = Start-Job -ArgumentList $name -ScriptBlock {
            param($name)
            $mutex = New-Object System.Threading.Mutex($false, $name)
            [void]$mutex.WaitOne()
            'held'
            Start-Sleep -Seconds 4
            $mutex.ReleaseMutex()
        }
        # Wait until the other process really has the mutex, however long it takes to start.
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline -and -not (@(Receive-Job $holder -Keep) -contains 'held')) { Start-Sleep -Milliseconds 100 }
        $messages = New-Object System.Collections.Generic.List[string]
        $log = { param([string]$Message) $messages.Add($Message) }.GetNewClosure()
        $result = Invoke-WithNamedMutex -Name $name -TimeoutMs 300 -Log $log -Action { 'ran' }
        Remove-Job $holder -Force
        $result | Should Be 'ran'
        ($messages -join ' ') | Should Match 'timed out'
    }
}

Describe 'Config store' {
    BeforeEach { Use-FakeDataDir }
    AfterEach { Remove-FakeDataDir }

    It 'keeps its data in SAPI_VOICE_DATA_DIR when that is set' {
        Get-SharedDataDir | Should Be $script:fakeDataDir
    }
    It 'falls back to the user profile when it is not set' {
        Remove-Item Env:\SAPI_VOICE_DATA_DIR
        $dir = Get-SharedDataDir
        $dir | Should Not Be $script:fakeDataDir
        $dir | Should Match 'sapi-voice-kit-shared$'
    }

    It 'keeps its settings in a data folder whose name has square brackets' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('sapi-voice-kit-data [1] ' + [Guid]::NewGuid().ToString('N'))
        $env:SAPI_VOICE_DATA_DIR = $dir
        try {
            Save-VoiceConfig -Changes @{ mode = 'literal' }
            (Get-VoiceConfig).mode | Should Be 'literal'
            Request-ActiveSpeech | Should Be $true
            Request-ActiveSpeech | Should Be $false
        } finally {
            $env:SAPI_VOICE_DATA_DIR = $script:fakeDataDir
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
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
    It 'removes settings without touching the others' {
        Save-VoiceConfig -Changes @{ voiceName = 'Microsoft Laura'; rate = 2 } | Out-Null
        Save-VoiceConfig -Remove @('voiceName') | Out-Null
        $config = Get-VoiceConfig
        $config.Contains('voiceName') | Should Be $false
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
    It 'treats a config that is a bare number, string or boolean as damaged' {
        foreach ($content in '5', '"texto"', 'true') {
            Remove-Item (Get-DataFilePath 'config.json*') -Force -ErrorAction SilentlyContinue
            Initialize-SharedDataDir | Out-Null
            Set-Content -Path (Get-DataFilePath 'config.json') -Value $content
            Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
            (@((Get-Content (Get-DataFilePath 'config.json') -Raw | ConvertFrom-Json).psobject.Properties.Name) -join ',') | Should Be 'local'
            Test-Path (Get-DataFilePath 'config.json.bad') | Should Be $true
        }
    }
    It 'treats a config whose section is not an object as damaged' {
        foreach ($content in '{"local":[1,2]}', '{"local":"texto"}') {
            Remove-Item (Get-DataFilePath 'config.json*') -Force -ErrorAction SilentlyContinue
            Initialize-SharedDataDir | Out-Null
            Set-Content -Path (Get-DataFilePath 'config.json') -Value $content
            (Get-VoiceConfig).Count | Should Be 0
            Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
            (Get-VoiceConfig).mode | Should Be 'active'
            @((Get-VoiceConfig).Keys | Where-Object { $_ -ne 'mode' }).Count | Should Be 0
            Test-Path (Get-DataFilePath 'config.json.bad') | Should Be $true
        }
    }
    It 'treats a config that is a JSON list as damaged, instead of saving its properties as sections' {
        Initialize-SharedDataDir | Out-Null
        Set-Content -Path (Get-DataFilePath 'config.json') -Value '[1, 2]'
        (Get-VoiceConfig).Count | Should Be 0
        Save-VoiceConfig -Changes @{ mode = 'active' } | Out-Null
        (@((Get-Content (Get-DataFilePath 'config.json') -Raw | ConvertFrom-Json).psobject.Properties.Name) -join ',') | Should Be 'local'
        Test-Path (Get-DataFilePath 'config.json.bad') | Should Be $true
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
    BeforeEach { Use-FakeDataDir }
    AfterEach { Remove-FakeDataDir }

    # Separate powershell.exe processes (Start-Job) all writing at once. Without
    # the lock this loses updates.
    It 'loses no write when 10 processes save at the same time' {
        $dataDir = $script:fakeDataDir
        $jobs = 1..10 | ForEach-Object {
            Start-Job -ArgumentList "$repoRoot\scripts\common.ps1", $dataDir, $_ -ScriptBlock {
                param($common, $dataDir, $i)
                $env:SAPI_VOICE_DATA_DIR = $dataDir
                . $common
                Save-VoiceConfig -Changes @{ "setting$i" = $true } | Out-Null
            }
        }
        $jobs | Wait-Job -Timeout 90 | Out-Null
        $failures = @($jobs | Where-Object { $_.State -ne 'Completed' })
        $jobs | Remove-Job -Force

        $config = Get-VoiceConfig
        $missing = @(1..10 | Where-Object { -not $config.Contains("setting$_") })
        $failures.Count | Should Be 0
        $missing.Count | Should Be 0
    }
}

Describe 'Duplicate-speech guard' {
    BeforeEach { Use-FakeDataDir }
    AfterEach { Remove-FakeDataDir }

    It 'sees no recent speech at first' {
        Test-RecentActiveSpeech | Should Be $false
    }
    It 'sees speech that was just recorded' {
        Set-RecentSpeechMarker
        Test-RecentActiveSpeech | Should Be $true
    }
    It 'forgets speech older than the window' {
        Initialize-SharedDataDir | Out-Null
        $old = [DateTime]::UtcNow.AddSeconds(-($script:SpeechGuardWindowSeconds + 5)).Ticks
        Set-Content -Path (Get-DataFilePath '.last-active-speech') -Value "$old"
        Test-RecentActiveSpeech | Should Be $false
    }
    It 'does not count a marker dated in the future as recent speech' {
        Initialize-SharedDataDir | Out-Null
        $future = [DateTime]::UtcNow.AddHours(1).Ticks
        Set-Content -Path (Get-DataFilePath '.last-active-speech') -Value "$future"
        Test-RecentActiveSpeech | Should Be $false
    }
    It 'lets the first caller speak and turns the next one away' {
        Request-ActiveSpeech | Should Be $true
        Request-ActiveSpeech | Should Be $false
    }
    It 'lets a caller speak again once the window has passed' {
        Initialize-SharedDataDir | Out-Null
        $old = [DateTime]::UtcNow.AddSeconds(-($script:SpeechGuardWindowSeconds + 5)).Ticks
        Set-Content -Path (Get-DataFilePath '.last-active-speech') -Value "$old"
        Request-ActiveSpeech | Should Be $true
    }
    It 'treats an unreadable marker as no recent speech' {
        Initialize-SharedDataDir | Out-Null
        Set-Content -Path (Get-DataFilePath '.last-active-speech') -Value 'garbage'
        Test-RecentActiveSpeech | Should Be $false
    }
    It 'gives the claim back, so a retry after a failed speech is not turned away' {
        Request-ActiveSpeech | Should Be $true
        Clear-RecentSpeechMarker
        Request-ActiveSpeech | Should Be $true
    }
    It 'stores a timestamp only, never text' {
        Set-RecentSpeechMarker
        (Get-Content -Path (Get-DataFilePath '.last-active-speech') -Raw).Trim() | Should Match '^\d+$'
    }
}

Describe 'Debug files' {
    BeforeEach { Use-FakeDataDir }
    AfterEach { Remove-FakeDataDir }

    It 'removes the copy of the last text and the logs, and nothing else' {
        Initialize-SharedDataDir | Out-Null
        foreach ($name in 'last-text.txt', 'log-say.txt', 'log-speak.txt', 'config.json', '.last-active-speech') {
            Set-Content -Path (Get-DataFilePath $name) -Value 'x'
        }
        Remove-DebugFiles
        (Get-ChildItem (Get-SharedDataDir) -Force -Name | Sort-Object) -join ',' | Should Be '.last-active-speech,config.json'
    }
    It 'does nothing when there is no data folder yet' {
        { Remove-DebugFiles } | Should Not Throw
        Test-Path (Get-SharedDataDir) | Should Be $false
    }
}

Describe 'A data folder whose name has square brackets' {
    BeforeEach {
        Use-FakeDataDir
        $script:bracketDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sapi-voice-kit-data [2] ' + [Guid]::NewGuid().ToString('N'))
        $env:SAPI_VOICE_DATA_DIR = $script:bracketDir
    }
    AfterEach {
        Remove-Item -LiteralPath $script:bracketDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-FakeDataDir
    }

    It 'replaces an existing config.json when settings are saved again' {
        Save-VoiceConfig -Changes @{ mode = 'literal' }
        Save-VoiceConfig -Changes @{ mode = 'summary' }
        (Get-VoiceConfig).mode | Should Be 'summary'
    }
    It 'sets a damaged config.json aside' {
        Save-VoiceConfig -Changes @{ mode = 'literal' }
        [System.IO.File]::WriteAllText((Join-Path $script:bracketDir 'config.json'), 'not json')
        Save-VoiceConfig -Changes @{ mode = 'summary' }
        (Get-VoiceConfig).mode | Should Be 'summary'
        Test-Path -LiteralPath (Join-Path $script:bracketDir 'config.json.bad') | Should Be $true
    }
    It 'replaces an earlier damaged copy when config.json is damaged a second time' {
        Save-VoiceConfig -Changes @{ mode = 'literal' }
        $config = Join-Path $script:bracketDir 'config.json'
        [System.IO.File]::WriteAllText($config, 'first damage')
        Save-VoiceConfig -Changes @{ mode = 'summary' }
        [System.IO.File]::WriteAllText($config, 'second damage')
        Save-VoiceConfig -Changes @{ mode = 'active' }
        (Get-VoiceConfig).mode | Should Be 'active'
        [System.IO.File]::ReadAllText($config + '.bad') | Should Be 'second damage'
    }
    It 'fails the first save when the temporary file cannot be moved into place' {
        New-Item -ItemType Directory -Path $script:bracketDir -Force | Out-Null
        $temp = Join-Path $script:bracketDir 'config.json.tmp'
        $held = New-Object System.IO.FileStream($temp, 'OpenOrCreate', 'Read', 'ReadWrite')
        try { { Save-VoiceConfig -Changes @{ mode = 'literal' } } | Should Throw }
        finally { $held.Dispose() }
        Test-Path -LiteralPath (Join-Path $script:bracketDir 'config.json') | Should Be $false
    }
    It 'removes its temporary file when the save fails, so no copy of the settings is left behind' {
        Save-VoiceConfig -Changes @{ mode = 'literal' }
        $config = Join-Path $script:bracketDir 'config.json'
        $held = [System.IO.File]::Open($config, 'Open', 'Read', 'Read')
        try { { Save-VoiceConfig -Changes @{ mode = 'natural' } } | Should Throw }
        finally { $held.Dispose() }
        Test-Path -LiteralPath ($config + '.tmp') | Should Be $false
        (Get-VoiceConfig).mode | Should Be 'literal'
    }
    It 'reports a failed save once, without a second error about the temporary file it could not delete' {
        New-Item -ItemType Directory -Path $script:bracketDir -Force | Out-Null
        $held = New-Object System.IO.FileStream((Join-Path $script:bracketDir 'config.json.tmp'), 'OpenOrCreate', 'Read', 'ReadWrite')
        try {
            $ErrorActionPreference = 'Continue'
            $records = @(& { try { Save-VoiceConfig -Changes @{ mode = 'literal' } } catch { 'thrown' } } 2>&1)
        } finally { $held.Dispose() }
        $records.Count | Should Be 1
        $records[0] | Should Be 'thrown'
    }
    It 'does not overwrite a damaged config.json when it cannot be set aside' {
        Save-VoiceConfig -Changes @{ mode = 'literal' }
        $config = Join-Path $script:bracketDir 'config.json'
        [System.IO.File]::WriteAllText($config, 'not json')
        [System.IO.File]::WriteAllText($config + '.bad', 'earlier copy')
        $held = [System.IO.File]::Open($config + '.bad', 'Open', 'ReadWrite', 'None')
        try {
            { Save-VoiceConfig -Changes @{ mode = 'summary' } } | Should Throw
        } finally { $held.Dispose() }
        [System.IO.File]::ReadAllText($config) | Should Be 'not json'
    }
    It 'writes, trims and removes the debug files' {
        $script:LogMaxBytes = 200
        $script:LogKeepLines = 3
        try {
            $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
            1..30 | ForEach-Object { $log.Invoke("line number $_ padded to be long enough") }
            @(Get-Content -LiteralPath (Join-Path $script:bracketDir 'log-test.txt')).Count | Should BeLessThan 10
            (Get-Content -LiteralPath (Join-Path $script:bracketDir 'log-test.txt') -Raw) | Should Match 'line number 28'
            (Get-Content -LiteralPath (Join-Path $script:bracketDir 'log-test.txt') -Raw) | Should Match 'line number 30'
        } finally {
            $script:LogMaxBytes = $script:DefaultLogMaxBytes
            $script:LogKeepLines = $script:DefaultLogKeepLines
        }
        Save-LastSpokenText -Text 'hola'
        Test-Path -LiteralPath (Join-Path $script:bracketDir 'last-text.txt') | Should Be $true
        Remove-DebugFiles
        Test-Path -LiteralPath (Join-Path $script:bracketDir 'last-text.txt') | Should Be $false
        Test-Path -LiteralPath (Join-Path $script:bracketDir 'log-test.txt') | Should Be $false
    }
    It 'clears the duplicate-speech marker' {
        Request-ActiveSpeech | Should Be $true
        Clear-RecentSpeechMarker
        Request-ActiveSpeech | Should Be $true
    }
}

Describe 'The duplicate-speech marker' {
    BeforeEach { Use-FakeDataDir }
    AfterEach { Remove-FakeDataDir }

    It 'stays silent when it cannot be written' {
        New-Item -ItemType Directory -Path (Get-DataFilePath '.last-active-speech') -Force | Out-Null
        @(Set-RecentSpeechMarker 2>&1).Count | Should Be 0
    }
}

Describe 'Logger' {
    BeforeEach { Use-FakeDataDir }
    AfterEach { Remove-FakeDataDir }

    It 'writes nothing, and creates nothing, when disabled' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $false
        $log.Invoke('hello')
        Test-Path (Get-SharedDataDir) | Should Be $false
    }
    It 'appends timestamped lines when enabled' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        $log.Invoke('first')
        $log.Invoke('second')
        $lines = Get-Content -Path (Get-DataFilePath 'log-test.txt')
        $lines.Count | Should Be 2
        $lines[1] | Should Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} - second$'
    }
    It 'does not throw, nor leak an error, when the log file is held open by another program' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        $log.Invoke('first')
        $held = [System.IO.File]::Open((Get-DataFilePath 'log-test.txt'), 'Open', 'ReadWrite', 'None')
        try {
            $ErrorActionPreference = 'Continue'
            $errors = @(& $log 'second' 2>&1)
            $errors.Count | Should Be 0
        } finally { $held.Dispose() }
    }
    # A logger reads the size cap when it is created, so these tests lower the cap first.
    function Use-SmallLog {
        $script:LogMaxBytes = 100
        $script:LogKeepLines = 3
        return Get-Logger -FileName 'log-test.txt' -Enabled $true
    }
    function Restore-LogLimits { $script:LogMaxBytes = $script:DefaultLogMaxBytes; $script:LogKeepLines = $script:DefaultLogKeepLines }

    It 'leaks no error on the first line of a new log' {
        $ErrorActionPreference = 'Continue'
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        @(& $log 'first' 2>&1).Count | Should Be 0
    }
    It 'leaks no error when a log past the size cap is held open and cannot be trimmed' {
        $ErrorActionPreference = 'Continue'
        try {
            $log = Use-SmallLog
            1..20 | ForEach-Object { & $log "line number $_ padded to pass the size cap" }
            $held = [System.IO.File]::Open((Get-DataFilePath 'log-test.txt'), 'Open', 'ReadWrite', 'None')
            try { @(& $log 'while the trim cannot read the file' 2>&1).Count | Should Be 0 }
            finally { $held.Dispose() }
        } finally { Restore-LogLimits }
    }
    It 'stamps each line with the current local time on a 24-hour clock' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        $before = Get-Date
        & $log 'stamped'
        $after = Get-Date
        $line = @(Get-Content -LiteralPath (Get-DataFilePath 'log-test.txt'))[-1]
        $stamp = [datetime]::ParseExact($line.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
        $stamp | Should BeGreaterThan $before.AddSeconds(-2)
        $stamp | Should BeLessThan $after.AddSeconds(2)
    }
    It 'keeps the documented limits: 50 KB, trimmed to the last 200 lines' {
        $script:DefaultLogMaxBytes | Should Be 51200
        $script:DefaultLogKeepLines | Should Be 200
    }
    It 'leaves a log that is under the size cap as it is' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        1..300 | ForEach-Object { & $log "line $_" }
        @(Get-Content -LiteralPath (Get-DataFilePath 'log-test.txt')).Count | Should Be 300
    }
    It 'keeps exactly the last lines when it trims, and the new line after them' {
        try {
            $log = Use-SmallLog
            Initialize-SharedDataDir | Out-Null
            Set-Content -LiteralPath (Get-DataFilePath 'log-test.txt') -Value (1..20 | ForEach-Object { "old line $_" }) -Encoding UTF8
            & $log 'new line'
        } finally { Restore-LogLimits }
        $lines = @(Get-Content -LiteralPath (Get-DataFilePath 'log-test.txt'))
        $lines.Count | Should Be 4
        $lines[0] | Should Be 'old line 18'
        $lines[2] | Should Be 'old line 20'
        $lines[3] | Should Match ' - new line$'
    }
    It 'writes accented text as UTF-8 with a byte-order mark, also when it trims the file' {
        $accents = 'canci' + [char]0xF3 + 'n ' + [char]0xF1 + 'and' + [char]0xFA
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $file = Get-DataFilePath 'log-test.txt'
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        1..3 | ForEach-Object { & $log "$accents $_" }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        ($bytes[0..2] -join ',') | Should Be '239,187,191'
        $utf8.GetString($bytes) | Should Not Match ([string][char]0xFFFD)
        Remove-Item -LiteralPath $file
        try {
            $log = Use-SmallLog
            Initialize-SharedDataDir | Out-Null
            Set-Content -LiteralPath $file -Value (1..20 | ForEach-Object { "$accents old $_" }) -Encoding UTF8
            & $log "$accents new"
        } finally { Restore-LogLimits }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        ($bytes[0..2] -join ',') | Should Be '239,187,191'
        $text = $utf8.GetString($bytes)
        $text | Should Match ([regex]::Escape($accents))
        $text | Should Not Match ([string][char]0xFFFD)
    }
    It 'does not throw when another process keeps the log mutex past its short wait' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        $ready = New-Object System.Threading.ManualResetEvent($false)
        $release = New-Object System.Threading.ManualResetEvent($false)
        $holder = [powershell]::Create()
        $holder.AddScript({
            param($ready, $release)
            $mutex = New-Object System.Threading.Mutex($false, 'Local\SapiVoiceKitLog')
            $got = $mutex.WaitOne(5000)
            $ready.Set() | Out-Null
            if ($got) {
                $release.WaitOne() | Out-Null
                $mutex.ReleaseMutex()
            }
        }).AddArgument($ready).AddArgument($release) | Out-Null
        $pending = $holder.BeginInvoke()
        try {
            $ready.WaitOne(10000) | Should Be $true
            $watch =[System.Diagnostics.Stopwatch]::StartNew()
            { $log.Invoke('while another holds the mutex') } | Should Not Throw
            $watch.Elapsed.TotalSeconds | Should BeGreaterThan 1.5
            $release.Set() | Out-Null
            $holder.EndInvoke($pending)
        } finally { $release.Set() | Out-Null; $holder.Dispose() }
    }
    It 'releases the log mutex after writing, so another thread can take it at once' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        & $log 'one line'
        $other = [powershell]::Create()
        $other.AddScript({
            $mutex = New-Object System.Threading.Mutex($false, 'Local\SapiVoiceKitLog')
            $taken = $mutex.WaitOne(0)
            if ($taken) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
            $taken
        }) | Out-Null
        try { @($other.Invoke())[0] | Should Be $true } finally { $other.Dispose() }
    }
    It 'writes even when the previous holder of the log mutex died without releasing it' {
        $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
        if (-not ('MutexAbandoner' -as [type])) {
            Add-Type -TypeDefinition @'
using System.Threading;
public static class MutexAbandoner {
    // Takes the named mutex on a thread that ends without releasing it.
    public static void Abandon(string name) {
        var thread = new Thread(() => { new Mutex(false, name).WaitOne(5000); });
        thread.Start();
        thread.Join();
    }
}
'@
        }
        [MutexAbandoner]::Abandon('Local\SapiVoiceKitLog')
        $log.Invoke('after an abandoned mutex')
        (Get-Content -Path (Get-DataFilePath 'log-test.txt') -Raw) | Should Match 'after an abandoned mutex'
    }
    It 'trims the file to its last lines once it passes the size cap' {
        $script:LogMaxBytes = 200
        $script:LogKeepLines = 3
        try {
            $log = Get-Logger -FileName 'log-test.txt' -Enabled $true
            1..30 | ForEach-Object { $log.Invoke("line number $_ padded to be long enough") }
            @(Get-Content -Path (Get-DataFilePath 'log-test.txt')).Count | Should BeLessThan 10
            (Get-Content -Path (Get-DataFilePath 'log-test.txt') -Raw) | Should Match 'line number 28'
            (Get-Content -Path (Get-DataFilePath 'log-test.txt') -Raw) | Should Match 'line number 30'
        } finally {
            $script:LogMaxBytes = $script:DefaultLogMaxBytes
            $script:LogKeepLines = $script:DefaultLogKeepLines
        }
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
