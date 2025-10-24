from setuptools import setup


APP = ["video_wallpaper.py"]
DATA_FILES = []
OPTIONS = {
    "argv_emulation": False,
    "plist": {
        "CFBundleIdentifier": "com.example.videowallpaper",
        "CFBundleName": "VideoWallpaper",
        "CFBundleDisplayName": "Video Wallpaper",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
    },
    "packages": ["AppKit", "AVFoundation", "AVKit", "Quartz"],
}


setup(
    app=APP,
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app", "pyobjc"],
)
