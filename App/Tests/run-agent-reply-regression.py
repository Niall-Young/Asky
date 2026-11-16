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
derived_data = Path(os.environ.get("ASKY_DERIVED_DATA", root / "build/DerivedData"))
products = derived_data / "Build/Products/Debug"
if not (products / "Search.o").exists():
    sys.exit("Build the Debug app with the README command first.")

sources = [path.stem for path in sorted((root / "App/Sources").glob("*.swift"))
           if path.stem != "AskyApp"]
command = ["xcrun", "swiftc", "-parse-as-library", "-whole-module-optimization", "-swift-version", "6", "-D", "DEBUG",
           "-target", platform.machine() + "-apple-macos14.0", "-I", str(products)]
command += ["-external-plugin-path", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins#/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/bin/swift-plugin-server"]
maps = derived_data / "Build/Intermediates.noindex/GeneratedModuleMaps"
for path in sorted(maps.glob("*.modulemap")):
    command += ["-Xcc", "-fmodule-map-file=" + str(path)]
for relative in ["swift-cmark/src/include", "swift-cmark/extensions/include"]:
    command += ["-I", str(derived_data / "SourcePackages/checkouts" / relative)]
command += [str(root / "App/Sources" / (name + ".swift")) for name in sources]
command += [str(root / "App/Tests/AgentReplyRegression.swift")]
command += [str(root / "App/Tests/AgentReactionRegression.swift")]
command += [str(root / "App/Tests/ApprovalMenuRegression.swift")]
command += [str(path) for path in sorted(products.glob("*.o"))]
artifacts = derived_data / "AgentReplyRegression" if "ASKY_DERIVED_DATA" in os.environ else root / "build"
artifacts.mkdir(parents=True, exist_ok=True)
binary = artifacts / "agent-reply-regression"
command += ["-lsqlite3", "-o", str(binary)]
environment = os.environ.copy()
environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=environment, text=True).strip()
command += ["-sdk", sdk]
subprocess.run(command, env=environment, cwd=root, check=True)
bundle = artifacts / "AgentReplyRegression.app/Contents"
(bundle / "MacOS").mkdir(parents=True, exist_ok=True)
(bundle / "Resources").mkdir(exist_ok=True)
copy_core_resources(products, bundle / "Resources")
shutil.copytree(products / "SwiftMath_SwiftMath.bundle", bundle / "Resources/SwiftMath_SwiftMath.bundle", dirs_exist_ok=True)
executable = bundle / "MacOS/AgentReplyRegression"
executable.unlink(missing_ok=True)
shutil.copy2(binary, executable)
shutil.copy2(products / "Asky.app/Contents/Resources/Assets.car", bundle / "Resources/Assets.car")
with (bundle / "Info.plist").open("wb") as output:
    plistlib.dump({"CFBundleExecutable": "AgentReplyRegression", "CFBundleIdentifier": "app.asky.reply-regression",
                  "CFBundleName": "AgentReplyRegression", "CFBundlePackageType": "APPL", "LSUIElement": True, "KHSourceRoot": str(root)}, output)
subprocess.run(["codesign", "--force", "--sign", "-", str(bundle.parent)], check=True)
subprocess.run([str(executable), *sys.argv[1:]], env=environment, cwd=root, check=True)
