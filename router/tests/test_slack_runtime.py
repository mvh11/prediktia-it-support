from prediktia_router.slack_runtime import _channel_allowlist


def test_channel_allowlist_parsing():
    assert _channel_allowlist("C1,C2, C3 ") == {"C1", "C2", "C3"}


def test_empty_channel_allowlist():
    assert _channel_allowlist("") == set()
    assert _channel_allowlist(None) == set()
