from sqlalchemy import (
    Column,
    Integer,
    Float,
    Enum,
    DateTime,
    ForeignKey,
    UniqueConstraint,
    func,
)
from config.database import Base


class DonorMatchResponse(Base):
    """
    Per-donor match decision pipeline.

    States
    ------
    FOUND             — match identified; both parties notified; awaiting recipient decision.
    ACCEPTED          — recipient chose "Connect & Contact"; contact + GPS unlocked.
    CONTINUED_SEARCH  — saved as backup; recipient chose "Keep Looking"; search continues.
    REJECTED          — donor or system declined.
    COMPLETED         — donation handoff marked complete.
    """

    __tablename__ = "donor_match_responses"
    __table_args__ = (
        UniqueConstraint("request_id", "donor_user_id", name="uq_request_donor"),
    )

    match_id = Column(Integer, primary_key=True, autoincrement=True)
    request_id = Column(
        Integer,
        ForeignKey("blood_requests.request_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    donor_user_id = Column(
        Integer,
        ForeignKey("users.user_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    status = Column(
        Enum(
            "FOUND",
            "ACCEPTED",
            "CONTINUED_SEARCH",
            "REJECTED",
            "COMPLETED",
        ),
        nullable=False,
        default="FOUND",
        index=True,
    )
    distance_km = Column(Float, nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
