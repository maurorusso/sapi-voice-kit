# sapi-voice-kit

Hablá con **Claude Code** en vez de leerlo. Escribí o dictá tu mensaje, y en vez de leer la respuesta en pantalla, escuchala — la respuesta completa, limpia para que suene como habla y no como un documento leído, no una leyenda y no un resumen recortado por las dudas. Sin API keys, sin Python, sin instaladores externos: usa la síntesis de voz nativa de Windows — la voz moderna de Windows 11 si la tenés instalada (suena notablemente más natural, confirmado escuchando una al lado de la otra), o la clásica `System.Speech`/SAPI si no, que viene con cualquier Windows sin nada que instalar.

Pensado para gente a la que le cuesta leer en pantalla, o para cualquiera que prefiera escuchar mientras trabaja. La respuesta en pantalla nunca se toca — esto solo afecta lo que escuchás.

## Por qué existe

Ya hay varios proyectos de voz para Claude Code, pero casi todos apuntan a macOS, o piden instalar Python/Node y conseguir una API key de algún proveedor de voz (edge-tts, ElevenLabs, Deepgram, Piper...). `sapi-voice-kit` es distinto: **un solo plugin, cero dependencias externas, cero instalador** — si tenés Windows, ya tenés todo lo que hace falta.

## Qué hace

- Lee en voz alta cada respuesta de Claude Code automáticamente, apenas termina cada turno.
- **Modo natural (por defecto):** lee la respuesta completa, limpia de markdown (encabezados, viñetas, links, sintaxis de código) para que suene como habla y no como un documento leído. No se acorta ni se omite nada — la respuesta en pantalla nunca se toca, esto solo afecta lo que se escucha.
- **Modo literal:** escuchás la respuesta tal cual está escrita, sin ninguna limpieza — útil sobre todo para revisar qué dice el texto crudo.
- **Modo resumen (`summary`):** escuchás un resumen real y condensado en vez de la respuesta completa — tarda unos 20 segundos más por respuesta (le pide el resumen a Claude aparte), así que es opcional, no viene activado por defecto.
- **Modo activo (`active`):** el modelo mismo dice una frase corta y natural, en el mismo turno — sin archivos, sin demora extra de una llamada aparte. Tan natural y rápido como se puede, pero la primera vez que se usa en una sesión te va a pedir permiso para correr el comando (ver la sección de Instalación más abajo para saltear ese cartel de una vez si querés). Funciona igual en la CLI y en Claude Cowork/Desktop — ver "Uso en Claude Cowork" más abajo para el detalle de por qué el mecanismo interno es distinto ahí.
- Detecta automáticamente una voz instalada que coincida con el idioma de tu sistema (en vez de venir fija en un idioma), prefiriendo una voz moderna de Windows 11 si tenés una instalada para ese idioma, y usando la clásica si no. Se puede cambiar a mano (`/sapi-voice-kit:voice`, ver más abajo) — la velocidad de lectura funciona igual en las dos.
- Términos de programación comunes (`git`, `commit`, `config`, `hook`, `function`, `readme`, `npm`, `javascript`, y unos 100 más) se pronuncian correctamente aunque estén en medio de una oración en otro idioma, usando la misma voz de siempre — no una segunda voz que corta la frase. Algunas palabras usan una pronunciación más "castellanizada" cuando suena mejor así (confirmado escuchando, no adivinado).
- Los nombres de archivo con extensión (`common.ps1`, `config.json`) se leen bien — el punto antes de la extensión se dice como "punto", en vez de sonar como una pausa rara cortada a la mitad. Lo mismo con rutas completas (`C:\...\common.ps1` o `scripts/speak.ps1`): se lee solo el nombre del archivo, no cada carpeta intermedia — y con archivos que empiezan con punto (`.env`, `.gitignore`, `.mcp.json`), que si no quedaban con un punto suelto y raro al principio.
- Abreviaturas comunes (`etc.`, `p. ej.`, `Dr.`, `aprox.`, `vs.`...) se dicen como la palabra completa ("etcétera", "por ejemplo"...) en vez de deletrearse letra por letra.
- Un salto de línea sin punto al final (algo muy común en texto escrito) se interpreta igual como el final de una idea, con una pausa — así no se lee todo pegado como si fuera una sola oración larga.
- Los links no se leen crudos — algunos motores de voz de Windows llegan a leer una URL como si fuera un emoticón (confirmado en vivo) por el `://` justo después de "https". En vez de eso, se dice "el link de github" (o el sitio que sea) — así, si hay dos links distintos en la misma respuesta, se distinguen entre sí. La pantalla sigue mostrando la dirección completa siempre.
- Si tenés dos sesiones de Claude Code con el plugin activo hablando al mismo tiempo (por ejemplo, dos ventanas abiertas), ya no se superponen — se turnan automáticamente en vez de sonar las dos juntas e ininteligibles.
- **`/sapi-voice-kit:mute`:** apaga toda lectura automática al toque, en todas tus sesiones de esta máquina a la vez, sin perder el modo que tenías elegido — para el caso de dos sesiones hablando encima una de la otra, o cualquier momento en que necesitás silencio ya. Pedir que se lea algo puntual sigue funcionando igual mientras está muteado.
- **Lectura a demanda:** en cualquier momento podés pedir "leeme eso" o "no entendí, léelo" y se lee la respuesta puntual que señalás, sin depender de que el modo automático esté prendido.

## Instalación

### Recomendado: como plugin

```
/plugin marketplace add https://github.com/maurorusso/sapi-voice-kit
/plugin install sapi-voice-kit
```

(Usar la URL completa con `https://` evita que Claude Code intente clonar por SSH por defecto, lo cual falla en máquinas sin una clave SSH de GitHub configurada. La forma corta `maurorusso/sapi-voice-kit` también funciona, pero solo si ya tenés acceso SSH a GitHub configurado.)

### Para probarlo sin instalar nada (desarrollo)

```bash
claude --plugin-dir "/ruta/a/sapi-voice-kit"
```

Carga el plugin solo para esa sesión, sin tocar tu configuración.

## Uso

Una vez instalado, no hay que hacer nada más — las respuestas se empiezan a leer solas.

Comandos disponibles:

| Comando | Qué hace |
|---|---|
| `/sapi-voice-kit:voice` | Lista las voces instaladas en Windows |
| `/sapi-voice-kit:voice <nombre>` | Fuerza una voz específica |
| `/sapi-voice-kit:voice <idioma>` | Fuerza un idioma (ej. `en-US`) |
| `/sapi-voice-kit:voice auto` | Vuelve a la detección automática de voz |
| `/sapi-voice-kit:voice <faster/slower>` | Ajusta la velocidad de lectura |
| `/sapi-voice-kit:mode natural` | (por defecto) Lee la respuesta completa, limpia para que suene como habla |
| `/sapi-voice-kit:mode literal` | Lee la respuesta completa exactamente como está escrita |
| `/sapi-voice-kit:mode summary` | Lee un resumen condensado (~20s más lento por respuesta) |
| `/sapi-voice-kit:mode active` | El modelo dice una frase corta él mismo, en el momento (puede pedir permiso la primera vez) — funciona igual en CLI y en Cowork, ver "Uso en Claude Cowork" más abajo |
| `/sapi-voice-kit:debug on` / `off` | Prende o apaga los archivos de log para diagnóstico (apagado por defecto) |
| `/sapi-voice-kit:mute on` / `off` | Apaga o reactiva toda lectura automática, en todas tus sesiones de esta máquina, sin perder el modo elegido |
| `/sapi-voice-kit:read-last` (o simplemente pedirlo: "leeme eso") | Lee en voz alta una respuesta puntual, ahora mismo, aunque esté muteado o el modo automático no esté prendido |
| `/sapi-voice-kit:test` | Dice una oración fija pensada para probar todo junto (términos técnicos, nombres de archivo, abreviaturas, una pregunta) — útil para confirmar por oído que todo suena bien después de instalar o de cambiar algo |

### Sobre el permiso del modo `active`

Este modo hace que el modelo corra un comando para hablar, así que la primera vez en cada sesión Claude Code te va a preguntar si lo autorizás — es el comportamiento normal y esperado, no un error, y **el plugin no puede saltear ese permiso por su cuenta** (ni debería: que un plugin se auto-otorgue permisos sería un problema de seguridad, no algo a resolver).

Cuando te aparezca el cartel, elegí "permitir siempre" para no verlo de nuevo en esa sesión. Si preferís saltearlo directamente desde el principio, podés agregar vos mismo una regla a tu `.claude/settings.json` (nunca es algo que el plugin haga por vos):

```json
{
  "permissions": {
    "allow": ["Bash(powershell*say.ps1*)"]
  }
}
```

(La regla exacta puede variar según tu versión de Claude Code — cuando te aparezca el cartel de permiso la primera vez, fijate qué regla te ofrece agregar y usá esa si es distinta a la de arriba.)

### Uso en Claude Cowork

Cowork no dispara los hooks automáticos de un plugin (`Stop`, `UserPromptSubmit`) — está confirmado en varios issues abiertos del repo de Claude Code, no es un bug de este plugin. Por eso los modos `natural`/`literal`/`summary` no funcionan solos ahí: dependen de esos hooks. El modo `active` sí funciona en Cowork — es el mismo modo que en la CLI, solo que por dentro usa un mecanismo distinto para llegar al mismo resultado.

Cowork sí soporta **servidores MCP locales** — procesos que corren en tu propia máquina, no en la nube (a diferencia de la herramienta de shell propia de Cowork, que sí corre en un sandbox remoto sin acceso a tu hardware, confirmado en vivo probando esto). Este plugin incluye uno (`mcp-server/server.js`), con una sola herramienta, `read_aloud`, que reusa exactamente el mismo `say.ps1` que ya usa el modo `active` en la CLI — mismo diccionario de pronunciación, mismo mutex entre sesiones, nada nuevo.

**Instalación:**

- **CLI o el tab "Code" de Claude Desktop:** no hay ningún paso aparte — es la misma instalación de la sección "Instalación" de arriba. Al instalar el plugin ahí, se registra solo el servidor MCP (`read_aloud`), sin tocar ningún archivo a mano — confirmado en vivo instalando el plugin real y escuchando audio real salir de la herramienta.
- **Cowork:** instalando desde el marketplace (Configuración → Plugins → Agregar marketplace, y después instalar `sapi-voice-kit` ahí), el servidor MCP se registró solo en una prueba real, apareciendo como una herramienta con un nombre parecido a `sapi-voice-kit__read_aloud` sin ningún paso manual — a diferencia de lo que documentamos antes (y de lo que decía la documentación de Anthropic sobre plugins de usuario). Si en tu caso no aparece solo, el paso manual de más abajo sigue funcionando como respaldo — pero **no agregues los dos a la vez**: si el automático ya registró el servidor, la entrada manual lo duplica.

  Si hace falta el paso manual, una sola vez:
  1. Configuración → Desarrollador → Servidores MCP locales → **Editar configuración**.
  2. Pegá esto, reemplazando `<ruta-del-plugin>` por la carpeta donde Cowork instaló el plugin (fijate la ruta exacta en el mensaje de instalación, o en Configuración → Plugins → sapi-voice-kit):
     ```json
     {
       "mcpServers": {
         "sapi-voice-kit": {
           "command": "node",
           "args": ["<ruta-del-plugin>/mcp-server/server.js"],
           "env": {
             "PLUGIN_ROOT": "<ruta-del-plugin>",
             "PLUGIN_DATA": "<ruta-de-datos-del-plugin>"
           }
         }
       }
     }
     ```

Además de `read_aloud`, el servidor MCP también expone `set_mode`, `set_mute`, `set_voice`, `list_voices`, `say_test` y `set_debug` — son los mismos comandos que `/sapi-voice-kit:mode`, `:mute`, `:voice`, `:test` y `:debug` usan en la CLI, pero como herramientas MCP, porque la terminal propia de Cowork corre en un sandbox en la nube sin PowerShell ni acceso a esta máquina y no puede ejecutar esos scripts directamente. Las skills de cada comando ya saben usarlos automáticamente cuando corren en Cowork/Desktop.

La configuración (modo, voz, mute, debug) vive en un solo archivo compartido, pero **separada en dos secciones independientes**: una para "local" (CLI + tab Code de Desktop — técnicamente no se pueden distinguir entre sí, así que comparten la misma) y otra para "cowork". Cambiar algo desde la CLI o el tab Code no toca la configuración de Cowork, y viceversa — así podés tener, por ejemplo, una voz en Cowork y otra distinta en la CLI, cada una con su propio modo y su propio mute.

Si venís de una versión anterior a esta separación: la migración automática solo trae tu configuración vieja al lado que use el plugin primero después de actualizar (normalmente "local"). Si tenías algo configurado del lado de Cowork específicamente, puede que tengas que volver a elegirlo una vez (`/sapi-voice-kit:voice`, `/sapi-voice-kit:mode`) — no se pierde nada, pero tampoco se migra solo a los dos lados a la vez.

Después de instalar (por cualquiera de los dos caminos):
1. `/sapi-voice-kit:mode active`.
2. La primera vez que se use, te va a pedir permiso para ejecutar la herramienta — es esperado.

**Diferencia importante con la CLI**: ahí, un hook lo dispara el runtime de Claude Code automáticamente, sin que el modelo tenga que acordarse de nada. En Cowork, una skill le recuerda al modelo que llame a `read_aloud` en cada turno, pero eso depende de que el modelo decida invocarla — no hay garantía de que pase en el 100% de los turnos. Si en algún momento no escuchás nada, probá pedir "leeme eso" (`/sapi-voice-kit:read-last`), que sigue funcionando igual.

## Privacidad: qué se guarda en disco, y cuándo

**Por defecto, este plugin no escribe absolutamente nada legible** en tu máquina más allá de la configuración que vos mismo elegís a propósito (`/sapi-voice-kit:voice`, `/sapi-voice-kit:mode`). No queda ningún archivo con una copia de lo que se dijo, ni logs, nada — ni siquiera se crea la carpeta de datos hasta que cambiás alguna preferencia.

La única excepción es un archivo minúsculo (`.last-active-speech`) que el modo `active` guarda para evitar hablar dos veces seguidas por accidente (puede pasar si el modelo dispara el mecanismo de la CLI y el de Cowork en el mismo turno) — guarda solo una marca de tiempo, nunca el texto ni nada derivado de él, y se pisa en cada uso.

Los archivos de log (`log-speak.txt`, y una copia del último texto leído en `last-text.txt`) **solo existen si vos los pedís explícitamente** con `/sapi-voice-kit:debug on`, para diagnosticar un problema puntual. Incluso con eso prendido, cada log tiene un tope de tamaño (se recorta solo a las últimas 200 líneas) — no crece para siempre. Se recomienda volver a apagarlo (`/sapi-voice-kit:debug off`) una vez resuelto lo que sea que estabas viendo.

`/sapi-voice-kit:mute` y la lectura a demanda no agregan ningún archivo nuevo: el mute es un valor más adentro del mismo `config.json` que ya se guardaba, y la lectura a demanda toma el texto que ya está en la conversación y lo pasa directo por memoria a la síntesis de voz — igual que el modo `active`, nunca toca disco.

El servidor MCP que usa el modo `active` en Cowork (`mcp-server/server.js`) tampoco agrega nada nuevo: es parte del código del plugin (misma carpeta que todo lo demás), no escribe ningún archivo — solo reenvía el texto a `say.ps1` por memoria, igual que en la CLI.

## Arquitectura: qué instala, dónde, y qué archivos toca

### Todo lo que el plugin pone en tu disco — dos carpetas, nada más

Cuando instalás el plugin, Claude Code crea **exactamente dos carpetas**, las dos dentro de tu carpeta de usuario de Windows. No se registra nada en "Programas y características", no se toca el `PATH`, no se instala ningún servicio, no se modifica ningún otro programa:

1. **El código del plugin** — una copia clonada de este repositorio de GitHub, tal cual, sin modificar:
   ```
   %USERPROFILE%\.claude\plugins\marketplaces\sapi-voice-kit\
   ```
   Ahí están los archivos `.ps1` (`speak.ps1`, `say.ps1`, `common.ps1`, etc.), los `SKILL.md`, el manifiesto del plugin, y (para el modo `active` en Cowork) `.mcp.json` y `mcp-server/server.js`. Esto es de solo lectura en la práctica — el plugin nunca se escribe a sí mismo.

2. **Tu configuración**, separada del código a propósito (para que sobreviva cuando el plugin se actualiza):
   ```
   %USERPROFILE%\.claude\plugins\data\sapi-voice-kit-sapi-voice-kit\
   ```
   Ahí vive **un solo archivo por defecto**, `config.json`, con la voz/idioma/modo/velocidad/muteo que elegiste — y ni siquiera ese archivo existe hasta que corrés `/sapi-voice-kit:voice`, `/sapi-voice-kit:mode` o `/sapi-voice-kit:mute` por primera vez. Usando el modo `active`, también aparece `.last-active-speech` (un hash y una marca de tiempo, no texto legible — ver Privacidad más arriba). Si activás `/sapi-voice-kit:debug on`, ahí también aparecen `log-speak.txt`, `log-say.txt` y `last-text.txt` — ver la sección de Privacidad más arriba para el detalle de cuándo y por qué.

**Nota sobre estas dos rutas en Claude Desktop:** lo de arriba es lo confirmado para una sesión de terminal (`claude` en una consola). En Claude Desktop (panel "Code"), se observó una estructura distinta: el código en `%USERPROFILE%\.claude\plugins\cache\sapi-voice-kit\sapi-voice-kit\<versión>\` y los datos en `%USERPROFILE%\.claude\plugins\data\sapi-voice-kit-inline\`. Mismo contenido, misma privacidad en los dos casos — solo cambia la carpeta exacta según qué cliente de Claude Code estés usando.

### ¿Usa alguna carpeta temporal? No — ninguna, en ningún modo

Es una pregunta que vale la pena responder explícitamente: **el plugin no escribe, en ningún momento, a `%TEMP%`, `C:\Windows\Temp`, ni ningún otro directorio temporal.** El texto que se lee en voz alta viaja siempre por memoria (stdin/stdout entre procesos), nunca pasa por un archivo intermedio — ni uno que se borre después, directamente no existe ese archivo en ningún punto del proceso. Esto fue una decisión deliberada (ver Privacidad arriba): se evaluó incluso la idea de un archivo que se autoborre al toque, y se descartó en favor de no escribir nada de entrada, que es más seguro todavía.

La única excepción real: en modo `summary`, la llamada `claude -p` es un proceso de Claude Code aparte, y ese proceso puede usar sus propios archivos temporales internos como cualquier sesión normal de Claude Code — eso está fuera del control de este plugin, es el mismo comportamiento que tendría cualquier uso tuyo de Claude Code sin el plugin de por medio.

### Cómo funciona cada modo, componente por componente

Para el detalle técnico completo (qué hook dispara qué script, qué parte de cada modo cuesta algo extra, con un diagrama por modo) ver [ARCHITECTURE.md](ARCHITECTURE.md).

## Cómo funciona (para curiosos)

- La pronunciación de términos técnicos comunes usa fonemas IPA reales sobre la *misma* voz elegida, sin importar el modo (salvo literal) — `PromptBuilder.AppendTextWithPronunciation` con la voz clásica, o una etiqueta SSML `<phoneme>` con la voz moderna, mismo diccionario en los dos casos. Cambiar a una segunda voz instalada para esto se probó y se descartó (funciona, pero suena a dos personas distintas hablando, y casi duplica el tiempo de lectura en respuestas con mucho código).
- La configuración (voz, idioma, modo) se guarda en la carpeta de datos propia del plugin, así que sobrevive a las actualizaciones. No se escribe nada más salvo que actives el modo debug (ver "Privacidad" arriba).

Nada sale de tu máquina salvo en modo `summary` (llamada a Claude): no hay servicios de terceros, no hay API keys propias del plugin, no hay telemetría. El modo `active` tampoco sale de tu máquina — es el modelo, que ya está corriendo en tu sesión, el que dispara `say.ps1` (directo en la CLI, vía el servidor MCP local en Cowork).

## Requisitos

- Windows (usa la síntesis de voz nativa, que es específica de Windows).
- Claude Code, o Claude Desktop/Cowork para usar el modo `active` ahí (usa el Node.js que ya viene con Claude Code/Desktop — no hace falta instalar nada aparte).
- La voz clásica (SAPI5) funciona en cualquier Windows, sin instalar nada. La voz moderna es opcional: necesita Windows 11 22H2 o más nuevo, y bajarla una vez desde Configuración → Accesibilidad → Narrador → "Agregar voces naturales" — si no la tenés, el plugin usa la clásica automáticamente, sin que tengas que hacer nada.

### Elegir qué voz usa

`/sapi-voice-kit:voice` (sin argumentos) lista todas las voces disponibles, agrupadas por motor, y te dice cuál se está usando ahora. Podés forzar una puntual con `/sapi-voice-kit:voice <nombre exacto>`, o volver a la detección automática con `/sapi-voice-kit:voice auto`.

## Aviso

Este es un proyecto de la comunidad, no afiliado con Anthropic ni respaldado por Anthropic. "Claude" y "Claude Code" son marcas de Anthropic, usadas acá solo para describir con qué es compatible este plugin.

## Licencia

MIT — ver [LICENSE](LICENSE).
