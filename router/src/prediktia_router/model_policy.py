from __future__ import annotations

from dataclasses import dataclass

from .criticality import Criticality


@dataclass(frozen=True)
class ModelPolicy:
    economy_model: str
    strong_model: str

    def model_for(self, criticality: Criticality) -> str | None:
        if criticality is Criticality.RULES_ONLY:
            return None
        if criticality is Criticality.ECONOMY_MODEL:
            return self.economy_model
        return self.strong_model
