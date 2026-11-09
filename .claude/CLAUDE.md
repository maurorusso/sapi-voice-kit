# sapi-voice-kit — contexto del proyecto

## Objetivo

Que alguien pueda usar Claude Code con la voz: en vez de leer la respuesta en pantalla, escucharla. Se escucha el contenido *completo* de la respuesta, reformulado para que se entienda claro y natural al oído. No es un recorte mecánico ni un resumen ultracorto. Está hecho para quien tiene dificultad para leer en pantalla o prefiere escuchar.

Solo usa la voz nativa de Windows: sin claves de API, sin Python, sin instalador.

## Invariantes: tienen que seguir siendo ciertas en cualquier cambio

- La respuesta en pantalla nunca se modifica. El camino de la voz está totalmente separado de lo que se muestra.
- Lo que se dice es una versión fiel y completa de la respuesta, no un sustituto recortado. Los bloques de código pasan a ser un aviso corto, y se descartan las tiras de cientos de caracteres ASCII sin espacios, como un bloque en base64. La única excepción es el modo `summary`, cuyo propósito es dar una versión resumida.
- Por defecto no se escribe en disco nada legible: ni logs ni copias de lo que se dijo. Solo `config.json` y una marca de tiempo sin contenido (`.last-active-speech`). El texto hablado viaja por memoria (stdin/stdout), nunca por un archivo temporal.
- Todo `.ps1` y `.psd1` dentro de `scripts/` se guarda en UTF-8 **con BOM**: sin él, Windows PowerShell 5.1 lee mal los acentos. `tests/common.Tests.ps1` lo comprueba.
- El código del plugin pasa los argumentos de las herramientas a PowerShell solo como argumentos separados de `spawn`, y el texto solo por stdin o por un heredoc con comillas simples, nunca concatenándolo en un comando de shell. Los dos comandos de voz que una skill le hace correr al modelo aceptan un valor solo después de comprobar que es el nombre de una voz instalada o un código de idioma.
- El plugin no tiene dependencias en tiempo de ejecución. Pester 3.4 (incluido en Windows PowerShell 5.1) y `node:test` son solo para desarrollo.

## Estructura

```
.claude-plugin/        plugin.json, marketplace.json (este repo es su propio marketplace)
hooks/hooks.json       hook Stop (speak.ps1) y hook UserPromptSubmit (prompt-active-mode.ps1)
.mcp.json              registra el servidor MCP para las sesiones de Claude Code
mcp-server/            la entrada de Cowork: server.js (conexiones), protocol.js, tools.js, powershell.js
scripts/               puntos de entrada: speak, say, say-test, self-test, prompt-active-mode, list-voices, set-*
scripts/common.ps1     carga scripts/lib/
scripts/lib/           un tema por archivo; la tabla está en ARCHITECTURE.md
skills/                comandos (voice, mode, mute, debug, test, selftest), read-last, cowork
tests/                 Pester (biblioteca y scripts de entrada de PowerShell) y node:test (servidor MCP, integridad del repo)
```

## Modos de lectura

El hook Stop recibe `last_assistant_message` y actúa según el `mode` de `config.json`:

- **natural** (por defecto): la respuesta entera, sin el markdown y con los bloques de código reemplazados por un aviso (`Get-CleanedText`).
- **literal**: la respuesta entera, tal como está escrita.
- **summary**: un resumen corto que sale de una llamada aparte a `claude -p --safe-mode --tools "" --no-session-persistence --model haiku` (sin herramientas, y sin guardar en el disco del usuario una transcripción de la respuesta). Son unos 20 s de silencio, por eso hay que elegirlo a propósito; si la llamada falla, se usa natural.
- **active**: el modelo dice él mismo una paráfrasis corta, durante el turno, pasándosela a `say.ps1`; el hook Stop no habla, así el audio nunca se duplica. En la CLI, un hook UserPromptSubmit se lo recuerda al modelo en cada turno (Claude Code pide permiso una vez por sesión); el comando es un heredoc de Bash, así que necesita la herramienta Bash. En Cowork, que no dispara los hooks de los plugins, `skills/cowork` le recuerda que llame a la herramienta MCP `read_aloud`.

`muted` pausa la lectura automática sin perder el modo. `read-last` ("leeme eso") lee una respuesta cuando se pide, a través de `say.ps1 -Force`, que ignora el silencio.

## Configuración

Una carpeta fija por usuario de Windows, compartida por todas las instalaciones: `%USERPROFILE%\.claude\plugins\data\sapi-voice-kit-shared\`. `config.json` tiene dos secciones independientes:

- `local`: todo lo que arrancan los hooks de Claude Code. La CLI y la pestaña Code de Desktop disparan los mismos hooks, así que el plugin no puede distinguirlas y comparten esta sección.
- `cowork`: todo lo que llega por el servidor MCP, que es la única forma en que Cowork llega al plugin.

`SAPI_VOICE_DATA_DIR`, si está definida, reemplaza esa carpeta: los tests y `/sapi-voice-kit:selftest` la usan para trabajar en una carpeta descartable sin tocar la configuración real, y el servidor MCP se la pasa a sus scripts. La sección la elige `SAPI_VOICE_NAMESPACE` (el servidor MCP pone `cowork` cuando lanza un script; por defecto es `local`). Las lecturas y escrituras pasan por un mutex con nombre (`Local\SapiVoiceKitConfig`); para escribir se usa un archivo temporal que después se renombra. La voz usa su propio mutex (`Local\SapiVoiceKitSpeak`) para que las sesiones en paralelo hablen por turnos en vez de pisarse; el log de depuración tiene un tercero (`Local\SapiVoiceKitLog`), que no es estricto. La protección contra hablar dos veces **no** es por sección, a propósito: existe justamente para evitar duplicados entre ellas.

## Voces

`Get-InstalledVoices` junta las voces OneCore (las modernas de Windows 11, listadas primero para que ganen en la elección automática) y las SAPI5 (clásicas, presentes en todo Windows). El nombre de voz o el idioma configurado se busca en esa única lista. Si una voz falla, `Invoke-SpeechSynthesis` prueba en este orden: OneCore → voz SAPI5 del idioma → voz SAPI5 por defecto.

Los términos técnicos (git, commit, hook, ...) reciben pronunciaciones en IPA con la *misma* voz, tomadas del diccionario del idioma de esa voz: `scripts/lib/pronunciations/<código>.psd1` (hoy solo existe `es.psd1`, que se usa para todas las voces en español: es-ES, es-MX, ...). Una voz en un idioma sin archivo no recibe ayudas, porque el IPA escrito para español está mal para otro idioma. Para sumar un idioma, se agrega su archivo; no cambia nada más. Las palabras que las voces acentúan mal aun con IPA se reescriben (`scripts/lib/respellings/<código>.psd1`, por ejemplo `natural` -> `naturál`: la voz respeta la tilde escrita y no la marca de acento del IPA; el texto en pantalla no cambia). Las dos cosas se omiten en el modo literal. Las reglas para agregar entradas están al principio de cada archivo. Los cambios se comprueban de oído con `/sapi-voice-kit:test`.

## Cowork

En Cowork no se disparan los hooks de los plugins, y su propia herramienta de shell es un entorno Linux remoto sin PowerShell, así que ahí el plugin habla y se configura a través del servidor MCP. Este ofrece `read_aloud`, `set_mode`, `set_mute`, `set_voice`, `list_voices`, `say_test` y `set_debug`; cada una corre un script y devuelve lo que este imprime. `read_aloud` le pasa `-RequireMode active` a `say.ps1`, así el chequeo del modo está en un solo lugar.

Que Cowork registre solo el servidor MCP del plugin no es consistente: Anthropic documenta que un plugin instalado por el usuario no trae servidores MCP, pero a veces apareció igual. El README da la entrada manual, que se hace una sola vez, como alternativa; agregarla cuando el servidor ya se registró lo duplica. Empaquetar el servidor como extensión de Desktop `.mcpb` no ayuda: anthropics/claude-code#26259 muestra que la máquina virtual de Cowork solo reenvía servidores `type: "sdk"` y descarta los stdio.

## Trabajar en este repo

- Tests: `powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests"` y `node --test`. El CI (`.github/workflows/test.yml`) corre los dos en cada PR y en cada push a `main`, en Windows, con Pester fijado en 3.4.0. `codeql.yml` analiza el servidor MCP; CodeQL no soporta PowerShell.
- La calidad del audio no se puede comprobar con un test: después de tocar `text-normalization.ps1` o un diccionario, correr `/sapi-voice-kit:test`. Antes de aprobar un PR que toque la voz, correr `/sapi-voice-kit:selftest` (unos 3 minutos, en voz alta): con el medidor de nivel de salida comprueba que cada modo suene o se quede en silencio según corresponda; si suena bien se sigue juzgando de oído.
- Todo cambio va en una rama y un PR; el dueño hace el merge.
- Nueva versión: subir `version` en `plugin.json` y en los dos lugares de `marketplace.json` (`tests/repo.test.js` comprueba que coincidan; el servidor MCP lee la versión del plugin de `plugin.json`).

## Decisiones (qué se probó y por qué quedó así)

- **Una segunda voz para los términos técnicos**: descartada. Funciona, pero suena a dos personas hablando y duplica el tiempo de lectura. En su lugar, ayudas en IPA con una sola voz.
- **Que el modelo agregue un bloque oculto `<!--voice-->` a su respuesta**: descartado. Un hook solo ve lo que ya está en pantalla; no hay canal oculto.
- **Un archivo temporal para el texto hablado**: descartado, aunque se borre solo. El texto va por memoria.
- **Usar la herramienta de shell de Cowork para correr `say.ps1`**: no funciona (es un entorno Linux remoto). Por eso existe el servidor MCP local.
- **Un quinto modo `cowork`**: descartado. Cowork y la CLI tienen un mismo comportamiento ("el modelo habla") por dos caminos distintos.
- **El SDK oficial de MCP**: descartado, para que el plugin no dependa de npm. La parte del protocolo que hace falta es chica.
- **Dos secciones de configuración (`local`, `cowork`) y no un archivo plano**: la voz tiene que poder ser distinta en Cowork.
- **Limpiar abreviaturas, rutas y URLs con expresiones regulares en el modo natural y en `say.ps1`, y con instrucciones al modelo en summary, active y read-last**: no se puede obligar al modelo, así que `say.ps1` también normaliza lo que recibe, y el modo summary pasa el resumen del modelo por `Get-CleanedText` antes de decirlo.
- **SSML `<prosody>` para la velocidad o la entonación de las preguntas**: las voces OneCore lo ignoran. La velocidad usa `SpeechSynthesizer.Options.SpeakingRate`.
- **Publicar en el directorio de plugins de Anthropic**: bloqueado por la política, que acepta hooks de tipo comando y servidores MCP locales solo de organizaciones verificadas, y el plugin necesita las dos cosas. Se distribuye desde este repositorio, que es su propio marketplace.
- **Que el plugin revise sus propios archivos**: descartado. El chequeo estaría en la misma carpeta que revisa, así que quien pueda cambiar los archivos también puede cambiar el chequeo, y una falsa alarma podría dejar sin audio a alguien que depende de él.

## Limitaciones conocidas

- Las preguntas en español tienen una entonación ascendente débil en todas las voces en español de Microsoft, SAPI5 u OneCore, y ningún SSML lo cambia. Una voz neuronal en la nube lo resolvería, a costa de claves de API e internet, que es justo lo que este proyecto existe para evitar.
- Las voces no tienen el sonido /ʃ/ ("sh"): "push" se dice "pus". Igual, la entrada del diccionario es mejor que nada.
- La pantalla de plugins de Cowork puede mostrar una versión vieja, y reiniciar no la actualiza.
- En el modo active en Cowork, que hable depende de que el modelo use la skill en cada turno.
- `.mcp.json` arranca `node` por nombre, y los hooks y las skills arrancan `powershell` por nombre. Los hooks corren con Git Bash o PowerShell, y ninguno de los dos busca programas en la carpeta actual. El `spawn` de Node sí lo hace, así que si Claude Code arranca el servidor MCP de esa forma desde la carpeta del proyecto (no está confirmado), correría un `node.exe` que ya estuviera en esa carpeta. `node` no tiene una ruta completa fija; solo las llamadas a PowerShell del propio servidor MCP usan la ruta completa de System32.
- Un nombre de archivo con varios puntos (`common.Tests.ps1`, `app.module.ts`) se lee como sus dos últimas partes y conserva las carpetas de adelante: la parte del nombre en el patrón de archivos no puede tener puntos, y permitirlos hacía el patrón demasiado lento con palabras largas llenas de puntos. Las rutas con espacios (`C:\Program Files\App\run.exe`) no se reconocen, así que queda una palabra antes del primer espacio; un nombre de archivo pegado a texto en chino, japonés o tailandés sin puntuación en el medio queda como está escrito (`\b` no encuentra un límite ahí); y `chart.js/package.json` se lee como una lista, porque tiene la misma forma que `README.md/other.md`. Las carpetas con mayúscula delante de un archivo `.js` con mayúscula (`Models/User.js`) se conservan, porque esa forma coincide con una lista de tecnologías (`MongoDB/Express/Node.js`).
- Un texto escrito sin espacios (chino, japonés, coreano, tailandés) pegado a una ruta de Windows con unidad, sin puntuación en el medio, se lee como parte de la ruta: después de `C:\`, el nombre de una carpeta puede estar en cualquier alfabeto, porque los nombres de usuario pueden estarlo. Dos URLs unidas por una coma sin espacio (`https://a.com,https://b.com`) se leen como un solo link. Si el nombre de una carpeta en una ruta con unidad tiene una coma, un punto y coma, un acento grave, un paréntesis sin cerrar o un guion, comilla o comilla angular tipográficos (válidos en Windows, `C:\Users\Smith,John`), la carpeta termina en ese carácter, porque esos caracteres son los que permiten separar dos rutas pegadas.
- Un comentario o un link dentro de un fragmento escrito con dos acentos graves (` ``<!-- x -->`` `) se trata como si estuviera fuera del código: el par de acentos graves que lo abre se lee como un fragmento vacío.
- Un Markdown ambiguo o mal escrito todavía puede hacer que se lea algo de código o que se pierda una línea: tres acentos graves mencionados al final de una línea se emparejan con la siguiente línea de cierre suelta (la frase "Hacé esto: ```" seguida de código y un cierre se lee como un solo bloque, que es lo que esa forma suele querer decir); un bloque que nunca se cierra se lee como texto; el contenido sin sangría de un bloque abierto después de un marcador de lista termina con ese elemento de la lista; un separador escrito `- - -`, una casilla vacía `[ ]` y una línea que empieza con un año y un punto (`2024. texto`, que se lee como elemento de lista) se dicen tal como están escritos o pierden ese comienzo. El marcador de cita se quita con cualquier sangría, así que una línea que empieza con `>=` pierde su `>`, igual que como lo lee Markdown.
- En el modo natural, una respuesta de más de unos 15.000 caracteres se corta cuando se agota el tiempo límite de 900 s del hook Stop (una voz en español dice unos 17 caracteres por segundo).
- Las voces modernas (OneCore) generan todo el audio antes de empezar a reproducir, así que una respuesta larga arranca con demora (unos 5 s para 10.000 caracteres), y pasados unos 65.000 caracteres se agota la espera de 30 s y el texto se vuelve a leer con una voz clásica.
- Un `read_aloud` largo ocupa la cola del servidor MCP hasta que termina de hablar, así que `set_mute` espera detrás.
- En el modo active, la paráfrasis hablada queda en la transcripción de la sesión de Claude, que el plugin no controla.
- Si el servidor MCP está registrado por el plugin y además por una entrada manual en `claude_desktop_config.json`, las sesiones de Claude Code ven dos herramientas `read_aloud`; la protección contra hablar dos veces absorbe la llamada doble.
