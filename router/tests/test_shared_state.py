from pathlib import Path

from prediktia_router.envelope import Envelope
from prediktia_router.shared_state import SharedStateStore


def env(message_id: str, subject: str = "Shared contract") -> Envelope:
    return Envelope(
        from_id="CHIEF_ARCHITECT",
        to_id="DATA_INTEGRITY_CHIEF",
        type="DECISION_REQUEST",
        message_id=message_id,
        reply_to="NONE",
        hop_count=0,
        subject=subject,
        body="Review this decision.",
    )


def test_shared_message_is_available_to_target(tmp_path: Path):
    db = str(tmp_path / "router.sqlite3")
    store = SharedStateStore(db)
    store.record_message(env("m-1"))
    rendered = store.render_context(
        agent_identity="DATA_INTEGRITY_CHIEF",
        subject="Shared contract",
    )
    assert "m-1" in rendered
    assert "Review this decision." in rendered


def test_decisions_packages_and_status_are_rendered(tmp_path: Path):
    db = str(tmp_path / "router.sqlite3")
    store = SharedStateStore(db)
    store.add_decision(
        source_agent="CHIEF_ARCHITECT",
        scope="GLOBAL",
        subject="Temporal evidence",
        body="Frozen contract remains authoritative.",
    )
    store.upsert_work_package(
        work_package_id="DI-3",
        owner="DATA_INTEGRITY_CHIEF",
        status="ACTIVE",
        summary="Recovery and failure isolation.",
    )
    store.upsert_department_status(
        agent_identity="MODULAR_PRINCIPAL",
        status="WAIT",
        summary="Awaiting integration arbitration.",
    )
    rendered = store.render_context(agent_identity="DATA_INTEGRITY_CHIEF")
    assert "Temporal evidence" in rendered
    assert "DI-3" in rendered
    assert "MODULAR_PRINCIPAL" in rendered
