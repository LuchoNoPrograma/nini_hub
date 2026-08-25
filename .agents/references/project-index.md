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
  -> product-migration.md
  -> skill especializada
  -> codigo y pruebas vigentes
```

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
| Motor objetivo | `/home/nini/IdeaProjects/nini-agents` |

La repo Nini Hub tiene `.git` independiente y no debe apuntar al remoto legacy.
El remoto nuevo se agregara solo en el punto de cutover autorizado.

## Baseline tras bloque Identidad

El working tree ya usa Nini Hub en producto, package Dart, app widget, assets,
Linux, Windows, release, metadata Codex, discovery/lifecycle y launch.
Permanecen deliberadamente:

- base logica SQLite `multicli_ai` con schemaVersion 2, hasta la migracion unica;
- `MULTICLI_HOME`, `~/MultiCliProfiles` y compatibilidad con perfiles existentes;
- scripts personales Nini Hub disponibles para build/install manual, con las
  variantes MultiCLI AI preservadas como rollback legacy.

Son contratos legacy preservados, no identidad vigente. Se retiran por
fracciones caracterizadas y aprobadas.

## Entrypoints y composicion

| Ruta o simbolo | Responsabilidad |
|---|---|
| `lib/main.dart` | Bootstrap SQLite, inicializacion Flutter y `ProviderScope` |
| `lib/app/nini_hub_app.dart` - `NiniHubApp` | App widget y startup visual |
| `lib/app/app_startup.dart` | Fallo tipado de startup |
| `lib/app/providers.dart` | Composition root productivo |
| `lib/app/shell/dashboard_shell.dart` | Shell, navegacion y acciones globales visibles |
| `lib/core/database/app_database.dart` - `AppDatabase` | Infraestructura SQLite compartida |
| `lib/core/database/database_bootstrap.dart` - `DatabaseBootstrap` | Resolucion de rutas, migracion unica, propiedad SQLite y apertura explicita |
| `lib/core/process/process_runner.dart` - `ProcessRunner` | Procesos, timeout, redaccion y command log |
| `lib/core/process/nini_agents_read_client.dart` - `NiniAgentsReadClient` | Transporte JSON v1 tipado para consultas y mutaciones de Nini Agents |

`lib/app/providers.dart` es el punto de sustitucion de implementaciones
concretas. No trasladar reglas o queries hacia ese archivo.

## Owners por feature

| Feature | Owner y anclas |
|---|---|
| Profiles | `features/profiles/domain/profile.dart`, `application/profile_management.dart`, `data/profile_discovery_service.dart`, `data/nini_agents_profile_lifecycle.dart`, `presentation/controllers/profiles_controller.dart` |
| Accounts | `features/accounts/domain/account.dart`, `application/account_management.dart`, `application/account_device_auth.dart`, `data/drift_account_repository.dart`, `presentation/controllers/accounts_controller.dart` |
| Workspaces | `features/workspaces/domain/workspace.dart`, `application/launch_agent.dart`, `data/drift_workspace_repository.dart`, `data/nini_agents_agent_launcher.dart`, `data/desktop_workspace_runtime.dart`, `presentation/controllers/workspace_controller.dart` |
| Usage | `features/usage/domain/usage.dart`, `application/usage_refresh.dart`, Data providers/repositories y `presentation/controllers/usage_controller.dart` |
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

### Heartbeat

- `HeartbeatPolicy` concentra ventanas y decisiones puras.
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
| Definicion | `lib/core/database/app_database.dart` |
| Migrador aislado | `lib/core/database/legacy_database_migrator.dart` - `LegacyDatabaseMigrator` |
| Bootstrap productivo | `lib/core/database/database_bootstrap.dart` - `DatabaseBootstrap` |
| Nombre logico | `multicli_ai` |
| Schema | Drift `schemaVersion = 2` |
| Linux legacy observado | `/home/nini/.local/share/com.nini.multi_cli_ai/multicli_ai.sqlite` |
| Linux objetivo | `/home/nini/.local/share/com.nini.hub/multicli_ai.sqlite` |
| Journal | WAL habilitado en `beforeOpen` |
| Propiedad SQLite | `PRAGMA application_id = 0x4E485542` (`NHUB`) |
| Migracion vigente | Comparacion exacta solo en primera migracion; reinicios confian en destino marcado y validado |

Tablas vigentes:

- `CliProfiles`
- `ProfileMetadatas`
- `CostShares`
- `UsageChecks`
- `QuotaWindows`
- `ResetCreditSnapshots`
- `DailyUsageBuckets`
- `CommandLogs`
- `Workspaces`
- `AppSettings`

Reglas:

- El cambio de application ID cambia el directorio de soporte en Linux.
- En Windows, `path_provider_windows` deriva el subdirectorio desde CompanyName y
  ProductName; confirmar ruta con runtime Windows antes del cutover.
- Conservar inicialmente nombre logico, schema, IDs, nulabilidad, UTC y settings.
- No editar `app_database.g.dart` ni incrementar schemaVersion para mover la base.
- No leer o registrar credenciales, contenido privado ni filas reales en docs.
- Si el origen tiene WAL, usar un mecanismo consistente y validar integridad y
  conteos con la aplicacion legacy cerrada.

### Contrato SQLite tras DB-01 y DB-02

- `LegacyDatabaseMigrator` recibe archivos origen y destino explicitos; no
  resuelve rutas del usuario ni se ejecuta automaticamente.
- Abre el origen sin migraciones Drift y con locking exclusivo; una conexion
  legacy abierta produce `sourceInUse`.
- Exige WAL, `user_version = 2`, las diez tablas conocidas, `quick_check` y
  `foreign_key_check` limpios.
- Genera un snapshot mediante `VACUUM INTO` dentro de un staging del mismo
  filesystem, valida conteos y equivalencia exacta de filas y activa mediante
  rename.
- El snapshot se marca `NHUB` antes de activarlo. En reinicios posteriores, un
  destino marcado se valida estructuralmente y devuelve `alreadyMigrated` sin
  compararlo otra vez contra el rollback legacy, por lo que conserva escrituras
  legitimas de Nini Hub. Un destino distinto, invalido o marcado por otra
  aplicacion no se sobrescribe.
- Una base fresca se marca al abrirla. Un destino sin marca solo se adopta por
  el contrato historico de primera migracion; un `application_id` ajeno falla
  cerrado. No cambia schemaVersion, tablas ni contenido de filas.
- Evidencia focalizada:
  `test/core/database/legacy_database_migrator_test.dart` con datos sinteticos y
  WAL retenido, y `test/core/database/database_bootstrap_test.dart` para rutas
  Linux/Windows, apertura explicita, conflicto, locking e idempotencia.
- `DatabaseBootstrap` obtiene el soporte Nini Hub con
  `getApplicationSupportDirectory`, deriva el legacy Linux como directorio
  hermano `com.nini.multi_cli_ai` y el Windows como `com.nini/MultiCLI AI`, y
  ejecuta el migrador antes de construir `AppDatabase`.
- La ejecucion Linux real conservo el origen como rollback SQLite valido. Al
  abrirlo de forma exclusiva, SQLite aplico el WAL pendiente al archivo
  principal y retiro el sidecar WAL; por ello el rollback conserva contenido,
  schema e integridad, no identidad byte a byte del conjunto previo.
- Evidencia real agregada: schema 2; `app_settings=26`, `cli_profiles=18`,
  `command_logs=907`, `cost_shares=0`, `daily_usage_buckets=18646`,
  `profile_metadatas=17`, `quota_windows=672`,
  `reset_credit_snapshots=722`, `usage_checks=722`, `workspaces=6`.
- `FIX-DB-01` corrigio el falso conflicto del segundo arranque tras escrituras
  legitimas. Antes de reparar la cabecera real se creo el snapshot consistente
  `/home/nini/.local/share/com.nini.hub/multicli_ai.pre-bootstrap-fix-20260824.sqlite`;
  coincide fila por fila en las diez tablas y conserva `application_id = 0`.
  La base activa quedo marcada `NHUB`, integra y con cero errores FK; el rollback
  legacy tambien permanece integro y sin marca.
- Fundamento SQLite: `https://sqlite.org/lang_vacuum.html` y
  `https://sqlite.org/wal.html`.

## Integraciones desktop vigentes

| Integracion | Owner actual | Direccion objetivo |
|---|---|---|
| Descubrimiento de perfiles | `ProfileDiscoveryService` + `NiniAgentsReadClient` | JSON `list/tools`, schema v1/v2 y sincronizacion SQLite sin inspeccionar perfiles |
| Lifecycle de perfiles | `NiniAgentsProfileLifecycle` | JSON `new/rename/delete`, metadata local y reconciliacion parcial por `status` |
| Launch | `NiniAgentsAgentLauncher` + `DesktopWorkspaceRuntime` | Ejecucion Nini Agents con terminal/working directory, titulos y recencia preservados |
| Procesos generales | `ProcessRunner` + `NiniAgentsReadClient` | Mantener ejecutable/args, timeout, redaccion, Activity y validacion JSON v1 |
| Codex Device Auth | `CodexAccountDeviceAuthGateway` | Mantener JSON-RPC dentro de Data y definir si requiere transporte Nini |
| Codex Usage | `CodexUsageProvider` | Mantener proveedor tras puerto y perfil Nini vigente |
| Heartbeat command | `ProcessHeartbeatCommandGateway` | Ejecutar con environment de perfil Nini y politica existente |
| Codex app-server | `providers/codex` y runtime compartido | StdIO limpio, lifecycle y errores tecnicos encapsulados |

## Contrato observado de Nini Agents

Repositorio observado: `/home/nini/IdeaProjects/nini-agents`, HEAD
`ad9630c996486dfb337644580bf76f533038e87d`. El worktree tenia cambios locales al
crear este indice; revalidarlo antes de cualquier delta y nunca revertirlo.
ENG-02A tambien esta aislada en el PR borrador `#1`: base temporal
`validation/eng-02a-base-ad9630c`, delta `a155613`, harness `b7790c9`, tip
test-only `879d461` y CI manual `32744574564`. Estas refs de validacion no
equivalen a publicar `main`.
ENG-02B/C esta versionada en `validation/eng-02b`, commits `c36a229` y
`fc3361f`. Ambos deltas fueron portados al worktree activo de `main` sin cambiar
su HEAD; el wrapper instalado apunta a ese checkout. Esto no equivale a merge
en `origin/main` ni a release publicado.

Fuentes externas principales:

- `docs/json-cli.md`: envelope JSON v1.
- `schema/cli-output.schema.json`: contrato machine-readable.
- `docs/adapter-schema.md`: profiles schema v2.
- `docs/plans/nini-agents-resume.md`: handoff hacia el consumidor Flutter.
- `docs/plans/nini-agents-end-to-end.md`: decisiones y evidencia del motor.
- `nini-agents` y `nini-agents.ps1`: entrypoints Linux/Windows.

Capacidades observadas:

- JSON v1 de consulta para `version`, `list/status`, `tools`, `doctor`, `stats`
  y `template list`.
- ENG-02A agrega `new --json` y `rename --json`; ENG-02B agrega
  `delete --json` con `--confirm <tool>/<profile>` exacto. Las tres mutaciones
  devuelven estados machine-safe y conservan las reglas de perfiles en Nini
  Agents. Delete devuelve solo `{tool,name}` tras exito y usa
  `confirmation_required`, `profile_not_found` u `operation_failed` con
  `not_applied`/`partially_applied` segun el punto de fallo.
- CI ENG-02B `32748238240`: cuatro tests delete Windows exitosos, Bats Ubuntu
  completo, shellcheck/PSScriptAnalyzer e install smoke Windows/Ubuntu verdes,
  Bash changed-line 100 % (9/9). Pester termino 424/442 y macOS repitio el
  parseo Bash 3.2 de la base; ambos son `separate_fix` y no fallos del contrato
  delete.
- ENG-02C agrega `exec <tool>/<profile> -- <args...>` stdout-clean para
  foreground `accountOverlay/fileOverlay`; Bash reemplaza el wrapper por el
  hijo y PowerShell hereda stdio y propaga el exit code.
- Profile summaries con `tool`, `name`, `type`, `schemaVersion` y `sizeBytes`.
- `MULTICLI_HOME` y `~/MultiCliProfiles` permanecen contratos compatibles.
- Schema v2 separa `.profile.json`, `auth/`, `.runtime/` y estado compartido.
- El shim `multi-cli` es temporal.

Contrato consumido por Nini Hub tras PRF-01, RUN-01, CDX-01 y OPS-01:

- `NiniAgentsReadClient` invoca directamente `nini-agents --json` con
  ejecutable y argumentos separados; no usa el shim `multi-cli`.
- Expone `version`, `list`, `status`, `tools` y las mutaciones
  `new`/`rename`/`delete`. Delete siempre envia `--confirm` con el target exacto.
  No existe ni se inventa un comando `capabilities`: `tools` es el inventario
  publico de capacidades.
- Valida schema del envelope, comando, consistencia `ok/data/error`, exit code,
  stderr limpio, conteos, orden, summaries schema v1/v2 y errores snake-case.
- Un `MULTICLI_HOME` explicito se propaga a discovery, status y mutaciones; el
  cliente no lee filesystem, credenciales, rutas internas ni contenido de
  perfiles.
- `ProfileDiscoveryService` deriva solo las rutas que exige el schema SQLite y
  sincroniza summaries schema 1/2, incluidos perfiles `isolated`. Conserva IDs,
  alias, favoritos, fechas y el indicador local de auth existente.
- `NiniAgentsProfileLifecycle` reemplaza `MultiCliProfileLifecycle` y
  `NiniAgentsAgentLauncher` reemplaza `MultiCliAgentLauncher`; el gateway
  `MultiCliGateway` fue retirado del producto.
- Launch administrado usa `nini-agents launch <tool>/<profile> -- <args>` sin
  parsear stdout interactivo. Conserva `MULTICLI_HOME`, working directory,
  terminales Linux/Windows, protocolo Hyper, titulo y recencia SQLite en UTC.
- App-server, Usage y Heartbeat administrados usan
  `nini-agents exec codex/<profile> -- <args...>`; el perfil principal conserva
  el ejecutable Codex nativo con `CODEX_HOME`.
- `ProcessRunner` reconoce wrappers de `PATHEXT` en Windows y permite propagar
  environment explicito a la terminal sin registrar su contenido.
- Rechazos `not_applied` se traducen a fallos tipados. Un estado
  `partially_applied` o transporte indeterminado consulta `status`, reconcilia
  SQLite y hace que Presentation refresque antes de informar el resultado.
- Evidencia Data local:
  `test/core/process/nini_agents_read_client_test.dart`,
  `test/features/profiles/data/profile_discovery_service_test.dart` y
  `test/features/profiles/data/nini_agents_profile_lifecycle_test.dart`, con
  doubles de proceso y payloads Linux/Windows sinteticos; RUN-01 agrega
  `test/core/process/process_runner_test.dart` y las pruebas Data de Workspaces
  para runtime desktop y launcher.

Brechas que no deben presentarse como resueltas:

- Publicacion del motor: `new`/`rename`/`delete` y `exec` estan versionados en la
  rama temporal y activos mediante el checkout local instalado, pero no fueron
  fusionados a `origin/main` ni publicados como release. Esa distribucion
  pertenece a `CUT-01`.
- Suite global del motor: permanecen 18 fallos Pester de la base. Los tests
  focales de ENG-02A/ENG-02B pasaron; cualquier diagnostico o fix sigue siendo
  un alcance separado.
- Incidente de base macOS: Bash 3.2 no parsea `lib/migration.sh:195`, linea de
  `ad9630c` fuera del delta ENG-02A; no esta diagnosticado/corregido.
- Mutaciones machine-safe distintas de `new`, `rename` y `delete`.
- `doctor --deep` JSON.
- Dispatch publico completo de movimiento.
- Ejecucion stdout-clean para `codex app-server --stdio`.
- Contrato de errores/cancelacion suficiente para todos los flujos Nini Hub.

Los puntos Motor deben congelar y validar estas capacidades en el repositorio
del motor mediante alcance separado.

## Scripts personales e instalacion

`scripts_personales/` esta ignorado por `.gitignore`; sus archivos no forman
parte del historial Git:

- `scripts_personales/compilar_multicli_ai.sh`
- `scripts_personales/compilar_e_instalar_multicli_ai.sh`
- `scripts_personales/compilar_nini_hub.sh`
- `scripts_personales/compilar_e_instalar_nini_hub.sh`

Las dos variantes legacy permanecen byte por byte como rollback. Las variantes
Nini Hub conservan el mismo flujo de build, staging, backup, activacion y
launcher con binario `nini_hub`, instalacion en `.local/opt/nini-hub` y desktop
entry `com.nini.hub`. Los cuatro archivos tienen modo `775` y permanecen
ignorados por Git. No versionarlos, publicarlos o ejecutarlos sin autorizacion
expresa.

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
