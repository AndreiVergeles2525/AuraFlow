import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import wallpaper_utils  # noqa: E402


class WallpaperUtilsTests(unittest.TestCase):
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

    def test_save_wallpaper_backup_skips_auraflow_last_frame(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            backup_path = temp_root / "wallpaper_backup.json"
            last_frame_path = temp_root / "last_frame.png"
            last_frame_path.write_bytes(b"frame")

            with mock.patch.object(wallpaper_utils, "WALLPAPER_BACKUP_PATH", backup_path):
                with mock.patch.object(wallpaper_utils, "LAST_FRAME_PATH", last_frame_path):
                    with mock.patch.object(wallpaper_utils, "ensure_app_support_dir"):
                        with mock.patch.object(
                            wallpaper_utils,
                            "_current_wallpapers",
                            return_value={"1": str(last_frame_path)},
                        ):
                            wallpaper_utils._save_wallpaper_backup_if_needed()

            self.assertFalse(backup_path.exists())

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
                                    restored = wallpaper_utils.restore_wallpaper_backup()

            self.assertTrue(restored)
            self.assertTrue(backup_path.exists())

    def test_save_wallpaper_backup_refreshes_when_user_wallpaper_changes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            backup_path = temp_root / "wallpaper_backup.json"
            backup_path.write_text('{"1": "/old/path.heic"}', encoding="utf-8")

            with mock.patch.object(wallpaper_utils, "WALLPAPER_BACKUP_PATH", backup_path):
                with mock.patch.object(wallpaper_utils, "ensure_app_support_dir"):
                    with mock.patch.object(
                        wallpaper_utils,
                        "_current_wallpapers",
                        return_value={"1": "/new/path.heic"},
                    ):
                        wallpaper_utils._save_wallpaper_backup_if_needed()

            content = backup_path.read_text(encoding="utf-8")
            self.assertIn("/new/path.heic", content)


if __name__ == "__main__":
    unittest.main()
