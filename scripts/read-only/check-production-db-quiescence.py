"""Read-only production DB quiescence inspection for the DI-A6 0008 window.

Requires DATABASE_URL in the environment. It never prints the URL, query text,
user names, client addresses, host names, or secrets.

PASS means PostgreSQL exposes no concurrent active/idle-in-transaction/long-running
sessions other than this inspection connection at the instant sampled.
It does not replace application-side writer shutdown.
"""

from __future__ import annotations

import os
import sys
from datetime import timedelta

import psycopg
from psycopg.rows import dict_row


def yn(value: bool) -> str:
    return "YES" if value else "NO"


def main() -> int:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        print("ERROR=DATABASE_URL_MISSING")
        return 2

    with psycopg.connect(url, autocommit=True, row_factory=dict_row) as conn:
        ssl_active = bool(conn.pgconn.ssl_in_use)
        with conn.cursor() as cur:
            cur.execute("BEGIN READ ONLY")
            cur.execute("SHOW transaction_read_only")
            read_only = str(cur.fetchone()["transaction_read_only"]).lower() in {"on", "true", "1"}

            cur.execute(
                """
                WITH s AS (
                    SELECT
                        pid,
                        state,
                        xact_start,
                        query_start,
                        backend_type,
                        wait_event_type,
                        wait_event
                    FROM pg_catalog.pg_stat_activity
                    WHERE datname = current_database()
                      AND pid <> pg_backend_pid()
                )
                SELECT
                    count(*)::int AS other_sessions_total,
                    count(*) FILTER (WHERE state = 'active')::int AS active_other_sessions,
                    count(*) FILTER (WHERE state = 'idle in transaction')::int AS idle_in_transaction_sessions,
                    count(*) FILTER (
                        WHERE xact_start IS NOT NULL
                          AND clock_timestamp() - xact_start > interval '5 minutes'
                    )::int AS long_running_transactions,
                    count(*) FILTER (
                        WHERE state = 'active'
                          AND query_start IS NOT NULL
                          AND clock_timestamp() - query_start > interval '5 minutes'
                    )::int AS long_running_active_queries,
                    count(*) FILTER (
                        WHERE backend_type = 'client backend'
                    )::int AS client_backend_sessions
                FROM s
                """
            )
            row = cur.fetchone()

            cur.execute(
                """
                SELECT count(*)::int AS waiting_client_backends
                FROM pg_catalog.pg_stat_activity
                WHERE datname = current_database()
                  AND pid <> pg_backend_pid()
                  AND backend_type = 'client backend'
                  AND wait_event_type IS NOT NULL
                """
            )
            waits = cur.fetchone()["waiting_client_backends"]

            cur.execute("ROLLBACK")

    values = {
        "OTHER_SESSIONS_TOTAL": row["other_sessions_total"],
        "ACTIVE_OTHER_SESSIONS": row["active_other_sessions"],
        "IDLE_IN_TRANSACTION_SESSIONS": row["idle_in_transaction_sessions"],
        "LONG_RUNNING_TRANSACTIONS_GT_5M": row["long_running_transactions"],
        "LONG_RUNNING_ACTIVE_QUERIES_GT_5M": row["long_running_active_queries"],
        "CLIENT_BACKEND_SESSIONS": row["client_backend_sessions"],
        "WAITING_CLIENT_BACKENDS": waits,
    }

    db_quiet = (
        values["ACTIVE_OTHER_SESSIONS"] == 0
        and values["IDLE_IN_TRANSACTION_SESSIONS"] == 0
        and values["LONG_RUNNING_TRANSACTIONS_GT_5M"] == 0
        and values["LONG_RUNNING_ACTIVE_QUERIES_GT_5M"] == 0
    )

    print("TRANSACTION_READ_ONLY=" + yn(read_only))
    print("SSL_CLIENT_ACTIVE=" + yn(ssl_active))
    for key, value in values.items():
        print(f"{key}={value}")
    print("DB_SIDE_QUIESCENCE=" + ("PASS" if read_only and ssl_active and db_quiet else "HOLD"))
    print("DATABASE_MUTATION=NO")
    print("SECRET_VALUES_PRINTED=NO")
    return 0 if read_only and ssl_active and db_quiet else 1


if __name__ == "__main__":
    sys.exit(main())
