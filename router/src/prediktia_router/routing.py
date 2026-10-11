from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .envelope import Envelope


ALLOWLISTED_IDENTITIES = {
    "CHIEF_ARCHITECT",
    "MODULAR_PRINCIPAL",
    "DATA_INTEGRITY_CHIEF",
    "INTEGRATION_COORDINATOR",
}

EXECUTING_TYPES = {
    "TASK",
    "DECISION_REQUEST",
    "CHANGE_INTENT",
    "ARBITRATION_REQUEST",
}


class Decision(str, Enum):
    EXECUTE = "EXECUTE"
    RECORD_ONLY = "RECORD_ONLY"
    DROP = "DROP"


@dataclass(frozen=True)
class RouteResult:
    decision: Decision
    reason: str


class RouterCore:
    def __init__(self, runtime_identity: str, max_hops: int = 8) -> None:
        if runtime_identity not in ALLOWLISTED_IDENTITIES:
            raise ValueError("runtime identity is not allowlisted")
        self.runtime_identity = runtime_identity
        self.max_hops = max_hops

    def decide(self, envelope: Envelope, emitted_by_runtime: bool = False) -> RouteResult:
        if envelope.to_id not in ALLOWLISTED_IDENTITIES:
            return RouteResult(Decision.DROP, "unknown_to")

        if envelope.hop_count > self.max_hops:
            return RouteResult(Decision.DROP, "hop_limit_exceeded")

        if emitted_by_runtime and envelope.from_id == self.runtime_identity:
            return RouteResult(Decision.DROP, "self_loop")

        if envelope.to_id != self.runtime_identity:
            return RouteResult(Decision.RECORD_ONLY, "not_for_this_runtime")

        if envelope.type in EXECUTING_TYPES:
            return RouteResult(Decision.EXECUTE, "execution_type")

        return RouteResult(Decision.RECORD_ONLY, "non_executing_type")
