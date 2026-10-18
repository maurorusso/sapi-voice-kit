# Links in text: how a URL is spoken, and how a markdown link is cleaned. Text in,
# text out: this file has no environment or process code, on purpose. It holds
# the tests that need a real-looking remote host (a www prefix, a subdomain).
#
#   powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests/urls.Tests.ps1"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
. "$repoRoot\scripts\common.ps1"

Describe 'A URL whose host is a bare IPv6 address' {
    It 'is read as a link to an IP address, with or without punctuation around it' {
        Get-CleanedText -Text 'Mirá http://[::1] y (http://[::1]) y http://[::1]. Fin' | Should Be 'Mirá el link de una dirección IP y (el link de una dirección IP) y el link de una dirección IP. Fin'
        Get-CleanedText -Text '[http://x.com]' | Should Be '[el link de x]'
        Get-CleanedText -Text 'http://user:pw@[::1] fin' | Should Be 'el link de una dirección IP fin'
        Get-CleanedText -Text '(http://admin@[2001:db8::1])' | Should Be '(el link de una dirección IP)'
        Get-CleanedText -Text 'http://[::ffff:192.0.2.1]/x' | Should Be 'el link de una dirección IP'
        Get-CleanedText -Text 'http://[::ffff:192.0.2.1] fin' | Should Be 'el link de una dirección IP fin'
    }
}

Describe 'A URL inside markup or data' {
    It 'ends at a quote, an angle bracket or a backtick, and keeps the text after it' {
        $e = [string][char]0xE9
        Get-CleanedText -Text ('Us' + [char]0xE1 + ' <a href="https://x.com/docs">hac' + $e + ' clic aqu' + [char]0xED + '</a> para ver') | Should Match ('hac' + $e + ' clic')
        Get-CleanedText -Text '{"url":"https://api.x.com/v1","key":"abc","n":1} y listo' | Should Be '{"url":"el link de x","key":"abc","n":1} y listo'
        Get-CleanedText -Text 'fetch("https://x.com/api",{method:"POST"}) y despues' | Should Match 'method:"POST"'
        Get-CleanedText -Text '<https://z.com>,<https://w.com>' | Should Be '<el link de z>,<el link de w>'
        $tick = [string][char]96
        Get-CleanedText -Text ('Dos: ' + $tick + 'https://a.com' + $tick + ',' + $tick + 'https://b.com' + $tick + ' ya') | Should Be 'Dos: el link de a,el link de b ya'
        Get-CleanedText -Text ('En ' + $tick + 'https://a.com/x' + $tick + '(ver) ya') | Should Match '\(ver\)'
    }
}

Describe 'A URL with characters that are easy to take for punctuation' {
    It 'keeps an underscore, a tilde and a semicolon inside the address' {
        Get-CleanedText -Text 'https://github.com/user/repo_name' | Should Be 'el link de github'
        Get-CleanedText -Text 'https://uni.edu/~juan/pagina' | Should Be 'el link de uni'
        Get-CleanedText -Text 'https://x.com/?a=1&amp;b=2' | Should Be 'el link de x'
    }
    It 'ends at an angle bracket' {
        Get-CleanedText -Text '<a href="u">https://x.com</a>' | Should Be '<a href="u">el link de x</a>'
        Get-CleanedText -Text '<https://x.com>texto' | Should Be '<el link de x>texto'
    }
}

Describe 'A URL in a compact table row' {
    It 'ends at the pipe and keeps the next cell' {
        $row = "|GitHub|https://github.com/foo|C" + [char]0xF3 + "digo fuente|"
        Get-CleanedText -Text ("|Nombre|Sitio|Descripcion|`n|---|---|---|`n" + $row) | Should Match 'C.digo fuente'
    }
}

Describe 'A URL with an at sign in its path' {
    It 'names the site of a scoped package or a channel handle, not the text after the at sign' {
        Get-CleanedText -Text 'https://www.npmjs.com/package/@angular/core' | Should Be 'el link de npmjs'
        Get-CleanedText -Text 'https://www.youtube.com/@mkbhd' | Should Be 'el link de youtube'
        Get-CleanedText -Text 'https://medium.com/@user/post-1' | Should Be 'el link de medium'
    }
}

Describe 'A URL with an at sign after the host' {
    It 'names the site, not the text after the at sign in the query or the fragment' {
        Get-CleanedText -Text 'https://example.com?email=a@b.org end' | Should Be 'el link de example end'
        Get-CleanedText -Text 'https://x.com#a@b end' | Should Be 'el link de x end'
        Get-CleanedText -Text 'https://user:pw@example.com/x' | Should Be 'el link de example'
    }
}

Describe 'ConvertTo-SpokenUrls' {
    It 'names the site instead of reading the URL' {
        ConvertTo-SpokenUrls -Text 'mirá https://example.com/some/page' | Should Be 'mirá el link de example'
    }
    It 'ignores a www prefix' {
        ConvertTo-SpokenUrls -Text 'https://www.example.com/algo' | Should Be 'el link de example'
    }
    It 'ignores subdomains' {
        ConvertTo-SpokenUrls -Text 'https://docs.example.com/x' | Should Be 'el link de example'
    }
    It 'leaves text without a URL alone' {
        ConvertTo-SpokenUrls -Text 'no hay ningún link acá' | Should Be 'no hay ningún link acá'
    }
    It 'reads a URL with Latin letters beyond Latin-1 (Polish, Hungarian, Turkish) as a whole' {
        $polish = 'https://pl.wikipedia.org/wiki/' + [char]0x141 + [char]0xF3 + 'd' + [char]0x17A
        ConvertTo-SpokenUrls -Text $polish | Should Be 'el link de wikipedia'
        ConvertTo-SpokenUrls -Text ('https://ejemplo.com/' + [char]0x151 + 'r' + [char]0x15F) | Should Be 'el link de ejemplo'
    }
    It 'reads a URL with umlauts and other letters at the edges of the Latin ranges as a whole' {
        foreach ($letters in ('K' + [char]0xF6 + 'ln'), ('M' + [char]0xFC + 'nchen'), ([string][char]0xD8 + 'resund'), ('Br' + [char]0xF8 + 'nd'), ([string][char]0xDC + 'ber')) {
            ConvertTo-SpokenUrls -Text ('https://de.wikipedia.org/wiki/' + $letters + ' fin') | Should Be 'el link de wikipedia fin'
        }
    }
    It 'reads a URL with German, Romanian and percent-encoded letters as a whole' {
        ConvertTo-SpokenUrls -Text ('https://de.wikipedia.org/wiki/Stra' + [char]0xDF + 'e') | Should Be 'el link de wikipedia'
        ConvertTo-SpokenUrls -Text ('https://ro.wikipedia.org/wiki/Timi' + [char]0x219 + 'oara') | Should Be 'el link de wikipedia'
        ConvertTo-SpokenUrls -Text 'https://es.wikipedia.org/wiki/Espa%C3%B1a' | Should Be 'el link de wikipedia'
    }
    It 'reads a URL with Vietnamese letters as a whole' {
        ConvertTo-SpokenUrls -Text ('Ver https://vi.wikipedia.org/wiki/Vi' + [char]0x1EC7 + 't_Nam ya') | Should Be 'Ver el link de wikipedia ya'
    }
    It 'reads a URL with commas and other symbols inside its path as a whole' {
        ConvertTo-SpokenUrls -Text 'ver https://www.google.com/maps/@40.7,-74.0,15z ahora' | Should Be 'ver el link de google ahora'
        foreach ($symbol in '$', '*', '^', '\') {
            ConvertTo-SpokenUrls -Text ('https://x.com/a' + $symbol + 'b fin') | Should Be 'el link de x fin'
        }
    }
    It 'reads a URL with exclamation marks inside its path as a whole' {
        ConvertTo-SpokenUrls -Text 'Mapa https://www.google.com/maps/place/X/data=!3m1!4b1 ok' | Should Be 'Mapa el link de google ok'
    }
    It 'reads a URL with parentheses, braces and a plus sign in its path or query as a whole' {
        ConvertTo-SpokenUrls -Text 'https://en.wikipedia.org/wiki/Python_(programming_language) fin' | Should Not Match 'programming'
        ConvertTo-SpokenUrls -Text 'https://x.com/users/{id}/posts' | Should Be 'el link de x'
        ConvertTo-SpokenUrls -Text 'https://x.com/search?q=a+b' | Should Be 'el link de x'
    }
    It 'keeps the punctuation written right after a URL, so the sentence still ends' {
        foreach ($mark in '?', '!', ':', ';', '.', ',') {
            ConvertTo-SpokenUrls -Text "Viste https://claude.ai$mark luego" | Should Be "Viste el link de claude$mark luego"
        }
    }
}

Describe 'Get-CleanedText with links' {
    It 'keeps only the label of a markdown link' {
        Get-CleanedText -Text 'mirá [la doc](https://example.com)' | Should Be 'mirá la doc'
    }
    It 'reads a bare URL as its site' {
        Get-CleanedText -Text 'mirá https://example.com/x/y ya' | Should Be 'mirá el link de example ya'
    }
}
