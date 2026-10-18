"""
Central environment configuration — load .env before any other app imports.
"""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

# Resolve ibdms_backend/.env regardless of cwd
_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_ENV_FILE = _BACKEND_ROOT / ".env"
load_dotenv(_ENV_FILE, override=True)

PORT: int = int(os.getenv("PORT", "5000"))
NGROK_BASE_URL: str = (os.getenv("NGROK_BASE_URL") or "").strip().rstrip("/")
GOOGLE_CLIENT_ID: str = os.getenv("GOOGLE_CLIENT_ID", "")
JWT_SECRET: str = os.getenv("JWT_SECRET", "SUPER_SECRET_COMP_SCI_KEY")


def get_public_base_url() -> str:
    """
    Public HTTPS base used for OAuth redirect URIs and email deep-links.
    Falls back to http://localhost:{PORT} when NGROK_BASE_URL is unset.
    """
    if NGROK_BASE_URL:
        return NGROK_BASE_URL
    return f"http://localhost:{PORT}"


def google_oauth_redirect_uri(path: str = "/api/auth/google/callback") -> str:
    """Authorized redirect URI for Google Cloud Console (backend callback)."""
    return f"{get_public_base_url()}{path}"


def google_web_redirect_uri(path: str = "/auth/google/callback") -> str:
    """Flutter web OAuth redirect (register in Google Cloud Console)."""
    return f"{get_public_base_url()}{path}"


def cors_origins() -> list[str]:
    """CORS allowlist — ngrok + local dev."""
    origins = {
        get_public_base_url(),
        f"http://localhost:{PORT}",
        f"http://127.0.0.1:{PORT}",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:52624",
        "http://127.0.0.1:52624",
    }
    if NGROK_BASE_URL:
        origins.add(NGROK_BASE_URL)
    return sorted(origins)


def cors_origin_regex() -> str:
    """Allow any localhost port (Flutter web dev uses varying ports)."""
    return r"http://(localhost|127\.0\.0\.1)(:\d+)?"
