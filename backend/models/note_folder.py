from datetime import datetime, timezone

from sqlalchemy import DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class NoteFolderDB(Base):
    __tablename__ = "note_folders"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    user_id: Mapped[str] = mapped_column(String, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    parent_id: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utc_now
    )

    def to_dict(self) -> dict[str, str | None]:
        return {
            "id": self.id,
            "name": self.name,
            "parent_id": self.parent_id,
            "created_at": self.created_at.isoformat(),
        }
