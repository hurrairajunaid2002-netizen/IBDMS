from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy.orm import Session

from config.database import get_db
from middleware.auth_guard import get_current_user
from models.match import DonorMatchResponse
from models.request import BloodRequest
from models.user import User
from schemas.match_schema import (
    AlertFeedDTO,
    AlertFeedItemDTO,
    MatchActionResponseDTO,
)
from controllers.matching_service import (
    assert_request_owner,
    count_accepted_matches,
    donor_alias,
    get_request_or_404,
    to_authorized_donor,
    to_match_overview,
)
from controllers.notification_tasks import (
    schedule_match_accepted_emails,
    schedule_recipient_accepted_email,
)

router = APIRouter(prefix="/api/alerts", tags=["Alerts & Consent Pipeline"])

_WAITING_STATES = ("FOUND", "CONTINUED_SEARCH")
_DECISION_STATES = ("FOUND",)


def _iso(dt) -> str | None:
    return dt.isoformat() if dt else None


@router.get("/feed", response_model=AlertFeedDTO)
def get_alert_feed(
    seen_alert_ids: str = "",
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Polling inbox — JWT-scoped. Poll every 4 s from Flutter while screen is active."""
    user_id = current_user["user_id"]
    seen = {x.strip() for x in (seen_alert_ids or "").split(",") if x.strip()}
    alerts: list[AlertFeedItemDTO] = []

    donor_matches = (
        db.query(DonorMatchResponse, BloodRequest)
        .join(BloodRequest, DonorMatchResponse.request_id == BloodRequest.request_id)
        .filter(
            DonorMatchResponse.donor_user_id == user_id,
            BloodRequest.recipient_user_id != user_id,
            DonorMatchResponse.status.in_(_WAITING_STATES + ("ACCEPTED",)),
            BloodRequest.status == "Pending",
        )
        .order_by(DonorMatchResponse.created_at.desc())
        .limit(50)
        .all()
    )

    for match, req in donor_matches:
        if match.status == "FOUND":
            title = f"Urgent! {req.blood_group_needed} patient nearby"
            msg = (
                f"A patient approximately {match.distance_km:.1f} km away "
                f"matches your blood type. View request."
            )
        elif match.status == "ACCEPTED":
            title = f"Connected — {req.blood_group_needed} request"
            msg = "Recipient chose to connect. Open app for contact details."
        else:
            title = f"{req.blood_group_needed} backup request"
            msg = f"Saved as backup candidate ({match.distance_km:.1f} km)."

        alerts.append(
            AlertFeedItemDTO(
                alert_id=f"match-{match.match_id}",
                alert_type="donor_match",
                title=title,
                message=msg,
                match_id=match.match_id,
                request_id=req.request_id,
                status=match.status,
                blood_group=req.blood_group_needed,
                distance_km=float(match.distance_km),
                created_at=_iso(match.created_at),
            )
        )

    recipient_requests = (
        db.query(BloodRequest)
        .filter(
            BloodRequest.recipient_user_id == user_id,
            BloodRequest.status.in_(("Pending", "Fulfilled")),
        )
        .order_by(BloodRequest.created_at.desc())
        .limit(10)
        .all()
    )

    for req in recipient_requests:
        found_matches = (
            db.query(DonorMatchResponse)
            .filter(
                DonorMatchResponse.request_id == req.request_id,
                DonorMatchResponse.status.in_(_DECISION_STATES),
            )
            .count()
        )
        backup_count = (
            db.query(DonorMatchResponse)
            .filter(
                DonorMatchResponse.request_id == req.request_id,
                DonorMatchResponse.status == "CONTINUED_SEARCH",
            )
            .count()
        )
        accepted_count = count_accepted_matches(db, req.request_id)

        if found_matches or backup_count or accepted_count:
            if found_matches:
                msg = (
                    f"We found {found_matches} donor(s)! "
                    f"Tap to connect or keep searching."
                )
            else:
                msg = (
                    f"{accepted_count} connected, {backup_count} backup donor(s)."
                )
            alerts.append(
                AlertFeedItemDTO(
                    alert_id=f"request-{req.request_id}",
                    alert_type="recipient_match_found",
                    title=f"Match found — {req.blood_group_needed}",
                    message=msg,
                    request_id=req.request_id,
                    status=req.status,
                    blood_group=req.blood_group_needed,
                    created_at=_iso(req.created_at),
                    payload={
                        "found_count": found_matches,
                        "backup_count": backup_count,
                        "accepted_count": accepted_count,
                        "current_radius_km": float(req.current_radius_km or 5),
                    },
                )
            )

    trigger_types = ("donor_match", "recipient_match_found")
    new_alerts = [
        a
        for a in alerts
        if a.alert_id not in seen
        and a.alert_type in trigger_types
        and (
            (a.alert_type == "donor_match" and a.status in ("FOUND", "ACCEPTED"))
            or (
                a.alert_type == "recipient_match_found"
                and (a.payload or {}).get("found_count", 0) > 0
            )
        )
    ]

    return AlertFeedDTO(
        count=len(alerts),
        alerts=alerts,
        new_alerts=new_alerts,
        polled_at=datetime.utcnow().isoformat() + "Z",
    )


@router.post("/matches/{match_id}/connect", response_model=MatchActionResponseDTO)
def connect_with_donor(
    match_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Recipient chooses "Connect & Contact Now".
    FOUND → ACCEPTED; unlocks mutual contact; sends confirmation emails.
    """
    match = db.query(DonorMatchResponse).filter(
        DonorMatchResponse.match_id == match_id
    ).first()
    if not match:
        raise HTTPException(status_code=404, detail="Match not found.")

    req = get_request_or_404(db, match.request_id)
    assert_request_owner(req, current_user["user_id"])

    if match.status not in ("FOUND", "CONTINUED_SEARCH"):
        raise HTTPException(
            status_code=400,
            detail=f"Cannot connect while match is {match.status}.",
        )

    match.status = "ACCEPTED"
    match.updated_at = datetime.utcnow()

    if count_accepted_matches(db, req.request_id) + 1 >= req.units_required:
        req.status = "Fulfilled"
        req.closed_at = datetime.utcnow()

    db.commit()
    db.refresh(match)

    donor = db.query(User).filter(User.user_id == match.donor_user_id).first()
    recipient = db.query(User).filter(User.user_id == req.recipient_user_id).first()

    if donor and recipient:
        schedule_match_accepted_emails(
            background_tasks,
            donor.email or "",
            donor.full_name,
            recipient.full_name,
            recipient.phone_number or "",
            req.blood_group_needed,
            float(req.request_latitude),
            float(req.request_longitude),
            req.request_id,
        )
        schedule_recipient_accepted_email(
            background_tasks,
            recipient.email or "",
            recipient.full_name,
            donor.full_name,
            donor.phone_number or "",
            req.blood_group_needed,
            float(req.request_latitude),
            float(req.request_longitude),
            req.request_id,
        )
        if donor.fcm_token:
            from controllers.notification_controller import send_fcm_push
            background_tasks.add_task(
                send_fcm_push,
                donor.fcm_token,
                "Recipient wants to connect",
                f"{recipient.full_name.split()[0]} chose to connect for "
                f"{req.blood_group_needed} blood.",
                {
                    "type": "match_connected",
                    "match_id": str(match.match_id),
                    "request_id": str(req.request_id),
                },
            )

    overview = to_match_overview(
        match, req, donor.full_name if donor else "Donor"
    )
    authorized = to_authorized_donor(db, match, req)
    return MatchActionResponseDTO(
        match_id=match.match_id,
        status=match.status,
        message="Connected! Contact details and location are now available.",
        overview=overview,
        authorized=authorized,
        search_continues=False,
    )


@router.post(
    "/matches/{match_id}/continue-search",
    response_model=MatchActionResponseDTO,
)
def keep_searching(
    match_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Recipient chooses "Keep Looking for More".
    FOUND → CONTINUED_SEARCH; donor saved as backup; escalation continues.
    """
    match = db.query(DonorMatchResponse).filter(
        DonorMatchResponse.match_id == match_id
    ).first()
    if not match:
        raise HTTPException(status_code=404, detail="Match not found.")

    req = get_request_or_404(db, match.request_id)
    assert_request_owner(req, current_user["user_id"])

    if match.status != "FOUND":
        raise HTTPException(
            status_code=400,
            detail=f"Only FOUND matches can be saved as backup (current: {match.status}).",
        )

    match.status = "CONTINUED_SEARCH"
    match.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(match)

    donor = db.query(User).filter(User.user_id == match.donor_user_id).first()
    overview = to_match_overview(
        match, req, donor.full_name if donor else "Donor"
    )
    return MatchActionResponseDTO(
        match_id=match.match_id,
        status=match.status,
        message=(
            "Donor saved as backup. Search continues for additional matches."
        ),
        overview=overview,
        search_continues=True,
    )


@router.post("/matches/{match_id}/accept", response_model=MatchActionResponseDTO)
def donor_accept_match(
    match_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Donor proactively accepts a FOUND invitation."""
    match = db.query(DonorMatchResponse).filter(
        DonorMatchResponse.match_id == match_id
    ).first()
    if not match:
        raise HTTPException(status_code=404, detail="Match not found.")
    if match.donor_user_id != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="Not your match invitation.")

    req = get_request_or_404(db, match.request_id)
    if req.recipient_user_id == current_user["user_id"]:
        raise HTTPException(status_code=400, detail="Cannot accept your own request.")

    if match.status not in ("FOUND", "CONTINUED_SEARCH"):
        raise HTTPException(status_code=400, detail=f"Match is already {match.status}.")

    match.status = "ACCEPTED"
    match.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(match)

    authorized = to_authorized_donor(db, match, req)
    return MatchActionResponseDTO(
        match_id=match.match_id,
        status=match.status,
        message="You accepted this request. Awaiting recipient connection.",
        authorized=authorized,
    )


@router.post("/matches/{match_id}/reject", response_model=MatchActionResponseDTO)
def reject_match(
    match_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    match = db.query(DonorMatchResponse).filter(
        DonorMatchResponse.match_id == match_id
    ).first()
    if not match:
        raise HTTPException(status_code=404, detail="Match not found.")
    if match.donor_user_id != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="Not your match invitation.")
    if match.status in ("REJECTED", "COMPLETED"):
        raise HTTPException(status_code=400, detail=f"Cannot reject a {match.status} match.")

    match.status = "REJECTED"
    match.updated_at = datetime.utcnow()
    db.commit()
    return MatchActionResponseDTO(
        match_id=match.match_id,
        status=match.status,
        message="Match declined.",
    )


@router.post("/matches/{match_id}/complete", response_model=MatchActionResponseDTO)
def complete_match(
    match_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    match = db.query(DonorMatchResponse).filter(
        DonorMatchResponse.match_id == match_id
    ).first()
    if not match:
        raise HTTPException(status_code=404, detail="Match not found.")

    req = get_request_or_404(db, match.request_id)
    user_id = current_user["user_id"]
    if user_id not in (match.donor_user_id, req.recipient_user_id):
        raise HTTPException(status_code=403, detail="Not authorized for this match.")

    if match.status != "ACCEPTED":
        raise HTTPException(status_code=400, detail="Only ACCEPTED matches can be completed.")

    match.status = "COMPLETED"
    match.updated_at = datetime.utcnow()
    db.commit()

    authorized = to_authorized_donor(db, match, req)
    return MatchActionResponseDTO(
        match_id=match.match_id,
        status=match.status,
        message="Match marked complete.",
        authorized=authorized,
    )


@router.get("/matches/{match_id}", response_model=MatchActionResponseDTO)
def get_match_detail(
    match_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    match = db.query(DonorMatchResponse).filter(
        DonorMatchResponse.match_id == match_id
    ).first()
    if not match:
        raise HTTPException(status_code=404, detail="Match not found.")

    req = get_request_or_404(db, match.request_id)
    user_id = current_user["user_id"]
    if user_id not in (match.donor_user_id, req.recipient_user_id):
        raise HTTPException(status_code=403, detail="Not authorized.")

    donor = db.query(User).filter(User.user_id == match.donor_user_id).first()
    overview = to_match_overview(
        match, req, donor.full_name if donor else "Donor"
    )

    if match.status in ("ACCEPTED", "COMPLETED"):
        return MatchActionResponseDTO(
            match_id=match.match_id,
            status=match.status,
            message="Authorized match details.",
            overview=overview,
            authorized=to_authorized_donor(db, match, req),
        )

    return MatchActionResponseDTO(
        match_id=match.match_id,
        status=match.status,
        message="Discovery view — choose Connect or Keep Searching.",
        overview=overview,
        search_continues=match.status == "CONTINUED_SEARCH",
    )
