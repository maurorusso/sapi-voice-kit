# Arquitectura de sapi-voice-kit

Detalle técnico de qué componente hace qué en cada uno de los cuatro modos de lectura — para instalación, comandos, y una descripción general, ver el [README](README.md).

## Qué corre en cada modo, componente por componente

Cada modo usa una combinación distinta de piezas. Los cuadros verdes son 100% locales e instantáneos; los amarillos son el único punto de cada modo que cuesta algo extra (uso de tu cuenta, tiempo de espera, o un permiso que aprobar).

### Modo `natural` (el que viene activado por defecto)

```mermaid
flowchart TD
    A(["Termina tu turno"]) --> B["Hook Stop se dispara:<br/>speak.ps1"]
    B --> C["Lee el evento del hook<br/>por stdin (bytes crudos, UTF-8)"]
    C --> D["Get-CleanedText:<br/>saca títulos, viñetas, links,<br/>bloques de código — nada se acorta"]
    D --> E["Get-PronunciationPrompt:<br/>aplica el diccionario de 82<br/>términos técnicos (IPA)"]
    E --> F["Invoke-SpeechSynthesis:<br/>elige voz + velocidad de config.json"]
    F --> G(["System.Speech habla<br/>(voz nativa de Windows)"])

    classDef local fill:#d4edda,stroke:#28a745,color:#000
    class B,C,D,E,F,G local
```

Todo local, todo instantáneo. Ningún componente sale de tu máquina.

### Modo `literal`

```mermaid
flowchart TD
    A(["Termina tu turno"]) --> B["Hook Stop se dispara:<br/>speak.ps1"]
    B --> C["Lee el evento del hook<br/>por stdin"]
    C --> D["Usa el texto tal cual está,<br/>sin limpiar ni procesar nada"]
    D --> E["Invoke-SpeechSynthesis:<br/>elige voz + velocidad<br/>(sin diccionario de pronunciación)"]
    E --> F(["System.Speech habla"])

    classDef local fill:#d4edda,stroke:#28a745,color:#000
    class B,C,D,E,F local
```

El modo más simple: cero procesamiento, cero componentes extra.

### Modo `summary`

```mermaid
flowchart TD
    A(["Termina tu turno"]) --> B["Hook Stop se dispara:<br/>speak.ps1"]
    B --> C["Lee el evento del hook<br/>por stdin"]
    C --> D["Get-CleanedText:<br/>saca markdown, 100% local"]
    D --> E["⚠️ Get-AiSummary:<br/>llamada APARTE a claude -p --safe-mode<br/>usa tu cuenta de Claude, ~20s fijos de espera"]
    E -->|"responde bien"| F["Usa el resumen que devolvió"]
    E -->|"falla (sin red, timeout, etc.)"| G["Cae al texto completo,<br/>igual que el modo natural"]
    F --> H["Get-PronunciationPrompt +<br/>Invoke-SpeechSynthesis"]
    G --> H
    H --> I(["System.Speech habla"])

    classDef local fill:#d4edda,stroke:#28a745,color:#000
    classDef extra fill:#fff3cd,stroke:#e0a800,color:#000
    class B,C,D,F,G,H,I local
    class E extra
```

El único de los cuatro que sale de tu máquina hacia una llamada de Claude — por eso no viene activado por defecto. Si esa llamada falla por lo que sea, nunca te quedás sin nada: cae al comportamiento del modo natural.

### Modo `active`

```mermaid
flowchart TD
    A(["Empieza tu turno"]) --> B["Hook UserPromptSubmit se dispara:<br/>prompt-active-mode.ps1"]
    B --> C["Te recuerda, cada turno,<br/>que hables vos mismo al terminar"]
    C --> D["Redactás una frase corta<br/>y natural para el oído"]
    D --> E["⚠️ Corrés say.ps1 con esa frase,<br/>pasada por un heredoc de stdin<br/>(primera vez puede pedir tu permiso)"]
    E --> F["say.ps1: Get-PronunciationPrompt +<br/>Invoke-SpeechSynthesis"]
    F --> G(["System.Speech habla,<br/>ya en el mismo turno"])

    H(["Termina tu turno"]) --> I["Hook Stop se dispara:<br/>speak.ps1"]
    I --> J["Ve que el modo es active:<br/>no hace nada, sale"]

    classDef local fill:#d4edda,stroke:#28a745,color:#000
    classDef extra fill:#fff3cd,stroke:#e0a800,color:#000
    class B,C,D,F,G,I,J local
    class E extra
```

El más rápido de los cuatro (nada de esperar a una llamada aparte), pero el único que le pide permiso a Claude Code — porque acá el que corre el comando es el modelo mismo, no un hook automático. Fíjate que el hook `Stop` (abajo del diagrama) sigue disparándose igual que en los otros modos, pero se queda quieto a propósito — así nunca se superponen las dos formas de hablar.
