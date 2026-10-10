-- =====================================================================
-- PREDIKTIA — M5.9C — VALIDACIÓN DEL LECTOR PROSPECTIVO (como admin)
-- AGENT_ID: IT_SUPPORT_AGENT
--
-- SOLO LECTURA: catálogos y funciones has_*_privilege dentro de una
-- transacción READ ONLY que termina en ROLLBACK. No lee filas de negocio.
-- Uso:
--   psql -X -v ON_ERROR_STOP=1 -v target_db=<BD_PRODUCCION> -f 02-validate-admin.sql -d "$DSN_ADMIN"
-- Cada bloque indica el resultado ESPERADO.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
\pset null '(null)'

BEGIN TRANSACTION READ ONLY;

\echo '=== V00 SESSION (esperado: target_db, tx_read_only=on) ==='
SELECT current_database() AS database,
       current_database() = :'target_db' AS is_target_db,
       current_setting('transaction_read_only') AS tx_read_only;

\echo '=== V01 ROLE ATTRIBUTES (esperado: _ro NOLOGIN; _reader LOGIN, connlimit 5; ambos sin super/createdb/createrole/replication/bypassrls) ==='
SELECT rolname, rolcanlogin, rolsuper, rolinherit, rolcreatedb, rolcreaterole,
       rolreplication, rolbypassrls, rolconnlimit, rolvaliduntil
FROM pg_roles
WHERE rolname IN ('prediktia_prospective_ro', 'prediktia_prospective_reader')
ORDER BY rolname;

\echo '=== V02 DIRECT MEMBERSHIPS OF THE NEW ROLES (esperado: 1 fila, reader -> _ro, inherit=t set=f admin=f) ==='
SELECT m.rolname AS member, g.rolname AS granted_role,
       am.inherit_option, am.set_option, am.admin_option
FROM pg_auth_members am
JOIN pg_roles g ON g.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE m.rolname IN ('prediktia_prospective_ro', 'prediktia_prospective_reader')
ORDER BY member, granted_role;

\echo '=== V02b WHO IS MEMBER OF THE NEW ROLES (informativo: en PG16+ el creador recibe ADMIN implícito; aceptable) ==='
SELECT g.rolname AS role, m.rolname AS member,
       am.inherit_option, am.set_option, am.admin_option
FROM pg_auth_members am
JOIN pg_roles g ON g.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE g.rolname IN ('prediktia_prospective_ro', 'prediktia_prospective_reader')
ORDER BY role, member;

\echo '=== V03 EFFECTIVE MEMBERSHIPS OF READER (esperado: solo prediktia_prospective_ro) ==='
SELECT b.rolname AS effective_member_of,
       pg_has_role('prediktia_prospective_reader', b.oid, 'USAGE') AS inherits_privileges
FROM pg_roles b
WHERE b.rolname <> 'prediktia_prospective_reader'
  AND pg_has_role('prediktia_prospective_reader', b.oid, 'MEMBER')
ORDER BY 1;

\echo '=== V04 BROAD / APPLICATION ROLES (esperado: 0 filas) ==='
SELECT b.rolname AS forbidden_role
FROM pg_roles b
WHERE pg_has_role('prediktia_prospective_reader', b.oid, 'MEMBER')
  AND (b.rolname LIKE 'pg\_%'
       OR b.rolname = 'neon_superuser'
       OR b.rolsuper OR b.rolcreaterole OR b.rolcreatedb OR b.rolbypassrls
       OR b.oid = (SELECT datdba FROM pg_database WHERE datname = current_database()))
ORDER BY 1;

\echo '=== V05 DATABASE PRIVILEGES (esperado: connect=t, create=f, temp=t heredado de PUBLIC) ==='
SELECT has_database_privilege('prediktia_prospective_reader', current_database(), 'CONNECT')   AS reader_connect,
       has_database_privilege('prediktia_prospective_reader', current_database(), 'CREATE')    AS reader_create,
       has_database_privilege('prediktia_prospective_reader', current_database(), 'TEMPORARY') AS reader_temp;

\echo '=== V05b EXPLICIT DB GRANT (esperado: _ro CONNECT, no grantable; nada más para los roles nuevos) ==='
SELECT CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS grantee,
       a.privilege_type, a.is_grantable
FROM pg_database d,
     LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
WHERE d.datname = current_database()
  AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('prediktia_prospective_ro', 'prediktia_prospective_reader'))
ORDER BY grantee, privilege_type;

\echo '=== V06 SCHEMA public (esperado: usage=t, create=f) ==='
SELECT has_schema_privilege('prediktia_prospective_reader', 'public', 'USAGE')  AS reader_usage,
       has_schema_privilege('prediktia_prospective_reader', 'public', 'CREATE') AS reader_create;

\echo '=== V07 ALLOWLIST: SELECT=t y todo lo demás=f en las 6 tablas (esperado: 6 filas, ok=t) ==='
SELECT t.name AS allowlisted_table,
       has_table_privilege('prediktia_prospective_reader', t.name, 'SELECT')     AS sel,
       has_table_privilege('prediktia_prospective_reader', t.name, 'INSERT')     AS ins,
       has_table_privilege('prediktia_prospective_reader', t.name, 'UPDATE')     AS upd,
       has_table_privilege('prediktia_prospective_reader', t.name, 'DELETE')     AS del,
       has_table_privilege('prediktia_prospective_reader', t.name, 'TRUNCATE')   AS trn,
       has_table_privilege('prediktia_prospective_reader', t.name, 'REFERENCES') AS ref,
       has_table_privilege('prediktia_prospective_reader', t.name, 'TRIGGER')    AS trg,
       has_table_privilege('prediktia_prospective_reader', t.name, 'MAINTAIN')   AS mnt,
       has_table_privilege('prediktia_prospective_reader', t.name, 'SELECT')
       AND NOT has_table_privilege('prediktia_prospective_reader', t.name,
             'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN') AS ok
FROM unnest(ARRAY[
  'public.fixture_observations',
  'public.fixtures',
  'public.fixture_statistics_observations',
  'public.statistics_runs',
  'public.team_provider_mappings',
  'public.seasons']) AS t(name)
ORDER BY 1;

\echo '=== V08 RELATIONS OUTSIDE ALLOWLIST WITH ANY PRIVILEGE (esperado: 0 filas; incluye alembic_version) ==='
SELECT n.nspname AS schema, c.relname AS object, c.relkind
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','p','v','m','f')
  AND n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
  AND n.nspname NOT LIKE 'pg\_temp\_%'
  AND n.nspname NOT LIKE 'pg\_toast\_temp\_%'
  AND format('%I.%I', n.nspname, c.relname) NOT IN (
        'public.fixture_observations',
        'public.fixtures',
        'public.fixture_statistics_observations',
        'public.statistics_runs',
        'public.team_provider_mappings',
        'public.seasons')
  AND (has_table_privilege('prediktia_prospective_reader', c.oid,
         'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
       OR has_any_column_privilege('prediktia_prospective_reader', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES'))
ORDER BY 1, 2;

\echo '=== V09 SEQUENCES WITH ANY PRIVILEGE (esperado: 0 filas) ==='
SELECT n.nspname AS schema, c.relname AS sequence
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'S'
  -- CASE evita que el planificador evalúe la función sobre relaciones que no son secuencias
  AND CASE WHEN c.relkind = 'S'
           THEN has_sequence_privilege('prediktia_prospective_reader', c.oid, 'USAGE, SELECT, UPDATE')
           ELSE false END
ORDER BY 1, 2;

\echo '=== V10 OBJECTS OWNED BY NEW ROLES (esperado: 0) ==='
SELECT count(*) AS owned_objects
FROM pg_shdepend s
JOIN pg_roles r ON r.oid = s.refobjid AND s.refclassid = 'pg_authid'::regclass
WHERE r.rolname IN ('prediktia_prospective_ro', 'prediktia_prospective_reader')
  AND s.deptype = 'o';

\echo '=== V11 ROLE SETTINGS (esperado: reader {default_transaction_read_only=on}, database=(all)) ==='
SELECT r.rolname,
       CASE WHEN s.setdatabase = 0 THEN '(all)' ELSE (SELECT datname FROM pg_database WHERE oid = s.setdatabase) END AS database,
       s.setconfig
FROM pg_db_role_setting s
JOIN pg_roles r ON r.oid = s.setrole
WHERE r.rolname IN ('prediktia_prospective_ro', 'prediktia_prospective_reader');

\echo '=== V12 PUBLIC TEMP/CONNECT UNCHANGED (esperado: public_has_temp=t, public_has_connect=t, public_has_create=f) ==='
SELECT bool_or(a.grantee = 0 AND a.privilege_type = 'TEMPORARY') AS public_has_temp,
       bool_or(a.grantee = 0 AND a.privilege_type = 'CONNECT')   AS public_has_connect,
       bool_or(a.grantee = 0 AND a.privilege_type = 'CREATE')    AS public_has_create
FROM pg_database d,
     LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
WHERE d.datname = current_database();

ROLLBACK;
\echo '=== END VALIDATE-ADMIN (ROLLBACK; ningún cambio) ==='
