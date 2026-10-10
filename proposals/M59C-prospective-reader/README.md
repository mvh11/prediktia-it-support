# M5.9C — Propuesta SQL del lector prospectivo (mínimo privilegio)

```
ESTADO: PREPARACIÓN — NO EJECUTADO
TARGET: PRODUCCIÓN (base exacta pasada como -v target_db=… en la ejecución)
RUNTIME_ALLOWLIST_COUNT: 6
0008_REQUIRED_BEFORE_EXECUTION: YES
READER_CREATION: DEFERRED_UNTIL_0008
AUTORIZACIÓN NECESARIA: CHIEF_ARCHITECT (CREATE ROLE / GRANT / ALTER ROLE / REVOKE / DROP ROLE)
```

Contrato: [`../../docs/prospective-reader-contract.md`](../../docs/prospective-reader-contract.md).

| Archivo | Qué hace | Modifica |
|---------|----------|----------|
| `01-create.sql` | Precondiciones (base exacta, `0008`, 6 tablas, roles ausentes) → crea `prediktia_prospective_ro` (NOLOGIN) y `prediktia_prospective_reader` (LOGIN), GRANT exactos, membresía única, `default_transaction_read_only = on` | Sí (una transacción) |
| `02-validate-admin.sql` | Validación como admin: atributos, membresías, roles amplios, CONNECT/CREATE/TEMP, USAGE, allowlist, fuera de allowlist, secuencias, ownership, ajustes de rol, PUBLIC TEMP | No (`READ ONLY` + `ROLLBACK`) |
| `03-validate-reader.sql` | Validación conectado como el lector: identidad, `default_transaction_read_only` efectivo, SELECT con `LIMIT 0` en las 6 tablas, sin SELECT fuera | No (sin filas de negocio; sin pruebas de escritura) |
| `04-rollback.sql` | REVOKE de los grants explícitos, REVOKE de la membresía, comprobación de dependencias → STOP si existen; DROP de ambos roles sin CASCADE | Sí (una transacción) |

## Lo que la propuesta concede

- `CONNECT` en la base de producción exacta.
- `USAGE` en el esquema `public`.
- `SELECT` en exactamente: `public.fixture_observations`, `public.fixtures`,
  `public.fixture_statistics_observations`, `public.statistics_runs`,
  `public.team_provider_mappings`, `public.seasons`.
- `default_transaction_read_only = on` en el rol de login (defensa en
  profundidad; el límite real son los GRANT).

Todos los privilegios van al rol `_ro`; el lector solo tiene la membresía en
`_ro` (`INHERIT TRUE, SET FALSE, ADMIN FALSE`).

## Lo que la propuesta NO concede

`pg_read_all_data`, `pg_write_all_data`, el rol administrativo del proveedor,
membresía en el rol de aplicación, `CREATE` en base o esquema, privilegios de
secuencia, escritura, nada sobre `public.alembic_version`, ni
`ALTER DEFAULT PRIVILEGES`. PUBLIC no se modifica: `TEMP` heredado se acepta
(no se declara STRICT_NO_TEMP).

## Secuencia de ejecución futura (solo con autorización del Chief)

1. Confirmar que `0008` está aplicada en producción.
2. `psql -X -v ON_ERROR_STOP=1 -v target_db=<BD_PRODUCCION> -f 01-create.sql -d "$DSN_ADMIN"`
3. En una sesión `psql` interactiva como admin: `\password prediktia_prospective_reader`
   (pide la contraseña sin eco y envía solo el hash SCRAM; la contraseña no
   queda en archivos, historial ni logs de sentencias). Equivalente no
   interactivo: `PASSWORD '<PASSWORD_SUPPLIED_SECURELY_AT_EXECUTION>'`.
   Guardar la contraseña solo en el gestor de secretos del emisor.
4. `02-validate-admin.sql` → todos los resultados deben coincidir con lo
   esperado indicado en cada bloque.
5. `03-validate-reader.sql` con la credencial del lector.
6. Si algo no coincide → `04-rollback.sql`.

### Guardas: salida distinta de cero

Toda guarda fallida de `01-create.sql` y `04-rollback.sql` imprime `STOP: …` y
termina `psql` con **código de salida 3** (un bloque `DO` sin efectos lanza una
excepción `M59C_GUARD_FAILED: …` y `ON_ERROR_STOP` aborta; `psql` no admite
código en `\quit`). La automatización debe tratar cualquier código ≠ 0 como
fallo.

`01-create.sql` (todas antes de cualquier `BEGIN`; cero cambios):

| Guarda | Condición |
|--------|-----------|
| target_db | falta `-v target_db=…` |
| base exacta | `current_database()` ≠ `target_db` |
| 6/6 tablas | cada una de las seis tablas de la allowlist debe existir como **tabla** (`relkind` r/p) en `public`; si falta alguna, se listan por nombre. `fixture_observations` sola no basta |
| roles ausentes | ya existe `prediktia_prospective_ro` o `prediktia_prospective_reader` |

`04-rollback.sql`: falta `target_db`, base incorrecta (antes de `BEGIN`), o
dependencias restantes (dentro de la transacción: la excepción la aborta y no
se confirma nada).

## Notas de seguridad

- Crear los roles **por SQL**, no desde la consola del proveedor: la consola
  suele añadir los roles al rol administrativo del proveedor (que hereda
  `pg_write_all_data`). `02-validate-admin.sql` (V03/V04) lo detecta.
- En PG16+ el rol que ejecuta `CREATE ROLE` recibe una membresía implícita
  `ADMIN` (sin INHERIT ni SET) sobre los roles creados. Es la dirección
  admin → lector y no da privilegios al lector (V02b, informativo).
- El proveedor puede exigir contraseñas de alta entropía para roles creados
  por SQL; usar una contraseña generada aleatoriamente.
- `CONNECTION LIMIT 5` acota el impacto de una credencial filtrada; ajustable.
- `default_transaction_read_only` puede desactivarse en sesión por el propio
  lector; por eso no es el límite de privilegio.
- Tablas futuras **no** se conceden automáticamente (sin default privileges):
  es lo deseado con una allowlist congelada.
- Rollback: cerrar antes las sesiones del lector (decisión del operador).
  Si quedan dependencias (p. ej. objetos de su propiedad en cualquier base), el
  script hace ROLLBACK y se detiene sin forzar.

## Verificación de la propuesta

Ensayada el 2026-10-09 en un PostgreSQL 18 local desechable (contenedor sin
red expuesta, eliminado al terminar; **no Neon**), con un owner no superusuario
con `CREATEROLE` que imita al rol de aplicación. "Sin cambios" = huella md5 de
roles `prediktia*`, ACL de base, ACL de esquema, ACL de las tablas de `public`,
membresías y ajustes de rol idéntica antes y después.

| Caso | Código | Sin cambios |
|------|--------|-------------|
| create: falta `target_db` | 3 | sí |
| create: base incorrecta | 3 | sí |
| create: falta cada una de las 6 tablas (6 casos, uno por tabla) | 3 | sí |
| create: `seasons` existe como vista, no tabla | 3 | sí |
| create: `_ro` ya existe | 3 | sí |
| create: `_reader` ya existe | 3 | sí |
| create: camino correcto | 0 | — (crea roles y grants) |
| validate-admin | 0 | todos los bloques según lo esperado (V07: 6/6 `ok=t`) |
| validate-reader | 0 | `default_transaction_read_only=on`; 6 SELECT `LIMIT 0`; ningún SELECT fuera |
| rollback: falta `target_db` | 3 | sí |
| rollback: base incorrecta | 3 | sí |
| rollback: dependencia (objeto propiedad del lector) | 3 | sí (roles, grants y membresía intactos) |
| rollback: limpio | 0 | roles eliminados; ACL de base y esquema idénticas a las originales |

Nota del rollback limpio: tras GRANT + REVOKE, las seis tablas quedan con ACL
explícita solo del owner en lugar de `NULL`; es equivalente en privilegios
efectivos al valor por defecto (comportamiento estándar de PostgreSQL).
