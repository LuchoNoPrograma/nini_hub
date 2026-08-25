# Arquitectura de Nini Hub

## Estado y objetivo

Nini Hub usa una Clean Architecture ligera por feature para Flutter Desktop.
La identidad, datos, motor, perfiles y operacion principales ya funcionan como
Nini Hub sobre `nini-agents`. Los nombres `MultiCli*`, `MULTICLI_HOME`, rutas de
perfiles y el nombre logico SQLite `multicli_ai` que aun existen son contratos
de compatibilidad preservados, no arquitectura objetivo pendiente.

```text
Flutter view/widget/dialog
          |
          v
presentation controller/notifier + view state
          |
          v
application use case
          |
          v
domain entity/policy/port/failure
          ^
          |
data repository/gateway/mapper
          |
          v
Drift | filesystem | Process | terminal | nini-agents | Codex JSON-RPC
```

| Capa | Puede depender de | No puede depender de |
|---|---|---|
| `domain` | Dart puro | Flutter, Riverpod, Drift, `dart:io`, plugins |
| `application` | Domain | Presentation, Drift, gateways concretos |
| `data` | Domain e infraestructura | Presentation, controllers |
| `presentation` | Application y modelos visibles de Domain | Data, Drift, filesystem, procesos |
| `app` | Todas, solo para composicion | Reglas, queries o parsing de proveedores |

`core` contiene solo capacidades compartidas con ownership real.
`core/database` es infraestructura Data compartida y solo puede ser importada
por Data y App.

## Estructura

```text
lib/
  app/
    providers.dart
    shell/
  core/
    database/
    process/
    platform/
    errors/
  features/{feature}/
    domain/
    application/
    data/
    presentation/
```

Crear solo carpetas y artefactos requeridos por una responsabilidad real.

## Responsabilidades

### Domain

- Modela perfiles, cuentas, workspaces, suscripciones, cuotas, actividad y
  heartbeat sin tecnologia.
- Mantiene invariantes, policies, IDs y fallos esperables.
- Define puertos para persistencia e integraciones reales.
- No contiene rows, companions, `BuildContext`, `AsyncValue`, JSON-RPC o
  `Platform`.

### Application

- Expone acciones y coordina orden de efectos mediante puertos.
- Recibe commands pequenos y devuelve resultados o fallos tipados.
- Modela aplicacion parcial cuando un efecto externo ya ocurrio y no puede
  revertirse.
- No crea casos de uso para getters o calculos triviales.

### Data

- Implementa repositories, queries Drift, mappers y migraciones.
- Encapsula filesystem, procesos, terminales, `nini-agents` y Codex app-server.
- Traduce errores tecnicos a fallos del contrato.
- Mantiene secretos y salida sensible fuera de contratos visibles.

### Presentation

- Renderiza UI y recoge acciones desktop.
- Mantiene estado inmutable y operaciones focalizadas por feature.
- Invoca Application mediante Riverpod.
- Correlaciona loading, progreso, error, retry y dispose.

### App

- Conecta puertos, adaptadores, casos de uso y controllers.
- Configura `ProviderScope`, ciclo de vida, tema, navegacion y shell.
- No acumula reglas ni vuelve a crear un controller global.

## Flujos ancla

### Lanzar agente

```text
LaunchAgentDialog
  -> WorkspaceController
  -> LaunchAgent
  -> AgentProfileRepository + WorkspaceRepository
  -> AgentLauncher
  -> adapter Data de nini-agents
  -> terminal/proceso desktop
```

Application valida perfil y workspace. El launcher ocurre antes de registrar la
apertura y guardar la seleccion. Data decide ejecutable, argumentos, environment
y terminal; Presentation solo muestra estado o fallo.

### Actualizar uso

```text
UsageController
  -> RefreshProfileUsage / RefreshAllUsage
  -> UsageProvider
  -> transaccion SQLite
  -> Activity
  -> Heartbeat
  -> sincronizacion visual acotada
```

Conservar el orden observable y evitar reload global. Una coordinacion
transversal vive en la feature propietaria de la accion visible.

### Startup

```text
Settings gate
  -> discovery
  -> Activity
  -> calendario
  -> monitor Heartbeat
  -> Accounts
```

El composition root conserva este orden salvo que un cambio aprobado lo
caracterice y sustituya.

## Persistencia

- Rows y companions permanecen en Data y se mapean a entidades.
- SQLite filtra, ordena, agrega y limita; evitar queries por fila y tablas
  completas para contar.
- Mantener schema, IDs, nulabilidad, dinero y UTC en todo cambio compatible.
- Un cambio de ubicacion no implica cambio de schema.
- La importacion legacy a Nini Hub ya fue unica. Bootstrap y reparaciones deben
  reconocer ownership `NHUB`, ser consistentes con WAL y conservar rollback.
- No abrir simultaneamente el mismo archivo fisico desde la aplicacion vieja y
  la nueva.

## Integracion con Nini Agents

`nini-agents` es un proceso externo y debe permanecer tras puertos de Domain y
adaptadores Data.

- Usar ejecutable y argumentos separados, sin shell intermedio por defecto.
- Propagar `MULTICLI_HOME` cuando el setting de perfiles lo requiera.
- Consumir JSON versionado para consultas y mutaciones machine-safe.
- Exigir stdout limpio para transportes como `codex app-server --stdio`.
- Controlar exit code, stderr, timeout, cancelacion, working directory y
  redaccion.
- No parsear mensajes humanos como contrato estable.
- No asumir que una capacidad planeada existe; comprobar docs, implementacion y
  pruebas del HEAD observado.

## Estado reactivo y concurrencia

- Un controller/notifier y un estado inmutable por feature.
- Streams Drift para lecturas reactivas cuando aporten estado focalizado.
- Cada respuesta asincrona debe corresponder a la solicitud vigente.
- Serializar operaciones externas cuando el contrato no admita concurrencia.
- Disable/dispose cancela timers y pendientes segun contrato, sin writes tardios
  no autorizados.
- No reintroducir `reload()` global como sincronizacion ordinaria.

## Compatibilidad desktop

- Linux y Windows son plataformas de primera clase.
- La UI debe soportar teclado, mouse, resize, constraints y scroll desde 900x600.
- Las rutas se normalizan segun plataforma tras un adapter, no en Domain o UI.
- Instaladores, terminales, application IDs y directorios de soporte se validan
  por plataforma.
- Evidencia Linux no demuestra Windows y viceversa.

## Criterios de revision

- Domain prueba sin Flutter, Drift, filesystem ni procesos.
- Presentation no importa Data, database o gateways concretos.
- Data no conoce controllers o widgets.
- App solo compone.
- El caso de uso expresa accion y orden de efectos.
- Rows Drift no cruzan Data.
- No aparecen N+1, cargas completas, reload global ni respuestas obsoletas.
- Procesos, rutas, secretos, timeout y plataforma quedan controlados.
- Formato, analisis y pruebas focalizadas cubren el delta.
- `test/architecture/import_boundaries_test.dart` mantiene los limites y su
  baseline explicita.
