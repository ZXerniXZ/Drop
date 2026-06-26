from datetime import datetime, timezone
from typing import Any

from sqlalchemy import DateTime, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class JobDB(Base):
    __tablename__ = "upload_jobs"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    user_id: Mapped[str] = mapped_column(String, index=True, nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False, default="processing")
    phase: Mapped[str | None] = mapped_column(String, nullable=True)
    progress: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    result: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    note_id: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utc_now
    )

    def to_status_dict(self) -> dict[str, Any]:
        data: dict[str, Any] = {
            "job_id": self.id,
            "status": self.status,
        }
        if self.note_id:
            data["note_id"] = self.note_id
        if self.error:
            data["error"] = self.error
        if self.result:
            data["result"] = self.result
        if self.phase:
            data["phase"] = self.phase
        if self.progress:
            data["progress"] = self.progress
        return data
