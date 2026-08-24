# Arquitectura de MultiCLI AI

## Contenido

- Objetivo y dependencias
- Estructura y responsabilidades
- Flujo entre capas
- Estado reactivo
- Persistencia e integraciones
- Contratos y errores
- Rendimiento y migracion

## Objetivo y dependencias

MultiCLI AI adopta una Clean Architecture ligera por feature para Flutter Desktop. Debe aislar Drift, filesystem, procesos, terminales y proveedores externos sin crear artefactos ceremoniales.

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
Drift | filesystem | Process | terminal | Multi CLI | Codex JSON-RPC
```

| Capa | Puede depender de | No puede depender de |
|---|---|---|
| `domain` | Dart puro | Flutter, Riverpod, Drift, `dart:io`, plugins |
| `application` | `domain` | Presentation, Drift, gateways concretos |
| `data` | `domain`, infraestructura | Presentation, controllers |
| `presentation` | `application`, modelos visibles de dominio | Drift, `data`, filesystem, procesos |
| `app` | Todas, solo para composicion | Reglas y consultas directas |

`core` contiene solo capacidades realmente compartidas, no codigo sin propietario.

Durante la transicion, `core/database` se considera infraestructura Data compartida. Puede ser importada por implementaciones Data y por el composition root, pero nunca por Domain o Presentation. Esta excepcion evita mover toda la base legacy como efecto lateral de una feature.

## Estructura y responsabilidades

```text
lib/
  app/
    providers.dart
    multi_cli_ai_app.dart
    shell/
  core/
    database/
    platform/
    errors/
    utils/
  features/{feature}/
    domain/
      entities/
      repositories/
      services/
      failures/
    application/
      use_cases/
      commands/
    data/
      datasources/
      repositories/
      gateways/
      mappers/
    presentation/
      controllers/
      state/
      views/
      widgets/
      dialogs/
```

Crear solo los folders y archivos requeridos. Una feature simple no necesita reproducir todo el arbol.

### Domain

- Modelar perfil, cuenta, workspace, suscripcion, cuota y actividad.
- Mantener invariantes y decisiones independientes de tecnologia.
- Definir puertos y fallos esperables.
- No contener rows, companions, `BuildContext`, `AsyncValue` o `Platform`.

### Application

- Exponer acciones: crear perfil, refrescar uso, lanzar agente o guardar suscripcion.
- Coordinar entidades, puertos, transacciones logicas y orden de efectos.
- Recibir commands pequenos o tipos del dominio y devolver resultados tipados.
- No crear un caso de uso para un getter o calculo trivial.

### Data

- Implementar puertos, queries Drift, mapeos y migraciones.
- Adaptar filesystem, Multi CLI, Codex app-server, procesos y terminales.
- Traducir errores tecnicos a fallos del contrato.
- Mantener secretos y salidas sensibles fuera de contratos visibles.

### Presentation

- Renderizar UI y recoger acciones.
- Mantener view state inmutable por feature.
- Invocar casos de uso mediante Riverpod.
- Correlacionar loading, progreso, error y cancelacion.
- Traducir fallos tipados a mensajes y acciones.

### App

- Conectar puertos con implementaciones en providers.
- Configurar `ProviderScope`, tema, navegacion, shell y ciclo de vida.
- No acumular todos los dominios en un controller global.

## Flujo entre capas

```text
LaunchAgentDialog
  -> LaunchAgentController.launch(profileId, workspaceId)
  -> LaunchAgent.execute(...)
  -> ProfileRepository.findById(...)
  -> WorkspaceRepository.findById(...)
  -> AgentLauncher.launch(...)
  -> MultiCliAgentLauncher
  -> ProcessRunner
```

El caso de uso valida disponibilidad, perfil y workspace. El adaptador decide ejecutable, argumentos y terminal. Presentation solo muestra progreso o fallo.

## Estado reactivo

```text
AccountsController   -> AccountsState
UsageController      -> UsageState
WorkspacesController -> WorkspacesState
ActivityController   -> ActivityState
SettingsController   -> SettingsState
```

- Observar providers focalizados y usar estado inmutable.
- Usar streams Drift para lecturas reactivas.
- Asociar cada respuesta asincrona con la solicitud vigente.
- No usar `reload()` global como sincronizacion ordinaria.
- No reintroducir una fachada o controller global para coordinar dominios migrados.

## Persistencia e integraciones

- Rows y companions permanecen en Data y se mapean a entidades.
- Agrupar consultas, seleccionar solo datos necesarios y usar transacciones.
- Incrementar `schemaVersion` y definir `onUpgrade` compatible.
- Separar ejecutable y argumentos; validar rutas y working directory.
- Controlar timeout, cancelacion, exit code, stdout/stderr y redaccion.
- Encapsular Linux y Windows tras puertos comunes.
- Modelar capacidades de proveedor y mantener JSON-RPC dentro del adaptador.

## Contratos y errores

- Preferir IDs y value objects estables.
- Mantener dinero en unidades menores y fechas UTC.
- Distinguir ausente, `null`, vacio y default.
- Usar fallos tipados para condiciones esperables.
- No exponer excepciones tecnicas como contrato UI.
- Comunicar features mediante casos de uso y puertos, no controllers ajenos ni event bus global.
- Ubicar un flujo transversal en Application de la feature propietaria de la accion visible. Esa feature consume puertos de los otros dominios.
- Mantener archivos, clases, metodos y estados tecnicos en ingles; reservar espanol para textos visibles.

## Rendimiento y migracion

- Evitar queries por perfil dentro de loops y cargas completas para ultimo registro o conteo.
- Filtrar, ordenar, agregar y limitar en SQLite.
- No reconstruir calendario, cuentas, logs y workspaces tras una operacion local.
- Paginar o limitar historiales crecientes.

Migrar incrementalmente, una fraccion aprobada a la vez. Los owners de feature
reemplazan fachadas compartidas sólo después de caracterizar sus consumidores y
el composition root conecta las implementaciones concretas. Las excepciones de
imports existentes se retiran o se congelan en una baseline explícita antes de
activar un guard automático.

Cada corte debe conservar comportamiento y datos.

## Criterios de revision

- Domain puede probarse sin Flutter, Drift ni filesystem.
- Presentation no importa Data, database o clientes concretos.
- Data no conoce controllers o widgets.
- El caso de uso expresa accion y orden de efectos.
- Rows Drift no cruzan el limite de Data.
- El estado se actualiza sin recargas globales innecesarias.
- Procesos, rutas, secretos, timeouts y plataforma estan controlados.
- Formato, analisis y pruebas focalizadas cubren el alcance modificado.
- `test/architecture/import_boundaries_test.dart` verifica automáticamente los
  límites de imports/exports en `lib/features`; su baseline estricta contiene
  únicamente las excepciones Presentation -> App existentes y debe reducirse
  cuando una de ellas se retire.
