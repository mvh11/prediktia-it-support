-- =====================================================================
-- PREDIKTIA — NEON PRIVILEGE / METADATA AUDIT (READ-ONLY)
-- AGENT_ID: IT_SUPPORT_AGENT
-- Ruta: scripts/read-only/neon_privilege_audit.sql
--
-- Clasificación: SOLO LECTURA. Únicamente SELECT/SHOW sobre catálogos.
-- No contiene CREATE/ALTER/DROP/GRANT/REVOKE/INSERT/UPDATE/DELETE.
-- Todo corre dentro de una transacción READ ONLY que termina en ROLLBACK.
-- No consulta contraseñas ni hashes (no se lee pg_authid ni rolpassword).
-- No consulta filas de negocio/aplicación: solo catálogos del sistema.
--
-- Validado en PostgreSQL 16 (clúster local desechable, rol no superusuario).
-- Uso: ver handoffs/local/M59C-LB-001.md. La credencial se pasa como
-- fuente opaca (variable de entorno); nunca en la línea ni en archivos.
--
-- Cubre solo la base de datos a la que se conecta.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
\pset null '(null)'

BEGIN TRANSACTION READ ONLY;

\echo '=== 00 SESSION ==='
SELECT current_database() AS database,
       current_user        AS audit_user,
       now() AT TIME ZONE 'UTC' AS audit_utc,
       current_setting('transaction_read_only') AS tx_read_only;

\echo '=== 01 SERVER / VERSION ==='
SELECT version();
SHOW server_version;
SHOW server_version_num;

\echo '=== 01b EXTENSIONS (current db) ==='
SELECT extname, extversion, pg_get_userbyid(extowner) AS owner,
       extnamespace::regnamespace AS schema
FROM pg_extension ORDER BY extname;

\echo '=== 02 DATABASES ==='
SELECT datname,
       pg_get_userbyid(datdba) AS owner,
       datallowconn,
       datconnlimit,
       datacl IS NULL AS acl_is_default,
       datacl
FROM pg_database
WHERE NOT datistemplate
ORDER BY datname;

\echo '=== 03 ROLES (sin contraseñas) ==='
SELECT rolname, rolcanlogin, rolsuper, rolinherit, rolcreatedb,
       rolcreaterole, rolreplication, rolbypassrls, rolconnlimit,
       rolvaliduntil, rolconfig
FROM pg_roles
WHERE rolname NOT LIKE 'pg\_%'
ORDER BY rolname;

\echo '=== 03b DIRECT ROLE MEMBERSHIPS (incluye roles pg_*) ==='
-- to_jsonb para ser compatible con PG<16 y PG16+ (inherit_option/set_option)
SELECT g.rolname AS granted_role,
       m.rolname AS member,
       gr.rolname AS grantor,
       to_jsonb(am) - 'oid' - 'roleid' - 'member' - 'grantor' AS options
FROM pg_auth_members am
JOIN pg_roles g  ON g.oid  = am.roleid
JOIN pg_roles m  ON m.oid  = am.member
LEFT JOIN pg_roles gr ON gr.oid = am.grantor
ORDER BY member, granted_role;

\echo '=== 09 EFFECTIVE MEMBERSHIPS OF LOGIN ROLES (transitivas) ==='
SELECT l.rolname AS login_role,
       b.rolname AS effective_member_of,
       pg_has_role(l.oid, b.oid, 'USAGE') AS inherits_privileges
FROM pg_roles l
CROSS JOIN pg_roles b
WHERE l.rolcanlogin
  AND l.oid <> b.oid
  AND pg_has_role(l.oid, b.oid, 'MEMBER')
ORDER BY login_role, effective_member_of;

\echo '=== 09b BROAD PREDEFINED ROLE HOLDERS ==='
SELECT b.rolname AS broad_role, r.rolname AS holder, r.rolcanlogin,
       pg_has_role(r.oid, b.oid, 'USAGE') AS inherits_privileges
FROM pg_roles b
CROSS JOIN pg_roles r
WHERE b.rolname IN ('pg_read_all_data','pg_write_all_data',
                    'pg_read_all_settings','pg_read_all_stats',
                    'pg_monitor','pg_signal_backend',
                    'pg_read_server_files','pg_write_server_files',
                    'pg_execute_server_program','pg_create_subscription',
                    'pg_checkpoint','pg_use_reserved_connections',
                    'neon_superuser')
  AND r.oid <> b.oid
  AND pg_has_role(r.oid, b.oid, 'MEMBER')
ORDER BY broad_role, holder;

\echo '=== 04 DATABASE PRIVILEGES (current db; NULL acl => defaults) ==='
SELECT d.datname,
       CASE a.grantee WHEN 0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(a.grantee) END AS grantee,
       pg_get_userbyid(a.grantor) AS grantor,
       a.privilege_type,
       a.is_grantable
FROM pg_database d,
     LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
WHERE d.datname = current_database()
ORDER BY grantee, privilege_type;

\echo '=== 10 PUBLIC TEMP ON CURRENT DB ==='
SELECT current_database() AS database,
       EXISTS (
         SELECT 1
         FROM pg_database d,
              LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
         WHERE d.datname = current_database()
           AND a.grantee = 0
           AND a.privilege_type = 'TEMPORARY'
       ) AS public_has_temp,
       EXISTS (
         SELECT 1
         FROM pg_database d,
              LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
         WHERE d.datname = current_database()
           AND a.grantee = 0
           AND a.privilege_type = 'CONNECT'
       ) AS public_has_connect,
       EXISTS (
         SELECT 1
         FROM pg_database d,
              LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
         WHERE d.datname = current_database()
           AND a.grantee = 0
           AND a.privilege_type = 'CREATE'
       ) AS public_has_create;

\echo '=== 05 SCHEMAS + PRIVILEGES (NULL acl => defaults) ==='
SELECT n.nspname AS schema,
       pg_get_userbyid(n.nspowner) AS owner,
       n.nspacl IS NULL AS acl_is_default,
       CASE a.grantee WHEN 0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(a.grantee) END AS grantee,
       a.privilege_type,
       a.is_grantable
FROM pg_namespace n,
     LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a
WHERE n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
  AND n.nspname NOT LIKE 'pg\_temp\_%'
  AND n.nspname NOT LIKE 'pg\_toast\_temp\_%'
ORDER BY schema, grantee, privilege_type;

\echo '=== 06 RELATIONS INVENTORY (tables/views/matviews/foreign/partitioned/sequences) ==='
SELECT n.nspname AS schema,
       c.relname AS object,
       CASE c.relkind WHEN 'r' THEN 'table' WHEN 'p' THEN 'partitioned_table'
                      WHEN 'v' THEN 'view'  WHEN 'm' THEN 'materialized_view'
                      WHEN 'f' THEN 'foreign_table' WHEN 'S' THEN 'sequence'
                      ELSE c.relkind::text END AS type,
       pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced,
       c.reltuples::bigint AS est_rows,
       c.relacl IS NULL AS acl_is_default
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','p','v','m','f','S')
  AND n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
  AND n.nspname NOT LIKE 'pg\_temp\_%'
ORDER BY schema, type, object;

\echo '=== 06b RELATION GRANTS (explicit + owner defaults) ==='
SELECT n.nspname AS schema,
       c.relname AS object,
       CASE a.grantee WHEN 0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(a.grantee) END AS grantee,
       pg_get_userbyid(a.grantor) AS grantor,
       a.privilege_type,
       a.is_grantable
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace,
LATERAL aclexplode(COALESCE(c.relacl,
        acldefault((CASE WHEN c.relkind = 'S' THEN 's' ELSE 'r' END)::"char", c.relowner))) a
WHERE c.relkind IN ('r','p','v','m','f','S')
  AND n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
  AND n.nspname NOT LIKE 'pg\_temp\_%'
ORDER BY schema, object, grantee, privilege_type;

\echo '=== 06c COLUMN-LEVEL GRANTS ==='
SELECT n.nspname AS schema, c.relname AS object, att.attname AS column_name,
       CASE a.grantee WHEN 0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(a.grantee) END AS grantee,
       a.privilege_type
FROM pg_attribute att
JOIN pg_class c ON c.oid = att.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace,
LATERAL aclexplode(att.attacl) a
WHERE att.attacl IS NOT NULL
  AND n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
ORDER BY schema, object, column_name;

\echo '=== 06d VIEW OWNERSHIP / security_invoker (vistas saltan RLS si owner la salta) ==='
SELECT n.nspname AS schema, c.relname AS view,
       pg_get_userbyid(c.relowner) AS owner,
       c.reloptions
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('v','m')
  AND n.nspname NOT IN ('pg_catalog','information_schema')
ORDER BY schema, view;

\echo '=== 06e SECURITY DEFINER FUNCTIONS (non-system schemas) ==='
SELECT n.nspname AS schema, p.proname AS function,
       pg_get_function_identity_arguments(p.oid) AS args,
       pg_get_userbyid(p.proowner) AS owner,
       p.proacl IS NULL AS acl_is_default_public_execute,
       p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prosecdef
  AND n.nspname NOT IN ('pg_catalog','information_schema')
ORDER BY schema, function;

\echo '=== 07 RLS POLICIES ==='
SELECT schemaname, tablename, policyname, permissive, roles, cmd,
       qual, with_check
FROM pg_policies
ORDER BY schemaname, tablename, policyname;

\echo '=== 08 DEFAULT PRIVILEGES (ALTER DEFAULT PRIVILEGES) ==='
SELECT pg_get_userbyid(d.defaclrole) AS for_role,
       COALESCE(n.nspname, '(all schemas)') AS in_schema,
       CASE d.defaclobjtype WHEN 'r' THEN 'tables' WHEN 'S' THEN 'sequences'
                            WHEN 'f' THEN 'functions' WHEN 'T' THEN 'types'
                            WHEN 'n' THEN 'schemas'
                            ELSE d.defaclobjtype::text END AS object_type,
       CASE a.grantee WHEN 0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(a.grantee) END AS grantee,
       a.privilege_type,
       a.is_grantable
FROM pg_default_acl d
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace,
LATERAL aclexplode(d.defaclacl) a
ORDER BY for_role, in_schema, object_type, grantee, privilege_type;

\echo '=== 11 RELEVANT SETTINGS ==='
SELECT name, setting, source
FROM pg_settings
WHERE name IN ('default_transaction_read_only','row_security',
               'search_path','log_statement','log_connections',
               'ssl','password_encryption','timezone')
ORDER BY name;

ROLLBACK;
\echo '=== END (ROLLBACK ejecutado; ningún cambio) ==='
