# DI-A6 0008 production quiescence runbook (pre-GO design)

Status: design ready; migration window NOT started

## Frozen ownership

- FIRST_NORMAL_WRITE_OWNER: MODULAR_PRINCIPAL
- REENABLE_OWNER: IT_SUPPORT_AGENT
- FIRST_CYCLE_MONITOR: MODULAR_PRINCIPAL + CLAUDE_AGENT + IT_SUPPORT_AGENT
- CHIEF_ARCHITECT: GO / NO-GO and exceptional rollback/restore authority

## Designated production control host

PRODUCTION_CONTROL_HOST: Host A (Data Integrity workstation)

Rationale:
- production DB and provider capability is present;
- no Prediktia writer process is currently running;
- no local scheduled task or Windows service writer was found;
- Docker writer surface was not found;
- local IT bridge/tooling already exists for read-only DB checks;
- Host B currently has a long-running local uvicorn process and is therefore less suitable as the single control point.

Host B remains production-capable and must be made operationally inert for the window.

## Known writer surfaces and controls

### GitHub Actions

Writer-related workflows:
- ops-live
- ops-catalog
- ops-stats (statistics domain; included conservatively)

Control:
- PREDIKTIA_SCHEDULER_ENABLED must not equal true; preferred explicit state false.

Verification:
- latest/current runs are skipped before runner allocation;
- no active ops-* run exists immediately before migration.

### Host B local FastAPI

Control:
- stop uvicorn app.main --reload before the migration window.

Verification:
- no uvicorn/app.main process;
- no listener on local TCP 8000.

API sync guard:
- verify effective SYNC_ENDPOINTS_ENABLED is false on Host B before stopping the service;
- after the service is stopped the HTTP write surface is quiescent regardless of the flag.

### Manual CLI on Host A and Host B

Potential fixture writers:
- app.jobs.live_sync
- app.jobs.history_backfill

Control:
- no manual invocation during migration;
- only Host A is intentionally used as the controlled production execution point.

Verification:
- no running process commandline matches live_sync, history_backfill, or ops_tick;
- DB run tables contain no running live-sync/backfill/statistics run immediately before 0008.

## DB-side quiescence gate

Immediately before 0008, run the read-only aggregate session check from Host A.

Required checks:
- no unexpected active client sessions;
- no idle-in-transaction sessions;
- no long-running transactions;
- no long-running active queries;
- no writer-related run records in running state.

Acceptance requires both application-side quiescence and DB-side quiescence PASS.

## Re-enable sequence after Chief GO and successful migration

1. IT confirms DB/schema acceptance and authorizes re-enable sequence.
2. MODULAR_PRINCIPAL performs the first normal functional application write.
3. MODULAR_PRINCIPAL + CLAUDE_AGENT + IT_SUPPORT_AGENT monitor the first cycle.
4. IT re-enables scheduler/API/local service surfaces in the approved order.

Do not execute any of these steps until the production window is explicitly opened by Chief.