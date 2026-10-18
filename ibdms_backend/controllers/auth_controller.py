"""
Authentication Controller
=========================
Handles: universal registration, credential login, Google Sign-In OIDC
         verification, profile completion, and forgot-password OTP flow.
"""

import os
import re
import secrets
from datetime import datetime, timedelta, date as date_type
from typing import Optional

import jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from models.user import User
from models.donor import DonorProfile
from schemas.auth_schema import (
    UserRegisterSchema,
    CompleteProfileSchema,
    ResetPasswordSchema,
)

from config.settings import GOOGLE_CLIENT_ID, JWT_SECRET
ALGORITHM = "HS256"
SECRET_KEY = JWT_SECRET
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ── In-memory OTP store (sufficient for FYP; replace with DB table in prod) ──
# Structure: { otp_string: {user_id, email, expires_at} }
_otp_store: dict = {}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _build_token(user: User) -> str:
    payload = {
        "sub": str(user.user_id),
        "role": user.role,
        "exp": datetime.utcnow() + timedelta(hours=24),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def _token_response(user: User, needs_profile: bool = False) -> dict:
    return {
        "access_token": _build_token(user),
        "token_type": "bearer",
        "role": user.role,
        "full_name": user.full_name,
        "blood_group": user.blood_group,
        "needs_profile": needs_profile,
        "needs_role_selection": user.role == "Unassigned",
    }


def _upsert_donor_profile(db: Session, user: User) -> None:
    """Create a DonorProfile for a newly registered universal user.
    Availability defaults to Inactive — user must explicitly enable it."""
    existing = db.query(DonorProfile).filter(
        DonorProfile.user_id == user.user_id
    ).first()
    if existing:
        return
    profile = DonorProfile(
        user_id=user.user_id,
        blood_group=user.blood_group or "O+",
        gps_latitude=24.8607,
        gps_longitude=67.0011,
        weight_kg=70.0,
        dob=date_type(1995, 1, 1),
        haemoglobin_level=13.5,
        availability_status="Inactive",  # User must opt-in to donate
        is_locked=False,
    )
    db.add(profile)


# ── Registration ──────────────────────────────────────────────────────────────

def register_new_user(db: Session, data: UserRegisterSchema) -> User:
    """
    Universal registration — no role selector.  New accounts start as
    role='Unassigned' until the user explicitly chooses Donor or Recipient
    during onboarding.
    """
    existing = db.query(User).filter(User.email == data.email).first()
    if existing:
        raise ValueError("An account with this email already exists.")

    hashed_pwd = pwd_context.hash(data.password)
    db_user = User(
        full_name=data.full_name,
        email=data.email,
        password_hash=hashed_pwd,
        role="Unassigned",
        phone_number=data.phone_number,
        blood_group=data.blood_group,
    )
    db.add(db_user)
    db.flush()  # Populate db_user.user_id without committing.

    # Bootstrap DonorProfile with supplied data if available.
    dob_parsed: date_type = date_type(1995, 1, 1)
    if data.dob:
        try:
            dob_parsed = datetime.strptime(data.dob, "%Y-%m-%d").date()
        except ValueError:
            pass

    profile = DonorProfile(
        user_id=db_user.user_id,
        blood_group=data.blood_group,
        gps_latitude=data.gps_latitude or 24.8607,
        gps_longitude=data.gps_longitude or 67.0011,
        weight_kg=data.weight_kg or 70.0,
        dob=dob_parsed,
        haemoglobin_level=13.5,
        availability_status="Inactive",
        is_locked=False,
    )
    db.add(profile)
    db.commit()
    db.refresh(db_user)
    return db_user


# ── Credential Login ──────────────────────────────────────────────────────────

def authenticate_user(db: Session, email: str, plain_password: str) -> Optional[dict]:
    user = db.query(User).filter(User.email == email.lower().strip()).first()
    if not user or not user.password_hash:
        return None
    if not pwd_context.verify(plain_password, user.password_hash):
        return None
    return _token_response(user)


# ── Google Sign-In ────────────────────────────────────────────────────────────

def google_signin(db: Session, id_token_str: str) -> dict:
    """
    Verify the Google ID token, then find-or-create the user record.
    Returns needs_profile=True when the account still needs phone/blood_group.

    Requires: pip install google-auth
    Setup:    Set GOOGLE_CLIENT_ID env var to your OAuth 2.0 client ID.
    """
    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests

        client_id = GOOGLE_CLIENT_ID
        if not client_id:
            raise ValueError(
                "GOOGLE_CLIENT_ID environment variable is not configured. "
                "See docs/SETUP_GOOGLE_SIGNIN.md for setup instructions."
            )

        idinfo = google_id_token.verify_oauth2_token(
            id_token_str,
            google_requests.Request(),
            client_id,
        )
        google_id = idinfo["sub"]
        email = idinfo.get("email", "").lower().strip()
        full_name = idinfo.get("name", email.split("@")[0])

    except ImportError:
        raise ValueError(
            "google-auth package not installed. Run: pip install google-auth"
        )

    # Find existing account by google_id or email.
    user = (
        db.query(User)
        .filter((User.google_id == google_id) | (User.email == email))
        .first()
    )

    if user is None:
        # Create a new universal account (no password needed for Google accounts).
        user = User(
            full_name=full_name,
            email=email,
            password_hash=None,
            role="Unassigned",
            phone_number="",
            blood_group=None,
            google_id=google_id,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    else:
        # Link google_id if the account was created via email/password.
        if not user.google_id:
            user.google_id = google_id
            db.commit()

    needs_profile = not user.phone_number or not user.blood_group
    return _token_response(user, needs_profile=needs_profile)


# ── Google Sign-In (Web / access-token fallback) ─────────────────────────────

def google_signin_web(db: Session, access_token_str: str) -> dict:
    """
    Web fallback: verify a Google OAuth2 access_token by calling Google's
    userinfo endpoint (https://www.googleapis.com/oauth2/v3/userinfo).
    Used when google_sign_in_web token-client flow returns no id_token.
    """
    import urllib.request
    import json as json_lib

    req = urllib.request.Request(
        "https://www.googleapis.com/oauth2/v3/userinfo",
        headers={"Authorization": f"Bearer {access_token_str}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            idinfo = json_lib.loads(resp.read().decode())
    except Exception as exc:
        raise ValueError(f"Could not verify Google access token: {exc}")

    google_id = idinfo.get("sub")
    email = idinfo.get("email", "").lower().strip()
    full_name = idinfo.get("name", email.split("@")[0])

    if not google_id or not email:
        raise ValueError("Google userinfo response missing required fields.")

    user = (
        db.query(User)
        .filter((User.google_id == google_id) | (User.email == email))
        .first()
    )

    if user is None:
        user = User(
            full_name=full_name,
            email=email,
            password_hash=None,
            role="Unassigned",
            phone_number="",
            blood_group=None,
            google_id=google_id,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    else:
        if not user.google_id:
            user.google_id = google_id
            db.commit()

    needs_profile = not user.phone_number or not user.blood_group
    return _token_response(user, needs_profile=needs_profile)


# ── Complete Profile (Google Sign-In) ─────────────────────────────────────────

def complete_profile(db: Session, user_id: int, data: CompleteProfileSchema) -> dict:
    """Finalise a Google-authenticated account that had missing profile data."""
    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise ValueError("User not found.")

    user.phone_number = data.phone_number
    user.blood_group = data.blood_group
    _upsert_donor_profile(db, user)
    db.commit()
    db.refresh(user)
    return _token_response(user, needs_profile=False)


# ── Role Selection (onboarding) ───────────────────────────────────────────────

def select_role(db: Session, user_id: int, role: str) -> dict:
    """Persist the user's explicit Donor vs Recipient preference."""
    if role not in ("Donor", "Recipient"):
        raise ValueError("Role must be Donor or Recipient.")

    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise ValueError("User not found.")
    if user.role == "Administrator":
        raise ValueError("Administrator accounts cannot change role here.")

    user.role = role
    db.commit()
    db.refresh(user)
    return _token_response(user, needs_profile=False)


# ── Forgot Password / OTP Reset ───────────────────────────────────────────────

def generate_reset_otp(db: Session, email: str) -> Optional[str]:
    """
    Creates a 6-digit OTP valid for 15 minutes.
    Returns the OTP (caller is responsible for emailing it).
    Returns None if no account exists for that email (caller should NOT
    reveal this to the client — always return HTTP 200 to prevent enum).
    """
    user = db.query(User).filter(User.email == email.lower().strip()).first()
    if not user:
        return None

    otp = str(secrets.randbelow(900_000) + 100_000)  # 6-digit: 100000–999999
    _otp_store[otp] = {
        "user_id": user.user_id,
        "email": email.lower().strip(),
        "expires_at": datetime.utcnow() + timedelta(minutes=15),
    }
    return otp


def reset_password(db: Session, data: ResetPasswordSchema) -> bool:
    """Verify OTP and update the user's password. Returns True on success."""
    record = _otp_store.get(data.otp)
    if not record:
        return False
    if record["email"] != data.email.lower().strip():
        return False
    if datetime.utcnow() > record["expires_at"]:
        _otp_store.pop(data.otp, None)
        return False

    user = db.query(User).filter(User.user_id == record["user_id"]).first()
    if not user:
        return False

    user.password_hash = pwd_context.hash(data.new_password)
    db.commit()
    _otp_store.pop(data.otp, None)
    return True


# ── FCM Token ─────────────────────────────────────────────────────────────────

def update_fcm_token(db: Session, user_id: int, token: str) -> None:
    """Store or refresh the device FCM token for push notifications."""
    user = db.query(User).filter(User.user_id == user_id).first()
    if user:
        user.fcm_token = token
        db.commit()
