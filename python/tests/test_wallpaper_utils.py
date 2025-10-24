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


if __name__ == "__main__":
    unittest.main()
