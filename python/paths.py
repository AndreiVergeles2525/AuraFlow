"""
Common filesystem locations for the video wallpaper daemon.
"""

from __future__ import annotations

import os
from pathlib import Path

APP_ID = "com.example.videowallpaper"
APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "AuraFlow"
CONFIG_PATH = APP_SUPPORT_DIR / "config.json"
PID_PATH = APP_SUPPORT_DIR / "daemon.pid"
LOG_PATH = APP_SUPPORT_DIR / "daemon.log"
LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
AGENT_PLIST_PATH = LAUNCH_AGENTS_DIR / f"{APP_ID}.plist"


def ensure_app_support_dir() -> None:
    """
    Ensure the application support directory exists.
    """

    APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
