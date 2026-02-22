#!/usr/bin/env python3
"""
Wallpaper daemon that projects a looping video onto the macOS desktop.

Intended to be launched in the background by the SwiftUI control app or via the
command-line manager. Reads configuration from a JSON file and keeps a minimal
PID file for coordination.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import signal
import sys
import os
import time
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import objc
from Foundation import NSObject, NSURL, NSNotificationCenter, NSProcessInfo
from PyObjCTools import AppHelper

import AppKit
import AVFoundation
import CoreMedia
import Quartz

from paths import (
    CONFIG_PATH,
    DAEMON_COMMAND_PATH,
    DAEMON_HEALTH_PATH,
    DAEMON_LOCK_PATH,
    DAEMON_PAUSED_PATH,
    ensure_app_support_dir,
    PID_PATH,
)

SCALE_MODE_TO_GRAVITY = {
    "fill": AVFoundation.AVLayerVideoGravityResizeAspectFill,
    "fit": AVFoundation.AVLayerVideoGravityResizeAspect,
    "stretch": AVFoundation.AVLayerVideoGravityResize,
}
DEFAULT_SCALE_MODE = "fill"
_DAEMON_LOCK_HANDLE = None


@dataclass
class DaemonConfig:
    """Serialisable configuration for the wallpaper daemon."""

    video_path: str
    playback_speed: float = 1.0
    volume: float = 0.0
    blend_interpolation: bool = False
    pause_on_fullscreen: bool = True
    scale_mode: str = DEFAULT_SCALE_MODE

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
        blend_interpolation=_as_bool(data.get("blend_interpolation", False)),
        pause_on_fullscreen=_as_bool(data.get("pause_on_fullscreen", True)),
        scale_mode=_normalize_scale_mode(data.get("scale_mode", DEFAULT_SCALE_MODE)),
    )


def _as_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"1", "true", "yes", "on"}:
            return True
        if lowered in {"0", "false", "no", "off"}:
            return False
    return bool(value)


def _normalize_scale_mode(value) -> str:
    if not isinstance(value, str):
        return DEFAULT_SCALE_MODE
    mode = value.strip().lower()
    if mode in SCALE_MODE_TO_GRAVITY:
        return mode
    return DEFAULT_SCALE_MODE


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
        self._manual_paused = False
        self._auto_paused_for_low_power = False
        self._auto_paused_for_fullscreen = False
        self._fullscreen_app_detected = False
        self._blend_interpolation_enabled = False
        self._blend_interpolation_active = False
        self._blend_filter_error = ""
        self._blend_previous_image = None
        self._blend_lock = threading.Lock()
        self._blend_strength = 0.72
        self._blend_target_fps = 18.0
        self._blend_min_interval_seconds = 1.0 / self._blend_target_fps
        self._blend_last_composition_time = -1.0
        self._blend_last_monotonic = 0.0
        self._stall_events = 0
        self._recovery_events = 0
        self._consecutive_stall_polls = 0
        self._last_recovery_reason = ""
        self._last_recovery_at = 0.0

        self._player = AVFoundation.AVPlayer.alloc().init()
        self._apply_config(config)
        return self

    def _apply_config(self, config: DaemonConfig):
        """Create player items and windows for the provided config."""

        self._is_paused = False
        self._manual_paused = False
        self._auto_paused_for_low_power = False
        self._auto_paused_for_fullscreen = False
        self._fullscreen_app_detected = False
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
        self._configure_blend_interpolation(player_item, asset, config.blend_interpolation)

        self._teardown_windows()
        self._setup_windows()

        self._player.play()
        self._player.setRate_(max(0.1, config.playback_speed))

    def _configure_blend_interpolation(
        self,
        player_item,
        asset,
        enabled: bool,
    ):
        self._blend_interpolation_enabled = bool(enabled)
        self._blend_interpolation_active = False
        self._blend_filter_error = ""
        self._blend_previous_image = None
        self._blend_last_composition_time = -1.0
        self._blend_last_monotonic = 0.0

        try:
            player_item.setVideoComposition_(None)
        except Exception:
            pass

        if not enabled:
            return

        composition_factory = getattr(
            AVFoundation.AVVideoComposition,
            "videoCompositionWithAsset_applyingCIFiltersWithHandler_",
            None,
        )
        if composition_factory is None:
            self._blend_filter_error = "blend_api_unavailable"
            return

        def _request_time_seconds(request) -> float | None:
            composition_time_getter = getattr(request, "compositionTime", None)
            if composition_time_getter is None:
                return None
            try:
                cm_time = composition_time_getter()
                seconds = float(CoreMedia.CMTimeGetSeconds(cm_time))
            except Exception:
                return None
            if seconds != seconds or seconds < 0:
                return None
            return seconds

        def _should_blend(current_seconds: float | None) -> bool:
            if current_seconds is not None:
                if self._blend_last_composition_time >= 0:
                    if (current_seconds - self._blend_last_composition_time) < self._blend_min_interval_seconds:
                        return False
                self._blend_last_composition_time = current_seconds
                return True

            now = time.monotonic()
            if self._blend_last_monotonic > 0:
                if (now - self._blend_last_monotonic) < self._blend_min_interval_seconds:
                    return False
            self._blend_last_monotonic = now
            return True

        def _blend_handler(request):
            source_image = request.sourceImage()
            output_image = source_image
            try:
                with self._blend_lock:
                    current_seconds = _request_time_seconds(request)
                    previous_image = self._blend_previous_image
                    if previous_image is not None and _should_blend(current_seconds):
                        blended = self._blend_images(
                            current_image=source_image,
                            previous_image=previous_image,
                        )
                        if blended is not None:
                            output_image = blended
                    self._blend_previous_image = source_image
            except Exception:
                output_image = source_image
            finish = getattr(request, "finishWithImage_context_", None)
            if finish is None:
                finish = getattr(request, "finishWithComposedVideoFrame_", None)
            if finish is None:
                return
            try:
                if getattr(request, "finishWithImage_context_", None) is not None:
                    finish(output_image, None)
                else:
                    finish(output_image)
            except Exception:
                try:
                    if getattr(request, "finishWithImage_context_", None) is not None:
                        finish(source_image, None)
                    else:
                        finish(source_image)
                except Exception:
                    pass

        try:
            video_composition = composition_factory(asset, _blend_handler)
            player_item.setVideoComposition_(video_composition)
            self._blend_interpolation_active = True
        except Exception:
            self._blend_filter_error = "blend_setup_failed"
            try:
                player_item.setVideoComposition_(None)
            except Exception:
                pass

    def _blend_images(self, current_image, previous_image):
        try:
            previous_cropped = previous_image.imageByCroppingToRect_(current_image.extent())
        except Exception:
            previous_cropped = previous_image

        dissolve = None
        try:
            dissolve = Quartz.CIFilter.filterWithName_("CIDissolveTransition")
        except Exception:
            dissolve = None
        if dissolve is None:
            return None

        dissolve.setDefaults()
        dissolve.setValue_forKey_(previous_cropped, "inputImage")
        dissolve.setValue_forKey_(current_image, "inputTargetImage")
        dissolve.setValue_forKey_(self._blend_strength, "inputTime")
        return dissolve.valueForKey_("outputImage")

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
            self._consecutive_stall_polls = 0
            return

        try:
            rate = float(self._player.rate())
        except Exception:
            rate = 0.0

        current_item = self._player.currentItem()
        if current_item is None:
            self._stall_events += 1
            self._recovery_events += 1
            self._consecutive_stall_polls += 1
            self._last_recovery_reason = "missing_item"
            self._last_recovery_at = time.time()
            self._apply_config(self._config)
            return

        if rate > 0.01:
            self._consecutive_stall_polls = 0
            return

        self._stall_events += 1
        self._recovery_events += 1
        self._consecutive_stall_polls += 1
        self._last_recovery_reason = "zero_rate"
        self._last_recovery_at = time.time()
        self._player.play()
        self._player.setRate_(max(0.1, self._config.playback_speed))

    def healthSnapshot(self):
        """Expose daemon health details for CLI/Swift monitoring."""

        screen_count = len(AppKit.NSScreen.screens())
        window_count = len(self._windows)

        try:
            rate = float(self._player.rate()) if self._player is not None else 0.0
        except Exception:
            rate = 0.0

        has_item = bool(
            self._player is not None and self._player.currentItem() is not None
        )

        reasons = []
        if self._player is None:
            reasons.append("player_missing")
        if window_count != screen_count:
            reasons.append("window_count_mismatch")
        if not self._is_paused and not has_item:
            reasons.append("missing_item")
        if (
            not self._is_paused
            and has_item
            and rate <= 0.01
            and self._consecutive_stall_polls >= 3
        ):
            reasons.append("rate_stuck")
        if self._blend_interpolation_enabled and not self._blend_interpolation_active:
            reasons.append("blend_unavailable")
        if self._blend_filter_error:
            reasons.append(self._blend_filter_error)
        return {
            "contract_version": 2,
            "updated_at": time.time(),
            "paused": self._is_paused,
            "manual_paused": self._manual_paused,
            "low_power_mode": self._is_low_power_mode_enabled(),
            "auto_paused_for_low_power": self._auto_paused_for_low_power,
            "pause_on_fullscreen": self._config.pause_on_fullscreen,
            "scale_mode": self._config.scale_mode,
            "fullscreen_app_detected": self._fullscreen_app_detected,
            "auto_paused_for_fullscreen": self._auto_paused_for_fullscreen,
            "blend_interpolation_enabled": self._blend_interpolation_enabled,
            "blend_interpolation_active": self._blend_interpolation_active,
            "player_rate": rate,
            "has_item": has_item,
            "screens": screen_count,
            "windows": window_count,
            "stall_events": self._stall_events,
            "recovery_events": self._recovery_events,
            "consecutive_stall_polls": self._consecutive_stall_polls,
            "last_recovery_reason": self._last_recovery_reason,
            "last_recovery_at": self._last_recovery_at,
            "suspicious": bool(reasons),
            "reason": ",".join(reasons),
        }

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
            player_layer.setVideoGravity_(self._video_gravity())
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

    def _video_gravity(self):
        mode = _normalize_scale_mode(self._config.scale_mode)
        return SCALE_MODE_TO_GRAVITY.get(
            mode, AVFoundation.AVLayerVideoGravityResizeAspectFill
        )

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
        self._manual_paused = True
        self._auto_paused_for_low_power = False
        self._auto_paused_for_fullscreen = False
        self._is_paused = True
        self._player.pause()

    def resume(self):
        """Resume playback after pause."""

        if self._player is None:
            return
        self._manual_paused = False
        low_power_mode = self._is_low_power_mode_enabled()
        fullscreen_active = (
            self._config.pause_on_fullscreen and self._is_fullscreen_app_active()
        )
        if low_power_mode or fullscreen_active:
            self._is_paused = True
            self._auto_paused_for_low_power = low_power_mode
            self._auto_paused_for_fullscreen = fullscreen_active
            return
        self._is_paused = False
        self._auto_paused_for_low_power = False
        self._auto_paused_for_fullscreen = False
        self._player.play()
        self._player.setRate_(max(0.1, self._config.playback_speed))

    def enforcePlaybackPolicies(self):
        """
        Pause during Low Power Mode/fullscreen apps and auto-resume when safe.
        """

        if self._player is None:
            return

        low_power_mode = self._is_low_power_mode_enabled()
        fullscreen_active = (
            self._config.pause_on_fullscreen and self._is_fullscreen_app_active()
        )
        self._fullscreen_app_detected = fullscreen_active

        if self._manual_paused:
            self._auto_paused_for_low_power = False
            self._auto_paused_for_fullscreen = False
            return

        should_auto_pause = low_power_mode or fullscreen_active
        if should_auto_pause:
            self._auto_paused_for_low_power = low_power_mode
            self._auto_paused_for_fullscreen = fullscreen_active
            if not self._is_paused:
                self._is_paused = True
                self._player.pause()
            return

        if self._is_paused and (
            self._auto_paused_for_low_power or self._auto_paused_for_fullscreen
        ):
            self._is_paused = False
            self._auto_paused_for_low_power = False
            self._auto_paused_for_fullscreen = False
            self._player.play()
            self._player.setRate_(max(0.1, self._config.playback_speed))

    def _is_fullscreen_app_active(self) -> bool:
        """
        Detect fullscreen windows on any screen excluding AuraFlow daemon windows.
        """

        screen_frames = []
        for screen in AppKit.NSScreen.screens():
            frame = screen.frame()
            screen_frames.append(
                {
                    "x": float(frame.origin.x),
                    "y": float(frame.origin.y),
                    "w": max(float(frame.size.width), 1.0),
                    "h": max(float(frame.size.height), 1.0),
                }
            )
        if not screen_frames:
            return False

        options = (
            Quartz.kCGWindowListOptionOnScreenOnly
            | Quartz.kCGWindowListExcludeDesktopElements
        )
        try:
            window_info = Quartz.CGWindowListCopyWindowInfo(
                options,
                Quartz.kCGNullWindowID,
            )
        except Exception:
            return False
        if not window_info:
            return False

        daemon_pid = os.getpid()
        for info in window_info:
            try:
                owner_pid = int(info.get(Quartz.kCGWindowOwnerPID, -1))
            except (TypeError, ValueError):
                owner_pid = -1
            if owner_pid == daemon_pid:
                continue

            alpha = float(info.get(Quartz.kCGWindowAlpha, 1.0) or 0.0)
            if alpha <= 0.01:
                continue

            bounds = info.get(Quartz.kCGWindowBounds)
            if not isinstance(bounds, dict):
                continue

            wx = float(bounds.get("X", 0.0))
            wy = float(bounds.get("Y", 0.0))
            ww = max(float(bounds.get("Width", 0.0)), 0.0)
            wh = max(float(bounds.get("Height", 0.0)), 0.0)
            if ww < 320 or wh < 240:
                continue

            for screen in screen_frames:
                coverage = self._coverage_ratio(
                    screen,
                    {"x": wx, "y": wy, "w": ww, "h": wh},
                )
                if coverage >= 0.93:
                    return True
        return False

    def _coverage_ratio(self, screen: dict, window: dict) -> float:
        sx1 = screen["x"]
        sy1 = screen["y"]
        sx2 = sx1 + screen["w"]
        sy2 = sy1 + screen["h"]

        wx1 = window["x"]
        wy1 = window["y"]
        wx2 = wx1 + window["w"]
        wy2 = wy1 + window["h"]

        ix1 = max(sx1, wx1)
        iy1 = max(sy1, wy1)
        ix2 = min(sx2, wx2)
        iy2 = min(sy2, wy2)
        if ix2 <= ix1 or iy2 <= iy1:
            return 0.0
        intersection = (ix2 - ix1) * (iy2 - iy1)
        screen_area = screen["w"] * screen["h"]
        if screen_area <= 0:
            return 0.0
        return intersection / screen_area

    def _is_low_power_mode_enabled(self) -> bool:
        try:
            return bool(NSProcessInfo.processInfo().isLowPowerModeEnabled())
        except Exception:
            return False


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
        self._writeHealthSnapshot()

    def applicationShouldTerminate_(self, _sender):
        self._shutdown()
        return AppKit.NSTerminateNow

    def applicationWillTerminate_(self, _notification):
        self._shutdown()

    def _shutdown(self):
        if self.commandTimer is not None:
            self.commandTimer.invalidate()
            self.commandTimer = None
        if self.playbackTimer is not None:
            self.playbackTimer.invalidate()
            self.playbackTimer = None
        if self.controller is not None:
            self.controller.stop()
            self.controller = None
        DAEMON_PAUSED_PATH.unlink(missing_ok=True)
        DAEMON_COMMAND_PATH.unlink(missing_ok=True)
        remove_pid_file()
        remove_health_file()

    def _writeHealthSnapshot(self):
        if self.controller is None:
            return
        write_health_file(self.controller.healthSnapshot())

    def pausePlayback(self):
        if self.controller is not None:
            self.controller.pause()
            self._writeHealthSnapshot()

    def resumePlayback(self):
        if self.controller is not None:
            self.controller.resume()
            self._writeHealthSnapshot()

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
        self._writeHealthSnapshot()

    def pollPlayback_(self, _timer):
        if self.controller is not None:
            self.controller.enforcePlaybackPolicies()
            self.controller.ensurePlaybackIsActive()
            self._writeHealthSnapshot()


def write_pid_file():
    """Persist current process identifier for coordination."""

    ensure_app_support_dir()
    PID_PATH.write_text(str(os.getpid()), encoding="utf-8")


def remove_pid_file():
    """Remove the persisted PID, if present."""

    if PID_PATH.exists():
        PID_PATH.unlink()


def write_health_file(payload: dict):
    """Persist daemon heartbeat/health snapshot for external monitoring."""

    ensure_app_support_dir()
    serialized = json.dumps(payload, separators=(",", ":"), ensure_ascii=True)
    tmp_path = DAEMON_HEALTH_PATH.with_suffix(".json.tmp")
    tmp_path.write_text(serialized, encoding="utf-8")
    tmp_path.replace(DAEMON_HEALTH_PATH)


def remove_health_file():
    """Delete daemon health snapshot if present."""

    DAEMON_HEALTH_PATH.unlink(missing_ok=True)


def run_daemon(config: DaemonConfig):
    """Instantiate NSApplication and enter the run loop."""

    if not acquire_single_instance_lock():
        raise RuntimeError("AuraFlow daemon is already running.")

    app = AppKit.NSApplication.sharedApplication()
    app.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)

    delegate = WallpaperAppDelegate.alloc().initWithConfig_(config)
    app.setDelegate_(delegate)

    def handle_shutdown(signum, _frame):
        # Terminate the application gracefully.
        AppKit.NSApp().terminate_(None)

    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)

    try:
        AppHelper.runEventLoop()
    finally:
        release_single_instance_lock()


def acquire_single_instance_lock() -> bool:
    global _DAEMON_LOCK_HANDLE
    ensure_app_support_dir()
    handle = DAEMON_LOCK_PATH.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return False
    handle.seek(0)
    handle.truncate(0)
    handle.write(str(os.getpid()))
    handle.flush()
    _DAEMON_LOCK_HANDLE = handle
    return True


def release_single_instance_lock() -> None:
    global _DAEMON_LOCK_HANDLE
    if _DAEMON_LOCK_HANDLE is None:
        return
    try:
        fcntl.flock(_DAEMON_LOCK_HANDLE.fileno(), fcntl.LOCK_UN)
    except OSError:
        pass
    try:
        _DAEMON_LOCK_HANDLE.close()
    except OSError:
        pass
    _DAEMON_LOCK_HANDLE = None


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
        "--blend-interpolation",
        choices=["on", "off"],
        help="Enable or disable lightweight frame blending.",
    )
    parser.add_argument(
        "--pause-on-fullscreen",
        choices=["on", "off"],
        help="Enable or disable automatic pause when fullscreen apps are visible.",
    )
    parser.add_argument(
        "--scale-mode",
        choices=["fill", "fit", "stretch"],
        help="Wallpaper scale algorithm.",
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
    if (
        args.video
        or args.speed is not None
        or args.volume is not None
        or args.blend_interpolation is not None
        or args.pause_on_fullscreen is not None
        or args.scale_mode is not None
        or not config_path.exists()
    ):
        ensure_app_support_dir()
        source = {}
        if config_path.exists():
            try:
                existing = json.loads(config_path.read_text(encoding="utf-8"))
                if isinstance(existing, dict):
                    source.update(existing)
            except (OSError, json.JSONDecodeError):
                pass

        if args.video is not None:
            source["video_path"] = args.video
        source.setdefault("video_path", "")

        if args.speed is not None:
            source["playback_speed"] = args.speed
        source.setdefault("playback_speed", 1.0)

        if args.volume is not None:
            source["volume"] = args.volume
        source.setdefault("volume", 0.0)

        if args.blend_interpolation is not None:
            source["blend_interpolation"] = args.blend_interpolation == "on"
        source.setdefault("blend_interpolation", False)

        if args.pause_on_fullscreen is not None:
            source["pause_on_fullscreen"] = args.pause_on_fullscreen == "on"
        source.setdefault("pause_on_fullscreen", True)
        if args.scale_mode is not None:
            source["scale_mode"] = _normalize_scale_mode(args.scale_mode)
        source.setdefault("scale_mode", DEFAULT_SCALE_MODE)
        config_path.write_text(json.dumps(source, indent=2), encoding="utf-8")

    config = load_config(config_path)

    if args.video:
        config.video_path = args.video
    if args.speed is not None:
        config.playback_speed = args.speed
    if args.volume is not None:
        config.volume = args.volume
    if args.blend_interpolation is not None:
        config.blend_interpolation = args.blend_interpolation == "on"
    if args.pause_on_fullscreen is not None:
        config.pause_on_fullscreen = args.pause_on_fullscreen == "on"
    if args.scale_mode is not None:
        config.scale_mode = _normalize_scale_mode(args.scale_mode)

    run_daemon(config)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - surface friendly error
        print(f"[daemon:error] {exc}", file=sys.stderr)
        sys.exit(1)
