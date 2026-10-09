# M5.9C — Prerrequisitos del rol `prediktia_prospective_reader` (análisis saneado)

```
AGENT_ID: IT_SUPPORT_AGENT
FASE: M5.9C
FECHA_UTC: 2026-10-09
BASE: evidence/M59C-LB-001-result.md + lectura de código de la rama Modular
      feature/modular-m59b-prospective-infra (d31eebc), solo lectura
NEON_BRANCH_CLASSIFICATION: UNKNOWN (hay indicadores de producción)
ALLOWLIST_STATUS: DERIVADA — NO CONFIRMADA
NEON_MUTATION: NO
CHANGE_MADE: NO
CHIEF_GATE_REACHED: NO
```

## 1. Clasificación de la rama Neon auditada

**UNKNOWN.** Ningún metadato accesible vincula el endpoint auditado con una
rama concreta de Neon. Indicadores de producción:

- el esquema auditado coincide con el estado documentado de producción
  (Alembic `0007`; no existe la tabla de `0008`);
- las tablas de seguimiento operativo contienen registros, es decir, los jobs
  operativos han corrido contra esta base.

Una rama de desarrollo copiada de producción presentaría el mismo aspecto.
Mientras no se confirme en la consola de Neon (o con el responsable del secreto
del entorno `production` de GitHub), toda propuesta GRANT/REVOKE debe tratar
esta base **como producción**.

## 2. Allowlist propuesta (solo `SELECT`, no confirmada)

Esquema: `public` (solo `USAGE`).

| Objeto | Uso en la ruta de lectura | Existe hoy |
|--------|---------------------------|------------|
| `public.fixture_observations` | hechos del partido en H (`STRICT_KNOWLEDGE`): kickoff, equipos, competición | **NO** (migración `0008`) |
| `public.fixtures` | solo enumeración de candidatos | Sí |
| `public.fixture_statistics_observations` | estadísticas *as-of* | Sí |
| `public.statistics_runs` | comprobaciones de calidad del run | Sí |
| `public.team_provider_mappings` | mappings activos de equipos | Sí |

Sin secuencias, vistas, funciones ni permisos de escritura. El resto de tablas
de `public` queda fuera de la allowlist.

**Origen:** traza de código emisor → `team_recent_form_v1` → repositorios de
conocimiento estricto y de estadísticas *as-of*. El registro de predicciones y
los anclajes son archivos, no base de datos; el lector no necesita escribir.

## 3. Bloqueos y pendientes

1. **`fixture_observations` no existe.** La base auditada parece estar en
   Alembic `0007`. Un lector de producción **no puede ser funcional antes de que
   exista `0008`** (`APPLICATION_MIGRATIONS: HOLD`; gate del Chief, dueños
   Modular/DI).
2. **Modular debe confirmar la ruta de lectura final.** Las fuentes de hechos y
   de features del emisor se inyectan y aún no están cableadas a la base; la
   allowlist se deriva de la única implementación existente.
3. **Universo de partidos elegibles para emisión:** su fuente no está definida
   en código (probablemente `fixture_observations`; quizá catálogo de
   competiciones/temporadas). Modular debe confirmarlo.
4. **Etiquetas de evaluación:** la evaluación confirmatoria es offline; falta
   confirmar si el lector necesita acceso a resultados.

## 4. Siguiente paso

Confirmación de Modular (puntos 2 a 4) y de la rama Neon (§1) antes de
redactar la propuesta GRANT/REVOKE para el Chief. No se ha modificado Neon.
