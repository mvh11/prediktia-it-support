# Contrato del lector prospectivo — `prediktia_prospective_reader`

```
FASE: M5.9C
ESTADO: APROBADO (contrato) — creación del rol DIFERIDA
READER_CREATION: DEFERRED_UNTIL_0008
NEON_ENDPOINT_CLASSIFICATION: UNRESOLVED
ÚLTIMA ACTUALIZACIÓN: 2026-10-09 (IT_SUPPORT_AGENT)
```

Nada de este documento se ha aplicado en Neon. Crear el rol, los GRANT y los
ajustes de rol siguen siendo **Chief Gate**.

Evidencia: [`../evidence/M59C-LB-001-result.md`](../evidence/M59C-LB-001-result.md),
[`../evidence/M59C-prospective-reader-prerequisites.md`](../evidence/M59C-prospective-reader-prerequisites.md),
[`../evidence/M59C-endpoint-classification.md`](../evidence/M59C-endpoint-classification.md).

## 1. Allowlist de runtime congelada

Decisión de ruta de lectura de la aplicación: **confirmada por Modular**
(entrada para TI; TI no la modifica ni la reinterpreta). `SELECT` únicamente
sobre estas seis tablas del esquema `public`:

```
FROZEN_RUNTIME_ALLOWLIST:
- public.fixture_observations
- public.fixtures
- public.fixture_statistics_observations
- public.statistics_runs
- public.team_provider_mappings
- public.seasons
```

Cualquier objeto adicional requiere actualizar este contrato y una nueva
aprobación.

## 2. Fuera de la autoridad de runtime

```
NOT_RUNTIME_AUTHORITY:
- public.competitions
- public.alembic_version
- objetos de etiquetas/resultados
- secuencias
- tablas de catch-up/backlog
```

## 3. Decisión sobre PUBLIC TEMP

```
PUBLIC_TEMP_DECISION:
- PUBLIC TEMP = YES aceptado como capacidad heredada, local a la sesión
- no se revoca TEMP a PUBLIC
- no se declara STRICT_NO_TEMP
- el runtime no debe depender de tablas temporales
```

En consecuencia, el lector **podrá** crear tablas temporales de sesión (heredado
de PUBLIC, desaparecen al cerrar la sesión); eso no es una escritura
persistente. Ninguna evidencia ni informe debe afirmar que el
lector carece de TEMP.

## 4. Creación del rol

```
READER_CREATION: DEFERRED_UNTIL_0008
```

`public.fixture_observations` la crea la migración Alembic `0008`, que aún no
existe en la base auditada (`APPLICATION_MIGRATIONS: HOLD`). El rol no se crea
hasta que `0008` esté aplicada y la clasificación del endpoint esté resuelta.

## 5. Propuesta final del rol (futura, no aplicada)

```
FINAL_FUTURE_ROLE_PROPOSAL:
- CONNECT solo a la base de producción exacta
- USAGE en el esquema public
- SELECT en las seis tablas de runtime exactas (§1)
- default_transaction_read_only = on (a nivel de rol)
- sin membresías
- sin pg_read_all_data
- sin privilegios de escritura persistentes
```

Notas de implementación para la futura solicitud al Chief (derivadas de la
auditoría M59C-LB-001):

- Crear el rol por SQL, no desde la consola del proveedor; la consola suele
  añadirlo al rol administrativo del proveedor, que hereda `pg_write_all_data`.
- Verificar después de crearlo que sus membresías efectivas estén vacías.
- No hay default privileges para el rol owner de la aplicación: los GRANT son
  por tabla y exactos; tablas nuevas **no** se conceden automáticamente (es lo
  deseado con una allowlist congelada).
- `default_transaction_read_only` es una defensa de sesión, no un límite de
  privilegio: el límite real son los GRANT exactos.
- No hay RLS en la base; el control de acceso es solo por privilegios.

## 6. Prerrequisitos abiertos

1. Aplicar `0008` en producción (gate del Chief; dueños Modular/DI).
2. Clasificar el endpoint auditado con una correspondencia directa
   (consola/API de Neon o comparación con el destino esperado del entorno
   `production` de GitHub).
3. Redactar la solicitud GRANT exacta para el Chief (qué, por qué, SQL,
   alcance, rollback, evidencia).
