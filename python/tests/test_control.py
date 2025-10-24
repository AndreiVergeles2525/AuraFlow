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
                with mock.patch.object(control, "set_wallpaper_from_video") as set_wallpaper:
                    with mock.patch.object(control, "start_daemon") as start_daemon:
                        with mock.patch.object(control, "build_status", return_value={"running": True, "config": {}, "pid": 1, "autostart": False}):
                            with mock.patch("builtins.print") as printer:
                                control.command_start(args)

        validate.assert_called_once()
        set_wallpaper.assert_called_once()
        start_daemon.assert_called_once()
        printer.assert_called()

    def test_command_stop_invokes_manager(self):
        args = Namespace()
        with mock.patch.object(control, "stop_daemon") as stop:
            with mock.patch("builtins.print") as printer:
                control.command_stop(args)
        stop.assert_called_once()
        printer.assert_called_once()

    def test_command_set_video_restarts_daemon(self):
        args = Namespace(video="/tmp/new.mp4")
        with mock.patch.object(control, "validate_video", return_value=Path("/tmp/new.mp4")):
            with mock.patch.object(control, "update_config", return_value={"video_path": "/tmp/new.mp4", "playback_speed": 1.0}):
                with mock.patch.object(control, "set_wallpaper_from_video", return_value=Path("/tmp/thumb.png")):
                    with mock.patch.object(control, "daemon_running", return_value=True):
                        with mock.patch.object(control, "restart_daemon") as restart:
                            with mock.patch.object(control, "build_status", return_value={"running": True, "config": {}, "pid": 1, "autostart": False, "wallpaper": ""}):
                                with mock.patch("builtins.print") as printer:
                                    control.command_set_video(args)

        restart.assert_called_once()
        printer.assert_called()

    def test_command_autostart_toggle(self):
        args = Namespace(state="on")
        with mock.patch.object(control, "load_config", return_value={"autostart": False}):
            with mock.patch.object(control, "update_config", return_value={"autostart": True}):
                with mock.patch.object(control, "enable_autostart") as enable:
                    with mock.patch.object(control, "build_status", return_value={"running": False, "config": {}, "pid": None, "autostart": True}):
                        with mock.patch("builtins.print") as printer:
                            control.command_autostart(args)
        enable.assert_called_once()
        printer.assert_called_once()


if __name__ == "__main__":
    unittest.main()
