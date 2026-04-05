import json
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import control  # noqa: E402


class ControlCLITests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.config_path = Path(self.temp_dir.name) / "config.json"
        self.addCleanup(self.temp_dir.cleanup)
        patcher_config = mock.patch.object(control, "CONFIG_PATH", self.config_path)
        patcher_config.start()
        self.addCleanup(patcher_config.stop)
        patcher_load = mock.patch.object(control, "load_config", return_value=control.DEFAULT_CONFIG.copy())
        patcher_save = mock.patch.object(control, "save_config")
        patcher_pid = mock.patch.object(control, "load_pid", return_value=123)
        self.addCleanup(patcher_load.stop)
        self.addCleanup(patcher_save.stop)
        self.addCleanup(patcher_pid.stop)
        patcher_load.start()
        patcher_save.start()
        patcher_pid.start()

    def test_command_start_validates_video_and_starts_daemon(self):
        args = Namespace(video="/tmp/video.mp4", speed=1.25)
        with mock.patch.object(control, "validate_video", return_value=Path("/tmp/video.mp4")) as validate:
            with mock.patch.object(control, "update_config", return_value={"video_path": "/tmp/video.mp4", "playback_speed": 1.25}):
                with mock.patch.object(control, "daemon_running", return_value=False):
                    with mock.patch.object(control, "refresh_wallpaper_backup") as refresh_backup:
                        with mock.patch.object(control, "set_wallpaper_from_video") as set_wallpaper:
                            with mock.patch.object(control, "start_daemon") as start_daemon:
                                with mock.patch.object(control, "build_status", return_value={"running": True, "config": {}, "pid": 1, "autostart": False}):
                                    with mock.patch("builtins.print") as printer:
                                        control.command_start(args)

        validate.assert_called_once()
        refresh_backup.assert_called_once()
        set_wallpaper.assert_called_once_with(Path("/tmp/video.mp4"))
        start_daemon.assert_called_once()
        printer.assert_called()

    def test_command_start_skips_backup_refresh_while_daemon_running(self):
        args = Namespace(video="/tmp/video.mp4", speed=1.25)
        with mock.patch.object(control, "validate_video", return_value=Path("/tmp/video.mp4")):
            with mock.patch.object(control, "update_config", return_value={"video_path": "/tmp/video.mp4", "playback_speed": 1.25}):
                with mock.patch.object(control, "daemon_running", return_value=True):
                    with mock.patch.object(control, "refresh_wallpaper_backup") as refresh_backup:
                        with mock.patch.object(control, "set_wallpaper_from_video") as set_wallpaper:
                            with mock.patch.object(control, "start_daemon") as start_daemon:
                                with mock.patch.object(control, "build_status", return_value={"running": True, "config": {}, "pid": 1, "autostart": False}):
                                    with mock.patch("builtins.print"):
                                        control.command_start(args)

        refresh_backup.assert_not_called()
        set_wallpaper.assert_called_once_with(Path("/tmp/video.mp4"))
        start_daemon.assert_called_once()

    def test_command_start_resume_without_video_override_does_not_refresh_managed_frame(self):
        args = Namespace(video=None, speed=None)
        config = {
            "video_path": "/tmp/video.mp4",
            "playback_speed": 1.0,
            "volume": 0.0,
            "blend_interpolation": False,
            "pause_on_fullscreen": True,
            "scale_mode": "fill",
        }
        with mock.patch.object(control, "load_config", return_value=config):
            with mock.patch.object(control, "daemon_running", return_value=True):
                with mock.patch.object(control, "refresh_wallpaper_backup") as refresh_backup:
                    with mock.patch.object(control, "set_wallpaper_from_video") as set_wallpaper:
                        with mock.patch.object(control, "start_daemon") as start_daemon:
                            with mock.patch.object(
                                control,
                                "build_status",
                                return_value={"running": True, "config": config, "pid": 1, "autostart": False},
                            ):
                                with mock.patch("builtins.print"):
                                    control.command_start(args)

        refresh_backup.assert_not_called()
        set_wallpaper.assert_not_called()
        start_daemon.assert_called_once_with(wait=0.35)

    def test_command_start_without_overrides_uses_resume_path(self):
        args = Namespace(video=None, speed=None)
        config = {
            "video_path": "/tmp/video.mp4",
            "playback_speed": 1.0,
            "volume": 0.0,
            "blend_interpolation": True,
            "pause_on_fullscreen": True,
            "scale_mode": "fill",
        }
        with mock.patch.object(control, "load_config", return_value=config):
            with mock.patch.object(control, "daemon_running", return_value=False):
                with mock.patch.object(control, "refresh_wallpaper_backup") as refresh_backup:
                    with mock.patch.object(control, "start_daemon") as start_daemon:
                        with mock.patch.object(
                            control,
                            "build_status",
                            return_value={"running": True, "config": config, "pid": 1, "autostart": False},
                        ):
                            with mock.patch.object(control, "set_wallpaper_from_video") as set_wallpaper:
                                with mock.patch("builtins.print") as printer:
                                    control.command_start(args)

        refresh_backup.assert_called_once()
        set_wallpaper.assert_called_once_with(Path("/tmp/video.mp4"))
        start_daemon.assert_called_once_with(wait=0.35)
        printer.assert_called_once()

    def test_command_stop_invokes_manager(self):
        args = Namespace()
        with mock.patch.object(control, "pause_daemon") as pause:
            with mock.patch.object(control, "build_status", return_value={"running": False, "config": {}, "pid": None, "autostart": False, "paused": True}):
                with mock.patch("builtins.print") as printer:
                    control.command_stop(args)
        pause.assert_called_once()
        printer.assert_called_once()

    def test_command_set_video_restarts_daemon(self):
        args = Namespace(video="/tmp/new.mp4")
        config = {
            "video_path": "/tmp/new.mp4",
            "playback_speed": 1.25,
            "volume": 0.0,
            "autostart": False,
            "blend_interpolation": True,
            "pause_on_fullscreen": False,
            "scale_mode": "fit",
        }
        with mock.patch.object(control, "validate_video", return_value=Path("/tmp/new.mp4")):
            with mock.patch.object(control, "update_config", return_value=config):
                with mock.patch.object(control, "set_wallpaper_from_video", return_value=Path("/tmp/thumb.png")):
                    with mock.patch.object(control, "daemon_running", return_value=True):
                        with mock.patch.object(control, "restart_daemon") as restart:
                            with mock.patch.object(control, "build_status", return_value={"running": True, "config": config, "pid": 1, "autostart": False, "wallpaper": ""}):
                                with mock.patch("builtins.print") as printer:
                                    control.command_set_video(args)

        restart.assert_called_once_with(
            video_path="/tmp/new.mp4",
            playback_speed=1.25,
            volume=0.0,
            blend_interpolation=True,
            pause_on_fullscreen=False,
            scale_mode="fit",
            wait=0.35,
        )
        printer.assert_called()

    def test_command_start_with_video_override_preserves_current_settings(self):
        args = Namespace(video="/tmp/new.mp4", speed=None)
        config = {
            "video_path": "/tmp/new.mp4",
            "playback_speed": 1.1,
            "volume": 0.0,
            "autostart": False,
            "blend_interpolation": True,
            "pause_on_fullscreen": False,
            "scale_mode": "stretch",
        }
        with mock.patch.object(control, "load_config", return_value=control.DEFAULT_CONFIG.copy()):
            with mock.patch.object(control, "validate_video", return_value=Path("/tmp/new.mp4")):
                with mock.patch.object(control, "update_config", return_value=config):
                    with mock.patch.object(control, "daemon_running", return_value=False):
                        with mock.patch.object(control, "refresh_wallpaper_backup") as refresh_backup:
                            with mock.patch.object(control, "set_wallpaper_from_video") as set_wallpaper:
                                with mock.patch.object(control, "start_daemon") as start_daemon:
                                    with mock.patch.object(control, "build_status", return_value={"running": True, "config": config, "pid": 1, "autostart": False}):
                                        with mock.patch("builtins.print"):
                                            control.command_start(args)

        refresh_backup.assert_called_once()
        set_wallpaper.assert_called_once_with(Path("/tmp/new.mp4"))
        start_daemon.assert_called_once_with(
            video_path="/tmp/new.mp4",
            playback_speed=1.1,
            volume=0.0,
            blend_interpolation=True,
            pause_on_fullscreen=False,
            scale_mode="stretch",
            wait=0.35,
        )

    def test_command_autostart_toggle(self):
        args = Namespace(state="on")
        with mock.patch.object(control, "load_config", return_value={"autostart": False, "video_path": "/tmp/video.mp4"}):
            with mock.patch.object(control, "validate_video", return_value=Path("/tmp/video.mp4")) as validate:
                with mock.patch.object(control, "daemon_running", return_value=False):
                    with mock.patch.object(control, "set_wallpaper_from_video") as set_wallpaper:
                        with mock.patch.object(control, "update_config", return_value={"autostart": True}):
                            with mock.patch.object(control, "enable_autostart") as enable:
                                with mock.patch.object(control, "build_status", return_value={"running": False, "config": {}, "pid": None, "autostart": True}):
                                    with mock.patch("builtins.print") as printer:
                                        control.command_autostart(args)
        validate.assert_called_once()
        set_wallpaper.assert_called_once_with(Path("/tmp/video.mp4"))
        enable.assert_called_once()
        printer.assert_called_once()

    def test_command_autostart_does_not_touch_wallpaper_when_running(self):
        args = Namespace(state="on")
        with mock.patch.object(control, "load_config", return_value={"autostart": False, "video_path": "/tmp/video.mp4"}):
            with mock.patch.object(control, "validate_video", return_value=Path("/tmp/video.mp4")) as validate:
                with mock.patch.object(control, "daemon_running", return_value=True):
                    with mock.patch.object(control, "set_wallpaper_from_video") as set_wallpaper:
                        with mock.patch.object(control, "update_config", return_value={"autostart": True}):
                            with mock.patch.object(control, "enable_autostart") as enable:
                                with mock.patch.object(control, "build_status", return_value={"running": True, "config": {}, "pid": 1, "autostart": True}):
                                    with mock.patch("builtins.print"):
                                        control.command_autostart(args)
        validate.assert_called_once()
        set_wallpaper.assert_not_called()
        enable.assert_called_once()

    def test_command_autostart_requires_video(self):
        args = Namespace(state="on")
        with mock.patch.object(control, "load_config", return_value={"autostart": False, "video_path": ""}):
            with self.assertRaises(SystemExit):
                control.command_autostart(args)

    def test_command_clear_wallpaper_restores_previous(self):
        args = Namespace()
        call_order: list[str] = []
        with mock.patch.object(
            control,
            "stop_daemon",
            side_effect=lambda timeout=1.5, preserve_frame=True: call_order.append("stop"),
        ) as stop:
            with mock.patch.object(
                control,
                "restore_wallpaper_backup",
                side_effect=lambda **_kwargs: (call_order.append("restore"), True)[1],
            ) as restore:
                with mock.patch.object(control, "build_status", return_value={"running": False, "config": {}, "pid": None, "autostart": False}):
                    with mock.patch("builtins.print") as printer:
                        control.command_clear_wallpaper(args)
        self.assertEqual(call_order[:2], ["stop", "restore"])
        stop.assert_called_once_with(timeout=0.6, preserve_frame=False)
        restore.assert_called_once_with(delete_backup=False, allow_fallback=False)
        printer.assert_called_once()

    def test_command_set_interpolation_restarts_running_daemon(self):
        args = Namespace(state="on")
        config = {
            "video_path": "/tmp/video.mp4",
            "playback_speed": 1.0,
            "volume": 0.0,
            "autostart": False,
            "blend_interpolation": True,
            "pause_on_fullscreen": True,
            "scale_mode": "fill",
        }
        with mock.patch.object(control, "update_config", return_value=config):
            with mock.patch.object(control, "daemon_running", return_value=True):
                with mock.patch.object(control, "restart_daemon") as restart:
                    with mock.patch.object(control, "build_status", return_value={"running": True, "config": config, "pid": 1, "autostart": False}):
                        with mock.patch("builtins.print") as printer:
                            control.command_set_interpolation(args)

        restart.assert_called_once()
        printer.assert_called_once()

    def test_command_set_fullscreen_pause_restarts_running_daemon(self):
        args = Namespace(state="off")
        config = {
            "video_path": "/tmp/video.mp4",
            "playback_speed": 1.0,
            "volume": 0.0,
            "autostart": False,
            "blend_interpolation": False,
            "pause_on_fullscreen": False,
            "scale_mode": "fill",
        }
        with mock.patch.object(control, "update_config", return_value=config):
            with mock.patch.object(control, "daemon_running", return_value=True):
                with mock.patch.object(control, "restart_daemon") as restart:
                    with mock.patch.object(control, "build_status", return_value={"running": True, "config": config, "pid": 1, "autostart": False}):
                        with mock.patch("builtins.print") as printer:
                            control.command_set_fullscreen_pause(args)

        restart.assert_called_once()
        printer.assert_called_once()

    def test_command_set_scale_restarts_running_daemon(self):
        args = Namespace(mode="fit")
        config = {
            "video_path": "/tmp/video.mp4",
            "playback_speed": 1.0,
            "volume": 0.0,
            "autostart": False,
            "blend_interpolation": False,
            "pause_on_fullscreen": True,
            "scale_mode": "fit",
        }
        with mock.patch.object(control, "update_config", return_value=config):
            with mock.patch.object(control, "daemon_running", return_value=True):
                with mock.patch.object(control, "restart_daemon") as restart:
                    with mock.patch.object(control, "build_status", return_value={"running": True, "config": config, "pid": 1, "autostart": False}):
                        with mock.patch("builtins.print") as printer:
                            control.command_set_scale(args)

        restart.assert_called_once()
        printer.assert_called_once()

    def test_command_metrics_prints_payload(self):
        args = Namespace()
        payload = {"running": True, "cpu_percent": 3.2}
        with mock.patch.object(control, "daemon_resource_metrics", return_value=payload):
            with mock.patch("builtins.print") as printer:
                control.command_metrics(args)

        printer.assert_called_once()

    def test_command_terminate_daemon_stops_process(self):
        args = Namespace()
        with mock.patch.object(control, "stop_daemon") as stop:
            with mock.patch.object(control, "build_status", return_value={"running": False, "config": {}, "pid": None, "autostart": False}):
                with mock.patch("builtins.print") as printer:
                    control.command_terminate_daemon(args)

        stop.assert_called_once()
        printer.assert_called_once()


if __name__ == "__main__":
    unittest.main()
