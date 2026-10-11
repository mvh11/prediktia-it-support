from __future__ import annotations

from dataclasses import dataclass

from .criticality import Criticality, classify_criticality
from .envelope import EnvelopeError, parse_envelope
from .executor import AgentExecutor, ExecutionRequest
from .routing import Decision, RouterCore
from .state import ProcessedMessageStore


@dataclass(frozen=True)
class ServiceResult:
    action: str
    reason: str
    response_text: str | None = None


class RouterService:
    def __init__(
        self,
        *,
        runtime_identity: str,
        executor: AgentExecutor,
        state: ProcessedMessageStore,
        max_hops: int = 8,
    ) -> None:
        self.runtime_identity = runtime_identity
        self.executor = executor
        self.state = state
        self.core = RouterCore(runtime_identity=runtime_identity, max_hops=max_hops)

    def process(
        self,
        *,
        text: str,
        slack_event_key: str,
        emitted_by_runtime: bool = False,
        context: str = "",
    ) -> ServiceResult:
        try:
            envelope = parse_envelope(text)
        except EnvelopeError as exc:
            return ServiceResult("DROP", f"malformed_envelope:{exc}")

        if self.state.seen(slack_event_key, envelope.message_id):
            return ServiceResult("DROP", "duplicate")

        route = self.core.decide(envelope, emitted_by_runtime=emitted_by_runtime)
        if route.decision is Decision.DROP:
            self.state.mark(slack_event_key, envelope.message_id)
            return ServiceResult("DROP", route.reason)

        if route.decision is Decision.RECORD_ONLY:
            self.state.mark(slack_event_key, envelope.message_id)
            return ServiceResult("RECORD_ONLY", route.reason)

        criticality = classify_criticality(envelope)
        if criticality.level is Criticality.RULES_ONLY:
            self.state.mark(slack_event_key, envelope.message_id)
            return ServiceResult("RECORD_ONLY", criticality.reason)

        execution = self.executor.execute(
            ExecutionRequest(
                agent_identity=envelope.to_id,
                message_type=envelope.type,
                subject=envelope.subject,
                body=envelope.body,
                context=context,
            )
        )
        self.state.mark(slack_event_key, envelope.message_id)
        return ServiceResult("RESPOND", criticality.reason, execution.response_text)
