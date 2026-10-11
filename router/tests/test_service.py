from pathlib import Path

from prediktia_router.executor import MockExecutor
from prediktia_router.service import RouterService
from prediktia_router.state import ProcessedMessageStore


def message(
    *,
    message_id: str = "m-1",
    to: str = "MODULAR_PRINCIPAL",
    type: str = "TASK",
    hop_count: int = 0,
) -> str:
    return (
        "FROM:\nCHIEF_ARCHITECT\n\n"
        f"TO:\n{to}\n\n"
        f"TYPE:\n{type}\n\n"
        f"MESSAGE_ID:\n{message_id}\n\n"
        "REPLY_TO:\nNONE\n\n"
        f"HOP_COUNT:\n{hop_count}\n\n"
        "SUBJECT:\nPhysical mock test\n\n"
        "BODY:\nRun safely"
    )


def service(tmp_path: Path) -> RouterService:
    return RouterService(
        runtime_identity="MODULAR_PRINCIPAL",
        executor=MockExecutor("PREDIKTIA_ROUTER_MOCK_OK"),
        state=ProcessedMessageStore(str(tmp_path / "state.sqlite3")),
    )


def test_task_generates_mock_response(tmp_path: Path):
    result = service(tmp_path).process(text=message(), slack_event_key="evt-1")
    assert result.action == "RESPOND"
    assert result.response_text == "PREDIKTIA_ROUTER_MOCK_OK"


def test_duplicate_is_dropped(tmp_path: Path):
    router = service(tmp_path)
    first = router.process(text=message(), slack_event_key="evt-1")
    second = router.process(text=message(), slack_event_key="evt-1")
    assert first.action == "RESPOND"
    assert second.action == "DROP"
    assert second.reason == "duplicate"


def test_status_does_not_call_model(tmp_path: Path):
    result = service(tmp_path).process(
        text=message(type="STATUS"), slack_event_key="evt-status"
    )
    assert result.action == "RECORD_ONLY"


def test_unknown_target_fails_closed(tmp_path: Path):
    result = service(tmp_path).process(
        text=message(to="UNKNOWN"), slack_event_key="evt-unknown"
    )
    assert result.action == "DROP"
    assert result.reason == "unknown_to"


def test_excessive_hop_count_fails_closed(tmp_path: Path):
    result = service(tmp_path).process(
        text=message(hop_count=9), slack_event_key="evt-hop"
    )
    assert result.action == "DROP"
    assert result.reason == "hop_limit_exceeded"


def test_malformed_envelope_fails_closed(tmp_path: Path):
    result = service(tmp_path).process(
        text="not an envelope", slack_event_key="evt-bad"
    )
    assert result.action == "DROP"
    assert result.reason.startswith("malformed_envelope:")
