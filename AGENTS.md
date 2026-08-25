# Instrucciones para agentes

## Producto y plataforma

- Nini Hub es una aplicacion Flutter Desktop para Linux y Windows.
- Es el sucesor independiente de MultiCLI AI y conserva su historial Git como
  linaje, no como repositorio remoto compartido.
- Administra datos locales reales, perfiles de herramientas de IA, credenciales
  controladas por cada herramienta, suscripciones, cuotas, workspaces, actividad
  y procesos.
- `nini-agents` es el motor vigente. Nini Hub es el plano de control desktop;
  no debe reimplementar dentro de Flutter el ownership del motor.
- Nombres `multi_cli_ai`, `MultiCli*`, `MULTICLI_HOME` y rutas legacy que aun
  existen son compatibilidad preservada, no identidad objetivo ni evidencia de
  una migracion activa. No retirarlos sin un alcance de compatibilidad/cutover
  aprobado.
- No tratar el proyecto como Android ni asumir capacidades fuera del escritorio.

## Lectura obligatoria

Antes de planificar o ejecutar trabajo relevante, leer en este orden:

1. `AGENTS.md`.
2. `.agents/references/architecture.md`.
3. `.agents/references/project-index.md` para localizar owners y contratos.
4. `.agents/references/product-migration.md` solo cuando el trabajo afecte
   bootstrap/rollback SQLite, compatibilidad legacy, QA de plataforma, cutover
   o deprecacion.
5. Las skills canonicas que correspondan al alcance real.

Revalidar branch, HEAD, worktree, rutas y contratos cuando difieran del snapshot
de la bitacora. El indice es un mapa de simbolos ancla, no sustituye la lectura
del codigo vigente.

## Alcance y autorizacion

- Antes de modificar codigo, documentacion, configuracion, migraciones o skills,
  investigar solo en lectura, informar el alcance y esperar aprobacion explicita.
- El alcance debe indicar objetivo, reglas, archivos, capas, contratos,
  persistencia o integraciones, exclusiones y validacion.
- La aprobacion cubre solo lo informado. Si aparece otro archivo, capa, contrato,
  schema, proceso, plataforma, permiso del sistema o efecto secundario, detenerse
  y solicitar ampliacion.
- Analisis, diagnostico, explicacion o plan no autorizan implementar.
- No mezclar una feature o fix con compatibilidad legacy, QA o cutover no
  aprobados.
- Modificar `/home/nini/IdeaProjects/nini-agents`,
  `/home/nini/StudioProjects/multi_cli_ai`, Codexporter, datos reales o remotos
  externos requiere alcance y aprobacion separados.

## Skills canonicas

Las cinco skills vigentes viven exclusivamente en `.agents/skills/`:

- `nini-hub-feature-integral`: features o cambios reales en dos o mas capas.
- `nini-hub-domain-application`: entidades, reglas, casos de uso, puertos y
  fallos.
- `nini-hub-data-desktop-integrations`: Drift, SQLite, filesystem, procesos,
  terminales, `nini-agents` y Codex app-server.
- `nini-hub-presentation-flutter-desktop`: Riverpod, estado, vistas, widgets y
  dialogs desktop.
- `nini-hub-diagnostico-incidentes`: causa desconocida, lentitud, bloqueo,
  concurrencia o resultado inconsistente sin implementar el fix.

Activar solo las skills necesarias. La orquestadora no reemplaza las skills de
capa. Ante un posible bug, diagnosticar antes de implementar; si afecta
compatibilidad o Cierre, registrar `preserve`, `separate_fix` o `blocked`.

## Arquitectura oficial

```text
presentation -> application -> domain
data --------------------------> domain
app -> composicion de implementaciones concretas
```

- `domain` es Dart puro: no Flutter, Riverpod, Drift, `dart:io`, plugins ni
  clientes externos.
- `application` coordina casos de uso mediante puertos de Domain.
- `data` implementa puertos y contiene persistencia, mapeos e integraciones.
- `presentation` contiene estado visual y UI; no importa Data, Drift,
  filesystem, procesos ni gateways concretos.
- `app` contiene composition root, shell, tema y navegacion; no reglas.
- `core/database` es infraestructura Data compartida. Solo Data y App pueden
  importarla.
- Crear solo artefactos con responsabilidad real. No completar plantillas con
  interfaces, DTO, mappers o estados vacios.

## Compatibilidad y cierre

- La implementacion principal de identidad, datos, motor, perfiles y operacion
  ya esta migrada. La bitacora operativa conserva el roadmap formal `12/14`, con
  QA Windows y cutover/deprecacion aun pendientes.
- El archivo historico de migracion es auditoria, no lectura ordinaria ni fuente
  de autorizacion. No acumular alli nuevas narraciones de features.
- Mantener una sola fraccion de Cierre activa y una puerta verificable.
- Conservar datos, IDs, nulabilidad, UTC, procesos, timeouts, perfiles,
  workspaces, settings y rollback aplicables.
- Registrar en la bitacora solo cambios del snapshot, decisiones, riesgos,
  compatibilidad o gates. Los detalles de features viven en codigo, pruebas e
  indice.
- No presentar una capacidad de `nini-agents` como distribuida solo porque
  exista en el checkout local. Verificar implementacion, pruebas y release real.

## Dominio y aplicacion

- No exponer rows Drift fuera de Data.
- Definir puertos solo para limites reales: persistencia, filesystem, reloj,
  procesos, terminales, `nini-agents` o proveedores.
- Usar casos de uso para acciones, reglas u orden de efectos; mantener calculos
  simples en entidades o policies.
- Un flujo transversal vive en Application de la feature propietaria de la
  accion visible y consume puertos de otras features, nunca sus controllers.
- Representar fallos esperables y aplicaciones parciales con tipos de Domain o
  Application.
- Mantener IDs, nulabilidad, dinero en unidades menores y fechas UTC
  consistentes.

## Datos e integraciones desktop

- Tratar SQLite como datos reales. Conservar schema, ruta de upgrade y rollback.
- La importacion historica fue unica e idempotente. Nini Hub usa su archivo
  SQLite propio; no volver a compartirlo vivo con MultiCLI AI.
- Si existe WAL, no copiar solamente el archivo `.sqlite`. Validar consistencia,
  destino ausente/existente, repeticion e interrupcion.
- No editar `app_database.g.dart`; regenerarlo solo dentro de un cambio de schema
  autorizado.
- Evitar N+1, tablas completas para contar, filtrado amplio en memoria,
  consultas duplicadas y recargas globales.
- Ejecutar procesos con ejecutable y argumentos separados; validar rutas,
  working directory, environment, timeout, cancelacion, exit code y salida.
- Redactar tokens, credenciales, rutas privadas y contenido sensible antes de
  persistir o mostrar logs.
- Encapsular Linux y Windows en adaptadores. No dispersar `Platform.is...` por
  Domain o Presentation.
- `nini-agents` debe exponer contratos machine-safe versionados para consumo de
  Nini Hub; stdout de un transporte JSON-RPC no admite preambulos humanos.

## Presentation Flutter Desktop

- Usar Riverpod con un controller/notifier por feature y estado inmutable.
- Una vista observa solo el estado necesario; una operacion local no recarga
  dominios ajenos.
- Disenar para teclado, mouse y ventanas redimensionables; referencia minima
  900x600.
- Usar constraints, `LayoutBuilder` y scroll para evitar overflow.
- Correlacionar operaciones asincronas para impedir que una respuesta antigua
  reemplace estado nuevo.
- Presentation traduce fallos tipados; no interpreta Drift o JSON-RPC.

## Git, repositorios y scripts

- Esta repo conserva el historial de MultiCLI AI y usa un remoto Nini Hub nuevo
  e independiente.
- No agregar como `origin` el repositorio histórico ni empujar a su remoto.
- No revertir, borrar, stagear, des-stagear, commitear o empujar sin instruccion
  expresa.
- Conservar cambios concurrentes y no modificar artefactos generados o de build.
- `scripts_personales/` esta ignorado y se conserva fuera de Git salvo
  autorizacion expresa. Validar sus permisos y contenido durante cada cambio.

## Validacion

- No ejecutar `flutter build`, instaladores ni builds nativos por defecto.
- Despues de modificar Dart: formato de archivos tocados, analisis focalizado y
  pruebas unitarias/widget dirigidas.
- Ejecutar `dart run build_runner` solo cuando la generacion forme parte del
  alcance aprobado.
- Ejecutar `test/architecture/import_boundaries_test.dart` cuando cambien
  limites o composicion.
- Para skills, ejecutar `quick_validate.py` cuando exista; si no esta disponible,
  registrar la limitacion y comprobar frontmatter, disparadores, nombres,
  rutas, contradicciones y secretos con validaciones equivalentes.
- No afirmar que compila, migra o funciona en Linux/Windows sin evidencia.

## Seguimiento y cierre

Al cerrar una fraccion informar:

1. **Resumen de implementacion:** resultado funcional.
2. **Antes y despues:** cambio de flujo, dependencias, costo o comportamiento.
3. **Detalle tecnico:** archivos, contratos, persistencia, integraciones y flujo
   reactivo.
4. **Validacion y pendientes:** evidencia, validaciones no ejecutadas, riesgos y
   pruebas manuales.

Actualizar la bitacora en el mismo delta solo cuando cambien compatibilidad,
riesgos o gates. El relevo debe indicar sin ambiguedad que esta aprobado, que
esta prohibido y cual es la siguiente accion.
