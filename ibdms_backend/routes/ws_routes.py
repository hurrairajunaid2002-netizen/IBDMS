"""WebSocket alert stream — instant FOUND push alongside HTTP live polling."""

import jwt
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query

from controllers.ws_hub import hub
from middleware.auth_guard import SECRET_KEY, ALGORITHM

router = APIRouter(tags=["WebSocket Alerts"])


def _user_id_from_token(token: str) -> int | None:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        sub = payload.get("sub")
        return int(sub) if sub is not None else None
    except jwt.PyJWTError:
        return None


@router.websocket("/ws/alerts")
async def alerts_websocket(
    websocket: WebSocket,
    token: str = Query(..., description="JWT Bearer token (same as REST API)"),
):
    """
    Real-time match events for the authenticated user.
    Flutter: `WebSocketChannel.connect(Uri.parse('$wsUrl?token=$jwt'))`
    """
    user_id = _user_id_from_token(token.strip())
    if user_id is None:
        await websocket.close(code=4401)
        return

    await hub.connect(user_id, websocket)
    try:
        while True:
            # Keep-alive; client may send "ping"
            msg = await websocket.receive_text()
            if msg.strip().lower() == "ping":
                await websocket.send_text('{"type":"pong"}')
    except WebSocketDisconnect:
        hub.disconnect(user_id, websocket)
