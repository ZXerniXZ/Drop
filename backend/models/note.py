from datetime import datetime, timezone
from typing import Any

from sqlalchemy import DateTime, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class NoteDB(Base):
    __tablename__ = "notes"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    user_id: Mapped[str] = mapped_column(String, index=True, nullable=False)
    title: Mapped[str] = mapped_column(String(80), nullable=False)
    summary: Mapped[str] = mapped_column(Text, nullable=False, default="")
    formatted_transcription: Mapped[str] = mapped_column(
        Text, nullable=False, default=""
    )
    raw_transcription: Mapped[str] = mapped_column(Text, nullable=False, default="")
    highlights: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    key_data: Mapped[dict[str, Any]] = mapped_column(
        JSON, nullable=False, default=dict
    )
    speaker_view: Mapped[list[dict[str, Any]]] = mapped_column(
        JSON, nullable=False, default=list
    )
    audio_filename: Mapped[str] = mapped_column(String, nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utc_now
    )

    def to_result_dict(self) -> dict[str, Any]:
        return {
            "success": True,
            "note_id": self.id,
            "filename": self.audio_filename,
            "raw_transcription": self.raw_transcription,
            "title": self.title,
            "formatted_transcription": self.formatted_transcription,
            "summary": self.summary,
            "highlights": self.highlights,
            "key_data": self.key_data,
            "speaker_view": self.speaker_view,
            "created_at": self.created_at.isoformat(),
        }
