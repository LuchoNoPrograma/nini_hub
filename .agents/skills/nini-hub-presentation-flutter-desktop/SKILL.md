---
name: nini-hub-presentation-flutter-desktop
description: Crear, corregir o revisar Presentation de Nini Hub con Flutter Desktop y Riverpod. Usar al tocar controllers/notifiers, view states, vistas, widgets, dialogs, filtros, navegacion, loading, errores o interacciones Linux/Windows; no usar para Drift, gateways concretos o reglas de negocio.
---

# Nini Hub Presentation Flutter Desktop

## Proposito

Mantener una UI desktop focalizada, reactiva y resistente a concurrencia sin conocer infraestructura concreta.

## Alcance del proyecto

- Codigo bajo `lib/features/{feature}/presentation` y shell/navegacion en `lib/app` cuando formen parte del alcance.
- Interacciones de teclado y mouse, ventanas redimensionables y referencia minima de 900x600.

## Fuentes

- Leer `AGENTS.md`, `.agents/references/architecture.md` y el owner de la feature en `.agents/references/project-index.md`.
- Leer commands, resultados y fallos Application antes de definir estado visual.

## Patrones del proyecto

- `lib/features/profiles/presentation/controllers/profiles_controller.dart` - `ProfilesController`: notifier por feature, dependencias compuestas y rechazo de doble operacion.
- `lib/features/profiles/presentation/state/profiles_state.dart` - `ProfilesState`: estado inmutable y operacion focalizada.
- `lib/features/usage/presentation/controllers/usage_refresh_coordinator.dart` - `UsageRefreshCoordinator`: sincronizacion serializada tras una accion visible.

## Flujo

1. Trazar estados loading, exito, vacio, fallo, reintento, seleccion y dispose del flujo.
2. Definir controller/notifier y estado inmutable propios de la feature.
3. Conectar Application sin importar Data, Drift, filesystem ni gateways.
4. Correlacionar operaciones asincronas y limitar la actualizacion al estado afectado.
5. Validar resize, scroll, teclado, mouse y mensajes visibles en español.

## Reglas

- Presentation traduce fallos tipados y no interpreta excepciones Drift o JSON-RPC.
- No usar reload global como sincronizacion ordinaria ni permitir que una respuesta vieja sustituya estado nuevo.
- No asumir patrones Android para Linux o Windows.

## Validacion

- Aplicar `dart format` y `flutter analyze` focalizado.
- Ejecutar pruebas de controller y widget dirigidas a loading, fallo, doble envio, respuesta tardia y resize aplicables.
- No afirmar comportamiento Linux/Windows sin la evidencia correspondiente.

## Autoevaluacion

- La vista observa solo el estado que necesita?
- El controller queda libre de Data y protege lifecycle y concurrencia?
