from datetime import datetime, timezone

from sqlalchemy import DateTime, Float, String
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserServerUsage(Base):
    """Secondi di audio gia' fatturati sulla chiave OpenRouter del server."""

    __tablename__ = "user_server_usage"

    user_id: Mapped[str] = mapped_column(String, primary_key=True)
    billed_seconds: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utc_now
    )
