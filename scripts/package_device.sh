#!/bin/bash
set -euo pipefail

app_path="build/Interline.xcarchive/Products/Applications/Interline.app"
plist_path="$app_path/Info.plist"
test -f "$plist_path"
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist_path")
xcrun lipo -verify_arch arm64 "$app_path/$executable"

mkdir -p dist
stage_dir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/interline-package.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
mkdir -p "$stage_dir/Payload"
ditto "$app_path" "$stage_dir/Payload/Interline.app"
ditto -c -k --keepParent "$stage_dir/Payload" dist/Interline-unsigned.ipa
cp docs/INSTALLATION.md dist/INSTALLATION.md

python3 - <<'PY'
import hashlib, json, os, plistlib, zipfile
from pathlib import Path
ipa = Path('dist/Interline-unsigned.ipa')
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, 'Corrupt IPA'
    info = plistlib.loads(archive.read('Payload/Interline.app/Info.plist'))
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'Simulator artifacts cannot run on iPhone'
    assert float(info['MinimumOSVersion']) >= 27, 'Unexpected deployment target'
    assert 'Payload/Interline.app/' + info['CFBundleExecutable'] in archive.namelist()
    assert not any(name.endswith('embedded.mobileprovision') for name in archive.namelist()), 'Unexpected provisioning profile in unsigned package'
metadata = {
    'commit': os.environ.get('GITHUB_SHA', 'local'),
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
    'bundleIdentifier': info['CFBundleIdentifier'],
    'minimumOSVersion': info['MinimumOSVersion'],
    'platform': 'iPhoneOS',
    'architecture': 'arm64',
    'appleSigned': False,
    'directlyInstallable': False,
    'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
}
Path('dist/BUILD-INFO.json').write_text(json.dumps(metadata, indent=2) + '\n')
print(json.dumps(metadata, indent=2))
PY
