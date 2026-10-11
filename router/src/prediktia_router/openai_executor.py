from __future__ import annotations

import os
import time

from openai import OpenAI

from .executor import ExecutionRequest, ExecutionResult
from .usage import UsageStore


MODEL_PRICES_PER_MILLION = {
    "gpt-5.6-luna": {"input": 0.20, "cached": 0.02, "output": 1.20},
    "gpt-5.6-sol": {"input": 4.00, "cached": 0.40, "output": 20.00},
}


class TieredOpenAIExecutor:
    def __init__(
        self,
        *,
        economy_model: str = "gpt-5.6-luna",
        strong_model: str = "gpt-5.6-sol",
        usage_store: UsageStore | None = None,
        client: OpenAI | None = None,
    ) -> None:
        self.economy_model = economy_model
        self.strong_model = strong_model
        self.usage_store = usage_store
        if client is not None:
            self.client = client
        else:
            api_key = os.environ.get("OPENAI_API_KEY", "").strip()
            if not api_key:
                raise RuntimeError("OPENAI_API_KEY is required for ROUTER_EXECUTOR=openai")
            self.client = OpenAI(api_key=api_key)

    def _model_for(self, criticality: int) -> str:
        return self.economy_model if criticality <= 1 else self.strong_model

    @staticmethod
    def _estimated_cost(
        model: str,
        *,
        input_tokens: int,
        cached_tokens: int,
        output_tokens: int,
    ) -> float:
        prices = MODEL_PRICES_PER_MILLION.get(model)
        if prices is None:
            return 0.0

        uncached = max(input_tokens - cached_tokens, 0)
        return (
            uncached * prices["input"]
            + cached_tokens * prices["cached"]
            + output_tokens * prices["output"]
        ) / 1_000_000

    def execute(self, request: ExecutionRequest) -> ExecutionResult:
        model = self._model_for(request.criticality)
        stable_prefix = (
            "You are an execution runtime for the PREDIKTIA project. "
            "Respect the supplied agent identity and departmental authority. "
            "Do not invent permissions. Keep operational responses concise and explicit.\n\n"
            f"AGENT_IDENTITY: {request.agent_identity}\n"
        )
        prompt = (
            stable_prefix
            + f"MESSAGE_TYPE: {request.message_type}\n"
            + f"SUBJECT: {request.subject}\n\n"
            + f"CONTEXT:\n{request.context}\n\n"
            + f"REQUEST:\n{request.body}\n"
        )

        started = time.perf_counter()
        response = self.client.responses.create(
            model=model,
            input=prompt,
        )
        latency_ms = int((time.perf_counter() - started) * 1000)

        usage = getattr(response, "usage", None)
        input_tokens = int(getattr(usage, "input_tokens", 0) or 0)
        output_tokens = int(getattr(usage, "output_tokens", 0) or 0)
        details = getattr(usage, "input_tokens_details", None)
        cached_tokens = int(getattr(details, "cached_tokens", 0) or 0)

        result = ExecutionResult(
            agent_identity=request.agent_identity,
            model=model,
            response_text=response.output_text,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cached_tokens=cached_tokens,
            latency_ms=latency_ms,
            estimated_cost_usd=self._estimated_cost(
                model,
                input_tokens=input_tokens,
                cached_tokens=cached_tokens,
                output_tokens=output_tokens,
            ),
        )
        if self.usage_store is not None:
            self.usage_store.record(result)
        return result
