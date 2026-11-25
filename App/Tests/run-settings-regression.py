#!/usr/bin/env python3
"""Compile the actual chat model and window against the products of the documented Debug build."""
import os
import platform
from pathlib import Path
from regression_resources import copy_core_resources
import subprocess
import sys
import plistlib
import shutil

root = Path(__file__).resolve().parents[2]
derived_data = Path(os.environ.get("ASKY_DERIVED_DATA", os.environ.get("KULAHERE_DERIVED_DATA", root / "build/DerivedData")))
products = derived_data / "Build/Products/Debug"
if not (products / "Search.o").exists():
    sys.exit("Build the Debug app with the README command first.")

environment = os.environ.copy()
environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=environment, text=True).strip()

sources = [path.stem for path in sorted((root / "App/Sources").glob("*.swift"))
           if path.stem != "AskyApp"]
command = ["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6", "-D", "DEBUG",
           "-sdk", sdk, "-target", platform.machine() + "-apple-macos14.0", "-I", str(products)]
command += ["-external-plugin-path", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins#/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/bin/swift-plugin-server"]
maps = derived_data / "Build/Intermediates.noindex/GeneratedModuleMaps"
for path in sorted(maps.glob("*.modulemap")):
    command += ["-Xcc", "-fmodule-map-file=" + str(path)]
for relative in ["swift-cmark/src/include", "swift-cmark/extensions/include"]:
    command += ["-I", str(derived_data / "SourcePackages/checkouts" / relative)]
command += [str(root / "App/Sources" / (name + ".swift")) for name in sources]
test_source = ("AboutSettingsRegression.swift" if "--about-page" in sys.argv else
               "PluginSettingsRegression.swift" if "--plugin-tabs" in sys.argv else
               "LocalShortcutsRegression.swift" if "--local-shortcuts" in sys.argv else "SettingsRegression.swift")
command += [str(root / "App/Tests" / test_source)]
command += [str(path) for path in sorted(products.glob("*.o"))]
binary = root / "build/settings-regression"
command += ["-lsqlite3", "-o", str(binary)]
subprocess.run(command, env=environment, cwd=root, check=True)
bundle = root / "build/SettingsRegression.app/Contents"
(bundle / "MacOS").mkdir(parents=True, exist_ok=True)
(bundle / "Resources").mkdir(exist_ok=True)
copy_core_resources(products, bundle / "Resources")
executable = bundle / "MacOS/SettingsRegression"
shutil.copy2(binary, executable)
shutil.copy2(products / "Asky.app/Contents/Resources/Assets.car", bundle / "Resources/Assets.car")
shutil.copy2(products / "Asky.app/Contents/Resources/AskyNative.icns", bundle / "Resources/AskyNative.icns")
for localization in (products / "Asky.app/Contents/Resources").glob("*.lproj"):
    shutil.copytree(localization, bundle / "Resources" / localization.name, dirs_exist_ok=True)
with (products / "Asky.app/Contents/Info.plist").open("rb") as source_plist:
    app_info = plistlib.load(source_plist)
with (bundle / "Info.plist").open("wb") as output:
    plistlib.dump({"CFBundleExecutable": "SettingsRegression", "CFBundleIdentifier": "app.asky.plugin-settings-regression" if "--plugin-tabs" in sys.argv else "app.asky.settings-regression",
                  "CFBundleName": "SettingsRegression", "CFBundleIconFile": "AskyNative", "CFBundleIconName": "AskyNative",
                  "CFBundleShortVersionString": app_info.get("CFBundleShortVersionString", "0.1.0"),
                  "CFBundleVersion": app_info.get("CFBundleVersion", "1"),
                  "CFBundleDevelopmentRegion": "zh-Hans", "CFBundlePackageType": "APPL", "LSUIElement": True}, output)
# Refresh the bundle signature after replacing its executable and resources.
subprocess.run(["codesign", "--force", "--sign", "-", str(bundle.parent)], check=True)
subprocess.run([str(executable), *sys.argv[1:]], env=environment, cwd=root, check=True)
