from __future__ import annotations

import sqlite3
from pathlib import Path

from .executor import ExecutionResult


class UsageStore:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self._init()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def _init(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS usage_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    agent_identity TEXT NOT NULL,
                    model TEXT NOT NULL,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL,
                    cached_tokens INTEGER NOT NULL,
                    latency_ms INTEGER NOT NULL,
                    estimated_cost_usd REAL NOT NULL,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )

    def record(self, result: ExecutionResult) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO usage_events (
                    agent_identity, model, input_tokens, output_tokens,
                    cached_tokens, latency_ms, estimated_cost_usd
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    result.agent_identity,
                    result.model,
                    result.input_tokens,
                    result.output_tokens,
                    result.cached_tokens,
                    result.latency_ms,
                    result.estimated_cost_usd,
                ),
            )

    def totals(self) -> tuple[int, int, int, float]:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT
                    COALESCE(SUM(input_tokens), 0),
                    COALESCE(SUM(output_tokens), 0),
                    COALESCE(SUM(cached_tokens), 0),
                    COALESCE(SUM(estimated_cost_usd), 0)
                FROM usage_events
                """
            ).fetchone()
        return int(row[0]), int(row[1]), int(row[2]), float(row[3])
