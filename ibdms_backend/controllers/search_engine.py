"""
Time-Staged Radius Escalation Engine
=====================================
Runs as a background daemon thread (started by main.py on_startup).

Algorithm
---------
Every POLL_INTERVAL_SECONDS the worker queries all 'Pending' blood requests.
For each request whose search_updated_at is at least STAGE_DURATION_SECONDS
old, the engine:

  1. Increments current_radius_km by STEP_KM (up to MAX_RADIUS_KM).
  2. Re-runs the Haversine matching pipeline at the new radius.
  3. If matched_count >= units_required  →  marks the request 'Fulfilled'.
  4. If new radius == MAX_RADIUS_KM and still no match after the stage
     wait  →  marks the request 'Unfulfilled' (Admin Notified).

Early-exit conditions (handled via /cancel endpoint in blood_routes.py):
  - Recipient calls POST /api/requests/{id}/cancel → status set to 'Cancelled'.
    The worker skips non-Pending requests, so escalation stops immediately.
"""

import threading
import time
from datetime import datetime

from config.database import SessionLocal
from models.request import BloodRequest
from controllers.matching_engine import process_matching_pipeline

# ── Tuneable constants ────────────────────────────────────────────────────────
POLL_INTERVAL_SECONDS: int = 30      # Worker wake-up frequency
STAGE_DURATION_SECONDS: int = 300    # 5 minutes per radius tier
INITIAL_RADIUS_KM: float = 5.0
STEP_KM: float = 5.0
MAX_RADIUS_KM: float = 50.0


# ── Worker implementation ─────────────────────────────────────────────────────

def _run_escalation_cycle() -> None:
    """Single escalation pass — opens its own DB session, closes it when done."""
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        pending = (
            db.query(BloodRequest)
            .filter(BloodRequest.status == "Pending")
            .all()
        )

        for req in pending:
            # Initialise search_updated_at if somehow missing.
            if req.search_updated_at is None:
                req.search_updated_at = now
                db.commit()
                continue

            elapsed = (now - req.search_updated_at).total_seconds()
            if elapsed < STAGE_DURATION_SECONDS:
                continue  # Stage timer not yet expired.

            current_r = float(req.current_radius_km or INITIAL_RADIUS_KM)

            # ── Hard ceiling: mark Unfulfilled and stop ────────────────────
            if current_r >= MAX_RADIUS_KM:
                req.status = "Unfulfilled"
                req.closed_at = now
                db.commit()
                print(
                    f"INFO:  [Escalation] Request {req.request_id} → Unfulfilled "
                    f"(exhausted {MAX_RADIUS_KM} km ceiling)"
                )
                continue

            # ── Increment radius and re-match ──────────────────────────────
            new_r = min(current_r + STEP_KM, MAX_RADIUS_KM)
            matched = process_matching_pipeline(
                db,
                float(req.request_latitude),
                float(req.request_longitude),
                req.blood_group_needed,
                new_r,
            )

            req.current_radius_km = new_r
            req.matched_count = len(matched)
            req.search_updated_at = now  # Reset stage timer.

            if len(matched) >= req.units_required:
                req.status = "Fulfilled"
                req.closed_at = now
                print(
                    f"INFO:  [Escalation] Request {req.request_id} → Fulfilled "
                    f"at {new_r} km ({len(matched)} donor(s))"
                )
            else:
                print(
                    f"INFO:  [Escalation] Request {req.request_id} → "
                    f"radius escalated to {new_r} km ({len(matched)} donor(s) found)"
                )

            if matched and req.status == "Pending":
                from controllers.notification_controller import (
                    broadcast_blood_request_push,
                    send_blood_request_alert,
                )

                location_hint = (
                    f"Lat {round(float(req.request_latitude), 3)}, "
                    f"Lon {round(float(req.request_longitude), 3)}"
                )
                fcm_tokens = [d["fcm_token"] for d in matched if d.get("fcm_token")]
                donor_emails = [d["email"] for d in matched if d.get("email")]

                threading.Thread(
                    target=broadcast_blood_request_push,
                    args=(
                        fcm_tokens,
                        req.blood_group_needed,
                        location_hint,
                        req.request_id,
                    ),
                    daemon=True,
                ).start()
                threading.Thread(
                    target=send_blood_request_alert,
                    args=(
                        donor_emails,
                        "IBDMS Patient",
                        req.blood_group_needed,
                        location_hint,
                        req.request_id,
                    ),
                    daemon=True,
                ).start()

            db.commit()

    except Exception as exc:
        print(f"WARNING: [Escalation] cycle error — {exc}")
    finally:
        db.close()


def _escalation_loop() -> None:
    print("INFO:     Radius escalation worker started (5 min stages, max 50 km).")
    while True:
        _run_escalation_cycle()
        time.sleep(POLL_INTERVAL_SECONDS)


def start_escalation_worker() -> None:
    """Spawn the daemon thread.  Call once from main.py on_startup."""
    t = threading.Thread(
        target=_escalation_loop,
        daemon=True,
        name="radius-escalation-worker",
    )
    t.start()
