from __future__ import annotations

from dataclasses import dataclass
from uuid import uuid4

from .context_store import AgentContextStore
from .criticality import Criticality, classify_criticality
from .envelope import Envelope, EnvelopeError, parse_envelope
from .executor import AgentExecutor, ExecutionRequest
from .routing import Decision, RouterCore
from .shared_state import SharedStateStore
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
        context_store: AgentContextStore | None = None,
        shared_state: SharedStateStore | None = None,
        max_hops: int = 8,
    ) -> None:
        self.runtime_identity = runtime_identity
        self.executor = executor
        self.state = state
        self.context_store = context_store
        self.shared_state = shared_state
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

        if self.shared_state is not None:
            self.shared_state.record_message(envelope)

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

        private_context = ""
        if self.context_store is not None:
            private_context = self.context_store.render(envelope.to_id)
            self.context_store.append_recent(
                envelope.to_id,
                "INBOUND:\n" + envelope.render(),
            )

        shared_context = ""
        if self.shared_state is not None:
            shared_context = self.shared_state.render_context(
                agent_identity=envelope.to_id,
                subject=envelope.subject,
                reply_to=envelope.reply_to,
            )

        combined_context = "\n\n".join(
            part for part in (private_context, shared_context, context) if part.strip()
        )

        execution = self.executor.execute(
            ExecutionRequest(
                agent_identity=envelope.to_id,
                message_type=envelope.type,
                subject=envelope.subject,
                body=envelope.body,
                context=combined_context,
                criticality=int(criticality.level),
            )
        )

        reply = Envelope(
            from_id=envelope.to_id,
            to_id=envelope.from_id,
            type="STATUS",
            message_id=str(uuid4()),
            reply_to=envelope.message_id,
            hop_count=envelope.hop_count + 1,
            subject=f"RE: {envelope.subject}",
            body=execution.response_text,
        )

        if self.context_store is not None:
            self.context_store.append_recent(
                envelope.to_id,
                "OUTBOUND:\n" + reply.render(),
            )

        if self.shared_state is not None:
            self.shared_state.record_message(reply)

        self.state.mark(slack_event_key, envelope.message_id)
        return ServiceResult("RESPOND", criticality.reason, reply.render())
