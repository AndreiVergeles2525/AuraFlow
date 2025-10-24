"""
Helpers to manage the wallpaper daemon lifecycle and auto-start behaviour.
"""

from __future__ import annotations

import json
import os
import plistlib
import signal
import subprocess
import time
import sys
from pathlib import Path
from typing import Optional

from paths import (
    AGENT_PLIST_PATH,
    APP_ID,
    CONFIG_PATH,
    LOG_PATH,
    PID_PATH,
    ensure_app_support_dir,
)


_LAST_LAUNCH_SIGNATURE: Optional[tuple] = None


def _python_executable() -> str:
    """Return the interpreter that should run the daemon."""

    return os.environ.get("PYTHON_EXECUTABLE") or sys.executable


def _daemon_script() -> Path:
    return Path(__file__).resolve().parent / "wallpaper_daemon.py"


def _launchctl(args, *, ignore_errors: bool = False) -> bool:
    result = subprocess.run(  # noqa: S603
        ["launchctl", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        if ignore_errors:
            return False
        message = result.stderr.strip() or result.stdout.strip() or "unknown error"
        raise RuntimeError(message)
    return True


def _launch_signature(
    config_path: Path,
    video_path: Optional[str],
    playback_speed: Optional[float],
    volume: Optional[float],
) -> tuple:
    try:
        config_hash = hash(config_path.read_bytes())
    except OSError:
        config_hash = None
    return (
        str(config_path.resolve()),
        video_path,
        None if playback_speed is None else float(playback_speed),
        None if volume is None else float(volume),
        config_hash,
    )


def _await_pid(pid: int, wait: float) -> None:
    if wait <= 0:
        return
    deadline = time.time() + wait
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
            return
        except OSError:
            time.sleep(0.05)


def _terminate_pid(pid: int, timeout: float = 1.0) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return

    deadline = time.time() + max(timeout, 0.2)
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except OSError:
            return
        time.sleep(0.05)

    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        return


def _list_daemon_pids() -> set[int]:
    script_path = str(_daemon_script())
    try:
        result = subprocess.run(  # noqa: S603
            ["pgrep", "-f", script_path],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return set()

    if result.returncode not in (0, 1):
        return set()

    pids = set()
    for line in result.stdout.strip().splitlines():
        try:
            pids.add(int(line.strip()))
        except ValueError:
            continue
    return pids


def _cleanup_orphaned_daemons(keep: Optional[set[int]] = None) -> None:
    keep = keep or set()
    active = _list_daemon_pids()
    pid_from_file = read_pid()
    if pid_from_file is not None:
        keep.add(pid_from_file)

    for pid in active - keep:
        _terminate_pid(pid, timeout=0.5)


def daemon_running() -> bool:
    """Check the PID file and verify whether the daemon is alive."""

    pid = read_pid()
    if pid is None:
        return False

    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def read_pid() -> Optional[int]:
    if not PID_PATH.exists():
        return None
    try:
        return int(PID_PATH.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None


def _write_pid(pid: int) -> None:
    ensure_app_support_dir()
    PID_PATH.write_text(str(pid), encoding="utf-8")


def _launch_daemon(
    config_path: Path = CONFIG_PATH,
    video_path: Optional[str] = None,
    playback_speed: Optional[float] = None,
    volume: Optional[float] = None,
) -> int:
    ensure_app_support_dir()
    log_file = LOG_PATH.open("ab")
    cmd = [
        _python_executable(),
        str(_daemon_script()),
        "--config",
        str(config_path),
    ]
    if video_path:
        cmd.extend(["--video", video_path])
    if playback_speed is not None:
        cmd.extend(["--speed", str(playback_speed)])
    if volume is not None:
        cmd.extend(["--volume", str(volume)])
    cmd.append("run")

    process = subprocess.Popen(  # noqa: S603
        cmd,
        stdout=log_file,
        stderr=log_file,
        start_new_session=True,
        close_fds=True,
    )
    # PID file is written by the daemon shortly after launch.
    return process.pid


def start_daemon(
    config_path: Path = CONFIG_PATH,
    video_path: Optional[str] = None,
    playback_speed: Optional[float] = None,
    volume: Optional[float] = None,
    wait: float = 0.5,
) -> int:
    global _LAST_LAUNCH_SIGNATURE
    signature = _launch_signature(config_path, video_path, playback_speed, volume)

    _cleanup_orphaned_daemons()

    if daemon_running():
        if _LAST_LAUNCH_SIGNATURE == signature and PID_PATH.exists():
            existing = read_pid()
            if existing is not None:
                return existing
        return restart_daemon(
            config_path=config_path,
            video_path=video_path,
            playback_speed=playback_speed,
            volume=volume,
            wait=wait,
        )

    pid = _launch_daemon(config_path, video_path, playback_speed, volume)
    _write_pid(pid)
    _LAST_LAUNCH_SIGNATURE = signature
    _await_pid(pid, wait)
    _cleanup_orphaned_daemons(keep={pid})
    return pid


def stop_daemon(timeout: float = 1.5) -> None:
    """Terminate the daemon process if it is running."""

    global _LAST_LAUNCH_SIGNATURE
    _LAST_LAUNCH_SIGNATURE = None

    pid = read_pid()
    if pid is not None:
        _terminate_pid(pid, timeout=timeout)
    PID_PATH.unlink(missing_ok=True)
    _cleanup_orphaned_daemons()
    return


def restart_daemon(
    config_path: Path = CONFIG_PATH,
    video_path: Optional[str] = None,
    playback_speed: Optional[float] = None,
    volume: Optional[float] = None,
    wait: float = 0.5,
) -> int:
    """Convenience helper to restart the daemon with updated parameters."""

    stop_daemon(timeout=1.5)
    return start_daemon(
        config_path=config_path,
        video_path=video_path,
        playback_speed=playback_speed,
        volume=volume,
        wait=wait,
    )


def _build_launch_agent_plist(config_path: Path) -> dict:
    return {
        "Label": APP_ID,
        "ProgramArguments": [
            _python_executable(),
            str(_daemon_script()),
            "--config",
            str(config_path),
            "run",
        ],
        "RunAtLoad": True,
        "KeepAlive": False,
        "StandardOutPath": str(LOG_PATH),
        "StandardErrorPath": str(LOG_PATH),
    }


def enable_autostart(config_path: Path = CONFIG_PATH) -> None:
    """Write the LaunchAgent plist and load it."""

    ensure_app_support_dir()
    AGENT_PLIST_PATH.parent.mkdir(parents=True, exist_ok=True)

    plist = _build_launch_agent_plist(config_path)
    plist_path_tmp = AGENT_PLIST_PATH.with_suffix(".plist.tmp")
    with plist_path_tmp.open("wb") as handle:
        plistlib.dump(plist, handle)
    plist_path_tmp.replace(AGENT_PLIST_PATH)

    _launchctl(["unload", str(AGENT_PLIST_PATH)], ignore_errors=True)
    _launchctl(["load", "-w", str(AGENT_PLIST_PATH)])


def disable_autostart() -> None:
    """Remove the LaunchAgent plist and unload."""

    if AGENT_PLIST_PATH.exists():
        _launchctl(["unload", str(AGENT_PLIST_PATH)], ignore_errors=True)
        AGENT_PLIST_PATH.unlink(missing_ok=True)


def autostart_enabled() -> bool:
    """Return True if the LaunchAgent plist currently exists."""

    return AGENT_PLIST_PATH.exists()
