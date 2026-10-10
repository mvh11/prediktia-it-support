# DI-A6 workstation runtime inventory — Host A (sanitized)

Classification: authorized PREDIKTIA workstation (Data Integrity lane)
Mode: read-only inventory

## Repository/runtime surface

- Multiple PREDIKTIA git worktrees are present.
- One primary backend .env is present with non-empty DATABASE_URL.
- The same primary backend .env contains non-empty provider API credentials.
- Dedicated DI-A6 rehearsal/G2 secret files are also present and are classified as non-production targets.
- Example/template env files are empty and do not confer runtime capability.

## Running processes

Observed relevant processes:
- Windows Terminal
- Claude client processes

Not observed:
- Python job process
- uvicorn/FastAPI process
- live_sync
- history_backfill
- ops_tick
- statistics_reconcile
- statistics_backfill

## Windows automation

- PREDIKTIA-related Task Scheduler entries: none found
- PREDIKTIA-related Windows services: none found
- Docker runtime: not installed or not in PATH

## WSL probe incident

The first audit attempted a WSL listing command. On this Windows build that command initiated WSL/component installation behavior instead of acting as a pure read. The audit was stopped without elevation; a restart was not performed for this task.

This means the original SYSTEM_MUTATION=NO line from that first local report is not accepted as authoritative. The inventory script has been corrected to never invoke wsl.exe; it now reads only Windows optional-feature state.

No PREDIKTIA process or writer was identified through the WSL output.

## Outstanding classification

The non-empty primary backend DATABASE_URL must still be classified as production vs non-production without exposing its value. Until that classification is complete:

- HAS_PRODUCTION_DATABASE_CREDENTIAL: unresolved
- MANUAL_CLI_CAPABILITY against production: unresolved
- Host A cannot yet be designated or excluded as PRODUCTION_CONTROL_HOST

No database mutation or application write was performed by the inventory.