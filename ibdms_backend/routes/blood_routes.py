from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime

from config.database import get_db
from schemas.blood_schema import BloodRequestCreateSchema
from middleware.auth_guard import get_current_user
from controllers.matching_engine import process_matching_pipeline, execute_haversine
from controllers.search_engine import (
    INITIAL_RADIUS_KM,
    MAX_RADIUS_KM,
    STAGE_DURATION_SECONDS,
    STEP_KM,
)
from models.request import BloodRequest

router = APIRouter(prefix="/api/requests", tags=["Emergency Engine Orchestrator"])


# ── POST /api/requests/create ─────────────────────────────────────────────────

@router.post("/create", status_code=status.HTTP_201_CREATED)
def create_blood_request(
    payload: BloodRequestCreateSchema,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),  # Any authenticated user
):
    """
    Create a new blood request.  Open to ALL authenticated users regardless of
    role — both Donors and Recipients can need blood in an emergency.

    The request is inserted with current_radius_km = 5 km.  An immediate
    Haversine pass is run at 5 km.  The background escalation worker then
    expands the radius by +5 km every 5 minutes until donors are found or
    the 50 km ceiling is hit.
    """
    now = datetime.utcnow()
    req = BloodRequest(
        recipient_user_id=current_user["user_id"],
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

    # Immediate first-pass match at 5 km.
    matched = process_matching_pipeline(
        db,
        payload.request_latitude,
        payload.request_longitude,
        payload.blood_group_needed,
        INITIAL_RADIUS_KM,
    )
    req.matched_count = len(matched)

    if len(matched) >= payload.units_required:
        req.status = "Fulfilled"
        req.closed_at = now

    db.commit()

    # ── Notify matched donors via FCM push + Email ─────────────────────────
    if matched:
        from controllers.notification_controller import (
            broadcast_blood_request_push,
            send_blood_request_alert,
        )
        location_hint = (
            f"Lat {round(payload.request_latitude, 3)}, "
            f"Lon {round(payload.request_longitude, 3)}"
        )
        fcm_tokens = [d["fcm_token"] for d in matched if d.get("fcm_token")]
        donor_emails = [d["email"] for d in matched if d.get("email")]

        # Non-blocking background pushes.
        import threading
        threading.Thread(
            target=broadcast_blood_request_push,
            args=(fcm_tokens, payload.blood_group_needed, location_hint, req.request_id),
            daemon=True,
        ).start()
        threading.Thread(
            target=send_blood_request_alert,
            args=(donor_emails, "IBDMS Patient", payload.blood_group_needed,
                  location_hint, req.request_id),
            daemon=True,
        ).start()

    return {
        "request_id": req.request_id,
        "status": req.status,
        "current_radius_km": INITIAL_RADIUS_KM,
        "next_radius_km": min(INITIAL_RADIUS_KM + STEP_KM, MAX_RADIUS_KM),
        "seconds_until_expansion": STAGE_DURATION_SECONDS if req.status == "Pending" else 0,
        "matched_count": len(matched),
        "matched_donors": matched[:10],
        "units_required": payload.units_required,
        "blood_group_needed": payload.blood_group_needed,
        "urgency_level": payload.urgency_level,
    }


# ── GET /api/requests/{id}/status ─────────────────────────────────────────────

@router.get("/{request_id}/status")
def get_request_status(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Live-poll endpoint.  Returns the current escalation state of a request:
    current radius, countdown to next expansion, and matched donor list.
    Frontend polls this every ~15 seconds to drive the countdown UI.
    """
    req = (
        db.query(BloodRequest)
        .filter(BloodRequest.request_id == request_id)
        .first()
    )
    if not req:
        raise HTTPException(status_code=404, detail="Blood request not found.")

    current_r = float(req.current_radius_km or INITIAL_RADIUS_KM)
    next_r = min(current_r + STEP_KM, MAX_RADIUS_KM)

    seconds_until = 0
    if req.status == "Pending" and req.search_updated_at:
        elapsed = (datetime.utcnow() - req.search_updated_at).total_seconds()
        seconds_until = max(0, int(STAGE_DURATION_SECONDS - elapsed))

    matched: list = []
    if req.status == "Pending":
        matched = process_matching_pipeline(
            db,
            float(req.request_latitude),
            float(req.request_longitude),
            req.blood_group_needed,
            current_r,
        )

    return {
        "request_id": req.request_id,
        "status": req.status,
        "current_radius_km": current_r,
        "next_radius_km": next_r,
        "seconds_until_expansion": seconds_until,
        "matched_count": len(matched),
        "matched_donors": matched[:10],
        "units_required": req.units_required,
        "blood_group_needed": req.blood_group_needed,
        "urgency_level": req.urgency_level,
        "created_at": req.created_at.isoformat() if req.created_at else None,
    }


# ── POST /api/requests/{id}/cancel ────────────────────────────────────────────

@router.post("/{request_id}/cancel", status_code=status.HTTP_200_OK)
def cancel_blood_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Cancel an active search.  Only the user who created the request may cancel
    it.  The escalation worker skips non-Pending requests, so the background
    loop terminates for this request immediately on next cycle.
    """
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


# ── GET /api/requests/nearby ──────────────────────────────────────────────────

@router.get("/nearby")
def get_nearby_requests(
    lat: float,
    lon: float,
    radius: float = 50.0,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Returns active Pending blood requests within `radius` km.
    Available to ALL authenticated users.
    """
    pending = (
        db.query(BloodRequest)
        .filter(BloodRequest.status == "Pending")
        .order_by(BloodRequest.created_at.desc())
        .limit(50)
        .all()
    )

    nearby = []
    for req in pending:
        dist = execute_haversine(
            lat, lon,
            float(req.request_latitude),
            float(req.request_longitude),
        )
        if dist <= radius:
            nearby.append(
                {
                    "request_id": req.request_id,
                    "blood_group_needed": req.blood_group_needed,
                    "units_required": req.units_required,
                    "urgency_level": req.urgency_level,
                    "distance_km": round(dist, 2),
                    "current_radius_km": float(req.current_radius_km or INITIAL_RADIUS_KM),
                    "location_hint": (
                        f"Lat {round(float(req.request_latitude), 3)}, "
                        f"Lon {round(float(req.request_longitude), 3)}"
                    ),
                    "status": req.status,
                    "created_at": req.created_at.isoformat() if req.created_at else None,
                }
            )

    nearby.sort(key=lambda x: x["distance_km"])
    return {"count": len(nearby), "requests": nearby}
