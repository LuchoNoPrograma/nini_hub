---
name: nini-hub-migrate-product
description: Planificar, ejecutar o continuar la migracion de Nini Hub desde MultiCLI AI y Multi CLI hacia la identidad Nini Hub y el motor nini-agents. Usar para fracciones de rebranding, compatibilidad SQLite, reemplazo de integraciones legacy, cutover o relevo entre agentes; no usar para features nuevas ni fixes aislados.
---

# Nini Hub Migrate Product

## Proposito

Gobernar una sola fraccion verificable de la migracion del producto sin perder historial, datos, comportamiento desktop ni continuidad entre agentes.

## Alcance del proyecto

- La migracion canonica vive en `.agents/references/product-migration.md` y se divide en 14 puntos agrupados en siete bloques.
- El legado funcional permanece en `lib/`, `linux/`, `windows/` y `scripts_personales/` hasta que su reemplazo tenga evidencia.
- Los repositorios externos `/home/nini/StudioProjects/multi_cli_ai` y `/home/nini/IdeaProjects/nini-agents` son dependencias de contexto, no targets implicitos de escritura.

## Fuentes

- Leer `AGENTS.md`, `.agents/references/architecture.md`, `.agents/references/project-index.md` y `.agents/references/product-migration.md` antes de delimitar una fraccion.
- Revalidar branch, HEAD, worktree y contratos externos cuando difieran del snapshot de la bitacora.

## Patrones del proyecto

- `lib/features/profiles/data/multi_cli_gateway.dart` - `MultiCliGateway`: frontera legacy de procesos que debe sustituirse por contrato, no por imports cruzados.
- `lib/core/database/app_database.dart` - `AppDatabase`: owner actual de SQLite schema v2 y punto de compatibilidad de datos.
- `lib/app/providers.dart` - providers de composicion: lugar donde se sustituyen implementaciones concretas despues de congelar contratos.

## Flujo

1. Retomar el snapshot y verificar hechos, decisiones, bloqueos y alcance aprobado.
2. Caracterizar entradas, salidas, datos, procesos, concurrencia, Linux y Windows del corte.
3. Presentar objetivo, reglas, archivos, capas, contratos, persistencia, integraciones, exclusiones y validacion; esperar aprobacion.
4. Ejecutar solo la fraccion aprobada usando las skills especializadas necesarias.
5. Validar equivalencia, actualizar el punto y dejar el siguiente relevo exacto.

## Reglas

- Mantener una sola fraccion activa y no mezclar migracion, fix, rediseño o cambio de schema no enumerado.
- Diferenciar `observed`, `inferred`, `decided`, `preserve`, `separate_fix` y `blocked`.
- No marcar un punto completo sin la evidencia exigida por su puerta de salida.

## Validacion

- Ejecutar formato, `flutter analyze` focalizado y pruebas dirigidas de los archivos productivos tocados.
- Ejecutar `flutter test test/architecture/import_boundaries_test.dart` cuando cambien limites o composicion.
- Registrar validaciones no ejecutadas, incluidos runtime Windows, procesos reales, red o builds nativos.

## Autoevaluacion

- La fraccion conserva historial, SQLite, perfiles, rutas, procesos y comportamiento observable aplicables?
- La bitacora permite que otro agente continue sin reconstruir la sesion?
