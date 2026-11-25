#!/usr/bin/env python3
"""Import the pinned MingCute checkout: python3 scripts/import-mingcute-icons.py /path/to/mingcute-icons."""
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / "scripts/mingcute-icons.json").read_text())
upstream = Path(sys.argv[1]).resolve()
revision = subprocess.check_output(["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip()
if revision != manifest["revision"]:
    raise SystemExit(f"Expected MingCute {manifest['revision']}, got {revision}")

def import_asset(asset, icon):
    if icon.startswith("custom/"):
        files = [root / manifest["customIcons"][icon.split("/")[-1]]]
    else:
        style = "filled" if icon.startswith("filled/") else "regular"
        files = list((upstream / "assets/svg/core" / style).rglob(icon.split("/")[-1] + ".svg"))
    if len(files) != 1:
        raise SystemExit(f"Expected one SVG for {icon}, found {len(files)}")
    target = root / "App/Assets.xcassets" / (asset + ".imageset")
    target.mkdir(exist_ok=True)
    for old in target.iterdir():
        if old.name != "Contents.json":
            old.unlink()
    if icon.startswith("custom/"):
        # Asset catalogs do not render SVG hex colors with an eight-digit alpha suffix.
        # Drop an opaque FF suffix without changing the supplied geometry or color.
        svg = re.sub(r"#([0-9A-Fa-f]{6})[Ff]{2}", r"#\1", files[0].read_text())
        (target / "icon.svg").write_text(svg)
    else:
        shutil.copyfile(files[0], target / "icon.svg")
    contents = {"images": [{"filename": "icon.svg", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
                "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"}}
    (target / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

swift_file = root / "App/Sources/MingCute.swift"
entries = "\n".join("        " + json.dumps(key) + ": " + json.dumps("MingCute-" + icon.replace("/", "-")) + ","
                    for key, icon in manifest["symbols"].items())
swift_file.write_text(re.sub(r"(static let assets: \[String: String\] = \[\n).*?(\n    \])",
                             lambda match: match[1] + entries + match[2],
                             swift_file.read_text(), flags=re.S))

for icon in sorted(set(manifest["symbols"].values())):
    import_asset("MingCute-" + icon.replace("/", "-"), icon)
for asset, icon in manifest["assets"].items():
    import_asset(asset, icon)
license_dir = root / "App/Resources/ThirdParty/MingCute"
license_dir.mkdir(parents=True, exist_ok=True)
shutil.copyfile(upstream / "LICENSE", license_dir / "LICENSE")
(license_dir / "NOTICE").write_text(f"MingCute Icons\n{manifest['repository']}\nRevision: {manifest['revision']}\nCopyright MingCute Design\nSelected SVGs are redistributed without modification under Apache-2.0.\nAutomatic approval and copy use project owner supplied MingCute hand_line and copy_2_line SVGs. bot_message_square is imported from MingCute Icons revision 9dc7d3ad074fb16477096a6a8109a6467d0e2fe3 under Apache-2.0. Opaque color suffixes are normalized for asset catalog compatibility.\n")
print(f"Imported {len(set(manifest['symbols'].values()))} MingCute symbols and {len(manifest['assets'])} existing asset aliases.")
