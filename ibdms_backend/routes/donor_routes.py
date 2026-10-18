from datetime import datetime, date as date_type
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from typing import Optional

from config.database import get_db
from middleware.auth_guard import get_current_user
from models.donor import DonorProfile
from models.user import User

router = APIRouter(prefix="/api/donor", tags=["Donor Profile Management"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class AvailabilityUpdateSchema(BaseModel):
    status: str  # "Active" or "Inactive"


class DonorEnrollSchema(BaseModel):
    """Fields required to self-enrol any authenticated user as a donor volunteer."""
    blood_group: str = Field(..., max_length=5)
    weight_kg: float = Field(..., ge=30.0)
    dob: str = Field(..., description="YYYY-MM-DD")
    gps_latitude: float = 24.8607
    gps_longitude: float = 67.0011


class DonorLocationUpdateSchema(BaseModel):
    """Live GPS ping — matching uses donor_profiles.gps_* (not phone cache)."""
    gps_latitude: float
    gps_longitude: float


# ── GET /api/donor/profile ────────────────────────────────────────────────────

@router.get("/profile")
def get_donor_profile(
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Return the logged-in user's account info and donor profile (if enrolled)."""
    user = db.query(User).filter(User.user_id == current_user["user_id"]).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    donor = (
        db.query(DonorProfile)
        .filter(DonorProfile.user_id == current_user["user_id"])
        .first()
    )

    return {
        "user_id": user.user_id,
        "full_name": user.full_name,
        "email": user.email,
        "phone_number": user.phone_number,
        "role": user.role,
        "donor_profile": (
            {
                "blood_group": donor.blood_group,
                "weight_kg": float(donor.weight_kg),
                "availability_status": donor.availability_status,
                "last_donation_date": (
                    donor.last_donation_date.isoformat()
                    if donor.last_donation_date
                    else None
                ),
            }
            if donor
            else None
        ),
    }


# ── POST /api/donor/enroll ────────────────────────────────────────────────────

@router.post("/enroll", status_code=status.HTTP_201_CREATED)
def enroll_as_donor(
    payload: DonorEnrollSchema,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Dual-Role Enrolment: any authenticated user (regardless of their login
    role — Recipient or Admin) can register a DonorProfile here to volunteer
    as a blood donor.  If a DonorProfile already exists this is a no-op.
    """
    existing = (
        db.query(DonorProfile)
        .filter(DonorProfile.user_id == current_user["user_id"])
        .first()
    )
    if existing:
        return {
            "message": "Already enrolled as a donor volunteer.",
            "blood_group": existing.blood_group,
            "availability_status": existing.availability_status,
        }

    from controllers.matching_engine import parse_coords

    if parse_coords(payload.gps_latitude, payload.gps_longitude, current_user["user_id"], "donor") is None:
        raise HTTPException(
            status_code=400,
            detail="Invalid donor GPS. Enable location permission and retry enrolment.",
        )

    dob_parsed: date_type = date_type(2000, 1, 1)
    try:
        dob_parsed = datetime.strptime(payload.dob, "%Y-%m-%d").date()
    except ValueError:
        pass

    profile = DonorProfile(
        user_id=current_user["user_id"],
        blood_group=payload.blood_group,
        gps_latitude=payload.gps_latitude,
        gps_longitude=payload.gps_longitude,
        weight_kg=payload.weight_kg,
        dob=dob_parsed,
        haemoglobin_level=13.5,
        availability_status="Active",
        is_locked=False,
    )
    db.add(profile)
    db.commit()
    db.refresh(profile)

    return {
        "message": "Successfully enrolled as a donor volunteer.",
        "blood_group": profile.blood_group,
        "availability_status": profile.availability_status,
    }


# ── PUT /api/donor/location ───────────────────────────────────────────────────

@router.put("/location")
def update_donor_location(
    payload: DonorLocationUpdateSchema,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Refresh donor GPS on the profile used by the matching engine.
    Call this whenever the donor opens Active Alerts or toggles availability.
    """
    from controllers.matching_engine import _dbg

    donor = (
        db.query(DonorProfile)
        .filter(DonorProfile.user_id == current_user["user_id"])
        .first()
    )
    if not donor:
        raise HTTPException(
            status_code=404,
            detail="No donor profile found. Enroll first via POST /api/donor/enroll.",
        )

    old_lat = float(donor.gps_latitude)
    old_lon = float(donor.gps_longitude)
    donor.gps_latitude = payload.gps_latitude
    donor.gps_longitude = payload.gps_longitude
    db.commit()

    _dbg(
        f"PUT /api/donor/location user_id={current_user['user_id']} "
        f"({old_lat:.5f},{old_lon:.5f}) → "
        f"({payload.gps_latitude:.5f},{payload.gps_longitude:.5f})"
    )

    return {
        "message": "Donor location updated.",
        "gps_latitude": float(donor.gps_latitude),
        "gps_longitude": float(donor.gps_longitude),
    }


# ── PUT /api/donor/availability ───────────────────────────────────────────────

@router.get("/cooldown")
def get_donor_cooldown(
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Returns the 60-day donation deferral status for the current user.
    Frontend uses this to display the cooldown screen instead of the donor feed.
    """
    from controllers.matching_engine import get_donor_cooldown

    donor = (
        db.query(DonorProfile)
        .filter(DonorProfile.user_id == current_user["user_id"])
        .first()
    )
    if not donor:
        return {"is_in_cooldown": False, "days_remaining": 0, "has_donor_profile": False}

    cooldown = get_donor_cooldown(donor)
    cooldown["has_donor_profile"] = True
    return cooldown


@router.put("/availability")
def update_availability(
    payload: AvailabilityUpdateSchema,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),  # Any role — not just Donor
):
    """
    Toggle donor availability.  Open to ANY authenticated user who has a
    DonorProfile (i.e. enrolled via /api/donor/enroll or during Donor registration).
    """
    allowed = {"Active", "Inactive"}
    if payload.status not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Status must be one of {allowed}.",
        )

    donor = (
        db.query(DonorProfile)
        .filter(DonorProfile.user_id == current_user["user_id"])
        .first()
    )
    if not donor:
        raise HTTPException(
            status_code=404,
            detail="No donor profile found. Enroll first via POST /api/donor/enroll.",
        )

    donor.availability_status = payload.status
    db.commit()
    return {"availability_status": donor.availability_status}
