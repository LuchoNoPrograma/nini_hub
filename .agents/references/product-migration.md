# Bitacora de migracion de Nini Hub

## Autoridad y continuidad

Esta es la bitacora operativa canonica para transformar el source heredado de
MultiCLI AI en Nini Hub. Debe permitir que otro LLM continue sin reconstruir
conversaciones ni asumir que el legado ya fue retirado.

Orden de autoridad:

```text
AGENTS.md
  -> autorizacion y reglas globales
.agents/references/architecture.md
  -> limites e invariantes
.agents/references/project-index.md
  -> owners, rutas y contratos ancla
.agents/skills/nini-hub-migrate-product/SKILL.md
  -> proceso por fracciones
esta bitacora
  -> estado, decisiones, evidencia y siguiente accion
```

La bitacora no autoriza cambios. Cada delta debe declarar objetivo, reglas,
archivos, capas, contratos, persistencia o integraciones, exclusiones y
validacion, y esperar aprobacion explicita.

Estados: `pending`, `investigating`, `awaiting_approval`, `approved`,
`in_progress`, `validating`, `complete`, `blocked`.

Etiquetas de evidencia: `observed`, `inferred`, `decided`, `preserve`,
`separate_fix`, `blocked_pending_decision`.

## Inicio en cero

- Baseline inicial: 2026-08-24, `0/14` puntos.
- El historial Git previo se conserva como linaje, pero ningun punto `complete`
  de la bitacora MultiCLI AI se importa como avance de Nini Hub.
- La arquitectura heredada y sus pruebas son evidencia de partida.
- La gobernanza, identidad, datos, motor, validacion y cutover de Nini Hub deben
  obtener evidencia propia.

## Snapshot vigente

- Fecha: 2026-08-24.
- Repo: `/home/nini/StudioProjects/nini_hub`.
- Branch y HEAD heredado: `main` /
  `5d378f24f49dc2d4594afbbf487890e463abc88d`.
- Git: `.git` independiente; `origin` apunta al repositorio nuevo
  `https://github.com/LuchoNoPrograma/nini_hub.git`, nunca al remoto legacy.
- Source legacy protegido: `/home/nini/StudioProjects/multi_cli_ai`, limpio en el
  mismo HEAD y con su `origin` original.
- Motor externo observado: `/home/nini/IdeaProjects/nini-agents`, HEAD
  `ad9630c996486dfb337644580bf76f533038e87d`, branch `main` ahead 1 y worktree
  con cambios locales. No asumir propiedad ni revertirlos.
- Validacion aislada ENG-02A: PR borrador `#1`, base temporal
  `validation/eng-02a-base-ad9630c`, delta `a155613`, harness `b7790c9`, tip
  test-only `879d461` y CI manual `32744574564`. Estas refs no modifican
  `origin/main` ni publican el HEAD local.
- Validacion aislada ENG-02B: branch temporal `validation/eng-02b`, commit
  `c36a229` y CI manual `32748238240`; tampoco modifica `main`, instala ni
  publica release.
- ENG-02C versionado: el worktree temporal
  `/tmp/nini-agents-eng02a.DALtct/repo`, branch `validation/eng-02b`, avanzo a
  `fc3361f`. ENG-02B/C tambien fue portado manualmente al worktree concurrente
  de `main` sin cambiar su HEAD, stagear ni borrar otros cambios.
- Activacion local del motor: `/home/nini/.local/bin/nini-agents` ya delegaba al
  checkout principal, por lo que el comando instalado expone `exec` sin
  reescribir el installer. `origin/main` y releases publicados no cambiaron.
- Activacion local de Nini Hub: release instalado en
  `/home/nini/.local/opt/nini-hub`, symlink `~/.local/bin/nini_hub` y launchers
  de escritorio/menu activos. `FIX-DB-01` reparo el falso conflicto de segundo
  arranque; la aplicacion usa la SQLite real marcada y queda abierta en Linux.
- Estado global: `12/14`; bloques Base, Identidad, Datos, Motor, Perfiles y
  Operacion completos. Solo quedan los dos puntos de Cierre.
- Fraccion activa: `QA-01`, `validating`. QA-01A completo la evidencia Linux;
  el runtime Windows real permanece como unica puerta de plataforma pendiente.
- Aprobacion: usuario autorizo el bootstrap historico `GOV-00`, que cubrio
  conjuntamente `REP-01` y `GOV-01`; tambien autorizo `ID-01`, `SCR-01`,
  `DB-01`, `DB-02`, el alcance Nini Hub de `ENG-01`, ENG-02A en el motor externo
  y la correccion focal de `remove_shortcut()` el 2026-08-24. La autorizacion
  posterior cubrio solo aislar ENG-02A, crear refs temporales/PR borrador,
  ejecutar CI y actualizar relevos; `VALID-ENG-02A-B/C` autorizo la harness
  exacta, una prueba in-process y esos relevos. ENG-02B autorizo delete JSON,
  pruebas/schema/documentacion, una branch/commit temporal, un unico CI y estos
  relevos; excluyo fixes de base, Flutter/SQLite, merge, release e instalacion.
  `PRF-01` autorizo el adapter Nini Hub de discovery y CRUD, reconciliacion
  parcial, composicion, fallos tipados, pruebas y relevos; excluyo launch,
  Device Auth, schema SQLite, motor externo, builds y Git. `RUN-01` autorizo el
  launcher Nini Agents, runtime desktop, terminal/environment, composicion,
  pruebas y relevos; excluyo el motor externo, Device Auth, app-server, schema,
  builds, perfiles reales y Git. `ENG-02C` autorizo exclusivamente el comando
  exec stdout-clean en el worktree aislado del motor, paridad Bash/PowerShell,
  pruebas sinteticas, contrato, README y bitacoras; excluyo Nini Hub productivo,
  SQLite, adapters/schema, datos reales, instalacion, Git e integracion.
  `CDX-01A` autorizo el transporte app-server de perfiles Codex default y
  gestionados, lifecycle de proceso, fallos tipados, migracion de Usage,
  Heartbeat y Device Auth al perfil completo, pruebas focalizadas y relevo;
  excluyo UI, SQLite, `hasAuthFile`, motor externo, perfiles/credenciales reales,
  builds, instalacion y Git. `CDX-01B` autorizo el puerto estrecho de Accounts,
  escritura focalizada de `hasAuthFile`, orden de efectos, composicion, snapshot
  visible, pruebas y relevo; excluyo schema, generated, OPS-01, motor externo,
  datos reales, builds, instalacion y Git. `OPS-01` autorizo el lanzamiento de
  Heartbeat administrado mediante `nini-agents exec`, la conservacion del
  perfil default nativo, la terminacion del arbol supervisado en timeout
  Windows, pruebas dirigidas y este relevo; excluyo schema, UI, motor externo,
  Activity reactiva, fixes legacy separados, datos reales, builds, instalacion
  y Git. El cierre posterior de `ENG-02` autorizo portar ENG-02B/C al checkout
  principal preservando sus cambios concurrentes, crear solo el commit aislado
  `fc3361f`, validar contratos/smokes sinteticos y actualizar relevos; excluyo
  branch nueva, installer, perfiles reales, builds, merge, push, tag y release.
  `QA-01A` autorizo analyze, matriz Flutter dirigida, consultas JSON instaladas,
  arranque debug Linux con roots temporales y actualizacion de indice/bitacora;
  excluyo fixes, datos reales, runtime Windows, installer, release y Git.
  `ACT-01` autorizo el build release/instalacion mediante los scripts personales
  existentes, apertura con SQLite/perfiles reales, discovery, actualización
  inicial de Usage/Heartbeat y este relevo; excluyo mutaciones de perfiles,
  acceso directo a credenciales, Device Auth, Windows, remoto, Git y retiro del
  producto legacy. `FIX-DB-01` autorizo la propiedad SQLite mediante
  `application_id`, regresiones focalizadas, backup consistente y reparacion de
  cabecera de la base real, build/reinstalacion Linux, lanzamiento instalado y
  actualizacion de relevos; excluyo schema, tablas, filas de negocio, generated,
  perfiles/credenciales, Windows, remoto y Git.
- Persistencia: SQLite real schema 2 migrada una vez al soporte Nini Hub y
  marcada con `PRAGMA application_id = 0x4E485542` (`NHUB`). La comparacion
  exacta con legacy queda limitada a la primera migracion; los reinicios validan
  el destino propio sin descartar escrituras legitimas. Nombre logico
  `multicli_ai` y schemaVersion 2 preservados.
- Scripts personales: variantes Nini Hub creadas y validadas; variantes legacy
  conservadas byte por byte; los cuatro archivos siguen ignorados por Git.
- Remoto Nini Hub: configurado como `origin`; el usuario autorizo categorizar,
  commitear y empujar los deltas locales de Accounts, Heartbeat, Usage y
  terminales de esta sesion hacia `origin/master`.

## Roadmap: 14 puntos en siete bloques

| Bloque | Punto | Estado | Puerta de salida |
|---|---|---|---|
| Base | 1. `REP-01` Repo independiente | complete | Historial y HEAD iguales al origen; `.git` distinto; sin remoto heredado; source original intacto |
| Base | 2. `GOV-01` Gobernanza y relevo | complete | `AGENTS.md`, arquitectura, indice, bitacora y 3-6 skills Nini Hub validas; sin skills legacy activas |
| Identidad | 3. `ID-01` Rebranding del producto | complete | Dart, Linux, Windows, assets, README y metadatos usan Nini Hub / `com.nini.hub`; baseline legacy enumerada |
| Identidad | 4. `SCR-01` Scripts personales | complete | Scripts renombrados y ajustados; permisos, staging, backup, launcher e instalacion verificados sin borrar versiones legacy |
| Datos | 5. `DB-01` Contrato y ensayo SQLite | complete | Origen/destino, cierre, WAL, backup, integridad, idempotencia, rollback y fixtures congelados sin tocar datos reales |
| Datos | 6. `DB-02` Migracion unica SQLite | complete | Contenido schema v2 transferido una vez al directorio Nini Hub, destino protegido y rollback conservado con evidencia |
| Motor | 7. `ENG-01` Contrato JSON de lectura | complete | Tools como inventario de capabilities, version/list/status y errores machine-safe congelados y probados en Bash/PowerShell |
| Motor | 8. `ENG-02` Mutaciones y exec transparente | complete | CRUD seguro y transporte stdout-clean para app-server disponibles y versionados en `nini-agents` |
| Perfiles | 9. `PRF-01` Discovery y lifecycle | complete | Nini Hub descubre schema v1/v2 y crea/renombra/borra mediante Nini Agents conservando metadata y fallos parciales |
| Perfiles | 10. `RUN-01` Launcher y workspaces | complete | Launch, terminal, Hyper/titulos, working directory, recencia y seleccion usan Nini Agents sin `MultiCliAgentLauncher` productivo |
| Operacion | 11. `CDX-01` Codex runtime y Device Auth | complete | App-server stdio, sesion compartida, auth, cancelacion, timeout y errores quedan detras del adapter Nini/Codex correcto |
| Operacion | 12. `OPS-01` Usage, Heartbeat y Activity | complete | Uso, scheduler, logs y sincronizacion focalizada operan con perfiles Nini; gateways Multi CLI productivos retirados |
| Cierre | 13. `QA-01` Equivalencia desktop | validating | Pruebas focalizadas, arquitectura, migracion y smoke Linux verdes; runtime Windows real pendiente |
| Cierre | 14. `CUT-01` Cutover y deprecacion | pending | Nini Hub es unico writer instalado, remoto nuevo publicado con autorizacion, rollback conservado y MultiCLI AI deprecated |

Conteo por bloque: Base 2 + Identidad 2 + Datos 2 + Motor 2 + Perfiles 2 +
Operacion 2 + Cierre 2 = 14.

No cambiar el total para agregar subtareas. Usar subdivisiones A/B/C dentro del
punto correspondiente y completar el punto solo cuando toda su puerta salga.

## Fraccion cerrada: GOV-00 (bootstrap de REP-01 y GOV-01)

`GOV-00` es el nombre historico del corte inicial aprobado, no un punto
adicional del roadmap. Su evidencia cerro conjuntamente `REP-01` y `GOV-01`,
que son los dos identificadores oficiales del bloque Base.

### Objetivo

Crear una repo local Nini Hub independiente y dejar gobernanza/relevo capaces de
continuar la migracion desde cero.

### Alcance aprobado

- Clonar el historial Git desde MultiCLI AI al nuevo root mediante una base Git
  independiente.
- Retirar el remoto heredado solo en Nini Hub.
- Copiar los dos scripts personales ignorados sin cambiar contenido ni permisos.
- Reemplazar la gobernanza heredada dentro de Nini Hub por `AGENTS.md`,
  arquitectura, indice, bitacora y skills `nini-hub-*` nuevas.
- Validar historial, repositorios, scripts, referencias y skills.

### Exclusiones

- Codigo Flutter, `pubspec.yaml`, Linux, Windows, assets y README de producto.
- SQLite real, schema, migraciones, archivos generados o settings.
- Instalaciones, builds, procesos externos, red, perfiles o credenciales.
- Cambios en MultiCLI AI, Nini Agents o Codexporter.
- Stage, commit, push, creacion de remoto o publicacion.

### Evidencia de cierre

- `REP-01`: clone local con objetos independientes; Nini Hub y MultiCLI AI usan
  directorios `.git` distintos y conservan HEAD
  `5d378f24f49dc2d4594afbbf487890e463abc88d`.
- Nini Hub tiene cero remotos; MultiCLI AI conserva
  `https://github.com/LuchoNoPrograma/multi_cli_ai.git` y worktree limpio.
- Los dos scripts personales coinciden por SHA-256 con el origen y conservan
  modo ejecutable `775`.
- `quick_validate.py` valido las seis skills `nini-hub-*`.
- `find .agents/skills -name SKILL.md` devuelve solo las seis skills Nini Hub;
  no quedan skills MultiCLI AI activas.
- Busquedas de nombres de skills legacy, bitacora legacy, TODO y patrones
  basicos de secretos en la gobernanza nueva no encontraron resultados.
- `git diff --check`: limpio.
- No se ejecutaron Flutter, tests de producto, builds, SQLite, procesos externos,
  red, perfiles reales, credenciales, instalacion, stage, commit o push.

### Resultado

- Antes: un solo repositorio MultiCLI AI con gobernanza y relevo 44/45 propios
  del producto legacy; scripts personales fuera del historial.
- Despues: Nini Hub posee repo Git local independiente, conserva todo el
  historial, tiene gobernanza nueva desde `0/14` y mantiene los scripts ignorados
  sin alteracion.
- La repo nueva queda intencionalmente con cambios de gobernanza sin stage ni
  commit; esa operacion requiere instruccion expresa.

## Decisiones congeladas

- `decided`: nombre humano **Nini Hub**.
- `decided`: package target `nini_hub`, executable target `nini_hub` y
  application ID target `com.nini.hub`.
- `decided`: Nini Hub es repo nueva con `.git` y remoto propios, pero conserva
  todos los commits previos como historial.
- `decided`: la repo no se crea mediante el mecanismo GitHub Fork; el remoto
  nuevo sera un repositorio independiente cuando se autorice.
- `decided`: la bitacora comienza en `0/14`, resumida como siete bloques de dos.
- `decided`: las skills comienzan bajo identidad Nini Hub y se anclan al codigo
  vigente; no se copian estados de avance legacy.
- `decided`: `nini-agents` permanece motor; Nini Hub es plano de control desktop.
- `decided`: SQLite se migra una sola vez a un destino nuevo; no se comparte un
  archivo fisico vivo entre aplicaciones.
- `preserve`: schemaVersion 2, nombre logico `multicli_ai`, tablas, IDs,
  nulabilidad, UTC, settings y datos hasta que un delta funcional autorice otra
  cosa.
- `preserve`: `MULTICLI_HOME`, `~/MultiCliProfiles`, perfiles existentes,
  workspaces y comportamiento de terminal aplicable.
- `preserve`: scripts personales permanecen ignorados y no publicados.

## Riesgos y brechas vigentes

- `observed`: la base Linux legacy usa WAL; una copia cruda del `.sqlite` puede
  perder transacciones.
- `observed`: cambiar el application ID cambia el directorio de soporte Linux.
- `inferred`: Windows cambiara su subdirectorio al cambiar ProductName; requiere
  runtime real para confirmar.
- `observed`: Nini Agents JSON v1 cubre consultas y las mutaciones
  `new`/`rename`/`delete` en ramas aisladas. ENG-02B paso sus cuatro tests
  Windows, Bats Ubuntu y Bash changed-line 100 % (9/9); el gate de modulos
  PowerShell permanecio 100 % (3/3) para el modulo JSON de ENG-02A. Pester
  termino 424/442: los mismos 18 fallos de base se conservan como
  `separate_fix`, no como fallos de delete.
- `observed`: ENG-02C agrega `nini-agents exec` para
  `accountOverlay/fileOverlay` foreground. Bash quedo validado con stdout
  limpio, PID transferido y exit code; PowerShell tiene implementacion y tests
  escritos pero no ejecutados. El delta esta en `fc3361f` y activo en el
  checkout local, pero no publicado en `origin/main` o un release.
- `separate_fix`: macOS no pudo parsear `lib/migration.sh:195` con Bash 3.2. La
  linea pertenece a `ad9630c`, fuera del delta ENG-02A, y requiere diagnostico
  y autorizacion propios antes de cualquier correccion.
- `observed`: el worktree de Nini Agents contiene cambios concurrentes; cualquier
  modificacion necesita alcance propio y no puede revertirlos.
- `decided`: PRF-01 conserva `hasAuthFile` ya persistido y no inspecciona
  credenciales. Un perfil nuevo comienza sin auth local confirmada; CDX-01B es
  el unico handoff que marca autenticacion local despues de una confirmacion
  real de Device Auth y antes de discovery, sin leer archivos privados.
- `observed`: QA-01A paso analyze, 223 pruebas dirigidas, contrato instalado y
  smoke debug Linux aislado; SQLite runtime obtuvo integridad `ok` y cero
  violaciones de foreign keys.
- `blocked_pending_decision`: no hay evidencia runtime Windows disponible en
  este workspace para cerrar `QA-01`; la prueba de casing de workspaces quedo
  omitida por plataforma.
- `separate_fix`: la caracterizacion legacy de Usage aun exige un overflow de
  marca de 25 px, pero el render vigente ya no produce esa excepcion; el test
  debe re-caracterizarse en un alcance propio. Los demas riesgos legacy —
  sincronizacion Usage parcial, Activity no reactiva/filtro timeout, `HOME`
  antes de `USERPROFILE` y semantica de borrado — no se corrigen dentro del
  rebranding.

## Reglas de actualizacion

- Mantener una sola fraccion activa.
- Actualizar snapshot y HEAD despues de cada cambio material o relevo.
- Registrar rutas y simbolos, no narracion de conversacion.
- Sustituir informacion superada en lugar de acumular estados contradictorios.
- No marcar `complete` con validacion pendiente o evidencia estatica cuando la
  puerta exige runtime.
- Registrar comandos y resultados compactos; no incluir secretos, perfiles
  reales, contenido de auth, tokens, IDs privados o dumps de SQLite.
- Al cerrar un punto, fijar el siguiente como `awaiting_approval` y delimitarlo
  antes de modificar.

## Fraccion cerrada: ID-01

### Objetivo y resultado

Cambiar la identidad tecnica y visible del source de MultiCLI AI a Nini Hub sin
alterar comportamiento, persistencia ni integraciones legacy. El producto usa
ahora `Nini Hub`, package y ejecutable `nini_hub`, clase `NiniHubApp`,
application ID `com.nini.hub` y metadata Codex `nini-hub` / `Nini Hub`.

### Alcance ejecutado

- Se actualizaron los imports de los 154 archivos Dart consumidores bajo
  `lib/` y `test/` de `package:multi_cli_ai` a `package:nini_hub`.
- `lib/app/multi_cli_ai_app.dart` paso a `lib/app/nini_hub_app.dart`; main,
  startup, dashboard y pruebas visibles usan la identidad nueva.
- `pubspec.yaml`, README y release workflow usan Nini Hub y artefactos
  `Nini-Hub-*`.
- Linux usa binario `nini_hub`, app ID y desktop entry `com.nini.hub`, recurso
  `nini_hub.png` e iconos hicolor nuevos.
- Windows usa proyecto/binario `nini_hub`, producto Nini Hub y ejecutable
  `nini_hub.exe` en CMake, resources y runner.
- Los assets `multicli-ai-*` fueron renombrados a `nini-hub-*` sin cambiar sus
  bytes.

### Contratos preservados y exclusiones

- `AppDatabase` conserva nombre logico `multicli_ai`, schemaVersion 2, tablas y
  ruta de apertura vigente; `app_database.g.dart` y `pubspec.lock` no cambiaron.
- `MultiCliGateway`, `MultiCliProfileLifecycle` y `MultiCliAgentLauncher`
  conservan nombres y conducta hasta los puntos de Motor, Perfiles y Launch.
- Permanecen `MULTICLI_HOME`, `~/MultiCliProfiles` y la descripcion honesta del
  motor legacy en README hasta reemplazarlo con evidencia de `nini-agents`.
- No se tocaron scripts personales, SQLite real, schema/migraciones, contratos
  Nini Agents, perfiles, credenciales, instalaciones, procesos externos ni UI
  funcional.

### Evidencia de cierre

- `flutter pub get --enforce-lockfile`: resolucion exitosa sin cambiar lockfile.
- `dart format` sobre los 154 archivos Dart consumidores: exitoso; solo
  `test/widget_test.dart` requirio ajuste de formato adicional al rebranding.
- `flutter analyze`: sin issues.
- Tests focalizados exitosos: limite de imports, startup de Settings y asset de
  marca de `widget_test.dart` (3 pruebas, 3 aprobadas).
- `desktop-file-validate linux/packaging/com.nini.hub.desktop`: exitoso.
- Guardas estaticas: cero imports `package:multi_cli_ai`; cero identidad de
  producto anterior en los targets de ID-01; assets requeridos presentes; iconos
  renombrados con el mismo SHA-256; `git diff --check` limpio.
- No se ejecutaron builds nativos, instaladores, runtime Linux/Windows, suites
  completas, SQLite, stage, commit, push ni publicacion.

## Fraccion cerrada: SCR-01

### Objetivo y resultado

Conservar los dos scripts personales MultiCLI AI y agregar variantes Nini Hub
capaces de localizar, instalar y exponer el binario renombrado sin modificar ni
publicar el rollback legacy.

### Alcance ejecutado

- Se crearon `scripts_personales/compilar_nini_hub.sh` y
  `scripts_personales/compilar_e_instalar_nini_hub.sh` como variantes adicionales
  ignoradas por Git.
- Build apunta a `release/bundle/nini_hub` y conserva `flutter pub get` seguido
  de `flutter build linux --release --no-pub`.
- Install usa `.local/opt/nini-hub`, backup `nini-hub.previous`, staging
  `.nini-hub.new.*`, enlace `.local/bin/nini_hub`, desktop entry
  `com.nini.hub.desktop` y launcher `Nini Hub.desktop`.
- El launcher usa ejecutable `nini_hub`, icono hicolor `com.nini.hub.png` con
  fallback `data/nini_hub.png` y `StartupWMClass=com.nini.hub`.

### Contratos preservados y exclusiones

- Los scripts MultiCLI AI originales no se modificaron; conservan SHA-256
  `bad43f2c028a4428c6a38c9223dcae09483fea111010c85ec8c6c46e3b6dc5fd` y
  `1049d1903721d5b8e4fdf7e6320f766a1da1f5a71113277e108e3b88030c84a8`.
- Los cuatro scripts conservan modo ejecutable `775`; las variantes nuevas
  mantienen quoting, validaciones, cleanup, backup, activacion y rollback del
  flujo legacy.
- No se ejecutaron los scripts, builds, instalacion, desinstalacion, launchers,
  `gio`, desktop database ni escrituras bajo `$HOME/.local`.
- No se tocaron SQLite, Dart, Linux/Windows versionado, perfiles, credenciales,
  Nini Agents, Git stage/commit/push ni remotos.

### Evidencia de cierre

- `bash -n` sobre ambas variantes Nini Hub: exitoso.
- `desktop-file-validate` sobre el launcher extraido con rutas sinteticas:
  exitoso; `shellcheck` no esta disponible en el entorno.
- Comparacion estructural contra cada script legacy aplicando solo los reemplazos
  de identidad aprobados: sin diferencias adicionales.
- Busqueda en variantes nuevas: cero identidad MultiCLI AI y presencia de todas
  las rutas, binarios, desktop entry, iconos, staging y backup Nini Hub.
- `stat`: modo `775` en los cuatro scripts; `git status --ignored` mantiene
  `scripts_personales/` como ignorado.

## Fraccion cerrada: DB-01

### Objetivo y resultado

Implementar y ensayar con datos sinteticos el contrato de migracion consistente
desde una SQLite legacy cerrada hacia un destino Nini Hub, sin conectarlo al
startup ni tocar datos reales.

### Alcance ejecutado

- Se creo `lib/core/database/legacy_database_migrator.dart` con resultados y
  fallos tipados para migracion, idempotencia, conflicto, origen abierto,
  validacion, activacion y cleanup.
- El origen se abre sin migraciones Drift y con locking exclusivo. Exige WAL,
  `user_version = 2`, las diez tablas vigentes, `quick_check` y
  `foreign_key_check` limpios.
- `VACUUM INTO` genera un snapshot transaccional en staging dentro del mismo
  filesystem. Antes del rename se comparan schema, conteos y filas exactas de
  cada tabla mediante `ATTACH` y `EXCEPT` en ambos sentidos.
- Un destino identico devuelve `alreadyMigrated`; un destino distinto, invalido
  o aparecido durante el proceso nunca se sobrescribe. El origen queda como
  rollback y el staging se limpia.
- Se creo `test/core/database/legacy_database_migrator_test.dart` con fixtures
  temporales que contienen una fila sintetica por tabla y un WAL retenido.

### Contratos preservados y exclusiones

- `app_database.dart`, `app_database.g.dart`, schemaVersion, tablas, `pubspec`,
  lockfile, composition root, startup y rutas productivas no cambiaron.
- No se localizaron, abrieron, copiaron o modificaron bases reales; no hubo
  escrituras bajo `$HOME/.local` ni exposicion de filas, perfiles, rutas privadas
  o credenciales.
- No se ejecutaron app, builds, runtime Windows, MultiCLI AI, Nini Agents,
  stage, commit, push o remotos.

### Evidencia de cierre

- `dart format` sobre migrador y prueba: limpio.
- `flutter analyze` focalizado: sin issues.
- Test dirigido: 7/7 aprobados — WAL confirmado, diez tablas y conteos,
  repeticion idempotente sin cambiar bytes, destino diferente intacto, rutas
  iguales rechazadas, schema incompatible rechazado, origen abierto rechazado y
  cleanup tras interrupcion antes de activacion.
- Guardas: generated, schema, dependencias y lockfile sin cambios de DB-01;
  `git diff --check` limpio.
- Fundamento verificado contra la documentacion oficial de SQLite para WAL,
  locking exclusivo, `VACUUM INTO`, `quick_check` y `user_version`.

## Fraccion cerrada: DB-02

### Objetivo y resultado

Conectar el migrador al arranque antes de Riverpod, migrar una sola vez la
SQLite Linux real al soporte Nini Hub y detener el startup de forma segura ante
locking, validacion o conflicto.

### Alcance ejecutado

- Se creo `lib/core/database/database_bootstrap.dart`. Resuelve el soporte
  vigente con `getApplicationSupportDirectory`, deriva el legacy Linux bajo
  `com.nini.multi_cli_ai` y el Windows bajo el producto hermano `MultiCLI AI`.
- El orden productivo es ruta -> migracion/idempotencia -> apertura explicita de
  `AppDatabase` -> override de `databaseProvider`. El provider ya no crea una
  conexion implicita y Settings no se construye cuando falla el bootstrap.
- `AppStartupFailure` traduce locking, conflicto, base invalida y errores de
  soporte sin exponer causas o rutas privadas. `NiniHubApp` muestra ese fallo
  antes de observar providers de datos.
- Se agrego `test/core/database/database_bootstrap_test.dart`, incluido un caso
  operativo opt-in que requiere el directorio real mediante environment, y se
  amplio la prueba focalizada de startup de Settings.

### Migracion Linux real

- Preflight y repeticion: `multi_cli_ai` y `nini_hub` cerrados, origen regular
  sin handles detectados, destino ausente antes de ejecutar y sin staging
  residual despues.
- Resultado inicial `migrated`; segunda ejecucion `alreadyMigrated`.
- Integridad: schema 2, las diez tablas esperadas, `quick_check` y
  `foreign_key_check` validos, con equivalencia exacta comprobada por el
  migrador. Solo se registraron conteos agregados:
  `app_settings=26`, `cli_profiles=18`, `command_logs=907`, `cost_shares=0`,
  `daily_usage_buckets=18646`, `profile_metadatas=17`, `quota_windows=672`,
  `reset_credit_snapshots=722`, `usage_checks=722`, `workspaces=6`.
- El origen permanece en su ruta como rollback SQLite valido. La apertura
  exclusiva consolido el WAL pendiente en el archivo principal y SQLite retiro
  el sidecar WAL; el contenido, schema e integridad se preservaron, pero el set
  fisico legacy no conserva hashes byte a byte previos.

### Contratos preservados y exclusiones

- Nombre logico `multicli_ai`, schemaVersion 2, tablas, IDs, filas, nulabilidad,
  settings y fechas se conservaron; no se edito `app_database.dart`,
  `app_database.g.dart`, `pubspec.lock` ni el schema.
- No se sobrescribio un destino previo ni se borro el origen. Windows queda
  cubierto por resolucion contractual y fixture, no por runtime real.
- No se cambiaron perfiles, motor, instaladores, scripts, Nini Agents,
  MultiCLI AI source, builds, remoto, stage, commit o push.

### Evidencia de cierre

- Formato y analisis focalizado: limpios.
- Pruebas focalizadas: 17 aprobadas y 1 operativa omitida por defecto; incluyen
  8 escenarios de bootstrap, 7 de DB-01 y 2 de startup. El caso real opt-in
  aprobo migracion e idempotencia por separado.
- Guardas de arquitectura, generated/schema/dependencias y diff se ejecutan al
  cierre de la fraccion; no se ejecuto build ni runtime Windows.

## Fraccion cerrada: ENG-01

### Objetivo y resultado

Congelar dentro de Nini Hub el consumo de las consultas JSON v1 ya entregadas
por Nini Agents, sin ampliar ni modificar el motor externo. El nuevo
`NiniAgentsReadClient` invoca directamente `nini-agents`, decodifica
`version`, `list`, `status` y `tools`, y falla de forma tipada ante problemas de
proceso, timeout o protocolo. `tools` es el inventario de capabilities; no se
agrego ni asumio un comando externo `capabilities`.

### Alcance ejecutado

- Se creo `lib/core/process/nini_agents_read_client.dart` como infraestructura
  compartida Data sobre `ProcessRunner`, con ejecutable canonico, argumentos
  separados y timeout de 15 segundos.
- El cliente valida envelope schema 1, producto y comando, consistencia entre
  exit code y `ok/data/error`, stderr vacio, un unico documento JSON, conteos,
  orden estable y campos tipados de perfiles y tools.
- Los profile summaries aceptan schema 1 y 2 y nunca contienen paths,
  `profileId`, credenciales ni runtime privado. `MULTICLI_HOME` se propaga solo
  cuando el caller entrega un root explicito para `list/status`.
- `NiniAgentsReadFailure` distingue ejecutable ausente, timeout, proceso,
  respuesta malformada, schema no soportado, violacion de protocolo y error
  remoto; conserva el `error.code` snake-case y exit code del motor.
- Se creo `test/core/process/nini_agents_read_client_test.dart` con doubles de
  proceso y respuestas Linux/Windows sinteticas.

### Contratos preservados y exclusiones

- `/home/nini/IdeaProjects/nini-agents` no fue modificado. Su contrato JSON v1
  publicado permanece owner del wire format y sus entrypoints Bash/PowerShell
  siguen separados de Flutter.
- `ProfileDiscoveryService`, `MultiCliGateway`, lifecycle, launch, providers,
  startup y SQLite no cambiaron. El cliente queda preparado pero no productivo;
  `PRF-01` hara el cutover de discovery y metadata mediante un alcance nuevo.
- No se accedieron perfiles o credenciales reales, no se ejecutaron mutaciones,
  app-server, UI, instalaciones, builds, stage, commit, push ni remotos.

### Evidencia de cierre

- `dart format` sobre cliente y prueba: limpio.
- `flutter analyze` focalizado: sin issues.
- Pruebas Nini Hub: 12/12 aprobadas para version, list/status, tools Linux y
  Windows, schema v1/v2, `MULTICLI_HOME`, errores remotos, ejecutable ausente,
  timeout, stdout contaminado, stderr, schema/comando/count/order invalidos y
  codigos no machine-safe.
- Contrato Bash del checkout Nini Agents observado en HEAD `ad9630c`: 11/11 en
  `tests/json_cli.bats`, exclusivamente con fixtures temporales.
- Paridad PowerShell congelada por `tests/JsonCli.Tests.ps1` y el CI verde
  `32603326309` sobre `5b74f5c`, ancestro del HEAD observado: Pester 393/393,
  `MultiCli.Json.psm1` con 100% de cobertura y smoke efimero Windows. Los tests
  contractuales no tienen cambios locales.
- PowerShell no esta instalado en este host; no se repitio runtime Windows ni se
  extrapola esa ausencia a los puntos de launch, integraciones o QA final.

## Subfraccion ENG-02A: delta validado en aislamiento

### Objetivo y resultado actual

Exponer `new` y `rename` mediante el envelope JSON v1 directamente en Nini
Agents, sin portar reglas de perfiles a Nini Hub. El motor externo conserva
validacion, adapters, metadata, runtime, aliases y shortcuts; Nini Hub todavia
no consume estas mutaciones ni modifica SQLite.

### Contrato implementado

- Exito: `state: applied` y resumen publico `tool`, `name`, `type`,
  `schemaVersion`; rename agrega `from`.
- Rechazo: `data: null`, codigo estable y `error.details.state` igual a
  `not_applied` o `partially_applied`.
- Codigos congelados: `invalid_arguments`, `invalid_identifier`,
  `profile_not_found`, `profile_exists`, `cross_tool_rename` y
  `operation_failed` segun el comando.
- No expone paths, `profileId`, credenciales, hashes, IDs de cuenta ni runtime
  privado. No lee contenido de autenticacion.

### Cambio incidental aprobado

Una reproduccion sintetica demostro que el rename Bash movia el perfil y se
detenia antes de recrear aliases cuando un adapter CLI no tenia desktop
shortcut: `remove_shortcut()` devolvia uno por la ultima prueba negativa bajo
`set -e`. La ampliacion aprobada agrega un retorno cero idempotente y una
regresion humana; no cambia targets ni borra archivos adicionales.

### Evidencia y gates

- Bash: 8/8 mutaciones JSON, 11/11 contrato JSON previo y 12/12 seguridad de
  perfiles; la copia aislada completo las 31/31 pruebas dirigidas.
- JSON Schema: cuatro envelopes de exito y rechazo para new/rename validados.
- Overlay: 22/23; el unico fallo pertenece al protocolo de titulo Hyper de
  cambios concurrentes y no cruza new/rename.
- CI manual `32741318583` sobre `94c1ef1`: las siete pruebas nuevas
  `JsonMutations.Tests.ps1` pasaron en Windows PowerShell 5.1/Pester 3.4.0.
  Tambien pasaron PSScriptAnalyzer, install smoke Windows y Ubuntu, shellcheck,
  Bats Ubuntu, actionlint y metadata de release.
- La harness `b7790c9` fijo `ad9630c` como baseline y uso `if: always()` para
  no omitir cobertura PowerShell tras el fallo global. CI `32743230689` aprobo
  Bash exacto 100 % (4/4) y revelo PowerShell 33,33 % (1/3): faltaban llamadas
  in-process al helper de error en `lib/MultiCli.Json.psm1:41-42`.
- El commit test-only `879d461` importo el modulo JSON en
  `ModuleFunctions.Tests.ps1` y verifico el envelope de error estable sin tocar
  producto. CI `32744574564` aprobo esa prueba, Bash changed-line 100 % (4/4),
  PowerShell changed-line 100 % (3/3) y `MultiCli.Json.psm1` 100 % (36/36).
- La suite Pester completa del tip termino 420 passed y 18 failed, sin skips,
  pending o inconclusive. El subconjunto de cobertura tuvo 283 passed, 17
  failed y 502 misses inesperados fuera del modulo JSON; por eso el job global
  sigue rojo aunque la cobertura exacta ENG-02A paso. No se corrigieron esos
  fallos.
- macOS fallo al parsear `lib/migration.sh:195` bajo Bash 3.2. `git blame`
  atribuye esa linea a `ad9630c`; es un incidente separado del delta ENG-02A.
- Validacion documental Nini Agents y `git diff --check` del alcance pasaron;
  la bitacora Nini Hub tambien quedo sin errores de whitespace.
- La validacion creo y publico solo dos ramas temporales, un commit de feature,
  un commit vacio de reintento, una harness CI, una prueba in-process y el PR
  borrador `#1`. No hubo perfiles o credenciales reales, SQLite, Flutter,
  builds, instalaciones, merge, release, cambios en `main` ni publicacion del
  HEAD local.

### Decision posterior y continuidad

Los gates changed-line exactos de ENG-02A quedaron cumplidos. Los 18 fallos de
la suite Pester y el parseo Bash 3.2 pertenecen a la base y conservan alcances
propios. El usuario autorizo continuar ENG-02B sin diagnosticarlos ni
corregirlos dentro de la mutacion JSON; no se ocultan ni se presentan como
resueltos.

## Subfraccion ENG-02B: delete JSON seguro validado en aislamiento

### Objetivo y contrato

- Forma publica no interactiva:
  `nini-agents --json delete <tool>/<profile> --confirm <tool>/<profile>`.
- La confirmacion debe coincidir exactamente. Falta, mismatch o identificador
  invalido falla antes de escribir con exit 2 y `not_applied`.
- Perfil ausente usa `profile_not_found`/`not_applied`. Un fallo despues de
  iniciar cleanup usa exit 6, `operation_failed` y `partially_applied` para que
  el consumidor haga un `list/status` fresco.
- Exito devuelve solo `state: applied` y la direccion publica `{tool,name}`.
  No expone `profileId`, paths, archivos auth, credenciales, hashes, IDs de
  cuenta ni runtime privado.
- Bash y PowerShell reutilizan los owners humanos de delete; el prompt humano
  no cambio. El bypass interno solo se activa despues de validar la
  confirmacion JSON exacta.

### Implementacion y evidencia

- Branch temporal `validation/eng-02b`, commit `c36a229`, construida sobre el
  tip validado `879d461`. El worktree concurrente original no fue sobreescrito.
- Archivos de producto: `nini-agents`, `nini-agents.ps1`,
  `schema/cli-output.schema.json`, `docs/json-cli.md` y `README.md`; pruebas
  equivalentes Bash/PowerShell y regresiones de contrato/containment.
- Local: sintaxis Bash, schema, tres envelopes delete, documentacion y
  `git diff --check` correctos; 35/35 pruebas focales, seguidas por 2/2
  aserciones finales de identificador/junction. Roots y credential store fueron
  temporales.
- Unico CI `32748238240`: pasaron actionlint, metadata, shellcheck,
  PSScriptAnalyzer, install smoke Windows/Ubuntu, Bats Ubuntu completo y Bash
  changed-line 100 % (9/9). Los cuatro tests ENG-02B pasaron en Windows
  PowerShell 5.1/Pester 3.4.0.
- El gate de modulos PowerShell reporto 100 % (3/3) para
  `MultiCli.Json.psm1`, linea heredada de ENG-02A. ENG-02B modifica el
  entrypoint PowerShell y su conducta se probo mediante procesos hijos; ese
  archivo no forma parte del instrumentador `lib/*.psm1`.
- Pester total termino 424 passed / 18 failed; ningun test ENG-02B fallo.
  macOS repitio el parse error de `lib/migration.sh:195` bajo Bash 3.2. Ambos
  incidentes se mantienen como `separate_fix`; no se cambiaron.
- No hubo perfiles o credenciales reales, Flutter, SQLite, build nativo,
  instalacion, merge, release ni publicacion de `main`.

### Siguiente gate

`PRF-01` necesita un alcance Nini Hub nuevo para reemplazar discovery y
lifecycle legacy con un adapter Data tipado de `new`/`rename`/`delete`, mapear
codigos/estados y reconciliar `partially_applied` mediante `list/status`. El
contrato puede desarrollarse contra `c36a229`; antes de un smoke instalado debe
decidirse merge/publicacion del motor. Launch/app-server stdout-clean queda
fuera y se tratara en `RUN-01`/`CDX-01`.

## Fraccion cerrada: PRF-01

### Objetivo y resultado

Reemplazar en Nini Hub el discovery por filesystem y el CRUD heredado de
`multi-cli` con el contrato JSON v1 de Nini Agents. `ProfileDiscoveryService`
consume `list/tools`, acepta summaries schema 1/2 y sincroniza SQLite sin abrir
directorios, metadata privada ni archivos de credenciales.

`NiniAgentsProfileLifecycle` ejecuta `new`, `rename` y `delete`; delete siempre
envia `--confirm` con el target exacto. `MultiCliProfileLifecycle` fue retirado
y `MultiCliGateway` ya no contiene mutaciones, aunque conserva launch y helpers
de workspace hasta `RUN-01`.

### Contratos y orden de efectos

- El transporte conserva ejecutable/argumentos separados, envelope schema 1,
  stdout/stderr estricto, timeout de 15 segundos para lectura y dos minutos
  para mutaciones.
- Exitos de mutacion validan `state: applied`, direcciones publicas exactas,
  tipos `full/shared/cli/isolated` y schema 1/2 cuando aplica.
- `not_applied` se traduce a fallos tipados de Profile sin exponer JSON a
  Presentation. Ejecutable ausente, conflictos y respuestas inconsistentes
  tienen mensajes visibles en espanol.
- `partially_applied` y transportes indeterminados consultan `status`. Rename
  conserva el ID si el target aparece y el origen ya no; delete elimina la fila
  solo si el target ya no aparece; despues se sincroniza SQLite. El controller
  hace una lectura fresca antes de informar el fallo y nunca simula rollback.
- En exito, rename actualiza identidad local despues del motor y delete elimina
  la fila/cascadas despues del motor. Create se materializa mediante discovery.

### Persistencia, metadata y compatibilidad

- No cambio schemaVersion 2, tablas, generated, IDs, nulabilidad ni formato UTC.
- Discovery deriva `profileHome` desde el root configurado y la direccion
  publica porque el schema SQLite legacy aun lo exige para launch; no prueba la
  existencia del path.
- Conserva display name, favorito, created/last-launched y `hasAuthFile` local.
  Los perfiles no listados pasan a `deactivated`; al reaparecer recuperan ID y
  metadata. Perfiles `isolated` ya tienen representacion de dominio.
- `tools.installed` alimenta disponibilidad del perfil principal. Herramientas
  no soportadas por Nini Hub se ignoran sin copiar reglas del motor.
- Un perfil nuevo comienza con `hasAuthFile = false`: el contrato publico no
  revela auth. El handoff posterior a Device Auth pertenece a `CDX-01` y no se
  resolvio inspeccionando credenciales.

### Archivos y composicion

- Transporte: `lib/core/process/nini_agents_read_client.dart`.
- Data Profiles: `profile_discovery_service.dart`,
  `nini_agents_profile_lifecycle.dart`, `profile_mapper.dart` y el gateway
  legacy reducido a launch/metadata visible.
- Domain/Presentation: `ProfileKind.isolated`, rechazos tipados y refresh
  visible tras fallos parciales.
- Composition root: providers compartidos de cliente, discovery y lifecycle
  Nini Agents.

### Evidencia y exclusiones

- `dart format` sobre los Dart tocados: limpio.
- `flutter analyze` focalizado sobre cliente, Profiles, composition root y
  consumidores afectados: sin issues.
- Gate principal: 57/57 pruebas aprobadas para contrato JSON, discovery,
  lifecycle, metadata Drift, Application, Controller, composicion, deactivacion
  y limite de imports.
- Consumidores afectados: 18/18 pruebas de Settings, Accounts, Activity y
  refresh; widget focalizado de providers 1/1. Total dirigido: 76 aprobadas.
- Guardas estaticas: no quedan mutaciones `new/rename/delete` ni stdin de
  confirmacion humana en el gateway productivo; `git diff --check` limpio al
  cierre.
- No se usaron perfiles o credenciales reales, no se ejecuto el binario
  instalado, build nativo, runtime Windows, schema/generacion, Device Auth,
  launch, app-server, stage, commit, push, merge ni release.
- El smoke real queda pendiente: CRUD existe solo en la branch temporal del
  motor `validation/eng-02b`/`c36a229`, no en `main` ni en una instalacion.

### Siguiente gate

`RUN-01` queda `awaiting_approval`. Debe caracterizar el launcher, terminales,
working directory, titulos, recencia y seleccion antes de retirar
`MultiCliAgentLauncher`; cualquier contrato stdout-clean faltante en el motor
requiere autorizacion separada sobre Nini Agents.

## Fraccion cerrada: RUN-01

### Objetivo y resultado

Retirar el launcher `multi-cli` productivo y ejecutar los perfiles administrados
con `nini-agents launch <tool>/<profile> -- <args>` dentro de la terminal
desktop. `NiniAgentsAgentLauncher` es ahora el adapter Data del puerto
`AgentLauncher`; los perfiles principales conservan el ejecutable nativo porque
no son perfiles administrados por el motor.

El launch de Nini Agents es interactivo y su stdout pertenece a la terminal del
usuario: Nini Hub no lo parsea ni necesita inventar un envelope JSON. El
transporte stdout-clean pendiente queda acotado a app-server en `CDX-01`.

### Contratos y orden de efectos

- Application conserva el orden caracterizado: validar perfil y workspace,
  abrir terminal, actualizar `lastLaunchedAt`, registrar apertura del workspace
  y guardar seleccion. Un fallo al abrir evita toda recencia y bookkeeping.
- El adapter conserva argumentos separados. Codex recibe
  `-c tui.terminal_title=[]`; los perfiles administrados reciben el root
  configurado mediante `MULTICLI_HOME` y el opt-in
  `NINI_AGENTS_HYPER_TITLE_LOCK=1`.
- `DesktopWorkspaceRuntime` concentra home, validacion de working directory y
  titulo `profile · workspace`; ya no se inspecciona la existencia del
  directorio privado del perfil antes de delegar al motor.
- `ProcessRunner.startInTerminal()` acepta environment explicito, lo combina
  con el proceso padre, retira `NO_COLOR` y lo propaga a terminales Linux,
  Hyper y Windows Terminal. La resolucion Windows acepta las extensiones de
  `PATHEXT`, incluido el wrapper instalado `nini-agents.cmd`.
- El foco de ventana permanece best-effort; no altera el resultado del launch.

### Persistencia, integraciones y archivos

- No cambio schemaVersion 2, tablas, generated, IDs, nulabilidad ni settings.
  La unica escritura es `cli_profiles.last_launched_at` en UTC despues de que
  la terminal fue creada, igual que en el flujo previo.
- `MultiCliGateway` y `MultiCliAgentLauncher` fueron eliminados. La metadata
  visible ya pertenece a `DriftProfileRepository`; el fallback de Inicio y los
  helpers desktop pasaron a `DesktopWorkspaceRuntime`.
- Owners nuevos: `lib/features/workspaces/data/nini_agents_agent_launcher.dart`
  y `desktop_workspace_runtime.dart`; `lib/app/providers.dart` compone el
  launcher con el `ProcessRunner` compartido.
- Nini Agents externo no fue modificado. Se observo su contrato Bash/PowerShell
  y la instalacion local, pero no se ejecutaron perfiles reales.

### Evidencia y exclusiones

- `dart format` sobre los ocho Dart tocados: limpio.
- `flutter analyze` focalizado sobre 10 archivos productivos y de prueba: sin
  issues.
- Pruebas de procesos, runtime desktop, launcher, Application, Drift,
  Controller y arquitectura: 26 aprobadas; una prueba de casing fue omitida
  porque requiere runtime Windows.
- `test/widget_test.dart` completo: 26/26 aprobadas. Total ejecutado RUN-01:
  se agregaron 4/4 de metadata/composicion Profiles, para 56 pruebas aprobadas
  y una omitida por plataforma.
- Guardas: no quedan imports, clases ni consumidores Dart de
  `MultiCliGateway`/`MultiCliAgentLauncher`; `git diff --check` limpio.
- No se ejecutaron build, instaladores, terminal real, perfiles o credenciales
  reales, runtime Windows, generacion, suite completa, app-server, Device Auth,
  stage, commit, push, merge ni release. La deteccion `.cmd` tiene prueba pura;
  QA final todavia requiere evidencia Windows real.

### Siguiente gate

`CDX-01` queda `awaiting_approval`. La investigacion read-only ya demostro que
el cliente vigente inicia `codex app-server` directamente con
`CODEX_HOME=profileHome`, omitiendo el runtime overlay y los argumentos
forzados del adapter Nini. Tambien identifico que Device Auth exitoso no
persiste explicitamente `hasAuthFile`, por lo que discovery puede conservar el
perfil como no autenticado. Hace falta aprobar el alcance exacto antes de
modificar app-server, sesion, metadata, cancelacion, timeouts o errores.

## Subfraccion ENG-02C: exec stdout-clean validado en aislamiento

### Objetivo y contrato

- Se agrego `nini-agents exec <tool>/<profile> -- <args...>` en el worktree
  aislado basado en `c36a229`. Es transporte raw, no envelope JSON v1.
- Acepta solo `accountOverlay/fileOverlay` foreground, incluidos perfiles
  legacy whole-root. Reutiliza binary, overlay, entorno limpiado y argumentos
  forzados de `launch`; adapters detached u otros mecanismos fallan antes de
  spawn.
- En exito, el launcher no agrega salida humana. Bash reemplaza el wrapper por
  el hijo y conserva el PID. PowerShell hereda stdin/stdout/stderr, espera y
  propaga el exit code; Nini Hub debera terminar el arbol supervisado al
  cancelar en Windows.

### Archivos y compatibilidad

- Motor: `nini-agents`, `nini-agents.ps1` y
  `lib/multicli-runtime.sh`.
- Contrato/pruebas: `docs/exec-contract.md`, `README.md`,
  `tests/exec_stdio.bats` y `tests/ExecStdio.Tests.ps1`.
- Relevos: las dos bitacoras del motor y este archivo.
- `launch`, shorthand, avisos humanos, Hyper, schema de adapters, credenciales,
  shims e instalacion no cambiaron.

### Validacion y limites

- Linux sintetico: nueva suite 4/4; overlay 21/21 con el opt-in Hyper retirado
  explicitamente del ambiente; isolated 24/24; launch performance 3/3. Total
  relacionado 52/52.
- Adapters 17/17, sintaxis Bash, documentacion y `git diff --check` pasaron.
- PowerShell/Pester, Windows y macOS no estan disponibles; las dos pruebas
  Pester nuevas no se ejecutaron. El gate Bash de cobertura termino con codigo
  2 antes de instrumentar porque falta `bashcov`.
- Solo se usaron homes, perfiles, binaries y credenciales sinteticos en roots
  temporales. No hubo Codex real, SQLite, perfiles/credenciales reales,
  instalacion, stage, commit, merge, push ni publicacion.

### Siguiente gate

Presentar y aprobar `CDX-01` en Nini Hub. Debe reemplazar el spawn directo por
el contrato exec, compartir una frontera de app-server entre Usage, Heartbeat y
Device Auth sin mezclar sus politicas, persistir el handoff de autenticacion en
SQLite, tipar protocolo/proceso/timeout/cancelacion y demostrar lifecycle. La
integracion o publicacion del motor conserva una autorizacion separada.

## Subfraccion CDX-01A: transporte y lifecycle Codex completos

### Objetivo y antes/despues

- El cliente Codex ahora recibe el `Profile` completo. Antes todos los perfiles
  iniciaban `codex app-server --stdio` directamente con `CODEX_HOME`; ahora el
  perfil default conserva esa frontera nativa y uno gestionado usa
  `nini-agents exec codex/<profile> -- app-server --stdio` con
  `MULTICLI_HOME` derivado de la ruta ya descubierta.
- Usage, Heartbeat y Device Auth delegan el perfil completo al mismo adapter de
  app-server. Sus politicas, timeouts y mapeos permanecen en sus features; no se
  introdujo una dependencia entre ellas ni una recarga global.
- El spawn conserva ejecutable y argumentos separados, `runInShell: false` y
  directorio del perfil. La ubicacion gestionada debe coincidir con la
  herramienta declarada antes de iniciar el proceso.

### Contrato, lifecycle y errores

- Stdout es un canal JSON-RPC estricto: una linea no JSON o un mensaje sin
  respuesta/notificacion valida cierra logicamente la sesion con
  `CODEX_PROTOCOL_ERROR`; ningun texto humano se interpreta ni se devuelve.
- Los fallos esperables distinguen ejecutable ausente, perfil ausente, timeout,
  salida prematura, protocolo, RPC y cancelacion. Refresh conserva sus estados
  publicos; Device Auth propaga el fallo tipado sin exponer diagnosticos en
  `toString()`.
- Stderr se captura hasta 4096 caracteres, se redacta y queda solo como
  diagnostico tipado. No se agregaron logs. El cierre es idempotente: cierra
  stdin, concede 200 ms, envia TERM/KILL al PID en Linux y usa `taskkill /T /F`
  para el arbol Windows despues de la gracia.
- La sesion Device Auth posee exactamente un proceso RPC para start, espera,
  cancelacion y cierre. El timeout de confirmacion se traduce a
  `DEVICE_AUTH_TIMEOUT`.

### Archivos, persistencia e integraciones

- Transporte/modelos: `lib/providers/codex/codex_app_server_client.dart` y
  `codex_app_server_models.dart`.
- Consumidores Data: `lib/features/usage/data/codex_usage_provider.dart`,
  `lib/features/heartbeat/data/codex_heartbeat_quota_probe.dart` y
  `lib/features/accounts/data/codex_account_device_auth_gateway.dart`.
- Pruebas: nuevo `test/providers/codex/codex_app_server_client_test.dart` y
  adaptacion de doubles en Usage, Heartbeat, refresh safety y fallback parcial.
- No cambio schemaVersion 2, tablas, filas Drift, `hasAuthFile`, credenciales ni
  filesystem real. Tampoco se modifico el motor externo; el comando `exec`
  requerido sigue aislado, sin instalar ni integrar en su `main`.

### Evidencia y exclusiones

- `dart format` sobre los diez Dart de la fraccion: limpio.
- `flutter analyze` focalizado sobre 13 archivos productivos y de prueba: sin
  issues.
- Transporte, runtime, Accounts, Usage, Heartbeat, refresh safety y fallback:
  22 pruebas aprobadas. La guarda arquitectonica agrego 1/1 aprobada.
- `git diff --check` del worktree: limpio. Se preservaron todos los cambios
  concurrentes y no se stageo, commiteo, borro ni revirtio nada.
- No se ejecutaron suite completa, build, instaladores, generacion, Codex real,
  perfiles/credenciales reales, Windows real, SQLite write, stage, commit, push,
  merge ni release.

### Resultado posterior

CDX-01B completo el handoff persistente y cerro `CDX-01`. El transporte de
perfiles administrados conserva como gate externo la integracion e instalacion
de `nini-agents exec` dentro de `ENG-02`.

## Subfraccion CDX-01B: handoff persistente de Device Auth completo

- Estado global y HEAD observado: `10/14`, Nini Hub `main` /
  `5d378f24f49dc2d4594afbbf487890e463abc88d` con worktree concurrente
  preservado.
- Bloque, punto y estado: Operacion, `CDX-01`, `complete`.
- Skills consumidas: `nini-hub-migrate-product`,
  `nini-hub-domain-application`, `nini-hub-data-desktop-integrations` y
  `nini-hub-presentation-flutter-desktop`.
- Alcance aprobado: puerto Accounts, escritura Drift focalizada, orden de
  efectos, composicion, snapshot visible, pruebas dirigidas y este relevo.

### Objetivo y antes/despues

- Antes, una confirmacion exitosa de Codex se registraba en Activity y disparaba
  discovery, Heartbeat y Usage, pero ninguna operacion cambiaba
  `cli_profiles.has_auth_file`; discovery preservaba `false` y Accounts podia
  seguir mostrando el perfil sin vincular.
- Ahora Accounts posee `AccountAuthenticationStore`. Solo `success=true` marca
  el `profileId` confirmado antes de discovery; `success=false` conserva el
  flujo previo sin escribir autenticacion.
- El `AccountSnapshot` final se carga una vez y el controller lo instala
  directamente. `synchronizeCore()` continua limitado a Activity y calendario;
  no se agrego reload global de Accounts.

### Contrato, persistencia y orden de efectos

- Orden exitoso: Activity de finalizacion -> `markAuthenticated` -> discovery
  -> monitor Heartbeat -> refresh Usage -> sincronizacion Activity/calendario ->
  snapshot Accounts.
- `DriftAccountAuthenticationStore` actualiza exclusivamente
  `cli_profiles.has_auth_file = true` por `profileId`. La operacion es
  idempotente y un ID ausente produce `AccountNotFoundFailure`.
- `AccountDeviceAuthProgress.authenticationPersisted` distingue un fallo
  posterior a la escritura de uno ocurrido antes. Permanecen
  `completionRecorded`, `profilesSynchronized` y `usageRefreshed` como ultimos
  efectos definitivamente aplicados.
- No cambiaron schemaVersion 2, tablas, migraciones, `app_database.dart`,
  `app_database.g.dart`, IDs, nulabilidad, UTC, credenciales ni filesystem.

### Archivos y composicion

- Domain/Application: `features/accounts/domain/account_device_auth.dart`,
  `account_failure.dart` y `application/account_device_auth.dart`.
- Data: nuevo
  `features/accounts/data/drift_account_authentication_store.dart`.
- App: `lib/app/providers.dart` compone el adapter dentro de
  `CompleteAccountDeviceAuth`.
- Pruebas: Application, adapter Drift, controller, composicion y el double
  consumidor de Usage. Discovery ya tenia una regresion que demuestra que
  conserva metadata local de autenticacion.

### Evidencia y exclusiones

- `dart format` sobre diez Dart del alcance: limpio.
- `flutter analyze` focalizado sobre diez archivos productivos/de prueba: sin
  issues.
- Accounts Application/Data/Controller/composicion: 20/20 pruebas aprobadas.
  Discovery y guarda arquitectonica: 5/5 aprobadas. Tres escenarios restantes
  de la caracterizacion Usage: 3/3 aprobados. Total dirigido aprobado: 28.
- El escenario legacy `dashboard refresh all keeps the legacy visible
  synchronization order` falla antes de ejecutar el flujo porque espera un
  overflow de marca de 25 px y `tester.takeException()` devuelve `null`; se
  registro como `separate_fix` y no se cambio dentro de CDX-01B.
- `git diff --check`: limpio. Se preservaron todos los cambios concurrentes y no
  se stageo, commiteo, borro ni revirtio nada.
- No se ejecutaron suite completa, build, instaladores, generacion, Codex real,
  perfiles/credenciales reales, Windows real, datos SQLite reales, motor
  externo, stage, commit, push, merge ni release.

### Siguiente gate

El cierre de `ENG-02` queda `awaiting_approval`: integrar/versionar el delta
ENG-02C del worktree aislado y decidir instalacion/smoke del motor antes de
presentar perfiles administrados como operativos end-to-end. `QA-01` y
`CUT-01` permanecen pendientes.

## Fraccion OPS-01: Usage, Heartbeat y Activity completos en Nini Hub

- Estado global y HEAD observado: `11/14`, Nini Hub `main` /
  `5d378f24f49dc2d4594afbbf487890e463abc88d` con worktree concurrente
  preservado.
- Bloque, punto y estado: Operacion, `OPS-01`, `complete`.
- Skills consumidas: `nini-hub-migrate-product`,
  `nini-hub-domain-application`, `nini-hub-data-desktop-integrations` y
  `nini-hub-presentation-flutter-desktop`.
- Alcance aprobado: invocacion Heartbeat por tipo de perfil, terminacion del
  arbol Windows en timeout, pruebas dirigidas y este relevo.

### Objetivo y antes/despues

- Antes, Usage y el quota probe de Heartbeat ya entregaban el `Profile`
  completo al adapter app-server, pero el comando Heartbeat omitia esa frontera:
  todos los perfiles ejecutaban `codex exec` con `CODEX_HOME`.
- Ahora un perfil administrado ejecuta
  `nini-agents exec codex/<profile> -- codex-child-args` con `MULTICLI_HOME`
  derivado de `profileHome`. El perfil default conserva `codex exec` con
  `CODEX_HOME`.
- El prompt, sandbox `read-only`, flags de aislamiento, razonamiento `low`,
  directorio temporal, `NO_COLOR`, timeout de 90 segundos, redaccion y resumen
  de Activity permanecen iguales.

### Contratos, integraciones y orden visible

- `ProcessHeartbeatCommandGateway` valida que la ruta del perfil administrado
  pertenezca a la herramienta antes de invocar Nini Agents. Ejecutable y
  argumentos permanecen separados; no se usa shell.
- `ProcessRunner` termina un timeout Windows con
  `taskkill /PID <pid> /T /F`, acotado a cinco segundos, y conserva un kill de
  respaldo si la terminacion del arbol falla. Linux mantiene TERM y KILL
  diferido.
- Los command logs continuan en la persistencia vigente de Activity, con estado
  `timeout` y exit code 124. No cambiaron schemaVersion, tablas, migraciones,
  generated, consultas ni datos reales.
- La sincronizacion visible sigue siendo focal y explicita: Activity ->
  calendario -> Accounts. Heartbeat refresca las proyecciones solo despues de
  exito; no se agrego recarga global ni reactividad nueva de Activity.

### Archivos y evidencia

- Producto: `lib/core/process/process_runner.dart` y
  `lib/features/heartbeat/data/process_heartbeat_command_gateway.dart`.
- Pruebas: `test/core/process/process_runner_test.dart` y
  `test/features/heartbeat/data/heartbeat_adapters_test.dart`.
- `dart format` sobre los cuatro Dart tocados: limpio. `flutter analyze`
  focalizado sobre esos cuatro archivos: sin issues.
- Adapters Heartbeat y timeout de proceso: 10/10 pruebas aprobadas. Application,
  scheduler, composicion, Accounts visible, Usage y Activity: 32/32 aprobadas.
  Guarda arquitectonica: 1/1 aprobada. Total posterior al cambio: 43 pruebas
  aprobadas; la baseline previa a editar fue 16/16.
- `git diff --check`: limpio tras actualizar este relevo. Se preservaron
  todos los cambios concurrentes y no se stageo, commiteo, borro ni revirtio
  nada.

### Riesgos, exclusiones y siguiente gate

- La ruta Windows real y `taskkill` no se ejecutaron en Windows; la prueba pura
  demuestra que el timeout solicita la terminacion del arbol y conserva el log
  tipado. Tampoco se ejecutaron perfiles o credenciales reales.
- No se modificaron schema, UI, Usage/Heartbeat amplios, Activity reactiva,
  motor externo, builds, instaladores, generacion, stage, commit, push, merge ni
  release. El overflow legacy y la no reactividad de Activity permanecen como
  `separate_fix` fuera de OPS-01.
- Resultado posterior: `ENG-02` integro y versiono el contrato
  `nini-agents exec`; el wrapper instalado ya apunta al checkout activo.
  Permanecen `QA-01` y `CUT-01`.

## Fraccion ENG-02: mutaciones y exec transparente completos

- Estado global y HEAD observado: `12/14`; Nini Hub `main` /
  `5d378f24f49dc2d4594afbbf487890e463abc88d`. Motor `main` /
  `ad9630c996486dfb337644580bf76f533038e87d`, ahead 1 y con todo el worktree
  concurrente preservado.
- Bloque, punto y estado: Motor, `ENG-02`, `complete`.
- Skills consumidas: `nini-hub-migrate-product`,
  `nini-hub-data-desktop-integrations`, `nini-agents-change-integral`,
  `nini-agents-adapter-runtime` y `nini-agents-upstream-integration`.
- Alcance aprobado: versionar ENG-02C en la branch aislada existente, portar
  manualmente ENG-02B/C al checkout principal, validar contratos focalizados y
  actualizar las bitacoras. No autorizo branch nueva, installer, perfiles
  reales, builds, suites amplias, merge, push, tag ni release.

### Antes/despues, contratos e integracion

- Antes, Nini Hub ya consumia delete JSON y `exec`, pero esos contratos solo
  existian en el worktree aislado del motor. El ejecutable instalado que apunta
  al checkout principal no los exponia.
- Ahora `--json delete` conserva confirmacion exacta, containment, estados
  `applied`/`not_applied`/`partially_applied` y envelope seguro. `exec` acepta
  solo perfiles foreground `accountOverlay/fileOverlay`, reutiliza el adapter y
  reemplaza el wrapper por el proceso hijo en Bash; PowerShell hereda stdio y
  propaga su exit code.
- La branch `validation/eng-02b` contiene el linaje versionado hasta `fc3361f`.
  El port al `main` concurrente se hizo por hunks para conservar movimiento
  remoto y todos los cambios previos; no cambio el HEAD ni el index.
- El wrapper regular `/home/nini/.local/bin/nini-agents` ya ejecutaba
  `/home/nini/IdeaProjects/nini-agents/nini-agents`. Sin reinstalarlo, el smoke
  de version/ayuda confirmo `1.0.0` y el comando `exec` activo.

### Validacion, riesgos y siguiente gate

- Motor Linux sintetico: 92/92 Bats focalizadas aprobadas con el opt-in externo
  de titulo Hyper retirado del ambiente. Tambien pasaron `bash -n`, JSON Schema,
  17 adapters, documentacion, metadata de release y `git diff --check`.
- Consumidor Nini Hub: 38/38 pruebas focalizadas de app-server, cliente JSON,
  lifecycle, launcher y Heartbeat; guarda arquitectonica 1/1 aprobada y
  `flutter analyze` focalizado sobre cinco integraciones sin issues.
- No se ejecutaron PowerShell/Pester, Windows, macOS, Codex real, perfiles o
  credenciales reales, builds ni instaladores. Los incidentes base Pester/Bash
  3.2 permanecen `separate_fix`; `origin/main` y releases del motor aun no
  contienen ENG-02.
- Resultado posterior: QA-01A valido la equivalencia Linux; `QA-01` permanece
  `validating` exclusivamente por el gate Windows real. `CUT-01` conserva la
  publicacion/cutover y deprecacion final.

## Subfraccion QA-01A: equivalencia Linux validada

- Estado global y HEAD observado: `12/14`; Nini Hub `main` /
  `5d378f24f49dc2d4594afbbf487890e463abc88d` con todo el worktree de migracion
  preservado. Bloque, punto y estado: Cierre, `QA-01`, `validating`.
- Skills consumidas: `nini-hub-migrate-product` y
  `nini-hub-data-desktop-integrations`.
- Alcance aprobado: análisis completo, matriz Flutter dirigida, consultas JSON
  al motor instalado, smoke desktop Linux debug con roots temporales y
  actualizacion de `project-index.md`/esta bitacora. Un fallo no autorizaba fix.

### Matriz, persistencia e integraciones

- `flutter analyze` completo termino sin issues.
- La matriz dirigida aprobo 223 pruebas de arquitectura, bootstrap/migracion
  SQLite, procesos, Settings, Profiles, Workspaces, Accounts/Device Auth,
  Usage, Heartbeat, Activity, Codex app-server y UI visible. Dos casos quedaron
  omitidos de forma esperada: migracion sobre soporte real no autorizado y
  deduplicacion de casing que exige runtime Windows.
- El wrapper instalado ejecuto `version`, `tools` y `list` JSON v1 sobre un
  `MULTICLI_HOME` temporal: 3/3 envelopes validos y cero perfiles descubiertos.
  No se creo, lanzo, autentico, renombro ni borro ningun perfil.
- El smoke real ejecuto `flutter run -d linux --debug` con `HOME`,
  `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` y `MULTICLI_HOME`
  temporales. Nini Hub construyo el bundle debug, abrio la ventana, expuso el
  VM service y cerro mediante el comando normal de Flutter sin errores.
- La SQLite runtime temporal quedo en el application ID `com.nini.hub`, con
  `PRAGMA integrity_check = ok` y cero filas en `foreign_key_check`. El root
  temporal fue enviado a la papelera; el artefacto debug permanece solo bajo
  `build/`, ignorado por Git.

### Exclusiones, riesgos y siguiente gate

- No cambiaron Dart, schemaVersion 2, tablas, migraciones, generated, motor,
  perfiles, credenciales ni datos reales. Tampoco hubo installer, release,
  stage, commit, merge, push o tag.
- No se ejecutaron runtime Windows, PowerShell/Pester, Codex real, Device Auth
  real ni terminal/launch de un perfil real. La evidencia Windows sintetica
  existente no sustituye el gate de plataforma.
- Para cerrar `QA-01` falta QA-01B en Windows real: confirmar directorios de
  soporte `Nini Hub`/legacy `MultiCLI AI`, casing de workspaces, resolucion del
  wrapper `.cmd`, launch en Windows Terminal, `nini-agents exec` PowerShell y
  terminacion del arbol supervisado. Hasta entonces el conteo permanece
  `12/14`; `CUT-01` no inicia.

## Activacion local ACT-01: Nini Hub instalado y operativo en Linux

- Estado global: `12/14`; esta activacion local no sustituye QA-01B ni declara
  `CUT-01`. Nini Hub quedo abierto desde el release instalado.
- Skills consumidas: `nini-hub-migrate-product`,
  `nini-hub-data-desktop-integrations` y, para clasificar un unico fallo real,
  `nini-hub-diagnostico-incidentes` sin implementar fix.
- Los scripts personales ya existentes
  `compilar_nini_hub.sh`/`compilar_e_instalar_nini_hub.sh` ejecutaron `pub get`,
  build Linux release, staging y activacion. No se recrearon ni modificaron.
- Primera instalacion: `/home/nini/.local/opt/nini-hub/nini_hub`, symlink
  `~/.local/bin/nini_hub`, launcher `~/Desktop/Nini Hub.desktop` y entrada
  `~/.local/share/applications/com.nini.hub.desktop`. Build e instalado tienen
  el mismo SHA-256; ambos desktop files pasaron validacion.
- No existia una instalacion Nini Hub previa, por lo que el script no genero
  `nini-hub.previous`. El origen consolidado y rollback de la migracion SQLite
  permanecen intactos; no se borro MultiCLI AI.

### Discovery, actualización y datos reales

- La configuracion real conserva `profiles_root_path` vacio, que resuelve al
  contrato default `/home/nini/MultiCliProfiles`. `nini-agents --json list`
  encontro 16 perfiles Codex schema v2: nueve `full` y siete `shared`.
- Startup sincronizo esos 16 perfiles gestionados mas el perfil Codex principal:
  17 filas Codex disponibles/autenticadas. La fila Claude existente permanece
  no disponible y no fue borrada; IDs, alias, favoritos y metadata se
  conservaron.
- El scheduler inicial actualizo los 17 estados Heartbeat: siete `active`, cinco
  `observing`, dos `verified`, dos `unsupported` y un `probe_failed`. No quedaron
  comandos `running`; 36 procesos terminaron `success` y uno quedo `error`.
- El unico fallo nuevo corresponde al perfil publico `codex/magic`: el upstream
  respondio `401 token_expired`. El log persistido esta redactado y no contiene
  el token. Se clasifica `preserve/user_action`: requiere volver a vincular ese
  perfil mediante Device Auth; ACT-01 no autorizaba reautenticacion automatica.
- La SQLite real termino con `PRAGMA integrity_check = ok` y cero violaciones de
  foreign keys. Nini Hub solo ejecuto discovery, estados Heartbeat, Activity y
  efectos normales de startup; no creo, renombro ni borro perfiles.

### Pendientes

- La aplicacion esta lista para uso Linux. El perfil `magic` necesita Device
  Auth manual si se desea recuperar su actualización de cuota.
- QA-01B Windows, publicación del motor/remoto y deprecacion de MultiCLI AI
  siguen pendientes. No hubo stage, commit, merge, push, tag o release remoto.

## Fix separado FIX-DB-01: reinicio seguro de la SQLite migrada

- Estado global y HEAD observado: `12/14`; Nini Hub `main` /
  `5d378f24f49dc2d4594afbbf487890e463abc88d`, con todo el worktree concurrente
  preservado. Este fix no agrega un punto al roadmap ni cierra QA-01B/CUT-01.
- Skills consumidas: `nini-hub-diagnostico-incidentes` y
  `nini-hub-data-desktop-integrations`.
- Incidente observado: tras ACT-01, el segundo arranque mostraba “Datos de Nini
  Hub en conflicto” aun sin otro proceso. La base destino tenia 944 comandos y
  la legacy 907 porque Usage/Heartbeat ya habia escrito datos legitimos.
- Causa: `LegacyDatabaseMigrator` volvia a exigir equivalencia exacta destino ↔
  legacy en cada arranque. La idempotencia solo estaba probada con un destino
  que no habia cambiado desde la migracion.

### Contrato y antes/despues

- Antes: primera migracion correcta -> Nini Hub escribe -> reinicio compara con
  rollback congelado -> falso `destinationConflict`.
- Despues: la primera migracion valida origen, snapshot, conteos y filas como
  antes, registra `PRAGMA application_id = 0x4E485542` (`NHUB`) antes de activar
  el destino y conserva el origen. Los reinicios reconocen el destino propio,
  vuelven a validar schema 2, diez tablas, `quick_check` y claves foraneas, y no
  lo comparan contra legacy.
- Bases nuevas tambien quedan marcadas al abrirse. Un `application_id` distinto
  de cero y de `NHUB` se rechaza de forma tipada; un destino legacy sin marca
  solo se adopta si supera la equivalencia exacta historica. No cambiaron
  schemaVersion, tablas, migraciones Drift, generated ni filas de negocio.
- Archivos: `lib/core/database/legacy_database_migrator.dart`,
  `lib/core/database/database_bootstrap.dart`, sus dos pruebas focalizadas,
  `project-index.md` y esta bitacora.

### Datos reales, instalacion y evidencia

- Con Nini Hub cerrado se creo mediante `VACUUM INTO` el rollback consistente
  `/home/nini/.local/share/com.nini.hub/multicli_ai.pre-bootstrap-fix-20260824.sqlite`.
  Sus diez tablas coinciden fila por fila con el destino previo al fix; schema 2,
  `integrity_check = ok`, cero FK y `application_id = 0`.
- Solo se cambio la cabecera de
  `/home/nini/.local/share/com.nini.hub/multicli_ai.sqlite` a `NHUB`. Inmediatamente
  despues conservaba 26 settings, 18 perfiles, 944 logs, 18.646 buckets, 672
  ventanas, 722 snapshots, 722 checks y 6 workspaces; integridad `ok` y cero FK.
  La SQLite legacy permanece sin marca e integra como rollback adicional.
- `flutter analyze` focalizado sobre cuatro archivos termino sin issues. Pasaron
  19 pruebas de migracion/bootstrap (mas un caso real opt-in omitido), 29 de
  startup/UI y una guarda arquitectonica. `git diff --check` se ejecuta al
  cierre.
- El script personal compilo e instalo release Linux; la instalacion anterior
  quedo en `/home/nini/.local/opt/nini-hub.previous`. El launcher instalado
  arranco sin el conflicto y la aplicacion permanecio activa; con el runtime
  abierto la base seguia marcada, `quick_check = ok`, cero FK, 18 perfiles, 17
  disponibles y cero comandos en ejecucion.
- No se probaron Windows real, instaladores Windows ni credenciales nuevas. El
  perfil `codex/magic` conserva el pendiente de Device Auth por su token
  expirado. QA-01B y CUT-01 siguen siendo los unicos puntos restantes.

## Fix separado FIX-ACC-01: correo de cuenta reconocido e inmutable

- Estado global y HEAD observado: `12/14`; Nini Hub `main` /
  `62a9dcaf3a792c21eb753e7d9cd668997f5dd2d5`. Este fix no agrega un punto al
  roadmap ni cambia los gates pendientes de QA-01B/CUT-01.
- Clasificacion: `separate_fix`. El diagnostico de solo lectura demostro que
  discovery y Usage conservaban el `profileId` correcto, pero el correo visible
  podia quedar obsoleto porque el primer reconocimiento inicializaba
  `profile_metadatas` una sola vez y Accounts priorizaba esa metadata sobre el
  ultimo resultado observado.
- Alcance aprobado el 2026-08-25: hacer que el correo pertenezca exclusivamente
  al reconocimiento Codex, retirarlo del contrato editable, bloquearlo en el
  dialog, autocorregirlo al consultar la cuenta y preservar el resto de datos
  administrativos. Se excluyeron schema, generated, SQLite real, motor externo,
  builds, instalacion, Git y cambios concurrentes ajenos.
- Skills consumidas: `nini-hub-diagnostico-incidentes`,
  `nini-hub-feature-integral`, `nini-hub-domain-application`,
  `nini-hub-data-desktop-integrations` y
  `nini-hub-presentation-flutter-desktop`.

### Contrato y antes/despues

- Antes, `UpdateAccountCommand` aceptaba `AccountMetadata` completo y
  `DriftAccountRepository.saveDetails()` podia sobrescribir
  `account_email`. `DriftUsageSnapshotRepository` solo copiaba el correo
  observado cuando no existia metadata; un cambio posterior de cuenta dejaba
  visible la identidad anterior.
- Ahora `AccountEditableMetadata` excluye el correo desde Domain/Application y
  el repository Accounts no lo escribe. El dialog muestra `Correo reconocido`
  como solo lectura. `Account.displayEmail` prioriza la observacion vigente y
  despues el ultimo exito antes de recurrir a metadata persistida.
- Usage es el unico owner de la sincronizacion: dentro de la misma transaccion
  del snapshot actualiza solo `profile_metadatas.account_email` y `updated_at`
  cuando Codex devuelve un correo no vacio diferente. Propietario, plan, notas,
  renovacion, moneda, pagos y cost shares se conservan.
- No se enlazan cuentas por alias, correo o nombre visible ni se mueven checks,
  cuotas o metadata entre IDs. El perfil afectado se autocorrige con su siguiente
  consulta/reconocimiento; no se hizo reparacion directa de datos reales.

### Archivos y evidencia

- Producto: `features/accounts/domain/account.dart`,
  `application/account_management.dart`, `data/drift_account_repository.dart`,
  `presentation/account_dialogs.dart` y
  `features/usage/data/drift_usage_snapshot_repository.dart`.
- Pruebas ajustadas en Accounts Domain/Application/Data/Controller/composicion
  y Usage Data; se agrego
  `test/features/accounts/presentation/account_edit_dialog_test.dart` para
  comprobar correo observado visible y no editable.
- `dart format` sobre los doce Dart del delta: limpio. `flutter analyze`
  focalizado sobre los doce items: sin issues. Regresiones dirigidas:
  33/33 aprobadas; guarda arquitectonica: 1/1 aprobada.
- No se ejecuto suite completa, build, instalacion, runtime Windows, escritura
  sobre SQLite real, Codex real, stage, commit, push, merge ni release. Los
  cambios concurrentes fuera del alcance permanecieron intactos.

## Fix separado FIX-UX-USAGE-01: progreso y resultados incrementales de cuotas

- Estado global y HEAD observado al cierre: `12/14`; Nini Hub `main` /
  `47578432a533785d309867d957241a02f45459a1`. Este fix se clasifica
  `separate_fix`: no agrega un punto al roadmap ni cambia los gates pendientes
  de QA-01B/CUT-01.
- Skills consumidas: `nini-hub-diagnostico-incidentes`,
  `nini-hub-feature-integral`, `nini-hub-domain-application` y
  `nini-hub-presentation-flutter-desktop`.
- Alcance aprobado el 2026-08-25: investigar la espera visual de la consulta
  multiple, exponer progreso real y publicar en Accounts cada snapshot ya
  persistido. Se excluyeron schema/generated, Data concreta, SQLite y perfiles
  reales, `nini-agents`, builds, instalacion, Git y cambios concurrentes ajenos.

### Antes/despues, contratos y orden de efectos

- Antes no existian chunks cerrados: `RefreshAllUsage` ya usaba un pool continuo
  de workers, con concurrencia default 3 y configurable entre 1 y 6. Cada worker
  tomaba el siguiente perfil al terminar, pero Presentation marcaba todas las
  tarjetas como cargando y Accounts solo recibia la proyeccion nueva despues de
  finalizar batch -> Activity -> Calendar -> Accounts.
- Ahora Application informa targets elegibles, inicio, resultado y fallo por
  perfil sin cambiar el pool. `UsageState` distingue `queued`, `running`,
  `completed` y `failed`, conserva conteos inmutables y mantiene el snapshot
  persistido mas reciente por perfil.
- Accounts proyecta ese snapshot sobre su entidad vigente en memoria: la cuota
  de una cuenta aparece al terminar esa consulta, mientras las demas siguen en
  cola o ejecutandose. La proyeccion conserva metadata, costos y ultimo exito,
  y rechaza una respuesta antigua para evitar que pise estado nuevo.
- El header muestra `procesadas/total`, consultas activas, cola y errores; al
  terminar proveedores mantiene feedback explicito con `Sincronizando vistas…`.
  Solo las tarjetas realmente activas animan spinner; cola, exito y fallo usan
  indicadores propios.
- La reconciliacion persistida final sigue ocurriendo una sola vez y conserva el
  orden Activity -> Calendar -> Accounts. Un fallo aplicado despues de guardar
  snapshot tambien sincroniza las vistas antes de reportar el error; no se
  agregaron recargas por cuenta ni consultas N+1.

### Archivos, persistencia y concurrencia

- Producto: `features/usage/application/usage_refresh.dart` y el nuevo
  `usage_account_projection.dart`; estado/controller/coordinator de Usage;
  `features/accounts/presentation/accounts_view.dart`; y
  `features/dashboard/presentation/dashboard_shell.dart`.
- Pruebas: Application y proyeccion de Usage, controller, coordinator,
  caracterizacion visible del dashboard y widgets de tarjetas. Se preservaron
  los cambios concurrentes ya presentes en Accounts/Settings/Heartbeat.
- No cambiaron puertos de persistencia, repositorios concretos, schemaVersion,
  tablas, migraciones, generated ni datos reales. La persistencia por perfil
  mantiene su atomicidad existente; la actualizacion incremental es una
  proyeccion reactiva de snapshots cuya escritura ya concluyo.
- El batch conserva concurrencia acotada 1..6, default 3. Los callbacks son
  sincronos y correlacionados con generacion/request del controller; las
  sincronizaciones visibles se serializan y mantienen un contador para no
  declarar idle entre recargas encadenadas.

### Validacion, riesgos y siguiente gate

- `dart format` se aplico a los Dart tocados. `flutter analyze` focalizado sobre
  13 items de producto/prueba termino sin issues. Pasaron 32/32 pruebas de
  Application/controllers/coordinator/Accounts, 27/27 de `widget_test.dart`,
  el caso dirigido de progreso/sincronizacion del dashboard y la guarda
  arquitectonica 1/1. `git diff --check` queda como verificacion final del delta.
- La corrida completa previa de
  `usage_legacy_characterization_test.dart` conserva un unico assertion legacy
  ajeno: esperaba un overflow de marca de 25 px que el layout vigente ya no
  produce. Se mantiene `separate_fix`; el nuevo escenario de progreso pasa de
  forma aislada.
- No se ejecutaron suite global, build, instalacion, runtime Linux/Windows con
  perfiles reales, Codex real, escritura SQLite real, stage, commit, push, merge
  ni release. La evidencia widget cubre el minimo desktop 900x620; falta QA-01B
  en Windows real para el roadmap, sin ampliar la autorizacion de este fix.
- Resultado: FIX-UX-USAGE-01 queda implementado y validado dentro del worktree.
  El siguiente punto autorizado de migracion sigue siendo QA-01B; cualquier
  ajuste del assertion legacy u otra expansion requiere alcance independiente.

## Mejora separada FEAT-TERM-01: terminal persistente configurable

- Estado global y HEAD observado al iniciar: `12/14`; Nini Hub `main` /
  `3450d1579f0d9af43995388a7f522872baaabb78`. Esta mejora no agrega un punto al
  roadmap ni cambia QA-01B/CUT-01.
- Skills consumidas: `nini-hub-feature-integral`,
  `nini-hub-domain-application`, `nini-hub-data-desktop-integrations` y
  `nini-hub-presentation-flutter-desktop`.
- Alcance aprobado el 2026-08-25: mantener abierta, de forma configurable, la
  terminal interactiva lanzada desde Workspaces cuando la sesion termine o el
  usuario pulse Ctrl+C; versionar el delta y empujarlo junto con los commits
  locales ya categorizados. Se excluyeron procesos internos, app-server,
  Heartbeat, perfiles/datos reales, schema/generated, builds, instalacion y
  cambios en `nini-agents`.

### Contrato, persistencia y plataforma

- `AppPreferences.keepTerminalOpenAfterExit` pertenece a Settings, queda activo
  por defecto y se persiste como `keep_terminal_open_after_exit` en la tabla
  key-value existente. La ausencia de la clave adopta el nuevo default; no
  cambia schemaVersion, tablas, migraciones ni generated.
- El switch `Mantener abierta al finalizar` se aplica a lanzamientos futuros.
  Activado, una sesion terminada —incluido exit code 130 por Ctrl+C— informa el
  resultado y vuelve a un shell login; el usuario cierra con `exit` o mediante
  la ventana. Desactivado conserva el lanzamiento directo y cierre actual.
- Solo `NiniAgentsAgentLauncher` consume la preferencia al abrir agentes
  principal o gestionado. App inyecta una lectura tardia de Settings; Domain no
  conoce plataforma y Presentation no importa ProcessRunner ni Data.
- Linux usa un wrapper Bash temporal con ejecutable y argumentos posicionales.
  Hyper conserva su transporte por environment y delega al mismo wrapper.
  Windows Terminal usa un script PowerShell local mediante `-NoExit -File` y
  conserva target/argumentos como elementos separados. No se interpola un
  command string ni se modifica el motor externo.

### Archivos y evidencia

- Producto: `features/settings/domain/app_preferences.dart`, repository Drift y
  dialog de Settings; `core/process/process_runner.dart`;
  `features/workspaces/data/nini_agents_agent_launcher.dart`; y composicion en
  `app/providers.dart`.
- Pruebas ajustadas en Settings Application/Data/Controller/composicion/UI,
  ProcessRunner, launcher de Workspaces y widget general. El wrapper Linux se
  ejecuto con un target sintetico que termino en 130 y comprobo el retorno a un
  shell `-l`; Windows se valido por composicion de argumentos y contrato del
  script, no mediante runtime real.
- `dart format` dejo limpios 14 Dart. `flutter analyze` focalizado sobre los 14
  items termino sin issues. Pasaron 30/30 pruebas de Settings/ProcessRunner/
  launcher, 27/27 de `widget_test.dart` y la guarda arquitectonica 1/1.
  `git diff --check` queda como verificacion final previa al commit.
- No se ejecutaron terminal interactiva con perfil real, runtime Windows,
  suite global, build, instalacion, SQLite real, credenciales, stage de datos,
  merge, tag ni release. El push autorizado publica solo commits locales de
  Nini Hub en `origin/master`; QA-01B sigue pendiente como evidencia Windows
  real del roadmap.

## Formato de relevo obligatorio

```text
Estado global y HEAD observado:
Bloque, punto y estado:
Objetivo funcional:
Skills consumidas:
Alcance aprobado:
Archivos ejecutados:
Antes y despues:
Contratos y orden de efectos:
Persistencia e integraciones:
Concurrencia, lifecycle y plataforma:
Validacion ejecutada y resultado:
Validacion no ejecutada:
Desviaciones y riesgos:
Siguiente punto y autorizacion requerida:
```
