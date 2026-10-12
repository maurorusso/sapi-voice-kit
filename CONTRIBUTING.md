# Contribuir a sapi-voice-kit

## Este proyecto no acepta contribuciones de código externas

`sapi-voice-kit` es un proyecto personal de un solo mantenedor — no hay proceso de revisión de pull requests, y los PRs que se abran no van a ser mergeados. Esto es una decisión deliberada, no un descuido: mantener eso funcionando bien (revisión, coordinación, tests de regresión para cambios de terceros) es un trabajo aparte que este proyecto no tiene pensado sostener.

Si igual abrís un pull request, es probable que se cierre sin mergear, aunque el código sea correcto.

## Qué sí es bienvenido

- **Reportar un bug**: abrí un [Issue](https://github.com/maurorusso/sapi-voice-kit/issues/new) con los pasos para reproducirlo, tu versión de Windows, y qué esperabas que pasara.
- **Preguntas o ideas**: usá [Discussions](https://github.com/maurorusso/sapi-voice-kit/discussions) para eso — no hace falta que sea un bug concreto.
- **Reportar una vulnerabilidad de seguridad**: seguí el proceso de [SECURITY.md](SECURITY.md) (privado, no un Issue público).

Los reportes y comentarios sí se leen y se toman en cuenta — lo que no se acepta es código de terceros directamente en el repo.

## Correr los tests

Sirve para quien haga su propia copia. Desde la raíz del repositorio, en Windows:

```
powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests"
node --test tests/
```

Pester 3.4 viene con Windows PowerShell 5.1, y `node:test` con Node: no hay que instalar nada. El audio no se puede probar con aserciones; después de cambiar la limpieza de texto o el diccionario, corré `/sapi-voice-kit:test` y escuchá.

## Si querés modificar el código para tu propio uso

Es MIT — cloná el repo, modificá lo que necesites, y usalo libremente. Solo no esperes que esos cambios se integren acá.
