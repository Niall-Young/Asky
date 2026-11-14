#!/usr/bin/env python3
"""Compile the actual clipboard model and window against the products of the documented Debug build."""
import os
import platform
from pathlib import Path
from regression_resources import copy_core_resources
import subprocess
import sys
import plistlib
import shutil

root = Path(__file__).resolve().parents[2]
products = root / "build/DerivedData/Build/Products/Debug"
if not (products / "Search.o").exists():
    sys.exit("Build the Debug app with the README command first.")

sources = [path.stem for path in sorted((root / "App/Sources").glob("*.swift"))
           if path.stem != "AskyApp"]
command = ["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6",
           "-target", platform.machine() + "-apple-macos26.0", "-I", str(products)]
command += ["-external-plugin-path", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins#/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/bin/swift-plugin-server"]
maps = root / "build/DerivedData/Build/Intermediates.noindex/GeneratedModuleMaps"
for path in sorted(maps.glob("*.modulemap")):
    command += ["-Xcc", "-fmodule-map-file=" + str(path)]
for relative in ["swift-cmark/src/include", "swift-cmark/extensions/include"]:
    command += ["-I", str(root / "build/DerivedData/SourcePackages/checkouts" / relative)]
command += [str(root / "App/Sources" / (name + ".swift")) for name in sources]
command += [str(root / "App/Tests/ClipboardRegression.swift")]
command += [str(path) for path in sorted(products.glob("*.o"))]
video_test = "--video-preview" in sys.argv
binary = root / ("build/clipboard-video-regression" if video_test else "build/clipboard-regression")
command += ["-lsqlite3", "-o", str(binary)]
environment = os.environ.copy()
environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=environment, text=True).strip()
command += ["-sdk", sdk]
subprocess.run(command, env=environment, cwd=root, check=True)
bundle = root / ("build/ClipboardVideoRegression.app/Contents" if video_test else "build/ClipboardRegression.app/Contents")
(bundle / "MacOS").mkdir(parents=True, exist_ok=True)
(bundle / "Resources").mkdir(exist_ok=True)
copy_core_resources(products, bundle / "Resources")
executable = bundle / "MacOS/ClipboardRegression"
shutil.copy2(binary, executable)
shutil.copy2(products / "Asky.app/Contents/Resources/Assets.car", bundle / "Resources/Assets.car")
with (bundle / "Info.plist").open("wb") as output:
    plistlib.dump({"CFBundleExecutable": "ClipboardRegression", "CFBundleIdentifier": "app.asky.clipboard-regression",
                  "CFBundleName": "ClipboardRegression", "CFBundlePackageType": "APPL", "LSUIElement": True}, output)
subprocess.run(["codesign", "--force", "--sign", "-", str(bundle.parent)], env=environment, cwd=root, check=True)
if "--paste-target" in sys.argv or "--drag-paste-target" in sys.argv:
    receiver = root / "build/ClipboardPasteReceiver.app/Contents"
    (receiver / "MacOS").mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, receiver / "MacOS/ClipboardRegression")
    with (receiver / "Info.plist").open("wb") as output:
        plistlib.dump({"CFBundleExecutable": "ClipboardRegression", "CFBundleIdentifier": "app.asky.paste-receiver",
                      "CFBundleName": "ClipboardPasteReceiver", "CFBundlePackageType": "APPL"}, output)
    subprocess.run(["codesign", "--force", "--sign", "-", str(receiver.parent)], check=True)
    environment["ASKY_CLIPBOARD_RECEIVER"] = str(receiver / "MacOS/ClipboardRegression")
if "--video-preview" in sys.argv:
    fixture = root / "build/clipboard-video-fixture.mp4"
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
                    "-i", "testsrc2=size=" + ("360x640" if "--portrait-video" in sys.argv else "640x360") + ":rate=24", "-t", "3", "-c:v", "libx264",
                    "-pix_fmt", "yuv420p", str(fixture)], check=True)
    environment["ASKY_CLIPBOARD_VIDEO_FIXTURE"] = str(fixture)
subprocess.run([str(executable), *sys.argv[1:]], env=environment, cwd=root, check=True)
