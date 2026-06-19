from sqlalchemy import Column, Integer, String, Enum, DateTime, func
from config.database import Base


class User(Base):
    __tablename__ = "users"

    user_id = Column(Integer, primary_key=True, autoincrement=True)
    full_name = Column(String(100), nullable=False)
    email = Column(String(100), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=True)  # nullable for Google-only accounts
    role = Column(Enum("Donor", "Recipient", "Administrator"), nullable=False, default="Donor")
    phone_number = Column(String(20), nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    # ── Universal profile fields (added v2.0) ─────────────────────────────────
    # blood_group: every user must declare their blood group at signup so
    #              both donation and request operations are immediately available.
    blood_group = Column(String(5), nullable=True)

    # google_id: populated when the account was created or linked via Google Sign-In.
    google_id = Column(String(128), nullable=True, unique=True)

    # fcm_token: Firebase Cloud Messaging device token for push notifications.
    #            Updated on each app launch via PUT /api/auth/fcm-token.
    fcm_token = Column(String(512), nullable=True)
