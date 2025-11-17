from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Optional


class PipelineState:
    """管理增量时间戳、缓存索引等运行状态"""

    def __init__(self, path: Path):
        self.path = path
        self.sessions: Dict[str, Dict[str, int]] = {}
        self.meta: Dict[str, str] = {}
        self._loaded = False

    def load(self) -> None:
        if self._loaded:
            return
        if self.path.exists():
            with open(self.path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.sessions = data.get("sessions", {})
            self.meta = data.get("meta", {})
        self._loaded = True

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "sessions": self.sessions,
                    "meta": self.meta,
                },
                f,
                ensure_ascii=False,
                indent=2,
            )

    def get_last_timestamp(self, session_id: str) -> Optional[int]:
        self.load()
        entry = self.sessions.get(session_id)
        if not entry:
            return None
        return entry.get("last_timestamp")

    def update_session(self, session_id: str, timestamp: Optional[int], **extra: int) -> None:
        self.load()
        if session_id not in self.sessions:
            self.sessions[session_id] = {}
        if timestamp is not None:
            previous = self.sessions[session_id].get("last_timestamp", 0)
            self.sessions[session_id]["last_timestamp"] = max(previous, timestamp)
        for key, value in extra.items():
            if value is not None:
                self.sessions[session_id][key] = value


__all__ = ["PipelineState"]
