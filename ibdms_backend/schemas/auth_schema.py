import re
from pydantic import BaseModel, EmailStr, Field, field_validator
from typing import Optional

# RFC 5322 compliant email regex used across all registration flows.
_EMAIL_RE = re.compile(
    r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$"
)


class UserRegisterSchema(BaseModel):
    """
    Universal registration schema — no role selector.
    All users are created as universal entities ('Donor' role by default).
    Blood group is mandatory for every account so the dual-role system works
    immediately after signup without additional onboarding steps.
    """
    full_name: str = Field(..., min_length=3, max_length=100)
    email: EmailStr
    password: str = Field(..., min_length=6)
    phone_number: str = Field(..., min_length=7, max_length=20)
    blood_group: str = Field(..., max_length=5, description="A+, A-, B+, B-, AB+, AB-, O+, O-")

    # Optional donor-profile bootstrap fields (GPS captured on mobile).
    weight_kg: Optional[float] = Field(None, ge=30.0)
    dob: Optional[str] = Field(None, description="YYYY-MM-DD")
    gps_latitude: Optional[float] = 24.8607
    gps_longitude: Optional[float] = 67.0011

    @field_validator("email")
    @classmethod
    def validate_email_format(cls, v: str) -> str:
        if not _EMAIL_RE.match(v):
            raise ValueError("Invalid email format. Must be a valid RFC-5322 address.")
        return v.lower().strip()

    @field_validator("blood_group")
    @classmethod
    def validate_blood_group(cls, v: str) -> str:
        valid = {"A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"}
        if v.upper() not in valid:
            raise ValueError(f"Blood group must be one of: {', '.join(sorted(valid))}")
        return v.upper()

    @field_validator("phone_number")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        digits = re.sub(r"[\s\-\+\(\)]", "", v)
        if not digits.isdigit() or len(digits) < 7:
            raise ValueError("Phone number must contain at least 7 digits.")
        return v.strip()


class GoogleSignInSchema(BaseModel):
    """Payload from the Flutter google_sign_in plugin."""
    id_token: str
    access_token: Optional[str] = None


class CompleteProfileSchema(BaseModel):
    """Sent after Google Sign-In when blood_group or phone_number is missing."""
    phone_number: str = Field(..., min_length=7, max_length=20)
    blood_group: str = Field(..., max_length=5)
    weight_kg: Optional[float] = None
    dob: Optional[str] = None

    @field_validator("blood_group")
    @classmethod
    def validate_bg(cls, v: str) -> str:
        valid = {"A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"}
        if v.upper() not in valid:
            raise ValueError(f"Blood group must be one of: {', '.join(sorted(valid))}")
        return v.upper()


class ForgotPasswordSchema(BaseModel):
    email: EmailStr

    @field_validator("email")
    @classmethod
    def validate_email_format(cls, v: str) -> str:
        if not _EMAIL_RE.match(v):
            raise ValueError("Invalid email address.")
        return v.lower().strip()


class ResetPasswordSchema(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=6, max_length=6)
    new_password: str = Field(..., min_length=6)


class FcmTokenUpdateSchema(BaseModel):
    fcm_token: str


class UserLoginSchema(BaseModel):
    email: EmailStr
    password: str


class TokenResponseSchema(BaseModel):
    access_token: str
    token_type: str
    role: str
    full_name: str
    blood_group: Optional[str] = None
    needs_profile: bool = False  # True when Google user has no phone/blood_group
