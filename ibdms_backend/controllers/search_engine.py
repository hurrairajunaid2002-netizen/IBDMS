"""
Time-Staged Radius Escalation Engine  (5 → 10 → 15 … → 50 km)
==============================================================
"""

import threading
import time
from datetime import datetime

from config.database import SessionLocal
from models.request import BloodRequest
from controllers.matching_service import (
    INITIAL_RADIUS_KM,
    MAX_RADIUS_KM,
    STEP_KM,
    count_accepted_matches,
    next_radius_tier,
    push_found_ws_events,
    search_donors_at_radius,
    sync_match_records,
)
from controllers.notification_tasks import notify_match_found_worker

POLL_INTERVAL_SECONDS: int = 30
STAGE_DURATION_SECONDS: int = 120


def _run_escalation_cycle() -> None:
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        pending = (
            db.query(BloodRequest)
            .filter(BloodRequest.status == "Pending")
            .all()
        )

        for req in pending:
            if req.search_updated_at is None:
                req.search_updated_at = now
                db.commit()
                continue

            elapsed = (now - req.search_updated_at).total_seconds()
            if elapsed < STAGE_DURATION_SECONDS:
                continue

            current_r = float(req.current_radius_km or INITIAL_RADIUS_KM)

            if current_r >= MAX_RADIUS_KM:
                accepted = count_accepted_matches(db, req.request_id)
                if accepted >= req.units_required:
                    req.status = "Fulfilled"
                    req.closed_at = now
                else:
                    req.status = "Unfulfilled"
                    req.closed_at = now
                db.commit()
                print(
                    f"INFO:  [Escalation] Request {req.request_id} → {req.status} "
                    f"(ceiling {MAX_RADIUS_KM} km)"
                )
                continue

            new_r = next_radius_tier(current_r)

            matched = search_donors_at_radius(
                db,
                float(req.request_latitude),
                float(req.request_longitude),
                req.blood_group_needed,
                new_r,
                exclude_user_ids=[req.recipient_user_id],
                searcher_user_id=req.recipient_user_id,
            )

            _, newly_found = sync_match_records(db, req.request_id, matched)
            req.current_radius_km = new_r
            req.matched_count = len(matched)
            req.search_updated_at = now

            if newly_found:
                donor_lookup = {d["user_id"]: d for d in matched if d.get("user_id")}
                notify_match_found_worker(db, req, newly_found, donor_lookup)
                push_found_ws_events(db, req, newly_found, donor_lookup)

            accepted = count_accepted_matches(db, req.request_id)
            if accepted >= req.units_required:
                req.status = "Fulfilled"
                req.closed_at = now
                print(
                    f"INFO:  [Escalation] Request {req.request_id} → Fulfilled "
                    f"({accepted} accepted donor(s))"
                )
            else:
                print(
                    f"INFO:  [Escalation] Request {req.request_id} → "
                    f"radius {new_r} km ({len(matched)} discovered, "
                    f"{accepted} accepted)"
                )

            db.commit()

    except Exception as exc:
        print(f"WARNING: [Escalation] cycle error — {exc}")
    finally:
        db.close()


def _escalation_loop() -> None:
    print(
        f"INFO:     Radius escalation worker started "
        f"({INITIAL_RADIUS_KM} km → {MAX_RADIUS_KM} km in +{STEP_KM} km / "
        f"{STAGE_DURATION_SECONDS}s stages)."
    )
    while True:
        _run_escalation_cycle()
        time.sleep(POLL_INTERVAL_SECONDS)


def start_escalation_worker() -> None:
    t = threading.Thread(
        target=_escalation_loop,
        daemon=True,
        name="radius-escalation-worker",
    )
    t.start()
