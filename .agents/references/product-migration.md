# Estado operativo y cierre de migracion de Nini Hub

## Proposito y autoridad

Este documento es el relevo operativo canonico del linaje MultiCLI AI -> Nini
Hub. Conserva solo el estado vigente, las decisiones que aun condicionan el
producto y las puertas pendientes. No es una cronologia de features.

Orden de autoridad:

```text
AGENTS.md
  -> .agents/references/architecture.md
  -> .agents/references/project-index.md
  -> este documento
  -> skill operativa correspondiente
  -> codigo y pruebas vigentes
```

La evidencia detallada acumulada hasta el 2026-08-25 permanece, sin
modificaciones, en
`.agents/references/product-migration-history-2026-08-25.md` con SHA-256
`4738cb07d5d4cf73e5da1da64afdbe1e918fe62cfe6ad9071076b2a98031656c`.
Consultar ese archivo solo para auditoria o para reconstruir una decision
historica concreta; no forma parte de la lectura ordinaria.

Este documento no autoriza cambios. Todo delta debe delimitar objetivo, reglas,
archivos, capas, contratos, persistencia o integraciones, exclusiones y
validacion, y esperar aprobacion explicita.

## Snapshot vigente

- Fecha de consolidacion: 2026-08-25.
- Repo: `/home/nini/StudioProjects/nini_hub`.
- Branch/HEAD observado: `main` /
  `6b4a8efb3a5b4fc068abf5ec0b431e0b9c12215b`.
- Remoto Nini Hub: `origin` apunta a
  `https://github.com/LuchoNoPrograma/nini_hub.git`; nunca debe apuntar al
  remoto historico.
- Estado formal: `12/14`. La implementacion principal opera como Nini Hub en
  Linux; solo quedan los puntos de Cierre.
- Gobernanza vigente: cinco skills operativas; la antigua skill general de
  migracion fue retirada porque sus owners ya estan implementados.
- Fraccion activa: `QA-01`, `validating`. QA-01A Linux esta completa y QA-01B
  requiere runtime Windows real.
- Siguiente punto: `CUT-01`, `pending`; no inicia hasta cerrar QA-01.
- La instalacion Linux existente no debe asumirse equivalente al worktree: los
  fixes posteriores requieren nueva compilacion/instalacion y smoke manual.
- `nini-agents` es el motor vigente. El ejecutable local delega al checkout de
  desarrollo; sus contratos CRUD/exec locales aun requieren verificar
  publicacion upstream durante CUT-01.
- SQLite Nini Hub conserva schemaVersion 2, nombre logico `multicli_ai` y
  `PRAGMA application_id = 0x4E485542` (`NHUB`). La importacion legacy ya fue
  ejecutada; Nini Hub no comparte su archivo vivo con MultiCLI AI.

Estados permitidos: `pending`, `investigating`, `awaiting_approval`,
`approved`, `in_progress`, `validating`, `complete`, `blocked`.

Etiquetas de evidencia: `observed`, `inferred`, `decided`, `preserve`,
`separate_fix`, `blocked_pending_decision`.

## Roadmap canonico: 14 puntos

| Bloque | Punto | Estado | Puerta de salida |
|---|---|---|---|
| Base | 1. `REP-01` Repo independiente | complete | Historial conservado, `.git` propio, remoto nuevo y source original intacto |
| Base | 2. `GOV-01` Gobernanza y relevo | complete | Reglas, arquitectura, indice, relevo y skills operativas vigentes |
| Identidad | 3. `ID-01` Identidad Nini Hub | complete | Producto, package, assets y metadatos usan Nini Hub / `com.nini.hub` |
| Identidad | 4. `SCR-01` Scripts personales | complete | Build/install Nini Hub preservan permisos, backup y launcher |
| Datos | 5. `DB-01` Contrato SQLite | complete | Origen, destino, WAL, integridad, idempotencia y rollback caracterizados |
| Datos | 6. `DB-02` Importacion unica SQLite | complete | Datos transferidos al destino propio y protegidos por ownership `NHUB` |
| Motor | 7. `ENG-01` Lecturas JSON | complete | `version/list/status/tools` machine-safe y versionados |
| Motor | 8. `ENG-02` Mutaciones y exec | complete | CRUD seguro y `exec` stdout-clean disponibles en el checkout integrado |
| Perfiles | 9. `PRF-01` Discovery/lifecycle | complete | Discovery y CRUD usan Nini Agents con reconciliacion parcial |
| Perfiles | 10. `RUN-01` Launch/workspaces | complete | Launch y terminal desktop usan Nini Agents preservando paths y recencia |
| Operacion | 11. `CDX-01` Codex y Device Auth | complete | App-server, auth, timeout y errores quedan tras adapters correctos |
| Operacion | 12. `OPS-01` Usage/Heartbeat/Activity | complete | Cuotas, scheduler, actividad y sincronizacion operan con perfiles Nini |
| Cierre | 13. `QA-01` Equivalencia desktop | validating | Linux verde; runtime Windows real pendiente |
| Cierre | 14. `CUT-01` Cutover/deprecacion | pending | Distribucion publicada, writer unico, rollback y deprecacion verificables |

No aumentar el total. Las comprobaciones A/B/C pertenecen al punto que sirven.

## Decisiones y compatibilidad preservada

- `decided`: identidad humana **Nini Hub**, package/executable `nini_hub` y
  application ID `com.nini.hub`.
- `decided`: Nini Hub posee repo y remoto independientes, conservando el
  historial anterior como linaje y nunca como fork operativo.
- `decided`: `nini-agents` es el motor; Flutter es el plano de control desktop y
  no reimplementa ownership del motor.
- `decided`: la importacion SQLite legacy fue unica. El destino Nini Hub es el
  writer vigente y valida ownership/integridad en reinicios.
- `preserve`: schemaVersion 2, tablas, IDs, nulabilidad, UTC, settings y dinero
  en unidades menores hasta un cambio de datos aprobado.
- `preserve`: `MULTICLI_HOME`, `~/MultiCliProfiles`, nombre logico SQLite
  `multicli_ai` y metadata existente son compatibilidad, no identidad activa.
- `preserve`: source MultiCLI AI, SQLite origen, snapshots/backup y scripts
  personales legacy no se borran durante QA/CUT sin autorizacion expresa.
- `preserve`: Linux y Windows son plataformas de primera clase; evidencia de
  una no sustituye runtime de la otra.

## Contratos operativos vigentes

### Datos y startup

- `DatabaseBootstrap` resuelve soporte, reconoce ownership `NHUB`, valida
  schema/integridad y abre una sola `AppDatabase` explicita.
- Un destino marcado puede divergir legitimamente del rollback despues de
  recibir escrituras. La equivalencia exacta solo pertenece a la importacion o
  adopcion inicial.
- WAL exige snapshot consistente; nunca copiar solo el `.sqlite` activo.
- Rows Drift permanecen en Data. No introducir N+1, lecturas completas para
  contar ni recargas globales.

### Motor, perfiles y procesos

- Consultas y mutaciones Nini Agents consumen JSON versionado. Transportes
  app-server exigen stdout limpio.
- `ProcessRunner` controla ejecutable/argumentos, environment, working
  directory, timeout, cancelacion, exit code, redaccion y Activity.
- Lecturas internas `version/list/status/tools` no contaminan Activity;
  mutaciones, launch y operaciones visibles si se registran.
- Perfiles administrados usan Nini Agents; el perfil Codex principal conserva
  su ejecutable nativo y `CODEX_HOME`.
- `hasAuthFile` solo cambia tras confirmacion real de Device Auth; no se
  inspeccionan ni exponen credenciales.

### Estado visible

- Usage usa concurrencia acotada y publica progreso/snapshots por perfil sin
  esperar el batch completo.
- Activity observa una query limitada y publica `running` y estado terminal sin
  polling global.
- Heartbeat conserva una sola instancia de scheduler, ciclo dinamico y
  distincion entre comando enviado y ancla verificada.
- Accounts compara dos lecturas exitosas para distinguir anclas confirmadas de
  proyecciones; usa un solo reloj reactivo compartido mientras la vista existe.

Los owners, simbolos y pruebas ancla viven en `project-index.md`; no duplicarlos
aqui.

## Gates pendientes

### QA-01B: Windows real

Objetivo: obtener evidencia de plataforma, no implementar fixes implicitos.

Comprobar en Windows real:

1. Directorios de soporte Nini Hub y legacy separados.
2. Casing y deduplicacion de workspaces.
3. Resolucion del wrapper `nini-agents.cmd` mediante `PATHEXT`.
4. Launch en Windows Terminal con working directory y argumentos preservados.
5. `nini-agents exec` PowerShell con stdio/exit code correctos.
6. Timeout/cancelacion del arbol supervisado sin procesos huerfanos.
7. UI redimensionable y flujos principales con la SQLite de prueba autorizada.

Un fallo se diagnostica y delimita como `separate_fix`; no autoriza cambiar
conducta. Hasta completar esta matriz, QA-01 permanece `validating` y el conteo
en `12/14`.

### CUT-01: distribucion y deprecacion

Solo despues de QA-01:

1. Revalidar HEAD/worktree y contratos Nini Hub/nini-agents publicados.
2. Obtener autorizacion separada para commit, push, merge, tag o release.
3. Confirmar que el motor distribuido contiene CRUD y `exec` requeridos.
4. Compilar/instalar por plataforma con rollback verificable.
5. Confirmar Nini Hub como unico writer activo de su SQLite.
6. Conservar rollback y deprecar MultiCLI AI sin borrar datos o historial.
7. Actualizar este roadmap a `14/14` solo con evidencia de salida completa.

## Riesgos y brechas activas

- `blocked_pending_decision`: no existe runtime Windows en este workspace; no
  puede cerrarse QA-01B localmente.
- `observed`: CRUD/exec de Nini Agents estan activos en el checkout local, pero
  deben verificarse en upstream/release durante CUT-01.
- `observed`: la suite base del motor conserva 18 fallos Pester ajenos a los
  contratos focales ya validados.
- `separate_fix`: Bash 3.2 de macOS no parsea una linea legacy de
  `lib/migration.sh`; no esta diagnosticada ni corregida.
- `observed`: la instalacion Linux puede quedar por detras del worktree; no
  afirmar que un fix esta instalado sin build/smoke posterior.

## Ledger compacto de trabajo cerrado

| ID | Resultado conservado |
|---|---|
| `GOV-00` / `REP-01` / `GOV-01` | Repo independiente y gobernanza Nini Hub creados desde cero |
| `ID-01` | Identidad de producto, package, desktop y assets migrada |
| `SCR-01` | Scripts personales Nini Hub creados con rollback legacy |
| `DB-01` | Contrato/ensayo SQLite con WAL, rollback e idempotencia |
| `DB-02` | Importacion unica a soporte Nini Hub ejecutada y validada |
| `ENG-01` | Lecturas JSON v1 machine-safe congeladas |
| `ENG-02A`, `ENG-02B`, `ENG-02C` | Tools, CRUD delete y exec stdout-clean validados por etapas |
| `PRF-01` | Discovery y lifecycle trasladados a Nini Agents |
| `RUN-01` | Launch/workspaces/terminal trasladados a Nini Agents |
| `CDX-01A`, `CDX-01B` | Transporte Codex y handoff Device Auth completados |
| `OPS-01` | Usage, Heartbeat y Activity operativos sobre perfiles Nini |
| `ENG-02` | Mutaciones/exec integrados en el checkout local del motor |
| `QA-01A` | Analyze, matriz dirigida y smoke Linux aislado verdes |
| `ACT-01` | Release Linux instalado y datos reales activados con autorizacion |
| `FIX-DB-01` | Reinicio SQLite propio sin falsa comparacion con rollback |
| `FIX-ACC-01` | Correo reconocido por Usage e inmutable en Accounts |
| `FIX-UX-USAGE-01` | Progreso y snapshots de cuotas incrementales |
| `FEAT-TERM-01` | Terminal persistente configurable despues de finalizar |
| `FIX-OPS-VIS-01` | Feedback Heartbeat/Activity inmediato y credencial explicita |
| `FIX-SCRIPT-01` | Instalador personal enlazado al compilador vigente |
| `FIX-OPS-NOISE-01` | Discovery unico y lecturas internas fuera de Activity |
| `FIX-UX-QUOTA-01` | Contador reactivo y anclas confirmadas/estimadas |

Para comandos, archivos, validaciones y exclusiones historicas consultar el
archivo de auditoria por ID. El ledger no convierte esos alcances cerrados en
autorizacion vigente.

## Reglas de mantenimiento

- Mantener una sola fraccion de Cierre activa.
- Reemplazar snapshot, riesgos y siguiente accion; no acumular narracion de
  features implementadas.
- Registrar un fix cerrado en el ledger solo si modifica compatibilidad, un gate
  o una decision operativa. El detalle vive en codigo, pruebas, indice y Git.
- No agregar inventarios volatiles, perfiles reales, tokens, contenido auth,
  dumps SQLite ni logs completos.
- Revalidar branch, HEAD, worktree, rutas y contratos antes de cada gate.
- No marcar `complete` con evidencia estatica cuando la puerta exige runtime.
- No editar el archivo historico; crear otro snapshot fechado solo si una
  auditoria futura necesita congelar contexto antes de otra compactacion.

## Siguiente accion

`QA-01B` es la unica fraccion activa del roadmap. Features y fixes separados
pueden continuar con alcance propio, pero no alteran el conteo. QA-01B requiere
entorno Windows real, alcance exacto y aprobacion antes de ejecutar. Si el
entorno no esta disponible, el estado correcto sigue siendo `12/14`, `QA-01
validating`, `CUT-01 pending`.

## Formato de relevo

```text
Estado global y HEAD observado:
Punto y estado:
Objetivo y alcance aprobado:
Archivos/contratos afectados:
Persistencia, integraciones y plataforma:
Validacion ejecutada y resultado:
Validacion no ejecutada:
Riesgos o desviaciones vigentes:
Siguiente accion y autorizacion requerida:
```
