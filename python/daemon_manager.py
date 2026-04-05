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
    DAEMON_COMMAND_PATH,
    DAEMON_HEALTH_PATH,
    DAEMON_LOCK_PATH,
    DAEMON_NO_FREEZE_PATH,
    DAEMON_PAUSED_PATH,
    LOG_PATH,
    PID_PATH,
    ensure_app_support_dir,
)


_LAST_LAUNCH_SIGNATURE: Optional[tuple] = None
HEALTH_STALE_SECONDS = 4.0
SCALE_MODES = {"fill", "fit", "stretch"}


def _python_executable() -> str:
    """Return the interpreter that should run the daemon."""

    return os.environ.get("PYTHON_EXECUTABLE") or sys.executable


def _daemon_script() -> Path:
    return Path(__file__).resolve().parent / "wallpaper_daemon.py"


def _control_script() -> Path:
    return Path(__file__).resolve().parent / "control.py"


def _python_environment() -> dict[str, str]:
    script_dir = str(_daemon_script().parent)
    site_packages_dir = str(_daemon_script().parent / "site-packages")

    python_paths: list[str] = [script_dir]
    if Path(site_packages_dir).exists():
        python_paths.append(site_packages_dir)

    existing = os.environ.get("PYTHONPATH")
    if existing:
        python_paths.append(existing)

    env: dict[str, str] = {}
    for key in ("PATH", "HOME", "USER", "LOGNAME", "TMPDIR"):
        value = os.environ.get(key)
        if value:
            env[key] = value

    env["PYTHONPATH"] = ":".join(python_paths)
    env["PYTHONUNBUFFERED"] = "1"
    return env


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


def _launchctl_domain_target() -> str:
    return f"gui/{os.getuid()}"


def _launchctl_service_target() -> str:
    return f"{_launchctl_domain_target()}/{APP_ID}"


def _launch_signature(
    config_path: Path,
    video_path: Optional[str],
    playback_speed: Optional[float],
    volume: Optional[float],
    blend_interpolation: Optional[bool],
    pause_on_fullscreen: Optional[bool],
    scale_mode: Optional[str],
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
        None if blend_interpolation is None else bool(blend_interpolation),
        None if pause_on_fullscreen is None else bool(pause_on_fullscreen),
        scale_mode or None,
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


def _terminate_pids(pids: set[int], timeout: float = 1.0) -> None:
    """
    Terminate multiple daemon PIDs using one shared timeout budget.

    This avoids additive waits when duplicate/orphan daemon processes exist.
    """

    alive = {pid for pid in pids if isinstance(pid, int) and pid > 0}
    if not alive:
        return

    for pid in list(alive):
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            alive.discard(pid)

    deadline = time.time() + max(timeout, 0.2)
    while alive and time.time() < deadline:
        for pid in list(alive):
            try:
                os.kill(pid, 0)
            except OSError:
                alive.discard(pid)
        if alive:
            time.sleep(0.05)

    for pid in list(alive):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            continue


def _list_daemon_pids() -> set[int]:
    script_path = str(_daemon_script())
    script_name = _daemon_script().name

    pids = _pgrep_pids(script_path)
    # Fallback for upgrades/moves where an older daemon keeps running from a
    # different app bundle path but uses the same script name.
    pids.update(_pgrep_pids(script_name))

    lock_pid = _read_lock_pid()
    if lock_pid is not None:
        pids.add(lock_pid)

    current_pid = os.getpid()
    return {
        pid
        for pid in pids
        if pid != current_pid and _pid_is_alive(pid)
    }


def _pgrep_pids(pattern: str) -> set[int]:
    try:
        result = subprocess.run(  # noqa: S603
            ["pgrep", "-f", pattern],
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


def _read_lock_pid() -> Optional[int]:
    if not DAEMON_LOCK_PATH.exists():
        return None
    try:
        raw = DAEMON_LOCK_PATH.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    if not raw:
        return None
    try:
        pid = int(raw)
    except ValueError:
        return None
    if pid <= 0:
        return None
    return pid


def _pid_is_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except PermissionError:
        try:
            result = subprocess.run(  # noqa: S603
                ["ps", "-p", str(pid), "-o", "pid="],
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError:
            return False
        return result.returncode == 0 and bool(result.stdout.strip())
    except OSError:
        return False
    return True


def _cleanup_orphaned_daemons(
    keep: Optional[set[int]] = None,
    timeout: float = 0.5,
) -> None:
    keep = keep or set()
    active = _list_daemon_pids()
    pid_from_file = read_pid()
    if pid_from_file is not None:
        keep.add(pid_from_file)

    _terminate_pids(active - keep, timeout=timeout)


def _resolve_primary_daemon_pid() -> Optional[int]:
    """
    Return the daemon PID to use for status/metrics.

    If PID file is stale but a daemon process exists, auto-heal PID_PATH.
    """

    pid_from_file = read_pid()
    active = _list_daemon_pids()
    lock_pid = _read_lock_pid()

    if lock_pid is not None and lock_pid in active:
        if pid_from_file != lock_pid:
            try:
                _write_pid(lock_pid)
            except OSError:
                pass
        return lock_pid

    if pid_from_file is not None and pid_from_file in active:
        return pid_from_file

    if not active:
        if pid_from_file is not None:
            try:
                PID_PATH.unlink(missing_ok=True)
            except OSError:
                pass
        return None

    resolved = max(active)
    try:
        _write_pid(resolved)
    except OSError:
        pass
    return resolved


def daemon_running() -> bool:
    """Check the PID file and verify whether the daemon is alive."""

    return _resolve_primary_daemon_pid() is not None


def daemon_paused() -> bool:
    """Return True when daemon process is alive and marked as paused."""

    if not DAEMON_PAUSED_PATH.exists():
        return False
    if _resolve_primary_daemon_pid() is None:
        try:
            DAEMON_PAUSED_PATH.unlink(missing_ok=True)
        except OSError:
            pass
        return False
    return True


def _coerce_bool(value, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"1", "true", "yes", "on"}:
            return True
        if lowered in {"0", "false", "no", "off"}:
            return False
    return default


def _coerce_int(value, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _coerce_float(value, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _config_scale_mode(default: str = "fill") -> str:
    try:
        raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default
    if not isinstance(raw, dict):
        return default
    mode = str(raw.get("scale_mode") or "").strip().lower()
    if mode in SCALE_MODES:
        return mode
    return default


def daemon_health(alive: Optional[bool] = None, paused: Optional[bool] = None) -> dict:
    """
    Return a normalized daemon health snapshot consumed by CLI and Swift UI.
    """

    if alive is None:
        alive = daemon_running()
    if paused is None:
        paused = daemon_paused() if alive else False

    health = {
        "contract_version": 2,
        "available": False,
        "fresh": False,
        "suspicious": False,
        "reason": "",
        "updated_at": None,
        "lag_seconds": None,
        "screens": 0,
        "windows": 0,
        "player_rate": 0.0,
        "stall_events": 0,
        "recovery_events": 0,
        "consecutive_stall_polls": 0,
        "paused": bool(paused),
        "manual_paused": False,
        "low_power_mode": False,
        "auto_paused_for_low_power": False,
        "blend_interpolation_enabled": False,
        "blend_interpolation_active": False,
        "pause_on_fullscreen": True,
        "scale_mode": _config_scale_mode("fill"),
        "fullscreen_app_detected": False,
        "auto_paused_for_fullscreen": False,
    }

    if not alive:
        return health

    if not DAEMON_HEALTH_PATH.exists():
        health["suspicious"] = True
        health["reason"] = "missing_heartbeat"
        return health

    try:
        raw = json.loads(DAEMON_HEALTH_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        health["suspicious"] = True
        health["reason"] = "invalid_heartbeat"
        return health

    if not isinstance(raw, dict):
        health["suspicious"] = True
        health["reason"] = "invalid_heartbeat"
        return health

    updated_at = _coerce_float(raw.get("updated_at"), 0.0)
    lag = max(0.0, time.time() - updated_at) if updated_at > 0 else None
    fresh = bool(lag is not None and lag <= HEALTH_STALE_SECONDS)

    reason = str(raw.get("reason") or "")
    suspicious = _coerce_bool(raw.get("suspicious"), False) or not fresh
    if not fresh:
        reason = f"{reason},stale_heartbeat" if reason else "stale_heartbeat"

    health.update(
        {
            "available": True,
            "fresh": fresh,
            "suspicious": suspicious,
            "reason": reason,
            "updated_at": updated_at if updated_at > 0 else None,
            "lag_seconds": lag,
            "screens": _coerce_int(raw.get("screens")),
            "windows": _coerce_int(raw.get("windows")),
            "player_rate": _coerce_float(raw.get("player_rate")),
            "stall_events": _coerce_int(raw.get("stall_events")),
            "recovery_events": _coerce_int(raw.get("recovery_events")),
            "consecutive_stall_polls": _coerce_int(
                raw.get("consecutive_stall_polls")
            ),
            "paused": _coerce_bool(raw.get("paused"), bool(paused)),
            "manual_paused": _coerce_bool(raw.get("manual_paused"), False),
            "low_power_mode": _coerce_bool(raw.get("low_power_mode"), False),
            "auto_paused_for_low_power": _coerce_bool(
                raw.get("auto_paused_for_low_power"), False
            ),
            "blend_interpolation_enabled": _coerce_bool(
                raw.get("blend_interpolation_enabled"), False
            ),
            "blend_interpolation_active": _coerce_bool(
                raw.get("blend_interpolation_active"), False
            ),
            "pause_on_fullscreen": _coerce_bool(
                raw.get("pause_on_fullscreen"), True
            ),
            "scale_mode": str(raw.get("scale_mode") or "fill"),
            "fullscreen_app_detected": _coerce_bool(
                raw.get("fullscreen_app_detected"), False
            ),
            "auto_paused_for_fullscreen": _coerce_bool(
                raw.get("auto_paused_for_fullscreen"), False
            ),
            "contract_version": _coerce_int(raw.get("contract_version"), 2),
        }
    )
    return health


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


def pause_daemon() -> bool:
    """Pause daemon playback while keeping wallpaper windows on screen."""

    if not daemon_running():
        return False

    ensure_app_support_dir()
    try:
        DAEMON_COMMAND_PATH.write_text("pause", encoding="utf-8")
    except OSError:
        return False
    DAEMON_PAUSED_PATH.write_text("1", encoding="utf-8")
    return True


def resume_daemon() -> bool:
    """Resume daemon playback if it was paused."""

    if not daemon_running():
        try:
            DAEMON_PAUSED_PATH.unlink(missing_ok=True)
        except OSError:
            pass
        return False

    ensure_app_support_dir()
    try:
        DAEMON_COMMAND_PATH.write_text("resume", encoding="utf-8")
    except OSError:
        return False
    DAEMON_PAUSED_PATH.unlink(missing_ok=True)
    return True


def _launch_daemon(
    config_path: Path = CONFIG_PATH,
    video_path: Optional[str] = None,
    playback_speed: Optional[float] = None,
    volume: Optional[float] = None,
    blend_interpolation: Optional[bool] = None,
    pause_on_fullscreen: Optional[bool] = None,
    scale_mode: Optional[str] = None,
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
    if blend_interpolation is not None:
        cmd.extend(
            ["--blend-interpolation", "on" if blend_interpolation else "off"]
        )
    if pause_on_fullscreen is not None:
        cmd.extend(
            ["--pause-on-fullscreen", "on" if pause_on_fullscreen else "off"]
        )
    if scale_mode:
        cmd.extend(["--scale-mode", scale_mode])
    cmd.append("run")

    process = subprocess.Popen(  # noqa: S603
        cmd,
        stdout=log_file,
        stderr=log_file,
        start_new_session=True,
        close_fds=True,
        env=_python_environment(),
    )
    # PID file is written by the daemon shortly after launch.
    return process.pid


def start_daemon(
    config_path: Path = CONFIG_PATH,
    video_path: Optional[str] = None,
    playback_speed: Optional[float] = None,
    volume: Optional[float] = None,
    blend_interpolation: Optional[bool] = None,
    pause_on_fullscreen: Optional[bool] = None,
    scale_mode: Optional[str] = None,
    wait: float = 0.5,
) -> int:
    _cleanup_orphaned_daemons()
    DAEMON_NO_FREEZE_PATH.unlink(missing_ok=True)
    plain_start = (
        video_path is None
        and playback_speed is None
        and volume is None
        and blend_interpolation is None
        and pause_on_fullscreen is None
        and scale_mode is None
    )

    if daemon_running():
        existing = read_pid()
        if existing is None:
            # The process may have terminated between checks.
            PID_PATH.unlink(missing_ok=True)
        else:
            paused = daemon_paused()
            if (
                paused
                and plain_start
            ):
                if resume_daemon():
                    return existing

            if plain_start:
                health = daemon_health(alive=True, paused=paused)
                if health.get("suspicious"):
                    return restart_daemon(
                        config_path=config_path,
                        video_path=video_path,
                        playback_speed=playback_speed,
                        volume=volume,
                        blend_interpolation=blend_interpolation,
                        pause_on_fullscreen=pause_on_fullscreen,
                        scale_mode=scale_mode,
                        wait=wait,
                    )

            # Plain "start" while already running should be a no-op.
            if plain_start:
                return existing

            # Non-plain start is an explicit reconfiguration. Perform one
            # deterministic stop before launch to avoid restart recursion.
            stop_daemon(timeout=1.5, preserve_frame=(video_path is None))

    pid = _launch_daemon(
        config_path,
        video_path,
        playback_speed,
        volume,
        blend_interpolation,
        pause_on_fullscreen,
        scale_mode,
    )
    _write_pid(pid)
    _await_pid(pid, wait)
    resolved = _resolve_primary_daemon_pid()
    if resolved is None:
        if _pid_is_alive(pid):
            resolved = pid
            try:
                _write_pid(resolved)
            except OSError:
                pass
        else:
            raise RuntimeError("Failed to start AuraFlow daemon.")

    keep = {resolved}
    if _pid_is_alive(pid):
        keep.add(pid)
    _cleanup_orphaned_daemons(keep=keep)
    return resolved


def stop_daemon(timeout: float = 1.5, preserve_frame: bool = True) -> None:
    """Terminate the daemon process if it is running."""

    global _LAST_LAUNCH_SIGNATURE
    _LAST_LAUNCH_SIGNATURE = None

    if preserve_frame:
        DAEMON_NO_FREEZE_PATH.unlink(missing_ok=True)
    else:
        ensure_app_support_dir()
        DAEMON_NO_FREEZE_PATH.write_text("1", encoding="utf-8")

    pid = read_pid()
    lock_pid = _read_lock_pid()
    active = _list_daemon_pids()
    if pid is not None:
        active.add(pid)
    if lock_pid is not None:
        active.add(lock_pid)
    _terminate_pids(active, timeout=timeout)
    for path in (PID_PATH, DAEMON_PAUSED_PATH, DAEMON_COMMAND_PATH, DAEMON_NO_FREEZE_PATH, DAEMON_HEALTH_PATH, DAEMON_LOCK_PATH):
        try:
            path.unlink(missing_ok=True)
        except OSError:
            continue
    _cleanup_orphaned_daemons(timeout=0.2)
    return


def restart_daemon(
    config_path: Path = CONFIG_PATH,
    video_path: Optional[str] = None,
    playback_speed: Optional[float] = None,
    volume: Optional[float] = None,
    blend_interpolation: Optional[bool] = None,
    pause_on_fullscreen: Optional[bool] = None,
    scale_mode: Optional[str] = None,
    wait: float = 0.5,
) -> int:
    """Convenience helper to restart the daemon with updated parameters."""

    stop_daemon(timeout=1.5, preserve_frame=(video_path is None))
    return start_daemon(
        config_path=config_path,
        video_path=video_path,
        playback_speed=playback_speed,
        volume=volume,
        blend_interpolation=blend_interpolation,
        pause_on_fullscreen=pause_on_fullscreen,
        scale_mode=scale_mode,
        wait=wait,
    )


def daemon_resource_metrics() -> dict:
    """
    Return lightweight daemon resource usage and playback health.
    """

    active_pids = sorted(_list_daemon_pids())
    pid = _resolve_primary_daemon_pid() if active_pids else None
    alive = pid is not None
    paused = daemon_paused() if alive else False
    health = daemon_health(alive=alive, paused=paused)
    payload = {
        "contract_version": 2,
        "updated_at": time.time(),
        "running": bool(alive and not paused),
        "paused": bool(paused),
        "pid": pid,
        "daemon_pids": active_pids,
        "process_count": len(active_pids),
        "cpu_percent": 0.0,
        "memory_mb": 0.0,
        "virtual_memory_mb": 0.0,
        "thread_count": 0,
        "health": health,
    }

    if not alive or not active_pids:
        return payload

    ps_targets = ",".join(str(current_pid) for current_pid in active_pids)
    try:
        result = subprocess.run(  # noqa: S603
            ["ps", "-p", ps_targets, "-o", "pid=,%cpu=,rss=,vsz="],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return payload

    if result.returncode != 0:
        return payload

    lines = [line.strip() for line in result.stdout.strip().splitlines() if line.strip()]
    if not lines:
        return payload

    total_cpu = 0.0
    total_memory_mb = 0.0
    total_virtual_memory_mb = 0.0
    total_threads = 0
    counted = 0

    for line in lines:
        parts = line.split()
        if len(parts) < 4:
            continue
        try:
            current_pid = int(parts[0])
            cpu = float(parts[1])
            memory_mb = float(parts[2]) / 1024.0
            virtual_memory_mb = float(parts[3]) / 1024.0
        except ValueError:
            continue

        total_cpu += cpu
        total_memory_mb += memory_mb
        total_virtual_memory_mb += virtual_memory_mb
        total_threads += _thread_count_for_pid(current_pid)
        counted += 1

    if counted == 0:
        return payload

    payload["cpu_percent"] = total_cpu
    payload["memory_mb"] = total_memory_mb
    payload["virtual_memory_mb"] = total_virtual_memory_mb
    payload["thread_count"] = total_threads
    return payload


def _thread_count_for_pid(pid: int) -> int:
    """
    Return thread count for a PID on macOS using ``ps -M``.
    """

    try:
        result = subprocess.run(  # noqa: S603
            ["ps", "-M", "-p", str(pid)],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return 0

    if result.returncode != 0:
        return 0

    lines = [line for line in result.stdout.splitlines() if line.strip()]
    if len(lines) <= 1:
        return 0
    return len(lines) - 1


def _build_launch_agent_plist(config_path: Path) -> dict:
    _ = config_path
    return {
        "Label": APP_ID,
        "ProgramArguments": [
            _python_executable(),
            str(_control_script()),
            "start",
        ],
        "EnvironmentVariables": _python_environment(),
        "WorkingDirectory": str(_control_script().parent),
        "RunAtLoad": True,
        "KeepAlive": False,
        "ProcessType": "Background",
        "StandardOutPath": str(LOG_PATH),
        "StandardErrorPath": str(LOG_PATH),
    }


def enable_autostart(config_path: Path = CONFIG_PATH) -> None:
    """Write/update the LaunchAgent plist for the next user login."""

    ensure_app_support_dir()
    AGENT_PLIST_PATH.parent.mkdir(parents=True, exist_ok=True)

    plist = _build_launch_agent_plist(config_path)
    plist_path_tmp = AGENT_PLIST_PATH.with_suffix(".plist.tmp")
    with plist_path_tmp.open("wb") as handle:
        plistlib.dump(plist, handle)
    plist_path_tmp.replace(AGENT_PLIST_PATH)

    domain_target = _launchctl_domain_target()
    service_target = _launchctl_service_target()
    plist_path = str(AGENT_PLIST_PATH)
    _launchctl(["bootout", domain_target, plist_path], ignore_errors=True)
    loaded = _launchctl(["bootstrap", domain_target, plist_path], ignore_errors=True)
    if not loaded:
        loaded = _launchctl(["load", "-w", plist_path], ignore_errors=True)
    if loaded:
        _launchctl(["enable", service_target], ignore_errors=True)
        _launchctl(["kickstart", "-k", service_target], ignore_errors=True)


def disable_autostart() -> None:
    """Remove the LaunchAgent plist and unload."""

    domain_target = _launchctl_domain_target()
    service_target = _launchctl_service_target()
    _launchctl(["bootout", service_target], ignore_errors=True)
    _launchctl(["bootout", domain_target, str(AGENT_PLIST_PATH)], ignore_errors=True)
    if AGENT_PLIST_PATH.exists():
        _launchctl(["unload", str(AGENT_PLIST_PATH)], ignore_errors=True)
        AGENT_PLIST_PATH.unlink(missing_ok=True)


def autostart_enabled() -> bool:
    """Return True if the LaunchAgent plist currently exists."""

    return AGENT_PLIST_PATH.exists()
