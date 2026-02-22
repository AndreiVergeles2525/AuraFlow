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
        self.config_path.write_text("{}", encoding="utf-8")
        patcher_pid = mock.patch.object(daemon_manager, "PID_PATH", self.pid_path)
        patcher_log = mock.patch.object(daemon_manager, "LOG_PATH", self.log_path)
        patcher_health = mock.patch.object(daemon_manager, "DAEMON_HEALTH_PATH", self.health_path)
        patcher_config = mock.patch.object(daemon_manager, "CONFIG_PATH", self.config_path)
        self.addCleanup(patcher_pid.stop)
        self.addCleanup(patcher_log.stop)
        self.addCleanup(patcher_health.stop)
        self.addCleanup(patcher_config.stop)
        patcher_pid.start()
        patcher_log.start()
        patcher_health.start()
        patcher_config.start()
        patcher_support = mock.patch.object(daemon_manager, "ensure_app_support_dir")
        self.addCleanup(patcher_support.stop)
        patcher_support.start()

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_start_daemon_launches_process_and_waits_for_pid(self):
        def fake_launch(*_args, **_kwargs):
            self.pid_path.write_text("123", encoding="utf-8")
            return 123

        with mock.patch.object(daemon_manager, "daemon_running", side_effect=[False, True]):
            with mock.patch.object(daemon_manager, "_launch_daemon", side_effect=fake_launch):
                pid = daemon_manager.start_daemon(config_path=self.config_path)

        self.assertEqual(pid, 123)
        self.assertTrue(self.pid_path.exists())

    def test_stop_daemon_sends_signal_and_removes_pid(self):
        self.pid_path.write_text("321", encoding="utf-8")

        with mock.patch("os.kill") as kill:
            kill.side_effect = [None, OSError()]
            daemon_manager.stop_daemon()

        kill.assert_called()
        self.assertFalse(self.pid_path.exists())

    def test_enable_autostart_writes_launch_agent(self):
        agent_dir = Path(self.temp_dir.name) / "LaunchAgents"
        agent_dir.mkdir()
        agent_path = agent_dir / "com.example.videowallpaper.plist"
        with mock.patch.object(daemon_manager, "AGENT_PLIST_PATH", agent_path):
            daemon_manager.enable_autostart(config_path=self.config_path)

        self.assertTrue(agent_path.exists())

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
        fake_ps = mock.Mock(returncode=0, stdout="456 12.5 20480\n457 3.0 10240\n")
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
        self.assertEqual(metrics["thread_count"], 11)

    def test_daemon_running_recovers_from_stale_pid_file(self):
        self.pid_path.write_text("123", encoding="utf-8")

        with mock.patch.object(daemon_manager, "_list_daemon_pids", return_value={777}):
            running = daemon_manager.daemon_running()

        self.assertTrue(running)
        self.assertEqual(self.pid_path.read_text(encoding="utf-8"), "777")


if __name__ == "__main__":
    unittest.main()
