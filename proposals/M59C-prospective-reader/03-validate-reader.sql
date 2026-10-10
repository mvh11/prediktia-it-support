-- =====================================================================
-- PREDIKTIA — M5.9C — VALIDACIÓN EFECTIVA (conectado COMO el lector)
-- AGENT_ID: IT_SUPPORT_AGENT
--
-- SOLO LECTURA. No lee filas de negocio: las consultas a tablas usan
-- LIMIT 0 (comprueban permiso, devuelven 0 filas). No prueba escrituras.
-- Uso:
--   psql -X -v ON_ERROR_STOP=1 -f 03-validate-reader.sql -d "$DSN_READER"
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo '=== R00 IDENTITY + SESSION DEFAULTS (esperado: reader, default_transaction_read_only=on, tx_read_only=on) ==='
SELECT current_user AS login_role,
       session_user,
       current_setting('default_transaction_read_only') AS default_transaction_read_only,
       current_setting('transaction_read_only')         AS tx_read_only;

\echo '=== R01 SELECT PERMITIDO EN LAS 6 TABLAS (esperado: sin error; 0 filas cada una) ==='
SELECT 'fixture_observations'            AS t, count(*) FROM (SELECT 1 FROM public.fixture_observations            LIMIT 0) s
UNION ALL
SELECT 'fixtures',                          count(*) FROM (SELECT 1 FROM public.fixtures                        LIMIT 0) s
UNION ALL
SELECT 'fixture_statistics_observations',   count(*) FROM (SELECT 1 FROM public.fixture_statistics_observations LIMIT 0) s
UNION ALL
SELECT 'statistics_runs',                   count(*) FROM (SELECT 1 FROM public.statistics_runs                 LIMIT 0) s
UNION ALL
SELECT 'team_provider_mappings',            count(*) FROM (SELECT 1 FROM public.team_provider_mappings          LIMIT 0) s
UNION ALL
SELECT 'seasons',                           count(*) FROM (SELECT 1 FROM public.seasons                         LIMIT 0) s;

\echo '=== R02 FUERA DE ALLOWLIST (esperado: sel=f en todas) ==='
SELECT c.relname AS object,
       has_table_privilege(c.oid, 'SELECT') AS sel
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f','S')
  AND c.relname NOT IN ('fixture_observations','fixtures','fixture_statistics_observations',
                        'statistics_runs','team_provider_mappings','seasons')
ORDER BY 1;

\echo '=== END VALIDATE-READER ==='
