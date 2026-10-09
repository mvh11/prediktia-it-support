# Estado actual — soporte TI

Última actualización: 2026-10-09 (sesión de bootstrap)

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
| 1 | Acceso de solo lectura con mínimo privilegio en Neon | Ver §4 | Diseño; creación **no autorizada** |
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

Checklist de verificación previa a la creación (todo **PENDIENTE**):

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
  abierta; merge a `main` pendiente de revisión). Nada más verificado aún.

## 6. Bloqueos actuales

| Bloqueo | Se necesita de |
|---------|----------------|
| Sin acceso de solo lectura a Neon para ejecutar el checklist de §4 | CHIEF_ARCHITECT (autorizar una vía de inspección de solo lectura) |
| Lista de objetos que necesita el lector prospectivo no definida | MODULAR_PRINCIPAL / Data Integrity |
| Proveedor del scheduler y hosting del emisor no seleccionados | CHIEF_ARCHITECT |
| Proveedor(es) TSA para RFC3161 no seleccionados | CHIEF_ARCHITECT |
| Destino/ubicación del backup independiente no seleccionado | CHIEF_ARCHITECT |

## 7. Próximas acciones de TI (solo lectura, dentro de la autoridad permanente)

1. Preparar las consultas de auditoría de solo lectura para el checklist de §4
   (sin ejecutarlas contra producción hasta que se autorice el acceso).
2. Redactar los diseños de scheduler, emisor, RFC3161 y backup para revisión
   del Chief.
