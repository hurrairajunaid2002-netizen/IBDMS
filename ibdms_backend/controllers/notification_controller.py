"""
Multi-Channel Notification Controller
======================================
Handles all outbound communications for IBDMS:

  SMTP Email  — Login security alerts, forgot-password OTPs,
                blood-request donor notifications.
  FCM Push    — Real-time push alerts to matched donors when a
                blood request is created or escalated.

Configuration (set in .env):
  SMTP_HOST         e.g. smtp.gmail.com
  SMTP_PORT         587 (TLS) or 465 (SSL)
  SMTP_USER         your-email@gmail.com
  SMTP_PASSWORD     Gmail App Password (not account password)
  SMTP_FROM         display name <your-email@gmail.com>
  FIREBASE_CRED     absolute path to firebase service-account.json
  GOOGLE_CLIENT_ID  OAuth 2.0 Web client ID for Google Sign-In

FCM Setup:
  1. Create a Firebase project at https://console.firebase.google.com
  2. Project Settings → Service Accounts → Generate new private key
  3. Save the JSON file and set FIREBASE_CRED=/path/to/file.json
  4. Place google-services.json in ibdms_frontend/android/app/

SMTP Setup (Gmail):
  1. Enable 2FA on your Google account.
  2. Google Account → Security → App Passwords → Generate.
  3. Use the 16-char app password as SMTP_PASSWORD.
"""

import os
import re
import smtplib
import threading
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr, formatdate, make_msgid
from html import escape as html_escape
from typing import List, Optional

from dotenv import load_dotenv

load_dotenv()

# ── Config from environment ───────────────────────────────────────────────────
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "").strip()
# Gmail app passwords are often copied with spaces — strip them for SMTP auth.
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "").replace(" ", "").strip()
SMTP_FROM_NAME = os.getenv("SMTP_FROM_NAME", "IBDMS")
SMTP_REPLY_TO = os.getenv("SMTP_REPLY_TO", SMTP_USER).strip() or SMTP_USER
FIREBASE_CRED = os.getenv("FIREBASE_CRED", "")

# ── FCM initialisation (lazy, so server starts even without Firebase setup) ──
_fcm_app = None
_fcm_lock = threading.Lock()


def _get_fcm_app():
    global _fcm_app
    if _fcm_app is not None:
        return _fcm_app
    with _fcm_lock:
        if _fcm_app is not None:
            return _fcm_app
        if not FIREBASE_CRED or not os.path.exists(FIREBASE_CRED):
            return None
        try:
            import firebase_admin
            from firebase_admin import credentials
            cred = credentials.Certificate(FIREBASE_CRED)
            _fcm_app = firebase_admin.initialize_app(cred)
            print("INFO:     Firebase Admin SDK initialised for FCM.")
        except Exception as exc:
            print(f"WARNING:  FCM init failed: {exc}")
            _fcm_app = None
    return _fcm_app


# ── SMTP helpers ──────────────────────────────────────────────────────────────

def _smtp_configured() -> bool:
    return bool(SMTP_USER and SMTP_PASSWORD)


def _html_to_plain(html: str) -> str:
    """Rough HTML-to-text fallback for multipart emails."""
    text = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", html, flags=re.I | re.S)
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"</p>", "\n\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _build_message(
    to: str,
    subject: str,
    html_body: str,
    text_body: Optional[str] = None,
) -> MIMEMultipart:
    """
    Build a deliverability-friendly MIME message.

    Gmail inbox placement improves when:
      - From/Reply-To match the authenticated SMTP account
      - Both text/plain and text/html parts are included
      - Subjects avoid spam triggers (URGENT, emojis, ALL CAPS)
    """
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = formataddr((SMTP_FROM_NAME, SMTP_USER))
    msg["To"] = to
    msg["Reply-To"] = SMTP_REPLY_TO
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid(domain=SMTP_USER.split("@")[-1])
    msg["MIME-Version"] = "1.0"
    msg["X-Mailer"] = "IBDMS"
    msg["Auto-Submitted"] = "auto-generated"

    plain = text_body or _html_to_plain(html_body)
    # RFC 2046: plain part first, then HTML.
    msg.attach(MIMEText(plain, "plain", "utf-8"))
    msg.attach(MIMEText(html_body, "html", "utf-8"))
    return msg


def _email_shell(title: str, body_html: str) -> str:
    """Consistent, lightweight HTML wrapper (no emojis / spam triggers)."""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html_escape(title)}</title>
</head>
<body style="margin:0;padding:0;background:#f6f6f6;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f6f6f6;padding:24px 0;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellspacing="0" cellpadding="0" style="background:#ffffff;border:1px solid #e8e8e8;border-radius:8px;">
          <tr>
            <td style="padding:24px 28px;">
              <p style="margin:0 0 16px;font-size:18px;font-weight:bold;color:#B71C1C;">{html_escape(title)}</p>
              {body_html}
              <hr style="border:none;border-top:1px solid #eee;margin:24px 0;">
              <p style="margin:0;font-size:12px;color:#888;line-height:1.5;">
                IBDMS — Intelligent Blood Donor Management System<br>
                Sent by {html_escape(SMTP_USER)}
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""


def _send_email_sync(
    to: str,
    subject: str,
    html_body: str,
    text_body: Optional[str] = None,
) -> bool:
    """Blocking SMTP send. Returns True on success."""
    if not _smtp_configured():
        print(f"INFO:  [Email] SMTP not configured — skipping '{subject}' to {to}")
        return False
    try:
        msg = _build_message(to, subject, html_body, text_body=text_body)

        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
            server.ehlo()
            server.starttls()
            server.ehlo()
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(SMTP_USER, [to], msg.as_string())
        print(f"INFO:  [Email] Sent '{subject}' -> {to}")
        return True
    except Exception as exc:
        print(f"WARNING: [Email] Failed '{subject}' -> {to}: {exc}")
        return False


def send_email(
    to: str,
    subject: str,
    html_body: str,
    text_body: Optional[str] = None,
) -> None:
    """Non-blocking: dispatches SMTP send in a daemon thread."""
    t = threading.Thread(
        target=_send_email_sync,
        args=(to, subject, html_body, text_body),
        daemon=True,
    )
    t.start()


# ── Templated email senders ───────────────────────────────────────────────────

def send_login_alert(to: str, user_name: str) -> None:
    safe_name = html_escape(user_name)
    when = __import__("datetime").datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
    subject = "IBDMS sign-in notification"
    body = f"""
      <p style="margin:0 0 12px;color:#333;">Hello {safe_name},</p>
      <p style="margin:0 0 12px;color:#333;">
        A new sign-in to your IBDMS account was detected on <strong>{when}</strong>.
      </p>
      <p style="margin:0;color:#333;">
        If this was not you, please reset your password in the app.
      </p>
    """
    text = (
        f"Hello {user_name},\n\n"
        f"A new sign-in to your IBDMS account was detected on {when}.\n\n"
        "If this was not you, please reset your password in the app.\n"
    )
    send_email(to, subject, _email_shell("Sign-in notification", body), text_body=text)


def send_forgot_password_email(to: str, user_name: str, otp: str) -> None:
    safe_name = html_escape(user_name)
    subject = "IBDMS password reset code"
    body = f"""
      <p style="margin:0 0 12px;color:#333;">Hello {safe_name},</p>
      <p style="margin:0 0 16px;color:#333;">
        Use this verification code to reset your password. It expires in 15 minutes.
      </p>
      <p style="margin:0 0 16px;font-size:28px;font-weight:bold;letter-spacing:6px;color:#B71C1C;">{html_escape(otp)}</p>
      <p style="margin:0;color:#333;">
        If you did not request a password reset, you can safely ignore this email.
      </p>
    """
    text = (
        f"Hello {user_name},\n\n"
        f"Your IBDMS password reset code is: {otp}\n"
        "This code expires in 15 minutes.\n\n"
        "If you did not request this, you can ignore this email.\n"
    )
    send_email(to, subject, _email_shell("Password reset code", body), text_body=text)


def send_blood_request_alert(
    donor_emails: List[str],
    requester_name: str,
    blood_group: str,
    location_hint: str,
    request_id: int,
) -> None:
    """Send blood-request notification to compatible donors."""
    safe_group = html_escape(blood_group)
    safe_location = html_escape(location_hint)
    subject = f"IBDMS blood donation request ({blood_group})"
    body = f"""
      <p style="margin:0 0 12px;color:#333;">
        A patient near you needs blood group <strong>{safe_group}</strong>.
      </p>
      <p style="margin:0 0 8px;color:#333;"><strong>Location:</strong> {safe_location}</p>
      <p style="margin:0 0 12px;color:#333;"><strong>Request ID:</strong> #{request_id}</p>
      <p style="margin:0;color:#333;">
        If you are available and eligible, please open the IBDMS app to respond.
      </p>
    """
    text = (
        f"A patient near you needs blood group {blood_group}.\n"
        f"Location: {location_hint}\n"
        f"Request ID: #{request_id}\n\n"
        "If you are available and eligible, please open the IBDMS app to respond.\n"
    )
    html = _email_shell("Blood donation request", body)
    for email in donor_emails:
        send_email(email, subject, html, text_body=text)


# ── FCM Push Notifications ────────────────────────────────────────────────────

def send_fcm_push(
    fcm_token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Send a push notification to a single device. Returns True on success."""
    app = _get_fcm_app()
    if app is None:
        return False
    try:
        from firebase_admin import messaging
        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=fcm_token,
            android=messaging.AndroidConfig(priority="high"),
        )
        messaging.send(msg)
        return True
    except Exception as exc:
        print(f"WARNING: [FCM] Push failed -> {fcm_token[:20]}...: {exc}")
        return False


def broadcast_blood_request_push(
    donor_tokens: List[str],
    blood_group: str,
    location_hint: str,
    request_id: int,
) -> int:
    """
    Broadcast an FCM push notification to all matched donors.
    Returns the count of successfully sent pushes.
    """
    if not donor_tokens:
        return 0
    app = _get_fcm_app()
    if app is None:
        print("INFO:  [FCM] Firebase not configured — push notifications skipped.")
        return 0

    try:
        from firebase_admin import messaging
        message = messaging.MulticastMessage(
            notification=messaging.Notification(
                title=f"🚨 Urgent: {blood_group} Blood Needed",
                body=f"A patient near {location_hint} requires {blood_group} blood. Tap to respond.",
            ),
            data={
                "request_id": str(request_id),
                "blood_group": blood_group,
                "type": "blood_request",
            },
            tokens=donor_tokens[:500],  # FCM multicast limit
            android=messaging.AndroidConfig(priority="high"),
        )
        response = messaging.send_each_for_multicast(message)
        success_count = response.success_count
        print(
            f"INFO:  [FCM] Broadcast: {success_count}/{len(donor_tokens)} "
            f"pushes sent for request #{request_id}"
        )
        return success_count
    except Exception as exc:
        print(f"WARNING: [FCM] Broadcast error: {exc}")
        return 0


def init_notifications() -> None:
    """Call once at app startup to eagerly initialise FCM and verify SMTP."""
    _get_fcm_app()
    if _smtp_configured():
        print(f"INFO:     SMTP email engine ready (host: {SMTP_HOST}).")
        if _verify_smtp_login():
            print("INFO:     SMTP login verified.")
        else:
            print(
                "WARNING:  SMTP login failed — emails will not be delivered. "
                "Check SMTP_USER / SMTP_PASSWORD (Gmail App Password, no spaces)."
            )
    else:
        print("INFO:     SMTP not configured — email notifications disabled.")


def _verify_smtp_login() -> bool:
    """Quick SMTP auth check at startup; does not send mail."""
    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
            server.ehlo()
            server.starttls()
            server.ehlo()
            server.login(SMTP_USER, SMTP_PASSWORD)
        return True
    except Exception as exc:
        print(f"WARNING: [Email] SMTP login check failed: {exc}")
        return False
