from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum

from .envelope import Envelope


class Criticality(IntEnum):
    RULES_ONLY = 0
    ECONOMY_MODEL = 1
    STRONG_MODEL = 2
    STRONG_MODEL_EXPANDED = 3


HIGH_RISK_TYPES = {
    "ARBITRATION_REQUEST",
    "DECISION_REQUEST",
}

RULES_ONLY_TYPES = {
    "INFO",
    "STATUS",
    "ACK",
}


@dataclass(frozen=True)
class CriticalityResult:
    level: Criticality
    reason: str


def classify_criticality(envelope: Envelope) -> CriticalityResult:
    message_type = envelope.type.upper()

    if message_type in RULES_ONLY_TYPES:
        return CriticalityResult(Criticality.RULES_ONLY, "non_decision_message")

    if message_type in HIGH_RISK_TYPES:
        return CriticalityResult(Criticality.STRONG_MODEL, "decision_or_arbitration")

    if message_type == "CHANGE_INTENT":
        body = f"{envelope.subject}\n{envelope.body}".lower()
        high_risk_markers = (
            "schema",
            "migration",
            "security",
            "ownership",
            "production",
            "contract",
            "temporal",
            "provider",
            "runtime",
        )
        if any(marker in body for marker in high_risk_markers):
            return CriticalityResult(
                Criticality.STRONG_MODEL_EXPANDED,
                "material_change_intent",
            )
        return CriticalityResult(Criticality.STRONG_MODEL, "change_intent")

    if message_type == "TASK":
        return CriticalityResult(Criticality.ECONOMY_MODEL, "routine_task")

    return CriticalityResult(Criticality.STRONG_MODEL, "unknown_or_ambiguous_type")
