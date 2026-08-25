---
name: nini-hub-feature-integral
description: Orquestar features de Nini Hub que creen un flujo nuevo o cambien realmente dos o mas capas entre Domain/Application, Data, Presentation y App. Usar para coordinar contratos y entrega vertical; no usar para cambios aislados, migracion legacy ni diagnostico sin fix autorizado.
---

# Nini Hub Feature Integral

## Proposito

Coordinar una entrega vertical pequena mediante contratos estables, ownership claro y validacion proporcional al riesgo.

## Alcance del proyecto

- Features bajo `lib/features/{feature}` y su conexion concreta en `lib/app`.
- Cruces de perfiles, cuentas, uso, heartbeat, actividad, settings y workspaces mediante puertos y casos de uso.

## Fuentes

- Leer `AGENTS.md`, `.agents/references/architecture.md` y `.agents/references/project-index.md`.
- Consumir las skills de Domain/Application, Data o Presentation solo cuando el delta toque esas responsabilidades.

## Patrones del proyecto

- `lib/features/workspaces/application/launch_agent.dart` - `LaunchAgent`: flujo transversal que valida perfil y workspace antes del launcher y del bookkeeping.
- `lib/app/providers.dart` - `profilesControllerProvider`: composition root que conecta puertos y casos de uso sin mover reglas a App.
- `lib/features/usage/presentation/controllers/usage_refresh_coordinator.dart` - `UsageRefreshCoordinator`: orden transversal y serializacion visibles que no deben dispersarse.

## Flujo

1. Identificar la accion visible, su feature propietaria y consumidores actuales.
2. Congelar commands, resultados, fallos, orden de efectos y estado reactivo.
3. Delimitar todas las capas y archivos necesarios antes de solicitar aprobacion.
4. Implementar de contratos hacia adaptadores, presentacion y composicion.
5. Validar el recorrido feliz, fallos esperables, concurrencia y regresiones fuera del owner.

## Reglas

- No comunicar features mediante controllers ajenos, repositories concretos o un event bus global.
- No agregar artefactos vacios para completar una plantilla.
- No ampliar un controller global cuando la feature puede tener owner propio.

## Validacion

- Aplicar `dart format` a los archivos Dart tocados.
- Ejecutar `flutter analyze` y pruebas unitarias/widget focalizadas al flujo.
- Ejecutar el guard de imports cuando cambien limites entre capas.

## Autoevaluacion

- Cada efecto tiene owner y orden explicitos?
- La UI observa solo el estado necesario y evita recargas globales?
