# Indice general de Nini Hub

## Proposito y uso

Este archivo permite localizar las responsabilidades importantes sin recorrer
todo el repositorio. Contiene rutas y simbolos ancla, no un inventario completo
ni conteos congelados. Antes de cambiar un owner, buscar consumidores actuales
con `rg` y revisar el HEAD/worktree real.

Orden de lectura para relevo:

```text
AGENTS.md
  -> architecture.md
  -> project-index.md
  -> product-migration.md solo para compatibilidad, QA o cutover
  -> skill especializada
  -> codigo y pruebas vigentes
```

La narracion historica completa esta archivada en
`product-migration-history-2026-08-25.md` y se consulta solo para auditoria por
ID; no forma parte del relevo ordinario.

## Identidad y repositorios

| Concepto | Estado vigente |
|---|---|
| Producto vigente | Nini Hub |
| Application ID vigente | `com.nini.hub` |
| Paquete Dart vigente | `nini_hub` |
| Ejecutable vigente | `nini_hub` |
| Repo de trabajo | `/home/nini/StudioProjects/nini_hub` |
| Linaje Git importado | MultiCLI AI hasta `5d378f24f49dc2d4594afbbf487890e463abc88d` |
| Repo legacy protegido | `/home/nini/StudioProjects/multi_cli_ai` |
| Remoto legacy protegido | `https://github.com/LuchoNoPrograma/multi_cli_ai.git` |
| Motor vigente | `/home/nini/IdeaProjects/nini-agents` |

La repo Nini Hub tiene `.git` y `origin` independientes y no debe apuntar al
remoto legacy. Publicar commits, tags o releases sigue requiriendo autorizacion.

## Compatibilidad preservada

Producto, package Dart, app widget, assets, Linux, Windows, metadata Codex,
discovery, lifecycle y launch ya usan Nini Hub/nini-agents. Permanecen
deliberadamente:

- base logica SQLite `multicli_ai` con schemaVersion 2 dentro del soporte Nini
  Hub ya importado y marcado `NHUB`;
- `MULTICLI_HOME`, `~/MultiCliProfiles` y compatibilidad con perfiles existentes;
- scripts personales Nini Hub disponibles para build/install manual, con las
  variantes MultiCLI AI preservadas como rollback legacy.

Son contratos compatibles, no identidad vigente ni trabajo de migracion
pendiente. Solo se retiran mediante un cambio de compatibilidad/cutover aprobado.

## Entrypoints y composicion

| Ruta o simbolo | Responsabilidad |
|---|---|
| `lib/main.dart` | Bootstrap SQLite, inicializacion Flutter y `ProviderScope` |
| `lib/app/nini_hub_app.dart` - `NiniHubApp` | App widget y startup visual |
| `lib/app/app_startup.dart` | Fallo tipado de startup |
| `lib/app/providers.dart` | Composition root productivo |
| `lib/app/shell/dashboard_shell.dart` | Shell, navegacion y acciones globales visibles |
| `lib/core/database/app_database.dart` - `AppDatabase` | Infraestructura SQLite compartida |
| `lib/core/database/database_bootstrap.dart` - `DatabaseBootstrap` | Resolucion de rutas, importacion compatible, ownership SQLite y apertura explicita |
| `lib/core/process/process_runner.dart` - `ProcessRunner` | Procesos, timeout, redaccion y command log |
| `lib/core/process/nini_agents_read_client.dart` - `NiniAgentsReadClient` | Transporte JSON v1 tipado para consultas y mutaciones de Nini Agents |

`lib/app/providers.dart` es el punto de sustitucion de implementaciones
concretas. No trasladar reglas o queries hacia ese archivo.

## Owners por feature

| Feature | Owner y anclas |
|---|---|
| Profiles | `features/profiles/domain/profile.dart`, `application/profile_management.dart`, `data/profile_discovery_service.dart`, `data/nini_agents_profile_lifecycle.dart`, `presentation/controllers/profiles_controller.dart` |
| Accounts | `features/accounts/domain/account.dart`, `application/account_management.dart`, `application/account_device_auth.dart`, `data/drift_account_repository.dart`, `presentation/accounts_quota_clock.dart`, `presentation/controllers/accounts_controller.dart` |
| Workspaces | `features/workspaces/domain/workspace.dart`, `application/launch_agent.dart`, `data/drift_workspace_repository.dart`, `data/nini_agents_agent_launcher.dart`, `data/desktop_workspace_runtime.dart`, `presentation/controllers/workspace_controller.dart` |
| Usage | `features/usage/domain/usage.dart`, `domain/quota_reset_anchor_policy.dart`, `application/usage_refresh.dart`, Data providers/repositories y `presentation/controllers/usage_controller.dart` |
| Heartbeat | `features/heartbeat/domain/heartbeat_policy.dart`, `application/heartbeat.dart`, `data/dart_heartbeat_scheduler.dart`, `presentation/controllers/heartbeat_controller.dart` |
| Activity | `features/activity/domain`, `application/activity_history.dart`, `data/drift_activity_repository.dart`, `presentation/controllers/activity_controller.dart` |
| Settings | `features/settings/domain/app_preferences.dart`, `application/settings.dart`, `data/drift_settings_repository.dart`, `data/desktop_settings_runtime.dart`, `presentation/controllers/settings_controller.dart` |
| Calendar | Vista y filtros bajo `features/calendar/presentation`; Usage conserva el calendario de cuotas bajo su propio owner |

## Contratos y ordenes de efectos importantes

### Profiles

- `DiscoverProfiles` devuelve snapshot estable.
- Create/Rename/Delete ejecutan primero el lifecycle JSON de Nini Agents,
  actualizan solo la identidad SQLite necesaria y despues redescubren.
- Un fallo posterior al efecto externo usa `ProfileMutationAppliedFailure`; no
  simular rollback que el motor no garantiza.
- `partially_applied` provoca `status`, reconciliacion SQLite y una lectura
  fresca del controller antes de presentar el fallo.
- Identidad historica, alias, favorito y fechas se conservan primero por path y
  luego por tool/profile/source. `hasAuthFile` se preserva como metadata local:
  el contrato publico no lee ni expone credenciales.

### Workspaces y launch

- `LaunchAgent` valida perfil y workspace.
- Ejecuta `AgentLauncher.launch()` antes de `recordOpened()` y de guardar la
  seleccion.
- `NiniAgentsAgentLauncher` usa `nini-agents launch` para perfiles administrados
  y conserva el ejecutable nativo para el perfil principal.
- El adapter Data decide terminal, argumentos, environment y working directory;
  propaga `MULTICLI_HOME` y el opt-in de titulo Hyper al motor.
- Paths Windows requieren normalizacion de casing tras el puerto.

### Usage y sincronizacion visible

- Provider -> snapshot SQLite -> Activity -> KeepAlive -> Activity/calendario ->
  Accounts.
- `UsageRefreshCoordinator` serializa la sincronizacion transversal.
- Evitar reload global y queries por cuenta dentro de loops.
- Accounts conserva la lectura visible y la exitosa inmediatamente anterior.
  `DriftAccountRepository` recupera hasta dos exitos por perfil en la misma
  query agrupada; la proyeccion incremental rota ambas muestras al avanzar un
  snapshot, sin esperar una recarga SQLite.
- `QuotaResetAnchorPolicy` distingue anclas confirmadas de proyecciones que se
  desplazan junto con la observacion. Uso positivo confirma salvo que las dos
  lecturas demuestren una proyeccion movil; sin evidencia suficiente la hora es
  estimada.
- `accountsQuotaClockProvider` publica una sola hora compartida cada minuto
  mientras Accounts esta montado. Los cards no crean timers propios y muestran
  `Reinicia en` solo para anclas confirmadas; el resto usa `Estimado en`.
- Activity observa en vivo los 250 `CommandLogs` mas recientes: la insercion
  `running` de `ProcessRunner` y su transicion terminal se publican sin esperar
  una recarga global ni el fin del flujo que origino el comando.
- `ProcessRunner.run()` registra Activity por defecto. Las lecturas internas
  machine-safe de Nini Agents (`version`, `list`, `status` y `tools`) desactivan
  ese registro; mutaciones, launch, Heartbeat y acciones operativas continúan
  visibles.

### Heartbeat

- `HeartbeatPolicy` concentra ventanas y decisiones puras.
- La ventana esperada se toma de la proyeccion Codex vigente; un perfil con una
  unica ventana de 43200 minutos conserva su ciclo de 30 dias. Exito del
  comando y verificacion del ancla son resultados distintos y ambos deben
  quedar explicitos para el usuario.
- El probe programado resuelve el perfil por ID desde `ProfileRepository`; no
  ejecuta discovery completo por cada cuenta. El arranque sincroniza perfiles
  una vez y el Heartbeat manual conserva su rediscovery de validacion.
- `DartHeartbeatScheduler` mantiene FIFO de operaciones, FIFO de probes, leases,
  timers y retencion.
- Nunca componer dos schedulers productivos.
- Disable cancela timers y pendientes; una operacion in-flight puede terminar,
  pero no debe producir writes tardios contrarios al estado vigente.

### Startup

- Orden previo a Riverpod: resolver soporte -> validar/migrar SQLite -> abrir
  `AppDatabase` objetivo -> validar/registrar propiedad SQLite -> override de
  `databaseProvider`.
- Un fallo de ruta, locking, validacion o apertura muestra un estado seguro sin
  construir Settings ni repositories. El provider productivo ya no abre una
  ruta SQLite implicita.
- Orden heredado: Settings gate -> discovery -> Activity -> calendario -> monitor
  Heartbeat -> Accounts.
- Los efectos bloqueantes y fallos parciales deben caracterizarse antes de
  cambiar el orden.

## SQLite y datos locales

| Elemento | Estado vigente |
|---|---|
| Definicion | `lib/core/database/app_database.dart` - `AppDatabase` |
| Importacion/ownership | `lib/core/database/legacy_database_migrator.dart` - `LegacyDatabaseMigrator` |
| Bootstrap | `lib/core/database/database_bootstrap.dart` - `DatabaseBootstrap` |
| Nombre logico | `multicli_ai` |
| Schema | Drift `schemaVersion = 2` |
| Journal | WAL habilitado en `beforeOpen` |
| Ownership | `PRAGMA application_id = 0x4E485542` (`NHUB`) |
| Soporte | Nini Hub y MultiCLI AI usan archivos fisicos separados |

Tablas vigentes: `CliProfiles`, `ProfileMetadatas`, `CostShares`,
`UsageChecks`, `QuotaWindows`, `ResetCreditSnapshots`,
`DailyUsageBuckets`, `CommandLogs`, `Workspaces` y `AppSettings`.

Contratos:

- El cambio de application ID separa el soporte por producto. Windows debe
  confirmar su ruta mediante runtime real antes de CUT-01.
- La importacion historica exige origen cerrado, WAL consistente,
  `user_version = 2`, tablas conocidas, `quick_check`, FK, conteos y
  equivalencia antes de activar el destino.
- El destino se marca `NHUB`. En reinicios se valida por ownership, schema e
  integridad; no se compara otra vez con el rollback y puede conservar
  escrituras legitimas nuevas.
- Un destino sin marca solo se adopta mediante el contrato historico exacto; un
  `application_id` ajeno falla cerrado.
- No editar `app_database.g.dart`, incrementar schema o tocar filas reales sin
  un alcance de datos independiente.
- No copiar solo el `.sqlite` cuando existe WAL ni abrir simultaneamente el
  mismo archivo desde ambos productos.
- Evidencia ancla:
  `test/core/database/legacy_database_migrator_test.dart` y
  `test/core/database/database_bootstrap_test.dart`.

## Integraciones desktop vigentes

| Integracion | Owner y contrato vigente |
|---|---|
| Discovery | `ProfileDiscoveryService` + `NiniAgentsReadClient`: JSON `list/tools`, schema v1/v2 y sincronizacion SQLite |
| Lifecycle | `NiniAgentsProfileLifecycle`: JSON `new/rename/delete`, metadata local y reconciliacion por `status` |
| Launch | `NiniAgentsAgentLauncher` + `DesktopWorkspaceRuntime`: terminal, working directory, titulo y recencia |
| Procesos | `ProcessRunner`: executable/args, environment, timeout, cancelacion, redaccion y Activity |
| Device Auth | `CodexAccountDeviceAuthGateway`: JSON-RPC encapsulado y handoff focal de autenticacion |
| Usage | `CodexUsageProvider`: app-server por perfil, snapshot tipado y persistencia atomica |
| Heartbeat | `ProcessHeartbeatCommandGateway` + scheduler unico: ciclo dinamico, exec y verificacion |
| Codex app-server | `providers/codex` + runtime compartido: stdio limpio, lifecycle y fallos tipados |

## Contrato vigente de Nini Agents

Repositorio externo: `/home/nini/IdeaProjects/nini-agents`. Revalidar
branch/HEAD/worktree, docs, implementacion y release antes de cualquier cambio o
afirmacion de distribucion; Nini Hub no posee ese worktree implicitamente.

Fuentes del motor que deben contrastarse cuando aplique:

- `docs/json-cli.md` y `schema/cli-output.schema.json`.
- `docs/adapter-schema.md`.
- `nini-agents` y `nini-agents.ps1`.

Contrato consumido por Nini Hub:

- `NiniAgentsReadClient` ejecuta `nini-agents --json` con argumentos
  separados y valida envelope v1, comando, `ok/data/error`, exit code, stderr,
  conteos, schema de summaries y errores snake-case.
- `tools` es el inventario de capacidades; no inventar un comando
  `capabilities`.
- Discovery/status/mutaciones propagan `MULTICLI_HOME` sin leer credenciales ni
  contenido de perfiles.
- `new/rename/delete` modelan `not_applied` y `partially_applied`; delete
  exige `--confirm <tool>/<profile>` exacto.
- Launch administrado usa
  `nini-agents launch <tool>/<profile> -- <args>`.
- App-server, Usage y Heartbeat administrados usan
  `nini-agents exec codex/<profile> -- <args>`; el perfil principal conserva
  Codex nativo con `CODEX_HOME`.
- Un resultado indeterminado consulta `status`, reconcilia SQLite y refresca
  Presentation antes de mostrar el fallo.
- `MultiCliGateway`, `MultiCliProfileLifecycle` y
  `MultiCliAgentLauncher` ya no son implementaciones productivas.

Brechas activas:

- Verificar durante CUT-01 que CRUD/exec esten fusionados y publicados en el
  motor distribuido; su presencia local no demuestra release.
- La suite base del motor conserva 18 fallos Pester ajenos al contrato focal.
- Bash 3.2/macOS conserva un incidente legacy no diagnosticado.
- Capacidades no consumidas por Nini Hub no deben presentarse como disponibles.
- Evidencia Data local:
  `test/core/process/nini_agents_read_client_test.dart`,
  `test/features/profiles/data/profile_discovery_service_test.dart`,
  `test/features/profiles/data/nini_agents_profile_lifecycle_test.dart` y
  pruebas de Workspaces/Heartbeat.

## Scripts personales e instalacion

`scripts_personales/` esta ignorado por `.gitignore`; sus archivos no forman
parte del historial Git:

- `scripts_personales/compilar.sh`
- `scripts_personales/instacompilado.sh`

`compilar.sh` ejecuta el build Linux release e `instacompilado.sh` lo invoca
antes del staging, backup, activacion y launcher con binario `nini_hub`,
instalacion en `.local/opt/nini-hub` y desktop entry `com.nini.hub`. Ambos
archivos tienen modo `775` y permanecen ignorados por Git. No versionarlos,
publicarlos o ejecutarlos sin autorizacion expresa.

## Validacion y pruebas ancla

| Area | Evidencia focalizada |
|---|---|
| Arquitectura | `test/architecture/import_boundaries_test.dart` |
| Profiles | `test/features/profiles/` |
| Workspaces | `test/features/workspaces/` |
| Usage | `test/features/usage/` |
| Heartbeat | `test/features/heartbeat/` |
| Accounts | `test/features/accounts/` |
| Activity | `test/features/activity/` |
| Settings | `test/features/settings/` |
| SQLite | migrador/fixtures, bootstrap/startup y caso real opt-in con directorio aprobado |
| Scripts | `bash -n` y validacion desktop/install focalizada |
| Linux | QA-01A: arranque debug real con HOME/datos/perfiles temporales, SQLite integra y cierre limpio |
| Windows | runtime real obligatorio para la puerta final |

No ejecutar builds nativos o suites completas por defecto. Registrar siempre lo
no ejecutado.

## Comandos de reindexado manual

Cuando no exista un grafo de codigo disponible, reconstruir el mapa necesario
con busquedas acotadas:

```bash
rg --files lib test linux windows
rg -n '^(abstract interface class|final class|class) ' lib/features lib/app lib/core
rg -n 'MultiCli|multi_cli|nini-agents|AppDatabase|ProcessRunner' lib linux windows
rg -n '^import |^export ' lib/features
```

Actualizar este indice solo cuando cambie ownership, un entrypoint, schema,
integracion, plataforma o comando de validacion. No agregar cada archivo nuevo.
