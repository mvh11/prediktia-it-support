from pathlib import Path

import pytest

from prediktia_router.envelope import EnvelopeError, parse_envelope
from prediktia_router.routing import Decision, RouterCore
from prediktia_router.state import ProcessedMessageStore


def msg(**overrides):
    data = {
        "FROM": "CHIEF_ARCHITECT",
        "TO": "MODULAR_PRINCIPAL",
        "TYPE": "TASK",
        "MESSAGE_ID": "m-1",
        "REPLY_TO": "NONE",
        "HOP_COUNT": "0",
        "SUBJECT": "test",
        "BODY": "hello",
    }
    data.update(overrides)
    return "\n".join(f"{k}:\n{v}\n" for k, v in data.items())


def test_task_routes_to_target_runtime():
    env = parse_envelope(msg())
    out = RouterCore("MODULAR_PRINCIPAL").decide(env)
    assert out.decision is Decision.EXECUTE


def test_info_does_not_auto_execute():
    env = parse_envelope(msg(TYPE="STATUS"))
    out = RouterCore("MODULAR_PRINCIPAL").decide(env)
    assert out.decision is Decision.RECORD_ONLY


def test_unknown_to_fails_closed():
    env = parse_envelope(msg(TO="UNKNOWN_AGENT"))
    out = RouterCore("MODULAR_PRINCIPAL").decide(env)
    assert out.decision is Decision.DROP
    assert out.reason == "unknown_to"


def test_hop_limit():
    env = parse_envelope(msg(HOP_COUNT="9"))
    out = RouterCore("MODULAR_PRINCIPAL", max_hops=8).decide(env)
    assert out.decision is Decision.DROP
    assert out.reason == "hop_limit_exceeded"


def test_self_loop_prevention():
    env = parse_envelope(msg(FROM="MODULAR_PRINCIPAL"))
    out = RouterCore("MODULAR_PRINCIPAL").decide(env, emitted_by_runtime=True)
    assert out.decision is Decision.DROP
    assert out.reason == "self_loop"


def test_malformed_envelope_rejected():
    with pytest.raises(EnvelopeError):
        parse_envelope("FROM:\nCHIEF_ARCHITECT\nTO:\nMODULAR_PRINCIPAL")


def test_dedupe_state_persists(tmp_path: Path):
    path = str(tmp_path / "router.sqlite3")
    store = ProcessedMessageStore(path)
    assert not store.seen("evt-1", "m-1")
    store.mark("evt-1", "m-1")
    assert store.seen("evt-1", "m-1")
    assert ProcessedMessageStore(path).seen("evt-1", "m-1")
