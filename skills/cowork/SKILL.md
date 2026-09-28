---
description: When sapi-voice-kit is configured in "active" mode AND you're running as Claude Cowork/Desktop (where automatic hooks don't fire), speak each response aloud yourself using the read_aloud MCP tool, at the end of the turn.
---

# sapi-voice-kit en Cowork

Esta skill solo aplica si estás corriendo como **Claude Cowork/Desktop**, no la CLI de Claude Code. Si sos la CLI: no hagas nada acá - ya te recuerda esto mismo un hook aparte (`prompt-active-mode.ps1`), y si además invocás esta skill vas a terminar hablando dos veces.

Si sos Cowork/Desktop: no hace falta que chequees vos el modo configurado - la herramienta `read_aloud` ya lo chequea del lado del servidor y no hace nada si el modo no es "active" (te va a devolver un mensaje diciendo que no se dijo nada). Antes esta skill pedía correr un comando de PowerShell para chequearlo acá primero, pero la herramienta de shell de Cowork corre en una máquina remota en la nube sin PowerShell ni acceso a tu `config.json` - ese chequeo nunca podía funcionar ahí (confirmado en vivo). Así que directamente: intentá llamar a `read_aloud` al final de cada turno, y confiá en su respuesta.

<!-- El párrafo siguiente (punto/link/ruta) se mantiene sincronizado a mano
     con $script:SpokenTextGuidance en scripts/common.ps1 (también usado
     por el prompt de Get-AiSummary y la instrucción de prompt-active-mode.ps1)
     - un skill es markdown estático, no se le puede interpolar esa variable.
     Si cambiás la redacción en un lugar, cambiala en los cuatro. -->

Al final de tu respuesta, después de cualquier llamada a herramientas, llamá a la herramienta MCP `read_aloud` (del servidor `sapi-voice-kit` - en tu lista de herramientas va a tener un nombre que contiene "sapi-voice-kit" y "read_aloud", por ejemplo `mcp__plugin_sapi-voice-kit_sapi-voice-kit__read_aloud` - el prefijo exacto puede variar según la versión de Claude Code/Cowork, buscá por esas dos palabras, no compares el nombre letra por letra) con el parámetro `text`, una versión hablada corta, natural y completa de tu respuesta (no la acortes ni omitas contenido real - es una paráfrasis hablada, no un resumen), en el mismo idioma, sin markdown. Si mencionás un archivo, decí "punto" en vez de un "." literal. Si mencionás un link, decí el nombre del sitio ("el link de GitHub"), no la URL. Si mencionás una ruta completa, decí solo el nombre del archivo, no cada carpeta intermedia.

No uses `force: true` a menos que el usuario haya pedido explícitamente que se lea algo puntual ("leeme eso") mientras está muteado - para el llamado normal de cada turno, dejalo en su valor por defecto (false), así respeta `/sapi-voice-kit:mute`.

Si te salteás esto, el usuario no escucha nada este turno. No hay garantía de que esta skill se dispare en todos los turnos - a diferencia del hook automático que usa Claude Code CLI, acá depende de que vos decidas invocarla cada vez. Es una limitación conocida de Cowork (los hooks de plugin no disparan ahí), no de este plugin. La primera vez que llames a `read_aloud` en una sesión, Cowork probablemente te pida confirmar el permiso - es esperado, no un error.
