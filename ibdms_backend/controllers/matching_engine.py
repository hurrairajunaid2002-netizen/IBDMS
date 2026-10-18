"""
Haversine Matching Engine
=========================
Bounding-box pre-filter + exact Haversine refinement (R = 6371 km).
Self-exclusion via exclude_user_ids (JWT user isolation).
"""

import math
import os
import traceback
from datetime import datetime, timedelta
from typing import List, Optional, Sequence, Tuple

from sqlalchemy.orm import Session

from controllers.blood_compatibility import (
    compatible_donor_groups,
    is_donor_compatible,
    normalize_blood_group,
)
from models.donor import DonorProfile
from models.user import User

DONATION_DEFERRAL_DAYS = 60
EARTH_RADIUS_KM = 6371.0
MATCH_DEBUG = os.getenv("IBDMS_MATCH_DEBUG", "1").lower() not in ("0", "false", "no")


def _dbg(msg: str) -> None:
    if MATCH_DEBUG:
        print(f"[MATCH-DEBUG] {msg}", flush=True)


def _critical(user_id: object, msg: str) -> None:
    print(f"[CRITICAL DEBUG] User {user_id} {msg}", flush=True)


def parse_coords(
    lat: object,
    lon: object,
    user_id: object = "?",
    role: str = "user",
) -> Optional[Tuple[float, float]]:
    """
    Return (lat, lon) or None if missing / 0.0 / invalid.
    Never raises — excludes bad rows without crashing the pipeline.
    """
    if lat is None or lon is None or lat == "" or lon == "":
        _critical(user_id, f"has empty/null {role} location coordinates!")
        return None
    try:
        lat_f = float(lat)
        lon_f = float(lon)
    except (TypeError, ValueError):
        _critical(user_id, f"has non-numeric {role} coordinates ({lat!r}, {lon!r})!")
        return None
    if not math.isfinite(lat_f) or not math.isfinite(lon_f):
        _critical(user_id, f"has non-finite {role} coordinates ({lat_f}, {lon_f})!")
        return None
    if abs(lat_f) < 0.0001 and abs(lon_f) < 0.0001:
        _critical(user_id, "has empty/0.0 location coordinates!")
        return None
    if not (-90 <= lat_f <= 90 and -180 <= lon_f <= 180):
        _critical(user_id, f"has out-of-range {role} coordinates ({lat_f}, {lon_f})!")
        return None
    return lat_f, lon_f


def calculate_haversine_distance(
    lat1: float, lon1: float, lat2: float, lon2: float
) -> float:
    """Great-circle distance in kilometres (Earth radius = 6371 km)."""
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1 - a)))
    return EARTH_RADIUS_KM * c


def log_distance_pair(
    searcher_user_id: object,
    req_lat: float,
    req_lon: float,
    donor_user_id: object,
    d_lat: float,
    d_lon: float,
) -> float:
    """Log exact distance in metres; return distance in km."""
    dist_km = calculate_haversine_distance(req_lat, req_lon, d_lat, d_lon)
    dist_m = dist_km * 1000.0
    print(
        f"[MATCH-DEBUG] Searcher user_id={searcher_user_id} coords=({req_lat:.6f}, {req_lon:.6f}) | "
        f"Donor user_id={donor_user_id} coords=({d_lat:.6f}, {d_lon:.6f}) | "
        f"distance={dist_m:.1f} m ({dist_km:.4f} km)",
        flush=True,
    )
    return dist_km


execute_haversine = calculate_haversine_distance


def _bounding_box(lat: float, lon: float, radius_km: float) -> tuple:
    lat_delta = radius_km / 111.0
    cos_lat = max(math.cos(math.radians(lat)), 0.01)
    lon_delta = radius_km / (111.0 * cos_lat)
    return (
        lat - lat_delta,
        lat + lat_delta,
        lon - lon_delta,
        lon + lon_delta,
    )


def _availability_is_active(status: object) -> bool:
    return str(status or "").strip().lower() == "active"


def process_matching_pipeline(
    db: Session,
    req_lat: float,
    req_lon: float,
    blood_group: str,
    search_radius: float,
    exclude_user_ids: Optional[Sequence[int]] = None,
    searcher_user_id: Optional[int] = None,
) -> list:
    """
    Find compatible, eligible donors within search_radius kilometres.
    Uses medically accurate ABO/Rh compatibility (not exact blood-type match).
    """
    recipient_blood = normalize_blood_group(blood_group)
    if not recipient_blood:
        _dbg(f"ABORT: invalid recipient blood group {blood_group!r}")
        return []

    donor_types = compatible_donor_groups(recipient_blood)
    _dbg("=" * 72)
    _dbg(
        f"PIPELINE START recipient={recipient_blood} "
        f"compatible_donors={donor_types} radius={search_radius} km "
        f"searcher_user_id={searcher_user_id}"
    )

    req_coords = parse_coords(req_lat, req_lon, searcher_user_id, role="searcher")
    if req_coords is None:
        _dbg("ABORT: searcher coordinates invalid")
        return []
    req_lat, req_lon = req_coords

    if not math.isfinite(search_radius) or search_radius <= 0:
        _dbg("ABORT: invalid search radius")
        return []

    exclude = {int(x) for x in (exclude_user_ids or [])}
    _dbg(f"Self-exclude user_ids (request owner only): {sorted(exclude) or '(none)'}")

    min_lat, max_lat, min_lon, max_lon = _bounding_box(req_lat, req_lon, search_radius)

    cooldown_gate = (
        datetime.utcnow() - timedelta(days=DONATION_DEFERRAL_DAYS)
    ).date()

    try:
        all_with_users = (
            db.query(DonorProfile, User)
            .join(User, DonorProfile.user_id == User.user_id)
            .all()
        )
    except Exception as exc:
        _dbg(f"FATAL: could not load donor profiles — {exc}")
        traceback.print_exc()
        return []

    _dbg(f"Total donor profiles in DB (before distance filter): {len(all_with_users)}")

    for donor, user in all_with_users:
        donor_coords = parse_coords(
            donor.gps_latitude,
            donor.gps_longitude,
            user.user_id,
            role="donor",
        )
        dist_km: Optional[float] = None
        if donor_coords is not None:
            d_lat, d_lon = donor_coords
            dist_km = log_distance_pair(
                searcher_user_id,
                req_lat,
                req_lon,
                user.user_id,
                d_lat,
                d_lon,
            )

        reasons: List[str] = []
        if user.user_id in exclude:
            reasons.append("SELF-EXCLUDED (request owner)")
        if not is_donor_compatible(donor.blood_group, recipient_blood):
            reasons.append(
                f"blood incompatible (donor={donor.blood_group!r}, "
                f"recipient={recipient_blood!r}, need one of {donor_types})"
            )
        if not _availability_is_active(donor.availability_status):
            reasons.append(f"availability={donor.availability_status!r} (need Active)")
        if donor_coords is None:
            reasons.append("invalid/missing GPS (excluded)")
        elif dist_km is not None and dist_km > search_radius:
            reasons.append(f"outside radius ({dist_km * 1000:.0f} m > {search_radius * 1000:.0f} m)")
        if donor.last_donation_date and donor.last_donation_date > cooldown_gate:
            reasons.append(f"60-day cooldown")

        verdict = "✓ ELIGIBLE" if not reasons else "✗ " + "; ".join(reasons)
        _dbg(f"  donor user_id={user.user_id} name={user.full_name!r} → {verdict}")

    # ── SQL bbox + blood pre-filter ───────────────────────────────────────────
    try:
        query = (
            db.query(DonorProfile, User)
            .join(User, DonorProfile.user_id == User.user_id)
            .filter(
                DonorProfile.blood_group.in_(donor_types),
                DonorProfile.gps_latitude.isnot(None),
                DonorProfile.gps_longitude.isnot(None),
                DonorProfile.gps_latitude >= min_lat,
                DonorProfile.gps_latitude <= max_lat,
                DonorProfile.gps_longitude >= min_lon,
                DonorProfile.gps_longitude <= max_lon,
            )
        )
        if exclude:
            query = query.filter(~User.user_id.in_(exclude))
        candidate_pool = [
            (d, u)
            for d, u in query.all()
            if _availability_is_active(d.availability_status)
            and is_donor_compatible(d.blood_group, recipient_blood)
        ]
    except Exception as exc:
        _dbg(f"FATAL: bbox SQL query failed — {exc}")
        traceback.print_exc()
        return []

    _dbg(f"After SQL bbox+blood filter: {len(candidate_pool)} candidate(s)")

    matched_cohort: List[dict] = []
    for donor, user in candidate_pool:
        if user.user_id in exclude:
            continue
        if donor.last_donation_date and donor.last_donation_date > cooldown_gate:
            continue

        donor_coords = parse_coords(
            donor.gps_latitude,
            donor.gps_longitude,
            user.user_id,
            role="donor",
        )
        if donor_coords is None:
            continue
        d_lat, d_lon = donor_coords

        distance = log_distance_pair(
            searcher_user_id,
            req_lat,
            req_lon,
            user.user_id,
            d_lat,
            d_lon,
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
                    "donor_latitude": d_lat,
                    "donor_longitude": d_lon,
                }
            )
            _dbg(f"  ✓ MATCHED user_id={user.user_id} at {distance * 1000:.1f} m")

    matched_cohort.sort(key=lambda x: x["distance_km"])
    _dbg(f"PIPELINE END → {len(matched_cohort)} donor(s) matched")
    _dbg("=" * 72)
    return matched_cohort


def get_donor_cooldown(donor: DonorProfile) -> dict:
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
