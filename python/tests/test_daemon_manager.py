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
        self.config_path = Path(self.temp_dir.name) / "config.json"
        self.config_path.write_text("{}", encoding="utf-8")
        patcher_pid = mock.patch.object(daemon_manager, "PID_PATH", self.pid_path)
        patcher_log = mock.patch.object(daemon_manager, "LOG_PATH", self.log_path)
        patcher_config = mock.patch.object(daemon_manager, "CONFIG_PATH", self.config_path)
        self.addCleanup(patcher_pid.stop)
        self.addCleanup(patcher_log.stop)
        self.addCleanup(patcher_config.stop)
        patcher_pid.start()
        patcher_log.start()
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
            with mock.patch("subprocess.run") as run:
                run.side_effect = [
                    mock.Mock(returncode=0, stderr="", stdout=""),
                    mock.Mock(returncode=0, stderr="", stdout=""),
                ]
                daemon_manager.enable_autostart(config_path=self.config_path)

        self.assertTrue(agent_path.exists())
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[0].args[0][0:2], ["launchctl", "unload"])
        self.assertEqual(run.call_args_list[1].args[0][0:2], ["launchctl", "load"])


if __name__ == "__main__":
    unittest.main()
