# M59C-LB-001 — Resultado de auditoría metadata (LOCAL_BRIDGE) — versión pública saneada

```
AGENT_ID: IT_SUPPORT_AGENT
EXECUTION_MODE: LOCAL_BRIDGE
TASK_ID: M59C-LB-001
EXECUTED_AT_UTC: 2026-10-09
IT_REPO_HEAD: 0230a2a37d7d3400a5f53729339d99eeb5d20c01
SCRIPT_BLOB: b6c7ee236207dc43b0696e1696ebf50084bb5559
RESULT: PASS
DATABASE_CLASS: Neon PostgreSQL gestionado, base de aplicación PREDIKTIA (conexión vía pooler)
POSTGRES_VERSION: 18
CREDENTIAL_CLASS: OWNER_ADMIN
TX_READ_ONLY: on
EXIT_CODE: 0
ROLLBACK_REACHED: YES
CHANGE_MADE: NO
APPLICATION_DATA_QUERIED: NO
SECRETS_EXPOSED: NO
```

## 1. Metodología

- Ejecución única de `scripts/read-only/neon_privilege_audit.sql` (sin
  modificar; blob verificado) con cliente `psql` 16 en la estación local.
- Credencial local existente usada como entrada opaca en memoria; nunca
  impresa ni guardada en este repositorio.
- Toda la ejecución dentro de `BEGIN TRANSACTION READ ONLY ... ROLLBACK`;
  `tx_read_only = on` confirmado; sin `ERROR`/`FATAL`.
- Solo catálogos del sistema; ninguna fila de tablas de aplicación.
- Un intento previo de invocación no ejecutó ninguna sentencia (orden de
  argumentos de `psql` en Windows); la auditoría se ejecutó una sola vez.
- La salida cruda completa permanece solo en la estación local, fuera de
  cualquier repositorio. Esta versión pública omite identificadores de
  endpoint, nombres de roles internos del proveedor, inventario de objetos y
  estimaciones de filas.

## 2. Conclusiones

| Control | Resultado |
|---------|-----------|
| Clase de la credencial de la aplicación | **OWNER_ADMIN**: crea roles y bases, salta RLS, es owner de la base y de todos los objetos de aplicación, y es miembro del rol administrativo del proveedor |
| Privilegios amplios heredados | **Sí**: por el rol administrativo del proveedor hereda `pg_read_all_data` y `pg_write_all_data` (además de `pg_monitor`, `pg_maintain`, `pg_signal_backend`) |
| PUBLIC CONNECT en la base | **YES** |
| PUBLIC TEMP en la base | **YES** |
| PUBLIC CREATE en la base | NO |
| Esquema `public` | USAGE para PUBLIC; CREATE solo para el owner de la base (default PG15+) |
| RLS | habilitada en **0** tablas de aplicación; **0** políticas |
| Grants explícitos | ninguno; todas las ACL de objetos son las de owner por defecto; sin grants por columna |
| Default privileges | solo existen para el rol administrativo interno del proveedor; **ninguno** para el rol owner de la aplicación |
| Vistas / funciones SECURITY DEFINER | ninguna en esquemas de aplicación |
| Extensiones | solo `plpgsql` |

## 3. Implicaciones para el futuro `prediktia_prospective_reader`

1. **Requiere grants explícitos.** Hoy no tendría acceso de lectura a ninguna
   tabla de aplicación; necesitará `GRANT SELECT` acotado.
2. **Default privileges.** Las tablas que cree la aplicación en migraciones
   futuras no se concederán automáticamente al lector; hará falta un
   `ALTER DEFAULT PRIVILEGES` para el rol owner de la aplicación.
3. **No debe pertenecer al rol administrativo del proveedor**, porque este
   hereda `pg_write_all_data`. Crear el rol por SQL (no desde la consola del
   proveedor, que suele añadir esa membresía) y verificar sus membresías
   efectivas después.
4. **Sin RLS:** el control de acceso será únicamente por privilegios.
5. **PUBLIC CONNECT/TEMP:** el lector podrá conectarse y crear tablas
   temporales salvo que se revoque a PUBLIC; decisión del Chief.

Todos los puntos 1, 2, 3 y 5 son **Chief Gate** (GRANT/REVOKE / default
privileges / roles). Nada de esto se ejecutó.

## 4. Pendiente

- No es posible determinar desde el catálogo si el endpoint auditado
  corresponde a la rama de producción o de desarrollo de Neon. Confirmar en la
  consola de Neon antes de aplicar cualquier propuesta sobre él.
