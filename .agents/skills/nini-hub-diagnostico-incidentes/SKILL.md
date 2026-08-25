---
name: nini-hub-diagnostico-incidentes
description: Investigar incidentes de Nini Hub con bugs, lentitud, bloqueos, cargas infinitas, estado obsoleto, resultados incorrectos, duplicados o fallos intermitentes cuando la causa aun no se conoce. Usar para trazar Flutter/Riverpod, Drift/SQLite, filesystem, procesos, terminales, nini-agents y Codex; no implementar el fix sin alcance posterior aprobado.
---

# Nini Hub Diagnostico Incidentes

## Proposito

Localizar la primera divergencia entre comportamiento esperado y observado conservando evidencia y separando diagnostico de implementacion.

## Alcance del proyecto

- Recorridos completos entre Presentation, Application, Domain, Data, App, SQLite y procesos desktop.
- Incidentes de concurrencia, lifecycle, streams, colas, timeouts, rutas, stdout/stderr y contratos externos.

## Fuentes

- Leer `AGENTS.md` y `.agents/references/project-index.md`; consultar la bitacora solo si el incidente afecta compatibilidad legacy, QA de plataforma o cutover.
- Revisar logs sanitizados, pruebas, codigo consumidor y cambios concurrentes sin modificar el sistema.

## Patrones del proyecto

- `lib/features/heartbeat/data/dart_heartbeat_scheduler.dart` - `DartHeartbeatScheduler`: colas FIFO, leases, timers, disable y operaciones in-flight.
- `lib/features/usage/presentation/controllers/usage_refresh_coordinator.dart` - `UsageRefreshCoordinator`: cola de sincronizacion transversal y propagacion de fallos visibles.
- `lib/core/process/process_runner.dart` - `ProcessRunner`: lifecycle del proceso, timeout, salida sanitizada y persistencia de Activity.

## Flujo

1. Definir sintoma, alcance, frecuencia, plataforma, ultima version conocida y resultado esperado.
2. Trazar el recorrido desde la accion visible hasta el primer estado o efecto divergente.
3. Separar evidencia observada, inferencias e hipotesis; descartar cada hipotesis con una comprobacion focalizada.
4. Clasificar la conducta como comportamiento vigente, compatibilidad a preservar, `separate_fix` o bloqueo demostrado.
5. Reportar causa o punto de bloqueo, impacto y validacion necesaria sin implementar el fix.

## Reglas

- No consultar ni modificar datos reales, credenciales, procesos o configuracion fuera del alcance autorizado.
- No convertir una prueba legacy en prueba de intencion sin contrastar producto, datos y contratos.
- No mezclar mitigacion, refactor o fix con el diagnostico.

## Validacion

- Usar reproducciones minimas, consultas de solo lectura, pruebas focalizadas y logs redactados.
- Registrar validaciones no ejecutadas y limites de evidencia Linux/Windows.
- No ejecutar suites completas, builds o procesos externos cuando una comprobacion acotada sea suficiente.

## Autoevaluacion

- La causa esta demostrada en el primer punto divergente o sigue siendo hipotesis?
- El fix propuesto queda fuera del diagnostico hasta recibir alcance y aprobacion?
