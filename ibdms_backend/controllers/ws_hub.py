"""
Thread-safe WebSocket event hub for instant match FOUND push to Flutter clients.
Polling remains the fallback when no socket is connected.
"""

from __future__ import annotations

import asyncio
import json
from collections import deque
from typing import Any, Deque, Dict, Set, Tuple

from fastapi import WebSocket


class WsHub:
    def __init__(self) -> None:
        self._connections: Dict[int, Set[WebSocket]] = {}
        self._queue: Deque[Tuple[int, dict]] = deque()
        self._drain_task: asyncio.Task | None = None

    async def connect(self, user_id: int, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections.setdefault(user_id, set()).add(websocket)
        print(f"[WS] user_id={user_id} connected ({len(self._connections[user_id])} socket(s))", flush=True)

    def disconnect(self, user_id: int, websocket: WebSocket) -> None:
        conns = self._connections.get(user_id)
        if not conns:
            return
        conns.discard(websocket)
        if not conns:
            self._connections.pop(user_id, None)
        print(f"[WS] user_id={user_id} disconnected", flush=True)

    def enqueue(self, user_id: int, payload: dict) -> None:
        """Safe to call from sync code (search pipeline / background worker)."""
        self._queue.append((user_id, payload))
        print(
            f"[WS] queued → user_id={user_id} type={payload.get('type')} "
            f"status={payload.get('status')}",
            flush=True,
        )

    async def start_drainer(self) -> None:
        if self._drain_task and not self._drain_task.done():
            return

        async def _loop() -> None:
            while True:
                while self._queue:
                    user_id, payload = self._queue.popleft()
                    await self.send_to_user(user_id, payload)
                await asyncio.sleep(0.05)

        self._drain_task = asyncio.create_task(_loop())

    async def send_to_user(self, user_id: int, payload: dict) -> None:
        conns = list(self._connections.get(user_id, []))
        if not conns:
            return
        dead: list[WebSocket] = []
        for ws in conns:
            try:
                await ws.send_text(json.dumps(payload))
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(user_id, ws)


hub = WsHub()
