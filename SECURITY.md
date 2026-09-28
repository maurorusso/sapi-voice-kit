# Política de seguridad

## Reportar una vulnerabilidad

Si encontrás un problema de seguridad en `sapi-voice-kit`, por favor **no abras un issue público**. En vez de eso, reportalo de forma privada:

- **GitHub Security Advisories** (recomendado): [github.com/maurorusso/sapi-voice-kit/security/advisories/new](https://github.com/maurorusso/sapi-voice-kit/security/advisories/new)
- O por correo a la dirección de contacto del autor listada en su perfil de GitHub ([@maurorusso](https://github.com/maurorusso)).

Incluí, si podés: qué versión del plugin usás, los pasos para reproducir el problema, y el impacto que creés que tiene.

## Qué esperar

Este es un proyecto de un solo mantenedor, sin equipo dedicado de seguridad — no hay un tiempo de respuesta garantizado, pero los reportes se toman en serio y se van a revisar apenas sea posible.

## Alcance

Este plugin no usa API keys, no se conecta a servicios de terceros propios (salvo el modo opcional `summary`, que usa tu propia sesión de Claude), y no envía telemetría. El código completo — qué se escribe en disco, cuándo, y por qué — está documentado en el [README](README.md#privacidad-qué-se-guarda-en-disco-y-cuándo) y en [CLAUDE.md](CLAUDE.md).
