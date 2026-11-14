import base64
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

spec = importlib.util.spec_from_file_location('validator', Path(__file__).with_name('validate-appcast.py'))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.archive, self.plist, self.feed = [root / name for name in ('Showcase.dmg', 'Info.plist', 'appcast.xml')]
        self.archive.write_bytes(b'update archive fixture')
        private = Ed25519PrivateKey.generate()
        public = private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        self.app = dict(CFBundleVersion='123456789', CFBundleShortVersionString='1.2.3',
                        LSMinimumSystemVersion='26.0', SUFeedURL=validator.FEED,
                        SUPublicEDKey=base64.b64encode(public).decode())
        self.plist.write_bytes(plistlib.dumps(self.app))
        signature = base64.b64encode(private.sign(self.archive.read_bytes())).decode()
        self.tree = ET.fromstring(f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
          <sparkle:version>123456789</sparkle:version><sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/rxtech-lab/MotionSwift/releases/download/v1.2.3/Showcase.dmg"
            length="{self.archive.stat().st_size}" sparkle:edSignature="{signature}"/>
          </item></channel></rss>''')

    def validate(self, tag='v1.2.3'):
        ET.ElementTree(self.tree).write(self.feed)
        validator.validate(self.feed, self.archive, self.plist, tag)

    def test_valid_release(self):
        self.validate()

    def test_corrupted_archive(self):
        self.archive.write_bytes(b'Update archive fixture')  # Same size, different contents.
        with self.assertRaises(InvalidSignature):
            self.validate()

    def test_metadata_mismatch(self):
        item = self.tree.find('./channel/item')
        for field in ('version', 'shortVersionString', 'minimumSystemVersion'):
            element = item.find(validator.NS + field)
            previous = element.text
            element.text = 'wrong'
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.validate()
            element.text = previous

    def test_wrong_url_or_length(self):
        enclosure = self.tree.find('./channel/item/enclosure')
        for field, value in [('url', 'https://example.com/update.dmg'), ('length', '0')]:
            previous = enclosure.get(field)
            enclosure.set(field, value)
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.validate()
            enclosure.set(field, previous)

    def test_prerelease_rejected(self):
        with self.assertRaises(ValueError):
            self.validate('v1.2.3-beta.1')

    def test_wrong_embedded_key(self):
        self.app['SUPublicEDKey'] = base64.b64encode(bytes(32)).decode()
        self.plist.write_bytes(plistlib.dumps(self.app))
        with self.assertRaises(InvalidSignature):
            self.validate()


if __name__ == '__main__':
    unittest.main()
