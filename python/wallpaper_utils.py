"""
Utility helpers for working with video frames and macOS desktop wallpaper.
"""

from __future__ import annotations

from collections import Counter
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

from paths import (
    APP_SUPPORT_DIR,
    LAST_FRAME_PATH,
    SYSTEM_WALLPAPER_INDEX_PATH,
    WALLPAPER_BACKUP_PATH,
    WALLPAPER_DESKTOP_BACKUP_PATH,
    WALLPAPER_DESKTOP_ORIGINAL_BACKUP_PATH,
    WALLPAPER_ORIGINAL_BACKUP_PATH,
    WALLPAPER_STORE_BACKUP_PATH,
    ensure_app_support_dir,
)

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


def _sanitize_wallpaper_backup(data: object) -> dict[str, str]:
    if not isinstance(data, dict):
        return {}

    wallpapers: dict[str, str] = {}
    for key, value in data.items():
        if not isinstance(key, str) or not isinstance(value, str) or not value:
            continue
        if _is_managed_wallpaper(value):
            continue
        wallpapers[key] = value
    return wallpapers


def _load_wallpaper_backup(path: Path | None = None) -> dict[str, str]:
    if path is None:
        path = WALLPAPER_BACKUP_PATH
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return _sanitize_wallpaper_backup(data)


def _write_wallpaper_backup(path: Path, wallpapers: dict[str, str]) -> None:
    path.write_text(
        json.dumps(wallpapers, indent=2),
        encoding="utf-8",
    )


def _save_wallpaper_store_backup_if_needed() -> None:
    try:
        source = SYSTEM_WALLPAPER_INDEX_PATH.expanduser().resolve(strict=False)
    except OSError:
        return
    if not source.exists() or not source.is_file():
        return

    try:
        if WALLPAPER_STORE_BACKUP_PATH.exists():
            current_bytes = WALLPAPER_STORE_BACKUP_PATH.read_bytes()
            source_bytes = source.read_bytes()
            if current_bytes == source_bytes:
                return
            WALLPAPER_STORE_BACKUP_PATH.write_bytes(source_bytes)
            return
        shutil.copy2(source, WALLPAPER_STORE_BACKUP_PATH)
    except OSError:
        return


def _reload_wallpaper_services() -> None:
    for process_name in (
        "WallpaperAgent",
        "wallpaperexportd",
        "WallpaperImageExtension",
        "WallpaperSequoiaExtension",
        "WallpaperLegacyExtension",
        "WallpaperDynamicExtension",
        "WallpaperAerialsExtension",
        "NeptuneOneWallpaper",
        "Dock",
    ):
        try:
            subprocess.run(  # noqa: S603
                ["killall", process_name],
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError:
            continue


def _restore_wallpaper_store_backup() -> bool:
    try:
        source = WALLPAPER_STORE_BACKUP_PATH.expanduser().resolve(strict=False)
        destination = SYSTEM_WALLPAPER_INDEX_PATH.expanduser().resolve(strict=False)
    except OSError:
        return False

    if not source.exists() or not source.is_file():
        return False

    try:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    except OSError:
        return False

    _reload_wallpaper_services()
    return True


def _load_desktop_picture_backup(path: Path) -> list[str]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(data, list):
        return []

    pictures: list[str] = []
    for value in data:
        if not isinstance(value, str) or not value:
            continue
        if _is_managed_wallpaper(value):
            continue
        pictures.append(value)
    return pictures


def _write_desktop_picture_backup(path: Path, desktop_paths: list[str]) -> None:
    path.write_text(
        json.dumps(desktop_paths, indent=2),
        encoding="utf-8",
    )


def _managed_frame_suffix() -> str:
    return LAST_FRAME_PATH.suffix or ".png"


def _is_managed_frame_candidate(path: Path) -> bool:
    try:
        candidate = path.expanduser().resolve(strict=False)
        support_dir = APP_SUPPORT_DIR.expanduser().resolve(strict=False)
    except OSError:
        return False

    if candidate.parent != support_dir:
        return False

    suffix = _managed_frame_suffix().lower()
    stem = LAST_FRAME_PATH.stem.lower()
    name = candidate.name.lower()
    if name == f"{stem}{suffix}":
        return True
    return name.startswith(f"{stem}_") and name.endswith(suffix)


def _next_managed_frame_path() -> Path:
    suffix = _managed_frame_suffix()
    unique = f"{LAST_FRAME_PATH.stem}_{int(time.time() * 1000)}_{os.getpid()}{suffix}"
    return LAST_FRAME_PATH.with_name(unique)


def _sync_last_frame_alias(source_path: Path) -> None:
    ensure_app_support_dir()
    alias = LAST_FRAME_PATH
    temp_alias = alias.with_name(f"{alias.stem}.tmp{_managed_frame_suffix()}")
    temp_alias.unlink(missing_ok=True)
    shutil.copy2(source_path, temp_alias)
    temp_alias.replace(alias)


def _cleanup_old_managed_frames(keep: Path) -> None:
    suffix = _managed_frame_suffix()
    pattern = f"{LAST_FRAME_PATH.stem}_*{suffix}"
    try:
        files = sorted(
            APP_SUPPORT_DIR.glob(pattern),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
    except OSError:
        return

    keep_resolved = keep.expanduser().resolve(strict=False)
    retained = 0
    for path in files:
        try:
            resolved = path.expanduser().resolve(strict=False)
        except OSError:
            continue
        if resolved == keep_resolved:
            retained += 1
            continue
        if retained < 3:
            retained += 1
            continue
        path.unlink(missing_ok=True)


def _commit_managed_frame(
    destination: Path,
    *,
    apply_wallpaper: bool = True,
) -> Path:
    _sync_last_frame_alias(destination)
    _cleanup_old_managed_frames(destination)
    if apply_wallpaper:
        set_wallpaper(destination)
    return destination


def _is_managed_wallpaper(path: str) -> bool:
    """Return True when a wallpaper path points to AuraFlow's generated frame."""

    try:
        candidate = Path(path).expanduser().resolve(strict=False)
    except OSError:
        return False

    managed = LAST_FRAME_PATH.expanduser().resolve(strict=False)
    if candidate == managed:
        return True
    return _is_managed_frame_candidate(candidate)
def _current_screen_ids() -> list[str]:
    try:
        screens = AppKit.NSScreen.screens()
    except Exception:
        return []
    return [_screen_identifier(screen) for screen in screens]


def _save_wallpaper_backup_if_needed() -> None:
    ensure_app_support_dir()
    wallpapers = _sanitize_wallpaper_backup(_current_wallpapers())
    if not wallpapers:
        return
    _save_wallpaper_store_backup_if_needed()
    existing = _load_wallpaper_backup(WALLPAPER_BACKUP_PATH)
    if existing == wallpapers:
        return

    _write_wallpaper_backup(WALLPAPER_BACKUP_PATH, wallpapers)


def refresh_wallpaper_backup() -> None:
    """
    Refresh the stored non-AuraFlow wallpaper snapshot from current system state.
    """

    _require_macos_frameworks()
    _save_wallpaper_backup_if_needed()


def _restore_wallpaper_paths(wallpapers: dict[str, str]) -> bool:
    """Apply provided wallpaper paths to matching screens."""

    workspace = AppKit.NSWorkspace.sharedWorkspace()
    fallback = next(iter(wallpapers.values()), None)
    unique_paths = {path for path in wallpapers.values() if path}
    restored = False
    applied_fallback_path: str | None = None

    for screen in AppKit.NSScreen.screens():
        path = wallpapers.get(_screen_identifier(screen)) or fallback
        if not path:
            continue
        image_path = Path(path).expanduser()
        if not image_path.exists():
            continue
        url = NSURL.fileURLWithPath_(str(image_path))
        result = workspace.setDesktopImageURL_forScreen_options_error_(url, screen, {}, None)
        success = False
        if isinstance(result, tuple):
            success = bool(result[0])
        elif isinstance(result, bool):
            success = result
        else:
            success = True

        if success:
            restored = True
            if applied_fallback_path is None:
                applied_fallback_path = str(image_path)

    if not restored:
        return False

    if applied_fallback_path and len(unique_paths) <= 1:
        if not _set_all_desktops_picture_via_system_events(applied_fallback_path):
            return False
        return True

    # Fast path: NSWorkspace restore already replaced AuraFlow-managed frames.
    # Add a short grace window because desktop API state can lag slightly.
    if _managed_wallpaper_cleared_within():
        return True

    if not applied_fallback_path:
        return False

    if not _set_all_desktops_picture_via_system_events(applied_fallback_path):
        return False
    return not _any_screen_uses_managed_wallpaper()


def _any_screen_uses_managed_wallpaper() -> bool:
    for path in _current_wallpapers().values():
        if _is_managed_wallpaper(path):
            return True
    return False


def _managed_wallpaper_cleared_within(
    timeout: float = 0.25,
    poll_interval: float = 0.05,
) -> bool:
    """
    Wait briefly for NSWorkspace wallpaper state to settle.
    """

    if not _any_screen_uses_managed_wallpaper():
        return True

    deadline = time.time() + max(timeout, 0.0)
    while time.time() < deadline:
        time.sleep(max(0.01, poll_interval))
        if not _any_screen_uses_managed_wallpaper():
            return True
    return False


def _set_all_desktops_picture_via_system_events(path: str) -> bool:
    """
    Fallback for Spaces-specific wallpaper assignments when NSWorkspace APIs
    report success but the active desktop still remains on AuraFlow frame.
    """

    escaped_path = path.replace("\\", "\\\\").replace('"', '\\"')
    apply_and_verify_script = (
        'tell application "System Events"\n'
        f'  set targetPath to POSIX path of (POSIX file "{escaped_path}")\n'
        "  try\n"
        "    repeat with d in desktops\n"
        f'      set picture of d to POSIX file "{escaped_path}"\n'
        "    end repeat\n"
        "  on error\n"
        '    return "error"\n'
        "  end try\n"
        "  repeat with d in desktops\n"
        "    try\n"
        "      set currentPath to POSIX path of (picture of d)\n"
        "      if currentPath is not targetPath then\n"
        '        return "mismatch"\n'
        "      end if\n"
        "    on error\n"
        '      return "mismatch"\n'
        "    end try\n"
        "  end repeat\n"
        '  return "ok"\n'
        "end tell"
    )

    for _ in range(2):
        result = _run_osascript(apply_and_verify_script)
        if result is None:
            return False
        if result.returncode == 0 and result.stdout.strip() == "ok":
            return True
        time.sleep(0.05)
    return False


def _set_desktop_picture_paths_via_system_events(desktop_paths: list[str]) -> bool:
    filtered_paths = [path for path in desktop_paths if path]
    if not filtered_paths:
        return False

    escaped_paths = [
        '"' + path.replace("\\", "\\\\").replace('"', '\\"') + '"'
        for path in filtered_paths
    ]
    script = (
        'tell application "System Events"\n'
        f'  set targetPaths to {{{", ".join(escaped_paths)}}}\n'
        "  set desktopCount to count of desktops\n"
        "  set targetCount to count of targetPaths\n"
        "  if targetCount is 0 then\n"
        '    return "error"\n'
        "  end if\n"
        "  try\n"
        "    repeat with i from 1 to desktopCount\n"
        "      set targetIndex to i\n"
        "      if targetIndex > targetCount then\n"
        "        set targetIndex to targetCount\n"
        "      end if\n"
        "      set targetPath to item targetIndex of targetPaths\n"
        "      set picture of desktop i to POSIX file targetPath\n"
        "    end repeat\n"
        "  on error\n"
        '    return "error"\n'
        "  end try\n"
        "  repeat with i from 1 to desktopCount\n"
        "    set targetIndex to i\n"
        "    if targetIndex > targetCount then\n"
        "      set targetIndex to targetCount\n"
        "    end if\n"
        "    set targetPath to item targetIndex of targetPaths\n"
        "    try\n"
        "      set currentPath to POSIX path of (picture of desktop i)\n"
        "      if currentPath is not targetPath then\n"
        '        return "mismatch"\n'
        "      end if\n"
        "    on error\n"
        '      return "mismatch"\n'
        "    end try\n"
        "  end repeat\n"
        '  return "ok"\n'
        "end tell"
    )

    for _ in range(2):
        result = _run_osascript(script)
        if result is None:
            return False
        if result.returncode == 0 and result.stdout.strip() == "ok":
            return True
        time.sleep(0.05)
    return False


def _run_osascript(script: str):
    try:
        return subprocess.run(  # noqa: S603
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None


def _desktop_picture_paths_via_system_events() -> list[str]:
    script = (
        'tell application "System Events"\n'
        "  set outputLines to {}\n"
        "  repeat with d in desktops\n"
        "    try\n"
        "      set end of outputLines to POSIX path of (picture of d)\n"
        "    end try\n"
        "  end repeat\n"
        '  return outputLines as string\n'
        "end tell"
    )
    result = _run_osascript(script)
    if result is None or result.returncode != 0:
        return []
    raw = result.stdout.strip()
    if not raw:
        return []
    lines = [line.strip() for line in raw.split(", ") if line.strip()]
    normalized: list[str] = []
    for line in lines:
        if _is_managed_wallpaper(line):
            continue
        normalized.append(line)
    return normalized


def _normalize_wallpaper_backup_for_spaces(wallpapers: dict[str, str]) -> dict[str, str]:
    desktop_candidates = _desktop_picture_paths_via_system_events()
    if desktop_candidates:
        ranked = Counter(desktop_candidates).most_common()
        target_ids = list(wallpapers.keys()) or _current_screen_ids() or ["1"]
        if not ranked:
            return wallpapers
        canonical_path = ranked[0][0]
        if not canonical_path:
            return wallpapers
        return {screen_id: canonical_path for screen_id in target_ids}

    if not wallpapers:
        return wallpapers

    candidates = [path for path in wallpapers.values() if path and not _is_managed_wallpaper(path)]
    if not candidates:
        return wallpapers

    ranked = Counter(candidates).most_common()
    if not ranked:
        return wallpapers

    canonical_path = ranked[0][0]
    if not canonical_path:
        return wallpapers

    return {screen_id: canonical_path for screen_id in wallpapers.keys()}


def _ffmpeg_candidate_executables() -> list[str]:
    env_value = os.environ.get("AURAFLOW_FFMPEG_PATH", "").strip()
    candidates: list[str] = []
    if env_value:
        candidates.append(env_value)
    bundled = _bundled_binary_executable("ffmpeg")
    if bundled:
        candidates.append(bundled)
    candidates.extend(
        [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
    )
    from_path = shutil.which("ffmpeg")
    if from_path:
        candidates.append(from_path)
    return candidates


def _bundled_binary_executable(name: str, origin: str | Path | None = None) -> str | None:
    current = Path(origin or __file__).expanduser().resolve(strict=False)
    for parent in (current.parent, *current.parents):
        candidate = parent / "bin" / name
        if os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def _resolve_ffmpeg_executable() -> str | None:
    seen: set[str] = set()
    for candidate in _ffmpeg_candidate_executables():
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        if os.access(candidate, os.X_OK):
            return candidate
    return None


def _extract_first_frame_with_ffmpeg(video_path: Path, output_path: Path | None = None) -> Path | None:
    ffmpeg = _resolve_ffmpeg_executable()
    if not ffmpeg:
        return None

    destination = output_path or _next_managed_frame_path()
    ensure_app_support_dir()
    temp_output = destination.with_name(f"{destination.stem}.tmp{destination.suffix or '.png'}")
    temp_output.unlink(missing_ok=True)
    destination.unlink(missing_ok=True)

    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-nostdin",
        "-y",
        "-i",
        str(video_path),
        "-map",
        "0:v:0",
        "-frames:v",
        "1",
        "-f",
        "image2",
        "-vcodec",
        "png",
        str(temp_output),
    ]

    try:
        result = subprocess.run(  # noqa: S603
            command,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None

    if result.returncode != 0 or not temp_output.exists() or temp_output.stat().st_size == 0:
        temp_output.unlink(missing_ok=True)
        return None

    temp_output.replace(destination)
    if destination != LAST_FRAME_PATH and _is_managed_frame_candidate(destination):
        _sync_last_frame_alias(destination)
        _cleanup_old_managed_frames(destination)
    return destination


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
    allow_original_fallback: bool = False,
) -> bool:
    """
    Restore the latest non-AuraFlow wallpaper snapshot.
    """

    _ = allow_original_fallback

    _require_macos_frameworks()
    restored = _restore_wallpaper_store_backup()
    wallpapers = _load_wallpaper_backup(WALLPAPER_BACKUP_PATH)
    if not restored and wallpapers:
        restored = _restore_wallpaper_paths(wallpapers)

    if not restored and allow_fallback:
        fallback_wallpapers = _fallback_system_wallpaper()
        if fallback_wallpapers:
            restored = _restore_wallpaper_paths(fallback_wallpapers)

    if restored and delete_backup:
        WALLPAPER_BACKUP_PATH.unlink(missing_ok=True)
        WALLPAPER_STORE_BACKUP_PATH.unlink(missing_ok=True)
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
    destination = _next_managed_frame_path()
    with destination.open("wb") as handle:
        handle.write(png_data)
    _sync_last_frame_alias(destination)
    _cleanup_old_managed_frames(destination)
    return destination


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
    _set_all_desktops_picture_via_system_events(str(image_path.expanduser().resolve(strict=False)))


def set_wallpaper_from_video(video_path: Path) -> Path:
    """
    Extract a representative frame and update AuraFlow's managed wallpaper.

    Returns the captured frame file used to refresh ``LAST_FRAME_PATH``.
    """
    try:
        image = extract_first_frame(video_path)
    except Exception:
        # Some catalog formats (for example certain WEBM variants) do not
        # provide a frame through AVAssetImageGenerator. Fallback to ffmpeg
        # extraction from the current video to avoid reusing stale last_frame.
        ffmpeg_frame = _extract_first_frame_with_ffmpeg(video_path)
        if ffmpeg_frame is not None:
            _commit_managed_frame(ffmpeg_frame, apply_wallpaper=True)
            return ffmpeg_frame
        current = _current_wallpapers()
        for path in current.values():
            candidate = Path(path).expanduser()
            if candidate.exists() and candidate.is_file() and not _is_managed_wallpaper(str(candidate)):
                return candidate
        raise

    temp_path = save_image_to_temp(image)
    _commit_managed_frame(temp_path, apply_wallpaper=True)
    return temp_path
