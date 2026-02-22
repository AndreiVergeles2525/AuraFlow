"""
Utility helpers for working with video frames and macOS desktop wallpaper.
"""

from __future__ import annotations

import json
from pathlib import Path

from paths import LAST_FRAME_PATH, WALLPAPER_BACKUP_PATH, ensure_app_support_dir

try:  # pragma: no cover - import availability depends on host environment
    import AppKit
    import AVFoundation
    from Foundation import NSURL
    from CoreMedia import CMTimeMakeWithSeconds
except ModuleNotFoundError:  # pragma: no cover
    AppKit = None
    AVFoundation = None
    NSURL = None
    CMTimeMakeWithSeconds = None


def _require_macos_frameworks() -> None:
    if AppKit is None or AVFoundation is None or NSURL is None or CMTimeMakeWithSeconds is None:
        raise RuntimeError(
            "PyObjC frameworks are not available. Install requirements from python/requirements.txt."
        )


def _screen_identifier(screen) -> str:
    description = screen.deviceDescription() or {}
    screen_number = description.get("NSScreenNumber")
    if screen_number is None:
        return str(hash(screen))
    try:
        return str(int(screen_number))
    except (TypeError, ValueError):
        return str(screen_number)


def _current_wallpapers() -> dict[str, str]:
    _require_macos_frameworks()
    workspace = AppKit.NSWorkspace.sharedWorkspace()
    wallpapers: dict[str, str] = {}
    for screen in AppKit.NSScreen.screens():
        url = workspace.desktopImageURLForScreen_(screen)
        if url is None:
            continue
        path = url.path() if hasattr(url, "path") else str(url)
        if path:
            wallpapers[_screen_identifier(screen)] = str(path)
    return wallpapers


def _load_wallpaper_backup() -> dict[str, str]:
    if not WALLPAPER_BACKUP_PATH.exists():
        return {}
    try:
        data = json.loads(WALLPAPER_BACKUP_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict):
        return {}

    wallpapers: dict[str, str] = {}
    for key, value in data.items():
        if (
            isinstance(key, str)
            and isinstance(value, str)
            and value
            and not _is_managed_wallpaper(value)
        ):
            wallpapers[key] = value
    return wallpapers


def _is_managed_wallpaper(path: str) -> bool:
    """Return True when a wallpaper path points to AuraFlow's generated frame."""

    try:
        candidate = Path(path).expanduser().resolve(strict=False)
    except OSError:
        return False

    managed = LAST_FRAME_PATH.expanduser().resolve(strict=False)
    return candidate == managed


def _save_wallpaper_backup_if_needed() -> None:
    ensure_app_support_dir()

    wallpapers = {
        screen_id: path
        for screen_id, path in _current_wallpapers().items()
        if not _is_managed_wallpaper(path)
    }
    if not wallpapers:
        return
    existing = _load_wallpaper_backup()
    if existing == wallpapers:
        return

    WALLPAPER_BACKUP_PATH.write_text(
        json.dumps(wallpapers, indent=2),
        encoding="utf-8",
    )


def _restore_wallpaper_paths(wallpapers: dict[str, str]) -> bool:
    """Apply provided wallpaper paths to matching screens."""

    workspace = AppKit.NSWorkspace.sharedWorkspace()
    fallback = next(iter(wallpapers.values()), None)
    restored = False

    for screen in AppKit.NSScreen.screens():
        path = wallpapers.get(_screen_identifier(screen)) or fallback
        if not path:
            continue
        image_path = Path(path).expanduser()
        if not image_path.exists():
            continue
        url = NSURL.fileURLWithPath_(str(image_path))
        workspace.setDesktopImageURL_forScreen_options_error_(url, screen, {}, None)
        restored = True

    return restored


def _fallback_system_wallpaper() -> dict[str, str]:
    """Return a default macOS wallpaper path for all screens if available."""

    desktop_pictures = Path("/System/Library/Desktop Pictures")
    if not desktop_pictures.exists():
        return {}

    candidates = sorted(desktop_pictures.glob("*.heic"))
    if not candidates:
        candidates = sorted(desktop_pictures.glob("*.jpg"))
    if not candidates:
        candidates = sorted(desktop_pictures.glob("*.png"))
    if not candidates:
        return {}

    default_image = str(candidates[0])
    return {_screen_identifier(screen): default_image for screen in AppKit.NSScreen.screens()}


def restore_wallpaper_backup(
    delete_backup: bool = False,
    allow_fallback: bool = False,
) -> bool:
    """
    Restore system wallpaper URLs captured before AuraFlow changed them.

    By default this restores only known user wallpaper paths from backup.
    Optional fallback to macOS defaults can be enabled explicitly.
    """

    _require_macos_frameworks()
    wallpapers = _load_wallpaper_backup()
    restored = _restore_wallpaper_paths(wallpapers) if wallpapers else False

    if not restored and allow_fallback:
        fallback_wallpapers = _fallback_system_wallpaper()
        if fallback_wallpapers:
            restored = _restore_wallpaper_paths(fallback_wallpapers)

    if restored and delete_backup:
        WALLPAPER_BACKUP_PATH.unlink(missing_ok=True)
    return restored


def validate_video(path: str) -> Path:
    """Ensure the provided path points to an existing file."""

    video_path = Path(path).expanduser().resolve()
    if not video_path.exists():
        raise FileNotFoundError(f"Video file not found: {video_path}")
    if not video_path.is_file():
        raise ValueError(f"Expected a file, got: {video_path}")

    return video_path


def extract_first_frame(video_path: Path) -> AppKit.NSImage:
    """
    Return an NSImage representing the first frame of the provided video.
    """

    _require_macos_frameworks()
    asset = AVFoundation.AVURLAsset.URLAssetWithURL_options_(
        NSURL.fileURLWithPath_(str(video_path)),
        {AVFoundation.AVURLAssetPreferPreciseDurationAndTimingKey: True},
    )
    generator = AVFoundation.AVAssetImageGenerator.assetImageGeneratorWithAsset_(asset)
    generator.setAppliesPreferredTrackTransform_(True)
    requested_time = CMTimeMakeWithSeconds(0.0, asset.duration().timescale or 600)
    result = generator.copyCGImageAtTime_actualTime_error_(requested_time, None, None)
    if isinstance(result, tuple):
        cg_image = result[0]
    else:
        cg_image = result
    if cg_image is None:
        raise RuntimeError("Unable to extract frame from video.")
    image = AppKit.NSImage.alloc().initWithCGImage_size_(cg_image, AppKit.NSZeroSize)
    return image


def save_image_to_temp(image: AppKit.NSImage) -> Path:
    """
    Persist an NSImage to a stable PNG file and return the path.
    """

    _require_macos_frameworks()
    representations = image.representations()
    bitmap = None
    for representation in representations:
        if isinstance(representation, AppKit.NSBitmapImageRep):
            bitmap = representation
            break
    if bitmap is None:
        cg_image = image.CGImageForProposedRect_context_hints_(None, None, None)
        if isinstance(cg_image, tuple):
            cg_image = cg_image[0]
        if cg_image is not None:
            bitmap = AppKit.NSBitmapImageRep.alloc().initWithCGImage_(cg_image)
    if bitmap is None:
        tiff_data = image.TIFFRepresentation()
        if tiff_data is not None:
            bitmap = AppKit.NSBitmapImageRep.imageRepWithData_(tiff_data)
    if bitmap is None:
        raise RuntimeError("Unable to create bitmap representation from video frame.")
    png_data = bitmap.representationUsingType_properties_(AppKit.NSPNGFileType, None)

    ensure_app_support_dir()
    with LAST_FRAME_PATH.open("wb") as handle:
        handle.write(png_data)
    return LAST_FRAME_PATH


def set_wallpaper(image_path: Path) -> None:
    """
    Apply the given image file as the wallpaper on all available screens.
    """

    _require_macos_frameworks()
    _save_wallpaper_backup_if_needed()
    workspace = AppKit.NSWorkspace.sharedWorkspace()
    url = NSURL.fileURLWithPath_(str(image_path))
    for screen in AppKit.NSScreen.screens():
        workspace.setDesktopImageURL_forScreen_options_error_(url, screen, {}, None)


def set_wallpaper_from_video(video_path: Path) -> Path:
    """
    Extract the first frame of a video file and set it as the system wallpaper.

    Returns the temporary image path that was applied.
    """

    image = extract_first_frame(video_path)
    temp_path = save_image_to_temp(image)
    set_wallpaper(temp_path)
    return temp_path
