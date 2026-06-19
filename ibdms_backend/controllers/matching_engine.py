"""
Haversine Matching Engine
=========================
Implements the exact spherical-distance formula specified in the IBDMS
architecture document, plus the donor eligibility pipeline.

60-Day Deferral Rule
--------------------
Whole-blood donors must wait at least 60 days (≈ 2 months) between
donations.  The matching pipeline enforces this via a strict date-delta
check against each candidate's last_donation_date.
"""

import math
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from models.donor import DonorProfile
from models.user import User

# ── Deferral constant ─────────────────────────────────────────────────────────
DONATION_DEFERRAL_DAYS = 60


# ── Core formula ──────────────────────────────────────────────────────────────

def calculate_haversine_distance(lat1: float, lon1: float,
                                  lat2: float, lon2: float) -> float:
    """
    Exact Haversine formula computing the great-circle distance between
    two GPS coordinates on Earth's surface.

    Args:
        lat1, lon1: Origin point (decimal degrees).
        lat2, lon2: Destination point (decimal degrees).

    Returns:
        Distance in kilometres.
    """
    R = 6371.0  # Earth's volumetric mean radius in km

    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)

    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c  # kilometres


# Alias kept for backward compatibility with existing imports.
execute_haversine = calculate_haversine_distance


# ── Donor eligibility pipeline ────────────────────────────────────────────────

def process_matching_pipeline(
    db: Session,
    req_lat: float,
    req_lon: float,
    blood_group: str,
    search_radius: float,
) -> list:
    """
    Find compatible, eligible donors within search_radius kilometres.

    Filters applied (in order):
      A. Blood group compatibility match.
      B. Availability status == 'Active'.
      C. 60-day deferral gate (last_donation_date must be > 60 days ago).
      D. Haversine distance ≤ search_radius.

    Returns a list of matched donor dicts, sorted by ascending distance.
    """
    candidate_pool = (
        db.query(DonorProfile, User)
        .join(User, DonorProfile.user_id == User.user_id)
        .filter(
            DonorProfile.blood_group == blood_group,
            DonorProfile.availability_status == "Active",
        )
        .all()
    )

    cooldown_gate = (
        datetime.utcnow() - timedelta(days=DONATION_DEFERRAL_DAYS)
    ).date()

    matched_cohort = []
    for donor, user in candidate_pool:
        # Filter C — 60-day deferral check.
        if donor.last_donation_date and donor.last_donation_date > cooldown_gate:
            continue

        # Filter D — Haversine spatial bounds check.
        distance = calculate_haversine_distance(
            req_lat, req_lon,
            float(donor.gps_latitude),
            float(donor.gps_longitude),
        )
        if distance <= search_radius:
            matched_cohort.append(
                {
                    "donor_id": donor.donor_id,
                    "user_id": user.user_id,
                    "name": user.full_name,
                    "phone": user.phone_number,
                    "email": user.email,
                    "blood_group": donor.blood_group,
                    "distance_km": round(distance, 2),
                    "fcm_token": user.fcm_token,
                }
            )

    return sorted(matched_cohort, key=lambda x: x["distance_km"])


# ── Cooldown utility ──────────────────────────────────────────────────────────

def get_donor_cooldown(donor: DonorProfile) -> dict:
    """
    Returns a cooldown status dict for a given DonorProfile.
    Used by GET /api/donor/cooldown to drive the frontend cooldown screen.
    """
    if not donor.last_donation_date:
        return {"is_in_cooldown": False, "days_remaining": 0}

    today = datetime.utcnow().date()
    delta = (today - donor.last_donation_date).days
    days_remaining = max(0, DONATION_DEFERRAL_DAYS - delta)
    eligible_date = donor.last_donation_date + timedelta(days=DONATION_DEFERRAL_DAYS)

    return {
        "is_in_cooldown": days_remaining > 0,
        "days_remaining": days_remaining,
        "last_donation_date": donor.last_donation_date.isoformat(),
        "eligible_date": eligible_date.isoformat(),
    }
