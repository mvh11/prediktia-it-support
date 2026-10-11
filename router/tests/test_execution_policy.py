from pathlib import Path

from prediktia_router.context_store import AgentContextStore
from prediktia_router.criticality import Criticality, classify_criticality
from prediktia_router.envelope import Envelope
from prediktia_router.executor import ExecutionRequest, MockExecutor
from prediktia_router.model_policy import ModelPolicy
from prediktia_router.usage import UsageStore


def env(message_type: str, subject: str = "subject", body: str = "body") -> Envelope:
    return Envelope(
        from_id="CHIEF_ARCHITECT",
        to_id="INTEGRATION_COORDINATOR",
        type=message_type,
        message_id="m-1",
        reply_to="NONE",
        hop_count=0,
        subject=subject,
        body=body,
    )


def test_status_is_rules_only():
    out = classify_criticality(env("STATUS"))
    assert out.level is Criticality.RULES_ONLY


def test_task_uses_economy_model():
    out = classify_criticality(env("TASK"))
    assert out.level is Criticality.ECONOMY_MODEL


def test_arbitration_uses_strong_model():
    out = classify_criticality(env("ARBITRATION_REQUEST"))
    assert out.level is Criticality.STRONG_MODEL


def test_material_change_intent_uses_expanded_strong_model():
    out = classify_criticality(
        env("CHANGE_INTENT", body="This changes schema and migration behavior")
    )
    assert out.level is Criticality.STRONG_MODEL_EXPANDED


def test_unknown_type_fails_up_to_strong_model():
    out = classify_criticality(env("SOMETHING_NEW"))
    assert out.level is Criticality.STRONG_MODEL


def test_model_policy():
    policy = ModelPolicy(economy_model="cheap", strong_model="strong")
    assert policy.model_for(Criticality.RULES_ONLY) is None
    assert policy.model_for(Criticality.ECONOMY_MODEL) == "cheap"
    assert policy.model_for(Criticality.STRONG_MODEL) == "strong"


def test_mock_executor():
    result = MockExecutor("ok").execute(
        ExecutionRequest(
            agent_identity="MODULAR_PRINCIPAL",
            message_type="TASK",
            subject="test",
            body="hello",
        )
    )
    assert result.response_text == "ok"
    assert result.model == "mock"


def test_context_store_persists(tmp_path: Path):
    path = str(tmp_path / "router.sqlite3")
    store = AgentContextStore(path)
    store.put("CHIEF_ARCHITECT", "durable", "recent")
    assert AgentContextStore(path).get("CHIEF_ARCHITECT") == ("durable", "recent")


def test_usage_store_totals(tmp_path: Path):
    path = str(tmp_path / "router.sqlite3")
    store = UsageStore(path)
    result = MockExecutor("ok").execute(
        ExecutionRequest(
            agent_identity="MODULAR_PRINCIPAL",
            message_type="TASK",
            subject="test",
            body="hello",
        )
    )
    store.record(result)
    assert store.totals() == (0, 0, 0, 0.0)
