# Instrucciones para agentes

## Producto y plataforma

- MultiCLI AI es una aplicacion Flutter Desktop para Linux y Windows.
- Administra datos locales reales, perfiles de CLI, credenciales controladas por cada herramienta, suscripciones, cuotas, workspaces y procesos.
- No tratar el proyecto como Android ni asumir capacidades fuera del escritorio.
- Conservar compatibilidad con SQLite, perfiles, rutas y configuracion existentes salvo autorizacion expresa.

## Alcance y autorizacion

- Antes de modificar codigo, documentacion, configuracion, migraciones o skills, investigar solo en lectura, informar el alcance y esperar aprobacion explicita.
- El alcance debe indicar objetivo, reglas, archivos, capas, contratos, persistencia o integraciones, exclusiones y validacion.
- La aprobacion cubre solo lo informado. Si aparece otro archivo, capa, contrato, migracion, proceso, permiso del sistema o efecto secundario, detenerse y solicitar ampliacion.
- Analisis, diagnostico, explicacion o plan no autorizan implementar.
- No mezclar una feature o fix con una migracion arquitectonica amplia no aprobada.

## Skills canonicas

Las skills vigentes viven exclusivamente en `.agents/skills/`:

- `multi-cli-ai-migrate-architecture`: migraciones legacy incrementales por fracciones, equivalencia funcional y continuidad entre agentes.
- `multi-cli-ai-feature-integral`: features nuevas o cambios reales en dos o mas capas.
- `multi-cli-ai-domain-application`: entidades, reglas, casos de uso, puertos y fallos.
- `multi-cli-ai-presentation-flutter-desktop`: Riverpod, estado, vistas, widgets y dialogs.
- `multi-cli-ai-data-desktop-integrations`: Drift, SQLite, filesystem, procesos, terminales, Multi CLI y Codex app-server.
- `multi-cli-ai-diagnostico-incidentes`: bugs, lentitud, bloqueos o resultados inconsistentes sin implementar el fix.

Activar solo las skills relevantes. La orquestadora no reemplaza las skills de capa.

Para una migracion arquitectonica legacy, activar primero `multi-cli-ai-migrate-architecture`, leer `.agents/references/architecture.md` y `.agents/references/architecture-migration.md`, trabajar una sola fraccion y consumir las skills de capa que correspondan. Si aparece un posible bug o no esta claro si la logica vigente es intencional, activar `multi-cli-ai-diagnostico-incidentes` y separar el diagnostico de cualquier fix.

## Arquitectura oficial

Leer `.agents/references/architecture.md` antes de crear una feature o modificar limites entre capas.

```text
presentation -> application -> domain
data --------------------------> domain
app -> composicion de implementaciones concretas
```

- `domain` es Dart puro: no Flutter, Riverpod, Drift, `dart:io`, plugins ni clientes externos.
- `application` coordina casos de uso mediante puertos del dominio.
- `data` implementa puertos y contiene persistencia, mapeos e integraciones.
- `presentation` contiene estado visual y UI; no importa `data`, Drift ni gateways concretos.
- `app` contiene composition root, shell, tema y navegacion, no reglas de negocio.
- Durante la transicion, `core/database` es infraestructura Data compartida. Solo Data y el composition root pueden importarla; Domain y Presentation no.
- Crear solo artefactos con responsabilidad real; no completar plantillas con interfaces, DTO, mappers o estados vacios.
- Migrar legacy de forma incremental y conservar contratos fuera del alcance.

## Dominio y aplicacion

- No exponer filas generadas por Drift fuera de `data`.
- Definir puertos solo para limites reales: persistencia, filesystem, reloj, procesos, terminales, Multi CLI o proveedores.
- Usar casos de uso para acciones, reglas o coordinacion; mantener calculos simples en su entidad o politica.
- Un flujo que cruza features vive en Application de la feature propietaria de la accion visible y consume puertos de las demas; nunca importa sus controllers o repositories concretos.
- Representar fallos esperables con tipos del dominio o aplicacion.
- Mantener IDs, nulabilidad, dinero en unidades menores y fechas UTC consistentes.

## Datos e integraciones desktop

- Tratar migraciones Drift como cambios sobre datos reales y conservar una ruta de upgrade compatible.
- No editar `app_database.g.dart`; regenerarlo solo dentro de un alcance autorizado.
- Evitar N+1, tablas completas para contar, filtrado amplio en memoria, consultas duplicadas y recargas globales.
- Preferir consultas acotadas, lotes, transacciones y streams `watch()` para estado reactivo.
- Ejecutar procesos con ejecutable y argumentos separados; validar rutas, timeout, salida y capacidades por plataforma.
- Redactar tokens, credenciales y contenido privado antes de persistir o mostrar logs.
- Encapsular Linux/Windows en adaptadores; no dispersar `Platform.is...` por domain o presentation.

## Presentation Flutter Desktop

- Usar Riverpod con un controller/notifier por feature y estado inmutable.
- Una vista observa solo el estado necesario; una operacion local no recarga dominios ajenos.
- Disenar para teclado, mouse y ventanas redimensionables. La referencia minima actual es 900x600.
- Usar constraints, `LayoutBuilder` y scroll para evitar overflow; no asumir patrones Android.
- Correlacionar operaciones asincronas para que una respuesta antigua no reemplace estado nuevo.
- Presentation traduce fallos tipados; no interpreta excepciones Drift o JSON-RPC directamente.

## Simplicidad y compatibilidad

- Respetar el patron existente mientras un modulo no haya sido migrado.
- No agregar dependencias, generadores o frameworks sin necesidad y autorizacion.
- No extraer helpers para logica corta usada dos veces o menos.
- Aplicar la arquitectura oficial a features nuevas; usar fachadas temporales para legacy.
- No ampliar `DashboardController` con nuevos dominios si la feature puede tener controller propio.
- Usar ingles para archivos, clases, metodos y estados tecnicos. Usar espanol para textos y mensajes visibles al usuario.

## Git y workspace

- No revertir, borrar, stagear, des-stagear, commitear ni empujar sin instruccion expresa.
- Trabajar con cambios concurrentes sin eliminarlos.
- No modificar artefactos de build, generados o helpers personales fuera del alcance.

## Validacion

- No ejecutar `flutter build`, instaladores ni builds nativos por defecto.
- Despues de modificar codigo, ejecutar sin aprobacion adicional formato de los archivos tocados, analisis estatico focalizado y pruebas unitarias/widget dirigidas al alcance.
- Ejecutar `dart run build_runner` solo cuando la generacion forme parte del alcance aprobado.
- No ejecutar suites completas cuando una prueba focalizada entregue evidencia suficiente.
- Un control automatico de imports no puede introducirse fallando contra legacy: definir una baseline explicita o agregarlo durante la primera migracion de capa.
- No afirmar que compila, migra o funciona en Linux/Windows sin evidencia.

## Seguimiento y cierre

Al ejecutar un plan, mantener pasos, decisiones, desviaciones y pendientes. Al cerrar incluir:

1. **Resumen de implementacion:** resultado funcional.
2. **Antes y despues:** cambio en flujo, dependencias, costo o comportamiento.
3. **Detalle tecnico:** archivos, contratos, persistencia, integraciones y flujo reactivo.
4. **Validacion y pendientes:** evidencia, validaciones no ejecutadas, riesgos y pruebas manuales.

Explicar recargas globales, consultas por fila, filtrado en memoria o contratos de infraestructura que hayan sido eliminados.
