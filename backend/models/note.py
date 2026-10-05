from datetime import datetime, timezone
from typing import Any

from sqlalchemy import DateTime, Float, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _key_data_has_substance(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    if str(value.get("location") or "").strip():
        return True
    for key in ("participants", "deadlines", "figures", "decisions"):
        items = value.get(key)
        if isinstance(items, list) and any(str(item).strip() for item in items):
            return True
    return False


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
    mind_map: Mapped[list[dict[str, Any]]] = mapped_column(
        JSON, nullable=False, default=list
    )
    # Timestamp reali di Whisper: [{start, end, text, words: [{w, start, end}]}]
    transcript_segments: Mapped[list[dict[str, Any]]] = mapped_column(
        JSON, nullable=False, default=list
    )
    audio_duration: Mapped[float | None] = mapped_column(Float, nullable=True)
    audio_filename: Mapped[str] = mapped_column(String, nullable=False, default="")
    source_language: Mapped[str | None] = mapped_column(String, nullable=True)
    output_language: Mapped[str | None] = mapped_column(String, nullable=True)
    source_share_token: Mapped[str | None] = mapped_column(
        String, index=True, nullable=True
    )
    # highlights / speakers / key_data -> "ready" once that analysis has run,
    # even when it found nothing.
    analysis_state: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utc_now
    )

    def effective_analysis_state(self) -> dict[str, str]:
        raw = self.analysis_state if isinstance(self.analysis_state, dict) else {}
        state = {str(key): str(value) for key, value in raw.items() if value}
        summary = self.summary or ""
        if "##" in summary:
            for key in ("highlights", "speakers", "key_data"):
                state.setdefault(key, "ready")
            return state
        if self.highlights:
            state.setdefault("highlights", "ready")
        if self.speaker_view:
            state.setdefault("speakers", "ready")
        if self.mind_map:
            state.setdefault("mind_map", "ready")
        if _key_data_has_substance(self.key_data):
            state.setdefault("key_data", "ready")
        return state

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
            "mind_map": self.mind_map or [],
            "analysis_state": self.effective_analysis_state(),
            "transcript_segments": self.transcript_segments or [],
            "audio_duration": self.audio_duration,
            "source_language": self.source_language,
            "output_language": self.output_language,
            "created_at": self.created_at.isoformat(),
        }
