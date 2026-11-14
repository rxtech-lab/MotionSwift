#!/usr/bin/env python3
"""Validate release metadata and verify the DMG signature against the embedded key."""
import base64
from pathlib import Path
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

FEED = 'https://update.motion.rxfilm.app/appcast.xml'
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def validate(feed, archive, plist, tag):
    if not re.fullmatch(r'v?[0-9]+\.[0-9]+\.[0-9]+', tag):
        raise ValueError('Only stable releases may publish the update feed')
    app = plistlib.loads(Path(plist).read_bytes())
    items = ET.parse(feed).findall('./channel/item')
    if len(items) != 1:
        raise ValueError('Expected exactly one release')
    item = items[0]
    enclosure = item.find('enclosure')
    archive = Path(archive)
    expected = {
        'version': app['CFBundleVersion'],
        'shortVersionString': app['CFBundleShortVersionString'],
        'minimumSystemVersion': app['LSMinimumSystemVersion'],
    }
    for name, value in expected.items():
        if item.findtext(NS + name) != value:
            raise ValueError(f'Wrong {name}')
    if app['CFBundleShortVersionString'] != tag.removeprefix('v') or app.get('SUFeedURL') != FEED:
        raise ValueError('Wrong release tag or feed URL')
    url = f'https://github.com/rxtech-lab/MotionSwift/releases/download/{tag}/{archive.name}'
    if enclosure is None or enclosure.get('url') != url:
        raise ValueError('Wrong download URL')
    if int(enclosure.get('length', '0')) != archive.stat().st_size:
        raise ValueError('Wrong archive length')
    key = Ed25519PublicKey.from_public_bytes(base64.b64decode(app['SUPublicEDKey'], validate=True))
    key.verify(base64.b64decode(enclosure.get(NS + 'edSignature', ''), validate=True), archive.read_bytes())
    print('Verified appcast metadata, download URL and Ed25519 signature')


if __name__ == '__main__':
    validate(*sys.argv[1:])
