"""
IBDMS Backend — FastAPI Application Entry Point  v3.0
======================================================
Startup order:
  1. Load .env (config.settings — must run before other config reads).
  2. Create all DB tables (create_all).
  3. Run idempotent ALTER TABLE column migrations.
  ...
"""

# ── Load environment FIRST ────────────────────────────────────────────────────
from config import settings as app_settings  # noqa: E402, F401 — triggers load_dotenv

import os
import socket
import threading
import time

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from config.database import Base, engine, SessionLocal
from models import User, DonorProfile, BloodRequest, DonorMatchResponse  # noqa: F401
from routes import (
    auth_routes,
    blood_routes,
    alerts_routes,
    chatbot_routes,
    donor_routes,
    admin_routes,
    ws_routes,
)
from controllers.search_engine import start_escalation_worker
from controllers.notification_controller import init_notifications
from controllers.ws_hub import hub

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Intelligent Blood Donation Management System (IBDMS)",
    description=(
        "Multi-tier FastAPI backend — Universal auth (Google + password) · "
        "dual-role entity capability · time-staged Haversine radius escalation · "
        "RAG-style AI chatbot · FCM + SMTP notifications · "
        "LAN UDP autodiscovery."
    ),
    version="3.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=app_settings.cors_origins(),
    allow_origin_regex=app_settings.cors_origin_regex(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

app.include_router(auth_routes.router)
app.include_router(blood_routes.router)
app.include_router(alerts_routes.router)
app.include_router(chatbot_routes.router)
app.include_router(donor_routes.router)
app.include_router(admin_routes.router)
app.include_router(ws_routes.router)


# ── Idempotent DB column migrations ──────────────────────────────────────────

def _run_column_migrations() -> None:
    """
    Adds new columns introduced in v2.0 and v3.0 without touching existing rows.
    Each ALTER TABLE is wrapped individually; duplicate-column errors are silently
    ignored, making this safe on every cold start.
    """
    migrations = [
        # v2.0 — Escalation state on blood_requests
        "ALTER TABLE blood_requests ADD COLUMN current_radius_km FLOAT NOT NULL DEFAULT 5.0",
        "ALTER TABLE blood_requests ADD COLUMN search_updated_at DATETIME NULL",
        "ALTER TABLE blood_requests ADD COLUMN matched_count INT NOT NULL DEFAULT 0",
        "ALTER TABLE blood_requests ADD COLUMN closed_at DATETIME NULL",
        (
            "ALTER TABLE blood_requests MODIFY COLUMN status "
            "ENUM('Pending','Fulfilled','Cancelled','Unfulfilled','Expired') "
            "NOT NULL DEFAULT 'Pending'"
        ),
        # v3.0 — Universal user profile columns
        "ALTER TABLE users ADD COLUMN blood_group VARCHAR(5) NULL",
        "ALTER TABLE users ADD COLUMN google_id VARCHAR(128) NULL",
        "ALTER TABLE users ADD COLUMN fcm_token VARCHAR(512) NULL",
        # Google-only accounts have no password; allow NULL in existing DBs.
        "ALTER TABLE users MODIFY password_hash VARCHAR(255) NULL",
        # Unique index on google_id (fails silently if already exists)
        "CREATE UNIQUE INDEX idx_users_google_id ON users (google_id)",
        "ALTER TABLE donor_profiles ADD COLUMN lifetime_donations INT NOT NULL DEFAULT 0",
        # v3.1 — Explicit onboarding role selection (no default Donor)
        (
            "ALTER TABLE users MODIFY COLUMN role "
            "ENUM('Donor','Recipient','Administrator','Unassigned') "
            "NOT NULL DEFAULT 'Unassigned'"
        ),
        # v4.0 — consent pipeline; ensure radius default stays 5 km
        "ALTER TABLE blood_requests MODIFY COLUMN current_radius_km FLOAT NOT NULL DEFAULT 5.0",
        # v4.1 — match decision states (FOUND / ACCEPTED / CONTINUED_SEARCH)
        (
            "ALTER TABLE donor_match_responses MODIFY COLUMN status "
            "ENUM('PENDING','FOUND','ACCEPTED','CONTINUED_SEARCH','REJECTED','COMPLETED') "
            "NOT NULL DEFAULT 'FOUND'"
        ),
        "UPDATE donor_match_responses SET status='FOUND' WHERE status='PENDING'",
        (
            "ALTER TABLE donor_match_responses MODIFY COLUMN status "
            "ENUM('FOUND','ACCEPTED','CONTINUED_SEARCH','REJECTED','COMPLETED') "
            "NOT NULL DEFAULT 'FOUND'"
        ),
    ]
    with engine.connect() as conn:
        for sql in migrations:
            try:
                conn.execute(text(sql))
                conn.commit()
            except Exception:
                pass  # Column / index already exists.
    print("INFO:     DB migration check complete.")


# ── Admin account seeding ─────────────────────────────────────────────────────

def _seed_admin() -> None:
    """
    Ensures the master administrator account exists with evaluation credentials.
    Upserts admin@ibdms.org so testing profiles always work.
    """
    from models.user import User
    from passlib.context import CryptContext

    eval_email = "admin@ibdms.org"
    eval_password = "Admin@Secure2026"
    env_email = os.getenv("ADMIN_EMAIL", eval_email)
    env_password = os.getenv("ADMIN_PASSWORD", eval_password)

    pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
    db = SessionLocal()
    try:
        for email, password, name in [
            (eval_email, eval_password, "Master Administrator"),
            (env_email, env_password, "System Administrator"),
        ]:
            email = email.strip().lower()
            user = db.query(User).filter(User.email == email).first()
            hashed = pwd_ctx.hash(password)
            if user:
                user.password_hash = hashed
                user.role = "Administrator"
                if name:
                    user.full_name = name
            else:
                db.add(
                    User(
                        full_name=name,
                        email=email,
                        password_hash=hashed,
                        role="Administrator",
                        phone_number="+92-300-0000000",
                        blood_group="O+",
                    )
                )
        db.commit()
        print(f"INFO:     Admin accounts ready: {eval_email} / {env_email}")
    finally:
        db.close()


# ── UDP LAN Autodiscovery Broadcaster ────────────────────────────────────────

def _udp_broadcaster() -> None:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(0.5)
        payload = f"IBDMS_SERVER:{app_settings.PORT}".encode()
        while True:
            try:
                sock.sendto(payload, ("<broadcast>", 5001))
            except Exception:
                pass
            time.sleep(3)
    except Exception as exc:
        print(f"WARNING:  UDP broadcaster stopped: {exc}")


# ── Application startup ───────────────────────────────────────────────────────

@app.on_event("startup")
async def on_startup() -> None:
    _run_column_migrations()
    _seed_admin()
    start_escalation_worker()
    init_notifications()
    await hub.start_drainer()

    t = threading.Thread(target=_udp_broadcaster, daemon=True, name="udp-broadcaster")
    t.start()
    print("INFO:     UDP autodiscovery broadcaster active on LAN:5001")
    print(f"INFO:     Public base URL: {app_settings.get_public_base_url()}")
    print(f"INFO:     Google OAuth redirect: {app_settings.google_oauth_redirect_uri()}")
    print(f"INFO:     Google Web redirect: {app_settings.google_web_redirect_uri()}")


# ── Health check ─────────────────────────────────────────────────────────────

@app.get("/")
def health_check():
    return {
        "status": "Operational",
        "system": "IBDMS Backend v4.0",
        "public_base_url": app_settings.get_public_base_url(),
        "port": app_settings.PORT,
        "google_oauth_redirect": app_settings.google_oauth_redirect_uri(),
        "google_web_redirect": app_settings.google_web_redirect_uri(),
        "features": [
            "Universal auth — password + Google Sign-In",
            "Forgot Password OTP via SMTP",
            "Dual-role entity (request blood + donate)",
            "Haversine matching with bbox pre-filter (5 → 50 km in +5 km steps)",
            "Two-stage privacy gate (PENDING → ACCEPTED contact reveal)",
            "JWT-scoped self-alert prevention",
            "Async SMTP + FCM via BackgroundTasks",
            "In-app alert polling feed",
            "60-day donor deferral lockout",
            "RAG-style AI chatbot with strict scope guard",
            "Admin management panel",
            "LAN UDP autodiscovery",
            "CORS enabled for mobile + web clients",
        ],
        "endpoints": [
            "POST /api/auth/register",
            "POST /api/auth/login",
            "GET  /api/auth/oauth-config",
            "POST /api/auth/google",
            "PUT  /api/auth/complete-profile",
            "PATCH /api/auth/select-role",
            "POST /api/auth/forgot-password",
            "POST /api/auth/reset-password",
            "PUT  /api/auth/fcm-token",
            "POST /api/requests/create",
            "GET  /api/requests/{id}/status",
            "POST /api/requests/{id}/cancel",
            "GET  /api/requests/nearby",
            "GET  /api/alerts/feed",
            "POST /api/alerts/matches/{id}/connect",
            "POST /api/alerts/matches/{id}/continue-search",
            "POST /api/alerts/matches/{id}/accept",
            "POST /api/alerts/matches/{id}/reject",
            "POST /api/alerts/matches/{id}/complete",
            "GET  /api/alerts/matches/{id}",
            "GET  /api/donor/profile",
            "GET  /api/donor/cooldown",
            "POST /api/donor/enroll",
            "PUT  /api/donor/availability",
            "POST /api/chatbot/message  ← RAG endpoint",
            "GET  /api/chatbot/query",
            "POST /api/admin/login",
            "GET  /api/admin/analytics/blood-stock",
            "GET  /api/admin/analytics/timeline",
            "GET  /api/admin/analytics/heatmap",
            "GET  /api/admin/donors",
            "GET  /api/admin/requests",
            "GET  /api/admin/users",
            "PUT  /api/admin/users/{id}/override",
            "GET  /api/admin/requests/unfulfilled",
            "PUT  /api/admin/requests/{id}/override",
        ],
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=app_settings.PORT,
        reload=True,
    )
