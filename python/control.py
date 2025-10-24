#!/usr/bin/env python3
"""
Command-line interface for controlling the video wallpaper daemon.

Provides commands for starting/stopping playback, adjusting settings, toggling
autostart and keeping configuration in sync with the Swift UI frontend.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, Optional

from daemon_manager import (
    autostart_enabled,
    disable_autostart,
    enable_autostart,
    restart_daemon,
    start_daemon,
    stop_daemon,
    daemon_running,
)
from paths import CONFIG_PATH, ensure_app_support_dir
from wallpaper_utils import set_wallpaper_from_video, validate_video


DEFAULT_CONFIG: Dict[str, Any] = {
    "video_path": "",
    "playback_speed": 1.0,
    "volume": 0.0,
    "autostart": False,
}


def load_config(path: Path = CONFIG_PATH) -> Dict[str, Any]:
    if not path.exists():
        ensure_app_support_dir()
        save_config(DEFAULT_CONFIG, path)
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    return {**DEFAULT_CONFIG, **data}


def save_config(config: Dict[str, Any], path: Path = CONFIG_PATH) -> None:
    ensure_app_support_dir()
    with path.open("w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2)


def update_config(updates: Dict[str, Any], path: Path = CONFIG_PATH) -> Dict[str, Any]:
    config = load_config(path)
    config.update(updates)
    save_config(config, path)
    return config


def build_status(config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    if config is None:
        config = load_config()
    return {
        "running": daemon_running(),
        "config": config,
        "pid": load_pid(),
        "autostart": autostart_enabled(),
    }


def command_start(args):
    config = load_config()
    if args.video:
        video_path = str(validate_video(args.video))
        config = update_config({"video_path": video_path}, CONFIG_PATH)
        set_wallpaper_from_video(Path(video_path))
    if args.speed is not None:
        config = update_config({"playback_speed": args.speed}, CONFIG_PATH)
    if not config["video_path"]:
        raise SystemExit("No video configured. Use 'set-video' first or pass --video.")

    start_daemon(
        video_path=config["video_path"],
        playback_speed=config["playback_speed"],
        volume=config.get("volume", 0.0),
        wait=0.35,
    )
    print(json.dumps(build_status(config)))


def command_stop(_args):
    stop_daemon()
    print(json.dumps(build_status()))


def command_status(_args):
    print(json.dumps(build_status()))


def command_set_video(args):
    video_path = str(validate_video(args.video))
    config = update_config({"video_path": video_path}, CONFIG_PATH)
    temp_path = set_wallpaper_from_video(Path(video_path))
    if daemon_running():
        restart_daemon(
            video_path=video_path,
            playback_speed=config["playback_speed"],
            volume=config.get("volume", 0.0),
            wait=0.35,
        )
    payload = build_status(config)
    payload["wallpaper"] = str(temp_path)
    print(json.dumps(payload))


def command_set_speed(args):
    config = update_config({"playback_speed": args.speed}, CONFIG_PATH)
    if daemon_running():
        restart_daemon(
            playback_speed=config["playback_speed"],
            volume=config.get("volume", 0.0),
            wait=0.35,
        )
    print(json.dumps(build_status(config)))


def command_autostart(args):
    config = load_config()
    if args.state == "on":
        enable_autostart()
        config = update_config({"autostart": True}, CONFIG_PATH)
    else:
        disable_autostart()
        config = update_config({"autostart": False}, CONFIG_PATH)
    print(json.dumps(build_status(config)))


def load_pid():
    try:
        from paths import PID_PATH

        if not PID_PATH.exists():
            return None
        return int(PID_PATH.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None


def build_parser():
    parser = argparse.ArgumentParser(description="Control the video wallpaper daemon.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    start_parser = subparsers.add_parser("start", help="Start the daemon.")
    start_parser.add_argument("--video", help="Optionally override video path.")
    start_parser.add_argument("--speed", type=float, help="Playback speed to apply.")
    start_parser.set_defaults(func=command_start)

    stop_parser = subparsers.add_parser("stop", help="Stop the daemon.")
    stop_parser.set_defaults(func=command_stop)

    status_parser = subparsers.add_parser("status", help="Report daemon status.")
    status_parser.set_defaults(func=command_status)

    video_parser = subparsers.add_parser("set-video", help="Change video and wallpaper.")
    video_parser.add_argument("video", help="Path to the new video file.")
    video_parser.set_defaults(func=command_set_video)

    speed_parser = subparsers.add_parser("set-speed", help="Adjust playback speed.")
    speed_parser.add_argument("speed", type=float, help="New playback speed.")
    speed_parser.set_defaults(func=command_set_speed)

    auto_parser = subparsers.add_parser("set-autostart", help="Toggle autostart.")
    auto_parser.add_argument(
        "state",
        choices=["on", "off"],
        help="Enable (on) or disable (off) LaunchAgent autostart.",
    )
    auto_parser.set_defaults(func=command_autostart)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
    except Exception as exc:
        raise SystemExit(str(exc)) from exc


if __name__ == "__main__":
    main(sys.argv[1:])
