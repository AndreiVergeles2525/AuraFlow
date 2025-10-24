#!/usr/bin/env python3
"""
AuraFlow Player for macOS
-------------------------

Launches a borderless, click-through window at desktop level that loops a given
video across all active displays. Requires macOS with PyObjC bindings installed.
"""

import argparse
import os
import signal
import sys

import objc
from Foundation import NSObject, NSURL
from PyObjCTools import AppHelper

import AppKit
import AVFoundation
import AVKit
import Quartz


class AuraFlowController(NSObject):
    """Configures desktop-level windows that play a looping video."""

    def initWithURL_volume_(self, url, volume):
        self = objc.super(AuraFlowController, self).init()
        if self is None:
            return None

        self._url = url
        self._windows = []
        self._player_views = []

        self._player = AVFoundation.AVQueuePlayer.queuePlayerWithItems_([])
        template_item = AVFoundation.AVPlayerItem.playerItemWithURL_(url)
        self._looper = AVFoundation.AVPlayerLooper.playerLooperWithPlayer_templateItem_(
            self._player, template_item
        )
        self._player.setActionAtItemEnd_(AVFoundation.AVPlayerActionAtItemEndNone)
        self._player.setVolume_(volume)
        self._setup_windows()
        self._player.play()
        return self

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

    def stop(self):
        """Stop playback and close windows."""
        if self._player is None:
            return
        self._player.pause()
        self._looper = None
        for window in self._windows:
            window.orderOut_(None)
        self._windows.clear()
        self._player_views.clear()
        self._player = None


class WallpaperAppDelegate(NSObject):
    """NSApplication delegate that wires the wallpaper controller."""

    controller = objc.ivar()

    def initWithURL_volume_(self, url, volume):
        self = objc.super(WallpaperAppDelegate, self).init()
        if self is None:
            return None
        self._url = url
        self._volume = volume
        return self

    def applicationDidFinishLaunching_(self, _notification):
        self.controller = AuraFlowController.alloc().initWithURL_volume_(
            self._url, self._volume
        )

    def applicationShouldTerminate_(self, _sender):
        if self.controller is not None:
            self.controller.stop()
        return AppKit.NSTerminateNow

    def applicationWillTerminate_(self, _notification):
        if self.controller is not None:
            self.controller.stop()


def validate_video(path):
    if not os.path.exists(path):
        raise FileNotFoundError(f"Video file not found: {path}")
    if not os.path.isfile(path):
        raise ValueError(f"Expected a file, got: {path}")
    return os.path.abspath(path)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Play a looping video as your macOS desktop wallpaper.",
    )
    parser.add_argument(
        "video",
        help="Path to a video file (e.g., .mp4, .mov)",
    )
    parser.add_argument(
        "--volume",
        type=float,
        default=0.0,
        help="Output volume (0.0 - 1.0). Defaults to muted.",
    )

    args = parser.parse_args(argv)
    video_path = validate_video(args.video)

    url = NSURL.fileURLWithPath_(video_path)
    app = AppKit.NSApplication.sharedApplication()
    app.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)

    delegate = WallpaperAppDelegate.alloc().initWithURL_volume_(
        url, max(0.0, min(args.volume, 1.0))
    )
    app.setDelegate_(delegate)

    def handle_termination(signum, _frame):
        AppKit.NSApp().terminate_(None)

    signal.signal(signal.SIGINT, handle_termination)
    signal.signal(signal.SIGTERM, handle_termination)

    AppHelper.runEventLoop()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - surface friendly error
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(1)
