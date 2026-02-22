"""
Common filesystem locations for the video wallpaper daemon.
"""

from __future__ import annotations

from pathlib import Path

APP_ID = "com.example.auraflow"
APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "AuraFlow"
CONFIG_PATH = APP_SUPPORT_DIR / "config.json"
PID_PATH = APP_SUPPORT_DIR / "daemon.pid"
LOG_PATH = APP_SUPPORT_DIR / "daemon.log"
DAEMON_PAUSED_PATH = APP_SUPPORT_DIR / "daemon.paused"
DAEMON_COMMAND_PATH = APP_SUPPORT_DIR / "daemon.command"
DAEMON_HEALTH_PATH = APP_SUPPORT_DIR / "daemon.health.json"
DAEMON_LOCK_PATH = APP_SUPPORT_DIR / "daemon.lock"
LAST_FRAME_PATH = APP_SUPPORT_DIR / "last_frame.png"
WALLPAPER_BACKUP_PATH = APP_SUPPORT_DIR / "wallpaper_backup.json"
WALLPAPER_ORIGINAL_BACKUP_PATH = APP_SUPPORT_DIR / "wallpaper_backup_original.json"
LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
AGENT_PLIST_PATH = LAUNCH_AGENTS_DIR / f"{APP_ID}.plist"


def ensure_app_support_dir() -> None:
    """
    Ensure the application support directory exists.
    """

    APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
