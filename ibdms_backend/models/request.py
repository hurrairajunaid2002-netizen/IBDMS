from sqlalchemy import Column, Integer, String, Numeric, Enum, DateTime, Float, ForeignKey, func
from config.database import Base


class BloodRequest(Base):
    __tablename__ = "blood_requests"

    request_id = Column(Integer, primary_key=True, autoincrement=True)
    recipient_user_id = Column(
        Integer, ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False
    )
    blood_group_needed = Column(String(5), nullable=False, index=True)
    units_required = Column(Integer, nullable=False)
    urgency_level = Column(Enum("Low", "Medium", "Critical"), nullable=False)
    request_latitude = Column(Numeric(10, 8), nullable=False)
    request_longitude = Column(Numeric(11, 8), nullable=False)

    # Extended status set — Cancelled and Unfulfilled support the escalation engine.
    status = Column(
        Enum("Pending", "Fulfilled", "Cancelled", "Unfulfilled", "Expired"),
        default="Pending",
        index=True,
    )

    # ── Time-staged radius escalation state ──────────────────────────────────
    # current_radius_km: the Haversine search boundary currently in effect.
    # search_updated_at: timestamp of the last radius increment (used by the
    #                    background worker to decide when to escalate again).
    # matched_count:     cached count of donors within current_radius_km.
    current_radius_km = Column(Float, default=5.0, nullable=False)
    search_updated_at = Column(DateTime, nullable=True)
    matched_count = Column(Integer, default=0, nullable=False)

    created_at = Column(DateTime, server_default=func.now())
    closed_at = Column(DateTime, nullable=True)
