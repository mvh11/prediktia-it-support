# PREDIKTIA Agent Router V1

Minimal infrastructure runtime for routing explicit PREDIKTIA departmental messages.

## Security boundary

- No product database credentials.
- No product repository write access.
- No migrations.
- No scheduler or prediction activation.
- Secrets are environment-only.
- Unknown identities, malformed envelopes, duplicates, and excessive hop counts fail closed.

## V1 identities

- CHIEF_ARCHITECT
- MODULAR_PRINCIPAL
- DATA_INTEGRITY_CHIEF
- INTEGRATION_COORDINATOR

## Message envelope

Every routed message must contain, in order:

- FROM
- TO
- TYPE
- MESSAGE_ID
- REPLY_TO
- HOP_COUNT
- SUBJECT
- BODY

## Current implementation

The first scaffold contains:

- strict envelope parser;
- allowlisted routing core;
- execution-type classification;
- hop-limit enforcement;
- self-loop prevention;
- SQLite idempotency store;
- targeted unit tests.

Slack Socket Mode, OpenAI execution, Slack publishing, and internal redispatch are intentionally the next layer after the routing core is validated.

## Local test

```bash
cd router
python -m venv .venv
. .venv/bin/activate
pip install -e ".[test]"
pytest
```
