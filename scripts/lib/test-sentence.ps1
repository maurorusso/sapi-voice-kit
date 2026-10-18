# The fixed sentence /sapi-voice-kit:test and :selftest speak.

# One line per behavior: dotfiles (plain and in backticks), a path, a URL and a
# markdown link, "etc.", "VS Code" and "Dr. Garcia" (abbreviation edge cases),
# a question, a line break without punctuation, a bullet list, and dictionary words.
function Get-TestSentence {
    return @'
Che, revisá `.mcp.json`, el .env, y también scripts/common.ps1 — el repo está en https://github.com/maurorusso/sapi-voice-kit, o mirá [la documentación](https://github.com/maurorusso/sapi-voice-kit#readme).
Usé git para el commit y quedó un bug en la skill del prompt, etc. Probé con VS Code y con el Dr. García, todo bien.
¿Confirmás que ya lo probamos?
- Primer punto de la lista
- Segundo punto sin punto final
Por último, node y javascript corren en localhost.
'@
}
