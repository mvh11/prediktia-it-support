from __future__ import annotations

import sqlite3
from pathlib import Path


class AgentContextStore:
    def __init__(self, db_path: str, recent_limit_chars: int = 12000) -> None:
        self.db_path = db_path
        self.recent_limit_chars = recent_limit_chars
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self._init()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def _init(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS agent_context (
                    agent_identity TEXT PRIMARY KEY,
                    durable_context TEXT NOT NULL DEFAULT '',
                    recent_context TEXT NOT NULL DEFAULT '',
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )

    def get(self, agent_identity: str) -> tuple[str, str]:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT durable_context, recent_context
                FROM agent_context
                WHERE agent_identity = ?
                """,
                (agent_identity,),
            ).fetchone()
        if row is None:
            return "", ""
        return row[0], row[1]

    def put(
        self,
        agent_identity: str,
        durable_context: str,
        recent_context: str,
    ) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO agent_context
                (agent_identity, durable_context, recent_context, updated_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(agent_identity) DO UPDATE SET
                    durable_context = excluded.durable_context,
                    recent_context = excluded.recent_context,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (
                    agent_identity,
                    durable_context,
                    recent_context[-self.recent_limit_chars :],
                ),
            )

    def append_recent(self, agent_identity: str, text: str) -> None:
        durable, recent = self.get(agent_identity)
        joined = (recent + "\n\n" + text).strip()
        self.put(agent_identity, durable, joined)

    def render(self, agent_identity: str) -> str:
        durable, recent = self.get(agent_identity)
        parts = []
        if durable.strip():
            parts.append("DURABLE CONTEXT:\n" + durable.strip())
        if recent.strip():
            parts.append("RECENT CONTEXT:\n" + recent.strip())
        return "\n\n".join(parts)
