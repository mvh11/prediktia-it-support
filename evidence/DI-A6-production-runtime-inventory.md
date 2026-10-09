# DI-A6 production runtime / writer inventory

Status: **IN PROGRESS**

This evidence package closes the authorized production execution-surface inventory
for the future Alembic 0008 window. No migration is executed by this work.

## Frozen ownership

- FIRST_NORMAL_WRITE_OWNER: MODULAR_PRINCIPAL
- REENABLE_OWNER: IT_SUPPORT_AGENT
- FIRST_CYCLE_MONITOR: MODULAR_PRINCIPAL + CLAUDE_AGENT + IT_SUPPORT_AGENT
- CHIEF_ARCHITECT: GO / NO-GO and exceptional rollback/restore authority

## Already proven

- GitHub C6 scheduler entrypoints are gated by `PREDIKTIA_SCHEDULER_ENABLED == 'true'`.
- Current observed scheduled runs for ops-live, ops-catalog and ops-stats resolve
  as skipped before runner allocation; no workflow steps execute.
- The application repository exposes fixture writes through the known fixture sync
  and historical backfill paths. HTTP sync endpoints are guarded by
  `SYNC_ENDPOINTS_ENABLED`, default false.
- No additional deployment manifest for Docker/Compose, Render, Railway, Fly,
  Vercel, Procfile, or similar was found in the current application repository tree.

## Remaining local evidence

Run `scripts/read-only/audit-production-runtime.ps1` on each authorized PREDIKTIA
workstation. The raw output stays local until sanitized. Secret values must never
be committed.

The inventory must determine, per host:

- production database credential capability;
- provider credential capability;
- PREDIKTIA repositories;
- relevant Python/uvicorn/job processes;
- Windows scheduled tasks;
- services;
- startup/autostart;
- Docker/WSL processes and cron;
- manual CLI capability.

## Future DB-side quiescence gate

Immediately before 0008, after all known writer surfaces are disabled, run
`scripts/read-only/check-production-db-quiescence.py` using the authorized
production DATABASE_URL as an opaque environment value.

Acceptance requires both:

1. all known/authorized application writer surfaces disabled or quiescent; and
2. DB_SIDE_QUIESCENCE=PASS at the immediate pre-migration sample.

The DB script is read-only and reports only aggregate session counts. It does not
print query text, usernames, client addresses, host names, or secrets.

## Current gate

PRODUCTION_0008: HOLD

The hold remains until both authorized PREDIKTIA workstations are inventoried and
the production FastAPI/manual/background execution surfaces can be classified.
