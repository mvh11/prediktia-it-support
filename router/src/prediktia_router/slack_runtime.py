from __future__ import annotations

import os
from collections.abc import Iterable

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

from .executor import AgentExecutor, MockExecutor
from .openai_executor import TieredOpenAIExecutor
from .service import RouterService
from .state import ProcessedMessageStore
from .usage import UsageStore


def _channel_allowlist(raw: str | None) -> set[str]:
    if not raw:
        return set()
    return {item.strip() for item in raw.split(",") if item.strip()}


def _build_executor(state_db: str) -> AgentExecutor:
    mode = os.getenv("ROUTER_EXECUTOR", "mock").strip().lower()
    if mode == "mock":
        return MockExecutor(os.getenv("ROUTER_MOCK_RESPONSE", "PREDIKTIA_ROUTER_MOCK_OK"))
    if mode == "openai":
        return TieredOpenAIExecutor(
            economy_model=os.getenv("ROUTER_ECONOMY_MODEL", "gpt-5.6-luna"),
            strong_model=os.getenv("ROUTER_STRONG_MODEL", "gpt-5.6-sol"),
            usage_store=UsageStore(state_db),
        )
    raise RuntimeError("ROUTER_EXECUTOR must be 'mock' or 'openai'")


def build_app(
    *,
    bot_token: str,
    runtime_identity: str,
    state_db: str,
    allowed_channels: Iterable[str],
    executor: AgentExecutor | None = None,
) -> App:
    app = App(token=bot_token)
    allowed = set(allowed_channels)
    service = RouterService(
        runtime_identity=runtime_identity,
        executor=executor or _build_executor(state_db),
        state=ProcessedMessageStore(state_db),
    )

    @app.event("message")
    def handle_message(event, say, logger):
        channel = event.get("channel")
        if channel not in allowed:
            return

        if event.get("subtype") is not None:
            return

        text = event.get("text") or ""
        event_key = event.get("client_msg_id") or event.get("ts") or ""
        if not event_key:
            logger.warning("Dropping Slack message without event key")
            return

        emitted_by_runtime = bool(event.get("bot_id"))
        result = service.process(
            text=text,
            slack_event_key=event_key,
            emitted_by_runtime=emitted_by_runtime,
        )
        if result.action == "RESPOND" and result.response_text:
            say(result.response_text)

    return app


def run_socket_mode() -> None:
    bot_token = os.environ["SLACK_BOT_TOKEN"]
    app_token = os.environ["SLACK_APP_TOKEN"]
    runtime_identity = os.environ["ROUTER_RUNTIME_IDENTITY"]
    state_db = os.getenv("ROUTER_STATE_DB", "./state/router.sqlite3")
    allowed_channels = _channel_allowlist(os.getenv("ROUTER_ALLOWED_CHANNELS"))

    if not allowed_channels:
        raise RuntimeError("ROUTER_ALLOWED_CHANNELS must contain at least one channel id")

    app = build_app(
        bot_token=bot_token,
        runtime_identity=runtime_identity,
        state_db=state_db,
        allowed_channels=allowed_channels,
    )
    SocketModeHandler(app, app_token).start()


if __name__ == "__main__":
    run_socket_mode()
