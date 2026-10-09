# Current status — IT support

Last updated: 2026-10-09 (bootstrap session)

Legend:
- **VERIFIED** — checked directly by IT_SUPPORT_AGENT, with evidence.
- **REPORTED** — stated by CHIEF_ARCHITECT / a department; not independently
  verified by IT.
- **PENDING** — not yet checked or not yet decided.

## 1. Project phase

| Item | Value | Status |
|------|-------|--------|
| Phase | M5.9C — production-readiness coordination | REPORTED |
| Canonical development baseline | `1c06ef9c2a78a556cd8c7ded89853c19ec9a856a` | REPORTED |
| Locally validated Modular candidate | `d31eebc8e923c3d0351ac55086e53e08c2a5f62b` | REPORTED |

## 2. Production restrictions (in force)

```
M5.9D_AUTHORIZED:        NO
REAL_PREDICTIONS:        OFF
SCHEDULER_ACTIVATED:     NO
STATISTICS_CATCHUP:      HOLD
APPLICATION_MIGRATIONS:  HOLD
MAIN_MERGE:              HOLD
```

Status: REPORTED. Any change requires CHIEF_ARCHITECT.

## 3. Active infrastructure workstreams

| # | Workstream | Accepted direction | State |
|---|-----------|--------------------|-------|
| 1 | Neon least-privilege read-only access | See §4 | Design; creation **not authorized** |
| 2 | External scheduler | managed external scheduler → authenticated dispatch → GitHub `workflow_dispatch` → deterministic `tick_id` → Prediktia execution → expected/observed reconciliation | Design; **do not activate** |
| 3 | Prospective emitter environment | dedicated Linux/cloud env (not dev PC); least privilege; immutable artifact with git commit/digest; external secrets; controlled deploy; restart must **not** trigger catch-up | Design; deployment not authorized |
| 4 | UTC/time synchronization | authoritative UTC on scheduler and emitter | PENDING |
| 5 | RFC3161 timestamping | per tick/batch; TSA receives digest only; preserve token + verification evidence | Design |
| 6 | Independent backup/restore | Neon native recovery is insufficient; independent backup outside Neon/emitter; restore to isolated env first; validate hash-chain + RFC3161 evidence after restore | Design; policy change needs Chief |
| 7 | Security and credential boundaries | separate reader vs. writer credentials; secrets external; none in repos | Ongoing |

## 4. Neon read-only access — proposed design

```
prediktia_prospective_ro      NOLOGIN   (permission role)
prediktia_prospective_reader  LOGIN     (member of _ro)
```

Principles: explicit CONNECT; explicit schema USAGE; explicit object-level
SELECT; no `pg_read_all_data`; no blanket `SELECT ON ALL TABLES` without Chief
approval; no broad default privileges; no writes; no DDL; credentials separate
from application writers; `default_transaction_read_only = on` as
defense-in-depth.

Pre-creation verification checklist (all **PENDING**):

- [ ] exact target database
- [ ] schemas in scope
- [ ] exact objects the reader requires
- [ ] PUBLIC privileges (database, schemas, functions)
- [ ] TEMP privilege
- [ ] existing roles and memberships
- [ ] object owners
- [ ] RLS status on target tables
- [ ] default privileges (`pg_default_acl`)

## 5. Verified by IT

- This repository initialized (bootstrap commit). Nothing else verified yet.

## 6. Current blockers

| Blocker | Needed from |
|---------|-------------|
| No read-only access to Neon yet to run the §4 checklist | CHIEF_ARCHITECT (authorize a read-only inspection path) |
| Required object list for the prospective reader not defined | MODULAR_PRINCIPAL / Data Integrity |
| Scheduler provider and emitter hosting not selected | CHIEF_ARCHITECT |
| TSA provider(s) for RFC3161 not selected | CHIEF_ARCHITECT |
| Independent backup target/location not selected | CHIEF_ARCHITECT |

## 7. Next IT actions (read-only, within standing authority)

1. Prepare read-only audit queries for the §4 checklist (no execution against
   production until access is authorized).
2. Draft scheduler, emitter, RFC3161 and backup designs for Chief review.
