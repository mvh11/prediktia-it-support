from __future__ import annotations

import sqlite3
from pathlib import Path

from .envelope import Envelope


class SharedStateStore:
    def __init__(self, db_path: str, context_limit_chars: int = 16000) -> None:
        self.db_path = db_path
        self.context_limit_chars = context_limit_chars
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self._init()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def _init(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS shared_messages (
                    message_id TEXT PRIMARY KEY,
                    reply_to TEXT NOT NULL,
                    from_id TEXT NOT NULL,
                    to_id TEXT NOT NULL,
                    type TEXT NOT NULL,
                    subject TEXT NOT NULL,
                    body TEXT NOT NULL,
                    hop_count INTEGER NOT NULL,
                    recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS durable_decisions (
                    decision_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_agent TEXT NOT NULL,
                    scope TEXT NOT NULL,
                    subject TEXT NOT NULL,
                    body TEXT NOT NULL,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS work_packages (
                    work_package_id TEXT PRIMARY KEY,
                    owner TEXT NOT NULL,
                    status TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS department_status (
                    agent_identity TEXT PRIMARY KEY,
                    status TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                """
            )

    def record_message(self, envelope: Envelope) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT OR IGNORE INTO shared_messages (
                    message_id, reply_to, from_id, to_id, type,
                    subject, body, hop_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    envelope.message_id,
                    envelope.reply_to,
                    envelope.from_id,
                    envelope.to_id,
                    envelope.type,
                    envelope.subject,
                    envelope.body,
                    envelope.hop_count,
                ),
            )

    def add_decision(
        self,
        *,
        source_agent: str,
        scope: str,
        subject: str,
        body: str,
    ) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO durable_decisions
                (source_agent, scope, subject, body)
                VALUES (?, ?, ?, ?)
                """,
                (source_agent, scope, subject, body),
            )

    def upsert_work_package(
        self,
        *,
        work_package_id: str,
        owner: str,
        status: str,
        summary: str,
    ) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO work_packages
                (work_package_id, owner, status, summary, updated_at)
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(work_package_id) DO UPDATE SET
                    owner = excluded.owner,
                    status = excluded.status,
                    summary = excluded.summary,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (work_package_id, owner, status, summary),
            )

    def upsert_department_status(
        self,
        *,
        agent_identity: str,
        status: str,
        summary: str,
    ) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO department_status
                (agent_identity, status, summary, updated_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(agent_identity) DO UPDATE SET
                    status = excluded.status,
                    summary = excluded.summary,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (agent_identity, status, summary),
            )

    def render_context(
        self,
        *,
        agent_identity: str,
        subject: str = "",
        reply_to: str = "",
        recent_messages: int = 20,
    ) -> str:
        blocks: list[str] = []
        with self._connect() as conn:
            decisions = conn.execute(
                """
                SELECT source_agent, scope, subject, body
                FROM durable_decisions
                ORDER BY decision_id DESC
                LIMIT 12
                """
            ).fetchall()
            if decisions:
                blocks.append(
                    "DURABLE SHARED DECISIONS:\n"
                    + "\n".join(
                        f"- [{source}/{scope}] {subj}: {body}"
                        for source, scope, subj, body in reversed(decisions)
                    )
                )

            packages = conn.execute(
                """
                SELECT work_package_id, owner, status, summary
                FROM work_packages
                ORDER BY updated_at DESC
                LIMIT 20
                """
            ).fetchall()
            if packages:
                blocks.append(
                    "WORK PACKAGES:\n"
                    + "\n".join(
                        f"- {wp} | owner={owner} | status={status} | {summary}"
                        for wp, owner, status, summary in packages
                    )
                )

            statuses = conn.execute(
                """
                SELECT agent_identity, status, summary
                FROM department_status
                ORDER BY updated_at DESC
                """
            ).fetchall()
            if statuses:
                blocks.append(
                    "DEPARTMENT STATUS:\n"
                    + "\n".join(
                        f"- {agent}: {status} | {summary}"
                        for agent, status, summary in statuses
                    )
                )

            params: list[object] = [agent_identity, agent_identity]
            where = "(from_id = ? OR to_id = ?)"
            if reply_to:
                where += " OR message_id = ? OR reply_to = ?"
                params.extend([reply_to, reply_to])
            if subject.strip():
                where += " OR subject = ?"
                params.append(subject.strip())

            params.append(recent_messages)
            rows = conn.execute(
                f"""
                SELECT message_id, reply_to, from_id, to_id, type, subject, body, hop_count
                FROM shared_messages
                WHERE {where}
                ORDER BY recorded_at DESC
                LIMIT ?
                """,
                params,
            ).fetchall()

            if rows:
                blocks.append(
                    "RELEVANT SHARED MESSAGES:\n"
                    + "\n\n".join(
                        (
                            f"MESSAGE_ID={message_id} REPLY_TO={reply} HOP={hop}\n"
                            f"FROM={from_id} TO={to_id} TYPE={msg_type}\n"
                            f"SUBJECT={subj}\nBODY={body}"
                        )
                        for message_id, reply, from_id, to_id, msg_type, subj, body, hop
                        in reversed(rows)
                    )
                )

        rendered = "\n\n".join(blocks)
        return rendered[-self.context_limit_chars :]
