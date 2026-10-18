"""
Enterprise Matching Service
===========================
Location-aware donor discovery with:
  • Bounding-box pre-filter + Haversine refinement
  • Auto-expanding radius (+5 km steps from 5 → 50 km)
  • Strict self-exclusion by JWT user id
  • Two-stage privacy DTO serialization
  • DonorMatchResponse consent record sync
"""

from __future__ import annotations

import math
from datetime import datetime
from typing import Iterable, List, Optional, Sequence, Tuple

from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError

from controllers.matching_engine import (
    calculate_haversine_distance,
    process_matching_pipeline,
)
from controllers.blood_compatibility import is_donor_compatible, normalize_blood_group
from models.match import DonorMatchResponse
from models.request import BloodRequest
from models.user import User
from schemas.match_schema import (
    AuthorizedDonorDTO,
    DiscoveryDonorDTO,
    DiscoveryRequestDTO,
    MatchOverviewDTO,
)

# ── Radius policy (5 km start, +5 km every 2 min, max 50 km) ─────────────────
INITIAL_RADIUS_KM: float = 5.0
STEP_KM: float = 5.0
MAX_RADIUS_KM: float = 50.0


def bounding_box(
    lat: float, lon: float, radius_km: float
) -> Tuple[float, float, float, float]:
    """Approximate lat/lon bounds before Haversine (1° lat ≈ 111 km)."""
    lat_delta = radius_km / 111.0
    cos_lat = max(math.cos(math.radians(lat)), 0.01)
    lon_delta = radius_km / (111.0 * cos_lat)
    return (
        lat - lat_delta,
        lat + lat_delta,
        lon - lon_delta,
        lon + lon_delta,
    )


def next_radius_tier(current_km: float) -> float:
    """Next escalation step: +5 km up to the 50 km ceiling."""
    return min(float(current_km) + STEP_KM, MAX_RADIUS_KM)


def distance_label(km: float) -> str:
    return f"{km:.1f} km away"


def donor_alias(full_name: str) -> str:
    parts = (full_name or "Donor").strip().split()
    if not parts:
        return "Donor"
    if len(parts) == 1:
        return parts[0]
    return f"{parts[0]} {parts[-1][0]}."


def search_donors_at_radius(
    db: Session,
    req_lat: float,
    req_lon: float,
    blood_group: str,
    radius_km: float,
    exclude_user_ids: Optional[Sequence[int]] = None,
    searcher_user_id: Optional[int] = None,
) -> List[dict]:
    """Search at exactly one radius — escalation is handled by the background worker."""
    try:
        sid = searcher_user_id
        if sid is None and exclude_user_ids and len(exclude_user_ids) == 1:
            sid = int(list(exclude_user_ids)[0])
        return process_matching_pipeline(
            db,
            req_lat,
            req_lon,
            blood_group,
            radius_km,
            exclude_user_ids=list(exclude_user_ids or []),
            searcher_user_id=sid,
        )
    except SQLAlchemyError:
        return []


def push_found_ws_events(
    db: Session,
    request: BloodRequest,
    newly_found: List[DonorMatchResponse],
    donor_lookup: dict,
) -> None:
    """Instant WebSocket push the moment FOUND rows are flushed."""
    if not newly_found:
        return
    from controllers.ws_hub import hub

    for match in newly_found:
        donor_data = donor_lookup.get(match.donor_user_id, {})
        dto = to_discovery_donor(donor_data, match)
        payload = dto.model_dump() if hasattr(dto, "model_dump") else dto.dict()
        hub.enqueue(
            request.recipient_user_id,
            {
                "type": "match_found",
                "status": "FOUND",
                "request_id": request.request_id,
                "match_data": payload,
            },
        )
        hub.enqueue(
            match.donor_user_id,
            {
                "type": "donor_match",
                "status": "FOUND",
                "request_id": request.request_id,
                "match_id": match.match_id,
                "blood_group": request.blood_group_needed,
                "distance_km": float(match.distance_km),
                "match_data": payload,
            },
        )


def search_donors_auto_expand(
    db: Session,
    req_lat: float,
    req_lon: float,
    blood_group: str,
    exclude_user_ids: Optional[Sequence[int]] = None,
    tiers: Optional[Sequence[float]] = None,
) -> Tuple[List[dict], float]:
    """
    Legacy helper — searches only at the first tier supplied (default: current
    INITIAL_RADIUS_KM). Does NOT jump to 25/50 km instantly.
    """
    radius = float((tiers or [INITIAL_RADIUS_KM])[0])
    matched = search_donors_at_radius(
        db, req_lat, req_lon, blood_group, radius, exclude_user_ids
    )
    return matched, radius


def sync_match_records(
    db: Session,
    request_id: int,
    matched_donors: Iterable[dict],
) -> tuple[List[DonorMatchResponse], List[DonorMatchResponse]]:
    """
    Upsert FOUND rows for newly discovered donors.
    Returns (all_touched_records, newly_created_records).
    """
    from controllers.matching_engine import _dbg

    records: List[DonorMatchResponse] = []
    newly_found: List[DonorMatchResponse] = []
    matched_list = list(matched_donors)
    _dbg(
        f"sync_match_records request_id={request_id} "
        f"incoming_matched_donors={len(matched_list)}"
    )
    for donor in matched_list:
        uid = donor.get("user_id")
        if uid is None:
            _dbg(f"  skip row: missing user_id in {donor}")
            continue
        existing = (
            db.query(DonorMatchResponse)
            .filter(
                DonorMatchResponse.request_id == request_id,
                DonorMatchResponse.donor_user_id == uid,
            )
            .first()
        )
        if existing:
            if existing.status in ("FOUND", "CONTINUED_SEARCH"):
                existing.distance_km = donor.get("distance_km", existing.distance_km)
            _dbg(
                f"  existing match_id={existing.match_id} donor_user_id={uid} "
                f"status={existing.status} (no new notification)"
            )
            records.append(existing)
            continue
        row = DonorMatchResponse(
            request_id=request_id,
            donor_user_id=uid,
            status="FOUND",
            distance_km=float(donor.get("distance_km", 0)),
        )
        db.add(row)
        records.append(row)
        newly_found.append(row)
        _dbg(
            f"  NEW FOUND row donor_user_id={uid} "
            f"distance={donor.get('distance_km')} km → will notify"
        )
    try:
        db.flush()
        for row in newly_found:
            _dbg(f"  flushed match_id={row.match_id} status={row.status}")
    except SQLAlchemyError as exc:
        _dbg(f"sync_match_records FLUSH FAILED: {exc}")
        db.rollback()
        return [], []
    _dbg(
        f"sync_match_records done: total={len(records)} newly_found={len(newly_found)}"
    )
    return records, newly_found


def count_accepted_matches(db: Session, request_id: int) -> int:
    return (
        db.query(DonorMatchResponse)
        .filter(
            DonorMatchResponse.request_id == request_id,
            DonorMatchResponse.status.in_(("ACCEPTED", "COMPLETED")),
        )
        .count()
    )


def to_discovery_donor(
    donor: dict,
    match: Optional[DonorMatchResponse] = None,
) -> DiscoveryDonorDTO:
    status = match.status if match else donor.get("status", "FOUND")
    dist = float(donor.get("distance_km", match.distance_km if match else 0))
    return DiscoveryDonorDTO(
        match_id=match.match_id if match else donor.get("match_id", 0),
        donor_alias=donor_alias(donor.get("name", "Donor")),
        blood_group=donor.get("blood_group", ""),
        distance_km=dist,
        distance_label=distance_label(dist),
        status=status,
        requires_decision=status in ("FOUND",),
    )


def to_match_overview(
    match: DonorMatchResponse,
    request: BloodRequest,
    donor_name: str = "Donor",
) -> MatchOverviewDTO:
    dist = float(match.distance_km)
    return MatchOverviewDTO(
        match_id=match.match_id,
        request_id=match.request_id,
        donor_alias=donor_alias(donor_name),
        blood_group=request.blood_group_needed,
        distance_km=dist,
        distance_label=distance_label(dist),
        status=match.status,
        requires_decision=match.status == "FOUND",
    )


def to_authorized_donor(
    db: Session,
    match: DonorMatchResponse,
    request: BloodRequest,
) -> Optional[AuthorizedDonorDTO]:
    if match.status not in ("ACCEPTED", "COMPLETED"):
        return None
    user = db.query(User).filter(User.user_id == match.donor_user_id).first()
    if not user:
        return None
    from models.donor import DonorProfile

    profile = (
        db.query(DonorProfile)
        .filter(DonorProfile.user_id == match.donor_user_id)
        .first()
    )
    return AuthorizedDonorDTO(
        match_id=match.match_id,
        donor_alias=donor_alias(user.full_name),
        blood_group=profile.blood_group if profile else (user.blood_group or ""),
        distance_km=float(match.distance_km),
        status=match.status,
        full_name=user.full_name,
        phone=user.phone_number or None,
        email=user.email or None,
        request_latitude=float(request.request_latitude),
        request_longitude=float(request.request_longitude),
    )


def build_discovery_request(
    req: BloodRequest,
    distance_km: float,
    match: Optional[DonorMatchResponse] = None,
) -> DiscoveryRequestDTO:
    return DiscoveryRequestDTO(
        request_id=req.request_id,
        blood_group_needed=req.blood_group_needed,
        units_required=req.units_required,
        urgency_level=req.urgency_level,
        distance_km=round(distance_km, 2),
        distance_label=distance_label(distance_km),
        status=req.status,
        match_id=match.match_id if match else None,
        match_status=match.status if match else None,
    )


def find_nearby_requests_for_donor(
    db: Session,
    donor_lat: float,
    donor_lon: float,
    donor_user_id: int,
    radius_km: float = MAX_RADIUS_KM,
) -> List[DiscoveryRequestDTO]:
    """Pending requests within radius — never includes the donor's own requests."""
    if not _valid_coords(donor_lat, donor_lon):
        return []

    from models.donor import DonorProfile

    donor_profile = (
        db.query(DonorProfile)
        .filter(DonorProfile.user_id == donor_user_id)
        .first()
    )
    donor_blood = (
        normalize_blood_group(donor_profile.blood_group)
        if donor_profile
        else None
    )

    min_lat, max_lat, min_lon, max_lon = bounding_box(
        donor_lat, donor_lon, radius_km
    )
    try:
        pending = (
            db.query(BloodRequest)
            .filter(
                BloodRequest.status == "Pending",
                BloodRequest.recipient_user_id != donor_user_id,
                BloodRequest.request_latitude >= min_lat,
                BloodRequest.request_latitude <= max_lat,
                BloodRequest.request_longitude >= min_lon,
                BloodRequest.request_longitude <= max_lon,
            )
            .order_by(BloodRequest.created_at.desc())
            .limit(100)
            .all()
        )
    except SQLAlchemyError:
        return []

    results: List[DiscoveryRequestDTO] = []
    for req in pending:
        dist = calculate_haversine_distance(
            donor_lat,
            donor_lon,
            float(req.request_latitude),
            float(req.request_longitude),
        )
        if dist > min(radius_km, float(req.current_radius_km or INITIAL_RADIUS_KM)):
            continue
        if donor_blood and not is_donor_compatible(
            donor_blood, req.blood_group_needed
        ):
            continue
        match = (
            db.query(DonorMatchResponse)
            .filter(
                DonorMatchResponse.request_id == req.request_id,
                DonorMatchResponse.donor_user_id == donor_user_id,
            )
            .first()
        )
        results.append(build_discovery_request(req, dist, match))

    results.sort(key=lambda x: x.distance_km)
    return results


def _valid_coords(lat: float, lon: float) -> bool:
    return (
        lat is not None
        and lon is not None
        and math.isfinite(lat)
        and math.isfinite(lon)
        and -90 <= lat <= 90
        and -180 <= lon <= 180
    )


def assert_request_owner(req: BloodRequest, user_id: int) -> None:
    from fastapi import HTTPException, status

    if req.recipient_user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this request.",
        )


def get_request_or_404(db: Session, request_id: int) -> BloodRequest:
    from fastapi import HTTPException, status

    req = db.query(BloodRequest).filter(BloodRequest.request_id == request_id).first()
    if not req:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Blood request not found.")
    return req
