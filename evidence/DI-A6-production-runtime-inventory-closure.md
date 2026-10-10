# DI-A6 production runtime inventory — sanitized closure

Status: INVENTORY CLOSED; production migration not started.

## Authorized production execution surfaces

1. GitHub Actions C6 workflows.
2. Data Integrity workstation (designated future production control host).
3. Modular workstation (production-capable; local FastAPI currently running on loopback and must be stopped for the migration window).

No other authorized production execution surface was positively identified by Data Integrity, Modular, repository inspection, or GitHub runtime inspection.

## GitHub

- ops-live, ops-catalog, and ops-stats are the known operational workflows.
- Current observed scheduled runs are skipped before runner allocation.
- Effective scheduler gate state is therefore not enabled.
- Migration-window control: keep the scheduler gate disabled and verify no active ops run immediately before migration.

## Data Integrity workstation

- Production DB capability: YES.
- Provider capability: YES.
- Running fixture writer process: NONE observed.
- Running FastAPI/uvicorn: NONE observed.
- Relevant scheduled task/service: NONE observed.
- Docker writer surface: NONE observed.
- Manual CLI production capability: YES.

## Modular workstation

- Production DB capability: YES.
- Local uvicorn/FastAPI on loopback is currently running.
- API sync endpoints are reported disabled by configuration/code inspection.
- No live_sync/history_backfill/ops_tick job was observed running.
- No related local scheduled task was reported.
- Manual CLI production capability exists.

Migration-window control for the Modular workstation:
- stop local uvicorn;
- verify no loopback API listener remains;
- verify no live_sync/history_backfill/ops_tick process is running;
- do not invoke manual production CLI until re-enable.

## Production API deployment resolution

PRODUCTION_FASTAPI_DEPLOYMENT: YES, local Modular workstation only among known/authorized surfaces.

No authorized external Render/Railway/Fly/Vercel/VPS/container deployment was identified. The application repository contains no deployment manifest for those platforms.

## Production control host

The Data Integrity workstation is designated as the single future PRODUCTION_CONTROL_HOST because it has the required production capability and read-only DB tooling while no conflicting writer process was observed.

The Modular workstation remains production-capable but must be operationally inert during the migration window.

## DB-side quiescence

A read-only aggregate PostgreSQL session inspection is prepared in scripts/read-only/check-production-db-quiescence.py.

Immediately before 0008, acceptance requires:
- known writer surfaces disabled/quiescent;
- no unexpected active client/writer sessions;
- no idle-in-transaction sessions;
- no long-running transactions/queries;
- no running live-sync/backfill/statistics run records.

## Frozen ownership

- FIRST_NORMAL_WRITE_OWNER: MODULAR_PRINCIPAL
- REENABLE_OWNER: IT_SUPPORT_AGENT
- FIRST_CYCLE_MONITOR: MODULAR_PRINCIPAL + CLAUDE_AGENT + IT_SUPPORT_AGENT
- CHIEF_ARCHITECT: GO / NO-GO and exceptional rollback/restore authority

## Gate

PRODUCTION_FIXTURE_WRITERS_INVENTORIED: YES
UNKNOWN_WRITERS: 0 (within known/authorized PREDIKTIA runtime surfaces)
SAFE_TO_ENTER_0008_QUIESCENCE: YES
PRODUCTION_0008_EXECUTED: NO
PRODUCTION_CHANGED_BY_THIS_INVENTORY: NO
PRODUCTION_0008 remains HOLD until Chief opens the migration window and immediate pre-migration quiescence passes.