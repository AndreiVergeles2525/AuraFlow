#!/usr/bin/env python3
"""
Wallpaper daemon that projects a looping video onto the macOS desktop.

Intended to be launched in the background by the SwiftUI control app or via the
command-line manager. Reads configuration from a JSON file and keeps a minimal
PID file for coordination.
"""

from __future__ import annotations

import argparse
import json
import signal
import sys
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import objc
from Foundation import NSObject, NSURL
from PyObjCTools import AppHelper

import AppKit
import AVFoundation
import AVKit
import Quartz

from paths import CONFIG_PATH, ensure_app_support_dir, PID_PATH


@dataclass
class DaemonConfig:
    """Serialisable configuration for the wallpaper daemon."""

    video_path: str
    playback_speed: float = 1.0
    volume: float = 0.0

    @property
    def video_url(self):
        return NSURL.fileURLWithPath_(self.video_path)


def load_config(path: Path) -> DaemonConfig:
    """Load daemon configuration from disk."""

    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if "video_path" not in data:
        raise ValueError("Configuration missing 'video_path'")

    return DaemonConfig(
        video_path=data["video_path"],
        playback_speed=float(data.get("playback_speed", 1.0)),
        volume=float(data.get("volume", 0.0)),
    )


class AuraFlowController(NSObject):
    """Configures desktop-level windows that play a looping video."""

    def initWithConfig_(self, config: DaemonConfig):
        self = objc.super(AuraFlowController, self).init()
        if self is None:
            return None

        self._config = config
        self._windows = []
        self._player_views = []

        self._player = AVFoundation.AVQueuePlayer.queuePlayerWithItems_([])
        self._looper = None
        self._apply_config(config)
        return self

    def _apply_config(self, config: DaemonConfig):
        """Create player items and windows for the provided config."""

        url = config.video_url
        template_item = AVFoundation.AVPlayerItem.playerItemWithURL_(url)
        self._player.removeAllItems()
        self._looper = AVFoundation.AVPlayerLooper.playerLooperWithPlayer_templateItem_(
            self._player, template_item
        )

        self._player.setActionAtItemEnd_(AVFoundation.AVPlayerActionAtItemEndNone)
        self._player.setVolume_(max(0.0, min(config.volume, 1.0)))

        self._teardown_windows()
        self._setup_windows()

        self._player.play()
        self._player.setRate_(max(0.1, config.playback_speed))

    def updateWithConfig_(self, config: DaemonConfig):
        """Replace playback content and parameters."""

        self._config = config
        self._apply_config(config)

    def _setup_windows(self):
        """Create one wallpaper window per screen."""

        desktop_level = Quartz.CGWindowLevelForKey(Quartz.kCGDesktopWindowLevelKey)
        behavior_flags = (
            AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces
            | AppKit.NSWindowCollectionBehaviorStationary
            | AppKit.NSWindowCollectionBehaviorIgnoresCycle
        )

        for screen in AppKit.NSScreen.screens():
            frame = screen.frame()
            window = (
                AppKit.NSWindow.alloc()
                .initWithContentRect_styleMask_backing_defer_(
                    frame,
                    AppKit.NSWindowStyleMaskBorderless,
                    AppKit.NSBackingStoreBuffered,
                    False,
                )
            )
            window.setReleasedWhenClosed_(False)
            window.setBackgroundColor_(AppKit.NSColor.blackColor())
            window.setLevel_(desktop_level)
            window.setOpaque_(True)
            window.setHasShadow_(False)
            window.setCollectionBehavior_(behavior_flags)
            window.setIgnoresMouseEvents_(True)

            player_view = AVKit.AVPlayerView.alloc().initWithFrame_(frame)
            player_view.setPlayer_(self._player)
            player_view.setControlsStyle_(AVKit.AVPlayerViewControlsStyleNone)
            player_view.setVideoGravity_(AVFoundation.AVLayerVideoGravityResizeAspectFill)
            player_view.setAutoresizingMask_(
                AppKit.NSViewWidthSizable | AppKit.NSViewHeightSizable
            )

            window.setContentView_(player_view)
            window.orderBack_(None)
            window.orderFrontRegardless()

            self._windows.append(window)
            self._player_views.append(player_view)

    def _teardown_windows(self):
        """Destroy existing wallpaper windows."""

        for window in self._windows:
            window.orderOut_(None)

        self._windows.clear()
        self._player_views.clear()

    def stop(self):
        """Stop playback and close windows."""

        if self._player is None:
            return

        self._player.pause()
        self._looper = None
        self._teardown_windows()
        self._player = None


class WallpaperAppDelegate(NSObject):
    """NSApplication delegate that wires the wallpaper controller."""

    controller = objc.ivar()

    def initWithConfig_(self, config: DaemonConfig):
        self = objc.super(WallpaperAppDelegate, self).init()
        if self is None:
            return None
        self._config = config
        return self

    def applicationDidFinishLaunching_(self, _notification):
        self.controller = AuraFlowController.alloc().initWithConfig_(self._config)
        write_pid_file()

    def applicationShouldTerminate_(self, _sender):
        if self.controller is not None:
            self.controller.stop()
        remove_pid_file()
        return AppKit.NSTerminateNow

    def applicationWillTerminate_(self, _notification):
        if self.controller is not None:
            self.controller.stop()
        remove_pid_file()


def write_pid_file():
    """Persist current process identifier for coordination."""

    ensure_app_support_dir()
    PID_PATH.write_text(str(os.getpid()), encoding="utf-8")


def remove_pid_file():
    """Remove the persisted PID, if present."""

    if PID_PATH.exists():
        PID_PATH.unlink()


def run_daemon(config: DaemonConfig):
    """Instantiate NSApplication and enter the run loop."""

    app = AppKit.NSApplication.sharedApplication()
    app.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)

    delegate = WallpaperAppDelegate.alloc().initWithConfig_(config)
    app.setDelegate_(delegate)

    def handle_shutdown(signum, _frame):
        # Terminate the application gracefully.
        AppKit.NSApp().terminate_(None)

    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)

    AppHelper.runEventLoop()


def parse_args(argv: Optional[list[str]] = None):
    parser = argparse.ArgumentParser(description="Video wallpaper daemon")
    parser.add_argument(
        "--config",
        type=Path,
        default=CONFIG_PATH,
        help=f"Path to JSON config (default: {CONFIG_PATH})",
    )
    parser.add_argument(
        "--video",
        help="Override video path (otherwise read from config)",
    )
    parser.add_argument(
        "--speed",
        type=float,
        help="Override playback speed (otherwise read from config)",
    )
    parser.add_argument(
        "--volume",
        type=float,
        help="Override playback volume (otherwise read from config)",
    )
    parser.add_argument(
        "--write-pid",
        action="store_true",
        help="Write PID file when starting (default behaviour).",
    )
    parser.add_argument(
        "command",
        choices=["run"],
        help="Only 'run' is supported; daemon stays in foreground.",
    )
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None):
    args = parse_args(argv)

    config_path: Path = args.config
    if args.video or not config_path.exists():
        ensure_app_support_dir()
        source = {
            "video_path": args.video,
            "playback_speed": args.speed or 1.0,
            "volume": args.volume or 0.0,
        }
        config_path.write_text(json.dumps(source, indent=2), encoding="utf-8")

    config = load_config(config_path)

    if args.video:
        config.video_path = args.video
    if args.speed is not None:
        config.playback_speed = args.speed
    if args.volume is not None:
        config.volume = args.volume

    run_daemon(config)


if __name__ == "__main__":
    try:
        import os  # noqa: WPS433  # used inside write_pid_file

        main()
    except Exception as exc:  # pragma: no cover - surface friendly error
        print(f"[daemon:error] {exc}", file=sys.stderr)
        sys.exit(1)
