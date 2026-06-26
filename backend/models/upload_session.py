from datetime import datetime, timezone
from typing import Any

from sqlalchemy import DateTime, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UploadSessionDB(Base):
    __tablename__ = "upload_sessions"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    user_id: Mapped[str] = mapped_column(String, index=True, nullable=False)
    filename: Mapped[str] = mapped_column(String, nullable=False)
    total_size: Mapped[int] = mapped_column(Integer, nullable=False)
    total_chunks: Mapped[int] = mapped_column(Integer, nullable=False)
    received_chunks: Mapped[list[int]] = mapped_column(
        JSON, nullable=False, default=list
    )
    metadata_json: Mapped[dict[str, Any]] = mapped_column(
        "metadata", JSON, nullable=False, default=dict
    )
    status: Mapped[str] = mapped_column(
        String, nullable=False, default="uploading"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utc_now
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    assembled_path: Mapped[str | None] = mapped_column(Text, nullable=True)

    def to_status_dict(self) -> dict[str, Any]:
        received = sorted(self.received_chunks or [])
        bytes_received = sum(
            _chunk_byte_size(self.total_size, self.total_chunks, i)
            for i in received
        )
        return {
            "upload_id": self.id,
            "status": self.status,
            "filename": self.filename,
            "total_size": self.total_size,
            "total_chunks": self.total_chunks,
            "received_chunks": received,
            "bytes_received": bytes_received,
            "chunk_size": CHUNK_SIZE,
        }


CHUNK_SIZE = 2 * 1024 * 1024
MAX_UPLOAD_BYTES = 500 * 1024 * 1024
SESSION_TTL_HOURS = 24
LEGACY_UPLOAD_MAX_BYTES = 4 * 1024 * 1024


def _chunk_byte_size(total_size: int, total_chunks: int, index: int) -> int:
    if index < 0 or index >= total_chunks:
        return 0
    if index < total_chunks - 1:
        return CHUNK_SIZE
    remainder = total_size % CHUNK_SIZE
    return remainder if remainder > 0 else CHUNK_SIZE


def expected_total_chunks(total_size: int) -> int:
    if total_size <= 0:
        return 0
    return (total_size + CHUNK_SIZE - 1) // CHUNK_SIZE
