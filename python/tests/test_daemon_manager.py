import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import daemon_manager  # noqa: E402


class DaemonManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.pid_path = Path(self.temp_dir.name) / "daemon.pid"
        self.log_path = Path(self.temp_dir.name) / "daemon.log"
        self.health_path = Path(self.temp_dir.name) / "daemon.health.json"
        self.config_path = Path(self.temp_dir.name) / "config.json"
        self.no_freeze_path = Path(self.temp_dir.name) / "daemon.no-freeze"
        self.config_path.write_text("{}", encoding="utf-8")
        patcher_pid = mock.patch.object(daemon_manager, "PID_PATH", self.pid_path)
        patcher_log = mock.patch.object(daemon_manager, "LOG_PATH", self.log_path)
        patcher_health = mock.patch.object(daemon_manager, "DAEMON_HEALTH_PATH", self.health_path)
        patcher_config = mock.patch.object(daemon_manager, "CONFIG_PATH", self.config_path)
        patcher_no_freeze = mock.patch.object(daemon_manager, "DAEMON_NO_FREEZE_PATH", self.no_freeze_path)
        self.lock_path = Path(self.temp_dir.name) / "daemon.lock"
        patcher_lock = mock.patch.object(daemon_manager, "DAEMON_LOCK_PATH", self.lock_path)
        self.addCleanup(patcher_pid.stop)
        self.addCleanup(patcher_log.stop)
        self.addCleanup(patcher_health.stop)
        self.addCleanup(patcher_config.stop)
        self.addCleanup(patcher_no_freeze.stop)
        self.addCleanup(patcher_lock.stop)
        patcher_pid.start()
        patcher_log.start()
        patcher_health.start()
        patcher_config.start()
        patcher_no_freeze.start()
        patcher_lock.start()
        patcher_support = mock.patch.object(daemon_manager, "ensure_app_support_dir")
        self.addCleanup(patcher_support.stop)
        patcher_support.start()

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_start_daemon_launches_process_and_waits_for_pid(self):
        def fake_launch(*_args, **_kwargs):
            self.pid_path.write_text("123", encoding="utf-8")
            return 123

        with mock.patch.object(daemon_manager, "daemon_running", side_effect=[False]):
            with mock.patch.object(daemon_manager, "_launch_daemon", side_effect=fake_launch):
                with mock.patch.object(daemon_manager, "_resolve_primary_daemon_pid", return_value=123):
                    with mock.patch.object(daemon_manager, "_cleanup_orphaned_daemons"):
                        pid = daemon_manager.start_daemon(config_path=self.config_path)

        self.assertEqual(pid, 123)
        self.assertTrue(self.pid_path.exists())

    def test_start_daemon_resumes_paused_instance_without_restart(self):
        with mock.patch.object(daemon_manager, "_cleanup_orphaned_daemons"):
            with mock.patch.object(daemon_manager, "daemon_running", return_value=True):
                with mock.patch.object(daemon_manager, "read_pid", return_value=777):
                    with mock.patch.object(daemon_manager, "daemon_paused", return_value=True):
                        with mock.patch.object(daemon_manager, "resume_daemon", return_value=True) as resume:
                            with mock.patch.object(daemon_manager, "restart_daemon") as restart:
                                pid = daemon_manager.start_daemon(config_path=self.config_path)

        self.assertEqual(pid, 777)
        resume.assert_called_once()
        restart.assert_not_called()

    def test_stop_daemon_sends_signal_and_removes_pid(self):
        self.pid_path.write_text("321", encoding="utf-8")

        with mock.patch("os.kill") as kill:
            kill.side_effect = [None, OSError()]
            daemon_manager.stop_daemon()

        kill.assert_called()
        self.assertFalse(self.pid_path.exists())

    def test_stop_daemon_without_preserving_frame_sets_and_clears_flag(self):
        self.pid_path.write_text("321", encoding="utf-8")

        with mock.patch("os.kill") as kill:
            kill.side_effect = [None, OSError()]
            daemon_manager.stop_daemon(preserve_frame=False)

        kill.assert_called()
        self.assertFalse(self.no_freeze_path.exists())

    def test_start_daemon_reconfiguring_video_stops_without_preserving_old_frame(self):
        with mock.patch.object(daemon_manager, "_cleanup_orphaned_daemons"):
            with mock.patch.object(daemon_manager, "daemon_running", return_value=True):
                with mock.patch.object(daemon_manager, "read_pid", return_value=777):
                    with mock.patch.object(daemon_manager, "stop_daemon") as stop:
                        with mock.patch.object(daemon_manager, "_launch_daemon", return_value=778):
                            with mock.patch.object(daemon_manager, "_resolve_primary_daemon_pid", return_value=778):
                                daemon_manager.start_daemon(
                                    config_path=self.config_path,
                                    video_path="/tmp/new-video.mp4",
                                )

        stop.assert_called_once_with(timeout=1.5, preserve_frame=False)

    def test_restart_daemon_reconfiguring_video_stops_without_preserving_old_frame(self):
        with mock.patch.object(daemon_manager, "stop_daemon") as stop:
            with mock.patch.object(daemon_manager, "start_daemon", return_value=778) as start:
                pid = daemon_manager.restart_daemon(
                    config_path=self.config_path,
                    video_path="/tmp/new-video.mp4",
                )

        self.assertEqual(pid, 778)
        stop.assert_called_once_with(timeout=1.5, preserve_frame=False)
        start.assert_called_once_with(
            config_path=self.config_path,
            video_path="/tmp/new-video.mp4",
            playback_speed=None,
            volume=None,
            blend_interpolation=None,
            pause_on_fullscreen=None,
            scale_mode=None,
            wait=0.5,
        )

    def test_enable_autostart_writes_launch_agent(self):
        agent_dir = Path(self.temp_dir.name) / "LaunchAgents"
        agent_dir.mkdir()
        agent_path = agent_dir / "com.example.videowallpaper.plist"
        with mock.patch.object(daemon_manager, "AGENT_PLIST_PATH", agent_path):
            with mock.patch.object(daemon_manager, "_launchctl", return_value=True):
                daemon_manager.enable_autostart(config_path=self.config_path)

        self.assertTrue(agent_path.exists())
        payload = agent_path.read_bytes()
        self.assertIn(b"control.py", payload)
        self.assertIn(b"<string>start</string>", payload)

    def test_python_environment_prefers_bundled_framework_runtime(self):
        executable = (
            "/Applications/AuraFlow.app/Contents/Frameworks/"
            "Python3.framework/Versions/3.9/bin/python3"
        )
        bundled_ffmpeg = "/Applications/AuraFlow.app/Contents/Resources/bin/ffmpeg"
        bundled_ffprobe = "/Applications/AuraFlow.app/Contents/Resources/bin/ffprobe"

        with mock.patch.dict(os.environ, {}, clear=True):
            with mock.patch.object(daemon_manager, "_python_executable", return_value=executable):
                with mock.patch.object(
                    daemon_manager,
                    "_bundled_binary_executable",
                    side_effect=lambda name, origin=None: bundled_ffmpeg if name == "ffmpeg" else bundled_ffprobe,
                ):
                    env = daemon_manager._python_environment()

        self.assertEqual(env["PYTHON_EXECUTABLE"], executable)
        self.assertEqual(
            env["PYTHONHOME"],
            "/Applications/AuraFlow.app/Contents/Frameworks/Python3.framework/Versions/3.9",
        )
        self.assertEqual(env["PYTHONNOUSERSITE"], "1")
        self.assertEqual(env["PYTHONDONTWRITEBYTECODE"], "1")
        self.assertEqual(env["AURAFLOW_FFMPEG_PATH"], bundled_ffmpeg)
        self.assertEqual(env["AURAFLOW_FFPROBE_PATH"], bundled_ffprobe)
        self.assertTrue(env["PATH"].startswith("/Applications/AuraFlow.app/Contents/Resources/bin"))

    def test_python_home_falls_back_to_existing_env_for_non_framework_runtime(self):
        with mock.patch.dict(os.environ, {"PYTHONHOME": "/tmp/custom-python-home"}, clear=True):
            home = daemon_manager._python_home("/usr/local/bin/python3")

        self.assertEqual(home, "/tmp/custom-python-home")

    def test_enable_autostart_loads_agent_into_current_session(self):
        agent_dir = Path(self.temp_dir.name) / "LaunchAgents"
        agent_dir.mkdir()
        agent_path = agent_dir / "com.example.videowallpaper.plist"

        with mock.patch.object(daemon_manager, "AGENT_PLIST_PATH", agent_path):
            with mock.patch.object(daemon_manager, "_launchctl", return_value=True) as launchctl:
                daemon_manager.enable_autostart(config_path=self.config_path)

        launchctl.assert_any_call(
            ["bootstrap", f"gui/{os.getuid()}", str(agent_path)],
            ignore_errors=True,
        )
        launchctl.assert_any_call(
            ["kickstart", "-k", f"gui/{os.getuid()}/{daemon_manager.APP_ID}"],
            ignore_errors=True,
        )

    def test_disable_autostart_unloads_and_removes_agent(self):
        agent_dir = Path(self.temp_dir.name) / "LaunchAgents"
        agent_dir.mkdir()
        agent_path = agent_dir / "com.example.videowallpaper.plist"
        agent_path.write_text("plist", encoding="utf-8")

        with mock.patch.object(daemon_manager, "AGENT_PLIST_PATH", agent_path):
            with mock.patch.object(daemon_manager, "_launchctl", return_value=True) as launchctl:
                daemon_manager.disable_autostart()

        self.assertFalse(agent_path.exists())
        launchctl.assert_any_call(
            ["bootout", f"gui/{os.getuid()}/{daemon_manager.APP_ID}"],
            ignore_errors=True,
        )

    def test_daemon_health_marks_missing_heartbeat_as_suspicious(self):
        with mock.patch.object(daemon_manager, "daemon_running", return_value=True):
            health = daemon_manager.daemon_health(alive=True, paused=False)

        self.assertTrue(health["suspicious"])
        self.assertEqual(health["reason"], "missing_heartbeat")

    def test_daemon_health_marks_stale_snapshot_as_suspicious(self):
        self.health_path.write_text(
            '{"updated_at": 1, "suspicious": false, "screens": 1, "windows": 1}',
            encoding="utf-8",
        )
        with mock.patch("time.time", return_value=1000.0):
            health = daemon_manager.daemon_health(alive=True, paused=False)

        self.assertTrue(health["suspicious"])
        self.assertIn("stale_heartbeat", health["reason"])

    def test_daemon_resource_metrics_parses_ps_output(self):
        fake_ps = mock.Mock(returncode=0, stdout="456 12.5 20480 81920\n457 3.0 10240 40960\n")
        with mock.patch.object(daemon_manager, "_list_daemon_pids", return_value={456, 457}):
            with mock.patch.object(daemon_manager, "_resolve_primary_daemon_pid", return_value=456):
                with mock.patch.object(daemon_manager, "daemon_paused", return_value=False):
                    with mock.patch.object(daemon_manager, "daemon_health", return_value={"suspicious": False}):
                        with mock.patch.object(
                            daemon_manager,
                            "_thread_count_for_pid",
                            side_effect=[9, 2],
                        ):
                            with mock.patch("subprocess.run", return_value=fake_ps):
                                metrics = daemon_manager.daemon_resource_metrics()

        self.assertTrue(metrics["running"])
        self.assertEqual(metrics["pid"], 456)
        self.assertEqual(metrics["process_count"], 2)
        self.assertAlmostEqual(metrics["cpu_percent"], 15.5)
        self.assertAlmostEqual(metrics["memory_mb"], 30.0)
        self.assertAlmostEqual(metrics["virtual_memory_mb"], 120.0)
        self.assertEqual(metrics["thread_count"], 11)

    def test_daemon_running_recovers_from_stale_pid_file(self):
        self.pid_path.write_text("123", encoding="utf-8")

        with mock.patch.object(daemon_manager, "_list_daemon_pids", return_value={777}):
            running = daemon_manager.daemon_running()

        self.assertTrue(running)
        self.assertEqual(self.pid_path.read_text(encoding="utf-8"), "777")

    def test_list_daemon_pids_includes_lock_pid_when_alive(self):
        self.lock_path.write_text("888", encoding="utf-8")

        with mock.patch.object(daemon_manager, "_pgrep_pids", return_value=set()):
            with mock.patch.object(daemon_manager, "_pid_is_alive", return_value=True):
                pids = daemon_manager._list_daemon_pids()

        self.assertEqual(pids, {888})


if __name__ == "__main__":
    unittest.main()
