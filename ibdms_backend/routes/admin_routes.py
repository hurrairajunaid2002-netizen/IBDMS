"""
Admin Management Routes
========================
All endpoints require role == 'Administrator'.
"""

from datetime import datetime, timedelta, date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from config.database import get_db
from middleware.auth_guard import RoleChecker
from models.user import User
from models.donor import DonorProfile
from models.request import BloodRequest

router = APIRouter(prefix="/api/admin", tags=["Administrator Management Panel"])

_admin_only = RoleChecker(["Administrator"])

BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
DEFERRAL_DAYS = 60


# ── Schemas ───────────────────────────────────────────────────────────────────

class UserOverrideSchema(BaseModel):
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    availability_status: Optional[str] = None
    is_locked: Optional[bool] = None
    blood_group: Optional[str] = None
    force_eligible: Optional[bool] = None
    gps_latitude: Optional[float] = None
    gps_longitude: Optional[float] = None


class RequestOverrideSchema(BaseModel):
    status: Optional[str] = None
    blood_group_needed: Optional[str] = None
    urgency_level: Optional[str] = None
    current_radius_km: Optional[float] = None
    request_latitude: Optional[float] = None
    request_longitude: Optional[float] = None
    recipient_name: Optional[str] = None


class AdminLoginSchema(BaseModel):
    email: str
    password: str


# ── Admin gateway login (isolated from public registration) ───────────────────

@router.post("/login")
def admin_login(payload: AdminLoginSchema, db: Session = Depends(get_db)):
    """Administrator-only login gate. Rejects non-admin accounts."""
    from passlib.context import CryptContext

    email = payload.email.strip().lower()
    user = db.query(User).filter(User.email == email).first()
    if not user or not user.password_hash:
        raise HTTPException(status_code=401, detail="Invalid admin credentials.")

    pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")
    if not pwd.verify(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid admin credentials.")

    if user.role != "Administrator":
        raise HTTPException(
            status_code=403,
            detail="This portal is restricted to administrators only.",
        )

    from controllers.auth_controller import _build_token

    token = _build_token(user)
    return {
        "access_token": token,
        "token_type": "bearer",
        "role": user.role,
        "full_name": user.full_name,
        "blood_group": user.blood_group,
        "needs_profile": False,
    }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _next_eligible(donor: DonorProfile) -> Optional[str]:
    if donor.is_locked and donor.lock_expiry_date:
        return donor.lock_expiry_date.isoformat()
    if donor.last_donation_date:
        eligible = donor.last_donation_date + timedelta(days=DEFERRAL_DAYS)
        if eligible > date.today():
            return eligible.isoformat()
    return None


def _lifetime_donations(donor: DonorProfile) -> int:
    stored = getattr(donor, "lifetime_donations", None)
    if stored is not None and stored > 0:
        return int(stored)
    return 1 if donor.last_donation_date else 0


# ── System Statistics ─────────────────────────────────────────────────────────

@router.get("/stats")
def get_system_stats(
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
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


# ── Analytics ─────────────────────────────────────────────────────────────────

@router.get("/analytics/blood-stock")
def blood_stock_chart(
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    """Active donor counts per blood group (clinical stock proxy)."""
    groups = []
    for bg in BLOOD_GROUPS:
        active = (
            db.query(DonorProfile)
            .filter(
                DonorProfile.blood_group == bg,
                DonorProfile.availability_status == "Active",
            )
            .count()
        )
        total = (
            db.query(DonorProfile).filter(DonorProfile.blood_group == bg).count()
        )
        groups.append({"blood_group": bg, "active_units": active, "total_units": total})
    return {"groups": groups}


@router.get("/analytics/timeline")
def request_timeline(
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    """Daily request volume vs fulfilment for the past 30 days."""
    today = date.today()
    start = today - timedelta(days=29)
    days = []
    for i in range(30):
        d = start + timedelta(days=i)
        day_start = datetime.combine(d, datetime.min.time())
        day_end = datetime.combine(d, datetime.max.time())
        created = (
            db.query(BloodRequest)
            .filter(
                BloodRequest.created_at >= day_start,
                BloodRequest.created_at <= day_end,
            )
            .count()
        )
        fulfilled = (
            db.query(BloodRequest)
            .filter(
                BloodRequest.status == "Fulfilled",
                BloodRequest.closed_at >= day_start,
                BloodRequest.closed_at <= day_end,
            )
            .count()
        )
        days.append(
            {
                "date": d.isoformat(),
                "label": d.strftime("%b %d"),
                "requests_created": created,
                "requests_fulfilled": fulfilled,
            }
        )
    return {"days": days}


@router.get("/analytics/heatmap")
def geographic_heatmap(
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    """Regional density of active emergency requests (rounded coordinate sectors)."""
    active_statuses = ("Pending", "Unfulfilled")
    requests = (
        db.query(BloodRequest)
        .filter(BloodRequest.status.in_(active_statuses))
        .all()
    )
    sectors: dict[str, dict] = {}
    for r in requests:
        lat = round(float(r.request_latitude or 0), 1)
        lng = round(float(r.request_longitude or 0), 1)
        key = f"{lat},{lng}"
        if key not in sectors:
            sectors[key] = {
                "sector": f"Sector {lat}°N, {lng}°E",
                "latitude": lat,
                "longitude": lng,
                "count": 0,
                "critical": 0,
            }
        sectors[key]["count"] += 1
        if r.urgency_level == "Critical":
            sectors[key]["critical"] += 1
    ranked = sorted(sectors.values(), key=lambda s: s["count"], reverse=True)
    return {"sectors": ranked[:20]}


# ── Donor Management Grid ─────────────────────────────────────────────────────

@router.get("/donors")
def list_donors(
    page: int = Query(1, ge=1),
    limit: int = Query(15, ge=1, le=100),
    search: Optional[str] = None,
    blood_group: Optional[str] = None,
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    q = (
        db.query(DonorProfile, User)
        .join(User, DonorProfile.user_id == User.user_id)
    )
    if search:
        term = f"%{search.strip()}%"
        q = q.filter(
            or_(
                User.full_name.ilike(term),
                User.phone_number.ilike(term),
                User.email.ilike(term),
            )
        )
    if blood_group and blood_group.upper() != "ALL":
        q = q.filter(DonorProfile.blood_group == blood_group.upper())

    total = q.count()
    rows = q.order_by(User.full_name).offset((page - 1) * limit).limit(limit).all()

    donors = []
    for donor, user in rows:
        donors.append(
            {
                "donor_id": donor.donor_id,
                "user_id": user.user_id,
                "full_name": user.full_name,
                "phone_number": user.phone_number,
                "email": user.email,
                "blood_group": donor.blood_group,
                "gps_latitude": (
                    float(donor.gps_latitude)
                    if donor.gps_latitude is not None
                    else None
                ),
                "gps_longitude": (
                    float(donor.gps_longitude)
                    if donor.gps_longitude is not None
                    else None
                ),
                "lifetime_donations": _lifetime_donations(donor),
                "next_eligible_date": _next_eligible(donor),
                "is_locked": donor.is_locked,
                "availability_status": donor.availability_status,
                "last_donation_date": (
                    donor.last_donation_date.isoformat()
                    if donor.last_donation_date
                    else None
                ),
            }
        )

    return {"total": total, "page": page, "limit": limit, "donors": donors}


# ── Request Management Stream ─────────────────────────────────────────────────

@router.get("/requests")
def list_requests(
    page: int = Query(1, ge=1),
    limit: int = Query(15, ge=1, le=100),
    search: Optional[str] = None,
    status: Optional[str] = None,
    blood_group: Optional[str] = None,
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    q = (
        db.query(BloodRequest, User)
        .join(User, BloodRequest.recipient_user_id == User.user_id)
    )
    if search:
        term = f"%{search.strip()}%"
        q = q.filter(
            or_(
                User.full_name.ilike(term),
                BloodRequest.blood_group_needed.ilike(term),
            )
        )
    if status and status.upper() != "ALL":
        q = q.filter(BloodRequest.status == status)
    if blood_group and blood_group.upper() != "ALL":
        q = q.filter(BloodRequest.blood_group_needed == blood_group.upper())

    total = q.count()
    rows = (
        q.order_by(BloodRequest.created_at.desc())
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )

    requests = []
    for req, user in rows:
        lat = float(req.request_latitude)
        lng = float(req.request_longitude)
        requests.append(
            {
                "request_id": req.request_id,
                "recipient_name": user.full_name,
                "recipient_user_id": user.user_id,
                "blood_group_needed": req.blood_group_needed,
                "urgency_level": req.urgency_level,
                "hospital_location": f"{lat:.4f}°N, {lng:.4f}°E",
                "request_latitude": lat,
                "request_longitude": lng,
                "current_radius_km": float(req.current_radius_km or 5),
                "status": req.status,
                "units_required": req.units_required,
                "created_at": req.created_at.isoformat() if req.created_at else None,
            }
        )

    return {"total": total, "page": page, "limit": limit, "requests": requests}


# ── Legacy user list (kept for compatibility) ─────────────────────────────────

@router.get("/users")
def list_users(
    page: int = 1,
    limit: int = 20,
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    q = db.query(User)
    if search:
        term = f"%{search.strip()}%"
        q = q.filter(
            or_(User.full_name.ilike(term), User.email.ilike(term))
        )
    offset = (page - 1) * limit
    users = q.offset(offset).limit(limit).all()
    total = q.count()

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

    return {"total": total, "page": page, "limit": limit, "users": result}


@router.put("/users/{user_id}/override")
def override_user(
    user_id: int,
    payload: UserOverrideSchema,
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")

    if payload.full_name:
        user.full_name = payload.full_name.strip()
    if payload.phone_number is not None:
        user.phone_number = payload.phone_number.strip()

    donor = db.query(DonorProfile).filter(DonorProfile.user_id == user_id).first()

    if payload.blood_group:
        bg = payload.blood_group.upper()
        user.blood_group = bg
        if donor:
            donor.blood_group = bg

    if donor:
        if payload.gps_latitude is not None:
            donor.gps_latitude = payload.gps_latitude
        if payload.gps_longitude is not None:
            donor.gps_longitude = payload.gps_longitude

        if payload.force_eligible:
            donor.is_locked = False
            donor.lock_expiry_date = None
            donor.availability_status = "Active"
        elif payload.is_locked is not None:
            donor.is_locked = payload.is_locked
            if payload.is_locked:
                donor.availability_status = "Locked"
                donor.lock_expiry_date = date.today() + timedelta(days=DEFERRAL_DAYS)
            else:
                donor.lock_expiry_date = None

        if payload.availability_status is not None:
            if payload.availability_status not in ("Active", "Inactive", "Locked"):
                raise HTTPException(status_code=400, detail="Invalid availability status.")
            donor.availability_status = payload.availability_status

    db.commit()
    return {"message": "User updated.", "user_id": user_id}


@router.get("/requests/unfulfilled")
def get_unfulfilled_requests(
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    requests = (
        db.query(BloodRequest, User)
        .join(User, BloodRequest.recipient_user_id == User.user_id)
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
                "recipient_name": u.full_name,
                "blood_group_needed": r.blood_group_needed,
                "units_required": r.units_required,
                "urgency_level": r.urgency_level,
                "current_radius_km": float(r.current_radius_km or 50),
                "status": r.status,
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "closed_at": r.closed_at.isoformat() if r.closed_at else None,
            }
            for r, u in requests
        ],
    }


@router.put("/requests/{request_id}/override")
def override_request(
    request_id: int,
    payload: RequestOverrideSchema,
    db: Session = Depends(get_db),
    _: dict = Depends(_admin_only),
):
    req = db.query(BloodRequest).filter(BloodRequest.request_id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found.")

    if payload.recipient_name:
        user = db.query(User).filter(User.user_id == req.recipient_user_id).first()
        if user:
            user.full_name = payload.recipient_name.strip()

    if payload.blood_group_needed:
        req.blood_group_needed = payload.blood_group_needed.upper()
    if payload.urgency_level:
        if payload.urgency_level not in ("Low", "Medium", "Critical"):
            raise HTTPException(status_code=400, detail="Invalid urgency level.")
        req.urgency_level = payload.urgency_level
    if payload.current_radius_km is not None:
        req.current_radius_km = max(5.0, min(50.0, payload.current_radius_km))
    if payload.request_latitude is not None:
        req.request_latitude = payload.request_latitude
    if payload.request_longitude is not None:
        req.request_longitude = payload.request_longitude

    if payload.status:
        allowed = {
            "Pending",
            "Fulfilled",
            "Cancelled",
            "Unfulfilled",
            "Expired",
        }
        if payload.status not in allowed:
            raise HTTPException(
                status_code=400,
                detail=f"Status must be one of: {allowed}",
            )
        req.status = payload.status
        if payload.status != "Pending":
            req.closed_at = datetime.utcnow()
        else:
            req.closed_at = None

    db.commit()
    return {
        "message": f"Request #{request_id} updated.",
        "request_id": request_id,
    }
