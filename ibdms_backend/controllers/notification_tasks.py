"""
Async notification dispatch helpers for FastAPI BackgroundTasks.
"""

from typing import Dict, List, Optional

from fastapi import BackgroundTasks
from sqlalchemy.orm import Session

from controllers import notification_controller as nc
from models.match import DonorMatchResponse
from models.request import BloodRequest
from models.user import User


def _valid_email(email: str) -> bool:
    return bool(email and "@" in email and "." in email.split("@")[-1])


def schedule_match_found_notifications(
    background_tasks: BackgroundTasks,
    db: Session,
    request: BloodRequest,
    newly_found: List[DonorMatchResponse],
    donor_lookup: Dict[int, dict],
) -> None:
    """
    Dual push the moment a NEW match row is created — recipient + each donor.
    """
    if not newly_found:
        return

    recipient = (
        db.query(User)
        .filter(User.user_id == request.recipient_user_id)
        .first()
    )
    recipient_token = recipient.fcm_token if recipient else None
    print(
        f"[MATCH-DEBUG] schedule_match_found_notifications: "
        f"newly_found={len(newly_found)} recipient_fcm={'yes' if recipient_token else 'NO TOKEN'}",
        flush=True,
    )

    for match in newly_found:
        donor_data = donor_lookup.get(match.donor_user_id, {})
        donor_token = donor_data.get("fcm_token")
        print(
            f"[MATCH-DEBUG]   notify match_id={match.match_id} "
            f"donor_user_id={match.donor_user_id} "
            f"donor_fcm={'yes' if donor_token else 'NO TOKEN'}",
            flush=True,
        )

        background_tasks.add_task(
            nc.notify_dual_match_found,
            recipient_token,
            donor_token,
            float(match.distance_km),
            request.blood_group_needed,
            match.match_id,
            request.request_id,
        )

        donor_email = donor_data.get("email")
        if _valid_email(donor_email or ""):
            background_tasks.add_task(
                nc.send_blood_request_alert,
                [donor_email],
                "IBDMS Patient",
                request.blood_group_needed,
                f"Approximately {match.distance_km:.1f} km away",
                request.request_id,
            )


def notify_match_found_worker(
    db: Session,
    request: BloodRequest,
    newly_found: List[DonorMatchResponse],
    donor_lookup: Dict[int, dict],
) -> None:
    """Thread-safe fallback for the escalation worker."""
    if not newly_found:
        return
    recipient = (
        db.query(User)
        .filter(User.user_id == request.recipient_user_id)
        .first()
    )
    recipient_token = recipient.fcm_token if recipient else None
    for match in newly_found:
        donor_data = donor_lookup.get(match.donor_user_id, {})
        nc.notify_dual_match_found(
            recipient_token,
            donor_data.get("fcm_token"),
            float(match.distance_km),
            request.blood_group_needed,
            match.match_id,
            request.request_id,
        )


def schedule_blood_request_alerts(
    background_tasks: BackgroundTasks,
    matched_donors: List[dict],
    blood_group: str,
    request_lat: float,
    request_lon: float,
    request_id: int,
    requester_alias: str = "IBDMS Patient",
) -> None:
    """Legacy email batch for donors (used alongside dual push)."""
    if not matched_donors:
        return
    emails = [
        d["email"]
        for d in matched_donors
        if _valid_email(d.get("email", ""))
    ]
    if emails:
        location_hint = (
            f"Approximately {round(request_lat, 2)}°N, {round(request_lon, 2)}°E"
        )
        background_tasks.add_task(
            nc.send_blood_request_alert,
            emails,
            requester_alias,
            blood_group,
            location_hint,
            request_id,
        )


def schedule_match_accepted_emails(
    background_tasks: BackgroundTasks,
    donor_email: str,
    donor_name: str,
    recipient_name: str,
    recipient_phone: str,
    blood_group: str,
    request_lat: float,
    request_lon: float,
    request_id: int,
) -> None:
    if _valid_email(donor_email):
        background_tasks.add_task(
            nc.send_donor_accept_confirmation_email,
            donor_email,
            donor_name,
            recipient_name,
            blood_group,
            request_lat,
            request_lon,
            request_id,
        )


def schedule_recipient_accepted_email(
    background_tasks: BackgroundTasks,
    recipient_email: str,
    recipient_name: str,
    donor_name: str,
    donor_phone: str,
    blood_group: str,
    request_lat: float,
    request_lon: float,
    request_id: int,
) -> None:
    if _valid_email(recipient_email):
        background_tasks.add_task(
            nc.send_recipient_match_accepted_email,
            recipient_email,
            recipient_name,
            donor_name,
            donor_phone,
            blood_group,
            request_lat,
            request_lon,
            request_id,
        )
