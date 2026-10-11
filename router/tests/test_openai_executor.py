from types import SimpleNamespace

from prediktia_router.executor import ExecutionRequest
from prediktia_router.openai_executor import TieredOpenAIExecutor


class FakeResponses:
    def __init__(self):
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(
            output_text="API_OK",
            usage=SimpleNamespace(
                input_tokens=100,
                output_tokens=20,
                input_tokens_details=SimpleNamespace(cached_tokens=40),
            ),
        )


class FakeClient:
    def __init__(self):
        self.responses = FakeResponses()


def request(criticality: int) -> ExecutionRequest:
    return ExecutionRequest(
        agent_identity="MODULAR_PRINCIPAL",
        message_type="TASK",
        subject="smoke",
        body="reply briefly",
        criticality=criticality,
    )


def test_criticality_one_uses_economy_model():
    client = FakeClient()
    out = TieredOpenAIExecutor(client=client).execute(request(1))
    assert out.model == "gpt-5.6-luna"
    assert client.responses.calls[0]["model"] == "gpt-5.6-luna"


def test_criticality_two_uses_strong_model():
    client = FakeClient()
    out = TieredOpenAIExecutor(client=client).execute(request(2))
    assert out.model == "gpt-5.6-sol"


def test_usage_and_cost_are_captured():
    out = TieredOpenAIExecutor(client=FakeClient()).execute(request(1))
    assert out.input_tokens == 100
    assert out.cached_tokens == 40
    assert out.output_tokens == 20
    assert out.estimated_cost_usd > 0
