---
name: nini-hub-data-desktop-integrations
description: Crear, corregir o revisar Data e integraciones desktop de Nini Hub. Usar al tocar Drift/SQLite, migraciones, repositories, mappers, filesystem, procesos, terminales Linux/Windows, nini-agents, Codex app-server, logs, timeouts o credenciales; no usar para reglas puras o UI.
---

# Nini Hub Data Desktop Integrations

## Proposito

Encapsular persistencia e integraciones de escritorio tras puertos estables sin perder datos, rendimiento ni seguridad.

## Alcance del proyecto

- Implementaciones bajo `lib/features/{feature}/data`, infraestructura compartida en `lib/core/database` y `lib/core/process`, y adaptadores de plataforma autorizados.
- SQLite schema v2 ya importada al soporte propio de Nini Hub; ownership `NHUB`, rutas/rollback legacy, WAL, perfiles, procesos y contratos machine-safe de nini-agents siguen siendo compatibilidad protegida.

## Fuentes

- Leer `AGENTS.md`, `.agents/references/architecture.md` y las secciones de persistencia e integraciones de `.agents/references/project-index.md`.
- Leer `.agents/references/product-migration.md` solo para bootstrap/rollback SQLite, QA Windows o cutover; el historial detallado no es contexto ordinario.
- Contrastar schema, upgrade y datos solo en el entorno autorizado; nunca inferir una migracion desde el modelo generado.

## Patrones del proyecto

- `lib/features/profiles/data/drift_profile_repository.dart` - `DriftProfileRepository`: recibe `AppDatabase`, limita la query y mapea rows dentro de Data.
- `lib/core/process/process_runner.dart` - `ProcessRunner`: ejecutable y argumentos separados, timeout, redaccion y Activity persistida.
- `lib/core/database/app_database.dart` - `AppDatabase`: tablas Drift, schemaVersion y estrategia de upgrade vigente.
- `lib/core/database/legacy_database_migrator.dart` - `LegacyDatabaseMigrator`: importacion historica, ownership del destino y rollback sin compartir una SQLite viva.

## Flujo

1. Caracterizar rutas, schema, queries, procesos, environment, stdout/stderr, timeout y diferencias Linux/Windows.
2. Delimitar contrato, transaccion, idempotencia, rollback y datos reales afectados.
3. Implementar el adapter o repository sin filtrar tecnologia fuera de Data.
4. Evitar N+1, cargas completas, filtros amplios en memoria, writes parciales no modelados y logs sensibles.
5. Validar con SQLite temporal o fixture y dobles de proceso antes de cualquier runtime real.

## Reglas

- No editar `app_database.g.dart`; regenerar solo cuando un schema autorizado lo requiera.
- No copiar solo el archivo SQLite principal cuando existe WAL activo ni compartir un archivo vivo entre aplicaciones.
- No escribir tokens, credenciales o contenido privado en logs, bitacoras, fixtures o mensajes visibles.

## Validacion

- Aplicar `dart format`, `flutter analyze` focalizado y pruebas Data dirigidas.
- Validar migraciones SQLite con origen, destino existente, repeticion e interrupcion segura.
- Registrar por separado smoke Linux y evidencia runtime Windows; no ejecutar builds nativos por defecto.

## Autoevaluacion

- La ruta de upgrade conserva todos los datos y permite rollback?
- Ejecutable, argumentos, environment, timeout, salida y redaccion estan controlados por plataforma?
