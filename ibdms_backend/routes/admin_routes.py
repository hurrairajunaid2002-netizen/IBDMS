"""
Admin Management Routes
========================
All endpoints require role == 'Administrator'.
Admin accounts are seeded via seed_admin() in main.py — there is no
public registration path for the Administrator role.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional

from config.database import get_db
from middleware.auth_guard import RoleChecker
from models.user import User
from models.donor import DonorProfile
from models.request import BloodRequest

router = APIRouter(prefix="/api/admin", tags=["Administrator Management Panel"])

_admin_only = RoleChecker(["Administrator"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class UserOverrideSchema(BaseModel):
    availability_status: Optional[str] = None   # "Active" | "Inactive"
    is_locked: Optional[bool] = None
    blood_group: Optional[str] = None


class RequestOverrideSchema(BaseModel):
    status: str  # "Pending" | "Fulfilled" | "Cancelled" | "Unfulfilled"


# ── System Statistics ─────────────────────────────────────────────────────────

@router.get("/stats")
def get_system_stats(
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    """Real-time system statistics for the admin dashboard."""
    total_users = db.query(User).count()
    total_donors = db.query(DonorProfile).count()
    active_donors = (
        db.query(DonorProfile)
        .filter(DonorProfile.availability_status == "Active")
        .count()
    )
    pending_requests = (
        db.query(BloodRequest).filter(BloodRequest.status == "Pending").count()
    )
    fulfilled_requests = (
        db.query(BloodRequest).filter(BloodRequest.status == "Fulfilled").count()
    )
    unfulfilled_requests = (
        db.query(BloodRequest).filter(BloodRequest.status == "Unfulfilled").count()
    )
    total_requests = db.query(BloodRequest).count()

    return {
        "total_users": total_users,
        "total_donor_profiles": total_donors,
        "active_donors": active_donors,
        "total_requests": total_requests,
        "pending_requests": pending_requests,
        "fulfilled_requests": fulfilled_requests,
        "unfulfilled_requests": unfulfilled_requests,
        "fulfilment_rate_pct": (
            round(fulfilled_requests / total_requests * 100, 1)
            if total_requests > 0
            else 0.0
        ),
    }


# ── User Management ───────────────────────────────────────────────────────────

@router.get("/users")
def list_users(
    page: int = 1,
    limit: int = 20,
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    """Paginated list of all user accounts with their donor profile status."""
    offset = (page - 1) * limit
    users = db.query(User).offset(offset).limit(limit).all()
    total = db.query(User).count()

    result = []
    for u in users:
        donor = (
            db.query(DonorProfile)
            .filter(DonorProfile.user_id == u.user_id)
            .first()
        )
        result.append(
            {
                "user_id": u.user_id,
                "full_name": u.full_name,
                "email": u.email,
                "phone_number": u.phone_number,
                "role": u.role,
                "blood_group": u.blood_group,
                "has_donor_profile": donor is not None,
                "donor_availability": donor.availability_status if donor else None,
                "is_locked": donor.is_locked if donor else False,
                "created_at": u.created_at.isoformat() if u.created_at else None,
            }
        )

    return {
        "total": total,
        "page": page,
        "limit": limit,
        "users": result,
    }


@router.put("/users/{user_id}/override")
def override_user(
    user_id: int,
    payload: UserOverrideSchema,
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    """Manually override a user's donor profile attributes."""
    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    donor = db.query(DonorProfile).filter(DonorProfile.user_id == user_id).first()

    if payload.blood_group:
        user.blood_group = payload.blood_group.upper()

    if donor:
        if payload.availability_status is not None:
            if payload.availability_status not in ("Active", "Inactive", "Locked"):
                raise HTTPException(status_code=400, detail="Invalid availability status.")
            donor.availability_status = payload.availability_status

        if payload.is_locked is not None:
            donor.is_locked = payload.is_locked
            if payload.is_locked:
                donor.availability_status = "Locked"

    db.commit()
    return {"message": "User updated.", "user_id": user_id}


# ── Unfulfilled Alerts ────────────────────────────────────────────────────────

@router.get("/requests/unfulfilled")
def get_unfulfilled_requests(
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    """Returns all requests that exhausted the 50 km search ceiling."""
    requests = (
        db.query(BloodRequest)
        .filter(BloodRequest.status == "Unfulfilled")
        .order_by(BloodRequest.created_at.desc())
        .limit(50)
        .all()
    )
    return {
        "count": len(requests),
        "requests": [
            {
                "request_id": r.request_id,
                "blood_group_needed": r.blood_group_needed,
                "units_required": r.units_required,
                "urgency_level": r.urgency_level,
                "current_radius_km": float(r.current_radius_km or 50),
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "closed_at": r.closed_at.isoformat() if r.closed_at else None,
            }
            for r in requests
        ],
    }


@router.put("/requests/{request_id}/override")
def override_request(
    request_id: int,
    payload: RequestOverrideSchema,
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    """Admin can manually set a request status."""
    from datetime import datetime

    req = db.query(BloodRequest).filter(BloodRequest.request_id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found.")

    allowed = {"Pending", "Fulfilled", "Cancelled", "Unfulfilled"}
    if payload.status not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Status must be one of: {allowed}",
        )

    req.status = payload.status
    if payload.status != "Pending":
        req.closed_at = datetime.utcnow()
    db.commit()
    return {"message": f"Request #{request_id} status set to '{payload.status}'.", "request_id": request_id}
