from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from config.database import get_db
from middleware.auth_guard import get_current_user
from schemas.auth_schema import (
    UserRegisterSchema,
    UserLoginSchema,
    TokenResponseSchema,
    GoogleSignInSchema,
    GoogleWebSignInSchema,
    CompleteProfileSchema,
    RoleSelectSchema,
    ForgotPasswordSchema,
    ResetPasswordSchema,
    FcmTokenUpdateSchema,
)
from controllers import auth_controller
from controllers.notification_controller import (
    send_login_alert,
    send_forgot_password_email,
)

router = APIRouter(prefix="/api/auth", tags=["Authentication System Gateway"])


@router.get("/oauth-config")
def oauth_config():
    """
    Public OAuth / redirect URIs for Google Cloud Console and Flutter clients.
    Uses NGROK_BASE_URL from .env when set.
    """
    from config.settings import (
        GOOGLE_CLIENT_ID,
        get_public_base_url,
        google_oauth_redirect_uri,
        google_web_redirect_uri,
    )

    base = get_public_base_url()
    return {
        "public_base_url": base,
        "google_client_id": GOOGLE_CLIENT_ID,
        "google_oauth_redirect_uri": google_oauth_redirect_uri(),
        "google_web_redirect_uri": google_web_redirect_uri(),
        "google_post_login_redirect": f"{base}/",
        "api_base": f"{base}/api",
    }


# ── Universal Registration ────────────────────────────────────────────────────

@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(payload: UserRegisterSchema, db: Session = Depends(get_db)):
    """
    Universal registration — no role selection.
    Blood group is mandatory; a DonorProfile is auto-created with
    Inactive availability so the user must explicitly opt-in to donate.
    Administrator accounts are seeded via backend seed_admin(), not
    reachable through this public endpoint.
    """
    try:
        user = auth_controller.register_new_user(db, payload)
        return {
            "message": "Account created successfully.",
            "user_id": user.user_id,
            "full_name": user.full_name,
            "blood_group": user.blood_group,
        }
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception:
        raise HTTPException(
            status_code=400,
            detail="Registration failed. Email may already be in use.",
        )


# ── Credential Login ──────────────────────────────────────────────────────────

@router.post("/login", response_model=TokenResponseSchema)
def login(payload: UserLoginSchema, db: Session = Depends(get_db)):
    result = auth_controller.authenticate_user(db, payload.email, payload.password)
    if not result:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
        )
    # Fire login-alert email in background (non-blocking).
    from models.user import User
    user = db.query(User).filter(User.email == payload.email.lower()).first()
    if user:
        send_login_alert(user.email, user.full_name)
    return result


# ── Google Sign-In ────────────────────────────────────────────────────────────

@router.post("/google", response_model=TokenResponseSchema)
def google_signin(payload: GoogleSignInSchema, db: Session = Depends(get_db)):
    """
    Verify a Google ID token from the Flutter google_sign_in plugin.
    If the user is new or has missing profile data, returns needs_profile=True.
    Frontend must redirect such users to the CompleteProfile screen.
    """
    try:
        result = auth_controller.google_signin(db, payload.id_token)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Google login failed. Please try again.",
        )

    # Login alert for Google Sign-In (same as password login).
    import jwt
    from models.user import User

    try:
        token_payload = jwt.decode(
            result["access_token"],
            auth_controller.SECRET_KEY,
            algorithms=[auth_controller.ALGORITHM],
        )
        user = db.query(User).filter(
            User.user_id == int(token_payload["sub"])
        ).first()
        if user:
            send_login_alert(user.email, user.full_name)
    except Exception:
        pass  # Never block login if the alert email fails.

    return result


# ── Google Sign-In Web (access-token fallback) ───────────────────────────────

@router.post("/google-web", response_model=TokenResponseSchema)
def google_signin_web(payload: GoogleWebSignInSchema, db: Session = Depends(get_db)):
    """
    Web-only fallback for google_sign_in_web token-client flow.
    Verifies the access_token against Google's userinfo endpoint.
    """
    try:
        result = auth_controller.google_signin_web(db, payload.access_token)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="Google web login failed. Please try again.")

    import jwt
    from models.user import User
    try:
        token_payload = jwt.decode(
            result["access_token"],
            auth_controller.SECRET_KEY,
            algorithms=[auth_controller.ALGORITHM],
        )
        user = db.query(User).filter(
            User.user_id == int(token_payload["sub"])
        ).first()
        if user:
            send_login_alert(user.email, user.full_name)
    except Exception:
        pass

    return result


# ── Complete Profile (Google Sign-In) ─────────────────────────────────────────

@router.put("/complete-profile", response_model=TokenResponseSchema)
def complete_profile(
    payload: CompleteProfileSchema,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Called after Google Sign-In when needs_profile=True.
    This screen is un-skippable on the frontend.
    """
    try:
        return auth_controller.complete_profile(db, current_user["user_id"], payload)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))


# ── Role Selection (onboarding) ───────────────────────────────────────────────

@router.patch("/select-role", response_model=TokenResponseSchema)
def select_role(
    payload: RoleSelectSchema,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Mandatory onboarding step for new users with role='Unassigned'.
    Persists Donor or Recipient and returns a fresh JWT with the chosen role.
    """
    try:
        return auth_controller.select_role(
            db, current_user["user_id"], payload.role
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


# ── Forgot Password ───────────────────────────────────────────────────────────

@router.post("/forgot-password", status_code=status.HTTP_200_OK)
def forgot_password(payload: ForgotPasswordSchema, db: Session = Depends(get_db)):
    """
    Generates a 6-digit OTP and emails it to the address.
    Always returns HTTP 200 to prevent account enumeration.
    """
    from models.user import User
    otp = auth_controller.generate_reset_otp(db, payload.email)
    if otp:
        user = db.query(User).filter(User.email == payload.email.lower()).first()
        if user:
            send_forgot_password_email(user.email, user.full_name, otp)
    return {
        "message": "If an account exists with that email, a reset code has been sent."
    }


# ── Reset Password ────────────────────────────────────────────────────────────

@router.post("/reset-password", status_code=status.HTTP_200_OK)
def reset_password(payload: ResetPasswordSchema, db: Session = Depends(get_db)):
    success = auth_controller.reset_password(db, payload)
    if not success:
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired OTP. Request a new reset code.",
        )
    return {"message": "Password updated successfully. You can now log in."}


# ── FCM Token ─────────────────────────────────────────────────────────────────

@router.put("/fcm-token", status_code=status.HTTP_200_OK)
def update_fcm_token(
    payload: FcmTokenUpdateSchema,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Called on every app launch to register/refresh the device FCM token.
    Required for push notification delivery.
    """
    auth_controller.update_fcm_token(db, current_user["user_id"], payload.fcm_token)
    return {"message": "FCM token updated."}
