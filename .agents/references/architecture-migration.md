# Bitácora de migración arquitectónica

## Autoridad y uso

Este archivo es el relevo operativo canónico de la migración legacy. Debe permitir
continuar sin reconstruir el historial de sesiones.

Orden de autoridad:

~~~text
AGENTS.md
  -> autorización, plataforma y reglas globales
.agents/references/architecture.md
  -> arquitectura objetivo e invariantes
.agents/skills/multi-cli-ai-migrate-architecture/SKILL.md
  -> proceso incremental
esta bitácora
  -> estado, decisiones, evidencia y relevo vigente
~~~

La bitácora no autoriza cambios. Antes de modificar, cada delta debe informar
objetivo, reglas, archivos, capas, contratos, persistencia o integraciones,
exclusiones y validación, y esperar aprobación explícita.

Estados válidos: pending, investigating, awaiting_approval, approved, in_progress,
validating, complete y blocked.

Reglas de mantenimiento:

- Mantener una sola fracción activa.
- Registrar rutas, símbolos, contratos y evidencia; no narración de sesión.
- Diferenciar observed, inferred, suspected, decided, preserve y separate_fix.
- Sustituir información superada en vez de acumularla.
- No marcar complete con validaciones pendientes o evidencia estática cuando se
  necesita runtime.
- Revalidar si branch, HEAD o worktree cambian.
- Conservar cambios concurrentes; no borrar, revertir, stagear ni commitear sin
  instrucción expresa.

## Snapshot vigente

- Actualización y HEAD: 2026-08-23, main / 7426e98.
- Plataforma: Flutter Desktop Linux y Windows.
- Estado: 44 de 45 puertas completas (97,8 %); GOV-02 complete.
- Runtime Heartbeat: owner nuevo conectado de extremo a extremo con una única
  instancia DartHeartbeatScheduler.
- RET-02 retiró Heartbeat legacy, servicios Usage/Settings puente y la fachada
  DashboardController; el Heartbeat nuevo conserva un scheduler único.
- Device Auth pertenece a Accounts y comparte un CodexClientRuntime explícito
  con Usage y Settings; los servicios legacy de Usage/Settings fueron retirados.
- Startup usa composición focalizada; navegación vive en DashboardShell y el
  fallback de workspace permanece detrás de MultiCliGateway.
- Sin fracción activa; la única puerta pendiente es WS-06B, bloqueada hasta
  disponer de evidencia runtime Windows.
- Restricción externa: no hay runtime Windows. WS-06B continúa bloqueada.
- Grafo: última indexación tras SET-02, 1.322 nodos y 3.963 relaciones; índice
  desactualizado porque la herramienta dejó de estar disponible.
- Worktree: migración y cambios concurrentes App/UI; no asumir propiedad.

Pendiente fijo: WS-06B.

## Arquitectura e invariantes

~~~text
presentation -> application -> domain
data --------------------------> domain
app -> composición de implementaciones concretas
~~~

- Domain es Dart puro: sin Flutter, Riverpod, Drift, dart:io, plugins ni clientes.
- Application coordina casos de uso mediante puertos de Domain.
- Data implementa puertos, mapea filas y encapsula SQLite, filesystem, procesos,
  terminales, Multi CLI y Codex.
- Presentation usa Application y modelos visibles de Domain; no importa Data,
  Drift, filesystem, procesos ni gateways concretos.
- App es composition root, shell, tema y navegación; no contiene reglas.
- core/database es infraestructura Data compartida durante la transición; sólo
  Data y App pueden importarla.
- Conservar SQLite, schema, upgrade, IDs, nulabilidad, dinero, UTC, perfiles,
  rutas y settings existentes salvo autorización funcional explícita.
- No editar app_database.g.dart manualmente.
- Linux y Windows son plataformas de primera clase.
- No mezclar migración, fix, optimización, rediseño, dependencia o cambio de
  esquema no enumerados.
- Evitar N+1, tablas completas para contar, filtros amplios en memoria, reload
  global y respuestas asíncronas obsoletas.

## Roadmap fijo

La unidad porcentual es la puerta de esta tabla. Las subdivisiones A/B/C no
agregan puertas; completan la puerta padre.

| Grupo | Fracciones | Estado | Puerta de salida |
|---|---|---|---|
| Gobernanza | GOV-01 relevo; GOV-02 baseline imports | complete | Continuidad y guard con excepciones explícitas |
| Workspaces | WS-01, 02A, 02B, 03, 04A, 04B, 05, 06A, 06B | hasta 06A complete; 06B pending | Evidencia runtime Windows |
| Settings | SET-01, 02, 03, 04A, 04B, 04C, 05 | complete | Startup, save y discovery equivalentes |
| Profiles | PRF-01 a PRF-05 | complete | CRUD propio y Multi CLI tras puertos |
| Accounts | ACC-01 a ACC-05 | complete | Modelos propios, proyección acotada y legacy retirado |
| Activity | ACT-01 a ACT-04 | complete | CommandLog no cruza Data; historial y clear focalizados |
| Usage | USG-01 a USG-05 | complete | Refresh sin reload global y fallbacks preservados |
| Heartbeat | HBT-01 a HBT-05 | complete | Scheduler, retries, datos, UI y composición propios |
| Retiro | RET-01 a RET-03 | complete | Sin consumidores ni imports legacy |

Conteo: Gobernanza 2 + Workspaces 9 + Settings 7 + Profiles 5 +
Accounts 5 + Activity 4 + Usage 5 + Heartbeat 5 + Retiro 3 = 45.

## Owners cerrados

### Workspaces — complete salvo WS-06B

- Domain/Application/Data/Presentation/App propios; salió de DashboardController.
- Conserva historial global, selección, recencia y orden launcher antes de
  bookkeeping.
- pathKey normaliza casing en Windows; el filtro puede ocultar la selección sin
  alterarla.
- Se eliminaron N+1 y recargas globales del flujo migrado.
- Pendiente exclusivo: evidencia runtime Windows:

~~~text
flutter test test/features/workspaces/data/drift_workspace_repository_test.dart --plain-name "deduplicates workspace path casing on Windows"
~~~

### Settings — complete

- AppPreferences conserva nueve settings y SettingsRepository/SettingsRuntime
  encapsulan persistencia y efectos.
- Load: repository -> keep-alive -> timeout.
- Save: normalizar -> keep-alive -> nueve writes -> timeout ->
  discovery/accounts -> scheduler.
- Startup bloqueante con retry y fallo parcial tipado si persistió antes de que
  fallara un efecto.
- Discovery compartido se serializa FIFO.
- Riesgos separados: keep-alive se aplica antes del write; nueve writes no son
  atómicos; controles pueden editarse durante save; valores almacenados inválidos
  tienen fallback legacy.

### Profiles — complete

- Discovery y lifecycle son propios; create/rename/delete usan Multi CLI antes
  de SQLite y no simulan rollback externo.
- Identidad se conserva primero por path y luego por toolKey, profileName y
  profileSource; alias, favorito y timestamps históricos se preservan.
- Create aplica alias desde Application; Profile queda separado de AgentProfile.
- Fallos posteriores al efecto usan ProfileMutationAppliedFailure.

### Accounts — complete

- Account usa Profile puro; AccountCardData, carga N+1 y escritura legacy fueron
  retirados.
- Selección máxima de siete cuentas, checks acotados y actualización de display
  antes de details.
- Un fallo posterior al primer write queda tipado como aplicación parcial.
- Accounts posee Device Auth de extremo a extremo: sesión/puerto de dominio,
  casos de uso, adapters Data, controller y diálogo sin cliente Codex concreto.

### Activity — complete

- Owner Domain/Application/Data/Presentation/App; historial limitado a 250
  registros, statuses conocidos y unknown, redacción y clear total focalizado.
- Filas Drift no salen de Data y no hay reload global ordinario.

### Usage — complete

- Owner Domain/Application/Data/Presentation/App; refresh: proveedor -> snapshot
  SQLite atómico -> Activity -> KeepAlive -> Activity/calendario -> Accounts.
- Calendario usa una consulta SQL acotada; controller correlaciona operaciones y
  el coordinador preserva orden transversal.
- Riesgo separado: el email histórico puede ser no determinista.

## Heartbeat: contrato activo

### Baseline HBT-01 — complete

- Settings habilita y monitorea perfiles Codex disponibles y vinculados.
- Usage agenda después de proveedor, transacción y Activity.
- Flujo manual: confirmación -> rescan -> run -> refresh Usage -> recargar
  Activity/calendario -> Accounts.
- Operaciones externas usan FIFO global; la admisión de probes tiene FIFO
  independiente y su ejecución entra después al FIFO de operaciones.
- Duplicados del mismo perfil se rechazan; perfiles distintos pueden esperar en
  la cola.
- Disable cancela timers y pendientes, pero no interrumpe una operación ya
  iniciada.
- Política: ventana 10.080 ± 60 minutos, preferencia limitId codex, umbral 1 %,
  espera ambigua 45 s, reset más 30 s, dos probes con tolerancia 2 s y backoff
  15 min / 1 h / 6 h.
- Persistencia: key codex_weekly_keep_alive_state_<profileId>, JSON v2, UTC, sin
  cambio de schema.
- Proceso: ejecutable y argumentos separados, environment del perfil, timeout
  90 s; quota probe 30 s; logs redactados.
- Correcciones modeladas en el owner nuevo: usar perfil vigente post-rescan,
  ligar verifiedResetAt a identidad y no escribir después de disable.

### HBT-02 Domain/Application — complete

- Archivos bajo lib/features/heartbeat/domain y application.
- HeartbeatPolicy concentra ventanas, tolerancias, backoff y decisiones puras.
- Puertos reales: perfiles, estado, historial, command, quota, activity, clock,
  delay y scheduler.
- Casos de uso: RunHeartbeat, ProbeHeartbeat y monitoreo.
- Resultados y fallos son tipados; perfiles ausentes, no Codex o no disponibles
  no se traducen desde excepciones técnicas en Presentation.
- El owner puro permanece sin Flutter, Drift, dart:io ni clientes.

### HBT-03 Data — complete

Persistencia e historial:

- heartbeat_state_mapper.dart conserva JSON v2, status legacy y UTC; JSON ausente,
  inválido o futuro cae a estado seguro unknown/default.
- drift_heartbeat_repository.dart conserva AppSettings y resuelve el historial
  con un único SELECT: limita primero a veinte UsageChecks previos, filtra ventana
  semanal, prioriza codex y devuelve máximo una observación.
- El owner nuevo elimina el patrón de hasta 21 selects; el servicio legacy que
  conservaba ese patrón fue retirado físicamente en RET-02A.

Integraciones:

- process_heartbeat_command_gateway.dart ejecuta codex exec con flags seguros,
  argumentos separados, environment por perfil, timeout y redacción.
- codex_heartbeat_quota_probe.dart encapsula el probe Codex de 30 segundos.
- process_heartbeat_activity_recorder.dart registra Activity focalizada y
  redactada.
- dart_heartbeat_runtime.dart implementa clock y delay.
- dart_heartbeat_scheduler.dart mantiene timers, retención, probes iniciales,
  leases por perfil y colas FIFO independientes.
- enqueueOperation<T>() es el punto obligatorio para serializar en HBT-05 las
  operaciones externas compuestas desde App.
- Disable vacía timers/pendientes; una operación in-flight termina, pero los casos
  de uso revalidan habilitación antes de persistir o reagendar.
- Pruebas sólo con dobles/SQLite memory: no se ejecutó Codex real, app-server,
  perfil real, credencial, red ni comando externo.

### HBT-04 Presentation — complete

Archivos:

- lib/features/heartbeat/presentation/state/heartbeat_state.dart
- lib/features/heartbeat/presentation/controllers/heartbeat_controller.dart
- test/features/heartbeat/presentation/heartbeat_controller_test.dart

Contrato:

- HeartbeatPresentationState mantiene colecciones inmutables por profileId:
  running, último resultado y último fallo visible.
- HeartbeatController rechaza doble run del mismo perfil y permite estado
  concurrente para perfiles distintos. HBT-05 serializa la operación concreta
  mediante DartHeartbeatScheduler.enqueueOperation().
- Forward de expectedWindowMinutes; verified/unverified finalizan con éxito;
  failed/skipped conservan resultado y fallo visible.
- Retry limpia sólo el fallo del perfil objetivo.
- Fallos tipados se traducen a español; la causa original queda disponible.
- Una respuesta tardía después de dispose no modifica estado.
- Usa Riverpod, Application y Domain; no importa Data, App, procesos ni database.
- HBT-05 lo conectó sin agregar dependencias de Data o App a Presentation.

Evidencia HBT-04:

- dart format sobre los tres archivos: limpio.
- flutter analyze focalizado: sin issues.
- 5 pruebas nuevas del controller: exitosas.
- Gate Heartbeat + servicio legacy + Settings: 56 pruebas exitosas.
- Sin build, runtime Windows, Codex real, app-server, credenciales o red.

## Decisiones y riesgos vigentes

- preserve: un efecto externo o write ya aplicado no se revierte por un fallo
  posterior; se devuelve fallo parcial tipado.
- decided: discovery compartido permanece FIFO y relee el root al iniciar cada
  llamada; no coalescer.
- decided: fechas persistidas y límites de integración permanecen en UTC.
- decided: Presentation no conoce filas Drift ni adaptadores concretos.
- decided: Usage conserva el orden transversal documentado; no moverlo a un
  controller ni reintroducir reload global.
- decided: el controller HBT-04 modela concurrencia visual por perfil; la FIFO
  real pertenece al scheduler concreto compuesto en App.
- decided: nunca deben quedar dos schedulers Heartbeat productivos.
- decided: JSON v2 y la key por perfil deben seguir legibles durante activación y
  retiro.
- separate_fix USG: el batch Usage puede completar con sincronización visible
  parcial; requiere un fix funcional propio.
- separate_fix ACT: los writes de Activity no son reactivos y el filtro de error
  excluye timeout; requiere un fix funcional propio.
- separate_fix PRF-WIN: `HOME` precede a `USERPROFILE` en Windows; validar y
  corregir la regla de plataforma en un alcance propio.
- separate_fix PRF-DELETE: el texto de borrado no coincide con la ausencia de FK
  de `CommandLogs`; decidir producto y persistencia antes de modificarlo.
- separate_fix UI: `DashboardShell` conserva un overflow de marca de 25 px ya
  caracterizado; requiere un fix Presentation propio.
- blocked_pending_decision: WS-06B requiere runtime Windows.
- decided: Device Auth conserva Activity antes de RPC; al completar ejecuta
  discovery, monitor, refresh Usage sin keepAlive, sincronización visible y
  recarga Accounts. Un rechazo omite refresh/sync/Accounts.
- decided: CodexClientRuntime es la única referencia mutable compartida por
  Device Auth, Usage y el timeout de Settings; el cliente/sesión concretos quedan
  en Data.
- decided: appStartupProvider conserva discovery -> Activity -> calendario ->
  monitor Heartbeat -> Accounts; discovery/Activity/calendario bloquean startup
  y Accounts mantiene su fallo local. La navegación pertenece al shell.
- observed: el índice de arquitectura está desactualizado; RET-03 se corroboró
  mediante búsquedas locales y GOV-02 no depende de ese índice: recorre las
  fuentes actuales en cada ejecución.

## HBT-05 Composición y activación — complete

- App compone repository, adapters, casos de uso, controller y una única
  DartHeartbeatScheduler; manual, observación Usage y probes programados
  comparten su FIFO de operaciones.
- UsageKeepAliveScheduler conserva su contrato bool síncrono mediante un bridge
  que encola trabajo detached; rechaza duplicados y registra fallos sanitizados
  sin futuros no manejados.
- Settings controla enable; appStartupProvider monitorea perfiles elegibles tras
  discovery y todos los caminos usan el scheduler nuevo.
- Accounts usa HeartbeatController. Tras verified/unverified refresca Usage y,
  mediante el coordinador, Activity, calendario y Accounts; failed/skipped no
  disparan recargas posteriores.
- DashboardShell incorpora loading global, conteo por perfil y bloqueo de refresh
  global durante Heartbeat.
- Persistencia conserva key y JSON v2; no hubo schema, migración, dependencia ni
  archivo generado.

Evidencia HBT-05:

- dart format sobre los trece archivos Dart tocados: limpio.
- flutter analyze focalizado sobre producción y pruebas: sin issues.
- Gate Heartbeat + Usage Application/coordinator + Settings + Accounts: 73
  pruebas exitosas.
- Pruebas de composición usan SQLite memory y overrides; no ejecutaron Codex,
  app-server, perfil real, credenciales, red, build ni runtime Windows.

## RET-01 a RET-03 Retiro de puentes legacy — complete

- RET-01 inventarió consumidores y congeló el orden A/B/C: Heartbeat muerto,
  Device Auth/cliente Codex/runtime Settings y fachada Dashboard.
- RET-02A eliminó CodexWeeklyKeepAliveService, LegacyUsageKeepAliveScheduler,
  Dashboard.startCodexHeartbeat y el mapper inverso exclusivo del adapter.
- RET-02B trasladó Device Auth a Accounts, introdujo CodexClientRuntime y
  DesktopSettingsRuntime, y retiró UsageRefreshService/LegacySettingsRuntime.
- RET-02C reemplazó DashboardController por appStartupProvider, navegación local
  en DashboardShell y workspaceFallbackDirectoryProvider. Retiró campos/métodos
  muertos y la caracterización Accounts que contradecía la composición vigente.
- RET-03 integró `ProfileDiscovery` directamente en ProfileDiscoveryService y
  retiró LegacyProfileDiscovery. Movió DTO técnicos Codex fuera de Accounts
  Domain, hizo privado el modelo de discovery y eliminó account_models.dart.
- Startup conserva Settings gate y discovery -> Activity -> calendario ->
  monitor -> Accounts. El home se resuelve perezosamente por MultiCliGateway;
  no se agregaron recargas globales ni queries por fila y se preservó el filtro
  acotado de perfiles Heartbeat elegibles en composición.
- Sin cambios de schema, migraciones, JSON v2, dependencias, UI, procesos,
  plataforma, archivos generados o contratos Domain/Application.

Auditoría RET-03: Domain/Application no importan Data, Presentation, App,
Flutter, Drift ni dart:io; Presentation no importa Data, Drift ni dart:io; no
quedan símbolos o imports productivos llamados `legacy`. GOV-02 controla la
baseline existente de cinco imports Presentation -> App:

- calendar_view.dart, accounts_view.dart y activity_view.dart importan
  app/providers.dart.
- dashboard_shell.dart importa app/app_startup.dart y app/providers.dart.

Evidencia compacta: RET-01 inventario estático; RET-02A 69 pruebas; RET-02B 68;
RET-02C 45; RET-03 52 pruebas focalizadas. Todos los cortes tuvieron
format/analyze limpios y usaron dobles/SQLite memory, sin Codex/CODEX_HOME,
credenciales, red, build ni runtime Windows.

## GOV-02 Guard automático de imports — complete

- `test/architecture/import_boundaries_test.dart` recorre las directivas
  `import` y `export` de `lib/features`, incluidas rutas `package:` y relativas.
- El guard aplica las direcciones Domain/Application/Data/Presentation y bloquea
  dependencias de tecnología o infraestructura prohibidas por capa.
- La baseline estricta enumera los cinco imports Presentation -> App existentes:
  cualquier alta o entrada obsoleta falla y requiere una decisión explícita.
- Se ejecuta dentro del `flutter test` ya documentado; no agregó dependencias,
  scripts, configuración CI ni cambios productivos.
- `dart format` sobre el test: limpio; `flutter analyze` focalizado: sin issues;
  una prueba focalizada sobre el árbol productivo: exitosa;
  `git diff --check`: limpio.
- Sin build, schema, migración, SQLite, proceso externo, red, Codex real ni
  runtime Windows.

## Retiro y cierre global

- RET-01 a RET-03: complete; no quedan consumidores de DashboardController,
  servicios legacy retirados ni símbolos/imports productivos llamados `legacy`.
- GOV-02: complete; el guard automático mantiene la baseline explícita sin
  aceptar regresiones silenciosas.
- La migración completa requiere únicamente WS-06B, que sigue bloqueada por la
  ausencia de runtime Windows.

## Formato canónico de cierre

~~~text
Estado global y HEAD observado:
Fracción y estado:
Objetivo funcional:
Skills consumidas:
Archivos ejecutados:
Antes y después:
Contratos y orden de efectos:
Persistencia e integraciones:
Concurrencia, lifecycle y plataforma:
Validación ejecutada y resultado:
Validación no ejecutada:
Desviaciones y riesgos:
Siguiente fracción candidata y autorización:
~~~
