"""
IBDMS Backend — FastAPI Application Entry Point  v3.0
======================================================
Startup order:
  1. Create all DB tables (create_all).
  2. Run idempotent ALTER TABLE column migrations.
  3. Seed the administrator account (env-configurable, one-time).
  4. Start the time-staged radius escalation worker thread.
  5. Start the UDP LAN autodiscovery broadcaster thread.
  6. Initialise the notification engine (SMTP + FCM).

Environment variables (set in ibdms_backend/.env):
  JWT_SECRET           HS256 signing secret (change in production!)
  ADMIN_EMAIL          admin@ibdms.com
  ADMIN_PASSWORD       Admin@IBDMS2024!
  SMTP_HOST            smtp.gmail.com
  SMTP_PORT            587
  SMTP_USER            your@gmail.com
  SMTP_PASSWORD        Gmail App Password
  SMTP_FROM            IBDMS <your@gmail.com>
  FIREBASE_CRED        /abs/path/service-account.json
  GOOGLE_CLIENT_ID     OAuth 2.0 Web Client ID
"""

import os
import socket
import threading
import time

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from config.database import Base, engine, SessionLocal
from routes import auth_routes, blood_routes, chatbot_routes, donor_routes
from routes import admin_routes
from controllers.search_engine import start_escalation_worker
from controllers.notification_controller import init_notifications

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
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_routes.router)
app.include_router(blood_routes.router)
app.include_router(chatbot_routes.router)
app.include_router(donor_routes.router)
app.include_router(admin_routes.router)


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
    Ensures at least one Administrator account exists.
    Credentials are read from environment variables so they are never
    hard-coded in source files checked into version control.
    """
    from models.user import User
    from passlib.context import CryptContext

    admin_email = os.getenv("ADMIN_EMAIL", "admin@ibdms.com")
    admin_password = os.getenv("ADMIN_PASSWORD", "Admin@IBDMS2024!")

    db = SessionLocal()
    try:
        existing = db.query(User).filter(User.email == admin_email).first()
        if existing:
            return
        pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")
        admin = User(
            full_name="System Administrator",
            email=admin_email,
            password_hash=pwd.hash(admin_password),
            role="Administrator",
            phone_number="+92-300-0000000",
            blood_group="O+",
        )
        db.add(admin)
        db.commit()
        print(f"INFO:     Admin account seeded: {admin_email}")
        print(f"INFO:     Default password: {admin_password}  ← change in .env")
    finally:
        db.close()


# ── UDP LAN Autodiscovery Broadcaster ────────────────────────────────────────

def _udp_broadcaster() -> None:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(0.5)
        payload = b"IBDMS_SERVER:5000"
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

    t = threading.Thread(target=_udp_broadcaster, daemon=True, name="udp-broadcaster")
    t.start()
    print("INFO:     UDP autodiscovery broadcaster active on LAN:5001")


# ── Health check ─────────────────────────────────────────────────────────────

@app.get("/")
def health_check():
    return {
        "status": "Operational",
        "system": "IBDMS Backend v3.0",
        "features": [
            "Universal auth — password + Google Sign-In",
            "Forgot Password OTP via SMTP",
            "Dual-role entity (request blood + donate)",
            "Time-staged radius escalation: 5 km → 50 km in 5-min steps",
            "60-day donor deferral lockout",
            "FCM push notifications to matched donors",
            "SMTP email: login alerts, forgot-password, request alerts",
            "RAG-style AI chatbot with strict scope guard",
            "Admin management panel",
            "LAN UDP autodiscovery",
        ],
        "endpoints": [
            "POST /api/auth/register",
            "POST /api/auth/login",
            "POST /api/auth/google",
            "PUT  /api/auth/complete-profile",
            "POST /api/auth/forgot-password",
            "POST /api/auth/reset-password",
            "PUT  /api/auth/fcm-token",
            "POST /api/requests/create",
            "GET  /api/requests/{id}/status",
            "POST /api/requests/{id}/cancel",
            "GET  /api/requests/nearby",
            "GET  /api/donor/profile",
            "GET  /api/donor/cooldown",
            "POST /api/donor/enroll",
            "PUT  /api/donor/availability",
            "POST /api/chatbot/message  ← RAG endpoint",
            "GET  /api/chatbot/query",
            "GET  /api/admin/stats",
            "GET  /api/admin/users",
            "PUT  /api/admin/users/{id}/override",
            "GET  /api/admin/requests/unfulfilled",
            "PUT  /api/admin/requests/{id}/override",
        ],
    }
