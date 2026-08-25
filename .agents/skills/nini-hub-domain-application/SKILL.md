---
name: nini-hub-domain-application
description: Crear, corregir o revisar Domain y Application de Nini Hub en Dart. Usar al tocar entidades, value objects, invariantes, politicas, fallos, puertos, commands, resultados o casos de uso; no usar para Drift, filesystem, procesos, Riverpod o widgets.
---

# Nini Hub Domain Application

## Proposito

Mantener reglas y coordinacion de Nini Hub independientes de Flutter, persistencia e integraciones concretas.

## Alcance del proyecto

- Codigo bajo `lib/features/{feature}/domain` y `lib/features/{feature}/application`.
- Puertos reales para SQLite, filesystem, procesos, terminales, nini-agents, Codex y reloj sin implementar tecnologia.

## Fuentes

- Leer `AGENTS.md`, `.agents/references/architecture.md` y la seccion de ownership de `.agents/references/project-index.md`.
- Leer los consumidores Data, Presentation y App solo para congelar el contrato observable.

## Patrones del proyecto

- `lib/features/profiles/application/profile_management.dart` - `CreateProfile`: dependencias `final` por constructor, validacion previa y fallo parcial tras efecto externo.
- `lib/features/workspaces/application/launch_agent.dart` - `LaunchAgent`: orden launcher antes de registrar y seleccionar workspace.
- `lib/features/heartbeat/domain/heartbeat_policy.dart` - `HeartbeatPolicy`: decisiones puras de tiempo y cuota sin infraestructura.

## Flujo

1. Trazar reglas, entradas, resultados, nulabilidad, IDs, fechas y fallos actuales.
2. Definir solo entidades, policies, puertos o casos de uso con responsabilidad real.
3. Preservar el orden de efectos y tipar aplicaciones parciales cuando un efecto no puede revertirse.
4. Actualizar consumidores solo si forman parte del delta integral aprobado.
5. Probar Domain/Application sin Flutter, Drift, filesystem ni procesos reales.

## Reglas

- Domain permanece en Dart puro y Application depende solo de Domain.
- No exponer rows Drift, JSON-RPC, excepciones tecnicas o `Platform` como contrato.
- Mantener dinero en unidades menores y fechas persistidas en UTC.

## Validacion

- Aplicar `dart format` a los archivos tocados.
- Ejecutar `flutter analyze` focalizado y las pruebas unitarias de los casos de uso o policies modificados.
- Comprobar imports con `flutter test test/architecture/import_boundaries_test.dart` cuando cambien contratos.

## Autoevaluacion

- El puerto representa una frontera real y no una abstraccion ceremonial?
- Los fallos esperables y efectos parciales permanecen tipados?
