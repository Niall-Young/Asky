from pathlib import Path
import hashlib, json, plistlib, shutil, subprocess, tempfile

from signing import RELEASE_IDENTITY, check_identity, sign_bundle
from notarization import DEFAULT_PROFILE, check_profile, notarize, staple

import argparse
parser = argparse.ArgumentParser(description="Package a built Asky release as DMG and updater ZIP")
parser.add_argument('--version', required=True)
parser.add_argument('--build', required=True)
parser.add_argument('--derived-data', required=True, type=Path)
parser.add_argument('--signing-identity', default=RELEASE_IDENTITY)
parser.add_argument('--notary-profile', default=DEFAULT_PROFILE)
args = parser.parse_args()
if not check_identity(args.signing_identity).startswith('Developer ID Application:'):
    raise SystemExit('Release packaging requires a Developer ID Application certificate.')
repo = Path(__file__).resolve().parent.parent
root = repo / 'build'
commit = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
if subprocess.check_output(['git', '-C', str(repo), 'status', '--porcelain'], text=True).strip():
    raise SystemExit('Commit source changes before packaging a release')
check_profile(args.notary_profile)
app = root / f'release-staging-{args.version}/Asky.app'
app.parent.mkdir(parents=True, exist_ok=True)
if app.exists():
    raise SystemExit(f'Staging bundle already exists: {app}')
shutil.copytree(args.derived_data / 'Build/Products/Release/Asky.app', app, symlinks=True)
resources = app / 'Contents/Resources'
shutil.copy2(repo / 'LICENSE', resources / 'LICENSE')
for retired in ('AgentRuntime', 'node'):
    if (resources / retired).exists():
        raise SystemExit(f'Rebuild the native app without retired runtime resources: {retired}')
if not (resources / 'PluginSupport/plugin-runner.mjs').is_file():
    raise SystemExit('Legacy plugin compatibility resource is missing')
info_path = app / 'Contents/Info.plist'
with info_path.open('rb') as f:
    info = plistlib.load(f)
info['CFBundleShortVersionString'] = args.version
info['CFBundleVersion'] = args.build
info['KHReleaseCommit'] = commit
info.pop('KHSourceRoot', None)
with info_path.open('wb') as f:
    plistlib.dump(info, f)
sign_bundle(app, args.signing_identity)
with tempfile.TemporaryDirectory(prefix='asky-notarize-') as temporary:
    archive = Path(temporary) / 'Asky.zip'
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
    notarize(archive, args.notary_profile, root / f'release-{args.version}-app-notarization.json')
staple(app)
subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)], check=True)
release_dir = root / f'releases/{args.version}'
release_dir.mkdir(parents=True, exist_ok=True)
zip_path = release_dir / f'Asky-{args.version}-macos-arm64.zip'
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(zip_path)], check=True)
sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
(release_dir / (zip_path.name + '.sha256')).write_text(f'{sha}  {zip_path.name}\n')
print(json.dumps({'artifact': str(zip_path), 'sha256': sha, 'size': zip_path.stat().st_size}))

# Customize Finder on a writable image, then freeze it as a compressed DMG.
with tempfile.TemporaryDirectory(prefix='asky-dmg-') as temp:
    workspace = Path(temp)
    folder = workspace / 'contents'
    folder.mkdir()
    shutil.copytree(app, folder / 'Asky.app', symlinks=True)
    (folder / 'Applications').symlink_to('/Applications')
    (folder / '.background').mkdir()
    shutil.copy2(repo / 'scripts/dmg/background.tiff', folder / '.background/background.tiff')
    writable = workspace / 'installer.dmg'
    mount = workspace / 'mount'
    dmg = release_dir / f'Asky-{args.version}-macos-arm64.dmg'
    if dmg.exists():
        raise SystemExit(f'Release image already exists: {dmg}')
    subprocess.run(['hdiutil', 'create', '-volname', f'Asky {args.version}', '-srcfolder', str(folder),
                    '-fs', 'HFS+', '-format', 'UDRW', str(writable)], check=True)
    subprocess.run(['hdiutil', 'attach', '-nobrowse', '-noautoopen', '-mountpoint', str(mount),
                    str(writable)], check=True)
    try:
        subprocess.run(['osascript', str(repo / 'scripts/dmg/layout.applescript'), str(mount)],
                       check=True, timeout=60)
        if not (mount / '.DS_Store').is_file():
            raise RuntimeError('Finder did not persist the installer layout')
        subprocess.run(['sync'], check=True)
    finally:
        if subprocess.run(['hdiutil', 'detach', str(mount)]).returncode:
            subprocess.run(['hdiutil', 'detach', '-force', str(mount)], check=True)
    subprocess.run(['hdiutil', 'convert', str(writable), '-format', 'UDZO', '-o', str(dmg)], check=True)
    subprocess.run(['codesign', '--force', '--sign', args.signing_identity,
                    '--timestamp', str(dmg)], check=True)
    notarize(dmg, args.notary_profile, root / f'release-{args.version}-dmg-notarization.json')
    staple(dmg)
    subprocess.run(['codesign', '--verify', '--strict', '--verbose=2', str(dmg)], check=True)
    checksum = hashlib.sha256(dmg.read_bytes()).hexdigest()
    (release_dir / (dmg.name + '.sha256')).write_text(f'{checksum}  {dmg.name}\n')
    subprocess.run(['hdiutil', 'verify', str(dmg)], check=True)
    print(json.dumps({'artifact': str(dmg), 'sha256': checksum, 'size': dmg.stat().st_size}))
