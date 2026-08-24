---
name: multi-cli-ai-migrate-architecture
description: Planificar, investigar, ejecutar o continuar migraciones arquitectonicas legacy de MultiCLI AI por fracciones pequenas, preservando funcionalidad, consumiendo las skills canonicas de capa y actualizando la bitacora de relevo. Usar tambien cuando otro agente deba retomar una migracion o cuando un posible bug pueda confundirse con comportamiento a conservar; no usar para features o fixes sin cambio de limites arquitectonicos.
---

# MultiCLI AI Migrate Architecture

## Proposito

Gobernar una sola fraccion de migracion legacy sin perder comportamiento, datos ni contexto entre agentes. Esta skill no reemplaza las skills de capa ni autoriza implementacion.

## Fuentes obligatorias

Leer en este orden:

1. `../../../AGENTS.md` para autorizacion y reglas globales.
2. `../../references/architecture.md` para limites e invariantes objetivo.
3. `../../references/architecture-migration.md` para baseline, fraccion activa, decisiones y relevo.

Si `HEAD`, branch o worktree difieren de la bitacora, revalidar la evidencia afectada antes de continuar. Nunca eliminar cambios concurrentes.

## Seleccion de skills

| Necesidad real de la fraccion | Skill adicional |
|---|---|
| Cambio real en dos o mas capas | `$multi-cli-ai-feature-integral` |
| Entidades, reglas, puertos, commands, fallos o casos de uso | `$multi-cli-ai-domain-application` |
| Drift, mappers, filesystem, procesos, terminales o proveedores | `$multi-cli-ai-data-desktop-integrations` |
| Controller, estado, view, widget o dialog | `$multi-cli-ai-presentation-flutter-desktop` |
| Bug posible, causa desconocida o comportamiento inconsistente | `$multi-cli-ai-diagnostico-incidentes` |

Activar solo las necesarias. La orquestadora integral coordina contratos; no sustituye la revision de cada capa.

## Granularidad

Una fraccion debe tener un solo objetivo funcional y una salida verificable. Preferir:

- una caracterizacion solo lectura;
- un contrato Domain/Application;
- una implementacion Data y mapper;
- un controller/state de Presentation;
- una conexion de composition root o fachada;
- una validacion de equivalencia y retiro de dependencia legacy.

No combinar en una fraccion un cambio de esquema, fix, optimizacion, rediseno visual o nueva funcionalidad salvo que el delta los enumere y el usuario los apruebe expresamente.

## Flujo obligatorio

1. **Retomar contexto:** leer las fuentes, verificar Git y resumir estado, fraccion, hechos, inferencias y pendientes.
2. **Investigar:** trazar entradas, salidas, reglas, efectos, datos, UI, concurrencia, Linux/Windows, consumidores y cobertura actual solo en lectura.
3. **Caracterizar:** completar la puerta de equivalencia funcional de la bitacora. Agregar pruebas de caracterizacion al delta si falta evidencia esencial.
4. **Auditar dudas:** ante una conducta sospechosa, activar diagnostico de incidentes. No implementar el fix. Registrar `preserve`, `separate_fix` o `blocked_pending_decision`.
5. **Congelar contratos:** definir IDs, nulabilidad, fallos, orden de efectos, ownership, transaccion, estado reactivo y fachada legacy necesarios.
6. **Delimitar:** presentar el delta exacto y esperar aprobacion. Incluir la bitacora entre los archivos si debe actualizarse.
7. **Ejecutar:** usar las skills de capa y modificar solo el corte aprobado. Detenerse ante otro archivo, contrato, migracion, plataforma o efecto.
8. **Validar:** formato, analisis focalizado, pruebas de caracterizacion y pruebas del nuevo propietario. Comparar comportamiento previo y posterior.
9. **Actualizar relevo:** registrar HEAD observado, archivos, contratos, decisiones, desviaciones, comandos, resultados, riesgos y siguiente fraccion. Mantener el baseline y el historial concisos.
10. **Reportar:** emitir el formato canonico de la bitacora y el cierre exigido por `AGENTS.md`.

## Equivalencia funcional

Una migracion es equivalente cuando conserva, segun corresponda:

- entradas, resultados, estados vacios, defaults y mensajes visibles;
- validaciones, reglas, fallos esperables y orden de efectos;
- datos existentes, IDs, nulabilidad, dinero, fechas UTC y ruta de upgrade;
- ejecutable, argumentos, environment, timeout, cancelacion y redaccion;
- loading, exito, error, reintento, seleccion y restricciones desktop;
- proteccion contra doble envio, estado obsoleto y recursos sin liberar;
- comportamiento Linux/Windows y limites de rendimiento observables.

No exigir conservar imports, rows o controllers legacy. Su reemplazo es el objetivo, siempre que el contrato observable permanezca estable.

## Posibles bugs

- No deducir intencion solo porque exista una prueba; una prueba puede caracterizar un bug.
- Comparar la conducta con reglas de producto, UI, datos reales, contratos externos y tests.
- Si el bug se confirma, proponer un fix separado. La migracion puede bloquearse o preservar temporalmente la conducta mediante una decision explicita.
- No ampliar el alcance para corregirlo y no ocultarlo bajo un refactor.

## Bitacora y continuidad

- Una sola fraccion puede estar activa.
- El diagnostico base es estable; agregar enmiendas fechadas.
- Registrar rutas y simbolos, no narraciones de sesion.
- Diferenciar `observed`, `inferred`, `suspected` y `decided`.
- No marcar `complete` con pruebas pendientes o evidencia solo estatica cuando hay comportamiento runtime.
- El relevo debe permitir que otro agente identifique en una lectura que esta aprobado, que esta prohibido y cual es la proxima accion.

## Autoevaluacion

- La fraccion es realmente pequena y tiene un solo resultado?
- Se leyeron arquitectura, bitacora y cambios concurrentes?
- Se consumieron todas y solo las skills necesarias?
- El comportamiento previo esta caracterizado antes de mover ownership?
- Las sospechas se diagnosticaron sin mezclarlas con un fix?
- Domain queda puro y Presentation deja de conocer infraestructura en el corte?
- Se conservaron datos, plataforma, errores y orden de efectos?
- El delta ejecutado coincide exactamente con el aprobado?
- La validacion demuestra equivalencia y la bitacora permite continuar?
