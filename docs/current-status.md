# Estado actual — soporte TI

Última actualización: 2026-10-09 (CLOUD_CONTROL_PLANE — modelo unificado + paquete M59C-LB-001)

## 0. Control de escritura (un escritor de TI a la vez)

```
ACTIVE_IT_WRITER: LOCAL_BRIDGE (M59C-LB-001)
WORKING_BRANCH:   claude/it-support-bootstrap-rqariy  (PR mvh11/prediktia-it-support#1, abierta)
CLOUD_CONTROL_PLANE: no escribe hasta que exista evidence/M59C-LB-001-result.md
                     o el Chief libere el turno.
```

Modelo: [`operating-model.md`](operating-model.md).

Leyenda:
- **VERIFICADO** — comprobado directamente por IT_SUPPORT_AGENT, con evidencia.
- **REPORTADO** — informado por CHIEF_ARCHITECT / un departamento; no verificado
  de forma independiente por TI.
- **PENDIENTE** — aún no comprobado o aún no decidido.

## 1. Fase del proyecto

| Elemento | Valor | Estado |
|----------|-------|--------|
| Fase | M5.9C — coordinación de preparación para producción | REPORTADO |
| Baseline canónico de desarrollo | `1c06ef9c2a78a556cd8c7ded89853c19ec9a856a` | REPORTADO |
| Candidato Modular validado localmente | `d31eebc8e923c3d0351ac55086e53e08c2a5f62b` | REPORTADO |

## 2. Restricciones de producción (vigentes)

```
M5.9D_AUTHORIZED:        NO
REAL_PREDICTIONS:        OFF
SCHEDULER_ACTIVATED:     NO
STATISTICS_CATCHUP:      HOLD
APPLICATION_MIGRATIONS:  HOLD
MAIN_MERGE:              HOLD
```

Estado: REPORTADO. Cualquier cambio requiere a CHIEF_ARCHITECT.

## 3. Frentes de infraestructura activos

| # | Frente | Dirección aceptada | Estado |
|---|--------|--------------------|--------|
| 1 | Acceso de solo lectura con mínimo privilegio en Neon | Ver §4 | Auditoría metadata lista para LOCAL_BRIDGE (`handoffs/local/M59C-LB-001.md`); creación de roles **no autorizada** |
| 2 | Scheduler externo | scheduler externo gestionado → dispatch autenticado → GitHub `workflow_dispatch` → `tick_id` determinista → ejecución Prediktia → reconciliación esperado/observado | Diseño; **no activar** |
| 3 | Entorno del emisor prospectivo | entorno Linux/nube dedicado (no PC de desarrollo); mínimo privilegio; artefacto inmutable con commit git/digest; secretos externos; despliegue controlado; un reinicio **no** debe disparar catch-up | Diseño; despliegue no autorizado |
| 4 | Sincronización UTC/hora | UTC autoritativo en scheduler y emisor | PENDIENTE |
| 5 | Sellado de tiempo RFC3161 | por tick/lote; la TSA recibe solo el digest; conservar token + evidencia de verificación | Diseño |
| 6 | Backup/restauración independiente | la recuperación nativa de Neon no basta; backup independiente fuera de Neon/emisor; restaurar primero en entorno aislado; validar hash-chain + evidencia RFC3161 tras restaurar | Diseño; cambios de política requieren al Chief |
| 7 | Límites de seguridad y credenciales | credenciales separadas lector vs. escritor; secretos externos; ninguno en repositorios | En curso |

## 4. Acceso de solo lectura en Neon — diseño propuesto

```
prediktia_prospective_ro      NOLOGIN   (rol de permisos)
prediktia_prospective_reader  LOGIN     (miembro de _ro)
```

Principios: CONNECT explícito; USAGE de esquema explícito; SELECT explícito por
objeto; sin `pg_read_all_data`; sin `SELECT ON ALL TABLES` general sin
aprobación del Chief; sin default privileges amplios; sin escrituras; sin DDL;
credenciales separadas de los escritores de la aplicación;
`default_transaction_read_only = on` como defensa en profundidad.

Pendiente de verificar (Neon, según su documentación): los roles creados desde la
consola/API de Neon reciben `neon_superuser`; los roles de este diseño deben
crearse por SQL.

Checklist de verificación previa a la creación (todo **PENDIENTE**; lo cubre
M59C-LB-001):

- [ ] base de datos objetivo exacta
- [ ] esquemas en alcance
- [ ] objetos exactos que necesita el lector
- [ ] privilegios de PUBLIC (base de datos, esquemas, funciones)
- [ ] privilegio TEMP
- [ ] roles y membresías existentes
- [ ] dueños de los objetos
- [ ] estado de RLS en las tablas objetivo
- [ ] default privileges (`pg_default_acl`)

## 5. Verificado por TI

- Repositorio inicializado; commit de bootstrap `4b3f57d` publicado en la rama
  `claude/it-support-bootstrap-rqariy` (PR mvh11/prediktia-it-support#1,
  abierta; merge a `main` pendiente de revisión).
- CLOUD_CONTROL_PLANE no tiene acceso a Neon: sin conector, sin credencial,
  sin configuración PG (comprobado 2026-10-09). Por diseño, no lo tendrá.
- `scripts/read-only/neon_privilege_audit.sql` validado en PostgreSQL 16 local
  desechable, con rol no superusuario: termina sin errores, en transacción
  READ ONLY + ROLLBACK, y la transacción rechaza escrituras.
- Rol temporal `prediktia_m59c_audit` (autorizado con condiciones por el Chief):
  **no creado**; el precheck falló en cloud por falta de identidad en Neon.
- Nada verificado aún sobre el estado real de Neon.

## 6. Bloqueos actuales

| Bloqueo | Se necesita de |
|---------|----------------|
| Ejecución de M59C-LB-001 en la estación local | Operador / LOCAL_BRIDGE |
| Lista de objetos que necesita el lector prospectivo no definida | MODULAR_PRINCIPAL / Data Integrity |
| Proveedor del scheduler y hosting del emisor no seleccionados | CHIEF_ARCHITECT |
| Proveedor(es) TSA para RFC3161 no seleccionados | CHIEF_ARCHITECT |
| Destino/ubicación del backup independiente no seleccionado | CHIEF_ARCHITECT |

## 7. Próximas acciones de TI (solo lectura, dentro de la autoridad permanente)

1. Revisar `evidence/M59C-LB-001-result.md` cuando LOCAL_BRIDGE lo publique y
   actualizar §4.
2. Con la evidencia y la lista de objetos requeridos, preparar la propuesta
   GRANT/REVOKE acotada para aprobación del Chief.
3. Redactar los diseños de scheduler, emisor, RFC3161 y backup para revisión
   del Chief.
