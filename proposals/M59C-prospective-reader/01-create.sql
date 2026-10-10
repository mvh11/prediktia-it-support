-- =====================================================================
-- PREDIKTIA — M5.9C — CREACIÓN DEL LECTOR PROSPECTIVO (PROPUESTA)
-- AGENT_ID: IT_SUPPORT_AGENT
--
-- ESTADO: PROPUESTA. NO EJECUTAR sin autorización explícita del Chief.
-- Requisito: migración Alembic 0008 aplicada y las SEIS tablas de la allowlist presentes.
-- Destino: base de PRODUCCIÓN exacta, pasada en la ejecución:
--   psql -X -v ON_ERROR_STOP=1 -v target_db=<BD_PRODUCCION> -f 01-create.sql -d "$DSN_ADMIN"
-- La contraseña NO va en este archivo: se fija después con \password (ver README).
-- Sin ALTER DEFAULT PRIVILEGES. Sin cambios a PUBLIC, RLS ni esquema.
-- =====================================================================

-- GUARDAS: toda condición fallida imprime 'STOP: …' y termina psql con código
-- de salida 3 (excepción en un bloque DO sin efectos + ON_ERROR_STOP), antes
-- de cualquier BEGIN o cambio persistente. psql no admite código en \quit.

\set ON_ERROR_STOP on
\pset pager off

\if :{?target_db}
\else
  \echo 'STOP: falta -v target_db=<BD_PRODUCCION>'
  DO $$ BEGIN RAISE EXCEPTION 'M59C_GUARD_FAILED: target_db no definido'; END $$;
\endif

-- ---------- Precondiciones (solo lectura) ----------
-- Las SEIS tablas de la allowlist deben existir como tablas en public
-- (fixture_observations sola no basta).
SELECT current_database() = :'target_db' AS ok_db,
       NOT EXISTS (SELECT 1 FROM pg_roles
                   WHERE rolname IN ('prediktia_prospective_ro',
                                     'prediktia_prospective_reader')) AS ok_roles_absent,
       COALESCE((
         SELECT string_agg(t.name, ',' ORDER BY t.name)
         FROM unnest(ARRAY[
                'fixture_observations',
                'fixtures',
                'fixture_statistics_observations',
                'statistics_runs',
                'team_provider_mappings',
                'seasons']) AS t(name)
         WHERE NOT EXISTS (
           SELECT 1 FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relname = t.name AND c.relkind IN ('r','p'))
       ), '') AS missing_tables
\gset

SELECT :'missing_tables' = '' AS ok_tables
\gset

\if :ok_db
\else
  \echo 'STOP: la base conectada no es target_db'
  DO $$ BEGIN RAISE EXCEPTION 'M59C_GUARD_FAILED: base incorrecta'; END $$;
\endif
\if :ok_tables
\else
  \echo 'STOP: faltan tablas de la allowlist en public:' :missing_tables
  DO $$ BEGIN RAISE EXCEPTION 'M59C_GUARD_FAILED: faltan tablas de la allowlist'; END $$;
\endif
\if :ok_roles_absent
\else
  \echo 'STOP: algún rol prediktia_prospective_* ya existe'
  DO $$ BEGIN RAISE EXCEPTION 'M59C_GUARD_FAILED: roles ya existen'; END $$;
\endif

\echo 'GUARDS OK: base exacta, 6/6 tablas presentes, roles ausentes'

-- ---------- Cambios (una sola transacción) ----------
BEGIN;

-- 1. Rol de permisos (sin login)
CREATE ROLE prediktia_prospective_ro
  NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- 2. Rol de login (sin contraseña aquí: se fija con \password tras el COMMIT)
CREATE ROLE prediktia_prospective_reader
  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS
  INHERIT CONNECTION LIMIT 5 PASSWORD NULL;

-- 3. Privilegios exactos, solo en el rol de permisos
GRANT CONNECT ON DATABASE :"target_db" TO prediktia_prospective_ro;
GRANT USAGE ON SCHEMA public TO prediktia_prospective_ro;
GRANT SELECT ON TABLE
  public.fixture_observations,
  public.fixtures,
  public.fixture_statistics_observations,
  public.statistics_runs,
  public.team_provider_mappings,
  public.seasons
TO prediktia_prospective_ro;

-- 4. Única membresía del lector (hereda privilegios; no puede SET ROLE ni administrar)
GRANT prediktia_prospective_ro TO prediktia_prospective_reader
  WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;

-- 5. Defensa en profundidad (no es el límite de privilegio; el límite son los GRANT)
ALTER ROLE prediktia_prospective_reader SET default_transaction_read_only = on;

COMMIT;

\echo '=== CREATE OK. Siguiente: fijar contraseña (meta-comando password de psql) y 02-validate-admin.sql ==='
