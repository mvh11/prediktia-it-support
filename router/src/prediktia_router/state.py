from __future__ import annotations

import sqlite3
from pathlib import Path


class ProcessedMessageStore:
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
                CREATE TABLE IF NOT EXISTS processed_messages (
                    dedupe_key TEXT PRIMARY KEY,
                    message_id TEXT NOT NULL,
                    slack_event_key TEXT NOT NULL,
                    processed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )

    def seen(self, slack_event_key: str, message_id: str) -> bool:
        key = self._key(slack_event_key, message_id)
        with self._connect() as conn:
            row = conn.execute(
                "SELECT 1 FROM processed_messages WHERE dedupe_key = ?",
                (key,),
            ).fetchone()
        return row is not None

    def mark(self, slack_event_key: str, message_id: str) -> None:
        key = self._key(slack_event_key, message_id)
        with self._connect() as conn:
            conn.execute(
                """
                INSERT OR IGNORE INTO processed_messages
                (dedupe_key, message_id, slack_event_key)
                VALUES (?, ?, ?)
                """,
                (key, message_id, slack_event_key),
            )

    @staticmethod
    def _key(slack_event_key: str, message_id: str) -> str:
        return f"{slack_event_key}::{message_id}"
