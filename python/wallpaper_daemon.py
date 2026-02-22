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
from Foundation import NSObject, NSURL, NSNotificationCenter
from PyObjCTools import AppHelper

import AppKit
import AVFoundation
import CoreMedia
import Quartz

from paths import (
    CONFIG_PATH,
    DAEMON_COMMAND_PATH,
    DAEMON_PAUSED_PATH,
    ensure_app_support_dir,
    PID_PATH,
)


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
        self._layer_views = []
        self._player_layers = []
        self._is_paused = False

        self._player = AVFoundation.AVPlayer.alloc().init()
        self._apply_config(config)
        return self

    def _apply_config(self, config: DaemonConfig):
        """Create player items and windows for the provided config."""

        self._is_paused = False
        url = config.video_url
        asset = AVFoundation.AVURLAsset.URLAssetWithURL_options_(
            url,
            {AVFoundation.AVURLAssetPreferPreciseDurationAndTimingKey: True},
        )
        player_item = AVFoundation.AVPlayerItem.playerItemWithAsset_(asset)
        try:
            player_item.setPreferredForwardBufferDuration_(2.0)
        except Exception:
            pass

        NSNotificationCenter.defaultCenter().removeObserver_(self)
        self._player.replaceCurrentItemWithPlayerItem_(player_item)
        NSNotificationCenter.defaultCenter().addObserver_selector_name_object_(
            self,
            "playerItemDidReachEnd:",
            AVFoundation.AVPlayerItemDidPlayToEndTimeNotification,
            player_item,
        )

        self._player.setActionAtItemEnd_(AVFoundation.AVPlayerActionAtItemEndNone)
        self._player.setAutomaticallyWaitsToMinimizeStalling_(False)
        self._player.setVolume_(max(0.0, min(config.volume, 1.0)))

        self._teardown_windows()
        self._setup_windows()

        self._player.play()
        self._player.setRate_(max(0.1, config.playback_speed))

    def playerItemDidReachEnd_(self, _notification):
        """Loop playback manually for reliability across variable video formats."""

        if self._player is None or self._is_paused:
            return
        try:
            self._player.seekToTime_toleranceBefore_toleranceAfter_(
                CoreMedia.kCMTimeZero,
                CoreMedia.kCMTimeZero,
                CoreMedia.kCMTimeZero,
            )
        except Exception:
            pass
        self._player.play()
        self._player.setRate_(max(0.1, self._config.playback_speed))

    def ensurePlaybackIsActive(self):
        """Recover from transient AVPlayer stalls without changing UI state."""

        if self._player is None or self._is_paused:
            return

        try:
            rate = float(self._player.rate())
        except Exception:
            rate = 0.0

        if rate > 0.01:
            return

        current_item = self._player.currentItem()
        if current_item is None:
            self._apply_config(self._config)
            return

        self._player.play()
        self._player.setRate_(max(0.1, self._config.playback_speed))

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
            window.setBackgroundColor_(AppKit.NSColor.clearColor())
            window.setLevel_(desktop_level)
            window.setOpaque_(False)
            window.setHasShadow_(False)
            window.setCollectionBehavior_(behavior_flags)
            window.setIgnoresMouseEvents_(True)

            layer_view = AppKit.NSView.alloc().initWithFrame_(frame)
            layer_view.setWantsLayer_(True)
            layer_view.setAutoresizingMask_(
                AppKit.NSViewWidthSizable | AppKit.NSViewHeightSizable
            )
            layer_view.layer().setBackgroundColor_(AppKit.NSColor.clearColor().CGColor())

            player_layer = AVFoundation.AVPlayerLayer.playerLayerWithPlayer_(self._player)
            player_layer.setVideoGravity_(AVFoundation.AVLayerVideoGravityResizeAspectFill)
            player_layer.setFrame_(layer_view.bounds())
            player_layer.setNeedsDisplayOnBoundsChange_(True)
            player_layer.setAutoresizingMask_(
                Quartz.kCALayerWidthSizable | Quartz.kCALayerHeightSizable
            )
            layer_view.layer().addSublayer_(player_layer)

            window.setContentView_(layer_view)
            window.orderBack_(None)
            window.orderFrontRegardless()

            self._windows.append(window)
            self._layer_views.append(layer_view)
            self._player_layers.append(player_layer)

    def _teardown_windows(self):
        """Destroy existing wallpaper windows."""

        for window in self._windows:
            window.orderOut_(None)

        self._windows.clear()
        self._layer_views.clear()
        self._player_layers.clear()

    def stop(self):
        """Stop playback and close windows."""

        if self._player is None:
            return

        NSNotificationCenter.defaultCenter().removeObserver_(self)
        self._player.pause()
        self._player.replaceCurrentItemWithPlayerItem_(None)
        self._teardown_windows()
        self._player = None

    def pause(self):
        """Pause playback on the currently rendered frame."""

        if self._player is None:
            return
        self._is_paused = True
        self._player.pause()

    def resume(self):
        """Resume playback after pause."""

        if self._player is None:
            return
        self._is_paused = False
        self._player.play()
        self._player.setRate_(max(0.1, self._config.playback_speed))


class WallpaperAppDelegate(NSObject):
    """NSApplication delegate that wires the wallpaper controller."""

    controller = objc.ivar()
    commandTimer = objc.ivar()
    playbackTimer = objc.ivar()

    def initWithConfig_(self, config: DaemonConfig):
        self = objc.super(WallpaperAppDelegate, self).init()
        if self is None:
            return None
        self._config = config
        return self

    def applicationDidFinishLaunching_(self, _notification):
        self.controller = AuraFlowController.alloc().initWithConfig_(self._config)
        DAEMON_PAUSED_PATH.unlink(missing_ok=True)
        DAEMON_COMMAND_PATH.unlink(missing_ok=True)
        self.commandTimer = AppKit.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            0.25,
            self,
            "pollCommand:",
            None,
            True,
        )
        self.playbackTimer = AppKit.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            1.0,
            self,
            "pollPlayback:",
            None,
            True,
        )
        write_pid_file()

    def applicationShouldTerminate_(self, _sender):
        if self.commandTimer is not None:
            self.commandTimer.invalidate()
            self.commandTimer = None
        if self.playbackTimer is not None:
            self.playbackTimer.invalidate()
            self.playbackTimer = None
        if self.controller is not None:
            self.controller.stop()
        DAEMON_PAUSED_PATH.unlink(missing_ok=True)
        DAEMON_COMMAND_PATH.unlink(missing_ok=True)
        remove_pid_file()
        return AppKit.NSTerminateNow

    def applicationWillTerminate_(self, _notification):
        if self.commandTimer is not None:
            self.commandTimer.invalidate()
            self.commandTimer = None
        if self.playbackTimer is not None:
            self.playbackTimer.invalidate()
            self.playbackTimer = None
        if self.controller is not None:
            self.controller.stop()
        DAEMON_PAUSED_PATH.unlink(missing_ok=True)
        DAEMON_COMMAND_PATH.unlink(missing_ok=True)
        remove_pid_file()

    def pausePlayback(self):
        if self.controller is not None:
            self.controller.pause()

    def resumePlayback(self):
        if self.controller is not None:
            self.controller.resume()

    def pollCommand_(self, _timer):
        if not DAEMON_COMMAND_PATH.exists():
            return
        try:
            command = DAEMON_COMMAND_PATH.read_text(encoding="utf-8").strip().lower()
        except OSError:
            return
        DAEMON_COMMAND_PATH.unlink(missing_ok=True)

        if command == "pause":
            self.pausePlayback()
            DAEMON_PAUSED_PATH.write_text("1", encoding="utf-8")
        elif command == "resume":
            self.resumePlayback()
            DAEMON_PAUSED_PATH.unlink(missing_ok=True)

    def pollPlayback_(self, _timer):
        if self.controller is not None:
            self.controller.ensurePlaybackIsActive()


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
