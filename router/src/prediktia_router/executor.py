from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class ExecutionRequest:
    agent_identity: str
    message_type: str
    subject: str
    body: str
    context: str = ""
    criticality: int = 1


@dataclass(frozen=True)
class ExecutionResult:
    agent_identity: str
    model: str
    response_text: str
    input_tokens: int = 0
    output_tokens: int = 0
    cached_tokens: int = 0
    latency_ms: int = 0
    estimated_cost_usd: float = 0.0


class AgentExecutor(Protocol):
    def execute(self, request: ExecutionRequest) -> ExecutionResult:
        ...


class MockExecutor:
    def __init__(self, response_text: str = "MOCK_OK") -> None:
        self.response_text = response_text

    def execute(self, request: ExecutionRequest) -> ExecutionResult:
        return ExecutionResult(
            agent_identity=request.agent_identity,
            model="mock",
            response_text=self.response_text,
        )
