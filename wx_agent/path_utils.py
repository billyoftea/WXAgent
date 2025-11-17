from __future__ import annotations

import sys
from pathlib import Path


def package_root() -> Path:
    """Return the base directory for bundled resources."""
    if hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)
    return Path(__file__).resolve().parent


def resource_path(*relative_parts: str) -> Path:
    """Resolve a path relative to the package root (works after PyInstaller)."""
    base = package_root()
    if not relative_parts:
        return base
    return (base.joinpath(*relative_parts)).resolve()


__all__ = ["package_root", "resource_path"]
