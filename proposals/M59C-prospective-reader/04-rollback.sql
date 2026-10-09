-- =====================================================================
-- PREDIKTIA — M5.9C — ROLLBACK DEL LECTOR PROSPECTIVO (PROPUESTA)
-- AGENT_ID: IT_SUPPORT_AGENT
--
-- ESTADO: PROPUESTA. NO EJECUTAR sin autorización explícita del Chief.
-- Sin CASCADE. Sin REASSIGN/DROP OWNED. Si quedan dependencias → STOP.
-- Toda guarda fallida termina psql con código de salida 3, sin confirmar cambios.
-- Uso:
--   psql -X -v ON_ERROR_STOP=1 -v target_db=<BD_PRODUCCION> -f 04-rollback.sql -d "$DSN_ADMIN"
-- Antes: cerrar las sesiones del lector (decisión del operador).
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off

\if :{?target_db}
\else
  \echo 'STOP: falta -v target_db=<BD_PRODUCCION>'
  DO $$ BEGIN RAISE EXCEPTION 'M59C_GUARD_FAILED: target_db no definido'; END $$;
\endif

SELECT current_database() = :'target_db' AS ok_db,
       (SELECT count(*) FROM pg_stat_activity
         WHERE usename = 'prediktia_prospective_reader') AS reader_sessions
\gset

\if :ok_db
\else
  \echo 'STOP: la base conectada no es target_db'
  DO $$ BEGIN RAISE EXCEPTION 'M59C_GUARD_FAILED: base incorrecta'; END $$;
\endif
\echo 'Sesiones activas del lector:' :reader_sessions

BEGIN;

-- 1. Revocar grants explícitos (solo los concedidos por 01-create.sql)
REVOKE SELECT ON TABLE
  public.fixture_observations,
  public.fixtures,
  public.fixture_statistics_observations,
  public.statistics_runs,
  public.team_provider_mappings,
  public.seasons
FROM prediktia_prospective_ro;
REVOKE USAGE ON SCHEMA public FROM prediktia_prospective_ro;
REVOKE CONNECT ON DATABASE :"target_db" FROM prediktia_prospective_ro;

-- 2. Quitar la membresía del lector en el rol de permisos
REVOKE prediktia_prospective_ro FROM prediktia_prospective_reader;

-- 3. Comprobar dependencias restantes en TODAS las bases (pg_shdepend es global)
SELECT count(*) > 0 AS has_remaining_deps
FROM pg_shdepend s
JOIN pg_roles r ON r.oid = s.refobjid AND s.refclassid = 'pg_authid'::regclass
WHERE r.rolname IN ('prediktia_prospective_ro', 'prediktia_prospective_reader')
\gset

\if :has_remaining_deps
  \echo 'STOP: quedan dependencias de los roles; no se fuerza la limpieza. Detalle:'
  SELECT r.rolname, s.dbid, s.classid::regclass, s.objid, s.deptype
  FROM pg_shdepend s
  JOIN pg_roles r ON r.oid = s.refobjid AND s.refclassid = 'pg_authid'::regclass
  WHERE r.rolname IN ('prediktia_prospective_ro', 'prediktia_prospective_reader');
  -- La excepción aborta la transacción; psql sale con código 3 y nada se confirma.
  DO $$ BEGIN RAISE EXCEPTION 'M59C_GUARD_FAILED: quedan dependencias'; END $$;
\endif

-- 4. Eliminar roles (sin CASCADE). DROP ROLE elimina también sus ajustes de rol.
DROP ROLE prediktia_prospective_reader;
DROP ROLE prediktia_prospective_ro;

COMMIT;

\echo '=== ROLLBACK OK: roles prediktia_prospective_* eliminados ==='
