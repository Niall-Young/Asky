"""Shared signing for release packaging and local installed bundles."""
from pathlib import Path
import argparse
import subprocess
import re

RELEASE_IDENTITY = 'Developer ID Application: Niall Young (V8GVW783CK)'
DEFAULT_IDENTITY = RELEASE_IDENTITY


def check_identity(identity):
    if identity == '-':
        raise SystemExit('Ad-hoc signing is disabled: use a persistent code-signing identity.')
    result = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    for line in result.splitlines():
        match = re.search(r'\b([0-9A-F]{40}) "([^"]+)"', line)
        if match and (identity == match[2] or identity.upper() == match[1]):
            return match[2]
    raise SystemExit(f'Signing identity unavailable: {identity}. Install the certificate and private key '
                     'or supply an existing certificate name/SHA-1 with --signing-identity.')


def sign_bundle(app, identity=DEFAULT_IDENTITY):
    name = check_identity(identity)
    timestamp = '--timestamp' if name.startswith('Developer ID Application:') else '--timestamp=none'
    repo = Path(__file__).resolve().parent.parent
    for name in ('asky-mcp', 'kulahere-mcp'):
        bridge = app / 'Contents/MacOS' / name
        if bridge.exists() and not bridge.is_symlink():
            subprocess.run(['codesign', '--force', '--sign', identity, timestamp,
                            '--options', 'runtime', str(bridge)], check=True)
    subprocess.run(['codesign', '--force', '--sign', identity, timestamp, '--options', 'runtime',
                    '--entitlements', str(repo / 'App/Asky.entitlements'), str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Sign an Asky bundle with a persistent identity')
    parser.add_argument('app', type=Path)
    parser.add_argument('--signing-identity', default=DEFAULT_IDENTITY)
    args = parser.parse_args()
    sign_bundle(args.app, args.signing_identity)
