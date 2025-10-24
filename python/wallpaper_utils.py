"""
Utility helpers for working with video frames and macOS desktop wallpaper.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Tuple

import AppKit
import AVFoundation
import Quartz

from Foundation import NSURL
from CoreMedia import CMTimeMakeWithSeconds


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
    Persist an NSImage to a temporary PNG file and return the path.
    """

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
    with tempfile.NamedTemporaryFile(delete=False, suffix=".png") as handle:
        handle.write(png_data)
        temp_path = Path(handle.name)
    return temp_path


def set_wallpaper(image_path: Path) -> None:
    """
    Apply the given image file as the wallpaper on all available screens.
    """

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
