from __future__ import annotations

from dataclasses import dataclass

REQUIRED_FIELDS = (
    "FROM",
    "TO",
    "TYPE",
    "MESSAGE_ID",
    "REPLY_TO",
    "HOP_COUNT",
    "SUBJECT",
    "BODY",
)


class EnvelopeError(ValueError):
    pass


@dataclass(frozen=True)
class Envelope:
    from_id: str
    to_id: str
    type: str
    message_id: str
    reply_to: str
    hop_count: int
    subject: str
    body: str

    def render(self) -> str:
        return (
            f"FROM:\n{self.from_id}\n\n"
            f"TO:\n{self.to_id}\n\n"
            f"TYPE:\n{self.type}\n\n"
            f"MESSAGE_ID:\n{self.message_id}\n\n"
            f"REPLY_TO:\n{self.reply_to}\n\n"
            f"HOP_COUNT:\n{self.hop_count}\n\n"
            f"SUBJECT:\n{self.subject}\n\n"
            f"BODY:\n{self.body}"
        )


def parse_envelope(text: str) -> Envelope:
    if not text or not text.strip():
        raise EnvelopeError("empty message")

    positions: list[tuple[int, str]] = []
    for field in REQUIRED_FIELDS:
        marker = f"{field}:"
        idx = text.find(marker)
        if idx < 0:
            raise EnvelopeError(f"missing field: {field}")
        positions.append((idx, field))

    positions.sort()
    if [field for _, field in positions] != list(REQUIRED_FIELDS):
        raise EnvelopeError("fields out of order")

    values: dict[str, str] = {}
    for i, (start, field) in enumerate(positions):
        value_start = start + len(field) + 1
        value_end = positions[i + 1][0] if i + 1 < len(positions) else len(text)
        values[field] = text[value_start:value_end].strip()

    for field in REQUIRED_FIELDS[:-1]:
        if values[field] == "":
            raise EnvelopeError(f"empty field: {field}")

    try:
        hop_count = int(values["HOP_COUNT"])
    except ValueError as exc:
        raise EnvelopeError("HOP_COUNT must be an integer") from exc

    if hop_count < 0:
        raise EnvelopeError("HOP_COUNT must be >= 0")

    return Envelope(
        from_id=values["FROM"],
        to_id=values["TO"],
        type=values["TYPE"],
        message_id=values["MESSAGE_ID"],
        reply_to=values["REPLY_TO"],
        hop_count=hop_count,
        subject=values["SUBJECT"],
        body=values["BODY"],
    )
