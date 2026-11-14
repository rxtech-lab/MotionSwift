#!/usr/bin/env python3
"""Check the packaged payload and decode audio without a developer-machine PATH."""
from pathlib import Path
import argparse
import base64
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('--version', help='Expected release version without the v prefix')
parser.add_argument('--build', help='Expected CI build number')
parser.add_argument('--require-updates', action='store_true', help='Require a release Sparkle key')
args = parser.parse_args()
app = args.app.resolve()
contents = app / 'Contents'
resources = contents / 'Resources'
info = plistlib.loads((contents / 'Info.plist').read_bytes())
if info.get('SUFeedURL') != 'https://update.motion.rxfilm.app/appcast.xml':
    raise RuntimeError('Unexpected Sparkle feed URL')
if args.require_updates and len(base64.b64decode(info.get('SUPublicEDKey', ''), validate=True)) != 32:
    raise RuntimeError('Release package is missing its Sparkle public key')
for key, expected in [('CFBundleShortVersionString', args.version), ('CFBundleVersion', args.build)]:
    if expected is not None and info.get(key) != expected:
        raise RuntimeError(f'{key}: expected {expected!r}, found {info.get(key)!r}')


def bundle_resources(name):
    root = resources / f'MotionSwift_{name}.bundle'
    nested = root / 'Contents/Resources'
    return nested if nested.is_dir() else root


required = [
    contents / 'MacOS' / info['CFBundleExecutable'],
    contents / 'Frameworks/Sparkle.framework/Versions/Current/Sparkle',
    contents / 'Frameworks/Sparkle.framework/Versions/Current/Autoupdate',
    contents / 'Frameworks/Sparkle.framework/Versions/Current/Updater.app/Contents/MacOS/Updater',
    contents / 'Frameworks/Sparkle.framework/Versions/Current/XPCServices/Installer.xpc/Contents/MacOS/Installer',
    contents / 'Frameworks/Sparkle.framework/Versions/Current/XPCServices/Downloader.xpc/Contents/MacOS/Downloader',
    resources / 'AppIcon.icns', resources / 'Assets.car',
    bundle_resources('MotionPortable') / 'JavaScript/vendor.json',
    bundle_resources('MotionRuntime') / 'JavaScript/engine.js',
    bundle_resources('motionswift-showcase') / 'Media/music.m4a',
    bundle_resources('motionswift-showcase') / 'OpenSource/index.tsx',
    bundle_resources('motionswift-showcase') / 'OpenSource/provenance.json',
    bundle_resources('motionswift-showcase') / 'OpenSource/THIRD-PARTY-LICENSES.txt',
    resources / 'ShowcaseProjects/tests/compositions/src/index.ts',
    resources / 'ShowcaseProjects/tests/compositions/public/effects.svg',
    resources / 'ShowcaseProjects/tests/three/public/models/probe.usdz',
    resources / 'ShowcaseProjects/Examples/MotionStudio/SampleProject/src/index.ts',
    resources / 'ShowcaseProjects/tests/fixtures/test-film/project.zip',
]
for path in required:
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f'Missing packaged resource: {path}')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
subprocess.run([str(contents / 'Helpers/ffmpeg'), '-v', 'error', '-i',
                str(bundle_resources('motionswift-showcase') / 'Media/music.m4a'),
                '-t', '0.1', '-f', 'null', '-'], check=True,
               env={'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'})
print(f'Package verified: {info["CFBundleShortVersionString"]} ({info["CFBundleVersion"]}), '
      f'macOS {info["LSMinimumSystemVersion"]}+')
