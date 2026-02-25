import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import wallpaper_utils  # noqa: E402


class WallpaperUtilsTests(unittest.TestCase):
    def test_set_all_desktops_picture_via_system_events_verifies_result(self):
        with mock.patch.object(
            wallpaper_utils,
            "_run_osascript",
            side_effect=[
                SimpleNamespace(returncode=0, stdout=""),
                SimpleNamespace(returncode=0, stdout="ok\n"),
            ],
        ) as run_osascript:
            applied = wallpaper_utils._set_all_desktops_picture_via_system_events("/tmp/frame.png")

        self.assertTrue(applied)
        self.assertGreaterEqual(run_osascript.call_count, 2)

    def test_set_all_desktops_picture_via_system_events_retries_on_mismatch(self):
        with mock.patch.object(
            wallpaper_utils,
            "_run_osascript",
            side_effect=[
                SimpleNamespace(returncode=0, stdout=""),
                SimpleNamespace(returncode=0, stdout="mismatch\n"),
                SimpleNamespace(returncode=0, stdout=""),
                SimpleNamespace(returncode=0, stdout="ok\n"),
            ],
        ):
            applied = wallpaper_utils._set_all_desktops_picture_via_system_events("/tmp/frame.png")

        self.assertTrue(applied)

    def test_validate_video_checks_existence(self):
        with tempfile.NamedTemporaryFile() as handle:
            path = wallpaper_utils.validate_video(handle.name)
            self.assertTrue(path.exists())

        with self.assertRaises(FileNotFoundError):
            wallpaper_utils.validate_video("/path/does/not/exist.mp4")

    def test_set_wallpaper_from_video_flows_through_helpers(self):
        fake_image = mock.Mock()
        temp_path = Path("/tmp/fake.png")
        with mock.patch.object(wallpaper_utils, "extract_first_frame", return_value=fake_image) as extract:
            with mock.patch.object(wallpaper_utils, "save_image_to_temp", return_value=temp_path) as save_image:
                with mock.patch.object(wallpaper_utils, "set_wallpaper") as set_wallpaper:
                    result = wallpaper_utils.set_wallpaper_from_video(Path("/tmp/video.mp4"))

        extract.assert_called_once()
        save_image.assert_called_once_with(fake_image)
        set_wallpaper.assert_called_once_with(temp_path)
        self.assertEqual(result, temp_path)

    def test_set_wallpaper_from_video_uses_ffmpeg_fallback_when_extract_fails(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            last_frame = temp_root / "last-frame.png"
            last_frame.write_bytes(b"frame")

            with mock.patch.object(wallpaper_utils, "extract_first_frame", side_effect=RuntimeError("fail")):
                with mock.patch.object(wallpaper_utils, "LAST_FRAME_PATH", last_frame):
                    with mock.patch.object(
                        wallpaper_utils,
                        "_extract_first_frame_with_ffmpeg",
                        return_value=last_frame,
                    ) as extract_with_ffmpeg:
                        with mock.patch.object(wallpaper_utils, "set_wallpaper") as set_wallpaper:
                            result = wallpaper_utils.set_wallpaper_from_video(Path("/tmp/video.webm"))

        extract_with_ffmpeg.assert_called_once_with(Path("/tmp/video.webm"))
        set_wallpaper.assert_called_once_with(last_frame)
        self.assertEqual(result, last_frame)

    def test_set_wallpaper_from_video_falls_back_to_current_wallpaper_path(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            current_wallpaper = temp_root / "current-wallpaper.heic"
            current_wallpaper.write_bytes(b"wallpaper")

            with mock.patch.object(wallpaper_utils, "extract_first_frame", side_effect=RuntimeError("fail")):
                with mock.patch.object(wallpaper_utils, "_extract_first_frame_with_ffmpeg", return_value=None):
                    with mock.patch.object(wallpaper_utils, "LAST_FRAME_PATH", temp_root / "missing-last-frame.png"):
                        with mock.patch.object(
                            wallpaper_utils,
                            "_current_wallpapers",
                            return_value={"1": str(current_wallpaper)},
                        ):
                            result = wallpaper_utils.set_wallpaper_from_video(Path("/tmp/video.webm"))

        self.assertEqual(result, current_wallpaper)

    def test_set_wallpaper_from_video_does_not_reuse_stale_managed_frame(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            stale_frame = temp_root / "last-frame.png"
            stale_frame.write_bytes(b"frame")

            with mock.patch.object(wallpaper_utils, "extract_first_frame", side_effect=RuntimeError("fail")):
                with mock.patch.object(wallpaper_utils, "_extract_first_frame_with_ffmpeg", return_value=None):
                    with mock.patch.object(wallpaper_utils, "LAST_FRAME_PATH", stale_frame):
                        with mock.patch.object(
                            wallpaper_utils,
                            "_current_wallpapers",
                            return_value={"1": str(stale_frame)},
                        ):
                            with self.assertRaises(RuntimeError):
                                wallpaper_utils.set_wallpaper_from_video(Path("/tmp/video.webm"))

    def test_extract_first_frame_with_ffmpeg_writes_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            output = temp_root / "last_frame.png"
            temp_output = temp_root / "last_frame.tmp.png"
            video = temp_root / "video.webm"
            video.write_bytes(b"video")

            def fake_run(*_args, **_kwargs):
                temp_output.write_bytes(b"png")
                return SimpleNamespace(returncode=0, stdout="", stderr="")

            with mock.patch.object(wallpaper_utils, "_resolve_ffmpeg_executable", return_value="/usr/bin/ffmpeg"):
                with mock.patch.object(wallpaper_utils, "ensure_app_support_dir"):
                    with mock.patch.object(wallpaper_utils.subprocess, "run", side_effect=fake_run):
                        result = wallpaper_utils._extract_first_frame_with_ffmpeg(video, output)
            self.assertEqual(result, output)
            self.assertTrue(output.exists())

    def test_set_wallpaper_applies_to_all_desktops_via_system_events(self):
        image_path = Path("/tmp/frame.png")
        fake_screen = object()
        fake_workspace = mock.Mock()

        fake_appkit = mock.Mock()
        fake_appkit.NSWorkspace.sharedWorkspace.return_value = fake_workspace
        fake_appkit.NSScreen.screens.return_value = [fake_screen]

        fake_nsurl = mock.Mock()
        fake_nsurl.fileURLWithPath_.side_effect = lambda path: path

        with mock.patch.object(wallpaper_utils, "_require_macos_frameworks"):
            with mock.patch.object(wallpaper_utils, "_save_wallpaper_backup_if_needed"):
                with mock.patch.object(
                    wallpaper_utils,
                    "_set_all_desktops_picture_via_system_events",
                    return_value=True,
                ) as apply_every_desktop:
                    with mock.patch.object(wallpaper_utils, "AppKit", fake_appkit):
                        with mock.patch.object(wallpaper_utils, "NSURL", fake_nsurl):
                            wallpaper_utils.set_wallpaper(image_path)

        fake_workspace.setDesktopImageURL_forScreen_options_error_.assert_called_once_with(
            str(image_path),
            fake_screen,
            {},
            None,
        )
        apply_every_desktop.assert_called_once_with(
            str(image_path.expanduser().resolve(strict=False))
        )

    def test_save_wallpaper_backup_skips_auraflow_last_frame(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            backup_path = temp_root / "wallpaper_backup.json"
            original_backup_path = temp_root / "wallpaper_backup_original.json"
            last_frame_path = temp_root / "last_frame.png"
            last_frame_path.write_bytes(b"frame")

            with mock.patch.object(wallpaper_utils, "WALLPAPER_BACKUP_PATH", backup_path):
                with mock.patch.object(wallpaper_utils, "WALLPAPER_ORIGINAL_BACKUP_PATH", original_backup_path):
                    with mock.patch.object(wallpaper_utils, "LAST_FRAME_PATH", last_frame_path):
                        with mock.patch.object(wallpaper_utils, "ensure_app_support_dir"):
                            with mock.patch.object(
                                wallpaper_utils,
                                "_current_wallpapers",
                                return_value={"1": str(last_frame_path)},
                            ):
                                wallpaper_utils._save_wallpaper_backup_if_needed()

            self.assertFalse(backup_path.exists())

    def test_save_wallpaper_backup_refreshes_when_external_wallpaper_changes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            backup_path = temp_root / "wallpaper_backup.json"
            original_backup_path = temp_root / "wallpaper_backup_original.json"
            backup_path.write_text('{"1":"/tmp/old.heic"}', encoding="utf-8")

            with mock.patch.object(wallpaper_utils, "WALLPAPER_BACKUP_PATH", backup_path):
                with mock.patch.object(wallpaper_utils, "WALLPAPER_ORIGINAL_BACKUP_PATH", original_backup_path):
                    with mock.patch.object(wallpaper_utils, "ensure_app_support_dir"):
                        with mock.patch.object(
                            wallpaper_utils,
                            "_current_wallpapers",
                            return_value={"1": "/tmp/new.heic"},
                        ):
                            with mock.patch.object(
                                wallpaper_utils,
                                "_is_managed_wallpaper",
                                return_value=False,
                            ):
                                wallpaper_utils._save_wallpaper_backup_if_needed()

            self.assertEqual(
                backup_path.read_text(encoding="utf-8").strip(),
                '{\n  "1": "/tmp/new.heic"\n}',
            )
            self.assertEqual(
                original_backup_path.read_text(encoding="utf-8").strip(),
                '{\n  "1": "/tmp/new.heic"\n}',
            )

    def test_load_wallpaper_backup_ignores_managed_last_frame(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            backup_path = temp_root / "wallpaper_backup.json"
            last_frame_path = temp_root / "last_frame.png"
            last_frame_path.write_bytes(b"frame")
            backup_path.write_text(
                json.dumps({"1": str(last_frame_path), "2": "/tmp/external.heic"}),
                encoding="utf-8",
            )

            with mock.patch.object(wallpaper_utils, "WALLPAPER_BACKUP_PATH", backup_path):
                with mock.patch.object(wallpaper_utils, "LAST_FRAME_PATH", last_frame_path):
                    loaded = wallpaper_utils._load_wallpaper_backup()

            self.assertEqual(loaded, {"2": "/tmp/external.heic"})

    def test_restore_wallpaper_backup_falls_back_to_system_image(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            desktop_pictures = temp_root / "Desktop Pictures"
            desktop_pictures.mkdir(parents=True)
            fallback_image = desktop_pictures / "Default.heic"
            fallback_image.write_bytes(b"image")

            fake_screen = object()
            fake_workspace = mock.Mock()

            fake_appkit = mock.Mock()
            fake_appkit.NSWorkspace.sharedWorkspace.return_value = fake_workspace
            fake_appkit.NSScreen.screens.return_value = [fake_screen]

            fake_nsurl = mock.Mock()
            fake_nsurl.fileURLWithPath_.side_effect = lambda path: path

            with mock.patch.object(wallpaper_utils, "_require_macos_frameworks"):
                with mock.patch.object(wallpaper_utils, "_load_wallpaper_backup", return_value={}):
                    with mock.patch.object(wallpaper_utils, "_screen_identifier", return_value="1"):
                        with mock.patch.object(wallpaper_utils, "AppKit", fake_appkit):
                            with mock.patch.object(wallpaper_utils, "NSURL", fake_nsurl):
                                with mock.patch.object(
                                    wallpaper_utils,
                                    "_set_all_desktops_picture_via_system_events",
                                    return_value=True,
                                ):
                                    with mock.patch.object(
                                        wallpaper_utils,
                                        "_fallback_system_wallpaper",
                                        return_value={"1": str(fallback_image)},
                                    ):
                                        restored = wallpaper_utils.restore_wallpaper_backup(
                                            allow_fallback=True
                                        )

            self.assertTrue(restored)
            fake_workspace.setDesktopImageURL_forScreen_options_error_.assert_called_once()

    def test_restore_wallpaper_backup_skips_fallback_by_default(self):
        with mock.patch.object(wallpaper_utils, "_require_macos_frameworks"):
            with mock.patch.object(wallpaper_utils, "_load_wallpaper_backup", return_value={}):
                with mock.patch.object(
                    wallpaper_utils,
                    "_fallback_system_wallpaper",
                    return_value={"1": "/System/Library/Desktop Pictures/Default.heic"},
                ) as fallback:
                    restored = wallpaper_utils.restore_wallpaper_backup()

        self.assertFalse(restored)
        fallback.assert_not_called()

    def test_restore_wallpaper_backup_does_not_delete_backup_by_default(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            backup_path = temp_root / "wallpaper_backup.json"
            image_path = temp_root / "wallpaper.heic"
            image_path.write_bytes(b"image")
            backup_path.write_text("{}", encoding="utf-8")

            fake_screen = object()
            fake_workspace = mock.Mock()

            fake_appkit = mock.Mock()
            fake_appkit.NSWorkspace.sharedWorkspace.return_value = fake_workspace
            fake_appkit.NSScreen.screens.return_value = [fake_screen]

            fake_nsurl = mock.Mock()
            fake_nsurl.fileURLWithPath_.side_effect = lambda path: path

            with mock.patch.object(wallpaper_utils, "WALLPAPER_BACKUP_PATH", backup_path):
                with mock.patch.object(wallpaper_utils, "_require_macos_frameworks"):
                    with mock.patch.object(
                        wallpaper_utils,
                        "_load_wallpaper_backup",
                        return_value={"1": str(image_path)},
                    ):
                        with mock.patch.object(wallpaper_utils, "_screen_identifier", return_value="1"):
                            with mock.patch.object(wallpaper_utils, "AppKit", fake_appkit):
                                with mock.patch.object(wallpaper_utils, "NSURL", fake_nsurl):
                                    with mock.patch.object(
                                        wallpaper_utils,
                                        "_set_all_desktops_picture_via_system_events",
                                        return_value=True,
                                    ):
                                        restored = wallpaper_utils.restore_wallpaper_backup()

            self.assertTrue(restored)
            self.assertTrue(backup_path.exists())

    def test_restore_wallpaper_backup_skips_system_events_when_not_needed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            image_path = temp_root / "wallpaper.heic"
            image_path.write_bytes(b"image")

            fake_screen = object()
            fake_workspace = mock.Mock()

            fake_appkit = mock.Mock()
            fake_appkit.NSWorkspace.sharedWorkspace.return_value = fake_workspace
            fake_appkit.NSScreen.screens.return_value = [fake_screen]

            fake_nsurl = mock.Mock()
            fake_nsurl.fileURLWithPath_.side_effect = lambda path: path

            with mock.patch.object(wallpaper_utils, "_require_macos_frameworks"):
                with mock.patch.object(
                    wallpaper_utils,
                    "_load_wallpaper_backup",
                    return_value={"1": str(image_path)},
                ):
                    with mock.patch.object(wallpaper_utils, "_screen_identifier", return_value="1"):
                        with mock.patch.object(wallpaper_utils, "AppKit", fake_appkit):
                            with mock.patch.object(wallpaper_utils, "NSURL", fake_nsurl):
                                with mock.patch.object(
                                    wallpaper_utils,
                                    "_any_screen_uses_managed_wallpaper",
                                    return_value=False,
                                ):
                                    with mock.patch.object(
                                        wallpaper_utils,
                                        "_set_all_desktops_picture_via_system_events",
                                        return_value=True,
                                    ) as sync_spaces:
                                        restored = wallpaper_utils.restore_wallpaper_backup()

            self.assertTrue(restored)
            sync_spaces.assert_not_called()

    def test_restore_wallpaper_backup_waits_briefly_before_system_events(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            image_path = temp_root / "wallpaper.heic"
            image_path.write_bytes(b"image")

            fake_screen = object()
            fake_workspace = mock.Mock()

            fake_appkit = mock.Mock()
            fake_appkit.NSWorkspace.sharedWorkspace.return_value = fake_workspace
            fake_appkit.NSScreen.screens.return_value = [fake_screen]

            fake_nsurl = mock.Mock()
            fake_nsurl.fileURLWithPath_.side_effect = lambda path: path

            with mock.patch.object(wallpaper_utils, "_require_macos_frameworks"):
                with mock.patch.object(
                    wallpaper_utils,
                    "_load_wallpaper_backup",
                    return_value={"1": str(image_path)},
                ):
                    with mock.patch.object(wallpaper_utils, "_screen_identifier", return_value="1"):
                        with mock.patch.object(wallpaper_utils, "AppKit", fake_appkit):
                            with mock.patch.object(wallpaper_utils, "NSURL", fake_nsurl):
                                with mock.patch.object(
                                    wallpaper_utils,
                                    "_any_screen_uses_managed_wallpaper",
                                    side_effect=[True, False],
                                ):
                                    with mock.patch("time.sleep"):
                                        with mock.patch.object(
                                            wallpaper_utils,
                                            "_set_all_desktops_picture_via_system_events",
                                            return_value=True,
                                        ) as sync_spaces:
                                            restored = wallpaper_utils.restore_wallpaper_backup()

            self.assertTrue(restored)
            sync_spaces.assert_not_called()

    def test_restore_wallpaper_uses_original_backup_when_current_invalid(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            backup_path = temp_root / "wallpaper_backup.json"
            original_backup_path = temp_root / "wallpaper_backup_original.json"
            image_path = temp_root / "wallpaper.heic"
            image_path.write_bytes(b"image")
            last_frame_path = temp_root / "last_frame.png"
            last_frame_path.write_bytes(b"frame")

            backup_path.write_text(json.dumps({"1": str(last_frame_path)}), encoding="utf-8")
            original_backup_path.write_text(json.dumps({"1": str(image_path)}), encoding="utf-8")

            fake_screen = object()
            fake_workspace = mock.Mock()

            fake_appkit = mock.Mock()
            fake_appkit.NSWorkspace.sharedWorkspace.return_value = fake_workspace
            fake_appkit.NSScreen.screens.return_value = [fake_screen]

            fake_nsurl = mock.Mock()
            fake_nsurl.fileURLWithPath_.side_effect = lambda path: path

            with mock.patch.object(wallpaper_utils, "WALLPAPER_BACKUP_PATH", backup_path):
                with mock.patch.object(wallpaper_utils, "WALLPAPER_ORIGINAL_BACKUP_PATH", original_backup_path):
                    with mock.patch.object(wallpaper_utils, "LAST_FRAME_PATH", last_frame_path):
                        with mock.patch.object(wallpaper_utils, "_require_macos_frameworks"):
                            with mock.patch.object(wallpaper_utils, "_screen_identifier", return_value="1"):
                                with mock.patch.object(wallpaper_utils, "AppKit", fake_appkit):
                                    with mock.patch.object(wallpaper_utils, "NSURL", fake_nsurl):
                                        with mock.patch.object(
                                            wallpaper_utils,
                                            "_set_all_desktops_picture_via_system_events",
                                            return_value=True,
                                        ):
                                            restored = wallpaper_utils.restore_wallpaper_backup()

            self.assertTrue(restored)
            fake_workspace.setDesktopImageURL_forScreen_options_error_.assert_called_once()


if __name__ == "__main__":
    unittest.main()
