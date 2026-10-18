from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy.orm import Session

from config.database import get_db
from schemas.blood_schema import BloodRequestCreateSchema
from schemas.match_schema import (
    BloodRequestCreateResponseDTO,
    BloodRequestLiveDTO,
    BloodRequestStatusDTO,
    DiscoveryDonorDTO,
    NearbyRequestsDTO,
)
from middleware.auth_guard import get_current_user
from controllers.matching_service import (
    INITIAL_RADIUS_KM,
    MAX_RADIUS_KM,
    assert_request_owner,
    find_nearby_requests_for_donor,
    get_request_or_404,
    next_radius_tier,
    push_found_ws_events,
    search_donors_at_radius,
    sync_match_records,
    to_discovery_donor,
)
from controllers.search_engine import STAGE_DURATION_SECONDS
from controllers.notification_tasks import schedule_match_found_notifications
from controllers.matching_engine import _dbg, parse_coords
from controllers.blood_compatibility import compatible_donor_groups, normalize_blood_group
from models.match import DonorMatchResponse
from models.request import BloodRequest

router = APIRouter(prefix="/api/requests", tags=["Emergency Engine Orchestrator"])


def _build_discovery_list(
    db: Session,
    request_id: int,
    matched: list,
) -> list[DiscoveryDonorDTO]:
    records = {
        r.donor_user_id: r
        for r in db.query(DonorMatchResponse)
        .filter(DonorMatchResponse.request_id == request_id)
        .all()
    }
    return [
        to_discovery_donor(d, records.get(d["user_id"]))
        for d in matched[:10]
    ]


def _parse_seen_match_ids(seen_match_ids: str) -> set[int]:
    seen: set[int] = set()
    for part in (seen_match_ids or "").split(","):
        part = part.strip()
        if part.isdigit():
            seen.add(int(part))
    return seen


def _poll_pending_request(
    db: Session,
    req: BloodRequest,
    background_tasks: BackgroundTasks,
) -> tuple[list, list[DiscoveryDonorDTO], float, float, int]:
    """Run matching + sync for a pending request; return poll payload parts."""
    current_r = float(req.current_radius_km or INITIAL_RADIUS_KM)
    next_r = next_radius_tier(current_r)

    seconds_until = 0
    if req.search_updated_at:
        elapsed = (datetime.utcnow() - req.search_updated_at).total_seconds()
        seconds_until = max(0, int(STAGE_DURATION_SECONDS - elapsed))

    matched: list = []
    if req.status == "Pending":
        matched = search_donors_at_radius(
            db,
            float(req.request_latitude),
            float(req.request_longitude),
            req.blood_group_needed,
            current_r,
            exclude_user_ids=[req.recipient_user_id],
            searcher_user_id=req.recipient_user_id,
        )
        _, newly_found = sync_match_records(db, req.request_id, matched)
        _dbg(
            f"poll request_id={req.request_id}: radius={current_r} km "
            f"matched={len(matched)} newly_found={len(newly_found)}"
        )
        if newly_found:
            donor_lookup = {d["user_id"]: d for d in matched if d.get("user_id")}
            schedule_match_found_notifications(
                background_tasks, db, req, newly_found, donor_lookup
            )
            push_found_ws_events(db, req, newly_found, donor_lookup)

    discovery = _build_discovery_list(db, req.request_id, matched)
    return matched, discovery, current_r, next_r, seconds_until


@router.post("/create", status_code=status.HTTP_201_CREATED, response_model=BloodRequestCreateResponseDTO)
def create_blood_request(
    payload: BloodRequestCreateSchema,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Create an emergency blood request. Starts at 5 km; the background worker
    expands +5 km every 2 minutes up to 50 km. Self-excluded from matching.
    """
    user_id = current_user["user_id"]
    now = datetime.utcnow()

    _dbg(
        f"POST /api/requests/create user_id={user_id} "
        f"coords=({payload.request_latitude}, {payload.request_longitude}) "
        f"blood={payload.blood_group_needed!r} urgency={payload.urgency_level!r}"
    )

    if not all(
        isinstance(v, (int, float)) for v in (payload.request_latitude, payload.request_longitude)
    ):
        raise HTTPException(status_code=400, detail="Invalid GPS coordinates.")

    if parse_coords(payload.request_latitude, payload.request_longitude, user_id, "searcher") is None:
        raise HTTPException(
            status_code=400,
            detail="Your GPS coordinates are invalid (0.0 or missing). Enable location and retry.",
        )

    req = BloodRequest(
        recipient_user_id=user_id,
        blood_group_needed=payload.blood_group_needed,
        units_required=payload.units_required,
        urgency_level=payload.urgency_level,
        request_latitude=payload.request_latitude,
        request_longitude=payload.request_longitude,
        status="Pending",
        current_radius_km=INITIAL_RADIUS_KM,
        search_updated_at=now,
        matched_count=0,
    )
    db.add(req)
    db.commit()
    db.refresh(req)

    matched = search_donors_at_radius(
        db,
        payload.request_latitude,
        payload.request_longitude,
        payload.blood_group_needed,
        INITIAL_RADIUS_KM,
        exclude_user_ids=[user_id],
        searcher_user_id=user_id,
    )
    _, newly_found = sync_match_records(db, req.request_id, matched)
    req.current_radius_km = INITIAL_RADIUS_KM
    req.matched_count = len(matched)
    db.commit()
    db.refresh(req)

    donor_lookup = {d["user_id"]: d for d in matched if d.get("user_id")}
    _dbg(
        f"create request_id={req.request_id}: matched={len(matched)} "
        f"newly_found={len(newly_found)} scheduling_notifications={bool(newly_found)}"
    )
    for m in newly_found:
        _dbg(
            f"  → FOUND match_id={m.match_id} donor_user_id={m.donor_user_id} "
            f"status={m.status} distance={m.distance_km} km"
        )
    schedule_match_found_notifications(
        background_tasks, db, req, newly_found, donor_lookup
    )
    push_found_ws_events(db, req, newly_found, donor_lookup)

    discovery = _build_discovery_list(db, req.request_id, matched)
    _dbg(
        f"create response: discovery_donors={len(discovery)} "
        f"statuses={[d.status for d in discovery]}"
    )
    next_r = next_radius_tier(INITIAL_RADIUS_KM)
    compatible = compatible_donor_groups(payload.blood_group_needed)

    return BloodRequestCreateResponseDTO(
        request_id=req.request_id,
        status=req.status,
        current_radius_km=INITIAL_RADIUS_KM,
        next_radius_km=next_r,
        seconds_until_expansion=STAGE_DURATION_SECONDS,
        matched_count=len(matched),
        matched_donors=discovery,
        units_required=payload.units_required,
        blood_group_needed=payload.blood_group_needed,
        compatible_donor_groups=compatible,
        urgency_level=payload.urgency_level,
    )


@router.get("/{request_id}/status", response_model=BloodRequestStatusDTO)
def get_request_status(
    request_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Live-poll endpoint — owner only. Returns masked discovery donors."""
    req = get_request_or_404(db, request_id)
    assert_request_owner(req, current_user["user_id"])

    _dbg(
        f"GET /api/requests/{request_id}/status user_id={current_user['user_id']} "
        f"req_coords=({req.request_latitude}, {req.request_longitude}) "
        f"blood={req.blood_group_needed!r} req_status={req.status}"
    )

    matched, discovery, current_r, next_r, seconds_until = _poll_pending_request(
        db, req, background_tasks
    )
    compatible = compatible_donor_groups(req.blood_group_needed)

    return BloodRequestStatusDTO(
        request_id=req.request_id,
        status=req.status,
        current_radius_km=current_r,
        next_radius_km=next_r,
        seconds_until_expansion=seconds_until,
        matched_count=len(matched),
        matched_donors=discovery,
        units_required=req.units_required,
        blood_group_needed=normalize_blood_group(req.blood_group_needed)
        or req.blood_group_needed,
        compatible_donor_groups=compatible,
        urgency_level=req.urgency_level,
        created_at=req.created_at.isoformat() if req.created_at else None,
    )


@router.get("/{request_id}/live", response_model=BloodRequestLiveDTO)
def get_live_search_updates(
    request_id: int,
    background_tasks: BackgroundTasks,
    seen_match_ids: str = "",
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Optimized 4-second live poll for the Searching screen.
    Pass comma-separated match IDs the client has already alerted on;
    response includes `new_match_events` for instant pop-ups.
    """
    req = get_request_or_404(db, request_id)
    assert_request_owner(req, current_user["user_id"])
    seen = _parse_seen_match_ids(seen_match_ids)

    matched, discovery, current_r, next_r, seconds_until = _poll_pending_request(
        db, req, background_tasks
    )

    new_events = [
        d
        for d in discovery
        if d.match_id not in seen and d.status in ("FOUND", "ACCEPTED")
    ]
    if new_events:
        _dbg(
            f"GET /live request_id={request_id} → {len(new_events)} new event(s) "
            f"for client seen={sorted(seen)}"
        )

    return BloodRequestLiveDTO(
        request_id=req.request_id,
        status=req.status,
        current_radius_km=current_r,
        next_radius_km=next_r,
        seconds_until_expansion=seconds_until,
        matched_count=len(matched),
        matched_donors=discovery,
        new_match_events=new_events,
        units_required=req.units_required,
        blood_group_needed=normalize_blood_group(req.blood_group_needed)
        or req.blood_group_needed,
        compatible_donor_groups=compatible_donor_groups(req.blood_group_needed),
        urgency_level=req.urgency_level,
        created_at=req.created_at.isoformat() if req.created_at else None,
    )


@router.post("/{request_id}/cancel", status_code=status.HTTP_200_OK)
def cancel_blood_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    req = (
        db.query(BloodRequest)
        .filter(
            BloodRequest.request_id == request_id,
            BloodRequest.recipient_user_id == current_user["user_id"],
        )
        .first()
    )
    if not req:
        raise HTTPException(
            status_code=404,
            detail="Request not found or you do not own this request.",
        )
    if req.status != "Pending":
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel a request with status '{req.status}'.",
        )

    req.status = "Cancelled"
    req.closed_at = datetime.utcnow()
    db.commit()
    return {"message": "Request cancelled.", "request_id": request_id}


@router.get("/nearby", response_model=NearbyRequestsDTO)
def get_nearby_requests(
    lat: float,
    lon: float,
    radius: float = MAX_RADIUS_KM,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Donor discovery feed — pending requests within radius.
    Never includes the caller's own requests (self-alert prevention).
    Phase 1 privacy: distance label only, no exact recipient coordinates.
    """
    if radius <= 0 or radius > MAX_RADIUS_KM:
        radius = MAX_RADIUS_KM

    nearby = find_nearby_requests_for_donor(
        db, lat, lon, current_user["user_id"], radius_km=radius
    )
    return NearbyRequestsDTO(count=len(nearby), requests=nearby)
